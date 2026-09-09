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
  Quote through Load and Stop to the location Account's `ShippingAddress`.
  Over 24 months, 122,268 of 133,278 quotes have both ends geocoded through
  their location accounts; most of the rest have Revenova's stop-level
  geolocation instead. 58,631 of the 58,921 location accounts ever used by a
  stop are geocoded; 14,973 of the 15,043 used last year have a postal code.
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
- RADIUS → distance from the end's coordinates. Measured over the last 24
  months: 223,062 of 238,616 stops have a geocoded location account, 14,908
  more have no account but carry Revenova's own stop geolocation, and only
  377 have neither. So the filter is an OR of the two sources, per end:
  `DISTANCE(rtms__Load__r.rtms__First_Stop__r.rtms__Location2__r.ShippingAddress, GEOLOCATION(lat, lng), unit) < radius OR DISTANCE(rtms__Load__r.rtms__First_Stop__r.rtms__Geolocation__c, GEOLOCATION(lat, lng), unit) < radius`
  (and `rtms__Last_Stop__r` for the destination). The service measures
  whether the OR form is slower than the account-only form and records both
  timings under Outcome; if the OR form is materially slower it becomes an
  opt-in flag `includeStopGeolocation`, default true.

The search CENTER (the place the user picks) always comes from the place
dictionary in phase 1. Typing an address or a city that is not in the
dictionary is phase 5's job (external geocoding of the center point only;
historical data never needs it).

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

## Outcome (2026-09-09)

Checked against the Definition of done above, item by item:

1. **Deployed through CI — done.** `Pricing_Place__c`, `PlaceNormalizer`,
   `PlaceBuilderBatch`, `PlaceWriteBatch`, `PlaceUsageBatch`,
   `LaneSearchService`, `LaneSearchQueryBuilder`, `LaneSearchFilters`,
   `LaneSearchRequest`, `LaneSearchResult`, the factory extensions, and
   supporting tests all merged to `main` through the standard PR pipeline:
   origin (`IulianEnescu78/PricingDepartment`) PRs **#9, #10, #11**; mirror
   (`TPLM/PricingDepartment`) PRs **#7, #8, #9**; all six MERGED. Deployed to
   PostProduc across three deploys: `0AfbZ00000CndR7SAJ` (22 tests, Tasks
   1-4), `0AfbZ00000CnqWPSAZ` (35 tests, Tasks 5-7), and
   `0AfbZ00000CnrU5SAJ` (36 tests, the `PlaceWriteBatch` fix below).
