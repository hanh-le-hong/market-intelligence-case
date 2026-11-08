-- =====================================================================
-- 00a_table_audit.sql
-- Per-table audit of database case_s_x against the case schema and
-- Appendix A. Three layers per table:
--   1. structure : columns and data types (compare with the schema diagram)
--   2. volume    : row count
--   3. content   : sample rows, categorical values, numeric/date ranges
-- Run block by block in VS Code (select a block, Cmd+Shift+E).
-- =====================================================================


-- ---------------------------------------------------------------------
-- LAYER 1: STRUCTURE. All 10 tables, all columns, data types, PK flag.
-- Compare column names and types with the schema diagram.
-- ---------------------------------------------------------------------
SELECT
    c.table_name,
    c.ordinal_position                     AS pos,
    c.column_name,
    c.data_type,
    CASE WHEN pk.column_name IS NOT NULL THEN 'PK' END AS key_flag
FROM information_schema.columns c
LEFT JOIN (
    SELECT kcu.table_name, kcu.column_name
    FROM information_schema.table_constraints tc
    JOIN information_schema.key_column_usage kcu
      ON kcu.constraint_name = tc.constraint_name
    WHERE tc.constraint_type = 'PRIMARY KEY'
) pk ON pk.table_name = c.table_name AND pk.column_name = c.column_name
WHERE c.table_schema = 'public'
ORDER BY c.table_name, c.ordinal_position;


-- ---------------------------------------------------------------------
-- LAYER 2: VOLUME. Row count per table.
-- ---------------------------------------------------------------------
SELECT 'dim_s_shop'                    AS table_name, COUNT(*) AS row_count FROM dim_s_shop
UNION ALL SELECT 'dim_s_product',                     COUNT(*) FROM dim_s_product
UNION ALL SELECT 'fact_s_order',                      COUNT(*) FROM fact_s_order
UNION ALL SELECT 'fact_s_order_item',                 COUNT(*) FROM fact_s_order_item
UNION ALL SELECT 'crawled_dim_x_shop',                COUNT(*) FROM crawled_dim_x_shop
UNION ALL SELECT 'crawled_dim_x_product',             COUNT(*) FROM crawled_dim_x_product
UNION ALL SELECT 'crawled_fact_x_shop',               COUNT(*) FROM crawled_fact_x_shop
UNION ALL SELECT 'crawled_fact_x_product',            COUNT(*) FROM crawled_fact_x_product
UNION ALL SELECT 'market_research_fact_x_shop',       COUNT(*) FROM market_research_fact_x_shop
UNION ALL SELECT 'fact_s_x_monthly_shop_mapping',     COUNT(*) FROM fact_s_x_monthly_shop_mapping;


-- ---------------------------------------------------------------------
-- LAYER 3: CONTENT, one table at a time.
-- For each table: (a) 5 sample rows, (b) categorical values, (c) ranges.
-- ---------------------------------------------------------------------

-- ===== 1. dim_s_shop =====
SELECT * FROM dim_s_shop ORDER BY shop_name LIMIT 5;
SELECT seller_type, status, shop_region, COUNT(*) FROM dim_s_shop GROUP BY 1, 2, 3 ORDER BY 1, 2, 3;
SELECT MIN(follower_count), MAX(follower_count), MIN(created_date), MAX(created_date) FROM dim_s_shop;

-- ===== 2. dim_s_product =====
SELECT * FROM dim_s_product ORDER BY product_name LIMIT 5;
SELECT category_lv1, category_lv2, COUNT(*) FROM dim_s_product GROUP BY 1, 2 ORDER BY 1, 2;
SELECT category_lv1, brand, COUNT(*) FROM dim_s_product GROUP BY 1, 2 ORDER BY 1, 2;   -- each brand in one category
SELECT status, COUNT(*) FROM dim_s_product GROUP BY 1;
SELECT MIN(current_price), MAX(current_price), MIN(created_date), MAX(last_updated_date) FROM dim_s_product;
SELECT COUNT(*) AS shops_with_many_lv1 FROM (SELECT s_shop_id FROM dim_s_product GROUP BY 1 HAVING COUNT(DISTINCT category_lv1) > 1) z;

-- ===== 3. fact_s_order =====
SELECT * FROM fact_s_order ORDER BY order_date LIMIT 5;
SELECT order_status, COUNT(*) FROM fact_s_order GROUP BY 1 ORDER BY 2 DESC;      -- 6 values per Appendix
SELECT buyer_region, COUNT(*) FROM fact_s_order GROUP BY 1;
SELECT order_month, COUNT(*) AS orders, SUM(gmv) AS gmv, SUM(nmv) AS nmv FROM fact_s_order GROUP BY 1 ORDER BY 1;
SELECT MIN(gmv), MAX(gmv), MIN(nmv), MAX(nmv), MIN(order_date), MAX(order_date) FROM fact_s_order;
SELECT COUNT(*) AS nmv_formula_violations FROM fact_s_order WHERE nmv <> gmv - discount_amount - shipping_fee;

-- ===== 4. fact_s_order_item =====
SELECT * FROM fact_s_order_item ORDER BY order_date LIMIT 5;
SELECT category_lv1, COUNT(*) AS items, SUM(item_gmv) AS gmv FROM fact_s_order_item GROUP BY 1 ORDER BY 1;
SELECT MIN(quantity), MAX(quantity), MIN(original_price), MAX(original_price), MIN(discounted_price), MAX(discounted_price) FROM fact_s_order_item;
SELECT COUNT(*) AS discounted_above_original FROM fact_s_order_item WHERE discounted_price > original_price;  -- expect 0
SELECT ROUND(AVG(items_per_order), 2) AS avg_items_per_order
FROM (SELECT order_id, COUNT(*) AS items_per_order FROM fact_s_order_item GROUP BY 1) z;

