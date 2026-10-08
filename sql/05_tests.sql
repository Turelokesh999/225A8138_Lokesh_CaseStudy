-- Data quality gate. Each block returns ONE number: violations (0 = pass).
-- DO NOT weaken these without explicit approval.

-- test: dim_customer primary key unique
SELECT count(*) - count(DISTINCT customer_id) FROM core.dim_customer;

-- test: dim_product primary key unique
SELECT count(*) - count(DISTINCT product_id) FROM core.dim_product;

-- test: dim_seller primary key unique
SELECT count(*) - count(DISTINCT seller_id) FROM core.dim_seller;

-- test: fact_orders primary key unique
SELECT count(*) - count(DISTINCT order_id) FROM core.fact_orders;

-- test: fact_order_items grain unique (order_id, order_item_id)
SELECT count(*) - count(DISTINCT (order_id, order_item_id)) FROM core.fact_order_items;

-- test: no NULL keys in fact_order_items
SELECT count(*) FROM core.fact_order_items
WHERE order_id IS NULL OR product_id IS NULL OR seller_id IS NULL;

-- test: no orphan items -> orders
SELECT count(*) FROM core.fact_order_items i
LEFT JOIN core.fact_orders o ON i.order_id = o.order_id
WHERE o.order_id IS NULL;

-- test: no orphan items -> products
SELECT count(*) FROM core.fact_order_items i
LEFT JOIN core.dim_product p ON i.product_id = p.product_id
WHERE p.product_id IS NULL;

-- test: no orphan items -> sellers
SELECT count(*) FROM core.fact_order_items i
LEFT JOIN core.dim_seller s ON i.seller_id = s.seller_id
WHERE s.seller_id IS NULL;

-- test: no orphan orders -> customers
SELECT count(*) FROM core.fact_orders o
LEFT JOIN core.dim_customer c ON o.customer_id = c.customer_id
WHERE c.customer_id IS NULL;

-- test: orders row count matches raw
SELECT abs((SELECT count(*) FROM raw.orders) - (SELECT count(*) FROM core.fact_orders));

-- test: revenue reconciliation (core items total = raw items total)
SELECT CASE WHEN abs(
  (SELECT sum(price + freight_value) FROM core.fact_order_items) -
  (SELECT sum(price + freight_value) FROM raw.order_items)
) < 0.01 THEN 0 ELSE 1 END;

-- test: reporting sales revenue reconciles for complete months
SELECT CASE WHEN abs(
  (SELECT sum(revenue) FROM reporting.rpt_sales_summary
   WHERE month >= DATE '2017-01-01' AND month < DATE '2018-09-01') -
  (SELECT sum(i.price) FROM core.fact_order_items i
   JOIN core.fact_orders o USING (order_id)
   WHERE o.purchase_ts >= TIMESTAMP '2017-01-01'
     AND o.purchase_ts < TIMESTAMP '2018-09-01')
) < 0.01 THEN 0 ELSE 1 END;

-- test: product performance revenue reconciles to core item price
SELECT CASE WHEN abs(
  (SELECT sum(revenue) FROM reporting.rpt_product_performance) -
  (SELECT sum(price) FROM core.fact_order_items)
) < 0.01 THEN 0 ELSE 1 END;

-- test: customer analysis has one row per customer_unique_id
SELECT count(*) - count(DISTINCT customer_unique_id)
FROM reporting.rpt_customer_analysis;

-- test: delivery report covers every delivered order exactly once
SELECT abs(
  (SELECT sum(delivered_orders) FROM reporting.rpt_delivery_performance) -
  (SELECT count(*) FROM core.fact_orders WHERE order_status = 'delivered')
);

-- test: seller scorecard revenue reconciles to core item price
SELECT CASE WHEN abs(
  (SELECT sum(revenue) FROM reporting.rpt_seller_scorecard) -
  (SELECT sum(price) FROM core.fact_order_items)
) < 0.01 THEN 0 ELSE 1 END;

-- test: regional sales revenue reconciles to core item price
SELECT CASE WHEN abs(
  (SELECT sum(revenue) FROM reporting.rpt_regional_sales) -
  (SELECT sum(price) FROM core.fact_order_items)
) < 0.01 THEN 0 ELSE 1 END;

-- test: customer RFM scores are all from 1 through 5
SELECT count(*) FROM reporting.rpt_customer_analysis
WHERE recency_score NOT BETWEEN 1 AND 5
   OR frequency_score NOT BETWEEN 1 AND 5
   OR monetary_score NOT BETWEEN 1 AND 5;

-- test: product revenue shares total 100 percent
SELECT CASE WHEN abs(sum(revenue_share_pct) - 100.0) < 0.01
            THEN 0 ELSE 1 END
FROM reporting.rpt_product_performance;

-- test: sales growth is restricted to complete months with a complete prior month
SELECT count(*) FROM reporting.rpt_sales_summary
WHERE is_complete_month IS DISTINCT FROM
        (month BETWEEN DATE '2017-01-01' AND DATE '2018-08-01')
   OR (revenue_growth_pct IS NOT NULL AND
       (NOT is_complete_month OR month = DATE '2017-01-01'));
