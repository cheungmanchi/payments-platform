"""Write a CSV of fake card transactions to data/.

Usage: python scripts/generate_transactions.py [--rows 1000] [--seed 42]
Stdlib only. Column order must match the COPY INTO column list in ingest.tf.
"""

import argparse
import csv
import random
import uuid
from datetime import datetime, timedelta, timezone
from pathlib import Path

HEADER = ["txn_id", "card_id", "merchant_id", "mcc", "amount", "currency", "status", "txn_ts_utc"]

# Merchant category codes (ISO 18245) with a typical median spend in major units
MCCS = {"5411": 35, "5812": 25, "5541": 60, "4111": 3, "5732": 180, "5999": 20}
CURRENCIES = ["GBP"] * 8 + ["EUR", "USD"]
STATUSES = ["AUTHORIZED"] * 94 + ["DECLINED"] * 5 + ["REVERSED"]


def make_row(rng: random.Random, now: datetime) -> list:
    mcc = rng.choice(list(MCCS))
    amount = round(rng.lognormvariate(0, 0.6) * MCCS[mcc], 2)
    ts = now - timedelta(seconds=rng.randint(0, 86_400))
    return [
        str(uuid.UUID(int=rng.getrandbits(128), version=4)),
        f"card_{rng.randint(1, 500):06d}",
        f"mrch_{rng.randint(1, 200):05d}",
        mcc,
        f"{amount:.2f}",
        rng.choice(CURRENCIES),
        rng.choice(STATUSES),
        ts.strftime("%Y-%m-%d %H:%M:%S"),
    ]


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--rows", type=int, default=1000)
    parser.add_argument("--seed", type=int, default=None)
    args = parser.parse_args()

    rng = random.Random(args.seed)
    now = datetime.now(timezone.utc).replace(tzinfo=None)
    out = Path(__file__).resolve().parent.parent / "data" / f"card_transactions_{now:%Y%m%d_%H%M%S}.csv"
    out.parent.mkdir(exist_ok=True)

    with out.open("w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(HEADER)
        writer.writerows(make_row(rng, now) for _ in range(args.rows))

    print(out)


if __name__ == "__main__":
    main()
