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
The core layer uses dimensions for customer, product, seller and calendar context,
with one order fact per order and one item fact per order line. I keep the source
customer key on orders and retain the stable customer_unique_id in the customer
dimension, so order joins stay valid while repeat-customer analysis can group
people across orders. Payments are summed and reviews are reduced to the latest
row at order grain before either is joined to orders; this avoids multiplying
orders or item revenue. Geolocation is averaged per postal prefix before lookup
for the same reason. Postal prefixes remain text, and lpad is conditional because
the raw customer prefixes were all five characters in the verifier run. Delivery
duration and lateness are populated only for delivered orders with the required
timestamps; missing translations fall back to the source category, then
`unknown`.

## 03_reporting_views
## 04_optimization
## Spark/Hadoop vs DuckDB mapping

