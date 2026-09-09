# Phase 1: Search Foundation

Status: design approved in conversation 2026-09-09, spec under user review. Parent: [roadmap](2026-09-07-pricing-department-roadmap.md). Follows [phase 0](2026-09-07-phase-0-engineering-hygiene-design.md).

## Purpose

Give the Pricing Department page a real lane search: origin and destination
at a chosen precision (radius, exact city, province/state, ZIP3), any
lookback in days, currency, mode and equipment, returning comparable carrier
quotes with statistics per currency. Phase 1 builds and tests the service
and the place dictionary. The current page keeps working unchanged; phase 2
puts a new UI on top.

## What changed since the roadmap was written

Measured in PostProduc on 2026-09-09:

- Revenova already maintains normalized lane keys on every Load:
  `rtms__City_Lane__c` ("Calgary, AB:Oshawa, ON"), `rtms__State_Lane__c`
  ("AB:ON"), `rtms__Zip3_Lane__c` ("T4A:L1J"), `rtms__Postal_Code_Lane__c`.
  Populated on 51,392 of 55,432 loads created in the last 365 days (93 %).
- SOQL `DISTANCE()` works across relationships in one query, from Carrier
  Quote through Load and Stop to the location Account's `ShippingAddress`;
  14,999 of 15,043 location accounts used in the last year are geocoded and
  14,973 have a postal code.
- Timings (LIMIT 2000): radius 100 mi at both ends over 90 days 2.3 s; the
  same over 365 days 13.3 s; radius plus mode plus equipment category over
  365 days 5.3 s; exact city lane 0.7 s; province lane or ZIP3 lane about
  1.2 s.
- 50,777 quotes in the last year are CAD and 15,067 are USD.
  `CAD_Quote_Total__c` is 0 for USD quotes, which is why today's statistics
  skip zeros. Statistics must be computed per currency.
- Revenova's lane keys still carry accents: "Montréal, QC" and
  "Montreal, QC" both occur. Normalization is still needed, but only on the
  city name.

Consequence: the "lane fields on Load, record-triggered flow, 24-month
backfill" work is dropped. Nothing is denormalized and nothing needs a
backfill.

## Scope

In:

1. `Pricing_Place__c` custom object and the batch that builds it from
   location accounts.
2. `PlaceNormalizer` Apex: canonical key for a city, province, country.
3. `LaneSearchService` Apex with typed request and result classes, tests.
4. Factory extensions needed by the tests (USD quotes, distinct locations,
   modes, equipment categories).
5. A Salesforce support request for custom indexes on the lane-key fields,
   filed by the user early in the phase.

Out: any UI change, any change to the existing `PricingDepartmentController`
beyond what tests need, external geocoding, any deploy to production.

## Place dictionary

Object `Pricing_Place__c` (one record per city/province/country):

| Field                | Type                           | Notes                                                                                   |
| -------------------- | ------------------------------ | --------------------------------------------------------------------------------------- |
| `Name`               | Text(80)                       | Display, e.g. "Montréal, QC, CA" (most common spelling among locations)                 |
| `Key__c`             | Text(120), external Id, unique | Normalized: `montreal                                                                   | qc  | ca` |
| `City__c`            | Text(80)                       | Display spelling                                                                        |
| `Province__c`        | Text(3)                        | Abbreviation: QC, ON, TX                                                                |
| `Country__c`         | Text(2)                        | ISO-2: CA, US, MX                                                                       |
| `Geolocation__c`     | Geolocation(6)                 | Average of the locations' shipping coordinates                                          |
| `Location_Count__c`  | Number                         | Location accounts under this key                                                        |
| `Load_Count_365d__c` | Number                         | Loads in the last 365 days with a first or last stop here                               |
| `Aliases__c`         | LongTextArea                   | Curated, one alias per line, e.g. "Mtl", "Montreal-Nord"; matched by the phase 2 picker |
| `Active__c`          | Checkbox, default true         | Pricing can hide a bad place without deleting it                                        |

