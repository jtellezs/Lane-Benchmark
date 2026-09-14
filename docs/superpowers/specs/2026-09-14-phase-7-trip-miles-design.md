# Phase 7 — Trip miles and truck routes on every lane

Date: 2026-09-14. Roadmap: phase 7, after phase 6 and its follow-ups merged as
`bc4710b`. Adds the length of the trip, in miles with km on click, the rate per
mile, and a truck route drawn on the map wherever the app shows a lane: the RFP
workbench (table, lane panel, Excel export) and Lane Benchmark (statistics,
results, CSV, map). Routing starts on the public openrouteservice API and is
built to switch to Trans-Pro's own Valhalla server without changing the app.

## 1. Decisions (brainstorm, 2026-09-14)

| #   | Decision                                                                                                                                                                                                                                                                                                                                                                                                |
| --- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| D1  | A lane's miles, in order of preference: (1) the **median of Revenova's billed miles** (`rtms__Load__c.rtms__Distance_Miles__c`, PC*Miler) on the loads its history search matched; (2) a **stored truck route** for the same place pair and truck; (3) an **approximate** distance: the straight line between the two places × **1.2**, labelled "approx.".                                             |
| D2  | Truck routes come from **OpenStreetMap**. Now: the public **openrouteservice** API (`driving-hgv` profile with truck limits). Later: Trans-Pro's **self-hosted Valhalla** server, whose contract is fixed in the owner's server brief (`/Users/iulian/Documents/Personal/valhalla-server-project-prompt.md`). Mapbox routing is not used.                                                               |
| D3  | A truck route is requested **when a pricer opens a lane** (RFP lane panel) or **runs a Lane Benchmark search**, one route per request. With openrouteservice, Load history makes **no routing calls** (its matrix ignores truck limits and its free quota is 2,000 routes a day); it only reuses stored routes. With Valhalla, Load history fills truck miles in batches through `/sources_to_targets`. |
| D4  | The app **stores** the miles and the route lines it receives (owner decision). openrouteservice's terms contain no storage ban and license results CC-BY-SA 4.0; Valhalla is self-hosted on OpenStreetMap data (ODbL). The app shows the required credit wherever a route or its miles appear.                                                                                                          |
| D5  | Routes are drawn on the **existing Mapbox Static Images** map: the main truck route and, when the router returns them, up to two alternatives in different colours, with a legend of miles and hours. The image is built on each view and **never stored or proxied**. openrouteservice gives no alternatives for trips over 100 km, so alternatives appear once Valhalla is live.                      |
| D6  | Miles appear **everywhere a lane appears**: RFP lane table, lane panel (with a new route map), Excel export, cost and sell per mile, Lane Benchmark statistics, results, CSV and map.                                                                                                                                                                                                                   |
| D7  | **Miles by default, km on click**; each browser remembers the choice. The Excel export always carries both.                                                                                                                                                                                                                                                                                             |
| D8  | No backfill job. Out of scope: tolls, per-stop mileage, choosing a route for pricing, per-customer truck profiles. Production is not deployed (user decision).                                                                                                                                                                                                                                          |

## 2. Facts this design rests on (2026-09-14)

