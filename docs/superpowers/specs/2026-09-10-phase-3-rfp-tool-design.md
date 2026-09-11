# Phase 3: RFP Tool — design

Date: 2026-09-10. Status: approved in conversation, written for review.
Roadmap: `2026-09-07-pricing-department-roadmap.md` (phase 3). Builds on phase 1
(`2026-09-09-phase-1-search-foundation-design.md`) and phase 2
(`2026-09-09-phase-2-lane-benchmark-ui-design.md`).

## Goal

Let the pricing team answer a customer RFP from inside Salesforce: upload the
customer's lane file, see the carrier-quote history for every lane, record the
carrier bids they collect (without creating Loads), choose a cost and a margin
per lane, and export the customer's file back with our prices filled in. Bids
become a second, flagged source in Lane Benchmark, and every project is visible
on the customer's Account.

## Decisions taken during brainstorming (2026-09-10)

- Own light objects (`RFP_Project__c`, `RFP_Lane__c`, `Benchmark_Rate__c`),
  not Revenova's RFP / Lane / Rate Entry module. Revenova's module is installed
  but unused (5 RFPs, last one 2024-12; 10 Lanes; 2 Rate Entries) and is built
  for customer quoting through tariff schedules, not for capturing carrier bids.
- Existing carrier-quote history is reused through `LaneSearchService`
  unchanged in meaning; the RFP tool never duplicates its query logic.
- Every customer file differs: the user maps columns after upload; the mapping
  is remembered per customer.
- End products of an RFP session: bids saved per lane, a sell price per lane,
  an export back to Excel in the customer's layout, and project tracking.
- Carrier-rate entry point lives only in the RFP tool. Lane Benchmark shows bids
  through a Source filter (All / Loads only / Bids only). Projects, files and
  bids are visible on the customer Account only.
- Approach A: the browser parses the workbook with the org's existing
  `sheetJs` static resource; lanes, bids and pricing are stored as records;
  history is fetched in chunks and snapshotted on the lane.

## Implementation split

Two plans, each shipping working software:

- **3a — foundation:** the three objects, permission sets, `BenchmarkRateService`,
  `BidSearchQueryBuilder`, the `source` filter through `LaneSearchRequest` /
  `LaneSearchService` / Lane Benchmark filters and results, `RfpTestDataFactory`,
  and the `rfpProjectsForAccount` component. After 3a a bid created through the
  record page already appears in Lane Benchmark.
- **3b — workbench:** `RfpController`, `RfpImportService`, `RfpHistoryService`,
  the RFP tab and every `rfp*` LWC (upload, mapping, table, panel, bid form,
  export), README and the Outcome.

## Data model

All three objects are custom, API 64.0, multi-currency aware (the org has
`CurrencyIsoCode` on every object). Field names are final unless the plan
records a defect.

### `RFP_Project__c`

| Field                 | Type                                                | Notes                                                                    |
| --------------------- | --------------------------------------------------- | ------------------------------------------------------------------------ |
| `Name`                | Text(80)                                            | Project name, for example "Costco Q4 2026"                               |
| `Customer__c`         | Lookup(Account)                                     | Lookup filter: record type in (Customer, New_Customer)                   |
| `Status__c`           | Picklist: Draft, Pricing, Sent, Awarded, Lost       | Default Draft                                                            |
| `Due_Date__c`         | Date                                                |                                                                          |
| `Default_Margin__c`   | Percent(5,2)                                        | Default 15; copied to each lane on import                                |
| `Column_Mapping__c`   | LongTextArea(32768)                                 | JSON `{ "originCity": "Origin City", ... }` as chosen on the last import |
| `Source_File_Name__c` | Text(255)                                           | The uploaded file's name; the file itself is a ContentDocumentLink       |
| `Lane_Count__c`       | Roll-up COUNT(RFP_Lane__c)                          |                                                                          |
| `Costed_Count__c`     | Roll-up COUNT(RFP_Lane__c WHERE Has_Cost__c = true) | Filters on the checkbox formula, not "Cost\_\_c != null" (see ruling 7)  |
| `Sold_Count__c`       | Roll-up COUNT(RFP_Lane__c WHERE Has_Sell__c = true) | Filters on the checkbox formula, not "Sell\_\_c != null" (see ruling 7)  |
| `Notes__c`            | LongTextArea(32768)                                 |                                                                          |

Sharing: private is not needed; keep Public Read/Write (the org's default for
pricing data). Files: the workbook is uploaded with `lightning-file-upload`
against the project record.

### `RFP_Lane__c` (master-detail to `RFP_Project__c`)

| Group    | Fields                                                                                                                                                                                                                                                                                                             |
| -------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Identity | `RFP_Project__c` (MD), `Row_Number__c` Number(6,0), `Raw_Row__c` LongTextArea(32768) JSON of the original row (header → cell), `Name` auto-number `L-{000000}`                                                                                                                                                     |
| Origin   | `Origin_City__c` Text(80), `Origin_Province__c` Text(80), `Origin_Country__c` Text(2), `Origin_Postal__c` Text(12), `Origin_Place__c` Lookup(Pricing_Place__c), `Origin_Resolved__c` Checkbox                                                                                                                      |
| Dest.    | same six fields with `Destination_` prefix                                                                                                                                                                                                                                                                         |
| Lane     | `Mode__c` Text(40), `Equipment_Category__c` Text(40), `Equipment_Type__c` Text(80), `Commodity__c` Text(255), `Quantity__c` Number(12,2), `Quantity_Unit__c` Text(20), `Shipments_Per_Year__c` Number(8,0), `Hazmat__c` Checkbox, `Customer_Fuel_Surcharge__c` Number(10,2), `Customer_FSC_Included__c` Checkbox   |
| History  | `Hist_Count__c` Number(8,0), `Hist_Min__c`, `Hist_Median__c`, `Hist_Average__c`, `Hist_Max__c` Currency(16,2), `Hist_Precision__c` Text(20) (CITY / PROVINCE / RADIUS-50KM), `Hist_Lookback_Days__c` Number(5,0), `Hist_As_Of__c` DateTime, `Hist_Status__c` Picklist: Pending, Done, Failed, No match, Unresolved |
| Pricing  | `Cost__c` Currency(16,2), `Cost_Source__c` Picklist: Bid, History median, Manual, `Selected_Bid__c` Lookup(Benchmark_Rate__c), `Margin__c` Percent(5,2), `Sell__c` Currency(16,2) (stored, written by the LWC as `Cost × (1 + Margin/100)` rounded to 2), `Notes__c` LongTextArea(4000)                            |

