# Phase 7 — Trip miles on every lane

Date: 2026-09-14. Roadmap: phase 7, after phase 6 and its follow-ups merged as
`bc4710b`. Adds the length of the trip, in miles with km on click, and the rate
per mile wherever the app shows a lane: the RFP workbench (table, lane panel,
Excel export) and Lane Benchmark (statistics, results, CSV).

## 1. Decisions from the brainstorm (2026-09-14)

| #   | Decision                                                                                                                                                                                                                 |
| --- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| D1  | A lane's miles are the **median of Revenova's Distance (Miles)** (`rtms__Load__c.rtms__Distance_Miles__c`) on the loads its history search matched. Bids carry no miles; a load with no miles or zero miles is left out. |
| D2  | When no matched load has miles, the lane gets the **road distance between its two places from Mapbox**, marked as an estimate. It is a car route, not a truck route.                                                     |
| D3  | The fallback is computed **during Load history and Refresh history**, in the same call (10 lanes): one Mapbox request per call covers every lane in it that needs a map distance.                                        |
| D4  | Every map distance is **saved once per ordered place pair** (origin place → destination place) and reused by every RFP and by Lane Benchmark.                                                                            |
| D5  | Miles appear **everywhere a lane appears** ("where we have a lane we have miles"): RFP lane table, lane panel, Excel export, cost and sell per mile, Lane Benchmark statistics, Lane Benchmark results and its CSV.      |
| D6  | **Miles by default, km on click.** One toggle switches distance and rate per distance to km; each browser remembers the choice. The Excel export always carries both miles and km.                                       |
| D7  | No backfill job. Existing lanes get miles on their next Load or Refresh history.                                                                                                                                         |
| D8  | Out of scope: truck-specific routing, tolls, driving time, per-stop mileage. Production is not deployed (user decision).                                                                                                 |

## 2. Today (measured in PostProduc, 2026-09-14)

- `rtms__Load__c.rtms__Distance_Miles__c` (Number 16,2) and `rtms__Distance_Kilometers__c` are filled by Revenova's mileage provider on 53,054 of 54,480 loads created in the last 365 days (97 %); 53 are zero; average 1,119 mi, maximum 6,249 mi. Revenova's managed classes (`rtms.MileageAPI`, `rtms.PCMilerAPI`) exist but are not a supported entry point for this app.
- Lane history rows come from `rtms__CarrierQuote__c` through `LaneSearchQueryBuilder.SELECT_CLAUSE`; the load is reachable as `rtms__Load__r`. `RfpHistoryService.run` handles at most 10 lanes per call (`MAX_LANES`; the LWC sends `HISTORY_CHUNK = 10`).
- 694 of the 712 sandbox RFP lanes have coordinates at both ends (`Pricing_Place__c.Geolocation__c`, Location, 6 decimals). Most lanes are US–US, then CA–CA, US–CA, CA–US and Mexico lanes.
- Mapbox: token `TPRO_KPI__c.Mapbox_Api_Key__c` (public `pk.` token), remote site `MapBox` (`https://api.mapbox.com`). `MapboxGeocoder` does forward geocoding and the static map only.
- Mapbox Matrix API (`/directions-matrix/v1/mapbox/driving/{coordinates}`): 2 to 25 coordinates per request, 60 requests per minute, `annotations=distance` returns meters, `null` for a pair with no route, `sources`/`destinations` select an M×N matrix, billed per element (sources × destinations, minimum 2).
- `LaneBenchmarkController.search` is `@AuraEnabled(cacheable=true)`: it cannot write, so a map lookup for Lane Benchmark needs its own method.
- `rfpTool.js` is at 554 of its 560-line ceiling; this phase adds no line to it.

## 3. Data model

**`RFP_Lane__c`** gains:

- `Miles__c` — Number(10, 1), the trip miles for this lane.
- `Miles_Source__c` — Picklist: `History`, `Map estimate`, `No route`, `No coordinates`, `Unavailable`. Blank means history has not run since phase 7.

