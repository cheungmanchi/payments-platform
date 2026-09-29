"""Schema drift tests. Contract: the snowflake_table declaration in ingest.tf.

A. Snowflake matches Terraform: a manual ALTER TABLE (or any console edit) makes `terraform plan` non empty.
B. Staged files match the table: COPY maps CSV fields by position, so a producer that reorders,
   renames or adds a column would load values into the wrong columns without an error.
   Every file on the stage must carry the exact header the table expects, in order.

Run: uv run pytest -v   (needs terraform on PATH and the SNOWFLAKE_* env vars)
"""

import json
import os
import subprocess
from pathlib import Path

import pytest
import snowflake.connector

ROOT = Path(__file__).resolve().parent.parent
STAGE = "PAYMENTS.RAW.CARD_TXN_STAGE"


def terraform(*args: str) -> subprocess.CompletedProcess:
    return subprocess.run(["terraform", *args], cwd=ROOT, capture_output=True, text=True)


@pytest.fixture(scope="session")
def expected_header() -> list[str]:
    """Source columns of RAW.CARD_TRANSACTIONS, in declared order, from Terraform state."""
    state = json.loads(terraform("show", "-json").stdout)
    table = next(
        r for r in state["values"]["root_module"]["resources"]
        if r["address"] == "snowflake_table.card_transactions"
    )
    return [c["name"].lower() for c in table["values"]["column"] if not c["name"].startswith("_")]


@pytest.fixture(scope="session")
def cursor():
    conn = snowflake.connector.connect(
        account=f"{os.environ['SNOWFLAKE_ORGANIZATION_NAME']}-{os.environ['SNOWFLAKE_ACCOUNT_NAME']}",
        user=os.environ["SNOWFLAKE_USER"],
        password=os.environ["SNOWFLAKE_PASSWORD"],
        database="PAYMENTS",
        schema="RAW",
        warehouse="ETL_XS",
    )
    with conn, conn.cursor() as cur:
        yield cur


def test_snowflake_matches_terraform():
    plan = terraform("plan", "-detailed-exitcode", "-input=false", "-no-color", "-lock=false")
    assert plan.returncode != 1, f"terraform plan errored:\n{plan.stderr}"
    changes = [line for line in plan.stdout.splitlines() if line.lstrip().startswith(("#", "~", "+", "-"))]
    assert plan.returncode == 0, "Snowflake has drifted from Terraform:\n" + "\n".join(changes)


def test_staged_files_match_table(cursor, expected_header):
    # Temporary format reads each line as one field, so the header comes back verbatim
    cursor.execute("CREATE TEMPORARY FILE FORMAT HEADER_LINE TYPE = CSV FIELD_DELIMITER = NONE SKIP_HEADER = 0")
    cursor.execute(
        f"SELECT METADATA$FILENAME, $1 FROM @{STAGE} (FILE_FORMAT => 'HEADER_LINE') "
        "WHERE METADATA$FILE_ROW_NUMBER = 1"
    )
    headers = {name: line.lower().split(",") for name, line in cursor.fetchall()}
    assert headers, f"No files on {STAGE}; nothing to check"

    drifted = {name: cols for name, cols in headers.items() if cols != expected_header}
    assert not drifted, f"Expected header {expected_header}\n" + "\n".join(
        f"  {name}: {cols}" for name, cols in drifted.items()
    )
