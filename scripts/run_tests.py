"""Runs sql/05_tests.sql. Each test is a block starting with `-- test: <name>`
followed by a query returning ONE number = count of failures (0 = pass).
"""
import os
import re
import sys

import duckdb

DB_PATH = os.environ.get("DUCKDB_PATH", "warehouse.duckdb")
TEST_FILE = "sql/05_tests.sql"


def load_tests(path):
    text = open(path, encoding="utf-8").read()
    parts = re.split(r"^-- test:\s*(.+)$", text, flags=re.MULTILINE)
    return list(zip(parts[1::2], parts[2::2]))  # (name, sql)


def main():
    con = duckdb.connect(DB_PATH, read_only=True)
    failed = 0
    for name, sql in load_tests(TEST_FILE):
        name = name.strip()
        try:
            bad = con.execute(sql.strip().rstrip(";")).fetchone()[0]
            status = "PASS" if bad == 0 else "FAIL"
            detail = "" if bad == 0 else f" ({bad} violations)"
        except Exception as e:  # missing table counts as failure
            status, detail, bad = "ERROR", f" ({e})", 1
        if bad != 0:
            failed += 1
        print(f"[{status}] {name}{detail}")
    con.close()
    print(f"\n{failed} failing test(s)")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
