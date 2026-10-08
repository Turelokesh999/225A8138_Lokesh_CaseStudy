-- Business reporting views. Every view is built only from core tables.
CREATE SCHEMA IF NOT EXISTS reporting;

-- Monthly sales are aggregated separately at order and item grain so item
-- rows cannot multiply order counts. Revenue is item price; freight is separate.
CREATE OR REPLACE VIEW reporting.rpt_sales_summary AS
WITH months AS (
  SELECT DISTINCT date_trunc('month', calendar_date)::DATE AS month
  FROM core.dim_date
), orders_by_month AS (
  SELECT date_trunc('month', purchase_ts)::DATE AS month,
         count(*) AS orders
  FROM core.fact_orders
  WHERE purchase_ts IS NOT NULL
  GROUP BY 1
), items_by_month AS (
  SELECT date_trunc('month', o.purchase_ts)::DATE AS month,
         count(*) AS items,
         sum(i.price) AS revenue,
         sum(i.freight_value) AS freight
  FROM core.fact_order_items i
  JOIN core.fact_orders o USING (order_id)
  WHERE o.purchase_ts IS NOT NULL
  GROUP BY 1
), monthly AS (
  SELECT m.month,
         coalesce(o.orders, 0) AS orders,
         coalesce(i.items, 0) AS items,
         coalesce(i.revenue, 0) AS revenue,
         coalesce(i.freight, 0) AS freight,
         m.month BETWEEN DATE '2017-01-01' AND DATE '2018-08-01'
           AS is_complete_month
  FROM months m
  LEFT JOIN orders_by_month o USING (month)
  LEFT JOIN items_by_month i USING (month)
), lagged AS (
  SELECT *, lag(revenue) OVER (ORDER BY month) AS previous_month_revenue,
            lag(month) OVER (ORDER BY month) AS previous_month
  FROM monthly
)
SELECT month,
       orders,
       items,
       revenue,
       freight,
       revenue / NULLIF(orders, 0) AS aov,
       is_complete_month,
       CASE WHEN is_complete_month
                  AND previous_month BETWEEN DATE '2017-01-01' AND DATE '2018-08-01'
            THEN 100.0 * (revenue - previous_month_revenue)
                 / NULLIF(previous_month_revenue, 0)
       END AS revenue_growth_pct
FROM lagged;

CREATE OR REPLACE VIEW reporting.rpt_product_performance AS
WITH item_categories AS (
  SELECT i.order_id,
         coalesce(p.category_en, 'unknown') AS category_en,
         i.price,
         o.review_score
  FROM core.fact_order_items i
  JOIN core.fact_orders o USING (order_id)
  JOIN core.dim_product p USING (product_id)
), category_sales AS (
  SELECT category_en,
         count(*) AS items_sold,
         sum(price) AS revenue
  FROM item_categories
  GROUP BY category_en
), order_category_reviews AS (
  SELECT DISTINCT order_id, category_en, review_score
  FROM item_categories
  WHERE review_score IS NOT NULL
), category_reviews AS (
  SELECT category_en, avg(review_score) AS avg_review_score
  FROM order_category_reviews
  GROUP BY category_en
)
SELECT s.category_en,
       s.items_sold,
       s.revenue,
       100.0 * s.revenue / NULLIF(sum(s.revenue) OVER (), 0) AS revenue_share_pct,
       r.avg_review_score,
       rank() OVER (ORDER BY s.revenue DESC) AS revenue_rank
FROM category_sales s
LEFT JOIN category_reviews r USING (category_en);