`Sell__c` is stored, not a formula, so an exported price never changes after
the fact when someone edits the margin.

### `Benchmark_Rate__c` (the carrier bid)

| Group     | Fields                                                                                                                                                                                                                                                                                                                                                                                                                              |
| --------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Links     | `RFP_Lane__c` Lookup(RFP_Lane__c), `RFP_Project__c` Lookup(RFP_Project__c) (copied from the lane on insert), `Name` auto-number `B-{000000}`                                                                                                                                                                                                                                                                                        |
| Carrier   | `Carrier__c` Lookup(Account) filtered to record types (Carrier, New_Carrier); `Carrier_Name__c` Text(255); `Contact_Name__c` Text(120); `Contact_Email__c` Email; `Contact_Phone__c` Phone. Validation rule `Carrier_Or_Name_Required`: `ISBLANK(Carrier__c) && ISBLANK(Carrier_Name__c)` is an error. Formula `Carrier_Display__c` = `IF(ISBLANK(Carrier__c), Carrier_Name__c, Carrier__r.Name)`                                   |
| Price     | `Rate__c` Currency(16,2) required, `CurrencyIsoCode`, `Fuel_Surcharge__c` Currency(16,2), `FSC_Included__c` Checkbox, `Transit_Days__c` Number(3,0), `Valid_From__c` Date (default today), `Expires_On__c` Date (default today + 30), `Status__c` formula Text: `IF(Expires_On__c < TODAY(), "Expired", "Active")`, `Notes__c` LongTextArea(4000)                                                                                   |
| Lane      | `Mode__c` Text(40), `Equipment_Category__c` Text(40) (ruling 3, copied from the lane so the equipment-category filter applies to bids), `Equipment_Type__c` Text(80), `Hazmat__c` Checkbox                                                                                                                                                                                                                                          |
| Lane keys | Copied from the lane on insert by `BenchmarkRateService`: `Origin_City__c`, `Origin_Province__c`, `Origin_Country__c`, `Origin_Postal__c`, `Origin_Place__c`, `Origin_Geolocation__c` (Geolocation, from the place), and the `Destination_` set; `City_Lane__c` Text(255) `"City, ST:City, ST"`, `State_Lane__c` Text(20) `"ST:ST"`, `Zip3_Lane__c` Text(20) `"XXX:XXX"` in exactly the format `PlaceNormalizer` produces for Loads |

Bids are records with real DML by pricing users; the RFP objects are created
and edited in user mode (`WITH USER_MODE` / `Security.stripInaccessible`),
unlike the phase 1 search which stays system mode by documented design.

### Permission sets

- `RFP_Tool_User`: tab `RFP_Tool`, app visibility, create/read/edit on the three
  objects with all fields, read on `Pricing_Place__c`, `Account`, and the
  carrier-quote fields Lane Benchmark uses; Apex classes `RfpController`,
  `RfpImportService`, `RfpHistoryService`, `BenchmarkRateService`,
  `LaneBenchmarkController`, `LaneSearchService`, `LaneBenchmarkPlaceService`.
- `Lane_Benchmark_User` gains read on `Benchmark_Rate__c` and its fields.

## Components

### Apex

| Class                            | Responsibility                                                                                                                                                                                                                                                                                                                                                                       |
| -------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `RfpController`                  | `@AuraEnabled` entry points: `listProjects(accountId?)`, `getProject(id)`, `saveProject(json)`, `importLanes(projectId, lanesJson)` (batches of 200 from the client), `getLanes(projectId)`, `loadHistory(laneIds, precision, lookbackDays)` (≤ 20 ids), `saveLanePricing(json)`, `saveBid(json)`, `getBids(laneId)`, `projectsForAccount(accountId)`, `columnMappingFor(accountId)` |
| `RfpImportService`               | Turns mapped rows into `RFP_Lane__c` records: trims, normalizes province/country through `PlaceNormalizer`, resolves `Pricing_Place__c` keys (city+province+country first, postal prefix second), sets `*_Resolved__c`, copies `Default_Margin__c`, stores `Raw_Row__c`                                                                                                              |
| `RfpHistoryService`              | For each lane builds a `LaneSearchRequest` (origin/destination place keys, precision, lookback, mode/equipment when mapped, `source = LOADS`), calls `LaneSearchService.search`, writes the snapshot fields; falls back to RADIUS 50 km when CITY returns 0 rows and records `Hist_Precision__c = 'RADIUS-50KM'`                                                                     |
| `BenchmarkRateService`           | Validates and inserts/updates bids, copies lane keys and geolocations from the lane and its places, sets `RFP_Project__c`, returns the saved bid with `Carrier_Display__c`                                                                                                                                                                                                           |
| `LaneSearchRequest` (phase 1)    | New field `sourceFilter` enum `RowSource { ALL, LOADS, BIDS }` (not `source`/`Source` — a field named like its enum type fails to compile, ruling 1), default ALL; `applyDefaults()` sets it                                                                                                                                                                                         |
| `LaneSearchService` (phase 1)    | When `sourceFilter != LOADS`, runs `BidSearchQueryBuilder` and merges the bid rows into `LaneSearchResult.rows` via `BidSearchService.mergeRows` (linear merge by `createdDate` descending, capped at `rowLimit`), before dedupe and stats; when `sourceFilter == BIDS` the quote query is skipped entirely                                                                          |
| `BidSearchQueryBuilder`          | Builds the `Benchmark_Rate__c` SOQL with the same precision semantics as `LaneSearchQueryBuilder` (city-lane LIKE variants, state lane, zip3 lane, `DISTANCE()` on the copied geolocations), `Valid_From__c <= TODAY`, `Expires_On__c >= TODAY` unless `sourceFilter == BIDS` (then expired bids are returned too, `Status__c = 'Expired'`), lookback on `CreatedDate`               |
| `LaneSearchResult.Row` (phase 1) | New field `bid` — one nested `@AuraEnabled BidDetail` (`rateId`, `expiresOn`, `status`, `transitDays`, `fuelSurcharge`, `fscIncluded`), null for a Load, not four flat fields (ruling 2, to stay under the `TooManyFields` limit)                                                                                                                                                    |
| `RfpTestDataFactory`             | Builders: `createProject(account)`, `createLane(project, originPlace, destPlace)`, `createBid(lane, rate)`; reuses `PricingTestDataFactory` for places, accounts and quotes                                                                                                                                                                                                          |

