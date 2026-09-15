# Phase 8 — Carriers to ask and split-lane options

Date: 2026-09-14. Roadmap: phase 8, built after phase 7 (trip miles and truck
routes) is merged. Two additions to Lane Benchmark and the RFP lane panel.
**Carriers to ask** lists, by name only, carriers that know a lane when the
first search finds no carrier rate. **Split-lane options** shows, only on a
click, how a lane has been moved in legs by different carriers, with leg costs,
and estimates a split through a handoff point when the lane has no split
history. Direct shipments stay first and remain the default.

## 1. Decisions (brainstorm and research, 2026-09-14)

| #   | Decision                                                                                                                                                                                                                                                                                                                                                                               |
| --- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| D1  | **Direct first.** Split-lane options load only when the pricer clicks **Split-lane options**; nothing about splits runs before that. Direct results keep their place at the top.                                                                                                                                                                                                       |
| D2  | **No rate** means the first search found no priced carrier rate (a total other than 0) **in the pricing currency**: the RFP lane's currency in the lane panel; on Lane Benchmark the currency filter, or any currency when no filter is set.                                                                                                                                           |
| D3  | **Carriers to ask runs by itself on single-lane views**: after a Lane Benchmark search, and when the RFP lane panel opens a lane, whenever D2 holds. It never runs inside Load history; the lane table shows a **no rate** tag instead.                                                                                                                                                |
| D4  | **Names only, never amounts.** Stage 1, same lane: carriers that quoted the lane in the last 3 years, plus carriers that moved legs of split shipments on the lane. Stage 2, only when stage 1 finds nobody: the top 10 carriers on the same state or province lane over the last year, ranked by loads moved.                                                                         |
| D5  | **Blacklisted carriers** (`Account.Black_List__c`) stay in the list with a warning badge. The existing blacklist warning on Lane Benchmark results switches to the same account flag.                                                                                                                                                                                                  |
| D6  | **Intercompany carriers** are hidden through an admin-editable list of carrier accounts, seeded with "Tpml (Trans-Pro Logistics)-TP org" and "TRANS-PRO LOGISTIQUE - TPML- LESSARD ORG". No name matching. The existing excluded-contact setting stays.                                                                                                                                |
| D7  | **Split-lane options show leg costs.** Real split history comes from Revenova freight plans over the last 12 months, grouped by handoff point: shipments, each leg's carriers and median cost, and the median total per shipment built from each shipment's own legs. A leg with no priced history shows carrier names only. Amounts are Canadian dollars as stored on Revenova loads. |
| D8  | **Estimated options** for lanes with no split history: an admin-editable list of handoff points, seeded with Laredo TX, San Diego CA and Calexico CA. Points within about 10 % extra distance qualify (at most 3). Estimate = leg 1 median + leg 2 median + a handoff cost the pricer types, labelled as an estimate.                                                                  |
| D9  | **Use as cost** in the RFP lane panel: a split option fills the lane cost and sets the cost source to the new value **Split**. It is off on lanes not priced in CAD, because split amounts are CAD.                                                                                                                                                                                    |
| D10 | **Architecture: two new cards with their own server calls.** The existing lane search is not changed, apart from the blacklist flag in D5.                                                                                                                                                                                                                                             |
| D11 | Out of scope: currency conversion of split amounts, handoff points suggested from data, Market Test quotes as a source (their loads carry no lane keys), RFP bids as a source (test data only), loads without a quote as a source, quote expiry (never filled), a stored carrier or split table, production deployment (owner decision).                                               |

## 2. Today (measured in PostProduc, 2026-09-14)

PostProduc is a copy of production whose data ends on 2026-08-14; the 712 RFP lanes in it belong to 5 test projects. Frequencies below are estimates.

