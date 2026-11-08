-- =====================================================================
-- Q3: Extend Q2 with X shop performance (crawled_fact_x_shop) for each
--     dual S shop. Report ADG, ADO, ABS, ABS tier for the X side.
-- Dialect: PostgreSQL
-- =====================================================================
-- ASSUMPTIONS (in addition to Q2 A1-A8)
-- B1. The X row is matched on x_shop_id (from the monthly mapping) AND
--     crawled_month = order_month, so S and X are compared in the same month.
-- B2. LEFT JOIN: a dual S shop stays in the top-20 list even when the
--     crawler has no row for that X shop in that month. X metrics are NULL
--     and x_abs_tier = 'no X data'. Dropping the shop would silently change
--     the top-20 list and hide a data gap.
-- B3. X metrics use estimated_gmv and estimated_order_count. These are
--     crawler estimates, not transactions. Small S-vs-X gaps (< ~10-15%)
--     should not be read as real differences.
-- B4. ADG, ADO, ABS and tier boundaries for X use exactly the same
--     formulas and thresholds as for S (Q2 A4-A6), so the two sides are
--     comparable column by column.
-- B5. gmv_ratio_x_vs_s = x_gmv / s_gmv. > 1 means the seller sells more on
--     X than on S that month. Reported as a convenience for the business
--     team; it is not required by the question.
-- =====================================================================
-- OUTPUT TEMPLATE (one row = one dual S shop in one month, 60 rows)
-- order_month | rank_in_month | s_shop_id | shop_name | seller_type | x_shop_id | x_shop_name
-- | days_in_month
-- | s_gmv | s_order_count | s_adg | s_ado | s_abs | s_abs_tier
-- | x_gmv | x_order_count | x_adg | x_ado | x_abs | x_abs_tier
-- | gmv_ratio_x_vs_s
-- =====================================================================

WITH shop_month AS (
    -- Layer 1 (same as Q2): S performance per (shop, month), dual shops only
    SELECT
        o.order_month,
        o.s_shop_id,
        m.x_shop_id,
        SUM(o.gmv)   AS s_gmv,
        COUNT(*)     AS s_order_count
    FROM fact_s_order AS o
    JOIN fact_s_x_monthly_shop_mapping AS m
        ON  m.s_shop_id     = o.s_shop_id
        AND m.mapping_month = o.order_month
    WHERE o.order_status = 'complete'
      AND o.order_month IN ('2026-08', '2026-09', '2026-10')
    GROUP BY o.order_month, o.s_shop_id, m.x_shop_id
),
ranked AS (
    -- Layer 2 (same as Q2): rank S shops within month, keep top 20
    SELECT
        sm.*,
        EXTRACT(DAY FROM (TO_DATE(sm.order_month || '-01', 'YYYY-MM-DD')
                          + INTERVAL '1 month' - INTERVAL '1 day'))::int AS days_in_month,
        ROW_NUMBER() OVER (PARTITION BY sm.order_month ORDER BY sm.s_gmv DESC) AS rank_in_month
    FROM shop_month AS sm
),
top20 AS (
    SELECT * FROM ranked WHERE rank_in_month <= 20
),
joined AS (
    -- Layer 3 (new in Q3): attach X performance for the same shop-month
    SELECT
        t.*,
        x.estimated_gmv          AS x_gmv,
        x.estimated_order_count  AS x_order_count
    FROM top20 AS t
    LEFT JOIN crawled_fact_x_shop AS x
        ON  x.x_shop_id     = t.x_shop_id
        AND x.crawled_month = t.order_month
)
SELECT
    j.order_month,
    j.rank_in_month,
    j.s_shop_id,
    s.shop_name,
    s.seller_type,
    j.x_shop_id,
    xd.shop_name                                                  AS x_shop_name,
    j.days_in_month,
    -- S side
    j.s_gmv,
    j.s_order_count,
    ROUND(j.s_gmv::numeric         / j.days_in_month, 2)         AS s_adg,
    ROUND(j.s_order_count::numeric / j.days_in_month, 2)         AS s_ado,
    ROUND(j.s_gmv::numeric         / j.s_order_count, 2)         AS s_abs,
    CASE
        WHEN j.s_gmv::numeric / j.s_order_count < 5  THEN 'under 5 USD'
        WHEN j.s_gmv::numeric / j.s_order_count < 10 THEN '5 - 10 USD'
        WHEN j.s_gmv::numeric / j.s_order_count < 50 THEN '10 - 50 USD'
        ELSE                                               'over 50 USD'
    END                                                           AS s_abs_tier,
    -- X side (NULL when the crawler has no row for that month)
    j.x_gmv,
    j.x_order_count,
    ROUND(j.x_gmv::numeric         / j.days_in_month, 2)         AS x_adg,
    ROUND(j.x_order_count::numeric / j.days_in_month, 2)         AS x_ado,
    ROUND(j.x_gmv::numeric / NULLIF(j.x_order_count, 0), 2)      AS x_abs,
    CASE
        WHEN j.x_gmv IS NULL OR j.x_order_count IS NULL OR j.x_order_count = 0 THEN 'no X data'
        WHEN j.x_gmv::numeric / j.x_order_count < 5  THEN 'under 5 USD'
        WHEN j.x_gmv::numeric / j.x_order_count < 10 THEN '5 - 10 USD'
        WHEN j.x_gmv::numeric / j.x_order_count < 50 THEN '10 - 50 USD'
        ELSE                                               'over 50 USD'
    END                                                           AS x_abs_tier,
    -- comparison helper
    ROUND(j.x_gmv::numeric / NULLIF(j.s_gmv, 0), 2)              AS gmv_ratio_x_vs_s
FROM joined AS j
JOIN dim_s_shop AS s
    ON s.s_shop_id = j.s_shop_id
LEFT JOIN crawled_dim_x_shop AS xd
    ON xd.x_shop_id = j.x_shop_id
ORDER BY j.order_month, j.rank_in_month;

-- ---------------------------------------------------------------------
-- SANITY CHECKS
-- C1. Still 60 rows (LEFT JOIN must not add or drop rows).
-- C2. Every row has exactly one x_shop_id (mapping is 1:1 per month).
-- C3. x_shop_005 in 2026-10 should show NULL X metrics and 'no X data'
--     if it is in the top 20 that month (crawler gap).
-- C4. s_abs_tier here equals abs_tier from Q2 for the same shop-month.
-- NOTE: NULLIF(x, 0) avoids division by zero; NULL / n stays NULL, so a
--       missing X row never raises an error.
