# Pricing Department (Salesforce)

Source for the Lightning pages the Trans-Pro pricing team works in: **Lane Benchmark**,
which searches historical carrier quotes and RFP bids for a lane and shows per-currency
stats, margin and a suggested sell, and the **RFP Tool** workbench, which prices a whole
customer RFP from the same search. The single "Pricing Department" page they grew out of
was retired in phase 4 - see "Retired: Pricing Department page (phase 4)" below.

Retrieved on 2026-09-07 from the `postproduc` sandbox (sf alias `sandbox`).

## What is in here

| Layer            | Component                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         | Notes                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            |
| ---------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Data             | `objects/Pricing_Place__c/*`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      | Phase 1 place dictionary: normalized city/province/country key, `Aliases__c`/`Spellings__c`, `Source__c` (`Locations`/`Mapbox`), geolocation, `Location_Count__c`/`Load_Count_365d__c`                                                                                                                                                                                                                                                                                                                           |
| Apex             | `classes/PlaceNormalizer`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         | Phase 1: normalizes raw `ShippingCity`/`ShippingState`/`ShippingCountry` into dictionary keys                                                                                                                                                                                                                                                                                                                                                                                                                    |
| Apex (batch)     | `classes/PlaceBuilderBatch`, `PlaceWriteBatch`, `PlaceUsageBatch`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 | Phase 1: builds/refreshes `Pricing_Place__c` from shipping locations, then fills `Load_Count_365d__c`; never deletes, never overwrites `Aliases__c`/`Active__c`                                                                                                                                                                                                                                                                                                                                                  |
| Apex             | `classes/LaneSearchService`, `LaneSearchQueryBuilder`, `LaneSearchFilters`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        | Phase 1: typed lane search over `rtms__CarrierQuote__c` (any precision, filters, per-currency stats, dedupe, truncation)                                                                                                                                                                                                                                                                                                                                                                                         |
| Apex             | `classes/LaneSearchRequest`, `LaneSearchResult`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   | Phase 1: typed request/result DTOs shared by `LaneSearchService` and `LaneBenchmarkController`                                                                                                                                                                                                                                                                                                                                                                                                                   |
| Apex             | `classes/LaneSearchExclusions`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    | Excluded Contact Ids for every lane search, read from `Pricing_Department_Setting__mdt.Default`; test hook for tests                                                                                                                                                                                                                                                                                                                                                                                             |
| Navigation       | `tabs/Lane_Benchmark`, `flexipages/Lane_Benchmark`, `applications/Lane_Benchmark`, `applications/TransPro` (tab added)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            | Phase 2: the Lane Benchmark page's own tab/page/app, plus the tab appended to the existing `TransPro` app                                                                                                                                                                                                                                                                                                                                                                                                        |
| UI               | `lwc/laneBenchmark`, `laneBenchmarkPlacePicker`, `laneBenchmarkFilters`, `laneBenchmarkStats`, `laneBenchmarkResults`, `laneBenchmarkMap`, `laneBenchmarkCsv`, `laneBenchmarkStorage`, `marginMath`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               | Phase 2: the nine Lane Benchmark bundles — container, place picker, filters, stats/margin, results table with CSV export, static map preview, and the CSV/storage/margin pure modules                                                                                                                                                                                                                                                                                                                            |
| Apex             | `classes/LaneBenchmarkController`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 | Aura/LWC entry points for the Lane Benchmark page: search, place autocomplete, filter options, geocode, map preview                                                                                                                                                                                                                                                                                                                                                                                              |
| Apex             | `classes/LaneBenchmarkPlaceService`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               | `Pricing_Place__c` reads/writes behind `LaneBenchmarkController`'s `geocode()`/`mapPreviewUrl()`, split out to keep the controller under the PMD CyclomaticComplexity threshold                                                                                                                                                                                                                                                                                                                                  |
| Apex             | `classes/MapboxGeocoder`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          | Forward geocoding and static map URLs through the org's Mapbox account                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| Apex             | `classes/MapboxHttp`, `TruckRoute`, `MapboxTruckRoute`, `RouteMapUrl`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             | Phase 7: the shared Mapbox token read and one-retry send (also used by `MapboxGeocoder`); the truck route value types and the profile read from `Truck_Routing_Setting__mdt`; the Directions API truck route with its regular-route fallback; the static route map URL (pins, main route, alternatives, kept under 8,000 characters)                                                                                                                                                                             |
| Apex             | `classes/TripMilesService`, `TripRouteView`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       | Phase 7: median, stored-route and approximate miles, `Truck_Route__c` reads and upserts in system mode; the route DTO returned by `RfpLaneController.laneRoute` and `LaneBenchmarkController.truckRoute`                                                                                                                                                                                                                                                                                                         |
| Apex             | `classes/LaneKeyMatcher`, `LaneLoadFilters`, `LaneQueries`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        | Phase 8: one lane end's lane-key condition for a precision and a load field path (moved out of `LaneSearchQueryBuilder`; the search SOQL is unchanged); the mode, equipment and hazmat conditions (moved out of `LaneSearchFilters`); the grouped quote counts, freight-plan and leg-load SOQL of the two new cards                                                                                                                                                                                              |
| Apex             | `classes/IntercompanyCarriers`, `HandoffPoints`, `ExchangeRates`, `CarrierWarning`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                | Phase 8: the intercompany carrier account Ids and the active handoff place keys from custom metadata; USD dated exchange rates applied per load date; the red results warning text from `Account.Black_List__c` and the Transportation Profile's `Outstanding_Claim__c`                                                                                                                                                                                                                                          |
| Apex             | `classes/CarrierLeadController`, `CarrierLeadService`, `CarrierLeadResult`, `FreightPlanReader`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   | Phase 8: Carriers to ask, names only (same lane over 3 years, then the top 10 on the state or province lane over a year), read in system mode with one user-mode `Account` read for the links; `FreightPlanReader` reads freight plans with their legs in system mode                                                                                                                                                                                                                                            |
| Apex             | `classes/SplitLaneController`, `SplitLaneService`, `SplitEstimates`, `SplitLaneResult`, `SplitTestData`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           | Phase 8: Split-lane options: freight-plan history over 12 months grouped by handoff, estimates through handoff points, amounts in CAD or USD; `SplitTestData` (`@IsTest`) builds carriers, leg loads and freight plans for the tests                                                                                                                                                                                                                                                                             |
| Apex tests       | `LaneSearchExclusionsTest`, `PlaceNormalizerTest`, `PricingTestDataFactoryTest`, `PlaceBuilderBatchTest`, `LaneSearchServiceTest`, `MapboxGeocoderTest`, `LaneBenchmarkControllerTest`, `LaneBenchmarkPlaceServiceTest`, `RfpTestDataFactoryTest`, `BenchmarkRateServiceTest`, `BidSearchQueryBuilderTest`, `BidSearchServiceTest`, `RfpControllerTest`, `RfpSecurityTest`, `RfpBidAccessTest`, `MapboxTruckRouteTest`, `RouteMapUrlTest`, `TripMilesServiceTest`, `RfpImportServiceTest`, `RfpLaneControllerTest`, `RfpHistoryServiceTest`, `RfpProjectControllerTest`, `RfpBidControllerTest`, `RfpPricingMathTest`, `RfpBulkServiceTest`, `RfpBulkControllerTest`, `SplitTestDataTest`, `LaneSearchQueryBuilderTest`, `LaneKeyMatcherTest`, `IntercompanyCarriersTest`, `HandoffPointsTest`, `ExchangeRatesTest`, `CarrierWarningTest`, `LaneQueriesTest`, `CarrierLeadServiceTest`, `CarrierLeadControllerTest`, `CarrierSplitSecurityTest`, `SplitLaneServiceTest`, `SplitEstimatesTest`, `SplitLaneControllerTest`, `CarrierSplitLimitsTest MarketTestServiceTest MarketTestControllerTest` | Behavior tests; `PricingTestDataFactory` builds the minimum valid Revenova graph the managed triggers require, so tests do not depend on org data                                                                                                                                                                                                                                                                                                                                                                |
| Data             | `objects/rtms__CarrierQuote__c/fields/*`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          | 24 custom fields on the Revenova TMS Carrier Quote object, almost all formulas                                                                                                                                                                                                                                                                                                                                                                                                                                   |
| Data (2nd layer) | fields on `rtms__CarrierService__c`, `rtms__TransportationProfile__c`, `rtms__Load__c`, `Account`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 | Custom fields those formulas read through lookups                                                                                                                                                                                                                                                                                                                                                                                                                                                                |
| Security         | `permissionsets/Lane_Benchmark_User`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              | Grants access to the Lane Benchmark page: app/tab visibility, Apex class access (`LaneBenchmarkController`, `LaneBenchmarkPlaceService`, `LaneSearchService`, `MapboxGeocoder`), object read on `rtms__CarrierQuote__c`/`rtms__Load__c`/`Pricing_Place__c`, field read on every field the page shows. Phase 7 adds read on `Truck_Route__c` and its fields, and class access to `TripRouteView`. Phase 8 adds class access to `CarrierLeadController` and `SplitLaneController`. Assign this to the pricing team |
| Security (CSP)   | `cspTrustedSites/Mapbox_API`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      | `img-src` trusted site for `https://api.mapbox.com`, needed for the Lane Benchmark static map preview                                                                                                                                                                                                                                                                                                                                                                                                            |
| Data             | `objects/RFP_Project__c/*`, `objects/RFP_Lane__c/*`, `objects/Benchmark_Rate__c/*`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                | Phase 3a: the RFP data model — project, lane and carrier bid; see "RFP Tool (phase 3a)" below                                                                                                                                                                                                                                                                                                                                                                                                                    |
| Data             | `objects/Truck_Route__c/*`, `objects/RFP_Lane__c/fields/Miles__c`, `Miles_Source__c`, `Route_Hours__c`, `objects/Truck_Routing_Setting__mdt/*`, `customMetadata/Truck_Routing_Setting.Default`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    | Phase 7: stored Mapbox routes per ordered place pair and truck profile; each lane's miles, their source and drive hours; the truck profile and the Approx factor. See "Trip miles (phase 7)" below                                                                                                                                                                                                                                                                                                               |
| Data             | `objects/Intercompany_Carrier__mdt/*`, `objects/Handoff_Point__mdt/*`, `customMetadata/Intercompany_Carrier.*`, `customMetadata/Handoff_Point.*`, `objects/RFP_Lane__c/fields/Cost_Source__c` (value `Split`)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     | Phase 8: the intercompany carrier accounts hidden from both cards, the handoff points tried for estimates, and the Split cost source. See "Carriers to ask and split-lane options (phase 8)" below                                                                                                                                                                                                                                                                                                               |
| Apex             | `classes/RfpTestDataFactory`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      | Phase 3a: test builders for projects, lanes, bids and places, reusing `PricingTestDataFactory`                                                                                                                                                                                                                                                                                                                                                                                                                   |
| Apex             | `classes/BenchmarkRateService`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    | Phase 3a: saves a bid and copies its lane keys from the lane's resolved places; since phase 6 the insert, update and reload go through `RfpBidAccess` (system mode after the lane check)                                                                                                                                                                                                                                                                                                                         |
| Apex             | `classes/BidSearchQueryBuilder`, `BidSearchService`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               | Phase 3a: builds the bid SOQL at the same precision `LaneSearchQueryBuilder` uses for Loads, and merges bid rows into `LaneSearchService`'s results                                                                                                                                                                                                                                                                                                                                                              |
| Apex             | `classes/RfpController`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           | Phase 3a: `projectsForAccount` for the customer Account component; phase 3b adds the workbench methods                                                                                                                                                                                                                                                                                                                                                                                                           |
| UI               | `lwc/rfpProjectsForAccount`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       | Phase 3a: "RFP Projects (customer)", the Account record page component listing a customer's projects, files and bid counts                                                                                                                                                                                                                                                                                                                                                                                       |
| Security         | `permissionsets/RFP_Tool_User`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    | Phase 3a: the pricing team's RFP access — create/read/edit on the three RFP objects, read on `Pricing_Place__c`/`Account`, the RFP and Lane Benchmark Apex classes; phase 7 adds read and edit on `RFP_Lane__c.Miles__c`, `Miles_Source__c` and `Route_Hours__c`, and read on `Truck_Route__c`, and class access to `TripRouteView`; phase 8 adds class access to `CarrierLeadController` and `SplitLaneController`                                                                                              |
| Apex             | `classes/RfpImportService`, `RfpLaneController`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   | Phase 3b: mapped rows into `RFP_Lane__c` (city key then postal prefix); lane list, pricing whitelist, raw rows for export, manual end resolution                                                                                                                                                                                                                                                                                                                                                                 |
| Apex             | `classes/RfpHistoryService`, `RfpHistoryController`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               | Phase 3b: per-lane carrier-quote history snapshots (CITY, falling back to the chosen radius, default 50 km, on a miss)                                                                                                                                                                                                                                                                                                                                                                                           |
| Apex             | `classes/RfpProjectController`, `RfpBidController`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                | Phase 3b: projects, column mapping, file attach, customer/carrier typeahead; bids                                                                                                                                                                                                                                                                                                                                                                                                                                |
| Apex             | `classes/RfpUserError`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            | Phase 3b: shared `AuraHandledException` helper used by the four workbench controllers                                                                                                                                                                                                                                                                                                                                                                                                                            |
| UI               | `lwc/rfpHeaderGuess`, `rfpSheet`, `rfpSheetLoader`, `rfpWorkbook`, `rfpMath`, `rfpPricing`, `rfpBatch`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            | Phase 3b: pure modules — header guessing, workbook parsing and CSV codepage detection, the SheetJS script loader, export workbook building, bid/price math, chunked lane batching                                                                                                                                                                                                                                                                                                                                |
| UI               | `lwc/rfpTool`, `rfpProjectList`, `rfpUpload`, `rfpColumnMapper`, `rfpLaneTable`, `rfpLanePanel`, `rfpBidForm`, `rfpAccountPicker`, `rfpExport`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    | Phase 3b: the workbench container plus its project list, file upload, column mapper, lane table, lane detail panel, bid form, customer/carrier typeahead and Excel export                                                                                                                                                                                                                                                                                                                                        |
| UI               | `lwc/helpCenter`, `helpHint`, `helpContent`; `staticresources/helpCenter`; `flexipages/Help_Center`, `tabs/Help_Center`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           | Phase 5: the Help tab (bilingual user guide built from `docs/help`), the "?" hint popover, and the module that loads the content                                                                                                                                                                                                                                                                                                                                                                                 |
| UI               | `lwc/distanceUnit`, `distanceUnitToggle`, `routeMap`; `messageChannels/Distance_Unit` (`Distance_Unit__c`)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        | Phase 7: the shared mi/km module, the toggle that publishes the unit, the static route map with its legend and Refresh route, and the Lightning message channel that keeps every component on a page on the same unit                                                                                                                                                                                                                                                                                            |
| UI               | `lwc/carrierLeadRules`, `carrierLeads`, `splitLaneOptions`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        | Phase 8: the no-rate, place-key and direct median rules; the Carriers to ask card; the Split-lane options card (CAD or USD, handoff cost, Use as cost). `laneBenchmark`, `rfpLanePanel`, `rfpLaneTable` (no rate tag), `rfpPricing` (Split) and `rfpWorkbook` (Cost source column) use them                                                                                                                                                                                                                      |
| Navigation       | `tabs/RFP_Tool`, `flexipages/RFP_Tool`, `applications/TransPro` (tab added), `applications/Lane_Benchmark` (tab added)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            | Phase 3b: the RFP Tool tab/page, added to both apps                                                                                                                                                                                                                                                                                                                                                                                                                                                              |
| Security         | `staticresources/sheetJs`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         | Phase 3b: SheetJS Community Edition 0.18.5 (Apache-2.0), vendored in-repo because the org's same-named static resource belongs to the EN6IA managed package                                                                                                                                                                                                                                                                                                                                                      |

