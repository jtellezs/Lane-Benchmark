# Pricing Department (Salesforce)

Source for the Lightning pages the Trans-Pro pricing team works in: **Lane Benchmark**,
which searches historical carrier quotes and RFP bids for a lane and shows per-currency
stats, margin and a suggested sell, and the **RFP Tool** workbench, which prices a whole
customer RFP from the same search. The single "Pricing Department" page they grew out of
was retired in phase 4 - see "Retired: Pricing Department page (phase 4)" below.

Retrieved on 2026-09-07 from the `postproduc` sandbox (sf alias `sandbox`).

## What is in here

| Layer            | Component                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         | Notes                                                                                                                                                                                                                                                                                                                                 |
| ---------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Data             | `objects/Pricing_Place__c/*`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      | Phase 1 place dictionary: normalized city/province/country key, `Aliases__c`/`Spellings__c`, `Source__c` (`Locations`/`Mapbox`), geolocation, `Location_Count__c`/`Load_Count_365d__c`                                                                                                                                                |
| Apex             | `classes/PlaceNormalizer`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         | Phase 1: normalizes raw `ShippingCity`/`ShippingState`/`ShippingCountry` into dictionary keys                                                                                                                                                                                                                                         |
| Apex (batch)     | `classes/PlaceBuilderBatch`, `PlaceWriteBatch`, `PlaceUsageBatch`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 | Phase 1: builds/refreshes `Pricing_Place__c` from shipping locations, then fills `Load_Count_365d__c`; never deletes, never overwrites `Aliases__c`/`Active__c`                                                                                                                                                                       |
| Apex             | `classes/LaneSearchService`, `LaneSearchQueryBuilder`, `LaneSearchFilters`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        | Phase 1: typed lane search over `rtms__CarrierQuote__c` (any precision, filters, per-currency stats, dedupe, truncation)                                                                                                                                                                                                              |
| Apex             | `classes/LaneSearchRequest`, `LaneSearchResult`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   | Phase 1: typed request/result DTOs shared by `LaneSearchService` and `LaneBenchmarkController`                                                                                                                                                                                                                                        |
| Apex             | `classes/LaneSearchExclusions`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    | Excluded Contact Ids for every lane search, read from `Pricing_Department_Setting__mdt.Default`; test hook for tests                                                                                                                                                                                                                  |
| Navigation       | `tabs/Lane_Benchmark`, `flexipages/Lane_Benchmark`, `applications/Lane_Benchmark`, `applications/TransPro` (tab added)                                                                                                                                                                                                                                                                                                                                                                                                                                                                            | Phase 2: the Lane Benchmark page's own tab/page/app, plus the tab appended to the existing `TransPro` app                                                                                                                                                                                                                             |
| UI               | `lwc/laneBenchmark`, `laneBenchmarkPlacePicker`, `laneBenchmarkFilters`, `laneBenchmarkStats`, `laneBenchmarkResults`, `laneBenchmarkMap`, `laneBenchmarkCsv`, `laneBenchmarkStorage`, `marginMath`                                                                                                                                                                                                                                                                                                                                                                                               | Phase 2: the nine Lane Benchmark bundles — container, place picker, filters, stats/margin, results table with CSV export, static map preview, and the CSV/storage/margin pure modules                                                                                                                                                 |
| Apex             | `classes/LaneBenchmarkController`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 | Aura/LWC entry points for the Lane Benchmark page: search, place autocomplete, filter options, geocode, map preview                                                                                                                                                                                                                   |
| Apex             | `classes/LaneBenchmarkPlaceService`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               | `Pricing_Place__c` reads/writes behind `LaneBenchmarkController`'s `geocode()`/`mapPreviewUrl()`, split out to keep the controller under the PMD CyclomaticComplexity threshold                                                                                                                                                       |
| Apex             | `classes/MapboxGeocoder`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          | Forward geocoding and static map URLs through the org's Mapbox account                                                                                                                                                                                                                                                                |
| Apex tests       | `LaneSearchExclusionsTest`, `PlaceNormalizerTest`, `PricingTestDataFactoryTest`, `PlaceBuilderBatchTest`, `LaneSearchServiceTest`, `MapboxGeocoderTest`, `LaneBenchmarkControllerTest`, `LaneBenchmarkPlaceServiceTest`, `RfpTestDataFactoryTest`, `BenchmarkRateServiceTest`, `BidSearchQueryBuilderTest`, `BidSearchServiceTest`, `RfpControllerTest`, `RfpSecurityTest`, `RfpBidAccessTest`, `RfpImportServiceTest`, `RfpLaneControllerTest`, `RfpHistoryServiceTest`, `RfpProjectControllerTest`, `RfpBidControllerTest`, `RfpPricingMathTest`, `RfpBulkServiceTest`, `RfpBulkControllerTest` | Behavior tests; `PricingTestDataFactory` builds the minimum valid Revenova graph the managed triggers require, so tests do not depend on org data                                                                                                                                                                                     |
| Data             | `objects/rtms__CarrierQuote__c/fields/*`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          | 24 custom fields on the Revenova TMS Carrier Quote object, almost all formulas                                                                                                                                                                                                                                                        |
| Data (2nd layer) | fields on `rtms__CarrierService__c`, `rtms__TransportationProfile__c`, `rtms__Load__c`, `Account`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 | Custom fields those formulas read through lookups                                                                                                                                                                                                                                                                                     |
| Security         | `permissionsets/Lane_Benchmark_User`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              | Grants access to the Lane Benchmark page: app/tab visibility, Apex class access (`LaneBenchmarkController`, `LaneBenchmarkPlaceService`, `LaneSearchService`, `MapboxGeocoder`), object read on `rtms__CarrierQuote__c`/`rtms__Load__c`/`Pricing_Place__c`, field read on every field the page shows. Assign this to the pricing team |
| Security (CSP)   | `cspTrustedSites/Mapbox_API`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      | `img-src` trusted site for `https://api.mapbox.com`, needed for the Lane Benchmark static map preview                                                                                                                                                                                                                                 |
| Data             | `objects/RFP_Project__c/*`, `objects/RFP_Lane__c/*`, `objects/Benchmark_Rate__c/*`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                | Phase 3a: the RFP data model — project, lane and carrier bid; see "RFP Tool (phase 3a)" below                                                                                                                                                                                                                                         |
| Apex             | `classes/RfpTestDataFactory`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      | Phase 3a: test builders for projects, lanes, bids and places, reusing `PricingTestDataFactory`                                                                                                                                                                                                                                        |
| Apex             | `classes/BenchmarkRateService`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    | Phase 3a: saves a bid in user mode and copies its lane keys from the lane's resolved places                                                                                                                                                                                                                                           |
| Apex             | `classes/BidSearchQueryBuilder`, `BidSearchService`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               | Phase 3a: builds the bid SOQL at the same precision `LaneSearchQueryBuilder` uses for Loads, and merges bid rows into `LaneSearchService`'s results                                                                                                                                                                                   |
| Apex             | `classes/RfpController`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           | Phase 3a: `projectsForAccount` for the customer Account component; phase 3b adds the workbench methods                                                                                                                                                                                                                                |
| UI               | `lwc/rfpProjectsForAccount`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       | Phase 3a: "RFP Projects (customer)", the Account record page component listing a customer's projects, files and bid counts                                                                                                                                                                                                            |
| Security         | `permissionsets/RFP_Tool_User`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    | Phase 3a: the pricing team's RFP access — create/read/edit on the three RFP objects, read on `Pricing_Place__c`/`Account`, the RFP and Lane Benchmark Apex classes                                                                                                                                                                    |
| Apex             | `classes/RfpImportService`, `RfpLaneController`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   | Phase 3b: mapped rows into `RFP_Lane__c` (city key then postal prefix); lane list, pricing whitelist, raw rows for export, manual end resolution                                                                                                                                                                                      |
| Apex             | `classes/RfpHistoryService`, `RfpHistoryController`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               | Phase 3b: per-lane carrier-quote history snapshots (CITY, falling back to the chosen radius, default 50 km, on a miss)                                                                                                                                                                                                                |
| Apex             | `classes/RfpProjectController`, `RfpBidController`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                | Phase 3b: projects, column mapping, file attach, customer/carrier typeahead; bids                                                                                                                                                                                                                                                     |
| Apex             | `classes/RfpUserError`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            | Phase 3b: shared `AuraHandledException` helper used by the four workbench controllers                                                                                                                                                                                                                                                 |
| UI               | `lwc/rfpHeaderGuess`, `rfpSheet`, `rfpSheetLoader`, `rfpWorkbook`, `rfpMath`, `rfpPricing`, `rfpBatch`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            | Phase 3b: pure modules — header guessing, workbook parsing and CSV codepage detection, the SheetJS script loader, export workbook building, bid/price math, chunked lane batching                                                                                                                                                     |
| UI               | `lwc/rfpTool`, `rfpProjectList`, `rfpUpload`, `rfpColumnMapper`, `rfpLaneTable`, `rfpLanePanel`, `rfpBidForm`, `rfpAccountPicker`, `rfpExport`                                                                                                                                                                                                                                                                                                                                                                                                                                                    | Phase 3b: the workbench container plus its project list, file upload, column mapper, lane table, lane detail panel, bid form, customer/carrier typeahead and Excel export                                                                                                                                                             |
| UI               | `lwc/helpCenter`, `helpHint`, `helpContent`; `staticresources/helpCenter`; `flexipages/Help_Center`, `tabs/Help_Center`                                                                                                                                                                                                                                                                                                                                                                                                                                                                           | Phase 5: the Help tab (bilingual user guide built from `docs/help`), the "?" hint popover, and the module that loads the content                                                                                                                                                                                                      |
| Navigation       | `tabs/RFP_Tool`, `flexipages/RFP_Tool`, `applications/TransPro` (tab added), `applications/Lane_Benchmark` (tab added)                                                                                                                                                                                                                                                                                                                                                                                                                                                                            | Phase 3b: the RFP Tool tab/page, added to both apps                                                                                                                                                                                                                                                                                   |
| Security         | `staticresources/sheetJs`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         | Phase 3b: SheetJS Community Edition 0.18.5 (Apache-2.0), vendored in-repo because the org's same-named static resource belongs to the EN6IA managed package                                                                                                                                                                           |

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