- **Billed miles.** `rtms__Distance_Miles__c` is filled on 53,054 of 54,480 loads created in the last 365 days (97 %). Revenova gets them from PC*Miler; its classes are "Type is not visible" to our Apex (check-only compile), so the app reads the field only.
- **Straight-line factor.** On 10,939 recent loads with stop coordinates, billed miles ÷ straight-line miles has a median of 1.196 (middle half 1.148–1.271); by country pair 1.17–1.25. Stop coordinates: `rtms__First_Stop__r` / `rtms__Last_Stop__r` → `rtms__Location2__r.ShippingLatitude/Longitude`.
- **Places.** 694 of the 712 sandbox RFP lanes have coordinates at both ends (`Pricing_Place__c.Geolocation__c`).
- **openrouteservice** (public API): `POST /v2/directions/driving-hgv/json` with `options.vehicle_type` = `hgv` and `options.profile_params.restrictions` (height, width, length in metres; weight, axleload in tonnes; `hazmat` true/false). No default truck dimensions: every limit must be sent. `units` = `mi`; geometry is an encoded polyline (precision 5); the summary gives distance and duration. Free Standard plan: 2,000 directions a day, 40 a minute; no SLA; no paid plan. Alternative routes only under 100 km. The matrix endpoint ignores truck restrictions. The key is sent in the `Authorization` header. Results are CC-BY-SA 4.0 with the credit "© openrouteservice by HeiGIT | Data from OpenStreetMap". The terms neither allow nor forbid company use in so many words.
- **Valhalla** (owner's server brief): one HTTPS base URL, header `X-Api-Key`; `POST /route` (costing `truck`, `costing_options.truck` height, width, length, weight, axle_load, axle_count, hazmat, use_truck_route; `units` = `miles`; `alternates` = 2; `format` = `osrm`; `shape_format` = `polyline5`); `POST /sources_to_targets` (the same truck costing, `units` = `miles`); `GET /status`. Default truck: 53 ft dry van, 80,000 lb (36.29 t), 13 ft 6 in (4.11 m), 102 in (2.6 m), length 21.64 m, axle load 9.07 t, 5 axles.
- **Mapbox Static Images**: path overlays take a precision-5 polyline with their own colour and width; URLs are limited to 8,192 characters; `auto` framing fits all overlays. Mapbox Product Terms forbid storing, proxying or screenshotting map images; no clause found against drawing another router's line. The token is already in the image URL the browser loads today (`MapboxGeocoder.staticMapUrl`).
- **OpenStreetMap truck data** is thin in North America (for example about 20,000 height-limit ways in Canada among 5.4 million road ways), so truck routes are best effort. Billed miles stay the first source.
- **Salesforce**: `LaneBenchmarkController.search` is cacheable (no DML or new callouts there); synchronous Apex has 6 MB of heap, 100 callouts and about 120 s of callout time per transaction; callouts must come before DML. `rfpTool.js` is at 554 of its 560-line ceiling; this phase adds no line to it.

## 3. Data model

**`RFP_Lane__c`** gains:

- `Miles__c` — Number(10, 1).
- `Miles_Source__c` — Picklist: `History`, `Truck route`, `Approx.`, `No coordinates`. Blank means history has not run since phase 7.

The history run and the lane route method write them in user mode after `Security.stripInaccessible(UPDATABLE)`, so `RFP_Tool_User` grants read and edit exactly like the `Hist_*` fields. A `Truck route` or `Approx.` value never overwrites `History`.

**New object `Truck_Route__c`** (label "Truck Route", Public Read Only, no tab): one stored route per place pair, router and truck.

- `Origin_Place__c`, `Destination_Place__c` — Lookups to `Pricing_Place__c`, not required, Set Null on delete.
- `Route_Key__c` — Text(120), External ID, Unique: `<origin place Id>:<destination place Id>:<router>:<truck key>`; the truck key is a short hash of the limits sent plus the hazmat flag.
- `Router__c` — Picklist: `openrouteservice`, `valhalla`.
- `Status__c` — Picklist: `Found`, `No route`.
- `Miles__c`, `Hours__c` — Number(10, 1) and Number(6, 1) for the main route.
- `Routes__c` — Long Text Area(131072): JSON list of up to 3 routes, each `{ miles, hours, polyline }`, polylines simplified to fit the map URL.
- `Checked_On__c` — Datetime.

Only Apex writes it, in system mode, with a justification comment. Both permission sets gain read on it. A row never expires; an admin deletes rows to re-ask. A row whose place was deleted is ignored.

**New custom metadata `Truck_Routing_Setting__mdt`**, record `Default`:

- `Router__c` (Text: `openrouteservice` or `valhalla`), `Named_Credential__c` (Text: `OpenRouteService` or `Valhalla`), `Enabled__c` (Checkbox).
- Truck: `Height_M__c` 4.11, `Width_M__c` 2.6, `Length_M__c` 21.64, `Weight_T__c` 36.29, `Axle_Load_T__c` 9.07, `Axle_Count__c` 5, `Use_Truck_Route__c` 0.5, `Alternates__c` 2.

**Named Credential `OpenRouteService`** (`https://api.openrouteservice.org`) with an External Credential that sends the key in `Authorization`; the admin enters the key in Setup, never in git. The `Valhalla` Named Credential (header `X-Api-Key`) is created by the admin when the server exists, from the server's handover note; the README runbook lists the values.

## 4. Apex

- **`TruckRouter`** (interface): `TruckRoute route(RouteRequest r)`; `Map<String, Decimal> matrixMiles(RouteMatrixRequest r)`; `Boolean supportsTruckMatrix()`; `Boolean supportsAlternatives()`; `String credit()`.
- **`OpenRouteServiceRouter`**: POST `callout:OpenRouteService/v2/directions/driving-hgv/json` with the truck limits from the setting and the lane's hazmat flag, `units` = `mi`, `instructions` = false; maps 400/404 "no route", 401/403 (key), 429 (quota) and 5xx to user sentences; `supportsTruckMatrix` and `supportsAlternatives` are false; credit "© openrouteservice by HeiGIT | Data from OpenStreetMap".
- **`ValhallaRouter`**: POST `callout:Valhalla/route` and `callout:Valhalla/sources_to_targets` exactly as the owner's server brief shows (costing `truck`, `format` = `osrm`, `shape_format` = `polyline5`, `alternates` from the setting); `supportsTruckMatrix` and `supportsAlternatives` are true; credit "© OpenStreetMap contributors". Built and unit-tested now against mocked responses; not enabled until the server exists.
- **`TruckRouters.current()`** reads `Truck_Routing_Setting__mdt.Default` and returns the router, or `null` when `Enabled__c` is false.
- **`TripMilesService`**:
  - `medianMiles(rows)` — median of load miles above zero, same median rule as `LaneSearchService`.
  - `approxMiles(Pricing_Place__c a, Pricing_Place__c b)` — great-circle miles × 1.2 (`CIRCUITY = 1.2`), rounded to whole miles; `null` without coordinates.
  - `storedRoutes(pairs, router, truckKey)` — reads `Truck_Route__c` by `Route_Key__c`.
  - `saveRoutes(...)` — upserts on `Route_Key__c` after the transaction's callouts.
- **`RouteMap`**: `String url(Pricing_Place__c origin, Pricing_Place__c destination, List<RouteLine> routes)` — Mapbox Static Images URL with pin `a` and pin `b`, the main route thick blue and alternatives amber and grey, `auto` framing, @2x; simplifies each polyline (Douglas–Peucker, tolerance raised until the URL is under 8,192 characters) and never includes anything but the public token already used.
- **History** (`LaneSearchQueryBuilder`, `LaneSearchResult`, `RfpHistoryService`): the query adds `rtms__Load__r.rtms__Distance_Miles__c`; rows carry `miles`; `LaneSearchResult` gains `medianMiles` and each `Stats` gains `ratePerMileMedian` (median of `carrierTotal ÷ miles` for that currency). `RfpHistoryService.run`, for each lane: `History` from `medianMiles`; else a stored `Truck_Route__c` for the lane's pair; else, when the current router `supportsTruckMatrix`, one `matrixMiles` call for the chunk's missing pairs (callout before DML) stored as `Truck route`; else `Approx.`. Unresolved lanes: `No coordinates`.
- **Live route**:
  - `RfpLaneController.truckRoute(Id laneId)` (new, `@AuraEnabled`, not cacheable): reads the lane in user mode; returns the stored route or asks the router once, stores it, updates the lane's miles when its source is not `History`, and returns `{ miles, hours, source, routes[{ miles, hours }], mapUrl, credit, message }`.
  - `LaneBenchmarkController.truckRoute(String originKey, String destinationKey, Boolean hazmat)` (new, not cacheable): the same for the searched places, without a lane update.
  - A disabled router, a missing key, a 429 or a failed callout returns the approximate miles, a map with the two pins and no line, and a one-sentence message; nothing is stored for that request.

## 5. What people see

- **`c/distanceUnit`** module (`mi`/`km`, key `tripMiles.unit.v1`, `formatDistance`, `perDistance`; 1 mi = 1.609344 km) and **`c-distance-unit-toggle`** ("mi | km", `aria-pressed`) sharing the choice on the Lightning message channel **`Distance_Unit__c`**.
- **RFP toolbar**: the toggle, next to Include RFP bids (in `rfpToolbar`).
- **RFP lane table**: a **Miles** column after History: "1,234 mi" (history), "1,234 mi" with a `truck` tag (stored truck route), "~1,234 mi" with an `approx.` tag, "—" for no coordinates; tooltip names the source.
- **Lane panel**: under the title, the miles and their source; **Cost per mile** and **Sell per mile** next to the prices, live; a **route map** loaded when the lane opens (calls `truckRoute`), with a legend of miles and hours per route and the credit line; a spinner while it loads and the message when routing is unavailable.
- **Excel export**: after "Transit days": Miles, Km, Miles source, Cost per mile, Sell per mile.
- **Lane Benchmark**: statistics header "Trip: 1,234 mi (median of N loads)" or "(truck route)" or "(approx.)"; **Rate per mile (median)** per currency; the existing map draws the truck route (calls `truckRoute` after a search) with its legend and credit; a **Miles** column in results and CSV (load rows: their load's miles; bid rows: "—"). The toggle sits in the statistics card header.
- **Help guide** (EN and FR): "Trip miles and truck routes" in `rfp-history`, `rfp-pricing` and `lb-stats`, including what "approx." and "truck" mean and that routes follow OpenStreetMap truck data; the static resource is rebuilt.

## 6. Limits, terms, operations

- **Quota**: openrouteservice allows 2,000 routes a day and 40 a minute. Routes are requested only on a person's action, stored, and reused by every lane and search with the same pair and truck; a 429 shows "Routing limit reached; try again later." and keeps the approximate miles.
- **Terms and credit**: openrouteservice results are CC-BY-SA 4.0; OpenStreetMap data is ODbL. The credit line is shown under every route map and in the lane panel; the Excel export adds it in a footer row. Sharing stored miles or routes outside Trans-Pro (customer files, carrier portals) may add attribution and share-alike duties: a legal read before doing so. Mapbox images are never stored, proxied or pre-generated. Two open questions for the owner, not blocking: HeiGIT's written confirmation of company use on the free key; a legal read of Mapbox §1.13 (share-alike data) for CC-BY-SA route lines drawn on its images.
- **Keys**: openrouteservice keys belong to one person; the admin creates it with a shared company mailbox and stores it only in the External Credential.
- **Switching to Valhalla** (runbook in the README): create the `Valhalla` Named Credential from the server's handover note, set `Router__c` = `valhalla` and `Named_Credential__c` = `Valhalla` on the `Default` setting, deploy or edit in Setup. Stored openrouteservice routes stay; new requests use the new router key, so lanes are re-routed as they are opened, and Load history fills missing truck miles in batches.
- **Callouts**: one route per `truckRoute` call; one matrix per 10-lane history chunk with Valhalla (at most 10 × 10); per-callout timeout 20 s.

## 7. Testing

- **Apex** (new `TripMilesServiceTest`, `OpenRouteServiceRouterTest`, `ValhallaRouterTest`, `RouteMapTest`; extended `RfpHistoryServiceTest`, `LaneSearchServiceTest`, `LaneBenchmarkControllerTest`, `RfpLaneControllerTest`, `RfpSecurityTest`): median and approximate miles; source order History → stored route → Valhalla matrix → Approx.; `History` never overwritten; openrouteservice request body (limits in metres and tonnes, hazmat, units) and error mapping (400/404, 401/403, 429, 5xx); Valhalla `/route` and `/sources_to_targets` bodies match the server brief's examples and responses parse (routes, alternates, miles, polyline5); a stored route makes no callout; the router switch through the setting; disabled router and missing key fall back to approx. with nothing stored; the map URL stays under 8,192 characters for a 3,000 km route and three lines; callouts before DML in the history run and in `truckRoute`; an RFP Tool user can call `truckRoute` on a lane they can read and gets `This lane is not available.` on one they cannot. `LaneSearchServiceTest`'s governor-sensitive method keeps its setup outside `Test.startTest`.
- **Jest**: `distanceUnit`; toggle on the channel; table column and tags; panel per-mile values, route map, legend, credit and fallback message; workbook columns and credit row; Lane Benchmark header, rate per mile, map legend, results column and CSV.
- **Browser (PostProduc)**, after the admin enters a test openrouteservice key: Load history fills Miles on every resolved lane (history or approx.); opening a lane draws a truck route and changes its tag to `truck`; reopening makes no new request (stored); a hazmat lane shows its own route; the km toggle switches table, panel and Lane Benchmark together; a Lane Benchmark search draws the route; the Excel export has the new columns and the credit row.
- The Apex test roster (README, CI) gains the four new test classes.

## 8. Rulings

- R70 — the lane's miles are the median over every matched load row at the precision the history used (radius matches included).
- R71 — the approximate distance is great-circle miles × 1.2, measured on Trans-Pro's own loads; one factor for every country pair (by-pair factors ranged 1.17–1.25).
- R72 — stored routes are keyed by ordered place pair, router and truck; direction matters and a different truck or hazmat flag is a different route.
- R73 — no automated routing calls with openrouteservice (quota and bulk-use limits); batch routing waits for Valhalla.
- R74 — place lookups on `Truck_Route__c` clear on delete instead of blocking it.
- R75 — the unit toggle is shared through a Lightning message channel, so components in different parts of the page stay in step under Lightning Web Security.
- R76 — storing routing miles and route lines is the owner's decision; openrouteservice's terms do not forbid it and Valhalla is self-hosted, while Mapbox images stay unstored.
