# Part B: projection model for company X (and S)

Live file: https://docs.google.com/spreadsheets/d/1LgIXNfAwEwsVd1FwZXyYwN49rmuzRnWOJmo0zYuTAfQ

An .xlsx export of the sheet is kept here for offline reading (`Case_S_vs_X_Q5_Projection_Model.xlsx`, File > Download > Microsoft Excel from the Google Sheet). Formulas survive the export; the Google Sheet is the editable master.

| Tab | Content |
|---|---|
| README | Purpose, how to use, model logic, notation |
| Assumptions | X inputs. B3 = scenario selector (Worst case / Base case / Best case). Scenario inputs by year (rows 8-18), quarterly inputs (rows 22-36), source or rationale in column O |
| Model | X quarterly GMV, orders, ADG, ADO, ABS, revenue lines (2) to (9), cost (10) to (12), P&L (13), take rate, margins; annual summary via SUMIFS |
| Scenarios | FY2027E for all three scenarios side by side, independent of the selector |
| Findings | Eight conclusions, caveats, live output table |
| Sources | Every external source with URL, what it was used for, access date |
| S Assumptions | Company S inputs. S share = 1 - X share - other platforms. Shopee VN fee schedule by quarter |
| S Model | Same structure as Model, for S |
| S vs X | Fiscal-year comparison (GMV, share, orders, AOV, revenue, take rate, voucher cost, P&L) with X / S multiples and pp gaps; quarterly view; seven comparison findings |

## Model logic in one paragraph

Market GMV for a projected quarter = same quarter of the prior year x (1 + scenario growth), which carries 2025 seasonality forward. Company GMV = market x share. Orders = GMV / AOV; AOV grows YoY at the scenario rate. Revenue (1) = mandatory fees (2) [transaction / freeship program fee (3) + handling fee per delivered order (4) + commission (5)] + ads (6) + value-added programs (7) [extra vouchers (8) + other (9)]. Cost (10) = freeship voucher subsidy (11) + discount voucher subsidy (12), both as % of GMV. P&L (13) = (1) - (10): contribution before fulfilment, payment, headcount and technology, per Appendix B, not EBITDA.

## Notation

USD bn = billions, USD m = millions, pp = percentage points, x = multiple, YoY = year on year, FY = fiscal year, A = actual, E = estimate. Blue cells = inputs, black = formulas.
