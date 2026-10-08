"""Build reproducible synthetic sales data for DuckDB performance experiments.

The source rows come from core.fact_order_items joined to core.fact_orders and
core.dim_customer. This script generates scale-up data only; it does not run
benchmarks.
"""
from __future__ import annotations

import argparse
import random
import shutil
from datetime import date, timedelta
from pathlib import Path

import duckdb

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_DATABASE = ROOT / "warehouse.duckdb"
SCALED_DIR = ROOT / "data" / "scaled"
START_DATE = date(2016, 1, 1)
DATE_SPAN_DAYS = (date(2019, 1, 1) - START_DATE).days


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--replications", "-N", type=int, default=100,
                        help="number of synthetic copies per source row (default: 100)")
    parser.add_argument("--seed", type=int, default=42,
                        help="fixed random seed used for date and price variation")
    parser.add_argument("--database", type=Path, default=DEFAULT_DATABASE,
                        help="DuckDB warehouse path (default: warehouse.duckdb)")
    args = parser.parse_args()
    if args.replications < 1:
        parser.error("--replications must be at least 1")
    return args


def format_size(byte_count: int) -> str:
    size = float(byte_count)
    for unit in ("B", "KiB", "MiB", "GiB", "TiB"):
        if size < 1024 or unit == "TiB":
            return f"{size:.2f} {unit}"
        size /= 1024
    return f"{size:.2f} TiB"


def clear_previous_exports() -> None:
    SCALED_DIR.mkdir(parents=True, exist_ok=True)
    for name in ("sales_scaled.csv", "sales_scaled.parquet"):
        path = SCALED_DIR / name
        if path.exists():
            path.unlink()
    partitioned = SCALED_DIR / "sales_partitioned"
    if partitioned.exists():
        shutil.rmtree(partitioned)


def main() -> None:
    args = parse_args()
    database = args.database if args.database.is_absolute() else ROOT / args.database
    if not database.is_file():
        raise SystemExit(f"Warehouse not found: {database}. Run python run_pipeline.py first.")

    rng = random.Random(args.seed)
    replica_rows = []
    for replica_id in range(args.replications):
        jitter = rng.uniform(-0.01, 0.01)
        purchase_date = START_DATE + timedelta(days=rng.randrange(DATE_SPAN_DAYS))
        replica_rows.append((replica_id, jitter, purchase_date))

    clear_previous_exports()
    con = duckdb.connect(str(database))
    try:
        con.execute("CREATE SCHEMA IF NOT EXISTS bench")
        con.execute("""
            CREATE TEMP TABLE replica_metadata (
                replica_id INTEGER,
                price_jitter DOUBLE,
                purchase_date DATE
            )
        """)
        con.executemany(
            "INSERT INTO replica_metadata VALUES (?, ?, ?)", replica_rows
        )
        con.execute("""
            CREATE OR REPLACE TABLE bench.sales_scaled AS
            SELECT
                CAST(i.order_id || '__r' || lpad(CAST(r.replica_id AS VARCHAR), 3, '0') AS VARCHAR) AS order_id,
                i.order_item_id,
                ROUND(i.price * (1 + r.price_jitter), 2) AS price,
                i.freight_value,
                r.purchase_date,
                c.state AS customer_state,
                EXTRACT(YEAR FROM r.purchase_date)::INTEGER AS year,
                EXTRACT(MONTH FROM r.purchase_date)::INTEGER AS month
            FROM core.fact_order_items AS i
            JOIN core.fact_orders AS o USING (order_id)
            JOIN core.dim_customer AS c ON c.customer_id = o.customer_id
            CROSS JOIN replica_metadata AS r
        """)
        row_count = con.execute("SELECT COUNT(*) FROM bench.sales_scaled").fetchone()[0]
        con.execute(
            f"COPY bench.sales_scaled TO '{(SCALED_DIR / 'sales_scaled.csv').as_posix()}' "
            "(FORMAT CSV, HEADER TRUE)"
        )
        con.execute(
            f"COPY bench.sales_scaled TO '{(SCALED_DIR / 'sales_scaled.parquet').as_posix()}' "
            "(FORMAT PARQUET, COMPRESSION ZSTD)"
        )
        partition_dir = SCALED_DIR / "sales_partitioned"
        con.execute(
            f"COPY bench.sales_scaled TO '{partition_dir.as_posix()}' "
            "(FORMAT PARQUET, PARTITION_BY (year, month), COMPRESSION ZSTD)"
        )
    finally:
        con.close()

    csv_path = SCALED_DIR / "sales_scaled.csv"
    parquet_path = SCALED_DIR / "sales_scaled.parquet"
    partitioned_files = list((SCALED_DIR / "sales_partitioned").rglob("*.parquet"))
    partitioned_size = sum(path.stat().st_size for path in partitioned_files)
    print(f"Synthetic table: bench.sales_scaled")
    print(f"Replications per source row: {args.replications}")
    print(f"Random seed: {args.seed}")
    print(f"Rows: {row_count:,}")
    print(f"CSV: {csv_path.relative_to(ROOT)} - {format_size(csv_path.stat().st_size)}")
    print(f"Parquet: {parquet_path.relative_to(ROOT)} - {format_size(parquet_path.stat().st_size)}")
    print(
        f"Partitioned Parquet: {(SCALED_DIR / 'sales_partitioned').relative_to(ROOT)} "
        f"- {len(partitioned_files)} files, {format_size(partitioned_size)}"
    )


if __name__ == "__main__":
    main()
