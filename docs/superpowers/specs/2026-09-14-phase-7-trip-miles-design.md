# Phase 7 — Trip miles and truck routes on every lane

Date: 2026-09-14. Roadmap: phase 7, after phase 6 and its follow-ups merged as
`bc4710b`. Adds the length of the trip (miles, km on click), the rate per mile
and a truck route drawn on the map, wherever the app shows a lane: the RFP
workbench (table, lane panel, Excel export) and Lane Benchmark (statistics,
results, CSV, map). Routing runs on Mapbox now and is built behind one
interface so a self-hosted Valhalla server (a separate project) can replace it
by configuration.

## 1. Decisions (brainstorm and research, 2026-09-14)

| #   | Decision                                                                                                                                                                                                                                                                                                                                                                        |
| --- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| D1  | A lane's miles come from, in order: **History** — the median of Revenova's billed Distance (Miles) (`rtms__Load__c.rtms__Distance_Miles__c`, filled by PC*Miler) on the loads its history search matched; **Truck route** — the miles of the truck route the routing provider returned for the lane's two places; **Approx** — the straight-line distance × 1.2.                |
| D2  | The routing provider is **Mapbox now** (Directions API, driving profile with the truck's height, width and weight, alternatives on) and **Valhalla later** (the owner's self-hosted server, true truck costing and a truck-aware matrix). A custom metadata setting picks the provider; switching needs no code change. openrouteservice was considered and dropped.            |
| D3  | The truck route is fetched **when a pricer opens a lane** in the RFP workbench or **runs a Lane Benchmark search**, once per place pair and truck profile; the result is **stored** and reused. Storing Mapbox routing results is the **owner's decision**, taken after the Mapbox Product Terms clause against caching or storing Navigation API results (§2.10.1) was raised. |
| D4  | **Load history** fills every resolved lane: history miles when matched loads have miles; otherwise truck-route miles from the provider's matrix when the provider supports truck limits in a matrix (Valhalla); otherwise Approx. Mapbox's Matrix API takes no truck limits, so on Mapbox Load history uses Approx.                                                             |
| D5  | The map is the **existing Mapbox static image**: pins for the two places, the main route as a thick line and up to two alternatives in other colours, with a legend of miles and hours per route. No interactive map (Mapbox GL JS is blocked by Lightning Web Security).                                                                                                       |
| D6  | **Miles by default, km on click**, remembered per browser, shared by every component on the page. Rate per mile (per km) wherever a price and miles meet. The Excel export always carries miles and km.                                                                                                                                                                         |
| D7  | The Approx factor **1.2** is measured, not guessed: on 10,939 PostProduc loads from the last year, billed miles ÷ straight-line miles has a median of 1.196 (middle half 1.148 to 1.271), stable across country pairs and trip lengths.                                                                                                                                         |
| D8  | Out of scope: the Valhalla server itself (separate project), hazmat routing on Mapbox (no parameter), truck length or axle limits on Mapbox (no parameters), tolls, per-stop mileage, a background backfill job. Production is not deployed (owner decision).                                                                                                                   |

## 2. Today (measured, 2026-09-14)