Not included on purpose:

- Managed-package metadata (`rtms__*` fields and objects, the `rtms.CarrierQuoteUpsert` trigger) is not retrievable.
- Two record-triggered flows on Carrier Quote (`UAT_Carrier_Quote_Created`, `UAT_Carrier_Quote_Delete`) belong to a separate UAT tracking system and only call its subflows. They are left out so a deploy from this project never touches them.

## How the data flows

```
Load (rtms__Load__c) ───┐
Carrier Service ────────┼─► formulas on rtms__CarrierQuote__c ─┐
Vendor Account ─────────┘                                      ├─► LaneSearchService ─► Lane Benchmark page
Benchmark_Rate__c (RFP bids) ──────────────────────────────────┘                        RFP workbench
```

Nearly every lane column is a cross-object formula on Carrier Quote (origin,
destination, mode, equipment, customer, contact, carrier risk, blacklist flag).
`LaneSearchService` binds them to one typed request - precision, radius, lookback,
filters - merges load-less `Benchmark_Rate__c` bids in as a second source, dedupes,
and returns per-currency stats to the Lane Benchmark page and to the RFP workbench's
per-lane history.

## Working with the org

### Environments

| Org        | Alias       | Role                                            | Data                    |
| ---------- | ----------- | ----------------------------------------------- | ----------------------- |
| PostProduc | `sandbox`   | Develop, test, CI, UAT. Real deploys land here. | Real, copied at refresh |
| Production | `vscodeOrg` | Live. Deployed after sign-off in PostProduc     | Real                    |

Full is other teams' active development sandbox and is not used for this project.
A Developer Pro sandbox (`devpro`) was also tried, but it cannot insert `rtms__Load__c`:
the Revenova managed triggers need configuration records that only a data-carrying
sandbox has.

### After a PostProduc refresh

Re-authorize the refreshed org:

```bash
sf org login web -a sandbox -r https://test.salesforce.com
```

Then regenerate the CI secret in the TPLM repository (see CI section). A refresh changes
the org id and appends `.invalid` to every user email.

Reinstalling the app is one command, and rerunning it is safe:

```bash
scripts/install-sandbox.sh                # deploy, assign the permission sets, report
scripts/install-sandbox.sh --dry-run      # validate only, change nothing
scripts/install-sandbox.sh --build-places # also start the place dictionary batch
scripts/install-sandbox.sh --org other    # a sandbox other than `sandbox`
```

It deploys the whole manifest with `NoTestRun` (about two minutes), assigns
`Lane_Benchmark_User` and `RFP_Tool_User`, treating an existing assignment as success,
and then reports the two pieces of **data** a metadata deploy cannot carry: the Mapbox
key in `TPRO_KPI__c.Mapbox_Api_Key__c` and the `Pricing_Place__c` dictionary. It prints
whether the key is set without ever selecting it, so the token stays out of terminals
and CI logs. The CSP trusted site and the remote site are metadata and ride along in the
manifest, so they need no manual step.

Before deploying it checks `Organization.IsSandbox` and refuses a production org — the
alias is not what protects you, the org's own answer is. Production goes live through
the runbook under "Retired: Pricing Department page (phase 4)", which runs the test
roster and the one-time destructive manifest.

A full refresh inherits the key and the dictionary from production, so the expected
result is "Nothing left to do by hand". Verified in PostProduc on 2026-09-16: deploy
`0AfbZ00000Crdh4SAB`, 326/326 components, 0 errors, both permission sets already
assigned, 10,554 places.

The commands it wraps, should you prefer to run them one at a time:

```bash
# Re-pull everything in the manifest
sf project retrieve start -x manifest/package.xml -o sandbox

# Deploy back (validate first)
sf project deploy validate -x manifest/package.xml -o sandbox
sf project deploy start    -x manifest/package.xml -o sandbox

# Run the tests
sf apex run test -n LaneSearchExclusionsTest -n PlaceNormalizerTest -n PricingTestDataFactoryTest -n PlaceBuilderBatchTest -n LaneSearchServiceTest -n MapboxGeocoderTest -n LaneBenchmarkControllerTest -n LaneBenchmarkPlaceServiceTest -n RfpTestDataFactoryTest -n BenchmarkRateServiceTest -n BidSearchQueryBuilderTest -n BidSearchServiceTest -n RfpControllerTest -n RfpSecurityTest -n RfpBidAccessTest -n MapboxTruckRouteTest -n RouteMapUrlTest -n TripMilesServiceTest -n RfpImportServiceTest -n RfpLaneControllerTest -n RfpHistoryServiceTest -n RfpProjectControllerTest -n RfpBidControllerTest -n RfpPricingMathTest -n RfpBulkServiceTest -n RfpBulkControllerTest -n SplitTestDataTest -n LaneSearchQueryBuilderTest -n LaneKeyMatcherTest -n IntercompanyCarriersTest -n HandoffPointsTest -n ExchangeRatesTest -n CarrierWarningTest -n LaneQueriesTest -n CarrierLeadServiceTest -n CarrierLeadControllerTest -n CarrierSplitSecurityTest -n SplitLaneServiceTest -n SplitEstimatesTest -n SplitLaneControllerTest -n CarrierSplitLimitsTest -n MarketTestServiceTest -n MarketTestControllerTest -o sandbox -r human -w 15
```

```bash
# Deploy to PostProduc. --post-destructive-changes is a two-step, not a re-runnable one:
# add the members to manifest/destructiveChangesPost.xml, deploy once, then empty the
# manifest again. A second deploy naming already-deleted components fails the whole run.
sf project deploy start -x manifest/package.xml --post-destructive-changes manifest/destructiveChangesPost.xml -o sandbox -l RunSpecifiedTests -t LaneSearchExclusionsTest PlaceNormalizerTest PricingTestDataFactoryTest PlaceBuilderBatchTest LaneSearchServiceTest MapboxGeocoderTest LaneBenchmarkControllerTest LaneBenchmarkPlaceServiceTest RfpTestDataFactoryTest BenchmarkRateServiceTest BidSearchQueryBuilderTest BidSearchServiceTest RfpControllerTest RfpSecurityTest RfpBidAccessTest MapboxTruckRouteTest RouteMapUrlTest TripMilesServiceTest RfpImportServiceTest RfpLaneControllerTest RfpHistoryServiceTest RfpProjectControllerTest RfpBidControllerTest RfpPricingMathTest RfpBulkServiceTest RfpBulkControllerTest SplitTestDataTest LaneSearchQueryBuilderTest LaneKeyMatcherTest IntercompanyCarriersTest HandoffPointsTest ExchangeRatesTest CarrierWarningTest LaneQueriesTest CarrierLeadServiceTest CarrierLeadControllerTest CarrierSplitSecurityTest SplitLaneServiceTest SplitEstimatesTest SplitLaneControllerTest CarrierSplitLimitsTest MarketTestServiceTest MarketTestControllerTest
```

Org aliases: `sandbox` = PostProduc, `vscodeOrg` = production.

User-mode Apex (`LaneBenchmarkController`, `RfpBidAccess`'s lane, project and
carrier checks, `RfpBulkService`, `RfpController`, `RfpHistoryService`,
`RfpImportService`, `RfpLaneController`, and `RfpProjectController`) needs its
permission set (`RFP_Tool_User`) already assigned to the test-running user
before a `RunSpecifiedTests` deploy — `WITH USER_MODE` reports a field the
running user cannot read as "No such column". When a deploy introduces or
changes that permission set in the same deploy as new user-mode code, deploy
the permission set on its own first with `-l NoTestRun`, assign it, then run
the real test-running deploy.

Every new LWC bundle must be registered in `manifest/package.xml`
(`LightningComponentBundle` members) — phase 3b found 16 bundles that had
been created but never added to the manifest, so `sf project retrieve start`
against the manifest would have silently dropped them.

### Place dictionary

`Pricing_Place__c` was built once in PostProduc on 2026-09-09 by running:

```apex
Database.executeBatch(new PlaceBuilderBatch(), 2000);
```

(`sf apex run -o sandbox` with that one line; `PlaceBuilderBatch.finish()` chains
`PlaceWriteBatch`, which upserts the built rows in governor-safe per-scope
transactions, then chains `PlaceUsageBatch` to fill `Load_Count_365d__c`, which
also writes through `PlaceWriteBatch`.) Rerun the same command any time; it never
deletes a place and never overwrites `Aliases__c` or `Active__c`.

Result: **10,496 places** (`SELECT COUNT() FROM Pricing_Place__c`), built from
58,755 location accounts referenced by a stop, which carry 11,479 distinct raw
`ShippingCity` spellings before normalization — so `PlaceNormalizer` collapses at
least 983 spelling/case/accent variants into shared keys (places are also split by
province and country, so the true collapse per city name is higher than that
difference suggests).

The dictionary was deleted and rebuilt from scratch on 2026-09-09 after the
Mexican-province fix, because every key holding a Mexican province changed
(`general escobedo|nuevo león|mx` → `general escobedo|nl|mx`) and an upsert by
`Key__c` would have left the old keys behind. The count came back to the same
10,496: the remapping is one-to-one, since no two Mexican state names share a code.
428 of those places are Mexican and **none** of them now carries a province longer
than the 2-letter code Revenova writes. 536 places worldwide (Guangdong, Istanbul,
Shanghai, Baden-Württemberg…) keep a full province name that used to be cut to three
characters.

Rerun the top 20 with:

```bash
sf data query -q "SELECT Name, Key__c, Location_Count__c, Load_Count_365d__c, Postal_Prefix__c FROM Pricing_Place__c ORDER BY Load_Count_365d__c DESC NULLS LAST LIMIT 20" -o sandbox
```

Top 20 places by loads touching this place (last 365 days), from the rebuilt
dictionary on 2026-09-09. `Load_Count_365d__c` counts one per load END, so a
load that both picks up and delivers in the same place counts 2 there.

| Name                      | Key                         | Locations | Loads (365d) | Postal prefix |
| ------------------------- | --------------------------- | --------- | ------------ | ------------- |
| Laredo, TX, US            | `laredo\|tx\|us`            | 970       | 6173         | 780           |
| Mississauga, ON, CA       | `mississauga\|on\|ca`       | 1470      | 2995         | L5T           |
| Lachine, QC, CA           | `lachine\|qc\|ca`           | 177       | 2892         | H8T           |
| Brampton, ON, CA          | `brampton\|on\|ca`          | 691       | 2754         | L6T           |
| Montréal, QC, CA          | `montreal\|qc\|ca`          | 1152      | 2720         | H4S           |
| Anjou, QC, CA             | `anjou\|qc\|ca`             | 121       | 2577         | H1J           |
| Calgary, AB, CA           | `calgary\|ab\|ca`           | 930       | 1918         | T2C           |
| Knowlton, QC, CA          | `knowlton\|qc\|ca`          | 16        | 1310         | J0E           |
| GENERAL ESCOBEDO, NL, MX  | `general escobedo\|nl\|mx`  | 5         | 1277         | 660           |
| Toronto, ON, CA           | `toronto\|on\|ca`           | 865       | 1179         | M9W           |
| Veracruz, ME, MX          | `veracruz\|me\|mx`          | 2         | 1165         | 916           |
| Baie-d'Urfé, QC, CA       | `baie d urfe\|qc\|ca`       | 68        | 1118         | H9X           |
| Laval, QC, CA             | `laval\|qc\|ca`             | 403       | 1043         | H7L           |
| Rocky View County, AB, CA | `rocky view county\|ab\|ca` | 47        | 921          | T4A           |
| Vaughan, ON, CA           | `vaughan\|on\|ca`           | 293       | 876          | L4K           |
| San Diego, CA, US         | `san diego\|ca\|us`         | 132       | 859          | 921           |
| Burnaby, BC, CA           | `burnaby\|bc\|ca`           | 175       | 851          | V5J           |
| Edmonton, AB, CA          | `edmonton\|ab\|ca`          | 658       | 845          | T5S           |
| Boucherville, QC, CA      | `boucherville\|qc\|ca`      | 144       | 835          | J4B           |
| Dorval, QC, CA            | `dorval\|qc\|ca`            | 223       | 732          | H9P           |

The two Mexican rows are the point of the fix: they read `Nue` and `Mex` before it,
and no CITY or PROVINCE search could reach either place. Every count here is lower
than the first build's, because the number now means loads (one per end) rather than
every stop on every load.

Montréal/Montreal spot check. `Spellings__c` is a long text area with one
spelling per line; the block below is reformatted onto single lines (`/`
between spellings) so it fits here:

```
SELECT Name, Key__c, Spellings__c FROM Pricing_Place__c WHERE Key__c LIKE 'montreal|%'
Montréal, QC, CA | montreal|qc|ca | MONTREAL / MONTREAL, / MONTRÉAL / MONTRÉAL, / Montreal / Montreal, / Montréal / Montréal, / montreal
Montreal, , CA   | montreal||ca   | MONTREAL / Montreal
```

`montreal|qc|ca` is the intended collapse: `Spellings__c` shows "Montréal",
"Montreal" and "MONTREAL" (plus accented/cased/punctuated variants) all merged
into one place under `ShippingState = QC` (the raw location accounts have 577
"Montréal", 573 "MONTREAL", and 18 more such rows — see the spec Outcome for the
full breakdown — plus a few unrelated near-matches like "Montrose" and
"Montréal-Nord", which correctly stay separate places). `montreal||ca` is a
second, minor key from a handful of accounts where the full city/province/postal
string was typed into `ShippingCity` with `ShippingState` left blank (e.g.
"Montreal QC", "MONTREAL, QC H2P 1L5") — real, messy source data the normalizer
correctly treats as a different (blank-province) key rather than silently
guessing the province.

`Name` has no field-level security of its own, so anyone who can edit
`Pricing_Place__c` can also retype the place's name - and `PlaceBuilderBatch`
overwrites it on the next run. Only `Aliases__c` and `Active__c` survive a rebuild.
Phase 4 removed `Pricing_Department_User`, which was the only permission set granting
that Edit; `Lane_Benchmark_User` and `RFP_Tool_User` grant Read alone, so curating
aliases now needs an admin or a new permission set.

