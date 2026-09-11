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

| Field                 | Type                                             | Notes                                                                    |
| --------------------- | ------------------------------------------------ | ------------------------------------------------------------------------ |
| `Name`                | Text(80)                                         | Project name, for example "Costco Q4 2026"                               |
| `Customer__c`         | Lookup(Account)                                  | Lookup filter: record type in (Customer, New_Customer)                   |
| `Status__c`           | Picklist: Draft, Pricing, Sent, Awarded, Lost    | Default Draft                                                            |
| `Due_Date__c`         | Date                                             |                                                                          |
| `Default_Margin__c`   | Percent(5,2)                                     | Default 15; copied to each lane on import                                |
| `Column_Mapping__c`   | LongTextArea(32768)                              | JSON `{ "originCity": "Origin City", ... }` as chosen on the last import |
| `Source_File_Name__c` | Text(255)                                        | The uploaded file's name; the file itself is a ContentDocumentLink       |
| `Lane_Count__c`       | Roll-up COUNT(RFP_Lane__c)                       |                                                                          |
| `Costed_Count__c`     | Roll-up COUNT(RFP_Lane__c WHERE Cost__c != null) |                                                                          |
| `Sold_Count__c`       | Roll-up COUNT(RFP_Lane__c WHERE Sell__c != null) |                                                                          |
| `Notes__c`            | LongTextArea(32768)                              |                                                                          |

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
| Lane      | `Mode__c` Text(40), `Equipment_Type__c` Text(80), `Hazmat__c` Checkbox                                                                                                                                                                                                                                                                                                                                                              |
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
| `LaneSearchRequest` (phase 1)    | New field `source` enum `Source { ALL, LOADS, BIDS }`, default ALL; `applyDefaults()` sets it                                                                                                                                                                                                                                                                                        |
| `LaneSearchService` (phase 1)    | When `source != LOADS`, runs `BidSearchQueryBuilder` and merges bid rows (`isBid = true`, `expiresOn`, `bidStatus`, `carrier` filled from the bid) into `LaneSearchResult.rows`, ordered by date descending, before dedupe and stats                                                                                                                                                 |
| `BidSearchQueryBuilder`          | Builds the `Benchmark_Rate__c` SOQL with the same precision semantics as `LaneSearchQueryBuilder` (city-lane LIKE variants, state lane, zip3 lane, `DISTANCE()` on the copied geolocations), `Valid_From__c <= TODAY`, `Expires_On__c >= TODAY` unless `source == BIDS` (then expired bids are returned with `bidStatus = 'Expired'`), lookback on `CreatedDate`                     |
| `LaneSearchResult.Row` (phase 1) | New fields `isBid` Boolean, `expiresOn` Date, `bidStatus` String, `source` String ('Load' / 'Bid')                                                                                                                                                                                                                                                                                   |
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
