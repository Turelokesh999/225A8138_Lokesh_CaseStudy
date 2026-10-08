# Design Decisions (write in your own words)

## Setup
The requirements are pinned so a rebuild uses the same dependency versions.
The pipeline defers the data quality gate until the core model is implemented;
this lets the empty scaffold run while keeping the existing tests unchanged.

One short section per SQL file: what it does, why each join/transform exists,
and what trap it avoids. You must be able to explain every line in the viva.

## 01_raw_load
## 02_core_model
## 03_reporting_views
## 04_optimization
## Spark/Hadoop vs DuckDB mapping
