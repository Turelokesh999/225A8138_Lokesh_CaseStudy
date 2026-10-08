"""Run sql/05_tests.sql; each test query returns a violation count (0 = pass)."""
import os
import re
import sys
from pathlib import Path

import duckdb

ROOT = Path(__file__).resolve().parents[1]

def project_path(value):
    path = Path(value)
    return path if path.is_absolute() else ROOT / path

DB_PATH = project_path(os.environ.get("DUCKDB_PATH", "warehouse.duckdb"))
TEST_FILE = ROOT / "sql" / "05_tests.sql"


def load_tests(path):
    text = path.read_text(encoding="utf-8")
    parts = re.split(r"^-- test:\s*(.+)$", text, flags=re.MULTILINE)
    return list(zip(parts[1::2], parts[2::2]))


def main():
    if not DB_PATH.is_file():
        print(f"ERROR: database not found: {DB_PATH}. Run python run_pipeline.py first.", file=sys.stderr)
        return 2
    if not TEST_FILE.is_file():
        print(f"ERROR: test file not found: {TEST_FILE}", file=sys.stderr)
        return 2

    con = duckdb.connect(str(DB_PATH), read_only=True)
    failed = 0
    for name, sql in load_tests(TEST_FILE):
        name = name.strip()
        try:
            bad = con.execute(sql.strip().rstrip(";")).fetchone()[0]
            status = "PASS" if bad == 0 else "FAIL"
            detail = "" if bad == 0 else f" ({bad} violations)"
        except Exception as e:
            status, detail, bad = "ERROR", f" ({e})", 1
        if bad != 0:
            failed += 1
        print(f"[{status}] {name}{detail}")
    con.close()
    print(f"\n{failed} failing test(s)")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())

