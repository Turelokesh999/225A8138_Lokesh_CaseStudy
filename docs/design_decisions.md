# Design Decisions (write in your own words)

## Setup
The requirements are pinned so a rebuild uses the same dependency versions.
The pipeline defers the data quality gate until the core model is implemented;
this lets the empty scaffold run while keeping the existing tests unchanged.

One short section per SQL file: what it does, why each join/transform exists,
and what trap it avoids. You must be able to explain every line in the viva.

## 01_raw_load
I use explicit types because automatic inference can mistake identifiers and postal codes for numbers, or infer dates and money differently across files. Keeping IDs and zip prefixes as VARCHAR preserves their meaning as labels, while TIMESTAMP and DECIMAL give later SQL a stable starting schema.

The raw tables keep the source columns and values as they arrive. That makes the input auditable and puts cleaning and deduplication in the core layer, where those transformations can be explained separately.

The verifier counts CSV records with Python's csv.reader because review comments can contain quoted line breaks. wc -l counts physical lines, so a multiline comment could be counted as multiple records.

The verifier found all 99,441 customer zip prefixes have length 5. The core model should preserve them as-is and only apply lpad to a prefix if its length is actually below 5.
## 02_core_model
Draft for review and rewriting in my own words: the core model separates customer,
product, seller, and date attributes from order and order-item facts. Payments are
summed to one row per order before joining so split payments cannot multiply an
order row or its item revenue. Reviews use `ROW_NUMBER()` ordered by the latest
answer timestamp to keep one review per order. Delivery days use the difference
between purchase and customer-delivery calendar dates; lateness compares the
delivery and estimated-delivery timestamps. Both are only set for delivered
orders with a customer-delivery timestamp. A complete date calendar is generated
between the first and last purchase date. Zip prefixes stay text; the model checks
customer and seller zips together and applies five-character padding consistently
only if a source prefix is not already five characters. No geolocation join is
performed in this phase. Orders without items are preserved in the order fact;
some non-fulfillment statuses have no item rows in the source.

## 03_reporting_views
Draft for review and rewriting in my own words: reporting views aggregate from
the core star schema. Sales, seller, and regional revenue use item price and
aggregate at item or order grain before joining to dimensions, so order or
payment multiplicity cannot repeat revenue. Monthly growth is shown only inside
the complete-month window; January 2017 has no growth value because its previous
month is outside that window. Customer analysis groups by `customer_unique_id`;
recency is measured from the latest purchase date in the warehouse, while
frequency and monetary scores rank order count and item spend. Delivery measures
include delivered orders only, and late percentage uses orders with a known
estimated-delivery timestamp. Revenue is price only in sales and product reports;
freight is shown separately in monthly sales.

## 04_optimization
## Spark/Hadoop vs DuckDB mapping


## 05_scale_up
The scale-up dataset repeats real core order-item rows to make controlled performance tests large enough to measure. Price jitter and dates are generated from a fixed seed, so reruns are reproducible while year/month partitions contain useful spread. These rows are synthetic and must not be presented as actual Olist sales or business findings.
