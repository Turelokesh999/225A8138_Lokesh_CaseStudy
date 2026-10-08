"""Single entry point: builds raw -> core -> reporting, then runs tests.

Usage:
    python run_pipeline.py             # full rebuild + tests
    python run_pipeline.py --skip-tests
    python run_pipeline.py --only 01   # run just sql/01_*.sql
"""
import argparse
import glob
import os
import subprocess
import sys
import time

import duckdb

DB_PATH = os.environ.get("DUCKDB_PATH", "warehouse.duckdb")
STEPS = ["01", "02", "03"]  # 04 (optimization) is run by scripts/benchmark.py


def run_sql_file(con, path):
    with open(path, encoding="utf-8") as f:
        sql = f.read()
    start = time.perf_counter()
    con.execute(sql)
    print(f"  ok  {os.path.basename(path)}  ({time.perf_counter() - start:.2f}s)")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--skip-tests", action="store_true")
    ap.add_argument("--only", help="step prefix, e.g. 01")
    args = ap.parse_args()

    # Fresh rebuild keeps the pipeline reproducible.
    if args.only is None and os.path.exists(DB_PATH):
        os.remove(DB_PATH)

    con = duckdb.connect(DB_PATH)
    print(f"DuckDB {duckdb.__version__} -> {DB_PATH}")
    for schema in ("raw", "core", "reporting"):
        con.execute(f"CREATE SCHEMA IF NOT EXISTS {schema}")

    steps = [args.only] if args.only else STEPS
    for step in steps:
        files = sorted(glob.glob(f"sql/{step}_*.sql"))
        if not files:
            print(f"  --  no file for step {step} yet, skipping")
        for path in files:
            run_sql_file(con, path)
    con.close()

    # The scaffold phase has no core model yet. Start enforcing the quality
    # gate as soon as the core SQL contains an implementation.
    core_sql = "sql/02_core_model.sql"
    core_is_implemented = os.path.isfile(core_sql) and "TODO" not in open(
        core_sql, encoding="utf-8"
    ).read()
    if not args.skip_tests and not args.only and core_is_implemented:
        sys.exit(subprocess.call([sys.executable, "scripts/run_tests.py"]))
    if not args.skip_tests and not args.only and not core_is_implemented:
        print("  --  core model not implemented; data quality gate deferred")


if __name__ == "__main__":
    main()
