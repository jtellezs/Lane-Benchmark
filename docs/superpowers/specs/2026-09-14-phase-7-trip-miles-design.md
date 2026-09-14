# Phase 7 — Trip miles and truck routes on every lane

Date: 2026-09-14. Roadmap: phase 7, after phase 6 and its follow-ups merged as
`bc4710b`. Adds the length of the trip (miles, km on click), the rate per mile
and a truck route drawn on the map, wherever the app shows a lane: the RFP
workbench (table, lane panel, Excel export) and Lane Benchmark (statistics,
results, CSV, map). Three sources only: Revenova's billed miles, Mapbox truck
routes and an approximate distance from the two places' coordinates.

## 1. Decisions (brainstorm and research, 2026-09-14)

| #   | Decision                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          |
| --- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| D1  | A lane's miles come from, in order: **History** — the median of Revenova's billed Distance (Miles) (`rtms__Load__c.rtms__Distance_Miles__c`, filled by PC*Miler) on the loads its history search matched; **Route** — the miles of the Mapbox route stored for the lane's two places (a truck route, or a regular route when the truck route breaks a truck limit); **Approx** — the straight-line distance between the two places' coordinates × 1.2.                                            |
| D2  | Routing is **Mapbox only**: the Directions API, driving profile with the truck's height, width and weight, alternatives on. **If the truck route breaks a truck limit or no truck route is found, the app asks again for a regular driving route (no truck limits) and uses that, labelled as a regular route.** Keep it simple now; finer truck handling can come later (owner, 2026-09-14). openrouteservice and a self-hosted Valhalla server were considered and dropped (owner, 2026-09-14). |
| D3  | The truck route is fetched **when a pricer opens a lane** in the RFP workbench or **runs a Lane Benchmark search**, once per place pair and truck profile; the result is **stored** and reused. Storing Mapbox routing results is the **owner's decision**, taken after the Mapbox Product Terms clause against caching or storing Navigation API results (§2.10.1) was raised.                                                                                                                   |
| D4  | **Load history** fills every resolved lane without calling Mapbox: history miles when matched loads have miles; otherwise the stored route miles for the lane's place pair; otherwise Approx. Mapbox's Matrix API takes no truck limits, and routing is only ever requested by a person's action.                                                                                                                                                                                                 |
| D5  | The map is the **existing Mapbox static image**: pins for the two places, the main route as a thick line and up to two alternatives in other colours, with a legend of miles and hours per route. No interactive map (Mapbox GL JS is blocked by Lightning Web Security).                                                                                                                                                                                                                         |
| D6  | **Miles by default, km on click**, remembered per browser, shared by every component on the page. Rate per mile (per km) wherever a price and miles meet. The Excel export always carries miles and km.                                                                                                                                                                                                                                                                                           |
| D7  | The Approx factor **1.2** is measured, not guessed: on 10,939 PostProduc loads from the last year, billed miles ÷ straight-line miles has a median of 1.196 (middle half 1.148 to 1.271), stable across country pairs and trip lengths.                                                                                                                                                                                                                                                           |
| D8  | Out of scope: any other routing provider, partial or best-effort truck routes (a route that breaks a limit is replaced by a regular route), hazmat routing (Mapbox has no parameter), truck length or axle limits (no Mapbox parameters), tolls, per-stop mileage, a background backfill job. Production is not deployed (owner decision).                                                                                                                                                        |

## 2. Today (measured, 2026-09-14)

- Billed miles: `rtms__Distance_Miles__c` is filled on 53,054 of 54,480 loads created in the last 365 days (97 %). Revenova's mileage classes (`rtms.MileageAPI`, `rtms.PCMilerAPI`, …) are "Type is not visible" to our Apex (check-only compile), so PC*Miler cannot be called directly.
- History rows come from `rtms__CarrierQuote__c` through `LaneSearchQueryBuilder.SELECT_CLAUSE`; `RfpHistoryService.run` handles at most 10 lanes per call. 694 of 712 sandbox RFP lanes have coordinates at both ends (`Pricing_Place__c.Geolocation__c`).
- Mapbox: token `TPRO_KPI__c.Mapbox_Api_Key__c` (public `pk.` token), remote site `MapBox`, CSP trusted site `Mapbox_API` (img-src). `MapboxGeocoder` does forward geocoding and builds the static map URL (`staticMapUrl`, GeoJSON overlay, 600×300). `LaneBenchmarkController.search` and `mapPreviewUrl` are cacheable, so anything that calls out and saves needs its own method.
- Mapbox Directions API: profiles `mapbox/driving` and `mapbox/driving-traffic`; `max_height` and `max_width` in metres (0–10), `max_weight` in metric tons (0–100), best-effort with regional coverage and violation notifications; no truck profile, no hazmat, no length or axle parameters; `alternatives=true` returns up to two alternatives (the docs contradict themselves on whether that is two or three routes in total); distance in metres, duration in seconds, geometry as a 5-decimal polyline by default with `overview=simplified`; 300 requests per minute; billed per request. The Matrix API accepts none of the truck parameters.
- Mapbox Static Images API: several path overlays per image (`path-{width}+{colour}-{opacity}({polyline})`), `auto` framing, 8,192-character URL limit.
- `rfpTool.js` is at 554 of its 560-line ceiling; this phase adds no line to it.