Both are written by the history run with the same permissions as the `Hist_*` fields.

**New object `Place_Distance__c`** (label "Place Distance", Public Read Only, not reportable by default, no tab):

- `Origin_Place__c` — Lookup to `Pricing_Place__c`, required, delete constraint Restrict.
- `Destination_Place__c` — Lookup to `Pricing_Place__c`, required, delete constraint Restrict.
- `Pair_Key__c` — Text(40), External ID, Unique: `<origin place Id>:<destination place Id>`, so a save is an upsert.
- `Miles__c` — Number(10, 1); blank when Mapbox found no route.
- `Status__c` — Picklist: `Found`, `No route`.
- `Checked_On__c` — Datetime of the Mapbox answer.

Distances between public places are not sensitive, so the object is Public Read Only; only Apex writes it, in system mode, through the service below. Both permission sets gain read on the object and its fields. A row never expires: an admin deletes a row to have that pair asked again.

## 4. Apex

**`TripMilesService`** (new, `with sharing`; its cache writes run in system mode with a justification comment):

- `Decimal medianMiles(List<LaneSearchResult.Row> rows)` — the median of `miles` over rows with miles above zero, same median rule as `LaneSearchService` (odd count: middle value; even count: mean of the two middle values); `null` when none.
- `Map<String, Result> distances(List<PlacePair> pairs)` — for each ordered pair: a saved `Place_Distance__c` row wins; pairs whose places lack coordinates return `No coordinates`; the rest are asked from Mapbox in as few Matrix requests as the 25-coordinate limit allows (unique places as coordinates, `sources` and `destinations` indices per request) and return `Found` or `No route`. A missing token or a failed callout returns `Unavailable` for the pairs of that request and saves nothing for them. Callouts happen before any DML.
- `void save(Map<String, Result> fresh)` — upserts the new `Found` and `No route` answers on `Pair_Key__c`. Called by the owner of the transaction after its callouts.

**`MapboxMatrix`** (new, next to `MapboxGeocoder`, reusing its token read and one-retry send): `List<List<Decimal>> distancesMeters(List<Coordinate> coordinates, List<Integer> sources, List<Integer> destinations)`; builds `annotations=distance`, maps HTTP and `code` errors to a `LaneSearchException` with a user sentence, never logs the token.

**Lane history** (`LaneSearchQueryBuilder`, `LaneSearchResult`, `LaneSearchService`, `RfpHistoryService`):