```bash
# Re-pull everything in the manifest
sf project retrieve start -x manifest/package.xml -o sandbox

# Deploy back (validate first)
sf project deploy validate -x manifest/package.xml -o sandbox
sf project deploy start    -x manifest/package.xml -o sandbox

# Run the tests
sf apex run test -n LaneSearchExclusionsTest -n PlaceNormalizerTest -n PricingTestDataFactoryTest -n PlaceBuilderBatchTest -n LaneSearchServiceTest -n MapboxGeocoderTest -n LaneBenchmarkControllerTest -n LaneBenchmarkPlaceServiceTest -n RfpTestDataFactoryTest -n BenchmarkRateServiceTest -n BidSearchQueryBuilderTest -n BidSearchServiceTest -n RfpControllerTest -n RfpSecurityTest -n RfpBidAccessTest -n RfpImportServiceTest -n RfpLaneControllerTest -n RfpHistoryServiceTest -n RfpProjectControllerTest -n RfpBidControllerTest -n RfpPricingMathTest -n RfpBulkServiceTest -n RfpBulkControllerTest -o sandbox -r human -w 15
```

```bash
# Deploy to PostProduc. --post-destructive-changes is a two-step, not a re-runnable one:
# add the members to manifest/destructiveChangesPost.xml, deploy once, then empty the
# manifest again. A second deploy naming already-deleted components fails the whole run.
sf project deploy start -x manifest/package.xml --post-destructive-changes manifest/destructiveChangesPost.xml -o sandbox -l RunSpecifiedTests -t LaneSearchExclusionsTest PlaceNormalizerTest PricingTestDataFactoryTest PlaceBuilderBatchTest LaneSearchServiceTest MapboxGeocoderTest LaneBenchmarkControllerTest LaneBenchmarkPlaceServiceTest RfpTestDataFactoryTest BenchmarkRateServiceTest BidSearchQueryBuilderTest BidSearchServiceTest RfpControllerTest RfpSecurityTest RfpBidAccessTest RfpImportServiceTest RfpLaneControllerTest RfpHistoryServiceTest RfpProjectControllerTest RfpBidControllerTest RfpPricingMathTest RfpBulkServiceTest RfpBulkControllerTest
```