CREATE OR REPLACE VIEW reporting.rpt_customer_analysis AS
WITH spend_by_order AS (
  SELECT order_id, sum(price + freight_value) AS order_spend
  FROM core.fact_order_items
  GROUP BY order_id
), customer_orders AS (
  SELECT c.customer_unique_id,
         o.order_id,
         o.purchase_ts::DATE AS order_date,
         coalesce(s.order_spend, 0) AS order_spend
  FROM core.fact_orders o
  JOIN core.dim_customer c USING (customer_id)
  LEFT JOIN spend_by_order s USING (order_id)
), customer_totals AS (
  SELECT customer_unique_id,
         count(DISTINCT order_id) AS orders,
         sum(order_spend) AS total_spend,
         min(order_date) AS first_order_date,
         max(order_date) AS last_order_date
  FROM customer_orders
  GROUP BY customer_unique_id
), as_of AS (
  SELECT max(order_date) AS as_of_date FROM customer_orders
), rfm_base AS (
  SELECT t.*,
         date_diff('day', t.last_order_date, a.as_of_date) AS recency_days
  FROM customer_totals t
  CROSS JOIN as_of a
), rfm_scores AS (
  SELECT *,
         ntile(5) OVER (ORDER BY recency_days DESC, customer_unique_id) AS recency_score,
         CASE WHEN orders = 1 THEN 1
              WHEN orders = 2 THEN 3
              WHEN orders >= 3 THEN 5
         END AS frequency_score,
         ntile(5) OVER (ORDER BY total_spend, customer_unique_id) AS monetary_score
  FROM rfm_base
)
SELECT customer_unique_id,
       orders,
       total_spend,
       first_order_date,
       last_order_date,
       orders > 1 AS is_repeat,
       recency_score,
       frequency_score,
       monetary_score,
       CASE WHEN recency_score >= 4 AND frequency_score >= 4 AND monetary_score >= 4
              THEN 'champions'
            WHEN frequency_score >= 4 AND recency_score >= 3
              THEN 'loyal customers'
            WHEN recency_score = 5 AND frequency_score = 1
              THEN 'new customers'
            WHEN recency_score <= 2
              THEN 'at risk'
            ELSE 'regular'
       END AS rfm_segment
FROM rfm_scores;

CREATE OR REPLACE VIEW reporting.rpt_delivery_performance AS
SELECT date_trunc('month', o.purchase_ts)::DATE AS month,
       c.state,
       avg(o.delivery_days) AS avg_delivery_days,
       100.0 * count(*) FILTER (WHERE o.is_late = true)
         / NULLIF(count(*) FILTER (WHERE o.is_late IS NOT NULL), 0) AS late_pct,
       count(*) AS delivered_orders
FROM core.fact_orders o
JOIN core.dim_customer c USING (customer_id)
WHERE o.order_status = 'delivered'
GROUP BY 1, 2;

CREATE OR REPLACE VIEW reporting.rpt_seller_scorecard AS
WITH seller_orders AS (
  SELECT i.seller_id,
         i.order_id,
         sum(i.price) AS revenue,
         max(o.review_score) AS review_score,
         max(o.is_late) AS is_late
  FROM core.fact_order_items i
  JOIN core.fact_orders o USING (order_id)
  GROUP BY i.seller_id, i.order_id
), seller_metrics AS (
  SELECT seller_id,
         sum(revenue) AS revenue,
         count(*) AS orders,
         avg(review_score) AS avg_review_score,
         100.0 * count(*) FILTER (WHERE is_late = false)
           / NULLIF(count(*) FILTER (WHERE is_late IS NOT NULL), 0) AS on_time_pct
  FROM seller_orders
  GROUP BY seller_id
)
SELECT s.seller_id,
       coalesce(m.revenue, 0) AS revenue,
       coalesce(m.orders, 0) AS orders,
       m.avg_review_score,
       m.on_time_pct,
       rank() OVER (ORDER BY coalesce(m.revenue, 0) DESC) AS revenue_rank
FROM core.dim_seller s
LEFT JOIN seller_metrics m USING (seller_id);

CREATE OR REPLACE VIEW reporting.rpt_regional_sales AS
WITH spend_by_order AS (
  SELECT order_id, sum(price) AS revenue
  FROM core.fact_order_items
  GROUP BY order_id
)
SELECT c.state,
       c.city,
       count(*) AS orders,
       sum(coalesce(s.revenue, 0)) AS revenue,
       count(DISTINCT c.customer_unique_id) AS customers
FROM core.fact_orders o
JOIN core.dim_customer c USING (customer_id)
LEFT JOIN spend_by_order s USING (order_id)
GROUP BY c.state, c.city;
