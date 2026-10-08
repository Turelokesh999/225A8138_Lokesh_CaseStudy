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
