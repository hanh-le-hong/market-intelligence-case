# Q4. Detecting and reconciling crawler vs market research disagreement on X GMV

No code required. A short illustrative query is included at the end only to show the criteria are implementable.

## 1. What we are comparing

Two sources describe the same thing, X shop GMV per month:

| | `crawled_fact_x_shop` | `market_research_fact_x_shop` |
|---|---|---|
| How it is produced | Crawler reads public shop pages and infers GMV from "sold" counters and prices | Vendor model, aggregated, bought from a provider |
| Granularity | Shop-month, every shop the crawler reached | Shop-month, only shops the provider covers |
| Known weaknesses (Appendix A) | Estimated, not real; depends on crawl timing and page changes | Higher-level, more stable, possible lag vs real performance |
| Appendix status | Starred (primary) | Not starred (secondary) |

Neither is ground truth. The goal is not to find "the right number" but to decide, per shop-month, which number to use and how much to trust it.

## 2. Detection: criteria and rationale

Run every month on all shop-months, in this order. Each criterion produces a flag; a shop-month can carry several.

| # | Criterion | Rule | Rationale |
|---|---|---|---|
| C1 | **Coverage** | Shop-month exists in only one source → `single_source` (crawler-only or MR-only). Not a disagreement, cannot be reconciled. | You cannot compare what you do not have. Must be separated first or it pollutes the gap statistics. In the mock data 50 of 399 crawler rows have no MR row. |
| C2 | **Relative gap** | gap = \|MR − crawler\| / max(MR, crawler). < 10% `consistent`, 10–25% `watch`, ≥ 25% `conflict`. | Both sources are estimates. Crawler error from counter rounding and crawl timing is typically ~10%; vendor models carry similar error. Two 10% errors can combine to ~20%, so below 25% the gap is within noise. Using max() in the denominator keeps the gap symmetric (a 2x difference is 50% whichever side is bigger). |
| C3 | **Materiality floor** | Apply C2 only when max(MR, crawler) ≥ 500 USD/month; below that mark `immaterial`. | A 100-USD shop with a 60% gap is a 60-USD problem. Percent gaps on tiny shops are noisy and never change a business decision. The floor keeps the conflict list short and actionable. Threshold is tunable; 500 USD ≈ bottom of what the acquisition team would chase. |
| C4 | **Persistence** | Same shop in `conflict` for ≥ 2 consecutive months → `systematic`; otherwise `one_off`. | One bad month is usually a crawl hiccup (page changed, campaign counter reset). Repeated conflict means one source is structurally wrong for that shop (wrong shop mapped, vendor model mis-specified). The fix is different, so the flag must be different. |
| C5 | **Direction / global bias** | Each month compute mean and spread of (MR − crawler)/crawler across all consistent shops. If mean bias drifts beyond ±5% or spread widens sharply month over month → `source_drift`. | If every shop moves the same way, the shops did not change; a source did (crawler broke, vendor re-trained its model). This is detected at population level, not per shop. In the mock data mean bias is +1.7%, spread 12.6%, i.e. healthy. |
| C6 | **Internal plausibility** | Per source, per shop-month: implied ABS = gmv / orders must fall inside the shop's category price band; orders = 0 with gmv > 0; GMV jump > 3x vs the same source's previous month. Any hit → `implausible_<source>`. | A disagreement tells you *that* the sources differ, not *which* is wrong. Internal checks give a verdict on each source alone. A crawler row with 0 orders and positive GMV is broken regardless of what MR says. |
| C7 | **Third reference for dual shops** | For dual shops, compare both X numbers with the S side of the same seller (S GMV, S ABS, S order count). The source whose ABS and order profile is closer to S is more credible. | Same seller, same products, same price points. S data is real transactions, so it anchors the plausible range for X. Only available for ~60% of shops here, but those are the shops the business team cares about. |

Why this order: C1 removes the incomparable, C3 removes the irrelevant, C2 scores the rest, C4–C7 explain the score. Skipping C1 and C3 and going straight to a percent threshold is the common mistake: the list fills with tiny shops and missing rows and nobody reads it.

## 3. Reconciliation: which number to use

Never average blindly. Averaging two estimates, one of which is broken, produces a third number that is wrong and looks reasonable. Instead, pick a source per shop-month with an explicit rule and record the choice.