- Billed miles: `rtms__Distance_Miles__c` is filled on 53,054 of 54,480 loads created in the last 365 days (97 %). Revenova's mileage classes (`rtms.MileageAPI`, `rtms.PCMilerAPI`, …) are "Type is not visible" to our Apex (check-only compile), so PC*Miler cannot be called directly.
- History rows come from `rtms__CarrierQuote__c` through `LaneSearchQueryBuilder.SELECT_CLAUSE`; `RfpHistoryService.run` handles at most 10 lanes per call. 694 of 712 sandbox RFP lanes have coordinates at both ends (`Pricing_Place__c.Geolocation__c`).
- Mapbox: token `TPRO_KPI__c.Mapbox_Api_Key__c` (public `pk.` token), remote site `MapBox`, CSP trusted site `Mapbox_API` (img-src). `MapboxGeocoder` does forward geocoding and builds the static map URL (`staticMapUrl`, GeoJSON overlay, 600×300). `LaneBenchmarkController.search` and `mapPreviewUrl` are cacheable, so anything that calls out and saves needs its own method.
- Mapbox Directions API: profiles `mapbox/driving` and `mapbox/driving-traffic`; `max_height` and `max_width` in metres (0–10), `max_weight` in metric tons (0–100), best-effort with regional coverage and violation notifications; no truck profile, no hazmat, no length or axle parameters; `alternatives=true` returns up to two alternatives (the docs contradict themselves on whether that is two or three routes in total); distance in metres, duration in seconds, geometry as a 5-decimal polyline by default with `overview=simplified`; 300 requests per minute; billed per request. The Matrix API accepts none of the truck parameters.
- Mapbox Static Images API: several path overlays per image (`path-{width}+{colour}-{opacity}({polyline})`), `auto` framing, 8,192-character URL limit.
- Valhalla (docs): truck costing with height, width, length (m), weight, axle load (t), axle count, hazmat, `use_truck_route`; `alternates` for two-location routes; `units=miles`; `format=osrm` with `shape_format=polyline5`; the matrix (`sources_to_targets`) supports truck costing; `/status` health endpoint; no built-in authentication.
- `rfpTool.js` is at 554 of its 560-line ceiling; this phase adds no line to it.

## 3. The routing seam (ready for Valhalla)

**`TruckRouter`** (Apex interface):

- `String providerName()`
- `Boolean supportsTruckMatrix()`
- `TruckRouting.RouteResult route(TruckRouting.Point origin, TruckRouting.Point destination, TruckRouting.Profile profile)` — up to 3 routes, each `{ miles, hours, polyline5 }`, main route first; status `Found`, `No route` or `Unavailable`.
- `List<List<Decimal>> matrixMiles(List<TruckRouting.Point> sources, List<TruckRouting.Point> targets, TruckRouting.Profile profile)` — only called when `supportsTruckMatrix()`; `null` cells for no route.

**`TruckRouting`** (factory and value types): reads `Truck_Routing_Setting__mdt.Default` and returns the configured router; builds the `Profile` from the setting and the lane's hazmat flag; computes `profileKey` (provider plus the rounded vehicle values) so a change of truck or provider never reuses an old route.

**`MapboxTruckRouter`** (live): `GET /directions/v5/mapbox/driving/{lon},{lat};{lon},{lat}?alternatives=true&overview=simplified&geometries=polyline&max_height=&max_width=&max_weight=&access_token=`; converts metres to miles and seconds to hours; `supportsTruckMatrix()` is `false`; hazmat, length and axle values are ignored and documented as such. Reuses `MapboxGeocoder`'s token read and one-retry send (moved into a small shared `MapboxHttp` helper). The token is never logged.

**`ValhallaTruckRouter`** (built, off): `POST callout:Valhalla_Routing/route` with the request shape agreed with the Valhalla project (`costing=truck`, `costing_options.truck` height, width, length, weight, axle_load, axle_count, hazmat, use_truck_route; `units=miles`; `alternates=2`; `format=osrm`; `shape_format=polyline5`) and `POST callout:Valhalla_Routing/sources_to_targets` (truck costing, miles); `supportsTruckMatrix()` is `true`. Tested with callout mocks against JSON fixtures copied from the Valhalla API reference.

**Configuration**

