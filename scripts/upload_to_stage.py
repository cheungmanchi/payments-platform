# /// script
# requires-python = ">=3.10"
# dependencies = ["snowflake-connector-python>=3.12"]
# ///
"""PUT CSVs from data/ into the internal stage, then optionally run the load task now.

Usage: uv run scripts/upload_to_stage.py [--run-task]
Uses the same SNOWFLAKE_* env vars as Terraform. Files already on the stage are skipped.
"""

import argparse
import os
from pathlib import Path

import snowflake.connector

STAGE = "PAYMENTS.RAW.CARD_TXN_STAGE"
TASK = "PAYMENTS.RAW.LOAD_CARD_TRANSACTIONS"
DATA_DIR = Path(__file__).resolve().parent.parent / "data"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--run-task", action="store_true", help="trigger the COPY task instead of waiting for 06:00 UTC")
    args = parser.parse_args()

    files = sorted(DATA_DIR.glob("*.csv"))
    if not files:
        raise SystemExit(f"No CSVs in {DATA_DIR}. Run scripts/generate_transactions.py first.")

    conn = snowflake.connector.connect(
        account=f"{os.environ['SNOWFLAKE_ORGANIZATION_NAME']}-{os.environ['SNOWFLAKE_ACCOUNT_NAME']}",
        user=os.environ["SNOWFLAKE_USER"],
        password=os.environ["SNOWFLAKE_PASSWORD"],
    )
    with conn, conn.cursor() as cur:
        for f in files:
            cur.execute(f"PUT 'file://{f.as_posix()}' @{STAGE} AUTO_COMPRESS=TRUE OVERWRITE=FALSE")
            source, _, _, _, _, _, status, _ = cur.fetchone()
            print(f"{source}: {status}")
        if args.run_task:
            cur.execute(f"EXECUTE TASK {TASK}")
            print(f"Triggered {TASK}. Check TASK_HISTORY in runbook.sql in about 1 minute.")


if __name__ == "__main__":
    main()