### Lane search

`LaneSearchService.search(LaneSearchRequest)` returns a `LaneSearchResult` (rows,
`statsByCurrency` per currency, `truncated`, `elapsedMs`, `dedupedCount`). A worked
example against real data lives at `scripts/apex/laneSearchExample.apex` (run with
`sf apex run -f scripts/apex/laneSearchExample.apex -o sandbox`); measured timings
are recorded in `docs/superpowers/specs/2026-09-09-phase-1-search-foundation-design.md`
under Outcome. Sample request, city precision, last 90 days:

```apex
LaneSearchRequest r = new LaneSearchRequest();
r.originKey = 'montreal|qc|ca';
r.destinationKey = 'toronto|on|ca';
r.originPrecision = LaneSearchRequest.Precision.CITY;
r.destinationPrecision = LaneSearchRequest.Precision.CITY;
r.lookbackDays = 90;
LaneSearchResult res = LaneSearchService.search(r);
```

### Support case

Custom-index request for `rtms__Load__c.rtms__City_Lane__c` /
`rtms__State_Lane__c` / `rtms__Zip3_Lane__c`: case number ______ (filed by the
user).

## Lane Benchmark (phase 2)

A new page, tab and Lightning app, alongside the existing Pricing Department
page (which stays untouched until pricing confirms the switch — see
"Retiring the old tab" below).

**Opening it:** either the **Lane Benchmark** tab inside the **TransPro**
app, or the standalone **Lane Benchmark** app from the App Launcher.

**After a deploy:** users may need a hard reload (Cmd+Shift+R) once, since
Lightning caches components in the browser.

**Precision** (chosen per origin and destination independently):

- **Exact city** — matches the place's normalized city/province/country key.
- **Province or state** — matches anywhere in that province/state.
- **Postal prefix** — matches the first three characters of the postal code.
- **Radius** — matches within a distance (mi or km) of the place's
  geolocation; a static map preview appears once at least one end uses this
  precision.

**Margin controls:** one margin percentage (default 15, buttons for 15% and
20%, or free entry 0-100) applies across every currency's stats card and
drives the suggested sell price (`cost × (1 + margin / 100)`) shown next to
the median and average.

**CSV export:** "Export CSV" downloads the currently visible rows
(RFC 4180 quoting, UTF-8 BOM so accented city names open correctly in
Excel/Numbers), named `lane-benchmark-<origin>-<destination>-<yyyymmdd>.csv`.

**Remembered filters:** the last search request is saved to `localStorage`
under the key `laneBenchmark.request.v1` and restored (and re-run) the next
time the page opens. The filters panel has a "Clear saved filters" link that
removes that key and also resets the page back to an empty request and no
result — a full reset, not just a storage clear.

**Search caching:** `LaneBenchmarkController.search` is a cacheable Apex
method (`@AuraEnabled(cacheable=true)`), so re-running an identical request
within a few minutes may serve cached rows instead of hitting the query again.

**Mapbox reuse:** the picker's "Search on the map" fallback and the radius
map preview call Mapbox through the same setup `KPI_ReportController`
already uses — no new credential was created. "Search on the map" creates
`Pricing_Place__c` rows (`Source__c = 'Mapbox'`) for any Lane Benchmark user
through system-mode Apex (`LaneBenchmarkPlaceService` is `without sharing`),
making one Mapbox call per click:

- Token: the org-default record of the hierarchy custom setting
  `TPRO_KPI__c`, field `Mapbox_Api_Key__c` (a public `pk.` token).
- Remote Site Setting: `MapBox`, for `https://api.mapbox.com`.
- CSP Trusted Site: `Mapbox_API` (`img-src`, for the static map `<img>`).

Because the token is public and appears in the static-map image URL,
add URL restrictions on it in the Mapbox account for `*.my.salesforce.com`,
`*.lightning.force.com` and `*.sandbox.my.salesforce.com` so it only works
from this org's domains.

**Permission set:** assign `Lane_Benchmark_User` to the pricing team —

```bash
sf org assign permset -n Lane_Benchmark_User -o sandbox
```

## Retired: Pricing Department page (phase 4)

Lane Benchmark and the RFP workbench replaced the original page, so on 2026-09-12 it
left the repo and PostProduc.

**Removed:** `tabs/Pricing_Department`, `flexipages/Pricing_Department`,
`lwc/pricingDepartment` (bundle and Jest suite), `lwc/quoteStats` (the old page's stats
helper, which nothing else imported), `classes/PricingDepartmentController` and
`PricingDepartmentControllerTest`, `permissionsets/Pricing_Department_User`, and the
reference-only `profiles/Pricing` (never deployed; git history keeps all of it).
The first commit of the change (`e4bd684`) removes the controller from the repo while
the manifest still lists the component that imported it, so that commit is not
deployable on its own; the branch was always deployed from its second commit onward.

**Kept:** the custom metadata type `Pricing_Department_Setting__mdt`, its
`Excluded_Contact_Ids__c` field and its `Default` record - every lane search still reads
the excluded Contact Ids from them, now through `LaneSearchExclusions`. Every
`rtms__CarrierQuote__c` formula field is kept too, including the eight only the old page
read: `Accepted_quote__c`, `CAD_Quote_Total__c`, `Customer_Name__c`, `Decline_Quotes__c`,
`Nb_Of_Pallets__c`, `Origin_Destination_Country__c`, `Ship_Date__c` and
`Shipping_Date__c`. Deleting a field is irreversible and reports may still use them, so
retiring those eight is an admin follow-up, not part of this change.

**PostProduc deploys:** `0AfbZ00000CpbZhSAJ` added `LaneSearchExclusions` and repointed
every consumer (124/124 Apex tests); `0AfbZ00000CpaH4SAJ` then deleted the five
components together with the two Apex classes (124/124). A first attempt,
`0AfbZ00000Cpb53SAB`, failed on "This apex class is referenced elsewhere in Salesforce":
Salesforce will not delete `PricingDepartmentController` while `lwc/pricingDepartment`
imports `getCarrierQuotes`, so both classes are deleted with the component instead - which
is why `manifest/destructiveChanges-phase4.xml` lists all of them in one file.
The orphaned `quoteStats` bundle was removed in the
review fix wave (deploy `0AfbZ00000CpbwHSAR`).

**Production is the admin's step, in this order** (users on the `Pricing` profile lose the
tab, so they need the replacement permission sets first). Two cautions before starting:
the command in step 3 deploys the whole manifest, so if production has not received
phases 1–3 yet this is their go-live too and their one-time steps come first (the Mapbox
key in `TPRO_KPI__c.Mapbox_Api_Key__c`, the CSP trusted site and remote site, the place
dictionary batch from "Place dictionary" above, and `Pricing_Department_Setting.Default`
being overwritten from the repo); and the manifest carries a snapshot of the `TransPro`
app, which replaces any navigation edits made in production Setup - retrieve production's
`TransPro` app and diff it against `applications/TransPro.app-meta.xml` first.

1. Assign the replacements to the pricing team, and unassign the old set from everyone
   who still holds it (a permission set with assignments cannot be deleted). List the
   holders, then remove each assignment by its Id:

```bash
sf org assign permset -n Lane_Benchmark_User -o vscodeOrg
sf org assign permset -n RFP_Tool_User -o vscodeOrg
sf data query -o vscodeOrg -q "SELECT Id, Assignee.Name FROM PermissionSetAssignment WHERE PermissionSet.Name = 'Pricing_Department_User'"
sf data delete record -o vscodeOrg -s PermissionSetAssignment -i <Id from the query, one command per row>
```

2. Pre-check the two legacy test classes. Phase 0 deleted
   `PricingDepartmentControllerTest3` and `PricingDepartmentController_TGN_TEST` from
   PostProduc only; if production still has them, the destructive deploy fails with
   "This apex class is referenced elsewhere in Salesforce" because both call the
   controller. Check, and when they exist add them to the `ApexClass` block of a local
   copy of the manifest:

```bash
sf org list metadata -o vscodeOrg -m ApexClass --json | grep -E "PricingDepartmentControllerTest3|PricingDepartmentController_TGN_TEST"
cp manifest/destructiveChanges-phase4.xml /tmp/destructive-phase4-prod.xml
# if the grep printed either name, add <members>…</members> lines for them next to
# PricingDepartmentControllerTest in /tmp/destructive-phase4-prod.xml and use that
# file in step 3 instead of manifest/destructiveChanges-phase4.xml
```

3. Deploy the code and run the one-time destructive manifest. It is deliberately not part
   of the routine deploy command: a second run fails, because the components are gone.

```bash
sf project deploy start -o vscodeOrg --manifest manifest/package.xml --post-destructive-changes manifest/destructiveChanges-phase4.xml -l RunSpecifiedTests -t LaneSearchExclusionsTest PlaceNormalizerTest PricingTestDataFactoryTest PlaceBuilderBatchTest LaneSearchServiceTest MapboxGeocoderTest LaneBenchmarkControllerTest LaneBenchmarkPlaceServiceTest RfpTestDataFactoryTest BenchmarkRateServiceTest BidSearchQueryBuilderTest BidSearchServiceTest RfpControllerTest RfpSecurityTest RfpBidAccessTest MapboxTruckRouteTest RouteMapUrlTest TripMilesServiceTest RfpImportServiceTest RfpLaneControllerTest RfpHistoryServiceTest RfpProjectControllerTest RfpBidControllerTest RfpPricingMathTest RfpBulkServiceTest RfpBulkControllerTest SplitTestDataTest LaneSearchQueryBuilderTest LaneKeyMatcherTest IntercompanyCarriersTest HandoffPointsTest ExchangeRatesTest CarrierWarningTest LaneQueriesTest CarrierLeadServiceTest CarrierLeadControllerTest CarrierSplitSecurityTest SplitLaneServiceTest SplitEstimatesTest SplitLaneControllerTest CarrierSplitLimitsTest MarketTestServiceTest MarketTestControllerTest -w 30
```