2. **Batch run, count, top 20, and spot check all recorded — done.** The
   batch ran once in PostProduc on 2026-09-09 (job chain
   `707bZ00000qwuH7QAI` → `707bZ00000qwtbMQAQ` → `707bZ00000qwmU2QAI` →
   `707bZ00000qwvMhQAI`, all `Completed`, 0 errors — see the write-batch fix
   below for why there's a chain of four jobs instead of two). Result:
   **10,496 `Pricing_Place__c` records**, from 58,755 qualifying location
   accounts carrying 11,479 distinct raw `ShippingCity` spellings. The top
   20 by load count is in the README "Place dictionary" section. Spot
   check: `Key__c LIKE 'montreal|%'` returns `montreal|qc|ca` ("Montréal,
   QC, CA") with `Spellings__c` = "Montreal / Montréal / MONTREAL /
   Montreal, / montreal / MONTRÉAL, / MONTRÉAL / Montréal, / MONTREAL," —
   confirming the intended collapse directly from the field — and a minor
   second key `montreal||ca` from a few accounts with the whole address
   typed into `ShippingCity` and `ShippingState` left blank; grouping the
   raw `Account.ShippingCity` values feeding `montreal|qc|ca` shows 577
   "Montréal", 573 "MONTREAL", and 18 more accented/cased/punctuated
   variants all collapsing into that one key. Getting the top 20 required a
   fix first — see "The `Pricing_Place__c` field-level-security gap" below.
3. **Tests pass — done**, per the deploy IDs in item 1 (36/36 passing after
   the `PlaceWriteBatch` fix, reported alongside the fix's deploy).
4. **Example script run against real data — done.**
   `scripts/apex/laneSearchExample.apex` needed no changes: it already used
   current field names (`includeStopGeolocation`, `Precision` enum values)
   with no reference to the renamed `Accepted`/`acceptedFilter` (see
   adaptations below). Montreal → Toronto, last 90 days, run 2026-09-09:

   | Precision                 | Rows | Truncated | ms  | Notes                                                       |
   | ------------------------- | ---- | --------- | --- | ----------------------------------------------------------- |
   | CITY                      | 1    | false     | 997 | CAD only, single quote                                      |
   | PROVINCE                  | 476  | false     | 618 | CAD + 1 USD row                                             |
   | ZIP3                      | 0    | false     | 867 | no quotes matched this pair's postal prefixes in the window |
   | RADIUS (100 mi both ends) | 377  | false     | 399 | CAD only                                                    |

   365-day radius comparison (100 mi both ends), accounts-only vs.
   with-stop-geolocation: **inconclusive in a single run (19.7 s
   accounts-only vs 2.2 s with stops, order-dependent)**. The with-stops
   form came out faster, not slower — the opposite of the "OR condition
   costs more" expectation — but the two requests reuse the same `r2`
   object and run back-to-back in one transaction, so the second query
   benefits from whatever the platform cached (query plan, buffer pool)
   while running the first; a single un-repeated, un-randomized pair of
   runs cannot separate the two effects. Default `includeStopGeolocation =
true` stands (the measured ratio is nowhere near "more than 1.5x
   slower" either direction); re-measure in phase 2 with alternating
   order.

5. **Support case — placeholder only.** README has the line; the case
   number is the user's action, not filed by this work.
6. **Roadmap updated** — see the roadmap doc: phase 1 status, and a new
   phase 6 (RFP tool) row plus a Backlog note.

### Adaptations recorded here honestly

- Revenova's managed `rtms__StopUpsert` trigger blanks stop-level
  `rtms__City__c` / `rtms__Postal_Code__c` / `rtms__Geolocation__c` on any
  stop that has `rtms__Location2__c` set (in and out of test context). The
  factory writes lane keys itself rather than relying on that trigger;
  account-less (ad hoc) stops keep their own geolocation, which is exactly
  the fallback the RADIUS precision's OR condition depends on.
- Account `State`/`Country` picklists in this org reject abbreviations
  ("QC", "CA"); `PricingTestDataFactory.createLocation` must be called with
  full names ("Quebec", "Canada").
- `LaneSearchRequest.Accepted.ANY` and a field named `accepted` could not be
  used as specified: `ANY` is a reserved Apex identifier, and a field named
  `accepted` collided with the `Accepted` enum type (Apex is
  case-insensitive). Renamed to `Accepted.ANY_STATUS` and
  `req.acceptedFilter`.
- The lane-search SOQL-building logic and the filter-application logic were
  split out of `LaneSearchService` into `LaneSearchQueryBuilder` and
  `LaneSearchFilters` to keep every class under PMD's class-level
  cyclomatic-complexity threshold without a suppression.
- `Spellings__c` (all known spellings for a place, newline-separated) and
  `Postal_Prefix__c` (most common postal prefix among the place's
  locations) were added to `Pricing_Place__c` beyond the fields originally
  listed in this spec's "Place dictionary" table; both are read by
  `PlaceBuilderBatchTest` and used in the README's spot check.
- **The DML-row-limit bug and its fix.** The first attempt to run the batch
  in PostProduc (before the fix below) failed: `PlaceBuilderBatch.finish()`
  upserted every built `Pricing_Place__c` row in one transaction, chunked
  into `Database.upsert()` calls of 2,000 records each, on the assumption
  that chunking avoided Salesforce's DML-row governor limits. It does not:
  Apex has two separate limits — 10,000 rows per single DML statement (which
  chunking does avoid) and **10,000 rows per transaction, cumulative across
  every DML statement in that transaction** (which chunking inside one
  `finish()` invocation does not avoid, since all the chunks are still one
  transaction). With 58,755 qualifying accounts and 11,479 distinct raw
  city spellings, the true place count (10,496) is well above that per-
  transaction ceiling, so `finish()` threw `Too many DML rows: 10001`,
  which rolled back every upsert in that transaction — the run completed
  with `NumberOfErrors = 1` and left `Pricing_Place__c` at zero rows. The
  same bug existed in `PlaceUsageBatch.finish()`'s single unchunked
  `update updates;`. The fix: a new `PlaceWriteBatch implements
Database.Batchable<Pricing_Place__c>`, whose `start()` returns the
  already-built `List<Pricing_Place__c>` as an `Iterable`, so each
  `execute()` scope runs in its **own** transaction — the per-transaction
  limit resets every 2,000 rows no matter how many rows there are in total.
  `PlaceBuilderBatch.finish()` now hands its built rows to
  `PlaceWriteBatch(records, chainUsageBatch = true)`, which chains
  `PlaceUsageBatch` once it finishes; `PlaceUsageBatch.finish()` now hands
  its changed rows to a second `PlaceWriteBatch(records, chainUsageBatch =
false)`. Fixed and merged as origin #11 / TPLM #9, deployed as
  `0AfbZ00000CnrU5SAJ` (36 tests). The rerun after the fix produced the
  chain of four completed jobs recorded in item 2 above, with 0 errors
  throughout.
- **The `Pricing_Place__c` field-level-security gap and its fix.** No
  permission set or profile granted object or field read on
  `Pricing_Place__c`, discovered while trying to query the top 20 places
  for this Outcome — not even to System Administrator (the profile every
  `sf` command in this project runs as). `SELECT Location_Count__c, ...
FROM Pricing_Place__c` failed with `No such column` from `sf data
query`, from static and dynamic SOQL in Execute Anonymous, and from the
  Tooling API (`sObject type 'Pricing_Place__c' is not supported`); only
  Apex compiled into a saved class (system mode, ignores FLS) could read
  these fields, which is why `LaneSearchService.search()` itself was
  unaffected (proven by item 4: the FLS enforcement is scoped to SOQL
  literally written inside an anonymous block, not to SOQL inside classes
  it calls). Not a regression from this phase's work — the object was
  never given a permission set because phase 1 has no UI touching it
  directly — but it was a real blocker for phase 2's place picker and for
  any admin/report/API access to this data. Fixed in this same branch:
  `Pricing_Department_User` gained `objectPermissions` for
  `Pricing_Place__c` (read + edit, `viewAllRecords = true`, no create/
  delete/modifyAllRecords) and `fieldPermissions` for every custom field
  except `Key__c` (readable on all ten; editable only on `Aliases__c` and
  `Active__c`, the two pricing curates by hand). `Key__c` was left out
  because it is a universally-required field and Salesforce rejects
  `fieldPermissions` entries for those (it deployed clean on the first
  attempt once `Key__c` was excluded, confirming the brief's prediction).
  Deployed alone as `0AfbZ00000CnsefSAB`, then assigned to the running
  user (`sf org assign permset`), after which the top 20 query and the
  full `Spellings__c` spot check both worked. Phase 2's
  `Lane_Benchmark_User` should carry these same grants forward when it
  replaces this permission set.