`PlaceBuilderBatch` (Batchable, Database.Stateful): iterates Accounts with a
shipping city and shipping latitude that are referenced by any
`rtms__Stop__c`, groups by normalized key, computes the averaged
coordinates and counts, and upserts by `Key__c`. Re-running it is safe; it
never deletes, and it never overwrites `Aliases__c` or `Active__c`. Scheduled
weekly once phase 2 ships; run once manually in phase 1.

`PlaceNormalizer`:

- `key(city, province, country)` → lowercase, accents stripped (NFD then
  remove combining marks), punctuation removed, whitespace collapsed,
  province mapped to its abbreviation through a fixed map of Canadian
  provinces and US states (both directions: "Quebec"→"QC", "QC"→"QC"),
  country mapped to ISO-2 ("Canada"→"CA", "United States"→"US",
  "USA"→"US", "Mexico"→"MX"). Unknown province or country is kept as typed,
  lowercased.
- `cityLaneVariants(place)` → the set of strings Revenova may have written
  in `rtms__City_Lane__c` for this place: the display spelling and every
  known spelling among its locations, accents both present and stripped.
  Used by the CITY precision so "Montreal" finds "Montréal".

## Search service

`LaneSearchService` is `without sharing` for the same reason as the
controller (pricing benchmarks every team's quotes); the comment says so.

`LaneSearchRequest` (Apex class, all fields optional unless noted):

| Field                                     | Type                                | Meaning                                                            |
| ----------------------------------------- | ----------------------------------- | ------------------------------------------------------------------ |
| `originKey`, `destinationKey`             | String                              | `Pricing_Place__c.Key__c`; blank means no constraint on that end   |
| `originPrecision`, `destinationPrecision` | Enum `RADIUS, CITY, PROVINCE, ZIP3` | Default CITY                                                       |
| `originRadius`, `destinationRadius`       | Decimal                             | Required when precision is RADIUS                                  |
| `radiusUnit`                              | Enum `MI, KM`                       | Default MI                                                         |
| `lookbackDays`                            | Integer                             | **Default 90. Any positive integer is accepted; there is no cap.** |
| `currency`                                | String                              | `CAD`, `USD`, or blank for both                                    |
| `modes`                                   | List<String>                        | Mode names, empty = all                                            |
| `equipmentCategories`                     | List<String>                        | `rtms__EquipmentType__c.rtms__Category__c` values, empty = all     |
| `equipmentTypes`                          | List<String>                        | Equipment type names, empty = all; combined with categories by OR  |
| `hazmatOnly`, `marketTestOnly`            | Boolean                             |                                                                    |
| `accepted`                                | Enum `ANY, ACCEPTED, DECLINED`      | Default ANY                                                        |
| `rowLimit`                                | Integer                             | Default 2000, max 2000                                             |

Precision mapping, per end:

- CITY → `rtms__Load__r.rtms__City_Lane__c` matched against the place's
  variants on the correct side of the colon (origin left, destination right)
  using bound `LIKE` patterns built from escaped variants.
- PROVINCE → `rtms__Load__r.rtms__State_Lane__c` side matches the place's
  province abbreviation.
- ZIP3 → `rtms__Load__r.rtms__Zip3_Lane__c` side matches the first three
  characters of the place's most common postal code prefix (from its
  locations); the request may also pass an explicit prefix.
- RADIUS → `DISTANCE(rtms__Load__r.rtms__First_Stop__r.rtms__Location2__r.ShippingAddress, GEOLOCATION(lat, lng), unit) < radius`
  for origin, `rtms__Last_Stop__r` for destination.

Always applied: `CreatedDate = LAST_N_DAYS:<lookbackDays>` (bound; the
service builds the literal from a validated integer), the excluded-contact
set from `Pricing_Department_Setting__mdt` through the existing parser,
`ORDER BY CreatedDate DESC`, `LIMIT rowLimit + 1` to detect truncation.

