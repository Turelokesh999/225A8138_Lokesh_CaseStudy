"""Benchmark harness: warm-up + N runs, median/min/max, appended to results/benchmarks.csv.
Times query EXECUTION via fetchall() (not pandas conversion).
"""
import csv
import os
import statistics
import time

import duckdb

DB_PATH = os.environ.get("DUCKDB_PATH", "warehouse.duckdb")
OUT = "results/benchmarks.csv"
RUNS = 5


def bench(con, experiment, variant, sql, runs=RUNS):
    con.execute(sql).fetchall()  # warm-up, not recorded
    times = []
    for _ in range(runs):
        t = time.perf_counter()
        con.execute(sql).fetchall()
        times.append(time.perf_counter() - t)
    row = [experiment, variant, runs, round(statistics.median(times), 4),
           round(min(times), 4), round(max(times), 4)]
    new = not os.path.exists(OUT)
    with open(OUT, "a", newline="") as f:
        w = csv.writer(f)
        if new:
            w.writerow(["experiment", "variant", "runs", "median_s", "min_s", "max_s"])
        w.writerow(row)
    print(row)


if __name__ == "__main__":
    con = duckdb.connect(DB_PATH)
    # TODO (Codex): threads 1/2/4/8, CSV vs Parquet vs table, partition pruning,
    # view vs table, memory_limit spill (set temp_directory first).
    # Run on the SCALED-UP table, not raw Olist (too small to show differences).
    con.close()