## 3. Mapbox truck routes

**`MapboxTruckRoute`** (new Apex class): `TruckRoute.Result route(TruckRoute.Point origin, TruckRoute.Point destination, TruckRoute.Profile profile)` — `GET /directions/v5/mapbox/driving/{lon},{lat};{lon},{lat}?alternatives=true&overview=simplified&geometries=polyline&max_height=&max_width=&max_weight=&access_token=`; up to 3 routes, each `{ miles, hours, polyline5 }`, main route first; `routeType` `Truck` or `Regular`; status `Found`, `No route` or `Unavailable`; metres to miles and seconds to hours. **Fallback:** when the main truck route carries a truck-limit violation notification (`maxHeight`, `maxWidth` or `maxWeight`) or Mapbox answers `NoRoute`, a second request without `max_height`, `max_width` and `max_weight` is sent and its routes are returned with `routeType` `Regular`; if that also finds nothing, the status is `No route`. At most two callouts per call. It reuses `MapboxGeocoder`'s token read and one-retry send, moved into a small shared `MapboxHttp` helper. The token is never logged or put in a thrown message.

**`TruckRoute`** (value types): `Point`, `Profile` (built from the setting below) and `profileKey` — the rounded height, width and weight — so a change of truck never reuses an old route. The key is the same for the truck request and its regular fallback, so one stored row answers the place pair either way.

**Configuration**: `Truck_Routing_Setting__mdt` (new), record `Default`: `Height_M__c` 4.11, `Width_M__c` 2.6, `Weight_T__c` 36.29, `Alternatives__c` (checkbox, on), `Approx_Factor__c` 1.2, `Timeout_Ms__c` 8000. The defaults describe a 53 ft dry-van tractor-trailer at 80,000 lb, 13 ft 6 in high, 102 in wide.

## 4. Data model

**`RFP_Lane__c`** gains:

- `Miles__c` — Number(10, 1).
- `Miles_Source__c` — Picklist: `History`, `Truck route`, `Regular route`, `Approx`, `No route`, `No coordinates`.
- `Route_Hours__c` — Number(6, 1), drive hours of the stored route; blank for History and Approx.

`RFP_Tool_User` grants read and edit on the three fields, like the `Hist_*` fields (the history run writes lanes in user mode after `Security.stripInaccessible(UPDATABLE)`; a missing grant would silently drop the miles). `Lane_Benchmark_User` has no lane permissions and needs none.

**`Truck_Route__c`** (new, label "Truck Route", Public Read Only, no tab):

- `Origin_Place__c`, `Destination_Place__c` — Lookups to `Pricing_Place__c`, not required, delete constraint Set Null (like every place lookup in the app); rows with a blank place are ignored.
- `Profile_Key__c` — Text(80).
- `Route_Key__c` — Text(160), External ID, Unique: `<origin Id>:<destination Id>:<profileKey>`.
- `Miles__c` — Number(10, 1), main route; `Hours__c` — Number(6, 1).
- `Route_Type__c` — Picklist `Truck`, `Regular`.
- `Status__c` — Picklist `Found`, `No route`.
- `Routes_Json__c` — Long Text Area(131072): up to 3 routes `{ miles, hours, polyline5 }`, main first, for redrawing the map without a new request.
- `Checked_On__c` — Datetime.

Only `TripMilesService` writes it, in system mode with a justification comment. Both permission sets gain read. A row never expires; the lane panel's **Refresh route** action replaces it (one new request). Direction matters: A→B and B→A are separate rows.

## 5. Apex behaviour

**`TripMilesService`** (new):

