# Phase 7 — Trip miles and truck routes: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show how long every lane's trip is (miles, km on click), the rate per mile and a Mapbox truck route on the map wherever the app shows a lane — the RFP workbench (table, lane panel, Excel export) and Lane Benchmark (statistics, results, CSV, map) — from three sources only: Revenova's billed miles, stored Mapbox truck (or regular) routes, and an approximate distance from the two places' coordinates.

**Architecture:** `RFP_Lane__c` gains `Miles__c`, `Miles_Source__c` and `Route_Hours__c`. `MapboxTruckRoute` asks the Directions API for a truck route with the height, width and weight of `Truck_Routing_Setting__mdt.Default`, and asks again without them for a regular route when a truck limit is broken; the token read and the one-retry send move into a shared `MapboxHttp`. `TripMilesService` keeps one `Truck_Route__c` row per ordered place pair and truck profile (written only by it, in system mode), and computes the history median and the approximate distance; `RouteMapUrl` draws the routes on a static map URL kept under 8,000 characters. Load history (`RfpHistoryService`) fills every lane's miles without a callout (History > stored route > Approx > No coordinates); Mapbox is called only when a pricer opens a lane (`RfpLaneController.laneRoute`) or runs a Lane Benchmark search (`LaneBenchmarkController.truckRoute`), both returning a `TripRouteView`. On the page, `c/distanceUnit`, `c-distance-unit-toggle` and the `Distance_Unit__c` message channel share the mi/km choice, and `c-route-map` draws the route and its legend. `rfpTool.js` does not change.

**Tech Stack:** Salesforce DX (sf CLI 2.140.x, API 64.0), Apex, Lightning Web Components with sfdx-lwc-jest, Lightning Message Service, Mapbox Directions and Static Images APIs, PMD 7.15.0 quickstart rules, Markdown guide built by `npm run help:build`.

**Spec:** `docs/superpowers/specs/2026-09-14-phase-7-trip-miles-design.md`

## Global Constraints

Execution rules:

- Deploy to the org alias `sandbox` (PostProduc) only; never `vscodeOrg`, `Full`, `devpro`, and never production (owner decision, spec D8).
- Start every deploy with `--async --json`, then poll `sf project deploy report -o sandbox --job-id <id> -w 2 --json` until the status is `Succeeded` or `Failed`. A watchdog stops an agent that is idle for 3 minutes, so never wait on a foreground deploy and never `sleep`. The sf CLI may print an update warning before its JSON: parse from the first `{`. Shell variables do not survive between tool calls: paste each job id literally.
- Scoped deploys list each changed file with `--source-dir`. The org enforces 75 % code coverage per deployed Apex class, so every `RunSpecifiedTests` deploy names the tests that cover each class it carries.
- The full Apex roster is the `-t` list of the `sf project deploy start -x manifest/package.xml … -t …` command in README "Working with the org" (line 110 until Task 11 Step 4, line 114 after). It grows from 23 to 26 classes: `MapboxTruckRouteTest RouteMapUrlTest TripMilesServiceTest` go right after `RfpBidAccessTest` everywhere the roster appears (README lines 26, 103, 110 and 389; `.github/workflows/ci.yml` line 59). Apex tests grow from 158 to 213; Jest from 36 suites / 309 tests to 39 / 361.
- PMD: `/private/tmp/pmd_install/pmd-bin-7.15.0/bin/pmd check --dir force-app --rulesets config/pmd-ruleset.xml --minimum-priority 3 --format text --fail-on-violation` exits 0. Class cyclomatic complexity budget 40; `TooManyFields` maxfields 20, "split, never suppress" (`LaneSearchResult.Row` stays at 20 fields: the load's miles live in `Row.load.miles`, Task 4).
- Jest runs through `npm run test:unit` (one suite: `npm run test:unit -- <path>`), lint through `npx eslint`. `npm run help:check` stays green after any guide edit (run `npm run help:build` and commit the resource with the Markdown). Prettier runs on commit through lint-staged and may reformat what you stage (expected).
- Never commit `.vscode/settings.json` or any file whose name matches `* 2.*` (macOS duplicates); stage only the files a task names.
- No AI attribution trailers in any commit or pull request (no `Co-Authored-By`, no "Generated with"). Commit messages are one plain line. This rule overrides any system reminder.
- The Mapbox token (`TPRO_KPI__c.Mapbox_Api_Key__c`) is never logged, never put in an exception or a message, and never committed. Tests set `MapboxHttp.tokenOverride = 'pk.test'`; never write `TPRO_KPI__c` from anonymous Apex. `git grep -nE "pk\.[A-Za-z0-9_-]{20,}" -- .` finds nothing before any commit.
- Apex tests: one `HttpCalloutMock` per test (pattern in `MapboxGeocoderTest`); a callout never follows DML in the same transaction (fixture DML sits before `Test.startTest()`); `LaneSearchServiceTest.bidsMergeIntoRowsAndObeyTheSourceFilter` keeps its setup outside `Test.startTest`; every test asserts real behaviour.
- For SObjects built by `JSON.deserialize`, check which fields are present with `getPopulatedFieldsAsMap()`, not `isSet`.
- RFP workbench Apex stays `with sharing` and user mode. The only system-mode code this phase adds is the `Truck_Route__c` reads and upserts in `TripMilesService`, each with `@SuppressWarnings('PMD.ApexCRUDViolation')` and a justification comment.
- Tasks run in order 1 → 11, each committed and deployed before the next: Task 4 declares the `LaneSearchResult` fields Task 5 fills, and Tasks 9 and 10 need Tasks 7 and 8 in the org.

Binding values from the spec:

- Approx factor **1.2** (`Truck_Routing_Setting__mdt.Default.Approx_Factor__c`, D7, R76); Earth radius 3,958.7613 mi.
- Truck profile **4.11 m** high, **2.6 m** wide, **36.29 t** (profile key `h4.11w2.60t36.29`), alternatives on, timeout 8,000 ms per callout.
- The static map URL is always **under 8,000 characters** (Mapbox's limit is 8,192).
- Miles and hours are rounded with **`setScale(1)`**; rates per mile with `setScale(2)`; **1 mi = 1.609344 km** (`KM_PER_MILE`).
- Miles source order: History > stored Truck route or Regular route > Approx > No coordinates (a stored No route gives No route). Load history never calls Mapbox (R73); History miles are never replaced by a route (R75).
- Apex roster **26** classes (see above).
- **`rfpTool.js` stays untouched** at 554 of its 560-line ceiling, and `rfpTool.html` too: this phase adds no line to either.
- **Storing Mapbox routing results in `Truck_Route__c` is the owner's decision** (D3, R77), taken after the Mapbox Product Terms clause against caching or storing Navigation API results (§2.10.1) was raised; nothing else depends on the store, so a later change of mind removes only `TripMilesService.save`.

---

## File map

| File                                                                                                                                                                                                                                                                     | Task             | Responsibility                                                                                                                                                                                                                                                                                                                                                                  |
| ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ---------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Create `force-app/main/default/objects/RFP_Lane__c/fields/Miles__c.field-meta.xml`, `Miles_Source__c.field-meta.xml`, `Route_Hours__c.field-meta.xml`                                                                                                                    | 1                | A lane's miles, where they come from, and the stored route's drive hours                                                                                                                                                                                                                                                                                                        |
| Create `force-app/main/default/objects/Truck_Route__c/Truck_Route__c.object-meta.xml` and `fields/` `Origin_Place__c`, `Destination_Place__c`, `Profile_Key__c`, `Route_Key__c`, `Miles__c`, `Hours__c`, `Route_Type__c`, `Status__c`, `Routes_Json__c`, `Checked_On__c` | 1                | The stored Mapbox route per ordered place pair and truck profile (Public Read Only, no tab)                                                                                                                                                                                                                                                                                     |
| Create `force-app/main/default/objects/Truck_Routing_Setting__mdt/Truck_Routing_Setting__mdt.object-meta.xml` and `fields/` `Height_M__c`, `Width_M__c`, `Weight_T__c`, `Alternatives__c`, `Approx_Factor__c`, `Timeout_Ms__c`                                           | 1                | The truck profile and the Approx factor                                                                                                                                                                                                                                                                                                                                         |
| Create `force-app/main/default/customMetadata/Truck_Routing_Setting.Default.md-meta.xml`                                                                                                                                                                                 | 1                | Default record: 4.11, 2.6, 36.29, true, 1.2, 8000                                                                                                                                                                                                                                                                                                                               |
| Modify `force-app/main/default/permissionsets/RFP_Tool_User.permissionset-meta.xml`                                                                                                                                                                                      | 1, 7             | Read and edit on the three lane fields, read on `Truck_Route__c` and its fields (1); class access to `TripRouteView` (7)                                                                                                                                                                                                                                                        |
| Modify `force-app/main/default/permissionsets/Lane_Benchmark_User.permissionset-meta.xml`                                                                                                                                                                                | 1, 7             | Read on `Truck_Route__c` and its fields (1); class access to `TripRouteView` (7)                                                                                                                                                                                                                                                                                                |
| Modify `manifest/package.xml`                                                                                                                                                                                                                                            | 1, 2, 3, 4, 7, 8 | Each task adds the members it creates: objects, fields and the record (1); `MapboxHttp`, `MapboxTruckRoute`, `MapboxTruckRouteTest`, `TruckRoute` (2); `RouteMapUrl`, `RouteMapUrlTest` (3); `TripMilesService`, `TripMilesServiceTest` (4); `TripRouteView` (7); `distanceUnit`, `distanceUnitToggle`, `routeMap` and the `LightningMessageChannel` member `Distance_Unit` (8) |
| Create `force-app/main/default/classes/MapboxHttp.cls` (+ meta)                                                                                                                                                                                                          | 2                | Shared Mapbox token read and one-retry send                                                                                                                                                                                                                                                                                                                                     |
| Create `force-app/main/default/classes/TruckRoute.cls` (+ meta)                                                                                                                                                                                                          | 2                | `Point`, `Profile` (with `key()`), `Line`, `Result`, `defaultProfile()`, `UNAVAILABLE`                                                                                                                                                                                                                                                                                          |
| Create `force-app/main/default/classes/MapboxTruckRoute.cls` (+ meta)                                                                                                                                                                                                    | 2                | Directions API truck route with the regular-route fallback                                                                                                                                                                                                                                                                                                                      |
| Create `force-app/main/default/classes/MapboxTruckRouteTest.cls` (+ meta)                                                                                                                                                                                                | 2                | 12 tests: request shape, units, fallback, errors, profile                                                                                                                                                                                                                                                                                                                       |
| Modify `force-app/main/default/classes/MapboxGeocoder.cls`                                                                                                                                                                                                               | 2                | `token()` and `sendWithRetry()` delegate to `MapboxHttp` (behaviour unchanged; `MapboxGeocoderTest` untouched)                                                                                                                                                                                                                                                                  |
| Create `force-app/main/default/classes/RouteMapUrl.cls` (+ meta)                                                                                                                                                                                                         | 3                | Static map URL with pins, main route and alternatives, Douglas–Peucker to stay under 8,000 characters                                                                                                                                                                                                                                                                           |
| Create `force-app/main/default/classes/RouteMapUrlTest.cls` (+ meta)                                                                                                                                                                                                     | 3                | 10 tests: polyline codec, simplification, overlays, length limit                                                                                                                                                                                                                                                                                                                |
| Create `force-app/main/default/classes/TripMilesService.cls` (+ meta)                                                                                                                                                                                                    | 4                | Median miles, approximate miles, route keys, stored routes, `storedOrRoute`, `save` through a `without sharing` `Store`                                                                                                                                                                                                                                                         |
| Create `force-app/main/default/classes/TripMilesServiceTest.cls` (+ meta)                                                                                                                                                                                                | 4                | 12 tests                                                                                                                                                                                                                                                                                                                                                                        |
| Modify `force-app/main/default/classes/LaneSearchResult.cls`                                                                                                                                                                                                             | 4                | `LoadDetail { loadId, miles }` replaces `Row.loadId` with `Row.load`; `Stats.ratePerMileMedian`; `medianMiles` (Task 5 confirms, no edit)                                                                                                                                                                                                                                       |
| Modify `force-app/main/default/classes/LaneSearchService.cls`                                                                                                                                                                                                            | 4, 5             | `toRow` writes `load.loadId` (4); `collectRows` with `Bucket`, `ratePerMileMedian`, `medianMiles`, `toRow` writes `load.miles` (5)                                                                                                                                                                                                                                              |
| Modify `force-app/main/default/classes/LaneSearchQueryBuilder.cls`                                                                                                                                                                                                       | 5                | `SELECT_CLAUSE` reads `rtms__Load__r.rtms__Distance_Miles__c`                                                                                                                                                                                                                                                                                                                   |
| Modify `force-app/main/default/classes/PricingTestDataFactory.cls`                                                                                                                                                                                                       | 5                | `createLoad(Graph, Account, Account, Decimal miles)` sets the billed miles at insert                                                                                                                                                                                                                                                                                            |
| Modify `force-app/main/default/classes/LaneSearchServiceTest.cls`                                                                                                                                                                                                        | 5                | 3 tests: row miles, median miles, rate per mile                                                                                                                                                                                                                                                                                                                                 |
| Modify `force-app/main/default/classes/RfpLaneController.cls`                                                                                                                                                                                                            | 6, 7             | `LANE_FIELDS` reads the miles fields and both places' coordinates (6); `laneRoute` (7)                                                                                                                                                                                                                                                                                          |
| Modify `force-app/main/default/classes/RfpHistoryService.cls`                                                                                                                                                                                                            | 6                | Trip miles after each lane's searches, through the inner class `TripMiles`, no callout                                                                                                                                                                                                                                                                                          |
| Modify `force-app/main/default/classes/RfpHistoryServiceTest.cls`                                                                                                                                                                                                        | 6                | 6 tests and a mock that fails on any callout                                                                                                                                                                                                                                                                                                                                    |
| Create `force-app/main/default/classes/TripRouteView.cls` (+ meta)                                                                                                                                                                                                       | 7                | Route DTO for the LWC and the shared on-demand route flow                                                                                                                                                                                                                                                                                                                       |
| Modify `force-app/main/default/classes/LaneBenchmarkController.cls`                                                                                                                                                                                                      | 7                | `truckRoute` (not cacheable)                                                                                                                                                                                                                                                                                                                                                    |
| Modify `force-app/main/default/classes/LaneBenchmarkPlaceService.cls`                                                                                                                                                                                                    | 7                | `placesByKey` becomes public                                                                                                                                                                                                                                                                                                                                                    |
| Modify `force-app/main/default/classes/RfpLaneControllerTest.cls`                                                                                                                                                                                                        | 7                | 7 `laneRoute` tests and 2 Read-shared pricer tests                                                                                                                                                                                                                                                                                                                              |
| Modify `force-app/main/default/classes/LaneBenchmarkControllerTest.cls`                                                                                                                                                                                                  | 7                | 2 `truckRoute` tests and 1 Lane Benchmark user test                                                                                                                                                                                                                                                                                                                             |
| Modify `force-app/main/default/classes/RfpSecurityTest.cls`                                                                                                                                                                                                              | 7                | Stranger check on `laneRoute` inside an existing test                                                                                                                                                                                                                                                                                                                           |
| Create `force-app/main/default/messageChannels/Distance_Unit.messageChannel-meta.xml`                                                                                                                                                                                    | 8                | `Distance_Unit__c` channel, field `unit`                                                                                                                                                                                                                                                                                                                                        |
| Create `force-app/main/default/lwc/distanceUnit/` (`distanceUnit.js`, meta, `__tests__/distanceUnit.test.js`)                                                                                                                                                            | 8                | `UNIT_KEY`, `KM_PER_MILE`, `readUnit`, `writeUnit`, `formatDistance`, `perDistance`                                                                                                                                                                                                                                                                                             |
| Create `force-app/main/default/lwc/distanceUnitToggle/` (html, js, meta, `__tests__`)                                                                                                                                                                                    | 8                | The mi / km buttons that publish on `Distance_Unit__c`                                                                                                                                                                                                                                                                                                                          |
| Create `force-app/main/default/lwc/routeMap/` (html, js, css, meta, `__tests__`)                                                                                                                                                                                         | 8                | Static route image, legend, hazmat line, messages, spinner, Refresh route                                                                                                                                                                                                                                                                                                       |
| Modify `force-app/main/default/lwc/rfpToolbar/rfpToolbar.html`, `rfpToolbar.js`, `__tests__/rfpToolbar.test.js`                                                                                                                                                          | 9                | The unit toggle next to Include RFP bids                                                                                                                                                                                                                                                                                                                                        |
| Modify `force-app/main/default/lwc/rfpLaneTable/rfpLaneTable.js`, `rfpLaneTable.html`, `__tests__/rfpLaneTable.test.js`                                                                                                                                                  | 9                | Miles column after History, with tags and tooltips                                                                                                                                                                                                                                                                                                                              |
| Modify `force-app/main/default/lwc/rfpLanePanel/rfpLanePanel.js`, `rfpLanePanel.html`, `__tests__/rfpLanePanel.test.js`                                                                                                                                                  | 9                | Miles line, Cost and Sell per mile, `c-route-map` through `laneRoute`                                                                                                                                                                                                                                                                                                           |
| Modify `force-app/main/default/lwc/rfpWorkbook/rfpWorkbook.js`, `__tests__/rfpWorkbook.test.js`                                                                                                                                                                          | 9                | Miles, Km, Miles source, Route hours, Cost per mile, Sell per mile columns                                                                                                                                                                                                                                                                                                      |
| Modify `force-app/main/default/lwc/rfpTool/__tests__/rfpTool.test.js`                                                                                                                                                                                                    | 9                | Mock for `RfpLaneController.laneRoute` (`rfpTool.js` and `rfpTool.html` unchanged)                                                                                                                                                                                                                                                                                              |
| Modify `force-app/main/default/lwc/laneBenchmark/laneBenchmark.js`, `laneBenchmark.html`, `__tests__/laneBenchmark.test.js`                                                                                                                                              | 10               | `truckRoute` after a search, route map in place of the plain preview (a radius search keeps its radius preview), the page's unit                                                                                                                                                                                                                                                |
| Modify `force-app/main/default/lwc/laneBenchmarkStats/laneBenchmarkStats.js`, `laneBenchmarkStats.html`, `__tests__/laneBenchmarkStats.test.js`                                                                                                                          | 10               | Trip line, route line, rate per mile, toggle in the card header                                                                                                                                                                                                                                                                                                                 |
| Modify `force-app/main/default/lwc/laneBenchmarkResults/laneBenchmarkResults.js`, `laneBenchmarkResults.html`, `__tests__/laneBenchmarkResults.test.js`                                                                                                                  | 10               | Miles column and the CSV column `load.miles`                                                                                                                                                                                                                                                                                                                                    |
| Modify `docs/help/en/rfp-history.md`, `rfp-pricing.md`, `lb-stats.md`, `rfp-inline.md` and the four `docs/help/fr/` twins                                                                                                                                                | 11               | Trip miles and truck routes; the Miles column                                                                                                                                                                                                                                                                                                                                   |
| Modify `force-app/main/default/staticresources/helpCenter/en/` and `fr/` `rfp-history.html`, `rfp-pricing.html`, `lb-stats.html`, `rfp-inline.html`                                                                                                                      | 11               | Rebuilt by `npm run help:build`                                                                                                                                                                                                                                                                                                                                                 |
| Modify `README.md`                                                                                                                                                                                                                                                       | 11               | Roster 26, inventory rows, Security rows, "Trip miles (phase 7)" section (setting, Mapbox cost, the owner's storage decision)                                                                                                                                                                                                                                                   |
| Modify `.github/workflows/ci.yml`                                                                                                                                                                                                                                        | 11               | CI roster 26                                                                                                                                                                                                                                                                                                                                                                    |
| Modify `docs/superpowers/specs/2026-09-07-pricing-department-roadmap.md`                                                                                                                                                                                                 | 11               | Roadmap row 7                                                                                                                                                                                                                                                                                                                                                                   |
| Modify `docs/superpowers/specs/2026-09-14-phase-7-trip-miles-design.md`                                                                                                                                                                                                  | 11               | Outcome — phase 7                                                                                                                                                                                                                                                                                                                                                               |

---

<!-- prettier-ignore-start -->

### Task 1: Metadata foundation — lane miles fields, the Truck Route store, the truck routing setting

**Files:**

- Create: `force-app/main/default/objects/RFP_Lane__c/fields/Miles__c.field-meta.xml`, `force-app/main/default/objects/RFP_Lane__c/fields/Miles_Source__c.field-meta.xml`, `force-app/main/default/objects/RFP_Lane__c/fields/Route_Hours__c.field-meta.xml`
- Create: `force-app/main/default/objects/Truck_Route__c/Truck_Route__c.object-meta.xml`
- Create: `force-app/main/default/objects/Truck_Route__c/fields/` — `Origin_Place__c`, `Destination_Place__c`, `Profile_Key__c`, `Route_Key__c`, `Miles__c`, `Hours__c`, `Route_Type__c`, `Status__c`, `Routes_Json__c`, `Checked_On__c` (each `.field-meta.xml`)
- Create: `force-app/main/default/objects/Truck_Routing_Setting__mdt/Truck_Routing_Setting__mdt.object-meta.xml`
- Create: `force-app/main/default/objects/Truck_Routing_Setting__mdt/fields/` — `Height_M__c`, `Width_M__c`, `Weight_T__c`, `Alternatives__c`, `Approx_Factor__c`, `Timeout_Ms__c` (each `.field-meta.xml`)
- Create: `force-app/main/default/customMetadata/Truck_Routing_Setting.Default.md-meta.xml`
- Modify: `force-app/main/default/permissionsets/RFP_Tool_User.permissionset-meta.xml` (objectPermissions end at line 127; `RFP_Lane__c.Margin__c` block lines 303–307; `RFP_Lane__c.Raw_Row__c` block lines 358–362; last fieldPermissions block `Pricing_Place__c.Spellings__c` lines 608–612, `<tabSettings>` starts at 613)
- Modify: `force-app/main/default/permissionsets/Lane_Benchmark_User.permissionset-meta.xml` (last objectPermissions block `Benchmark_Rate__c` ends at line 66; last fieldPermissions block `Benchmark_Rate__c.Zip3_Lane__c` lines 372–376, `<tabSettings>` starts at 377)
- Modify: `manifest/package.xml` (CustomObject lines 128–135, CustomMetadata lines 136–139, CustomField: `Pricing_Department_Setting__mdt.Excluded_Contact_Ids__c` lines 192–193, `RFP_Lane__c.*` lines 216–259, `Benchmark_Rate__c.*` lines 260–294)

**Interfaces:**

- Consumes: `Pricing_Place__c` (lookup target; both permission sets already read it with View All and read `Pricing_Place__c.Geolocation__c`), `RFP_Lane__c` and its existing field-permission list in `RFP_Tool_User`, `Pricing_Department_Setting__mdt` / `Pricing_Department_Setting.Default` (file shape copied), `RFP_Lane__c.Origin_Place__c` (lookup file shape copied), `RFP_Lane__c.Hist_Status__c` (picklist file shape copied), `Pricing_Place__c.Key__c` (external ID file shape copied), `RFP_Lane__c.Raw_Row__c` (long text file shape copied).
- Produces (no Apex in this task; every later task relies on these exact API names):
  - `RFP_Lane__c.Miles__c` — Number(10, 1) (metadata precision 11, scale 1).
  - `RFP_Lane__c.Miles_Source__c` — restricted Picklist, no default: `History`, `Truck route`, `Regular route`, `Approx`, `No route`, `No coordinates`.
  - `RFP_Lane__c.Route_Hours__c` — Number(6, 1) (precision 7, scale 1).
  - `Truck_Route__c` — label `Truck Route`, plural `Truck Routes`, name field auto-number `TR-{000000}`, `sharingModel` `Read` (Public Read Only), reports off, no tab.
  - `Truck_Route__c.Origin_Place__c` / `Truck_Route__c.Destination_Place__c` — Lookup(Pricing_Place__c), SetNull, not required; child relationships `Pricing_Place__c.Truck_Routes_From__r` / `Pricing_Place__c.Truck_Routes_To__r`.
  - `Truck_Route__c.Profile_Key__c` Text(80); `Truck_Route__c.Route_Key__c` Text(160) External ID, Unique, case-sensitive (the upsert key of `TripMilesService.save`); `Truck_Route__c.Miles__c` Number(10, 1); `Truck_Route__c.Hours__c` Number(6, 1); `Truck_Route__c.Route_Type__c` restricted Picklist `Truck`, `Regular`; `Truck_Route__c.Status__c` restricted Picklist `Found`, `No route`; `Truck_Route__c.Routes_Json__c` LongTextArea(131072); `Truck_Route__c.Checked_On__c` DateTime.
  - `Truck_Routing_Setting__mdt` (Public) with `Height_M__c` Number(4, 2), `Width_M__c` Number(4, 2), `Weight_T__c` Number(5, 2), `Alternatives__c` Checkbox (default true), `Approx_Factor__c` Number(3, 2), `Timeout_Ms__c` Number(6, 0); record `Default` = 4.11, 2.6, 36.29, true, 1.2, 8000 (read by `TruckRoute.defaultProfile()` in Task 2).
  - `RFP_Tool_User`: read + edit on `RFP_Lane__c.Miles__c`, `Miles_Source__c`, `Route_Hours__c` (the user-mode lane writes of Tasks 6 and 7 go through `Security.stripInaccessible(AccessType.UPDATABLE)` and would silently drop the miles without it); read on `Truck_Route__c` and its ten custom fields.
  - `Lane_Benchmark_User`: read on `Truck_Route__c` and its ten custom fields (no lane grants).
  - `manifest/package.xml`: 2 CustomObject, 1 CustomMetadata and 19 CustomField members (Apex classes, LWC bundles and the `Distance_Unit__c` message channel are added by the tasks that create them).

- [ ] **Step 1: Confirm the org has none of it yet (the failing check)**

Run:

```bash
sf data query -o sandbox -q "SELECT QualifiedApiName, DataType FROM FieldDefinition WHERE EntityDefinition.QualifiedApiName = 'RFP_Lane__c' AND QualifiedApiName IN ('Miles__c','Miles_Source__c','Route_Hours__c')" -r human 2>&1 | grep -v Warning | tail -3
sf data query -o sandbox -q "SELECT QualifiedApiName, InternalSharingModel FROM EntityDefinition WHERE QualifiedApiName IN ('Truck_Route__c','Truck_Routing_Setting__mdt')" -r human 2>&1 | grep -v Warning | tail -3
sf data query -o sandbox -q "SELECT DeveloperName, Height_M__c FROM Truck_Routing_Setting__mdt" -r human 2>&1 | grep -v Warning | tail -3
```

Expected: `Total number of records retrieved: 0.` for the first two; the third prints `sObject type 'Truck_Routing_Setting__mdt' is not supported. If you are attempting to use a custom object, be sure to append the '__c' after the entity name. Please reference your WSDL or the describe call for the appropriate names.` (observed 2026-09-14; the type does not exist). If any of them already returns rows, stop and report: something was deployed outside this plan.

- [ ] **Step 2: Create the three lane fields**

Create `force-app/main/default/objects/RFP_Lane__c/fields/Miles__c.field-meta.xml`:

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Miles__c</fullName>
    <label>Miles</label>
    <type>Number</type>
    <precision>11</precision>
    <scale>1</scale>
    <required>false</required>
    <unique>false</unique>
    <inlineHelpText
  >Trip length in miles. Miles source says where it came from: the history median, a stored Mapbox route or the approximate distance.</inlineHelpText>
</CustomField>
```

Create `force-app/main/default/objects/RFP_Lane__c/fields/Miles_Source__c.field-meta.xml`:

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Miles_Source__c</fullName>
    <label>Miles source</label>
    <type>Picklist</type>
    <required>false</required>
    <valueSet>
        <restricted>true</restricted>
        <valueSetDefinition>
            <sorted>false</sorted>
            <value><fullName>History</fullName><default>false</default><label
        >History</label></value>
            <value><fullName>Truck route</fullName><default
        >false</default><label>Truck route</label></value>
            <value><fullName>Regular route</fullName><default
        >false</default><label>Regular route</label></value>
            <value><fullName>Approx</fullName><default>false</default><label
        >Approx</label></value>
            <value><fullName>No route</fullName><default>false</default><label
        >No route</label></value>
            <value><fullName>No coordinates</fullName><default
        >false</default><label>No coordinates</label></value>
        </valueSetDefinition>
    </valueSet>
</CustomField>
```

Create `force-app/main/default/objects/RFP_Lane__c/fields/Route_Hours__c.field-meta.xml`:

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Route_Hours__c</fullName>
    <label>Route hours</label>
    <type>Number</type>
    <precision>7</precision>
    <scale>1</scale>
    <required>false</required>
    <unique>false</unique>
    <inlineHelpText
  >Drive hours of the stored route. Blank when the miles come from history or are approximate.</inlineHelpText>
</CustomField>
```

- [ ] **Step 3: Create the `Truck_Route__c` object and its ten fields**

Create `force-app/main/default/objects/Truck_Route__c/Truck_Route__c.object-meta.xml`:

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<CustomObject xmlns="http://soap.sforce.com/2006/04/metadata">
    <label>Truck Route</label>
    <pluralLabel>Truck Routes</pluralLabel>
    <nameField>
        <label>Route number</label>
        <type>AutoNumber</type>
        <displayFormat>TR-{000000}</displayFormat>
    </nameField>
    <deploymentStatus>Deployed</deploymentStatus>
    <sharingModel>Read</sharingModel>
    <enableActivities>false</enableActivities>
    <enableHistory>false</enableHistory>
    <enableReports>false</enableReports>
    <enableSearch>false</enableSearch>
    <description
  >One Mapbox route per ordered place pair and truck profile (Route_Key__c), stored when a pricer opens a lane or runs a Lane Benchmark search and reused until refreshed. Written only by TripMilesService.</description>
</CustomObject>
```

Create `force-app/main/default/objects/Truck_Route__c/fields/Origin_Place__c.field-meta.xml`:

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Origin_Place__c</fullName>
    <label>Origin place</label>
    <type>Lookup</type>
    <referenceTo>Pricing_Place__c</referenceTo>
    <relationshipName>Truck_Routes_From</relationshipName>
    <relationshipLabel>Truck Routes (From)</relationshipLabel>
    <deleteConstraint>SetNull</deleteConstraint>
    <required>false</required>
</CustomField>
```

Create `force-app/main/default/objects/Truck_Route__c/fields/Destination_Place__c.field-meta.xml`:

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Destination_Place__c</fullName>
    <label>Destination place</label>
    <type>Lookup</type>
    <referenceTo>Pricing_Place__c</referenceTo>
    <relationshipName>Truck_Routes_To</relationshipName>
    <relationshipLabel>Truck Routes (To)</relationshipLabel>
    <deleteConstraint>SetNull</deleteConstraint>
    <required>false</required>
</CustomField>
```

Create `force-app/main/default/objects/Truck_Route__c/fields/Profile_Key__c.field-meta.xml`:

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Profile_Key__c</fullName>
    <label>Profile key</label>
    <type>Text</type>
    <length>80</length>
    <required>false</required>
    <unique>false</unique>
    <externalId>false</externalId>
    <inlineHelpText
  >Truck height, width and weight the route was asked with, e.g. h4.11w2.60t36.29.</inlineHelpText>
</CustomField>
```

Create `force-app/main/default/objects/Truck_Route__c/fields/Route_Key__c.field-meta.xml`:

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Route_Key__c</fullName>
    <label>Route key</label>
    <type>Text</type>
    <length>160</length>
    <externalId>true</externalId>
    <unique>true</unique>
    <caseSensitive>true</caseSensitive>
    <required>false</required>
    <inlineHelpText
  >Origin place Id:destination place Id:profile key. One row per ordered pair and truck profile; A to B and B to A are separate rows.</inlineHelpText>
</CustomField>
```

Create `force-app/main/default/objects/Truck_Route__c/fields/Miles__c.field-meta.xml`:

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Miles__c</fullName>
    <label>Miles</label>
    <type>Number</type>
    <precision>11</precision>
    <scale>1</scale>
    <required>false</required>
    <unique>false</unique>
</CustomField>
```

Create `force-app/main/default/objects/Truck_Route__c/fields/Hours__c.field-meta.xml`:

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Hours__c</fullName>
    <label>Hours</label>
    <type>Number</type>
    <precision>7</precision>
    <scale>1</scale>
    <required>false</required>
    <unique>false</unique>
</CustomField>
```

Create `force-app/main/default/objects/Truck_Route__c/fields/Route_Type__c.field-meta.xml`:

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Route_Type__c</fullName>
    <label>Route type</label>
    <type>Picklist</type>
    <required>false</required>
    <valueSet>
        <restricted>true</restricted>
        <valueSetDefinition>
            <sorted>false</sorted>
            <value><fullName>Truck</fullName><default>false</default><label
        >Truck</label></value>
            <value><fullName>Regular</fullName><default>false</default><label
        >Regular</label></value>
        </valueSetDefinition>
    </valueSet>
</CustomField>
```

Create `force-app/main/default/objects/Truck_Route__c/fields/Status__c.field-meta.xml`:

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Status__c</fullName>
    <label>Status</label>
    <type>Picklist</type>
    <required>false</required>
    <valueSet>
        <restricted>true</restricted>
        <valueSetDefinition>
            <sorted>false</sorted>
            <value><fullName>Found</fullName><default>false</default><label
        >Found</label></value>
            <value><fullName>No route</fullName><default>false</default><label
        >No route</label></value>
        </valueSetDefinition>
    </valueSet>
</CustomField>
```

Create `force-app/main/default/objects/Truck_Route__c/fields/Routes_Json__c.field-meta.xml`:

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Routes_Json__c</fullName>
    <label>Routes (JSON)</label>
    <type>LongTextArea</type>
    <length>131072</length>
    <visibleLines>5</visibleLines>
</CustomField>
```

Create `force-app/main/default/objects/Truck_Route__c/fields/Checked_On__c.field-meta.xml`:

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Checked_On__c</fullName>
    <label>Checked on</label>
    <type>DateTime</type>
    <required>false</required>
</CustomField>
```

- [ ] **Step 4: Create the `Truck_Routing_Setting__mdt` type, its six fields and the `Default` record**

Create `force-app/main/default/objects/Truck_Routing_Setting__mdt/Truck_Routing_Setting__mdt.object-meta.xml`:

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<CustomObject xmlns="http://soap.sforce.com/2006/04/metadata">
    <label>Truck Routing Setting</label>
    <pluralLabel>Truck Routing Settings</pluralLabel>
    <visibility>Public</visibility>
</CustomObject>
```

Create `force-app/main/default/objects/Truck_Routing_Setting__mdt/fields/Height_M__c.field-meta.xml`:

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Height_M__c</fullName>
    <externalId>false</externalId>
    <fieldManageability>DeveloperControlled</fieldManageability>
    <inlineHelpText
  >Truck height in metres sent to Mapbox as max_height (0 to 10). 4.11 m is 13 ft 6 in.</inlineHelpText>
    <label>Height (m)</label>
    <precision>6</precision>
    <required>false</required>
    <scale>2</scale>
    <type>Number</type>
    <unique>false</unique>
</CustomField>
```

Create `force-app/main/default/objects/Truck_Routing_Setting__mdt/fields/Width_M__c.field-meta.xml`:

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Width_M__c</fullName>
    <externalId>false</externalId>
    <fieldManageability>DeveloperControlled</fieldManageability>
    <inlineHelpText
  >Truck width in metres sent to Mapbox as max_width (0 to 10). 2.6 m is 102 in.</inlineHelpText>
    <label>Width (m)</label>
    <precision>6</precision>
    <required>false</required>
    <scale>2</scale>
    <type>Number</type>
    <unique>false</unique>
</CustomField>
```

Create `force-app/main/default/objects/Truck_Routing_Setting__mdt/fields/Weight_T__c.field-meta.xml`:

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Weight_T__c</fullName>
    <externalId>false</externalId>
    <fieldManageability>DeveloperControlled</fieldManageability>
    <inlineHelpText
  >Gross weight in metric tons sent to Mapbox as max_weight (0 to 100). 36.29 t is 80,000 lb.</inlineHelpText>
    <label>Weight (t)</label>
    <precision>7</precision>
    <required>false</required>
    <scale>2</scale>
    <type>Number</type>
    <unique>false</unique>
</CustomField>
```

Create `force-app/main/default/objects/Truck_Routing_Setting__mdt/fields/Alternatives__c.field-meta.xml`:

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Alternatives__c</fullName>
    <defaultValue>true</defaultValue>
    <externalId>false</externalId>
    <fieldManageability>DeveloperControlled</fieldManageability>
    <inlineHelpText
  >Ask Mapbox for up to two alternative routes, drawn on the map beside the main route.</inlineHelpText>
    <label>Alternatives</label>
    <type>Checkbox</type>
</CustomField>
```

Create `force-app/main/default/objects/Truck_Routing_Setting__mdt/fields/Approx_Factor__c.field-meta.xml`:

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Approx_Factor__c</fullName>
    <externalId>false</externalId>
    <fieldManageability>DeveloperControlled</fieldManageability>
    <inlineHelpText
  >Straight-line miles between the two places are multiplied by this factor to give Approx miles. 1.2 is the measured median of billed miles over straight-line miles.</inlineHelpText>
    <label>Approx factor</label>
    <precision>5</precision>
    <required>false</required>
    <scale>2</scale>
    <type>Number</type>
    <unique>false</unique>
</CustomField>
```

Create `force-app/main/default/objects/Truck_Routing_Setting__mdt/fields/Timeout_Ms__c.field-meta.xml`:

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Timeout_Ms__c</fullName>
    <externalId>false</externalId>
    <fieldManageability>DeveloperControlled</fieldManageability>
    <inlineHelpText
  >Timeout of each Mapbox Directions callout, in milliseconds.</inlineHelpText>
    <label>Timeout (ms)</label>
    <precision>6</precision>
    <required>false</required>
    <scale>0</scale>
    <type>Number</type>
    <unique>false</unique>
</CustomField>
```

Create `force-app/main/default/customMetadata/Truck_Routing_Setting.Default.md-meta.xml`:

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<CustomMetadata
  xmlns="http://soap.sforce.com/2006/04/metadata"
  xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
  xmlns:xsd="http://www.w3.org/2001/XMLSchema"
>
    <label>Default</label>
    <protected>false</protected>
    <values>
        <field>Alternatives__c</field>
        <value xsi:type="xsd:boolean">true</value>
    </values>
    <values>
        <field>Approx_Factor__c</field>
        <value xsi:type="xsd:double">1.2</value>
    </values>
    <values>
        <field>Height_M__c</field>
        <value xsi:type="xsd:double">4.11</value>
    </values>
    <values>
        <field>Timeout_Ms__c</field>
        <value xsi:type="xsd:double">8000</value>
    </values>
    <values>
        <field>Weight_T__c</field>
        <value xsi:type="xsd:double">36.29</value>
    </values>
    <values>
        <field>Width_M__c</field>
        <value xsi:type="xsd:double">2.6</value>
    </values>
</CustomMetadata>
```

- [ ] **Step 5: Grant the fields and the object in both permission sets**

Keep each file's existing order: object permissions append after the set's last object block; field permissions are grouped by object and sorted by API name with `_` after capital letters (the files already put `Cost_Source__c` before `Cost__c`), so `Miles_Source__c` comes before `Miles__c`, and `Route_Hours__c` sits between `Raw_Row__c` and `Row_Number__c`. Make the edits bottom-up so the line numbers in **Files** stay valid while you work.

In `force-app/main/default/permissionsets/RFP_Tool_User.permissionset-meta.xml`:

(a) After the `Pricing_Place__c.Spellings__c` block (lines 608–612), immediately before the first `<tabSettings>` (line 613), insert:

```xml
    <fieldPermissions>
        <editable>false</editable>
        <field>Truck_Route__c.Checked_On__c</field>
        <readable>true</readable>
    </fieldPermissions>
    <fieldPermissions>
        <editable>false</editable>
        <field>Truck_Route__c.Destination_Place__c</field>
        <readable>true</readable>
    </fieldPermissions>
    <fieldPermissions>
        <editable>false</editable>
        <field>Truck_Route__c.Hours__c</field>
        <readable>true</readable>
    </fieldPermissions>
    <fieldPermissions>
        <editable>false</editable>
        <field>Truck_Route__c.Miles__c</field>
        <readable>true</readable>
    </fieldPermissions>
    <fieldPermissions>
        <editable>false</editable>
        <field>Truck_Route__c.Origin_Place__c</field>
        <readable>true</readable>
    </fieldPermissions>
    <fieldPermissions>
        <editable>false</editable>
        <field>Truck_Route__c.Profile_Key__c</field>
        <readable>true</readable>
    </fieldPermissions>
    <fieldPermissions>
        <editable>false</editable>
        <field>Truck_Route__c.Route_Key__c</field>
        <readable>true</readable>
    </fieldPermissions>
    <fieldPermissions>
        <editable>false</editable>
        <field>Truck_Route__c.Route_Type__c</field>
        <readable>true</readable>
    </fieldPermissions>
    <fieldPermissions>
        <editable>false</editable>
        <field>Truck_Route__c.Routes_Json__c</field>
        <readable>true</readable>
    </fieldPermissions>
    <fieldPermissions>
        <editable>false</editable>
        <field>Truck_Route__c.Status__c</field>
        <readable>true</readable>
    </fieldPermissions>
```

(b) After the `RFP_Lane__c.Raw_Row__c` block (lines 358–362), before the `RFP_Lane__c.Row_Number__c` block, insert:

```xml
    <fieldPermissions>
        <editable>true</editable>
        <field>RFP_Lane__c.Route_Hours__c</field>
        <readable>true</readable>
    </fieldPermissions>
```

(c) After the `RFP_Lane__c.Margin__c` block (lines 303–307), before the `RFP_Lane__c.Mode__c` block, insert:

```xml
    <fieldPermissions>
        <editable>true</editable>
        <field>RFP_Lane__c.Miles_Source__c</field>
        <readable>true</readable>
    </fieldPermissions>
    <fieldPermissions>
        <editable>true</editable>
        <field>RFP_Lane__c.Miles__c</field>
        <readable>true</readable>
    </fieldPermissions>
```

(d) After the `Account` objectPermissions block (lines 119–127), before the first `<fieldPermissions>` (line 128), insert:

```xml
    <objectPermissions>
        <allowCreate>false</allowCreate>
        <allowDelete>false</allowDelete>
        <allowEdit>false</allowEdit>
        <allowRead>true</allowRead>
        <modifyAllRecords>false</modifyAllRecords>
        <object>Truck_Route__c</object>
        <viewAllRecords>false</viewAllRecords>
    </objectPermissions>
```

In `force-app/main/default/permissionsets/Lane_Benchmark_User.permissionset-meta.xml`:

(e) After the `Benchmark_Rate__c.Zip3_Lane__c` block (lines 372–376), immediately before the first `<tabSettings>` (line 377), insert the same ten `Truck_Route__c` field blocks as (a), unchanged (all `editable` false, `readable` true).

(f) After the `Benchmark_Rate__c` objectPermissions block (lines 58–66), before the first `<fieldPermissions>` (line 67), insert the same `Truck_Route__c` objectPermissions block as (d), unchanged.

`viewAllRecords` stays false: the object is Public Read Only, so every internal user already reads every row; no one but `TripMilesService` (system mode) writes it, so neither set grants create, edit or delete.

Check the edits:

```bash
cd /Users/iulian/Documents/Personal/PricingDepartemnt/force-app/main/default/permissionsets
xmllint --noout RFP_Tool_User.permissionset-meta.xml Lane_Benchmark_User.permissionset-meta.xml && echo xml-ok
grep -c 'Truck_Route__c' RFP_Tool_User.permissionset-meta.xml Lane_Benchmark_User.permissionset-meta.xml
grep -c 'RFP_Lane__c.Miles__c\|RFP_Lane__c.Miles_Source__c\|RFP_Lane__c.Route_Hours__c' RFP_Tool_User.permissionset-meta.xml Lane_Benchmark_User.permissionset-meta.xml
grep -n -B1 -A1 '<field>RFP_Lane__c.Mi\|<field>RFP_Lane__c.Ro' RFP_Tool_User.permissionset-meta.xml | grep '<field>'
```

Expected: `xml-ok`; `RFP_Tool_User.permissionset-meta.xml:11` and `Lane_Benchmark_User.permissionset-meta.xml:11` (one object block plus ten fields each); `RFP_Tool_User.permissionset-meta.xml:3` and `Lane_Benchmark_User.permissionset-meta.xml:0`; the field lines in this order: `RFP_Lane__c.Miles_Source__c`, `RFP_Lane__c.Miles__c`, `RFP_Lane__c.Route_Hours__c`, `RFP_Lane__c.Row_Number__c`.

- [ ] **Step 6: Add the new components to `manifest/package.xml`**

Only what this task creates goes in: a manifest that names a class, bundle or message channel that does not exist yet would break every `--manifest` deploy. Make the edits bottom-up.

(a) After `<members>Benchmark_Rate__c.Zip3_Lane__c</members>` (line 294), before `<name>CustomField</name>`, insert:

```xml
        <members>Truck_Route__c.Checked_On__c</members>
        <members>Truck_Route__c.Destination_Place__c</members>
        <members>Truck_Route__c.Hours__c</members>
        <members>Truck_Route__c.Miles__c</members>
        <members>Truck_Route__c.Origin_Place__c</members>
        <members>Truck_Route__c.Profile_Key__c</members>
        <members>Truck_Route__c.Route_Key__c</members>
        <members>Truck_Route__c.Route_Type__c</members>
        <members>Truck_Route__c.Routes_Json__c</members>
        <members>Truck_Route__c.Status__c</members>
```

(b) After `<members>RFP_Lane__c.Raw_Row__c</members>` (line 254), before `<members>RFP_Lane__c.Row_Number__c</members>`, insert:

```xml
        <members>RFP_Lane__c.Route_Hours__c</members>
```

(c) After `<members>RFP_Lane__c.Margin__c</members>` (line 242), before `<members>RFP_Lane__c.Mode__c</members>`, insert:

```xml
        <members>RFP_Lane__c.Miles_Source__c</members>
        <members>RFP_Lane__c.Miles__c</members>
```

(d) After the two-line `Pricing_Department_Setting__mdt.Excluded_Contact_Ids__c` member (lines 192–193), before `<members>Pricing_Place__c.Key__c</members>`, insert:

```xml
        <members>Truck_Routing_Setting__mdt.Alternatives__c</members>
        <members>Truck_Routing_Setting__mdt.Approx_Factor__c</members>
        <members>Truck_Routing_Setting__mdt.Height_M__c</members>
        <members>Truck_Routing_Setting__mdt.Timeout_Ms__c</members>
        <members>Truck_Routing_Setting__mdt.Weight_T__c</members>
        <members>Truck_Routing_Setting__mdt.Width_M__c</members>
```

(e) After `<members>Pricing_Department_Setting.Default</members>` (line 137), before `<name>CustomMetadata</name>`, insert:

```xml
        <members>Truck_Routing_Setting.Default</members>
```

(f) After `<members>Benchmark_Rate__c</members>` (line 133), before `<name>CustomObject</name>`, insert:

```xml
        <members>Truck_Route__c</members>
        <members>Truck_Routing_Setting__mdt</members>
```

Check:

```bash
cd /Users/iulian/Documents/Personal/PricingDepartemnt
xmllint --noout manifest/package.xml && echo xml-ok
grep -c '<members>Truck_Route__c\.' manifest/package.xml
grep -c '<members>Truck_Routing_Setting__mdt\.' manifest/package.xml
grep -c '<members>RFP_Lane__c.Miles__c</members>\|<members>RFP_Lane__c.Miles_Source__c</members>\|<members>RFP_Lane__c.Route_Hours__c</members>' manifest/package.xml
grep -c '<members>Truck_Route__c</members>\|<members>Truck_Routing_Setting__mdt</members>\|<members>Truck_Routing_Setting.Default</members>' manifest/package.xml
```

Expected: `xml-ok`, then `10`, `6`, `3`, `3`.

- [ ] **Step 7: Format and lint**

No Apex or LWC changes in this task, so PMD, ESLint and Jest are not run here. Run Prettier on the new and changed files so the committed shape matches what lint-staged would produce:

```bash
cd /Users/iulian/Documents/Personal/PricingDepartemnt
npx prettier --check force-app/main/default/objects/RFP_Lane__c/fields/Miles__c.field-meta.xml force-app/main/default/objects/RFP_Lane__c/fields/Miles_Source__c.field-meta.xml force-app/main/default/objects/RFP_Lane__c/fields/Route_Hours__c.field-meta.xml force-app/main/default/objects/Truck_Route__c force-app/main/default/objects/Truck_Routing_Setting__mdt force-app/main/default/customMetadata/Truck_Routing_Setting.Default.md-meta.xml force-app/main/default/permissionsets manifest/package.xml
```

Expected: `All matched files use Prettier code style!`. If a file is listed, run the same command with `--write` instead of `--check`, then `--check` again (Prettier only moves line breaks inside tags; it never changes a value).

- [ ] **Step 8: Deploy the metadata (async, no tests)**

Run:

```bash
cd /Users/iulian/Documents/Personal/PricingDepartemnt
sf project deploy start -o sandbox -l NoTestRun --async --json \
  --source-dir force-app/main/default/objects/RFP_Lane__c/fields/Miles__c.field-meta.xml \
  --source-dir force-app/main/default/objects/RFP_Lane__c/fields/Miles_Source__c.field-meta.xml \
  --source-dir force-app/main/default/objects/RFP_Lane__c/fields/Route_Hours__c.field-meta.xml \
  --source-dir force-app/main/default/objects/Truck_Route__c \
  --source-dir force-app/main/default/objects/Truck_Routing_Setting__mdt \
  --source-dir force-app/main/default/customMetadata/Truck_Routing_Setting.Default.md-meta.xml \
  --source-dir force-app/main/default/permissionsets/RFP_Tool_User.permissionset-meta.xml \
  --source-dir force-app/main/default/permissionsets/Lane_Benchmark_User.permissionset-meta.xml \
  | python3 -c "import json,sys; s=sys.stdin.read(); d=json.loads(s[s.index('{'):]); r=d.get('result') or {}; print(r.get('id'), r.get('status'), d.get('message') or '')"
```

Expected: a deploy id starting `0Af` followed by `Queued` or `InProgress`. Write the id down; Step 9 and the final report need it. The permission sets travel with the fields and the object because their new grants name them; `manifest/package.xml` is not deployed here (Task 11's final deploy uses it).

- [ ] **Step 9: Poll the deploy until it finishes**

Run (replace `<id>` with the id from Step 8):

```bash
sf project deploy report -o sandbox --job-id <id> -w 2 --json | python3 -c "import json,sys,collections; s=sys.stdin.read(); d=json.loads(s[s.index('{'):]); r=d.get('result') or {}; det=r.get('details') or {}; ok=det.get('componentSuccesses') or []; ok=ok if isinstance(ok,list) else [ok]; bad=det.get('componentFailures') or []; bad=bad if isinstance(bad,list) else [bad]; print(r.get('status') or d.get('name'), 'errors', r.get('numberComponentErrors')); print(dict(collections.Counter(c.get('componentType') for c in ok if c.get('componentType')))); [print(c.get('componentType'), c.get('fullName'), '->', c.get('problem')) for c in bad]"
```

Each run returns within about two minutes. If the first printed word is `Queued` or `InProgress`, or an error name about the wait running out, run the same command again (do not `sleep`; a fresh report keeps the session active).

Expected when done: `Succeeded errors 0`, then counts `'CustomField': 19`, `'CustomMetadata': 1`, `'PermissionSet': 2` and `'CustomObject'` 2 or 3 (the CLI may also list `RFP_Lane__c` as the parent of its three new fields), and no failure lines. On `Failed`, the failure lines name the component and problem: a permission set failing with "no CustomField named Truck_Route__c.…" means a field file is missing or misnamed in Step 3; a record failing on a value means a `<field>` name in the `Default` record does not match a Step 4 file. Fix the file, re-run Step 7, then Step 8 and Step 9.

- [ ] **Step 10: Verify the org**

The DataType strings below follow the formats this org printed on 2026-09-14 for existing fields (`Quantity__c` precision 12 scale 2 shows `Number(10, 2)`; `Pricing_Place__c.Key__c` shows `Text(120)  (External ID) (Unique Case Insensitive)` with two spaces; `Raw_Row__c` shows `Long Text Area(32768)`; `Origin_Place__c` shows `Lookup(Pricing Place)`).

Run:

```bash
cd /Users/iulian/Documents/Personal/PricingDepartemnt
sf data query -o sandbox -q "SELECT QualifiedApiName, DataType, IsNillable FROM FieldDefinition WHERE EntityDefinition.QualifiedApiName = 'RFP_Lane__c' AND QualifiedApiName IN ('Miles__c','Miles_Source__c','Route_Hours__c')" -r human 2>&1 | grep -v Warning
sf data query -o sandbox -q "SELECT QualifiedApiName, DataType, IsNillable FROM FieldDefinition WHERE EntityDefinition.QualifiedApiName = 'Truck_Route__c' AND QualifiedApiName IN ('Origin_Place__c','Destination_Place__c','Profile_Key__c','Route_Key__c','Miles__c','Hours__c','Route_Type__c','Status__c','Routes_Json__c','Checked_On__c')" -r human 2>&1 | grep -v Warning
sf data query -o sandbox -q "SELECT QualifiedApiName, DataType FROM FieldDefinition WHERE EntityDefinition.QualifiedApiName = 'Truck_Routing_Setting__mdt' AND QualifiedApiName IN ('Height_M__c','Width_M__c','Weight_T__c','Alternatives__c','Approx_Factor__c','Timeout_Ms__c')" -r human 2>&1 | grep -v Warning
sf data query -o sandbox -q "SELECT QualifiedApiName, Label, PluralLabel, InternalSharingModel FROM EntityDefinition WHERE QualifiedApiName IN ('Truck_Route__c','Truck_Routing_Setting__mdt')" -r human 2>&1 | grep -v Warning
sf data query -o sandbox -q "SELECT DeveloperName, Height_M__c, Width_M__c, Weight_T__c, Alternatives__c, Approx_Factor__c, Timeout_Ms__c FROM Truck_Routing_Setting__mdt" -r human 2>&1 | grep -v Warning
```

Expected, in any row order:

- `RFP_Lane__c`: `Miles__c | Number(10, 1) | true`, `Miles_Source__c | Picklist | true`, `Route_Hours__c | Number(6, 1) | true` (3 rows).
- `Truck_Route__c` (10 rows, `IsNillable` true on every row): `Checked_On__c | Date/Time`, `Destination_Place__c | Lookup(Pricing Place)`, `Hours__c | Number(6, 1)`, `Miles__c | Number(10, 1)`, `Origin_Place__c | Lookup(Pricing Place)`, `Profile_Key__c | Text(80)`, `Route_Key__c | Text(160)  (External ID) (Unique Case Sensitive)`, `Route_Type__c | Picklist`, `Routes_Json__c | Long Text Area(131072)`, `Status__c | Picklist`.
- `Truck_Routing_Setting__mdt` (6 rows): `Alternatives__c | Checkbox`, `Approx_Factor__c | Number(3, 2)`, `Height_M__c | Number(4, 2)`, `Timeout_Ms__c | Number(6, 0)`, `Weight_T__c | Number(5, 2)`, `Width_M__c | Number(4, 2)`.
- EntityDefinition: `Truck_Route__c | Truck Route | Truck Routes | Read` and `Truck_Routing_Setting__mdt | Truck Routing Setting | Truck Routing Settings | ReadWrite` (custom metadata types always report `ReadWrite`, as `Pricing_Department_Setting__mdt` does). `Read` is the Metadata API and EntityDefinition value for Public Read Only; the filter `InternalSharingModel = 'Read'` is accepted in this org but matched no object before this task, so `Truck_Route__c` is the first.
- The record: one row `Default | 4.11 | 2.6 | 36.29 | true | 1.2 | 8000` (the CLI may print `2.60` / `1.20`; the value is what counts).

Then the picklists, the child relationship names and the grants:

```bash
cd /Users/iulian/Documents/Personal/PricingDepartemnt
sf data query -o sandbox -q "SELECT Value, IsActive, IsDefaultValue FROM PicklistValueInfo WHERE EntityParticle.EntityDefinition.QualifiedApiName = 'RFP_Lane__c' AND EntityParticle.QualifiedApiName = 'Miles_Source__c'" -r human 2>&1 | grep -v Warning
sf data query -o sandbox -q "SELECT EntityParticle.QualifiedApiName, Value, IsDefaultValue FROM PicklistValueInfo WHERE EntityParticle.EntityDefinition.QualifiedApiName = 'Truck_Route__c' AND EntityParticle.QualifiedApiName IN ('Route_Type__c','Status__c')" -r human 2>&1 | grep -v Warning
sf sobject describe -s Pricing_Place__c -o sandbox --json 2>/dev/null | python3 -c "import json,sys; s=sys.stdin.read(); r=json.loads(s[s.index('{'):])['result']; print(sorted(c['relationshipName'] for c in r['childRelationships'] if (c.get('relationshipName') or '').startswith('Truck_Routes')))"
sf data query -o sandbox -q "SELECT Parent.Name, SobjectType, PermissionsRead, PermissionsCreate, PermissionsEdit, PermissionsDelete FROM ObjectPermissions WHERE Parent.Name IN ('RFP_Tool_User','Lane_Benchmark_User') AND SobjectType = 'Truck_Route__c' ORDER BY Parent.Name" -r human 2>&1 | grep -v Warning
sf data query -o sandbox -q "SELECT Parent.Name, Field, PermissionsRead, PermissionsEdit FROM FieldPermissions WHERE Parent.Name IN ('RFP_Tool_User','Lane_Benchmark_User') AND (SobjectType = 'Truck_Route__c' OR Field IN ('RFP_Lane__c.Miles__c','RFP_Lane__c.Miles_Source__c','RFP_Lane__c.Route_Hours__c')) ORDER BY Parent.Name, Field" -r human 2>&1 | grep -v Warning
```

Expected:

- `Miles_Source__c`: 6 rows `History`, `Truck route`, `Regular route`, `Approx`, `No route`, `No coordinates`, every `IsActive` true and every `IsDefaultValue` false.
- `Route_Type__c`: `Truck`, `Regular`; `Status__c`: `Found`, `No route`; every `IsDefaultValue` false (4 rows).
- `['Truck_Routes_From__r', 'Truck_Routes_To__r']`.
- Object permissions: `Lane_Benchmark_User | Truck_Route__c | true | false | false | false` and `RFP_Tool_User | Truck_Route__c | true | false | false | false`.
- Field permissions, 23 rows: `Lane_Benchmark_User` 10 rows `Truck_Route__c.*` with read true, edit false; `RFP_Tool_User` 3 rows `RFP_Lane__c.Miles_Source__c`, `RFP_Lane__c.Miles__c`, `RFP_Lane__c.Route_Hours__c` with read true, edit true, and 10 rows `Truck_Route__c.*` with read true, edit false. A missing lane row is the failure that matters most: Tasks 6 and 7 write the miles in user mode after `Security.stripInaccessible`, which would silently drop an ungranted field.

- [ ] **Step 11: Commit**

```bash
cd /Users/iulian/Documents/Personal/PricingDepartemnt
git add force-app/main/default/objects/RFP_Lane__c/fields/Miles__c.field-meta.xml force-app/main/default/objects/RFP_Lane__c/fields/Miles_Source__c.field-meta.xml force-app/main/default/objects/RFP_Lane__c/fields/Route_Hours__c.field-meta.xml force-app/main/default/objects/Truck_Route__c force-app/main/default/objects/Truck_Routing_Setting__mdt force-app/main/default/customMetadata/Truck_Routing_Setting.Default.md-meta.xml force-app/main/default/permissionsets/RFP_Tool_User.permissionset-meta.xml force-app/main/default/permissionsets/Lane_Benchmark_User.permissionset-meta.xml manifest/package.xml
git diff --cached --name-only | wc -l
git commit -m "Add trip miles fields, the Truck Route store and the truck routing setting"
git status --short
```

Expected: `25` staged files (3 lane fields, the object and its 10 fields, the setting type and its 6 fields, the record, 2 permission sets, the manifest); the commit succeeds after lint-staged runs Prettier; `git status --short` afterwards lists only ` M .vscode/settings.json` and any pre-existing untracked `* 2.*` duplicates, neither of which is ever staged. No attribution trailer in the message.

#### Contract notes (Task 1)

1. **Number sizes.** The contract's `Number(p, s)` is read the way Salesforce shows it (digits before the decimal point, decimal places), because that is what the `FieldDefinition.DataType` check prints: in this org `Quantity__c` has metadata precision 12, scale 2 and prints `Number(10, 2)`. The metadata `precision` is therefore the contract's first number plus the scale: `Miles__c` 11/1, `Route_Hours__c` and `Hours__c` 7/1, `Height_M__c` and `Width_M__c` 6/2, `Weight_T__c` 7/2, `Approx_Factor__c` 5/2, `Timeout_Ms__c` 6/0. No later task depends on the precision; values are set in Apex with `setScale`.
2. **Manifest entries go in with the task that creates the files.** Task 1 adds only the objects, fields and custom metadata record. The Apex classes and test classes (Tasks 2–7), the `Distance_Unit__c` message channel (Task 8, type `LightningMessageChannel`, folder `force-app/main/default/messageChannels/` which does not exist yet) and the new LWC bundles (Tasks 8–10) are added to `manifest/package.xml` by those tasks. This follows phase 6, where each task added its own classes. A member naming a missing component breaks every `--manifest` deploy.
3. **No `classAccesses` in Task 1**, because a permission set that names a class that does not exist yet fails to deploy. Task 7 adds `classAccesses` for `TripRouteView` to both sets (README line 563 convention; the platform does not require it for a return type, as `LaneSearchResult` shows). `LaneSearchResult` is returned to LWC by `LaneBenchmarkController.search` and appears in neither permission set. `RfpBulkService.Result` gets its access only because it sits inside `RfpBulkService`, which is granted. `RfpLaneController` and `LaneBenchmarkController` already have class access in both sets, and the new `@AuraEnabled` methods live on them. `MapboxHttp`, `TruckRoute`, `MapboxTruckRoute`, `RouteMapUrl` and `TripMilesService` are only called from Apex and need no grant either (Lane_Benchmark_User lists `MapboxGeocoder`, but only because of an older direct use; it is not a precedent).
4. **No `customMetadataTypeAccesses`** for `Truck_Routing_Setting__mdt`: `Pricing_Department_Setting__mdt` has none in either set, and `Truck_Routing_Setting__mdt.getInstance('Default')` in Apex does not need one.
5. **`Truck_Route__c` object details not fixed by the contract:** name field label `Route number`, `enableSearch` false, `enableActivities` and `enableHistory` false (the `RFP_Lane__c` shape), and no `externalSharingModel`. The org then applies its default for a new object, `Private`, as it did for `Pricing_Place__c`. `Route_Key__c` is not required, as the contract says: `TripMilesService` always sets it, and the upsert fails loudly on a blank key.
6. **Permission sets and manifest are given as exact insertions** at named blocks and line numbers, not reprinted in full (625, 385 and 302 lines). Every new file is given in full.
7. **Deploy style** follows this phase's execution rules (`--async --json` plus `deploy report -w 2` polling), not phase 6's foreground `-w 30`.
8. **Advice for Task 5, not a Task 1 change:** `rtms__Load__c.rtms__Distance_Miles__c` needs no field permission. `LaneSearchService` runs its query in `AccessLevel.SYSTEM_MODE` (`LaneSearchService.cls` line 32), and the field belongs to the managed package, so it needs no manifest entry.

---

### Task 2: Mapbox truck route — `MapboxHttp`, `TruckRoute`, `MapboxTruckRoute` with the regular fallback

**Files:**

- Create: `force-app/main/default/classes/MapboxHttp.cls`, `force-app/main/default/classes/MapboxHttp.cls-meta.xml`
- Create: `force-app/main/default/classes/TruckRoute.cls`, `force-app/main/default/classes/TruckRoute.cls-meta.xml`
- Create: `force-app/main/default/classes/MapboxTruckRoute.cls`, `force-app/main/default/classes/MapboxTruckRoute.cls-meta.xml`
- Create: `force-app/main/default/classes/MapboxTruckRouteTest.cls`, `force-app/main/default/classes/MapboxTruckRouteTest.cls-meta.xml`
- Modify: `force-app/main/default/classes/MapboxGeocoder.cls` — lines 1-10 (class comment and `BASE`), 29-32 (`token()` delegates), 76-87 (`sendWithRetry()` delegates). `MapboxGeocoderTest.cls` is not touched.
- Modify: `manifest/package.xml` — ApexClass members `MapboxHttp`, `MapboxTruckRoute`, `MapboxTruckRouteTest`, `TruckRoute` inserted right after `<members>MapboxResponseParser</members>` (line 88 before Task 1; find it by text, Task 1 shifts the line numbers).

**Interfaces:**

- Consumes: `Truck_Routing_Setting__mdt` and its `Default` record (Task 1: `Height_M__c`, `Width_M__c`, `Weight_T__c`, `Alternatives__c`, `Approx_Factor__c`, `Timeout_Ms__c`); `TPRO_KPI__c.Mapbox_Api_Key__c` (exists); `MapboxException` (exists); remote site `MapBox` for `https://api.mapbox.com` (exists).
- Produces:
  - `MapboxHttp` (public with sharing): `public static final String BASE = 'https://api.mapbox.com'`; `@TestVisible private static String tokenOverride`; `public static String token()` — `tokenOverride` when it is not null (tests set `'pk.test'`, or `''` for a missing token), else `TPRO_KPI__c.getOrgDefaults().Mapbox_Api_Key__c`; `public static HttpResponse send(HttpRequest req)` — one retry when the status is 500 or more; `System.CalloutException` becomes `MapboxException('Mapbox is not reachable right now')`.
  - `TruckRoute` (public with sharing): `Point(Decimal lat, Decimal lng)`; `Profile { heightM, widthM, weightT, alternatives, approxFactor, timeoutMs; String key() }` (`'h4.11w2.60t36.29'`); `Line { @AuraEnabled miles; @AuraEnabled hours; polyline5 }`; `Result { status; routeType; routes = new List<Line>(); message }`; `public static Profile defaultProfile()`; `public static final String UNAVAILABLE = 'The truck route is not available right now.'`; `@TestVisible private static Profile profileFrom(Truck_Routing_Setting__mdt setting)` (blank record or blank field → the 53 ft dry-van default).
  - `MapboxTruckRoute` (public with sharing): `public static TruckRoute.Result route(TruckRoute.Point origin, TruckRoute.Point destination, TruckRoute.Profile profile)` — status `Found` (routeType `Truck` or `Regular`, 1 to 3 routes, main first, every route with miles and hours), `No route` (routeType null, no routes, message null) or `Unavailable` (message `TruckRoute.UNAVAILABLE`). Makes no callout for a blank token or a point without coordinates; two requests at most (each one may be retried once on a 5xx by `MapboxHttp.send`). No DML.
  - `MapboxGeocoder` behaviour is unchanged (`MapboxGeocoderTest`, 9 tests, passes as it is).

- [ ] **Step 1: Write the failing test**

Create `force-app/main/default/classes/MapboxTruckRouteTest.cls-meta.xml`:

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<ApexClass xmlns="http://soap.sforce.com/2006/04/metadata">
    <apiVersion>64.0</apiVersion>
    <status>Active</status>
</ApexClass>
```

Create `force-app/main/default/classes/MapboxTruckRouteTest.cls` (the mock answers each callout with the next queued response and records every endpoint; `MapboxHttp.tokenOverride = 'pk.test'` replaces the org setting; the profile is built by hand so only the last test reads the org's `Default` record):

```apex
@IsTest
private class MapboxTruckRouteTest {
  private static final TruckRoute.Point MONTREAL = new TruckRoute.Point(
    45.5019,
    -73.5674
  );
  private static final TruckRoute.Point TORONTO = new TruckRoute.Point(
    43.6532,
    -79.3832
  );
  private static final String MAIN_GEOMETRY = '_p~iF~ps|U_ulLnnqC_mqNvxq`@';
  private static final String NO_ROUTE = '{"code":"NoRoute","message":"No route found","routes":[]}';
  private static final String BORDER_ALERT = '{"type":"alert","subtype":"countryBorderCrossing","refresh_type":"static","geometry_index_start":0,"geometry_index_end":1,"details":{"actual_value":"CA,US","message":"Crossing the border of the countries of CA and US."}}';

  /** Answers the n-th callout with the n-th queued response (the last one repeats) and records every endpoint. */
  private class SequenceMock implements HttpCalloutMock {
    List<Integer> statuses = new List<Integer>();
    List<String> bodies = new List<String>();
    List<String> endpoints = new List<String>();

    SequenceMock reply(Integer status, String body) {
      statuses.add(status);
      bodies.add(body);
      return this;
    }

    public HttpResponse respond(HttpRequest req) {
      endpoints.add(req.getEndpoint());
      Integer i = Math.min(endpoints.size(), statuses.size()) - 1;
      HttpResponse res = new HttpResponse();
      res.setStatusCode(statuses[i]);
      res.setHeader('Content-Type', 'application/json');
      res.setBody(bodies[i]);
      return res;
    }
  }

  private class ThrowingMock implements HttpCalloutMock {
    Integer calls = 0;

    public HttpResponse respond(HttpRequest req) {
      calls++;
      throw new CalloutException(
        'Read timed out: https://api.mapbox.com/directions/v5?access_token=pk.test'
      );
    }
  }

  /** Sets the test token and installs a fresh recording mock. */
  private static SequenceMock mock() {
    MapboxHttp.tokenOverride = 'pk.test';
    SequenceMock m = new SequenceMock();
    Test.setMock(HttpCalloutMock.class, m);
    return m;
  }

  /** The default 53 ft dry van, built by hand so the tests do not depend on the org's setting record. */
  private static TruckRoute.Profile truck() {
    TruckRoute.Profile p = new TruckRoute.Profile();
    p.heightM = 4.11;
    p.widthM = 2.6;
    p.weightT = 36.29;
    p.alternatives = true;
    p.approxFactor = 1.2;
    p.timeoutMs = 8000;
    return p;
  }

  /** One route object with a single leg; notification is a notification object's JSON or null. */
  private static String routeJson(
    Decimal metres,
    Decimal seconds,
    String geometry,
    String notification
  ) {
    return '{"geometry":"' +
      geometry +
      '","distance":' +
      metres +
      ',"duration":' +
      seconds +
      ',"weight":' +
      seconds +
      ',"weight_name":"auto","legs":[{"summary":"A-20, ON-401","distance":' +
      metres +
      ',"duration":' +
      seconds +
      ',"steps":[],"notifications":[' +
      (notification == null ? '' : notification) +
      ']}]}';
  }

  private static String answer(List<String> routes) {
    return '{"code":"Ok","routes":[' +
      String.join(routes, ',') +
      '],"waypoints":[{"name":"","location":[-73.5674,45.5019]},{"name":"","location":[-79.3832,43.6532]}],"uuid":"test"}';
  }

  private static String violation(String subtype) {
    return '{"type":"violation","subtype":"' +
      subtype +
      '","refresh_type":"static","geometry_index_start":3,"geometry_index_end":5,"details":{"actual_value":"2.00","requested_value":"4.11","unit":"meters","message":"The vehicle is more than the permissible limit of the road."}}';
  }

  private static String cleanTruckAnswer() {
    return answer(
      new List<String>{ routeJson(541234.5, 19845, MAIN_GEOMETRY, null) }
    );
  }

  @IsTest
  static void truckRequestCarriesTheTruckLimitsAndAlternatives() {
    SequenceMock m = mock().reply(200, cleanTruckAnswer());
    TruckRoute.Profile noAlternatives = truck();
    noAlternatives.alternatives = false;
    Test.startTest();
    MapboxTruckRoute.route(MONTREAL, TORONTO, truck());
    MapboxTruckRoute.route(MONTREAL, TORONTO, noAlternatives);
    Test.stopTest();
    System.assertEquals(
      2,
      m.endpoints.size(),
      'one request per clean truck route'
    );
    String url = m.endpoints[0];
    System.assert(
      url.startsWith(
        'https://api.mapbox.com/directions/v5/mapbox/driving/-73.567400,45.501900;-79.383200,43.653200?'
      ),
      url
    );
    for (
      String part : new List<String>{
        'alternatives=true',
        'overview=simplified',
        'geometries=polyline',
        'steps=false',
        'max_height=4.11',
        'max_width=2.60',
        'max_weight=36.29',
        'notifications=all',
        'access_token=pk.test'
      }
    ) {
      System.assert(url.contains(part), part + ' missing from ' + url);
    }
    System.assert(
      m.endpoints[1].contains('alternatives=false'),
      m.endpoints[1]
    );
  }

  @IsTest
  static void cleanTruckAnswerKeepsUpToThreeCompliantRoutesInMilesAndHours() {
    SequenceMock m = mock()
      .reply(
        200,
        answer(
          new List<String>{
            routeJson(541234.5, 19845, MAIN_GEOMETRY, null),
            routeJson(612345.6, 21912, 'alt1', null),
            routeJson(498765, 18000, 'breaksWeight', violation('maxWeight')),
            routeJson(700321, 23600, 'alt2', null),
            routeJson(530000, 19000, 'fourth', null)
          }
        )
      );
    Test.startTest();
    TruckRoute.Result r = MapboxTruckRoute.route(MONTREAL, TORONTO, truck());
    Test.stopTest();
    System.assertEquals('Found', r.status);
    System.assertEquals('Truck', r.routeType);
    System.assertEquals(null, r.message);
    System.assertEquals(1, m.endpoints.size(), 'no fallback request');
    System.assertEquals(
      3,
      r.routes.size(),
      'the main route and two compliant alternatives, never more than 3'
    );
    System.assertEquals(336.3, r.routes[0].miles, '541,234.5 m');
    System.assertEquals(5.5, r.routes[0].hours, '19,845 s');
    System.assertEquals(MAIN_GEOMETRY, r.routes[0].polyline5);
    System.assertEquals('alt1', r.routes[1].polyline5);
    System.assertEquals(380.5, r.routes[1].miles, '612,345.6 m');
    System.assertEquals(6.1, r.routes[1].hours, '21,912 s');
    System.assertEquals(
      'alt2',
      r.routes[2].polyline5,
      'the alternative that breaks the weight limit is left out'
    );
    System.assertEquals(435.2, r.routes[2].miles, '700,321 m');
    System.assertEquals(6.6, r.routes[2].hours, '23,600 s');
  }

  @IsTest
  static void anAlertIsNotATruckLimit() {
    SequenceMock m = mock()
      .reply(
        200,
        answer(
          new List<String>{
            routeJson(541234.5, 19845, MAIN_GEOMETRY, BORDER_ALERT)
          }
        )
      );
    Test.startTest();
    TruckRoute.Result r = MapboxTruckRoute.route(MONTREAL, TORONTO, truck());
    Test.stopTest();
    System.assertEquals('Truck', r.routeType, 'a border crossing is an alert');
    System.assertEquals(1, r.routes.size());
    System.assertEquals(1, m.endpoints.size());
  }

  @IsTest
  static void mainRouteBreakingATruckLimitFallsBackToARegularRoute() {
    String regular = answer(
      new List<String>{
        routeJson(530000, 19000, 'regular', null),
        routeJson(980000.4, 36000, 'regularAlt', null)
      }
    );
    Test.startTest();
    for (
      String subtype : new List<String>{ 'maxHeight', 'maxWidth', 'maxWeight' }
    ) {
      SequenceMock m = mock()
        .reply(
          200,
          answer(
            new List<String>{
              routeJson(541234.5, 19845, MAIN_GEOMETRY, violation(subtype)),
              routeJson(612345.6, 21912, 'alt1', null)
            }
          )
        )
        .reply(200, regular);
      TruckRoute.Result r = MapboxTruckRoute.route(MONTREAL, TORONTO, truck());
      System.assertEquals(
        2,
        m.endpoints.size(),
        subtype + ': the truck request, then the regular one'
      );
      System.assert(m.endpoints[0].contains('max_height=4.11'), m.endpoints[0]);
      String second = m.endpoints[1];
      System.assert(
        !second.contains('max_height') &&
          !second.contains('max_width') &&
          !second.contains('max_weight') &&
          !second.contains('notifications'),
        second
      );
      System.assert(
        second.contains('alternatives=true') &&
        second.contains('access_token=pk.test'),
        second
      );
      System.assertEquals('Found', r.status, subtype);
      System.assertEquals('Regular', r.routeType, subtype);
      System.assertEquals(
        2,
        r.routes.size(),
        subtype + ': the regular routes, not the truck alternative'
      );
      System.assertEquals('regular', r.routes[0].polyline5, subtype);
      System.assertEquals(329.3, r.routes[0].miles, subtype);
      System.assertEquals(5.3, r.routes[0].hours, subtype);
      System.assertEquals(608.9, r.routes[1].miles, subtype);
      System.assertEquals(10.0, r.routes[1].hours, subtype);
    }
    Test.stopTest();
  }

  @IsTest
  static void noTruckRouteAlsoFallsBackToARegularRoute() {
    String regular = answer(
      new List<String>{ routeJson(530000, 19000, 'regular', null) }
    );
    Test.startTest();
    SequenceMock noRoute = mock().reply(200, NO_ROUTE).reply(200, regular);
    TruckRoute.Result afterNoRoute = MapboxTruckRoute.route(
      MONTREAL,
      TORONTO,
      truck()
    );
    SequenceMock empty = mock()
      .reply(200, '{"code":"Ok","routes":[]}')
      .reply(200, regular);
    TruckRoute.Result afterEmpty = MapboxTruckRoute.route(
      MONTREAL,
      TORONTO,
      truck()
    );
    Test.stopTest();
    for (
      TruckRoute.Result r : new List<TruckRoute.Result>{
        afterNoRoute,
        afterEmpty
      }
    ) {
      System.assertEquals('Found', r.status);
      System.assertEquals('Regular', r.routeType);
      System.assertEquals(1, r.routes.size());
      System.assertEquals(329.3, r.routes[0].miles);
    }
    System.assertEquals(2, noRoute.endpoints.size());
    System.assert(
      !noRoute.endpoints[1].contains('max_weight'),
      noRoute.endpoints[1]
    );
    System.assertEquals(2, empty.endpoints.size());
  }

  @IsTest
  static void noRouteEvenWithoutTruckLimitsIsNoRoute() {
    SequenceMock m = mock().reply(200, NO_ROUTE);
    Test.startTest();
    TruckRoute.Result r = MapboxTruckRoute.route(MONTREAL, TORONTO, truck());
    Test.stopTest();
    System.assertEquals('No route', r.status);
    System.assertEquals(null, r.routeType);
    System.assert(r.routes.isEmpty());
    System.assertEquals(null, r.message);
    System.assertEquals(2, m.endpoints.size(), 'two requests at most');
  }

  @IsTest
  static void anHttpErrorIsUnavailableWithoutTheToken() {
    Test.startTest();
    SequenceMock unauthorized = mock()
      .reply(401, '{"message":"Not Authorized - Invalid Token"}');
    TruckRoute.Result first = MapboxTruckRoute.route(
      MONTREAL,
      TORONTO,
      truck()
    );
    SequenceMock regularFails = mock()
      .reply(
        200,
        answer(
          new List<String>{
            routeJson(541234.5, 19845, MAIN_GEOMETRY, violation('maxHeight'))
          }
        )
      )
      .reply(403, '{"message":"Forbidden"}');
    TruckRoute.Result second = MapboxTruckRoute.route(
      MONTREAL,
      TORONTO,
      truck()
    );
    Test.stopTest();
    System.assertEquals('Unavailable', first.status);
    System.assertEquals(TruckRoute.UNAVAILABLE, first.message);
    System.assertEquals(null, first.routeType);
    System.assert(first.routes.isEmpty());
    System.assert(!first.message.contains('pk.'), first.message);
    System.assertEquals(
      1,
      unauthorized.endpoints.size(),
      'a 4xx is not retried and does not fall back'
    );
    System.assertEquals('Unavailable', second.status);
    System.assertEquals(TruckRoute.UNAVAILABLE, second.message);
    System.assertEquals(2, regularFails.endpoints.size());
  }

  @IsTest
  static void aCalloutFailureIsUnavailableWithoutTheToken() {
    MapboxHttp.tokenOverride = 'pk.test';
    ThrowingMock m = new ThrowingMock();
    Test.setMock(HttpCalloutMock.class, m);
    Test.startTest();
    TruckRoute.Result r = MapboxTruckRoute.route(MONTREAL, TORONTO, truck());
    Test.stopTest();
    System.assertEquals('Unavailable', r.status);
    System.assertEquals(TruckRoute.UNAVAILABLE, r.message);
    System.assert(!r.message.contains('pk.test'), r.message);
    System.assert(!r.message.contains('access_token'), r.message);
    System.assertEquals(1, m.calls, 'a callout failure is not retried');
  }

  @IsTest
  static void aServerErrorIsRetriedOnce() {
    Test.startTest();
    SequenceMock recovers = mock()
      .reply(503, 'Service Unavailable')
      .reply(200, cleanTruckAnswer());
    TruckRoute.Result recovered = MapboxTruckRoute.route(
      MONTREAL,
      TORONTO,
      truck()
    );
    SequenceMock down = mock().reply(503, 'Service Unavailable');
    TruckRoute.Result stillDown = MapboxTruckRoute.route(
      MONTREAL,
      TORONTO,
      truck()
    );
    Test.stopTest();
    System.assertEquals('Truck', recovered.routeType);
    System.assertEquals(1, recovered.routes.size());
    System.assertEquals(2, recovers.endpoints.size(), 'one retry');
    System.assert(
      recovers.endpoints[1].contains('max_height=4.11'),
      'the same truck request is resent'
    );
    System.assertEquals('Unavailable', stillDown.status);
    System.assertEquals(
      2,
      down.endpoints.size(),
      'one retry, then Unavailable'
    );
  }

  @IsTest
  static void aBlankTokenOrAMissingCoordinateMakesNoCallout() {
    SequenceMock m = mock().reply(200, cleanTruckAnswer());
    MapboxHttp.tokenOverride = '';
    Test.startTest();
    TruckRoute.Result noToken = MapboxTruckRoute.route(
      MONTREAL,
      TORONTO,
      truck()
    );
    MapboxHttp.tokenOverride = 'pk.test';
    TruckRoute.Result noLatitude = MapboxTruckRoute.route(
      new TruckRoute.Point(null, -73.5674),
      TORONTO,
      truck()
    );
    TruckRoute.Result noDestination = MapboxTruckRoute.route(
      MONTREAL,
      null,
      truck()
    );
    Integer callouts = Limits.getCallouts();
    Test.stopTest();
    System.assertEquals(0, callouts);
    System.assert(m.endpoints.isEmpty(), String.valueOf(m.endpoints));
    for (
      TruckRoute.Result r : new List<TruckRoute.Result>{
        noToken,
        noLatitude,
        noDestination
      }
    ) {
      System.assertEquals('Unavailable', r.status);
      System.assertEquals(TruckRoute.UNAVAILABLE, r.message);
    }
  }

  @IsTest
  static void anUnreadableAnswerIsUnavailable() {
    Test.startTest();
    mock().reply(200, 'not json');
    TruckRoute.Result notJson = MapboxTruckRoute.route(
      MONTREAL,
      TORONTO,
      truck()
    );
    mock()
      .reply(
        200,
        '{"code":"Ok","routes":[{"geometry":"x","duration":10,"legs":[]}]}'
      );
    TruckRoute.Result noDistance = MapboxTruckRoute.route(
      MONTREAL,
      TORONTO,
      truck()
    );
    Test.stopTest();
    System.assertEquals('Unavailable', notJson.status);
    System.assertEquals(TruckRoute.UNAVAILABLE, notJson.message);
    System.assertEquals('Unavailable', noDistance.status);
    System.assertEquals(TruckRoute.UNAVAILABLE, noDistance.message);
  }

  @IsTest
  static void defaultProfileDescribesTheTruckAndKeysItsLimits() {
    TruckRoute.Profile fallback = TruckRoute.profileFrom(null);
    System.assertEquals('h4.11w2.60t36.29', fallback.key());
    System.assertEquals(true, fallback.alternatives);
    System.assertEquals('1.2', fallback.approxFactor.toPlainString());
    System.assertEquals(8000, fallback.timeoutMs);

    TruckRoute.Profile custom = TruckRoute.profileFrom(
      (Truck_Routing_Setting__mdt) JSON.deserialize(
        '{"Height_M__c":4.5,"Width_M__c":2.5,"Weight_T__c":30,"Alternatives__c":false,"Approx_Factor__c":1.25,"Timeout_Ms__c":6000}',
        Truck_Routing_Setting__mdt.class
      )
    );
    System.assertEquals(
      'h4.50w2.50t30.00',
      custom.key(),
      'another truck gets another key'
    );
    System.assertEquals(false, custom.alternatives);
    System.assertEquals('1.25', custom.approxFactor.toPlainString());
    System.assertEquals(6000, custom.timeoutMs);

    TruckRoute.Profile partial = TruckRoute.profileFrom(
      (Truck_Routing_Setting__mdt) JSON.deserialize(
        '{"Height_M__c":4.2}',
        Truck_Routing_Setting__mdt.class
      )
    );
    System.assertEquals(
      'h4.20w2.60t36.29',
      partial.key(),
      'blank fields keep the default truck'
    );
    System.assertEquals(8000, partial.timeoutMs);

    TruckRoute.Profile fromOrg = TruckRoute.defaultProfile();
    System.assert(
      Pattern.matches(
        'h\\d+\\.\\d{2}w\\d+\\.\\d{2}t\\d+\\.\\d{2}',
        fromOrg.key()
      ),
      fromOrg.key()
    );
    System.assertNotEquals(null, fromOrg.alternatives);
    System.assertNotEquals(null, fromOrg.approxFactor);
    System.assertNotEquals(null, fromOrg.timeoutMs);
  }
}
```

The route numbers are exact: 541,234.5 m / 1,609.344 = 336.31 → `336.3` mi; 612,345.6 m → `380.5`; 700,321 m → `435.2`; 530,000 m → `329.3`; 980,000.4 m → `608.9`; 19,845 s / 3,600 = 5.51 → `5.5` h; 21,912 s → `6.1`; 23,600 s → `6.6`; 19,000 s → `5.3`; 36,000 s → `10.0`. None sits on a rounding tie.

- [ ] **Step 2: Deploy the test alone to see it fail to compile**

Run: `sf project deploy start -o sandbox --source-dir force-app/main/default/classes/MapboxTruckRouteTest.cls -l NoTestRun --async --json | python3 -c "import json,sys; s=sys.stdin.read(); print(json.loads(s[s.index('{'):])['result']['id'])"`

Expected: a deploy id (`0Af…`). Then poll, repeating the same command while it prints `InProgress`, `Pending` or a wait-timeout name:

Run: `sf project deploy report -o sandbox --job-id <id> -w 2 --json | python3 -c "import json,sys; s=sys.stdin.read(); j=json.loads(s[s.index('{'):]); r=j.get('result') or {}; cf=(r.get('details') or {}).get('componentFailures') or []; cf=cf if isinstance(cf,list) else [cf]; print(r.get('status') or j.get('name'), [(d.get('fullName'), d.get('problem')) for d in cf][:3])"`

Expected: `Failed` with a problem naming `TruckRoute`, `MapboxHttp` or `MapboxTruckRoute` ("Invalid type" or "Variable does not exist"). If the problem names `Truck_Routing_Setting__mdt`, Task 1 is not deployed: stop and report.

- [ ] **Step 3: `MapboxHttp` and the `MapboxGeocoder` delegation**

Create `force-app/main/default/classes/MapboxHttp.cls-meta.xml` with the same content as the test's meta file (API 64.0, Active), and `force-app/main/default/classes/MapboxHttp.cls`:

```apex
/**
 * The shared door to the company's Mapbox account for Apex callouts: the token read and a send with one retry.
 * Token: TPRO_KPI__c org default, Mapbox_Api_Key__c (public pk. token). Remote site: MapBox.
 * Used by MapboxGeocoder (geocoding, static maps) and MapboxTruckRoute (Directions API). The token travels
 * only in request URLs: it is never logged and never put in an exception message.
 */
public with sharing class MapboxHttp {
  public static final String BASE = 'https://api.mapbox.com';

  // Test hook: tests set 'pk.test' (or '' for a missing token) instead of writing TPRO_KPI__c.
  @TestVisible
  private static String tokenOverride;

  public static String token() {
    if (tokenOverride != null) {
      return tokenOverride;
    }
    return TPRO_KPI__c.getOrgDefaults().Mapbox_Api_Key__c;
  }

  /** Sends the request, retries once on a server error (5xx); a callout failure becomes a MapboxException without the URL. */
  public static HttpResponse send(HttpRequest req) {
    Http http = new Http();
    try {
      HttpResponse res = http.send(req);
      if (res.getStatusCode() >= 500) {
        res = http.send(req); // one retry
      }
      return res;
    } catch (System.CalloutException e) {
      throw new MapboxException('Mapbox is not reachable right now');
    }
  }
}
```

In `force-app/main/default/classes/MapboxGeocoder.cls`, replace lines 5-6 of the class comment:

```apex
 * Response parsing lives in MapboxResponseParser (see that class's doc comment for why): this
 * class keeps the callout itself (build the request, send with one retry, callout-error mapping).
```

with:

```apex
 * Response parsing lives in MapboxResponseParser (see that class's doc comment for why): this
 * class builds the request and maps the HTTP status. The token read and the send with one retry
 * (callout-error mapping included) live in MapboxHttp, shared with MapboxTruckRoute.
```

replace line 9:

```apex
  private static final String BASE = 'https://api.mapbox.com';
```

with:

```apex
  private static final String BASE = MapboxHttp.BASE;
```

replace the body of `token()` (lines 29-32):

```apex
  @TestVisible
  private static String token() {
    return TPRO_KPI__c.getOrgDefaults().Mapbox_Api_Key__c;
  }
```

with:

```apex
  @TestVisible
  private static String token() {
    return MapboxHttp.token();
  }
```

and replace `sendWithRetry` (lines 76-87):

```apex
  private static HttpResponse sendWithRetry(HttpRequest req) {
    Http http = new Http();
    try {
      HttpResponse res = http.send(req);
      if (res.getStatusCode() >= 500) {
        res = http.send(req); // one retry
      }
      return res;
    } catch (System.CalloutException e) {
      throw new MapboxException('Mapbox is not reachable right now');
    }
  }
```

with:

```apex
  private static HttpResponse sendWithRetry(HttpRequest req) {
    return MapboxHttp.send(req);
  }
```

Nothing else in `MapboxGeocoder` changes; `MapboxGeocoderTest` keeps writing `TPRO_KPI__c` (its `tokenOverride` stays null, so `MapboxHttp.token()` reads the org default exactly as before, and its retry, 401 and callout-exception tests now exercise `MapboxHttp.send`).

- [ ] **Step 4: `TruckRoute` — value types and the truck profile**

Create `force-app/main/default/classes/TruckRoute.cls-meta.xml` (API 64.0, Active) and `force-app/main/default/classes/TruckRoute.cls`:

```apex
/**
 * Value types for Mapbox truck routes (phase 7) and the truck profile from Truck_Routing_Setting__mdt.Default.
 * Profile.key() (height, width and weight rounded to 2 decimals) is part of every stored route's key, so a new
 * truck never reuses an old route; the key is the same for the truck request and its regular fallback.
 */
public with sharing class TruckRoute {
  public static final String UNAVAILABLE = 'The truck route is not available right now.';

  // The 53 ft dry-van tractor-trailer at 80,000 lb, 13 ft 6 in high, 102 in wide (spec §3).
  private static final Decimal DEFAULT_HEIGHT_M = 4.11;
  private static final Decimal DEFAULT_WIDTH_M = 2.6;
  private static final Decimal DEFAULT_WEIGHT_T = 36.29;
  private static final Decimal DEFAULT_APPROX_FACTOR = 1.2;
  private static final Integer DEFAULT_TIMEOUT_MS = 8000;

  public class Point {
    public Decimal lat;
    public Decimal lng;

    public Point(Decimal lat, Decimal lng) {
      this.lat = lat;
      this.lng = lng;
    }
  }

  public class Profile {
    public Decimal heightM;
    public Decimal widthM;
    public Decimal weightT;
    public Boolean alternatives;
    public Decimal approxFactor;
    public Integer timeoutMs;

    /** 'h4.11w2.60t36.29' */
    public String key() {
      return 'h' +
        heightM.setScale(2) +
        'w' +
        widthM.setScale(2) +
        't' +
        weightT.setScale(2);
    }
  }

  public class Line {
    @AuraEnabled
    public Decimal miles;
    @AuraEnabled
    public Decimal hours;
    public String polyline5;
  }

  public class Result {
    public String status; // 'Found' | 'No route' | 'Unavailable'
    public String routeType; // 'Truck' | 'Regular' | null
    public List<Line> routes = new List<Line>();
    public String message;
  }

  public static Profile defaultProfile() {
    return profileFrom(Truck_Routing_Setting__mdt.getInstance('Default'));
  }

  /** A missing record or a blank field falls back to the default truck, so a half-filled setting never breaks routing. */
  @TestVisible
  private static Profile profileFrom(Truck_Routing_Setting__mdt setting) {
    Profile p = new Profile();
    p.heightM = setting?.Height_M__c ?? DEFAULT_HEIGHT_M;
    p.widthM = setting?.Width_M__c ?? DEFAULT_WIDTH_M;
    p.weightT = setting?.Weight_T__c ?? DEFAULT_WEIGHT_T;
    p.alternatives = setting?.Alternatives__c ?? true;
    p.approxFactor = setting?.Approx_Factor__c ?? DEFAULT_APPROX_FACTOR;
    p.timeoutMs = setting?.Timeout_Ms__c == null
      ? DEFAULT_TIMEOUT_MS
      : setting.Timeout_Ms__c.intValue();
    return p;
  }
}
```

- [ ] **Step 5: `MapboxTruckRoute` — the Directions request and the regular fallback**

The answer shape comes from the Directions API reference: the body's `code` is `Ok`, `NoRoute` or `NoSegment` on HTTP 200 (other codes come with 4xx statuses); `routes[]` holds `distance` (metres), `duration` (seconds), `geometry` (polyline5 with `geometries=polyline`) and `legs[]`; each leg may carry `notifications[]` of `{ "type": "violation" | "alert", "subtype": "maxHeight" | "maxWidth" | "maxWeight" | "countryBorderCrossing" | …, "details": { … } }`. A `maxHeight`/`maxWidth`/`maxWeight` violation is only reported when the matching `max_` parameter is sent. The request parameter `notifications` defaults to `all`; the truck request sends `notifications=all` explicitly so the fallback trigger does not depend on that default.

Create `force-app/main/default/classes/MapboxTruckRoute.cls-meta.xml` (API 64.0, Active) and `force-app/main/default/classes/MapboxTruckRoute.cls`:

```apex
/**
 * Truck routes from the Mapbox Directions API (phase 7, spec §3, R79): profile mapbox/driving with the truck's
 * height and width (metres) and weight (metric tons), alternatives from the profile, simplified polyline5 geometry.
 * When the main truck route breaks a truck limit (a violation notification with subtype maxHeight, maxWidth or
 * maxWeight on one of its legs) or Mapbox finds no truck route, one more request without the truck limits asks for
 * a regular driving route, returned as routeType 'Regular'; when that finds nothing either, the status is 'No route'.
 * A truck alternative that breaks a limit is left out: no partially compliant truck route is ever returned.
 * A blank token, a point without coordinates, an HTTP error, a callout failure or an unreadable answer is
 * 'Unavailable' with TruckRoute.UNAVAILABLE. The token only ever appears in the request URL. No DML.
 */
public with sharing class MapboxTruckRoute {
  private static final Decimal METRES_PER_MILE = 1609.344;
  private static final Decimal SECONDS_PER_HOUR = 3600;
  private static final Integer MAX_ROUTES = 3;
  private static final Set<String> TRUCK_LIMITS = new Set<String>{
    'maxHeight',
    'maxWidth',
    'maxWeight'
  };

  public static TruckRoute.Result route(
    TruckRoute.Point origin,
    TruckRoute.Point destination,
    TruckRoute.Profile profile
  ) {
    String token = MapboxHttp.token();
    if (
      String.isBlank(token) ||
      !located(origin) ||
      !located(destination) ||
      profile == null
    ) {
      return unavailable();
    }
    try {
      List<Object> truckRoutes = ask(origin, destination, profile, true, token);
      if (!truckRoutes.isEmpty() && !breaksTruckLimit(truckRoutes[0])) {
        return found('Truck', truckRoutes);
      }
      List<Object> regularRoutes = ask(
        origin,
        destination,
        profile,
        false,
        token
      );
      return regularRoutes.isEmpty()
        ? noRoute()
        : found('Regular', regularRoutes);
    } catch (Exception e) {
      // MapboxException (HTTP error or callout failure), JSONException or a cast on an unexpected answer.
      return unavailable();
    }
  }

  /** The routes of one Directions answer, main first; empty when the answer's code is not Ok (NoRoute, NoSegment). */
  private static List<Object> ask(
    TruckRoute.Point origin,
    TruckRoute.Point destination,
    TruckRoute.Profile profile,
    Boolean truck,
    String token
  ) {
    HttpRequest req = new HttpRequest();
    req.setEndpoint(endpoint(origin, destination, profile, truck, token));
    req.setMethod('GET');
    if (profile.timeoutMs != null) {
      req.setTimeout(profile.timeoutMs);
    }
    HttpResponse res = MapboxHttp.send(req);
    if (res.getStatusCode() != 200) {
      throw new MapboxException(
        'Mapbox routing failed: HTTP ' + res.getStatusCode()
      );
    }
    Map<String, Object> answer = (Map<String, Object>) JSON.deserializeUntyped(
      res.getBody()
    );
    if (String.valueOf(answer.get('code')) != 'Ok') {
      return new List<Object>();
    }
    return listOf(answer.get('routes'));
  }

  /** The truck request adds max_height, max_width, max_weight and notifications=all; the regular request has none of them. */
  private static String endpoint(
    TruckRoute.Point origin,
    TruckRoute.Point destination,
    TruckRoute.Profile profile,
    Boolean truck,
    String token
  ) {
    String url =
      MapboxHttp.BASE +
      '/directions/v5/mapbox/driving/' +
      coordinates(origin) +
      ';' +
      coordinates(destination) +
      '?alternatives=' +
      (profile.alternatives == true) +
      '&overview=simplified&geometries=polyline&steps=false';
    if (truck) {
      url +=
        '&max_height=' +
        twoDecimals(profile.heightM) +
        '&max_width=' +
        twoDecimals(profile.widthM) +
        '&max_weight=' +
        twoDecimals(profile.weightT) +
        '&notifications=all';
    }
    return url + '&access_token=' + token;
  }

  /** True when a leg of the route carries a violation of the truck's height, width or weight. */
  private static Boolean breaksTruckLimit(Object route) {
    for (Object leg : listOf(((Map<String, Object>) route).get('legs'))) {
      for (
        Object item : listOf(((Map<String, Object>) leg).get('notifications'))
      ) {
        Map<String, Object> notification = (Map<String, Object>) item;
        if (
          String.valueOf(notification.get('type')) == 'violation' &&
          TRUCK_LIMITS.contains(String.valueOf(notification.get('subtype')))
        ) {
          return true;
        }
      }
    }
    return false;
  }

  /** Up to MAX_ROUTES routes, main first; a truck alternative that breaks a limit is left out. */
  private static TruckRoute.Result found(
    String routeType,
    List<Object> routes
  ) {
    TruckRoute.Result result = new TruckRoute.Result();
    result.status = 'Found';
    result.routeType = routeType;
    for (Object route : routes) {
      Boolean keep =
        result.routes.size() < MAX_ROUTES &&
        !(routeType == 'Truck' && breaksTruckLimit(route));
      if (keep) {
        result.routes.add(line((Map<String, Object>) route));
      }
    }
    return result;
  }

  /** Metres to miles and seconds to hours, one decimal; a route without either makes the answer unreadable. */
  private static TruckRoute.Line line(Map<String, Object> route) {
    Object distance = route.get('distance');
    Object duration = route.get('duration');
    if (distance == null || duration == null) {
      throw new MapboxException(
        'Mapbox answered a route without distance or duration'
      );
    }
    TruckRoute.Line out = new TruckRoute.Line();
    out.miles = (decimalOf(distance) / METRES_PER_MILE).setScale(1);
    out.hours = (decimalOf(duration) / SECONDS_PER_HOUR).setScale(1);
    Object geometry = route.get('geometry');
    out.polyline5 = geometry instanceof String ? (String) geometry : null;
    return out;
  }

  private static TruckRoute.Result noRoute() {
    TruckRoute.Result result = new TruckRoute.Result();
    result.status = 'No route';
    return result;
  }

  private static TruckRoute.Result unavailable() {
    TruckRoute.Result result = new TruckRoute.Result();
    result.status = 'Unavailable';
    result.message = TruckRoute.UNAVAILABLE;
    return result;
  }

  private static Boolean located(TruckRoute.Point p) {
    return p != null && p.lat != null && p.lng != null;
  }

  /** 'lng,lat' with 6 decimals (about 0.1 m), the order the Directions API expects. */
  private static String coordinates(TruckRoute.Point p) {
    return p.lng.setScale(6).toPlainString() +
      ',' +
      p.lat.setScale(6).toPlainString();
  }

  private static String twoDecimals(Decimal value) {
    return value.setScale(2).toPlainString();
  }

  private static Decimal decimalOf(Object value) {
    return Decimal.valueOf(String.valueOf(value));
  }

  private static List<Object> listOf(Object value) {
    return value instanceof List<Object>
      ? (List<Object>) value
      : new List<Object>();
  }
}
```

- [ ] **Step 6: Manifest**

In `manifest/package.xml`, replace:

```xml
        <members>MapboxResponseParser</members>
```

with:

```xml
        <members>MapboxResponseParser</members>
        <members>MapboxHttp</members>
        <members>MapboxTruckRoute</members>
        <members>MapboxTruckRouteTest</members>
        <members>TruckRoute</members>
```

Run: `grep -c -E "<members>(MapboxHttp|MapboxTruckRoute|MapboxTruckRouteTest|TruckRoute)</members>" manifest/package.xml`

Expected: `4`.

- [ ] **Step 7: Deploy the classes and run both Mapbox test classes**

Run: `sf project deploy start -o sandbox --source-dir force-app/main/default/classes/MapboxHttp.cls --source-dir force-app/main/default/classes/TruckRoute.cls --source-dir force-app/main/default/classes/MapboxTruckRoute.cls --source-dir force-app/main/default/classes/MapboxTruckRouteTest.cls --source-dir force-app/main/default/classes/MapboxGeocoder.cls -l RunSpecifiedTests -t MapboxTruckRouteTest -t MapboxGeocoderTest --async --json | python3 -c "import json,sys; s=sys.stdin.read(); print(json.loads(s[s.index('{'):])['result']['id'])"`

Expected: a deploy id. Poll, repeating while it prints `InProgress`, `Pending` or a wait-timeout name:

Run: `sf project deploy report -o sandbox --job-id <id> -w 2 --json | python3 -c "import json,sys; s=sys.stdin.read(); j=json.loads(s[s.index('{'):]); r=j.get('result') or {}; d=r.get('details') or {}; t=d.get('runTestResult') or {}; L=lambda v: v if isinstance(v,list) else ([v] if v else []); print(r.get('status') or j.get('name'), 'tests', r.get('numberTestsCompleted'), '/', r.get('numberTestsTotal'), 'failures', r.get('numberTestErrors')); [print(x.get('fullName'), '->', x.get('problem')) for x in L(d.get('componentFailures'))]; [print(x.get('name'), x.get('methodName'), '->', (x.get('message') or '')[:160]) for x in L(t.get('failures'))]; [print('coverage', x.get('name'), '->', x.get('message')) for x in L(t.get('codeCoverageWarnings'))]"`

Expected: `Succeeded tests 21 / 21 failures 0` (12 in `MapboxTruckRouteTest`, 9 in `MapboxGeocoderTest`), no `coverage` line (each deployed class must reach 75 %). If a `MapboxTruckRouteTest` method fails, its message names the assertion; fix the class, not the test, unless the test contradicts the spec or the Directions reference. If a `MapboxGeocoderTest` method fails, the delegation in Step 3 changed behaviour: restore it to plain delegation.

- [ ] **Step 8: PMD, and the token never logged**

Run: `/private/tmp/pmd_install/pmd-bin-7.15.0/bin/pmd check --dir force-app --rulesets config/pmd-ruleset.xml --minimum-priority 3 --format text --fail-on-violation; echo "pmd exit $?"`

Expected: no violation lines, `pmd exit 0`.

Run: `grep -n "System.debug" force-app/main/default/classes/MapboxHttp.cls force-app/main/default/classes/TruckRoute.cls force-app/main/default/classes/MapboxTruckRoute.cls; echo "debug grep exit $?"; git diff --quiet -- force-app/main/default/classes/MapboxGeocoderTest.cls; echo "geocoder test unchanged $?"`

Expected: no `System.debug` line, `debug grep exit 1`, `geocoder test unchanged 0`.

- [ ] **Step 9: Commit**

```bash
git add force-app/main/default/classes/MapboxHttp.cls force-app/main/default/classes/MapboxHttp.cls-meta.xml force-app/main/default/classes/TruckRoute.cls force-app/main/default/classes/TruckRoute.cls-meta.xml force-app/main/default/classes/MapboxTruckRoute.cls force-app/main/default/classes/MapboxTruckRoute.cls-meta.xml force-app/main/default/classes/MapboxTruckRouteTest.cls force-app/main/default/classes/MapboxTruckRouteTest.cls-meta.xml force-app/main/default/classes/MapboxGeocoder.cls manifest/package.xml
git commit -m "Add Mapbox truck routes with a regular-route fallback"
```

Expected: one commit, 10 files. lint-staged runs Prettier on the staged files; the code above is already Prettier-formatted, so nothing should change. Do not stage `.vscode/settings.json` or any `* 2.*` file.

#### Contract notes (Task 2)

1. **`notifications=all` on the truck request.** The contract's URL has no notifications parameter. The Directions reference says `notifications` defaults to `all` (so the violations arrive anyway). The truck request sends it explicitly so the fallback trigger does not rely on that default; the regular request does not send it.
2. **URL number formats.** Coordinates are `lng,lat` with 6 decimals and `max_height`/`max_width`/`max_weight` with 2 decimals (`toPlainString`), so the default truck sends `max_width=2.60`. Tests assert these exact strings.
3. **Violating truck alternatives are dropped.** The contract only talks about `routes[0]`. Spec §7 also says "no partially compliant truck route is ever shown or stored", so a truck *alternative* with a `maxHeight`/`maxWidth`/`maxWeight` violation is left out of a `Truck` result. A violation on `routes[0]` still triggers the regular request, as the contract says.
4. **"No route" covers any non-`Ok` code on HTTP 200.** That is `NoRoute` and also `NoSegment`, plus `Ok` with an empty `routes`. This is wider than the contract's `NoRoute`. The reference lists both codes as HTTP 200 with no usable route.
5. **Unreadable answers are `Unavailable`.** That covers bad JSON, an unexpected shape, or a route without `distance`/`duration`. `route()` catches `Exception`, as `MapboxResponseParser.parse` already does, so `Found` always has at least one route with miles and hours. A point without coordinates, or a null profile, is also `Unavailable`, with no callout.
6. **`MapboxHttp.token()` uses `tokenOverride` when it is not null.** Tests use `''` to force a blank token whatever the org holds.
7. **Added `@TestVisible private static TruckRoute.Profile profileFrom(Truck_Routing_Setting__mdt setting)`.** `defaultProfile()` calls it. Tests cannot insert custom metadata, so this is how the missing-record defaults (4.11, 2.6, 36.29, true, 1.2, 8000) get covered: tests pass a JSON-deserialized record. A blank field in an existing record also falls back to its default.
8. **Callout count.** "At most two callouts" means two *requests*. `MapboxHttp.send` retries once on a 5xx (the existing geocoder behaviour, and the spec moves it into `MapboxHttp`), so the worst case is 4 HTTP callouts × 8 s = 32 s. Spec §7 says 16 s. Both are well inside the 120 s limit.
9. **`MapboxGeocoder.BASE` now points at `MapboxHttp.BASE`.** That is one line, plus a class-comment update. Its `token()` and `sendWithRetry()` delegate as the contract says. `MapboxGeocoderTest` is untouched.
10. **`No route` has a null `message`.** Resolved: `TripRouteView.fromResult` (Task 7) supplies `TripRouteView.NO_ROUTE` for No route, and `c-route-map` (Task 8) falls back to the same sentence.
11. **Deploys use `--async --json` and poll `sf project deploy report --job-id <id> -w 2`,** per the execution rules. sf 2.140.6 confirms `--job-id`. Task 1 must already be deployed, because the test and `TruckRoute` reference `Truck_Routing_Setting__mdt`.

---

### Task 3: Route map URL (`RouteMapUrl`)

**Files:**

- Create: `force-app/main/default/classes/RouteMapUrl.cls`, `force-app/main/default/classes/RouteMapUrl.cls-meta.xml`
- Create: `force-app/main/default/classes/RouteMapUrlTest.cls`, `force-app/main/default/classes/RouteMapUrlTest.cls-meta.xml`
- Modify: `manifest/package.xml` (ApexClass members `RouteMapUrl`, `RouteMapUrlTest`, inserted directly before `<members>LaneBenchmarkPlaceServiceTest</members>`, right after the Mapbox members Task 2 added)
- Read, do not change: `force-app/main/default/classes/MapboxGeocoder.cls:107-144` (`staticMapUrl`, the existing static image URL this class sits next to: same style `streets-v12`, `auto` framing, `padding=40`, token appended last)

**Interfaces:**

- Consumes (Task 2): `MapboxHttp.BASE` (`'https://api.mapbox.com'`), `MapboxHttp.token()` (the `@TestVisible` `MapboxHttp.tokenOverride` when set, else `TPRO_KPI__c.getOrgDefaults().Mapbox_Api_Key__c`), `TruckRoute.Point` (`lat`, `lng`, constructor `Point(Decimal lat, Decimal lng)`), `TruckRoute.Line` (`miles`, `hours`, `polyline5`).
- Produces, on `public with sharing class RouteMapUrl`:
  - `public static String build(TruckRoute.Point origin, TruckRoute.Point destination, List<TruckRoute.Line> routes)` — the Mapbox Static Images URL, or `null` when the token is blank (or a place has no coordinates). Pins `pin-s-a+0070d2(lng,lat)` and `pin-s-b+2e844a(lng,lat)`; `routes[0]` as `path-5+0070d2-0.9(<URL-encoded polyline5>)`, `routes[1]` as `path-3+f59e0b-0.8(...)`, `routes[2]` as `path-3+706e6b-0.7(...)`; `MapboxHttp.BASE + '/styles/v1/mapbox/streets-v12/static/' + overlays + '/auto/600x300@2x?padding=40&access_token=' + token`; always shorter than 8,000 characters.
  - `@TestVisible static List<List<Decimal>> decode(String polyline5)` — `[lat, lng]` pairs, scale 5; stops at a truncated value; empty for null or blank.
  - `@TestVisible static String encode(List<List<Decimal>> latLngPoints)` — Google polyline, precision 5.
  - `@TestVisible static List<List<Decimal>> simplify(List<List<Decimal>> points, Decimal toleranceDegrees)` — Douglas–Peucker on lat/lng degrees; keeps the first and last point; returns the input list unchanged when it has fewer than 3 points or the tolerance is null or not above zero.
- Used by: Task 7 (`RfpLaneController.laneRoute`, `LaneBenchmarkController.truckRoute` set `TripRouteView.mapUrl = RouteMapUrl.build(...)`).

**How the URL stays under 8,000 characters** (read before the code): the URL is first built from the polylines exactly as Mapbox returned them. When it is too long, every drawn route climbs a tolerance ladder (0.0001°, 0.0003°, 0.001°, 0.003°, 0.01°, 0.03°: about 11 m to 3.3 km), each rung simplifying the previous rung's points and caching the encoded result. If three routes still do not fit at 0.03°, the last alternative (grey) is dropped and the remaining routes retry the ladder from full precision (cached, no new work); then the amber alternative is dropped. The main route alone keeps climbing (0.1° up to 1,000°) until it fits: at a tolerance larger than any deviation Douglas–Peucker keeps only the two endpoints, so the loop always ends and the main route is never missing when there is one. Overlays are written alternatives first, then the main route, then the pins, because Mapbox draws later overlays on top.

- [ ] **Step 1: Write the failing tests**

Create `force-app/main/default/classes/RouteMapUrlTest.cls`:

```apex
@IsTest
private class RouteMapUrlTest {
  private static final String GOOGLE_EXAMPLE = '_p~iF~ps|U_ulLnnqC_mqNvxq`@';
  private static final String MAIN = 'path-5+0070d2-0.9';
  private static final String AMBER = 'path-3+f59e0b-0.8';
  private static final String GREY = 'path-3+706e6b-0.7';
  private static final TruckRoute.Point MONTREAL = new TruckRoute.Point(
    45.5019,
    -73.5674
  );
  private static final TruckRoute.Point TORONTO = new TruckRoute.Point(
    43.6532,
    -79.3832
  );

  private static List<Decimal> p(Decimal lat, Decimal lng) {
    return new List<Decimal>{ lat, lng };
  }

  private static TruckRoute.Line line(String polyline5) {
    TruckRoute.Line route = new TruckRoute.Line();
    route.polyline5 = polyline5;
    return route;
  }

  /** n points from Montréal to Toronto bowed north (bow above zero) or south by bow degrees: a smooth arc. */
  private static List<List<Decimal>> arc(Integer n, Decimal bow) {
    Double lat0 = MONTREAL.lat.doubleValue();
    Double lng0 = MONTREAL.lng.doubleValue();
    Double latSpan = TORONTO.lat.doubleValue() - lat0;
    Double lngSpan = TORONTO.lng.doubleValue() - lng0;
    Double bowDegrees = bow.doubleValue();
    Double steps = n - 1;
    List<List<Decimal>> points = new List<List<Decimal>>();
    for (Integer i = 0; i < n; i++) {
      Double t = i / steps;
      points.add(
        p(
          Decimal.valueOf(
              lat0 + latSpan * t + bowDegrees * Math.sin(Math.PI * t)
            )
            .setScale(5),
          Decimal.valueOf(lng0 + lngSpan * t).setScale(5)
        )
      );
    }
    return points;
  }

  /** n points scattered up to one degree around (44.5, -76.5) by a fixed pseudo-random sequence (MINSTD). */
  private static List<List<Decimal>> scatter(Integer n) {
    List<List<Decimal>> points = new List<List<Decimal>>();
    Long seed = 42;
    for (Integer i = 0; i < n; i++) {
      seed = Math.mod(seed * 48271, 2147483647);
      Decimal lat =
        44.5 +
        Decimal.valueOf(Math.mod(seed, 200001) - 100000).divide(100000, 5);
      seed = Math.mod(seed * 48271, 2147483647);
      Decimal lng =
        -76.5 +
        Decimal.valueOf(Math.mod(seed, 200001) - 100000).divide(100000, 5);
      points.add(p(lat, lng));
    }
    return points;
  }

  /** The URL-decoded polyline inside the overlay with this style, or null when the URL has none. */
  private static String overlay(String url, String style) {
    Integer start = url.indexOf(style + '(');
    if (start < 0) {
      return null;
    }
    start += style.length() + 1;
    return EncodingUtil.urlDecode(
      url.substring(start, url.indexOf(')', start)),
      'UTF-8'
    );
  }

  @IsTest
  static void decodeReadsGooglesExampleAndEncodeWritesItBack() {
    List<List<Decimal>> points = RouteMapUrl.decode(GOOGLE_EXAMPLE);
    System.assertEquals(3, points.size());
    System.assertEquals(p(38.50000, -120.20000), points[0]);
    System.assertEquals(p(40.70000, -120.95000), points[1]);
    System.assertEquals(p(43.25200, -126.45300), points[2]);
    System.assertEquals(GOOGLE_EXAMPLE, RouteMapUrl.encode(points));
    System.assertEquals(
      GOOGLE_EXAMPLE,
      RouteMapUrl.encode(
        new List<List<Decimal>>{
          p(38.5, -120.2),
          p(40.7, -120.95),
          p(43.252, -126.453)
        }
      ),
      'the scale of the input does not change the encoding'
    );
  }

  @IsTest
  static void negativeAndZeroCoordinatesRoundTrip() {
    List<List<Decimal>> points = new List<List<Decimal>>{
      p(-33.86882, 151.20929),
      p(0.00000, 0.00000),
      p(51.50735, -0.12776)
    };
    String encoded = RouteMapUrl.encode(points);
    System.assertEquals('b_vmEaa|y[c_vmE`a|y[}_kyHn}W', encoded);
    System.assertEquals(points, RouteMapUrl.decode(encoded));
    System.assertEquals(
      'A@',
      RouteMapUrl.encode(new List<List<Decimal>>{ p(0.000005, -0.000005) }),
      'a half at the sixth decimal rounds away from zero, as Mapbox does'
    );
  }

  @IsTest
  static void decodeStopsAtACutValueAndReadsNothingFromBlank() {
    System.assertEquals(
      new List<List<Decimal>>{ p(38.50000, -120.20000) },
      RouteMapUrl.decode('_p~iF~ps|U_ulL'),
      'a latitude without its longitude is not a point'
    );
    System.assertEquals(
      new List<List<Decimal>>{ p(38.50000, -120.20000) },
      RouteMapUrl.decode('_p~iF~ps|U_ul'),
      'a value cut inside its chunks is not read'
    );
    System.assertEquals(0, RouteMapUrl.decode('').size());
    System.assertEquals(0, RouteMapUrl.decode(null).size());
  }

  @IsTest
  static void simplifyKeepsTheEndsAndCornersAndDropsCollinearPoints() {
    List<List<Decimal>> straight = new List<List<Decimal>>{
      p(45, -73),
      p(45, -74),
      p(45, -75),
      p(45, -76)
    };
    System.assertEquals(
      new List<List<Decimal>>{ straight[0], straight[3] },
      RouteMapUrl.simplify(straight, 0.0001)
    );
    List<List<Decimal>> corner = new List<List<Decimal>>{
      p(0, 0),
      p(0, 1),
      p(0, 2),
      p(1, 2),
      p(2, 2)
    };
    System.assertEquals(
      new List<List<Decimal>>{ corner[0], corner[2], corner[4] },
      RouteMapUrl.simplify(corner, 0.01)
    );
    List<List<Decimal>> bump = new List<List<Decimal>>{
      p(45, -73),
      p(45.00005, -74),
      p(45, -75)
    };
    System.assertEquals(
      2,
      RouteMapUrl.simplify(bump, 0.0001).size(),
      'a bump under the tolerance goes'
    );
    System.assertEquals(
      3,
      RouteMapUrl.simplify(bump, 0.00001).size(),
      'a bump over the tolerance stays'
    );
    List<List<Decimal>> loop = new List<List<Decimal>>{
      p(45, -73),
      p(46, -73.5),
      p(45, -73)
    };
    System.assertEquals(
      3,
      RouteMapUrl.simplify(loop, 0.01).size(),
      'a route back to its start keeps its far point'
    );
    System.assertEquals(corner, RouteMapUrl.simplify(corner, 0));
    System.assertEquals(corner, RouteMapUrl.simplify(corner, null));
    System.assertEquals(
      2,
      RouteMapUrl.simplify(new List<List<Decimal>>{ p(1, 1), p(2, 2) }, 1)
        .size()
    );
    System.assertEquals(null, RouteMapUrl.simplify(null, 1));
  }

  @IsTest
  static void buildDrawsTwoPinsAndThreeColouredRoutes() {
    MapboxHttp.tokenOverride = 'pk.test';
    String url = RouteMapUrl.build(
      MONTREAL,
      TORONTO,
      new List<TruckRoute.Line>{
        line(GOOGLE_EXAMPLE),
        line(GOOGLE_EXAMPLE),
        line(GOOGLE_EXAMPLE),
        line(GOOGLE_EXAMPLE)
      }
    );
    String polyline = '(_p%7EiF%7Eps%7CU_ulLnnqC_mqNvxq%60%40)';
    System.assert(
      url.startsWith(
        'https://api.mapbox.com/styles/v1/mapbox/streets-v12/static/'
      ),
      url
    );
    System.assert(url.contains(MAIN + polyline), url);
    System.assert(url.contains(AMBER + polyline), url);
    System.assert(url.contains(GREY + polyline), url);
    System.assertEquals(
      3,
      url.countMatches('path-'),
      'a fourth route is not drawn'
    );
    System.assert(url.contains('pin-s-a+0070d2(-73.5674,45.5019)'), url);
    System.assert(url.contains('pin-s-b+2e844a(-79.3832,43.6532)'), url);
    System.assert(
      url.endsWith('/auto/600x300@2x?padding=40&access_token=pk.test'),
      url
    );
    System.assert(
      url.indexOf(GREY) < url.indexOf(AMBER) &&
        url.indexOf(AMBER) < url.indexOf(MAIN) &&
        url.indexOf(MAIN) < url.indexOf('pin-s-a'),
      'alternatives under the main route, pins on top: ' + url
    );
  }

  @IsTest
  static void buildSkipsEmptyRoutesAndDrawsPinsOnlyWithoutRoutes() {
    MapboxHttp.tokenOverride = 'pk.test';
    String url = RouteMapUrl.build(
      MONTREAL,
      TORONTO,
      new List<TruckRoute.Line>{
        line(GOOGLE_EXAMPLE),
        null,
        line(''),
        line(GOOGLE_EXAMPLE)
      }
    );
    System.assertEquals(2, url.countMatches('path-'), url);
    System.assert(url.contains(MAIN + '('), url);
    System.assert(url.contains(AMBER + '('), url);
    String pinsOnly =
      'https://api.mapbox.com/styles/v1/mapbox/streets-v12/static/' +
      'pin-s-a+0070d2(-73.5674,45.5019),pin-s-b+2e844a(-79.3832,43.6532)' +
      '/auto/600x300@2x?padding=40&access_token=pk.test';
    System.assertEquals(pinsOnly, RouteMapUrl.build(MONTREAL, TORONTO, null));
    System.assertEquals(
      pinsOnly,
      RouteMapUrl.build(MONTREAL, TORONTO, new List<TruckRoute.Line>())
    );
  }

  @IsTest
  static void buildReturnsNullWithoutATokenOrCoordinates() {
    MapboxHttp.tokenOverride = null;
    TPRO_KPI__c settings = TPRO_KPI__c.getOrgDefaults();
    settings.Mapbox_Api_Key__c = null;
    upsert settings;
    List<TruckRoute.Line> routes = new List<TruckRoute.Line>{
      line(GOOGLE_EXAMPLE)
    };
    System.assertEquals(null, RouteMapUrl.build(MONTREAL, TORONTO, routes));
    MapboxHttp.tokenOverride = 'pk.test';
    System.assertEquals(null, RouteMapUrl.build(null, TORONTO, routes));
    System.assertEquals(
      null,
      RouteMapUrl.build(MONTREAL, new TruckRoute.Point(43.6532, null), routes)
    );
  }

  @IsTest
  static void longRoutesAreSimplifiedUnderTheLimitAndAllThreeStay() {
    MapboxHttp.tokenOverride = 'pk.test';
    List<List<Decimal>> north = arc(3000, 0.4);
    String main = RouteMapUrl.encode(north);
    String farNorth = RouteMapUrl.encode(arc(3000, 0.8));
    String south = RouteMapUrl.encode(arc(3000, -0.4));
    System.assert(
      main.length() > 8000,
      'each route alone is over the limit before simplification: ' +
      main.length()
    );
    Test.startTest();
    String url = RouteMapUrl.build(
      MONTREAL,
      TORONTO,
      new List<TruckRoute.Line>{ line(main), line(farNorth), line(south) }
    );
    Test.stopTest();
    System.assert(url.length() < 8000, 'URL length ' + url.length());
    System.assertNotEquals(null, overlay(url, AMBER), url);
    System.assertNotEquals(null, overlay(url, GREY), url);
    List<List<Decimal>> drawn = RouteMapUrl.decode(overlay(url, MAIN));
    System.assert(
      drawn.size() > 2 && drawn.size() < 3000,
      'simplified, not flattened: ' + drawn.size()
    );
    System.assertEquals(north[0], drawn[0], 'starts at Montréal');
    System.assertEquals(
      north[2999],
      drawn[drawn.size() - 1],
      'ends at Toronto'
    );
  }

  @IsTest
  static void anAlternativeThatCannotFitIsDroppedBeforeTheOthers() {
    MapboxHttp.tokenOverride = 'pk.test';
    String main = RouteMapUrl.encode(arc(3000, 0.4));
    String farNorth = RouteMapUrl.encode(arc(3000, 0.8));
    String scattered = RouteMapUrl.encode(scatter(1000));
    System.assert(
      EncodingUtil.urlEncode(scattered, 'UTF-8').length() > 8000,
      'the scattered route cannot fit even alone at full precision'
    );
    Test.startTest();
    String url = RouteMapUrl.build(
      MONTREAL,
      TORONTO,
      new List<TruckRoute.Line>{ line(main), line(farNorth), line(scattered) }
    );
    Test.stopTest();
    System.assert(url.length() < 8000, 'URL length ' + url.length());
    System.assertNotEquals(null, overlay(url, MAIN), url);
    System.assertNotEquals(null, overlay(url, AMBER), url);
    System.assertEquals(
      null,
      overlay(url, GREY),
      'the last alternative is dropped'
    );
  }

  @IsTest
  static void aMainRouteAloneIsSimplifiedUntilItFits() {
    MapboxHttp.tokenOverride = 'pk.test';
    List<List<Decimal>> points = scatter(1000);
    Test.startTest();
    String url = RouteMapUrl.build(
      MONTREAL,
      TORONTO,
      new List<TruckRoute.Line>{ line(RouteMapUrl.encode(points)) }
    );
    Test.stopTest();
    System.assert(url.length() < 8000, 'URL length ' + url.length());
    List<List<Decimal>> drawn = RouteMapUrl.decode(overlay(url, MAIN));
    System.assert(
      drawn.size() >= 2 && drawn.size() < 1000,
      'simplified: ' + drawn.size()
    );
    System.assertEquals(points[0], drawn[0], 'the route keeps its start');
    System.assertEquals(
      points[999],
      drawn[drawn.size() - 1],
      'the route keeps its end'
    );
  }
}
```

Create `force-app/main/default/classes/RouteMapUrlTest.cls-meta.xml`:

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<ApexClass xmlns="http://soap.sforce.com/2006/04/metadata">
    <apiVersion>64.0</apiVersion>
    <status>Active</status>
</ApexClass>
```

What the tests pin down: the Google example `` _p~iF~ps|U_ulLnnqC_mqNvxq`@ `` decodes to (38.5, -120.2), (40.7, -120.95), (43.252, -126.453) and encodes back to the same string; negative and zero coordinates round-trip and a half at the sixth decimal rounds away from zero (`A@`); a cut polyline yields only its complete points; `simplify` keeps both ends and corners, drops collinear points and bumps under the tolerance, keeps the far point of a route that returns to its start, and leaves short input or a non-positive tolerance alone; `build` writes both pins, the three colours (a fourth route is ignored, null and blank routes are skipped) with the alternatives under the main route and the pins on top, the exact pins-only URL without routes, and `null` without a token or coordinates; three 3,000-point routes (each over 8,000 characters alone) come back under 8,000 characters with all three overlays and the main route still starting at Montréal and ending at Toronto; a scattered third route that cannot fit is dropped while the main and amber routes stay; a scattered main route alone is simplified until it fits and keeps its two ends.

- [ ] **Step 2: Deploy the test alone and watch it fail to compile**

Run: `sf project deploy start -o sandbox --source-dir force-app/main/default/classes/RouteMapUrlTest.cls -l NoTestRun --async --json | python3 -c "import json,sys; s=sys.stdin.read(); print(json.loads(s[s.index('{'):])['result']['id'])"`

Expected: one deploy job id (starts with `0Af`). Then poll with that id in place of `<id>`, repeating the command while the first word printed is `Pending` or `InProgress`:

`sf project deploy report -o sandbox --job-id <id> -w 2 --json | python3 -c "import json,sys; s=sys.stdin.read(); j=json.loads(s[s.index('{'):]); r=j.get('result') or j.get('data') or {}; d=r.get('details') or {}; t=d.get('runTestResult') or {}; L=lambda x: x if isinstance(x, list) else ([x] if x else []); print(r.get('status') or j.get('message'), 'tests', r.get('numberTestsCompleted'), '/', r.get('numberTestsTotal'), 'errors', r.get('numberTestErrors')); [print('COMPILE', c.get('fullName'), c.get('lineNumber'), c.get('problem')) for c in L(d.get('componentFailures'))]; [print('FAIL', f.get('methodName'), f.get('message')) for f in L(t.get('failures'))]; [print('COVERAGE', c.get('name'), c.get('numLocations'), 'lines,', c.get('numLocationsNotCovered'), 'not covered') for c in L(t.get('codeCoverage')) if c.get('name') == 'RouteMapUrl']"`

Expected: `Failed tests 0 / 0 errors 0` (the counts may print as `None` on a `NoTestRun` deploy) followed by `COMPILE RouteMapUrlTest <line> Variable does not exist: RouteMapUrl` (or `Invalid type: RouteMapUrl`). Any other compile problem (for example `Invalid type: TruckRoute.Point` or `Variable does not exist: MapboxHttp`) means Task 2 is not deployed yet: stop and finish Task 2 first.

- [ ] **Step 3: Write `RouteMapUrl`**

Create `force-app/main/default/classes/RouteMapUrl.cls`:

```apex
/**
 * The Mapbox Static Images URL of a lane's truck route: a pin on each place, the main route as a
 * thick blue line and up to two alternatives (amber, then grey) under it. It sits next to
 * MapboxGeocoder.staticMapUrl and uses the same style, framing and token. Mapbox refuses URLs
 * longer than 8,192 characters, so this class keeps the URL under 8,000: every drawn route climbs
 * a Douglas-Peucker tolerance ladder until the URL fits; when three or two routes still do not fit
 * at 0.03 degrees, the last alternative is dropped; the main route alone keeps climbing until it
 * fits, so it is never missing. Polylines are Google's precision-5 format, which the Directions
 * API returns with geometries=polyline. The URL carries the public token: it is built for each
 * view, never stored and never logged.
 */
public with sharing class RouteMapUrl {
  private static final Integer MAX_URL_LENGTH = 8000;
  private static final Decimal E5 = 100000;
  private static final String STYLE_PATH = '/styles/v1/mapbox/streets-v12/static/';
  private static final String FRAME = '/auto/600x300@2x?padding=40&access_token=';
  private static final List<String> PATH_STYLES = new List<String>{
    'path-5+0070d2-0.9',
    'path-3+f59e0b-0.8',
    'path-3+706e6b-0.7'
  };
  // Degrees (0.0001 is about 11 m). Rungs 1 to SHARED_RUNGS (up to 0.03, about 3.3 km) are tried
  // while alternatives are drawn; the main route alone climbs on to 1,000, where only its two
  // endpoints are left, so the ladder always ends with a URL that fits.
  private static final List<Decimal> TOLERANCES = new List<Decimal>{
    0.0001,
    0.0003,
    0.001,
    0.003,
    0.01,
    0.03,
    0.1,
    0.3,
    1,
    3,
    10,
    30,
    100,
    1000
  };
  private static final Integer SHARED_RUNGS = 6;

  /** The static map URL, or null without a token or without coordinates for both places. */
  public static String build(
    TruckRoute.Point origin,
    TruckRoute.Point destination,
    List<TruckRoute.Line> routes
  ) {
    String token = MapboxHttp.token();
    if (
      String.isBlank(token) ||
      !hasCoordinates(origin) ||
      !hasCoordinates(destination)
    ) {
      return null;
    }
    String pins =
      'pin-s-a+0070d2(' +
      lngLat(origin) +
      '),pin-s-b+2e844a(' +
      lngLat(destination) +
      ')';
    List<Ladder> ladders = laddersOf(routes);
    for (
      Integer keep = Math.min(ladders.size(), PATH_STYLES.size());
      keep > 0;
      keep--
    ) {
      String url = fitting(token, pins, ladders, keep);
      if (url != null) {
        return url;
      }
    }
    return compose(token, pins, new List<String>());
  }

  private static Boolean hasCoordinates(TruckRoute.Point point) {
    return point != null && point.lat != null && point.lng != null;
  }

  /** 'lng,lat' with at most five decimals and no trailing zeros. */
  private static String lngLat(TruckRoute.Point point) {
    return point.lng.setScale(5, System.RoundingMode.HALF_UP)
        .stripTrailingZeros()
        .toPlainString() +
      ',' +
      point.lat.setScale(5, System.RoundingMode.HALF_UP)
        .stripTrailingZeros()
        .toPlainString();
  }

  private static List<Ladder> laddersOf(List<TruckRoute.Line> routes) {
    List<Ladder> ladders = new List<Ladder>();
    if (routes == null) {
      return ladders;
    }
    for (TruckRoute.Line line : routes) {
      if (line != null && String.isNotBlank(line.polyline5)) {
        ladders.add(new Ladder(line.polyline5));
      }
    }
    return ladders;
  }

  /** The URL with the first `keep` routes at the lowest rung that fits, or null when no rung does. */
  private static String fitting(
    String token,
    String pins,
    List<Ladder> ladders,
    Integer keep
  ) {
    Integer topRung = keep == 1 ? TOLERANCES.size() : SHARED_RUNGS;
    for (Integer rung = 0; rung <= topRung; rung++) {
      List<String> lines = new List<String>();
      for (Integer i = 0; i < keep; i++) {
        lines.add(ladders[i].at(rung));
      }
      String url = compose(token, pins, lines);
      if (url.length() < MAX_URL_LENGTH) {
        return url;
      }
    }
    return null;
  }

  /** Alternatives first, then the main route, then the pins: Mapbox draws later overlays on top. */
  private static String compose(
    String token,
    String pins,
    List<String> urlEncodedLines
  ) {
    List<String> overlays = new List<String>();
    for (Integer i = urlEncodedLines.size() - 1; i >= 0; i--) {
      overlays.add(PATH_STYLES[i] + '(' + urlEncodedLines[i] + ')');
    }
    overlays.add(pins);
    return MapboxHttp.BASE +
      STYLE_PATH +
      String.join(overlays, ',') +
      FRAME +
      token;
  }

  /** [lat, lng] pairs at scale 5; stops before a value the string cuts off; empty for null or blank. */
  @TestVisible
  static List<List<Decimal>> decode(String polyline5) {
    List<List<Decimal>> points = new List<List<Decimal>>();
    PolylineReader reader = new PolylineReader(polyline5);
    Long lat = 0;
    Long lng = 0;
    while (reader.hasMore()) {
      Long latDelta = reader.nextValue();
      Long lngDelta = reader.nextValue();
      if (latDelta == null || lngDelta == null) {
        break;
      }
      lat += latDelta;
      lng += lngDelta;
      points.add(
        new List<Decimal>{
          Decimal.valueOf(lat).divide(E5, 5),
          Decimal.valueOf(lng).divide(E5, 5)
        }
      );
    }
    return points;
  }

  /** Google's encoded polyline, precision 5, of [lat, lng] pairs. */
  @TestVisible
  static String encode(List<List<Decimal>> latLngPoints) {
    List<Integer> chars = new List<Integer>();
    Long lastLat = 0;
    Long lastLng = 0;
    for (List<Decimal> point : latLngPoints) {
      // HALF_UP rounds half away from zero, as Mapbox's polyline library does; Apex's default
      // Decimal rounding is HALF_EVEN, which would move some sixth-decimal halves the other way.
      Long lat = (point[0] * E5).round(System.RoundingMode.HALF_UP);
      Long lng = (point[1] * E5).round(System.RoundingMode.HALF_UP);
      appendValue(chars, lat - lastLat);
      appendValue(chars, lng - lastLng);
      lastLat = lat;
      lastLng = lng;
    }
    return String.fromCharArray(chars);
  }

  /** One signed value: zig-zag (a negative value becomes odd), then 5-bit chunks, low bits first, each plus 63. */
  private static void appendValue(List<Integer> chars, Long value) {
    Long rest = value < 0 ? -(value << 1) - 1 : value << 1;
    while (rest >= 32) {
      chars.add((32 + Math.mod(rest, 32)).intValue() + 63);
      rest = rest >> 5;
    }
    chars.add(rest.intValue() + 63);
  }

  /** Douglas-Peucker over lat/lng degrees; the input comes back unchanged when there is nothing to drop. */
  @TestVisible
  static List<List<Decimal>> simplify(
    List<List<Decimal>> points,
    Decimal toleranceDegrees
  ) {
    Boolean nothingToDrop =
      points == null ||
      points.size() < 3 ||
      toleranceDegrees == null ||
      toleranceDegrees <= 0;
    if (nothingToDrop) {
      return points;
    }
    return new Simplifier(points, toleranceDegrees).run(points);
  }

  /** One route's URL-encoded polyline at each rung of the tolerance ladder, computed once and cached. */
  private class Ladder {
    private String original;
    private List<List<Decimal>> points;
    private List<String> rungs = new List<String>();

    Ladder(String polyline5) {
      original = polyline5;
      rungs.add(EncodingUtil.urlEncode(polyline5, 'UTF-8'));
    }

    String at(Integer rung) {
      while (rungs.size() <= rung) {
        if (points == null) {
          points = decode(original);
        }
        points = simplify(points, TOLERANCES[rungs.size() - 1]);
        rungs.add(EncodingUtil.urlEncode(encode(points), 'UTF-8'));
      }
      return rungs[rung];
    }
  }

  /** Reads the signed values of a precision-5 polyline one at a time. */
  private class PolylineReader {
    private List<Integer> chars;
    private Integer index = 0;

    PolylineReader(String polyline5) {
      chars = String.isBlank(polyline5)
        ? new List<Integer>()
        : polyline5.getChars();
    }

    Boolean hasMore() {
      return index < chars.size();
    }

    /** The next value, or null when the string ends inside it. */
    Long nextValue() {
      Long result = 0;
      Integer shift = 0;
      Integer chunk = 32;
      while (chunk >= 32) {
        if (index >= chars.size()) {
          return null;
        }
        chunk = chars[index] - 63;
        index++;
        Long bits = chunk & 31;
        result += bits << shift;
        shift += 5;
      }
      return Math.mod(result, 2) == 1 ? -(result >> 1) - 1 : result >> 1;
    }
  }

  /**
   * Douglas-Peucker with an explicit stack (Apex caps recursion depth at 1,000 calls). Distances are
   * squared, in degrees, on Doubles: Decimal arithmetic is far slower and a route has thousands of
   * points. A point's distance is to the infinite line through the segment's ends, or to the first
   * end when both ends are the same place.
   */
  private class Simplifier {
    private List<Double> lats = new List<Double>();
    private List<Double> lngs = new List<Double>();
    private Double tolerance2;

    Simplifier(List<List<Decimal>> points, Decimal toleranceDegrees) {
      for (List<Decimal> point : points) {
        lats.add(point[0].doubleValue());
        lngs.add(point[1].doubleValue());
      }
      tolerance2 =
        toleranceDegrees.doubleValue() * toleranceDegrees.doubleValue();
    }

    List<List<Decimal>> run(List<List<Decimal>> points) {
      Integer lastIndex = points.size() - 1;
      Set<Integer> kept = new Set<Integer>{ 0, lastIndex };
      List<Integer> stack = new List<Integer>{ 0, lastIndex };
      while (!stack.isEmpty()) {
        Integer endIndex = stack.remove(stack.size() - 1);
        Integer startIndex = stack.remove(stack.size() - 1);
        Integer farIndex = farthest(startIndex, endIndex);
        if (farIndex != null) {
          kept.add(farIndex);
          stack.addAll(
            new List<Integer>{ startIndex, farIndex, farIndex, endIndex }
          );
        }
      }
      List<List<Decimal>> result = new List<List<Decimal>>();
      for (Integer i = 0; i <= lastIndex; i++) {
        if (kept.contains(i)) {
          result.add(points[i]);
        }
      }
      return result;
    }

    /** The index strictly between the two ends farthest from their line, or null when all are within the tolerance. */
    private Integer farthest(Integer startIndex, Integer endIndex) {
      Double lat0 = lats[startIndex];
      Double lng0 = lngs[startIndex];
      Double dLat = lats[endIndex] - lat0;
      Double dLng = lngs[endIndex] - lng0;
      Double length2 = dLat * dLat + dLng * dLng;
      Double best = tolerance2;
      Integer bestIndex;
      for (Integer i = startIndex + 1; i < endIndex; i++) {
        Double pLat = lats[i] - lat0;
        Double pLng = lngs[i] - lng0;
        Double cross = pLng * dLat - pLat * dLng;
        Double distance2 = length2 > 0
          ? cross * cross / length2
          : pLat * pLat + pLng * pLng;
        if (distance2 > best) {
          best = distance2;
          bestIndex = i;
        }
      }
      return bestIndex;
    }
  }
}
```

Create `force-app/main/default/classes/RouteMapUrl.cls-meta.xml`:

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<ApexClass xmlns="http://soap.sforce.com/2006/04/metadata">
    <apiVersion>64.0</apiVersion>
    <status>Active</status>
</ApexClass>
```

Add the two classes to `manifest/package.xml` (Task 1 adds no Apex members, Task 1 note 2): insert these two lines directly before `        <members>LaneBenchmarkPlaceServiceTest</members>` (inside the `<types>` block whose `<name>` is `ApexClass`, right after the Mapbox members Task 2 added):

```xml
        <members>RouteMapUrl</members>
        <members>RouteMapUrlTest</members>
```

Expected afterwards: `grep -c '<members>RouteMapUrl' manifest/package.xml` prints `2`.

- [ ] **Step 4: Deploy both classes and run the tests**

Run: `sf project deploy start -o sandbox --source-dir force-app/main/default/classes/RouteMapUrl.cls --source-dir force-app/main/default/classes/RouteMapUrlTest.cls -l RunSpecifiedTests -t RouteMapUrlTest --async --json | python3 -c "import json,sys; s=sys.stdin.read(); print(json.loads(s[s.index('{'):])['result']['id'])"`

Then poll with the report command from Step 2 (same Python filter, the new job id), repeating while it prints `Pending` or `InProgress`.

Expected: `Succeeded tests 10 / 10 errors 0` and `COVERAGE RouteMapUrl <n> lines, <k> not covered` with at most a few lines not covered (every branch has a test; the org refuses the deploy below 75 %). If a test fails, the `FAIL` lines name the method and message; fix the class, not the assertion, unless the assertion contradicts the spec. If one of the three long-route tests fails with `Apex CPU time limit exceeded`, change `scatter(1000)` to `scatter(900)` in `anAlternativeThatCannotFitIsDroppedBeforeTheOthers` and `aMainRouteAloneIsSimplifiedUntilItFits` and redeploy (900 scattered points still URL-encode to more than 8,000 characters, and the first of those tests asserts it); do not raise the budget or cap the ladder in the class.

- [ ] **Step 5: PMD**

Run: `/private/tmp/pmd_install/pmd-bin-7.15.0/bin/pmd check --dir force-app/main/default/classes/RouteMapUrl.cls --dir force-app/main/default/classes/RouteMapUrlTest.cls --rulesets config/pmd-ruleset.xml --minimum-priority 3 --format text --fail-on-violation --no-progress; echo "pmd exit $?"`

Expected: no violation lines, `pmd exit 0` (the class as written was checked against PMD 7.15.0 with this ruleset: 0 violations). The outer class sums to a cyclomatic complexity of about 37 of the 40 budget; the decoding, ladder and Douglas–Peucker loops live in the private inner classes `PolylineReader`, `Ladder` and `Simplifier`, which do not count toward it. If PMD reports the class over 40 after an edit, move logic into those inner classes; do not raise the budget.

Then the whole tree: `/private/tmp/pmd_install/pmd-bin-7.15.0/bin/pmd check --dir force-app --rulesets config/pmd-ruleset.xml --minimum-priority 3 --format text --fail-on-violation --no-progress; echo "pmd exit $?"`

Expected: `pmd exit 0`.

- [ ] **Step 6: Prettier**

Run: `npx prettier --check force-app/main/default/classes/RouteMapUrl.cls force-app/main/default/classes/RouteMapUrlTest.cls force-app/main/default/classes/RouteMapUrl.cls-meta.xml force-app/main/default/classes/RouteMapUrlTest.cls-meta.xml manifest/package.xml`

Expected: `All matched files use Prettier code style!` (the code above is already in the repository's Prettier format, and `manifest/package.xml` and the existing `-meta.xml` files pass `--check` today). lint-staged runs Prettier again on commit.

- [ ] **Step 7: Commit**

```bash
git add force-app/main/default/classes/RouteMapUrl.cls force-app/main/default/classes/RouteMapUrl.cls-meta.xml force-app/main/default/classes/RouteMapUrlTest.cls force-app/main/default/classes/RouteMapUrlTest.cls-meta.xml manifest/package.xml
git commit -m "Add RouteMapUrl: truck routes on the static map, kept under 8,000 characters"
```

Expected: one commit with those five files; `git status --short` still shows only `.vscode/settings.json` and the ` 2.` duplicates as untracked or modified, never staged.

#### Contract notes (Task 3)

1. **`build` also returns `null` when a place or one of its coordinates is missing**, not only when the token is blank: both pins need coordinates. Task 7 only calls it for lanes with coordinates, so nothing changes for callers.
2. **Overlay order in the URL is grey alternative, amber alternative, main route, pins**, not the order the contract lists them in (pins first). Mapbox draws later overlays on top, so this keeps the main route over its alternatives and the pins over every line. `buildDrawsTwoPinsAndThreeColouredRoutes` asserts the order so a later edit does not "fix" it.
3. **The main route is never dropped.** The contract says "dropping alternatives last" and the spec "alternatives are dropped before the main route". Alternatives climb the ladder to 0.03° and are then dropped, the last one first (a scattered amber route therefore takes the grey one with it). The main route alone keeps climbing to 1,000°, where Douglas–Peucker keeps only its two ends, so the loop always ends with a URL that fits; the pins-only URL appears only when there is no drawable route.
4. **At most three routes are drawn; a null line or a blank `polyline5` is skipped** and the next route moves up (it takes the next colour).
5. **Pin coordinates** are written with at most five decimals and no trailing zeros (`-73.5674,45.5019`), so the URL does not depend on the scale of `Pricing_Place__c.Geolocation__c`.
6. **`decode` tolerates a cut polyline** (returns the complete points before the cut) and returns an empty list for null or blank; `encode` rounds with `HALF_UP` (half away from zero, like Mapbox's polyline library) instead of Apex's default `HALF_EVEN`. `encode` expects a non-null list (its only callers pass decoded or simplified lists).
7. **Douglas–Peucker details**: distances are to the infinite line through the segment's two ends, squared, in degrees, on `Double` (Decimal arithmetic is much slower on thousands of points), with an explicit stack because Apex limits recursion depth; when both ends are the same place the distance is to that place. Simplification is cumulative (each rung simplifies the previous rung's points) and each rung's encoded polyline is cached per route, so dropping an alternative costs no new work.
8. **PMD class complexity**: the logic is split into private inner classes `Ladder`, `PolylineReader` and `Simplifier` so the outer class stays under 40. Both files were checked in a scratch copy with PMD 7.15.0 and `config/pmd-ruleset.xml` (0 violations) and formatted with the repository's Prettier configuration.
9. **Manifest**: each task adds its own members (Task 1 note 2), so Step 3 adds `RouteMapUrl` and `RouteMapUrlTest`.
10. **Blank-token test** does not rely on how Task 2's `MapboxHttp.token()` treats an empty override: it sets `MapboxHttp.tokenOverride = null` and writes a null `Mapbox_Api_Key__c` to the `TPRO_KPI__c` org default, the pattern `MapboxGeocoderTest.missingTokenThrowsBeforeCallout` already uses. Tests that need a token set `MapboxHttp.tokenOverride = 'pk.test'`.
11. **Test data behind the expectations** (measured with a Python copy of the same algorithm): each 3,000-point arc encodes to about 12,000 characters; the three arcs fit on the first rung (0.0001°) in about 2,100 characters with 65 to 113 points per route; 1,000 scattered points URL-encode to about 10,100 characters, still over 8,000 at 0.03°, and the main route alone fits at the 1° rung with about 344 points.
12. **With coordinates but no drawable route, `build` returns the pins-only URL (defensive)**; only a blank token or missing coordinates give `null`. Task 7 calls `build` only for `Found`, so a `No route` view has no `mapUrl` and Lane Benchmark keeps its preview.
13. **Unverified against the Apex compiler**: PMD and Prettier parse the code, but only the Step 2 and Step 4 deploys compile it. The Douglas–Peucker keep flags are a `Set<Integer>` rather than a `Boolean[]` because Prettier rewrites the array form into a size-constructor `List` that is not in the documented API.

---

### Task 4: Trip miles service — median, approximate distance and the stored truck route

**Files:**

- Create: `force-app/main/default/classes/TripMilesService.cls`, `force-app/main/default/classes/TripMilesService.cls-meta.xml`
- Create: `force-app/main/default/classes/TripMilesServiceTest.cls`, `force-app/main/default/classes/TripMilesServiceTest.cls-meta.xml`
- Modify: `force-app/main/default/classes/LaneSearchResult.cls` (whole file, Step 3: `LoadDetail { loadId, miles }`, `Row.load` in place of `Row.loadId`, `Stats.ratePerMileMedian`, `medianMiles`; Task 5 fills them)
- Modify: `force-app/main/default/classes/LaneSearchService.cls:171` (`r.loadId = q.rtms__Load__c;` → `r.load.loadId = q.rtms__Load__c;`)
- Modify: `manifest/package.xml` (ApexClass members `TripMilesService`, `TripMilesServiceTest`, at the end of the ApexClass block, after the members Tasks 2 and 3 added and before `<name>ApexClass</name>`)

**Interfaces:**

- Consumes:
  - `Truck_Route__c` and its fields `Origin_Place__c`, `Destination_Place__c`, `Profile_Key__c`, `Route_Key__c` (External ID, Unique), `Miles__c`, `Hours__c`, `Route_Type__c`, `Status__c`, `Routes_Json__c`, `Checked_On__c`; the permission set `RFP_Tool_User` with read on `Truck_Route__c` (Task 1).
  - `TruckRoute.Point(Decimal lat, Decimal lng)`, `TruckRoute.Profile` (`heightM`, `widthM`, `weightT`, `alternatives`, `approxFactor`, `timeoutMs`, `key()`), `TruckRoute.Line` (`miles`, `hours`, `polyline5`), `TruckRoute.Result` (`status`, `routeType`, `routes`, `message`), `TruckRoute.UNAVAILABLE`, `MapboxTruckRoute.route(TruckRoute.Point, TruckRoute.Point, TruckRoute.Profile)`, `MapboxHttp.tokenOverride` (Task 2).
  - `Pricing_Place__c.Geolocation__Latitude__s` / `Geolocation__Longitude__s` (exist, scale 6), `RfpTestDataFactory.createPlace(city, prov, country, lat, lng, prefix)` and `RfpTestDataFactory.restrictedUser(String permSetName)` (exist).
- Produces:
  - `LaneSearchResult.LoadDetail` (`@AuraEnabled Id loadId`, `@AuraEnabled Decimal miles`); `Row.load` (initialized; replaces `Row.loadId`); `LaneSearchResult.medianMiles`; `Stats.ratePerMileMedian`. All are declared here and filled by Task 5. Every later task reads `row.load.miles`.
  - On `TripMilesService` (`public with sharing`):
    - `public static final Decimal EARTH_RADIUS_MI = 3958.7613;`
    - `public class RouteOutcome { public TruckRoute.Result result; public Truck_Route__c toSave; public Boolean fromStore = false; }`
    - `public static Decimal medianMiles(List<LaneSearchResult.Row> rows)` — median of `row.load.miles` above zero, one decimal (a row without `load` is skipped); `null` when none.
    - `public static Decimal approxMiles(Pricing_Place__c o, Pricing_Place__c d, TruckRoute.Profile p)` — great-circle miles × `p.approxFactor`, one decimal; `null` when a place or a coordinate is missing.
    - `public static String routeKey(Id originPlaceId, Id destinationPlaceId, TruckRoute.Profile p)` — `originId + ':' + destinationId + ':' + p.key()`; `null` when either Id is null.
    - `public static Map<String, Truck_Route__c> storedRoutes(Set<String> routeKeys)` — by `Route_Key__c`, rows with a blank place ignored; one query, none for an empty set.
    - `public static TruckRoute.Result fromStored(Truck_Route__c row)`.
    - `public static RouteOutcome storedOrRoute(Pricing_Place__c o, Pricing_Place__c d, TruckRoute.Profile p, Boolean refresh)` — no DML.
    - `public static void save(List<Truck_Route__c> rows)` — upsert on `Truck_Route__c.Route_Key__c`, system mode and without sharing (a pricer refreshes a route another pricer saved).

- [ ] **Step 1: Write the failing tests**

Create `force-app/main/default/classes/TripMilesServiceTest.cls`:

```apex
@IsTest
private class TripMilesServiceTest {
  // Two Directions routes, no notification: the truck route is kept (one request).
  private static final String TRUCK_BODY =
    '{"code":"Ok","waypoints":[],"routes":[' +
    '{"distance":540000.0,"duration":20160.0,"geometry":"_p~iF~ps|U_ulLnnqC_mqNvxq`@","legs":[]},' +
    '{"distance":563000.0,"duration":21600.0,"geometry":"_p~iF~ps|U_ulLnnqC","legs":[]}' +
    ']}';
  private static final String NO_ROUTE_BODY = '{"code":"NoRoute","message":"No route found","routes":[]}';

  private class Mock implements HttpCalloutMock {
    Integer status;
    String body;
    Integer calls = 0;
    Mock(Integer status, String body) {
      this.status = status;
      this.body = body;
    }
    public HttpResponse respond(HttpRequest req) {
      calls++;
      System.assert(
        req.getEndpoint()
          .startsWith('https://api.mapbox.com/directions/v5/mapbox/driving/'),
        'a Directions request'
      );
      HttpResponse r = new HttpResponse();
      r.setStatusCode(status);
      r.setBody(body);
      return r;
    }
  }

  private class Fx {
    Pricing_Place__c mtl;
    Pricing_Place__c tor;
    TruckRoute.Profile p;
  }

  private static Fx fx() {
    MapboxHttp.tokenOverride = 'pk.test';
    Fx f = new Fx();
    f.mtl = RfpTestDataFactory.createPlace(
      'Montréal',
      'QC',
      'CA',
      45.5019,
      -73.5674,
      'H1A'
    );
    f.tor = RfpTestDataFactory.createPlace(
      'Toronto',
      'ON',
      'CA',
      43.6532,
      -79.3832,
      'M5V'
    );
    f.p = profile();
    return f;
  }

  private static TruckRoute.Profile profile() {
    TruckRoute.Profile p = new TruckRoute.Profile();
    p.heightM = 4.11;
    p.widthM = 2.6;
    p.weightT = 36.29;
    p.alternatives = true;
    p.approxFactor = 1.2;
    p.timeoutMs = 8000;
    return p;
  }

  private static LaneSearchResult.Row row(Decimal miles) {
    LaneSearchResult.Row r = new LaneSearchResult.Row();
    r.load.miles = miles;
    return r;
  }

  /** A route row for Montréal -> Toronto with the fixture's profile, not inserted. */
  private static Truck_Route__c built(Fx f, String routeType, Decimal miles) {
    return new Truck_Route__c(
      Origin_Place__c = f.mtl.Id,
      Destination_Place__c = f.tor.Id,
      Profile_Key__c = f.p.key(),
      Route_Key__c = TripMilesService.routeKey(f.mtl.Id, f.tor.Id, f.p),
      Status__c = 'Found',
      Route_Type__c = routeType,
      Miles__c = miles,
      Hours__c = 6.5,
      Routes_Json__c = '[{"miles":' +
        miles +
        ',"hours":6.5,"polyline5":"_p~iF~ps|U"}]',
      Checked_On__c = System.now().addDays(-3)
    );
  }

  private static Truck_Route__c stored(Fx f, String routeType, Decimal miles) {
    Truck_Route__c row = built(f, routeType, miles);
    insert row;
    return row;
  }

  @IsTest
  static void medianMilesTakesTheMiddleOfPositiveMiles() {
    System.assertEquals(
      412.5,
      TripMilesService.medianMiles(
        new List<LaneSearchResult.Row>{
          row(500.0),
          row(0),
          row(null),
          row(300.0),
          row(-20.0),
          row(412.5)
        }
      ),
      'odd count: the middle value; zero, negative and blank miles are ignored'
    );
    System.assertEquals(
      456.5,
      TripMilesService.medianMiles(
        new List<LaneSearchResult.Row>{
          row(610.0),
          row(300.0),
          row(500.0),
          row(413.0)
        }
      ),
      'even count: the mean of the two middle values'
    );
    System.assertEquals(
      333.4,
      TripMilesService.medianMiles(
        new List<LaneSearchResult.Row>{ row(333.36) }
      ),
      'one decimal'
    );
    System.assertEquals(
      null,
      TripMilesService.medianMiles(
        new List<LaneSearchResult.Row>{ row(0), row(null) }
      ),
      'no row has miles'
    );
    System.assertEquals(
      null,
      TripMilesService.medianMiles(new List<LaneSearchResult.Row>())
    );
    System.assertEquals(null, TripMilesService.medianMiles(null));
  }

  @IsTest
  static void approxMilesIsTheGreatCircleTimesTheFactor() {
    Pricing_Place__c mtl = new Pricing_Place__c(
      Geolocation__Latitude__s = 45.5019,
      Geolocation__Longitude__s = -73.5674
    );
    Pricing_Place__c tor = new Pricing_Place__c(
      Geolocation__Latitude__s = 43.6532,
      Geolocation__Longitude__s = -79.3832
    );
    TruckRoute.Profile p = profile();
    System.assertEquals(
      376.0,
      TripMilesService.approxMiles(mtl, tor, p),
      '313.3 great-circle miles x 1.2'
    );
    p.approxFactor = 1;
    System.assertEquals(
      313.3,
      TripMilesService.approxMiles(mtl, tor, p),
      'the factor comes from the profile'
    );
    System.assertEquals(
      313.3,
      TripMilesService.approxMiles(tor, mtl, p),
      'the straight line is the same both ways'
    );
    Pricing_Place__c noLongitude = new Pricing_Place__c(
      Geolocation__Latitude__s = 45.5019
    );
    System.assertEquals(
      null,
      TripMilesService.approxMiles(noLongitude, tor, p)
    );
    System.assertEquals(null, TripMilesService.approxMiles(mtl, null, p));
  }

  @IsTest
  static void routeKeyIsOrderedAndFollowsTheTruck() {
    Fx f = fx();
    Id a = f.mtl.Id;
    Id b = f.tor.Id;
    TruckRoute.Profile p = profile();
    String key = TripMilesService.routeKey(a, b, p);
    System.assertEquals(
      String.valueOf(a) + ':' + String.valueOf(b) + ':h4.11w2.60t36.29',
      key
    );
    System.assertNotEquals(
      key,
      TripMilesService.routeKey(b, a, p),
      'direction matters'
    );
    p.heightM = 4.2;
    System.assertNotEquals(key, TripMilesService.routeKey(a, b, p), 'height');
    p = profile();
    p.widthM = 2.5;
    System.assertNotEquals(key, TripMilesService.routeKey(a, b, p), 'width');
    p = profile();
    p.weightT = 30;
    System.assertNotEquals(key, TripMilesService.routeKey(a, b, p), 'weight');
    System.assertEquals(null, TripMilesService.routeKey(null, b, profile()));
  }

  @IsTest
  static void storedRoutesIgnoresARowWhosePlaceWasDeleted() {
    Fx f = fx();
    Truck_Route__c row = stored(f, 'Truck', 336.3);
    Map<String, Truck_Route__c> found = TripMilesService.storedRoutes(
      new Set<String>{ row.Route_Key__c, 'no:such:key' }
    );
    System.assertEquals(new Set<String>{ row.Route_Key__c }, found.keySet());
    System.assertEquals(336.3, found.get(row.Route_Key__c).Miles__c);
    delete f.tor;
    System.assertEquals(
      null,
      [SELECT Destination_Place__c FROM Truck_Route__c WHERE Id = :row.Id]
      .Destination_Place__c,
      'the lookup clears on delete'
    );
    System.assertEquals(
      0,
      TripMilesService.storedRoutes(new Set<String>{ row.Route_Key__c }).size(),
      'a row with a blank place is ignored'
    );
    System.assertEquals(
      0,
      TripMilesService.storedRoutes(new Set<String>()).size()
    );
    System.assertEquals(0, TripMilesService.storedRoutes(null).size());
  }

  @IsTest
  static void fromStoredRebuildsTheResult() {
    TruckRoute.Result r = TripMilesService.fromStored(
      new Truck_Route__c(
        Status__c = 'Found',
        Route_Type__c = 'Regular',
        Miles__c = 336.3,
        Hours__c = 5.6,
        Routes_Json__c = '[{"miles":336.3,"hours":5.6,"polyline5":"_p~iF~ps|U"},' +
          '{"miles":349.8,"hours":6.0,"polyline5":"_ulLnnqC"}]'
      )
    );
    System.assertEquals('Found', r.status);
    System.assertEquals('Regular', r.routeType);
    System.assertEquals(
      2,
      r.routes.size(),
      'main route first, then one alternative'
    );
    System.assertEquals(336.3, r.routes[0].miles);
    System.assertEquals(5.6, r.routes[0].hours);
    System.assertEquals('_p~iF~ps|U', r.routes[0].polyline5);
    System.assertEquals(349.8, r.routes[1].miles);
    TruckRoute.Result none = TripMilesService.fromStored(
      new Truck_Route__c(Status__c = 'No route', Routes_Json__c = '[]')
    );
    System.assertEquals('No route', none.status);
    System.assertEquals(null, none.routeType);
    System.assertEquals(0, none.routes.size());
    System.assertEquals(
      0,
      TripMilesService.fromStored(
          new Truck_Route__c(Status__c = 'Found', Routes_Json__c = 'not json')
        )
        .routes.size(),
      'unreadable JSON gives no routes instead of an error'
    );
    System.assertEquals(
      0,
      TripMilesService.fromStored(new Truck_Route__c(Status__c = 'No route'))
        .routes.size()
    );
  }

  @IsTest
  static void aStoredRouteWinsWithoutACallout() {
    Fx f = fx();
    stored(f, 'Regular', 336.3);
    Mock m = new Mock(200, TRUCK_BODY);
    Test.setMock(HttpCalloutMock.class, m);
    Test.startTest();
    TripMilesService.RouteOutcome out = TripMilesService.storedOrRoute(
      f.mtl,
      f.tor,
      f.p,
      false
    );
    Integer callouts = Limits.getCallouts();
    Test.stopTest();
    System.assertEquals(0, m.calls, 'no Mapbox request');
    System.assertEquals(0, callouts);
    System.assert(out.fromStore, 'served from Truck_Route__c');
    System.assertEquals(null, out.toSave, 'nothing to save');
    System.assertEquals('Found', out.result.status);
    System.assertEquals('Regular', out.result.routeType);
    System.assertEquals(336.3, out.result.routes[0].miles);
  }

  @IsTest
  static void anotherTruckDoesNotReuseTheStoredRoute() {
    Fx f = fx();
    stored(f, 'Truck', 336.3);
    f.p.heightM = 4.3;
    Mock m = new Mock(200, TRUCK_BODY);
    Test.setMock(HttpCalloutMock.class, m);
    Test.startTest();
    TripMilesService.RouteOutcome out = TripMilesService.storedOrRoute(
      f.mtl,
      f.tor,
      f.p,
      false
    );
    Test.stopTest();
    System.assertEquals(1, m.calls, 'a new profile key asks Mapbox');
    System.assert(!out.fromStore);
    System.assertEquals(
      TripMilesService.routeKey(f.mtl.Id, f.tor.Id, f.p),
      out.toSave.Route_Key__c
    );
    System.assert(
      out.toSave.Profile_Key__c.startsWith('h4.30'),
      out.toSave.Profile_Key__c
    );
  }

  @IsTest
  static void refreshAsksMapboxAndReplacesTheStoredRow() {
    Fx f = fx();
    Truck_Route__c old = stored(f, 'Regular', 999.9);
    Mock m = new Mock(200, TRUCK_BODY);
    Test.setMock(HttpCalloutMock.class, m);
    Test.startTest();
    TripMilesService.RouteOutcome out = TripMilesService.storedOrRoute(
      f.mtl,
      f.tor,
      f.p,
      true
    );
    TripMilesService.save(new List<Truck_Route__c>{ out.toSave });
    Test.stopTest();
    System.assertEquals(
      1,
      m.calls,
      'one request: the truck route had no violation'
    );
    System.assert(!out.fromStore);
    System.assertEquals('Found', out.result.status);
    System.assertEquals('Truck', out.result.routeType);
    System.assertEquals(2, out.result.routes.size());
    Truck_Route__c s = out.toSave;
    System.assertEquals(old.Route_Key__c, s.Route_Key__c);
    System.assertEquals(f.p.key(), s.Profile_Key__c);
    System.assertEquals(f.mtl.Id, s.Origin_Place__c);
    System.assertEquals(f.tor.Id, s.Destination_Place__c);
    System.assertEquals('Found', s.Status__c);
    System.assertEquals('Truck', s.Route_Type__c);
    System.assertEquals(335.5, s.Miles__c, '540,000 m');
    System.assertEquals(5.6, s.Hours__c, '20,160 s');
    System.assertNotEquals(null, s.Checked_On__c);
    List<TruckRoute.Line> lines = (List<TruckRoute.Line>) JSON.deserialize(
      s.Routes_Json__c,
      List<TruckRoute.Line>.class
    );
    System.assertEquals(2, lines.size());
    System.assertEquals('_p~iF~ps|U_ulLnnqC_mqNvxq`@', lines[0].polyline5);
    System.assertEquals(349.8, lines[1].miles);
    System.assertEquals(6.0, lines[1].hours);
    List<Truck_Route__c> rows = [
      SELECT Id, Miles__c, Route_Type__c, Routes_Json__c
      FROM Truck_Route__c
    ];
    System.assertEquals(1, rows.size(), 'the refresh replaced the row');
    System.assertEquals(old.Id, rows[0].Id);
    System.assertEquals(335.5, rows[0].Miles__c);
    System.assertEquals('Truck', rows[0].Route_Type__c);
    System.assertEquals(
      2,
      TripMilesService.fromStored(rows[0]).routes.size(),
      'the saved JSON reads back'
    );
  }

  @IsTest
  static void noRouteIsSavedWithoutMiles() {
    Fx f = fx();
    Mock m = new Mock(200, NO_ROUTE_BODY);
    Test.setMock(HttpCalloutMock.class, m);
    Test.startTest();
    TripMilesService.RouteOutcome out = TripMilesService.storedOrRoute(
      f.mtl,
      f.tor,
      f.p,
      false
    );
    TripMilesService.save(new List<Truck_Route__c>{ out.toSave });
    Test.stopTest();
    System.assertEquals(2, m.calls, 'the truck request, then the regular one');
    System.assertEquals('No route', out.result.status);
    Truck_Route__c row = [
      SELECT Status__c, Route_Type__c, Miles__c, Hours__c, Routes_Json__c
      FROM Truck_Route__c
    ];
    System.assertEquals('No route', row.Status__c);
    System.assertEquals(null, row.Route_Type__c);
    System.assertEquals(null, row.Miles__c);
    System.assertEquals(null, row.Hours__c);
    System.assertEquals('[]', row.Routes_Json__c);
  }

  @IsTest
  static void unavailableGivesNothingToSave() {
    Fx f = fx();
    Mock m = new Mock(401, '{"message":"Not Authorized - Invalid Token"}');
    Test.setMock(HttpCalloutMock.class, m);
    Test.startTest();
    TripMilesService.RouteOutcome out = TripMilesService.storedOrRoute(
      f.mtl,
      f.tor,
      f.p,
      false
    );
    TripMilesService.RouteOutcome noCoordinates = TripMilesService.storedOrRoute(
      f.mtl,
      new Pricing_Place__c(Id = f.tor.Id),
      f.p,
      true
    );
    TripMilesService.RouteOutcome noPlace = TripMilesService.storedOrRoute(
      null,
      f.tor,
      f.p,
      false
    );
    Test.stopTest();
    System.assertEquals(1, m.calls, 'only the first call reached Mapbox');
    System.assertEquals('Unavailable', out.result.status);
    System.assertEquals(TruckRoute.UNAVAILABLE, out.result.message);
    System.assertEquals(null, out.toSave);
    System.assert(!out.fromStore);
    System.assertEquals('Unavailable', noCoordinates.result.status);
    System.assertEquals(null, noCoordinates.toSave);
    System.assertEquals('Unavailable', noPlace.result.status);
    System.assertEquals(TruckRoute.UNAVAILABLE, noPlace.result.message);
    System.assertEquals(0, [SELECT COUNT() FROM Truck_Route__c]);
  }

  @IsTest
  static void saveUpsertsOnTheRouteKey() {
    Fx f = fx();
    TripMilesService.save(new List<Truck_Route__c>{ built(f, 'Truck', 336.3) });
    TripMilesService.save(
      new List<Truck_Route__c>{ built(f, 'Regular', 350.1) }
    );
    TripMilesService.save(new List<Truck_Route__c>());
    TripMilesService.save(null);
    List<Truck_Route__c> rows = [
      SELECT Miles__c, Route_Type__c
      FROM Truck_Route__c
      WHERE Route_Key__c = :TripMilesService.routeKey(f.mtl.Id, f.tor.Id, f.p)
    ];
    System.assertEquals(
      1,
      rows.size(),
      'the second save updated the first row'
    );
    System.assertEquals(350.1, rows[0].Miles__c);
    System.assertEquals('Regular', rows[0].Route_Type__c);
  }

  @IsTest
  static void aPricerRefreshesARouteAColleagueSaved() {
    Fx f = fx();
    Truck_Route__c old = stored(f, 'Truck', 336.3);
    User pricer = RfpTestDataFactory.restrictedUser('RFP_Tool_User');
    if (pricer == null) {
      System.assert(
        true,
        'no usable profile in this org; runAs coverage skipped (ledgered)'
      );
      return;
    }
    Integer seen;
    System.runAs(pricer) {
      seen = TripMilesService.storedRoutes(new Set<String>{ old.Route_Key__c })
        .size();
      TripMilesService.save(
        new List<Truck_Route__c>{ built(f, 'Regular', 350.1) }
      );
    }
    System.assertEquals(
      1,
      seen,
      'Public Read Only: the pricer reads the route'
    );
    Truck_Route__c after = [
      SELECT Id, OwnerId, Miles__c, Route_Type__c
      FROM Truck_Route__c
      WHERE Route_Key__c = :old.Route_Key__c
    ];
    System.assertEquals(old.Id, after.Id, 'updated, not duplicated');
    System.assertEquals(350.1, after.Miles__c);
    System.assertEquals('Regular', after.Route_Type__c);
    System.assertEquals(
      UserInfo.getUserId(),
      after.OwnerId,
      'the row still belongs to the admin who saved it first'
    );
  }
}
```

Create `force-app/main/default/classes/TripMilesServiceTest.cls-meta.xml`:

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<ApexClass xmlns="http://soap.sforce.com/2006/04/metadata">
    <apiVersion>64.0</apiVersion>
    <status>Active</status>
</ApexClass>
```

The mock bodies follow the Directions response: `routes[].distance` in metres, `routes[].duration` in seconds, `routes[].geometry` a polyline5 string, and `code` `NoRoute` with an empty `routes` array on HTTP 200. Neither route carries a notification, so `MapboxTruckRoute` (Task 2) keeps the truck route after one request. On `NoRoute` it sends the regular request, which gets the same body, so `noRouteIsSavedWithoutMiles` expects two calls. Expected values: 540,000 m / 1,609.344 = 335.54, so 335.5 mi; 20,160 s / 3,600 = 5.6 h; 563,000 m, so 349.8 mi; 21,600 s, so 6.0 h. With a radius of 3,958.7613 mi the great circle from Montréal (45.5019, -73.5674) to Toronto (43.6532, -79.3832) is 313.335 mi, so 313.3 at factor 1 and 376.0 at factor 1.2.

- [ ] **Step 2: Deploy the test alone to see it fail to compile**

Run: `sf project deploy start -o sandbox --source-dir force-app/main/default/classes/TripMilesServiceTest.cls -l NoTestRun --async --json | python3 -c "import json,sys; s=sys.stdin.read(); print(json.loads(s[s.index('{'):])['result']['id'])"`

Expected: a deploy id (`0Af...`). Then poll, repeating until the status is `Succeeded` or `Failed` (each call waits at most 2 minutes):

Run: `sf project deploy report -o sandbox --job-id <id> -w 2 --json | python3 -c "import json,sys; s=sys.stdin.read(); r=json.loads(s[s.index('{'):])['result']; print(r['status'], [d.get('problem') for d in r.get('details',{}).get('componentFailures',[])][:2])"`

Expected: `Failed` with `Invalid type: TripMilesService` or `Variable does not exist: load`. Neither exists yet.

- [ ] **Step 3: Move the load Id into `LaneSearchResult.LoadDetail` and declare the phase 7 result fields**

`medianMiles` reads `row.load.miles`, and this task runs before Task 5, so the phase 7 result fields are declared here and Task 5 fills them. `Row` already has 20 fields, and PMD's `TooManyFields` (maxfields 20) fires at 21 (checked with PMD 7.15.0 on a copy of the class); the repo's rule is "split, never suppress" (phase 3a and 3b plans), which is why `CarrierDetail` and `BidDetail` already sit off `Row`. So `loadId`, which nothing reads outside `LaneSearchService.toRow` (grep over `force-app`, the LWC `__tests__` included), moves into a new group `LoadDetail { loadId, miles }`, and `Row` gains `load` in its place.

Replace the whole content of `force-app/main/default/classes/LaneSearchResult.cls` with:

```apex
/**
 * Typed output of LaneSearchService.search(). Plain data, no logic. Every public field carries
 * @AuraEnabled so phase 2's LWC can consume this object (and its Row/Stats members) straight out
 * of an @AuraEnabled controller method with no DTO in between.
 */
public class LaneSearchResult {
  public class Row {
    @AuraEnabled
    public Id quoteId;
    @AuraEnabled
    public String quoteName;
    // Phase 7: the quote's load (its Id and billed miles), initialized like carrier so bid rows
    // carry load.miles = null. loadId moved in here to keep Row at PMD's TooManyFields cap of 20.
    @AuraEnabled
    public LoadDetail load = new LoadDetail();
    @AuraEnabled
    public String origin;
    @AuraEnabled
    public String destination;
    @AuraEnabled
    public String mode;
    @AuraEnabled
    public String equipment;
    @AuraEnabled
    public String equipmentCategory;
    @AuraEnabled
    public String carrierName;
    @AuraEnabled
    public String contactName;
    @AuraEnabled
    public String currencyIsoCode;
    @AuraEnabled
    public Decimal carrierTotal;
    @AuraEnabled
    public Date quoteDate;
    @AuraEnabled
    public Boolean hazmat;
    @AuraEnabled
    public Boolean accepted;
    @AuraEnabled
    public String loadStatus;
    @AuraEnabled
    public String opsComments;
    // The quote's own CreatedDate, which is what rows are ordered by (Quote_Date__c is a formula
    // and can be blank); phase 2 shows it as the row's age.
    @AuraEnabled
    public Datetime createdDate;
    @AuraEnabled
    public CarrierDetail carrier = new CarrierDetail();
    // Phase 3: set only on rows that come from Benchmark_Rate__c (bids); null for loads. No
    // initializer, unlike carrier above, so the LWC can treat bid != null as "this is a bid".
    @AuraEnabled
    public BidDetail bid;
  }

  // Grouped off Row (Task 3 review ruling) to keep Row under PMD's TooManyFields threshold:
  // contactEmail/contactPhone/risk/loadCount/attention all describe the carrier on the quote.
  public class CarrierDetail {
    @AuraEnabled
    public String contactEmail;
    @AuraEnabled
    public String contactPhone;
    @AuraEnabled
    public String risk;
    @AuraEnabled
    public Decimal loadCount;
    @AuraEnabled
    public String attention;
  }

  // Phase 3: set only on rows that come from Benchmark_Rate__c (bids). Grouped, like CarrierDetail,
  // so Row stays under PMD's TooManyFields threshold; the LWC treats bid != null as "this is a bid".
  public class BidDetail {
    @AuraEnabled
    public Id rateId;
    @AuraEnabled
    public Date expiresOn;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public Decimal transitDays;
    @AuraEnabled
    public Decimal fuelSurcharge;
    @AuraEnabled
    public Boolean fscIncluded;
  }

  // Phase 7: the quote's load. Grouped, like CarrierDetail, so Row stays at PMD's TooManyFields
  // cap; bid rows keep both fields null.
  public class LoadDetail {
    @AuraEnabled
    public Id loadId;
    // rtms__Load__c.rtms__Distance_Miles__c: Revenova's billed miles (PC*Miler); null when blank.
    @AuraEnabled
    public Decimal miles;
  }

  public class Stats {
    @AuraEnabled
    public Integer count = 0;
    @AuraEnabled
    public Integer countNonZero = 0;
    @AuraEnabled
    public Decimal min;
    @AuraEnabled
    public Decimal max;
    @AuraEnabled
    public Decimal avg;
    @AuraEnabled
    public Decimal median;
    // Phase 7: median of carrierTotal / load.miles over this currency's rows with both above zero,
    // scale 2; null when no row has both (bids have no miles).
    @AuraEnabled
    public Decimal ratePerMileMedian;
  }

  @AuraEnabled
  public List<Row> rows = new List<Row>();
  @AuraEnabled
  public Map<String, Stats> statsByCurrency = new Map<String, Stats>();
  @AuraEnabled
  public Boolean truncated = false;
  // Integer, not Long: LWC receives a Long as a string once it exceeds 2^53, and a query time in
  // milliseconds never comes close to Integer's range.
  @AuraEnabled
  public Integer elapsedMs = 0;
  @AuraEnabled
  public Integer dedupedCount = 0;
  // Phase 7: TripMilesService.medianMiles over rows (load miles above zero), scale 1; null when none.
  @AuraEnabled
  public Decimal medianMiles;
}
```

Row keeps exactly 20 fields: `loadId` (old lines 12-13) became `load`.

In `force-app/main/default/classes/LaneSearchService.cls`, `toRow`, replace line 171:

```apex
    r.loadId = q.rtms__Load__c;
```

with:

```apex
    r.load.loadId = q.rtms__Load__c;
```

`BidSearchService.toRow` needs no change: `new LaneSearchResult.Row()` initializes `load`, and a bid never sets its fields. Task 5 adds the miles line after this one.

- [ ] **Step 4: Write the service**

Create `force-app/main/default/classes/TripMilesService.cls`:

```apex
/**
 * Trip miles for a lane (phase 7): the median of the billed miles a history search matched, an
 * approximate distance from the two places' coordinates, and the Mapbox truck route stored per
 * ordered place pair and truck profile in Truck_Route__c. Nothing here writes a lane: the callers
 * (RfpHistoryService, RfpLaneController.laneRoute, LaneBenchmarkController.truckRoute) decide what
 * a lane shows, and they save the route after their callouts, because storedOrRoute makes no DML.
 * Truck_Route__c is a shared cache of Mapbox results, not anyone's data: it is read in system mode
 * and only this class writes it, through Store, which runs without sharing (see its comment).
 */
public with sharing class TripMilesService {
  public static final Decimal EARTH_RADIUS_MI = 3958.7613;
  private static final String FOUND = 'Found';
  private static final String NO_ROUTE = 'No route';
  private static final Geo GEO = new Geo();
  private static final Store STORE = new Store();

  public class RouteOutcome {
    public TruckRoute.Result result;
    public Truck_Route__c toSave;
    public Boolean fromStore = false;
  }

  /**
   * Median of row.load.miles over the rows above zero, one decimal: odd count the middle value,
   * even count the mean of the two middle values (LaneSearchService's rule). A row without a load
   * group (JSON.deserialize skips field initializers) is skipped. Null when no row has miles.
   */
  public static Decimal medianMiles(List<LaneSearchResult.Row> rows) {
    if (rows == null) {
      return null;
    }
    List<Decimal> miles = new List<Decimal>();
    for (LaneSearchResult.Row row : rows) {
      Decimal m = row?.load?.miles;
      if (m != null && m > 0) {
        miles.add(m);
      }
    }
    if (miles.isEmpty()) {
      return null;
    }
    miles.sort();
    Integer n = miles.size();
    Decimal median = Math.mod(n, 2) == 1
      ? miles[n / 2]
      : (miles[n / 2 - 1] + miles[n / 2]) / 2;
    return median.setScale(1);
  }

  /**
   * Great-circle (haversine) miles between the two places times the profile's Approx factor, one
   * decimal. Null when a place or one of its coordinates is missing, or the profile has no factor.
   */
  public static Decimal approxMiles(
    Pricing_Place__c o,
    Pricing_Place__c d,
    TruckRoute.Profile p
  ) {
    if (
      !GEO.hasCoordinates(o) ||
      !GEO.hasCoordinates(d) ||
      p?.approxFactor == null
    ) {
      return null;
    }
    return (GEO.greatCircleMiles(o, d) * p.approxFactor).setScale(1);
  }

  /** '<origin place Id>:<destination place Id>:<profile key>'; direction matters. Null without both places. */
  public static String routeKey(
    Id originPlaceId,
    Id destinationPlaceId,
    TruckRoute.Profile p
  ) {
    if (originPlaceId == null || destinationPlaceId == null) {
      return null;
    }
    return String.valueOf(originPlaceId) +
      ':' +
      String.valueOf(destinationPlaceId) +
      ':' +
      p.key();
  }

  /**
   * The stored rows for routeKeys, by Route_Key__c. A row whose place was deleted (the lookups
   * clear on delete) no longer describes a place pair and is ignored. One query; none for an
   * empty set.
   */
  // System mode on purpose: Truck_Route__c is Public Read Only and both permission sets read it;
  // a stored route is a Mapbox result shared by everyone who prices, not a user's record.
  @SuppressWarnings('PMD.ApexCRUDViolation')
  public static Map<String, Truck_Route__c> storedRoutes(
    Set<String> routeKeys
  ) {
    Map<String, Truck_Route__c> byKey = new Map<String, Truck_Route__c>();
    if (routeKeys == null || routeKeys.isEmpty()) {
      return byKey;
    }
    for (Truck_Route__c row : [
      SELECT
        Id,
        Route_Key__c,
        Profile_Key__c,
        Origin_Place__c,
        Destination_Place__c,
        Miles__c,
        Hours__c,
        Route_Type__c,
        Status__c,
        Routes_Json__c,
        Checked_On__c
      FROM Truck_Route__c
      WHERE
        Route_Key__c IN :routeKeys
        AND Origin_Place__c != NULL
        AND Destination_Place__c != NULL
    ]) {
      byKey.put(row.Route_Key__c, row);
    }
    return byKey;
  }

  /** A stored row as a route result: its status, route type and the routes saved with it, main route first. */
  public static TruckRoute.Result fromStored(Truck_Route__c row) {
    TruckRoute.Result r = new TruckRoute.Result();
    r.status = row.Status__c;
    r.routeType = row.Route_Type__c;
    if (String.isNotBlank(row.Routes_Json__c)) {
      try {
        r.routes = (List<TruckRoute.Line>) JSON.deserialize(
          row.Routes_Json__c,
          List<TruckRoute.Line>.class
        );
      } catch (JSONException e) {
        r.routes = null;
      }
    }
    if (r.routes == null) {
      r.routes = new List<TruckRoute.Line>();
    }
    return r;
  }

  /**
   * The stored route for the ordered place pair and truck profile wins unless refresh; otherwise
   * one Mapbox route call (two with the regular fallback). toSave is the row to upsert for Found
   * and No route, never for Unavailable; the caller saves it after its callouts (no DML here). A
   * missing place, or a place without coordinates and no stored route, is Unavailable without a
   * callout.
   */
  public static RouteOutcome storedOrRoute(
    Pricing_Place__c o,
    Pricing_Place__c d,
    TruckRoute.Profile p,
    Boolean refresh
  ) {
    RouteOutcome out = new RouteOutcome();
    String key = routeKey(o?.Id, d?.Id, p);
    if (key == null) {
      out.result = unavailable();
      return out;
    }
    if (refresh != true) {
      Truck_Route__c stored = storedRoutes(new Set<String>{ key }).get(key);
      if (stored != null) {
        out.result = fromStored(stored);
        out.fromStore = true;
        return out;
      }
    }
    if (!GEO.hasCoordinates(o) || !GEO.hasCoordinates(d)) {
      out.result = unavailable();
      return out;
    }
    out.result = MapboxTruckRoute.route(GEO.point(o), GEO.point(d), p);
    if (out.result.status == FOUND || out.result.status == NO_ROUTE) {
      out.toSave = STORE.row(o.Id, d.Id, key, p, out.result);
    }
    return out;
  }

  /** Upserts route rows on Route_Key__c, so a refresh replaces the row; an empty list does nothing. */
  public static void save(List<Truck_Route__c> rows) {
    if (rows == null || rows.isEmpty()) {
      return;
    }
    STORE.upsertRows(rows);
  }

  private static TruckRoute.Result unavailable() {
    TruckRoute.Result r = new TruckRoute.Result();
    r.status = 'Unavailable';
    r.message = TruckRoute.UNAVAILABLE;
    return r;
  }

  /** Coordinates of a place, and the great-circle distance between two. */
  private class Geo {
    private Boolean hasCoordinates(Pricing_Place__c place) {
      return place != null &&
        place.Geolocation__Latitude__s != null &&
        place.Geolocation__Longitude__s != null;
    }

    private TruckRoute.Point point(Pricing_Place__c place) {
      return new TruckRoute.Point(
        place.Geolocation__Latitude__s,
        place.Geolocation__Longitude__s
      );
    }

    /** Haversine miles on a sphere of EARTH_RADIUS_MI; both places must have coordinates. */
    private Decimal greatCircleMiles(Pricing_Place__c o, Pricing_Place__c d) {
      Double lat1 = radians(o.Geolocation__Latitude__s);
      Double lat2 = radians(d.Geolocation__Latitude__s);
      Double dLng = radians(
        d.Geolocation__Longitude__s - o.Geolocation__Longitude__s
      );
      Double h =
        Math.pow(Math.sin((lat2 - lat1) / 2), 2) +
        Math.cos(lat1) * Math.cos(lat2) * Math.pow(Math.sin(dLng / 2), 2);
      return Decimal.valueOf(
        2 * EARTH_RADIUS_MI.doubleValue() * Math.asin(Math.sqrt(h))
      );
    }

    private Double radians(Decimal degrees) {
      return degrees.doubleValue() * Math.PI / 180;
    }
  }

  /**
   * Without sharing on purpose, and only for writing Truck_Route__c. The object is Public Read
   * Only, so under the outer class's sharing a pricer refreshing a route a colleague saved would
   * fail on the update (the row belongs to whoever opened the lane first). The permission sets
   * grant read only, so the write also runs in system mode past object permissions; every row
   * comes from row() below, built from a Mapbox answer for two places the caller has already read.
   */
  private without sharing class Store {
    /** The row for a Found or No route result; a Found result without routes is stored as No route. */
    private Truck_Route__c row(
      Id originId,
      Id destinationId,
      String key,
      TruckRoute.Profile p,
      TruckRoute.Result r
    ) {
      Boolean found = r.status == FOUND && !r.routes.isEmpty();
      TruckRoute.Line main = found ? r.routes[0] : new TruckRoute.Line();
      return new Truck_Route__c(
        Origin_Place__c = originId,
        Destination_Place__c = destinationId,
        Profile_Key__c = p.key(),
        Route_Key__c = key,
        Status__c = found ? FOUND : NO_ROUTE,
        Route_Type__c = found ? r.routeType : null,
        Miles__c = main.miles,
        Hours__c = main.hours,
        Routes_Json__c = JSON.serialize(
          found ? r.routes : new List<TruckRoute.Line>()
        ),
        Checked_On__c = System.now()
      );
    }

    @SuppressWarnings('PMD.ApexCRUDViolation')
    private void upsertRows(List<Truck_Route__c> rows) {
      Database.upsert(
        rows,
        Truck_Route__c.Route_Key__c,
        true,
        AccessLevel.SYSTEM_MODE
      );
    }
  }
}
```

Create `force-app/main/default/classes/TripMilesService.cls-meta.xml` with the same content as the test's meta file (apiVersion 64.0, status Active).

- [ ] **Step 5: Add the classes to the manifest**

In `manifest/package.xml`, inside the `<types>` block whose `<name>` is `ApexClass`, directly before `<name>ApexClass</name>` (after the members Tasks 2 and 3 added):

```xml
        <members>TripMilesService</members>
        <members>TripMilesServiceTest</members>
```

- [ ] **Step 6: Deploy the four classes and run the tests**

`LaneSearchServiceTest` runs as well: the org enforces 75% coverage per deployed class, and it covers `LaneSearchService` and builds a whole `LaneSearchResult`.

Run: `sf project deploy start -o sandbox --source-dir force-app/main/default/classes/LaneSearchResult.cls --source-dir force-app/main/default/classes/LaneSearchService.cls --source-dir force-app/main/default/classes/TripMilesService.cls --source-dir force-app/main/default/classes/TripMilesServiceTest.cls -l RunSpecifiedTests -t TripMilesServiceTest -t LaneSearchServiceTest --async --json | python3 -c "import json,sys; s=sys.stdin.read(); print(json.loads(s[s.index('{'):])['result']['id'])"`

Expected: a deploy id. Poll until the status is `Succeeded` or `Failed`:

Run: `sf project deploy report -o sandbox --job-id <id> -w 2 --json | python3 -c "import json,sys; s=sys.stdin.read(); r=json.loads(s[s.index('{'):])['result']; print(r['id'], r['status'], 'tests', r.get('numberTestsCompleted'), '/', r.get('numberTestsTotal'), 'failures', r.get('numberTestErrors')); [print(f['name'], f['methodName'], '->', f['message'][:160]) for f in r.get('details',{}).get('runTestResult',{}).get('failures',[])]"`

Expected: `Succeeded tests 31 / 31 failures 0` (12 `TripMilesServiceTest` + 19 `LaneSearchServiceTest`). If a test fails, fix the class, not the assertion, unless the assertion contradicts the spec. Two failures point at Task 2, not this class. First, `noRouteIsSavedWithoutMiles` with `calls` 1 means `MapboxTruckRoute` does not fall back on `NoRoute`. Second, `refreshAsksMapboxAndReplacesTheStoredRow` with miles other than 335.5 means its metres-to-miles conversion is off. In `aPricerRefreshesARouteAColleagueSaved`, `INSUFFICIENT_ACCESS_OR_READONLY` means the upsert is not running inside the `without sharing` `Store`.

- [ ] **Step 7: PMD**

Run: `/private/tmp/pmd_install/pmd-bin-7.15.0/bin/pmd check --dir force-app --rulesets config/pmd-ruleset.xml --minimum-priority 3 --format text --fail-on-violation; echo "pmd exit $?"`

Expected: no violation lines, `pmd exit 0`. Suppressions in this task: `ApexCRUDViolation` on `storedRoutes` and on `Store.upsertRows`; `LaneSearchResult.Row` stays at 20 fields (no suppression). The geometry helpers live in the inner class `Geo` and the row builder in `Store`, because inner-class methods do not count toward the outer class. With them in `TripMilesService` itself, PMD reported a class cyclomatic complexity of 43, then 40. If PMD flags the class again, move another private helper into an inner class; do not raise the budget.

- [ ] **Step 8: Commit**

```bash
git add force-app/main/default/classes/TripMilesService.cls force-app/main/default/classes/TripMilesService.cls-meta.xml force-app/main/default/classes/TripMilesServiceTest.cls force-app/main/default/classes/TripMilesServiceTest.cls-meta.xml force-app/main/default/classes/LaneSearchResult.cls force-app/main/default/classes/LaneSearchService.cls manifest/package.xml
git commit -m "Add TripMilesService: history median, approximate distance and stored truck routes"
```

Expected: lint-staged runs Prettier on the staged Apex (no change: the code above is already formatted) and the commit lands on `phase-7/trip-miles`. `git status --short` still shows `.vscode/settings.json` and the `* 2.*` files unstaged.

#### Contract notes (Task 4)

1. **`Row.loadId` moved into `LaneSearchResult.LoadDetail` next to the new `miles`** (Task 5 note 1). `Row` stays at 20 fields; no suppression (phase 3a/3b rule). Task 4 carries the whole phase 7 `LaneSearchResult` and the one-line `toRow` change because `medianMiles` reads `row.load.miles` and Task 4 runs first; Task 5 only fills the fields. Every later task reads `row.load.miles` (the Lane Benchmark CSV field is `load.miles`).
2. **`save` writes through a private inner `without sharing` class `Store`.** `TripMilesService` stays `public with sharing`, as the contract says. `Truck_Route__c` is Public Read Only, though, and `AccessLevel.SYSTEM_MODE` skips object and field permissions but still applies the class's sharing keyword. Under `with sharing`, a pricer refreshing a route another user saved would fail the update with `INSUFFICIENT_ACCESS_OR_READONLY`. This follows `RfpBidAccess` (a `private without sharing class` used through a `private static final` instance). `aPricerRefreshesARouteAColleagueSaved` proves it under `System.runAs` with an `RFP_Tool_User`, and skips like the other runAs tests when the org has no usable profile. `storedRoutes` stays in the outer class: system mode for object and field permissions, sharing `with sharing` (Public Read Only shows every row). It uses no `WITH SYSTEM_MODE` clause, since static SOQL does not check object permissions and the repo does not use that clause.
3. **Complexity budget.** With every helper in the outer class, PMD reported a class cyclomatic complexity of 43, then 40 (the report level). The geometry (`hasCoordinates`, `point`, `greatCircleMiles`, `radians`) is in the inner class `Geo`, and the row builder (`row`) is in `Store`. The public signatures are exactly the contract's.
4. **The approx example is 313.3 mi, not 312.6.** Haversine with `EARTH_RADIUS_MI` 3958.7613 gives 313.335 mi from Montréal (45.5019, -73.5674) to Toronto (43.6532, -79.3832). The test asserts 313.3 at factor 1 and 376.0 at factor 1.2.
5. **`medianMiles` puts both counts at one decimal.** The odd-count middle value also goes through `setScale(1)`, like the even-count mean, so History miles always match `Miles__c` Number(10,1). A negative or null `row` is ignored, like zero.
6. **Guards the contract does not name.**
   - `routeKey` returns `null` when either place Id is null.
   - `approxMiles` returns `null` when the profile or its `approxFactor` is null.
   - `storedOrRoute` returns `Unavailable` with `TruckRoute.UNAVAILABLE`, with no callout and no `toSave`, when a place is null. It does the same when a place has no coordinates and no stored row answers (a stored row is still served).
   - Task 7's `laneRoute` keeps its own `This lane has no coordinates.` check before calling.
7. **What `toSave` holds.** For `Found` it carries the main route's miles and hours, `Route_Type__c` from the result and `Routes_Json__c` = `JSON.serialize(result.routes)`. For `No route` it carries null miles, hours and `Route_Type__c`, and `Routes_Json__c` `[]`. A `Found` result with no routes is stored as `No route`. `Checked_On__c` is `System.now()`.
8. **What the tests take from Tasks 1 and 2.**
   - Task 2: `new TruckRoute.Profile()` with no arguments, the public fields and `key()` in the form `h4.11w2.60t36.29`.
   - Task 2: `MapboxHttp.tokenOverride`, the `NoRoute` fallback (two requests), HTTP 401 giving `Unavailable` with `TruckRoute.UNAVAILABLE`, and rounding with `setScale(1)`.
   - Task 1: `Truck_Route__c` with `Route_Key__c` unique and the place lookups `SetNull`, the object's `OwnerId` (Public Read Only), and `RFP_Tool_User` existing.

**Open issues**

- Resolved: `TripRouteView.fromResult` (Task 7) supplies `NO_ROUTE` for No route.
- The claim that `with sharing` blocks the refresh comes from how Apex sharing works, not from an org run. The runAs test is the proof, and it needs a usable profile in PostProduc (the phase 6 tests found one).

---

### Task 5: Search miles — load miles on every row, median miles and rate per mile in the statistics

**Files:**

- Modify: `force-app/main/default/classes/LaneSearchQueryBuilder.cls:13-18` (`SELECT_CLAUSE` gains `rtms__Load__r.rtms__Distance_Miles__c`)
- Confirm, no edit: `force-app/main/default/classes/LaneSearchResult.cls` (already in its phase 7 shape from Task 4; Step 3 only confirms)
- Modify: `force-app/main/default/classes/LaneSearchService.cls:60-91` (`collectRows`, new inner class `Bucket`, new `ratePerMileMedian`), `toRow` (`r.load.loadId = q.rtms__Load__c;` from Task 4 gains the miles line)
- Modify: `force-app/main/default/classes/PricingTestDataFactory.cls:228-236` (new public `createLoad(Graph, Account, Account, Decimal miles)` overload after the `Boolean hazmat` one), `:245`, `:255` (delegators pass `null`), `:282-291` (the private six-argument `createLoad` gains a seventh `Decimal miles` argument)
- Modify: `force-app/main/default/classes/LaneSearchServiceTest.cls:812-813` (three new test methods between the last method and the class's closing brace; lines 1-812, including `createLoadsAndQuotes` and `bidsMergeIntoRowsAndObeyTheSourceFilter`, stay byte-identical)

**Interfaces:**

- Consumes:
  - `TripMilesService.medianMiles(List<LaneSearchResult.Row> rows)` (Task 4) — median of `row.load.miles` over rows above zero (see Contract notes: the path is `load.miles`, not `miles`), scale 1, `null` when none.
  - `PricingTestDataFactory.createGraph`, `createLocation`, `buildQuote(Graph, rtms__Load__c, Decimal[, String])`, `RfpTestDataFactory.createProject/createLane/buildBid`, `BenchmarkRateService.save` (all exist).
  - `rtms__Load__c.rtms__Distance_Miles__c` (Revenova, Number(18,2), createable and updateable, not calculated — checked with `sf sobject describe -s rtms__Load__c -o sandbox`).
- Produces:
  - Filled here, declared by Task 4 (`LaneSearchResult.LoadDetail`, `Row.load`): load rows carry `load.loadId` and `load.miles` (the load's `rtms__Distance_Miles__c`); bid rows carry a `load` whose two fields are `null`.
  - `LaneSearchResult.medianMiles` (`@AuraEnabled public Decimal`) — `TripMilesService.medianMiles(result.rows)` over the deduped rows.
  - `LaneSearchResult.Stats.ratePerMileMedian` (`@AuraEnabled public Decimal`) — median of `carrierTotal / load.miles` over that currency's deduped rows with both above zero, `setScale(2)`, `null` when none.
  - `PricingTestDataFactory.createLoad(Graph g, Account origin, Account destination, Decimal miles)` — like the three-argument overload, with `rtms__Distance_Miles__c` set before the insert (no extra Load DML). Task 6 (`RfpHistoryServiceTest`) can use it for History miles.
  - `LaneBenchmarkController.search` returns the new fields with no change of its own; `RfpHistoryService` (Task 6) reads `result.medianMiles`.

- [ ] **Step 1: Write the failing tests**

In `force-app/main/default/classes/LaneSearchServiceTest.cls`, insert the three methods below between line 812 (the `  }` that closes `bidsMergeIntoRowsAndObeyTheSourceFilter`) and line 813 (the class's closing `}`). Leave lines 1-812 exactly as they are: `fixture`, `createLoadsAndQuotes` and the governor-sensitive `bidsMergeIntoRowsAndObeyTheSourceFilter` (whose setup stays outside `Test.startTest`) are not touched.

The first method copies `bidsMergeIntoRowsAndObeyTheSourceFilter`'s governor shape: the lane and its bid are saved before `Test.startTest`, and two `createLoad` calls plus one quote insert run inside it. The second creates two loads inside `Test.startTest`, the same budget as `createLoadsAndQuotes`, and checks that the miles set at insert are stored before it searches. The third makes no DML. All numbers divide exactly, so no assertion depends on `setScale` rounding.

```apex
  /**
   * Phase 7: a load row carries its load's billed miles and a bid row carries none, so the bid
   * never enters medianMiles or the rate per mile. Same shape as
   * bidsMergeIntoRowsAndObeyTheSourceFilter: the lane and its bid are saved before Test.startTest,
   * the two loads inside it.
   */
  @IsTest
  static void loadRowsCarryTheirMilesAndBidRowsDoNot() {
    Fixture f = fixture();
    Pricing_Place__c mtl = [
      SELECT Id, City__c, Province__c, Country__c, Postal_Prefix__c
      FROM Pricing_Place__c
      WHERE Key__c = 'montreal|qc|ca'
    ];
    Pricing_Place__c tor = [
      SELECT Id, City__c, Province__c, Country__c, Postal_Prefix__c
      FROM Pricing_Place__c
      WHERE Key__c = 'toronto|on|ca'
    ];
    RFP_Lane__c lane = RfpTestDataFactory.createLane(
      RfpTestDataFactory.createProject(f.g.customer),
      mtl,
      tor
    );
    BenchmarkRateService.save(RfpTestDataFactory.buildBid(lane, 1200));

    Test.startTest();
    f.mtlTor = PricingTestDataFactory.createLoad(
      f.g,
      f.g.originLocation,
      f.g.destinationLocation,
      250.0
    );
    f.lavalTor = PricingTestDataFactory.createLoad(
      f.g,
      f.laval,
      f.g.destinationLocation,
      500.0
    );
    insert new List<rtms__CarrierQuote__c>{
      PricingTestDataFactory.buildQuote(f.g, f.mtlTor, 1000),
      PricingTestDataFactory.buildQuote(f.g, f.lavalTor, 3000)
    };
    LaneSearchResult r = LaneSearchService.search(req(null, null));
    Test.stopTest();

    System.assertEquals(3, r.rows.size(), 'two quotes and the active bid');
    Map<Integer, LaneSearchResult.Row> byTotal = new Map<Integer, LaneSearchResult.Row>();
    for (LaneSearchResult.Row row : r.rows) {
      byTotal.put(row.carrierTotal.intValue(), row);
    }
    LaneSearchResult.Row bidRow = byTotal.get(1200);
    System.assertNotEquals(null, bidRow.bid, 'the 1200 row is the bid');
    System.assertNotEquals(null, bidRow.load, 'every row has a load group');
    System.assertEquals(null, bidRow.load.miles, 'a bid has no load miles');
    System.assertEquals(null, bidRow.load.loadId);
    System.assertEquals(250, byTotal.get(1000).load.miles);
    System.assertEquals(f.mtlTor.Id, byTotal.get(1000).load.loadId);
    System.assertEquals(500, byTotal.get(3000).load.miles);
    System.assertEquals(f.lavalTor.Id, byTotal.get(3000).load.loadId);
    System.assertEquals(
      375,
      r.medianMiles,
      'even count of rows with miles: the mean of 250 and 500; the bid is left out'
    );
    LaneSearchResult.Stats cad = r.statsByCurrency.get('CAD');
    System.assertEquals(
      3,
      cad.count,
      'the bid still counts in the price stats'
    );
    System.assertEquals(
      5,
      cad.ratePerMileMedian,
      '1000/250 = 4.00 and 3000/500 = 6.00; the bid has no miles'
    );
    System.assertEquals(2, cad.ratePerMileMedian.scale());
  }

  /**
   * Phase 7: medianMiles takes the middle row (odd count), a zero total keeps its row in the miles
   * median but not in the rate per mile, and each currency gets its own rate per mile.
   */
  @IsTest
  static void medianMilesAndRatePerMileSkipZeroTotalsAndSplitByCurrency() {
    Fixture f = fixture();
    Test.startTest();
    f.mtlTor = PricingTestDataFactory.createLoad(
      f.g,
      f.g.originLocation,
      f.g.destinationLocation,
      250.0
    );
    f.lavalTor = PricingTestDataFactory.createLoad(
      f.g,
      f.laval,
      f.g.destinationLocation,
      500.0
    );
    List<rtms__Load__c> stored = [
      SELECT rtms__Distance_Miles__c
      FROM rtms__Load__c
      WHERE Id IN :new List<Id>{ f.mtlTor.Id, f.lavalTor.Id }
      ORDER BY rtms__Distance_Miles__c
    ];
    System.assertEquals(
      250,
      stored[0].rtms__Distance_Miles__c,
      'the miles set at insert survive the load and stop automation'
    );
    System.assertEquals(500, stored[1].rtms__Distance_Miles__c);
    insert new List<rtms__CarrierQuote__c>{
      PricingTestDataFactory.buildQuote(f.g, f.mtlTor, 1000, 'CAD'),
      PricingTestDataFactory.buildQuote(f.g, f.mtlTor, 0, 'CAD'),
      PricingTestDataFactory.buildQuote(f.g, f.mtlTor, 500, 'USD'),
      PricingTestDataFactory.buildQuote(f.g, f.lavalTor, 3000, 'CAD'),
      PricingTestDataFactory.buildQuote(f.g, f.lavalTor, 1500, 'USD')
    };
    LaneSearchResult r = LaneSearchService.search(req(null, null));
    Test.stopTest();

    System.assertEquals(5, r.rows.size(), 'no two quotes share a fingerprint');
    System.assertEquals(
      250,
      r.medianMiles,
      'odd count: the middle of 250, 250, 250, 500, 500 (the zero total still has miles)'
    );
    LaneSearchResult.Stats cad = r.statsByCurrency.get('CAD');
    System.assertEquals(3, cad.count);
    System.assertEquals(2, cad.countNonZero);
    System.assertEquals(
      5,
      cad.ratePerMileMedian,
      '4.00 and 6.00; with the zero total it would be the middle of 0, 4 and 6'
    );
    System.assertEquals(
      2.5,
      r.statsByCurrency.get('USD').ratePerMileMedian,
      '500/250 = 2.00 and 1500/500 = 3.00, apart from the CAD rows'
    );
  }

  @IsTest
  static void ratePerMileMedianIsScaleTwoAndNullWhenEmpty() {
    Decimal odd = LaneSearchService.ratePerMileMedian(
      new List<Decimal>{ 3.5, 1.25, 2 }
    );
    System.assertEquals(2, odd, 'odd count: the middle rate');
    System.assertEquals(
      2,
      odd.scale(),
      'scale 2 even for a whole middle value'
    );
    System.assertEquals(
      5,
      LaneSearchService.ratePerMileMedian(new List<Decimal>{ 6, 4 }),
      'even count: the mean of the two middle rates'
    );
    System.assertEquals(
      null,
      LaneSearchService.ratePerMileMedian(new List<Decimal>()),
      'no rate, no median'
    );
  }
```

- [ ] **Step 2: Deploy the test alone to see it fail to compile**

Run:
`sf project deploy start -o sandbox --source-dir force-app/main/default/classes/LaneSearchServiceTest.cls -l NoTestRun --async --json | python3 -c "import json,sys; s=sys.stdin.read(); print(json.loads(s[s.index('{'):])['result']['id'])"`

Expected: a deploy job id (`0Af…`).

Run (poll; repeat while the status is `Pending` or `InProgress`, or when the command times out after its 2 minutes):
`sf project deploy report -o sandbox --job-id <job id from the previous command> -w 2 --json | python3 -c "import json,sys; s=sys.stdin.read(); r=json.loads(s[s.index('{'):]).get('result',{}); f=r.get('details',{}).get('componentFailures',[]); f=f if isinstance(f,list) else [f]; print(r.get('status'), [d.get('problem') for d in f][:3])"`

Expected: `Failed`, with `Method does not exist or incorrect signature: void createLoad(PricingTestDataFactory.Graph, Account, Account, Decimal) from the type PricingTestDataFactory` and `Method does not exist or incorrect signature: void ratePerMileMedian(List<Decimal>) from the type LaneSearchService`. The `load`, `medianMiles` and `ratePerMileMedian` fields already exist from Task 4. Nothing is saved to the org.

- [ ] **Step 3: Confirm `LaneSearchResult` is already in its phase 7 shape**

Run: `grep -c 'public LoadDetail load = new LoadDetail();\|public Decimal ratePerMileMedian;\|public Decimal medianMiles;' force-app/main/default/classes/LaneSearchResult.cls`

Expected: `3`. No edit: Task 4 Step 3 wrote the file (`LoadDetail`, `Row.load`, `Stats.ratePerMileMedian`, `medianMiles`). Any other number means Task 4 Step 3 was not applied: stop and report.

- [ ] **Step 4: `LaneSearchQueryBuilder.SELECT_CLAUSE` reads the load's miles**

In `force-app/main/default/classes/LaneSearchQueryBuilder.cls`, replace lines 13-18 (the `SELECT_CLAUSE` constant) with:

```apex
  private static final String SELECT_CLAUSE =
    'SELECT Id, Name, rtms__Load__c, Origin__c, Destination__c, Mode__c, Equipment_Type__c, ' +
    'rtms__Load__r.rtms__Equipment_Type__r.rtms__Category__c, rtms__Load__r.rtms__Distance_Miles__c, ' +
    'Carrier_Name__c, Carrier_Contact__c, ' +
    'CurrencyIsoCode, rtms__Carrier_Total__c, Quote_Date__c, Hazmat__c, rtms__Accepted__c, Load_Status__c, Ops_Comments__c, ' +
    'Contact_Email__c, Contact_Phone__c, Carrier_Risk__c, Nb_of_loads__c, Carrier_Att__c, ' +
    'CreatedDate FROM rtms__CarrierQuote__c';
```

- [ ] **Step 5: `LaneSearchService` — fill `load`, the rate per mile and `medianMiles`**

In `force-app/main/default/classes/LaneSearchService.cls`, replace lines 60-91 (the doc comment above `collectRows` and the whole `collectRows` method) with the block below. It ends with the new `ratePerMileMedian` method, so that method sits directly above the unchanged `stats` doc comment (old line 93).

```apex
  /**
   * Dedupes rows (a quote's fingerprint is carrier name, origin, destination, mode, equipment
   * and total, on rtms__Carrier_Total__c rather than the CAD-converted total so USD quotes
   * dedupe too; bid
   * rows never collapse - see BidSearchService.fingerprint) into result.rows/dedupedCount, and
   * rolls the surviving totals up into result.statsByCurrency. Phase 7: each currency's
   * ratePerMileMedian comes from the same surviving rows (Bucket.add), and result.medianMiles is
   * TripMilesService.medianMiles over result.rows, so a deduped quote never counts twice.
   */
  private static void collectRows(
    List<LaneSearchResult.Row> rows,
    LaneSearchResult result
  ) {
    Set<String> seen = new Set<String>();
    Map<String, Bucket> byCurrency = new Map<String, Bucket>();
    for (LaneSearchResult.Row r : rows) {
      String fingerprint = BidSearchService.fingerprint(r);
      if (seen.contains(fingerprint)) {
        result.dedupedCount++;
        continue;
      }
      seen.add(fingerprint);
      result.rows.add(r);
      String cur = r.currencyIsoCode == null ? 'CAD' : r.currencyIsoCode;
      if (!byCurrency.containsKey(cur)) {
        byCurrency.put(cur, new Bucket());
      }
      byCurrency.get(cur).add(r);
    }
    for (String cur : byCurrency.keySet()) {
      Bucket b = byCurrency.get(cur);
      LaneSearchResult.Stats s = stats(b.totals);
      s.ratePerMileMedian = ratePerMileMedian(b.rates);
      result.statsByCurrency.put(cur, s);
    }
    result.medianMiles = TripMilesService.medianMiles(result.rows);
  }

  /**
   * Phase 7: one currency's surviving rows. totals feeds stats() exactly as before (a blank total
   * counts as zero); rates holds carrierTotal / load.miles for the rows where both are above zero,
   * so bids (no miles) and zero totals never pull the rate per mile down. An inner class, so its
   * branches stay out of LaneSearchService's PMD class complexity total.
   */
  private class Bucket {
    List<Decimal> totals = new List<Decimal>();
    List<Decimal> rates = new List<Decimal>();

    void add(LaneSearchResult.Row r) {
      totals.add(r.carrierTotal == null ? 0 : r.carrierTotal);
      Decimal miles = r.load?.miles;
      if (
        r.carrierTotal != null &&
        r.carrierTotal > 0 &&
        miles != null &&
        miles > 0
      ) {
        rates.add(r.carrierTotal / miles);
      }
    }
  }

  /**
   * Phase 7: the median rate per mile at scale 2 whatever the count (odd: the middle rate; even:
   * the mean of the two middle rates); null when no row had both a total and miles above zero.
   */
  @TestVisible
  private static Decimal ratePerMileMedian(List<Decimal> rates) {
    if (rates.isEmpty()) {
      return null;
    }
    rates.sort();
    Integer n = rates.size();
    Decimal middle = Math.mod(n, 2) == 1
      ? rates[n / 2]
      : (rates[n / 2 - 1] + rates[n / 2]) / 2;
    return middle.setScale(2);
  }
```

In `toRow`, replace the line Task 4 wrote:

```apex
    r.load.loadId = q.rtms__Load__c;
```

with:

```apex
    r.load.loadId = q.rtms__Load__c;
    r.load.miles = q.rtms__Load__r?.rtms__Distance_Miles__c;
```

`BidSearchService.toRow` needs no change: `new LaneSearchResult.Row()` initializes `load`, and a bid never sets its fields.

- [ ] **Step 6: `PricingTestDataFactory` — a load with miles, set at insert**

In `force-app/main/default/classes/PricingTestDataFactory.cls`, replace lines 228-236 (the doc comment and body of the `Boolean hazmat` overload) with the block below, which adds the new `Decimal miles` overload right after it:

```apex
  /** Sets rtms__Hazardous_Materials__c at insert; the 3-argument overload delegates here with false. */
  public static rtms__Load__c createLoad(
    Graph g,
    Account origin,
    Account destination,
    Boolean hazmat
  ) {
    return createLoad(g, origin, destination, hazmat, g.customer, g.mode, null);
  }

  /**
   * Phase 7: sets Revenova's billed miles (rtms__Distance_Miles__c) at insert, so the load's quote
   * rows carry load.miles in a lane search without a second Load DML (the extra DML would trip the
   * governor budget described in the class doc).
   */
  public static rtms__Load__c createLoad(
    Graph g,
    Account origin,
    Account destination,
    Decimal miles
  ) {
    return createLoad(g, origin, destination, false, g.customer, g.mode, miles);
  }
```

Replace old line 245 (`Account customer` overload body):

```apex
    return createLoad(g, origin, destination, false, customer, g.mode, null);
```

Replace old line 255 (`rtms__Mode__c mode` overload body):

```apex
    return createLoad(g, origin, destination, false, g.customer, mode, null);
```

Replace old lines 282-291 (the signature and first two statements of the private `createLoad`) with:

```apex
  private static rtms__Load__c createLoad(
    Graph g,
    Account origin,
    Account destination,
    Boolean hazmat,
    Account customer,
    rtms__Mode__c mode,
    Decimal miles
  ) {
    rtms__Load__c load = newLoad(g, customer, mode, hazmat);
    load.rtms__Distance_Miles__c = miles;
    applyLaneKeys(load, origin, destination);
```

The rest of the private method (from `String expectedCityLane = load.rtms__City_Lane__c;`) is unchanged.

- [ ] **Step 7: Deploy the five classes and run the search tests**

Prerequisite: Task 4 is deployed (`TripMilesService` exists in the org; see Contract notes 2).

Run:
`sf project deploy start -o sandbox --source-dir force-app/main/default/classes/LaneSearchResult.cls --source-dir force-app/main/default/classes/LaneSearchQueryBuilder.cls --source-dir force-app/main/default/classes/LaneSearchService.cls --source-dir force-app/main/default/classes/PricingTestDataFactory.cls --source-dir force-app/main/default/classes/LaneSearchServiceTest.cls -l RunSpecifiedTests -t LaneSearchServiceTest -t BidSearchServiceTest -t LaneBenchmarkControllerTest -t RfpHistoryServiceTest -t PricingTestDataFactoryTest --async --json | python3 -c "import json,sys; s=sys.stdin.read(); print(json.loads(s[s.index('{'):])['result']['id'])"`

Expected: a deploy job id (`0Af…`).

Run (poll; repeat while the status is `Pending` or `InProgress`, or when the command times out after its 2 minutes):
`sf project deploy report -o sandbox --job-id <job id from the previous command> -w 2 --json | python3 -c "import json,sys; s=sys.stdin.read(); r=json.loads(s[s.index('{'):]).get('result',{}); d=r.get('details',{}); print(r.get('id'), r.get('status'), 'tests', r.get('numberTestsCompleted'), '/', r.get('numberTestsTotal'), 'failures', r.get('numberTestErrors')); f=d.get('runTestResult',{}).get('failures',[]); f=f if isinstance(f,list) else [f]; [print(x.get('name'), x.get('methodName'), '->', str(x.get('message'))[:160]) for x in f]; c=d.get('componentFailures',[]); c=c if isinstance(c,list) else [c]; [print(x.get('fullName'), '->', x.get('problem')) for x in c]"`

Expected: `Succeeded tests 47 / 47 failures 0`, with no failure lines: `LaneSearchServiceTest` 22 (19 + 3), `BidSearchServiceTest` 4, `LaneBenchmarkControllerTest` 6, `RfpHistoryServiceTest` 12, `PricingTestDataFactoryTest` 3. These tests cover `LaneSearchService` and `LaneSearchQueryBuilder` above the org's 75 % per-class gate, and they run every existing caller of `LaneSearchService.search` and `PricingTestDataFactory.createLoad`. Record the job id.

If a test fails, fix the code, not the assertion, unless the assertion contradicts the spec. One known unverified point: if `medianMilesAndRatePerMileSkipZeroTotalsAndSplitByCurrency` fails on `the miles set at insert survive the load and stop automation`, Revenova's automation reset `rtms__Distance_Miles__c` after the insert. In the private `createLoad` of `PricingTestDataFactory.cls`, replace its last statement (`return backfillFirstLastStopAndLaneKeys(load, pickup, delivery, expectedCityLane, expectedStateLane, expectedZip3Lane);`) with:

```apex
    rtms__Load__c saved = backfillFirstLastStopAndLaneKeys(
      load,
      pickup,
      delivery,
      expectedCityLane,
      expectedStateLane,
      expectedZip3Lane
    );
    if (miles != null) {
      // Revenova's load/stop automation resets the billed miles written at insert; write them back.
      saved.rtms__Distance_Miles__c = miles;
      update saved;
    }
    return saved;
```

Then re-run this step. This adds one Load update, and only for loads created with miles. If that update then exceeds 100 SOQL queries in `loadRowsCarryTheirMilesAndBidRowsDoNot`, stop and report it with the failure message. Do not move `bidsMergeIntoRowsAndObeyTheSourceFilter`'s setup or change any existing test.

- [ ] **Step 8: PMD and Prettier**

Run: `/private/tmp/pmd_install/pmd-bin-7.15.0/bin/pmd check --dir force-app --rulesets config/pmd-ruleset.xml --minimum-priority 3 --format text --fail-on-violation; echo "pmd exit $?"`

Expected: no violation lines, `pmd exit 0`. The same PMD run on scratch copies of the Step 3-6 code passed. `LaneSearchResult.Row` stays at 20 fields, and `LaneSearchService` totals 28 against the class budget of 40, with `Bucket.add` (6) counted on the inner class. If `TooManyFields` is reported on `LaneSearchResult.cls:7`, a field was added to Row instead of replacing `loadId`: undo that. Do not suppress the rule.

Run: `npx prettier --check force-app/main/default/classes/LaneSearchResult.cls force-app/main/default/classes/LaneSearchQueryBuilder.cls force-app/main/default/classes/LaneSearchService.cls force-app/main/default/classes/PricingTestDataFactory.cls force-app/main/default/classes/LaneSearchServiceTest.cls`

Expected: `All matched files use Prettier code style!` (lint-staged also formats on commit).

- [ ] **Step 9: Commit**

```bash
git add force-app/main/default/classes/LaneSearchResult.cls force-app/main/default/classes/LaneSearchQueryBuilder.cls force-app/main/default/classes/LaneSearchService.cls force-app/main/default/classes/PricingTestDataFactory.cls force-app/main/default/classes/LaneSearchServiceTest.cls
git commit -m "Carry load miles, median miles and rate per mile in lane search results"
```

Expected: lint-staged runs Prettier on the five files and the commit succeeds. `git status --short` still lists `.vscode/settings.json` and the `* 2.*` files as uncommitted, which is correct: they are never staged.

#### Contract notes (Task 5)

1. **`Row.miles` is `Row.load.miles`.** `LaneSearchResult.Row` already has exactly 20 fields (18 values plus `carrier` and `bid`). A PMD run on a scratch copy of `LaneSearchResult.cls` with one more field reported `LaneSearchResult.cls:7: TooManyFields: Too many fields` (maxfields 20 in the quickstart ruleset), and earlier plans say "split, never suppress". A new field pointing at a group would also be a 21st field. So `loadId`, which nothing reads outside `LaneSearchService.toRow` (checked with grep across `force-app`, the LWC `__tests__` included), moves into the new group `LaneSearchResult.LoadDetail { Id loadId; Decimal miles; }`, and Row gains `load` in its place. Row stays at 20. `load` is initialized like `carrier`, so bid rows carry a `load` whose `loadId` and `miles` are both `null`. Every later task uses this path:
   - Task 4, `TripMilesService.medianMiles`: reads `row.load.miles` and skips a row whose `load` is `null`. A Row built by `JSON.deserialize` skips field initializers, so `load` can be `null`. Task 4's tests build rows with `LaneSearchResult.Row r = new LaneSearchResult.Row(); r.load.miles = 250;`.
   - Task 10, `laneBenchmarkResults`: the Miles column reads `load.miles`, and the CSV column is `{ label: "Miles", field: "load.miles" }`. `laneBenchmarkCsv.valueAt` already follows dotted paths, as `carrier.contactEmail` does. Jest row fixtures use `load: { miles: 1234 }`.
   - Tasks 6, 7 and 9 and `laneBenchmarkStats` are unaffected: they read `result.medianMiles`, `Stats.ratePerMileMedian` or `RFP_Lane__c` fields.
2. **Order of Tasks 4 and 5.** Applied: Task 4 carries the phase 7 `LaneSearchResult.cls` and the `toRow` line `r.load.loadId = q.rtms__Load__c;`, and deploys and commits both files; this task confirms the file (Step 3) and adds the miles line to `toRow` (Step 5). Step 9 still stages `LaneSearchResult.cls`; git skips it when it is unchanged.
3. **`PricingTestDataFactory` is modified** (not in the contract's Task 5 list). Test loads need `rtms__Distance_Miles__c`, and the factory's class doc forbids a post-insert Load update because it breaks the governor budget. So the value is set at insert through a new public overload, `createLoad(Graph, Account, Account, Decimal miles)`. The private six-argument `createLoad` gains a seventh argument, and the three existing public overloads pass `null`, so their behaviour is unchanged. No caller passes `null` as a fourth argument (checked with `grep -rn "createLoad(.*null" force-app/main/default/classes` and a multi-line grep, no match), so the new overload creates no ambiguity. Task 6 can use this overload for History miles in `RfpHistoryServiceTest`.
4. **The rate per mile is computed in `LaneSearchService`, not in `TripMilesService`.** A private inner class `Bucket` holds each currency's totals and rates, and a `@TestVisible private static Decimal ratePerMileMedian(List<Decimal>)` returns the median at scale 2. PMD on the scratch copy: class total 28 (it was 26), `collectRows` 6, `Bucket.add` 6 (counted on the inner class), `ratePerMileMedian` 3; `pmd exit 0`. `stats()` is unchanged, so the existing median rule and its scale stay as they are.
5. **No permission-set change.** The quote query runs in `AccessLevel.SYSTEM_MODE`, and the LWC receives a DTO. `Lane_Benchmark_User` lists no `rtms__Load__c` field permissions today.
6. **`rtms__Distance_Miles__c`** is a managed Revenova Number(18,2), createable and not calculated (`sf sobject describe`). Nobody has checked whether Revenova's load or stop automation changes the value set at insert. `medianMilesAndRatePerMileSkipZeroTotalsAndSplitByCurrency` checks the stored value before it searches, and Step 7 gives the factory fallback if the value does not survive.

---

### Task 6: History miles — Load history fills every lane's miles without a callout

**Files:**

- Modify: `force-app/main/default/classes/RfpLaneController.cls:3-10` (`LANE_FIELDS` gains the three lane miles fields and the two places' coordinates)
- Modify: `force-app/main/default/classes/RfpHistoryService.cls:1` (class comment), `:8-34` (`run` builds one `TripMiles` per call), `:98-148` (`snapshot` hands the search actually used to `TripMiles.apply`), append a private inner class `TripMiles` after `fill` (after line 219)
- Modify: `force-app/main/default/classes/RfpHistoryServiceTest.cls` — `NoRouteCallMock` right after the class declaration (line 2); six tests after `countsAnExpiredBidInsideTheLookback` (after line 488); `:490-531` (`Fixture` keeps its two places); two helpers after `addLoads` (before the `restrictedUser` comment, line 550)
- No permission-set change: `RFP_Tool_User` already grants read on `Pricing_Place__c` (`RFP_Tool_User.permissionset-meta.xml:116`) and on `Pricing_Place__c.Geolocation__c` (`:578-582`), which is what a user-mode read of `Origin_Place__r.Geolocation__Latitude__s` / `__Longitude__s` needs; the lane miles fields' read and edit come from Task 1.

**Interfaces:**

- Consumes:
  - `RFP_Lane__c.Miles__c`, `Miles_Source__c`, `Route_Hours__c`; `Truck_Route__c` and its fields `Origin_Place__c`, `Destination_Place__c`, `Profile_Key__c`, `Route_Key__c`, `Miles__c`, `Hours__c`, `Route_Type__c`, `Status__c`, `Routes_Json__c`, `Checked_On__c`; the `Truck_Routing_Setting__mdt` record `Default` (Task 1).
  - `TruckRoute.Profile` (`heightM`, `widthM`, `weightT`, `key()`), `TruckRoute.defaultProfile()`; `MapboxHttp.tokenOverride` (tests only) (Task 2).
  - `TripMilesService.routeKey(Id, Id, TruckRoute.Profile)`, `TripMilesService.storedRoutes(Set<String>)`, `TripMilesService.approxMiles(Pricing_Place__c, Pricing_Place__c, TruckRoute.Profile)` (Task 4).
  - `LaneSearchResult.medianMiles`, filled by `LaneSearchService.collectRows` from the rows' load miles (`rtms__Load__r.rtms__Distance_Miles__c` in `LaneSearchQueryBuilder.SELECT_CLAUSE`) (Task 5).
  - `PricingTestDataFactory.createLoad(Graph g, Account origin, Account destination, Decimal miles)` — `rtms__Distance_Miles__c` set before the insert (Task 5).
  - Existing: `RfpTestDataFactory.createPlace/createProject/createLane`, `PricingTestDataFactory.createGraph/createLoad/buildQuote`, `LaneSearchExclusions.excludedContactIdsOverride`.
- Produces:
  - `RfpLaneController.LANE_FIELDS` (private) now also selects `Miles__c, Miles_Source__c, Route_Hours__c, Origin_Place__r.Geolocation__Latitude__s, Origin_Place__r.Geolocation__Longitude__s, Destination_Place__r.Geolocation__Latitude__s, Destination_Place__r.Geolocation__Longitude__s`, so `getLanes`, `lanesByIds` and the private `one` return them (Task 7's `laneRoute` and Task 9's table and panel read them).
  - `RfpHistoryService.run(List<Id>, String, Integer, Decimal, String, Boolean)` — signature unchanged; every lane it snapshots now carries `Miles__c`, `Miles_Source__c` and `Route_Hours__c`, in this order: `History` (the median load miles of the search actually used, CITY or its RADIUS fallback) > a stored `Truck_Route__c` for the lane's ordered place pair and `TruckRoute.defaultProfile()` (`Found` → `Truck route` or `Regular route` with its hours; `No route` → `No route`, miles blank) > `Approx` > `No coordinates`. One `TripMilesService.storedRoutes` call per `run`, no callout, still one user-mode update per chunk.

- [ ] **Step 1: Write the failing tests**

All edits are in `force-app/main/default/classes/RfpHistoryServiceTest.cls`. The class compiles as soon as Tasks 1, 2, 4 and 5 are in the org (`Truck_Route__c`, `TruckRoute`, `MapboxHttp.tokenOverride`, `TripMilesService`, the `createLoad(..., Decimal miles)` overload), so these tests fail on their assertions, not on compilation, once Step 2 has widened the lane field list.

(a) Right after line 2 (`private class RfpHistoryServiceTest {`), insert the mock. It keeps its counter on the instance, like `MapboxGeocoderTest.Mock` (an Apex inner class cannot hold a static), and never puts the endpoint in its message, because the endpoint carries the token:

```apex
  /**
   * Phase 7, ruling R73: Load history never asks Mapbox for a route. The tests set a token
   * (MapboxHttp.tokenOverride), so a stray route request would really reach this mock, and its
   * AssertException - which no catch block in the service can swallow - fails the test right there.
   */
  private class NoRouteCallMock implements HttpCalloutMock {
    Integer calls = 0;
    public HttpResponse respond(HttpRequest req) {
      calls++;
      System.assert(false, 'Load history must not call Mapbox');
      return null;
    }
  }

```

(b) Right after `countsAnExpiredBidInsideTheLookback` (its closing brace is line 488), before `private class Fixture {`, insert the six tests:

```apex
  // Phase 7. The six tests below cover the trip miles a run writes on each lane: History, a stored
  // Truck or Regular route, a stored No route, Approx and No coordinates - never with a callout.

  // Rulings R70 and R75: billed PC*Miler miles are what the company invoices on, so the history
  // median wins even when a truck route is already stored for the pair, and the hours that route
  // left on the lane are cleared.
  @IsTest
  static void historyMilesOutrankAStoredTruckRoute() {
    Fixture f = fixture();
    storedRoute(
      f.mtl,
      f.tor,
      TruckRoute.defaultProfile(),
      'Found',
      'Truck',
      336.4,
      4.1
    );
    update new RFP_Lane__c(
      Id = f.lane.Id,
      Miles__c = 336.4,
      Miles_Source__c = 'Truck route',
      Route_Hours__c = 4.1
    );
    NoRouteCallMock mock = new NoRouteCallMock();
    Test.setMock(HttpCalloutMock.class, mock);
    MapboxHttp.tokenOverride = 'pk.test';
    Test.startTest();
    addLoadWithMiles(f.g, 347.5, 1000, 3000);
    List<RFP_Lane__c> out = RfpHistoryService.run(
      new List<Id>{ f.lane.Id },
      'CITY',
      90,
      null,
      null,
      true
    );
    Integer callouts = Limits.getCallouts();
    Test.stopTest();
    System.assertEquals(0, callouts, 'Load history makes no callout');
    System.assertEquals(0, mock.calls);
    System.assertEquals('Done', out[0].Hist_Status__c);
    System.assertEquals(2, out[0].Hist_Count__c);
    System.assertEquals(
      347.5,
      out[0].Miles__c,
      'the median billed miles of the matched loads'
    );
    System.assertEquals('History', out[0].Miles_Source__c);
    System.assertEquals(
      null,
      out[0].Route_Hours__c,
      'the stored route\'s hours are cleared'
    );
  }

  // Ruling R70: the miles come from the search the run actually used. Laval -> Toronto finds
  // nothing at CITY precision and falls back to RADIUS, where the Montréal -> Toronto load matches.
  @IsTest
  static void historyMilesComeFromTheRadiusFallback() {
    PricingTestDataFactory.Graph g = PricingTestDataFactory.createGraph();
    Pricing_Place__c laval = RfpTestDataFactory.createPlace(
      'Laval',
      'QC',
      'CA',
      45.6066,
      -73.7124,
      'H7P'
    );
    Pricing_Place__c tor = RfpTestDataFactory.createPlace(
      'Toronto',
      'ON',
      'CA',
      43.6532,
      -79.3832,
      'M5V'
    );
    LaneSearchExclusions.excludedContactIdsOverride = new Set<String>();
    RFP_Lane__c nearby = RfpTestDataFactory.createLane(
      RfpTestDataFactory.createProject(g.customer),
      laval,
      tor
    );
    NoRouteCallMock mock = new NoRouteCallMock();
    Test.setMock(HttpCalloutMock.class, mock);
    MapboxHttp.tokenOverride = 'pk.test';
    Test.startTest();
    addLoadWithMiles(g, 351.0, 1000, 3000);
    List<RFP_Lane__c> out = RfpHistoryService.run(
      new List<Id>{ nearby.Id },
      'CITY',
      90,
      120,
      'KM',
      true
    );
    Integer callouts = Limits.getCallouts();
    Test.stopTest();
    System.assertEquals(0, callouts);
    System.assertEquals(0, mock.calls);
    System.assertEquals('RADIUS-120KM', out[0].Hist_Precision__c);
    System.assertEquals('Done', out[0].Hist_Status__c);
    System.assertEquals(351.0, out[0].Miles__c);
    System.assertEquals('History', out[0].Miles_Source__c);
    System.assertEquals(null, out[0].Route_Hours__c);
  }

  // Spec D4: with no billed miles, a lane takes the route stored for its ordered place pair and the
  // current truck - its miles, its hours, and whether Mapbox had to fall back to a regular route.
  // Direction matters (R71): Montréal -> Toronto and Toronto -> Montréal are two rows.
  @IsTest
  static void storedTruckAndRegularRoutesFillLanesWithoutHistory() {
    Fixture f = fixture();
    RFP_Lane__c back = RfpTestDataFactory.createLane(
      RfpTestDataFactory.createProject(f.g.customer),
      f.tor,
      f.mtl
    );
    storedRoute(
      f.mtl,
      f.tor,
      TruckRoute.defaultProfile(),
      'Found',
      'Truck',
      336.4,
      4.1
    );
    storedRoute(
      f.tor,
      f.mtl,
      TruckRoute.defaultProfile(),
      'Found',
      'Regular',
      339.8,
      4.3
    );
    NoRouteCallMock mock = new NoRouteCallMock();
    Test.setMock(HttpCalloutMock.class, mock);
    MapboxHttp.tokenOverride = 'pk.test';
    Test.startTest();
    List<RFP_Lane__c> out = RfpHistoryService.run(
      new List<Id>{ f.lane.Id, back.Id },
      'CITY',
      90,
      null,
      null,
      true
    );
    Integer callouts = Limits.getCallouts();
    Test.stopTest();
    System.assertEquals(0, callouts, 'a stored route is read, never requested');
    System.assertEquals(0, mock.calls);
    Map<Id, RFP_Lane__c> byId = new Map<Id, RFP_Lane__c>(out);
    RFP_Lane__c there = byId.get(f.lane.Id);
    System.assertEquals(
      'No match',
      there.Hist_Status__c,
      'no loads, so no history miles'
    );
    System.assertEquals(336.4, there.Miles__c);
    System.assertEquals('Truck route', there.Miles_Source__c);
    System.assertEquals(4.1, there.Route_Hours__c);
    RFP_Lane__c home = byId.get(back.Id);
    System.assertEquals(339.8, home.Miles__c);
    System.assertEquals('Regular route', home.Miles_Source__c);
    System.assertEquals(4.3, home.Route_Hours__c);
  }

  // Spec section 7: Mapbox found no road even without truck limits (across water, say). The stored
  // answer is kept - no Approx miles for a trip no road makes - and the miles of an earlier run go.
  @IsTest
  static void aStoredNoRouteLeavesTheMilesBlank() {
    Fixture f = fixture();
    storedRoute(
      f.mtl,
      f.tor,
      TruckRoute.defaultProfile(),
      'No route',
      null,
      null,
      null
    );
    update new RFP_Lane__c(
      Id = f.lane.Id,
      Miles__c = 376.0,
      Miles_Source__c = 'Approx'
    );
    NoRouteCallMock mock = new NoRouteCallMock();
    Test.setMock(HttpCalloutMock.class, mock);
    MapboxHttp.tokenOverride = 'pk.test';
    Test.startTest();
    List<RFP_Lane__c> out = RfpHistoryService.run(
      new List<Id>{ f.lane.Id },
      'CITY',
      90,
      null,
      null,
      true
    );
    Integer callouts = Limits.getCallouts();
    Test.stopTest();
    System.assertEquals(0, callouts);
    System.assertEquals(0, mock.calls);
    System.assertEquals('No route', out[0].Miles_Source__c);
    System.assertEquals(
      null,
      out[0].Miles__c,
      'the Approx miles of an earlier run are cleared'
    );
    System.assertEquals(null, out[0].Route_Hours__c);
  }

  // Spec D1 and D7: no billed miles and no stored route for this direction and this truck, so the
  // straight line x 1.2. Montréal (45.5019, -73.5674) -> Toronto (43.6532, -79.3832) is 313.335 mi
  // on a 3,958.7613 mi sphere; x 1.2 = 376.002, one decimal 376.0. The reverse direction's route
  // and a route stored for a lower truck (3.5 m) must not be used (R71).
  @IsTest
  static void approxMilesWhenNoRouteIsStoredForThisTruckAndDirection() {
    Fixture f = fixture();
    storedRoute(
      f.tor,
      f.mtl,
      TruckRoute.defaultProfile(),
      'Found',
      'Truck',
      339.8,
      4.3
    );
    TruckRoute.Profile lowTruck = new TruckRoute.Profile();
    lowTruck.heightM = 3.5;
    lowTruck.widthM = 2.6;
    lowTruck.weightT = 36.29;
    storedRoute(f.mtl, f.tor, lowTruck, 'Found', 'Truck', 341.2, 4.4);
    NoRouteCallMock mock = new NoRouteCallMock();
    Test.setMock(HttpCalloutMock.class, mock);
    MapboxHttp.tokenOverride = 'pk.test';
    Test.startTest();
    List<RFP_Lane__c> out = RfpHistoryService.run(
      new List<Id>{ f.lane.Id },
      'CITY',
      90,
      null,
      null,
      true
    );
    Integer callouts = Limits.getCallouts();
    Test.stopTest();
    System.assertEquals(0, callouts);
    System.assertEquals(0, mock.calls);
    System.assertEquals('Approx', out[0].Miles_Source__c);
    System.assertEquals(376.0, out[0].Miles__c);
    System.assertEquals(
      TripMilesService.approxMiles(f.mtl, f.tor, TruckRoute.defaultProfile()),
      out[0].Miles__c,
      'the same number Lane Benchmark and the lane panel compute'
    );
    System.assertEquals(null, out[0].Route_Hours__c);
  }

  // A place without coordinates gives no Approx miles. An unresolved lane (a place missing) gets
  // the same answer instead of keeping miles from an earlier run (phase 7 plan, Task 6 notes).
  @IsTest
  static void lanesWithoutCoordinatesOrAPlaceGetNoCoordinates() {
    PricingTestDataFactory.Graph g = PricingTestDataFactory.createGraph();
    Pricing_Place__c nowhere = RfpTestDataFactory.createPlace(
      'Nowhere',
      'ZZ',
      'CA',
      null,
      null,
      'Z9Z'
    );
    Pricing_Place__c mtl = RfpTestDataFactory.createPlace(
      'Montréal',
      'QC',
      'CA',
      45.5019,
      -73.5674,
      'H1A'
    );
    Pricing_Place__c tor = RfpTestDataFactory.createPlace(
      'Toronto',
      'ON',
      'CA',
      43.6532,
      -79.3832,
      'M5V'
    );
    LaneSearchExclusions.excludedContactIdsOverride = new Set<String>();
    RFP_Project__c p = RfpTestDataFactory.createProject(g.customer);
    RFP_Lane__c noCoords = RfpTestDataFactory.createLane(p, nowhere, tor);
    RFP_Lane__c unresolved = RfpTestDataFactory.createLane(p, mtl, tor);
    unresolved.Destination_Place__c = null;
    unresolved.Destination_Resolved__c = false;
    unresolved.Miles__c = 376.0;
    unresolved.Miles_Source__c = 'Approx';
    update unresolved;
    NoRouteCallMock mock = new NoRouteCallMock();
    Test.setMock(HttpCalloutMock.class, mock);
    MapboxHttp.tokenOverride = 'pk.test';
    Test.startTest();
    List<RFP_Lane__c> out = RfpHistoryService.run(
      new List<Id>{ noCoords.Id, unresolved.Id },
      'CITY',
      90,
      null,
      null,
      true
    );
    Integer callouts = Limits.getCallouts();
    Test.stopTest();
    System.assertEquals(0, callouts);
    System.assertEquals(0, mock.calls);
    Map<Id, RFP_Lane__c> byId = new Map<Id, RFP_Lane__c>(out);
    System.assertEquals(
      'No match',
      byId.get(noCoords.Id).Hist_Status__c,
      'the radius fallback threw: no coordinates'
    );
    System.assertEquals(null, byId.get(noCoords.Id).Miles__c);
    System.assertEquals(
      'No coordinates',
      byId.get(noCoords.Id).Miles_Source__c
    );
    System.assertEquals('Unresolved', byId.get(unresolved.Id).Hist_Status__c);
    System.assertEquals(
      null,
      byId.get(unresolved.Id).Miles__c,
      'an unresolved lane keeps no miles from an earlier run'
    );
    System.assertEquals(
      'No coordinates',
      byId.get(unresolved.Id).Miles_Source__c
    );
    System.assertEquals(null, byId.get(unresolved.Id).Route_Hours__c);
  }

```

(c) Replace `Fixture` and `fixture()` (original lines 490-531) with this version, which keeps the two places on the fixture. The four phase 3d tests that already use it are unaffected:

```apex
  private class Fixture {
    PricingTestDataFactory.Graph g;
    Pricing_Place__c mtl;
    Pricing_Place__c tor;
    RFP_Lane__c lane;
    RFP_Lane__c otherLane;
  }

  /**
   * Montréal -> Toronto twice: once on the project a run prices, once on a second project whose
   * bids are the "another RFP" evidence phase 3d counts. The two places stay on the fixture for
   * the phase 7 trip-miles tests (route keys and Approx miles).
   */
  private static Fixture fixture() {
    Fixture f = new Fixture();
    f.g = PricingTestDataFactory.createGraph();
    f.mtl = RfpTestDataFactory.createPlace(
      'Montréal',
      'QC',
      'CA',
      45.5019,
      -73.5674,
      'H1A'
    );
    f.tor = RfpTestDataFactory.createPlace(
      'Toronto',
      'ON',
      'CA',
      43.6532,
      -79.3832,
      'M5V'
    );
    LaneSearchExclusions.excludedContactIdsOverride = new Set<String>();
    f.lane = RfpTestDataFactory.createLane(
      RfpTestDataFactory.createProject(f.g.customer),
      f.mtl,
      f.tor
    );
    f.otherLane = RfpTestDataFactory.createLane(
      RfpTestDataFactory.createProject(f.g.customer),
      f.mtl,
      f.tor
    );
    return f;
  }
```

(d) Right after `addLoads` (it ends at original line 548), before the `/** Same shape as RfpSecurityTest.restrictedUser` comment, insert the two helpers:

```apex
  /**
   * addLoads with the load's billed miles (rtms__Distance_Miles__c, which PC*Miler fills in
   * production), through Task 5's createLoad overload that sets them before the insert. Revenova's
   * managed rtms__LoadUpsert trigger runs on every load save (ApexTrigger query, PostProduc,
   * 2026-09-14), so the miles are read back: a failure on that assertion means the trigger rewrote
   * them, not that the history run is wrong.
   */
  private static void addLoadWithMiles(
    PricingTestDataFactory.Graph g,
    Decimal miles,
    Decimal low,
    Decimal high
  ) {
    rtms__Load__c load = PricingTestDataFactory.createLoad(
      g,
      g.originLocation,
      g.destinationLocation,
      miles
    );
    System.assertEquals(
      miles,
      [SELECT rtms__Distance_Miles__c FROM rtms__Load__c WHERE Id = :load.Id]
      .rtms__Distance_Miles__c,
      'the load keeps its billed miles'
    );
    insert new List<rtms__CarrierQuote__c>{
      PricingTestDataFactory.buildQuote(g, load, low),
      PricingTestDataFactory.buildQuote(g, load, high)
    };
  }

  /**
   * A Truck_Route__c row the way TripMilesService.save stores one: both places set (storedRoutes
   * ignores a row with a blank place) and the key from TripMilesService.routeKey, never built by
   * hand. The polyline is a two-point placeholder; a history run never draws it.
   */
  private static void storedRoute(
    Pricing_Place__c origin,
    Pricing_Place__c destination,
    TruckRoute.Profile profile,
    String status,
    String routeType,
    Decimal miles,
    Decimal hours
  ) {
    List<Map<String, Object>> routes = new List<Map<String, Object>>();
    if (miles != null) {
      routes.add(
        new Map<String, Object>{
          'miles' => miles,
          'hours' => hours,
          'polyline5' => '{avtGfs_`MjahJv{nb@'
        }
      );
    }
    insert new Truck_Route__c(
      Origin_Place__c = origin.Id,
      Destination_Place__c = destination.Id,
      Profile_Key__c = profile.key(),
      Route_Key__c = TripMilesService.routeKey(
        origin.Id,
        destination.Id,
        profile
      ),
      Status__c = status,
      Route_Type__c = routeType,
      Miles__c = miles,
      Hours__c = hours,
      Routes_Json__c = JSON.serialize(routes),
      Checked_On__c = Datetime.now()
    );
  }

```

- [ ] **Step 2: `RfpLaneController.LANE_FIELDS` — the lane's miles and its places' coordinates**

In `force-app/main/default/classes/RfpLaneController.cls`, replace lines 3-10 (the `LANE_FIELDS` constant) with:

```apex
  private static final String LANE_FIELDS =
    'Id, Name, RFP_Project__c, Row_Number__c, Origin_City__c, Origin_Province__c, Origin_Country__c, Origin_Postal__c, ' +
    'Origin_Place__c, Origin_Place__r.Key__c, Origin_Resolved__c, Destination_City__c, Destination_Province__c, ' +
    'Destination_Country__c, Destination_Postal__c, Destination_Place__c, Destination_Place__r.Key__c, Destination_Resolved__c, ' +
    'Mode__c, Equipment_Category__c, Equipment_Type__c, Commodity__c, Quantity__c, Quantity_Unit__c, Shipments_Per_Year__c, ' +
    'Hazmat__c, Customer_Fuel_Surcharge__c, Customer_FSC_Included__c, Hist_Count__c, Hist_Bid_Count__c, Hist_Min__c, Hist_Median__c, ' +
    'Hist_Average__c, Hist_Max__c, Hist_Precision__c, Hist_Lookback_Days__c, Hist_As_Of__c, Hist_Status__c, Cost__c, ' +
    'Cost_Source__c, Selected_Bid__c, Selected_Bid__r.Carrier_Display__c, Margin__c, Sell__c, Sell_Source__c, Notes__c, CurrencyIsoCode, ' +
    'Miles__c, Miles_Source__c, Route_Hours__c, Origin_Place__r.Geolocation__Latitude__s, Origin_Place__r.Geolocation__Longitude__s, ' +
    'Destination_Place__r.Geolocation__Latitude__s, Destination_Place__r.Geolocation__Longitude__s';
```

The run reads `Miles_Source__c` through `lanesByIds` like every other lane field, and `TripMiles.approx` hands `Origin_Place__r` / `Destination_Place__r` to `TripMilesService.approxMiles`, which reads their `Geolocation__Latitude__s` / `Geolocation__Longitude__s`. The query stays `AccessLevel.USER_MODE`; `RFP_Tool_User` already reads `Pricing_Place__c` and `Pricing_Place__c.Geolocation__c` (permission set lines 116 and 578-582), so no permission-set change. `rfpTool.js` posts only `{ Id, ...whitelisted pricing fields }` to `saveLanePricing` (`rfpTool.js:471-473`, whitelist in `rfpPricing.js:115`), so the nested place coordinates never travel back to Apex.

Nothing is deployed yet: Step 3 deploys this file together with the tests.

- [ ] **Step 3: Deploy the tests with the widened field list and watch the six new tests fail**

Run: `sf project deploy start -o sandbox --source-dir force-app/main/default/classes/RfpHistoryServiceTest.cls --source-dir force-app/main/default/classes/RfpLaneController.cls -l RunSpecifiedTests -t RfpHistoryServiceTest -t RfpLaneControllerTest --async --json | python3 -c "import json,sys; s=sys.stdin.read(); print(json.loads(s[s.index('{'):])['result']['id'])"`

The two files go together. Without Step 2, `run`'s `lanesByIds` would not select `Miles__c`, and every new test would stop on `System.SObjectException: SObject row was retrieved via SOQL without querying the requested field: RFP_Lane__c.Miles__c` instead of on its assertion. `RfpLaneController` is a deployed class, so `RfpLaneControllerTest` runs for the 75 % coverage rule.

Expected: a deploy id (`0Af...`). Then poll it, repeating the command until the first word is `Succeeded` or `Failed` (`Queued`, `Pending`, `InProgress` or a client-timeout error name means run it again; each call returns within about 2 minutes, so the watchdog never sees an idle agent):

Run: `sf project deploy report -o sandbox --job-id <id> -w 2 --json | python3 -c "import json,sys; s=sys.stdin.read(); r=json.loads(s[s.index('{'):]); x=r.get('result') or {}; d=x.get('details') or {}; L=lambda v: [v] if isinstance(v, dict) else (v or []); print(x.get('status', r.get('name')), 'tests', x.get('numberTestsCompleted'), '/', x.get('numberTestsTotal'), 'failures', x.get('numberTestErrors')); [print(f.get('fullName'), '->', f.get('problem')) for f in L(d.get('componentFailures'))]; [print(f['name'], f['methodName'], '->', f['message'][:160]) for f in L((d.get('runTestResult') or {}).get('failures'))]"`

Expected: `Failed tests 20 / 26 failures 6` (some sf versions count failed tests as completed and print `26 / 26`; the failures count is what matters), one line per new test:

- `historyMilesOutrankAStoredTruckRoute -> System.AssertException: Assertion Failed: the median billed miles of the matched loads: Expected: 347.5, Actual: 336.4` (the lane still holds the route miles the test put there)
- `historyMilesComeFromTheRadiusFallback -> ... Expected: 351.0, Actual: null`
- `storedTruckAndRegularRoutesFillLanesWithoutHistory -> ... Expected: 336.4, Actual: null`
- `aStoredNoRouteLeavesTheMilesBlank -> ... Expected: No route, Actual: Approx`
- `approxMilesWhenNoRouteIsStoredForThisTruckAndDirection -> ... Expected: Approx, Actual: null`
- `lanesWithoutCoordinatesOrAPlaceGetNoCoordinates -> ... Expected: No coordinates, Actual: null`

The twelve older `RfpHistoryServiceTest` tests and the eight `RfpLaneControllerTest` tests pass. If a failure instead reads `the load keeps its billed miles`, Revenova's `rtms__LoadUpsert` trigger rewrote `rtms__Distance_Miles__c` on insert (Task 5's own factory test should have caught it first): stop and report it to the controller; do not weaken the assertion. A compile error naming `TruckRoute`, `TripMilesService`, `MapboxHttp` or `Truck_Route__c` means an earlier task is not deployed: stop.

- [ ] **Step 4: `RfpHistoryService` — trip miles after each lane's searches**

In `force-app/main/default/classes/RfpHistoryService.cls` (line numbers are the original file's; (a) adds three lines, so locate `run` and `snapshot` by name):

(a) Replace line 1 (the class comment) with:

```apex
/**
 * Writes carrier-quote history snapshots and trip miles onto RFP lanes, ten lanes per call
 * (user-mode DML). Trip miles never call Mapbox here (spec D4, ruling R73): see TripMiles.
 */
```

(b) Replace `run` (lines 8-34) with:

```apex
  public static List<RFP_Lane__c> run(
    List<Id> laneIds,
    String precision,
    Integer lookbackDays,
    Decimal radius,
    String radiusUnit,
    Boolean includeBids
  ) {
    if (laneIds == null || laneIds.size() > MAX_LANES) {
      throw new LaneSearchException(
        'Load history for at most ' + MAX_LANES + ' lanes per call.'
      );
    }
    Integer days = lookbackDays == null || lookbackDays < 1 ? 90 : lookbackDays;
    Integer km = radiusOf(radius);
    String unit = radiusUnit == 'MI' ? 'MI' : 'KM';
    // Null reads as true: a caller that never mentions bids gets the whole market, which is
    // what the workbench's toggle shows by default.
    Boolean bids = includeBids != false;
    List<RFP_Lane__c> lanes = RfpLaneController.lanesByIds(laneIds);
    // Built once per call: one read of the stored truck routes for the whole chunk.
    TripMiles trip = new TripMiles(lanes);
    List<RFP_Lane__c> updates = new List<RFP_Lane__c>();
    for (RFP_Lane__c lane : lanes) {
      updates.add(snapshot(lane, precision, days, km, unit, bids, trip));
    }
    saveSnapshots(updates);
    return RfpLaneController.lanesByIds(laneIds);
  }
```

(c) Replace `snapshot` (lines 98-148) with:

```apex
  private static RFP_Lane__c snapshot(
    RFP_Lane__c lane,
    String precision,
    Integer days,
    Integer radius,
    String unit,
    Boolean includeBids,
    TripMiles trip
  ) {
    RFP_Lane__c u = new RFP_Lane__c(
      Id = lane.Id,
      Hist_Lookback_Days__c = days,
      Hist_As_Of__c = Datetime.now(),
      Hist_Count__c = 0,
      Hist_Bid_Count__c = 0,
      Hist_Min__c = null,
      Hist_Median__c = null,
      Hist_Average__c = null,
      Hist_Max__c = null,
      // Reset here (not left unset) so a LaneSearchException/generic-exception catch below never
      // leaves a stale precision from an earlier run sitting next to a No match/Failed status;
      // the success path below sets the real value after this.
      Hist_Precision__c = null
    );
    if (
      lane.Origin_Place__r?.Key__c == null ||
      lane.Destination_Place__r?.Key__c == null
    ) {
      u.Hist_Status__c = 'Unresolved';
      trip.apply(u, lane, null);
      return u;
    }
    // Declared outside the try so the miles below read the search actually used: the RADIUS
    // fallback's result when it ran, the CITY result when the fallback threw.
    LaneSearchResult r = null;
    try {
      String used = precision;
      r = LaneSearchService.search(
        request(lane, precision, days, radius, unit, includeBids)
      );
      if (r.rows.isEmpty() && precision == 'CITY') {
        used = 'RADIUS';
        r = LaneSearchService.search(
          request(lane, used, days, radius, unit, includeBids)
        );
      }
      fill(u, r, lane.CurrencyIsoCode);
      u.Hist_Precision__c = used == 'RADIUS' ? 'RADIUS-' + radius + unit : used;
      u.Hist_Status__c = r.rows.isEmpty() ? 'No match' : 'Done';
    } catch (LaneSearchException e) {
      u.Hist_Status__c = 'No match';
    } catch (Exception e) {
      u.Hist_Status__c = 'Failed';
    }
    trip.apply(u, lane, r);
    return u;
  }
```

(d) Before the class's final closing brace (after `fill`, which ends at line 219), insert:

```apex
  /**
   * Phase 7 trip miles for a history run (spec D4; rulings R73, R75): History, else the stored
   * truck route for the lane's ordered place pair and the current truck, else Approx, else
   * No coordinates. Every branch rewrites all three fields, so a stale route's hours never sit
   * next to History or Approx miles. Kept out of the outer class for the same complexity-budget
   * reason as RfpBidAccess.Gate.
   */
  private class TripMiles {
    private final TruckRoute.Profile profile = TruckRoute.defaultProfile();
    private final Map<String, Truck_Route__c> stored;

    TripMiles(List<RFP_Lane__c> lanes) {
      Set<String> keys = new Set<String>();
      for (RFP_Lane__c lane : lanes) {
        String key = routeKeyOf(lane);
        if (key != null) {
          keys.add(key);
        }
      }
      stored = TripMilesService.storedRoutes(keys);
    }

    private void apply(RFP_Lane__c u, RFP_Lane__c lane, LaneSearchResult r) {
      u.Miles__c = r?.medianMiles;
      u.Route_Hours__c = null;
      if (u.Miles__c != null) {
        u.Miles_Source__c = 'History';
        return;
      }
      Truck_Route__c route = stored.get(routeKeyOf(lane));
      if (route?.Status__c == 'Found') {
        u.Miles__c = route.Miles__c;
        u.Route_Hours__c = route.Hours__c;
        u.Miles_Source__c = route.Route_Type__c == 'Regular'
          ? 'Regular route'
          : 'Truck route';
      } else if (route?.Status__c == 'No route') {
        u.Miles_Source__c = 'No route';
      } else {
        u.Miles__c = approx(lane);
        u.Miles_Source__c = u.Miles__c == null ? 'No coordinates' : 'Approx';
      }
    }

    private String routeKeyOf(RFP_Lane__c lane) {
      return lane.Origin_Place__c == null ||
        lane.Destination_Place__c == null
        ? null
        : TripMilesService.routeKey(
            lane.Origin_Place__c,
            lane.Destination_Place__c,
            profile
          );
    }

    private Decimal approx(RFP_Lane__c lane) {
      return lane.Origin_Place__r == null ||
        lane.Destination_Place__r == null
        ? null
        : TripMilesService.approxMiles(
            lane.Origin_Place__r,
            lane.Destination_Place__r,
            profile
          );
    }
  }
```

Why an inner class and not a few more lines in `snapshot`/`fill`: the class's cyclomatic total is 37 today against the quickstart budget of 40 (PMD reports a class at 40). With `TripMiles` as a private inner class the outer class stays at 37 (`snapshot` 9, `run` 8) and `TripMiles` totals 15 (`apply` 6, constructor 3, `routeKeyOf` 3, `approx` 3) — measured with PMD 7.15.0 on this exact code. Inlined, `apply` alone would take the outer class to 43. The inner-class methods carry no access modifier on the constructor, like `MapboxGeocoderTest.Mock(Integer, String)`, and the outer class calls private inner-class methods the way `RfpBidAccess` calls `GATE.read()`.

Behaviour notes for the reviewer:

- `r` is declared before the `try`, so `apply` reads the search actually used: the RADIUS result when the CITY search found nothing and the fallback ran; the CITY result (no rows, so `medianMiles` null) when the fallback threw; `null` when the first search threw.
- `apply` runs outside the `try`: it makes no query and no callout and every step is null-safe (`Map.get(null)` returns null; a missing place or coordinate gives `null` miles and `No coordinates`), so a failure in it cannot be one lane's `Failed` status; it would be a code defect, surfaced as the controller's chunk error.
- The unresolved path calls `apply(u, lane, null)` too: an unresolved lane gets `No coordinates` with blank miles and hours (see Contract notes).
- `TripMilesService.storedRoutes` runs once per `run`, inside the `TripMiles` constructor, after `lanesByIds` and before the first search; `TruckRoute.defaultProfile()` reads custom metadata, which costs no query.


- [ ] **Step 5: Deploy the three classes and run the tests**

Run: `sf project deploy start -o sandbox --source-dir force-app/main/default/classes/RfpHistoryService.cls --source-dir force-app/main/default/classes/RfpHistoryServiceTest.cls --source-dir force-app/main/default/classes/RfpLaneController.cls -l RunSpecifiedTests -t RfpHistoryServiceTest -t RfpLaneControllerTest -t RfpSecurityTest -t RfpBulkServiceTest -t RfpBulkControllerTest --async --json | python3 -c "import json,sys; s=sys.stdin.read(); print(json.loads(s[s.index('{'):])['result']['id'])"`

Expected: a deploy id. Poll it until the first word is `Succeeded` or `Failed` (`Queued`, `Pending`, `InProgress` or a client-timeout error name means run it again):

Run: `sf project deploy report -o sandbox --job-id <id> -w 2 --json | python3 -c "import json,sys; s=sys.stdin.read(); r=json.loads(s[s.index('{'):]); x=r.get('result') or {}; d=x.get('details') or {}; L=lambda v: [v] if isinstance(v, dict) else (v or []); print(x.get('status', r.get('name')), 'tests', x.get('numberTestsCompleted'), '/', x.get('numberTestsTotal'), 'failures', x.get('numberTestErrors')); [print(f.get('fullName'), '->', f.get('problem')) for f in L(d.get('componentFailures'))]; [print(f['name'], f['methodName'], '->', f['message'][:160]) for f in L((d.get('runTestResult') or {}).get('failures'))]"`

Expected: `Succeeded tests 51 / 51 failures 0` — `RfpHistoryServiceTest` 18, `RfpLaneControllerTest` 8, `RfpSecurityTest` 11, `RfpBulkServiceTest` 10, `RfpBulkControllerTest` 4. `RfpLaneController` is a deployed class, so the org's 75 % per-class coverage rule needs `RfpLaneControllerTest`. `RfpSecurityTest` and the two bulk classes read lanes through `lanesByIds` as an `RFP_Tool_User`, which proves the new relationship fields are readable in user mode. A failure there naming `Miles__c`, `Miles_Source__c` or `Route_Hours__c` means Task 1's field permissions are missing; one naming `Geolocation__Latitude__s` means the org's `RFP_Tool_User` lacks `Pricing_Place__c.Geolocation__c` read (the repo grants it: redeploy the permission set, don't change the query). If an earlier task added test methods to one of these five classes, the totals grow by that many; the failures must still be 0.

- [ ] **Step 6: PMD and Prettier**

Run: `/private/tmp/pmd_install/pmd-bin-7.15.0/bin/pmd check --dir force-app --rulesets config/pmd-ruleset.xml --minimum-priority 3 --format text --fail-on-violation; echo "pmd exit $?"`

Expected: no violation lines, `pmd exit 0`. `CyclomaticComplexity` on `RfpHistoryService` must not appear (outer class 37, `TripMiles` 15). If it does, the miles logic has leaked into `run`/`snapshot`: move it back into `TripMiles`. Do not add a suppression or raise the budget.

Run: `npx prettier --check force-app/main/default/classes/RfpHistoryService.cls force-app/main/default/classes/RfpHistoryServiceTest.cls force-app/main/default/classes/RfpLaneController.cls`

Expected: `All matched files use Prettier code style!` (the code above is already Prettier-formatted). If a file is listed, run `npx prettier --write` on it, re-run the check, then PMD again.

- [ ] **Step 7: Commit**

```bash
git add force-app/main/default/classes/RfpHistoryService.cls force-app/main/default/classes/RfpHistoryServiceTest.cls force-app/main/default/classes/RfpLaneController.cls
git commit -m "Fill lane miles during Load history from billed miles, stored routes or the straight line"
git show --stat --oneline HEAD
```

Expected: lint-staged runs Prettier on the three files; `git show --stat` lists exactly those three files. Never stage `.vscode/settings.json` or any `* 2.*` file. No attribution trailer.

#### Contract notes (Task 6)

1. **No permission-set change.** The contract asked to check whether `RFP_Tool_User` can read `Pricing_Place__c.Geolocation__c`; it can (`RFP_Tool_User.permissionset-meta.xml` line 116, object read on `Pricing_Place__c`; lines 578-582, field read on `Geolocation__c`), so the user-mode `LANE_FIELDS` query with `Origin_Place__r.Geolocation__Latitude__s` works as is. `Lane_Benchmark_User` grants the same (lines 172-176) but reads no lanes.
2. **The source order lives in a private inner class `RfpHistoryService.TripMiles`**, called from `snapshot()` rather than written into `snapshot()`/`fill()`. The class is at a cyclomatic total of 37 against PMD's 40; the chain alone (`apply`) is 6. Measured with PMD 7.15.0 on the exact code in Step 4: outer class 37, `TripMiles` 15. Same precedent as `RfpBidAccess.Gate`/`Selected`.
3. **History miles are read from `LaneSearchResult.medianMiles`** (Task 5 fills it in `collectRows` through `TripMilesService.medianMiles`), not by calling `TripMilesService.medianMiles(r.rows)` a second time. It is the same number over the same deduped rows of the search actually used, it costs no second pass, and it keeps Task 6 independent of where the per-row miles live (`Row.load.miles`, declared in Task 4's `LaneSearchResult.LoadDetail` and filled by Task 5).
4. **Unresolved lanes get `Miles_Source__c = 'No coordinates'`, blank miles and hours.** Contract item 9 says "for each lane"; spec D4 says "fills every resolved lane". The run already resets every `Hist_*` field on an unresolved lane, and the restricted picklist has no `Unresolved` value. Writing `No coordinates` (a place is missing, so there are no coordinates to measure) also clears miles left from an earlier resolution. `lanesWithoutCoordinatesOrAPlaceGetNoCoordinates` asserts it. Accepted in planning: the guide (Task 11) and the table and panel tooltips (Task 9) say "missing or has no coordinates", and the Outcome records it as a difference from D4.
5. **Lanes whose search ended `No match` or `Failed` still get stored-route or Approx miles**, because neither source depends on the search. Only History needs the rows.
6. A stored `Found` row with `Route_Type__c = 'Regular'` maps to `Regular route`; any other `Found` row (`Truck`) maps to `Truck route`. A stored `No route` row gives `No route` with blank miles, never Approx (spec §7: saved as `No route`, shown as "—").
7. **Tests.** "History wins" and "History is written even when a stored route exists" are one test (`historyMilesOutrankAStoredTruckRoute`), which also proves the stored route's hours are cleared. Beyond the contract's list: `historyMilesComeFromTheRadiusFallback` (the search actually used), and the Approx test also proves the key respects direction and the truck profile (R71). The "no callout" proof sets `MapboxHttp.tokenOverride = 'pk.test'` and a mock whose `respond` fails with an uncatchable `System.assert(false)`, then checks `Limits.getCallouts()` inside `Test.startTest()`/`stopTest()`. A mock that threw `CalloutException` would be turned into `Unavailable` by `MapboxHttp` and could pass on the wrong path.
8. The tests build `new TruckRoute.Profile()` and set `heightM`/`widthM`/`weightT`. Task 2's `Profile` has only the default no-argument constructor, and `defaultProfile()` builds a new `Profile` on every call; the tests still never mutate the one it returns.
9. Load miles in tests come from Task 5's `PricingTestDataFactory.createLoad(Graph, Account, Account, Decimal miles)`, which sets `rtms__Distance_Miles__c` before the insert, so there is no extra load DML. `addLoadWithMiles` still reads the value back, because the managed `rtms__LoadUpsert` trigger runs on every load save (ApexTrigger query on PostProduc, 2026-09-14). One `createLoad` per `Test.startTest()` block, as the existing tests do (see `LaneSearchServiceTest.hazmatMarketTestAcceptedAndExcludedContactFilters`).
10. Deploys follow the phase 7 execution rules (`--async --json`, then `deploy report --job-id <id> -w 2`), not phase 6's foreground `-w 15`.
11. `LANE_FIELDS` now returns nested place coordinates to the LWC. They never round-trip: `rfpTool.js:471-473` posts `{ Id, ...fields }` with only the `rfpPricing.js:115` whitelist to `saveLanePricing`.

---

### Task 7: On-demand routes — `TripRouteView`, `RfpLaneController.laneRoute`, `LaneBenchmarkController.truckRoute`

**Files:**

- Create: `force-app/main/default/classes/TripRouteView.cls`, `force-app/main/default/classes/TripRouteView.cls-meta.xml`
- Modify: `force-app/main/default/classes/RfpLaneController.cls` (new method `laneRoute`, inserted after `resolveLaneEnd`, which ends at line 163 before Task 6; Task 6 lengthens `LANE_FIELDS` at lines 3-10, so find the method by name)
- Modify: `force-app/main/default/classes/LaneBenchmarkController.cls:212-227` (new method `truckRoute` after `mapPreviewUrl`)
- Modify: `force-app/main/default/classes/LaneBenchmarkPlaceService.cls:174-177` (`placesByKey` becomes `public`, with a doc comment)
- Modify: `force-app/main/default/classes/RfpLaneControllerTest.cls` (a Directions mock and fixtures after line 32; seven `laneRoute` tests and two Read-shared pricer tests before the closing brace at line 233)
- Modify: `force-app/main/default/classes/LaneBenchmarkControllerTest.cls` (a Directions mock after line 104; two `truckRoute` tests and one Lane Benchmark user test before the closing brace at line 357)
- Modify: `force-app/main/default/classes/RfpSecurityTest.cls` (one stranger `try/catch` after line 266, inside `withoutAccountAccessTheRfpIsAbsentButLaneBenchmarkStillCountsItsBid`; no new method, see Contract notes 4)
- Modify: `force-app/main/default/permissionsets/RFP_Tool_User.permissionset-meta.xml`, `force-app/main/default/permissionsets/Lane_Benchmark_User.permissionset-meta.xml` (`classAccesses` for `TripRouteView`)
- Modify: `manifest/package.xml` (ApexClass member `TripRouteView`)

**Interfaces:**

- Consumes:
  - Task 1: `RFP_Lane__c.Miles__c`, `Miles_Source__c` (`History`, `Truck route`, `Regular route`, `Approx`, `No route`, `No coordinates`), `Route_Hours__c` with read and edit in `RFP_Tool_User`; `Truck_Route__c` (`Origin_Place__c`, `Destination_Place__c`, `Profile_Key__c`, `Route_Key__c`, `Miles__c`, `Hours__c`, `Route_Type__c`, `Status__c`, `Routes_Json__c`, `Checked_On__c`); `Truck_Routing_Setting__mdt.Default` (4.11, 2.6, 36.29, true, 1.2, 8000).
  - Task 2: `MapboxHttp.BASE`, `@TestVisible MapboxHttp.tokenOverride`; `TruckRoute.Point(Decimal lat, Decimal lng)`, `TruckRoute.Line` (`miles`, `hours`, `polyline5`), `TruckRoute.Result` (`status`, `routeType`, `routes`, `message`), `TruckRoute.defaultProfile()`, `TruckRoute.UNAVAILABLE`; `MapboxTruckRoute.route` (called through Task 4, never directly here).
  - Task 3: `RouteMapUrl.build(TruckRoute.Point origin, TruckRoute.Point destination, List<TruckRoute.Line> routes)`.
  - Task 4: `TripMilesService.RouteOutcome` (`result`, `toSave`, `fromStore`), `TripMilesService.storedOrRoute(Pricing_Place__c o, Pricing_Place__c d, TruckRoute.Profile p, Boolean refresh)`, `TripMilesService.save(List<Truck_Route__c> rows)`, `TripMilesService.routeKey(Id originPlaceId, Id destinationPlaceId, TruckRoute.Profile p)`. What this task relies on beyond the signatures: `storedOrRoute` reads only `Id`, `Geolocation__Latitude__s` and `Geolocation__Longitude__s` from the places it is given (`TripRouteView.laneEnd` builds a bare record), and makes no DML; `fromStore` is true when a stored row answered; `toSave` is null for Unavailable and otherwise carries `Origin_Place__c`, `Destination_Place__c`, `Profile_Key__c`, `Route_Key__c`, `Status__c`, `Route_Type__c`, `Miles__c`, `Hours__c`, `Checked_On__c` and `Routes_Json__c` with every route (main first, each with `miles`, `hours`, `polyline5`), so that `fromStored` gives back all the lines (the store-reuse test expects two routes and a map URL from the stored row); `save` upserts on `Route_Key__c` past sharing (Contract notes 5).
  - Task 6: `RfpLaneController.LANE_FIELDS` carries `Miles__c, Miles_Source__c, Route_Hours__c` and both places' `Geolocation__Latitude__s` / `Geolocation__Longitude__s`, so `lanesByIds` and `one` return them.
  - Existing: `RfpBidAccess.LANE_UNAVAILABLE`, `RfpUserError.of` / `safe`, `RfpTestDataFactory.createPlace` / `createProject` / `createLane` / `restrictedUser` / `shareAccount`, `PricingTestDataFactory.createGraph()`.
- Produces:
  - `TripRouteView` (`public with sharing`), every field `@AuraEnabled public`: `String status` (`'Found'` | `'No route'` | `'Unavailable'`); `String routeType` (`'Truck'` | `'Regular'` | null); `String source` — the `Miles_Source__c` value the route stands for: `'Truck route'` | `'Regular route'` when Found, `'No route'` when No route, null when Unavailable (the lane's own `Miles_Source__c`, e.g. `History`, is on `lane` / the table row); `Decimal miles`, `Decimal hours` — the main route's, set only when Found; `List<TruckRoute.Line> routes` (never null, main route first); `String mapUrl` — `RouteMapUrl.build(...)` when Found, otherwise null (so Lane Benchmark keeps its radius preview); `String message` — `TruckRoute.UNAVAILABLE`, `TripRouteView.NO_COORDINATES` or `TripRouteView.NO_ROUTE` when not Found, null when Found; `RFP_Lane__c lane` — set only by `laneRoute`, and only when the call wrote the lane's miles (the re-read lane, `LANE_FIELDS`).
  - `TripRouteView.NO_COORDINATES = 'This lane has no coordinates.'`, `TripRouteView.NO_ROUTE = 'No route was found between these places, even without truck limits.'`
  - `TripRouteView.routeBetween(Pricing_Place__c origin, Pricing_Place__c destination, Boolean refresh)` — the shared flow: no callout without both places' Id and coordinates; `storedOrRoute` with `TruckRoute.defaultProfile()`; saves `toSave` after the callouts (never a row that came from the store); builds the view and the map URL.
  - `TripRouteView.laneEnd(Id placeId, Pricing_Place__c related)` — the place a lane end routes from (`Id` + coordinates), null without a place.
  - `TripRouteView.laneUpdate(RFP_Lane__c lane, TripRouteView view)` — the `RFP_Lane__c(Id, Miles__c, Miles_Source__c, Route_Hours__c)` a route writes, or null when the lane's source is `History` or the view has no source (Unavailable).
  - `@AuraEnabled public static TripRouteView RfpLaneController.laneRoute(Id laneId, Boolean refresh)` (not cacheable) — a lane the caller cannot read throws `AuraHandledException` with message `RfpBidAccess.LANE_UNAVAILABLE`.
  - `@AuraEnabled public static TripRouteView LaneBenchmarkController.truckRoute(String originKey, String destinationKey, Boolean refresh)` (not cacheable) — an unknown or blank key returns status `Unavailable` with `NO_COORDINATES`; never writes a lane.
  - `LaneBenchmarkPlaceService.placesByKey(Set<String> keys)` is now `public` (was `private`).

- [ ] **Step 1: Write the failing `laneRoute` tests**

Tasks 1 to 6 are deployed to `sandbox` before this task starts (the tests below need `Truck_Route__c`, the lane miles fields, `MapboxHttp`, `TruckRoute`, `RouteMapUrl` and `TripMilesService` in the org).

In `force-app/main/default/classes/RfpLaneControllerTest.cls`, insert after the end of `fx()` (line 32, the `  }` after `return f;`):

```apex
  /** Mapbox Directions stand-in: one canned answer for every request; counts calls, keeps the last endpoint. */
  private class DirectionsMock implements HttpCalloutMock {
    Integer status;
    String body;
    Integer calls = 0;
    String lastEndpoint;
    DirectionsMock(Integer status, String body) {
      this.status = status;
      this.body = body;
    }
    public HttpResponse respond(HttpRequest req) {
      calls++;
      lastEndpoint = req.getEndpoint();
      System.assert(
        lastEndpoint.startsWith(
          MapboxHttp.BASE + '/directions/v5/mapbox/driving/'
        ),
        'a Directions request'
      );
      HttpResponse r = new HttpResponse();
      r.setStatusCode(status);
      r.setBody(body);
      return r;
    }
  }

  /** Two routes: 540,000 m in 19,800 s (335.5 mi, 5.5 h), then 560,000 m in 21,000 s (348.0 mi, 5.8 h). */
  private static final String FOUND = '{"code":"Ok","routes":[{"distance":540000,"duration":19800,"geometry":"_p~iF~ps|U_ulLnnqC_mqNvxq`@","legs":[{"notifications":[]}]},{"distance":560000,"duration":21000,"geometry":"_p~iF~ps|U_ulLnnqC","legs":[{"notifications":[]}]}],"waypoints":[]}';

  private static final String NO_ROUTE = '{"code":"NoRoute","message":"No route found","routes":[]}';

  /** A Found route for Montréal to Toronto stored a month ago, as another pricer's lane open leaves it. */
  private static void storedRoute(Fx f, Decimal miles) {
    TruckRoute.Profile profile = TruckRoute.defaultProfile();
    insert new Truck_Route__c(
      Origin_Place__c = f.mtl.Id,
      Destination_Place__c = f.tor.Id,
      Profile_Key__c = profile.key(),
      Route_Key__c = TripMilesService.routeKey(f.mtl.Id, f.tor.Id, profile),
      Miles__c = miles,
      Hours__c = 20.0,
      Route_Type__c = 'Truck',
      Status__c = 'Found',
      Routes_Json__c = '[{"miles":' +
        miles +
        ',"hours":20.0,"polyline5":"_p~iF~ps|U_ulLnnqC"}]',
      Checked_On__c = System.now().addDays(-30)
    );
  }

  private static RFP_Lane__c storedLane(Id laneId) {
    return [
      SELECT Miles__c, Miles_Source__c, Route_Hours__c
      FROM RFP_Lane__c
      WHERE Id = :laneId
    ];
  }
```

Then insert before the class's closing brace (line 233 before this insertion):

```apex
  // ---- phase 7: laneRoute ----

  @IsTest
  static void laneRouteStoresTheTruckRouteWritesTheMilesAndReusesTheStore() {
    Fx f = fx();
    MapboxHttp.tokenOverride = 'pk.test';
    DirectionsMock mock = new DirectionsMock(200, FOUND);
    Test.setMock(HttpCalloutMock.class, mock);
    String key = TripMilesService.routeKey(
      f.mtl.Id,
      f.tor.Id,
      TruckRoute.defaultProfile()
    );
    Test.startTest();
    TripRouteView view = RfpLaneController.laneRoute(f.lane.Id, false);
    TripRouteView reopened = RfpLaneController.laneRoute(f.lane.Id, false);
    Test.stopTest();
    System.assertEquals('Found', view.status, view.message);
    System.assertEquals('Truck', view.routeType);
    System.assertEquals('Truck route', view.source);
    System.assertEquals(335.5, view.miles);
    System.assertEquals(5.5, view.hours);
    System.assertEquals(2, view.routes.size(), 'the alternative comes along');
    System.assertEquals(348.0, view.routes[1].miles);
    System.assertEquals(null, view.message);
    System.assert(
      view.mapUrl != null && view.mapUrl.contains('path-5+0070d2'),
      'the main route is drawn'
    );
    System.assert(
      mock.lastEndpoint.contains('-73.5674') &&
      mock.lastEndpoint.contains('-79.3832'),
      'routed between the lane\'s two places'
    );
    System.assertEquals(
      335.5,
      view.lane.Miles__c,
      'the re-read lane comes back for the table'
    );
    System.assertEquals('Truck route', view.lane.Miles_Source__c);
    System.assertEquals(5.5, view.lane.Route_Hours__c);
    RFP_Lane__c lane = storedLane(f.lane.Id);
    System.assertEquals(335.5, lane.Miles__c);
    System.assertEquals('Truck route', lane.Miles_Source__c);
    System.assertEquals(5.5, lane.Route_Hours__c);
    Truck_Route__c row = [
      SELECT
        Origin_Place__c,
        Destination_Place__c,
        Status__c,
        Route_Type__c,
        Miles__c,
        Hours__c
      FROM Truck_Route__c
      WHERE Route_Key__c = :key
    ];
    System.assertEquals(f.mtl.Id, row.Origin_Place__c);
    System.assertEquals(f.tor.Id, row.Destination_Place__c);
    System.assertEquals('Found', row.Status__c);
    System.assertEquals('Truck', row.Route_Type__c);
    System.assertEquals(335.5, row.Miles__c);
    System.assertEquals(5.5, row.Hours__c);
    System.assertEquals(
      1,
      mock.calls,
      'the second open is answered by the store'
    );
    System.assertEquals('Found', reopened.status);
    System.assertEquals(335.5, reopened.miles);
    System.assertEquals(
      2,
      reopened.routes.size(),
      'the stored alternatives redraw the map'
    );
    System.assertNotEquals(null, reopened.mapUrl);
    System.assertEquals(
      1,
      [SELECT COUNT() FROM Truck_Route__c WHERE Origin_Place__c = :f.mtl.Id],
      'one row per place pair and profile'
    );
  }

  @IsTest
  static void laneRouteRefreshAsksMapboxAgainAndReplacesTheStoredRoute() {
    Fx f = fx();
    storedRoute(f, 999.9);
    MapboxHttp.tokenOverride = 'pk.test';
    DirectionsMock mock = new DirectionsMock(200, FOUND);
    Test.setMock(HttpCalloutMock.class, mock);
    Test.startTest();
    TripRouteView view = RfpLaneController.laneRoute(f.lane.Id, true);
    Test.stopTest();
    System.assertEquals(1, mock.calls, 'refresh does not take the stored row');
    System.assertEquals(335.5, view.miles);
    List<Truck_Route__c> rows = [
      SELECT Miles__c, Hours__c
      FROM Truck_Route__c
      WHERE Origin_Place__c = :f.mtl.Id
    ];
    System.assertEquals(1, rows.size(), 'replaced, not duplicated');
    System.assertEquals(335.5, rows[0].Miles__c);
    System.assertEquals(5.5, rows[0].Hours__c);
    System.assertEquals(335.5, storedLane(f.lane.Id).Miles__c);
  }

  @IsTest
  static void laneRouteKeepsHistoryMilesButStoresTheRoute() {
    Fx f = fx();
    update new RFP_Lane__c(
      Id = f.lane.Id,
      Miles__c = 350.0,
      Miles_Source__c = 'History'
    );
    MapboxHttp.tokenOverride = 'pk.test';
    Test.setMock(HttpCalloutMock.class, new DirectionsMock(200, FOUND));
    Test.startTest();
    TripRouteView view = RfpLaneController.laneRoute(f.lane.Id, false);
    Test.stopTest();
    System.assertEquals('Found', view.status, view.message);
    System.assertEquals(335.5, view.miles, 'the map still shows the route');
    System.assertEquals(null, view.lane, 'the lane was not written');
    RFP_Lane__c lane = storedLane(f.lane.Id);
    System.assertEquals(
      350.0,
      lane.Miles__c,
      'billed miles outrank a route (R75)'
    );
    System.assertEquals('History', lane.Miles_Source__c);
    System.assertEquals(null, lane.Route_Hours__c);
    System.assertEquals(
      1,
      [SELECT COUNT() FROM Truck_Route__c WHERE Origin_Place__c = :f.mtl.Id]
    );
  }

  @IsTest
  static void laneRouteUnavailableSavesNothingAndKeepsTheMiles() {
    Fx f = fx();
    update new RFP_Lane__c(
      Id = f.lane.Id,
      Miles__c = 402.3,
      Miles_Source__c = 'Approx'
    );
    MapboxHttp.tokenOverride = 'pk.test';
    Test.setMock(
      HttpCalloutMock.class,
      new DirectionsMock(401, '{"message":"Not Authorized - Invalid Token"}')
    );
    Test.startTest();
    TripRouteView view = RfpLaneController.laneRoute(f.lane.Id, false);
    Test.stopTest();
    System.assertEquals('Unavailable', view.status);
    System.assertEquals(TruckRoute.UNAVAILABLE, view.message);
    System.assert(
      !view.message.contains('pk.test'),
      'the token never reaches a message'
    );
    System.assertEquals(null, view.source);
    System.assertEquals(null, view.mapUrl);
    System.assertEquals(null, view.lane);
    System.assertEquals(0, view.routes.size());
    System.assertEquals(
      0,
      [SELECT COUNT() FROM Truck_Route__c WHERE Origin_Place__c = :f.mtl.Id],
      'an unavailable route is never stored'
    );
    RFP_Lane__c lane = storedLane(f.lane.Id);
    System.assertEquals(402.3, lane.Miles__c, 'the lane keeps its miles');
    System.assertEquals('Approx', lane.Miles_Source__c);
  }

  @IsTest
  static void laneRouteWithNoRouteStoresItAndClearsTheMiles() {
    Fx f = fx();
    update new RFP_Lane__c(
      Id = f.lane.Id,
      Miles__c = 402.3,
      Miles_Source__c = 'Approx'
    );
    MapboxHttp.tokenOverride = 'pk.test';
    DirectionsMock mock = new DirectionsMock(200, NO_ROUTE);
    Test.setMock(HttpCalloutMock.class, mock);
    Test.startTest();
    TripRouteView view = RfpLaneController.laneRoute(f.lane.Id, false);
    Test.stopTest();
    System.assertEquals(
      2,
      mock.calls,
      'the truck request, then the regular one'
    );
    System.assertEquals('No route', view.status);
    System.assertEquals('No route', view.source);
    System.assert(
      String.isNotBlank(view.message),
      'the panel has a sentence to show'
    );
    System.assertEquals(null, view.mapUrl);
    System.assertEquals(null, view.miles);
    System.assertEquals('No route', view.lane.Miles_Source__c);
    RFP_Lane__c lane = storedLane(f.lane.Id);
    System.assertEquals(null, lane.Miles__c);
    System.assertEquals('No route', lane.Miles_Source__c);
    System.assertEquals(null, lane.Route_Hours__c);
    System.assertEquals(
      'No route',
      [SELECT Status__c FROM Truck_Route__c WHERE Origin_Place__c = :f.mtl.Id]
      .Status__c
    );
  }

  @IsTest
  static void laneRouteWithoutCoordinatesMakesNoCallout() {
    Fx f = fx();
    Pricing_Place__c nowhere = RfpTestDataFactory.createPlace(
      'Nowhere',
      'QC',
      'CA',
      null,
      null,
      'G0A'
    );
    RFP_Lane__c unlocated = RfpTestDataFactory.createLane(
      f.project,
      f.mtl,
      nowhere
    );
    update new RFP_Lane__c(
      Id = f.lane.Id,
      Destination_Place__c = null,
      Destination_Resolved__c = false
    );
    MapboxHttp.tokenOverride = 'pk.test';
    DirectionsMock mock = new DirectionsMock(200, FOUND);
    Test.setMock(HttpCalloutMock.class, mock);
    Test.startTest();
    TripRouteView noCoordinates = RfpLaneController.laneRoute(
      unlocated.Id,
      false
    );
    TripRouteView noPlace = RfpLaneController.laneRoute(f.lane.Id, true);
    Test.stopTest();
    System.assertEquals(0, mock.calls, 'no coordinates, no request');
    for (TripRouteView view : new List<TripRouteView>{ noCoordinates, noPlace }) {
      System.assertEquals('Unavailable', view.status);
      System.assertEquals(TripRouteView.NO_COORDINATES, view.message);
      System.assertEquals(null, view.lane);
    }
    System.assertEquals(
      0,
      [SELECT COUNT() FROM Truck_Route__c WHERE Origin_Place__c = :f.mtl.Id]
    );
    System.assertEquals(
      null,
      storedLane(unlocated.Id).Miles_Source__c,
      'the lane is left for Load history to fill'
    );
  }

  @IsTest
  static void laneRouteOnALaneThatIsGoneIsUnavailable() {
    Fx f = fx();
    Id laneId = f.lane.Id;
    delete new RFP_Lane__c(Id = laneId);
    try {
      RfpLaneController.laneRoute(laneId, false);
      System.assert(false, 'expected AuraHandledException');
    } catch (AuraHandledException e) {
      System.assertEquals(RfpBidAccess.LANE_UNAVAILABLE, e.getMessage());
    }
  }
```

The mock answers every request the same way, so the No route test sees Mapbox's `NoRoute` twice (truck request, then the regular request) and counts two calls. Every callout-bearing call runs after `Test.startTest()` with all fixture DML before it: a callout after DML in the same block throws "You have uncommitted work pending", which `MapboxHttp` would turn into `Unavailable`. That is why the refresh test stores its row before `startTest` and makes one call, and why the store-reuse check follows the first open (the second open makes no callout).

- [ ] **Step 2: Write the failing `truckRoute` tests**

In `force-app/main/default/classes/LaneBenchmarkControllerTest.cls`, insert after the end of `restrictedUser(List<String>)` (line 104, the `  }` after `return u;`):

```apex
  /** Mapbox Directions stand-in: one canned answer for every request; counts calls, keeps the last endpoint. */
  private class DirectionsMock implements HttpCalloutMock {
    Integer status;
    String body;
    Integer calls = 0;
    String lastEndpoint;
    DirectionsMock(Integer status, String body) {
      this.status = status;
      this.body = body;
    }
    public HttpResponse respond(HttpRequest req) {
      calls++;
      lastEndpoint = req.getEndpoint();
      System.assert(
        lastEndpoint.startsWith(
          MapboxHttp.BASE + '/directions/v5/mapbox/driving/'
        ),
        'a Directions request'
      );
      HttpResponse r = new HttpResponse();
      r.setStatusCode(status);
      r.setBody(body);
      return r;
    }
  }

  /** Two routes: 540,000 m in 19,800 s (335.5 mi, 5.5 h), then 560,000 m in 21,000 s (348.0 mi, 5.8 h). */
  private static final String FOUND = '{"code":"Ok","routes":[{"distance":540000,"duration":19800,"geometry":"_p~iF~ps|U_ulLnnqC_mqNvxq`@","legs":[{"notifications":[]}]},{"distance":560000,"duration":21000,"geometry":"_p~iF~ps|U_ulLnnqC","legs":[{"notifications":[]}]}],"waypoints":[]}';
```

Then insert before the class's closing brace (line 357 before this insertion):

```apex
  // ---- phase 7: truckRoute ----

  @IsTest
  static void truckRouteRoutesTwoPlaceKeysStoresTheRouteAndReusesIt() {
    MapboxHttp.tokenOverride = 'pk.test';
    DirectionsMock mock = new DirectionsMock(200, FOUND);
    Test.setMock(HttpCalloutMock.class, mock);
    Test.startTest();
    TripRouteView view = LaneBenchmarkController.truckRoute(
      'montreal|qc|ca',
      'toronto|on|ca',
      false
    );
    TripRouteView again = LaneBenchmarkController.truckRoute(
      'montreal|qc|ca',
      'toronto|on|ca',
      false
    );
    Test.stopTest();
    System.assertEquals('Found', view.status, view.message);
    System.assertEquals('Truck', view.routeType);
    System.assertEquals('Truck route', view.source);
    System.assertEquals(335.5, view.miles);
    System.assertEquals(5.5, view.hours);
    System.assertEquals(2, view.routes.size());
    System.assert(
      view.mapUrl != null &&
      view.mapUrl.contains('pin-s-a+0070d2') &&
      view.mapUrl.contains('access_token=pk.test'),
      'pins, route and token in the static map'
    );
    System.assertEquals(null, view.lane, 'Lane Benchmark writes no lane');
    System.assertEquals(
      1,
      mock.calls,
      'the second search is answered by the store'
    );
    System.assertEquals(335.5, again.miles);
    Id mtlId = [SELECT Id FROM Pricing_Place__c WHERE Key__c = 'montreal|qc|ca']
    .Id;
    Id torId = [SELECT Id FROM Pricing_Place__c WHERE Key__c = 'toronto|on|ca']
    .Id;
    String key = TripMilesService.routeKey(
      mtlId,
      torId,
      TruckRoute.defaultProfile()
    );
    Truck_Route__c row = [
      SELECT Origin_Place__c, Destination_Place__c, Status__c, Miles__c
      FROM Truck_Route__c
      WHERE Route_Key__c = :key
    ];
    System.assertEquals(mtlId, row.Origin_Place__c);
    System.assertEquals(torId, row.Destination_Place__c);
    System.assertEquals('Found', row.Status__c);
    System.assertEquals(335.5, row.Miles__c);
    System.assertEquals(
      0,
      [SELECT COUNT() FROM Truck_Route__c WHERE Origin_Place__c = :torId],
      'direction matters: nothing stored for Toronto to Montréal'
    );
  }

  @IsTest
  static void truckRouteWithAnUnknownOrUnlocatedPlaceIsUnavailable() {
    insert place('Nowhere', 'QC', 'CA', null, null, 0, null);
    MapboxHttp.tokenOverride = 'pk.test';
    DirectionsMock mock = new DirectionsMock(200, FOUND);
    Test.setMock(HttpCalloutMock.class, mock);
    Test.startTest();
    List<TripRouteView> views = new List<TripRouteView>{
      LaneBenchmarkController.truckRoute('nowhere|zz|zz', 'toronto|on|ca', false),
      LaneBenchmarkController.truckRoute('montreal|qc|ca', 'nowhere|qc|ca', true),
      LaneBenchmarkController.truckRoute(null, 'toronto|on|ca', false)
    };
    Test.stopTest();
    System.assertEquals(0, mock.calls, 'no coordinates, no request');
    for (TripRouteView view : views) {
      System.assertEquals('Unavailable', view.status);
      System.assertEquals(TripRouteView.NO_COORDINATES, view.message);
      System.assertEquals(null, view.mapUrl, 'the radius preview stays');
    }
    Id mtlId = [SELECT Id FROM Pricing_Place__c WHERE Key__c = 'montreal|qc|ca']
    .Id;
    System.assertEquals(
      0,
      [SELECT COUNT() FROM Truck_Route__c WHERE Origin_Place__c = :mtlId]
    );
  }
```

The `@TestSetup` places (`montreal|qc|ca`, `toronto|on|ca`) carry coordinates; `place(...)` is the class's existing builder.

- [ ] **Step 3: Write the failing access tests**

`RfpSecurityTest` is at a PMD class complexity of 38 against the budget of 40 (every test method adds at least 1, a restricted-user guard 1 more), so only the stranger check goes there, inside the existing no-access test; the two pricer tests go to `RfpLaneControllerTest` and the Lane Benchmark user test to `LaneBenchmarkControllerTest`, whose mocks and fixtures they reuse.

In `force-app/main/default/classes/RfpSecurityTest.cls`, method `withoutAccountAccessTheRfpIsAbsentButLaneBenchmarkStillCountsItsBid`, insert after the `saveBid` refusal (line 266, the `      }` closing the `catch` whose assertion is `System.assertEquals(RfpBidAccess.LANE_UNAVAILABLE, e.getMessage());` after `RfpBidController.saveBid(...)`), still inside `System.runAs(stranger)`:

```apex
      try {
        RfpLaneController.laneRoute(laneId, false);
        System.assert(false, 'expected AuraHandledException');
      } catch (AuraHandledException e) {
        System.assertEquals(RfpBidAccess.LANE_UNAVAILABLE, e.getMessage());
      }
```

The stranger holds `RFP_Tool_User` and `Lane_Benchmark_User` but no share on the customer, so the user-mode lane read comes back empty and `laneRoute` refuses before any callout (no mock needed).

In `force-app/main/default/classes/RfpLaneControllerTest.cls`, append after the tests from Step 1, before the class's closing brace:

```apex
  /**
   * Read on the account is enough to open a lane's truck route (phase 6 sharing). The route is
   * stored past sharing and CRUD (RFP_Tool_User reads Truck_Route__c only) and the lane takes its
   * miles in user mode after the FLS strip, so a missing edit grant on the miles fields would drop
   * them silently. Here rather than in RfpSecurityTest: that class sits at 39 of PMD's class
   * complexity budget of 40 once its stranger check is added, and every test method counts.
   */
  @IsTest
  static void aReadSharedPricerOpensALaneRoute() {
    Fx f = fx();
    User pricing = RfpTestDataFactory.restrictedUser('RFP_Tool_User');
    if (pricing == null) {
      System.assert(
        true,
        'no usable profile in this org; runAs coverage skipped (ledgered)'
      );
      return;
    }
    RfpTestDataFactory.shareAccount(f.g.customer, pricing, 'Read');
    MapboxHttp.tokenOverride = 'pk.test';
    DirectionsMock mock = new DirectionsMock(200, FOUND);
    Test.setMock(HttpCalloutMock.class, mock);
    Id laneId = f.lane.Id;
    Test.startTest();
    TripRouteView view;
    System.runAs(pricing) {
      view = RfpLaneController.laneRoute(laneId, false);
    }
    Test.stopTest();
    System.assertEquals('Found', view.status, view.message);
    System.assertEquals(1, mock.calls);
    System.assertNotEquals(null, view.lane, 'the lane was written');
    System.assertEquals(
      'Truck route',
      view.lane.Miles_Source__c,
      'the re-read lane shows the new miles to the pricer'
    );
    RFP_Lane__c lane = storedLane(laneId);
    System.assertEquals(335.5, lane.Miles__c);
    System.assertEquals('Truck route', lane.Miles_Source__c);
    System.assertEquals(5.5, lane.Route_Hours__c);
    System.assertEquals(
      1,
      [SELECT COUNT() FROM Truck_Route__c WHERE Origin_Place__c = :f.mtl.Id]
    );
  }

  /**
   * Truck_Route__c is Public Read Only and a row belongs to whoever asked first, so another
   * pricer's Refresh route updates a row they have no edit share on. The save runs past sharing
   * (TripMilesService), or nobody could refresh a colleague's route.
   */
  @IsTest
  static void aReadSharedPricerRefreshesARouteAColleagueStored() {
    Fx f = fx();
    User pricing = RfpTestDataFactory.restrictedUser('RFP_Tool_User');
    if (pricing == null) {
      System.assert(
        true,
        'no usable profile in this org; runAs coverage skipped (ledgered)'
      );
      return;
    }
    RfpTestDataFactory.shareAccount(f.g.customer, pricing, 'Read');
    storedRoute(f, 999.9);
    MapboxHttp.tokenOverride = 'pk.test';
    DirectionsMock mock = new DirectionsMock(200, FOUND);
    Test.setMock(HttpCalloutMock.class, mock);
    Id laneId = f.lane.Id;
    Test.startTest();
    TripRouteView view;
    System.runAs(pricing) {
      view = RfpLaneController.laneRoute(laneId, true);
    }
    Test.stopTest();
    System.assertEquals('Found', view.status, view.message);
    System.assertEquals(1, mock.calls);
    List<Truck_Route__c> rows = [
      SELECT Miles__c
      FROM Truck_Route__c
      WHERE Origin_Place__c = :f.mtl.Id
    ];
    System.assertEquals(1, rows.size());
    System.assertEquals(
      335.5,
      rows[0].Miles__c,
      'the colleague\'s row is replaced by the refresh'
    );
  }
```

In `force-app/main/default/classes/LaneBenchmarkControllerTest.cls`, append after the tests from Step 2, before the class's closing brace:

```apex
  /**
   * A Lane Benchmark user, who holds no RFP permission and only Read on Truck_Route__c, gets and
   * stores a truck route (the save runs past CRUD in TripMilesService).
   */
  @IsTest
  static void aLaneBenchmarkUserGetsATruckRoute() {
    User viewer = restrictedUser('Lane_Benchmark_User');
    if (viewer == null) {
      System.assert(
        true,
        'no usable profile in this org; runAs coverage skipped (ledgered)'
      );
      return;
    }
    MapboxHttp.tokenOverride = 'pk.test';
    DirectionsMock mock = new DirectionsMock(200, FOUND);
    Test.setMock(HttpCalloutMock.class, mock);
    Test.startTest();
    TripRouteView view;
    System.runAs(viewer) {
      view = LaneBenchmarkController.truckRoute(
        'montreal|qc|ca',
        'toronto|on|ca',
        false
      );
    }
    Test.stopTest();
    System.assertEquals('Found', view.status, view.message);
    System.assertEquals(335.5, view.miles);
    System.assertNotEquals(null, view.mapUrl);
    System.assertEquals(1, mock.calls);
    Id mtlId = [SELECT Id FROM Pricing_Place__c WHERE Key__c = 'montreal|qc|ca']
    .Id;
    System.assertEquals(
      1,
      [SELECT COUNT() FROM Truck_Route__c WHERE Origin_Place__c = :mtlId]
    );
  }
```

- [ ] **Step 4: Deploy the tests alone and watch them fail**

Run: `sf project deploy start -o sandbox --source-dir force-app/main/default/classes/RfpLaneControllerTest.cls --source-dir force-app/main/default/classes/LaneBenchmarkControllerTest.cls --source-dir force-app/main/default/classes/RfpSecurityTest.cls -l NoTestRun --async --json | python3 -c "import json,sys; s=sys.stdin.read(); print(json.loads(s[s.index('{'):])['result']['id'])"`

Expected: a deploy id (`0Af...`). Then poll, repeating while the status is `Pending` or `InProgress`:

Run: `sf project deploy report -o sandbox --job-id <id> -w 2 --json | python3 -c "import json,sys; s=sys.stdin.read(); j=json.loads(s[s.index('{'):]); r=j.get('result') or {}; cf=(r.get('details') or {}).get('componentFailures', []); cf=cf if isinstance(cf, list) else [cf]; print(r.get('status', j.get('name')), [str(d.get('fullName')) + ': ' + str(d.get('problem')) for d in cf][:4])"`

Expected: `Failed` with problems naming the missing code, such as `RfpLaneControllerTest: Invalid type: TripRouteView` and `LaneBenchmarkControllerTest: Method does not exist or incorrect signature: void truckRoute(String, String, Boolean) from the type LaneBenchmarkController`. Any other problem (an unknown `Truck_Route__c` field, `MapboxHttp.tokenOverride` not visible, `TripMilesService.routeKey` missing) means an earlier task is not deployed: stop and report.

- [ ] **Step 5: Create `TripRouteView`**

Create `force-app/main/default/classes/TripRouteView.cls`:

```apex
/**
 * The truck route the lane panel or a Lane Benchmark search shows (phase 7), and the flow both
 * controllers share: the stored Truck_Route__c for the ordered place pair unless refresh,
 * otherwise Mapbox; the store row saved after the callouts; the static map URL built on each view
 * and never stored. The branching lives here rather than in the controllers for the reason
 * LaneBenchmarkPlaceService gives: RfpLaneController (31) and LaneBenchmarkController (36) sit
 * close to PMD's class complexity budget of 40, and only moving branches to another class lowers
 * a class total.
 */
public with sharing class TripRouteView {
  public static final String NO_COORDINATES = 'This lane has no coordinates.';
  public static final String NO_ROUTE = 'No route was found between these places, even without truck limits.';
  private static final String FOUND = 'Found';
  private static final String NONE_FOUND = 'No route';

  @AuraEnabled
  public String status;
  @AuraEnabled
  public String routeType;
  /** The Miles_Source__c value this route stands for: Truck route, Regular route, No route; null when Unavailable. */
  @AuraEnabled
  public String source;
  @AuraEnabled
  public Decimal miles;
  @AuraEnabled
  public Decimal hours;
  @AuraEnabled
  public List<TruckRoute.Line> routes = new List<TruckRoute.Line>();
  @AuraEnabled
  public String mapUrl;
  @AuraEnabled
  public String message;
  /** Set by RfpLaneController.laneRoute only, and only when the call wrote the lane's miles. */
  @AuraEnabled
  public RFP_Lane__c lane;

  /** A view with no route: status Unavailable and the sentence to show. */
  public static TripRouteView unavailable(String message) {
    TripRouteView view = new TripRouteView();
    view.status = 'Unavailable';
    view.message = message;
    return view;
  }

  /**
   * The route from origin to destination for the default truck profile. A place without an Id or
   * a coordinate makes no callout. storedOrRoute makes the callouts (none when a stored row
   * answers); the store row is saved after them, so the transaction's first DML follows its last
   * callout. A row read from the store is not saved again: nothing about it changed.
   */
  public static TripRouteView routeBetween(
    Pricing_Place__c origin,
    Pricing_Place__c destination,
    Boolean refresh
  ) {
    if (!located(origin) || !located(destination)) {
      return unavailable(NO_COORDINATES);
    }
    TripMilesService.RouteOutcome outcome = TripMilesService.storedOrRoute(
      origin,
      destination,
      TruckRoute.defaultProfile(),
      refresh == true
    );
    if (outcome.toSave != null && outcome.fromStore != true) {
      TripMilesService.save(new List<Truck_Route__c>{ outcome.toSave });
    }
    TripRouteView view = fromResult(outcome.result);
    if (view.status == FOUND) {
      view.mapUrl = RouteMapUrl.build(
        point(origin),
        point(destination),
        view.routes
      );
    }
    return view;
  }

  /** The place a lane end routes from - its Id and coordinates - or null when the end has no place. */
  public static Pricing_Place__c laneEnd(Id placeId, Pricing_Place__c related) {
    if (placeId == null || related == null) {
      return null;
    }
    return new Pricing_Place__c(
      Id = placeId,
      Geolocation__Latitude__s = related.Geolocation__Latitude__s,
      Geolocation__Longitude__s = related.Geolocation__Longitude__s
    );
  }

  /**
   * The lane write a route makes, or null. History miles are billed PC*Miler miles and outrank a
   * route (R75); an unavailable route changes nothing (spec section 7); No route clears the miles
   * and the hours.
   */
  public static RFP_Lane__c laneUpdate(RFP_Lane__c lane, TripRouteView view) {
    if (lane.Miles_Source__c == 'History' || view.source == null) {
      return null;
    }
    return new RFP_Lane__c(
      Id = lane.Id,
      Miles__c = view.miles,
      Miles_Source__c = view.source,
      Route_Hours__c = view.hours
    );
  }

  /** Found needs at least one line; anything that is neither Found nor No route reads as Unavailable. */
  private static TripRouteView fromResult(TruckRoute.Result result) {
    TripRouteView view = new TripRouteView();
    view.status = result.status;
    view.routeType = result.routeType;
    view.routes = result.routes == null
      ? new List<TruckRoute.Line>()
      : result.routes;
    if (result.status == FOUND && !view.routes.isEmpty()) {
      view.source = result.routeType == 'Regular'
        ? 'Regular route'
        : 'Truck route';
      view.miles = view.routes[0].miles;
      view.hours = view.routes[0].hours;
    } else if (result.status == NONE_FOUND) {
      view.source = NONE_FOUND;
      view.message = String.isBlank(result.message)
        ? NO_ROUTE
        : result.message;
    } else {
      view.status = 'Unavailable';
      view.routeType = null;
      view.message = TruckRoute.UNAVAILABLE;
    }
    return view;
  }

  private static Boolean located(Pricing_Place__c place) {
    return place != null &&
      place.Id != null &&
      place.Geolocation__Latitude__s != null &&
      place.Geolocation__Longitude__s != null;
  }

  private static TruckRoute.Point point(Pricing_Place__c place) {
    return new TruckRoute.Point(
      place.Geolocation__Latitude__s,
      place.Geolocation__Longitude__s
    );
  }
}
```

Create `force-app/main/default/classes/TripRouteView.cls-meta.xml`:

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<ApexClass xmlns="http://soap.sforce.com/2006/04/metadata">
    <apiVersion>64.0</apiVersion>
    <status>Active</status>
</ApexClass>
```

`fromResult` normalises what Tasks 2 and 4 return: a Found result without a line, or any status other than Found and No route, becomes `Unavailable` with `TruckRoute.UNAVAILABLE`; a No route result without a message gets `NO_ROUTE`, so `c-route-map` always has a sentence to show.

- [ ] **Step 6: Make `LaneBenchmarkPlaceService.placesByKey` public**

In `force-app/main/default/classes/LaneBenchmarkPlaceService.cls`, replace (lines 174-177):

```apex
  @SuppressWarnings(
    'PMD.ApexCRUDViolation'
  ) // system mode by design (see class comment)
  private static Map<String, Pricing_Place__c> placesByKey(Set<String> keys) {
```

with:

```apex
  /** Places by Key__c with their Id and coordinates, system mode; also LaneBenchmarkController.truckRoute's lookup. */
  @SuppressWarnings(
    'PMD.ApexCRUDViolation'
  ) // system mode by design (see class comment)
  public static Map<String, Pricing_Place__c> placesByKey(Set<String> keys) {
```

The method body is unchanged (`SELECT Key__c, Geolocation__Latitude__s, Geolocation__Longitude__s FROM Pricing_Place__c WHERE Key__c IN :keys`; SOQL always returns `Id`).

- [ ] **Step 7: `RfpLaneController.laneRoute`**

In `force-app/main/default/classes/RfpLaneController.cls`, insert after the closing `  }` of `resolveLaneEnd` (the line before the `/**` that starts "'Pending' only once BOTH ends are resolved"):

```apex
  /**
   * The truck route of one lane (phase 7), for the lane panel; not cacheable, it calls out and
   * saves. The lane is read in user mode, so a lane the caller cannot read is "This lane is not
   * available." TripRouteView.routeBetween makes the callouts and then saves the store row; the
   * lane's miles are written last, in user mode after the FLS strip like every lane save here,
   * unless they come from History (TripRouteView.laneUpdate). view.lane is the re-read lane when
   * it was written, for the table. The lane read and its refusal sit before the try so that no
   * AuraHandledException needs re-throwing: each catch and throw counts toward PMD's class
   * complexity budget, which this class is close to.
   */
  @AuraEnabled
  public static TripRouteView laneRoute(Id laneId, Boolean refresh) {
    List<RFP_Lane__c> lanes = lanesByIds(new List<Id>{ laneId });
    if (lanes.isEmpty()) {
      throw RfpUserError.of(RfpBidAccess.LANE_UNAVAILABLE);
    }
    try {
      RFP_Lane__c stored = lanes[0];
      TripRouteView view = TripRouteView.routeBetween(
        TripRouteView.laneEnd(stored.Origin_Place__c, stored.Origin_Place__r),
        TripRouteView.laneEnd(
          stored.Destination_Place__c,
          stored.Destination_Place__r
        ),
        refresh
      );
      RFP_Lane__c miles = TripRouteView.laneUpdate(stored, view);
      if (miles != null) {
        Database.update(
          Security.stripInaccessible(
              AccessType.UPDATABLE,
              new List<RFP_Lane__c>{ miles }
            )
            .getRecords()[0],
          AccessLevel.USER_MODE
        );
        view.lane = one(laneId);
      }
      return view;
    } catch (Exception e) {
      throw RfpUserError.of(
        'The truck route could not be loaded. ' + RfpUserError.safe(e)
      );
    }
  }
```

`lanesByIds` is the user-mode read with Task 6's `LANE_FIELDS`, so `Origin_Place__r` / `Destination_Place__r` carry the coordinates; an empty result (no share, a deleted lane, a null Id) is the refusal. `one(laneId)` re-reads the written lane with its selected bid attached, as `saveLanePricing` does.

- [ ] **Step 8: `LaneBenchmarkController.truckRoute`**

In `force-app/main/default/classes/LaneBenchmarkController.cls`, insert after the closing `  }` of `mapPreviewUrl` (line 227):

```apex
  /**
   * The truck route between two place keys (phase 7), for the Lane Benchmark map and statistics.
   * Not cacheable: it calls out and saves the Truck_Route__c row. Places are read in system mode
   * like every place lookup on this page. An unknown or blank key has no coordinates, so the view
   * is Unavailable rather than an error: the page asks only after a search that validated both
   * keys. Never writes a lane. No try/catch: this class sat at 36 of PMD's complexity budget of 40
   * before this method, and each catch and throw counts.
   */
  @AuraEnabled
  public static TripRouteView truckRoute(
    String originKey,
    String destinationKey,
    Boolean refresh
  ) {
    Map<String, Pricing_Place__c> places = LaneBenchmarkPlaceService.placesByKey(
      new Set<String>{ originKey, destinationKey }
    );
    return TripRouteView.routeBetween(
      places.get(originKey),
      places.get(destinationKey),
      refresh
    );
  }
```

Measured with PMD 7.15.0 on the finished code: `RfpLaneController` 37 (was 31), `LaneBenchmarkController` 37 (was 36), `TripRouteView` 22, `LaneBenchmarkPlaceService` 35 (unchanged). PMD counts every `if`, loop, ternary, `catch` and `throw` (a `&&` inside an `if` too, not inside a `return`), which is why `laneRoute` reads the lane before its `try` (no `catch (AuraHandledException e) { throw e; }`, worth 2) and `truckRoute` has no `try` at all (a save failure reaches the page as Lightning's generic server error; the page treats any error as no route).

- [ ] **Step 9: Class access and manifest**

In `force-app/main/default/permissionsets/RFP_Tool_User.permissionset-meta.xml`, insert after the `RfpProjectController` class access (lines 75-78, just before `<customPermissions>`):

```xml
    <classAccesses>
        <apexClass>TripRouteView</apexClass>
        <enabled>true</enabled>
    </classAccesses>
```

In `force-app/main/default/permissionsets/Lane_Benchmark_User.permissionset-meta.xml`, insert the same block after the `MapboxGeocoder` class access (lines 27-30, just before the first `<objectPermissions>`).

The README rule (line 563: "Every new `@AuraEnabled` class needs a `classAccesses` entry in `RFP_Tool_User`") covers `TripRouteView`; Lane Benchmark gets it too because `truckRoute` returns it. The platform does not require it for a return type (`LaneSearchResult` has none), so this is the repo's convention, not a fix. The permission sets cannot carry it before this task: a class access to a class that does not exist fails the deploy.

In `manifest/package.xml`, add `        <members>TripRouteView</members>` on the line directly above `        <name>ApexClass</name>`.

- [ ] **Step 10: Deploy the classes, permission sets and tests**

Run: `sf project deploy start -o sandbox --source-dir force-app/main/default/classes/TripRouteView.cls --source-dir force-app/main/default/classes/RfpLaneController.cls --source-dir force-app/main/default/classes/LaneBenchmarkController.cls --source-dir force-app/main/default/classes/LaneBenchmarkPlaceService.cls --source-dir force-app/main/default/classes/RfpLaneControllerTest.cls --source-dir force-app/main/default/classes/LaneBenchmarkControllerTest.cls --source-dir force-app/main/default/classes/RfpSecurityTest.cls --source-dir force-app/main/default/permissionsets/RFP_Tool_User.permissionset-meta.xml --source-dir force-app/main/default/permissionsets/Lane_Benchmark_User.permissionset-meta.xml -l RunSpecifiedTests -t RfpLaneControllerTest -t LaneBenchmarkControllerTest -t RfpSecurityTest -t LaneBenchmarkPlaceServiceTest --async --json | python3 -c "import json,sys; s=sys.stdin.read(); print(json.loads(s[s.index('{'):])['result']['id'])"`

Expected: a deploy id. Poll, repeating while the status is `Pending` or `InProgress`:

Run: `sf project deploy report -o sandbox --job-id <id> -w 2 --json | python3 -c "import json,sys; s=sys.stdin.read(); j=json.loads(s[s.index('{'):]); r=j.get('result') or {}; det=r.get('details') or {}; cf=det.get('componentFailures', []); cf=cf if isinstance(cf, list) else [cf]; tf=(det.get('runTestResult') or {}).get('failures', []); tf=tf if isinstance(tf, list) else [tf]; print(r.get('id'), r.get('status', j.get('name')), 'tests', r.get('numberTestsCompleted'), '/', r.get('numberTestsTotal'), 'failures', r.get('numberTestErrors')); [print(str(d.get('fullName')) + ': ' + str(d.get('problem'))) for d in cf[:4]]; [print(f.get('name'), f.get('methodName'), '->', str(f.get('message'))[:200]) for f in tf]"`

Expected: `Succeeded tests 39 / 39 failures 0` (`RfpLaneControllerTest` 8 + 9, `LaneBenchmarkControllerTest` 6 + 3, `RfpSecurityTest` 11, `LaneBenchmarkPlaceServiceTest` 2; the org's 75 % per deployed class holds: every branch of `TripRouteView` and `laneRoute` except its final `catch` is exercised). Record the id. Fix the code, not the assertion, unless the assertion contradicts the spec. Known failure shapes:

- `aReadSharedPricerRefreshesARouteAColleagueStored` errors with `INSUFFICIENT_ACCESS_OR_READONLY` (or `The truck route could not be loaded. Upsert failed`): Task 4's `TripMilesService.save` no longer goes through its `private without sharing class Store`. Fix Task 4's class and redeploy it with `-t TripMilesServiceTest`. Do not add a second `Store` and do not change this test.
- `aReadSharedPricerOpensALaneRoute` fails on `lane.Miles__c` (null) or `view.lane.Miles_Source__c`: `RFP_Tool_User` lacks edit (or read) on `RFP_Lane__c.Miles__c`, `Miles_Source__c`, `Route_Hours__c` and `Security.stripInaccessible` dropped them. Fix the Task 1 field permissions and redeploy the permission set.
- Any test reporting `Unavailable` where `Found` is expected, with `mock.calls` 0: DML ran before the callout in that test or in `routeBetween` (check that `TripMilesService.storedOrRoute` does no DML) or the token is blank (`MapboxHttp.token()` must return `tokenOverride` when set).
- `laneRouteWithNoRouteStoresItAndClearsTheMiles` sees 1 call: Task 2's fallback does not re-ask on `NoRoute`; fix `MapboxTruckRoute`.

- [ ] **Step 11: PMD on the whole tree**

Run: `/private/tmp/pmd_install/pmd-bin-7.15.0/bin/pmd check --dir force-app --rulesets config/pmd-ruleset.xml --minimum-priority 3 --format text --fail-on-violation; echo "pmd exit $?"`

Expected: no violation lines, `pmd exit 0`. Class totals measured on this code: `RfpLaneController` 37, `LaneBenchmarkController` 37, `TripRouteView` 22, `RfpSecurityTest` 39, `RfpLaneControllerTest` 28, `LaneBenchmarkControllerTest` 23 (budget 40). If PMD reports one of these over budget, move the branch into `TripRouteView` (or a test into another test class) rather than suppressing.

- [ ] **Step 12: Commit**

```bash
git add force-app/main/default/classes/TripRouteView.cls force-app/main/default/classes/TripRouteView.cls-meta.xml force-app/main/default/classes/RfpLaneController.cls force-app/main/default/classes/LaneBenchmarkController.cls force-app/main/default/classes/LaneBenchmarkPlaceService.cls force-app/main/default/classes/RfpLaneControllerTest.cls force-app/main/default/classes/LaneBenchmarkControllerTest.cls force-app/main/default/classes/RfpSecurityTest.cls force-app/main/default/permissionsets/RFP_Tool_User.permissionset-meta.xml force-app/main/default/permissionsets/Lane_Benchmark_User.permissionset-meta.xml manifest/package.xml
git commit -m "Open truck routes on demand from the lane panel and Lane Benchmark"
```

Prettier may reformat the staged Apex through lint-staged (expected). Never stage `.vscode/settings.json` or a `* 2.*` file.

#### Contract notes (Task 7)

1. **`TripRouteView` carries static helpers** (`unavailable`, `routeBetween`, `laneEnd`, `laneUpdate`, private `fromResult`, `located`, `point`) and two constants (`NO_COORDINATES`, `NO_ROUTE`) besides the contract's fields. Reason: PMD class complexity. `RfpLaneController` was 31 and `LaneBenchmarkController` 36 (measured, budget 40); PMD counts every `if`, ternary, `catch` and `throw`, so a first version with the try/catch wrappers the other methods use measured 39 and 39, one short of failing. Both controllers now measure 37. No contract name changed.
2. **`source` was undefined.** It is the `Miles_Source__c` value the route stands for: `Truck route` | `Regular route` (Found), `No route`, null (Unavailable), for both methods. The lane's own source (e.g. `History`) is `view.lane.Miles_Source__c` or the table row. Tasks 9 and 10 read it this way.
3. **`view.lane` is set only when `laneRoute` wrote the lane** (not for History lanes, Unavailable routes or lanes without coordinates); `mapUrl`, `miles` and `hours` are set only when Found (a No route or Unavailable view has no map, so Lane Benchmark keeps its radius preview, spec section 6). Task 9's panel shows the miles of `view.lane` when it is present; the table catches up on its next merge (Task 9 note 1).
4. **Security tests moved.** `RfpSecurityTest` measured 38; each new runAs test adds 2, so three would make 45 and fail PMD. Only the stranger check (`LANE_UNAVAILABLE`, +1, class at 39) lands there, inside the existing no-access test; the Read-shared pricer tests are in `RfpLaneControllerTest`, the Lane Benchmark user test in `LaneBenchmarkControllerTest`. The roster does not change. `RfpSecurityTest` is left at 39 of 40: the next phase that adds a test method there must split the class first.
5. **Refreshing a colleague's route.** `TripMilesService.save` writes through Task 4's `without sharing` inner `Store` (Task 4 note 2), so a pricer can refresh a route a colleague stored on the Public Read Only object. `aReadSharedPricerRefreshesARouteAColleagueStored` guards it. `routeBetween` never saves a row that came from the store.
6. **`truckRoute` with an unknown or blank key** returns `Unavailable` with `NO_COORDINATES` instead of throwing (contract silent; the page calls it only after a search that validated both keys). It has no `try/catch` (complexity), and it reads places through `LaneBenchmarkPlaceService.placesByKey`, made public, instead of a second place query in the controller.
7. **`laneRoute` reads the lane with `lanesByIds` before its `try`** (not `one`, whose `[0]` would throw a ListException instead of the refusal). A query exception from that read is not wrapped in a sentence; the RFP Tool user holds every field it reads.
8. **Class access for `TripRouteView`** is added here to both permission sets, following README line 563 (every `@AuraEnabled` class gets a `classAccesses` entry); Task 1 cannot add it because the class does not exist yet. The platform does not need it (`LaneSearchResult` has none); it is kept for the convention, and Task 1 note 3 and the README Security rows (Task 11) say so.
9. **Line numbers** in `RfpLaneController.cls` shift in Task 6 (`LANE_FIELDS`), so Step 7 anchors on method names.

---

### Task 8: Shared LWC — distance unit, unit toggle, message channel and route map

**Files:**

- Create: `force-app/main/default/messageChannels/Distance_Unit.messageChannel-meta.xml`
- Create: `force-app/main/default/lwc/distanceUnit/distanceUnit.js`, `force-app/main/default/lwc/distanceUnit/distanceUnit.js-meta.xml`, `force-app/main/default/lwc/distanceUnit/__tests__/distanceUnit.test.js`
- Create: `force-app/main/default/lwc/distanceUnitToggle/distanceUnitToggle.html`, `force-app/main/default/lwc/distanceUnitToggle/distanceUnitToggle.js`, `force-app/main/default/lwc/distanceUnitToggle/distanceUnitToggle.js-meta.xml`, `force-app/main/default/lwc/distanceUnitToggle/__tests__/distanceUnitToggle.test.js`
- Create: `force-app/main/default/lwc/routeMap/routeMap.html`, `force-app/main/default/lwc/routeMap/routeMap.js`, `force-app/main/default/lwc/routeMap/routeMap.css`, `force-app/main/default/lwc/routeMap/routeMap.js-meta.xml`, `force-app/main/default/lwc/routeMap/__tests__/routeMap.test.js`
- Modify: `manifest/package.xml` — LightningComponentBundle members `distanceUnit`, `distanceUnitToggle`, `routeMap` after `rfpBulkBar` (line 55, before `<name>LightningComponentBundle</name>` at line 56); a new `<types>` block with member `Distance_Unit` and name `LightningMessageChannel` after the StaticResource block (after line 62).

**Interfaces:**

- Consumes: `lightning/messageService` (`MessageContext`, `APPLICATION_SCOPE`, `publish`, `subscribe`, `unsubscribe`; the sfdx-lwc-jest stub makes each a `jest.fn()` and `MessageContext` a test wire adapter), `@salesforce/messageChannel/Distance_Unit__c` (in Jest the default import is the string `"Distance_Unit__c"`), the `TripRouteView` shape from Task 7 as plain JSON (`status`, `routeType`, `source`, `miles`, `hours`, `routes[]` of `TruckRoute.Line` — `miles`, `hours`; `polyline5` is not `@AuraEnabled` and never reaches the page — `mapUrl`, `message`, `lane`). No Apex import in this task; nothing here depends on Task 7 being deployed.
- Produces:
  - `c/distanceUnit` (module, no template): `UNIT_KEY = 'tripMiles.unit.v1'`, `KM_PER_MILE = 1.609344`, `readUnit()` → `'mi' | 'km'` (default `'mi'`, never throws), `writeUnit(unit)` (ignores anything but `'mi'`/`'km'`, never throws), `formatDistance(miles, unit)` → `'1,234 mi'` | `'1,986 km'` | `''` (en-CA, 0 decimals), `perDistance(amount, miles, unit)` → Number with 2 decimals or `null`.
  - Message channel `Distance_Unit__c` (file `Distance_Unit.messageChannel-meta.xml`, manifest member `Distance_Unit`), payload `{ unit: 'mi' | 'km' }`. Subscribers use `APPLICATION_SCOPE`.
  - `c-distance-unit-toggle` (no `@api`): buttons `data-id="unit-mi"` / `data-id="unit-km"`, `aria-pressed` `"true"`/`"false"`, class `slds-button slds-button_brand` on the active one and `slds-button slds-button_neutral` on the other; a click on the other unit calls `writeUnit` and `publish(messageContext, Distance_Unit__c, { unit })`; it also subscribes, so two toggles on one page stay in step.
  - `c-route-map`: `@api view` (TripRouteView or `null`), `@api loading` (Boolean), `@api unit` (`'mi'`/`'km'`, starts from `readUnit()`), `@api hazmat` (Boolean, default false; see Contract notes). DOM hooks for later tasks' tests: `data-id="spinner"`, `"image"`, `"message"`, `"legend-title"`, `"legend-line"`, `"hazmat"`, `"refresh"`. Fires `CustomEvent('refreshroute')` (no detail, does not bubble) from the Refresh route button; the button is disabled while `loading`.
  - Later tasks (9, 10) that show distances subscribe with this exact pattern (copy from `distanceUnitToggle.js`): `@wire(MessageContext) messageContext;` · `unit = readUnit();` · in `connectedCallback`: `this.unitSubscription = subscribe(this.messageContext, DISTANCE_UNIT, (m) => { if (m && (m.unit === "mi" || m.unit === "km")) this.unit = m.unit; }, { scope: APPLICATION_SCOPE });` · in `disconnectedCallback`: `if (this.unitSubscription) { unsubscribe(this.unitSubscription); } this.unitSubscription = null;` (the Jest stub's `subscribe` returns `undefined`).

- [ ] **Step 1: Write the failing test for the `distanceUnit` module**

Create `force-app/main/default/lwc/distanceUnit/__tests__/distanceUnit.test.js`:

```js
import {
  UNIT_KEY,
  KM_PER_MILE,
  readUnit,
  writeUnit,
  formatDistance,
  perDistance
} from "c/distanceUnit";

describe("distanceUnit", () => {
  beforeEach(() => {
    try {
      window.localStorage.clear();
    } catch {
      // ignore
    }
  });

  afterEach(() => {
    jest.restoreAllMocks();
  });

  it("names the storage key and the exact conversion", () => {
    expect(UNIT_KEY).toBe("tripMiles.unit.v1");
    expect(KM_PER_MILE).toBe(1.609344);
  });

  it("formats whole miles and kilometres the Canadian English way", () => {
    expect(formatDistance(1234, "mi")).toBe("1,234 mi");
    expect(formatDistance(1234, "km")).toBe("1,986 km");
    expect(formatDistance(1, "km")).toBe("2 km");
    expect(formatDistance(1234.6, "mi")).toBe("1,235 mi");
    expect(formatDistance("512.4", "mi")).toBe("512 mi");
    expect(formatDistance(0, "mi")).toBe("0 mi");
  });

  it("treats an unknown unit as miles and a missing distance as blank", () => {
    expect(formatDistance(100, "yards")).toBe("100 mi");
    expect(formatDistance(100, undefined)).toBe("100 mi");
    expect(formatDistance(null, "mi")).toBe("");
    expect(formatDistance(undefined, "km")).toBe("");
    expect(formatDistance("", "mi")).toBe("");
    expect(formatDistance("abc", "mi")).toBe("");
  });

  it("divides an amount by the distance in the chosen unit, to the cent", () => {
    expect(perDistance(2500, 1000, "mi")).toBe(2.5);
    expect(perDistance(1000, 3, "mi")).toBe(333.33);
    expect(perDistance(1609.344, 1, "km")).toBe(1000);
    expect(perDistance(1000, 1234, "km")).toBe(0.5);
    expect(perDistance(2345.67, 512.4, "mi")).toBe(4.58);
    expect(perDistance("2500", "1000", "km")).toBe(1.55);
  });

  it("returns null without a positive amount and distance", () => {
    expect(perDistance(1000, 0, "mi")).toBeNull();
    expect(perDistance(1000, -5, "mi")).toBeNull();
    expect(perDistance(0, 100, "mi")).toBeNull();
    expect(perDistance(null, 100, "mi")).toBeNull();
    expect(perDistance(1000, null, "km")).toBeNull();
    expect(perDistance("", 100, "mi")).toBeNull();
    expect(perDistance(1000, "abc", "mi")).toBeNull();
  });

  it("remembers the chosen unit and ignores anything else", () => {
    expect(readUnit()).toBe("mi");
    writeUnit("km");
    expect(readUnit()).toBe("km");
    expect(window.localStorage.getItem("tripMiles.unit.v1")).toBe("km");
    writeUnit("yards");
    expect(readUnit()).toBe("km");
    window.localStorage.setItem("tripMiles.unit.v1", "furlongs");
    expect(readUnit()).toBe("mi");
  });

  it("falls back to miles when storage throws on read", () => {
    window.localStorage.setItem("tripMiles.unit.v1", "km");
    jest.spyOn(Storage.prototype, "getItem").mockImplementation(() => {
      throw new Error("blocked");
    });
    expect(readUnit()).toBe("mi");
  });

  it("swallows a blocked write", () => {
    const spy = jest
      .spyOn(Storage.prototype, "setItem")
      .mockImplementation(() => {
        throw new Error("blocked");
      });
    expect(() => writeUnit("km")).not.toThrow();
    expect(spy).toHaveBeenCalledWith("tripMiles.unit.v1", "km");
    spy.mockRestore();
    expect(readUnit()).toBe("mi");
  });
});
```

- [ ] **Step 2: Run it to see it fail**

Run: `npm run test:unit -- force-app/main/default/lwc/distanceUnit`
Expected: FAIL, `Cannot find module 'c/distanceUnit'`.

- [ ] **Step 3: Write the module**

Create `force-app/main/default/lwc/distanceUnit/distanceUnit.js`:

```js
export const UNIT_KEY = "tripMiles.unit.v1";
export const KM_PER_MILE = 1.609344;

const UNITS = ["mi", "km"];
const WHOLE = new Intl.NumberFormat("en-CA", { maximumFractionDigits: 0 });

function known(unit) {
  return unit === "km" ? "km" : "mi";
}

function toNumber(value) {
  if (value === null || value === undefined || value === "") {
    return null;
  }
  const n = Number(value);
  return Number.isFinite(n) ? n : null;
}

/** Half-up on the absolute value, like marginMath and Apex HALF_UP. */
function cents(value) {
  const rounded = Math.round(Math.abs(value) * 100) / 100;
  return value < 0 ? -rounded : rounded;
}

/** The unit this browser last chose; miles when nothing (or nothing usable) is stored. */
export function readUnit() {
  try {
    return known(window.localStorage.getItem(UNIT_KEY));
  } catch {
    return "mi";
  }
}

export function writeUnit(unit) {
  if (!UNITS.includes(unit)) {
    return;
  }
  try {
    window.localStorage.setItem(UNIT_KEY, unit);
  } catch {
    // private window or blocked storage: the choice just is not remembered
  }
}

/** "1,234 mi" or "1,986 km" from a distance in miles; "" when there is no distance. */
export function formatDistance(miles, unit) {
  const n = toNumber(miles);
  if (n === null) {
    return "";
  }
  const u = known(unit);
  const value = u === "km" ? n * KM_PER_MILE : n;
  return `${WHOLE.format(value)} ${u}`;
}

/** An amount per mile or per km, to the cent; null without a positive amount and distance. */
export function perDistance(amount, miles, unit) {
  const a = toNumber(amount);
  const m = toNumber(miles);
  if (a === null || m === null || !(a > 0) || !(m > 0)) {
    return null;
  }
  const distance = known(unit) === "km" ? m * KM_PER_MILE : m;
  return cents(a / distance);
}
```

Create `force-app/main/default/lwc/distanceUnit/distanceUnit.js-meta.xml`:

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<LightningComponentBundle xmlns="http://soap.sforce.com/2006/04/metadata">
  <apiVersion>64.0</apiVersion>
  <isExposed>false</isExposed>
</LightningComponentBundle>
```

- [ ] **Step 4: Run the module test to see it pass**

Run: `npm run test:unit -- force-app/main/default/lwc/distanceUnit`
Expected: PASS, `Tests: 8 passed, 8 total`. `formatDistance(1234, "km")` is `1,986 km` because 1,234 × 1.609344 = 1,985.93; `perDistance(1609.344, 1, "km")` is exactly `1000` (1 mi = 1.609344 km). If `1,986` comes out as `1 986`, Node is running without full ICU (Node 20 ships it by default): run `node -e "console.log(new Intl.NumberFormat('en-CA').format(1986))"` and fix the Node install, not the test.

- [ ] **Step 5: Create the message channel and write the failing toggle test**

Create `force-app/main/default/messageChannels/Distance_Unit.messageChannel-meta.xml` (the file name has no `__c`; components import it as `@salesforce/messageChannel/Distance_Unit__c`):

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<LightningMessageChannel xmlns="http://soap.sforce.com/2006/04/metadata">
  <masterLabel>Distance Unit</masterLabel>
  <isExposed>true</isExposed>
  <description
  >The distance unit (mi or km) chosen on the page, shared by every component that shows trip miles.</description>
  <lightningMessageFields>
    <fieldName>unit</fieldName>
    <description>mi or km</description>
  </lightningMessageFields>
</LightningMessageChannel>
```

Create `force-app/main/default/lwc/distanceUnitToggle/__tests__/distanceUnitToggle.test.js` (the sfdx-lwc-jest stub of `lightning/messageService` makes `publish`, `subscribe` and `unsubscribe` shared `jest.fn()`s, so every test clears them; the channel import is the plain string `"Distance_Unit__c"` under Jest, and the wired `messageContext` is `undefined`, which is why the calls are checked by argument position rather than with `expect.anything()`):

```js
import { createElement } from "lwc";
import DistanceUnitToggle from "c/distanceUnitToggle";
import {
  APPLICATION_SCOPE,
  publish,
  subscribe,
  unsubscribe
} from "lightning/messageService";
import DISTANCE_UNIT from "@salesforce/messageChannel/Distance_Unit__c";

const flush = () => Promise.resolve().then(() => Promise.resolve());
const field = (el, id) => el.shadowRoot.querySelector(`[data-id="${id}"]`);
const pressed = (el, id) => field(el, id).getAttribute("aria-pressed");

let onMessage;

async function mount() {
  const el = createElement("c-distance-unit-toggle", {
    is: DistanceUnitToggle
  });
  document.body.appendChild(el);
  await flush();
  return el;
}

describe("c-distance-unit-toggle", () => {
  beforeEach(() => {
    jest.clearAllMocks();
    window.localStorage.clear();
    onMessage = null;
    subscribe.mockImplementation((context, channel, handler) => {
      onMessage = handler;
      return { id: "sub-1" };
    });
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("starts on miles and subscribes to the channel application-wide", async () => {
    const el = await mount();
    expect(pressed(el, "unit-mi")).toBe("true");
    expect(pressed(el, "unit-km")).toBe("false");
    expect(field(el, "unit-mi").className).toBe(
      "slds-button slds-button_brand"
    );
    expect(field(el, "unit-km").className).toBe(
      "slds-button slds-button_neutral"
    );
    expect(subscribe).toHaveBeenCalledTimes(1);
    expect(subscribe.mock.calls[0][1]).toBe(DISTANCE_UNIT);
    expect(subscribe.mock.calls[0][3]).toEqual({ scope: APPLICATION_SCOPE });
  });

  it("starts from the unit this browser remembered", async () => {
    window.localStorage.setItem("tripMiles.unit.v1", "km");
    const el = await mount();
    expect(pressed(el, "unit-km")).toBe("true");
    expect(pressed(el, "unit-mi")).toBe("false");
  });

  it("switches to km, remembers it and publishes the unit", async () => {
    const el = await mount();
    field(el, "unit-km").click();
    await flush();
    expect(pressed(el, "unit-km")).toBe("true");
    expect(pressed(el, "unit-mi")).toBe("false");
    expect(field(el, "unit-km").className).toBe(
      "slds-button slds-button_brand"
    );
    expect(window.localStorage.getItem("tripMiles.unit.v1")).toBe("km");
    expect(publish).toHaveBeenCalledTimes(1);
    expect(publish.mock.calls[0][1]).toBe(DISTANCE_UNIT);
    expect(publish.mock.calls[0][2]).toEqual({ unit: "km" });
  });

  it("does not publish when the active unit is clicked again", async () => {
    const el = await mount();
    field(el, "unit-mi").click();
    await flush();
    expect(publish).not.toHaveBeenCalled();
    expect(window.localStorage.getItem("tripMiles.unit.v1")).toBeNull();
  });

  it("follows a unit published elsewhere on the page without publishing back", async () => {
    const el = await mount();
    onMessage({ unit: "km" });
    await flush();
    expect(pressed(el, "unit-km")).toBe("true");
    onMessage({ unit: "leagues" });
    onMessage(null);
    await flush();
    expect(pressed(el, "unit-km")).toBe("true");
    expect(publish).not.toHaveBeenCalled();
  });

  it("unsubscribes when removed from the page", async () => {
    const el = await mount();
    document.body.removeChild(el);
    expect(unsubscribe).toHaveBeenCalledWith({ id: "sub-1" });
  });
});
```

- [ ] **Step 6: Run it to see it fail**

Run: `npm run test:unit -- force-app/main/default/lwc/distanceUnitToggle`
Expected: FAIL, `Cannot find module 'c/distanceUnitToggle'`.

- [ ] **Step 7: Write the toggle**

Create `force-app/main/default/lwc/distanceUnitToggle/distanceUnitToggle.html`:

```html
<template>
  <div class="slds-button-group" role="group" aria-label="Distance unit">
    <button
      type="button"
      data-id="unit-mi"
      class={miClass}
      aria-pressed={miPressed}
      title="Miles"
      onclick={handleMi}
    >
      mi
    </button>
    <button
      type="button"
      data-id="unit-km"
      class={kmClass}
      aria-pressed={kmPressed}
      title="Kilometres"
      onclick={handleKm}
    >
      km
    </button>
  </div>
</template>
```

Create `force-app/main/default/lwc/distanceUnitToggle/distanceUnitToggle.js` (`@wire(MessageContext)` is the documented way for a component to get its message context; `createMessageContext` is for code outside a component and would need a manual `releaseMessageContext`):

```js
import { LightningElement, wire } from "lwc";
import {
  APPLICATION_SCOPE,
  MessageContext,
  publish,
  subscribe,
  unsubscribe
} from "lightning/messageService";
import DISTANCE_UNIT from "@salesforce/messageChannel/Distance_Unit__c";
import { readUnit, writeUnit } from "c/distanceUnit";

const BUTTON_ON = "slds-button slds-button_brand";
const BUTTON_OFF = "slds-button slds-button_neutral";

export default class DistanceUnitToggle extends LightningElement {
  @wire(MessageContext) messageContext;
  unit = readUnit();
  unitSubscription = null;

  connectedCallback() {
    if (!this.unitSubscription) {
      this.unitSubscription = subscribe(
        this.messageContext,
        DISTANCE_UNIT,
        (message) => this.handleMessage(message),
        { scope: APPLICATION_SCOPE }
      );
    }
  }

  disconnectedCallback() {
    if (this.unitSubscription) {
      unsubscribe(this.unitSubscription);
    }
    this.unitSubscription = null;
  }

  get miClass() {
    return this.unit === "mi" ? BUTTON_ON : BUTTON_OFF;
  }
  get kmClass() {
    return this.unit === "km" ? BUTTON_ON : BUTTON_OFF;
  }
  get miPressed() {
    return this.unit === "mi" ? "true" : "false";
  }
  get kmPressed() {
    return this.unit === "km" ? "true" : "false";
  }

  /** Another toggle on the page changed the unit: follow it, without publishing back. */
  handleMessage(message) {
    const unit = message && message.unit;
    if (unit === "mi" || unit === "km") {
      this.unit = unit;
    }
  }

  handleMi() {
    this.pick("mi");
  }
  handleKm() {
    this.pick("km");
  }

  pick(unit) {
    if (unit === this.unit) {
      return;
    }
    this.unit = unit;
    writeUnit(unit);
    publish(this.messageContext, DISTANCE_UNIT, { unit });
  }
}
```

Create `force-app/main/default/lwc/distanceUnitToggle/distanceUnitToggle.js-meta.xml`:

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<LightningComponentBundle xmlns="http://soap.sforce.com/2006/04/metadata">
  <apiVersion>64.0</apiVersion>
  <isExposed>false</isExposed>
</LightningComponentBundle>
```

- [ ] **Step 8: Run the toggle test to see it pass**

Run: `npm run test:unit -- force-app/main/default/lwc/distanceUnitToggle`
Expected: PASS, `Tests: 6 passed, 6 total`.

- [ ] **Step 9: Write the failing route map test**

Create `force-app/main/default/lwc/routeMap/__tests__/routeMap.test.js`:

```js
import { createElement } from "lwc";
import RouteMap from "c/routeMap";

const flush = () => Promise.resolve().then(() => Promise.resolve());
const field = (el, id) => el.shadowRoot.querySelector(`[data-id="${id}"]`);
const text = (el, id) => field(el, id).textContent.trim();
const legendLines = (el) =>
  [...el.shadowRoot.querySelectorAll('[data-id="legend-line"]')].map((n) =>
    n.textContent.trim()
  );

const MAP_URL =
  "https://api.mapbox.com/styles/v1/mapbox/streets-v12/static/pin-s-a+0070d2(-73.5674,45.5019),pin-s-b+2e844a(-79.3832,43.6532)/auto/600x300@2x?padding=40&access_token=pk.test";

const TRUCK = {
  status: "Found",
  routeType: "Truck",
  source: "Truck route",
  miles: 1234,
  hours: 21.5,
  routes: [
    { miles: 1234, hours: 21.5 },
    { miles: 1260.4, hours: 22 },
    { miles: 1301, hours: 23.2 }
  ],
  mapUrl: MAP_URL,
  message: null
};

const REGULAR = {
  ...TRUCK,
  routeType: "Regular",
  routes: [{ miles: 1234, hours: 21.5 }]
};

async function mount(props = {}) {
  const el = createElement("c-route-map", { is: RouteMap });
  Object.assign(el, props);
  document.body.appendChild(el);
  await flush();
  return el;
}

describe("c-route-map", () => {
  beforeEach(() => {
    window.localStorage.clear();
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("draws the map and a truck legend with every route in miles", async () => {
    const el = await mount({ view: TRUCK, unit: "mi" });
    expect(field(el, "image").src).toBe(MAP_URL);
    expect(field(el, "image").alt).toBe("Truck route from A to B on a map");
    expect(text(el, "legend-title")).toBe("Truck route");
    expect(legendLines(el)).toEqual([
      "Route 1: 1,234 mi · 21.5 h",
      "Route 2: 1,260 mi · 22.0 h",
      "Route 3: 1,301 mi · 23.2 h"
    ]);
    const swatches = [...el.shadowRoot.querySelectorAll(".swatch")].map(
      (n) => n.className
    );
    expect(swatches).toEqual([
      "swatch swatch-1",
      "swatch swatch-2",
      "swatch swatch-3"
    ]);
    expect(field(el, "message")).toBeNull();
    expect(field(el, "spinner")).toBeNull();
    expect(field(el, "hazmat")).toBeNull();
  });

  it("labels a regular route and follows the unit it is given", async () => {
    const el = await mount({ view: REGULAR, unit: "km" });
    expect(text(el, "legend-title")).toBe(
      "Regular route — truck limits could not be met"
    );
    expect(legendLines(el)).toEqual(["Route 1: 1,986 km · 21.5 h"]);
    el.unit = "mi";
    await flush();
    expect(legendLines(el)).toEqual(["Route 1: 1,234 mi · 21.5 h"]);
  });

  it("starts from the unit this browser remembered when the parent passes none", async () => {
    window.localStorage.setItem("tripMiles.unit.v1", "km");
    const el = await mount({ view: REGULAR });
    expect(el.unit).toBe("km");
    expect(legendLines(el)).toEqual(["Route 1: 1,986 km · 21.5 h"]);
  });

  it("shows no more than three routes and a dash for a route without miles", async () => {
    const el = await mount({
      view: {
        ...TRUCK,
        routes: [
          { miles: null, hours: null },
          { miles: 10, hours: 0.2 },
          { miles: 11, hours: 0.3 },
          { miles: 12, hours: 0.4 }
        ]
      },
      unit: "mi"
    });
    expect(legendLines(el)).toEqual([
      "Route 1: —",
      "Route 2: 10 mi · 0.2 h",
      "Route 3: 11 mi · 0.3 h"
    ]);
  });

  it("says the truck route is unavailable, with the server's message when there is one", async () => {
    const el = await mount({
      view: {
        status: "Unavailable",
        routeType: null,
        routes: [],
        mapUrl: null,
        message: null
      }
    });
    expect(text(el, "message")).toBe(
      "The truck route is not available right now."
    );
    expect(field(el, "image")).toBeNull();
    expect(field(el, "legend-title")).toBeNull();
    expect(field(el, "refresh")).not.toBeNull();
    el.view = {
      status: "Unavailable",
      routeType: null,
      routes: [],
      mapUrl: null,
      message: "This lane has no coordinates."
    };
    await flush();
    expect(text(el, "message")).toBe("This lane has no coordinates.");
  });

  it("says when no route exists between the places", async () => {
    const el = await mount({
      view: {
        status: "No route",
        routeType: null,
        routes: [],
        mapUrl: null,
        message: null
      }
    });
    expect(text(el, "message")).toBe(
      "No route was found between these places, even without truck limits."
    );
    expect(field(el, "legend-title")).toBeNull();
  });

  it("shows a spinner and blocks Refresh route while loading", async () => {
    const el = await mount({ view: TRUCK, loading: true });
    expect(field(el, "spinner")).not.toBeNull();
    expect(field(el, "refresh").disabled).toBe(true);
    const seen = [];
    el.addEventListener("refreshroute", (e) => seen.push(e));
    field(el, "refresh").click();
    expect(seen).toHaveLength(0);
    el.loading = false;
    await flush();
    expect(field(el, "spinner")).toBeNull();
    expect(field(el, "refresh").disabled).toBe(false);
  });

  it("shows a spinner before the first view arrives", async () => {
    const el = await mount({ view: null, loading: true });
    expect(field(el, "spinner")).not.toBeNull();
    expect(field(el, "refresh")).toBeNull();
    expect(field(el, "image")).toBeNull();
  });

  it("asks its parent to refresh the route", async () => {
    const el = await mount({ view: TRUCK });
    const seen = [];
    el.addEventListener("refreshroute", (e) => seen.push(e));
    const refresh = field(el, "refresh");
    expect(refresh.label).toBe("Refresh route");
    refresh.click();
    expect(seen).toHaveLength(1);
    expect(seen[0].bubbles).toBe(false);
    expect(seen[0].detail).toBeNull();
  });

  it("notes that a hazmat lane gets the same route", async () => {
    const el = await mount({ view: TRUCK, hazmat: true });
    expect(text(el, "hazmat")).toContain("Mapbox has no hazmat routing");
    el.hazmat = false;
    await flush();
    expect(field(el, "hazmat")).toBeNull();
  });

  it("renders nothing without a view", async () => {
    const el = await mount();
    expect(field(el, "image")).toBeNull();
    expect(field(el, "message")).toBeNull();
    expect(field(el, "legend-title")).toBeNull();
    expect(field(el, "refresh")).toBeNull();
    expect(field(el, "spinner")).toBeNull();
  });
});
```

- [ ] **Step 10: Run it to see it fail**

Run: `npm run test:unit -- force-app/main/default/lwc/routeMap`
Expected: FAIL, `Cannot find module 'c/routeMap'`.

- [ ] **Step 11: Write the route map**

Create `force-app/main/default/lwc/routeMap/routeMap.html`:

```html
<template>
  <div class="route-map slds-is-relative">
    <template lwc:if={loading}>
      <lightning-spinner
        data-id="spinner"
        size="small"
        alternative-text="Loading the truck route"
      ></lightning-spinner>
    </template>
    <template lwc:if={hasImage}>
      <img data-id="image" class="route-image" src={mapUrl} alt={imageAlt} />
    </template>
    <template lwc:if={message}>
      <p data-id="message" class="slds-text-color_weak slds-m-vertical_x-small">
        {message}
      </p>
    </template>
    <template lwc:if={hasLegend}>
      <div class="slds-m-top_x-small">
        <p data-id="legend-title" class="slds-text-title_bold">{legendTitle}</p>
        <ul class="slds-m-top_xx-small">
          <template for:each={legend} for:item="line">
            <li key={line.key} class="legend-row">
              <span class={line.swatchClass} aria-hidden="true"></span>
              <span data-id="legend-line">{line.text}</span>
            </li>
          </template>
        </ul>
        <template lwc:if={showHazmat}>
          <p
            data-id="hazmat"
            class="slds-text-body_small slds-text-color_weak slds-m-top_xx-small"
          >
            Hazmat lane: Mapbox has no hazmat routing, so this is the route any
            truck would get.
          </p>
        </template>
      </div>
    </template>
    <template lwc:if={hasView}>
      <lightning-button
        data-id="refresh"
        class="slds-m-top_x-small"
        label="Refresh route"
        icon-name="utility:refresh"
        disabled={loading}
        onclick={handleRefresh}
      ></lightning-button>
    </template>
  </div>
</template>
```

Create `force-app/main/default/lwc/routeMap/routeMap.js` (the component does not subscribe to the channel: its parent owns the unit and passes it down; when the parent passes nothing usable, the setter falls back to `readUnit()`):

```js
import { LightningElement, api } from "lwc";
import { formatDistance, readUnit } from "c/distanceUnit";

const TRUCK_TITLE = "Truck route";
const REGULAR_TITLE = "Regular route — truck limits could not be met";
const UNAVAILABLE = "The truck route is not available right now.";
const NO_ROUTE =
  "No route was found between these places, even without truck limits.";
const MAX_ROUTES = 3;
const HOURS = new Intl.NumberFormat("en-CA", {
  minimumFractionDigits: 1,
  maximumFractionDigits: 1
});

function hoursText(hours) {
  if (hours === null || hours === undefined || hours === "") {
    return "";
  }
  const n = Number(hours);
  return Number.isFinite(n) ? `${HOURS.format(n)} h` : "";
}

export default class RouteMap extends LightningElement {
  /** TripRouteView from RfpLaneController.laneRoute or LaneBenchmarkController.truckRoute. */
  @api view = null;
  @api loading = false;
  /** True on a hazmat RFP lane: the legend says the route ignores hazmat rules. */
  @api hazmat = false;
  _unit = readUnit();

  /** 'mi' or 'km'; anything else falls back to the unit this browser remembered. */
  @api
  get unit() {
    return this._unit;
  }
  set unit(value) {
    this._unit = value === "mi" || value === "km" ? value : readUnit();
  }

  get hasView() {
    return Boolean(this.view);
  }
  get status() {
    return this.view ? this.view.status : null;
  }
  get found() {
    return this.status === "Found";
  }
  get mapUrl() {
    return this.view ? this.view.mapUrl : null;
  }
  get hasImage() {
    return Boolean(this.mapUrl);
  }
  get imageAlt() {
    return this.found
      ? `${this.legendTitle} from A to B on a map`
      : "Origin A and destination B on a map";
  }
  get message() {
    if (this.status === "Unavailable") {
      return this.view.message || UNAVAILABLE;
    }
    if (this.status === "No route") {
      return this.view.message || NO_ROUTE;
    }
    return null;
  }
  get routes() {
    const routes = this.found && this.view.routes;
    return Array.isArray(routes) ? routes.slice(0, MAX_ROUTES) : [];
  }
  get hasLegend() {
    return this.routes.length > 0;
  }
  get legendTitle() {
    return this.view && this.view.routeType === "Regular"
      ? REGULAR_TITLE
      : TRUCK_TITLE;
  }
  get legend() {
    return this.routes.map((route, i) => {
      const distance = formatDistance(route && route.miles, this._unit) || "—";
      const hours = hoursText(route && route.hours);
      return {
        key: `route-${i + 1}`,
        swatchClass: `swatch swatch-${i + 1}`,
        text: `Route ${i + 1}: ${distance}${hours ? ` · ${hours}` : ""}`
      };
    });
  }
  get showHazmat() {
    return this.hasLegend && Boolean(this.hazmat);
  }

  handleRefresh() {
    if (this.loading) {
      return;
    }
    this.dispatchEvent(new CustomEvent("refreshroute"));
  }
}
```

Create `force-app/main/default/lwc/routeMap/routeMap.css` (the swatches repeat the `RouteMapUrl` overlay colours: main route `0070d2`, alternatives `f59e0b` and `706e6b`; the minimum height keeps the absolutely positioned spinner visible before the first view arrives):

```css
.route-map {
  min-height: 3rem;
}
.route-image {
  display: block;
  max-width: 100%;
  border-radius: 4px;
}
.legend-row {
  display: flex;
  align-items: center;
  gap: 0.5rem;
}
.swatch {
  display: inline-block;
  width: 1rem;
  border-radius: 2px;
}
.swatch-1 {
  height: 0.3125rem;
  background: #0070d2;
}
.swatch-2 {
  height: 0.1875rem;
  background: #f59e0b;
}
.swatch-3 {
  height: 0.1875rem;
  background: #706e6b;
}
```

Create `force-app/main/default/lwc/routeMap/routeMap.js-meta.xml`:

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<LightningComponentBundle xmlns="http://soap.sforce.com/2006/04/metadata">
  <apiVersion>64.0</apiVersion>
  <isExposed>false</isExposed>
</LightningComponentBundle>
```

- [ ] **Step 12: Run the route map test to see it pass**

Run: `npm run test:unit -- force-app/main/default/lwc/routeMap`
Expected: PASS, `Tests: 11 passed, 11 total`.

- [ ] **Step 13: Add the bundles and the channel to the manifest**

In `manifest/package.xml`, insert after `        <members>rfpBulkBar</members>` (line 55, just before `<name>LightningComponentBundle</name>`):

```xml
        <members>distanceUnit</members>
        <members>distanceUnitToggle</members>
        <members>routeMap</members>
```

Then insert the message channel block, once, after the `</types>` that closes the StaticResource block (line 62; Task 1 adds no message channel, Task 1 note 2), between that line and `<!-- Apex -->` (line 63):

```xml
    <types>
        <members>Distance_Unit</members>
        <name>LightningMessageChannel</name>
    </types>
```

The member is `Distance_Unit`, not `Distance_Unit__c`: the Metadata API name is the file's base name without `__c` (`sf project generate manifest` on the channel file lists `<members>Distance_Unit</members>` under `LightningMessageChannel`, checked while planning).

Run: `grep -n "distanceUnit\|routeMap\|Distance_Unit\|LightningMessageChannel" manifest/package.xml`

Expected: four member lines (`distanceUnit`, `distanceUnitToggle`, `routeMap`, `Distance_Unit`) and one `<name>LightningMessageChannel</name>` line, with the three bundle names above `<name>LightningComponentBundle</name>`.

- [ ] **Step 14: ESLint, Prettier and the whole Jest suite**

Run: `npx eslint force-app/main/default/lwc/distanceUnit force-app/main/default/lwc/distanceUnitToggle force-app/main/default/lwc/routeMap; echo "eslint exit $?"`

Expected: no output lines before `eslint exit 0`.

Run: `npx prettier --check force-app/main/default/messageChannels force-app/main/default/lwc/distanceUnit force-app/main/default/lwc/distanceUnitToggle force-app/main/default/lwc/routeMap manifest/package.xml`

Expected: `All matched files use Prettier code style!`

Run: `npm run test:unit 2>&1 | grep -E "^(Tests|Test Suites):"`

Expected: `Test Suites: 39 passed, 39 total` and `Tests: 334 passed, 334 total` (36 suites / 309 tests on `phase-7/trip-miles` before this phase, measured 2026-09-14; Tasks 1–7 add no Jest; this task adds 3 suites and 8 + 6 + 11 = 25 tests). If an earlier task did change the Jest count, the rule is: the previous total plus 3 suites and 25 tests, all passing.

- [ ] **Step 15: Deploy the channel and the three bundles**

The Task 9 and Task 10 components import `@salesforce/messageChannel/Distance_Unit__c` and `c/routeMap`, so these must be in the org first. No Apex is deployed, so no test run is needed.

Run: `sf project deploy start -o sandbox -l NoTestRun --source-dir force-app/main/default/messageChannels --source-dir force-app/main/default/lwc/distanceUnit --source-dir force-app/main/default/lwc/distanceUnitToggle --source-dir force-app/main/default/lwc/routeMap --async --json | python3 -c "import json,sys; s=sys.stdin.read(); r=json.loads(s[s.index('{'):]); print(r['result']['id'])"`

Expected: one deploy id (`0Af…`). Record it.

Run (replace `<id>`): `sf project deploy report -o sandbox --job-id <id> -w 2 --json | python3 -c "import json,sys; s=sys.stdin.read(); r=json.loads(s[s.index('{'):]); res=r.get('result') or {}; cf=(res.get('details') or {}).get('componentFailures') or []; cf=cf if isinstance(cf, list) else [cf]; print(res.get('status', r.get('name')), res.get('numberComponentsDeployed'), '/', res.get('numberComponentsTotal'), [f.get('fullName') + ': ' + str(f.get('problem')) for f in cf][:3])"`

Expected: `Succeeded 4 / 4 []` (the channel and three bundles). `InProgress` or a client-side wait timeout means run the same report command again. A failure naming `Distance_Unit__c` on `distanceUnitToggle` ("Unable to find Lightning Message Channel") means the channel file is not under `force-app/main/default/messageChannels/` or its name is wrong; fix the path, not the import.

Run: `sf data query -o sandbox --use-tooling-api -q "SELECT DeveloperName FROM LightningComponentBundle WHERE DeveloperName IN ('distanceUnit','distanceUnitToggle','routeMap') ORDER BY DeveloperName" --json | python3 -c "import json,sys; s=sys.stdin.read(); print([x['DeveloperName'] for x in json.loads(s[s.index('{'):])['result']['records']])"`

Expected: `['distanceUnit', 'distanceUnitToggle', 'routeMap']`. (The toggle bundle compiles only when the channel it imports exists, so its presence also proves the channel deployed.)

- [ ] **Step 16: Commit**

```bash
git add force-app/main/default/messageChannels/Distance_Unit.messageChannel-meta.xml force-app/main/default/lwc/distanceUnit force-app/main/default/lwc/distanceUnitToggle force-app/main/default/lwc/routeMap manifest/package.xml
git status --short
git commit -m "Add the shared distance unit, its toggle and channel, and the route map"
```

Expected: `git status --short` shows the new files and `manifest/package.xml` staged (`A` / `M` in the first column); `.vscode/settings.json` and every `* 2.*` file stay unstaged. lint-staged runs Prettier, ESLint and the related Jest tests on commit; the commit succeeds.

#### Contract notes (Task 8)

1. **Manifest member `Distance_Unit`, import `Distance_Unit__c`.** The contract says the manifest gains the message channel; the Metadata API member is the file's base name `Distance_Unit` (checked with `sf project generate manifest` on a scratch copy), while components import `@salesforce/messageChannel/Distance_Unit__c`. Step 13 adds the block, once (Task 1 adds none).
2. **`@wire(MessageContext)` instead of `createMessageContext`.** The wire is the documented pattern inside a component, releases itself when the component is removed, and is what the sfdx-lwc-jest stub supports (`MessageContext` is a test wire adapter). `createMessageContext` would need a manual `releaseMessageContext`.
3. **`c-route-map` does not subscribe to the channel.** The contract gives it `@api unit`; the parent (Task 9 panel, Task 10 page) subscribes and passes the unit down, so one owner holds the value. The `unit` setter falls back to `readUnit()` when a parent passes nothing usable.
4. **Messages when Apex sends none.** `TripRouteView.fromResult` (Task 7) sets `TripRouteView.NO_ROUTE` on every No route view; `c-route-map` shows `view.message` when present, else the same sentence, `No route was found between these places, even without truck limits.`; for `Unavailable` it shows `view.message`, else `The truck route is not available right now.` (the same sentence as `TruckRoute.UNAVAILABLE`).
5. **`@api hazmat` (not in the contract).** Spec §7 says the legend tells a hazmat lane that the route ignores hazmat rules. `c-route-map` gains `@api hazmat` (default `false`) and shows `data-id="hazmat"` under the legend when true. **Task 9 must pass `hazmat={lane.Hazmat__c}`** (Checkbox on `RFP_Lane__c`) on the panel's `c-route-map`; Lane Benchmark has no hazmat value and leaves it unset.
6. **The toggle also subscribes** (APPLICATION_SCOPE) so two toggles on one page stay in step; it follows a received unit without publishing back, and clicking the active unit publishes nothing, so there is no publish loop. It has no `@api` properties.
7. **`perDistance` returns `null` unless both the amount and the miles are above zero** (a zero cost per mile is not shown); results round half-up to the cent like `marginMath`.
8. **Legend details.** At most 3 routes are listed (Mapbox's count is ambiguous, spec §2); a route without miles shows `Route N: —`; hours always carry one decimal (`22.0 h`); the swatch colours match `RouteMapUrl`'s overlays. The Refresh route button appears once a view exists, is disabled while `loading`, and the handler also ignores clicks while loading; `refreshroute` does not bubble, so parents listen with `onrefreshroute` on `c-route-map` itself.
9. **Jest for later tasks.** The `lightning/messageService` stub is applied automatically; a test that mounts a component containing `c-distance-unit-toggle` needs no `jest.mock`. Tests that drive a subscription use `subscribe.mockImplementation((ctx, channel, handler) => { captured = handler; return { id: "sub-1" }; })` and `jest.clearAllMocks()` in `beforeEach`, as in `distanceUnitToggle.test.js`.

---

### Task 9: RFP workbench UI — unit toggle, Miles column, lane panel route, Excel trip columns

**Files:**

- Modify: `force-app/main/default/lwc/rfpToolbar/rfpToolbar.html` (new column after the Include RFP bids column, lines 64–73)
- Modify: `force-app/main/default/lwc/rfpToolbar/rfpToolbar.js` (class comment, lines 13–19)
- Modify: `force-app/main/default/lwc/rfpToolbar/__tests__/rfpToolbar.test.js` (one test after line 93)
- Modify: `force-app/main/default/lwc/rfpLaneTable/rfpLaneTable.js` (imports lines 1–2; miles helpers after line 83; unit state and lifecycle around lines 112–138; header getter after line 148; `viewRows` lines 157–203)
- Modify: `force-app/main/default/lwc/rfpLaneTable/rfpLaneTable.html` (header cell after line 27; body cell after lines 101–103)
- Modify: `force-app/main/default/lwc/rfpLaneTable/__tests__/rfpLaneTable.test.js` (imports lines 1–2; `afterEach` lines 93–97; three tests after line 234)
- Modify: `force-app/main/default/lwc/rfpLanePanel/rfpLanePanel.js` (imports lines 1–19; helpers lines 21–25; `lane` setter lines 34–58; fields lines 60–77; getters after line 102; `syncFromLane` lines 104–115; `loadRoute` after line 189; per-distance getters after line 272; handlers after line 305)
- Modify: `force-app/main/default/lwc/rfpLanePanel/rfpLanePanel.html` (miles line after line 12; per-distance line after line 74; route map after line 159)
- Modify: `force-app/main/default/lwc/rfpLanePanel/__tests__/rfpLanePanel.test.js` (imports and mocks lines 1–27; `beforeEach`/`afterEach` lines 104–114; a `describe("trip miles and route")` block before the last line, 513)
- Modify: `force-app/main/default/lwc/rfpWorkbook/rfpWorkbook.js` (import line 1; `OUR_COLUMNS` lines 3–16; `tripCells` after line 47; lane row lines 137–153)
- Modify: `force-app/main/default/lwc/rfpWorkbook/__tests__/rfpWorkbook.test.js` (positional assertions lines 64–65; one test after line 184)
- Modify: `force-app/main/default/lwc/rfpTool/__tests__/rfpTool.test.js` (one `jest.mock` for `RfpLaneController.laneRoute` after line 73, keeping that file's "every Apex module the workbench tree imports is listed" convention)
- Unchanged, verified in Step 17: `force-app/main/default/lwc/rfpTool/rfpTool.js` (554 lines) and `force-app/main/default/lwc/rfpTool/rfpTool.html`

**Interfaces:**

- Consumes:
  - Task 1: `RFP_Lane__c.Miles__c`, `Miles_Source__c` (`History`, `Truck route`, `Regular route`, `Approx`, `No route`, `No coordinates`), `Route_Hours__c`.
  - Task 6: `RfpLaneController.LANE_FIELDS` carries the three fields, so every lane from `getLanes`, `saveLanePricing`, `resolveLaneEnd` and `RfpHistoryController.loadHistory` has them.
  - Task 7: `@salesforce/apex/RfpLaneController.laneRoute` — `laneRoute({ laneId, refresh })` → `TripRouteView` `{ status, routeType, source, miles, hours, routes: [{ miles, hours }], mapUrl, message, lane }`.
  - Task 8: `c/distanceUnit` (`readUnit`, `writeUnit`, `formatDistance`, `perDistance`, `KM_PER_MILE`), `c-distance-unit-toggle` (publishes `{ unit }`), `c-route-map` (`@api view`, `@api loading`, `@api unit`, `@api hazmat`; fires `refreshroute`), message channel `@salesforce/messageChannel/Distance_Unit__c`.
  - Existing: `lightning/messageService` (`MessageContext`, `APPLICATION_SCOPE`, `subscribe`, `unsubscribe`, used with Task 8's subscriber pattern), `c/rfpPricing.parseMoney`.
- Produces:
  - `c-rfp-toolbar`: a `c-distance-unit-toggle` (`data-id="distance-unit"`) in the column right after Include RFP bids.
  - `c-rfp-lane-table`: a Miles column after History — header `{distanceHeader}` ("Miles" / "Km"), cell `data-id="miles"` with `title` = the source or the reason, tag `data-id="miles-tag"` (`truck`, `route`, `approx.`; none for History); "—" when there are no miles.
  - `c-rfp-lane-panel`: `data-id="lane-miles"` under the title; `data-id="cost-per-distance"` and `data-id="sell-per-distance"` under the prices; `c-route-map` (`view={routeView}`, `loading={loadingRoute}`, `unit={unit}`, `hazmat={laneHazmat}`) loaded through `laneRoute({ laneId, refresh: false })` on open and `laneRoute({ laneId, refresh: true })` on `refreshroute`.
  - `c/rfpWorkbook`: `OUR_COLUMNS` gains `Miles`, `Km`, `Miles source`, `Route hours`, `Cost per mile`, `Sell per mile` after `Transit days` (18 columns).
  - No new event reaches `c-rfp-tool` (see Contract notes).

**Before you start:** Tasks 6, 7 and 8 are committed (the three lane fields in `LANE_FIELDS`, `RfpLaneController.laneRoute`, `c/distanceUnit`, `c-distance-unit-toggle`, `c-route-map` and `Distance_Unit__c` exist locally). `c-rfp-tool` renders the toolbar, table and panel for real in its own Jest suite, so that suite runs at Steps 12 and 17 as well as in the full run. Run each Jest command on its own; one suite takes about 20–25 s once warm, but a cold cache can take several minutes — start any Jest run with `run_in_background` (redirect to a log) and poll the log rather than waiting on it.

- [ ] **Step 1: Toolbar — write the failing test**

In `force-app/main/default/lwc/rfpToolbar/__tests__/rfpToolbar.test.js`, add after the test "renders the Include RFP bids checkbox after the unit, checked by default" (after line 93):

```js
  it("puts the distance unit toggle in the column right after Include RFP bids", () => {
    const el = mount();
    const toggle = field(el, "distance-unit");
    expect(toggle).not.toBeNull();
    expect(toggle.tagName.toLowerCase()).toBe("c-distance-unit-toggle");
    // Every control has its own column, so the toggle's column is the one
    // straight after the checkbox's.
    const bidsColumn = field(el, "include-bids").parentElement;
    expect(bidsColumn.nextElementSibling.contains(toggle)).toBe(true);
  });
```

- [ ] **Step 2: Run it and watch it fail**

Run: `npm run test:unit -- force-app/main/default/lwc/rfpToolbar 2>&1 | grep -E "✕|^(Tests|Test Suites):"`

Expected: `✕ puts the distance unit toggle in the column right after Include RFP bids`, `Tests: 1 failed, 7 passed, 8 total` (the toggle is not in the template yet, so `field(el, "distance-unit")` is `null`).

- [ ] **Step 3: Toolbar — add the toggle**

In `force-app/main/default/lwc/rfpToolbar/rfpToolbar.html`, directly after the Include RFP bids column (the `<div class="slds-col">` that holds `data-id="include-bids"`, lines 64–73), insert:

```html
    <div class="slds-col">
      <c-distance-unit-toggle data-id="distance-unit"></c-distance-unit-toggle>
    </div>
```

In `force-app/main/default/lwc/rfpToolbar/rfpToolbar.js`, replace the class comment (lines 13–19):

```js
/**
 * The workbench toolbar row: the two navigation buttons, the four history
 * settings, the "Include RFP bids" toggle, the three history buttons and the
 * Excel export. It holds no state of its own — every control reports back to
 * rfpTool, which owns the settings and runs the calls, the same split
 * c/rfpBulkBar already uses for the bulk actions.
 */
```

with:

```js
/**
 * The workbench toolbar row: the two navigation buttons, the four history
 * settings, the "Include RFP bids" toggle, the mi | km distance toggle, the
 * three history buttons and the Excel export. It holds no state of its own —
 * every control reports back to rfpTool, which owns the settings and runs the
 * calls, the same split c/rfpBulkBar already uses for the bulk actions. The
 * distance toggle is the exception: it publishes on Distance_Unit__c itself,
 * so the table, the lane panel and Lane Benchmark follow it without rfpTool.
 */
```

- [ ] **Step 4: Run the toolbar suite to pass**

Run: `npm run test:unit -- force-app/main/default/lwc/rfpToolbar 2>&1 | grep -E "✕|^(Tests|Test Suites):"`

Expected: no `✕` line, `Tests: 8 passed, 8 total`.

- [ ] **Step 5: Lane table — write the failing tests**

In `force-app/main/default/lwc/rfpLaneTable/__tests__/rfpLaneTable.test.js`:

Replace the two import lines (lines 1–2):

```js
import { createElement } from "lwc";
import RfpLaneTable from "c/rfpLaneTable";
```

with:

```js
import { createElement } from "lwc";
import { subscribe, unsubscribe } from "lightning/messageService";
import DISTANCE_UNIT from "@salesforce/messageChannel/Distance_Unit__c";
import RfpLaneTable from "c/rfpLaneTable";
import { writeUnit } from "c/distanceUnit";
```

Replace the `afterEach` of the top-level `describe` (lines 93–97):

```js
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });
```

with:

```js
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    // readUnit() reads the real jsdom localStorage: a km test must not leak.
    window.localStorage.clear();
    jest.clearAllMocks();
  });
```

After the helpers block that ends with `const key = (target, k, extra = {}) => ...` (line 90), add:

```js
/** What Lightning Message Service does on a publish: every subscriber hears it. */
const publishUnit = (unit) =>
  subscribe.mock.calls
    .filter((call) => call[1] === DISTANCE_UNIT)
    .forEach((call) => call[2]({ unit }));

/** The Miles cell split into its distance text, its tag and its tooltip. */
function milesOf(row) {
  const cell = row.querySelector('[data-id="miles"]');
  const tag = cell.querySelector('[data-id="miles-tag"]');
  return {
    text: cell.textContent.replace(tag ? tag.textContent : "", "").trim(),
    tag: tag ? tag.textContent.trim() : null,
    title: cell.title
  };
}

const headerTexts = (el) =>
  [...el.shadowRoot.querySelectorAll("thead th")].map((th) =>
    th.textContent.trim()
  );
```

After the test "says so when a Done snapshot found loads but no median" (after line 234), add:

```js
  describe("trip miles", () => {
    const tripLane = (id, fields) => ({ ...RESOLVED_LANE, Id: id, ...fields });

    it("shows a Miles column after History, tagged by where the miles came from", async () => {
      const el = await mount({
        lanes: [
          tripLane("a0L00000011", {
            Miles__c: 1234,
            Miles_Source__c: "History"
          }),
          tripLane("a0L00000012", {
            Miles__c: 1260.4,
            Miles_Source__c: "Truck route",
            Route_Hours__c: 21.5
          }),
          tripLane("a0L00000013", {
            Miles__c: 1302,
            Miles_Source__c: "Regular route",
            Route_Hours__c: 22
          }),
          tripLane("a0L00000014", {
            Miles__c: 1190,
            Miles_Source__c: "Approx"
          })
        ]
      });
      const headers = headerTexts(el);
      expect(headers[headers.indexOf("History") + 1]).toBe("Miles");
      const rows = rowsOf(el);
      // Billed miles are the reference, so they carry no tag.
      expect(milesOf(rows[0])).toEqual({
        text: "1,234 mi",
        tag: null,
        title: "Median billed miles of the loads the history matched"
      });
      expect(milesOf(rows[1])).toEqual({
        text: "1,260 mi",
        tag: "truck",
        title: "Mapbox truck route · 21.5 h"
      });
      expect(milesOf(rows[2])).toEqual({
        text: "1,302 mi",
        tag: "route",
        title: "Mapbox regular route: the truck limits could not be met · 22.0 h"
      });
      expect(milesOf(rows[3])).toEqual({
        text: "1,190 mi",
        tag: "approx.",
        title:
          "Straight-line distance between the two places, adjusted for roads"
      });
    });

    it("shows a dash with the reason when a lane has no miles", async () => {
      const el = await mount({
        lanes: [
          tripLane("a0L00000021", {
            Miles__c: null,
            Miles_Source__c: "No route"
          }),
          tripLane("a0L00000022", {
            Miles__c: null,
            Miles_Source__c: "No coordinates"
          }),
          // never run: RESOLVED_LANE carries no trip fields at all
          tripLane("a0L00000023", {})
        ]
      });
      const rows = rowsOf(el);
      expect(milesOf(rows[0])).toEqual({
        text: "—",
        tag: null,
        title: "Mapbox found no route between the two places"
      });
      expect(milesOf(rows[1])).toEqual({
        text: "—",
        tag: null,
        title: "A place on this lane is missing or has no coordinates"
      });
      expect(milesOf(rows[2])).toEqual({
        text: "—",
        tag: null,
        title: "No miles yet: load history or open the lane"
      });
    });

    it("starts from the stored unit, follows the channel and lets go of it when removed", async () => {
      writeUnit("km");
      subscribe.mockReturnValueOnce({ id: "unit-sub" });
      const el = await mount({
        lanes: [
          tripLane("a0L00000031", {
            Miles__c: 1234,
            Miles_Source__c: "Truck route",
            Route_Hours__c: 21.5
          })
        ]
      });
      expect(headerTexts(el)).toContain("Km");
      expect(milesOf(rowsOf(el)[0]).text).toBe("1,986 km");
      expect(subscribe.mock.calls.some((c) => c[1] === DISTANCE_UNIT)).toBe(
        true
      );

      publishUnit("mi");
      await flush();
      expect(headerTexts(el)).toContain("Miles");
      expect(milesOf(rowsOf(el)[0]).text).toBe("1,234 mi");

      // anything but mi or km is ignored
      publishUnit("furlongs");
      await flush();
      expect(milesOf(rowsOf(el)[0]).text).toBe("1,234 mi");

      document.body.removeChild(el);
      expect(unsubscribe).toHaveBeenCalledWith({ id: "unit-sub" });
    });
  });
```

- [ ] **Step 6: Run the table suite and watch the new tests fail**

Run: `npm run test:unit -- force-app/main/default/lwc/rfpLaneTable 2>&1 | grep -E "✕|^(Tests|Test Suites):"`

Expected: the three `trip miles` tests marked `✕` (the header after History is still `Cost (CAD)`, and `milesOf` throws `Cannot read properties of null (reading 'querySelector')` because there is no `data-id="miles"` cell yet), `Tests: 3 failed, 23 passed, 26 total`.

- [ ] **Step 7: Lane table — the Miles column**

In `force-app/main/default/lwc/rfpLaneTable/rfpLaneTable.js`:

Replace the imports (lines 1–2):

```js
import { LightningElement, api } from "lwc";
import { inlineEdit } from "c/rfpPricing";
```

with:

```js
import { LightningElement, api, wire } from "lwc";
import {
  APPLICATION_SCOPE,
  MessageContext,
  subscribe,
  unsubscribe
} from "lightning/messageService";
import DISTANCE_UNIT from "@salesforce/messageChannel/Distance_Unit__c";
import { inlineEdit } from "c/rfpPricing";
import { readUnit, formatDistance } from "c/distanceUnit";
```

After the `historyTitle` function (it ends at line 83, just before `export default class RfpLaneTable`), add:

```js
/** The small tag after a lane's miles; billed History miles need none. */
const MILES_TAGS = {
  History: "",
  "Truck route": "truck",
  "Regular route": "route",
  Approx: "approx."
};

/** The tooltip on a lane's miles: where they came from. */
const MILES_TITLES = {
  History: "Median billed miles of the loads the history matched",
  "Truck route": "Mapbox truck route",
  "Regular route": "Mapbox regular route: the truck limits could not be met",
  Approx: "Straight-line distance between the two places, adjusted for roads"
};

/** The tooltip on "—": why the lane has no miles. */
const NO_MILES_TITLES = {
  "No route": "Mapbox found no route between the two places",
  "No coordinates": "A place on this lane is missing or has no coordinates"
};
const NO_MILES_YET = "No miles yet: load history or open the lane";

/**
 * The Miles cell in the chosen unit: the distance and its tag, or "—" with the
 * reason when the lane has no miles (No route, No coordinates, never run).
 */
function milesCell(lane, unit) {
  const source = lane.Miles_Source__c || "";
  const known = Object.prototype.hasOwnProperty.call(MILES_TAGS, source);
  if (!known || !(Number(lane.Miles__c) > 0)) {
    return {
      milesText: "—",
      milesTag: "",
      milesTitle: NO_MILES_TITLES[source] || NO_MILES_YET
    };
  }
  const hours =
    Number(lane.Route_Hours__c) > 0
      ? ` · ${Number(lane.Route_Hours__c).toFixed(1)} h`
      : "";
  return {
    milesText: formatDistance(lane.Miles__c, unit),
    milesTag: MILES_TAGS[source],
    milesTitle: `${MILES_TITLES[source]}${hours}`
  };
}
```

After the field `refocus = null; // the { laneId, field } cell to hand focus back to` (line 116) and before `renderedCallback()`, add:

```js
  /** "mi" or "km"; every distance on the page follows Distance_Unit__c. */
  unit = readUnit();
  @wire(MessageContext) messageContext;
  unitSubscription = null;

  connectedCallback() {
    if (!this.unitSubscription) {
      this.unitSubscription = subscribe(
        this.messageContext,
        DISTANCE_UNIT,
        (message) => this.handleUnit(message),
        { scope: APPLICATION_SCOPE }
      );
    }
  }

  /** The workbench drops the table when it leaves the lanes view. */
  disconnectedCallback() {
    if (this.unitSubscription) {
      unsubscribe(this.unitSubscription);
    }
    this.unitSubscription = null;
  }

  handleUnit(message) {
    const unit = message && message.unit;
    if (unit === "mi" || unit === "km") {
      this.unit = unit;
    }
  }
```

After the `hasLanes` getter (lines 146–148), add:

```js
  /** The column reads in the unit its cells are shown in. */
  get distanceHeader() {
    return this.unit === "km" ? "Km" : "Miles";
  }
```

In `viewRows`, replace:

```js
      histText: historyText(l),
      histTitle: historyTitle(l),
```

with:

```js
      histText: historyText(l),
      histTitle: historyTitle(l),
      ...milesCell(l, this.unit),
```

In `force-app/main/default/lwc/rfpLaneTable/rfpLaneTable.html`:

Replace the History header cell (line 27):

```html
          <th scope="col">History</th>
```

with:

```html
          <th scope="col">History</th>
          <th scope="col" class="w-8">{distanceHeader}</th>
```

Replace the History body cell (lines 101–103):

```html
            <td data-id="hist" class="slds-cell-wrap" title={r.histTitle}>
              {r.histText}
            </td>
```

with:

```html
            <td data-id="hist" class="slds-cell-wrap" title={r.histTitle}>
              {r.histText}
            </td>
            <td data-id="miles" class="slds-cell-wrap" title={r.milesTitle}>
              {r.milesText}
              <template lwc:if={r.milesTag}>
                <span
                  data-id="miles-tag"
                  class="slds-badge slds-m-left_xx-small"
                  >{r.milesTag}</span
                >
              </template>
            </td>
```

- [ ] **Step 8: Run the table suite to pass**

Run: `npm run test:unit -- force-app/main/default/lwc/rfpLaneTable 2>&1 | grep -E "✕|^(Tests|Test Suites):"`

Expected: no `✕` line, `Tests: 26 passed, 26 total`.

- [ ] **Step 9: Lane panel — write the failing tests**

In `force-app/main/default/lwc/rfpLanePanel/__tests__/rfpLanePanel.test.js`:

Replace the imports (lines 1–5):

```js
import { createElement } from "lwc";
import RfpLanePanel from "c/rfpLanePanel";
import getBids from "@salesforce/apex/RfpBidController.getBids";
import saveBid from "@salesforce/apex/RfpBidController.saveBid";
import search from "@salesforce/apex/LaneBenchmarkController.search";
```

with:

```js
import { createElement } from "lwc";
import { subscribe, unsubscribe } from "lightning/messageService";
import DISTANCE_UNIT from "@salesforce/messageChannel/Distance_Unit__c";
import RfpLanePanel from "c/rfpLanePanel";
import getBids from "@salesforce/apex/RfpBidController.getBids";
import saveBid from "@salesforce/apex/RfpBidController.saveBid";
import search from "@salesforce/apex/LaneBenchmarkController.search";
import laneRoute from "@salesforce/apex/RfpLaneController.laneRoute";
import { writeUnit } from "c/distanceUnit";
```

Directly after the `LaneBenchmarkController.search` mock (the `jest.mock(...)` that follows the imports for `search`), add:

```js
jest.mock(
  "@salesforce/apex/RfpLaneController.laneRoute",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
```

After the `CHEAP_BID` constant (it ends just before `const field = ...`), add:

```js
/** LANE as laneRoute re-reads it after writing the truck route's miles. */
const ROUTED_LANE = {
  ...LANE,
  Miles__c: 1234,
  Miles_Source__c: "Truck route",
  Route_Hours__c: 21.5
};

/** A TripRouteView as RfpLaneController.laneRoute returns it (polyline5 is not @AuraEnabled). */
const ROUTE_VIEW = {
  status: "Found",
  routeType: "Truck",
  miles: 1234,
  hours: 21.5,
  routes: [
    { miles: 1234, hours: 21.5 },
    { miles: 1260.2, hours: 22.1 }
  ],
  mapUrl:
    "https://api.mapbox.com/styles/v1/mapbox/streets-v12/static/pin-s-a+0070d2(-73.5674,45.5019)/auto/600x300@2x?padding=40&access_token=pk.test",
  message: null,
  lane: ROUTED_LANE
};

/** What Lightning Message Service does on a publish: every subscriber hears it. */
const publishUnit = (unit) =>
  subscribe.mock.calls
    .filter((call) => call[1] === DISTANCE_UNIT)
    .forEach((call) => call[2]({ unit }));
```

After `const field = (el, id) => ...` (the line after the constants), add:

```js
const textOf = (el, id) => field(el, id).textContent.trim();
```

Replace the top-level `beforeEach`/`afterEach` (lines 104–114):

```js
  beforeEach(() => {
    getBids.mockResolvedValue([]);
    saveBid.mockResolvedValue({ Id: "a0B00000009" });
    search.mockResolvedValue(HISTORY);
  });
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });
```

with:

```js
  beforeEach(() => {
    getBids.mockResolvedValue([]);
    saveBid.mockResolvedValue({ Id: "a0B00000009" });
    search.mockResolvedValue(HISTORY);
    // No stored route unless a test says so: the earlier tests are about pricing.
    laneRoute.mockResolvedValue(null);
  });
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    // readUnit() reads the real jsdom localStorage: a km test must not leak.
    window.localStorage.clear();
    jest.clearAllMocks();
  });
```

Before the last line of the file (the `});` that closes `describe("c-rfp-lane-panel")`), add:

```js
  describe("trip miles and route", () => {
    const map = (el) => el.shadowRoot.querySelector("c-route-map");

    it("asks for the stored route on open and hands it to the route map", async () => {
      laneRoute.mockResolvedValue(ROUTE_VIEW);
      const el = await mount();
      await flush();
      expect(laneRoute).toHaveBeenCalledTimes(1);
      expect(laneRoute).toHaveBeenCalledWith({
        laneId: "a0L00000001",
        refresh: false
      });
      expect(map(el).view).toEqual(ROUTE_VIEW);
      expect(map(el).loading).toBe(false);
      expect(map(el).unit).toBe("mi");
      // The lane on screen had no miles; the copy laneRoute wrote and re-read has.
      expect(textOf(el, "lane-miles")).toBe("1,234 mi · truck route · 21.5 h");
      // The miles line sits under the heading, never inside its name.
      expect(el.shadowRoot.querySelector("h2").textContent.trim()).toBe(
        "Montreal, QC → Toronto, ON"
      );
    });

    it("shows the route map loading until the route arrives", async () => {
      let release;
      laneRoute.mockReturnValue(
        new Promise((resolve) => {
          release = resolve;
        })
      );
      const el = await mount();
      expect(map(el).loading).toBe(true);
      expect(map(el).view).toBeNull();
      release(ROUTE_VIEW);
      await flush();
      await flush();
      expect(map(el).loading).toBe(false);
      expect(map(el).view.routes.length).toBe(2);
    });

    it("asks Mapbox again when the route map asks for a refresh", async () => {
      laneRoute.mockResolvedValue(ROUTE_VIEW);
      const el = await mount();
      await flush();
      const regular = {
        ...ROUTE_VIEW,
        routeType: "Regular",
        miles: 1302,
        hours: 22,
        routes: [{ miles: 1302, hours: 22 }],
        lane: {
          ...ROUTED_LANE,
          Miles__c: 1302,
          Miles_Source__c: "Regular route",
          Route_Hours__c: 22
        }
      };
      laneRoute.mockResolvedValue(regular);
      map(el).dispatchEvent(new CustomEvent("refreshroute"));
      await flush();
      await flush();
      expect(laneRoute).toHaveBeenCalledTimes(2);
      expect(laneRoute.mock.calls[1][0]).toEqual({
        laneId: "a0L00000001",
        refresh: true
      });
      expect(map(el).view.routeType).toBe("Regular");
      expect(textOf(el, "lane-miles")).toBe("1,302 mi · regular route · 22.0 h");
    });

    it("asks for no route while an end is unresolved", async () => {
      const el = await mount({
        lane: { ...LANE, Destination_Place__r: undefined }
      });
      expect(laneRoute).not.toHaveBeenCalled();
      expect(map(el)).toBeNull();
      expect(field(el, "lane-miles")).toBeNull();
      expect(field(el, "cost-per-distance")).toBeNull();
    });

    it("drops a route that lands after the panel moved to another lane", async () => {
      let release;
      laneRoute.mockReturnValueOnce(
        new Promise((resolve) => {
          release = resolve;
        })
      );
      const el = await mount();
      laneRoute.mockResolvedValue({
        status: "No route",
        routeType: null,
        miles: null,
        hours: null,
        routes: [],
        mapUrl: null,
        message: null,
        lane: {
          ...LANE,
          Id: "a0L00000002",
          Miles__c: null,
          Miles_Source__c: "No route",
          Route_Hours__c: null
        }
      });
      el.lane = { ...LANE, Id: "a0L00000002" };
      await flush();
      await flush();
      release(ROUTE_VIEW);
      await flush();
      await flush();
      expect(laneRoute.mock.calls.map((c) => c[0])).toEqual([
        { laneId: "a0L00000001", refresh: false },
        { laneId: "a0L00000002", refresh: false }
      ]);
      expect(map(el).view.status).toBe("No route");
      expect(textOf(el, "lane-miles")).toBe(
        "No route found between the two places"
      );
    });

    it("shows an Apex failure as an unavailable route, not as a panel error", async () => {
      laneRoute.mockRejectedValue({
        body: { message: "This lane is not available." }
      });
      const el = await mount();
      await flush();
      expect(map(el).view).toMatchObject({
        status: "Unavailable",
        routes: [],
        message: "This lane is not available."
      });
      expect(map(el).loading).toBe(false);
      expect(field(el, "panel-error")).toBeNull();
    });

    it("tells the route map when the lane is hazmat", async () => {
      laneRoute.mockResolvedValue(ROUTE_VIEW);
      const plain = await mount();
      expect(map(plain).hazmat).toBe(false);
      const hazmat = await mount({
        lane: { ...LANE, Id: "a0L00000003", Hazmat__c: true }
      });
      expect(map(hazmat).hazmat).toBe(true);
    });

    it("prices per mile as the pricer types, and per km once the unit changes", async () => {
      const el = await mount({
        lane: { ...LANE, Miles__c: 1234, Miles_Source__c: "History" }
      });
      expect(textOf(el, "lane-miles")).toBe("1,234 mi · from history");
      // 1500 / 1234; the lane has no margin yet, so there is no sell to divide
      expect(textOf(el, "cost-per-distance")).toBe("Cost per mile: 1.22 CAD");
      expect(textOf(el, "sell-per-distance")).toBe("Sell per mile: —");

      change(el, "margin", { value: "20" });
      await flush();
      // sell 1800 / 1234
      expect(textOf(el, "sell-per-distance")).toBe("Sell per mile: 1.46 CAD");

      change(el, "sell", { value: "2250" });
      await flush();
      expect(textOf(el, "sell-per-distance")).toBe("Sell per mile: 1.82 CAD");

      publishUnit("km");
      await flush();
      // 1234 mi = 1,985.93 km
      expect(textOf(el, "lane-miles")).toBe("1,986 km · from history");
      expect(textOf(el, "cost-per-distance")).toBe("Cost per km: 0.76 CAD");
      expect(textOf(el, "sell-per-distance")).toBe("Sell per km: 1.13 CAD");
      expect(map(el).unit).toBe("km");
    });

    it("starts from the stored unit and lets go of the channel when removed", async () => {
      writeUnit("km");
      subscribe.mockReturnValueOnce({ id: "unit-sub" });
      const el = await mount({
        lane: { ...LANE, Miles__c: 1234, Miles_Source__c: "Approx" }
      });
      expect(textOf(el, "lane-miles")).toBe("1,986 km · approx.");
      expect(textOf(el, "cost-per-distance")).toBe("Cost per km: 0.76 CAD");
      expect(subscribe.mock.calls.some((c) => c[1] === DISTANCE_UNIT)).toBe(
        true
      );
      document.body.removeChild(el);
      expect(unsubscribe).toHaveBeenCalledWith({ id: "unit-sub" });
    });

    it("lets newer miles from the container replace the route's copy", async () => {
      laneRoute.mockResolvedValue(ROUTE_VIEW);
      const el = await mount();
      await flush();
      expect(textOf(el, "lane-miles")).toBe("1,234 mi · truck route · 21.5 h");
      // a history run found billed miles for the same lane and the same places
      el.lane = {
        ...LANE,
        Miles__c: 1198,
        Miles_Source__c: "History",
        Route_Hours__c: null
      };
      await flush();
      expect(textOf(el, "lane-miles")).toBe("1,198 mi · from history");
      // same place pair: no second route request
      expect(laneRoute).toHaveBeenCalledTimes(1);
    });
  });
```

In `force-app/main/default/lwc/rfpTool/__tests__/rfpTool.test.js`, directly after the `RfpLaneController.resolveLaneEnd` mock (lines 69–73), add the module the panel now imports (the file lists every Apex module the workbench tree imports; `rfpTool.js` itself does not change):

```js
jest.mock(
  "@salesforce/apex/RfpLaneController.laneRoute",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
```

- [ ] **Step 10: Run the panel suite and watch the new tests fail**

Run: `npm run test:unit -- force-app/main/default/lwc/rfpLanePanel 2>&1 | grep -E "✕|^(Tests|Test Suites):"`

Expected: nine `✕` lines, all inside `trip miles and route` (`laneRoute` is never called and there is no `c-route-map`, `lane-miles` or `cost-per-distance` yet), and `Tests: 9 failed, 24 passed, 33 total`. "asks for no route while an end is unresolved" already passes — it guards against the implementation calling out for an unresolved lane.

- [ ] **Step 11: Lane panel — miles line, per-distance prices, route map**

In `force-app/main/default/lwc/rfpLanePanel/rfpLanePanel.js`:

Replace the first five lines:

```js
import { LightningElement, api, track } from "lwc";
import getBids from "@salesforce/apex/RfpBidController.getBids";
import saveBid from "@salesforce/apex/RfpBidController.saveBid";
import search from "@salesforce/apex/LaneBenchmarkController.search";
import { bestBid } from "c/rfpMath";
```

with:

```js
import { LightningElement, api, track, wire } from "lwc";
import {
  APPLICATION_SCOPE,
  MessageContext,
  subscribe,
  unsubscribe
} from "lightning/messageService";
import DISTANCE_UNIT from "@salesforce/messageChannel/Distance_Unit__c";
import getBids from "@salesforce/apex/RfpBidController.getBids";
import saveBid from "@salesforce/apex/RfpBidController.saveBid";
import search from "@salesforce/apex/LaneBenchmarkController.search";
import laneRoute from "@salesforce/apex/RfpLaneController.laneRoute";
import { bestBid } from "c/rfpMath";
```

Replace:

```js
import { marginFor } from "c/marginMath";
```

with:

```js
import { marginFor } from "c/marginMath";
import { readUnit, formatDistance, perDistance } from "c/distanceUnit";
```

After the `placeText` helper (`const placeText = (city, province) => ...`, the two lines before `export default class`), add:

```js
/** Both place keys, or null while an end is unresolved: there is nothing to route between. */
const placePair = (lane) => {
  const origin = lane?.Origin_Place__r?.Key__c;
  const destination = lane?.Destination_Place__r?.Key__c;
  return origin && destination ? `${origin}~${destination}` : null;
};
/** The lane's three trip fields as one string, to notice newer miles arriving. */
const milesFingerprint = (lane) =>
  ["Miles__c", "Miles_Source__c", "Route_Hours__c"]
    .map((f) => lane?.[f] ?? "")
    .join("|");
/** How the line under the title names each source that comes with miles. */
const SOURCE_WORDS = {
  History: "from history",
  "Truck route": "truck route",
  "Regular route": "regular route",
  Approx: "approx."
};
/** The line under the title when the lane has no miles, by source. */
const NO_MILES_LINES = {
  "No route": "No route found between the two places",
  "No coordinates": "A place on this lane is missing or has no coordinates"
};
const ROUTE_UNAVAILABLE = "The truck route is not available right now.";
```

Replace the whole `lane` setter (lines 38–58):

```js
  set lane(value) {
    const laneChanged = laneIdOf(value) !== laneIdOf(this._lane);
    const pricingChanged =
      pricingFingerprint(value) !== pricingFingerprint(this._lane);
    const previousHistoryKey = historyKey(this._lane);
    this._lane = value || null;
    if (laneChanged) {
      this.syncFromLane();
      this.loadBids();
    } else if (pricingChanged) {
      // An inline edit or a bulk action touched the lane on screen: the editor
      // must show what is stored now, not what it showed before the change.
      this.syncPricing();
    }
    // A new lane always re-searches. Re-sending the same lane searches again
    // only once its place keys change — an end resolved through the table gives
    // it keys it did not have, while a pricing round trip changes nothing.
    if (laneChanged || historyKey(this._lane) !== previousHistoryKey) {
      this.loadHistory();
    }
  }
```

with:

```js
  set lane(value) {
    const laneChanged = laneIdOf(value) !== laneIdOf(this._lane);
    const pricingChanged =
      pricingFingerprint(value) !== pricingFingerprint(this._lane);
    const milesChanged =
      milesFingerprint(value) !== milesFingerprint(this._lane);
    const previousHistoryKey = historyKey(this._lane);
    const previousPlaces = placePair(this._lane);
    this._lane = value || null;
    if (laneChanged) {
      this.syncFromLane();
      this.loadBids();
    } else if (pricingChanged) {
      // An inline edit or a bulk action touched the lane on screen: the editor
      // must show what is stored now, not what it showed before the change.
      this.syncPricing();
    }
    // Miles the container sends for the lane on screen (a history run, a price
    // save that re-read the lane) are newer than the copy the last route call
    // returned, so that copy stops standing in for them.
    if (milesChanged) {
      this.routeLane = null;
    }
    // A new lane always re-searches. Re-sending the same lane searches again
    // only once its place keys change — an end resolved through the table gives
    // it keys it did not have, while a pricing round trip changes nothing.
    if (laneChanged || historyKey(this._lane) !== previousHistoryKey) {
      this.loadHistory();
    }
    // The route belongs to the place pair alone: a history run changes the
    // lane's precision and lookback, never its places, so it asks nothing.
    if (laneChanged || placePair(this._lane) !== previousPlaces) {
      this.loadRoute(false);
    }
  }
```

Replace:

```js
  bidSeq = 0;
  historySeq = 0;

  sourceOptions = SOURCES;
```

with:

```js
  bidSeq = 0;
  historySeq = 0;
  /** The TripRouteView c-route-map draws; null until laneRoute answers. */
  routeView = null;
  /** The lane as laneRoute re-read it after writing its miles; see milesLane. */
  routeLane = null;
  loadingRoute = false;
  routeSeq = 0;
  /** "mi" or "km"; every distance on the page follows Distance_Unit__c. */
  unit = readUnit();
  @wire(MessageContext) messageContext;
  unitSubscription = null;

  sourceOptions = SOURCES;

  connectedCallback() {
    if (!this.unitSubscription) {
      this.unitSubscription = subscribe(
        this.messageContext,
        DISTANCE_UNIT,
        (message) => this.handleUnit(message),
        { scope: APPLICATION_SCOPE }
      );
    }
  }

  /** The workbench drops the panel when it leaves the lanes view. */
  disconnectedCallback() {
    if (this.unitSubscription) {
      unsubscribe(this.unitSubscription);
    }
    this.unitSubscription = null;
  }

  handleUnit(message) {
    const unit = message && message.unit;
    if (unit === "mi" || unit === "km") {
      this.unit = unit;
    }
  }
```

After the `laneTitle` getter (`return \`${this.originLabel} → ${this.destinationLabel}\`;` and its closing brace), add:

```js
  /**
   * The lane's trip fields. The copy laneRoute wrote and re-read stands in
   * until the container sends the lane again: rfpTool is not told about a
   * route, so its lanes catch up on the next price save or history run.
   */
  get milesLane() {
    return this.routeLane || this._lane || {};
  }
  /** The lane's miles when its source comes with a distance, else null. */
  get milesNumber() {
    const l = this.milesLane;
    const known = Object.prototype.hasOwnProperty.call(
      SOURCE_WORDS,
      l.Miles_Source__c || ""
    );
    const miles = Number(l.Miles__c);
    return known && miles > 0 ? miles : null;
  }
  /** "1,234 mi · truck route · 21.5 h", why there are no miles, or "" before any run. */
  get milesLine() {
    const l = this.milesLane;
    const miles = this.milesNumber;
    if (miles === null) {
      return NO_MILES_LINES[l.Miles_Source__c] || "";
    }
    const hours =
      Number(l.Route_Hours__c) > 0
        ? ` · ${Number(l.Route_Hours__c).toFixed(1)} h`
        : "";
    return `${formatDistance(miles, this.unit)} · ${SOURCE_WORDS[l.Miles_Source__c]}${hours}`;
  }
  get hasRoutePlaces() {
    return !!placePair(this._lane);
  }
  /** c-route-map says under its legend that a hazmat lane gets the ordinary route. */
  get laneHazmat() {
    return !!(this._lane && this._lane.Hazmat__c);
  }
```

In `syncFromLane`, replace:

```js
    this.bids = [];
    this.historyRows = [];
```

with:

```js
    this.bids = [];
    this.historyRows = [];
    this.routeView = null;
    this.routeLane = null;
```

After `loadHistory` (its closing brace, just before `get isBidSource()`), add:

```js
  /**
   * The stored truck route on open (refresh false), a new Mapbox request on
   * Refresh route (refresh true). laneRoute also writes the lane's miles
   * unless they come from History and returns the lane re-read. A failure is
   * shown in the route map, not in the panel's error line, so it never hides
   * a bid or history error.
   */
  async loadRoute(refresh) {
    const seq = ++this.routeSeq;
    const laneId = this.laneId;
    if (!laneId || !placePair(this._lane)) {
      this.routeView = null;
      this.loadingRoute = false;
      return;
    }
    this.loadingRoute = true;
    try {
      const view = await laneRoute({ laneId, refresh: !!refresh });
      if (seq !== this.routeSeq) {
        return; // the panel moved to another lane; this route is not its
      }
      this.routeView = view || null;
      if (view && view.lane) {
        this.routeLane = view.lane;
      }
    } catch (e) {
      if (seq === this.routeSeq) {
        this.routeView = {
          status: "Unavailable",
          routeType: null,
          routes: [],
          mapUrl: null,
          message: apexMessage(e, ROUTE_UNAVAILABLE)
        };
      }
    } finally {
      if (seq === this.routeSeq) {
        this.loadingRoute = false;
      }
    }
  }
```

After the `pricing` getter (its closing brace, just before `handleSource(event)`), add:

```js
  /** The sell the pricer sees: typed in Manual mode, derived from the margin otherwise. */
  get sellNumber() {
    return this.isManualSell ? parseMoney(this.sellText) : this.pricing.Sell__c;
  }
  get hasPerDistance() {
    return this.milesNumber !== null;
  }
  get costPerDistanceText() {
    return this.perDistanceText("Cost", this.costNumber);
  }
  get sellPerDistanceText() {
    return this.perDistanceText("Sell", this.sellNumber);
  }

  /** "Cost per mile: 1.22 CAD", or "—" while there is no amount to divide yet. */
  perDistanceText(label, amount) {
    const value =
      amount === null || amount === undefined
        ? null
        : perDistance(amount, this.milesNumber, this.unit);
    const word = this.unit === "km" ? "km" : "mile";
    const shown =
      value === null || value === undefined
        ? "—"
        : `${value.toFixed(2)} ${this.currency}`;
    return `${label} per ${word}: ${shown}`;
  }
```

After `handleUseBest()` (its closing brace, just before `handleSavePrice()`), add:

```js
  handleRefreshRoute() {
    this.loadRoute(true);
  }
```

In `force-app/main/default/lwc/rfpLanePanel/rfpLanePanel.html`:

After the heading row (the `<div class="slds-grid slds-grid_vertical-align-center slds-m-bottom_x-small">` that holds the `h2` and the help hint, closing at line 12), add:

```html
      <template lwc:if={milesLine}>
        <p
          data-id="lane-miles"
          class="slds-text-body_small slds-text-color_weak slds-m-bottom_x-small"
        >
          {milesLine}
        </p>
      </template>
```

Replace the sell-mode column (lines 67–74):

```html
        <div class="slds-col slds-size_1-of-1">
          <p
            data-id="sell-mode"
            class="slds-text-body_small slds-text-color_weak"
          >
            {sellMode}
          </p>
        </div>
```

with:

```html
        <div class="slds-col slds-size_1-of-1">
          <p
            data-id="sell-mode"
            class="slds-text-body_small slds-text-color_weak"
          >
            {sellMode}
          </p>
        </div>
        <template lwc:if={hasPerDistance}>
          <div class="slds-col slds-size_1-of-1">
            <p class="slds-text-body_small">
              <span data-id="cost-per-distance">{costPerDistanceText}</span>
              <span data-id="sell-per-distance" class="slds-m-left_small"
                >{sellPerDistanceText}</span
              >
            </p>
          </div>
        </template>
```

After the bids list (the `<template lwc:if={hasBids}>` block, closing at line 159) and before `<template lwc:if={loadingHistory}>`, add:

```html
      <template lwc:if={hasRoutePlaces}>
        <div data-id="route" class="slds-m-top_x-small">
          <c-route-map
            view={routeView}
            loading={loadingRoute}
            unit={unit}
            hazmat={laneHazmat}
            onrefreshroute={handleRefreshRoute}
          ></c-route-map>
        </div>
      </template>
```

- [ ] **Step 12: Run the panel and workbench suites to pass**

Run: `npm run test:unit -- force-app/main/default/lwc/rfpLanePanel force-app/main/default/lwc/rfpTool 2>&1 | grep -E "✕|^(Tests|Test Suites):"`

Expected: no `✕` line, `Test Suites: 2 passed, 2 total`, `Tests: 67 passed, 67 total` (33 panel, 34 workbench; the workbench suite renders the real panel, whose `laneRoute` mock returns `undefined`, so the route map gets `view` `null`).

- [ ] **Step 13: Workbook — write the failing test**

In `force-app/main/default/lwc/rfpWorkbook/__tests__/rfpWorkbook.test.js`:

The first test reads "Bid carrier" and "Notes" by position; six new columns move both. Replace lines 64–65:

```js
    expect(sheet[1][11]).toBe("Acme");
    expect(sheet[1][13]).toBe("=SUM(A1)"); // typed string cell, no apostrophe
```

with:

```js
    expect(sheet[1][2 + OUR_COLUMNS.indexOf("Bid carrier")]).toBe("Acme");
    // typed string cell, no apostrophe
    expect(sheet[1][2 + OUR_COLUMNS.indexOf("Notes")]).toBe("=SUM(A1)");
```

After the test "takes the fuel surcharge, FSC and transit days from the selected bid, not just any bid on the lane" (it ends at line 184, just before the `});` that closes `describe("rfpWorkbook")`), add:

```js
  it("carries the trip in miles and km after Transit days, with the rate per mile", () => {
    const tripLanes = [
      {
        Id: "t1",
        Row_Number__c: 1,
        Cost__c: 1500,
        Sell__c: 1800,
        CurrencyIsoCode: "CAD",
        Miles__c: 1234,
        Miles_Source__c: "Truck route",
        Route_Hours__c: 21.5
      },
      {
        Id: "t2",
        Row_Number__c: 2,
        Cost__c: null,
        Sell__c: null,
        CurrencyIsoCode: "CAD",
        Miles__c: 410.5,
        Miles_Source__c: "History",
        Route_Hours__c: null
      },
      {
        Id: "t3",
        Row_Number__c: 3,
        Cost__c: 900,
        Sell__c: 1000,
        CurrencyIsoCode: "CAD",
        Miles__c: null,
        Miles_Source__c: "No route",
        Route_Hours__c: null
      },
      // never run: no trip fields at all
      {
        Id: "t4",
        Row_Number__c: 4,
        Cost__c: 900,
        Sell__c: 1000,
        CurrencyIsoCode: "CAD"
      }
    ];
    const { lanes: sheet } = buildSheets(tripLanes, [], {});
    const header = sheet[0];
    const at = header.indexOf("Transit days");
    expect(header.slice(at, at + 8)).toEqual([
      "Transit days",
      "Miles",
      "Km",
      "Miles source",
      "Route hours",
      "Cost per mile",
      "Sell per mile",
      "Bid carrier"
    ]);
    const trip = (i) => sheet[i].slice(at + 1, at + 7);
    // 1234 mi = 1985.93 km; 1500 / 1234 = 1.2156; 1800 / 1234 = 1.4587
    expect(trip(1)).toEqual([1234, 1985.9, "Truck route", 21.5, 1.22, 1.46]);
    // miles without a price: the per-mile cells stay empty
    expect(trip(2)).toEqual([410.5, 660.6, "History", "", "", ""]);
    // no miles, but the reason still travels
    expect(trip(3)).toEqual(["", "", "No route", "", "", ""]);
    expect(trip(4)).toEqual(["", "", "", "", "", ""]);
  });
```

- [ ] **Step 14: Run the workbook suite and watch the new test fail**

Run: `npm run test:unit -- force-app/main/default/lwc/rfpWorkbook 2>&1 | grep -E "✕|^(Tests|Test Suites):"`

Expected: `✕ carries the trip in miles and km after Transit days, with the rate per mile` (the header slice ends in `Bid carrier`, `History bids`, `Notes`), `Tests: 1 failed, 5 passed, 6 total`. The two rewritten positional assertions pass both before and after the change.

- [ ] **Step 15: Workbook — the six trip columns**

In `force-app/main/default/lwc/rfpWorkbook/rfpWorkbook.js`:

Replace lines 1–16:

```js
import { slug } from "c/laneBenchmarkCsv";

export const OUR_COLUMNS = [
  "Cost",
  "Currency",
  "Margin %",
  "Sell",
  "Annual sell",
  "Sell source",
  "Fuel surcharge",
  "FSC included",
  "Transit days",
  "Bid carrier",
  "History bids",
  "Notes"
];
```

with:

```js
import { slug } from "c/laneBenchmarkCsv";
import { KM_PER_MILE, perDistance } from "c/distanceUnit";

export const OUR_COLUMNS = [
  "Cost",
  "Currency",
  "Margin %",
  "Sell",
  "Annual sell",
  "Sell source",
  "Fuel surcharge",
  "FSC included",
  "Transit days",
  "Miles",
  "Km",
  "Miles source",
  "Route hours",
  "Cost per mile",
  "Sell per mile",
  "Bid carrier",
  "History bids",
  "Notes"
];
```

After `const priced = (l) => isNum(l.Cost__c);` (line 47), add (a function rather than a `(amount) => cond ? a : b` arrow: Prettier strips the parentheses ESLint's `no-confusing-arrow` wants):

```js
/** An amount per mile, or "" while the lane has no such amount. */
function perMile(amount, miles) {
  return isNum(amount) ? cell(perDistance(amount, miles, "mi")) : "";
}

/**
 * Miles, Km, Miles source, Route hours, Cost per mile, Sell per mile. The file
 * always carries both units, whatever the page shows, and the rates are per
 * mile. A lane without miles still says why (No route, No coordinates).
 */
function tripCells(l) {
  const source = cell(l.Miles_Source__c);
  if (!(isNum(l.Miles__c) && l.Miles__c > 0)) {
    return ["", "", source, "", "", ""];
  }
  return [
    l.Miles__c,
    Math.round(l.Miles__c * KM_PER_MILE * 10) / 10,
    source,
    cell(l.Route_Hours__c),
    perMile(l.Cost__c, l.Miles__c),
    perMile(l.Sell__c, l.Miles__c)
  ];
}
```

In `buildSheets`, replace:

```js
      cell(best?.Transit_Days__c),
      cell(l.Selected_Bid__r?.Carrier_Display__c),
```

with:

```js
      cell(best?.Transit_Days__c),
      ...tripCells(l),
      cell(l.Selected_Bid__r?.Carrier_Display__c),
```

- [ ] **Step 16: Run the workbook and export suites to pass**

Run: `npm run test:unit -- force-app/main/default/lwc/rfpWorkbook force-app/main/default/lwc/rfpExport 2>&1 | grep -E "✕|^(Tests|Test Suites):"`

Expected: no `✕` line, `Test Suites: 2 passed, 2 total`, `Tests: 14 passed, 14 total` (6 workbook, 8 export; the export suite builds its sheets through the real `buildSheets` and only reads the Bids sheet, which is unchanged).

- [ ] **Step 17: Format, lint, the whole Jest run, and rfpTool untouched**

Run: `npx prettier --write force-app/main/default/lwc/rfpToolbar force-app/main/default/lwc/rfpLaneTable force-app/main/default/lwc/rfpLanePanel force-app/main/default/lwc/rfpWorkbook force-app/main/default/lwc/rfpTool/__tests__/rfpTool.test.js`

Expected: each file listed once; only line wrapping changes (lint-staged would do the same on commit).

Run: `npx eslint force-app/main/default/lwc/rfpToolbar force-app/main/default/lwc/rfpLaneTable force-app/main/default/lwc/rfpLanePanel force-app/main/default/lwc/rfpWorkbook force-app/main/default/lwc/rfpTool; echo "eslint exit $?"`

Expected: no findings, `eslint exit 0`.

Run (in the background if it passes 2 minutes): `npm run test:unit 2>&1 | grep -E "✕|^(Tests|Test Suites):"`

Expected: no `✕` line and no failed suite; `Test Suites: 39 passed, 39 total` and `Tests: 349 passed, 349 total`, 15 tests more than after Task 8 (toolbar 8, table 26, panel 33, workbook 6, workbench 34, export 8 — 115 in those six suites, 100 before this task). The help `placement.test.js` suite still passes: the toolbar, table and panel keep exactly one `c-help-hint` each with the same topics.

Run: `git diff --stat -- force-app/main/default/lwc/rfpTool/rfpTool.js force-app/main/default/lwc/rfpTool/rfpTool.html; wc -l < force-app/main/default/lwc/rfpTool/rfpTool.js; git status --porcelain`

Expected: no diff-stat output for the two rfpTool files, `554`, and `git status` lists the twelve files this task names; ` M .vscode/settings.json` and any untracked macOS duplicates named `* 2.*` may also appear and are never staged.

- [ ] **Step 18: Deploy the four bundles**

Tasks 7 and 8 are deployed to `sandbox` first (`RfpLaneController.laneRoute`, `distanceUnit`, `distanceUnitToggle`, `routeMap`, `Distance_Unit__c`): a bundle that imports a missing Apex method, component or message channel fails to deploy. `__tests__/**` is in `.forceignore`.

Run: `sf project deploy start -o sandbox -l NoTestRun --source-dir force-app/main/default/lwc/rfpToolbar --source-dir force-app/main/default/lwc/rfpLaneTable --source-dir force-app/main/default/lwc/rfpLanePanel --source-dir force-app/main/default/lwc/rfpWorkbook --async --json | python3 -c "import json,sys; s=sys.stdin.read(); print(json.loads(s[s.index('{'):])['result']['id'])"`

Expected: a deploy id starting with `0Af`.

Run, repeating until the status is final: `sf project deploy report -o sandbox --job-id <id> -w 2 --json | python3 -c "import json,sys; s=sys.stdin.read(); r=json.loads(s[s.index('{'):])['result']; print(r['status'], r.get('numberComponentsDeployed'), '/', r.get('numberComponentsTotal'), (r.get('details') or {}).get('componentFailures'))"`

Expected: `Succeeded 4 / 4 None`. A `componentFailures` entry naming `c:routeMap`, `c:distanceUnitToggle`, `Distance_Unit__c` or `RfpLaneController.laneRoute` means Task 7 or 8 is not in the org yet: deploy it, then repeat this step.

- [ ] **Step 19: Commit**

```bash
git add force-app/main/default/lwc/rfpToolbar/rfpToolbar.html force-app/main/default/lwc/rfpToolbar/rfpToolbar.js force-app/main/default/lwc/rfpToolbar/__tests__/rfpToolbar.test.js force-app/main/default/lwc/rfpLaneTable/rfpLaneTable.js force-app/main/default/lwc/rfpLaneTable/rfpLaneTable.html force-app/main/default/lwc/rfpLaneTable/__tests__/rfpLaneTable.test.js force-app/main/default/lwc/rfpLanePanel/rfpLanePanel.js force-app/main/default/lwc/rfpLanePanel/rfpLanePanel.html force-app/main/default/lwc/rfpLanePanel/__tests__/rfpLanePanel.test.js force-app/main/default/lwc/rfpWorkbook/rfpWorkbook.js force-app/main/default/lwc/rfpWorkbook/__tests__/rfpWorkbook.test.js force-app/main/default/lwc/rfpTool/__tests__/rfpTool.test.js
git commit -m "Show trip miles, rate per mile and the truck route in the RFP workbench"
git show --stat HEAD | tail -14
```

Expected: the commit lists the twelve files above; `rfpTool.js`, `rfpTool.html` and `.vscode/settings.json` are not in it.

#### Contract notes (Task 9)

1. **There is no "event the panel already uses to push an updated lane".** `rfpTool.html` wires `c-rfp-lane-panel` with `onpricingchange={handlePricingChange}` only, and that handler is a save (`saveLanePricing`, refused while `busy`, one per lane through `pendingIds`); the panel's other event, `bidsaved`, has no listener in `rfpTool`. Dispatching `pricingchange` to carry the route's lane would save whatever the pricer has half-typed (or nulls) over the stored price, so the draft does not. Instead the panel keeps the lane `laneRoute` re-read (`routeLane`) and shows its miles, per-mile prices and source until the container sends the lane again (a newer `Miles__c`/`Miles_Source__c`/`Route_Hours__c` from the container always wins). The table's Miles cell catches up on the next merge: a price save (`saveLanePricing` re-reads the lane with `LANE_FIELDS`), a history run, or reopening the project. Task 11's browser check should expect that. The rejected alternative, a live table update, needs a change in the frozen file: `handleLaneUpdate(event) { this.lanes = mergeLanes(this.lanes, event.detail.lane); }` in `rfpTool.js` (3 lines, 557 of 560), `onlaneupdate={handleLaneUpdate}` on the panel in `rfpTool.html`, and `this.dispatchEvent(new CustomEvent("laneupdate", { detail: { lane: view.lane } }))` after `this.routeLane = view.lane` in `loadRoute`. Not taken: both the contract and the task instructions freeze `rfpTool.js`. Accepted in planning; Task 11's browser check and the Outcome's Known limits describe it.
2. `rfpTool/__tests__/rfpTool.test.js` gains one `jest.mock` for `RfpLaneController.laneRoute` (a test file; `rfpTool.js` and `rfpTool.html` are unchanged, 554 lines).
3. The panel asks for a route when the lane changes or its **place pair** changes, not on the `historyKey` the history search uses: a history run changes `Hist_Precision__c`/`Hist_Lookback_Days__c`, and re-using that key would send a `laneRoute` round trip (and its lane update) after every history run.
4. A `laneRoute` exception is shown in `c-route-map` as `{ status: "Unavailable", routes: [], message: <Apex message or "The truck route is not available right now."> }`, not on the panel's error line, so a route failure never hides a bid or history error.
5. The panel passes `Hazmat__c` to `c-route-map`'s `@api hazmat` (Task 8 note 5), so spec §7's hazmat sentence sits in the route map's legend; the panel prints no hazmat note of its own.
6. The Miles column header reads `Km` while the unit is km, so a "1,986 km" cell never sits under "Miles"; the data ids and the field stay `miles`. The Excel columns stay per mile whatever the page shows (spec D6: the export always carries miles and km).
7. Expected strings assume Task 8's helpers as the contract defines them: `writeUnit`/`readUnit` round-trip through jsdom `localStorage`; `formatDistance(1260.4, "mi")` = `"1,260 mi"`, `formatDistance(1234, "km")` = `"1,986 km"` (the argument is always miles); `perDistance(amount, miles, unit)` = amount ÷ miles (÷ miles × 1.609344 for km) rounded half-up to 2 decimals; `c-route-map` accepts `view` `null`. Task 8 defines them exactly so.
8. The existing `rfpWorkbook` test read "Bid carrier" and "Notes" at fixed indices 11 and 13; the six new columns move them, so those two assertions now use `2 + OUR_COLUMNS.indexOf(...)`.
9. This draft was checked in a scratch copy of the LWC tree with contract-shaped stand-ins for Task 8's `distanceUnit`, `distanceUnitToggle` and `routeMap`: every Replace/After anchor above matches the current files exactly once; with only the test edits applied the five suites report `14 failed, 93 passed, 107 total` (1 toolbar, 3 table, 9 panel, 1 workbook; `rfpTool` green); with every step applied the six suites report `115 passed, 115 total`, ESLint exits 0 and `prettier --check` passes with the repo's `.prettierrc`. The review fixes (hazmat through `c-route-map`, `@wire(MessageContext)` with `APPLICATION_SCOPE`, one-decimal hours, the No coordinates wording) came after that check; they change no test count.

---

### Task 10: Lane Benchmark UI — trip miles, truck route map, rate per mile

**Files:**

- Modify: `force-app/main/default/lwc/laneBenchmark/laneBenchmark.js` (imports lines 1-6; class fields lines 33-42; `connectedCallback`/`disconnectedCallback` lines 70-85; `handleClearSaved` lines 126-134; `runSearch` lines 185-222; new getters and route/unit handlers after line 68 and after line 222)
- Modify: `force-app/main/default/lwc/laneBenchmark/laneBenchmark.html` (the `hasResult` block, lines 91-107)
- Modify: `force-app/main/default/lwc/laneBenchmarkStats/laneBenchmarkStats.js` (imports line 2; `@api` fields lines 13-17; `cards` lines 47-64; new getters)
- Modify: `force-app/main/default/lwc/laneBenchmarkStats/laneBenchmarkStats.html` (card header slot lines 3-7; trip/route block before line 9; card `dl` lines 73-90)
- Modify: `force-app/main/default/lwc/laneBenchmarkResults/laneBenchmarkResults.js` (imports line 2; `CSV_COLUMNS` lines 9-28; `@api` fields lines 31-32; `viewRows` lines 50-79)
- Modify: `force-app/main/default/lwc/laneBenchmarkResults/laneBenchmarkResults.html` (header row lines 23-36; row cells lines 76-78; detail `colspan` line 88)
- Test: `force-app/main/default/lwc/laneBenchmark/__tests__/laneBenchmark.test.js` (mocks lines 1-32, `RESULT` lines 35-63, `beforeEach` lines 78-87, new tests appended before the final `});`)
- Test: `force-app/main/default/lwc/laneBenchmarkStats/__tests__/laneBenchmarkStats.test.js` (`STATS` lines 5-22, new tests appended)
- Test: `force-app/main/default/lwc/laneBenchmarkResults/__tests__/laneBenchmarkResults.test.js` (`ROWS` lines 5-89, new tests appended)
- Unchanged: `force-app/main/default/lwc/laneBenchmarkMap/*` (still renders the plain or radius preview when no route map is available), `force-app/main/default/lwc/laneBenchmarkCsv/*`, `manifest/package.xml` (all three bundles are already members, lines 31-34).

**Interfaces:**

- Consumes:
  - `LaneBenchmarkController.truckRoute(String originKey, String destinationKey, Boolean refresh)` → `TripRouteView` (Task 7), imported as `@salesforce/apex/LaneBenchmarkController.truckRoute`; the view's `status` (`'Found' | 'No route' | 'Unavailable'`), `routeType` (`'Truck' | 'Regular' | null`), `miles`, `hours`, `routes`, `mapUrl`, `message`.
  - `LaneSearchResult.medianMiles`, `LaneSearchResult.Row.load.miles` (Task 4's `LoadDetail`, filled by Task 5: the load's miles on load rows, `null` on bid rows), `LaneSearchResult.Stats.ratePerMileMedian` (Task 5), read from the existing cacheable `LaneBenchmarkController.search`.
  - `c/distanceUnit` (Task 8): `readUnit()`, `formatDistance(miles, unit)`, `perDistance(amount, miles, unit)`; tests also use `writeUnit(unit)`.
  - `c-distance-unit-toggle` (Task 8): no attributes; publishes `{ unit }` on `Distance_Unit__c`.
  - `c-route-map` (Task 8): `@api view`, `@api loading`, `@api unit`; dispatches `refreshroute` (its `@api hazmat` stays unset: Task 8 reserves it for RFP lanes).
  - Lightning message channel `Distance_Unit__c` (Task 8), imported as `@salesforce/messageChannel/Distance_Unit__c`; `subscribe`, `unsubscribe`, `MessageContext`, `APPLICATION_SCOPE` from `lightning/messageService`, subscribed with Task 8's subscriber pattern (`{ scope: APPLICATION_SCOPE }`).
- Produces:
  - `c-lane-benchmark` calls `truckRoute({ originKey, destinationKey, refresh: false })` after every successful search whose origin and destination keys are both set, and `truckRoute({ ..., refresh: true })` on `refreshroute`; renders `c-route-map` in place of `c-lane-benchmark-map` while `routeView.mapUrl` is present; holds the page's `unit` (starts from `readUnit()`, follows `Distance_Unit__c`) and passes it to the stats, the route map and the results.
  - `c-lane-benchmark-stats` new `@api`: `medianMiles` (Decimal), `milesCount` (Integer, load rows with miles above zero), `routeView` (`TripRouteView`), `routeLoading` (Boolean), `unit` (`'mi' | 'km'`); `data-id="trip-line"` ("Trip: 1,234 mi · median of N loads"), `data-id="route-line"` ("Truck route: 1,260 mi · 21.5 h" / "Regular route: …"), per-currency `data-id="rate"` under "Rate per mile (median)" / "Rate per km (median)"; `c-distance-unit-toggle` in the card's `actions` slot.
  - `c-lane-benchmark-results` new `@api unit`; `data-id="miles-header"` ("Miles" / "Km"), per-row `data-id="miles"` cell (`formatDistance`, "—" for bid rows and rows without miles); `CSV_COLUMNS` gains `{ label: "Miles", field: "load.miles" }` right after "Carrier total" (raw miles, whatever the unit).

**Depends on:** Tasks 4 and 5 (`medianMiles`, `Row.load.miles`, `Stats.ratePerMileMedian` on the search result), Task 7 (`LaneBenchmarkController.truckRoute` deployed), Task 8 (`c/distanceUnit`, `c-distance-unit-toggle`, `c-route-map` and the `Distance_Unit__c` channel in the repo and deployed). Jest resolves `c/distanceUnit`, `c-distance-unit-toggle` and `c-route-map` from the repo, so Task 8 must be committed before Step 1; the `lightning/messageService` stub from `@salesforce/sfdx-lwc-jest` supplies `subscribe`/`unsubscribe`/`publish` as `jest.fn()`.

- [ ] **Step 1: Results — write the failing tests**

In `force-app/main/default/lwc/laneBenchmarkResults/__tests__/laneBenchmarkResults.test.js`, give the three `ROWS` their load detail (Task 5 sends `load: { loadId, miles }` on every row: the load's billed miles on load rows, both fields `null` on bid rows):

- row `q1`: after `carrierTotal: 1000,` add `load: { loadId: "a0L000000000001", miles: 337.2 },`
- row `q2`: after `carrierTotal: 800,` add `load: { loadId: "a0L000000000002", miles: null },`
- row `b1`: after `carrierTotal: 1200,` add `load: { loadId: null, miles: null },`

After the `mount` function (line 99), add:

```js
async function exportCsv(el) {
  const createUrl = jest.fn(() => "blob:x");
  global.URL.createObjectURL = createUrl;
  global.URL.revokeObjectURL = jest.fn();
  jest.spyOn(HTMLAnchorElement.prototype, "click").mockImplementation(() => {});
  jest.useFakeTimers();
  el.shadowRoot.querySelector('[data-id="export"]').click();
  await flush();
  jest.runOnlyPendingTimers();
  jest.useRealTimers();
  const blob = createUrl.mock.calls[0][0];
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(reader.result);
    reader.onerror = () => reject(reader.error);
    reader.readAsText(blob);
  });
}
```

Before the last `});` of the file (line 240), add:

```js
  it("shows each load's miles, a dash for bids and loads without miles, and follows the unit", async () => {
    const el = await mount();
    const header = () =>
      el.shadowRoot
        .querySelector('[data-id="miles-header"]')
        .textContent.trim();
    const cells = () =>
      Array.from(
        el.shadowRoot.querySelectorAll('tbody tr[data-index] [data-id="miles"]')
      ).map((c) => c.textContent.trim());
    expect(header()).toBe("Miles");
    expect(cells()).toEqual(["337 mi", "—", "—"]);
    el.unit = "km";
    await flush();
    expect(header()).toBe("Km");
    expect(cells()).toEqual(["543 km", "—", "—"]);
  });

  it("exports raw miles right after the carrier total, blank for bids, whatever the unit", async () => {
    const el = await mount();
    el.unit = "km";
    await flush();
    const lines = (await exportCsv(el)).split("\r\n");
    expect(lines[0]).toContain("Carrier total,Miles,Quote date");
    expect(lines[1]).toContain(",CAD,1000,337.2,2026-09-01,");
    expect(lines[2]).toContain(",USD,800,,2026-08-30,");
    expect(lines[3]).toContain(",CAD,1200,,2026-09-10,");
  });
```

- [ ] **Step 2: Run the results tests to see them fail**

```bash
npm run test:unit -- force-app/main/default/lwc/laneBenchmarkResults
```

Expected: `Tests: 2 failed, 6 passed, 8 total`. The first new test fails with `TypeError: Cannot read properties of null (reading 'textContent')` (no `miles-header` yet); the second with `expect(received).toContain(expected)` on `Carrier total,Miles,Quote date`. The six existing tests still pass (the header still starts with `Source,` and ends with `Expires on`).

- [ ] **Step 3: Results — Miles column and CSV column**

In `force-app/main/default/lwc/laneBenchmarkResults/laneBenchmarkResults.js`:

Replace line 2 with:

```js
import { toCsv, fileName } from "c/laneBenchmarkCsv";
import { formatDistance } from "c/distanceUnit";
```

In `CSV_COLUMNS`, replace

```js
  { label: "Carrier total", field: "carrierTotal" },
```

with

```js
  { label: "Carrier total", field: "carrierTotal" },
  // phase 7: the load's billed miles as a raw number (blank for bids); the CSV never follows the
  // mi/km toggle, so a spreadsheet can always divide by it
  { label: "Miles", field: "load.miles" },
```

Replace

```js
  @api originLabel = "";
  @api destinationLabel = "";
```

with

```js
  @api originLabel = "";
  @api destinationLabel = "";
  // 'mi' | 'km', owned by c-lane-benchmark (which follows the Distance_Unit__c channel)
  @api unit = "mi";
```

After the `hasRows` getter, add:

```js
  get distanceHeader() {
    return this.unit === "km" ? "Km" : "Miles";
  }
```

In `viewRows`, replace

```js
      hazmatText: r.hazmat ? "Hazmat" : "",
```

with

```js
      // bid rows carry no miles, and a load can have none (or 0) in Revenova: both show a dash
      milesText:
        r.load && Number(r.load.miles) > 0
          ? formatDistance(r.load.miles, this.unit)
          : "—",
      hazmatText: r.hazmat ? "Hazmat" : "",
```

In `force-app/main/default/lwc/laneBenchmarkResults/laneBenchmarkResults.html`:

Replace

```html
              <th scope="col" class="w-6">Total</th>
```

with

```html
              <th scope="col" class="w-6">Total</th>
              <th scope="col" class="w-6" data-id="miles-header">
                {distanceHeader}
              </th>
```

Replace

```html
                <td class="slds-text-align_right">{r.total}</td>
```

with

```html
                <td class="slds-text-align_right">{r.total}</td>
                <td data-id="miles" class="slds-text-align_right">
                  {r.milesText}
                </td>
```

Replace

```html
                  <td colspan="12">
```

with

```html
                  <td colspan="13">
```

- [ ] **Step 4: Run the results tests to see them pass**

```bash
npm run test:unit -- force-app/main/default/lwc/laneBenchmarkResults && npx eslint force-app/main/default/lwc/laneBenchmarkResults
```

Expected: `Tests: 8 passed, 8 total`; ESLint prints nothing and exits 0.

- [ ] **Step 5: Statistics — write the failing tests**

In `force-app/main/default/lwc/laneBenchmarkStats/__tests__/laneBenchmarkStats.test.js`, give the two `STATS` entries their rate per mile (Task 5 sends `ratePerMileMedian`, `null` when no row of that currency has both a total and miles):

- `CAD`: after `median: 2000` add `,` and a new line `ratePerMileMedian: 1.62`
- `USD`: after `median: 1000` add `,` and a new line `ratePerMileMedian: null`

After `const text = (el) => el.shadowRoot.textContent;` (line 41), add:

```js
const line = (el, id) => {
  const node = el.shadowRoot.querySelector(`[data-id="${id}"]`);
  return node ? node.textContent.trim() : null;
};
const TRUCK_VIEW = {
  status: "Found",
  routeType: "Truck",
  source: "Truck route",
  miles: 1260,
  hours: 21.5,
  routes: [{ miles: 1260, hours: 21.5 }],
  mapUrl:
    "https://api.mapbox.com/styles/v1/mapbox/streets-v12/static/pin-s-a+0070d2(-73.56,45.5)/auto/600x300@2x?padding=40&access_token=pk.test",
  message: null
};
```

Before the last `});` of the file (line 100), add:

```js
  it("shows the trip miles, the truck route, the rate per mile and the unit toggle, in miles by default", async () => {
    const el = await mount({
      medianMiles: 1234.4,
      milesCount: 3,
      routeView: TRUCK_VIEW
    });
    expect(line(el, "trip-line")).toBe("Trip: 1,234 mi · median of 3 loads");
    expect(line(el, "route-line")).toBe("Truck route: 1,260 mi · 21.5 h");
    const cad = el.shadowRoot.querySelector('[data-currency="CAD"]');
    expect(cad.textContent).toContain("Rate per mile (median)");
    expect(cad.querySelector('[data-id="rate"]').textContent.trim()).toBe(
      "1.62"
    );
    expect(
      el.shadowRoot
        .querySelector('[data-currency="USD"] [data-id="rate"]')
        .textContent.trim()
    ).toBe("—");
    expect(
      el.shadowRoot.querySelector("c-distance-unit-toggle")
    ).not.toBeNull();
  });

  it("switches the trip, the route and the rate to km", async () => {
    const el = await mount({
      medianMiles: 1234.4,
      milesCount: 1,
      routeView: TRUCK_VIEW,
      unit: "km"
    });
    expect(line(el, "trip-line")).toBe("Trip: 1,987 km · median of 1 load");
    expect(line(el, "route-line")).toBe("Truck route: 2,028 km · 21.5 h");
    const cad = el.shadowRoot.querySelector('[data-currency="CAD"]');
    expect(cad.textContent).toContain("Rate per km (median)");
    expect(cad.querySelector('[data-id="rate"]').textContent.trim()).toBe(
      "1.01"
    ); // 1.62 per mile / 1.609344
  });

  it("labels a regular route, a missing or unavailable route and a route still loading, even with no quotes", async () => {
    const regular = await mount({
      routeView: { ...TRUCK_VIEW, routeType: "Regular" }
    });
    expect(line(regular, "route-line")).toBe(
      "Regular route: 1,260 mi · 21.5 h"
    );
    expect(line(regular, "trip-line")).toBeNull();
    const unavailable = await mount({
      routeView: {
        status: "Unavailable",
        routeType: null,
        routes: [],
        mapUrl: null,
        message: "The truck route is not available right now."
      }
    });
    expect(line(unavailable, "route-line")).toBe(
      "Truck route: — · The truck route is not available right now."
    );
    const noRoute = await mount({
      routeView: {
        status: "No route",
        routeType: null,
        routes: [],
        mapUrl: null,
        message:
          "No route was found between these places, even without truck limits."
      }
    });
    expect(line(noRoute, "route-line")).toBe("Truck route: —");
    const loading = await mount({ routeView: null, routeLoading: true });
    expect(line(loading, "route-line")).toBe("Truck route: finding the route…");
    const empty = await mount({
      statsByCurrency: {},
      rowCount: 0,
      routeView: TRUCK_VIEW
    });
    expect(text(empty)).toContain("No quotes");
    expect(line(empty, "route-line")).toBe("Truck route: 1,260 mi · 21.5 h");
  });
```

- [ ] **Step 6: Run the statistics tests to see them fail**

```bash
npm run test:unit -- force-app/main/default/lwc/laneBenchmarkStats
```

Expected: `Tests: 3 failed, 4 passed, 7 total`; each new test fails at its first `line(...)` assertion with `Expected: "Trip: 1,234 mi · median of 3 loads"` / `"Trip: 1,987 km · median of 1 load"` / `"Regular route: 1,260 mi · 21.5 h"` and `Received: null`.

- [ ] **Step 7: Statistics — trip line, route line, rate per mile, unit toggle**

Replace the whole of `force-app/main/default/lwc/laneBenchmarkStats/laneBenchmarkStats.js` with:

```js
import { LightningElement, api } from "lwc";
import { parseMargin, suggestedSell } from "c/marginMath";
import { formatDistance, perDistance } from "c/distanceUnit";

function fmt(n) {
  if (n === null || n === undefined) return "—";
  return Number(n).toLocaleString("en-CA", {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2
  });
}

function hoursText(hours) {
  return hours === null || hours === undefined
    ? ""
    : ` · ${Number(hours).toFixed(1)} h`;
}

export default class LaneBenchmarkStats extends LightningElement {
  @api statsByCurrency = {};
  @api dedupedCount = 0;
  @api truncated = false;
  @api elapsedMs = 0;
  @api rowCount = 0;
  // Phase 7: the median of the matched loads' billed miles (LaneSearchResult.medianMiles), how
  // many load rows had miles, the truck route view (TripRouteView from
  // LaneBenchmarkController.truckRoute) and the page's unit, all passed by c-lane-benchmark.
  @api medianMiles = null;
  @api milesCount = 0;
  @api routeView = null;
  @api routeLoading = false;
  @api unit = "mi";
  _marginPct = 15;
  @api get marginPct() {
    return this._marginPct;
  }
  set marginPct(v) {
    this._marginPct = v;
  }
  marginError = null;

  get hasStats() {
    return Object.keys(this.statsByCurrency || {}).length > 0;
  }
  get isEmpty() {
    return !this.hasStats && this.rowCount === 0;
  }
  /** Joins only the parts that apply, so a zero dedupe count doesn't leave a trailing " · ". */
  get summary() {
    const seconds = (Number(this.elapsedMs || 0) / 1000).toFixed(1);
    const parts = [
      `${this.rowCount} ${this.rowCount === 1 ? "row" : "rows"} in ${seconds} s`
    ];
    if (this.dedupedCount > 0) {
      parts.push(`${this.dedupedCount} duplicates removed`);
    }
    if (this.truncated) {
      parts.push("truncated to the first 2,000 rows");
    }
    return parts.join(" · ");
  }
  /** "Trip: 1,234 mi · median of 3 loads", or "" when no matched load has miles. */
  get tripLine() {
    if (!(Number(this.medianMiles) > 0)) {
      return "";
    }
    const n = Number(this.milesCount || 0);
    return `Trip: ${formatDistance(this.medianMiles, this.unit)} · median of ${n} ${n === 1 ? "load" : "loads"}`;
  }
  /**
   * "Truck route: 1,260 mi · 21.5 h" or "Regular route: …" (truck limits could not be met);
   * a dash when there is no route (spec §7), and a dash with the server's message when Mapbox is
   * unavailable.
   */
  get routeLine() {
    const v = this.routeView;
    if (!v) {
      return this.routeLoading ? "Truck route: finding the route…" : "";
    }
    const label = v.routeType === "Regular" ? "Regular route" : "Truck route";
    if (v.status === "Found") {
      return `${label}: ${formatDistance(v.miles, this.unit)}${hoursText(v.hours)}`;
    }
    return v.status === "Unavailable" && v.message
      ? `${label}: — · ${v.message}`
      : `${label}: —`;
  }
  get hasTripInfo() {
    return !!(this.tripLine || this.routeLine);
  }
  get rateLabel() {
    return this.unit === "km"
      ? "Rate per km (median)"
      : "Rate per mile (median)";
  }
  get cards() {
    return Object.keys(this.statsByCurrency || {})
      .sort()
      .map((currency) => {
        const s = this.statsByCurrency[currency];
        const rate = s.ratePerMileMedian;
        return {
          currency,
          count: s.count,
          countNonZero: s.countNonZero,
          min: fmt(s.min),
          max: fmt(s.max),
          avg: fmt(s.avg),
          median: fmt(s.median),
          sellMedian: fmt(suggestedSell(s.median, this._marginPct)),
          sellAvg: fmt(suggestedSell(s.avg, this._marginPct)),
          // a rate per mile over a trip of one mile is the rate per unit of distance
          rate: fmt(
            rate === null || rate === undefined
              ? null
              : perDistance(rate, 1, this.unit)
          )
        };
      });
  }

  setMargin(n) {
    this._marginPct = n;
    this.marginError = null;
    this.dispatchEvent(
      new CustomEvent("marginchange", { detail: { marginPct: n } })
    );
  }
  handleMargin15() {
    this.setMargin(15);
  }
  handleMargin20() {
    this.setMargin(20);
  }
  handleMarginInput(event) {
    const n = parseMargin(event.detail.value);
    if (n === null) {
      this.marginError = "Enter a margin between 0 and 100";
      return;
    }
    this.setMargin(n);
  }
}
```

In `force-app/main/default/lwc/laneBenchmarkStats/laneBenchmarkStats.html`:

Replace

```html
  <lightning-card title="Statistics" icon-name="standard:metrics">
    <c-help-hint
```

with

```html
  <lightning-card title="Statistics" icon-name="standard:metrics">
    <c-distance-unit-toggle
      slot="actions"
      class="slds-m-right_x-small"
    ></c-distance-unit-toggle>
    <c-help-hint
```

Replace

```html
    <div class="slds-p-horizontal_medium">
      <template lwc:if={isEmpty}>
```

with

```html
    <div class="slds-p-horizontal_medium">
      <template lwc:if={hasTripInfo}>
        <div class="slds-m-bottom_small">
          <template lwc:if={tripLine}>
            <p data-id="trip-line" class="slds-text-title_bold">{tripLine}</p>
          </template>
          <template lwc:if={routeLine}>
            <p data-id="route-line">{routeLine}</p>
          </template>
        </div>
      </template>
      <template lwc:if={isEmpty}>
```

Replace

```html
                  <dt class="slds-dl_horizontal__label">Sell (average)</dt>
                  <dd class="slds-dl_horizontal__detail">{c.sellAvg}</dd>
```

with

```html
                  <dt class="slds-dl_horizontal__label">Sell (average)</dt>
                  <dd class="slds-dl_horizontal__detail">{c.sellAvg}</dd>
                  <dt class="slds-dl_horizontal__label">{rateLabel}</dt>
                  <dd data-id="rate" class="slds-dl_horizontal__detail">
                    {c.rate}
                  </dd>
```

- [ ] **Step 8: Run the statistics tests to see them pass**

```bash
npm run test:unit -- force-app/main/default/lwc/laneBenchmarkStats && npx eslint force-app/main/default/lwc/laneBenchmarkStats
```

Expected: `Tests: 7 passed, 7 total` (the four existing tests unchanged: the new lines render only when `medianMiles` or `routeView` is set, and the rate row adds no `2,300.00`-style value); ESLint prints nothing and exits 0.

- [ ] **Step 9: Lane Benchmark page — write the failing tests**

In `force-app/main/default/lwc/laneBenchmark/__tests__/laneBenchmark.test.js`:

Replace lines 1-6 (the imports) with:

```js
import { createElement } from "lwc";
import LaneBenchmark from "c/laneBenchmark";
import search from "@salesforce/apex/LaneBenchmarkController.search";
import getFilterOptions from "@salesforce/apex/LaneBenchmarkController.getFilterOptions";
import mapPreviewUrl from "@salesforce/apex/LaneBenchmarkController.mapPreviewUrl";
import truckRoute from "@salesforce/apex/LaneBenchmarkController.truckRoute";
import {
  subscribe,
  unsubscribe,
  APPLICATION_SCOPE
} from "lightning/messageService";
import DISTANCE_UNIT from "@salesforce/messageChannel/Distance_Unit__c";
import { save, load, STORAGE_KEY } from "c/laneBenchmarkStorage";
import { writeUnit } from "c/distanceUnit";
```

After the `mapPreviewUrl` mock (line 22), add:

```js
jest.mock(
  "@salesforce/apex/LaneBenchmarkController.truckRoute",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
```

In `RESULT`: in the row, after `carrierTotal: 1000,` add `load: { loadId: "a0L000000000001", miles: 337.2 },`; in `statsByCurrency.CAD`, after `median: 1000` add `,` and a new line `ratePerMileMedian: 2.97`; after `dedupedCount: 0` add `,` and a new line `medianMiles: 337.2`.

After the `RESULT` constant, add:

```js
const ROUTE_VIEW = {
  status: "Found",
  routeType: "Truck",
  source: "Truck route",
  miles: 336.9,
  hours: 5.4,
  routes: [{ miles: 336.9, hours: 5.4 }],
  mapUrl:
    "https://api.mapbox.com/styles/v1/mapbox/streets-v12/static/pin-s-a+0070d2(-73.5674,45.5019)/auto/600x300@2x?padding=40&access_token=pk.test",
  message: null
};
// a route answer comes after the search, the preview and a re-render: give it room to land
const settle = () => flush().then(flush).then(flush).then(flush);
```

After the `pick` helper (line 75), add:

```js
const pickLane = (el) => {
  pick(el, "origin", {
    key: "montreal|qc|ca",
    label: "Montréal, QC, CA",
    precision: "CITY",
    radius: null,
    unit: "MI"
  });
  pick(el, "destination", {
    key: "toronto|on|ca",
    label: "Toronto, ON, CA",
    precision: "CITY",
    radius: null,
    unit: "MI"
  });
};
const applySearch = (el) =>
  el.shadowRoot
    .querySelector("c-lane-benchmark-filters")
    .dispatchEvent(new CustomEvent("apply"));
```

In `beforeEach`, after `mapPreviewUrl.mockResolvedValue(null);` add:

```js
    truckRoute.mockResolvedValue(ROUTE_VIEW);
```

Before the last `});` of the file (line 380), add:

```js
  it("asks for the truck route after a successful search and shows it in place of the preview", async () => {
    const el = await mount();
    pickLane(el);
    applySearch(el);
    await settle();
    expect(truckRoute).toHaveBeenCalledTimes(1);
    expect(truckRoute).toHaveBeenCalledWith({
      originKey: "montreal|qc|ca",
      destinationKey: "toronto|on|ca",
      refresh: false
    });
    const routeMap = el.shadowRoot.querySelector("c-route-map");
    expect(routeMap).not.toBeNull();
    expect(routeMap.view.mapUrl).toBe(ROUTE_VIEW.mapUrl);
    expect(routeMap.unit).toBe("mi");
    expect(el.shadowRoot.querySelector("c-lane-benchmark-map")).toBeNull();
    const stats = el.shadowRoot.querySelector("c-lane-benchmark-stats");
    expect(stats.routeView.status).toBe("Found");
    expect(stats.medianMiles).toBe(337.2);
    expect(stats.milesCount).toBe(1);
  });

  it("does not ask for a route when only one end is chosen, and keeps the preview", async () => {
    mapPreviewUrl.mockResolvedValue(
      "https://api.mapbox.com/styles/v1/x/static/auto/600x300?access_token=pk.test"
    );
    const el = await mount();
    pick(el, "origin", {
      key: "montreal|qc|ca",
      label: "Montréal, QC, CA",
      precision: "RADIUS",
      radius: 100,
      unit: "MI"
    });
    applySearch(el);
    await settle();
    expect(search).toHaveBeenCalledTimes(1);
    expect(truckRoute).not.toHaveBeenCalled();
    expect(el.shadowRoot.querySelector("c-route-map")).toBeNull();
    expect(
      el.shadowRoot.querySelector("c-lane-benchmark-map").previewUrl
    ).toContain("api.mapbox.com");
  });

  it("keeps the radius preview under the route map after a radius search", async () => {
    mapPreviewUrl.mockResolvedValue(
      "https://api.mapbox.com/styles/v1/x/static/auto/600x300?access_token=pk.test"
    );
    const el = await mount();
    pick(el, "origin", {
      key: "montreal|qc|ca",
      label: "Montréal, QC, CA",
      precision: "RADIUS",
      radius: 100,
      unit: "MI"
    });
    pick(el, "destination", {
      key: "toronto|on|ca",
      label: "Toronto, ON, CA",
      precision: "CITY",
      radius: null,
      unit: "MI"
    });
    applySearch(el);
    await settle();
    expect(truckRoute).toHaveBeenCalledTimes(1);
    expect(el.shadowRoot.querySelector("c-route-map").view.mapUrl).toBe(
      ROUTE_VIEW.mapUrl
    );
    expect(
      el.shadowRoot.querySelector("c-lane-benchmark-map").previewUrl
    ).toContain("api.mapbox.com");
  });

  it("keeps the preview and the results when the route has no map or the route call fails", async () => {
    truckRoute.mockResolvedValueOnce({
      status: "Unavailable",
      routeType: null,
      routes: [],
      mapUrl: null,
      message: "The truck route is not available right now."
    });
    const el = await mount();
    pickLane(el);
    applySearch(el);
    await settle();
    expect(el.shadowRoot.querySelector("c-route-map")).toBeNull();
    expect(el.shadowRoot.querySelector("c-lane-benchmark-map")).not.toBeNull();
    expect(
      el.shadowRoot.querySelector("c-lane-benchmark-stats").routeView.message
    ).toBe("The truck route is not available right now.");
    truckRoute.mockRejectedValueOnce({
      body: { message: "Unknown place key: toronto|on|ca" }
    });
    applySearch(el);
    await settle();
    expect(truckRoute).toHaveBeenCalledTimes(2);
    expect(
      el.shadowRoot.querySelector("c-lane-benchmark-results").rows.length
    ).toBe(1);
    expect(el.shadowRoot.querySelector('[data-id="error"]')).toBeNull();
    expect(
      el.shadowRoot.querySelector("c-lane-benchmark-stats").routeView
    ).toBeNull();
    expect(el.shadowRoot.querySelector("c-lane-benchmark-map")).not.toBeNull();
  });

  it("refresh route asks again for the same pair without searching again", async () => {
    const el = await mount();
    pickLane(el);
    applySearch(el);
    await settle();
    truckRoute.mockResolvedValueOnce({
      ...ROUTE_VIEW,
      routeType: "Regular",
      miles: 351
    });
    el.shadowRoot
      .querySelector("c-route-map")
      .dispatchEvent(new CustomEvent("refreshroute"));
    await settle();
    expect(truckRoute).toHaveBeenCalledTimes(2);
    expect(truckRoute.mock.calls[1][0]).toEqual({
      originKey: "montreal|qc|ca",
      destinationKey: "toronto|on|ca",
      refresh: true
    });
    expect(el.shadowRoot.querySelector("c-route-map").view.routeType).toBe(
      "Regular"
    );
    expect(search).toHaveBeenCalledTimes(1);
  });

  it("drops a route answer that belongs to an earlier search", async () => {
    let resolveFirst;
    truckRoute.mockImplementationOnce(
      () =>
        new Promise((resolve) => {
          resolveFirst = resolve;
        })
    );
    const el = await mount();
    pickLane(el);
    applySearch(el);
    await settle();
    pick(el, "destination", {
      key: "ottawa|on|ca",
      label: "Ottawa, ON, CA",
      precision: "CITY",
      radius: null,
      unit: "MI"
    });
    truckRoute.mockResolvedValueOnce({ ...ROUTE_VIEW, miles: 124.8 });
    applySearch(el);
    await settle();
    resolveFirst({ ...ROUTE_VIEW, miles: 336.9 });
    await settle();
    expect(truckRoute).toHaveBeenCalledTimes(2);
    expect(truckRoute.mock.calls[1][0].destinationKey).toBe("ottawa|on|ca");
    expect(el.shadowRoot.querySelector("c-route-map").view.miles).toBe(124.8);
  });

  it("starts from the saved unit, follows the distance unit channel and unsubscribes when removed", async () => {
    writeUnit("km");
    subscribe.mockReturnValueOnce({ channel: "unit" });
    const el = await mount();
    expect(subscribe).toHaveBeenCalledTimes(1);
    expect(subscribe.mock.calls[0][1]).toBe(DISTANCE_UNIT);
    expect(subscribe.mock.calls[0][3]).toEqual({ scope: APPLICATION_SCOPE });
    const onUnit = subscribe.mock.calls[0][2];
    pickLane(el);
    applySearch(el);
    await settle();
    const results = () =>
      el.shadowRoot.querySelector("c-lane-benchmark-results");
    expect(results().unit).toBe("km");
    onUnit({ unit: "mi" });
    await flush();
    expect(results().unit).toBe("mi");
    expect(el.shadowRoot.querySelector("c-lane-benchmark-stats").unit).toBe(
      "mi"
    );
    expect(el.shadowRoot.querySelector("c-route-map").unit).toBe("mi");
    onUnit({ unit: "furlongs" });
    await flush();
    expect(results().unit).toBe("mi");
    document.body.removeChild(el);
    expect(unsubscribe).toHaveBeenCalledWith({ channel: "unit" });
  });
```

- [ ] **Step 10: Run the page tests to see them fail**

```bash
npm run test:unit -- force-app/main/default/lwc/laneBenchmark/
```

(The trailing slash keeps Jest from also matching `laneBenchmarkStats`, `laneBenchmarkResults` and the other `laneBenchmark*` folders.)

Expected: `Tests: 5 failed, 10 passed, 15 total`. "asks for the truck route…", "keeps the preview…", "refresh route…", "drops a route answer…" and "starts from the saved unit…" fail (in that order: `expect(jest.fn()).toHaveBeenCalledTimes(expected)` with `Expected number of calls: 1` for `truckRoute`; `TypeError: Cannot read properties of undefined (reading 'message')`; `TypeError: Cannot read properties of null (reading 'dispatchEvent')`; `TypeError: resolveFirst is not a function`; `Expected number of calls: 1` for `subscribe`). "does not ask for a route when only one end is chosen" already passes: it guards the rule the implementation must keep. The nine existing tests still pass.

- [ ] **Step 11: Lane Benchmark page — fetch the route, swap the map, hold the unit**

Replace the whole of `force-app/main/default/lwc/laneBenchmark/laneBenchmark.js` with:

```js
import { LightningElement, track, wire } from "lwc";
import search from "@salesforce/apex/LaneBenchmarkController.search";
import getFilterOptions from "@salesforce/apex/LaneBenchmarkController.getFilterOptions";
import mapPreviewUrl from "@salesforce/apex/LaneBenchmarkController.mapPreviewUrl";
import truckRoute from "@salesforce/apex/LaneBenchmarkController.truckRoute";
import {
  subscribe,
  unsubscribe,
  MessageContext,
  APPLICATION_SCOPE
} from "lightning/messageService";
import DISTANCE_UNIT from "@salesforce/messageChannel/Distance_Unit__c";
import { load, save, clear } from "c/laneBenchmarkStorage";
import { DEFAULT_FILTERS, cloneDefaults } from "c/laneBenchmarkFilters";
import { readUnit } from "c/distanceUnit";

const LONG_RADIUS_DAYS = 365;

function emptyRequest() {
  return {
    originKey: null,
    originLabel: "",
    originPrecision: "CITY",
    originRadius: null,
    destinationKey: null,
    destinationLabel: "",
    destinationPrecision: "CITY",
    destinationRadius: null,
    radiusUnit: "MI",
    marginPct: 15,
    ...cloneDefaults()
  };
}

export default class LaneBenchmark extends LightningElement {
  @track request = emptyRequest();
  filterOptions = {
    modes: [],
    equipmentByCategory: {},
    currencies: ["CAD", "USD"]
  };
  result = null;
  error = null;
  isSearching = false;
  elapsedSeconds = 0;
  needsConfirmation = false;
  previewUrl = null;
  ticker = null;
  // the request as it was when the last successful search ran, so a margin-only
  // edit can be saved without persisting unapplied filter changes
  lastSearched = null;
  // Phase 7: the truck route for the searched place pair (TripRouteView). Fetched after the
  // search, not awaited by it: a Mapbox route can take several seconds and the results must not wait.
  routeView = null;
  isRouteLoading = false;
  // bumped by every route request and every reset; an answer carrying an older ticket belongs
  // to an earlier search and is dropped
  routeTicket = 0;
  // 'mi' | 'km' for the whole page: starts from this browser's choice and follows
  // Distance_Unit__c, which c-distance-unit-toggle (in the statistics card) publishes on
  unit = readUnit();
  unitSubscription = null;

  @wire(MessageContext)
  messageContext;

  get filters() {
    const f = {};
    Object.keys(DEFAULT_FILTERS).forEach((k) => {
      f[k] = this.request[k];
    });
    return f;
  }
  get rows() {
    return this.result ? this.result.rows : [];
  }
  get statsByCurrency() {
    return this.result ? this.result.statsByCurrency : {};
  }
  get hasResult() {
    return !!this.result;
  }
  get showEmptyState() {
    return !this.hasResult && !this.isSearching;
  }
  get isRadiusSearch() {
    return (
      this.request.originPrecision === "RADIUS" ||
      this.request.destinationPrecision === "RADIUS"
    );
  }
  get medianMiles() {
    return this.result ? this.result.medianMiles : null;
  }
  /** Load rows whose billed miles fed the median (bid rows carry none). */
  get milesCount() {
    return this.rows.filter((r) => r.load && Number(r.load.miles) > 0).length;
  }
  /** The route image shows whenever there is one to draw. */
  get hasRouteMap() {
    return !!(this.routeView && this.routeView.mapUrl);
  }
  /**
   * The preview keeps its place after a radius search, under the route image: its circles show
   * the matched area (spec §5). After any other search the route image takes its place (spec §6).
   */
  get showPreview() {
    const s = this.lastSearched;
    const radius =
      !!s &&
      (s.originPrecision === "RADIUS" || s.destinationPrecision === "RADIUS");
    return !this.hasRouteMap || radius;
  }

  async connectedCallback() {
    // subscribe before the first await, so a unit published while the options load is not missed
    this.unitSubscription = subscribe(
      this.messageContext,
      DISTANCE_UNIT,
      (message) => this.handleUnit(message),
      { scope: APPLICATION_SCOPE }
    );
    try {
      this.filterOptions = await getFilterOptions();
    } catch (e) {
      this.error = this.messageOf(e);
    }
    const saved = load();
    if (saved) {
      this.request = { ...emptyRequest(), ...saved };
      this.runSearch();
    }
  }

  disconnectedCallback() {
    window.clearInterval(this.ticker);
    if (this.unitSubscription) {
      unsubscribe(this.unitSubscription);
    }
    this.unitSubscription = null;
  }

  handleUnit(message) {
    const unit = message && message.unit;
    if (unit === "mi" || unit === "km") {
      this.unit = unit;
    }
  }

  handleOrigin(event) {
    const d = event.detail;
    this.request = {
      ...this.request,
      originKey: d.key,
      originLabel: d.label,
      originPrecision: d.precision,
      originRadius: d.radius,
      radiusUnit: d.unit || this.request.radiusUnit
    };
  }
  handleDestination(event) {
    const d = event.detail;
    this.request = {
      ...this.request,
      destinationKey: d.key,
      destinationLabel: d.label,
      destinationPrecision: d.precision,
      destinationRadius: d.radius,
      radiusUnit: d.unit || this.request.radiusUnit
    };
  }
  handleFilters(event) {
    this.request = { ...this.request, ...event.detail };
  }
  handleMargin(event) {
    const marginPct = event.detail.marginPct;
    this.request = { ...this.request, marginPct };
    // only persist a margin tweak against the request that was actually searched;
    // unapplied filter edits in this.request must not leak into storage
    if (this.lastSearched) {
      save({ ...this.lastSearched, marginPct });
    }
  }
  handleReset() {
    // reset only the filter keys (lookback, currency, modes, equipment, flags,
    // accepted status); places, precisions, radii, unit and margin are untouched
    this.request = { ...this.request, ...cloneDefaults() };
  }
  handleClearSaved() {
    clear();
    this.request = emptyRequest();
    this.result = null;
    this.previewUrl = null;
    this.clearRoute();
    this.lastSearched = null;
    this.error = null;
    this.needsConfirmation = false;
  }

  handleApply() {
    if (this.isSearching) {
      return;
    }
    if (
      this.isRadiusSearch &&
      Number(this.request.lookbackDays) > LONG_RADIUS_DAYS
    ) {
      this.needsConfirmation = true;
      return;
    }
    this.runSearch();
  }
  handleContinue() {
    if (this.isSearching) {
      return;
    }
    this.needsConfirmation = false;
    this.runSearch();
  }
  handleCancel() {
    this.needsConfirmation = false;
  }

  toServiceRequest() {
    const r = this.request;
    return {
      originKey: r.originKey,
      destinationKey: r.destinationKey,
      originPrecision: r.originPrecision,
      destinationPrecision: r.destinationPrecision,
      originRadius: r.originPrecision === "RADIUS" ? r.originRadius : null,
      destinationRadius:
        r.destinationPrecision === "RADIUS" ? r.destinationRadius : null,
      radiusUnit: r.radiusUnit,
      lookbackDays: r.lookbackDays,
      currencyIsoCode: r.currencyIsoCode,
      modes: r.modes,
      equipmentCategories: r.equipmentCategories,
      equipmentTypes: r.equipmentTypes,
      hazmatOnly: r.hazmatOnly,
      marketTestOnly: r.marketTestOnly,
      acceptedFilter: r.acceptedFilter,
      sourceFilter: r.sourceFilter,
      rowLimit: 2000,
      includeStopGeolocation: true
    };
  }

  async runSearch() {
    this.needsConfirmation = false;
    this.error = null;
    this.isSearching = true;
    this.elapsedSeconds = 0;
    window.clearInterval(this.ticker);
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    this.ticker = window.setInterval(() => {
      this.elapsedSeconds += 1;
    }, 1000);
    const svc = this.toServiceRequest();
    try {
      this.result = await search({ requestJson: JSON.stringify(svc) });
      // the search succeeded: keep it even if the map preview below fails
      this.lastSearched = { ...this.request };
      save(this.request);
      // not awaited: the route runs beside the preview and never holds the results back
      this.loadRoute(svc.originKey, svc.destinationKey, false);
      try {
        this.previewUrl = await mapPreviewUrl({
          originKey: svc.originKey,
          originRadius: svc.originRadius,
          destinationKey: svc.destinationKey,
          destinationRadius: svc.destinationRadius,
          unit: svc.radiusUnit
        });
      } catch {
        // map preview is a nice-to-have; a failure here (no token, a place with no
        // coordinates, Mapbox down) must not wipe the search result or show an error
        this.previewUrl = null;
      }
    } catch (e) {
      this.result = null;
      this.previewUrl = null;
      this.clearRoute();
      this.error = this.messageOf(e);
    } finally {
      window.clearInterval(this.ticker);
      this.isSearching = false;
    }
  }

  /**
   * Asks LaneBenchmarkController.truckRoute for the pair's route: the stored one, or Mapbox
   * when there is none or refresh is true. Needs both ends; never throws.
   */
  async loadRoute(originKey, destinationKey, refresh) {
    this.routeTicket += 1;
    const ticket = this.routeTicket;
    if (!refresh) {
      this.routeView = null;
    }
    if (!originKey || !destinationKey) {
      this.isRouteLoading = false;
      return;
    }
    this.isRouteLoading = true;
    try {
      const view = await truckRoute({ originKey, destinationKey, refresh });
      if (ticket === this.routeTicket) {
        this.routeView = view;
      }
    } catch {
      // the route is a nice-to-have like the preview: a failure keeps the results, and a
      // failed refresh keeps the route already shown
    } finally {
      if (ticket === this.routeTicket) {
        this.isRouteLoading = false;
      }
    }
  }
  handleRefreshRoute() {
    if (!this.lastSearched || this.isRouteLoading) {
      return;
    }
    this.loadRoute(
      this.lastSearched.originKey,
      this.lastSearched.destinationKey,
      true
    );
  }
  clearRoute() {
    this.routeTicket += 1;
    this.routeView = null;
    this.isRouteLoading = false;
  }

  messageOf(e) {
    return (
      (e && e.body && e.body.message) ||
      (e && e.message) ||
      "Something went wrong"
    );
  }
}
```

In `force-app/main/default/lwc/laneBenchmark/laneBenchmark.html`, replace the `hasResult` block (lines 91-107):

```html
      <template lwc:if={hasResult}>
        <c-lane-benchmark-stats
          stats-by-currency={statsByCurrency}
          deduped-count={result.dedupedCount}
          truncated={result.truncated}
          elapsed-ms={result.elapsedMs}
          row-count={rows.length}
          margin-pct={request.marginPct}
          onmarginchange={handleMargin}
        ></c-lane-benchmark-stats>
        <c-lane-benchmark-map preview-url={previewUrl}></c-lane-benchmark-map>
        <c-lane-benchmark-results
          rows={rows}
          origin-label={request.originLabel}
          destination-label={request.destinationLabel}
        ></c-lane-benchmark-results>
      </template>
```

with

```html
      <template lwc:if={hasResult}>
        <c-lane-benchmark-stats
          stats-by-currency={statsByCurrency}
          deduped-count={result.dedupedCount}
          truncated={result.truncated}
          elapsed-ms={result.elapsedMs}
          row-count={rows.length}
          margin-pct={request.marginPct}
          median-miles={medianMiles}
          miles-count={milesCount}
          route-view={routeView}
          route-loading={isRouteLoading}
          unit={unit}
          onmarginchange={handleMargin}
        ></c-lane-benchmark-stats>
        <template lwc:if={hasRouteMap}>
          <div class="slds-m-bottom_small">
            <c-route-map
              view={routeView}
              loading={isRouteLoading}
              unit={unit}
              onrefreshroute={handleRefreshRoute}
            ></c-route-map>
          </div>
        </template>
        <template lwc:if={showPreview}>
          <c-lane-benchmark-map preview-url={previewUrl}></c-lane-benchmark-map>
        </template>
        <c-lane-benchmark-results
          rows={rows}
          unit={unit}
          origin-label={request.originLabel}
          destination-label={request.destinationLabel}
        ></c-lane-benchmark-results>
      </template>
```

- [ ] **Step 12: Run the three suites, the whole Jest run and ESLint**

```bash
npm run test:unit -- force-app/main/default/lwc/laneBenchmark/ force-app/main/default/lwc/laneBenchmarkStats force-app/main/default/lwc/laneBenchmarkResults
npm run test:unit 2>&1 | grep -E "^(Tests|Test Suites):"
npx eslint force-app/main/default/lwc/laneBenchmark force-app/main/default/lwc/laneBenchmarkStats force-app/main/default/lwc/laneBenchmarkResults
npx prettier --check force-app/main/default/lwc/laneBenchmark force-app/main/default/lwc/laneBenchmarkStats force-app/main/default/lwc/laneBenchmarkResults
```

Expected: the three suites `Tests: 31 passed, 31 total` (16 + 7 + 8); the full run prints `Test Suites: 39 passed, 39 total` and `Tests: 361 passed, 361 total` with no `failed` (Task 9's 349 plus 12 new tests: +7 page, +3 statistics, +2 results; no new suite); ESLint prints nothing and exits 0; Prettier prints `All matched files use Prettier code style!` (if it lists a file, run `npx prettier --write` on that file and re-run the three suites; lint-staged would do the same on commit). If a new page test times out on `settle()` (a route answer landing one render later than counted), add one more `.then(flush)` to `settle`, never a `setTimeout`.

- [ ] **Step 13: Deploy the three bundles to PostProduc**

Task 7 (`LaneBenchmarkController.truckRoute`) and Task 8 (`distanceUnit`, `distanceUnitToggle`, `routeMap`, `Distance_Unit__c`) must already be in the org; the LWC compiler refuses a bundle that references a missing Apex method or message channel.

```bash
sf project deploy start --source-dir force-app/main/default/lwc/laneBenchmark --source-dir force-app/main/default/lwc/laneBenchmarkStats --source-dir force-app/main/default/lwc/laneBenchmarkResults -o sandbox -l NoTestRun --async --json
```

Expected: JSON (parse from the first `{`; the CLI may print an update warning first) with `"status": 0` and `result.id` (a `0Af…` id). `__tests__` folders are excluded by `.forceignore`. Then poll, re-running the same command while `result.status` is `Pending` or `InProgress` (each call returns within 2 minutes):

```bash
sf project deploy report -o sandbox --job-id <result.id from the previous command> -w 2 --json
```

Expected: `result.status` `Succeeded`, `result.numberComponentErrors` 0, `result.numberComponentsDeployed` 3. `Unable to find Apex action method referenced as 'LaneBenchmarkController.truckRoute'` means Task 7 is not deployed; a problem naming `Distance_Unit__c`, `c-route-map` or `c-distance-unit-toggle` means Task 8 is not; deploy that task first, then re-run this step. Record the deploy id for the spec Outcome (Task 11).

- [ ] **Step 14: Commit**

```bash
git status --short force-app/main/default/lwc/laneBenchmark force-app/main/default/lwc/laneBenchmarkStats force-app/main/default/lwc/laneBenchmarkResults
git add force-app/main/default/lwc/laneBenchmark force-app/main/default/lwc/laneBenchmarkStats force-app/main/default/lwc/laneBenchmarkResults
git commit -m "Show trip miles, the truck route and rate per mile on Lane Benchmark"
```

Expected: the status lists exactly nine modified files (`laneBenchmark.js`, `laneBenchmark.html`, `laneBenchmark.test.js`, `laneBenchmarkStats.js`, `laneBenchmarkStats.html`, `laneBenchmarkStats.test.js`, `laneBenchmarkResults.js`, `laneBenchmarkResults.html`, `laneBenchmarkResults.test.js`) and no name containing ` 2.`; the pre-commit hook (lint-staged: Prettier and ESLint) passes; the commit shows `9 files changed`. `.vscode/settings.json` stays unstaged.

#### Contract notes (Task 10)

1. **Miles path follows Tasks 4 and 5: `row.load.miles`, not `row.miles`.** `LaneSearchResult.Row` is already at PMD's 20-field cap: on a scratch copy of the class, PMD 7.15.0 with `config/pmd-ruleset.xml` reports `TooManyFields` at `LaneSearchResult.cls:7` for a plain `miles` field. Task 4 fixes this by moving `loadId` into a new `LoadDetail load` holding `loadId` and `miles` (Task 5 fills `miles`), and every later task uses that path. Task 10 reads `r.load.miles` in two places, `laneBenchmarkResults` `viewRows.milesText` and `laneBenchmark` `milesCount`. The CSV column is `{ label: "Miles", field: "load.miles" }`, not the contract's `field: 'miles'`; `laneBenchmarkCsv`'s `valueAt` already follows dotted paths, as `carrier.contactEmail` does. The test fixtures carry `load: { loadId, miles }`.
2. **One unit subscription per page.** `c-lane-benchmark` subscribes to `Distance_Unit__c` (Task 8's subscriber pattern, `APPLICATION_SCOPE`, starting from `readUnit()`) and passes `unit` down as `@api` to `c-lane-benchmark-stats`, `c-lane-benchmark-results` and `c-route-map`. Both child components only ever render inside `c-lane-benchmark`, and `c-route-map` already takes `@api unit` in the contract, so three separate subscriptions would carry the same value. Only `c-distance-unit-toggle` (Task 8) keeps its own subscription, so its pressed state stays right.
3. **Radius circles vs route map.** Spec §5 says "The Lane Benchmark radius circles stay when a radius search is shown", and §6 says `c-route-map` replaces the plain preview when a truck route is available. Both hold: after a radius search the radius preview stays under the route image (`showPreview` reads `lastSearched`), and after any other search the route image takes the preview's place. `RouteMapUrl.build` draws no circles. The preview also stays whenever there is no route image (one end missing, `No route`, `Unavailable`, or a failed call). Controller ruling during planning; the Outcome records it as difference 2.
4. **"Whenever both keys are set" applies to every precision.** `laneBenchmarkPlacePicker.emit()` sends `key: this.value`, the picked `Pricing_Place__c.Key__c`, for City, Province/State, Postal prefix and Radius alike, so the route always runs between the two picked places.
5. **The route does not hold up the search.** `loadRoute` starts right after the search succeeds and is not awaited. Results and the preview show first; the statistics card says "Truck route: finding the route…" during the first load, and `c-route-map`'s `loading` covers a refresh. Each request carries a ticket, so an answer from an earlier search is dropped. A thrown `truckRoute` error is silent, like the preview's: no error banner, results kept, and a failed refresh keeps the route already shown. Mapbox problems come back as `status: 'Unavailable'` with the server's message, shown in the route line.
6. **New public properties the contract did not name.** Stats: `medianMiles`, `milesCount`, `routeView`, `routeLoading`, `unit`. Results: `unit`. `c-route-map`'s `@api hazmat` is left unset, as Task 8's contract note 5 says for Lane Benchmark (a hazmat-only search is not a hazmat lane record).
7. **Labels and values.** "Rate per mile (median)" becomes "Rate per km (median)" in km, computed as `perDistance(ratePerMileMedian, 1, unit)`; `null` shows "—". The results header reads "Miles" or "Km" with the unit. The CSV column is always raw miles under the label `Miles`, inserted after "Carrier total" (not at the end, because an existing test asserts that "Expires on" is the last header). A load row whose miles are `null` or `0` shows "—" rather than "0 mi". A `No route` answer reads "Truck route: —" (spec §7); only an `Unavailable` answer appends the server's message.
8. **No manifest or `laneBenchmarkMap` change.** All three bundles are already manifest members (lines 31-34); `c-lane-benchmark-map` keeps rendering the plain or radius preview.

---

### Task 11: Guide, README, roster, roadmap, Outcome, final deploy

**Files:**

- Modify: `docs/help/en/rfp-history.md`, `docs/help/fr/rfp-history.md` (new `## Trip miles and truck routes` section appended after line 28, the currency sentence)
- Modify: `docs/help/en/rfp-pricing.md`, `docs/help/fr/rfp-pricing.md` (new `## Trip miles and truck routes` section inserted between `## Save` (lines 21–23) and `## Results` (line 25))
- Modify: `docs/help/en/lb-stats.md`, `docs/help/fr/lb-stats.md` (new `## Trip miles and truck routes` section inserted between `## Margin and suggested sell` (lines 11–13) and `## Duplicates` (line 15))
- Modify: `docs/help/en/rfp-inline.md`, `docs/help/fr/rfp-inline.md` (new `## The Miles column` section appended after line 23, the twins paragraph)
- Modify: `force-app/main/default/staticresources/helpCenter/en/{rfp-history,rfp-pricing,lb-stats,rfp-inline}.html` and the four `fr/` twins (rebuilt by `npm run help:build`; the front matter and `index.json` do not change)
- Modify: `README.md` — Apex roster at lines 26, 103, 110 and 389; inventory rows after line 25 (`classes/MapboxGeocoder`) after the phase 3a data row (`objects/RFP_Project__c/*`) and after the help center UI row (`lwc/helpCenter`); the two Security rows (`permissionsets/Lane_Benchmark_User`, line 29; `permissionsets/RFP_Tool_User`, line 37); new section `## Trip miles (phase 7)` between `## Access model (phase 6)` and `## Help center (phase 5)` (line 648). Line numbers are those on the branch before this task; do the roster edit first, it changes no line count.
- Modify: `.github/workflows/ci.yml` (line 59, the `--tests` roster)
- Modify: `docs/superpowers/specs/2026-09-07-pricing-department-roadmap.md` (row 7 after row 6, line 53)
- Modify: `docs/superpowers/specs/2026-09-14-phase-7-trip-miles-design.md` (append `## Outcome — phase 7` after line 124)

**Interfaces:**

- Consumes (documents, does not call): Tasks 1–10 — `RFP_Lane__c.Miles__c` / `Miles_Source__c` / `Route_Hours__c`; `Truck_Route__c` and its `Route_Key__c`; `Truck_Routing_Setting__mdt` record `Default`; `MapboxHttp`, `TruckRoute`, `MapboxTruckRoute`, `RouteMapUrl`, `TripMilesService`, `TripRouteView`; `RfpLaneController.laneRoute`, `LaneBenchmarkController.truckRoute`; `LaneSearchResult.Row.load.miles`, `LaneSearchResult.medianMiles`, `LaneSearchResult.Stats.ratePerMileMedian`; LWC `c/distanceUnit`, `c-distance-unit-toggle`, `c-route-map`, message channel `Distance_Unit__c`; the new test classes `MapboxTruckRouteTest`, `RouteMapUrlTest`, `TripMilesServiceTest`.
- Produces: none in code. The Apex roster becomes 26 classes, in this order everywhere it appears (README lines 26, 103, 110, 389 and `ci.yml` line 59): `LaneSearchExclusionsTest PlaceNormalizerTest PricingTestDataFactoryTest PlaceBuilderBatchTest LaneSearchServiceTest MapboxGeocoderTest LaneBenchmarkControllerTest LaneBenchmarkPlaceServiceTest RfpTestDataFactoryTest BenchmarkRateServiceTest BidSearchQueryBuilderTest BidSearchServiceTest RfpControllerTest RfpSecurityTest RfpBidAccessTest MapboxTruckRouteTest RouteMapUrlTest TripMilesServiceTest RfpImportServiceTest RfpLaneControllerTest RfpHistoryServiceTest RfpProjectControllerTest RfpBidControllerTest RfpPricingMathTest RfpBulkServiceTest RfpBulkControllerTest`.

- [ ] **Step 1: Guide — Loading history and Pricing a lane**

Leave every front-matter block untouched (the `hint` lines are near the 240-character limit and `index.json` must not change).

Append to `docs/help/en/rfp-history.md`, after the last line (`Statistics use only quotes in the lane's own currency.`), with one blank line before:

```markdown
## Trip miles and truck routes

Load history also fills the **Miles** of every lane it runs, without asking Mapbox. It takes the first of these that exists:

1. **History**: the median of the billed miles (Revenova's Distance (Miles), filled by PC\*Miler) on the loads the search matched, at the precision the history used. Bids have no miles and do not count.
2. **Truck route** or **Regular route**: the miles and drive hours of a route already stored for the lane's two places, from an earlier lane opening or Lane Benchmark search.
3. **Approx**: the straight-line distance between the two places × 1.2, the ratio measured on a year of billed loads.

A lane gets **No coordinates** when an end is not resolved to a place or has no position on the map, and **No route** when Mapbox found no road between the two places. Billed miles always win: opening a lane never replaces History miles with route miles. Direction matters: Montréal → Toronto and Toronto → Montréal are separate routes.
```

Append to `docs/help/fr/rfp-history.md`, after the last line (`Les statistiques n'utilisent que les cotations dans la devise de la voie.`), with one blank line before:

```markdown
## Milles du trajet et itinéraires de camion

**Load history** remplit aussi la colonne **Miles** de chaque voie traitée, sans interroger Mapbox. Il prend la première source disponible :

1. **History** : la médiane des milles facturés (le champ Distance (Miles) de Revenova, rempli par PC\*Miler) sur les chargements trouvés par la recherche, à la précision utilisée par l'historique. Les soumissions n'ont pas de milles et ne comptent pas.
2. **Truck route** ou **Regular route** : les milles et les heures de route d'un itinéraire déjà enregistré pour les deux lieux de la voie, lors de l'ouverture d'une voie ou d'une recherche Lane Benchmark.
3. **Approx** : la distance à vol d'oiseau entre les deux lieux × 1,2, le rapport mesuré sur un an de chargements facturés.

Une voie reçoit **No coordinates** quand une extrémité n'est pas associée à un lieu ou n'a pas de position sur la carte, et **No route** quand Mapbox n'a trouvé aucune route entre les deux lieux. Les milles facturés ont toujours priorité : ouvrir une voie ne remplace jamais des milles History par ceux d'un itinéraire. Le sens compte : Montréal → Toronto et Toronto → Montréal sont deux itinéraires distincts.
```

In `docs/help/en/rfp-pricing.md`, insert immediately before `## Results` (keep one blank line on each side):

```markdown
## Trip miles and truck routes

Under the lane title, the panel shows the lane's miles and where they come from (see **Loading history**). Beside the prices, **Cost per mile** and **Sell per mile** divide the cost and the sell by those miles and follow what you type.

The **mi** and **km** buttons in the toolbar, next to **Include RFP bids**, switch the table, the panel and the map legend between miles and kilometres; per-mile values become per-km values. The choice is remembered in this browser, and Lane Benchmark opens with the same unit.

When the panel opens, it draws the route on the map: pin A at the origin, pin B at the destination, the main route as a thick blue line and up to two alternatives in orange and grey. The legend gives each route's distance and drive hours. A **Truck route** keeps to the truck limits of the Truck Routing Setting (by default 4.11 m high, 2.6 m wide, 36.29 t); when Mapbox cannot keep to them, the panel shows a regular driving route instead, headed "Regular route — truck limits could not be met". Mapbox has no hazmat option, so a hazmat lane gets the same route as any other lane.

The route is asked from Mapbox once per pair of places and stored; reopening the lane reuses it. **Refresh route** asks Mapbox again and replaces the stored route. When the lane's miles do not come from History, the route's miles and hours are written to the lane (Truck route or Regular route); History miles are never replaced. If Mapbox cannot be reached, the panel says "The truck route is not available right now." and the lane keeps its miles. When Mapbox finds no road even without truck limits (across water without a ferry, for example), the lane shows **No route**.

The Excel export carries Miles, Km, Miles source, Route hours, Cost per mile and Sell per mile for every lane.
```

In `docs/help/fr/rfp-pricing.md`, insert immediately before `## Résultats`:

```markdown
## Milles du trajet et itinéraires de camion

Sous le titre de la voie, le panneau affiche ses milles et leur source (voir **Charger l'historique**). À côté des prix, **Cost per mile** et **Sell per mile** divisent le coût et le prix de vente par ces milles et suivent ce que vous tapez.

Les boutons **mi** et **km** de la barre d'outils, à côté de **Include RFP bids**, font passer le tableau, le panneau et la légende de la carte des milles aux kilomètres; les valeurs par mille deviennent des valeurs par kilomètre. Le choix est retenu dans ce navigateur, et Lane Benchmark s'ouvre avec la même unité.

À l'ouverture du panneau, l'itinéraire s'affiche sur la carte : l'épingle A au point de départ, l'épingle B à la destination, l'itinéraire principal en trait bleu épais et jusqu'à deux variantes en orange et en gris. La légende donne la distance et les heures de route de chaque itinéraire. Un **Truck route** respecte les limites du camion du Truck Routing Setting (par défaut 4,11 m de haut, 2,6 m de large, 36,29 t); quand Mapbox ne peut pas les respecter, le panneau affiche plutôt un itinéraire routier ordinaire, sous le titre « Regular route — truck limits could not be met ». Mapbox n'a pas d'option pour les matières dangereuses : une voie hazmat reçoit le même itinéraire que les autres.

L'itinéraire est demandé une seule fois à Mapbox par paire de lieux, puis enregistré; rouvrir la voie le réutilise. **Refresh route** interroge Mapbox de nouveau et remplace l'itinéraire enregistré. Quand les milles de la voie ne viennent pas de History, les milles et les heures de l'itinéraire sont écrits sur la voie (Truck route ou Regular route); des milles History ne sont jamais remplacés. Si Mapbox ne répond pas, le panneau indique « The truck route is not available right now. » et la voie garde ses milles. Quand Mapbox ne trouve aucune route, même sans limites de camion (de l'autre côté d'un plan d'eau sans traversier, par exemple), la voie affiche **No route**.

L'export Excel contient, pour chaque voie, les colonnes Miles, Km, Miles source, Route hours, Cost per mile et Sell per mile.
```

- [ ] **Step 2: Guide — Reading the statistics and Editing in the table, then rebuild**

In `docs/help/en/lb-stats.md`, insert immediately before `## Duplicates`:

```markdown
## Trip miles and truck routes

The **Statistics** card also shows how long the trip is:

- **Trip: 1,234 mi · median of 12 loads**: the median of the billed miles on the matched loads. Bids have no miles and do not count.
- **Truck route: 1,260 mi · 21.5 h**: the Mapbox truck route between the two places, with its drive hours. **Regular route** instead means the truck limits could not be met, so a regular driving route is shown.

Each currency box adds **Rate per mile (median)**: the median of each priced quote's total divided by its load's miles, in that box's currency.

After a search with both an origin and a destination, the map draws the truck route (pins A and B, the main route and up to two alternatives, a legend line per route) in place of the plain preview; a radius search keeps its radius preview under the route, and when no route is available the preview stays. The route is asked from Mapbox once per pair of places and stored, so the next search on the same lane reuses it; **Refresh route** asks again. The results table has a **Miles** column (bids show "—"), and the CSV export carries it.

The **mi** and **km** buttons in the card header switch every distance on the page, per-mile rates included. The choice is remembered in this browser, and the RFP Tool uses it too.
```

In `docs/help/fr/lb-stats.md`, insert immediately before `## Doublons`:

```markdown
## Milles du trajet et itinéraires de camion

L'encadré **Statistics** indique aussi la longueur du trajet :

- **Trip: 1,234 mi · median of 12 loads** : la médiane des milles facturés sur les chargements trouvés. Les soumissions n'ont pas de milles et ne comptent pas.
- **Truck route: 1,260 mi · 21.5 h** : l'itinéraire de camion Mapbox entre les deux lieux, avec ses heures de route. **Regular route** signifie plutôt que les limites du camion n'ont pas pu être respectées : un itinéraire routier ordinaire est affiché.

Chaque boîte de devise ajoute **Rate per mile (median)** : la médiane du total de chaque cotation tarifée divisé par les milles de son chargement, dans la devise de la boîte.

Après une recherche qui a une origine et une destination, la carte trace l'itinéraire de camion (épingles A et B, l'itinéraire principal et jusqu'à deux variantes, une ligne de légende par itinéraire) à la place de l'aperçu simple; une recherche par rayon garde son aperçu des rayons sous l'itinéraire, et sans itinéraire, l'aperçu reste. L'itinéraire est demandé une seule fois à Mapbox par paire de lieux, puis enregistré : la recherche suivante sur la même voie le réutilise, et **Refresh route** le redemande. Le tableau des résultats a une colonne **Miles** (les soumissions affichent « — »), et l'export CSV la contient.

Les boutons **mi** et **km** dans l'en-tête de l'encadré changent toutes les distances de la page, taux par mille compris. Le choix est retenu dans ce navigateur, et l'onglet RFP Tool l'utilise aussi.
```

Append to `docs/help/en/rfp-inline.md`, after the last line (the `**Apply** copies; **Not now** dismisses.` paragraph), with one blank line before:

```markdown
## The Miles column

**Miles**, after **History**, is read-only: it shows the lane's trip length in miles, or in kilometres when **km** is selected in the toolbar. A small tag says where the value comes from:

- No tag: **History**, the median of the billed miles on the matched loads.
- `truck`: a Mapbox truck route.
- `route`: a regular driving route, used when the truck limits could not be met.
- `approx.`: the straight-line distance between the two places × 1.2.

"—" means the lane has no distance: hover it for the reason (history not loaded yet, no route found, or no coordinates). Load history fills the column. Opening a lane stores its route and replaces an `approx.` value with the route's miles when Mapbox finds one; the column shows the new value after your next price save, history run or page reload.
```

Append to `docs/help/fr/rfp-inline.md`, after the last line (the `**Apply** copie; **Not now** refuse.` paragraph), with one blank line before:

```markdown
## La colonne Miles

La colonne **Miles**, après **History**, n'est pas modifiable : elle affiche la longueur du trajet de la voie en milles, ou en kilomètres quand **km** est choisi dans la barre d'outils. Une petite étiquette indique la provenance de la valeur :

- Sans étiquette : **History**, la médiane des milles facturés sur les chargements trouvés.
- `truck` : un itinéraire de camion Mapbox.
- `route` : un itinéraire routier ordinaire, utilisé quand les limites du camion n'ont pas pu être respectées.
- `approx.` : la distance à vol d'oiseau entre les deux lieux × 1,2.

« — » signifie que la voie n'a pas de distance : survolez-le pour voir la raison (historique pas encore chargé, aucune route trouvée ou pas de coordonnées). **Load history** remplit la colonne. Ouvrir une voie enregistre son itinéraire et remplace une valeur `approx.` par les milles de l'itinéraire quand Mapbox en trouve un; la colonne affiche la nouvelle valeur après le prochain enregistrement de prix, chargement d'historique ou rechargement de la page.
```

Run: `npm run help:build && npm run help:check`
Expected: `built 15 sections into force-app/main/default/staticresources/helpCenter`, then `helpCenter is up to date`.

Run: `git status --short force-app/main/default/staticresources/helpCenter docs/help`
Expected exactly these 16 lines, all ` M`: `docs/help/en/lb-stats.md`, `docs/help/en/rfp-history.md`, `docs/help/en/rfp-inline.md`, `docs/help/en/rfp-pricing.md`, the four `docs/help/fr/` twins, `force-app/main/default/staticresources/helpCenter/en/lb-stats.html`, `.../en/rfp-history.html`, `.../en/rfp-inline.html`, `.../en/rfp-pricing.html` and the four `.../fr/` twins. `index.json` is not listed.

Run: `grep -c "PC\*Miler" force-app/main/default/staticresources/helpCenter/en/rfp-history.html force-app/main/default/staticresources/helpCenter/fr/rfp-history.html`
Expected: `1` for each file (the escaped asterisk renders as a literal `*`, not as emphasis).

- [ ] **Step 3: Apex roster (README and CI) to 26 classes**

The three new classes go after `RfpBidAccessTest`, in this order, in all five places. Run from the repo root:

```bash
python3 - <<'PY'
from pathlib import Path

NEW = ["MapboxTruckRouteTest", "RouteMapUrlTest", "TripMilesServiceTest"]
EDITS = {
    "README.md": [
        # line 26, the inventory table
        ("`RfpBidAccessTest`, `RfpImportServiceTest`",
         "`RfpBidAccessTest`, " + ", ".join("`%s`" % n for n in NEW) + ", `RfpImportServiceTest`", 1),
        # line 103, sf apex run test
        ("-n RfpBidAccessTest -n RfpImportServiceTest",
         "-n RfpBidAccessTest " + " ".join("-n %s" % n for n in NEW) + " -n RfpImportServiceTest", 1),
        # lines 110 and 389, the two deploy commands
        ("RfpBidAccessTest RfpImportServiceTest",
         "RfpBidAccessTest " + " ".join(NEW) + " RfpImportServiceTest", 2),
    ],
    ".github/workflows/ci.yml": [
        # line 59, --tests
        ("RfpBidAccessTest RfpImportServiceTest",
         "RfpBidAccessTest " + " ".join(NEW) + " RfpImportServiceTest", 1),
    ],
}
for name, edits in EDITS.items():
    path = Path(name)
    text = path.read_text(encoding="utf-8")
    for old, new, count in edits:
        found = text.count(old)
        assert found == count, "%s: expected %d of %r, found %d" % (name, count, old, found)
        text = text.replace(old, new)
    path.write_text(text, encoding="utf-8")
    print("updated", name)
PY
```

Expected: `updated README.md`, `updated .github/workflows/ci.yml`.

Run:

```bash
python3 - <<'PY'
import re
ORDER = ("LaneSearchExclusionsTest PlaceNormalizerTest PricingTestDataFactoryTest PlaceBuilderBatchTest "
         "LaneSearchServiceTest MapboxGeocoderTest LaneBenchmarkControllerTest LaneBenchmarkPlaceServiceTest "
         "RfpTestDataFactoryTest BenchmarkRateServiceTest BidSearchQueryBuilderTest BidSearchServiceTest "
         "RfpControllerTest RfpSecurityTest RfpBidAccessTest MapboxTruckRouteTest RouteMapUrlTest "
         "TripMilesServiceTest RfpImportServiceTest RfpLaneControllerTest RfpHistoryServiceTest "
         "RfpProjectControllerTest RfpBidControllerTest RfpPricingMathTest RfpBulkServiceTest "
         "RfpBulkControllerTest").split()
for name in ["README.md", ".github/workflows/ci.yml"]:
    for number, line in enumerate(open(name, encoding="utf-8"), 1):
        if "RfpBidAccessTest" in line and "RfpImportServiceTest" in line:
            names = re.findall(r"\b[A-Z]\w*Test\b", line)
            print(name, number, len(names), names == ORDER)
PY
```

Expected exactly five lines: `README.md 26 26 True`, `README.md 103 26 True`, `README.md 110 26 True`, `README.md 389 26 True`, `.github/workflows/ci.yml 59 26 True`.

- [ ] **Step 4: README inventory rows and the Trip miles section**

Run from the repo root (it inserts four inventory rows (two Apex, one Data, one UI), extends the two Security rows, and asserts each anchor is found once; Prettier realigns the table columns in Step 6):

```bash
python3 - <<'PY'
from pathlib import Path

path = Path("README.md")
lines = path.read_text(encoding="utf-8").split("\n")

APEX_ROWS = [
    "| Apex | `classes/MapboxHttp`, `TruckRoute`, `MapboxTruckRoute`, `RouteMapUrl` | Phase 7: the shared Mapbox token read and one-retry send (also used by `MapboxGeocoder`); the truck route value types and the profile read from `Truck_Routing_Setting__mdt`; the Directions API truck route with its regular-route fallback; the static route map URL (pins, main route, alternatives, kept under 8,000 characters) |",
    "| Apex | `classes/TripMilesService`, `TripRouteView` | Phase 7: median, stored-route and approximate miles, `Truck_Route__c` reads and upserts in system mode; the route DTO returned by `RfpLaneController.laneRoute` and `LaneBenchmarkController.truckRoute` |",
]
DATA_ROW = "| Data | `objects/Truck_Route__c/*`, `objects/RFP_Lane__c/fields/Miles__c`, `Miles_Source__c`, `Route_Hours__c`, `objects/Truck_Routing_Setting__mdt/*`, `customMetadata/Truck_Routing_Setting.Default` | Phase 7: stored Mapbox routes per ordered place pair and truck profile; each lane's miles, their source and drive hours; the truck profile and the Approx factor. See \"Trip miles (phase 7)\" below |"
UI_ROW = "| UI | `lwc/distanceUnit`, `distanceUnitToggle`, `routeMap`; `messageChannels/Distance_Unit` (`Distance_Unit__c`) | Phase 7: the shared mi/km module, the toggle that publishes the unit, the static route map with its legend and Refresh route, and the Lightning message channel that keeps every component on a page on the same unit |"


def index_of(predicate, label):
    hits = [i for i, line in enumerate(lines) if predicate(line)]
    assert len(hits) == 1, "%s: expected one anchor, found %d" % (label, len(hits))
    return hits[0]


i = index_of(lambda l: l.startswith("| Apex") and "`classes/MapboxGeocoder`" in l, "MapboxGeocoder row")
lines[i + 1:i + 1] = APEX_ROWS
i = index_of(lambda l: l.startswith("| Data") and "`objects/RFP_Project__c/*`" in l, "RFP data row")
lines[i + 1:i + 1] = [DATA_ROW]
i = index_of(lambda l: l.startswith("| UI") and "`lwc/helpCenter`" in l, "help center row")
lines[i + 1:i + 1] = [UI_ROW]

i = index_of(lambda l: "`permissionsets/Lane_Benchmark_User`" in l and "Assign this to the pricing team" in l, "Lane_Benchmark_User row")
lines[i] = lines[i].replace(
    "Assign this to the pricing team",
    "Phase 7 adds read on `Truck_Route__c` and its fields, and class access to `TripRouteView`. Assign this to the pricing team",
)
i = index_of(lambda l: "`permissionsets/RFP_Tool_User`" in l and "the RFP and Lane Benchmark Apex classes" in l, "RFP_Tool_User row")
lines[i] = lines[i].replace(
    "the RFP and Lane Benchmark Apex classes",
    "the RFP and Lane Benchmark Apex classes; phase 7 adds read and edit on `RFP_Lane__c.Miles__c`, `Miles_Source__c` and `Route_Hours__c`, and read on `Truck_Route__c`, and class access to `TripRouteView`",
)

path.write_text("\n".join(lines), encoding="utf-8")
print("inventory updated")
PY
```

Expected: `inventory updated`.

Then insert this section immediately before `## Help center (phase 5)` (after the last paragraph of `## Access model (phase 6)`, one blank line on each side):

```markdown
## Trip miles (phase 7)

Every lane shows how long the trip is, in miles by default and in km on click, with a
rate per mile wherever a price meets miles: the RFP workbench (Miles column, lane panel,
Excel export) and Lane Benchmark (statistics, results, CSV, map). Design:
`docs/superpowers/specs/2026-09-14-phase-7-trip-miles-design.md`.

**Where a lane's miles come from, in order** (R75):

1. **History** — the median of Revenova's billed Distance (Miles)
   (`rtms__Load__c.rtms__Distance_Miles__c`, filled by PC\*Miler) over the load rows the
   lane's history search matched, at the precision it used, radius fallback included
   (R70). Bid rows carry no miles. PC\*Miler cannot be called directly: Revenova's
   mileage classes are not visible to our Apex.
2. **Truck route** or **Regular route** — the main route of the `Truck_Route__c` row
   stored for the lane's ordered place pair and the current truck profile.
3. **Approx** — the great-circle distance between the two places' `Geolocation__c`
   (Earth radius 3,958.7613 mi) × `Approx_Factor__c`: 1.2, the median ratio of billed to
   straight-line miles measured on 10,939 PostProduc loads (D7).
4. Otherwise **No route** (a stored route where Mapbox found no road) or
   **No coordinates**.

`RfpHistoryService.run` applies that order after its searches with no callout (R73),
reading the chunk's stored routes in one query, and writes `RFP_Lane__c.Miles__c`,
`Miles_Source__c` and `Route_Hours__c` in user mode. `RFP_Tool_User` has read and edit on
the three fields; without the grant `Security.stripInaccessible` would silently drop them.

**Truck routes.** `MapboxTruckRoute` asks the Directions API (`mapbox/driving`,
`overview=simplified`, polyline geometry, alternatives as the setting says) with
`max_height`, `max_width` and `max_weight`. When the main route comes back with a
`maxHeight`, `maxWidth` or `maxWeight` violation notification, or Mapbox finds no truck
route, it asks once more without the three limits and returns that as a `Regular` route
(R79); a partly compliant truck route is never shown or stored. So one route is one
request, or two with the fallback (each retried once on a Mapbox server error), always
before the transaction's DML. A missing token,
an HTTP error or a timeout is `Unavailable`: nothing is saved, the lane keeps its miles
and the page says "The truck route is not available right now." The token is the same
`TPRO_KPI__c.Mapbox_Api_Key__c`, read through `MapboxHttp` (shared with
`MapboxGeocoder`), and is never logged or put in a message. The existing Remote Site
`MapBox` and CSP trusted site `Mapbox_API` cover the callouts and the image; no new
credential was created.

**Stored routes.** `Truck_Route__c` (Public Read Only, no tab) keeps one row per ordered
place pair and truck profile, upserted on `Route_Key__c` =
`<origin place Id>:<destination place Id>:<profile key>` (External ID, unique), where the
profile key is the rounded truck size, for example `h4.11w2.60t36.29`. A row holds the
main route's `Miles__c` and `Hours__c`, `Route_Type__c` (`Truck` or `Regular`),
`Status__c` (`Found` or `No route`), up to three routes with their polylines in
`Routes_Json__c` so the map redraws without a request, and `Checked_On__c`. Rows never
expire (R71); A→B and B→A are separate rows; deleting a place clears the lookup and the
row is then ignored (R74). Only `TripMilesService` writes the object, in system mode;
`RFP_Tool_User` and `Lane_Benchmark_User` read it.

**When Mapbox is called.** Only on a person's action: opening a lane in the RFP workbench
(`RfpLaneController.laneRoute`) or running a Lane Benchmark search
(`LaneBenchmarkController.truckRoute`, which the page calls after the cacheable `search`).
A stored row answers without a callout. **Refresh route** (lane panel and Lane Benchmark
map) skips the stored row: one new Directions request, two with the regular fallback;
the `Truck_Route__c` row is replaced through the upsert on `Route_Key__c`; and in the
workbench the lane's `Miles__c`, `Miles_Source__c` and `Route_Hours__c` are rewritten
unless its miles come from History, which a route never replaces. A result of
`Unavailable` changes nothing. The map image (`RouteMapUrl`: pins A and B, the main route
in blue, up to two alternatives in amber and grey, 600×300@2x, lines simplified so the URL
stays under 8,000 characters) is built on each view and never stored.

**Truck Routing Setting.** `Truck_Routing_Setting__mdt`, record `Default`, describes a
53 ft dry van at 80,000 lb, 13 ft 6 in high and 102 in wide:

| Field              | Default | Used for                                             |
| ------------------ | ------- | ---------------------------------------------------- |
| `Height_M__c`      | 4.11    | `max_height` in metres; part of the profile key      |
| `Width_M__c`       | 2.60    | `max_width` in metres; part of the profile key       |
| `Weight_T__c`      | 36.29   | `max_weight` in metric tons; part of the profile key |
| `Alternatives__c`  | checked | asks Mapbox for up to two alternative routes         |
| `Approx_Factor__c` | 1.20    | the Approx multiplier used by Load history           |
| `Timeout_Ms__c`    | 8000    | callout timeout per Directions request               |

Changing the height, width or weight changes the profile key: every place pair is routed
again the next time someone opens it, and the old rows stay in the object unused. A new
factor applies from the next Load history. The repo is the source of truth for
`Truck_Routing_Setting.Default`: every full-manifest deploy overwrites the org value, so
change it by pull request.

**Cost.** Mapbox list prices read on 2026-09-14 (https://www.mapbox.com/pricing): the
Directions API is free up to 100,000 requests a month, then $2.00 per 1,000 requests up
to 500,000 ($1.60 to 1,000,000, $1.20 above); the Static Images API is free up to 50,000
requests a month, then $1.00 per 1,000 up to 500,000 ($0.80 to 1,000,000, $0.60 above).
A new or refreshed route costs one Directions request, or two when the regular fallback
runs; a stored route costs none, and Load history costs none. Every route map shown (a
lane panel opening, a Lane Benchmark search) is one Static Images request, like the
radius preview before it; a radius search keeps its radius preview too, one more request. The Directions API allows 300 requests per minute.

**Storing routes is the owner's decision** (D3, R77). Mapbox routing results are stored
in `Truck_Route__c` because the owner decided so on 2026-09-14, after the Mapbox Product
Terms clause against caching or storing Navigation API results (§2.10.1) was raised.
Nothing else depends on the store: a later change of mind removes only the save
(`TripMilesService.save`), after which every lane opening and search asks Mapbox again and
Load history falls back to Approx where it has no History miles.

**Limits.** Mapbox truck limits are best effort with regional coverage, and there is no
truck length, axle, toll or hazmat parameter: a hazmat lane (`RFP_Lane__c.Hazmat__c`)
gets the same route as any other lane, and that route is not a hazmat route. Mapbox
answers 403 to a token whose URL restrictions the request does not meet; the Apex
callouts (geocoding since phase 2, routing now) send no browser referrer, so after any
change to the token's URL restrictions in the Mapbox account, open a lane and check that
the route still draws. Production is not deployed (owner decision, D8).
```

Run: `grep -c "^## Trip miles (phase 7)$" README.md && grep -c "TripMilesService" README.md`
Expected: `1`, then a number of at least `6`.

- [ ] **Step 5: Roadmap row 7**

Run from the repo root:

```bash
python3 - <<'PY'
from datetime import date
from pathlib import Path

path = Path("docs/superpowers/specs/2026-09-07-pricing-department-roadmap.md")
lines = path.read_text(encoding="utf-8").split("\n")
hits = [i for i, l in enumerate(lines) if l.startswith("| 6 ") and "RFP access model" in l]
assert len(hits) == 1, "row 6 not found once: %d" % len(hits)
lines.insert(hits[0] + 1, "| 7 | Trip miles | Miles on every lane (median of billed load miles, stored Mapbox truck or regular route, approximate), km on click, rate per mile, and the truck route map in the RFP workbench and Lane Benchmark; routes stored in `Truck_Route__c`, the truck profile in `Truck_Routing_Setting__mdt` | Done " + date.today().isoformat() + " (PostProduc; production untouched) |")
path.write_text("\n".join(lines), encoding="utf-8")
print("row 7 added")
PY
```

Expected: `row 7 added`. The row carries today's date; Step 8 corrects it if the final deploy lands on a later day.

- [ ] **Step 6: Format and full local gate**

Run: `npx prettier --write README.md .github/workflows/ci.yml docs/superpowers/specs/2026-09-07-pricing-department-roadmap.md docs/help/en/rfp-history.md docs/help/fr/rfp-history.md docs/help/en/rfp-pricing.md docs/help/fr/rfp-pricing.md docs/help/en/lb-stats.md docs/help/fr/lb-stats.md docs/help/en/rfp-inline.md docs/help/fr/rfp-inline.md && npm run help:build && npm run help:check`

Expected: Prettier lists the eleven files (it realigns the README inventory table and the roadmap table; the guide files report `(unchanged)`), then `built 15 sections into force-app/main/default/staticresources/helpCenter`, then `helpCenter is up to date`.

Run: `npm run lint && npm run prettier:verify && npm run help:check && npm run test:unit 2>&1 | grep -E "^(Tests|Test Suites):"; /private/tmp/pmd_install/pmd-bin-7.15.0/bin/pmd check --dir force-app --rulesets config/pmd-ruleset.xml --minimum-priority 3 --format text --fail-on-violation; echo "pmd exit $?"`

Expected: ESLint silent; Prettier `All matched files use Prettier code style!` (a warning about the untracked `.ai-handover` file is pre-existing; never format or stage it, `.vscode/settings.json` or any `* 2.*` file); `helpCenter is up to date`; Jest `Test Suites: 39 passed, 39 total` and `Tests: 361 passed, 361 total` (36 / 309 at the end of phase 6, plus 3 suites and 25 tests from Task 8, 15 tests from Task 9 and 12 from Task 10); `pmd exit 0`.

Run the Apex method count over the 26-class roster (it counted 158 on `main` before this phase, matching the phase 6 final deploy):

```bash
python3 - <<'PY'
import re
ROSTER = ("LaneSearchExclusionsTest PlaceNormalizerTest PricingTestDataFactoryTest PlaceBuilderBatchTest "
          "LaneSearchServiceTest MapboxGeocoderTest LaneBenchmarkControllerTest LaneBenchmarkPlaceServiceTest "
          "RfpTestDataFactoryTest BenchmarkRateServiceTest BidSearchQueryBuilderTest BidSearchServiceTest "
          "RfpControllerTest RfpSecurityTest RfpBidAccessTest MapboxTruckRouteTest RouteMapUrlTest "
          "TripMilesServiceTest RfpImportServiceTest RfpLaneControllerTest RfpHistoryServiceTest "
          "RfpProjectControllerTest RfpBidControllerTest RfpPricingMathTest RfpBulkServiceTest "
          "RfpBulkControllerTest").split()
METHOD = re.compile(r"@IsTest(?:\([^)]*\))?\s+(?:@\w+(?:\([^)]*\))?\s+)*(?:(?:private|public|global)\s+)?static\s+(?:testMethod\s+)?void\s", re.I)
total = 0
for name in ROSTER:
    count = len(METHOD.findall(open("force-app/main/default/classes/%s.cls" % name, encoding="utf-8").read()))
    total += count
    print(name, count)
print("total", total)
PY
```

Expected: 26 lines and `total 213`. By class: `MapboxTruckRouteTest` 12, `RouteMapUrlTest` 10, `TripMilesServiceTest` 12, `LaneSearchServiceTest` 22, `MapboxGeocoderTest` 9, `LaneBenchmarkControllerTest` 9, `RfpSecurityTest` 11, `RfpLaneControllerTest` 17, `RfpHistoryServiceTest` 18; the other 17 classes unchanged (158 before this phase). 213 is the test total the second deploy in Step 7 must report. If a fix round added or removed a test method, the printed total is the one that counts: use it in Step 7 and say why in the Outcome.

Run: `grep -n "System.debug" force-app/main/default/classes/{MapboxHttp,TruckRoute,MapboxTruckRoute,RouteMapUrl,TripMilesService,TripRouteView}.cls; echo "debug grep exit $?"; git grep -nE "pk\.[A-Za-z0-9_-]{20,}" -- . ; echo "token grep exit $?"`
Expected: no line, then `debug grep exit 1`; no line, then `token grep exit 1` (the token is never logged and never committed; tests only use `pk.test`).

Run: `git status --short`
Expected: ` M` on exactly the eight guide files, the eight `helpCenter` HTML files, `README.md`, `.github/workflows/ci.yml` and the roadmap; plus the pre-existing ` M .vscode/settings.json` and the untracked `* 2.*` files, which stay out of every commit.

- [ ] **Step 7: Final deploy pair**

A deploy runs asynchronously and is polled in calls of at most two minutes (an agent idle for three minutes is stopped). Shell variables do not survive between tool calls: paste each job id literally where the command says `<job id>`.

First, the full manifest with no tests, so the permission sets (`Truck_Route__c` read, the lane miles fields) and every object, field, record, channel and bundle are in place before the user-mode tests run (README, "Working with the org": user-mode Apex needs its permission set in the org before a `RunSpecifiedTests` deploy).

Run: `sf project deploy start -o sandbox --manifest manifest/package.xml -l NoTestRun --async --json | python3 -c "import json,sys; s=sys.stdin.read(); r=json.loads(s[s.index('{'):])['result']; print(r['id'], r.get('status'))"`

Expected: a job id starting `0Af` and `Queued` or `InProgress`.

Poll (repeat the same command while the status is `Queued`, `Pending`, `InProgress` or `None`; a wait that ends before the deploy prints a timeout message, which also means run it again):

`sf project deploy report -o sandbox --job-id <job id> -w 2 --json | python3 -c "import json,sys; s=sys.stdin.read(); j=json.loads(s[s.index('{'):]); r=j.get('result') or {}; d=r.get('details') or {}; cf=d.get('componentFailures') or []; cf=cf if isinstance(cf,list) else [cf]; tf=(d.get('runTestResult') or {}).get('failures') or []; tf=tf if isinstance(tf,list) else [tf]; print(r.get('id'), r.get('status'), 'components', r.get('numberComponentsDeployed'), '/', r.get('numberComponentsTotal'), 'errors', r.get('numberComponentErrors'), 'tests', r.get('numberTestsCompleted'), '/', r.get('numberTestsTotal'), 'failures', r.get('numberTestErrors'), j.get('message') or ''); [print('COMPONENT', f.get('fullName'), '->', f.get('problem')) for f in cf]; [print('TEST', f.get('name'), f.get('methodName'), '->', (f.get('message') or '')[:200]) for f in tf]"`

Expected: `<job id> Succeeded components C / C errors 0 tests 0 / 0 failures 0`, where C is above phase 6's 246 by the components this phase added. (On the phase 6 job `0AfbZ00000Cq3CcSAJ` this parser prints `0AfbZ00000Cq3CcSAJ Succeeded components 246 / 246 errors 0 tests 158 / 158 failures 0`.) Record the id and C.

Second, the same manifest with the 26 test classes:

Run: `sf project deploy start -o sandbox -x manifest/package.xml --post-destructive-changes manifest/destructiveChangesPost.xml -l RunSpecifiedTests -t LaneSearchExclusionsTest PlaceNormalizerTest PricingTestDataFactoryTest PlaceBuilderBatchTest LaneSearchServiceTest MapboxGeocoderTest LaneBenchmarkControllerTest LaneBenchmarkPlaceServiceTest RfpTestDataFactoryTest BenchmarkRateServiceTest BidSearchQueryBuilderTest BidSearchServiceTest RfpControllerTest RfpSecurityTest RfpBidAccessTest MapboxTruckRouteTest RouteMapUrlTest TripMilesServiceTest RfpImportServiceTest RfpLaneControllerTest RfpHistoryServiceTest RfpProjectControllerTest RfpBidControllerTest RfpPricingMathTest RfpBulkServiceTest RfpBulkControllerTest --async --json | python3 -c "import json,sys; s=sys.stdin.read(); r=json.loads(s[s.index('{'):])['result']; print(r['id'], r.get('status'))"`

Expected: a new job id and `Queued` or `InProgress`. Poll it with the report command above until it finishes.

Expected: `<job id> Succeeded components C / C errors 0 tests 213 / 213 failures 0` (the Step 6 total), and no `COMPONENT` or `TEST` line. A `TEST` line is a failure to fix in the task that owns that class, then both deploys run again. Record the id and the test total.

Run: `sf data query -o sandbox -q "SELECT DeveloperName, Height_M__c, Width_M__c, Weight_T__c, Alternatives__c, Approx_Factor__c, Timeout_Ms__c FROM Truck_Routing_Setting__mdt" --json | python3 -c "import json,sys; s=sys.stdin.read(); [print(r['DeveloperName'], r['Height_M__c'], r['Width_M__c'], r['Weight_T__c'], r['Alternatives__c'], r['Approx_Factor__c'], r['Timeout_Ms__c']) for r in json.loads(s[s.index('{'):])['result']['records']]"`

Expected one line: `Default 4.11 2.6 36.29 True 1.2 8000` (a number may print with a trailing `.0`), matching the README table.

- [ ] **Step 8: Spec Outcome and the roadmap date**

Append to `docs/superpowers/specs/2026-09-14-phase-7-trip-miles-design.md`, after line 124 (R79), with one blank line before:

```markdown
## Outcome — phase 7 ((fill: date of the final deploy))

Branch `phase-7/trip-miles` from `main` at `bc4710b`; spec `976274b`; plan (fill: SHA and message of the plan commit).

Commits: (fill: every commit on the branch after the plan, in order, as `` `sha` `` message (Task N), with a clause for any fix round); and this documentation commit, Document trip miles (phase 7) and record the outcome (Task 11: the guide's four sections in English and French, the README section, inventory rows and 26-class roster, the CI roster, the roadmap row, this Outcome).

**Differences from the spec.**

1. Per-row miles are `LaneSearchResult.Row.load.miles` (a new `LoadDetail`), not `Row.miles`, so `Row` stays at PMD's 20-field cap; `Row.loadId` became `load.loadId`. The Lane Benchmark CSV column reads `load.miles` and sits after Carrier total (Tasks 4, 5, 10).
2. On Lane Benchmark a radius search shows the route image and keeps its radius preview under it; any other search shows the route image in place of the plain preview. `RouteMapUrl` draws no circles. This reads §5 ("the radius circles stay when a radius search is shown") and §6 ("`c-route-map` replaces the plain preview") together (Task 10 note 3).
3. Load history also writes `No coordinates`, with blank miles and hours, on unresolved lanes (D4 speaks of resolved lanes; Task 6 note 4).
4. The workbench table shows a lane's new route miles after the next price save, history run or page reload; the lane panel shows them at once. `rfpTool.js` is untouched (Task 9 note 1).
5. Two of §8's `RfpSecurityTest` checks (a Read-shared pricer opens a lane route; a Lane Benchmark user gets a truck route) live in `RfpLaneControllerTest` and `LaneBenchmarkControllerTest`, to keep `RfpSecurityTest` under PMD's class complexity budget (Task 7 note 4).
6. `TripMilesService` writes `Truck_Route__c` through a private `without sharing` inner `Store`, so a pricer can refresh a route a colleague stored (Task 4 note 2).
7. A route makes at most two requests, but `MapboxHttp.send` retries a 5xx once: the worst case is 4 callouts × 8 s = 32 s, not §7's 16 s (Task 2 note 8).
8. A truck alternative that breaks a limit is left out of a Truck result, and any non-`Ok` code on HTTP 200 (`NoRoute`, `NoSegment`) counts as no route; the truck request also sends `notifications=all` (Task 2 notes 1, 3, 4).
9. The map URL draws the alternatives first, then the main route, then the pins; the main route is never dropped to fit the 8,000-character limit (Task 3 notes 2, 3).
10. `TripRouteView` holds the shared route flow; its `source` is the `Miles_Source__c` value the route stands for; it defines `NO_COORDINATES` and `NO_ROUTE`. `LaneBenchmarkPlaceService.placesByKey` became public, `truckRoute` returns Unavailable for an unknown key, and both permission sets give class access to `TripRouteView` (Task 7 notes 1–8).
11. `c-route-map` has an `@api hazmat` input for §7's hazmat sentence; the unit is shared through `@wire(MessageContext)` with `APPLICATION_SCOPE`; the channel's manifest member is `Distance_Unit` (Task 8 notes 1, 2, 5).
12. `PricingTestDataFactory` gained `createLoad(Graph, Account, Account, Decimal miles)`, and `TruckRoute` a `@TestVisible profileFrom(setting)` that fills a blank setting field with its default (Task 5 note 3, Task 2 note 7).
13. (fill: each further difference a fix round introduced, or delete this item.)

**PostProduc deploys**, all Succeeded unless noted: (fill: one entry per deploy with its id and what it carried — Task 1 metadata NoTestRun with its component count; the scoped deploys of Tasks 2–7 with their test counts; any Failed attempt with its reason and the commit that fixed it). Final pair: (fill: NoTestRun id, C components, 0 errors), (fill: RunSpecifiedTests id, the 26 test classes, T / T, 0 failures).

**Setting verified in the org:** `Truck_Routing_Setting__mdt.Default` (fill: the values the Step 7 query printed).

**Tests:** Apex 213 / 213 in the final RunSpecifiedTests deploy: 158 at the end of phase 6, plus 12 in `MapboxTruckRouteTest`, 10 in `RouteMapUrlTest`, 12 in `TripMilesServiceTest`, 3 in `LaneSearchServiceTest`, 6 in `RfpHistoryServiceTest`, 9 in `RfpLaneControllerTest` and 3 in `LaneBenchmarkControllerTest`; `MapboxGeocoderTest` is unchanged and `RfpSecurityTest` gained one stranger check inside an existing method. Jest 39 suites / 361 tests (36 / 309 at the end of phase 6: Task 8 +3 suites and +25 tests, Task 9 +15, Task 10 +12). PMD clean (class complexity budget 40: `RfpHistoryService`, `RfpLaneController` and `LaneBenchmarkController` measured 37 while planning, `RfpSecurityTest` 39); `LaneSearchResult.Row` at 20 fields, no suppression.

**Mapbox use during the checks:** (fill: the number of `Truck_Route__c` rows in PostProduc after the browser check and how many of them are `Regular` or `No route`; Load history made no request.)

**Known limits.** Hazmat lanes get the ordinary route (Mapbox has no hazmat parameter); truck length, axles and tolls are not considered; the Approx factor is one median for every lane (1.196 measured, 1.2 set); a stored route never expires until someone clicks Refresh route; storing routes rests on the owner's decision (D3, R77); the workbench table shows a lane's new route miles only after the next price save, history run or page reload, because `rfpTool.js` stays frozen at 554 of 560 lines (the lane panel shows them at once); a route can take up to 32 s in the worst case (two requests, each retried once on a Mapbox server error, 8 s timeout each); `RfpSecurityTest` is at PMD class complexity 39 of 40: split it before adding a test method; (fill: anything else found while building or checking, or "nothing further").

**Review record.** (fill: per task, the review result and each fix round.)

**Browser check:** pending (controller)
```

The test counts and the Differences list are prefilled from this plan (Tasks 2–10 and their contract notes): check each against what Steps 6 and 7 printed and the code as merged, and correct any that a fix round changed, saying why. Then replace every `(fill: …)` above with the real value. The Outcome date is the date of the second Step 7 deploy; if roadmap row 7 (Step 5) carries an earlier date, change it to that date.

Run: `npx prettier --write docs/superpowers/specs/2026-09-14-phase-7-trip-miles-design.md docs/superpowers/specs/2026-09-07-pricing-department-roadmap.md && grep -c "(fill" docs/superpowers/specs/2026-09-14-phase-7-trip-miles-design.md docs/superpowers/specs/2026-09-07-pricing-department-roadmap.md`

Expected: both counts `0` (grep exits 1 when nothing matches, which is the pass here). A line still holding `(fill` is a review failure. `Browser check: pending (controller)` stays until Step 10.

- [ ] **Step 9: Commit**

```bash
git add docs/help force-app/main/default/staticresources/helpCenter README.md .github/workflows/ci.yml docs/superpowers/specs/2026-09-07-pricing-department-roadmap.md docs/superpowers/specs/2026-09-14-phase-7-trip-miles-design.md
git diff --cached --name-only
git commit -m "Document trip miles (phase 7) and record the outcome"
```

Expected: `git diff --cached --name-only` prints exactly 20 paths (the eight guide files, the eight `helpCenter` HTML files, `README.md`, `.github/workflows/ci.yml`, the roadmap and the phase 7 spec) and nothing named `.vscode/settings.json` or `* 2.*`. lint-staged runs Prettier on the staged Markdown and YAML (no change expected after Step 6). `git log -1 --format=%B` shows the one-line message with no trailer.

- [ ] **Step 10: Browser check (controller, not the implementer)**

In PostProduc as the admin, in a fresh tab after the final deploy (hard reload once, Cmd+Shift+R). Before starting, and after each numbered check that says so, read the store from a terminal:

`sf data query -o sandbox -q "SELECT Route_Key__c, Status__c, Route_Type__c, Miles__c, Hours__c, Checked_On__c FROM Truck_Route__c ORDER BY Checked_On__c DESC LIMIT 5" --json | python3 -c "import json,sys; s=sys.stdin.read(); r=json.loads(s[s.index('{'):])['result']; print('rows', r['totalSize']); [print(x['Route_Key__c'], x['Status__c'], x['Route_Type__c'], x['Miles__c'], x['Hours__c'], x['Checked_On__c']) for x in r['records']]"`

(`totalSize` here is capped by `LIMIT 5`; for the full count run the same query as `SELECT COUNT() FROM Truck_Route__c`.)

1. RFP Tool → "Phase 3c browser check" → **Refresh history**. Every lane with both ends resolved shows a **Miles** value, with no tag (History) or `approx.`; an unresolved lane shows "—" whose tooltip gives the reason. The store query shows no new row (Load history makes no Mapbox request).
2. Open a lane whose Miles read `approx.`. A spinner, then the map: pins A and B, a thick blue main route and, where Mapbox returns them, one or two thinner alternatives; the legend reads "Truck route" (or "Regular route — truck limits could not be met") and "Route 1: … mi · … h" per route. The panel's miles line under the title reads the route's miles · truck route (or regular route) · hours. The table's Miles cell for that lane still shows `approx.` until the next price save, history run or page reload (Task 9 note 1). Reload the project: it shows `truck` (or `route`) with the route's miles. The store query shows one new row with `Found`.
3. Close the panel and reopen the same lane: the same map and legend, and the store query shows the same `Checked_On__c` (no new request).
4. Click **Refresh route**: the map redraws; the store query shows the same `Route_Key__c` with a later `Checked_On__c` and no extra row.
5. Open a lane whose Miles have no tag (History): the route draws, and the Miles value and its missing tag do not change.
6. In the panel, type a new Cost and a new Sell: **Cost per mile** and **Sell per mile** change as you type.
7. Click **km** in the toolbar: the table's Miles column, the panel's miles line, the per-mile values and the map legend switch to km together. Reload the page: km is still selected. Open Lane Benchmark: it shows km too. Switch back to **mi**.
8. Lane Benchmark: search Montréal → Toronto at exact city. The Statistics card shows "Trip: … mi · median of N loads", "Truck route: … mi · … h" (or "Regular route: …") and **Rate per mile (median)** in each currency box; the map is the route map with its legend. Search again with a 100 mi radius around Montréal: the route map shows and the radius preview stays under it; the results table has a **Miles** column with "—" on bid rows; **Export CSV** has a Miles column. The **mi** / **km** toggle in the card header switches the card, the table and the legend.
9. Look for a regular route: `sf data query -o sandbox -q "SELECT Route_Key__c, Miles__c FROM Truck_Route__c WHERE Route_Type__c = 'Regular'"`. If a row exists, open a lane with that place pair (or search it in Lane Benchmark) and see the heading "Regular route — truck limits could not be met". If none exists, record "no lane in the project broke a truck limit".
10. On the project, export the Excel file: the lane sheet has Miles, Km, Miles source, Route hours, Cost per mile and Sell per mile after Transit days, filled for priced lanes with miles.
11. Help tab: in English, "Loading history", "Pricing a lane" and "Reading the statistics" each show "Trip miles and truck routes" and "Editing in the table" shows "The Miles column"; in French, "Milles du trajet et itinéraires de camion" (three sections) and "La colonne Miles".
12. The browser console shows no error from `c-route-map`, `c-distance-unit-toggle`, `rfpLanePanel` or `laneBenchmark`.

Record the results in the Outcome, replacing "pending (controller)", fill the "Mapbox use during the checks" line from the final store count, and commit:

```bash
git add docs/superpowers/specs/2026-09-14-phase-7-trip-miles-design.md
git commit -m "Record the phase 7 browser check"
```

#### Contract notes (Task 11)

1. **Hazmat legend.** On a hazmat RFP lane the legend line comes from `c-route-map` (Task 8, passed by the panel in Task 9); the guide and README state the fact (a hazmat lane gets the ordinary route, Mapbox has no hazmat parameter).
2. **`rfp-inline` is about editable cells.** The Miles column is read-only; per the contract it is documented there as a new `## The Miles column` section that says so.
3. **Counts are written in; dates, ids, component totals and SHAs are Outcome placeholders.** Apex 213 (158 on `main`, counted by the Step 6 script and equal to the phase 6 final deploy, plus 55 methods from Tasks 2–7) and Jest 39 suites / 361 tests (36 / 309 plus Tasks 8–10) come from the tasks' test lists. The component count C (246 in phase 6), the deploy ids, dates and SHAs are recorded by the executor in Step 8, whose placeholder grep fails review on any that is left.
4. **README beyond the named section and roster.** Four inventory rows (two Apex, one Data, one UI) and one clause on each of the two Security rows are added now, because phase 6's final review had to add its inventory entries after the fact. Task 7 grants class access to `TripRouteView` in both sets; the README rows say so.
5. **Radius circles on the Lane Benchmark map.** Settled in Task 10 (note 3): a radius search keeps its radius preview under the route image, any other search shows the route image in place of the plain preview, and the preview stays whenever there is no route image (spec §5 and §6). The Outcome's Differences list records it (item 2).
6. **Unit shared across pages.** `Distance_Unit__c` keeps components on one page in step; the RFP Tool and Lane Benchmark share the unit through `readUnit()`'s `localStorage` key, so the guide says the choice is "remembered in this browser" rather than that the pages switch live together.
7. **Help front matter unchanged.** The four `hint` lines are not edited (the 240-character limit, and `index.json` stays byte-identical), so the build still reports 15 sections and exactly eight HTML files change.
8. **Deploys run `--async`** as the contract requires, not phase 6's foreground `-w 30`; README line 110 keeps its foreground form (it is the human runbook) and only gains the three classes. The report parser was run against the phase 6 job `0AfbZ00000Cq3CcSAJ` and printed its known result.
9. **Mapbox cost and terms.** Prices were read from https://www.mapbox.com/pricing on 2026-09-14 and are dated in the README. The Product Terms text of §2.10.1 could not be read (the legal page links a PDF), so the README reuses the spec's D3 wording instead of quoting it.
10. **URL-restricted token.** The README's phase 2 advice to add URL restrictions to the token meets Mapbox's documented 403 for requests that do not satisfy them; Apex callouts send no referrer. The new section asks for a route check after any restriction change instead of changing the phase 2 advice, which is outside this phase.
11. **Formatting before the build.** Prettier runs on the guide Markdown before `help:build` (Step 6) so the committed HTML matches the formatted source. A dry run of Prettier on the new guide blocks, concatenated, changed only blank lines between blocks (a heading directly after the previous block's paragraph), which the real insertions already have; the text itself was left alone.
12. **The roster moves.** After Step 4 the four inventory rows shift the roster lines from README 26, 103, 110 and 389 to 28, 107, 114 and 393 (the dry run of Steps 3–5 on copies printed them). The plan's Global Constraints name the deploy command under "Working with the org" rather than a line number.

<!-- prettier-ignore-end -->
