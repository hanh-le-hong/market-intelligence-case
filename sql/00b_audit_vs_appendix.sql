-- =====================================================================
-- 00_audit_mock_vs_appendix.sql
-- Audit: does the mock data respect every assumption in Appendix A?
-- Run on database case_s_x. Every "violations" value should be 0.
-- =====================================================================

-- ---------- Part 1: one row per assumption, violations must be 0 ----------
SELECT 'A1 fact_s_order: one row per order'              AS check_name,
       COUNT(*) - COUNT(DISTINCT order_id)                AS violations
FROM fact_s_order
UNION ALL
SELECT 'A2 NMV = GMV - discount - shipping fee',
       COUNT(*)
FROM fact_s_order
WHERE nmv <> gmv - discount_amount - shipping_fee
UNION ALL
SELECT 'A3 order_month derived from order_date (fact_s_order)',
       COUNT(*)
FROM fact_s_order
WHERE order_month <> TO_CHAR(order_date, 'YYYY-MM')
UNION ALL
SELECT 'A3 order_month derived from order_date (fact_s_order_item)',
       COUNT(*)
FROM fact_s_order_item
WHERE order_month <> TO_CHAR(order_date, 'YYYY-MM')
UNION ALL
SELECT 'A4 order gmv = sum of item_gmv',
       COUNT(*)
FROM fact_s_order o
JOIN (SELECT order_id, SUM(item_gmv) AS item_sum
      FROM fact_s_order_item GROUP BY order_id) i USING (order_id)
WHERE o.gmv <> i.item_sum
UNION ALL
SELECT 'A5 item s_shop_id (redundant) = order s_shop_id',
       COUNT(*)
FROM fact_s_order_item i
JOIN fact_s_order o USING (order_id)
WHERE i.s_shop_id <> o.s_shop_id
UNION ALL
SELECT 'A6 item_gmv = quantity * original_price (GMV before discount)',
       COUNT(*)
FROM fact_s_order_item
WHERE item_gmv <> quantity * original_price
UNION ALL
SELECT 'A7 mapping one-to-one per month: S -> X',
       COUNT(*)
FROM (SELECT mapping_month, s_shop_id
      FROM fact_s_x_monthly_shop_mapping
      GROUP BY 1, 2 HAVING COUNT(*) > 1) z
UNION ALL
SELECT 'A7 mapping one-to-one per month: X -> S',
       COUNT(*)
FROM (SELECT mapping_month, x_shop_id
      FROM fact_s_x_monthly_shop_mapping
      GROUP BY 1, 2 HAVING COUNT(*) > 1) z
UNION ALL
SELECT 'A8 all month columns are YYYY-MM',
       (SELECT COUNT(*) FROM fact_s_order                  WHERE order_month   !~ '^\d{4}-\d{2}$')
     + (SELECT COUNT(*) FROM crawled_fact_x_shop           WHERE crawled_month !~ '^\d{4}-\d{2}$')
     + (SELECT COUNT(*) FROM market_research_fact_x_shop   WHERE report_month  !~ '^\d{4}-\d{2}$')
     + (SELECT COUNT(*) FROM fact_s_x_monthly_shop_mapping WHERE mapping_month !~ '^\d{4}-\d{2}$')
UNION ALL
SELECT 'A9 X categories aligned with S taxonomy',
       COUNT(*)
FROM (SELECT DISTINCT category_lv1, category_lv2 FROM crawled_dim_x_product
      EXCEPT
      SELECT DISTINCT category_lv1, category_lv2 FROM dim_s_product) z
UNION ALL
SELECT 'A10 crawled_fact_x_shop: one row per (x_shop_id, crawled_month)',
       COUNT(*)
FROM (SELECT x_shop_id, crawled_month
      FROM crawled_fact_x_shop
      GROUP BY 1, 2 HAVING COUNT(*) > 1) z
UNION ALL
SELECT 'A11 mapping references existing S shops',
       COUNT(*)
FROM fact_s_x_monthly_shop_mapping m
LEFT JOIN dim_s_shop s USING (s_shop_id)
WHERE s.s_shop_id IS NULL
UNION ALL
SELECT 'A12 mapping references existing X shops',
       COUNT(*)
FROM fact_s_x_monthly_shop_mapping m
LEFT JOIN crawled_dim_x_shop x USING (x_shop_id)
WHERE x.x_shop_id IS NULL;

-- ---------- Part 2: value inventories (eyeball against the appendix) ----------

-- order_status must be within: created, paid, on_delivery, complete, canceled, returned
SELECT order_status, COUNT(*) AS order_count
FROM fact_s_order
GROUP BY order_status
ORDER BY order_count DESC;

-- seller_type on both sides
SELECT 'S' AS side, seller_type, COUNT(*) AS shops FROM dim_s_shop GROUP BY 1, 2
UNION ALL
SELECT 'X', seller_type, COUNT(*) FROM crawled_dim_x_shop GROUP BY 1, 2
ORDER BY 1, 2;

-- month coverage per table
SELECT 'fact_s_order' AS tbl, MIN(order_month) AS first_month, MAX(order_month) AS last_month, COUNT(DISTINCT order_month) AS n_months FROM fact_s_order
UNION ALL
SELECT 'crawled_fact_x_shop', MIN(crawled_month), MAX(crawled_month), COUNT(DISTINCT crawled_month) FROM crawled_fact_x_shop
UNION ALL
SELECT 'market_research_fact_x_shop', MIN(report_month), MAX(report_month), COUNT(DISTINCT report_month) FROM market_research_fact_x_shop
UNION ALL
SELECT 'fact_s_x_monthly_shop_mapping', MIN(mapping_month), MAX(mapping_month), COUNT(DISTINCT mapping_month) FROM fact_s_x_monthly_shop_mapping;

-- ---------- Part 3: added after per-table audit ----------
-- A13. NMV must not be negative (shipping fee cannot exceed GMV after discount)
SELECT 'A13 NMV >= 0' AS check_name, COUNT(*) AS violations FROM fact_s_order WHERE nmv < 0;
-- A14. discounted_price never above original_price
SELECT 'A14 discounted_price <= original_price' AS check_name, COUNT(*) AS violations FROM fact_s_order_item WHERE discounted_price > original_price;
-- A15. Mall shops are either single-brand (name = '<brand> Official Store',
--      every product carries that brand) or multi-brand retailers (>= 5 brands,
--      e.g. Phong Vũ, ShopDunk). A Mall shop with 2-4 brands is a data error.
SELECT 'A15 Mall shop brand consistency' AS check_name, COUNT(*) AS violations
FROM (SELECT p.s_shop_id, COUNT(DISTINCT p.brand) AS n_brands
      FROM dim_s_product p JOIN dim_s_shop s USING (s_shop_id)
      WHERE s.seller_type = 'Mall' GROUP BY 1 HAVING COUNT(DISTINCT p.brand) BETWEEN 2 AND 4) z;
-- A16. product category_lv2 belongs to its category_lv1 (no lv2 under two lv1)
SELECT 'A16 lv2 under one lv1' AS check_name, COUNT(*) AS violations
FROM (SELECT category_lv2 FROM dim_s_product GROUP BY 1 HAVING COUNT(DISTINCT category_lv1) > 2) z;
