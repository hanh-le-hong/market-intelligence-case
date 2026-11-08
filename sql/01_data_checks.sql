-- =====================================================================
-- 01_data_checks.sql
-- Basic data checks before analysis. Run on database case_s_x.
-- =====================================================================

-- CHECK 1: which months exist, orders and GMV per month
SELECT order_month, COUNT(*) AS order_count, SUM(gmv) AS total_gmv
FROM fact_s_order
GROUP BY order_month
ORDER BY order_month;

-- CHECK 2: which order_status values exist, orders per status
SELECT order_status, COUNT(*) AS order_count
FROM fact_s_order
GROUP BY order_status
ORDER BY order_count DESC;

-- CHECK 3: is (x_shop_id, crawled_month) unique in crawled_fact_x_shop? (expect 0 rows)
SELECT x_shop_id, crawled_month, COUNT(*) AS row_count
FROM crawled_fact_x_shop
GROUP BY x_shop_id, crawled_month
HAVING COUNT(*) > 1;

-- CHECK 4: does any S shop map to more than one X shop in the same month? (expect 0 rows)
SELECT mapping_month, s_shop_id, COUNT(*) AS x_shop_count
FROM fact_s_x_monthly_shop_mapping
GROUP BY mapping_month, s_shop_id
HAVING COUNT(*) > 1;

-- CHECK 5: number of dual shops per month
SELECT mapping_month, COUNT(*) AS dual_shop_count
FROM fact_s_x_monthly_shop_mapping
GROUP BY mapping_month
ORDER BY mapping_month;