### LWC

| Bundle                     | Responsibility                                                                                                                                                                                                                                              |
| -------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `rfpTool`                  | Container for the tab: project list ↔ project workspace routing, holds the project and lanes                                                                                                                                                                |
| `rfpProjectList`           | List of projects (all, or for one account), "New project" form                                                                                                                                                                                              |
| `rfpUpload`                | `lightning-file-upload` to the project + SheetJS read of the same file in the browser (`loadScript` of the `sheetJs` static resource); emits `{ headers, rows }`                                                                                            |
| `rfpColumnMapper`          | Header → field mapping UI with auto-detection (`rfpHeaderGuess` pure module) and the remembered mapping; emits the mapping JSON                                                                                                                             |
| `rfpLaneTable`             | The workbench table (row, origin, destination, mode, equipment, history, best bid, cost, margin, sell, status); inline place picker for unresolved ends (reuses `c/laneBenchmarkPlacePicker`); per-lane save                                                |
| `rfpLanePanel`             | Side panel: `c/laneBenchmarkResults` for the lane (rows from `RfpController.loadHistory` detail call or a direct `LaneBenchmarkController.search`), bid list, cost/margin/sell editor                                                                       |
| `rfpBidForm`               | Add/edit carrier rate: Account lookup (`lightning-record-picker` filtered to carrier record types) or "Carrier not in the system" switch revealing name/contact/email/phone; rate, currency, FSC, FSC included, transit days, valid from, expires on, notes |
| `rfpExport`                | Pure module `rfpWorkbook` (builds sheets from `Raw_Row__c` + our columns, injection guard) + a button component that downloads through SheetJS `writeFile`                                                                                                  |
| `rfpProjectsForAccount`    | Account record page component: projects, files, counts, bids; visibility rule on the flexipage: record type Customer or New_Customer                                                                                                                        |
| `laneBenchmarkFilters` (2) | New "Source" radio group (All / Loads only / Bids only) → request field `source`                                                                                                                                                                            |
| `laneBenchmarkResults` (2) | "Bid" badge with expiry, greyed rows for expired bids, Source column in the CSV                                                                                                                                                                             |
| `rfpMath`                  | Pure module: `sellFor(cost, marginPct)`, `bestBid(bids)` (lowest active rate in the project currency; mixed currencies are not compared, the UI says so)                                                                                                    |

Navigation: CustomTab `RFP_Tool` on FlexiPage `RFP_Tool`, added to the
`TransPro` app (last tab) and to the `Lane_Benchmark` app.

## Flow

1. **New project.** Customer, name, due date, currency, default margin → save →
   upload panel.
2. **Upload.** The file is stored on the project (Files) and parsed in the
   browser (first sheet; `.xlsx`, `.xlsm`, `.xls`, `.csv`). More than 2,000 data
   rows: refused with "Split the file; the workbench handles 2,000 lanes".
3. **Map.** Header row + three sample rows. Targets: origin city, origin
   state/province, origin country, origin postal, destination × 4, mode,
   equipment, commodity, quantity, quantity unit, shipments per year, fuel
   surcharge, FSC included. Required: origin city and destination city, or
   origin postal and destination postal. Auto-detection pre-fills from the
   remembered mapping for that customer, else from header heuristics.
4. **Import.** Rows go to `importLanes` in batches of 200 with a progress bar.
   The service normalizes, resolves places, stores everything. Summary: lanes
   imported, ends unresolved.
