"""Independent check of sql/01_raw_load.sql.

Counts records in each CSV with Python's csv module (which understands quoted
multi-line fields, unlike `wc -l`) and compares with the DuckDB raw tables.
Exit code 1 on any mismatch.
"""
import csv
import os
import sys
from pathlib import Path

import duckdb

ROOT = Path(__file__).resolve().parent.parent
os.chdir(ROOT)
_db = Path(os.environ.get("DUCKDB_PATH", "warehouse.duckdb"))
DB_PATH = _db if _db.is_absolute() else ROOT / _db

TABLES = {
    "customers": "olist_customers_dataset.csv",
    "geolocation": "olist_geolocation_dataset.csv",
    "orders": "olist_orders_dataset.csv",
    "order_items": "olist_order_items_dataset.csv",
    "order_payments": "olist_order_payments_dataset.csv",
    "order_reviews": "olist_order_reviews_dataset.csv",
    "products": "olist_products_dataset.csv",
    "sellers": "olist_sellers_dataset.csv",
    "category_translation": "product_category_name_translation.csv",
}


def csv_records(path):
    with open(path, encoding="utf-8", newline="") as f:
        return sum(1 for _ in csv.reader(f)) - 1  # minus header


def main():
    if not DB_PATH.exists():
        print(f"ERROR: {DB_PATH} not found. Run: python run_pipeline.py --only 01")
        sys.exit(2)
    con = duckdb.connect(str(DB_PATH), read_only=True)
    bad = 0
    print(f"{'table':<22}{'csv records':>14}{'duckdb rows':>14}  status")
    for table, fname in TABLES.items():
        expected = csv_records(Path("data/raw") / fname)
        actual = con.execute(f"SELECT count(*) FROM raw.{table}").fetchone()[0]
        ok = expected == actual
        bad += not ok
        print(f"{table:<22}{expected:>14,}{actual:>14,}  {'OK' if ok else 'MISMATCH'}")

    print("\nDESCRIBE raw.orders / raw.order_items")
    for t in ("orders", "order_items"):
        for row in con.execute(f"DESCRIBE raw.{t}").fetchall():
            print(f"  {t}.{row[0]:<32}{row[1]}")

    print("\nSanity checks")
    q = lambda s: con.execute(s).fetchone()[0]
    print("  orders with NULL purchase timestamp :", q("SELECT count(*) FROM raw.orders WHERE order_purchase_timestamp IS NULL"))
    print("  customer zip length distribution    :",
          con.execute("SELECT length(customer_zip_code_prefix) l, count(*) FROM raw.customers GROUP BY 1 ORDER BY 1").fetchall())
    con.close()
    print(f"\n{bad} table(s) with mismatched counts")
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
