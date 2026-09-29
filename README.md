# payments-platform

A small payments shaped data platform on Snowflake, declared in Terraform, with one test that fails when the schema drifts.

## The invariant

**Every card transaction lands in the column it belongs to, or it does not land at all.**

Raw loads in Snowflake usually map CSV fields by position. If an upstream producer swaps two columns of the same type, say `card_id` and `merchant_id`, the load succeeds, row counts look right, and every downstream join on card or merchant is quietly wrong. Nothing errors. In payments that ends up in reconciliation breaks, chargeback disputes and fraud models trained on the wrong entity.

The same failure happens from the other side when someone edits the table by hand in the console, and the next deploy either reverts the fix or fails for reasons nobody can trace.

This repo protects the invariant with a single contract and a test that checks both sides of it.

## How it holds

```
                 ingest.tf: snowflake_table.card_transactions   (the contract)
                  │                          │                          │
          declares the table        generates the COPY          read by the test
                  │                  column list and $1..$n              │
                  ▼                          ▼                          ▼
     PAYMENTS.RAW.CARD_TRANSACTIONS  ◄── daily task ◄── @CARD_TXN_STAGE ◄── producer CSVs
```

1. **One contract.** Columns are declared once, in [ingest.tf](ingest.tf). The COPY statement's column list is derived from that declaration, so there is no second copy to forget.
2. **Test A: Snowflake matches Terraform.** `terraform plan -detailed-exitcode` must be empty. A manual `ALTER TABLE` turns it red.
3. **Test B: staged files match the table.** Before the 06:00 UTC load, every file on the stage must carry exactly the contract's header, in order. A swapped, renamed or extra column turns it red and names the file.

Both live in [tests/test_schema_drift.py](tests/test_schema_drift.py).

## See it fail

```powershell
python scripts/generate_transactions.py --rows 10 --drift swap   # producer swaps card_id and merchant_id
uv run scripts/upload_to_stage.py
uv run pytest -v                                                  # test_staged_files_match_table fails
```

`--drift rename` and `--drift extra` simulate the other common upstream changes. Cleanup commands are in [runbook.sql](runbook.sql).

## What is in here

| Path | Purpose |
|---|---|
| [main.tf](main.tf) | Database `PAYMENTS`, schema `RAW`, warehouse `ETL_XS` (XSMALL, suspends after 60 seconds) |
| [ingest.tf](ingest.tf) | CSV file format, internal stage, `CARD_TRANSACTIONS` table, daily COPY task |
| [scripts/](scripts/) | Fake transaction generator (stdlib only) and stage uploader |
| [tests/](tests/) | The drift test |
| [runbook.sql](runbook.sql) | Operational checks: row counts, task history, credit burn |

## Run it

Needs Terraform 1.6 or later, [uv](https://docs.astral.sh/uv/), and a Snowflake account. Credentials come from environment variables only and are never written to a file.

```powershell
$env:SNOWFLAKE_ORGANIZATION_NAME = "<org>"
$env:SNOWFLAKE_ACCOUNT_NAME      = "<account>"
$env:SNOWFLAKE_USER              = "<user>"
$env:SNOWFLAKE_PASSWORD          = Read-Host "Password"

terraform init
terraform apply
python scripts/generate_transactions.py
uv run scripts/upload_to_stage.py --run-task
uv run pytest -v
```

Running cost: the task wakes an XSMALL warehouse once a day for about a minute, roughly 0.02 credits a day.

## Design choices

1. **Internal stage, not a cloud bucket.** It keeps the repo to one provider and one account. Swapping in `snowflake_stage_external_s3` changes one resource; the contract and tests stay the same.
2. **COPY load metadata for idempotency.** Snowflake remembers which files it has loaded, so rerunning the task never double counts a transaction.
3. **`snowflake_table` is a preview resource** in provider v2 and is opted into explicitly in [main.tf](main.tf).
4. **Header check, not `MATCH_BY_COLUMN_NAME`.** Matching by name would survive a swap but silently load NULLs after a rename. A contract that fails loudly is the safer default for money.
