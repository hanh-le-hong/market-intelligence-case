-- =====================================================================
-- Q2: Top 20 dual shops in S (by GMV) each month, last 3 months,
--     with ADG, ADO, ABS and ABS tier.
-- Dialect: PostgreSQL
-- =====================================================================
-- ASSUMPTIONS
-- A1. Last 3 months = 2026-08, 2026-09, 2026-10 (latest 3 months in data).
-- A2. GMV and order count are taken from fact_s_order (one row per order),
--     order_status = 'complete' only, same rule as Q1.
-- A3. Dual shop = the S shop has a row in fact_s_x_monthly_shop_mapping
--     for THAT month. Mapping is monthly, so dual status is evaluated
--     per month (a shop can be dual in Sep and not in Aug).
-- A4. ADG = monthly GMV / number of calendar days in that month.
--     ADO = monthly order count / number of calendar days in that month.
--     Days are taken from the calendar (31, 30, 31), not from days with sales.
-- A5. ABS = monthly GMV / monthly order count (per Appendix definition).
-- A6. ABS tier boundaries, lower bound inclusive, upper bound exclusive:
--     under 5: ABS < 5 | 5-10: 5 <= ABS < 10 | 10-50: 10 <= ABS < 50 | over 50: ABS >= 50
-- A7. Ranking by GMV uses ROW_NUMBER: exactly 20 rows per month.
-- A8. Shop details (shop_name, seller_type) from dim_s_shop. x_shop_id is
--     carried from the mapping so Q3 can join X performance directly.
-- =====================================================================
-- OUTPUT TEMPLATE (one row = one dual S shop in one month, 60 rows)
-- order_month | rank_in_month | s_shop_id | shop_name | seller_type
-- | x_shop_id | days_in_month | gmv | order_count | adg | ado | abs | abs_tier
-- =====================================================================

WITH shop_month AS (
    -- Layer 1: S performance per (shop, month), dual shops only
    SELECT
        o.order_month,
        o.s_shop_id,
        m.x_shop_id,
        SUM(o.gmv)   AS gmv,
        COUNT(*)     AS order_count          -- one row per order in fact_s_order
    FROM fact_s_order AS o
    JOIN fact_s_x_monthly_shop_mapping AS m
        ON  m.s_shop_id     = o.s_shop_id
        AND m.mapping_month = o.order_month  -- dual status is per month
    WHERE o.order_status = 'complete'
      AND o.order_month IN ('2026-08', '2026-09', '2026-10')
    GROUP BY o.order_month, o.s_shop_id, m.x_shop_id
),
metrics AS (
    -- Layer 2: derived metrics
    SELECT
        sm.*,
        EXTRACT(DAY FROM (TO_DATE(sm.order_month || '-01', 'YYYY-MM-DD')
                          + INTERVAL '1 month' - INTERVAL '1 day'))::int AS days_in_month,
        ROUND(sm.gmv::numeric / sm.order_count, 2)                      AS abs
    FROM shop_month AS sm
),
ranked AS (
    -- Layer 3: rank within month by GMV
    SELECT
        mt.*,
        ROW_NUMBER() OVER (PARTITION BY mt.order_month ORDER BY mt.gmv DESC) AS rank_in_month
    FROM metrics AS mt
)
SELECT
    r.order_month,
    r.rank_in_month,
    r.s_shop_id,
    s.shop_name,
    s.seller_type,
    r.x_shop_id,
    r.days_in_month,
    r.gmv,
    r.order_count,
    ROUND(r.gmv::numeric         / r.days_in_month, 2) AS adg,
    ROUND(r.order_count::numeric / r.days_in_month, 2) AS ado,
    r.abs,
    CASE
        WHEN r.abs < 5  THEN 'under 5 USD'
        WHEN r.abs < 10 THEN '5 - 10 USD'
        WHEN r.abs < 50 THEN '10 - 50 USD'
        ELSE                 'over 50 USD'
    END AS abs_tier
FROM ranked AS r
JOIN dim_s_shop AS s
    ON s.s_shop_id = r.s_shop_id
WHERE r.rank_in_month <= 20
ORDER BY r.order_month, r.rank_in_month;

-- ---------------------------------------------------------------------
-- SANITY CHECKS
-- C1. 20 rows per month, 60 total.
-- C2. days_in_month = 31 / 30 / 31 for Aug / Sep / Oct.
-- C3. abs * order_count ≈ gmv for any row.
-- C4. Shop s_shop_007 must not appear in 2026-08 even if its GMV is high
--     (not dual that month).
-- NOTE: SQL Server equivalent for days_in_month:
--   DAY(EOMONTH(CAST(order_month + '-01' AS date)))
