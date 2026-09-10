# Phase 2: Lane Benchmark UI

Status: design approved in conversation 2026-09-09 (approach B), spec under user
review. Parent: [roadmap](2026-09-07-pricing-department-roadmap.md). Builds on
[phase 1](2026-09-09-phase-1-search-foundation-design.md).

## Purpose

Give pricing a new page, **Lane Benchmark**, on top of phase 1's
`LaneSearchService`: pick origin and destination from the place dictionary or
from Mapbox when the dictionary has no match, choose precision and lookback,
filter by currency, mode and equipment, and see comparable carrier quotes with
per-currency statistics and a suggested sell price at a chosen margin. The
old Pricing Department tab stays untouched until pricing confirms the switch.

Decisions taken in conversation: placement is both a tab in the TransPro app
and a dedicated Lightning app; margin and suggested sell are included now
(former phase 4); external geocoding uses the company's existing Mapbox key
(former phase 5); results include carrier detail on click, CSV export and
remembered filters; no links to Load or Quote records.

## Scope

In:

1. Metadata: FlexiPage `Lane_Benchmark` (App Page), CustomTab
   `Lane_Benchmark`, CustomApplication `Lane_Benchmark`, the tab added to the
   `TransPro` app, permission set `Lane_Benchmark_User`.
2. Apex `LaneBenchmarkController` (search, place autocomplete, filter options,
   Mapbox geocoding) and `MapboxGeocoder` (callout through a Named Credential).
3. `Pricing_Place__c` gains `Source__c` (picklist: `Locations`, `Mapbox`) so
   geocoded places join the dictionary and are visibly distinct.
4. LWC: `laneBenchmark` (container), `laneBenchmarkPlacePicker`,
   `laneBenchmarkFilters`, `laneBenchmarkStats`, `laneBenchmarkResults`,
   `laneBenchmarkMap` (static preview), pure modules `laneBenchmarkCsv`,
   `marginMath`, `laneBenchmarkStorage`.
5. Tests: Jest per component and module; Apex tests for the controller and
   the geocoder (HTTP mock); CI list extended.
6. `LaneSearchResult.Row` gains the carrier-detail fields the popup needs.

Out: retiring the old tab (separate change after pricing signs off), saving
named searches, links to records, the RFP tool (now phase 3), any change to
the search semantics of phase 1.

## Navigation and access

- `Lane_Benchmark` App Page (single region, `laneBenchmark`), `Lane_Benchmark`
  tab (label "Lane Benchmark", motif `Custom53: Compass`), `Lane_Benchmark`
  Lightning app (Standard navigation, tabs: `Lane_Benchmark`), and
  `Lane_Benchmark` appended to the `TransPro` app's `<tabs>`. Deploying the
  TransPro app metadata overwrites it: retrieve it fresh from PostProduc in
  the task that edits it, add the one tab, deploy, and keep the retrieved
  file in the repo from then on.
- Permission set `Lane_Benchmark_User`: tab visibility, `Lane_Benchmark` app
  visibility, Apex access to `LaneBenchmarkController`, `LaneSearchService`,
  `MapboxGeocoder`, object read on `rtms__CarrierQuote__c`, `rtms__Load__c`,
  `Pricing_Place__c` (edit on `Aliases__c`/`Active__c` stays in
  `Pricing_Department_User`), field read on every field the page shows, and
  nothing else. It is
  assigned by the user to the pricing team after deploy; `Pricing_Department_User`
  is unchanged.

## Controller

