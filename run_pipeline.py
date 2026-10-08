"""Single entry point: builds raw -> core -> reporting, then runs tests."""
import argparse
import os
import subprocess
import sys
import time
from pathlib import Path

import duckdb

ROOT = Path(__file__).resolve().parent

def project_path(value):
    path = Path(value)
    return path if path.is_absolute() else ROOT / path

DB_PATH = project_path(os.environ.get("DUCKDB_PATH", "warehouse.duckdb"))
STEPS = ["01", "02", "03"]


def run_sql_file(con, path):
    sql = path.read_text(encoding="utf-8")
    start = time.perf_counter()
    con.execute(sql)
    print(f"  ok  {path.name}  ({time.perf_counter() - start:.2f}s)")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--skip-tests", action="store_true")
    ap.add_argument("--only", help="step prefix, e.g. 01")
    args = ap.parse_args()

    if args.only is None and DB_PATH.exists():
        DB_PATH.unlink()

    con = duckdb.connect(str(DB_PATH))
    print(f"DuckDB {duckdb.__version__} -> {DB_PATH}")
    for schema in ("raw", "core", "reporting"):
        con.execute(f"CREATE SCHEMA IF NOT EXISTS {schema}")

    steps = [args.only] if args.only else STEPS
    for step in steps:
        files = sorted((ROOT / "sql").glob(f"{step}_*.sql"))
        if not files:
            print(f"  --  no file for step {step} yet, skipping")
        for path in files:
            run_sql_file(con, path)
    con.close()

    core_sql = ROOT / "sql" / "02_core_model.sql"
    core_is_implemented = core_sql.is_file() and "TODO" not in core_sql.read_text(encoding="utf-8")
    if not args.skip_tests and not args.only and core_is_implemented:
        sys.exit(subprocess.call([sys.executable, str(ROOT / "scripts" / "run_tests.py")], cwd=ROOT))
    if not args.skip_tests and not args.only and not core_is_implemented:
        print("  --  core model not implemented; data quality gate deferred")


if __name__ == "__main__":
    main()