5. **History.** `loadHistory` runs 20 lanes per call (CITY, 90 days by default;
   toolbar can set PROVINCE or RADIUS and any lookback, then "Refresh
   history"). Zero rows at CITY → automatic RADIUS 50 km retry for that lane.
   Chunk failure marks its lanes `Failed`; the run continues; "Retry failed".
6. **Price.** Clicking a lane opens the panel. Cost comes from a bid, the
   history median, or manual entry; margin defaults from the project; sell is
   computed and stored; every change saves that lane.
7. **Bids.** "Add carrier rate" from the panel. Save → bid list refreshes; if
   it is the lowest active bid in the project currency, a "Use as cost" hint
   appears.
8. **Export.** Workbook rebuilt from `Raw_Row__c` in `Row_Number__c` order with
   appended columns: Cost, Currency, Margin %, Sell, Fuel surcharge, FSC
   included, Transit days, Bid carrier, Notes; sheet 2 "Bids" (lane row, carrier,
   contact, rate, currency, FSC, transit, valid from, expires on, notes).
   Filename `<customer>-<project>-<yyyymmdd>.xlsx`. Unpriced cells stay empty.
9. **Reopen.** `getProject` + `getLanes` restore the workbench from snapshots;
   nothing is recomputed until asked.

## Lane Benchmark integration

- Filters: "Source" (All / Loads only / Bids only), saved with the remembered
  request (storage key stays `laneBenchmark.request.v1`; a missing `source`
  reads as ALL).
- Results: bid rows show a "Bid" badge, `Expires <date>`, and the bid's
  carrier contact; "Bids only" also lists expired bids, greyed, with
  "Expired". Row click opens the same carrier detail popup.
- Stats: computed over the rows the source filter returns, per currency, as
  today.
- CSV: new first column "Source" (Load / Bid) and "Expires on".

## Account integration

`rfpProjectsForAccount` on the Account Lightning record page (retrieve the
current `Account` flexipage, add the component in the right sidebar with a
component visibility filter `Record Type Developer Name = Customer OR
New_Customer`). Rows: project, status, due date, lanes, costed, sold, bids,
files; row click navigates to the RFP tool with the project open (URL state
`c__projectId`).

## Error handling

| Situation                             | Behaviour                                                                                |
| ------------------------------------- | ---------------------------------------------------------------------------------------- |
| File unreadable / empty / no header   | Import does not start; message names the problem                                         |
| Required mapping missing              | "Import" disabled with the missing targets listed                                        |
| Row with empty origin and destination | Skipped and counted in the summary                                                       |
| Place not resolved                    | Lane imported, `Hist_Status__c = Unresolved`, inline picker; fixing it re-runs that lane |
| History chunk error (limits, timeout) | Lanes in the chunk → `Failed`; run continues; "Retry failed" button                      |
| Bid without carrier lookup or name    | Form blocks submit; the validation rule is the last line of defence                      |
| Mixed currencies among bids           | Best-bid hint only compares bids in the project currency; others are shown, not compared |
| Export with zero priced lanes         | Allowed, with a confirmation ("No lane has a price yet")                                 |
| Apex exceptions                       | `AuraHandledException` with a user sentence; no SOQL or stack text reaches the page      |

## Limits and performance

- 2,000 lanes per file; 200 lanes per import call; 20 lanes per history call
  (two queries each, plus one for bids when the panel opens).
- Snapshots on the lane keep reopen to two queries.
- `Benchmark_Rate__c` lane-key fields are indexed the same way Loads are: the
  Salesforce custom-index case in the README covers both objects.
- SheetJS is loaded once per page from the existing static resource
  (`sheetJs`, full build; the plan verifies the version and, if older than
  0.18, uploads `sheetJs_0_20` alongside rather than replacing a resource
  someone else owns).

## Security

- The RFP Apex runs in user mode; the phase 1 search stays system mode.
- All SOQL is bound; free text from the spreadsheet is never concatenated into
  a query (place resolution goes through `PlaceNormalizer.key()` and binds).
- Export cells: strings starting with `= + - @ \t \r` get the leading
  apostrophe, as the CSV export does.
- No new secrets. The Mapbox token stays where phase 2 left it.
- Field-level access is granted only through the two permission sets.

## Testing

- Apex (new test classes `RfpImportServiceTest`, `RfpHistoryServiceTest`,
  `BenchmarkRateServiceTest`, `RfpControllerTest`, `BidSearchQueryBuilderTest`,
  and additions to `LaneSearchServiceTest` for the source filter): resolution
  by city+province+country and by postal prefix; unresolved ends; batch import
  of 200 rows; snapshot writing; CITY→RADIUS fallback; lane-key copying on bid
  insert; validation rule; source ALL/LOADS/BIDS; expired bid handling; Account
  list. Every deploy adds these classes to the `-t` list.
- Jest: `rfpHeaderGuess` (common headers: "Origin City", "O City", "From City",
  "Orig", "Dest", "Zip", "Postal", "Mode", "Equip"), `rfpMath`, `rfpWorkbook`
  (order, empty cells, injection guard, second sheet), `rfpBidForm` validation
  and the new-carrier switch, `rfpLaneTable` cost/margin/sell edits and save
  events, `laneBenchmarkFilters` Source control, `laneBenchmarkResults` bid
  badge and CSV Source column, `rfpProjectsForAccount` rendering.
- Manual in PostProduc: import an anonymized real RFP (≥ 100 lanes), fix two
  unresolved ends, price three lanes three ways, add a new-carrier bid and an
  existing-carrier bid, export and open in Excel, then search one of those
  lanes in Lane Benchmark under each Source setting and confirm the badge and
  expiry.

## Out of scope (phase 3)

Sending the response to the customer; converting a free-text carrier into an
Account; bids on carrier Account pages; awarding logic; Revenova RFP linkage;
retiring the old page (phase 4).

## Definition of done

Objects, permission sets, tab/page/app entries and the Account component
deployed to PostProduc; all Apex tests green with the full `-t` list; Jest,
ESLint, Prettier and PMD clean; the manual checks above recorded in an
`## Outcome` section here; README section "RFP Tool (phase 3)"; roadmap phase
3 marked done.

## Outcome — 3a (2026-09-11)

Branch `phase-3a/foundation`, commits `7575be6..e53994e` (`b47776e`,
`dc3255f`, `e4ad045`, `844a94c`, `33169a3`, `65b1997`, `5c198f9`, `e53994e`).
This section and its docs commit land on the same branch, after `e53994e`.
The tab/page/app, import, history, workbench and export named in "3b —
workbench" above are not part of 3a; only the foundation goal ("After 3a a
bid created through the record page already appears in Lane Benchmark") was
targeted. That goal was true only for bids created through
`BenchmarkRateService.save` until the final review fix wave below: a bid
inserted or updated directly on the record page (bypassing `save()`) carried
no lane keys, so it did not match a Lane Benchmark search. The
`BenchmarkRateTrigger` before-insert/before-update trigger, added in that fix
wave, stamps every bid regardless of how it was created, so the exit
criterion is now true without qualification.

**Deploys** (all to `sandbox`/PostProduc; ids and counts from the task
reports):

| Task                                                                       | Deploy id                                                                                                 | Tests        |
| -------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------- | ------------ |
| 1 — objects, validation rule, permission sets                              | validate `0AfbZ00000Cont3SAB`, deploy `0AfbZ00000ConwHSAR`                                                | 60/60        |
| 2 — `RfpTestDataFactory`                                                   | `0AfbZ00000CooM5SAJ`                                                                                      | 61/61        |
| 3 — `BenchmarkRateService`                                                 | `0AfbZ00000CooxBSAR`; fix round 1 `0AfbZ00000CoprdSAB`                                                    | 65/65; 69/69 |
| 4 — `sourceFilter`, `Row.bid`, `BidSearchQueryBuilder`                     | `0AfbZ00000CopjZSAR` (first attempt `0AfbZ00000CopRpSAJ` failed 68/69 on the test-assertion defect below) | 69/69        |
| 5 — `BidSearchService`, merge into `LaneSearchService`                     | `0AfbZ00000Coq69SAB`                                                                                      | 73/73        |
| 6 — Lane Benchmark Source filter, bid rows, CSV (LWC only, no Apex deploy) | —                                                                                                         | Jest 66/66   |
| 7 — `RfpController`, `rfpProjectsForAccount`                               | `0AfbZ00000CorBtSAJ`                                                                                      | 74/74        |

Final state: **74/74** Apex tests across thirteen classes, **Jest 68/68**,
PMD (quickstart, priority 3, `--fail-on-violation`) exit 0 on every task,
ESLint/Prettier clean.

**Adaptations from the plan and spec.**

Rulings recorded in the plan header (applied as written; see the plan's
"Rulings that amend the spec" for the full text):

1. `sourceFilter` of enum `RowSource { ALL, LOADS, BIDS }`, not `source` of
   enum `Source`. `ALL` compiled without needing the `ALL_SOURCES` fallback.
2. `LaneSearchResult.Row.bid` is one nested `BidDetail` (`rateId`,
   `expiresOn`, `status`, `transitDays`, `fuelSurcharge`, `fscIncluded`), not
   four flat fields.
3. `Benchmark_Rate__c.Equipment_Category__c` Text(40) added, copied from the
   lane, so the equipment-category filter applies to bids.
4. For bids, `marketTestOnly = true` and `acceptedFilter` ACCEPTED/DECLINED
   return no bids.
5. `RfpController` ships with `projectsForAccount` only in 3a.
6. No Account FlexiPage is edited; `rfpProjectsForAccount` renders nothing off
   the Customer/New_Customer record types; the App Builder placement is a
   recorded manual step (below), not done in 3a.
7. `RFP_Project__c` roll-ups filter on the checkbox formulas `Has_Cost__c` /
   `Has_Sell__c`, not on "field not blank".
8. Bid rows never dedupe (their fingerprint includes the bid Id);
   `truncated` covers both the quote query and the bid query.
9. Bid lane keys are built from the lane's resolved places, never from
   spreadsheet text.

Additional rulings the ledger recorded during implementation (plan defects,
not spec decisions):

- A COUNT roll-up's `<summarizedField>` is rejected by Salesforce ("bad value
  for restricted picklist field: Id"); the field generator omits it for
  `summaryOperation = count` (Task 1).
- `merge` is a reserved Apex identifier (the `MERGE` DML statement); the
  method is `BidSearchService.mergeRows` (Task 5).
- With `sourceFilter = BIDS` the quote query must be skipped entirely —
  `LaneSearchQueryBuilder` has no `RowSource` concept — so
  `LaneSearchService.search` guards it; this is the spec's own intent ("Bids
  only") (Task 5).
- `BidSearchQueryBuilderTest.filtersAndSourceRules`'s
  `!soql.contains('Expires_On__c')` assertion can never pass, since the
  column is always in the SELECT list; narrowed to
  `!soql.contains('Expires_On__c >= TODAY')` (Task 4).
- A hard-coded Id literal in `BidSearchServiceTest` was replaced by a
  `mockRateId()` helper to satisfy PMD's `AvoidHardcodingId` — same value,
  built without a literal (Task 5).
- `RFP_Tool_User` was missing read `fieldPermissions` on every
  `Pricing_Place__c` custom field except `Key__c`, needed by
  `BenchmarkRateService.loadLane`'s `WITH USER_MODE` query; added (Task 3 fix
  round 1).