- **First search**: city on both ends, 90-day lookback, accepted and declined quotes, loads plus active bids, no mode filter; a rate is a row whose total is not 0 (`LaneSearchService` `countNonZero`). Nothing marks "no rate" today: Lane Benchmark implies it from the statistics, the RFP lane panel ignores them, Load history writes `No match` or `Done` with a blank median.
- **How often**: about 1 customer load in 3 had no priced carrier rate at city level in the 90 days before it was created (2,110 of 6,732): 26 % of direct loads, 77 % of split loads searched on their full lane. Counted by distinct lane it is 54 %, because most lanes have a single load.
- **Quotes**: `rtms__CarrierQuote__c` holds 404,381 quotes from 2018; the carrier is `rtms__Vendor__c` (indexed, equal to the displayed carrier on 2,000 of 2,000 recent quotes). The load lane keys (`rtms__City_Lane__c`, `rtms__State_Lane__c`, `rtms__Zip3_Lane__c`) are indexed External IDs; a destination-only pattern (`%:value`) is not selective.
- **Split shipments**: a Revenova freight plan links one customer load (`rtms__FreightPlanLoad__c.rtms__Type__c = 'Customer'`) to carrier legs (`'Carrier'`, ordered by `rtms__Number__c`). Customer loads leave `rtms__Freight_Plan__c` empty, so plans are found through the junction; junction rows were re-created in 2026, so dates come from `rtms__Load__r.CreatedDate`. Only 276 of 3,992 split customer loads in a year have any carrier quote, while their 8,242 legs name 767 carriers. Of split loads whose full lane had no priced rate, 67 % had every leg priced at city level.
- **Yield of a deeper search** on the hardest no-rate lanes: older quotes on the same lane name carriers on about 1 lane in 5 (usually 1 or 2 names); the same state lane names carriers on about 9 lanes in 10 but with a median of 38 names, hence the top 10.
- **Pollution**: in a year, intercompany vendors quoted 4,787 times (Tpml) and 1,918 times (Lessard org); the app hides only the Tpml contact. Name rules also catch real carriers (RHINO EXPRESS S.A DE C.V - LESSARD, Transport Simon Lessard Inc - Qc). `Account.Black_List__c` is set on 548 carrier accounts (596 accepted quotes from 4 carriers in a year); today's red results warning reads the Transportation Profile flag, which matches 0 quotes.
- **Money**: every load is in CAD; a load's `rtms__Carrier_Quote_Total__c` holds CAD at the rate of the quote date (USD quotes × about 1.366). `Load_Cost_CAD__c` is unreliable for USD legs and `rtms__Vendor_Quote_Total__c` equals the carrier total. Split customer loads have no carrier total, so costs come from the legs.
- **Handoffs**: Laredo TX is the handoff on 1,677 of 1,771 Mexico to US or Canada splits; San Diego 72, Calexico 13. The border crossing fee is usually inside the Mexican leg's quote; yard, transload and cross-dock fees are almost never recorded.
- **Code budgets**: `LaneSearchRequest` holds 20 of PMD's 20 fields; class complexity is 36 of 40 in `LaneBenchmarkController`, 37 in `RfpHistoryService`, 39 in `RfpSecurityTest` after phase 7; `rfpTool.js` is at 554 of its 560-line ceiling.

## 3. Carriers to ask

**Input**: the same request JSON the first search used (Lane Benchmark's service request; the lane panel's history request) and the pricing currency. The screen decides whether D2 holds from the search result it already has, then calls the server once.

**Stage 1, same lane** (last 3 years, non-cancelled loads):

- _Quotes_: carrier quotes on the first search's lane keys at its precision (city, province or postal prefix; a radius search uses the two places' city keys), grouped by `rtms__Vendor__c`, counting distinct loads quoted, distinct loads moved (accepted quotes) and the latest quote date.
- _Split legs_: customer loads on the same city lane that belong to a freight plan, then that plan's carrier legs, grouped by the leg load's carrier, counting distinct leg loads moved and the latest date.
- The two are merged per carrier (sources: Quote, Split leg), ranked by loads moved, then loads quoted, then last seen, and capped at 25.

**Stage 2, same state or province lane**, only when stage 1 finds no carrier: quotes on the state lane key over the last 365 days, grouped by carrier, ranked by loads moved then last seen, top 10. When the first search already used province keys, stage 1 covered that lane and stage 2 is skipped.

**Each carrier shows**: name, loads moved, loads quoted, last seen, sources, a blacklisted badge when `Account.Black_List__c` is set, and a link to the account only when the user can read it. Intercompany carriers from the D6 list and the excluded contact never appear.

**Names only**: every query is a grouped count that never selects an amount; the result type has no amount field, and a test fails when one appears.

