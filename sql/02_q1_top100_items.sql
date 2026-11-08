-- =====================================================================
-- Q1: Top 100 selling items each month (by GMV), company S, last 3 months
-- Dialect: PostgreSQL
-- =====================================================================
-- ASSUMPTIONS
-- A1. Last 3 months = the 3 latest months present in fact_s_order_item
--     (2026-08, 2026-09, 2026-10). Hard-coded here.
-- A2. "Selling" = order_status = 'complete' only (delivered, not returned).
--     created, paid, on_delivery are not final; canceled and returned are
--     not sales. This also matches X data, whose estimated GMV cannot
--     include canceled orders.
-- A3. GMV = SUM(item_gmv). Per Appendix A, GMV is before discount
--     deduction, and item_gmv already carries that definition.
-- A4. average selling price = quantity-weighted average of
--     discounted_price (actual paid unit price), not current_price
--     (listing price). min/max price = MIN/MAX of discounted_price.
-- A5. order_count = COUNT(DISTINCT order_id), because one order can
--     contain the same product on more than one item row.
-- A6. Item = s_product_id. Item details taken from dim_s_product:
--     product_name, brand, category_lv1, category_lv2.
-- A7. Ranking uses ROW_NUMBER, so exactly 100 rows per month.
--     Ties at rank 100 are broken arbitrarily.
-- =====================================================================
-- OUTPUT TEMPLATE (one row = one product in one month, max 300 rows)
-- order_month | rank_in_month | s_product_id | product_name | brand
-- | category_lv1 | category_lv2 | avg_price | min_price | max_price
-- | gmv | order_count
-- =====================================================================


-- ---------------------------------------------------------------------
-- STEP 1: filter and aggregate per (month, product). No dim join, no rank.
-- ---------------------------------------------------------------------
SELECT
    i.order_month,
    i.s_product_id,
    SUM(i.item_gmv)                                                           AS gmv,
    COUNT(DISTINCT i.order_id)                                                AS order_count,
    ROUND(SUM(i.discounted_price * i.quantity)::numeric / SUM(i.quantity), 2) AS avg_price,
    MIN(i.discounted_price)                                                   AS min_price,
    MAX(i.discounted_price)                                                   AS max_price
FROM fact_s_order_item AS i
JOIN fact_s_order AS o
    ON o.order_id = i.order_id
WHERE o.order_status = 'complete'
  AND i.order_month IN ('2026-08', '2026-09', '2026-10')
GROUP BY i.order_month, i.s_product_id
ORDER BY i.order_month, gmv DESC;


-- ---------------------------------------------------------------------
-- STEP 2: add product details from dim_s_product.
-- New: one more JOIN, four more columns in SELECT and in GROUP BY.
-- Row count must stay the same as STEP 1 (dim has one row per product).
-- ---------------------------------------------------------------------
SELECT
    i.order_month,
    i.s_product_id,
    p.product_name,
    p.brand,
    p.category_lv1,
    p.category_lv2,
    SUM(i.item_gmv)                                                           AS gmv,
    COUNT(DISTINCT i.order_id)                                                AS order_count,
    ROUND(SUM(i.discounted_price * i.quantity)::numeric / SUM(i.quantity), 2) AS avg_price,
    MIN(i.discounted_price)                                                   AS min_price,
    MAX(i.discounted_price)                                                   AS max_price
FROM fact_s_order_item AS i
JOIN fact_s_order AS o
    ON o.order_id = i.order_id
JOIN dim_s_product AS p
    ON p.s_product_id = i.s_product_id
WHERE o.order_status = 'complete'
  AND i.order_month IN ('2026-08', '2026-09', '2026-10')
GROUP BY i.order_month, i.s_product_id,
         p.product_name, p.brand, p.category_lv1, p.category_lv2
ORDER BY i.order_month, gmv DESC;