-- ===== 5. crawled_dim_x_shop =====
SELECT * FROM crawled_dim_x_shop ORDER BY shop_name LIMIT 5;
SELECT seller_type, shop_region, COUNT(*) FROM crawled_dim_x_shop GROUP BY 1, 2 ORDER BY 1, 2;
SELECT MIN(first_crawled_date), MAX(first_crawled_date), MIN(latest_crawled_date), MAX(latest_crawled_date) FROM crawled_dim_x_shop;

-- ===== 6. crawled_dim_x_product =====
SELECT * FROM crawled_dim_x_product ORDER BY product_name LIMIT 5;
SELECT category_lv1, category_lv2, COUNT(*) FROM crawled_dim_x_product GROUP BY 1, 2 ORDER BY 1, 2;
SELECT status, COUNT(*) FROM crawled_dim_x_product GROUP BY 1;
-- taxonomy aligned with S? expect 0
SELECT COUNT(*) AS x_cat_not_in_s FROM (
    SELECT DISTINCT category_lv1, category_lv2 FROM crawled_dim_x_product
    EXCEPT
    SELECT DISTINCT category_lv1, category_lv2 FROM dim_s_product) z;

-- ===== 7. crawled_fact_x_shop =====
SELECT * FROM crawled_fact_x_shop ORDER BY crawled_month, estimated_gmv DESC LIMIT 5;
SELECT crawled_month, COUNT(*) AS shops, SUM(estimated_gmv) AS est_gmv, SUM(estimated_order_count) AS est_orders FROM crawled_fact_x_shop GROUP BY 1 ORDER BY 1;
SELECT data_source, COUNT(*) FROM crawled_fact_x_shop GROUP BY 1;
SELECT MIN(rating_score), MAX(rating_score), MIN(follower_count), MAX(follower_count) FROM crawled_fact_x_shop;
-- which X shop-months are missing? (expect x_shop_005 in 2026-10)
SELECT d.shop_name, m.crawled_month
FROM crawled_dim_x_shop d
CROSS JOIN (SELECT DISTINCT crawled_month FROM crawled_fact_x_shop) m
LEFT JOIN crawled_fact_x_shop f ON f.x_shop_id = d.x_shop_id AND f.crawled_month = m.crawled_month
WHERE f.x_shop_id IS NULL
ORDER BY 1, 2;

-- ===== 8. market_research_fact_x_shop =====
SELECT * FROM market_research_fact_x_shop ORDER BY report_month, estimated_gmv DESC LIMIT 5;
SELECT report_month, COUNT(*) AS shops, SUM(estimated_gmv) AS est_gmv FROM market_research_fact_x_shop GROUP BY 1 ORDER BY 1;
SELECT data_source_name, shop_type, COUNT(*) FROM market_research_fact_x_shop GROUP BY 1, 2 ORDER BY 1, 2;
-- coverage vs crawler: how many shop-months exist in crawler but not in market research?
SELECT COUNT(*) AS crawler_only_shop_months
FROM crawled_fact_x_shop c
LEFT JOIN market_research_fact_x_shop m ON m.x_shop_id = c.x_shop_id AND m.report_month = c.crawled_month
WHERE m.x_shop_id IS NULL;

-- ===== 9. crawled_fact_x_product =====
SELECT * FROM crawled_fact_x_product ORDER BY crawled_month, estimated_gmv DESC LIMIT 5;
SELECT crawled_month, COUNT(*) AS products, SUM(estimated_gmv) AS est_gmv FROM crawled_fact_x_product GROUP BY 1 ORDER BY 1;
-- price sanity: min <= median <= max, expect 0 violations
SELECT COUNT(*) AS price_order_violations FROM crawled_fact_x_product WHERE NOT (min_price <= median_price AND median_price <= max_price);

-- ===== 10. fact_s_x_monthly_shop_mapping =====
SELECT * FROM fact_s_x_monthly_shop_mapping ORDER BY mapping_month, s_shop_id LIMIT 5;
SELECT mapping_month, COUNT(*) AS dual_shops FROM fact_s_x_monthly_shop_mapping GROUP BY 1 ORDER BY 1;
SELECT mapping_source, COUNT(*) FROM fact_s_x_monthly_shop_mapping GROUP BY 1 ORDER BY 2 DESC;
-- which S shops are dual in some months but not all? (expect s_shop_007)
SELECT s.shop_name, COUNT(DISTINCT m.mapping_month) AS months_mapped
FROM fact_s_x_monthly_shop_mapping m
JOIN dim_s_shop s USING (s_shop_id)
GROUP BY 1
HAVING COUNT(DISTINCT m.mapping_month) < (SELECT COUNT(DISTINCT mapping_month) FROM fact_s_x_monthly_shop_mapping)
ORDER BY 1;
-- S-only and X-only shop counts in the latest month
SELECT
    (SELECT COUNT(*) FROM dim_s_shop) AS s_shops_total,
    (SELECT COUNT(*) FROM fact_s_x_monthly_shop_mapping WHERE mapping_month = '2026-10') AS dual_in_oct,
    (SELECT COUNT(*) FROM dim_s_shop) - (SELECT COUNT(*) FROM fact_s_x_monthly_shop_mapping WHERE mapping_month = '2026-10') AS s_only_in_oct,
    (SELECT COUNT(*) FROM crawled_dim_x_shop) - (SELECT COUNT(*) FROM fact_s_x_monthly_shop_mapping WHERE mapping_month = '2026-10') AS x_only_in_oct;