- `Decimal medianMiles(List<LaneSearchResult.Row> rows)` — median of `miles` over rows above zero, same rule as `LaneSearchService` (odd count middle value, even count mean of the two middle values).
- `Decimal approxMiles(Pricing_Place__c o, Pricing_Place__c d)` — great-circle miles (Earth radius 3,958.7613 mi) × `Approx_Factor__c`, one decimal; `null` without coordinates.
- `TruckRoute.Result storedOrRoute(Pricing_Place__c o, Pricing_Place__c d, TruckRoute.Profile p, Boolean refresh)` — a saved `Truck_Route__c` wins unless `refresh`; otherwise one Mapbox route call (two with the regular fallback). Returns the result and the row to save; the caller saves after its callouts.
- `void save(List<Truck_Route__c> rows)` — upsert on `Route_Key__c`.

**Lane history** (`LaneSearchQueryBuilder`, `LaneSearchResult`, `LaneSearchService`, `RfpHistoryService`):

- `SELECT_CLAUSE` adds `rtms__Load__r.rtms__Distance_Miles__c`; `LaneSearchResult.Row` gains `miles` (bid rows `null`); `LaneSearchResult` gains `medianMiles`; `LaneSearchResult.Stats` gains `ratePerMileMedian` (median of `carrierTotal / miles` over that currency's rows with both above zero).
- `RfpHistoryService.run`, after its searches: each lane with `medianMiles` takes it (`History`); otherwise a stored `Truck_Route__c` for its place pair and the current profile (`Truck route` or `Regular route` from its `Route_Type__c`, with its hours); otherwise `Approx`, or `No coordinates`. No callout. One extra query per call reads the stored routes for the chunk's pairs.

**On demand**

- `RfpLaneController.laneRoute(Id laneId, Boolean refresh)` (`@AuraEnabled`, not cacheable): reads the lane in user mode; if it has resolved places, calls `storedOrRoute`; saves the store row after the callouts; when the lane's source is not `History`, writes `Miles__c` (main route), `Miles_Source__c` = `Truck route` or `Regular route`, `Route_Hours__c`; returns `{ routes[], mapUrl, source, message }`.
- `LaneBenchmarkController.truckRoute(String originKey, String destinationKey, Boolean refresh)` (`@AuraEnabled`, not cacheable): resolves the two places, `storedOrRoute`, save, returns `{ routes[], mapUrl, message }`. The page calls it after a search; the cacheable `search` is unchanged apart from the new row and statistics fields.

**Map URL** (`RouteMapUrl`, new, next to `MapboxGeocoder.staticMapUrl`): `pin-s-a+0070d2` and `pin-s-b+2e844a` for the places, the main route `path-5+0070d2-0.9`, alternatives `path-3+f59e0b-0.8` and `path-3+706e6b-0.7`; `auto` framing, 600×300 @2x. If the URL would pass 8,000 characters, Apex simplifies each line (Douglas–Peucker, growing tolerance) and re-encodes it until it fits; if it still does not fit, alternatives are dropped before the main route. The Lane Benchmark radius circles stay when a radius search is shown. The image is built on each view and never stored.

## 6. What people see

A shared LWC module **`c/distanceUnit`** holds the unit (`mi` default, `km`; localStorage key `tripMiles.unit.v1`, guarded), `formatDistance(miles, unit)`, `perDistance(amount, miles, unit)` (1 mi = 1.609344 km). **`c-distance-unit-toggle`** ("mi | km", `aria-pressed`) publishes on the Lightning message channel **`Distance_Unit__c`**. A shared **`c-route-map`** shows the image, a legend ("Truck route" or "Regular route — truck limits could not be met", then each route's miles or km and hours) and a Refresh route button.

- **RFP toolbar**: the unit toggle next to Include RFP bids (`rfpToolbar`).
- **RFP lane table**: a **Miles** column after History — the value with a small tag: none for History, `truck` for Truck route, `route` for Regular route, `approx.` for Approx; "—" with the reason as a tooltip otherwise.
- **Lane panel**: miles and source under the lane title; **Cost per mile** and **Sell per mile** next to the prices, live as the pricer types; `c-route-map` below, loaded on open through `laneRoute` (a spinner while it loads; a short message if the route is unavailable).
- **Excel export** (`rfpWorkbook` lane sheet): Miles, Km, Miles source, Route hours, Cost per mile, Sell per mile.
- **Lane Benchmark statistics**: "Trip: 1,234 mi · median of N loads" and "Truck route: 1,260 mi · 21.5 h" (or "Regular route: …"); **Rate per mile (median)** per currency; the toggle in the card header.
- **Lane Benchmark map**: `c-route-map` replaces the plain preview when a truck route is available; the radius preview stays otherwise.
- **Lane Benchmark results**: a **Miles** column (load miles; bid rows "—") and the CSV column.
- **Help guide** (EN and FR): "Trip miles and truck routes" in `rfp-history`, `rfp-pricing` and `lb-stats`, the table column in `rfp-inline`; the resource is rebuilt.

## 7. Limits, errors, cost

- One on-demand route is one callout, or two when the truck route breaks a limit and the regular route is asked; always before the transaction's DML. The timeout is 8 s per callout (setting), so at most 16 s, well inside the 120 s cumulative callout limit. Load history makes no callout.
- Mapbox Directions: 300 requests per minute, billed per request; each place pair and truck profile is requested once, then served from `Truck_Route__c` until a pricer refreshes it. The static map image is billed per view as today.
- A missing token, an HTTP error or a timeout returns `Unavailable`: nothing is saved, the lane keeps its current miles, the panel says "The truck route is not available right now."
- Mapbox finds no route even without truck limits (for example across water): saved as `No route`, shown as "—".
- Mapbox truck limits are best effort: when the main truck route comes back with a violation notification, the app drops it and uses the regular route instead (D2); no partially compliant truck route is ever shown or stored.
- Hazmat lanes get the same route as other lanes (Mapbox has no hazmat parameter); the legend says so on a hazmat lane.

## 8. Testing

- **Apex**: `TripMilesServiceTest` (median rules; approx math and factor; a stored route makes no callout — `Limits.getCallouts()` stays 0; refresh replaces the row; a missing place is ignored; the profile key changes with any truck value), `MapboxTruckRouteTest` (the first request carries the truck values and alternatives; metres→miles, seconds→hours; up to 3 routes; a main route with a `maxHeight`, `maxWidth` or `maxWeight` violation triggers a second request without truck values and returns `Regular`; a truck `NoRoute` also falls back; regular `NoRoute` gives `No route`; at most two callouts; HTTP 401 and timeout → Unavailable; token never in a thrown message), `RouteMapUrlTest` (overlays and colours; a long route is simplified under 8,000 characters; alternatives dropped as a last resort), extended `RfpHistoryServiceTest` (History > stored Truck or Regular route > Approx > No coordinates; no callout), `LaneSearchServiceTest` (row miles, median miles, rate per mile; its governor-sensitive method keeps setup outside `Test.startTest`), `RfpLaneControllerTest` and `LaneBenchmarkControllerTest` (on-demand routes, saved, lane written only when not History, callout before DML), `RfpSecurityTest` (an RFP Tool user opens a lane route; a Lane Benchmark user gets a truck route; a stranger without the lane gets the existing unavailable-lane error).
- **Jest**: `distanceUnit`, the toggle and channel, table column tags, panel per-mile values, `c-route-map` legend and refresh, workbook columns, stats lines, results column and CSV.
- **Browser (PostProduc)**: Load history on "Phase 3c browser check" fills Miles for every resolved lane (History or Approx); opening a lane without history draws the truck route with alternatives and stores Truck route miles (a lane whose truck route breaks a limit shows and stores a regular route); reopening makes no new request; km toggle switches table, panel and Lane Benchmark together; a Lane Benchmark search draws the route; the Excel export has the new columns.
- The Apex roster (README, CI) gains the new test classes.

## 9. Rulings

- R70 — history miles are the median over every matched load row at the precision the history used (radius matches included).
- R71 — stored routes are keyed by ordered place pair and truck profile and never expire; the pricer refreshes on demand.
- R72 — the unit toggle is shared through a Lightning message channel, so components in different parts of the page stay in step under Lightning Web Security.
- R73 — no backfill job and no routing during Load history; opening a lane or searching fills truck routes.
- R74 — place lookups on `Truck_Route__c` clear on delete instead of blocking it.
- R75 — History miles outrank a stored truck route: billed PC*Miler miles are what the company invoices on.
- R76 — the Approx factor is 1.2 from the measured median billed/straight-line ratio (D7), kept in the setting so it can be tuned without code.
- R77 — storing Mapbox routing results is the owner's decision (D3); nothing else in the code depends on it, so a later change of mind only removes the save.
- R78 — one routing provider (Mapbox), no provider interface: other providers were dropped by the owner, so the seam would be unused code.
- R79 — a truck route that breaks a truck limit, or no truck route at all, is replaced by a regular driving route, labelled as such; best-effort truck routes are never shown (owner: keep it simple, add complexity later).