## 4. Split-lane options

**History** (on click; last 12 months by the customer load's date, non-cancelled):

1. Find customer loads in freight plans on the lane (the first search's city keys; province keys when the first search used province; a radius search uses the places' city keys).
2. Read their plans' carrier legs in order, with each leg's carrier, lane, CAD carrier total and last stop's account (the handoff).
3. Leave out any shipment with a cancelled leg or an intercompany carrier on a leg.
4. Group shipments by their handoff sequence (for example "via Laredo, TX · SFMN Park ITC Laredo yard"), most shipments first, at most 5 groups.
5. For each group: shipments; for each leg position, its carriers (distinct, with legs moved) and the median of its priced leg totals; the **median total per shipment** over shipments whose legs are all priced, with that count. A leg position with no priced total shows names only.

**Estimates** (only when history finds no group):

1. Take the active handoff points from the D8 list; drop a point equal to the lane's origin or destination.
2. Keep points whose approximate distance origin → point → destination is at most 10 % above origin → destination (phase 7's great-circle × 1.2), at most 3, least extra distance first.
3. For each point, read Revenova loads over the last 365 days on the two leg lanes (origin side at the first search's precision, point side at city): carrier legs and direct loads with a positive CAD carrier total, at most 500 per leg. Each leg shows its carriers and the median total.
4. Estimate = leg 1 median + leg 2 median + the typed handoff cost, labelled **Estimate**. A leg without priced loads shows carrier names and no estimate total.

**Direct stays in view**: the first search's median in the pricing currency is shown beside the options.

**Use as cost** (RFP lane panel, CAD lanes only): fills the lane cost with the option's total (history median total, or estimate including the typed handoff cost) and sets `Cost_Source__c` to `Split`, through the panel's existing pricing change (saved like choosing a bid, clearing any selected bid). The margin then works as for any cost.

## 5. Data and settings

- `RFP_Lane__c.Cost_Source__c` gains the value **Split**; pricing math, bulk copy and the Excel export treat it as a stored cost with its own label.
- **`Intercompany_Carrier__mdt`** (new, public): `Carrier_Account_Id__c` Text(18), `Note__c` Text(255); records for the two accounts in D6 (their Ids are read from PostProduc while planning).
- **`Handoff_Point__mdt`** (new, public): `Place_Key__c` Text(255) (a `Pricing_Place__c.Key__c`), `Active__c` Checkbox; records Laredo TX, San Diego CA, Calexico CA.
- No new object and no stored results: answers come from cacheable Apex, and **Refresh** asks again.
- Both permission sets get class access to the two new controllers.

## 6. Apex behaviour

- `CarrierLeadController.findCarrierLeads(String requestJson, String pricingCurrency)` — `@AuraEnabled(cacheable=true)`; honours `excludeProjectId` only for a readable project, as `LaneBenchmarkController.search` does.
- `CarrierLeadService` — reads quotes, freight plans and legs in system mode, like `LaneSearchService`, because carrier quotes inherit Private load sharing; one user-mode `Account` read decides each link.
- `CarrierLeadResult` — `leads` (carrier Id, name, loads moved, loads quoted, last seen, sources, blacklisted, can open), `stage` (`Same lane`, `State lane`, `None`), `truncated`; no `Decimal` field anywhere.
- `SplitLaneController.splitOptions(String requestJson, String pricingCurrency)` — `@AuraEnabled(cacheable=true)`; returns `SplitLaneResult` (history groups or estimate options, each leg's carriers, medians and counts, the direct median). The handoff cost is added on the screen.
- `IntercompanyCarriers` and `HandoffPoints` read the two custom metadata lists, with test overrides (custom metadata cannot be inserted in tests), like `LaneSearchExclusions`.
- The blacklist warning on Lane Benchmark results reads the quote carrier account's `Black_List__c`.
- New classes carry the logic; `LaneSearchService`, `LaneSearchRequest`, `LaneBenchmarkController` and `RfpHistoryService` keep their budgets.

## 7. What people see

- **Lane Benchmark**, right column top to bottom: Statistics; **Carriers to ask** when D2 holds ("No carrier rate on this lane in CAD. These carriers quoted or moved it before; amounts are not shown."); phase 7's route map; Results; a **Split-lane options** button at the bottom.
- **RFP lane panel**: **Carriers to ask** under the history results when the lane has no rate in its currency, then the **Split-lane options** button; each option has **Use as cost** on CAD lanes.
- **Stage 2 wording**: "No carrier on this exact lane. Top carriers on QC to ON over the last year."
- **Split card**: one block per handoff group or estimate, for example "Via Laredo, TX · SFMN Park ITC Laredo yard · 34 shipments", then leg lines "Leg 1 General Escobedo, NL → Laredo, TX · Q Transportes (18), Fletes Mex (9) · median 1,248 CAD", then "Total per shipment, median 6,453 CAD (31 shipments)". Estimates read "Estimate via Laredo, TX · +6 % distance", with a **Handoff cost (CAD)** input.
- **Lane table**: a **no rate** tag in the History cell when history found nothing or found no priced rate in the lane's currency (`No match`, or `Done` with a blank median).
- **Help guide** (EN and FR): the two cards and the tag in `lb-stats`, `rfp-pricing` and `rfp-inline`; the resource is rebuilt.
- `rfpTool.js` and `rfpTool.html` do not change.

## 8. Limits, errors, security

- Carriers to ask: about 8 queries per call (an estimate from the design, to be measured in the browser check), each stage a grouped count capped at 50 carriers, never more than 3 years, never a radius over 3 years; a query-row check stops early and shows "The list may be incomplete".
- Split history: two junction queries plus one leg read; estimates: at most 3 points × 2 leg reads of at most 500 loads.
- Each card fails on its own with a short message and **Retry**; the first search's rates and rows are never held back. Cacheable answers make reopening a lane instant.
- Carrier names and carrier costs are already visible to everyone who runs a lane search. Carriers to ask shows no amount at all; split options show leg costs the way Lane Benchmark results already show quote totals, and never name the customer.
- Use as cost uses the lane panel's existing user-mode save; the new picklist value needs no new permission.

## 9. Testing

- Apex: each stage (quotes, split legs, state lane, ranking, cap), the D2 currency rule, intercompany and excluded-contact removal, blacklisted badge, account link only when readable, the names-only key set, split history grouping and medians, shipments with cancelled or intercompany legs left out, estimate point selection and totals, the blacklist warning source. New security tests go in a new test class.
- The first plan task checks whether Revenova's managed triggers allow inserting `rtms__FreightPlan__c` and `rtms__FreightPlanLoad__c` in tests; if not, the services read plan rows through a test-only hook.
- Jest: both cards (loading, empty, error and Retry, stage 2 wording, badge, link), the no rate tag, Use as cost on and off, the handoff cost input.
- Browser check: General Escobedo, NL → St-Augustin-de-Desmaures, QC for split history; a lane with no rate for Carriers to ask; a USD lane to see Use as cost off.

## 10. Rulings

- R80 — "no rate" is judged in the pricing currency (D2), matching how an RFP lane's median works.
- R81 — Carriers to ask stops at the first stage that finds a carrier; stage 2 never mixes with stage 1.
- R82 — "loads moved" counts accepted quotes and split legs; ranking is loads moved, then loads quoted, then last seen.
- R83 — a radius first search uses the two places' city keys for the deeper steps; no radius search spans 3 years.
- R84 — split history dates come from the customer load, because freight-plan junction rows were re-created in 2026.
- R85 — the split total is the median of each shipment's own leg sum, over shipments with every leg priced, not a sum of leg medians.
- R86 — estimates read Revenova load totals in CAD on the two leg lanes over 365 days, not quote currency buckets, so they stay in CAD like history (most Mexican legs are quoted in USD).
- R87 — a shipment with a cancelled leg or an intercompany carrier on a leg is left out of split history.
- R88 — Use as cost works only on CAD lanes; this phase converts no currency.
- R89 — intercompany carriers are listed by account Id; the existing excluded-contact setting stays as it is.
- R90 — blacklisted carriers stay visible with a badge, and the existing results warning reads the same account flag.
- R91 — nothing is stored: cacheable Apex serves repeated views and Refresh asks again.
- R92 — new classes hold the logic, so the existing search classes keep their PMD budgets and field caps.
- R93 — Load history is unchanged apart from the lane table's no rate tag, which reads existing fields.