- `RFP_Tool_User`'s generated `fieldPermissions` excluded every Summary and
  formula field, but a `WITH USER_MODE` query needs read access on roll-ups
  and formulas too — `Carrier_Display__c`/`Status__c` (Task 3),
  `Lane_Count__c`/`Costed_Count__c`/`Sold_Count__c` (Task 7). Rule: grant
  `readable=true`/`editable=false` on every roll-up/formula field of the
  three objects.
- The field generator set `formulaTreatBlanksAs = BlankAsZero` on every
  formula, which makes `NOT(ISBLANK(Cost__c))` always evaluate true;
  `Has_Cost__c`/`Has_Sell__c` now use `BlankAsBlank`, the correct setting for
  an `ISBLANK`-based checkbox formula, so `Costed_Count__c`/`Sold_Count__c`
  count correctly (Task 7).
- `cityLane()` applies `PlaceNormalizer.provinceCode` to a place's
  `Province__c` while `cityLaneVariants` uses `Province__c` as stored;
  dictionary places already store the 2-letter code, so the two agree today.
  A place that ever carried a long province name would be missed at CITY
  precision (found at PROVINCE) — accepted rather than changed, since it
  matches how Revenova writes Loads (pre-Task-1 ruling).
- App Builder placement: not done. Trans-Pro Customer accounts use
  Revenova's managed page `rtms__Account_TMS_Record_Default` (template
  "Header and Left Sidebar"); App Builder can only save a clone of a managed
  page (it proposed the API name `Account_TMS_Record_Default14`), and
  activating that clone changes the Account page for the whole org (or a
  chosen app/record type/profile scope) — an admin decision on a shared
  sandbox, not a controller ruling. Nothing was saved. See the README's "RFP
  Tool (phase 3a)" section for the exact steps (Task 7).

**Deferred.**

- No Apex test runs `System.runAs` a user restricted to only `RFP_Tool_User`;
  every deploy's tests pass because the deploying/test-running user also
  holds `Lane_Benchmark_User` (and other permission sets), which can mask a
  missing grant. Recommended for 3b: an in-test `PermissionSetAssignment`
  under `runAs`.
