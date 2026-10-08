# Mini Data Warehouse: Phase Status and Codex Prompts

## Status

| Phase | Status |
|---|---|
| Setup | DONE |
| Raw load | DONE |
| Core model | DONE |
| Extra checks (Phase 3) | IN PROGRESS |
| Reporting | TODO |
| Benchmarks | TODO |
| Analysis | TODO |
| Report | TODO |
| Bonus | TODO |

## Phase 2 prompt: Core model

Work on `feat/core-model`. Read `AGENTS.md` first and follow its table contract and data rules. Implement `sql/02_core_model.sql` to build the clean star schema from the `raw` tables:

- Create `core.dim_customer`, `core.dim_product`, `core.dim_seller`, and `core.dim_date`.
- Create `core.fact_orders` and `core.fact_order_items` at their documented grains.
- Keep `customer_id` as the order-level dimension key and retain `customer_unique_id` for repeat-customer analysis.
- Aggregate payments and reviews to one row per order before joining; deduplicate reviews by keeping the latest per order.
- Collapse geolocation to one row per zip prefix before joining, and map missing product translations to the Portuguese category or `unknown`.
- Restrict delivery metrics to delivered orders with non-NULL timestamps.
- Do not modify `sql/05_tests.sql`. Run the pipeline and all existing data-quality tests; fix model logic if a check fails.
- Verified raw result: all 99,441 customer zip prefixes have length 5. Preserve those values; apply `lpad` only to rows whose zip prefix is actually shorter than 5 characters.
- Add a concise design decision note explaining the model choices, then show `git diff --stat` before committing.
