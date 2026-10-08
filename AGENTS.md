# AGENTS.md: Rules for Codex

Project: Mini Data Warehouse using DuckDB + SQL (Olist e-commerce dataset).
Layers: `raw` -> `core` (star schema) -> `reporting`.

## Hard rules
1. **Never fabricate results.** Every number, timing, or row count in docs or
   reports must come from a real run. Benchmarks are written to
   `results/benchmarks.csv` by code, never typed by hand.
2. **Run before commit.** Execute every SQL file you write against DuckDB and fix
   all errors before finishing. Show the command and its output.
3. **Do not edit tests to make them pass.** If a test in `sql/05_tests.sql`
   fails, fix the data/model logic. Changing a test requires explicit user approval.
4. **DuckDB SQL only.** No Spark, Postgres, or MySQL syntax. If unsure, check the DuckDB docs.
5. **One task per prompt.** Only touch files named in the task. Do not refactor
   unrelated files.
6. **Core first, bonus last.** Do not add Docker, Kubernetes, CI, or APIs until
   the user says the `v1-core` tag is done.
7. **No secrets, no data in git.** Never commit `.env`, `kaggle.json`, `data/`,
   `*.duckdb`, or `*.parquet`.
8. **Relative paths only.** No absolute paths, no hardcoded usernames.
9. **Single writer.** Only `run_pipeline.py` writes to the warehouse. Notebooks
   open it with `read_only=True` and close connections.

## Data rules (known traps)
- Use `customer_unique_id` (not `customer_id`) for repeat-rate, RFM, CLV.
- Aggregate `order_payments` and `order_reviews` to one row per order BEFORE joining to items.
- Deduplicate reviews: keep latest per `order_id` with `ROW_NUMBER()`.
- Collapse geolocation to one row per zip prefix before joining.
- Delivery metrics: only `order_status = 'delivered'` with non-NULL timestamps.
- Category: `COALESCE(english_name, portuguese_name, 'unknown')`.
- Declare explicit column types in `read_csv`; zip prefixes are VARCHAR.
- Growth analysis: use complete months only (about 2017-01 to 2018-08).
- Guard divisions with `NULLIF`.

## Table contract (tests depend on these names)
- `core.dim_customer(customer_id, customer_unique_id, ...)`
- `core.dim_product(product_id, ...)`, `core.dim_seller(seller_id, ...)`, `core.dim_date(date_key, ...)`
- `core.fact_orders(order_id, customer_id, ...)`
- `core.fact_order_items(order_id, order_item_id, product_id, seller_id, price, freight_value, ...)`
- Reporting views are prefixed `reporting.rpt_*`.

## Build order
1. `sql/01_raw_load.sql`  -> row counts printed
2. `sql/02_core_model.sql` -> `python scripts/run_tests.py` passes
3. `sql/03_reporting_views.sql`
4. `scripts/benchmark.py` + `sql/04_optimization.sql`
5. Charts, README, report
6. Bonus (only on request)

## Git
- Branch per task: `feat/raw-load`, `feat/core-model`, ...
- Small commits, message format: `feat: ...`, `fix: ...`, `test: ...`, `docs: ...`
- Show `git diff --stat` before committing. Do not push to `main` directly.

## Definition of done for any task
- SQL/script runs cleanly from scratch via `python run_pipeline.py`
- `python scripts/run_tests.py` passes (once core exists)
- Short note added to `docs/design_decisions.md` explaining the "why"
