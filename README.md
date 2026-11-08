# Case study: Company S vs Company X (Market Intelligence)

Take-home test for a Senior Market Intelligence Analyst role. Company S is the internal platform; company X is a competitor known only through crawled and market-research data. The task: build a comparative view of S and X to support seller acquisition.

**Submission PDF:** `submission/Case_S_vs_X_Answers_LeHongHanh.pdf`

| Part | Question | Deliverable |
|---|---|---|
| A1 | Top 100 selling items per month (by GMV) for S, with price stats and order count | `sql/02_q1_top100_items.sql`, `results/q1_result.csv` (300 rows) |
| A2 | Top 20 dual shops per month with ADG, ADO, ABS, ABS tier | `sql/03_q2_top20_dual_shops.sql`, `results/q2_result.csv` (60 rows) |
| A3 | A2 extended with X shop performance from crawled data | `sql/04_q3_s_vs_x_performance.sql`, `results/q3_result.csv` (60 rows) |
| A4 | Strategy to detect and reconcile crawler vs market-research disagreement (no code) | `q4_reconciliation/q4_crawler_vs_market_research.md`, [Google Doc](https://docs.google.com/document/d/1weGjmNjq-L1TKyGHXxeGyTWV5MOia0XOcUD4bwYUfFU) |
| B | Projection model for X: GMV, orders, P&L (Appendix B structure) | [Google Sheet, 9 tabs](https://docs.google.com/spreadsheets/d/1LgIXNfAwEwsVd1FwZXyYwN49rmuzRnWOJmo0zYuTAfQ) |

## Approach

The test provides a schema and a data dictionary (Appendix A) but no data. To write and test real queries I:

1. **Built a mock PostgreSQL database** that follows the schema and Appendix A exactly: 10 tables, 100 S shops, 100 X shops, 60 dual pairs, 13 category lv1 / 98 lv2, 2,500 products, 37,479 orders, 56,219 order items, months 2026-07 to 2026-10. Values in USD. Shop and brand names follow the Vietnamese ecommerce landscape (Mall brand stores, multi-brand retailers, non-mall shops).
2. **Planted edge cases** so the queries are tested against them: a shop that becomes dual only from September (mapping is monthly), an X shop with no crawl in October, three shop-months where crawler and market research disagree by more than 2x, a banned shop and an inactive shop, four months of data so "last 3 months" has to be filtered.
3. **Audited the mock data against Appendix A** before writing any answer (`sql/00b_audit_vs_appendix.sql`, 18 checks: one row per order, NMV = GMV - discount - shipping, order GMV = sum of item GMV, mapping is 1:1 per month, item shop = order shop, and so on).
4. **Wrote each answer as a layered query** (filter and aggregate, then derive, then rank, then present) with assumptions, output template and sanity checks in the file header.

## Repository layout

```
market-intelligence-case/
├── README.md
├── submission/
│   ├── Case_S_vs_X_Answers_LeHongHanh.pdf    # the submitted answers
│   └── answers.html                          # source of the PDF
├── sql/
│   ├── 00_mock_database.sql.gz               # CREATE TABLE + INSERT for the mock database (gunzip first)
│   ├── 00a_table_audit.sql                   # structure, row counts, per-table content checks
│   ├── 00b_audit_vs_appendix.sql             # 18 checks of the mock data against Appendix A
│   ├── 01_data_checks.sql                    # months, statuses, uniqueness, dual count per month
│   ├── 02_q1_top100_items.sql                # A1, built in 4 steps; STEP 4 is the final query
│   ├── 03_q2_top20_dual_shops.sql            # A2
│   └── 04_q3_s_vs_x_performance.sql          # A3
├── results/
│   ├── q1_result.csv
│   ├── q2_result.csv
│   └── q3_result.csv
├── q4_reconciliation/
│   └── q4_crawler_vs_market_research.md      # A4, criteria + reconciliation rules + illustrative query
└── q5_projection_model/
    └── README.md                             # what is in the Google Sheet and how to use it
```

## Reproduce

Requires Docker.

```bash
docker run --name postgres-lab -e POSTGRES_PASSWORD=postgres -p 5432:5432 -d postgres:17
docker exec -it postgres-lab psql -U postgres -c "CREATE DATABASE case_s_x;"
gunzip -k sql/00_mock_database.sql.gz
docker exec -i postgres-lab psql -U postgres -d case_s_x < sql/00_mock_database.sql
docker exec -it postgres-lab psql -U postgres -d case_s_x -c "\dt"
```

Then run the files in `sql/` in order. Each answer file ends with the final query; run that block alone to get the result in `results/`.

Dialect is PostgreSQL. Where SQL Server (T-SQL) differs (`TOP` vs `LIMIT`, `EOMONTH`, casting) it is noted in the file.

## Assumptions shared by A1 to A3

- Last 3 months = the three latest months in the data: 2026-08, 2026-09, 2026-10.
- Sold = `order_status = 'complete'`. Created / paid / on_delivery are not final; canceled / returned are not sales.
- GMV per Appendix A: before discount and shipping deduction. All values in USD.
- ADG and ADO use calendar days of the month. ABS = GMV / orders. Tier bounds: lower inclusive, upper exclusive.
- Top-N uses `ROW_NUMBER()`, so exactly N rows per month.

Question-specific assumptions are in the header of each SQL file and in the PDF.

## Part B: projection model

Quarterly model, Q1 2025A to Q4 2027E, three scenarios (Worst / Base / Best from X's perspective), USD at 26,000 VND/USD, P&L lines (1) to (13) as in Appendix B. X is assumed to be TikTok Shop Vietnam, the second-largest platform. Inputs are blue with a source or rationale beside each one. Tabs: README, Assumptions, Model, Scenarios, Findings, Sources. Extra, not asked by the test: the same model for company S (Shopee Vietnam) and an `S vs X` comparison tab, because "second largest" only means something relative to the largest.

Base case: X GMV USD 6.8bn (FY2025A) to USD 12.1bn (FY2027E); take rate 10.9% to 18.7%; P&L (Appendix B contribution) USD 131m to USD 1.5bn. X closes the GMV gap with S (0.74x to 0.92x) but passes it only in the Best case.

## Tools

PostgreSQL 17 in Docker, VS Code (PostgreSQL extension), Google Sheets, Google Docs. Mock data generated with a Python script.