-- ---------------------------------------------------------------------
-- STEP 3: same result as STEP 2, rewritten as a CTE.
-- A CTE (WITH ... AS) names an intermediate result so the next step can
-- read from it like a table. Nothing changes in the numbers.
-- ---------------------------------------------------------------------
WITH item_month AS (
    SELECT
        i.order_month,
        i.s_product_id,
        p.product_name,
        p.brand,
        p.category_lv1,
        p.category_lv2,
        SUM(i.item_gmv)                                                           AS gmv,
        COUNT(DISTINCT i.order_id)                                                AS order_count,
        ROUND(SUM(i.discounted_price * i.quantity)::numeric / SUM(i.quantity), 2) AS avg_price,
        MIN(i.discounted_price)                                                   AS min_price,
        MAX(i.discounted_price)                                                   AS max_price
    FROM fact_s_order_item AS i
    JOIN fact_s_order AS o
        ON o.order_id = i.order_id
    JOIN dim_s_product AS p
        ON p.s_product_id = i.s_product_id
    WHERE o.order_status = 'complete'
      AND i.order_month IN ('2026-08', '2026-09', '2026-10')
    GROUP BY i.order_month, i.s_product_id,
             p.product_name, p.brand, p.category_lv1, p.category_lv2
)
SELECT *
FROM item_month
ORDER BY order_month, gmv DESC;


-- ---------------------------------------------------------------------
-- STEP 4 (FINAL): rank within each month and keep the top 100.
-- ROW_NUMBER() OVER (PARTITION BY order_month ORDER BY gmv DESC)
--   PARTITION BY = restart numbering for every month
--   ORDER BY     = 1 goes to the highest GMV
-- The rank is computed in a second CTE because a window function
-- cannot be used directly inside WHERE.
-- ---------------------------------------------------------------------
WITH item_month AS (
    SELECT
        i.order_month,
        i.s_product_id,
        p.product_name,
        p.brand,
        p.category_lv1,
        p.category_lv2,
        SUM(i.item_gmv)                                                           AS gmv,
        COUNT(DISTINCT i.order_id)                                                AS order_count,
        ROUND(SUM(i.discounted_price * i.quantity)::numeric / SUM(i.quantity), 2) AS avg_price,
        MIN(i.discounted_price)                                                   AS min_price,
        MAX(i.discounted_price)                                                   AS max_price
    FROM fact_s_order_item AS i
    JOIN fact_s_order AS o
        ON o.order_id = i.order_id
    JOIN dim_s_product AS p
        ON p.s_product_id = i.s_product_id
    WHERE o.order_status = 'complete'
      AND i.order_month IN ('2026-08', '2026-09', '2026-10')
    GROUP BY i.order_month, i.s_product_id,
             p.product_name, p.brand, p.category_lv1, p.category_lv2
),
ranked AS (
    SELECT
        *,
        ROW_NUMBER() OVER (PARTITION BY order_month ORDER BY gmv DESC) AS rank_in_month
    FROM item_month
)
SELECT
    order_month,
    rank_in_month,
    s_product_id,
    product_name,
    brand,
    category_lv1,
    category_lv2,
    avg_price,
    min_price,
    max_price,
    gmv,
    order_count
FROM ranked
WHERE rank_in_month <= 100
ORDER BY order_month, rank_in_month;


-- ---------------------------------------------------------------------
-- SANITY CHECKS on the final result
-- ---------------------------------------------------------------------
-- C1. Exactly 100 rows per month?
-- C2. rank 1 of each month has the highest gmv in that month?
-- Wrap the final query in a CTE and count:
--   SELECT order_month, COUNT(*), MAX(rank_in_month) FROM final GROUP BY 1;

-- NOTE: dynamic "last 3 months" instead of hard-coding
--   AND i.order_month IN (
--       SELECT DISTINCT order_month FROM fact_s_order_item
--       ORDER BY order_month DESC LIMIT 3
--   )
-- SQL Server equivalent: SELECT DISTINCT TOP 3 order_month ... ORDER BY order_month DESC