Org aliases: `sandbox` = PostProduc, `vscodeOrg` = production.

User-mode Apex (`RfpController`, `BenchmarkRateService`) needs its permission
set (`RFP_Tool_User`) already assigned to the test-running user before a
`RunSpecifiedTests` deploy — `WITH USER_MODE` reports a field the running user
cannot read as "No such column". When a deploy introduces or changes that
permission set in the same deploy as new user-mode code, deploy the
permission set on its own first with `-l NoTestRun`, assign it, then run the
real test-running deploy.

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
sf project deploy start -o vscodeOrg --manifest manifest/package.xml --post-destructive-changes manifest/destructiveChanges-phase4.xml -l RunSpecifiedTests -t LaneSearchExclusionsTest PlaceNormalizerTest PricingTestDataFactoryTest PlaceBuilderBatchTest LaneSearchServiceTest MapboxGeocoderTest LaneBenchmarkControllerTest LaneBenchmarkPlaceServiceTest RfpTestDataFactoryTest BenchmarkRateServiceTest BidSearchQueryBuilderTest BidSearchServiceTest RfpControllerTest RfpSecurityTest RfpImportServiceTest RfpLaneControllerTest RfpHistoryServiceTest RfpProjectControllerTest RfpBidControllerTest RfpPricingMathTest RfpBulkServiceTest RfpBulkControllerTest -w 30
```

## RFP Tool (phase 3a)

Foundation only: the data model, the bid service, bids as a second source in
Lane Benchmark, and a customer Account component. The workbench (upload,
mapping, history, bid form, export, the `RFP_Tool` tab/page) is phase 3b — see
the spec's Outcome for what is still open.

| Object              | Purpose                                                                                                                                 | Key fields                                                                                                                                                                                                               |
| ------------------- | --------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `RFP_Project__c`    | One customer RFP: the uploaded lane file, its lanes, bids and prices                                                                    | `Customer__c` (Account lookup), `Status__c`, `Due_Date__c`, `Default_Margin__c`, roll-ups `Lane_Count__c` / `Costed_Count__c` / `Sold_Count__c`                                                                          |
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
stamped too; `save()` itself now only validates `Rate__c` and does the
USER_MODE insert/update/reload, since `RFP_Tool_User` marks the lane-key and
geolocation fields not editable (see Permission sets below) and a user-mode
DML can no longer set them. The trigger also defaults `Valid_From__c` /
`Expires_On__c` to today / today+30 for every bid that doesn't already have
them, on top of the same defaults now carried on the field metadata itself
(`<defaultValue>TODAY()</defaultValue>` / `TODAY() + 30`, which only prefill
the standard "New" page, not an Apex-created record — hence the trigger).

**Permission sets.**

- `RFP_Tool_User` — the pricing team's access: create/read/edit on the three
  RFP objects, read on `Pricing_Place__c` and `Account`, Apex class access
  to `RfpController`, `RfpImportService`, `RfpLaneController`,
  `BenchmarkRateService`, `LaneBenchmarkController`,
  `LaneBenchmarkPlaceService`, `LaneSearchService`, `MapboxGeocoder`, and the
  `RFP_Tool` custom permission (gates `rfpProjectsForAccount`, below).
  `City_Lane__c` / `State_Lane__c` / `Zip3_Lane__c` /
  `Origin_Geolocation__c` / `Destination_Geolocation__c` on `Benchmark_Rate__c`
  are readable but not editable: they are service-maintained by
  `BenchmarkRateTrigger`, never user-entered.
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

**Bids.** `Benchmark_Rate__c` is Private. The workbench never queries it in user mode:
`RfpBidAccess` is the one class that reads and writes bids, after proving in user mode
that the running user can read the lane, in system mode restricted to those lanes and
through `Security.stripInaccessible`. Rule: a lane you can see grants its bids, whoever
recorded them. Lane Benchmark (`LaneSearchService`, `BidSearchService`) keeps reading
every bid in system mode and shows carrier, rate and expiry only, never the customer.

**Admin task (not code).** Pricers need at least Read on the customer accounts they
price for: through the role hierarchy or an Account sharing rule to the pricing group.
Account is Private in this org, so without one of those a pricer sees no RFP. In
PostProduc the admin user holds `RFP_Tool_User` and sees everything; the restriction is
proven by `RfpSecurityTest` (three users) and `RfpBidAccessTest`.

**Production.** None of these objects exist there yet; the go-live deploy creates them in
their final shape. A sandbox that already holds RFP data converts in place as long as
every project has a customer (the New project form requires one).

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