`LaneBenchmarkController`, `without sharing` with the standard comment
("pricing benchmarks every team's quotes; access is gated by the Lane
Benchmark permission sets"). All methods `@AuraEnabled(cacheable=true)`
except `geocode`, which writes the cache and is therefore not cacheable.

| Method                                          | Input                       | Output                                                                                                            | Notes                                                                                                                                                                                                                                                                                                                                                                                                                                                  |
| ----------------------------------------------- | --------------------------- | ----------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `search(String requestJson)`                    | JSON of `LaneSearchRequest` | `LaneSearchResult`                                                                                                | `JSON.deserialize` keeps enums; `LaneSearchRequest.validate()` applies defaults to omitted fields. `LaneSearchException` and `QueryException` are rethrown as `AuraHandledException` with a user-readable message (`setMessage`).                                                                                                                                                                                                                      |
| `searchPlaces(String term, Integer limitCount)` | free text, 1-10             | `List<PlaceOption>`                                                                                               | Normalizes `term` with `PlaceNormalizer.normalizeCity`; matches active places where `Key__c LIKE :norm + '%'` OR `Aliases__c LIKE '%' + term + '%'` (escaped); `ORDER BY Load_Count_365d__c DESC NULLS LAST, Name`; `limitCount` capped at 10. `PlaceOption { key, label, province, country, loadCount, source, lat, lng }`, label `"Montréal, QC, CA"`. Terms shorter than 2 characters return an empty list.                                         |
| `getFilterOptions()`                            | none                        | `FilterOptions { modes: List<String>, equipmentByCategory: Map<String, List<String>>, currencies: List<String> }` | Enabled `rtms__Mode__c` by `rtms__Order__c`; enabled `rtms__EquipmentType__c` grouped by `rtms__Category__c` (null category → "Other"); currencies fixed `CAD`, `USD`.                                                                                                                                                                                                                                                                                 |
| `geocode(String query, String countryHint)`     | free text, optional ISO-2   | `List<PlaceOption>`                                                                                               | Calls `MapboxGeocoder.forward(query, countryHint)` (up to 5 results, `types=place,locality,postcode`, `country=ca,us,mx`), converts each to a `Pricing_Place__c` with `Source__c = 'Mapbox'`, upserts by `Key__c` **only if the key does not already exist** (never downgrades a Locations place), and returns them as `PlaceOption`s. Called only when the user explicitly asks ("Search on the map" action in the picker), never on every keystroke. |

`LaneBenchmarkPlaceService.upsertFromGeocode()` (which backs `geocode()`'s
place-matching) only ever inserts new places; the name is a misnomer kept
as-is for now since it never updates an existing record either way.

`LaneSearchResult.Row` gains a nested `carrier` (`CarrierDetail`) with
`contactEmail`, `contactPhone`, `risk`, `loadCount`, `attention` (from
`Contact_Email__c`, `Contact_Phone__c`, `Carrier_Risk__c`, `Nb_of_loads__c`,
`Carrier_Att__c`, already selected by phase 0's controller;
`LaneSearchQueryBuilder.SELECT_CLAUSE` adds them) — grouped off `Row` itself
to keep `Row` under PMD's `TooManyFields` threshold. This is a phase 1 class
edit, covered by an added assertion in `LaneSearchServiceTest`.

## Mapbox integration

- **What Mapbox does:** provide coordinates and a canonical name for a place
  the dictionary does not know (forward geocoding), and render a small static
  map of the origin and destination circles (Static Images API). What it does
  not do: any distance filtering; that stays in SOQL over Revenova's geocoded
  stops.
- **Credentials (decided 2026-09-09 after inspecting the org):** the company
  already stores a Mapbox **public** token (`pk.`) in the org-default record
  of the hierarchy custom setting `TPRO_KPI__c`, field `Mapbox_Api_Key__c`,
  and already has an active Remote Site Setting `MapBox` for
  `https://api.mapbox.com`; `KPI_ReportController` uses both today. Phase 2
  reuses them: `MapboxGeocoder` reads
  `TPRO_KPI__c.getOrgDefaults().Mapbox_Api_Key__c` at call time and throws
  `MapboxException('Mapbox token is not configured')` when blank; no Named
  Credential is introduced, no token enters git. Because the token is a
  public one, the static map preview may use the same token in the image
  URL, which is Mapbox's intended model for `pk.` tokens; the user should
  add URL restrictions for the Salesforce domains
  (`*.my.salesforce.com`, `*.lightning.force.com`, `*.sandbox.my.salesforce.com`)
  on the token in the Mapbox account, and the README says so. The
  `Lane_Benchmark_User` permission set needs no credential access; it needs
  read on the `TPRO_KPI__c` setting only if a future change moves the read
  out of system mode (Apex reads custom settings regardless of FLS).
- **`MapboxGeocoder`:** `public with sharing class` with
  `static List<GeoResult> forward(String query, String countryHint)`
  (`GeoResult { name, city, province, country, lat, lng, postalPrefix }`,
  derived from the feature's `context` array: `region.short_code` gives
  `CA-QC`/`US-TX`/`MX-NLE`, mapped to the province codes phase 1 stores by a
  small table for MX ISO codes → Revenova codes, e.g. `NLE→NL`, `MEX→ME`,
  `PUE→PB`; keep the ISO code when unmapped), a 10-second timeout, one retry
  on 5xx, and a `MapboxException` on 4xx or malformed JSON. Requests are
  limited to 5 results and `language=en`. Rate: one call per explicit user
  action; the controller rejects queries under 3 characters.
- **Static map preview:** `laneBenchmarkMap` renders an `<img>` from the
  Static Images API with two circle overlays (GeoJSON `overlay` parameter)
  centred on the chosen origin and destination with their radii, 600×300,
  only when at least one end uses RADIUS precision. This needs the token in
  the image URL, so the controller builds it (`mapPreviewUrl(...)`) with the
  same public token from the custom setting; the component renders nothing
  when the token is blank. A CSP Trusted Site for `https://api.mapbox.com`
  (img-src) is added.
- **Caching:** every geocoded result is stored as a `Pricing_Place__c` with
  `Source__c = 'Mapbox'`, `Location_Count__c = 0`, `Load_Count_365d__c = 0`,
  `Active__c = true`; it appears in later autocompletes for everyone, ranked
  after dictionary places. `PlaceBuilderBatch` never deletes and, when a
  Mapbox place's key later appears among locations, the upsert sets
  `Source__c = 'Locations'` and real counts.

## Components

- **`laneBenchmark`** (container, `lightning__AppPage` and `lightning__HomePage`):
  owns one `request` object mirroring `LaneSearchRequest` (plain JS object;
  enums as strings), the last `result`, `isSearching`, `elapsedSeconds`
  (ticks while searching), `error`. On connect: loads filter options, restores
  saved filters via `laneBenchmarkStorage`, and runs a search only if a
  saved request exists. Before a RADIUS search with `lookbackDays > 365` it
  shows an inline notice with the measured expectation ("radius searches over
  a year can take 10-20 seconds") and a Continue button. Layout: filters
  card left (30%), stats card + map + results right (70%); collapses to one
  column under 1024 px.
- **`laneBenchmarkPlacePicker`** (used twice; `@api label`, `@api value`
  (key), `@api precision`, `@api radius`, `@api unit`): a `lightning-input`
  with debounced (250 ms) typeahead calling `searchPlaces`, a dropdown of up
  to 10 options showing `label · N loads` and a `Mapbox` pill for geocoded
  places, keyboard navigation (up/down/enter/escape), a footer action
  "Not found? Search on the map" that calls `geocode(term)` and shows its
  results in the same dropdown; a precision `lightning-combobox`
  (Exact city / Province or state / Postal prefix / Radius) and, when Radius,
  a number input plus mi/km toggle. Emits `placechange
{key, label, precision, radius, unit}`.
- **`laneBenchmarkFilters`**: lookback days (`lightning-input type=number`,
  min 1, default 90), currency (All/CAD/USD), modes (dual-listbox or checkbox
  group from options), equipment categories (checkbox group) and equipment
  types (dual-listbox filtered by the chosen categories), hazmat, market test,
  accepted/declined radio, Apply and Reset, and a "Clear saved filters" link.
  Emits `filterschange` with the partial request and `apply`/`reset`.
- **`laneBenchmarkStats`**: one card per currency present in
  `statsByCurrency`: count (and non-zero count), min, median, average, max;
  margin input (default 15, buttons 15% and 20%, free entry 0-100) shared
  across currencies; suggested sell shown for median and average:
  `cost × (1 + margin/100)`, rounded to 2 decimals via `marginMath`. Shows
  "n rows removed as duplicates" and the truncation notice when set.
- **`laneBenchmarkResults`**: `lightning-datatable`-free plain table (the
  existing page's expandable rows and mode colouring are kept) newest first:
  #, origin, destination, carrier (clickable → popup), equipment, mode,
  currency, carrier total, quote date, load status, hazmat, accepted. Expand
  row shows ops comments and contact. Carrier popup: contact, email, phone,
  risk, loads, attention flags (all from the Row). "Export CSV" downloads the
  visible rows with the same columns through `laneBenchmarkCsv` (RFC 4180
  quoting, UTF-8 BOM so Excel opens accents correctly), file name
  `lane-benchmark-<origin>-<destination>-<yyyymmdd>.csv`.
- **`laneBenchmarkMap`**: `@api previewUrl`; renders the image or nothing.
- **Pure modules:** `laneBenchmarkCsv.toCsv(rows, columns)`,
  `marginMath.suggestedSell(cost, marginPct)` and `parseMargin(text)`,
  `laneBenchmarkStorage.load()/save(request)/clear()` on `localStorage` key
  `laneBenchmark.request.v1` (try/catch everything; absence is normal).

## Errors and states

Empty state before the first search explains the four precisions in one
sentence each. Searching state shows a spinner with elapsed seconds. Errors
from the controller appear in an inline `slds-notify` box with the message;
Mapbox errors say "Map search is unavailable right now" and keep the
dictionary results. Zero rows says so, and if any end was RADIUS suggests
widening the radius or the lookback.

## Testing

- Jest: picker (debounce, selection event, keyboard, map fallback action),
  filters (emits the exact request, reset restores defaults, clear-saved
  calls storage), stats (per-currency cards, margin buttons and free entry,
  suggested sell math via `marginMath`), results (row count, expand, popup
  open/close, CSV content via `laneBenchmarkCsv` with a quoted comma and an
  accent), container (restores saved request and searches, warning gate for
  long radius searches, error box), storage module (round trip, corrupt
  value ignored), map (renders only with a url).
- Apex: `LaneBenchmarkControllerTest` (search JSON round trip with defaults,
  error translation to `AuraHandledException`, `searchPlaces` normalization
  and alias match and ordering, `getFilterOptions` shape, `geocode` with a
  mocked `MapboxGeocoder` result inserting a Mapbox place and not downgrading
  an existing Locations place); `MapboxGeocoderTest` with `HttpCalloutMock`
  (happy path, MX region mapping, 5xx retry, 4xx exception, malformed JSON).
- CI: add both test classes to the workflow and README.

## Definition of done

1. Tab, page, app and permission set deployed to PostProduc through CI; the
   TransPro app shows the tab; the user assigns `Lane_Benchmark_User` to
   pricing.
2. The existing token in `TPRO_KPI__c.Mapbox_Api_Key__c` works from the page:
   a geocode of "Saguenay, QC" creates a Mapbox place and a search runs from
   it; the user has added URL restrictions on the token in Mapbox.
3. A pricing user completes a Montreal→Toronto search at each precision, a
   USD lane, and a CSV export; margins at 15% and 20% show suggested sell.
4. All Jest and Apex tests pass in CI; PMD clean.
5. README documents the Mapbox reuse (custom setting, remote site, token restrictions), the storage key,
   and the retirement plan for the old tab; roadmap updated.

## Outcome (2026-09-10)

Deploys to PostProduc (`sandbox`), in order:

- Backend (Tasks 1-3, `phase-2/backend`, merged as PR #17): `0AfbZ00000CoFY1SAN`.
- Components, check-only (Tasks 4-9, `phase-2/components`, merged as PR #18): `0AfbZ00000CoHI6SAN` (55/55 Apex tests).
- Task 10 (page, tab, app, TransPro tab, permission set, CSP site): `0AfbZ00000CoN0vSAF` (Succeeded, 55/55 Apex tests across the seven required classes: `PricingDepartmentControllerTest`, `PlaceNormalizerTest`, `PricingTestDataFactoryTest`, `PlaceBuilderBatchTest`, `LaneSearchServiceTest`, `MapboxGeocoderTest`, `LaneBenchmarkControllerTest`).

Jest: 62 tests passing across the picker, filters, stats, results, map,
container and the three pure modules (54 before the final-review fix wave;
+7 for keyboard navigation, the stale-response guard, the map-search guard,
the summary wording and the long-radius confirmation reset; +1 in round 2
for the pick-then-resolve guard).

### Manual checks

Done 2026-09-10 in PostProduc (`sandbox`), as the user who deployed, with
`Lane_Benchmark_User` assigned. Loads in PostProduc stop at the sandbox
refresh, so row counts are lower than production would give.

- Montreal -> Toronto, both ends Exact city, 90 days: 1 row in 0.9 s; the
  CAD stats card shows min/median/average/max and Sell (median) 252.89 at the
  default 15 % margin.
- Same lane with destination Radius 100 km: 45 rows in 0.4 s, "3 duplicates
  removed"; the Mapbox static map appears with the 100 km circle around
  Toronto; results span Burlington, Mississauga, Etobicoke, Hamilton and
  Guelph.
- 20 % button: Sell (median) moves from 1,610.00 to 1,680.00 (median 1,400).
- Typeahead: "Montreal" lists Montréal, QC, CA (2720 loads) first, then the
  spelling variants and the "Not found? Search on the map" button; "Saguenay"
  resolves from the dictionary (9 loads).
- Search on the map: "Kuujjuaq" (not in the dictionary) returns
  "Kuujjuaq, QC, CA" with the Mapbox badge; picking it and applying gives the
  empty state ("No quotes match this lane and these filters yet ...") with
  the map still showing the Toronto circle. No console errors.
- Navigation: the Trans-Pro app shows "Lane Benchmark" as a regular tab (last
  in the bar); the Lane Benchmark app opens from its own URL with the single
  tab. The Revenova "Transportation" app does not list it, as intended.
- Not exercised in the browser: CSV export (the download cannot be triggered
  from the automated session). The file content is covered by the
  `laneBenchmarkCsv` Jest tests (BOM, RFC 4180 quoting, formula-injection
  guard); the user should open one export in Excel/Numbers and confirm
  accents survive.
- Cosmetic, left for the final review: the results box says "Run a search to
  see quotes." after a search that returned zero rows; the counter reads
  "1 rows"; the Radius field starts empty when Radius is selected.

### Adaptations from the plan's verbatim code

- `Pricing_Place__c.Aliases__c` became a plain `Text(255)`, comma-separated
  field rather than a long text area, so it can appear in a SOQL `LIKE`
  filter (`searchPlaces`'s alias match) — a long text area field cannot be
  filtered in SOQL.
- `LaneSearchRequest.validate()` applies `applyDefaults()` first, because
  `JSON.deserialize` does not run field initializers: a field the UI leaves
  out of the JSON request arrives `null`, not at its declared default, so
  defaults have to be filled in before the rest of validation runs.
- `LaneBenchmarkPlaceService` was split out of `LaneBenchmarkController` to
  keep the controller's PMD cyclomatic-complexity total under the 40
  threshold (extracting private helpers within the controller alone does not
  reduce a class-wide total; moving the branches to another class does).
- The Mapbox token is read from the org-default record of the hierarchy
  custom setting `TPRO_KPI__c`, field `Mapbox_Api_Key__c` (a public `pk.`
  token, already in use by `KPI_ReportController`) — not a Named Credential.
  See "Mapbox integration" above.
- The permission set grants `viewAllRecords` on `Pricing_Place__c` (public
  reference data; the controller is `without sharing` so it changes nothing).
- The tab motif is `Custom80: Motorcycle` (known to deploy) rather than the
  planned `Custom53: Compass`.
- Final-review fixes: callout errors are mapped to `MapboxException` without
  the URL; the country hint is validated before it reaches the Mapbox
  request; keyboard navigation was added to the picker; concurrent geocode
  inserts are tolerated; the `MapBox` Remote Site Setting is now in the repo.
  Keyboard navigation verified in PostProduc; `lightning-input` forwards
  `role`, `aria-expanded`, `aria-autocomplete` and `aria-controls` to its
  native input, but not `aria-activedescendant`, so the highlighted option is
  not announced to screen readers — deferred to phase 4 (needs a native
  input).

### Deferred to phase 4

- The Radius field's default value.
- The `QueryException` raw message surfaced by `search()`.
- `aria-activedescendant` announcement for the picker's highlighted option
  (see the final-review fixes bullet above — needs a native `<input>`).
- A TransPro app snapshot in the manifest.