`LaneSearchResult`:

| Field             | Meaning                                                                                                                                                                                                   |
| ----------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `rows`            | List of `Row`: quote Id, name, load Id, origin, destination, mode, equipment, equipment category, carrier name, contact, currency, carrier total, quote date, hazmat, accepted, load status, ops comments |
| `statsByCurrency` | Map currency → `Stats { count, countNonZero, min, max, avg, median }` computed on `rtms__Carrier_Total__c` in that currency, zeros excluded from min/max/avg/median but counted                           |
| `truncated`       | True when more than `rowLimit` rows matched                                                                                                                                                               |
| `elapsedMs`       | Query time, for the phase 2 UI to show and for us to measure                                                                                                                                              |
| `dedupedCount`    | Rows removed by the existing dedupe rule (same total, carrier, lane, mode, equipment)                                                                                                                     |

Rules carried over from the controller: the dedupe rule stays; wildcard
characters `%` and `_` in any free-text input are escaped; a `null` request
field means "no constraint".

Lookback semantics: the default is 90 days. Any positive integer is
accepted, with no ceiling, because pricing decides how far back a lane
comparison should reach. Expected response times, measured: lane-key
precisions stay near one second at any window; radius grows roughly
linearly with the window (about 13 s for a year at both ends, about half
that when a mode or equipment category is also set). The service records
`elapsedMs` so the phase 2 UI can show a progress state and so real usage
can be measured. To make long radius windows fast, the user files a Salesforce support case
early in phase 1 asking for custom indexes on `rtms__Load__c.rtms__City_Lane__c`,
`rtms__State_Lane__c` and `rtms__Zip3_Lane__c` (`CreatedDate` is already
indexed). The case number is tracked in the README until closed.

Error handling: invalid request (negative lookback, radius missing for
RADIUS, unknown place key) throws `LaneSearchException` with a message the
UI can show; SOQL errors propagate. No silent fallbacks.

## Testing

Apex, run in PostProduc as phase 0 established:

- `PlaceNormalizerTest`: accents, case, punctuation, province names and
  abbreviations, country variants, unknown inputs preserved.
- `PlaceBuilderBatchTest`: builds places from factory accounts (two
  spellings of one city collapse to one place, averaged coordinates, counts;
  rerun does not duplicate and preserves `Aliases__c`/`Active__c`).
- `LaneSearchServiceTest`: one method per precision at each end, lookback
  boundary (with `Test.setCreatedDate`), currency split and per-currency
  stats including median on odd and even counts, mode and category filters,
  hazmat, market test, accepted/declined, excluded contact, dedupe count,
  truncation flag at `rowLimit`, invalid requests throw.
- Factory extensions: `createLoads(n, ...)`-style helper is NOT attempted
  (org automation is not bulkified); tests create at most three loads each,
  inside `Test.startTest()` where needed. New helpers: a second location
  pair in another province, a USD quote builder, an equipment type with a
  chosen category, a mode by name.

Jest: none in phase 1 (no UI change). CI unchanged.

## Definition of done

1. `Pricing_Place__c`, `PlaceBuilderBatch`, `PlaceNormalizer`,
   `LaneSearchService` and its classes deployed to PostProduc through CI.
2. The batch run once in PostProduc; the place count and the top 20 places
   by load count recorded in the README; a spot check that Montréal and
   Montreal collapsed into one place.
3. All new tests pass in PostProduc; controller tests still pass.
4. A documented anonymous-Apex example that runs a Montreal→Toronto search
   at each precision against real data, with the measured `elapsedMs`
   recorded in this spec under an Outcome heading.
5. Support case for custom indexes filed (number in the README).
6. Roadmap updated: phase 2 is the UI on this service, phase 3 folded in,
   phase 4 per-currency pricing suggestion, phase 5 unchanged.