- `SELECT_CLAUSE` adds `rtms__Load__r.rtms__Distance_Miles__c`; `LaneSearchResult.Row` gains `miles` (load rows: the load's miles; bid rows: `null`).
- `LaneSearchResult` gains `medianMiles` (all rows) and `LaneSearchResult.Stats` gains `ratePerMileMedian`: the median of `carrierTotal / miles` over that currency's rows with both above zero.
- `RfpHistoryService.run`: after the searches and before any DML, each lane takes `medianMiles` of its rows (`Miles_Source__c = History`); lanes still without miles send their resolved place pair to `TripMilesService.distances` in one batch; then the lane update, then `TripMilesService.save`. An unresolved lane keeps `Miles__c` blank with `No coordinates`.

**Lane Benchmark** (`LaneBenchmarkController`):

- `search` is unchanged apart from the new row and statistics fields.
- New `@AuraEnabled public static TripMiles tripMiles(String originKey, String destinationKey)` (not cacheable): resolves the two place keys, returns the saved distance or asks Mapbox once and saves it; returns `{ miles, source }` with `source` = `Map estimate`, `No route`, `No coordinates` or `Unavailable`. The page calls it only when the search result has no `medianMiles`.

## 5. What people see

A shared LWC module **`c/distanceUnit`** holds the unit (`mi` or `km`, key `tripMiles.unit.v1` in localStorage, guarded like the help language), `formatDistance(miles, unit)` and `perDistance(amount, miles, unit)` (1 mi = 1.609344 km). A small **`c-distance-unit-toggle`** ("mi | km", pressed state exposed with `aria-pressed`) publishes the choice on a Lightning message channel **`Distance_Unit__c`**, so every component on the page switches at once.

- **RFP toolbar**: the toggle sits next to Include RFP bids (in `rfpToolbar`, not `rfpTool`).
- **RFP lane table**: a **Miles** column after History — "1,234 mi" or "1,986 km"; an `est.` tag when the source is `Map estimate`; "—" with the reason as a tooltip for `No route`, `No coordinates`, `Unavailable` or blank.
- **Lane panel**: under the lane title, "1,234 mi (history)" or "(map estimate)"; next to the prices, **Cost per mile** and **Sell per mile** (or per km), recomputed as the pricer types; blank when the lane has no miles.
- **Excel export** (`rfpWorkbook` lane sheet): new columns after "Transit days": Miles, Km, Miles source, Cost per mile, Sell per mile — always miles and km, whatever the toggle.
- **Lane Benchmark statistics**: a header line "Trip: 1,234 mi (median of N loads)" or "Trip: 1,234 mi (map estimate)"; in each currency block, **Rate per mile (median)**; the toggle sits in the card header.
- **Lane Benchmark results**: a **Miles** column (load rows show their load's miles; bid rows "—") and the same column in the CSV.
- **Help guide** (EN and FR): a "Trip miles" paragraph in `rfp-history` and `lb-stats`, and the table column in `rfp-inline`; the static resource is rebuilt.

## 6. Limits, errors, cost

- A history call of 10 lanes needs at most one Matrix request (at most 20 unique places); callouts per transaction stay far below 100. `tripMiles` makes at most one.
- Mapbox rate limit is 60 Matrix requests per minute; history calls run one after another, so a 2,000-lane RFP makes at most 200 requests over several minutes, and repeated pairs cost nothing after the first time.
- Billing is per matrix element; the service asks only for the sources and destinations of pairs that are not saved yet, so a pair is billed once. The admin checks the Mapbox plan before go-live.
- Mapbox answers `null` for a pair with no route (for example across water): saved as `No route`, shown as "—".
- A failed or unauthorised callout never blocks the history run: the lanes of that request show `Unavailable` and are asked again on the next Refresh history.

## 7. Testing

- **Apex** (new `TripMilesServiceTest`, `MapboxMatrixTest`; extended `RfpHistoryServiceTest`, `LaneSearchServiceTest`, `LaneBenchmarkControllerTest`, `RfpSecurityTest`): median rules and zero or missing miles; a saved pair makes no callout (`Limits.getCallouts()` stays 0); a Matrix mock with 13 distinct pairs is split into two requests; `null` becomes `No route`; missing token becomes `Unavailable` with nothing saved; places without coordinates; the history run calls out before its DML (no "uncommitted work pending"); rate per mile median per currency; `tripMiles` for a Lane Benchmark user; an RFP Tool user runs history and gets miles. `LaneSearchServiceTest`'s governor-sensitive method keeps its setup outside `Test.startTest`.
- **Jest**: `distanceUnit` (format, per distance, storage guard), the toggle publishing on the channel, table column and `est.` tag, panel cost and sell per mile live, workbook columns, stats header and rate per mile, results column and CSV.
- **Browser (PostProduc)**: Load history on the "Phase 3c browser check" project fills Miles for every resolved lane; a lane with no matched load shows `est.`; km toggle switches table, panel and Lane Benchmark together; a Lane Benchmark search on a rare pair shows the map estimate; the Excel export has the five new columns.
- The Apex test roster (README, CI) gains the two new test classes.

## 8. Rulings

- R70 — the lane's miles are the median over every matched load row at the precision the history used (radius matches included), not only exact-city loads.
- R71 — map distances are saved per ordered place pair and never expire; direction matters because Mapbox routes are not symmetric.
- R72 — the unit toggle is shared through a Lightning message channel rather than a DOM event, so components in different parts of the page stay in step under Lightning Web Security.
- R73 — no backfill job; the next Load or Refresh history fills existing lanes.