- `Truck_Routing_Setting__mdt` (new), record `Default`: `Provider__c` (Picklist: `Mapbox`, `Valhalla`; default `Mapbox`), `Height_M__c` 4.11, `Width_M__c` 2.6, `Length_M__c` 21.64, `Weight_T__c` 36.29, `Axle_Load_T__c` 9.07, `Axle_Count__c` 5, `Use_Truck_Route__c` 0.5, `Alternatives__c` 2, `Approx_Factor__c` 1.2, `Timeout_Ms__c` 8000. Defaults describe a 53 ft dry-van tractor-trailer at 80,000 lb, 13 ft 6 in high, 102 in wide.
- External Credential `Valhalla_Routing` (custom authentication, one principal parameter for the key sent as header `X-Api-Key`) and Named Credential `Valhalla_Routing` with a placeholder URL `https://valhalla.invalid`. No key is committed; the admin enters the real URL and key at Valhalla go-live (README runbook). Both permission sets gain access to the External Credential principal.

## 4. Data model

**`RFP_Lane__c`** gains:

- `Miles__c` — Number(10, 1).
- `Miles_Source__c` — Picklist: `History`, `Truck route`, `Approx`, `No route`, `No coordinates`.
- `Route_Hours__c` — Number(6, 1), drive hours of the stored truck route; blank for History and Approx.

`RFP_Tool_User` grants read and edit on the three fields, like the `Hist_*` fields (the history run writes lanes in user mode after `Security.stripInaccessible(UPDATABLE)`; a missing grant would silently drop the miles). `Lane_Benchmark_User` has no lane permissions and needs none.

**`Truck_Route__c`** (new, label "Truck Route", Public Read Only, no tab):

- `Origin_Place__c`, `Destination_Place__c` — Lookups to `Pricing_Place__c`, not required, delete constraint Set Null (like every place lookup in the app); rows with a blank place are ignored.
- `Provider__c` — Picklist `Mapbox`, `Valhalla`.
- `Profile_Key__c` — Text(80).
- `Route_Key__c` — Text(160), External ID, Unique: `<origin Id>:<destination Id>:<profileKey>`.
- `Miles__c` — Number(10, 1), main route; `Hours__c` — Number(6, 1).
- `Status__c` — Picklist `Found`, `No route`.
- `Routes_Json__c` — Long Text Area(131072): up to 3 routes `{ miles, hours, polyline5 }`, main first, for redrawing the map without a new request.
- `Checked_On__c` — Datetime.

Only `TripMilesService` writes it, in system mode with a justification comment. Both permission sets gain read. A row never expires; the lane panel's **Refresh route** action replaces it (one new request). Direction matters: A→B and B→A are separate rows.

## 5. Apex behaviour

**`TripMilesService`** (new):

- `Decimal medianMiles(List<LaneSearchResult.Row> rows)` — median of `miles` over rows above zero, same rule as `LaneSearchService` (odd count middle value, even count mean of the two middle values).
- `Decimal approxMiles(Pricing_Place__c o, Pricing_Place__c d)` — great-circle miles (Earth radius 3,958.7613 mi) × `Approx_Factor__c`, one decimal; `null` without coordinates.
- `TruckRouting.RouteResult storedOrRoute(Pricing_Place__c o, Pricing_Place__c d, TruckRouting.Profile p, Boolean refresh)` — a saved `Truck_Route__c` wins unless `refresh`; otherwise one router call. Returns the result and the row to save; the caller saves after its callouts.
- `void save(List<Truck_Route__c> rows)` — upsert on `Route_Key__c`.

**Lane history** (`LaneSearchQueryBuilder`, `LaneSearchResult`, `LaneSearchService`, `RfpHistoryService`):