## RFP Tool (phase 3a)

Foundation only: the data model, the bid service, bids as a second source in
Lane Benchmark, and a customer Account component. The workbench (upload,
mapping, history, bid form, export, the `RFP_Tool` tab/page) is phase 3b — see
the spec's Outcome for what is still open.

| Object              | Purpose                                                                                                                                 | Key fields                                                                                                                                                                                                               |
| ------------------- | --------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `RFP_Project__c`    | One customer RFP: the uploaded lane file, its lanes, bids and prices                                                                    | `Customer__c` (master-detail to Account, write requires master Read — phase 6), `Status__c`, `Due_Date__c`, `Default_Margin__c`, roll-ups `Lane_Count__c` / `Costed_Count__c` / `Sold_Count__c`                          |
| `RFP_Lane__c`       | One spreadsheet row of a project: the lane as the customer wrote it, the resolved places, the history snapshot and the chosen cost/sell | `RFP_Project__c` (master-detail), `Origin_Place__c` / `Destination_Place__c` (`Pricing_Place__c` lookups), `Mode__c`, `Equipment_Category__c`, `Cost__c` / `Margin__c` / `Sell__c`, `Has_Cost__c` / `Has_Sell__c`        |
| `Benchmark_Rate__c` | A carrier bid for a lane, captured without a Load                                                                                       | `RFP_Lane__c` / `RFP_Project__c` lookups, `Carrier__c` / `Carrier_Name__c`, `Rate__c`, `Valid_From__c` / `Expires_On__c`, `City_Lane__c` / `State_Lane__c` / `Zip3_Lane__c`, formulas `Status__c` / `Carrier_Display__c` |

**Lane keys and the `BenchmarkRateTrigger`.** A bid carries none of
`City_Lane__c` / `State_Lane__c` / `Zip3_Lane__c` from the browser. The
`before insert` / `before update` trigger `BenchmarkRateTrigger` calls
`BenchmarkRateService.applyLanes`, which copies them (plus
`RFP_Project__c`, the origin/destination geolocations, and — only when blank
on the bid — `Mode__c` / `Equipment_Category__c` / `Equipment_Type__c` /
`Hazmat__c`) from the lane's resolved `Pricing_Place__c` records
(`Origin_Place__r` / `Destination_Place__r`: city, province, postal prefix,
geolocation) into the same `"City, ST:City, ST"` / `"ST:ST"` / `"XXX:XXX"`
format `PlaceNormalizer` writes for Loads, so a bid matches a CITY-precision
search through `PlaceNormalizer.cityLaneVariants` exactly as a Load does.
Running this in a trigger (system context, one bulk query per batch for every
referenced lane) rather than only in `BenchmarkRateService.save` means a bid
created directly on the record page — bypassing `save()` entirely — is
stamped too; `save()` itself now only validates `Rate__c`. Since phase 6 the
insert/update/reload go through `RfpBidAccess`, in system mode after the lane
check (see "Access model (phase 6)" below). The caller still cannot set the
project, lane keys or geolocations: `RFP_Tool_User` marks those fields not editable
(see Permission sets below), and `RfpBidAccess` copies only the
caller-settable fields and strips the rest through
`Security.stripInaccessible` before the DML. The trigger also defaults `Valid_From__c` /
`Expires_On__c` to today / today+30 for every bid that doesn't already have
them, on top of the same defaults now carried on the field metadata itself
(`<defaultValue>TODAY()</defaultValue>` / `TODAY() + 30`, which only prefill
the standard "New" page, not an Apex-created record — hence the trigger).

**Permission sets.**

- `RFP_Tool_User` — the pricing team's access: create/read/edit on the three
  RFP objects (`RFP_Project__c`, `RFP_Lane__c`, `Benchmark_Rate__c`), delete on
  `RFP_Lane__c` and `Benchmark_Rate__c` only (no delete on `RFP_Project__c`),
  read on `Account` and read with View All on `Pricing_Place__c`, Apex class
  access to its 17 classes: `BenchmarkRateService`, `LaneBenchmarkController`,
  `LaneBenchmarkPlaceService`, `LaneSearchExclusions`, `LaneSearchService`,
  `MapboxGeocoder`, `RfpBidController`, `RfpBulkController`, `RfpBulkService`,
  `RfpController`, `RfpHistoryController`, `RfpHistoryService`,
  `RfpImportService`, `RfpLaneController`, `RfpPricingInput`,
  `RfpPricingMath`, and `RfpProjectController`, and the `RFP_Tool` custom
  permission (gates `rfpProjectsForAccount`, below). `RFP_Project__c` /
  `City_Lane__c` / `State_Lane__c` / `Zip3_Lane__c` / `Origin_Geolocation__c` /
  `Destination_Geolocation__c` on `Benchmark_Rate__c` are readable but not
  editable: they are service-maintained by `BenchmarkRateTrigger`, never
  user-entered. The project's grant through a lane-less bid (R67) relies on
  that.
- `Lane_Benchmark_User` gains object read on `Benchmark_Rate__c` and field read
  on all of its fields, including the formula fields `Carrier_Display__c` /
  `Status__c` (no create/edit — bids are entered through the RFP tool, not
  Lane Benchmark).
- Formula and roll-up fields need their own explicit read `fieldPermissions`
  entry, same as any other field: `WITH USER_MODE` reports a field the running
  user cannot read as "No such column", identical to a genuinely missing
  field, even though the field is never editable. This bit `Carrier_Display__c`
  / `Status__c` on `Benchmark_Rate__c` and `Lane_Count__c` / `Costed_Count__c`
  / `Sold_Count__c` on `RFP_Project__c` during 3a; both are now granted
  read-only.
- `RFP_Tool` — a custom permission (not a permission set) carried by
  `RFP_Tool_User`. `rfpProjectsForAccount` renders nothing, and never wires
  the Apex adapter with an `accountId`, unless the running user holds it —
  assign `RFP_Tool_User` to grant it.

**Lane Benchmark "Source" filter.** A radio group — All / Loads only / Bids
only, default All. "Bids only" is the only setting that also returns expired
bids; every other setting keeps the active-window `Expires_On__c >= TODAY`
condition. A bid row shows a "Bid" badge next to the carrier name and its
expiry in place of Accepted/Declined; an expired bid's entire row is greyed
out. The CSV export gains a "Source" column (`Load` / `Bid`) first.

**Customer Account component.** `rfpProjectsForAccount` (label "RFP Projects
(customer)") lists a customer's RFP projects, file names and bid counts; a row
click opens the project. It renders nothing on a non-customer record type, and
nothing for a user who lacks the `RFP_Tool` custom permission (assign
`RFP_Tool_User`).
Trans-Pro Customer accounts use Revenova's managed page
`rtms__Account_TMS_Record_Default` (template "Header and Left Sidebar"), and
App Builder can only save a clone of a managed page, never edit it in place.
To place the component:

1. Open a Customer account → the Setup gear → **Edit Page**. App Builder
   offers to save a clone.
2. Drag **RFP Projects (customer)** into the left sidebar, under the
   Activity/Chatter/Files tabs (or wherever the admin prefers).
3. **Save**, then **Activation** → choose the scope: org default for Account,
   or an App/Record Type/Profile assignment scoped to the Trans-Pro app and
   the Customer record type.
4. Note the clone's API name (App Builder proposed
   `Account_TMS_Record_Default14` when this was scoped) for future reference.

This step was not performed in 3a — activating a clone changes the Account
page for the whole org, an admin decision on a shared sandbox — so the
component is deployed but not yet visible on any Account page.

## RFP Tool (phase 3b)

The workbench: upload a customer's lane file, map its columns, import lanes,
pull carrier-quote history, price each lane, record carrier bids, and export
the customer's file back with our prices filled in.

**Opening it.** The **RFP Tool** tab, present in both the **TransPro** and
**Lane Benchmark** apps. The **RFP Projects (customer)** component on a
customer Account also opens a project directly: a row click navigates to
`standard__navItemPage` `RFP_Tool` with state `c__projectId`, which `rfpTool`
reads from `CurrentPageReference` and opens without showing the project list.

**Flow.** Project (create or open) → upload the customer's file → map its
columns to our fields (the mapping is remembered per customer) → import
lanes (each end resolved to a `Pricing_Place__c` by city key, then postal
prefix) → load carrier-quote history per lane (CITY, falling back to the
chosen radius, default 50 km, on a CITY miss) and carrier bids from other
RFPs → price each lane (from a bid, the history median, or
a manual cost, plus margin) → record carrier bids → export the customer's
file back with our prices and the selected bid filled in.

A second upload into the same project continues the row numbering where the
lanes already there left off, so the two sheets never share a row number.
Cells longer than the field they land in are cut to the field's length on
import (mode 40, equipment category 40, equipment type 80, quantity unit 20,
commodity 255, postal 12), and a row the platform still refuses is counted
into the import summary as `failed N` instead of taking its whole 200-row
chunk with it.

**Limits.**

- Upload: 3 MB per file, 2,000 lanes per project.
- Import: 200 rows per `importLanes` call (the browser chunks a larger file).
- History: 10 lanes per `loadHistory` call.
- Raw rows (export only): paged 500 at a time through `getRawRows`.
- Export: at most 200 lanes' selected bids are fetched, one `getBids` call
  per lane, when building the workbook.

**SheetJS.** The browser parses the workbook with static resource `sheetJs`
(SheetJS Community Edition 0.18.5, Apache-2.0), vendored under
`force-app/main/default/staticresources/`. It could not stay org-side as the
plan assumed: the org's own `sheetJs` StaticResource belongs to the EN6IA
managed package, so a bare `resourceUrl` reference to it never resolves (see
the spec Outcome for the ruling). Keep the vendored file at 0.18.5 unless it
is deliberately upgraded.

**CSV encoding.** A `.csv`/`.txt` upload carries no encoding of its own; the
bytes are sniffed with `TextDecoder('utf-8', { fatal: true })` before
parsing — decodable as UTF-8, it is read as UTF-8 (SheetJS codepage 65001),
otherwise as Windows-1252 (1252). Workbook formats (`.xlsx`/`.xlsm`/`.xls`)
carry their own encoding and are read as-is.

