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
## 03_reporting_views
## 04_optimization
## Spark/Hadoop vs DuckDB mapping

