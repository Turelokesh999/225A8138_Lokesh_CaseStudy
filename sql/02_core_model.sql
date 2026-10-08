-- Build the core star schema from the raw Olist tables.

CREATE SCHEMA IF NOT EXISTS core;

-- Decide zip normalization consistently across customer and seller dimensions.
-- The current source has five-character prefixes, so this leaves them unchanged.
CREATE OR REPLACE TABLE core.dim_customer AS
WITH all_zips AS (
  SELECT customer_zip_code_prefix AS zip_prefix FROM raw.customers
  UNION ALL
  SELECT seller_zip_code_prefix FROM raw.sellers
), zip_policy AS (
  SELECT coalesce(bool_or(coalesce(length(trim(zip_prefix)) <> 5, true)), false) AS needs_lpad
  FROM all_zips
)
SELECT c.customer_id,
       c.customer_unique_id,
       trim(c.customer_city) AS city,
       upper(trim(c.customer_state)) AS state,
       CASE WHEN z.needs_lpad THEN lpad(trim(c.customer_zip_code_prefix), 5, '0')
            ELSE trim(c.customer_zip_code_prefix)
       END AS zip_prefix
FROM raw.customers c
CROSS JOIN zip_policy z;

CREATE OR REPLACE TABLE core.dim_product AS
WITH translations AS (
  SELECT product_category_name,
         max(nullif(trim(product_category_name_english), '')) AS category_en
  FROM raw.category_translation
  GROUP BY product_category_name
), products AS (
  SELECT *, row_number() OVER (
    PARTITION BY product_id
    ORDER BY product_category_name NULLS LAST,
             product_weight_g NULLS LAST,
             product_length_cm NULLS LAST,
             product_height_cm NULLS LAST,
             product_width_cm NULLS LAST
  ) AS rn
  FROM raw.products
)
SELECT p.product_id,
       nullif(trim(p.product_category_name), '') AS category_pt,
       coalesce(t.category_en, nullif(trim(p.product_category_name), ''), 'unknown')
         AS category_en,
       p.product_weight_g AS weight_g,
       p.product_length_cm AS length_cm,
       p.product_height_cm AS height_cm,
       p.product_width_cm AS width_cm,
       p.product_photos_qty AS photos_qty
FROM products p
LEFT JOIN translations t
  ON p.product_category_name = t.product_category_name
WHERE p.rn = 1;

CREATE OR REPLACE TABLE core.dim_seller AS
WITH all_zips AS (
  SELECT customer_zip_code_prefix AS zip_prefix FROM raw.customers
  UNION ALL
  SELECT seller_zip_code_prefix FROM raw.sellers
), zip_policy AS (
  SELECT coalesce(bool_or(coalesce(length(trim(zip_prefix)) <> 5, true)), false) AS needs_lpad
  FROM all_zips
), sellers AS (
  SELECT *, row_number() OVER (
    PARTITION BY seller_id
    ORDER BY seller_city NULLS LAST, seller_state NULLS LAST,
             seller_zip_code_prefix NULLS LAST
  ) AS rn
  FROM raw.sellers
)
SELECT s.seller_id,
       trim(s.seller_city) AS city,
       upper(trim(s.seller_state)) AS state,
       CASE WHEN z.needs_lpad THEN lpad(trim(s.seller_zip_code_prefix), 5, '0')
            ELSE trim(s.seller_zip_code_prefix)
       END AS zip_prefix
FROM sellers s
CROSS JOIN zip_policy z
WHERE s.rn = 1;

CREATE OR REPLACE TABLE core.dim_date AS
WITH bounds AS (
  SELECT min(order_purchase_timestamp)::DATE AS min_date,
         max(order_purchase_timestamp)::DATE AS max_date
  FROM raw.orders
  WHERE order_purchase_timestamp IS NOT NULL
), calendar AS (
  SELECT d::DATE AS calendar_date
  FROM bounds,
       generate_series(min_date, max_date, INTERVAL 1 DAY) AS dates(d)
)
SELECT CAST(strftime(calendar_date, '%Y%m%d') AS INTEGER) AS date_key,
       calendar_date,
       extract(year FROM calendar_date)::INTEGER AS year,
       extract(quarter FROM calendar_date)::INTEGER AS quarter,
       extract(month FROM calendar_date)::INTEGER AS month,
       extract(day FROM calendar_date)::INTEGER AS day,
       extract(isodow FROM calendar_date)::INTEGER AS day_of_week,
       extract(isodow FROM calendar_date) IN (6, 7) AS is_weekend
FROM calendar;

-- Aggregate the many payment rows and choose one latest review per order before
-- joining either to orders. This preserves one fact row per order.
CREATE OR REPLACE TABLE core.fact_orders AS
WITH payments AS (
  SELECT order_id,
         sum(payment_value) AS payment_total,
         max(payment_installments)::INTEGER AS payment_installments_max
  FROM raw.order_payments
  GROUP BY order_id
), ranked_reviews AS (
  SELECT order_id, review_score,
         row_number() OVER (
           PARTITION BY order_id
           ORDER BY review_answer_timestamp DESC NULLS LAST,
                    review_creation_date DESC NULLS LAST,
                    review_id DESC
         ) AS rn
  FROM raw.order_reviews
), latest_reviews AS (
  SELECT order_id, review_score
  FROM ranked_reviews
  WHERE rn = 1
)
SELECT o.order_id,
       o.customer_id,
       o.order_status,
       o.order_purchase_timestamp AS purchase_ts,
       o.order_approved_at AS approved_ts,
       o.order_delivered_carrier_date AS delivered_carrier_ts,
       o.order_delivered_customer_date AS delivered_customer_ts,
       o.order_estimated_delivery_date AS estimated_delivery_ts,
       CAST(strftime(o.order_purchase_timestamp::DATE, '%Y%m%d') AS INTEGER)
         AS date_key,
       CASE WHEN o.order_status = 'delivered'
                  AND o.order_delivered_customer_date IS NOT NULL
                  AND o.order_purchase_timestamp IS NOT NULL
            THEN date_diff('day', o.order_purchase_timestamp::DATE,
                           o.order_delivered_customer_date::DATE)
       END AS delivery_days,
       CASE WHEN o.order_status = 'delivered'
                  AND o.order_delivered_customer_date IS NOT NULL
                  AND o.order_estimated_delivery_date IS NOT NULL
            THEN o.order_delivered_customer_date > o.order_estimated_delivery_date
       END AS is_late,
       p.payment_total,
       p.payment_installments_max,
       r.review_score
FROM raw.orders o
LEFT JOIN payments p ON o.order_id = p.order_id
LEFT JOIN latest_reviews r ON o.order_id = r.order_id;

CREATE OR REPLACE TABLE core.fact_order_items AS
SELECT order_id,
       order_item_id,
       product_id,
       seller_id,
       price,
       freight_value,
       shipping_limit_date AS shipping_limit_ts
FROM raw.order_items;