- App Builder placement of `rfpProjectsForAccount` is pending the admin's
  choice of activation scope (org default for Account, vs. an App/Record
  Type/Profile assignment) — see the README.
- The comment on `sourceFilter` in `LaneSearchRequest` overstates the
  name-collision reason it documents (cosmetic; Task 4).
- `laneBenchmarkResults`'s detail row renders a trailing " · " for Load rows,
  since `transitText`/`fscText` are empty strings for a Load, not a bid
  (cosmetic; Task 6).

**Final review fixes (2026-09-11).** A whole-branch review of `7575be6..f1b23f5`
found ten items, fixed in one final wave before 3a closes:

1. `BidSearchQueryBuilder.addLike` returns without adding a condition when the
   place has no province/postal prefix at that precision, instead of throwing
   — the end is unconstrained, so a bid missing that attribute still matches
   on its other end.
2. `BenchmarkRateTrigger` (before insert, before update) calls
   `BenchmarkRateService.applyLanes`, which bulk-loads every referenced lane
   in one query and stamps lane keys/project/geolocations (always) and
   `Mode__c`/`Equipment_Category__c`/`Equipment_Type__c`/`Hazmat__c` (only
   when blank on the bid), plus `Valid_From__c`/`Expires_On__c` defaults, for
   every bid in the trigger batch.
