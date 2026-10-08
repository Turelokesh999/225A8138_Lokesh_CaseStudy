-- Build the clean Olist star schema from raw source tables.

CREATE SCHEMA IF NOT EXISTS core;

-- Geolocation has many observations per postal prefix. Average coordinates
-- first so a customer or seller can match at most one geolocation row.
CREATE OR REPLACE TABLE core.dim_customer AS
WITH geo AS (
  SELECT geolocation_zip_code_prefix,
         avg(geolocation_lat) AS latitude,
         avg(geolocation_lng) AS longitude
  FROM raw.geolocation
  GROUP BY geolocation_zip_code_prefix
), customers AS (
  SELECT *,
         CASE WHEN length(trim(customer_zip_code_prefix)) < 5
              THEN lpad(trim(customer_zip_code_prefix), 5, '0')
              ELSE trim(customer_zip_code_prefix)
         END AS zip_prefix
  FROM raw.customers
)
SELECT c.customer_id,
       c.customer_unique_id,
       c.zip_prefix AS customer_zip_code_prefix,
       trim(c.customer_city) AS customer_city,
       upper(trim(c.customer_state)) AS customer_state,
       g.latitude,
       g.longitude
FROM customers c
LEFT JOIN geo g
  ON c.zip_prefix = g.geolocation_zip_code_prefix;

CREATE OR REPLACE TABLE core.dim_product AS
WITH translations AS (
  SELECT product_category_name,
         max(nullif(trim(product_category_name_english), '')) AS english_name
  FROM raw.category_translation
  GROUP BY product_category_name
), products AS (
  SELECT *, row_number() OVER (
    PARTITION BY product_id ORDER BY product_id
  ) AS rn
  FROM raw.products
)
SELECT p.product_id,
       coalesce(t.english_name, nullif(trim(p.product_category_name), ''), 'unknown')
         AS product_category,
       p.product_name_lenght AS product_name_length,
       p.product_description_lenght AS product_description_length,
       p.product_photos_qty AS product_photos_qty,
       p.product_weight_g AS product_weight_g,
       p.product_length_cm AS product_length_cm,
       p.product_height_cm AS product_height_cm,
       p.product_width_cm AS product_width_cm
FROM products p
LEFT JOIN translations t
  ON p.product_category_name = t.product_category_name
WHERE p.rn = 1;

CREATE OR REPLACE TABLE core.dim_seller AS
WITH geo AS (
  SELECT geolocation_zip_code_prefix,
         avg(geolocation_lat) AS latitude,
         avg(geolocation_lng) AS longitude
  FROM raw.geolocation
  GROUP BY geolocation_zip_code_prefix
), sellers AS (
  SELECT *, row_number() OVER (
    PARTITION BY seller_id ORDER BY seller_id
  ) AS rn,
  CASE WHEN length(trim(seller_zip_code_prefix)) < 5
       THEN lpad(trim(seller_zip_code_prefix), 5, '0')
       ELSE trim(seller_zip_code_prefix)
  END AS zip_prefix
  FROM raw.sellers
)
SELECT s.seller_id,
       s.zip_prefix AS seller_zip_code_prefix,
       trim(s.seller_city) AS seller_city,
       upper(trim(s.seller_state)) AS seller_state,
       g.latitude,
       g.longitude
FROM sellers s
LEFT JOIN geo g
  ON s.zip_prefix = g.geolocation_zip_code_prefix
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
       strftime(calendar_date, '%B') AS month_name,
       extract(day FROM calendar_date)::INTEGER AS day,
       extract(isodow FROM calendar_date)::INTEGER AS weekday,
       strftime(calendar_date, '%A') AS weekday_name
FROM calendar;

-- Payment and review tables are many-to-one at order grain. Reduce them
-- before joining to orders so they cannot multiply order rows or item revenue.
CREATE OR REPLACE TABLE core.fact_orders AS
WITH payments AS (
  SELECT order_id,
         sum(payment_value) AS payment_total,
         count(*)::INTEGER AS payment_count,
         max(payment_installments)::INTEGER AS max_payment_installments
  FROM raw.order_payments
  GROUP BY order_id
), latest_reviews AS (
  SELECT order_id, review_score, review_creation_date,
         review_answer_timestamp, review_comment_title,
         review_comment_message
  FROM raw.order_reviews
  QUALIFY row_number() OVER (
    PARTITION BY order_id
    ORDER BY review_creation_date DESC NULLS LAST,
             review_answer_timestamp DESC NULLS LAST,
             review_id DESC
  ) = 1
)
SELECT o.order_id,
       o.customer_id,
       o.order_status,
       o.order_purchase_timestamp,
       o.order_purchase_timestamp::DATE AS order_date,
       CAST(strftime(o.order_purchase_timestamp::DATE, '%Y%m%d') AS INTEGER)
         AS date_key,
       o.order_approved_at,
       o.order_delivered_carrier_date,
       o.order_delivered_customer_date,
       o.order_estimated_delivery_date,
       CASE WHEN o.order_status = 'delivered'
                  AND o.order_delivered_customer_date IS NOT NULL
                  AND o.order_purchase_timestamp IS NOT NULL
            THEN date_diff('day', o.order_purchase_timestamp::DATE,
                           o.order_delivered_customer_date::DATE)
       END AS delivery_days,
       CASE WHEN o.order_status = 'delivered'
                  AND o.order_delivered_customer_date IS NOT NULL
                  AND o.order_estimated_delivery_date IS NOT NULL
            THEN o.order_delivered_customer_date::DATE
                 > o.order_estimated_delivery_date::DATE
       END AS is_late,
       p.payment_total,
       coalesce(p.payment_count, 0) AS payment_count,
       p.max_payment_installments,
       r.review_score,
       r.review_creation_date,
       r.review_answer_timestamp,
       r.review_comment_title,
       r.review_comment_message
FROM raw.orders o
LEFT JOIN payments p ON o.order_id = p.order_id
LEFT JOIN latest_reviews r ON o.order_id = r.order_id;

CREATE OR REPLACE TABLE core.fact_order_items AS
SELECT order_id,
       order_item_id,
       product_id,
       seller_id,
       shipping_limit_date,
       price,
       freight_value,
       price + freight_value AS item_total
FROM raw.order_items;