**Typeaheads.** The customer and carrier pickers (`rfpAccountPicker`) both
call the same Apex typeahead, `RfpProjectController.searchAccounts(term,
kind)`, filtered by Account record type.

**Uploaded file.** `attachFile` inserts the raw upload as a
`ContentVersion`/`ContentDocumentLink` on the `RFP_Project__c` record; it
shows up under Files on the project, not on the lanes.

**Permission set and custom permission.** `RFP_Tool_User` gains tab
visibility for `RFP_Tool` (alongside its existing `Lane_Benchmark` app and
tab visibility) and class access to every workbench controller — now
including the bulk controller — and to the services behind them
(`RfpProjectController`, `RfpLaneController`, `RfpHistoryController`,
`RfpBidController`, `RfpBulkController`, `RfpImportService`,
`RfpHistoryService`, `RfpBulkService`, `RfpPricingInput`,
`RfpPricingMath`). Every new `@AuraEnabled` class needs a `classAccesses`
entry in `RFP_Tool_User`, just as every new bundle needs a manifest entry.
The `RFP_Tool` custom permission (added in 3a) still gates
`rfpProjectsForAccount`; assigning `RFP_Tool_User` grants both the
workbench tab and that permission.

### Phase 3c — pricing

- **Sell and margin are linked.** Typing a margin recomputes the sell; typing a sell recomputes the margin and marks the lane `Sell source = Manual`. A Manual sell survives later cost changes (the margin moves instead). Lanes saved before 3c read as Margin.
- **Radius.** The "Radius" box (1–500, km or mi, default 50 km) is used for Radius precision and for the city → radius fallback; the snapshot stamps `RADIUS-<n>KM|MI` in `Hist_Precision__c`.
- **Bulk bar.** Scope "Selected (N)" or "All lanes (M)"; Use median (applies where a lane has a history median; lanes costed from a bid or by hand are skipped and offered as "Overwrite them"; lanes without a median are reported separately), Apply margin / cost / sell, Add carrier rate (one Benchmark Rate per lane, selected as the cost; lanes in another currency are skipped), Delete selected (two clicks; takes the lanes' carrier rates). Every action runs 200 lanes per Apex call (`RfpBulkController`), user mode, with a progress bar and Stop.
- **Inline editing.** Click or press Enter on a Cost, Margin or Sell cell; Enter/Tab save and move down the column, Shift+Tab up, Escape cancels, leaving the cell saves. A row shows a sync icon while saving and a red icon (hover for the reason) when the save failed.
- **Filters.** Show: all / unpriced / no history match / unresolved ends / manual cost or sell / selected, plus a text search on origin, destination and equipment. "Select all" selects the rows shown.
- **Twins.** After a lane is priced, unpriced lanes with the same two places, mode and equipment are offered "Apply the same cost and sell to N identical lanes" (`copyPricing`: the twin points at the same bid).
- **Export.** New columns Annual sell (sell × shipments per year) and Sell source; a third sheet, Summary (counts, total annual sell per currency, average margin, by mode).
- **Permissions.** `RFP_Tool_User` can now delete `RFP_Lane__c` and `Benchmark_Rate__c`.
- **Limits.** Bulk actions run 200 lanes per Apex call; a lane's twins are matched on origin place, destination place, mode and equipment; the delete confirm resets when the selection changes; the radius is 1–500.

### Phase 3d — bids in history

- **What is counted.** A lane's history counts Revenova carrier quotes _and_ the carrier bids (`Benchmark_Rate__c`) recorded on other RFP projects — plus bids with no project, from Lane Benchmark — for the same lane match and the same lookback. The count, the median and the min/avg/max tooltip all run over both sources.
- **The exclusion.** Bids on the project being priced are left out: they are the pricer's own inputs on the sheet in front of them, not market evidence, and the lane panel already lists them separately (ruling R46).
- **Expired bids.** A bid inside the lookback counts even when its validity window has passed — an old RFP's bids are nearly always expired (30-day default) and are exactly the quotes this is for; the lookback, not the expiry, bounds relevance (ruling R45). The panel's results table still greys them and shows "Expires <date>".
- **The toggle.** "Include RFP bids" in the workbench toolbar (on by default) applies to the next Load history / Refresh history / Retry failed run. With it off a run is loads-only, exactly as before 3d.
- **The new field.** `RFP_Lane__c.Hist_Bid_Count__c` records how many of the counted rows were bids. The History cell then reads `12 loads + 3 bids · median 5800.00` (and stays `12 · median …` when none were), the export carries a "History bids" column, and the lane panel's own results query repeats the lane's last run — bids and expired bids when the count is anything but 0, loads only when it is 0.

## Access model (phase 6)

**Who sees an RFP.** `RFP_Project__c.Customer__c` is a master-detail to Account with
"write requires master Read" on, and `RFP_Lane__c` follows the project the same way.
So Salesforce account sharing decides: a user who can read a customer account sees its
RFPs (RFP Tool list, the account page component, deep links) and can create, price and
delete their lanes and bids; a user who cannot read the account does not see the RFP at
all. There is no owner on a project. Admins with View All Data see everything. Deleting
an account deletes its RFPs and lanes; their bids survive with the lookups cleared.

**Bids.** `Benchmark_Rate__c` is Private. The workbench runs no SOQL or DML on
`Benchmark_Rate__c` in user mode: `RfpBidAccess` is the one class that reads and writes
the bids of an RFP's own lanes (bid counts are gated on the project); the history run and
the lane panel's market search read other RFPs' bids through the Lane Benchmark services,
as the phase 6 design's D2 intends. `RfpBidAccess` first proves in user mode that the
running user can read the lane, then works in system mode restricted to those lanes and
through `Security.stripInaccessible`. The user-mode lane query does traverse
`Selected_Bid__r`; for a colleague's Private bid that traversal comes back empty, and
`RfpBidAccess.attachSelectedBids` fills it after every `RfpLaneController` lane read.
Rule: a lane you can see grants its bids, whoever recorded them. A bid whose lane was
deleted outside the workbench keeps its project and is granted through it, read in user
mode (R67). That adds no access because a bid's project is service-maintained:
`BenchmarkRateTrigger` stamps it from the lane and `RFP_Tool_User` cannot edit it, so it is
the project of the last lane the bid had, and lanes follow their project.

Three hardening points from the phase 6 final review and its residual round. A bid save
copies only the caller-settable fields (carrier, contact, rate, currency, fuel surcharge,
transit days, validity dates, notes, mode, equipment, hazmat, and the lane on insert
only), so the owner, the project and the lane keys come only from the platform and
`BenchmarkRateTrigger`; an update that names another lane, or none, is refused with "A bid
cannot move to another lane." And Lane Benchmark honours an RFP exclusion
(`excludeProjectId`) only for a project the caller can read in user mode, so two searches
cannot reveal which bids belong to an RFP the caller cannot see; the RFP history run keeps
its own exclusion. And a bid save may name a carrier account (`Carrier__c`) only if the
caller can read that account in user mode (R66), otherwise it is refused with "That
carrier is not available.": the system-mode DML skips the sharing check a lookup gets, and
the reloaded bid would show the account's name. A carrier the bid already stores is not
re-checked, so a colleague can still edit the rate of a bid whose carrier account they
cannot read.

Lane Benchmark (`LaneSearchService`, `BidSearchService`) keeps reading
every bid in system mode and shows carrier, rate and expiry only, never the customer.

**Admin task (not code).** Pricers need at least Read on the customer accounts they
price for: through the role hierarchy or an Account sharing rule to the pricing group.
Account is Private in this org, so without one of those a pricer sees no RFP. In
PostProduc the admin user holds `RFP_Tool_User` and sees everything; the restriction is
proven by `RfpSecurityTest` (restricted users created per scenario, holding
`RFP_Tool_User`, `Lane_Benchmark_User` or both, with the admin as the account owner) and
`RfpBidAccessTest`.

**Production.** None of these objects exist there yet; the go-live deploy creates them in
their final shape. A sandbox that already holds RFP data converts in place as long as
every project has a customer (the New project form requires one). The carrier tests in
`RfpSecurityTest` and `RfpBulkControllerTest` expect the Account fields `Company_Org__c`
and `Black_List__c`; in an org whose carrier sharing lets a restricted user read their
blacklisted Trans-Pro Logistica carrier they skip instead of failing (R68), so there the
carrier check is proven only by the PostProduc runs.

## Trip miles (phase 7)

Every lane shows how long the trip is, in miles by default and in km on click, with a
rate per mile wherever a price meets miles: the RFP workbench (Miles column, lane panel,
Excel export) and Lane Benchmark (statistics, results, CSV, map). Design:
`docs/superpowers/specs/2026-09-14-phase-7-trip-miles-design.md`.

**Where a lane's miles come from, in order** (R75):

1. **History** — the median of Revenova's billed Distance (Miles)
   (`rtms__Load__c.rtms__Distance_Miles__c`, filled by PC\*Miler) over the loads the
   lane's history search matched, each load counted once however many of its quotes
   matched, at the precision it used, radius fallback included (R70). Bid rows carry no
   miles. PC\*Miler cannot be called directly: Revenova's mileage classes are not visible
   to our Apex.
2. **Truck route** or **Regular route** — the main route of the `Truck_Route__c` row
   stored for the lane's ordered place pair and the current truck profile.
3. **No route** — a stored route for the pair where Mapbox found no road, even without
   truck limits: the miles and hours stay blank, and no Approx distance is drawn for a
   trip no road makes.
4. **Approx** — the great-circle distance between the two places' `Geolocation__c`
   (Earth radius 3,958.7613 mi) × `Approx_Factor__c`: 1.2, the median ratio of billed to
   straight-line miles measured on 10,939 PostProduc loads (D7).
5. Otherwise **No coordinates**: an end is not resolved to a place, or a place has no
   position.

`RfpHistoryService.run` applies that order after its searches with no callout (R73),
reading the chunk's stored routes in one query, and writes `RFP_Lane__c.Miles__c`,
`Miles_Source__c` and `Route_Hours__c` in user mode. `RFP_Tool_User` has read and edit on
the three fields; without the grant `Security.stripInaccessible` would silently drop them.
Resolving a lane end (`RfpLaneController.resolveLaneEnd`) clears the three fields: they
belonged to the old place pair, and the lane panel's route or the next Load history fills
them.

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
unless its miles come from History, which a route never replaces. While Load history or a
bulk action is running, the lane panel holds its route request (the map shows its spinner
and Refresh route waits) and sends it when the run ends. `laneRoute` decides on
the lane read again `FOR UPDATE` after its callouts, so History miles that a Load history
saved while the route was on its way stay; a lane that already holds the route's values is
not rewritten, and the panel gets the lane as stored. A store save that throws a
`DmlException` (two pricers storing the same new route at once) still shows the route,
which is stored on a later open. A result of
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
runs; a stored route costs none, and Load history costs none. Every image shown is one
Static Images request. A lane panel opening loads only the route image. A Lane Benchmark
search asks for a preview only when an end uses Radius (`LaneBenchmarkPlaceService.previewUrl`
returns none otherwise), so a search without a radius loads one image, the route, and a
radius search loads two: its radius preview, usually while the route is still being found,
and the route image above it. The Directions API allows 300 requests per minute.

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

## Carriers to ask and split-lane options (phase 8)

Two cards on Lane Benchmark and the RFP lane panel, for lanes where the first search finds
no carrier rate. **Carriers to ask** names carriers that know the lane, without amounts.
**Split-lane options** shows, only on a click, how the lane has been moved in legs by
different carriers, with leg costs, or estimates a split through a handoff point. Direct
results stay first. Design:
`docs/superpowers/specs/2026-09-14-phase-8-carriers-and-split-lanes-design.md`.

**Carriers to ask.** The screen decides "no rate" from the search it already has: no row
with a total other than 0 in the pricing currency (the RFP lane's currency; on Lane
Benchmark the currency filter, or any currency without one) (D2, R80). When that holds and
both ends have a place key, `c-carrier-leads` calls the cacheable
`CarrierLeadController.findCarrierLeads(requestJson, attempt)`. `CarrierLeadService.find`
keeps only the request's place keys, precisions, postal prefixes and mode, equipment and
hazmat filters (R101). Stage 1, same lane, 3 years: two grouped counts on
`rtms__CarrierQuote__c` by `rtms__Vendor__c`, loads quoted and loads moved
(`rtms__Accepted__c = true`), each capped at 50 carriers (R107), plus the carrier legs of
freight plans whose customer load is on the lane (at most 500 plans, read as plain rows
through `FreightPlanReader`); merged per carrier and ranked by loads moved, loads quoted,
last seen (R82). Stage 2, only when stage 1 is empty: the same reads over 365 days on the
state or province lane, with each end's stop account `ShippingCountry` matching the place's
country (Revenova reuses state codes across countries, R102), top 10 by loads moved then
last seen; skipped when a place has no `Province__c` or both ends used province keys (R95).
Quotes, plans and legs are read in system mode, as in `LaneSearchService`, because carrier
quotes inherit Private load sharing; one `WITH USER_MODE` read on `Account` decides each
link (`canOpen`). `CarrierLeadResult` has no amount field and no query in the path selects
one (R106). A query-row guard stops early and sets `truncated` ("The list may be
incomplete."): before each query, and before each grouped quote count after a `COUNT()` of
the quote rows that count would read, because `COUNT_DISTINCT` and `MAX` charge every row
they aggregate to the 50,000-row limit. Load history never runs it; the lane table shows a **no rate** tag read from
`Hist_Status__c` and `Hist_Median__c` (R93).

**Split-lane options.** `c-split-lane-options` calls the cacheable
`SplitLaneController.splitOptions(requestJson, currencyCode, attempt)` on a click (D1);
`currencyCode` is `CAD` or `USD`, anything else is refused. History: one parent-child query
on `rtms__FreightPlan__c` with a semi-join on customer junction rows on the lane over 365
days (R104), at most 1,000 plans; a shipment with a cancelled leg or an intercompany carrier
on a leg is left out (R87); shipments are grouped by their handoffs (the destination half of
each leg's `rtms__City_Lane__c` and the leg's last stop account name, R105); each leg
position shows its carriers with legs moved and the median of its priced
`rtms__Carrier_Quote_Total__c`, and the group's total is the median of each fully priced
shipment's own leg sum (R85). Estimates, only when history finds no group: the active
handoff points whose approximate distance origin → point → destination is at most 10 %
above the direct one (`TripMilesService.approxMiles`, no Mapbox call), at most 3; each
point reads two legs, each the most recent 500 moved loads on that leg lane over 365 days
with a positive CAD carrier total, cancelled and intercompany loads left out (R86). The
handoff cost is typed on the screen and added there. In the lane panel, **Use as cost**
puts an option's total in the price editor with cost source `Split`, a new
`RFP_Lane__c.Cost_Source__c` value, and the pricer saves with **Save price** through the
existing `saveLanePricing` (R98); it works while the card shows the lane's currency (R88).
The Excel export has a Cost source column after Currency (R99).

**Currency.** Revenova stores every leg cost in CAD. For USD, `ExchangeRates` reads the USD
`DatedConversionRate` periods from 400 days back in one query and multiplies each load's
CAD cost by the `ConversionRate` of the period holding the load's `CreatedDate` (USD
amount = CAD amount × rate; the latest period for later dates, the first for earlier
ones) before medians and sums (R109). The card notes the start date of the latest rate it
used. PostProduc holds weekly USD rates, the latest starting 2026-08-11 at 0.7239 USD per
CAD (the static `CurrencyType` rate is 0.7443). **Production must keep these weekly dated
USD rates current** for USD amounts to be right; whether it does is to be confirmed. With no
USD period at all the card says "No USD exchange rate is available." Statistics, results
and RFP medians keep their currency buckets; nothing else converts (D11).

**The two settings.** Both are public custom metadata types, read with test overrides
because custom metadata cannot be inserted in tests:

- `Intercompany_Carrier__mdt` (`Carrier_Account_Id__c` Text(18), `Note__c`): carrier
  accounts left out of both cards (D6, R89): the quote counts and estimate leg reads exclude
  them in SOQL, and freight-plan legs are dropped as the plan rows are read (a split shipment
  with such a leg is left out of history, R87). Records
  `Tpml_TP_Org` ("Tpml (Trans-Pro Logistics)-TP org") and `Lessard_Org` ("TRANS-PRO
  LOGISTIQUE - TPML- LESSARD ORG"). `IntercompanyCarriers` skips a value that is not a 15-
  or 18-character Account Id and writes a `WARN` debug line. The existing excluded-contact
  setting (`Pricing_Department_Setting__mdt`) still applies, to quotes only.
- `Handoff_Point__mdt` (`Place_Key__c` Text(120), `Active__c`): the handoff points
  estimates try (D8). Records `Laredo_TX_US`, `San_Diego_CA_US` and `Calexico_CA_US`, all
  active, whose keys are `Pricing_Place__c.Key__c` values. A key with no place, or a place
  with no coordinates, is ignored.

An admin edits them in Setup → Custom Metadata Types → Intercompany Carrier (or Handoff
Point) → Manage Records: **New** adds a carrier account (its 18-character Id from the
account URL) or a handoff point (a key exactly as in `Pricing_Place__c.Key__c`, for
example `laredo|tx|us`); clearing `Active__c` retires a handoff point without deleting it.
A change applies to the next card the server answers; a view the browser already cached can
show the old answer until it expires. The repo is the source of truth for the five records:
every full-manifest deploy overwrites them with the repo's values, so make the same change
in `force-app/main/default/customMetadata/` by pull request, or the next deploy undoes an
edited record (a record added only in Setup is left alone by deploys, but stays out of the
repo).

**Nothing is stored.** No new object and no stored result: both controllers are cacheable,
the cards have no Refresh control, and **Retry** after a failure passes a new `attempt` so
the call reaches the server (R91). The only data a pricer writes is a `Split` cost through
**Save price**. Copy pricing and the twin offer treat a Split cost like any other stored cost
(R100).

**Results warning.** The red warning in Lane Benchmark results and the RFP lane panel's
history results is built by `CarrierWarning`: " THE CARRIER IS BLACK-LISTED " when the
quote's vendor account (on a bid row, the bid's carrier account) has `Black_List__c`, then
" UNDER A CLAIM " when the Transportation Profile has `Outstanding_Claim__c`, trimmed.
`Carrier_Att__c`, whose blacklist half read a Transportation Profile flag that matched no
quote in a year, is no longer read (D5, R90). Blacklisted carriers stay visible in both
cards with a **Blacklisted** badge (R94).

**Queries.** Carriers to ask makes 7 queries for stage 1 (places, a `COUNT()` and a grouped
count for loads quoted, the same pair for loads moved, plans with legs, the `Account` read)
and 5 more when stage 2 runs; split history makes the places read and one plan query, plus
one rate query in USD; estimates add the handoff places and at most 6 leg reads. The
`COUNT()` before each grouped count came with the final review's query-row fix; the measured
counts are in the spec Outcome.

**Access.** `Lane_Benchmark_User` and `RFP_Tool_User` give class access to
`CarrierLeadController` and `SplitLaneController`; no object or field permission changed,
and the new picklist value needs none. Production is not deployed (owner decision, R108).

## Market test (phase 9)

A tab of its own: pick a lane, record what carriers quote for it now, and read
those rates beside what the lane has done over the last 90 days. No RFP and no
customer are involved.

| Piece                                                          | Purpose                                                                                                                                                              |
| -------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `tabs/Market_Test`, `flexipages/Market_Test`, `lwc/marketTest` | The page. Two `laneBenchmarkPlacePicker` ends, the history half from `LaneBenchmarkController.search` unchanged, the capture half through the existing `rfpBidForm`. |
| `classes/MarketTestController`                                 | The page's only Apex surface: `getRates`, `saveRate`, `updateRate`, `deleteRate`. Nothing is cacheable - the page mutates this list and re-reads it.                 |
| `classes/MarketTestService`                                    | `without sharing`, like `LaneSearchService`. Stamps the lane keys, scopes every read on the marker, and gates every write on ownership.                              |
| `objects/Benchmark_Rate__c/fields/Market_Test__c`              | The marker.                                                                                                                                                          |

**A market-test rate is a `Benchmark_Rate__c`** with `RFP_Project__c` and
`RFP_Lane__c` null and `Market_Test__c` true. It counts in the lane's median
everywhere the app shows one, exactly as an RFP bid does: no lane search reads
or filters the marker.

**Why a marker and not the absent lookups.** Both lookups are `SetNull`, so
deleting a customer account leaves its bids with no project and no lane -
byte-for-byte the shape of a market-test rate. A read scoped on that absence
would have listed a deleted customer's bids to everyone holding the permission
set. Only `MarketTestService` writes the marker, so an orphan can never carry
one. `MarketTestServiceTest` pins this: an orphan sharing the same lane is
never listed, never updatable and never deletable here.

**The lane keys are stamped by the service**, not by the trigger.
`BenchmarkRateService.applyLanes` copies them from an RFP lane, and a
market-test rate has none, so without this the rate would match no lane search
and never reach the median it exists to join.

**Access.** Everyone with either permission set reads every rate on a lane, the
same way the median already includes them; editing and deleting are restricted
to the record's owner. `Lane_Benchmark_User` gains create, edit and delete on
`Benchmark_Rate__c` (the owner's decision: open it to everyone, withdraw it if
abused). The object stays `Private` with no sharing rules, so that grant is
object-level only, and an RFP bid is refused by the write path outright.

**Not this.** The org also holds a legacy `Market_Test__c` custom object, 1,176
records, dormant since February 2023, whose quote counts point at the Revenova
quotes under the Market Test customer account. It is unrelated to this page, is
in no app's navigation, and is left untouched.

## Help center (phase 5)

Pricers get a **Help** tab (`Help_Center`, in the Lane Benchmark and Trans-Pro
apps) with the user guide in English and French, and a small "?" next to the
title of twelve areas in Lane Benchmark and the RFP Tool that opens a one-line
hint with a "Read more" link into the matching section.

**Editing the guide.** The source is `docs/help/en/<slug>.md` and
`docs/help/fr/<slug>.md` — one file per section, the same slugs in both
languages, a front-matter block with `title`, `order` and `hint` (the popover
text, at most 240 characters), then Markdown limited to `##`/`###` headings,
paragraphs, bold, italics, inline code, links, lists and tables. No images.
After editing run `npm run help:build`; it renders the files into the
`helpCenter` static resource, which is committed. `npm run help:check` (run by
CI) fails when the resource is stale or a rule is broken. Deploy the resource
with the normal full-manifest command; users see the change after a reload.

**Adding a hint.** Put `<c-help-hint topic="<slug>" label="Help: <area>">` in
the host component's markup (no JavaScript needed), beside a heading or label
rather than inside it, so the hint's assistive text does not join that
element's name. Then add the host and its topic to the `EXPECTED` map in
`lwc/helpContent/__tests__/placement.test.js`: that test pins one hint per
listed host and fails on a topic that is not in the guide.

**Language.** The tab opens in French when the user's Salesforce language is
French (`fr*`) and in English otherwise; the EN | FR toggle is remembered per browser
(`helpCenter.lang.v1`). Deep links: `/lightning/n/Help_Center?c__section=rfp-pricing&c__lang=fr`.

**Access.** Tab visibility comes with `Lane_Benchmark_User` and `RFP_Tool_User`.
No Apex is involved.

## Known issues worth fixing

- The excluded Contact Ids live in `Pricing_Department_Setting__mdt` (record `Default`, field `Excluded_Contact_Ids__c`) instead of being hardcoded, and `LaneSearchExclusions` reads them for every lane search. The repo is the source of truth for `Pricing_Department_Setting.Default`; every deploy overwrites the org value, so admins request changes by pull request.
- Every filter is a `LIKE '%x%'` on formula fields, which cannot use indexes; dedupe happens in Apex after the 500-row limit is applied.
- Trip miles (phase 7): the workbench table and the Excel export show a lane's route miles only after the next price save, history run or reload; the lane panel shows them at once.
- Trip miles: a lane whose two ends are the same place shows 0.0 miles (Approx, or a zero-mile route); the right label is for the owner to decide.
- Trip miles: every lane opening reads the lane again and, for a lane with no stored route, calls Mapbox, so clicking through new lanes spends Directions requests.
- Trip miles: after a Province / state or postal prefix (ZIP3) search, Lane Benchmark still shows the city-to-city truck route between the two picked places, beside a trip median that covers the wider match.
- Carriers to ask and split-lane options (phase 8): USD amounts on the split card are only as current as Salesforce's weekly USD dated exchange rates; whether production keeps them current is to be confirmed.
- Carriers to ask: stage 2 leaves out loads whose first or last stop account has a blank `ShippingCountry` (about 4 % of recent loads in PostProduc).
- Split-lane options: a handoff group is named from the leg's lane and its last stop account, so one yard recorded under two account names shows as two groups.
- Carriers to ask: stage 2's top 10 shows no "The list may be incomplete." note but is exact only while neither grouped count is cut at 50 carriers: a carrier outside the 50 with the most accepted-quote loads counts only its split legs as loads moved and can fall out of the top 10, and on a lane with fewer than 10 movers and more than 50 quoting carriers the rest of the top 10 comes from the 50 carriers with the most loads quoted.
- Carriers to ask: `CarrierLeadController` has 90 % test coverage (18 of 20 lines; its `QueryException` branch is untested), so any untested line added to it later can fail a scoped deploy's 75 % coverage gate.
- Carriers to ask and split-lane options: the caps and the query-row guard are tested with small fixtures only — the group cap with 51 carriers (`CarrierLeadServiceTest.stateLaneIgnoresTheGroupCap`), the 500-plan and 1,000-plan caps with exactly that many plans built in memory through `FreightPlanReader.rowsOverride`, and the guard, before a query and before each grouped quote count, through `CarrierLeadService.rowLimitOverride` (`CarrierSplitLimitsTest MarketTestServiceTest MarketTestControllerTest`); no test runs at production volume.
- Carriers to ask and split-lane options: the 500-plan and 1,000-plan reads have no ORDER BY, so a capped read takes an arbitrary subset of plans; a plan's `CreatedDate` is not the shipment date (R84), so ordering by it would not pick recent shipments either.
- Carriers to ask: a stage whose next grouped quote count would read more quote rows than the query-row guard leaves stops before that count and shows "The list may be incomplete." with the carriers counted so far; on the busiest province pair in PostProduc (ON to QC) stage 1 reads 13,626 of the 50,000 query rows, so a production-sized lane can reach it.
- Phase 8 tests run close to the 100-query limit: a Carrier record type `Account` costs 21 to 23 SOQL queries through the org's Account flows (6 to 8 when inserted blacklisted), so the fixtures insert carriers blacklisted where no assertion reads the flag, and each split shipment test holds one shipment.

## Continuous integration

`.github/workflows/ci.yml` runs on every pull request and on pushes to `main`, identically
in both repositories:

| Job    | What it does                                                                                                  | Fails on                                   |
| ------ | ------------------------------------------------------------------------------------------------------------- | ------------------------------------------ |
| `lwc`  | `npm ci`, ESLint, Prettier check, Jest with coverage                                                          | lint error, formatting drift, failing test |
| `apex` | validates the manifest against PostProduc and runs the project's test classes (see the workflow for the list) | compile error, test failure                |
| `pmd`  | PMD 7 Apex quickstart, priority 3 (all quickstart rules), text output in the job log                          | any quickstart violation                   |

CI never deploys. Deploys to PostProduc are run by a developer after merge (command
above).

Secret `SFDX_AUTH_URL_POSTPRODUC` is set in the TPLM repository only. The personal
mirror (`IulianEnescu78/PricingDepartment`) has no org secret, so its `apex` job detects
that and skips its Salesforce steps instead of failing; the `apex` job only validates for
real in the TPLM repository. Regenerate the secret after every PostProduc refresh:

```bash
set -o pipefail
sf org auth show-sfdx-auth-url -o sandbox --json 2>/dev/null \
  | python3 -c "import json,sys; u=json.load(sys.stdin)['result']['sfdxAuthUrl']; assert u.startswith('force://'); sys.stdout.write(u)" \
  | GH_TOKEN=$(gh auth token -u IulianEnescu) gh secret set SFDX_AUTH_URL_POSTPRODUC -R TPLM/PricingDepartment
```

Never echo or print the auth URL; pipe it directly from `sf org auth show-sfdx-auth-url` into
`gh secret set`. (`sf org display --verbose --json` no longer includes the real URL on current
CLI versions; it returns a `[REDACTED]` placeholder.)

### Branch protection

Enabled on `main` in both repositories: required status checks (strict, i.e. branches
must be up to date before merging), no force pushes, no deletions.
`IulianEnescu78/PricingDepartment` requires `["lwc", "pmd"]` (it has no org secret, so
`apex` cannot be a required context there); `TPLM/PricingDepartment` requires
`["lwc", "apex", "pmd"]`.

## Git remotes

| Remote   | URL                                                 | Account                                            |
| -------- | --------------------------------------------------- | -------------------------------------------------- |
| `origin` | https://github.com/IulianEnescu78/PricingDepartment | personal (primary)                                 |
| `tplm`   | https://github.com/TPLM/PricingDepartment           | Trans-Pro org, via the `IulianEnescu` GitHub login |

Always push `origin` first, then `tplm`. The default credential helper holds the personal
login, which cannot see the private TPLM repo, so push to `tplm` with the work token:

```bash
git push origin main
WT=$(gh auth token -u IulianEnescu) && git -c credential.helper= -c "credential.helper=!f() { echo username=IulianEnescu; echo password=$WT; }; f" push tplm main
```