| Situation (from the flags) | Use | Confidence | Why |
|---|---|---|---|
| `consistent` | Crawler | High | Both agree; crawler is more granular (products, monthly cadence, shop attributes) and is the starred source |
| `watch` | Crawler, keep MR for reference | Medium | Inside combined noise; do not treat the gap as a finding |
| `conflict` + `implausible_crawler` | MR | Medium | Crawler row is internally broken for that month |
| `conflict` + `implausible_mr` | Crawler | Medium | Vendor model is off for that shop |
| `conflict` + MR ≈ crawler of the previous month | Crawler | Medium | Classic vendor lag (Appendix: "possible lag vs real performance"). MR is describing last month |
| `conflict`, both plausible, dual shop | Source closer to S profile (C7) | Medium | Triangulate with real data |
| `conflict`, both plausible, non-dual, `one_off` | Crawler, flag row | Low | Default to primary source but mark it; exclude from top-N rankings that month |
| `conflict` + `systematic` | **Neither; escalate** | None | Likely a mapping error (wrong X shop) or a dead listing. Send to the mapping / crawler owner; keep the shop out of comparative views until resolved |
| `single_source` | The one available | Low | State clearly in output that it is unverified |

Output of reconciliation is a table at shop-month grain:
`x_shop_id, month, crawler_gmv, mr_gmv, gap_pct, flags, gmv_final, source_used, confidence`.
Downstream queries (Q3 and any dashboard) read `gmv_final` and `confidence`, never the raw sources directly. This makes every number traceable to a rule.

## 4. Operating it

- **Cadence**: run the detection the day after both sources land each month. Review only `conflict` and `source_drift`; `watch` is logged, not reviewed.
- **Thresholds are parameters, not constants**: start with 10 / 25% and 500 USD, then calibrate on 3–6 months of history: if more than ~5% of material shop-months land in `conflict`, the bar is too tight for these sources; if `systematic` cases are never caught, it is too loose.
- **Feedback loop**: every resolved `systematic` case should produce a fix upstream (mapping corrected, crawler selector repaired, vendor queried), otherwise the same shop returns next month.
- **Reporting rule**: any S-vs-X comparison shown to the business carries the confidence column. A `low` row is shown greyed or with a footnote; a `none` row is excluded.

## 5. Illustration on the mock data

Applying C1–C3 to the 399 crawler shop-months:

| status | shop-months |
|---|---|
| consistent | 339 |
| watch | 7 |
| conflict | 3 |
| crawler only | 50 |

The 3 conflicts are all in 2026-09 with MR = 2.2x crawler (Energizer Flagship, Walfos Flagship, House Home Appliances VN). None of the three persists into 2026-10, so they are `one_off`; under the rules above they default to crawler and are flagged low confidence for September. Mean bias across consistent rows is +1.7% with 12.6% spread, so there is no global drift.

Illustrative detection query (C1–C3 only):

```sql
WITH both_src AS (
    SELECT COALESCE(c.x_shop_id, m.x_shop_id)        AS x_shop_id,
           COALESCE(c.crawled_month, m.report_month) AS month,
           c.estimated_gmv                            AS crawler_gmv,
           m.estimated_gmv                            AS mr_gmv
    FROM crawled_fact_x_shop c
    FULL JOIN market_research_fact_x_shop m
        ON m.x_shop_id = c.x_shop_id AND m.report_month = c.crawled_month
)
SELECT x_shop_id, month, crawler_gmv, mr_gmv,
       ROUND(ABS(mr_gmv - crawler_gmv)::numeric / NULLIF(GREATEST(mr_gmv, crawler_gmv), 0), 3) AS gap_pct,
       CASE
           WHEN crawler_gmv IS NULL OR mr_gmv IS NULL                          THEN 'single_source'
           WHEN GREATEST(mr_gmv, crawler_gmv) < 500                            THEN 'immaterial'
           WHEN ABS(mr_gmv - crawler_gmv)::numeric / GREATEST(mr_gmv, crawler_gmv) < 0.10 THEN 'consistent'
           WHEN ABS(mr_gmv - crawler_gmv)::numeric / GREATEST(mr_gmv, crawler_gmv) < 0.25 THEN 'watch'
           ELSE 'conflict'
       END AS status
FROM both_src;
```