- `SELECT_CLAUSE` adds `rtms__Load__r.rtms__Distance_Miles__c`; `LaneSearchResult.Row` gains `miles` (bid rows `null`); `LaneSearchResult` gains `medianMiles`; `LaneSearchResult.Stats` gains `ratePerMileMedian` (median of `carrierTotal / miles` over that currency's rows with both above zero).
- `RfpHistoryService.run`, after its searches and before any DML: each lane with `medianMiles` takes it (`History`); a lane already holding `Truck route` miles keeps them; if the configured router `supportsTruckMatrix()`, the remaining lanes' place pairs go to one `matrixMiles` call (≤ 10 sources × 10 targets) and take `Truck route`; the rest take `Approx`, or `No coordinates`. Then the lane update, then `TripMilesService.save`.

**On demand**

- `RfpLaneController.laneRoute(Id laneId, Boolean refresh)` (`@AuraEnabled`, not cacheable): reads the lane in user mode; if it has resolved places, calls `storedOrRoute`; saves the store row; when the lane's source is not `History`, writes `Miles__c` (main route), `Miles_Source__c = Truck route`, `Route_Hours__c`; returns `{ routes[], mapUrl, source }`.
- `LaneBenchmarkController.truckRoute(String originKey, String destinationKey, Boolean refresh)` (`@AuraEnabled`, not cacheable): resolves the two places, `storedOrRoute`, save, returns `{ routes[], mapUrl }`. The page calls it after a search; the cacheable `search` is unchanged apart from the new row and statistics fields.

**Map URL** (`RouteMapUrl`, new, next to `MapboxGeocoder.staticMapUrl`): `pin-s-a+0070d2` and `pin-s-b+2e844a` for the places, the main route `path-5+0070d2-0.9`, alternatives `path-3+f59e0b-0.8` and `path-3+706e6b-0.7`; `auto` framing, 600×300 @2x. If the URL would pass 8,000 characters, Apex simplifies each line (Douglas–Peucker, growing tolerance) and re-encodes it until it fits; if it still does not fit, alternatives are dropped before the main route. The Lane Benchmark radius circles stay when a radius search is shown.

## 6. What people see

A shared LWC module **`c/distanceUnit`** holds the unit (`mi` default, `km`; localStorage key `tripMiles.unit.v1`, guarded), `formatDistance(miles, unit)`, `perDistance(amount, miles, unit)` (1 mi = 1.609344 km). **`c-distance-unit-toggle`** ("mi | km", `aria-pressed`) publishes on the Lightning message channel **`Distance_Unit__c`**. A shared **`c-route-map`** shows the image, a legend (route, miles or km, hours) and a Refresh route button.

- **RFP toolbar**: the unit toggle next to Include RFP bids (`rfpToolbar`).
- **RFP lane table**: a **Miles** column after History — the value with a small tag: none for History, `truck` for Truck route, `approx.` for Approx; "—" with the reason as a tooltip otherwise.
- **Lane panel**: miles and source under the lane title; **Cost per mile** and **Sell per mile** next to the prices, live as the pricer types; `c-route-map` below, loaded on open through `laneRoute` (a spinner while it loads; a short message if the route is unavailable).
- **Excel export** (`rfpWorkbook` lane sheet): Miles, Km, Miles source, Route hours, Cost per mile, Sell per mile.
- **Lane Benchmark statistics**: "Trip: 1,234 mi · median of N loads" and "Truck route: 1,260 mi · 21.5 h"; **Rate per mile (median)** per currency; the toggle in the card header.
- **Lane Benchmark map**: `c-route-map` replaces the plain preview when a truck route is available; the radius preview stays otherwise.
- **Lane Benchmark results**: a **Miles** column (load miles; bid rows "—") and the CSV column.
- **Help guide** (EN and FR): "Trip miles and truck routes" in `rfp-history`, `rfp-pricing` and `lb-stats`, the table column in `rfp-inline`; the resource is rebuilt.

## 7. Limits, errors, cost

- One on-demand route is one callout; the history matrix (Valhalla only) is one callout per 10-lane call. Callouts always run before the transaction's DML. The router timeout is 8 s (setting), well inside the 120 s cumulative callout limit.
- Mapbox Directions: 300 requests per minute, billed per request; each place pair and truck profile is requested once, then served from `Truck_Route__c` until a pricer refreshes it.
- A missing token or credential, an HTTP error or a timeout returns `Unavailable`: nothing is saved, the lane keeps its current miles, the panel says "The truck route is not available right now."
- Mapbox answers with no route (for example across water): saved as `No route`, shown as "—".
- Mapbox truck limits are best effort: a route that breaks one comes back with a violation notification; the service stores the route and records `violations` in `Routes_Json__c`, and the legend shows "restrictions not guaranteed on this route".

## 8. Switching to Valhalla (runbook, not code)

1. The Valhalla project hands over the HTTPS base URL and the key.
2. Setup → Named Credentials → `Valhalla_Routing`: set the URL; External Credential principal: set the key.
3. `Truck_Routing_Setting__mdt.Default.Provider__c` = `Valhalla`.
4. Refresh history on a project: lanes without history now get `Truck route` miles from the matrix instead of `Approx`; opened lanes get Valhalla routes (new `Route_Key__c`, because the provider is part of the profile key).
5. Attribution on the map legend switches to "© OpenStreetMap contributors".

## 9. Testing

- **Apex**: `TripMilesServiceTest` (median rules; approx math and factor; store hit makes no callout — `Limits.getCallouts()` stays 0; refresh replaces the row; a missing place is ignored), `MapboxTruckRouterTest` (request URL carries the truck values and alternatives; metres→miles, seconds→hours; up to 3 routes; no route; HTTP 401 and timeout → Unavailable; token never in a thrown message), `ValhallaTruckRouterTest` (route and matrix request bodies match the agreed contract; fixture responses parsed; `null` matrix cells), `TruckRoutingTest` (factory per provider; profile key changes with any vehicle value or provider), `RouteMapUrlTest` (overlays and colours; a long route is simplified under 8,000 characters; alternatives dropped last resort), extended `RfpHistoryServiceTest` (History > kept Truck route > matrix > Approx; callouts before DML), `LaneSearchServiceTest` (row miles, median miles, rate per mile; its governor-sensitive method keeps setup outside `Test.startTest`), `RfpLaneControllerTest` and `LaneBenchmarkControllerTest` (on-demand routes, saved, lane written only when not History), `RfpSecurityTest` (an RFP Tool user opens a lane route; a Lane Benchmark user gets a truck route; a stranger without the lane gets the existing unavailable-lane error).
- **Jest**: `distanceUnit`, the toggle and channel, table column tags, panel per-mile values, `c-route-map` legend and refresh, workbook columns, stats lines, results column and CSV.
- **Browser (PostProduc)**: Load history on "Phase 3c browser check" fills Miles for every resolved lane (History or Approx); opening lane 1 draws the truck route with alternatives and stores Truck route miles on a lane without history; km toggle switches table, panel and Lane Benchmark together; a Lane Benchmark search draws the route; the Excel export has the new columns. Setting `Provider__c` to `Valhalla` without a server shows the unavailable message and saves nothing.
- The Apex roster (README, CI) gains the new test classes.

## 10. Rulings

- R70 — history miles are the median over every matched load row at the precision the history used (radius matches included).
- R71 — stored routes are keyed by ordered place pair and truck profile (provider included) and never expire; the pricer refreshes on demand.
- R72 — the unit toggle is shared through a Lightning message channel, so components in different parts of the page stay in step under Lightning Web Security.
- R73 — no backfill job; Load history and opening a lane fill existing lanes.
- R74 — place lookups on `Truck_Route__c` clear on delete instead of blocking it.
- R75 — History miles outrank a stored truck route: billed PC*Miler miles are what the company invoices on.
- R76 — the Approx factor is 1.2 from the measured median billed/straight-line ratio (D7), kept in the setting so it can be tuned without code.
- R77 — storing Mapbox routing results is the owner's decision (D3); nothing in the code depends on it, so a later change of mind only removes the save.
- R78 — the router seam is an Apex interface selected by custom metadata; the Valhalla adapter ships tested but off, against the request contract agreed with the Valhalla server project.