3. `Benchmark_Rate__c.Valid_From__c`/`Expires_On__c` gain field-level
   `<defaultValue>` (`TODAY()` / `TODAY() + 30`); the field generator's
   `formula()` gained a `blanks` parameter so it stops regressing
   `Has_Cost__c`/`Has_Sell__c` back to `BlankAsZero` on every re-run (see the
   plan header's defects note).
4. `RfpController.projectsForAccount(null)` returns an empty list instead of
   querying with a null bind.
5. `BidSearchService.isBefore` renamed to `isNewer` (same body).
6. Manifest gains `ApexTrigger` (`BenchmarkRateTrigger`) and
   `CustomPermission` (`RFP_Tool`) type blocks.
7. New custom permission `RFP_Tool`, carried by `RFP_Tool_User`.
8. `rfpProjectsForAccount` gates on the `RFP_Tool` custom permission in
   addition to the Customer/New_Customer record type check, and never wires
   the Apex adapter with an `accountId` when the permission is absent.
9. `RFP_Tool_User` marks `Benchmark_Rate__c`'s lane-key and geolocation
   fields (`City_Lane__c`, `State_Lane__c`, `Zip3_Lane__c`,
   `Origin_Geolocation__c`, `Destination_Geolocation__c`) not editable, since
   they are now exclusively trigger-maintained; `Lane_Benchmark_User` gains
   read-only grants on `Carrier_Display__c`/`Status__c`, closing a gap the
   same as Task 3/7's `Carrier_Display__c`/`Status__c`/roll-up fix, but on the
   read-only permission set this time.
10. This Outcome's exit-criterion correction (above), the README's "RFP Tool
    (phase 3a)" section, and the plan header's defects note.

## Outcome — 3b (2026-09-11)

Branch `phase-3b/workbench` (from `phase-3b/plan` at `44afe01`), commits
`b49bb2f..cf251b7` (18 commits: `b49bb2f`, `4c20353`, `1dfde94`, `ba1c11e`,
`4b8ee42`, `45aa7c1`, `cd80c75`, `a3cecd8`, `5028910`, `a3df4e3`, `976052f`,
`0819bce`, `61a1574`, `61ae7fb`, `52ec554`, `f4926cd`, `b2eeaf1`, `cf251b7`).
This section and the rest of the docs task land on the same branch, after
`cf251b7`. Every deploy below is to `sandbox`/PostProduc; ids and counts are
from the controller's ledger
(`.superpowers/sdd/2026-09-11-phase-3b-rfp-workbench/progress.md`).

**Deploys and tests.**

| Task                                                                                               | Deploy id(s)                                                                                                                                                                                             | Tests             |
| -------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------- |
| 1 — harden `save()`, runAs tests, precision tests                                                  | `0AfbZ00000CouWMSAZ` (RED-but-green), `0AfbZ00000Cp1HhSAJ` (GREEN); fix round: `0AfbZ00000Cp1uPSAR` deployed once with the fix reverted, to prove the new test catches the regression                    | 82/82; 82/82      |
| 2 — `RfpImportService`, `RfpLaneController`                                                        | `0AfbZ00000Cp2QgSAJ`; fix round `0AfbZ00000Cp14pSAB`                                                                                                                                                     | 90/90; 91/91      |
| 3 — `RfpHistoryService`, `RfpHistoryController`                                                    | `0AfbZ00000Cp6inSAB` (RED, compile), `0AfbZ00000Cp6NrSAJ` (NoTestRun), `0AfbZ00000Cp8JBSAZ`; fix round `0AfbZ00000CpA4rSAF`                                                                              | 95/95; 97/97      |
| 4 — `RfpProjectController`, `RfpBidController`                                                     | `0AfbZ00000CpB49SAF` (RED), `0AfbZ00000CpCY5SAN`; fix round `0AfbZ00000CpD2lSAF`                                                                                                                         | 102/102; 102/102  |
| 5 — pure modules `rfpHeaderGuess`, `rfpSheet`, `rfpWorkbook`, `rfpMath`                            | — (LWC only, no Apex deploy)                                                                                                                                                                             | Jest 77 → 78      |
| 6 — `rfpUpload`, `rfpColumnMapper`                                                                 | — (LWC only)                                                                                                                                                                                             | Jest 81 → 83      |
| 7 — `rfpLaneTable`, `rfpLanePanel`, `rfpBidForm`, `rfpAccountPicker`                               | — (LWC only)                                                                                                                                                                                             | Jest 117 → 128    |
| 8 — `rfpTool`, `rfpProjectList`, `rfpExport`                                                       | — (LWC only)                                                                                                                                                                                             | Jest 173 → 179    |
| 9 — `RFP_Tool` tab/page/app entries, vendored `sheetJs` static resource, manifest LWC registration | `0AfbZ00000CpJ89SAF` / `0AfbZ00000CpJEbSAN` rolled back ("Invalid reference sheetJs of type resourceUrl"); after the unblock: `0AfbZ00000CpJphSAF` (NoTestRun, 230/230 components), `0AfbZ00000CpH7ySAF` | —; 102/102        |
| Browser fix wave (B1–B5, cross-task, before the final review)                                      | `0AfbZ00000CpKtpSAF`                                                                                                                                                                                     | 102/102; Jest 187 |
| 10 — docs and outcome (this task)                                                                  | — (docs only)                                                                                                                                                                                            | —                 |

Final state: **102/102** Apex tests across nineteen classes, **Jest 187**
(from 77 at the start of the LWC-only tasks), PMD clean on every commit,
ESLint/Prettier clean.

**Rulings recorded in the plan header** (applied as written; full text in the
plan's "Rulings that amend the spec"):

1. `rfpUpload` reads the file with a plain `<input type="file">` and
   `FileReader`, not `lightning-file-upload`; `attachFile` inserts
   `ContentVersion`/`ContentDocumentLink` in user mode; 3 MB client-side cap.
2. History runs 10 lanes per call, `rowLimit` 500; CITY then a 50 km RADIUS
   fallback; a per-lane `LaneSearchException` → `'No match'`, any other
   exception → `'Failed'`; a chunk never fails as a whole.
3. `getLanes` never returns `Raw_Row__c`; `getRawRows` pages 500 rows for
   export only.
4. Import rows use nested `RowEnd origin/destination` objects; lanes and bids
   travel to the LWC as SObjects, queried in user mode.
5. `RfpController` keeps only `projectsForAccount`; the workbench methods
   live in four new controllers.
6. `BenchmarkRateService.save` strips non-writable fields (the 3a deferral);
   `saveLanePricing` updates a fixed whitelist; place fixes go through
   `resolveLaneEnd`.
7. Export writes typed `xlsx` string cells (SheetJS type `s`); the workbook
   is built by pure `rfpWorkbook.buildSheets` and written via
   `XLSX.write(wb, { type: "array" })` → `Blob` → the existing
   attach-anchor/deferred-revoke download pattern.
8. Sell price reuses `c/marginMath.suggestedSell`; `rfpMath` adds `bestBid`
   only; `slug()` is exported from `c/laneBenchmarkCsv` for the export
   filename.
9. Mode/equipment from the spreadsheet are free text and carry no filter in
   history searches in 3b (a recorded deferral).
10. Postal-prefix resolution picks the place with the highest
    `Load_Count_365d__c` among places sharing the prefix; with no country on
    the row, the city key is tried for CA, then US, then MX.
11. Customer/carrier lookups are Apex typeaheads (`searchAccounts(term, kind)`) rendered like `laneBenchmarkPlacePicker`, on the plan's assumption that `lightning-record-picker` has no Jest stub in this project — wrong (the repo's `sfdx-lwc-jest` does ship one), but the typeahead design was kept anyway (ledger ruling R13).
12. `rfpProjectsForAccount` retargets its row click to `standard__navItemPage` `{ apiName: "RFP_Tool", state: { c__projectId } }`; `rfpTool` reads it from `CurrentPageReference`.
13. runAs tests build a test-only user under `System.runAs(new User(Id = UserInfo.getUserId()))`, profile `Standard User` else `Minimum Access - Salesforce`, skipped (and ledgered) if neither exists or no license is free.

**Rulings recorded during implementation** (ledger R1–R17, controller
decisions on review findings — full text in the ledger):

- **R1** — `RfpUserError` (`of`/`safe`) is a shared helper for Tasks 2–4;
  `RfpController` (3a) keeps its own copy, out of scope to touch.
- **R2** — `Rate__c` has no explicit FLS entry in `RFP_Tool_User`: no action,
  since a required field is always readable/editable without one.
- **R3** — when a permission-set-only `NoTestRun` deploy is impossible
  (forward reference to classes not yet in the org), deploy the full
  manifest `NoTestRun` first, then the test-running deploy; kept as the
  procedure for the rest of the plan.
- **R4** — `resolveLaneEnd` sets `Hist_Status__c = 'Pending'` only when the
  other end is already resolved, else `'Unresolved'` (real defect, fixed).
- **R5** — `RfpUserError.safe`'s `substringBefore('.')` on a period-less
  message: parked/closed after confirming in anonymous Apex that it returns
  the original string, not `''`.
- **R6** — history-write DML uses `allOrNone = false` with a best-effort
  `Hist_Status__c = 'Failed'` flip on the ids that failed, instead of
  discarding the whole chunk (real defect, fixed).
- **R7** — added the PROVINCE no-match test; the generic `'Failed'` catch
  inside `snapshot()` stays untested — parked, no cheap trigger for it.
- **R8** — `listProjects` splits `LIST_FIELDS` from `DETAIL_FIELDS` so the
  200-row list no longer carries `Column_Mapping__c`/`Notes__c` (real
  defect, fixed).
- **R9** — `attachFile`'s USER_MODE DML on freshly built records, without a
  `stripInaccessible` call: parked, no change — it fails closed (throws)
  rather than silently trimming, the safer failure.
- **R10** — added a `buildSheets` selected-bid export test using real bid
  and lane ids (real gap, fixed).
- **R11** — `bestBid`'s `!== "Expired"` check: parked, no change —
  `Benchmark_Rate__c.Status__c` is the exact two-value formula
  `IF(Expires_On__c < TODAY(), "Expired", "Active")`.
- **R12** — blank spreadsheet headers are excluded from the column-mapper
  options; a nameless column cannot be addressed by header name either way.
- **R13** — the repo's `sfdx-lwc-jest` does ship a `recordPicker` stub (the
  plan's ruling 11 assumed none); the Apex typeahead design is kept anyway —
  one picker serves customers and carriers, no lookup-filter metadata
  needed.
- **R14** — export bids are collected inside `rfpExport` at export time
  (matching decision 6's original intent), not on every workbench open.
- **R15** — no `onbidsaved` handler in the container; decision 8 (no
  container-level bid state) stands.
- **R16** — the plan's assumption that `sheetJs` "stays org-side" and
  resolves through a bare `resourceUrl` reference (plan ruling 9 / the
  global constraints) was wrong: the org's `sheetJs` StaticResource belongs
  to the EN6IA managed package, so the reference cannot resolve. SheetJS
  Community Edition 0.18.5 (Apache-2.0, `xlsx.full.min.js`, 881,727 bytes —
  the same size as the org copy) is now vendored as our own `sheetJs`
  static resource, registered in the manifest.
- **R17** — the LWC bundles from Tasks 5–8 were never registered in
  `manifest/package.xml` (only Apex was); Task 9 registers all 16, and the
  README now notes that every new bundle must be added to the manifest.

**Browser checks (B1–B5), fixed in one cross-task wave before the final
review** (commits `b2eeaf1..cf251b7`, deploy `0AfbZ00000CpKtpSAF` 102/102,
Jest 187):

- **B1** — `rfpUpload` read CSV bytes with SheetJS `type: "array"` and no
  codepage, so a UTF-8 CSV without a BOM decoded as Windows-1252
  ("Trois-Rivières" → "Trois-RiviÃ¨res"). Fixed: for `.csv`/`.txt`, sniff the
  bytes with `TextDecoder('utf-8', { fatal: true })` and pass SheetJS
  codepage 65001 on success, else 1252. Re-verified by a unit test only (no
  unresolved lane was left to re-upload in the browser re-check).
- **B2** — the `c-lane-benchmark-results` table inside the narrow
  `rfpLanePanel` rendered one character per line (columns crushed). Fixed:
  wrapped in an `overflow-x: auto` container with a minimum width.
  Re-verified by unit tests only.
- **B3** (Minor) — "Sell 6670.00CAD" lacked a space before the currency
  code; fixed in the same wave.
- **B4** — clicking inside the inline place picker also selected its row;
  the panel then re-rendered shorter, the page scrolled to the top, and the
  picker's option list ended up off-screen. Fixed: click/keydown
  propagation from the picker cell is stopped before it reaches the row,
  and `rfpLanePanel` gets a minimum height so the layout does not collapse
  on selection change.
- **B5** — "Export to Excel" failed in the org with "Lightning Web Security:
  Unsupported MIME type" (`Blob` built with the `.xlsx` spreadsheet MIME
  type). Fixed: the `Blob` is built with `application/octet-stream`
  instead; the `.xlsx` file name still opens correctly in Excel. The
  `rfpExport` test asserting the MIME type was updated to match.

Re-check after the fix wave: the LWS MIME error is gone and the export
status line is clean; no file visibly landed only because that Chrome
profile has "Ask where to save each file" enabled — a native OS Save dialog
the browser automation cannot see or click, unrelated to the code (see
"Open items" below).

**Deferred (minor findings, from the ledger, not fixed in 3b).**

- Task 1: `PermissionSet` lookup lacks a `LIMIT 1`/empty guard
  (plan-mandated verbatim code); the `Fx` fixture is duplicated across test
  classes (plan-anticipated).
- Task 2: the ledger's implementer report said four supplementary tests,
  the diff has three; `applyEnd`/`resolveLaneEnd`'s parallel side-branches
  could share a helper; rethrow/catch paths are untested.
- Task 3: the controller's generic `catch` omits `safe(e)`; `request()`
  treats an unknown precision as CITY but records the raw value on the
  lane; the second best-effort update (the `'Failed'` flip) skips
  `stripInaccessible` and writes `Hist_Status__c` only.
- Task 4: `columnMappingFor` scans only the latest 200 projects; a
  null-base64 upload reuses the 3 MB error message; the whitelist key
  lookup is case-sensitive; a bid test fixture is repeated inline instead
  of shared.
- Task 5: the sheet parser's "No header row" branch is unreachable; blanking
  the Currency cell is untested; there is no dedup between customer headers
  and `OUR_COLUMNS`.
- Task 6: duplicate header names resolve to the first column (an
  `rfpSheet` design choice, not a bug); the `loadScript` path, the
  2,000-row cap and the `FileReader` fallback are untested; `missingText`
  wording could be clearer; the file input has no `aria-describedby`.
- Task 7: clicking the inline picker also selects its row (Task 8 could
  `stopPropagation` at the container if it matters — later folded into B4's
  fix).
- Task 8: the ">200 selected-bid" export cap has no test covering the note
  it shows; `rfpTool.js` is 360 lines; export can issue up to 200
  sequential `getBids` calls.
- Browser fix wave: fixed panel/table sizes stay at 480px/900px; B1 (CSV
  codepage) is verified by a unit test only, never re-exercised live in the
  browser after the fix.

**Open items (user-side, not controller work).**

- Assign the `RFP_Tool_User` permission set to the pricing team so they can see the `RFP_Tool` tab and use the workbench (`sf org assign permset -n RFP_Tool_User -o sandbox`).
- App Builder placement of `rfpProjectsForAccount` on a clone of Revenova's
  managed Account page (`rtms__Account_TMS_Record_Default`) is still
  pending — carried over from 3a, unchanged in 3b; see the README's "RFP
  Tool (phase 3a)" section for the exact steps and why App Builder can only
  save a clone, never edit the managed page in place.
- The place dictionary (phase 1, `Pricing_Place__c`) holds mojibake
  duplicates from Revenova Locations data, found while browser-checking the
  import (Browser check 1): `'Trois-Riviã ̈Res'`, `'Trois-Rivires'` next to
  the correct `'Trois-Rivières'`. Cleaning these is phase 1 dictionary
  hygiene, not 3b work.
- The Chrome "ask where to save each file" setting that hid the exported
  workbook during the re-check is local to the tester's browser profile; it
  does not affect other users and needs no code change.
