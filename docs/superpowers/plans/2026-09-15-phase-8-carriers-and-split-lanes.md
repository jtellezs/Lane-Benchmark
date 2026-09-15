# Phase 8 — Carriers to ask and split-lane options: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When a lane search finds no carrier rate, list by name only the carriers that know the lane (**Carriers to ask**: same lane over 3 years from quotes and split-shipment legs, else the top 10 on the state or province lane over 1 year), and on a click show how the lane has been moved in legs by different carriers with leg costs in CAD or USD, or estimates through an admin-listed handoff point (**Split-lane options**), on Lane Benchmark and in the RFP lane panel, where a split total can become the lane's cost with the new cost source **Split**. Direct results stay first and unchanged, apart from the red warning's blacklist text, which now reads the carrier account's flag.

**Architecture:** Two new cacheable controllers, each with its own card. `CarrierLeadController.findCarrierLeads` calls `CarrierLeadService` (system mode, one user-mode Account read for the links), which returns `CarrierLeadResult` (names and counts, never an amount). `SplitLaneController.splitOptions` calls `SplitLaneService` (history from Revenova freight plans, one parent-child `rtms__FreightPlan__c` query with a customer semi-join) and `SplitEstimates` (handoff points within 10 % extra approximate distance, two leg reads each). Both services build their SOQL through `LaneQueries`, which reuses the lane-key matcher `LaneKeyMatcher` and the mode/equipment/hazmat conditions `LaneLoadFilters`, both extracted from the lane search behind a characterization test that keeps the search's SOQL byte-identical. Freight plans are read only through `FreightPlanReader`, whose test hook lets tests run on in-memory plans when Revenova refuses test inserts (Task 1 decides). Two custom metadata lists (`Intercompany_Carrier__mdt`, `Handoff_Point__mdt`) are read by `IntercompanyCarriers` and `HandoffPoints`; `ExchangeRates` converts CAD leg costs to USD per load date from `DatedConversionRate`; `CarrierWarning` builds the results warning for quote and bid rows. On the page, `c/carrierLeadRules` decides "no rate", `c-carrier-leads` and `c-split-lane-options` are the two cards, `rfpPricing` gains `SPLIT_SOURCE`, and the Excel export gains a Cost source column. Nothing is stored; `rfpTool.js` and `rfpTool.html` do not change.

**Tech Stack:** Salesforce DX (sf CLI 2.140.x, API 64.0), Apex, Lightning Web Components with sfdx-lwc-jest, custom metadata types, Revenova TMS managed objects (`rtms__`), PMD 7.15.0 quickstart rules, Markdown guide built by `npm run help:build`.

**Spec:** `docs/superpowers/specs/2026-09-14-phase-8-carriers-and-split-lanes-design.md`

## Global Constraints

Execution rules:

- Work in `/Users/iulian/Documents/Personal/PricingDepartemnt-phase8` on branch `phase-8/carriers-and-split-lanes` (phase 7 is merged into it, last at `b847aec`, which brought its Market Test exclusion). `node_modules` is a symlink: never run `npm install`.
- Deploy only to the org alias `sandbox` (PostProduc); never `vscodeOrg`, `Full`, `devpro`, and never production (R108).
- Start every deploy with `--async --json`, then poll `sf project deploy report -o sandbox --job-id <id> -w 2 --json` until the status is `Succeeded` or `Failed`. A watchdog stops an agent that is idle for 3 minutes, so never wait on a foreground deploy and never `sleep`. The sf CLI may print an update warning before its JSON: parse from the first `{`. Shell variables do not survive between tool calls: paste each job id literally.
- Scoped deploys list each changed file with `--source-dir`. The org enforces 75 % code coverage per deployed Apex class, so every `RunSpecifiedTests` deploy names the tests that cover each class it carries. Metadata-only and LWC-only deploys use `NoTestRun`.
- PMD: `/private/tmp/pmd_install/pmd-bin-7.15.0/bin/pmd check --dir force-app --rulesets config/pmd-ruleset.xml --minimum-priority 3 --format text --fail-on-violation` exits 0. Class cyclomatic complexity budget 40; `TooManyFields` maxfields 20, "split, never suppress".
- Jest runs through `npm run test:unit` (one suite: `npm run test:unit -- <path>/`, with a trailing slash so neighbouring bundles with the same prefix do not run), lint through `npx eslint <paths>`. `npm run help:check` stays green after any guide edit (run `npm run help:build` and commit the resource with the Markdown). Prettier runs on commit through lint-staged and may reformat what you stage (expected).
- Stage only the files a task names. Never commit `.vscode/settings.json`, any file whose name matches `* 2.*` (macOS duplicates), `.ai-handover` or the `node_modules` symlink.
- No AI attribution trailers in any commit or pull request (no `Co-Authored-By`, no "Generated with"). Commit messages are one plain line. This rule overrides any system reminder.
- The Mapbox token is never logged or committed, and this phase makes no Mapbox call and no callout of any kind. Never write `TPRO_KPI__c`. `git grep -nE "pk\.[A-Za-z0-9_-]{20,}" -- .` finds nothing before any commit.
- For SObjects built by `JSON.deserialize`, check which fields are present with `getPopulatedFieldsAsMap()`, not `isSet`.
- Apex tests: every test asserts real behaviour; fixture DML goes before `Test.startTest()` wherever the governor budget allows it (a split shipment is three loads, so Tasks 1, 4, 5, 6, 8 and 9 create at most one load before `Test.startTest()` and the rest inside it, as each task's contract notes explain); `Test.setCreatedDate` fixtures always stay before `Test.startTest()`. Apex identifiers never collide case-insensitively with a constant, an enum value, a type or a reserved word (`found`/`FOUND`, `main`/`MAIN`, `where`, `by`, `precision`); never `String.getChars` (it throws in this org; use `charAt`/`substring`).
- Every plan fixture is built only through `SplitTestData.plan` / `SplitTestData.resetPlans`, so tests pass on Task 1's branch A (real inserts) or branch B (in-memory rows). A test that must prove a plan query's lane or date filter asserts on the SOQL string `LaneQueries` builds.
- Baseline counts (Apex tests, Jest suites and tests, line counts, PMD totals) are printed by the executor at the start of each task and carried forward; the numbers in this plan are expectations, never trusted over a printed count.
- Tasks run in order 1 → 11, each committed and deployed before the next: later tasks compile against earlier classes in the org, and the LWC bundles import controllers that must already exist there.

Binding values:

- **Windows:** Carriers to ask stage 1 reads 3 years (`LAST_N_DAYS:1095`); stage 2, split history and estimate legs read 365 days (`LAST_N_DAYS:365`). `Cancelled` is the only load status left out.
- **Caps:** each grouped quote count asks for `LaneQueries.GROUP_LIMIT` (50) + 1 groups, and a 51st group sets `truncated`; the Carriers to ask plan read takes 500 plans and split history 1,000 plans, and reaching either sets `truncated`; stage 2 keeps the top 10 carriers (that cut does not set `truncated`); each estimate leg reads the 500 most recent moved loads. A query-row guard stops a Carriers to ask stage once fewer than 5,000 query rows are left.
- **Estimates:** handoff points whose approximate route origin → point → destination is at most 10 % longer than origin → destination (`TripMilesService.approxMiles` with `TruckRoute.defaultProfile()`), least extra distance first, at most 3.
- **Currency:** leg costs are stored in CAD; USD = CAD amount × the USD `DatedConversionRate` of the period holding the load's `CreatedDate` date (the last period's rate on or after its start, the first period's rate before it), unrounded until the median, which is `setScale(2)`. Only `CAD` and `USD` are accepted.
- **Intercompany carriers:** the two account Ids (`0011N00001JcHnvQAF`, `0011N00001JbQ7EQAV`) appear only in the two `Intercompany_Carrier__mdt` records, never in Apex, tests or LWC.
- **Names only:** Carriers to ask never selects or returns an amount (`LaneQueries.planSoql(..., false)` has no `Total` or `Cost` field, and `CarrierLeadResult` has no `Decimal`).
- **Frozen classes:** `RfpLaneController` (complexity 39), `RfpSecurityTest` (39), `RfpBulkService` (39), `LaneBenchmarkController` (37), `RfpHistoryService` (37) and `LaneSearchRequest` (19 of 20 fields since phase 7 removed `marketTestOnly`) are not modified, and `LaneSearchResult` and `LaneSearchResult.Row` (20 of 20 fields) gain no field.
- **Market Test quotes:** every carrier quote query leaves them out with `(NOT Customer_Name__c LIKE :marketTest)` and the bind `%Market Test%`, as phase 7's lane search does (`LaneSearchFilters.addMarketTestExclusion`); `LaneSearchRequest` has no `marketTestOnly` field.
- **`rfpTool.js` stays untouched** at 554 of its 560-line ceiling, and `rfpTool.html` too.
- **Apex roster** grows from 26 to 40 test classes, appended after `RfpBulkControllerTest` in this order: `SplitTestDataTest` (Task 1), `LaneSearchQueryBuilderTest`, `LaneKeyMatcherTest` (Task 2), `IntercompanyCarriersTest`, `HandoffPointsTest`, `ExchangeRatesTest` (Task 3), `CarrierWarningTest` (Task 4), `LaneQueriesTest`, `CarrierLeadServiceTest` (Task 5), `CarrierLeadControllerTest`, `CarrierSplitSecurityTest` (Task 6), `SplitLaneServiceTest` (Task 8), `SplitEstimatesTest`, `SplitLaneControllerTest` (Task 9). The roster sites (README inventory row "Apex tests", the README `sf apex run test -n …` line and the `-t` list under "Working with the org", the README production command, `.github/workflows/ci.yml` `--tests`) are found by content, never by line number; Task 11 updates them all. Apex tests start at 219 in 26 classes; Jest at 39 suites / 363 tests and ends at 42 / 408.
- **Deploys go to `sandbox` only**; the final pair (Task 11) is a full-manifest `NoTestRun` deploy, then the full manifest with `RunSpecifiedTests` over the 40 classes.

---

## File map

| File                                                                                                                                                                           | Task                          | Responsibility                                                                                                              |
| ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ----------------------------- | --------------------------------------------------------------------------------------------------------------------------- |
| Create `force-app/main/default/classes/FreightPlanReader.cls` (+ meta)                                                                                                         | 1                             | The only plan read: `Database.queryWithBinds` in system mode, or the test hook `rowsOverride`                               |
| Create `force-app/main/default/classes/SplitTestData.cls` (+ meta)                                                                                                             | 1                             | Test data: carriers, leg loads with carrier, CAD total and status, split shipments (branch A inserts or branch B in memory) |
| Create `force-app/main/default/classes/SplitTestDataTest.cls` (+ meta)                                                                                                         | 1                             | Proves which branch holds in PostProduc and measures the fixture budget                                                     |
| Modify `force-app/main/default/classes/PricingTestDataFactory.cls`                                                                                                             | 1                             | `createLoad(Graph, Account, Account, rtms__Load__c template)` so leg fields ride the insert                                 |
| Create `force-app/main/default/objects/Intercompany_Carrier__mdt/` (object, `Carrier_Account_Id__c`, `Note__c`)                                                                | 1                             | The admin list of intercompany carrier accounts                                                                             |
| Create `force-app/main/default/objects/Handoff_Point__mdt/` (object, `Place_Key__c`, `Active__c`)                                                                              | 1                             | The admin list of handoff points                                                                                            |
| Create `force-app/main/default/customMetadata/Intercompany_Carrier.Tpml_TP_Org.md-meta.xml`, `Intercompany_Carrier.Lessard_Org.md-meta.xml`                                    | 1                             | The two seeded intercompany accounts (the only place their Ids appear)                                                      |
| Create `force-app/main/default/customMetadata/Handoff_Point.Laredo_TX_US.md-meta.xml`, `Handoff_Point.San_Diego_CA_US.md-meta.xml`, `Handoff_Point.Calexico_CA_US.md-meta.xml` | 1                             | The three seeded handoff points                                                                                             |
| Modify `force-app/main/default/objects/RFP_Lane__c/fields/Cost_Source__c.field-meta.xml`                                                                                       | 1                             | Picklist value `Split` after `Manual`                                                                                       |
| Modify `manifest/package.xml`                                                                                                                                                  | 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 | Every new class, test class, custom metadata type, field, record and LWC bundle                                             |
| Create `force-app/main/default/classes/LaneSearchQueryBuilderTest.cls` (+ meta)                                                                                                | 2, 4                          | Characterization of the search SOQL and binds (Task 2); the new select (Task 4)                                             |
| Create `force-app/main/default/classes/LaneKeyMatcher.cls` (+ meta), `LaneKeyMatcherTest.cls` (+ meta)                                                                         | 2                             | One lane-key condition per end on any load path                                                                             |
| Create `force-app/main/default/classes/LaneLoadFilters.cls` (+ meta)                                                                                                           | 2                             | Mode, equipment and hazmat conditions on any load path                                                                      |
| Modify `force-app/main/default/classes/LaneSearchQueryBuilder.cls`                                                                                                             | 2, 4                          | `addEnd` calls `LaneKeyMatcher` (Task 2); `SELECT_CLAUSE` reads the two warning flags (Task 4)                              |
| Modify `force-app/main/default/classes/LaneSearchFilters.cls`                                                                                                                  | 2                             | `addFilters` calls `LaneLoadFilters.add`                                                                                    |
| Create `force-app/main/default/classes/IntercompanyCarriers.cls` (+ meta), `IntercompanyCarriersTest.cls` (+ meta)                                                             | 3                             | Account Ids from `Intercompany_Carrier__mdt`                                                                                |
| Create `force-app/main/default/classes/HandoffPoints.cls` (+ meta), `HandoffPointsTest.cls` (+ meta)                                                                           | 3                             | Active place keys from `Handoff_Point__mdt`                                                                                 |
| Create `force-app/main/default/classes/ExchangeRates.cls` (+ meta), `ExchangeRatesTest.cls` (+ meta)                                                                           | 3                             | USD dated periods and the CAD → USD conversion per load date                                                                |
| Create `force-app/main/default/classes/CarrierWarning.cls` (+ meta), `CarrierWarningTest.cls` (+ meta)                                                                         | 4                             | The red warning text from the blacklist and claim flags                                                                     |
| Modify `force-app/main/default/classes/LaneSearchService.cls`                                                                                                                  | 4                             | `toRow` sets `carrier.attention` through `CarrierWarning`                                                                   |
| Modify `force-app/main/default/classes/BidSearchQueryBuilder.cls`, `BidSearchService.cls`                                                                                      | 4                             | Bid rows read `Carrier__r.Black_List__c` and get the warning                                                                |
| Modify `force-app/main/default/classes/LaneSearchServiceTest.cls`, `BidSearchServiceTest.cls`                                                                                  | 4                             | The warning on quote and bid rows                                                                                           |
| Create `force-app/main/default/classes/CarrierLeadResult.cls` (+ meta)                                                                                                         | 5                             | Carriers to ask answer: names and counts, never an amount                                                                   |
| Create `force-app/main/default/classes/LaneQueries.cls` (+ meta), `LaneQueriesTest.cls` (+ meta)                                                                               | 5, 9                          | Lane, state lane, quote count and plan SOQL (Task 5); leg conditions and leg load SOQL (Task 9)                             |
| Create `force-app/main/default/classes/CarrierLeadService.cls` (+ meta), `CarrierLeadServiceTest.cls` (+ meta)                                                                 | 5, 6                          | Stage 1 (Task 5) and stage 2 (Task 6)                                                                                       |
| Create `force-app/main/default/classes/CarrierLeadController.cls` (+ meta), `CarrierLeadControllerTest.cls` (+ meta)                                                           | 6                             | `findCarrierLeads`, cacheable, errors as short user messages                                                                |
| Create `force-app/main/default/classes/CarrierSplitSecurityTest.cls` (+ meta)                                                                                                  | 6, 9                          | Account links, restricted users, class access (Task 6); split options for restricted users (Task 9)                         |
| Modify `force-app/main/default/permissionsets/Lane_Benchmark_User.permissionset-meta.xml`, `RFP_Tool_User.permissionset-meta.xml`                                              | 6, 9                          | Class access to `CarrierLeadController` (Task 6) and `SplitLaneController` (Task 9)                                         |
| Create `force-app/main/default/lwc/carrierLeadRules/` (js, meta, `__tests__`)                                                                                                  | 7                             | `hasBothKeys`, `noRate`, `directMedian`                                                                                     |
| Create `force-app/main/default/lwc/carrierLeads/` (html, js, css, meta, `__tests__`)                                                                                           | 7                             | The Carriers to ask card                                                                                                    |
| Modify `force-app/main/default/lwc/rfpLaneTable/rfpLaneTable.js`, `rfpLaneTable.html`, `__tests__/rfpLaneTable.test.js`                                                        | 7                             | The no rate tag in the History cell                                                                                         |
| Modify `force-app/main/default/lwc/laneBenchmark/laneBenchmark.js`, `laneBenchmark.html`, `__tests__/laneBenchmark.test.js`                                                    | 7, 10                         | Carriers to ask under the statistics (Task 7); the split card under the results (Task 10)                                   |
| Modify `force-app/main/default/lwc/rfpLanePanel/rfpLanePanel.js`, `rfpLanePanel.html`, `__tests__/rfpLanePanel.test.js`                                                        | 7, 10                         | History statistics and Carriers to ask (Task 7); the split card, Use as cost and the Split source (Task 10)                 |
| Modify `force-app/main/default/lwc/rfpTool/__tests__/rfpTool.test.js`                                                                                                          | 7, 10                         | Apex mocks for the two new controllers (`rfpTool.js` and `rfpTool.html` untouched)                                          |
| Create `force-app/main/default/classes/SplitLaneResult.cls` (+ meta)                                                                                                           | 8                             | Split options answer: options, legs, leg carriers, medians, rate date                                                       |
| Create `force-app/main/default/classes/SplitLaneService.cls` (+ meta), `SplitLaneServiceTest.cls` (+ meta)                                                                     | 8, 9                          | History groups and USD conversion (Task 8); the estimate call and the no-option message (Task 9)                            |
| Create `force-app/main/default/classes/SplitEstimates.cls` (+ meta), `SplitEstimatesTest.cls` (+ meta)                                                                         | 9                             | Handoff point selection and the two leg reads per point                                                                     |
| Create `force-app/main/default/classes/SplitLaneController.cls` (+ meta), `SplitLaneControllerTest.cls` (+ meta)                                                               | 9                             | `splitOptions`, cacheable, CAD or USD only                                                                                  |
| Create `force-app/main/default/lwc/splitLaneOptions/` (html, js, css, meta, `__tests__`)                                                                                       | 10                            | The Split-lane options card                                                                                                 |
| Modify `force-app/main/default/lwc/rfpPricing/rfpPricing.js`, `__tests__/rfpPricing.test.js`                                                                                   | 10                            | `SPLIT_SOURCE` and `costFor("Split", …)`                                                                                    |
| Modify `force-app/main/default/lwc/rfpWorkbook/rfpWorkbook.js`, `__tests__/rfpWorkbook.test.js`                                                                                | 10                            | The Cost source column after Currency                                                                                       |
| Modify `docs/help/en/lb-stats.md`, `rfp-pricing.md`, `rfp-inline.md`, `rfp-filters-export.md` and the four `docs/help/fr/` twins                                               | 11                            | The guide in English and French                                                                                             |
| Modify `force-app/main/default/staticresources/helpCenter/en/` and `fr/` `lb-stats.html`, `rfp-pricing.html`, `rfp-inline.html`, `rfp-filters-export.html`                     | 11                            | Rebuilt by `npm run help:build`                                                                                             |
| Modify `README.md`                                                                                                                                                             | 11                            | Roster 40 at every site, inventory and security rows, the phase 8 section, known issues                                     |
| Modify `.github/workflows/ci.yml`                                                                                                                                              | 11                            | The CI test roster                                                                                                          |
| Modify `docs/superpowers/specs/2026-09-07-pricing-department-roadmap.md`                                                                                                       | 11                            | Roadmap row 8                                                                                                               |
| Modify `docs/superpowers/specs/2026-09-14-phase-8-carriers-and-split-lanes-design.md`                                                                                          | 11                            | `## 11. Outcome — phase 8`                                                                                                  |

## Rulings carried into the plan

Where a task's code or tests differ from the contract the tasks were drafted against, or settle a point it left open, the ruling is listed here; each task's "Contract notes" give the detail.

1. **Results warning (contract A6).** The text is built by `CarrierWarning.text(blacklisted, underClaim)`, called from `LaneSearchService.toRow` and from `BidSearchService`, so both row kinds share it and `LaneSearchService` keeps its PMD budget; the spec (§6) places the text in `LaneSearchService` (Task 4). The quote fixture inserts a blacklisted carrier instead of updating one, because PostProduc's `Account_BlackList` flow reassigns an account whose flag is turned on; `Lane_Benchmark_User` keeps its unused read on `Carrier_Att__c` (no other permission change this phase).
2. **Fixture budget over "fixture DML before `Test.startTest()`".** A split shipment is three loads and three loads in one governor context reach 101 queries, so a test holds one split shipment at most: at most one load before `Test.startTest()` (always the one a `Test.setCreatedDate` needs) and the rest inside it, with each scenario in its own test method (Tasks 1, 4, 5, 6, 8, 9). Each task gives the fallback for a 101.
3. **Task 1 measures through a probe deploy** (no trace flag in PostProduc): the budget test ends on `System.assert(false, budget)` until Step 9 removes it, and its message also reports the query room left in the outer context. The measured numbers go to the Task 1 report, not into Apex comments. `PricingTestDataFactory` gains `createLoad(Graph, Account, Account, rtms__Load__c template)` so leg fields ride the insert (not in the contract's Task 1 file list). `resetPlans()` always sets `FreightPlanReader.rowsOverride` to null. The decision test also asserts that the automation gives a leg load no carrier quote; if it does, Task 1 stops for an owner ruling.
4. **Legs off the customer lane.** Carriers to ask tests build split legs to a yard off the customer lane (Task 5: Kingston, ON; Task 6 stage 2: Drummondville, QC, off QC:ON), as real legs are, so no quote the automation might give a leg reaches the quote counts.
5. **Request defaults.** `CarrierLeadService.find` (Tasks 5 and 6) and `SplitLaneService.options` (Task 8) call `req.applyDefaults()`, not `validate()`: both cards ignore the lookback, radius and request currency (R101), and the first search has already validated the same request. A ZIP3 end without a postal prefix still throws from `LaneKeyMatcher`.
6. **`LaneKeyMatcher`** (Task 2): the precision parameter is named `endPrecision` (a parameter named `precision` hides the enum); an explicit ZIP3 prefix counts only on a ZIP3 end; the missing-prefix message reads `place.Key__c`, so callers select `Key__c`; a null precision reads as CITY; `condition` returns null when an end has no constraint, and every caller adds only non-null conditions. `BidSearchQueryBuilder` is not switched to it.
7. **Readers** (Task 3): in-memory custom metadata rows are built with `JSON.deserialize`; parse helpers `parseIds` and `parseKeys`; overrides are returned as copies; `ExchangeRates.usd` reads `WITH SYSTEM_MODE` (restricted pricers may lack read on `DatedConversionRate`); `fromCad` also returns null for a null date; the period lookup takes the latest start on or before the day, else the first period; `ExchangeRates.Period` is always written qualified.
8. **Carriers to ask stage 1** (Task 5): a missing place returns stage `None` (the search would throw); the plan read uses a copy of the lane binds; `quoteCountSoql`'s first parameter is named `onLane`; `@TestVisible rowReserve = 5000` is the guard's test hook and the guard also runs before the Account read; ranking lives in `@TestVisible ranked(leads, byQuoted)` with an inner `LeadOrder`, and Task 6's whole-file service keeps `find`, `ranked` and `rowReserve` for Task 5's tests; names compare ignoring case; a leg load that also has an accepted quote by the same carrier counts twice in loads moved (contract sum); the user-mode Account read catches an exception and then opens no link.
9. **Carriers to ask stage 2 and controller** (Task 6): `@TestVisible` seams `stateLaneLeads` and `stateLane`, because branch B's plan hook answers every plan read; `stateLaneLabel` is set only when stage 2 names a carrier; a stage 1 `truncated` carries into stage 2; stage 2 does not run after the row guard stopped stage 1; the stop-country test uses NL (Newfoundland and Nuevo León); `CarrierLeadController` is `with sharing`, refuses a request that deserializes to null, and copies `LaneBenchmarkController`'s messages. A 51st carrier group marks only stage 1 incomplete (stage 1 shows every carrier it finds, R97); stage 2 is marked incomplete only by its 500-plan cap or the query-row guard, because its grouped counts come back ordered by loads, so its top 10 is exact (controller ruling 2026-09-15; cost if wrong: on a busy state lane a carrier whose split legs would lift it into the top 10 can be missed without the note). Tally keeps the cap in `groupCapped` and `finish` reads it only when `top` is null.
10. **Carriers to ask card** (Task 7): `leads-heading` shows for a same-lane answer, `leads-stage2` for a state-lane answer, `leads-empty` when there is no lead; a null `lastSeen` reads "last seen —"; the account link opens a new tab; the error shows the Apex message or "The carriers to ask could not be loaded."; a blank `requestJson` clears the card; the no rate tag is `slds-badge slds-m-left_xx-small` and the Blacklisted badge `slds-badge slds-theme_error slds-m-left_x-small`; no help hint on the card. A Lane Benchmark test proves the statistics and results stay when Carriers to ask fails (spec §8).
11. **Split history** (Task 8): `SplitLaneService` adds the public inner class `LegRow`, `@TestVisible groupHistory(...)` and `@TestVisible historySoql(...)`, so grouping is tested in memory and the lane and date filters on the SOQL text; the group key is the leg count plus the lowercased label, and blank label parts are dropped; sums stay unrounded and the median rounds once; the `→` and `·` separators are literal UTF-8; inner classes call outer helpers qualified and sort with `Comparable` wrappers.
12. **Split estimates and controller** (Task 9): `SplitLaneController` is `with sharing`, compares the currency with `'CAD'.equals` (so `usd` is refused), and refuses unreadable and null requests through two helpers; `SplitEstimates` holds `@TestVisible` constants `MAX_EXTRA`, `MAX_POINTS`, `LEG_DAYS`, `LEG_LIMIT`; `LaneQueries.legConditions` returns null when an end cannot be matched; the 365-day window and the positive-total rule are proven on the SOQL text; point-selection tests add Little Rock, St. Louis and Chicago through `HandoffPoints.keysOverride`; the Step 9 call site is an exact replacement of Task 8's last two `options` lines; Task 8's null-message assertion becomes `NO_OPTION_MESSAGE` in Task 9 Step 5; class access to `SplitLaneController` is checked by its own test, `bothPermissionSetsOpenTheSplitController`, beside Task 6's `bothPermissionSetsGrantThePhaseEightControllers`.
13. **Split card and Split cost** (Task 10): `requestJson` is a getter/setter that closes the card and forgets kept answers for a new request; `splitCost` resets in `syncPricing`; any `startCurrency` but `USD` opens in CAD; a leg with no carrier reads "no carrier found" (text not in the spec or contract); `use-as-cost-off` is one note per card and `direct-median` shows in each option; the `leg-blacklisted` badge uses Task 7's classes (R94); `rfpWorkbook`'s `cell()` only blanks null values (it is not a formula guard; the new cell holds picklist values only).
14. **Docs and final deploy** (Task 11): the roster has five sites (the README `sf apex run test -n …` line too); the guide keeps English UI names in French headings; the results warning is documented in the README only (no guide page mentions it); the README tells admins to edit both lists in Setup and in the repo, because full-manifest deploys overwrite the records; the Outcome records as difference 6 that intercompany carriers are removed in SOQL from quote counts and estimate leg reads but from freight-plan legs in Apex (§3 says "by the queries themselves"; R87 needs the whole shipment skipped).

15. **Market Test exclusion (phase 7 change, owner 2026-09-15).** Phase 7 dropped Lane Benchmark's "Market test only" filter and removed `LaneSearchRequest.marketTestOnly`; every lane search now adds `(NOT Customer_Name__c LIKE :marketTest)` between hazmat and the accepted filter. Task 2's characterization test therefore expects that condition and the `marketTest` bind on every case (its drafting note about replaying the old builder predates this), and `LaneSearchFilters` measures 17 before the extraction and 7 after. `LaneQueries.quoteCountSoql` (Task 5) adds the same condition, because the owner asked for Market Test quotes to be left out of Carriers to ask as well (spec R110); split history and estimates read loads, and Market Test loads carry no lane keys, so they need nothing. Task 11's scope checks compare against `b847aec` (phase 7 merged with this change) instead of `44081a7`.

---

<!-- prettier-ignore-start -->

### Task 1: Revenova test data and metadata — freight plan fixtures, intercompany carriers, handoff points, the Split cost source

**Files:**

- Create: `force-app/main/default/classes/FreightPlanReader.cls`, `force-app/main/default/classes/FreightPlanReader.cls-meta.xml`
- Create: `force-app/main/default/classes/SplitTestData.cls`, `force-app/main/default/classes/SplitTestData.cls-meta.xml`
- Create: `force-app/main/default/classes/SplitTestDataTest.cls`, `force-app/main/default/classes/SplitTestDataTest.cls-meta.xml`
- Modify: `force-app/main/default/classes/PricingTestDataFactory.cls` (the private 7-argument `createLoad` takes a load template instead of `Decimal miles`; a new public overload `createLoad(Graph, Account, Account, rtms__Load__c template)`; the phase 7 miles overload passes its miles through a template; behaviour of every existing overload unchanged)
- Create: `force-app/main/default/objects/Intercompany_Carrier__mdt/Intercompany_Carrier__mdt.object-meta.xml`, `force-app/main/default/objects/Intercompany_Carrier__mdt/fields/Carrier_Account_Id__c.field-meta.xml`, `force-app/main/default/objects/Intercompany_Carrier__mdt/fields/Note__c.field-meta.xml`
- Create: `force-app/main/default/objects/Handoff_Point__mdt/Handoff_Point__mdt.object-meta.xml`, `force-app/main/default/objects/Handoff_Point__mdt/fields/Place_Key__c.field-meta.xml`, `force-app/main/default/objects/Handoff_Point__mdt/fields/Active__c.field-meta.xml`
- Create: `force-app/main/default/customMetadata/Intercompany_Carrier.Tpml_TP_Org.md-meta.xml`, `force-app/main/default/customMetadata/Intercompany_Carrier.Lessard_Org.md-meta.xml`
- Create: `force-app/main/default/customMetadata/Handoff_Point.Laredo_TX_US.md-meta.xml`, `force-app/main/default/customMetadata/Handoff_Point.San_Diego_CA_US.md-meta.xml`, `force-app/main/default/customMetadata/Handoff_Point.Calexico_CA_US.md-meta.xml`
- Modify: `force-app/main/default/objects/RFP_Lane__c/fields/Cost_Source__c.field-meta.xml` (value `Split` after `Manual`)
- Modify: `manifest/package.xml` (ApexClass `FreightPlanReader`, `SplitTestData`, `SplitTestDataTest` after `TripRouteView`; CustomObject `Intercompany_Carrier__mdt`, `Handoff_Point__mdt` after `Truck_Routing_Setting__mdt`; CustomMetadata the five records after `Truck_Routing_Setting.Default`; CustomField the four new fields after `Truck_Routing_Setting__mdt.Width_M__c`). Every anchor below is found by its text, never by a line number.

**Interfaces:**

- Consumes:
  - `PricingTestDataFactory.Graph` (`customer`, `vendor`, `originLocation` Montreal QC, `destinationLocation` Toronto ON, `mode`, `equipment`), `PricingTestDataFactory.createGraph()`, `createLoad(Graph, Account, Account)` (lane keys `Montreal, QC:Toronto, ON`, `QC:ON`, `A1A:A1A`), `createLocation(name, city, province, country, postalCode, lat, lng)` and the class doc's governor budget (one `createLoad` fits before `Test.startTest()` after `createGraph`, two fit inside it; `LaneSearchServiceTest.hazmatAcceptedAndExcludedContactFiltersNeverReturnMarketTestQuotes` records that three inside one block overflow).
  - Revenova objects, verified in PostProduc 2026-09-15: `rtms__FreightPlan__c` (no required custom field, `Name` auto number, `Freight_Plan_Cost__c` roll-up; managed trigger `rtms.FreightPlan` active), `rtms__FreightPlanLoad__c` (`rtms__Freight_Plan__c` and `rtms__Load__c` Master-Detail, `rtms__Number__c` Number(3,0), `rtms__Type__c` picklist `Customer`/`Carrier`; the org trigger `FreightPlanLoadTrigger` is Inactive), `rtms__Load__c.rtms__Carrier__c` Lookup(Account), `rtms__Carrier_Quote_Total__c` Currency(16,2), `rtms__Load_Status__c` picklist (none a formula; `rtms__In_Freight_Plan__c` is a formula), `Account.Black_List__c` Checkbox.
  - The child relationship `rtms__Freight_Plan_Loads__r` and the verified parent-child plan query (contract "VERIFIED IN POSTPRODUC").
- Produces (every later task relies on these exact names):
  - `public without sharing class FreightPlanReader` — `@TestVisible private static List<rtms__FreightPlan__c> rowsOverride;` and `public static List<rtms__FreightPlan__c> read(String soql, Map<String, Object> binds)` (returns `rowsOverride` when it is not null, else `Database.queryWithBinds(soql, binds, AccessLevel.SYSTEM_MODE)`).
  - `@IsTest public class SplitTestData`:
    - `public static Account carrier(String name, Boolean blacklisted)` — inserted Carrier account (record type `Carrier`, TMS type `Carrier (Ground)`, CAD, `Black_List__c` = blacklisted).
    - `public static rtms__Load__c legLoad(PricingTestDataFactory.Graph g, Account origin, Account destination, Account carrierAccount, Decimal cadTotal, String status)` — an inserted load with stops and lane keys from the factory and `rtms__Carrier__c`, `rtms__Carrier_Quote_Total__c`, `rtms__Load_Status__c` set (at insert, or by one follow-up update when Step 8 proves insert values do not stick).
    - `public static rtms__FreightPlan__c plan(rtms__Load__c customerLoad, List<rtms__Load__c> legLoads)` — branch A inserts the plan, the Customer row (Number 1) and the Carrier rows (Number 2, 3, …); branch B builds the parent-child row in memory and appends it to `FreightPlanReader.rowsOverride`. Which branch holds is written in the class comment by Step 9.
    - `public static void resetPlans()` — sets `FreightPlanReader.rowsOverride` to null (harmless in branch A, where nothing sets it).
  - `PricingTestDataFactory.createLoad(Graph g, Account origin, Account destination, rtms__Load__c template)` — copies every populated template field onto the load before insert.
  - `Intercompany_Carrier__mdt` (Public): `Carrier_Account_Id__c` Text(18), `Note__c` Text(255); records `Tpml_TP_Org`, `Lessard_Org`.
  - `Handoff_Point__mdt` (Public): `Place_Key__c` Text(120), `Active__c` Checkbox default true; records `Laredo_TX_US`, `San_Diego_CA_US`, `Calexico_CA_US`.
  - `RFP_Lane__c.Cost_Source__c` values `Bid`, `History median`, `Manual`, `Split`.
  - The measured fixture budget (queries and DML per `legLoad` and per `plan`) in the `SplitTestData` class comment, which Tasks 5, 6, 8 and 9 size their tests by.

- [ ] **Step 1: Print the baseline and confirm the org has none of this yet (the failing check)**

Run:

```bash
cd /Users/iulian/Documents/Personal/PricingDepartemnt-phase8
git log --oneline -1
ls force-app/main/default/classes/*Test.cls | wc -l
sf data query -o sandbox -q "SELECT Name FROM ApexClass WHERE Name IN ('FreightPlanReader','SplitTestData','SplitTestDataTest')" -r human 2>&1 | grep -v Warning | tail -2
sf data query -o sandbox -q "SELECT QualifiedApiName FROM EntityDefinition WHERE QualifiedApiName IN ('Intercompany_Carrier__mdt','Handoff_Point__mdt')" -r human 2>&1 | grep -v Warning | tail -2
sf data query -o sandbox -q "SELECT Value, IsActive FROM PicklistValueInfo WHERE EntityParticle.EntityDefinition.QualifiedApiName = 'RFP_Lane__c' AND EntityParticle.QualifiedApiName = 'Cost_Source__c'" -r human 2>&1 | grep -v Warning
sf data query -o sandbox -q "SELECT Key__c, City__c, Province__c, Country__c, Geolocation__Latitude__s, Geolocation__Longitude__s FROM Pricing_Place__c WHERE Key__c IN ('laredo|tx|us','san diego|ca|us','calexico|ca|us') ORDER BY Key__c" -r human 2>&1 | grep -v Warning
sf data query -o sandbox -q "SELECT Id, Name, rtms__TMS_Type__c FROM Account WHERE Id IN ('0011N00001JcHnvQAF','0011N00001JbQ7EQAV') ORDER BY Name" -r human 2>&1 | grep -v Warning
```

Expected (observed while planning, 2026-09-15):

- a commit at or after `44081a7` on `phase-8/carriers-and-split-lanes`, and `26` test classes. Print both numbers into the task report; later counts are measured from them, not from this plan.
- `Total number of records retrieved: 0.` for the ApexClass and EntityDefinition queries. If either returns rows, stop and report: something was deployed outside this plan.
- `Cost_Source__c`: 3 rows `Bid`, `History median`, `Manual`, all active.
- 3 places: `calexico|ca|us | Calexico | CA | US | 32.683461 | -115.421826`, `laredo|tx|us | Laredo | TX | US | 27.618453 | -99.509907`, `san diego|ca|us | San Diego | CA | US | 32.662087 | -117.035038`. A missing key means a Handoff Point record would point at no place: stop and report.
- 2 accounts: `0011N00001JbQ7EQAV | TRANS-PRO LOGISTIQUE - TPML- LESSARD ORG | Carrier (Ground)` and `0011N00001JcHnvQAF | Tpml (Trans-Pro Logistics)-TP org | Carrier (Ground)`.

- [ ] **Step 2: Write the failing test**

Create `force-app/main/default/classes/SplitTestDataTest.cls`:

```apex
/**
 * Proves the phase 8 split fixtures in PostProduc: leg loads keep their carrier, CAD carrier total and
 * status; a plan built by SplitTestData.plan comes back through FreightPlanReader with the Customer
 * row first and the Carrier rows in rtms__Number__c order; and one split shipment leaves query room
 * for the code under test. PLAN_SOQL is the parent-child query verified in PostProduc on 2026-09-15,
 * written out by hand because LaneQueries.planSoql arrives in Task 5.
 */
@IsTest
private class SplitTestDataTest {
  private static final String PLAN_SOQL =
    'SELECT Id, (SELECT rtms__Number__c, rtms__Type__c, rtms__Load__c, rtms__Load__r.CreatedDate, ' +
    'rtms__Load__r.rtms__Carrier__c, rtms__Load__r.rtms__Carrier__r.Name, ' +
    'rtms__Load__r.rtms__Carrier__r.Black_List__c, rtms__Load__r.rtms__City_Lane__c, ' +
    'rtms__Load__r.rtms__Load_Status__c, rtms__Load__r.rtms__Carrier_Quote_Total__c, ' +
    'rtms__Load__r.rtms__Last_Stop__r.rtms__Location2__r.Name ' +
    'FROM rtms__Freight_Plan_Loads__r ORDER BY rtms__Number__c) ' +
    'FROM rtms__FreightPlan__c WHERE Id IN (SELECT rtms__Freight_Plan__c FROM rtms__FreightPlanLoad__c ' +
    'WHERE rtms__Type__c = \'Customer\' AND rtms__Load__r.rtms__City_Lane__c LIKE :oCity ' +
    'AND rtms__Load__r.CreatedDate = LAST_N_DAYS:365 ' +
    'AND rtms__Load__r.rtms__Load_Status__c != \'Cancelled\') LIMIT 10';

  private class Fixture {
    PricingTestDataFactory.Graph g;
    Account yard;
    Account blacklisted;
    rtms__Load__c customerLoad;
  }

  /**
   * Everything that runs before Test.startTest(): the graph (Montreal QC -> Toronto ON), the Kingston
   * yard where leg 1 ends, one blacklisted carrier and the customer load, which is the one createLoad
   * the factory's class doc lets run before Test.startTest().
   */
  private static Fixture fixture() {
    Fixture f = new Fixture();
    f.g = PricingTestDataFactory.createGraph();
    f.yard = PricingTestDataFactory.createLocation(
      'Kingston Yard',
      'Kingston',
      'Ontario',
      'Canada',
      'K7K 1A1',
      44.2312,
      -76.486
    );
    f.blacklisted = SplitTestData.carrier('Blacklisted Leg Carrier', true);
    f.customerLoad = PricingTestDataFactory.createLoad(
      f.g,
      f.g.originLocation,
      f.g.destinationLocation
    );
    return f;
  }

  private static String spent(Integer queriesBefore, Integer dmlBefore) {
    return (Limits.getQueries() - queriesBefore) +
      ' queries / ' +
      (Limits.getDmlStatements() - dmlBefore) +
      ' DML';
  }

  @IsTest
  static void planRowsKeepLegOrderCarrierTotalAndStatus() {
    Fixture f = fixture();
    Test.startTest();
    rtms__Load__c leg1 = SplitTestData.legLoad(
      f.g,
      f.g.originLocation,
      f.yard,
      f.g.vendor,
      1250.00,
      'Delivered'
    );
    rtms__Load__c leg2 = SplitTestData.legLoad(
      f.g,
      f.yard,
      f.g.destinationLocation,
      f.blacklisted,
      980.50,
      'Cancelled'
    );
    SplitTestData.plan(f.customerLoad, new List<rtms__Load__c>{ leg1, leg2 });
    Test.stopTest();

    List<Id> legIds = new List<Id>{ leg1.Id, leg2.Id };
    Map<Id, rtms__Load__c> stored = new Map<Id, rtms__Load__c>(
      [
        SELECT
          rtms__Carrier__c,
          rtms__Carrier_Quote_Total__c,
          rtms__Load_Status__c
        FROM rtms__Load__c
        WHERE Id IN :legIds
      ]
    );
    System.assertEquals(
      0,
      [
        SELECT COUNT()
        FROM rtms__CarrierQuote__c
        WHERE rtms__Load__c IN :legIds
      ],
      'a leg load gets no carrier quote from the automation, so leg fixtures never reach the quote counts'
    );
    System.assertEquals(
      f.g.vendor.Id,
      stored.get(leg1.Id).rtms__Carrier__c,
      'leg 1 keeps its carrier'
    );
    System.assertEquals(
      1250.00,
      stored.get(leg1.Id).rtms__Carrier_Quote_Total__c,
      'leg 1 keeps its CAD carrier total'
    );
    System.assertEquals(
      'Delivered',
      stored.get(leg1.Id).rtms__Load_Status__c,
      'leg 1 keeps its status'
    );
    System.assertEquals(
      f.blacklisted.Id,
      stored.get(leg2.Id).rtms__Carrier__c,
      'leg 2 keeps its carrier'
    );
    System.assertEquals(
      980.50,
      stored.get(leg2.Id).rtms__Carrier_Quote_Total__c,
      'leg 2 keeps its CAD carrier total'
    );
    System.assertEquals(
      'Cancelled',
      stored.get(leg2.Id).rtms__Load_Status__c,
      'leg 2 keeps its status'
    );

    List<rtms__FreightPlan__c> plans = FreightPlanReader.read(
      PLAN_SOQL,
      new Map<String, Object>{ 'oCity' => 'Montreal, QC:%' }
    );
    System.assertEquals(
      1,
      plans.size(),
      'one plan whose customer load is on the lane'
    );
    List<rtms__FreightPlanLoad__c> rows = new List<rtms__FreightPlanLoad__c>();
    for (rtms__FreightPlanLoad__c row : plans[0].rtms__Freight_Plan_Loads__r) {
      rows.add(row);
    }
    System.assertEquals(
      3,
      rows.size(),
      'the customer row and two carrier rows'
    );

    System.assertEquals(1, rows[0].rtms__Number__c, 'customer row first');
    System.assertEquals('Customer', rows[0].rtms__Type__c);
    System.assertEquals(f.customerLoad.Id, rows[0].rtms__Load__c);
    System.assertEquals(
      null,
      rows[0].rtms__Load__r.rtms__Carrier__c,
      'the customer load has no carrier'
    );
    System.assertEquals(
      'Montreal, QC:Toronto, ON',
      rows[0].rtms__Load__r.rtms__City_Lane__c
    );

    System.assertEquals(2, rows[1].rtms__Number__c, 'leg 1 second');
    System.assertEquals('Carrier', rows[1].rtms__Type__c);
    System.assertEquals(leg1.Id, rows[1].rtms__Load__c);
    System.assertEquals(f.g.vendor.Id, rows[1].rtms__Load__r.rtms__Carrier__c);
    System.assertEquals(
      'Test Carrier',
      rows[1].rtms__Load__r.rtms__Carrier__r.Name
    );
    System.assertEquals(
      false,
      rows[1].rtms__Load__r.rtms__Carrier__r.Black_List__c
    );
    System.assertEquals(
      1250.00,
      rows[1].rtms__Load__r.rtms__Carrier_Quote_Total__c
    );
    System.assertEquals(
      'Delivered',
      rows[1].rtms__Load__r.rtms__Load_Status__c
    );
    System.assertEquals(
      'Montreal, QC:Kingston, ON',
      rows[1].rtms__Load__r.rtms__City_Lane__c
    );
    System.assertEquals(
      'Kingston Yard',
      rows[1].rtms__Load__r.rtms__Last_Stop__r.rtms__Location2__r.Name,
      'the handoff yard is the last stop account of leg 1'
    );

    System.assertEquals(3, rows[2].rtms__Number__c, 'leg 2 third');
    System.assertEquals('Carrier', rows[2].rtms__Type__c);
    System.assertEquals(leg2.Id, rows[2].rtms__Load__c);
    System.assertEquals(
      f.blacklisted.Id,
      rows[2].rtms__Load__r.rtms__Carrier__c
    );
    System.assertEquals(
      'Blacklisted Leg Carrier',
      rows[2].rtms__Load__r.rtms__Carrier__r.Name
    );
    System.assertEquals(
      true,
      rows[2].rtms__Load__r.rtms__Carrier__r.Black_List__c
    );
    System.assertEquals(
      980.50,
      rows[2].rtms__Load__r.rtms__Carrier_Quote_Total__c
    );
    System.assertEquals(
      'Cancelled',
      rows[2].rtms__Load__r.rtms__Load_Status__c
    );
    System.assertEquals(
      'Kingston, ON:Toronto, ON',
      rows[2].rtms__Load__r.rtms__City_Lane__c
    );
    System.assertEquals(
      'Destination Co',
      rows[2].rtms__Load__r.rtms__Last_Stop__r.rtms__Location2__r.Name
    );
  }

  @IsTest
  static void oneSplitShipmentLeavesQueryRoomForTheCodeUnderTest() {
    Fixture f = fixture();
    Integer outerQueries = Limits.getQueries();
    String budget =
      'SplitTestData budget: before Test.startTest ' +
      outerQueries +
      ' queries / ' +
      Limits.getDmlStatements() +
      ' DML';
    Test.startTest();
    Integer queriesBefore = Limits.getQueries();
    Integer dmlBefore = Limits.getDmlStatements();
    rtms__Load__c leg1 = SplitTestData.legLoad(
      f.g,
      f.g.originLocation,
      f.yard,
      f.g.vendor,
      1250.00,
      'Delivered'
    );
    budget += '; legLoad 1 ' + spent(queriesBefore, dmlBefore);
    queriesBefore = Limits.getQueries();
    dmlBefore = Limits.getDmlStatements();
    rtms__Load__c leg2 = SplitTestData.legLoad(
      f.g,
      f.yard,
      f.g.destinationLocation,
      f.blacklisted,
      980.50,
      'Cancelled'
    );
    budget += '; legLoad 2 ' + spent(queriesBefore, dmlBefore);
    queriesBefore = Limits.getQueries();
    dmlBefore = Limits.getDmlStatements();
    SplitTestData.plan(f.customerLoad, new List<rtms__Load__c>{ leg1, leg2 });
    budget += '; plan ' + spent(queriesBefore, dmlBefore);
    Integer roomLeft = Limits.getLimitQueries() - Limits.getQueries();
    budget +=
      '; left inside Test.startTest ' +
      roomLeft +
      ' queries / ' +
      (Limits.getLimitDmlStatements() - Limits.getDmlStatements()) +
      ' DML';
    budget +=
      '; outer context after the fixture ' +
      (Limits.getLimitQueries() - outerQueries) +
      ' queries left';
    System.debug(LoggingLevel.INFO, budget);
    Test.stopTest();
    System.assert(
      roomLeft >= 20,
      'one split shipment must leave 20 queries for the code under test: ' +
      budget
    );
    System.assert(false, budget); // PROBE: Task 1 Step 9 deletes this line
  }

  @IsTest
  static void readReturnsTheOverrideWithoutAQueryAndResetClearsIt() {
    FreightPlanReader.rowsOverride = new List<rtms__FreightPlan__c>{
      new rtms__FreightPlan__c()
    };
    Map<String, Object> binds = new Map<String, Object>{ 'none' => null };
    Integer queriesBefore = Limits.getQueries();
    List<rtms__FreightPlan__c> rows = FreightPlanReader.read(
      'SELECT Id FROM rtms__FreightPlan__c WHERE Id = :none',
      binds
    );
    System.assertEquals(
      queriesBefore,
      Limits.getQueries(),
      'the override answers without a query'
    );
    System.assert(
      rows === FreightPlanReader.rowsOverride,
      'read returns the override list itself'
    );
    SplitTestData.resetPlans();
    System.assertEquals(
      null,
      FreightPlanReader.rowsOverride,
      'resetPlans clears the override'
    );
    System.assertEquals(
      0,
      FreightPlanReader.read(
          'SELECT Id FROM rtms__FreightPlan__c WHERE Id = :none',
          binds
        )
        .size(),
      'after the reset the reader queries again'
    );
    System.assertEquals(
      queriesBefore + 1,
      Limits.getQueries(),
      'one query after the reset'
    );
  }
}
```

Create `force-app/main/default/classes/SplitTestDataTest.cls-meta.xml`:

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<ApexClass xmlns="http://soap.sforce.com/2006/04/metadata">
    <apiVersion>64.0</apiVersion>
    <status>Active</status>
</ApexClass>
```

What the three tests prove:

- `planRowsKeepLegOrderCarrierTotalAndStatus` is the branch decision. Leg 1 is Montreal QC to the Kingston yard, carrier the graph's vendor, 1,250.00 CAD, `Delivered`. Leg 2 is the yard to Toronto ON, a blacklisted carrier, 980.50 CAD, `Cancelled`. It re-reads both leg loads straight from `rtms__Load__c`, which proves the three fields stick whatever the plan branch is. It then reads the plan through `FreightPlanReader.read` with the verified parent-child query: 3 child rows in `rtms__Number__c` order, the Customer row first, each leg with its carrier, blacklist flag, total, status, city lane and last stop account.
- `oneSplitShipmentLeavesQueryRoomForTheCodeUnderTest` measures `Limits.getQueries()` and `Limits.getDmlStatements()` before `Test.startTest()`, per `legLoad` and per `plan`. It writes them in one `System.debug` line, keeps 20 queries of room for the service a later test calls, and ends on a deliberate `System.assert(false, budget)` probe. The org has no active trace flag, so a debug line cannot be read back from a deploy; the probe's failure message carries the same line, and a deploy with a failing test saves nothing. Step 9 deletes the probe.
- `readReturnsTheOverrideWithoutAQueryAndResetClearsIt` covers `FreightPlanReader`'s override path (without it, branch A would leave the class at 2 of 3 lines) and `resetPlans`.

The customer load is created before `Test.startTest()` and both legs and the plan inside it, following `PricingTestDataFactory`'s class doc: after `createGraph()`, one `createLoad` fits the un-reset budget and two more fit the fresh one (`LaneSearchServiceTest.hazmatAcceptedAndExcludedContactFiltersNeverReturnMarketTestQuotes` records three in one block hitting 101 queries).

- [ ] **Step 3: Deploy the test alone to see it fail to compile**

Run:

```bash
cd /Users/iulian/Documents/Personal/PricingDepartemnt-phase8
sf project deploy start -o sandbox --source-dir force-app/main/default/classes/SplitTestDataTest.cls -l NoTestRun --async --json | python3 -c "import json,sys; s=sys.stdin.read(); r=json.loads(s[s.index('{'):]); print((r.get('result') or {}).get('id'), (r.get('result') or {}).get('status'), r.get('message') or '')"
```

Expected: a deploy id (`0Af...`) and `Queued` or `InProgress`. Poll it, repeating until the first word is `Succeeded` or `Failed`. `Queued`, `Pending`, `InProgress` or a client-timeout error name means run it again; each call returns within about 2 minutes:

```bash
sf project deploy report -o sandbox --job-id <id> -w 2 --json | python3 -c "import json,sys; s=sys.stdin.read(); r=json.loads(s[s.index('{'):]); x=r.get('result') or {}; d=x.get('details') or {}; L=lambda v: [v] if isinstance(v, dict) else (v or []); print(x.get('status', r.get('name')), 'tests', x.get('numberTestsCompleted'), '/', x.get('numberTestsTotal'), 'failures', x.get('numberTestErrors')); [print('COMPILE', f.get('fullName'), f.get('lineNumber'), f.get('problem')) for f in L(d.get('componentFailures'))]; [print(f['name'], f['methodName'], '->', f['message'][:700], '|', (f.get('stackTrace') or '')[:300]) for f in L((d.get('runTestResult') or {}).get('failures'))]"
```

Expected: `Failed`, with `COMPILE SplitTestDataTest` lines naming the missing code: `Invalid type: SplitTestData`, `Variable does not exist: SplitTestData` or `Variable does not exist: FreightPlanReader`. Nothing is saved. A problem naming `PricingTestDataFactory.createLocation`, `rtms__FreightPlan__c` or `rtms__Freight_Plan_Loads__r` is a real error in the test: fix the test and run this step again.

- [ ] **Step 4: Let `PricingTestDataFactory.createLoad` take a load template**

The factory keeps its full `createLoad` private, so a leg's carrier, total and status can only ride the insert through a new overload. Phase 7 set the same precedent for `rtms__Distance_Miles__c`: a second Load DML would cost the governor budget in the class doc.

In `force-app/main/default/classes/PricingTestDataFactory.cls`:

(a) In the phase 7 miles overload (`createLoad(Graph g, Account origin, Account destination, Decimal miles)`), replace its body line

```apex
    return createLoad(g, origin, destination, false, g.customer, g.mode, miles);
  }
```

with the body below, followed by the new overload:

```apex
    return createLoad(
      g,
      origin,
      destination,
      false,
      g.customer,
      g.mode,
      new rtms__Load__c(rtms__Distance_Miles__c = miles)
    );
  }

  /**
   * Phase 8: copies every field set on template onto the load before insert (a split leg's
   * rtms__Carrier__c, rtms__Carrier_Quote_Total__c and rtms__Load_Status__c, see SplitTestData.legLoad),
   * so the values ride the insert instead of a second Load DML (the governor budget in the class
   * doc). Customer, mode, equipment, lane keys and stops stay the factory's.
   */
  public static rtms__Load__c createLoad(
    Graph g,
    Account origin,
    Account destination,
    rtms__Load__c template
  ) {
    return createLoad(
      g,
      origin,
      destination,
      false,
      g.customer,
      g.mode,
      template
    );
  }
```

(b) In the private 7-argument `createLoad` (the one whose last parameter is `Decimal miles`), replace

```apex
    rtms__Mode__c mode,
    Decimal miles
  ) {
    rtms__Load__c load = newLoad(g, customer, mode, hazmat);
    load.rtms__Distance_Miles__c = miles;
```

with

```apex
    rtms__Mode__c mode,
    rtms__Load__c template
  ) {
    rtms__Load__c load = newLoad(g, customer, mode, hazmat);
    if (template != null) {
      Map<String, Object> preset = template.getPopulatedFieldsAsMap();
      for (String field : preset.keySet()) {
        load.put(field, preset.get(field));
      }
    }
```

The three other callers of the private method already pass `null` as the last argument, which now means "no template"; they do not change. Check:

```bash
cd /Users/iulian/Documents/Personal/PricingDepartemnt-phase8
grep -c "Decimal miles" force-app/main/default/classes/PricingTestDataFactory.cls
grep -c "rtms__Load__c template" force-app/main/default/classes/PricingTestDataFactory.cls
grep -rn "createLoad(" force-app/main/default/classes --include='*.cls' | grep -v "PricingTestDataFactory.cls" | wc -l
```

Expected: `1` (was `2`: only the public miles overload keeps the parameter now), `2` (the new overload and the private method), and `31` calls outside the factory (counted on 2026-09-15 before the edit; none of them changes).

- [ ] **Step 5: Write `FreightPlanReader`**

Create `force-app/main/default/classes/FreightPlanReader.cls`:

```apex
/**
 * Reads Revenova freight plans with their junction rows (rtms__Freight_Plan_Loads__r) for Carriers to
 * ask (CarrierLeadService) and Split-lane options (SplitLaneService). Both services read plans only
 * through this class, so a test can hand them plan rows through rowsOverride when Revenova's managed
 * code refuses test inserts (see SplitTestData's class comment for the branch that holds). Callers
 * iterate the child rows with a for loop: reading a child list of more than 200 rows directly throws.
 */
// Runs without sharing on purpose, like LaneSearchService: loads inherit Private sharing and pricing reads every team's split shipments. Access is gated by the Lane Benchmark and RFP Tool permission sets.
public without sharing class FreightPlanReader {
  // Test hook: tests set this (through SplitTestData) because freight plans may not be insertable in tests.
  @TestVisible
  private static List<rtms__FreightPlan__c> rowsOverride;

  /** The plans soql selects, in system mode; the override instead when a test set one. */
  @SuppressWarnings(
    'PMD.ApexCRUDViolation'
  ) // system mode by design (see class comment); Database.queryWithBinds also counts as CRUD for PMD
  public static List<rtms__FreightPlan__c> read(
    String soql,
    Map<String, Object> binds
  ) {
    if (rowsOverride != null) {
      return rowsOverride;
    }
    return Database.queryWithBinds(soql, binds, AccessLevel.SYSTEM_MODE);
  }
}
```

Create `force-app/main/default/classes/FreightPlanReader.cls-meta.xml`:

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<ApexClass xmlns="http://soap.sforce.com/2006/04/metadata">
    <apiVersion>64.0</apiVersion>
    <status>Active</status>
</ApexClass>
```

- [ ] **Step 6: Write `SplitTestData` (branch A: plans inserted, leg fields at insert)**

Create `force-app/main/default/classes/SplitTestData.cls`:

```apex
/**
 * Phase 8 fixtures for split shipments (Revenova freight plans): carrier accounts, leg loads with a
 * carrier, a CAD carrier total and a status, and freight plans that link one customer load (junction
 * row Number 1, Type Customer) to its carrier legs (Number 2, 3, ..., Type Carrier). Later tests build
 * plans ONLY through plan() and resetPlans(), and a test that must prove the plan SOQL's lane or date
 * filter asserts on the LaneQueries SOQL string instead of on rows, so every test works whichever
 * branch below holds.
 *
 * UNPROVEN: Task 1 Step 9 replaces this paragraph with the branch PostProduc proved (plan inserts or
 * in-memory plans, leg fields at insert or by an update) and the measured governor budget.
 */
@IsTest
public class SplitTestData {
  /** An inserted carrier account shaped like the graph's vendor, blacklisted or not. */
  public static Account carrier(String name, Boolean blacklisted) {
    Account a = new Account(
      Name = name,
      RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
        .get('Carrier')
        .getRecordTypeId(),
      rtms__TMS_Type__c = 'Carrier (Ground)',
      Black_List__c = blacklisted == true,
      CurrencyIsoCode = 'CAD'
    );
    insert a;
    return a;
  }

  /**
   * A leg load from origin to destination (stops and lane keys from PricingTestDataFactory) with its
   * carrier, CAD carrier total and status. The returned load carries the factory's re-queried fields
   * plus these three as sent; SplitTestDataTest proves the org keeps them.
   */
  public static rtms__Load__c legLoad(
    PricingTestDataFactory.Graph g,
    Account origin,
    Account destination,
    Account carrierAccount,
    Decimal cadTotal,
    String status
  ) {
    rtms__Load__c template = new rtms__Load__c(
      rtms__Carrier__c = carrierAccount == null ? null : carrierAccount.Id,
      rtms__Carrier_Quote_Total__c = cadTotal,
      rtms__Load_Status__c = status
    );
    rtms__Load__c load = PricingTestDataFactory.createLoad(
      g,
      origin,
      destination,
      template
    );
    load.rtms__Carrier__c = template.rtms__Carrier__c;
    load.rtms__Carrier_Quote_Total__c = cadTotal;
    load.rtms__Load_Status__c = status;
    return load;
  }

  /** Branch A: inserts the plan, the Customer row (Number 1) and one Carrier row per leg (Number 2, 3, ...). */
  public static rtms__FreightPlan__c plan(
    rtms__Load__c customerLoad,
    List<rtms__Load__c> legLoads
  ) {
    rtms__FreightPlan__c freightPlan = new rtms__FreightPlan__c();
    insert freightPlan;
    List<rtms__FreightPlanLoad__c> junctionRows = new List<rtms__FreightPlanLoad__c>{
      new rtms__FreightPlanLoad__c(
        rtms__Freight_Plan__c = freightPlan.Id,
        rtms__Load__c = customerLoad.Id,
        rtms__Type__c = 'Customer',
        rtms__Number__c = 1
      )
    };
    Integer position = 2;
    for (rtms__Load__c leg : legLoads) {
      junctionRows.add(
        new rtms__FreightPlanLoad__c(
          rtms__Freight_Plan__c = freightPlan.Id,
          rtms__Load__c = leg.Id,
          rtms__Type__c = 'Carrier',
          rtms__Number__c = position
        )
      );
      position++;
    }
    insert junctionRows;
    return freightPlan;
  }

  /** Clears the in-memory plans; harmless in branch A, where nothing sets them. */
  public static void resetPlans() {
    FreightPlanReader.rowsOverride = null;
  }
}
```

Create `force-app/main/default/classes/SplitTestData.cls-meta.xml`:

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<ApexClass xmlns="http://soap.sforce.com/2006/04/metadata">
    <apiVersion>64.0</apiVersion>
    <status>Active</status>
</ApexClass>
```

Then format and lint the four Apex files:

```bash
cd /Users/iulian/Documents/Personal/PricingDepartemnt-phase8
npx prettier --check force-app/main/default/classes/FreightPlanReader.cls force-app/main/default/classes/SplitTestData.cls force-app/main/default/classes/SplitTestDataTest.cls force-app/main/default/classes/PricingTestDataFactory.cls
/private/tmp/pmd_install/pmd-bin-7.15.0/bin/pmd check --dir force-app --rulesets config/pmd-ruleset.xml --minimum-priority 3 --format text --fail-on-violation; echo "pmd exit $?"
```

Expected: `All matched files use Prettier code style!` and `pmd exit 0`. This plan's code was run through the repo's Prettier config and this PMD ruleset while planning, with no change and no violation, and so were the branch B and update variants of Step 8.

- [ ] **Step 7: Deploy the classes with the probe (a deploy that fails by design)**

Run:

```bash
cd /Users/iulian/Documents/Personal/PricingDepartemnt-phase8
sf project deploy start -o sandbox --source-dir force-app/main/default/classes/FreightPlanReader.cls --source-dir force-app/main/default/classes/SplitTestData.cls --source-dir force-app/main/default/classes/SplitTestDataTest.cls --source-dir force-app/main/default/classes/PricingTestDataFactory.cls -l RunSpecifiedTests -t SplitTestDataTest -t PricingTestDataFactoryTest -t LaneSearchServiceTest --async --json | python3 -c "import json,sys; s=sys.stdin.read(); r=json.loads(s[s.index('{'):]); print((r.get('result') or {}).get('id'), (r.get('result') or {}).get('status'), r.get('message') or '')"
```

`FreightPlanReader` is the only non-test class; `SplitTestDataTest` covers it. `PricingTestDataFactoryTest` and `LaneSearchServiceTest` run because Step 4 changed the factory, and `LaneSearchServiceTest` calls every `createLoad` overload: base, hazmat, market-test customer, mode and miles.

Expected: a deploy id. Poll with the Step 3 command until the first word is `Succeeded` or `Failed`.

Expected when the probe is the only failure: `Failed tests 28 / 28 failures 1`. Here 28 is 3 `SplitTestDataTest` + 3 `PricingTestDataFactoryTest` + 22 `LaneSearchServiceTest`, counted on 2026-09-15; some sf versions print fewer tests completed, and the failures count is what matters. The one line reads:

`SplitTestDataTest oneSplitShipmentLeavesQueryRoomForTheCodeUnderTest -> System.AssertException: Assertion Failed: SplitTestData budget: before Test.startTest <q> queries / <d> DML; legLoad 1 <q> queries / <d> DML; legLoad 2 <q> queries / <d> DML; plan <q> queries / <d> DML; left inside Test.startTest <q> queries / <d> DML; outer context after the fixture <q> queries left | ...`

Copy that whole line and the deploy id into the task report.

- [ ] **Step 8: Decide the branch from the failures**

Read every failure line of Step 7 and apply the first rule that matches. After an edit, run Step 6's Prettier and PMD check and Step 7 again. Stop when the only failure is the probe line; a changed branch or leg-field variant stays for the rest of the phase.

1. **Only the probe fails.** Branch A holds and the leg fields stick at insert. Go to Step 9.
2. **`planRowsKeepLegOrderCarrierTotalAndStatus` fails on `leg 1 keeps its carrier`, `… keeps its CAD carrier total` or `… keeps its status`** (either leg, message `Expected: …, Actual: …`), **or a leg load insert throws** (`System.DmlException: Insert failed` with a stack trace through `PricingTestDataFactory.createLoad` and `SplitTestData.legLoad`): the org does not keep what rode the insert. Apply the **update variant**:
   - Replace the whole `legLoad` method in `SplitTestData.cls` (its doc comment through its closing brace) with:

```apex
  /**
   * A leg load from origin to destination (stops and lane keys from PricingTestDataFactory); its
   * carrier, CAD carrier total and status are written by one follow-up update, because PostProduc
   * does not keep them when they ride the insert (Task 1 Step 8). SplitTestDataTest proves the org
   * keeps them after the update.
   */
  public static rtms__Load__c legLoad(
    PricingTestDataFactory.Graph g,
    Account origin,
    Account destination,
    Account carrierAccount,
    Decimal cadTotal,
    String status
  ) {
    rtms__Load__c load = PricingTestDataFactory.createLoad(
      g,
      origin,
      destination
    );
    load.rtms__Carrier__c = carrierAccount == null ? null : carrierAccount.Id;
    load.rtms__Carrier_Quote_Total__c = cadTotal;
    load.rtms__Load_Status__c = status;
    update load;
    return load;
  }
```

   - Undo Step 4: `git checkout -- force-app/main/default/classes/PricingTestDataFactory.cls`. The template overload has no caller now.
   - From here on, the Step 7 command drops `--source-dir force-app/main/default/classes/PricingTestDataFactory.cls`, `-t PricingTestDataFactoryTest` and `-t LaneSearchServiceTest`. It becomes `sf project deploy start -o sandbox --source-dir force-app/main/default/classes/FreightPlanReader.cls --source-dir force-app/main/default/classes/SplitTestData.cls --source-dir force-app/main/default/classes/SplitTestDataTest.cls -l RunSpecifiedTests -t SplitTestDataTest --async --json | python3 -c "import json,sys; s=sys.stdin.read(); r=json.loads(s[s.index('{'):]); print((r.get('result') or {}).get('id'), (r.get('result') or {}).get('status'), r.get('message') or '')"`, and the expected count is `3 / 3 failures 1`.
   - If the same `keeps its …` assertion fails again with the update variant, stop and report the message and the actual value. Do not add accepted carrier quotes to force the total: they would count in Carriers to ask's quote reads (Task 5). While planning, 0 of the 634 split legs with a positive carrier total in the last 60 days lacked an accepted quote, so Revenova may derive the total from quotes.
3. **Refused plan: a `SplitTestData.plan` line in the stack trace.** The message has `System.DmlException` with `FIELD_CUSTOM_VALIDATION_EXCEPTION`, `CANNOT_INSERT_UPDATE_ACTIVATE_ENTITY` naming an `rtms.` trigger, `REQUIRED_FIELD_MISSING`, `INVALID_CROSS_REFERENCE_KEY` or any other insert error on `rtms__FreightPlan__c` or `rtms__FreightPlanLoad__c`. Or it has `System.LimitException: Too many SOQL queries: 101` / `Too many DML statements` thrown from `SplitTestData.plan`. Or `planRowsKeepLegOrderCarrierTotalAndStatus` fails on `one plan whose customer load is on the lane` / `the customer row and two carrier rows`, meaning the inserted rows do not come back. In all these cases branch A does not hold. Apply **branch B**: replace the whole branch A `plan` method in `SplitTestData.cls` (from `/** Branch A: inserts` through its closing brace) with:

```apex
  /**
   * Branch B: re-queries the loads and builds the parent-child row the verified plan query returns
   * (child relationship JSON {"totalSize":n,"done":true,"records":[...]}) in memory, then appends it to
   * FreightPlanReader.rowsOverride. The row carries every field any plan query selects, whatever the
   * query asks, and FreightPlanReader returns it for any SOQL: the lane, date and status filters of
   * the semi-join are proven on the LaneQueries SOQL string, not on these rows.
   */
  public static rtms__FreightPlan__c plan(
    rtms__Load__c customerLoad,
    List<rtms__Load__c> legLoads
  ) {
    List<Id> loadIds = new List<Id>{ customerLoad.Id };
    for (rtms__Load__c leg : legLoads) {
      loadIds.add(leg.Id);
    }
    Map<Id, rtms__Load__c> loads = new Map<Id, rtms__Load__c>(
      [
        SELECT
          Id,
          CreatedDate,
          rtms__Carrier__c,
          rtms__Carrier__r.Name,
          rtms__Carrier__r.Black_List__c,
          rtms__City_Lane__c,
          rtms__Load_Status__c,
          rtms__Carrier_Quote_Total__c,
          rtms__Last_Stop__r.rtms__Location2__r.Name
        FROM rtms__Load__c
        WHERE Id IN :loadIds
      ]
    );
    List<Object> children = new List<Object>();
    for (Integer i = 0; i < loadIds.size(); i++) {
      children.add(
        new Map<String, Object>{
          'attributes' => new Map<String, Object>{
            'type' => 'rtms__FreightPlanLoad__c'
          },
          'rtms__Number__c' => i + 1,
          'rtms__Type__c' => i == 0 ? 'Customer' : 'Carrier',
          'rtms__Load__c' => loadIds[i],
          'rtms__Load__r' => JSON.deserializeUntyped(
            JSON.serialize(loads.get(loadIds[i]))
          )
        }
      );
    }
    if (FreightPlanReader.rowsOverride == null) {
      FreightPlanReader.rowsOverride = new List<rtms__FreightPlan__c>();
    }
    String fakeId =
      rtms__FreightPlan__c.SObjectType.getDescribe().getKeyPrefix() +
      String.valueOf(FreightPlanReader.rowsOverride.size() + 1)
        .leftPad(12, '0');
    Map<String, Object> planRow = new Map<String, Object>{
      'attributes' => new Map<String, Object>{
        'type' => 'rtms__FreightPlan__c'
      },
      'Id' => fakeId,
      'rtms__Freight_Plan_Loads__r' => new Map<String, Object>{
        'totalSize' => children.size(),
        'done' => true,
        'records' => children
      }
    };
    rtms__FreightPlan__c freightPlan = (rtms__FreightPlan__c) JSON.deserialize(
      JSON.serialize(planRow),
      rtms__FreightPlan__c.class
    );
    FreightPlanReader.rowsOverride.add(freightPlan);
    return freightPlan;
  }
```

   Nothing else changes: `resetPlans` already clears `FreightPlanReader.rowsOverride`, and the three tests pass unchanged on branch B (the plan read returns the in-memory row, and the leg loads are still re-read from `rtms__Load__c`).
4. **`System.LimitException: Too many SOQL queries: 101` thrown from `legLoad` or before `Test.startTest()`** (stack trace through `PricingTestDataFactory.createLoad`, `createGraph` or `SplitTestDataTest.fixture`): the factory's documented two-loads-per-fresh-context budget does not hold for leg loads. Stop and report with the stack trace; later tasks cannot put a split shipment in one test. If the 101 is thrown from `SplitTestDataTest.planRowsKeepLegOrderCarrierTotalAndStatus` after `Test.stopTest()` (the `stored` re-read, the carrier quote count or the `FreightPlanReader.read` line), move `Test.stopTest();` to just after the last assertion of the method, so those reads run inside the fresh context the budget test proves has 20 queries left, and run Step 7 again.
5. **`one split shipment must leave 20 queries for the code under test` fails.** When the plan cost on that line is 5 queries or more, apply branch B (rule 3) and run Step 7 again: in-memory plans cost one query. Otherwise, stop and report the line.
6. **`PricingTestDataFactoryTest` or `LaneSearchServiceTest` fails.** Step 4 broke an overload: compare the change with Step 4, fix it and run Step 7 again. If the failure is unrelated to the change, stop and report.
7. **`planRowsKeepLegOrderCarrierTotalAndStatus` fails on `a leg load gets no carrier quote from the automation`** (`Expected: 0, Actual: <n>`): Revenova creates carrier quotes for a load that gets a carrier and a total, so leg fixtures would reach the quote counts of Carriers to ask. Stop and report the count. Tasks 5 and 6 already build their legs to a yard off the customer lane (and, in stage 2, off its state lane), but the owner must rule before Task 5 starts whether its quote assertions still hold.
8. **A `COMPILE` line, or any other failure:** fix a typo against this plan's code; otherwise stop and report the line.

- [ ] **Step 9: Record the branch and the budget, then remove the probe**

In `force-app/main/default/classes/SplitTestData.cls`, replace the class comment's last paragraph (the two lines starting ` * UNPROVEN: Task 1 Step 9 replaces this paragraph`) with these lines, keeping only the PLANS line and the LEG FIELDS line that Step 8 proved:

```apex
 * PLANS: inserted (branch A). Revenova's managed code lets a test insert rtms__FreightPlan__c and
 * rtms__FreightPlanLoad__c, so plan() inserts real rows, FreightPlanReader runs the real query and
 * resetPlans() has nothing to clear.
 * PLANS: in memory (branch B). PostProduc refused the test insert (the Step 7 failure message is
 * quoted in the Task 1 report), so plan() re-reads the loads and appends the parent-child row to
 * FreightPlanReader.rowsOverride; resetPlans() clears them.
 * LEG FIELDS: at insert, through PricingTestDataFactory.createLoad(g, origin, destination, template).
 * LEG FIELDS: by one update after insert; PostProduc did not keep rtms__Carrier__c,
 * rtms__Carrier_Quote_Total__c or rtms__Load_Status__c when it rode the insert (the field and
 * value are in the Task 1 report).
 * BUDGET: the query and DML counts of the probe (SplitTestDataTest's "budget" debug line) are in
 * the Task 1 report with the deploy id. A test holds ONE real split shipment: its
 * customer load before Test.startTest(), both legLoad calls and plan() inside it, then the code under
 * test within the queries left.
```

Copy the probe's budget line, the failure message (branch B or the update variant) and the Step 7 deploy id into the Task 1 report. In `force-app/main/default/classes/SplitTestDataTest.cls`, delete the line `    System.assert(false, budget); // PROBE: Task 1 Step 9 deletes this line`. The `System.debug` line and the 20-query assertion stay. Check:

```bash
cd /Users/iulian/Documents/Personal/PricingDepartemnt-phase8
grep -c "fill:" force-app/main/default/classes/SplitTestData.cls
grep -c "UNPROVEN\|PROBE" force-app/main/default/classes/SplitTestData.cls force-app/main/default/classes/SplitTestDataTest.cls
grep -c "^ \* PLANS: \|^ \* LEG FIELDS: " force-app/main/default/classes/SplitTestData.cls
npx prettier --write force-app/main/default/classes/SplitTestData.cls force-app/main/default/classes/SplitTestDataTest.cls
/private/tmp/pmd_install/pmd-bin-7.15.0/bin/pmd check --dir force-app --rulesets config/pmd-ruleset.xml --minimum-priority 3 --format text --fail-on-violation; echo "pmd exit $?"
```

Expected: `0`; `SplitTestData.cls:0` and `SplitTestDataTest.cls:0`; `2` (one PLANS line, one LEG FIELDS line); Prettier may rewrap the comment; `pmd exit 0`.

- [ ] **Step 10: Deploy the classes for real**

Run the Step 7 deploy command again: the variant with the factory and its two extra tests, or the update-variant command from Step 8 rule 2 if that rule applied. Poll with the Step 3 command.

Expected: `Succeeded tests 28 / 28 failures 0`, or `Succeeded tests 3 / 3 failures 0` for the update variant, with no `COMPILE` line. Record the deploy id in the task report. A failure other than the removed probe means Step 9 changed code: compare it with Step 9 and run again.

- [ ] **Step 11: Create the two custom metadata types and their fields**


Create `force-app/main/default/objects/Intercompany_Carrier__mdt/Intercompany_Carrier__mdt.object-meta.xml`:

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<CustomObject xmlns="http://soap.sforce.com/2006/04/metadata">
    <description
  >Carrier accounts that belong to the Trans-Pro group. Carriers to ask and Split-lane options leave out their quotes, their split legs and any split shipment that uses them. One record per account.</description>
    <label>Intercompany Carrier</label>
    <pluralLabel>Intercompany Carriers</pluralLabel>
    <visibility>Public</visibility>
</CustomObject>
```

Create `force-app/main/default/objects/Intercompany_Carrier__mdt/fields/Carrier_Account_Id__c.field-meta.xml`:

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Carrier_Account_Id__c</fullName>
    <externalId>false</externalId>
    <fieldManageability>DeveloperControlled</fieldManageability>
    <inlineHelpText
  >The carrier Account Id, 15 or 18 characters. An entry that is not an Account Id is ignored.</inlineHelpText>
    <label>Carrier Account Id</label>
    <length>18</length>
    <required>false</required>
    <type>Text</type>
    <unique>false</unique>
</CustomField>
```

Create `force-app/main/default/objects/Intercompany_Carrier__mdt/fields/Note__c.field-meta.xml`:

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Note__c</fullName>
    <externalId>false</externalId>
    <fieldManageability>DeveloperControlled</fieldManageability>
    <inlineHelpText
  >Who the account is, for the admin reading the list. Not used by the app.</inlineHelpText>
    <label>Note</label>
    <length>255</length>
    <required>false</required>
    <type>Text</type>
    <unique>false</unique>
</CustomField>
```

Create `force-app/main/default/objects/Handoff_Point__mdt/Handoff_Point__mdt.object-meta.xml`:

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<CustomObject xmlns="http://soap.sforce.com/2006/04/metadata">
    <description
  >Places where a split shipment can change carriers. Split-lane options estimates a split through an active point when a lane has no split history. One record per place.</description>
    <label>Handoff Point</label>
    <pluralLabel>Handoff Points</pluralLabel>
    <visibility>Public</visibility>
</CustomObject>
```

Create `force-app/main/default/objects/Handoff_Point__mdt/fields/Place_Key__c.field-meta.xml`:

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Place_Key__c</fullName>
    <externalId>false</externalId>
    <fieldManageability>DeveloperControlled</fieldManageability>
    <inlineHelpText
  >The Pricing Place key of the point, city|province|country in lower case, for example laredo|tx|us.</inlineHelpText>
    <label>Place Key</label>
    <length>120</length>
    <required>false</required>
    <type>Text</type>
    <unique>false</unique>
</CustomField>
```

Create `force-app/main/default/objects/Handoff_Point__mdt/fields/Active__c.field-meta.xml`:

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Active__c</fullName>
    <defaultValue>true</defaultValue>
    <externalId>false</externalId>
    <fieldManageability>DeveloperControlled</fieldManageability>
    <inlineHelpText
  >Clear to stop estimating splits through this point without deleting it.</inlineHelpText>
    <label>Active</label>
    <type>Checkbox</type>
</CustomField>
```

`fieldManageability` `DeveloperControlled` and `visibility` `Public` copy `Pricing_Department_Setting__mdt` and `Truck_Routing_Setting__mdt`. In this unpackaged org an admin still edits the records in Setup > Custom Metadata Types > Manage Records. Tasks 3 and 11 read and document the lists.

- [ ] **Step 12: Create the five records**


Create `force-app/main/default/customMetadata/Intercompany_Carrier.Tpml_TP_Org.md-meta.xml`:

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<CustomMetadata
  xmlns="http://soap.sforce.com/2006/04/metadata"
  xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
  xmlns:xsd="http://www.w3.org/2001/XMLSchema"
>
    <label>Tpml TP org</label>
    <protected>false</protected>
    <values>
        <field>Carrier_Account_Id__c</field>
        <value xsi:type="xsd:string">0011N00001JcHnvQAF</value>
    </values>
    <values>
        <field>Note__c</field>
        <value xsi:type="xsd:string">Tpml (Trans-Pro Logistics)-TP org</value>
    </values>
</CustomMetadata>
```

Create `force-app/main/default/customMetadata/Intercompany_Carrier.Lessard_Org.md-meta.xml`:

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<CustomMetadata
  xmlns="http://soap.sforce.com/2006/04/metadata"
  xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
  xmlns:xsd="http://www.w3.org/2001/XMLSchema"
>
    <label>Lessard org</label>
    <protected>false</protected>
    <values>
        <field>Carrier_Account_Id__c</field>
        <value xsi:type="xsd:string">0011N00001JbQ7EQAV</value>
    </values>
    <values>
        <field>Note__c</field>
        <value
      xsi:type="xsd:string"
    >TRANS-PRO LOGISTIQUE - TPML- LESSARD ORG</value>
    </values>
</CustomMetadata>
```

Create `force-app/main/default/customMetadata/Handoff_Point.Laredo_TX_US.md-meta.xml`:

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<CustomMetadata
  xmlns="http://soap.sforce.com/2006/04/metadata"
  xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
  xmlns:xsd="http://www.w3.org/2001/XMLSchema"
>
    <label>Laredo, TX</label>
    <protected>false</protected>
    <values>
        <field>Active__c</field>
        <value xsi:type="xsd:boolean">true</value>
    </values>
    <values>
        <field>Place_Key__c</field>
        <value xsi:type="xsd:string">laredo|tx|us</value>
    </values>
</CustomMetadata>
```

Create `force-app/main/default/customMetadata/Handoff_Point.San_Diego_CA_US.md-meta.xml`:

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<CustomMetadata
  xmlns="http://soap.sforce.com/2006/04/metadata"
  xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
  xmlns:xsd="http://www.w3.org/2001/XMLSchema"
>
    <label>San Diego, CA</label>
    <protected>false</protected>
    <values>
        <field>Active__c</field>
        <value xsi:type="xsd:boolean">true</value>
    </values>
    <values>
        <field>Place_Key__c</field>
        <value xsi:type="xsd:string">san diego|ca|us</value>
    </values>
</CustomMetadata>
```

Create `force-app/main/default/customMetadata/Handoff_Point.Calexico_CA_US.md-meta.xml`:

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<CustomMetadata
  xmlns="http://soap.sforce.com/2006/04/metadata"
  xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
  xmlns:xsd="http://www.w3.org/2001/XMLSchema"
>
    <label>Calexico, CA</label>
    <protected>false</protected>
    <values>
        <field>Active__c</field>
        <value xsi:type="xsd:boolean">true</value>
    </values>
    <values>
        <field>Place_Key__c</field>
        <value xsi:type="xsd:string">calexico|ca|us</value>
    </values>
</CustomMetadata>
```

The two account Ids appear only in these two records, never in Apex (Task 3's `IntercompanyCarriers` reads them). Step 1 printed the accounts; the three place keys are the `Pricing_Place__c.Key__c` values Step 1 printed.

- [ ] **Step 13: Add `Split` to `RFP_Lane__c.Cost_Source__c`**

In `force-app/main/default/objects/RFP_Lane__c/fields/Cost_Source__c.field-meta.xml`, right after the `Manual` value

```xml
            <value><fullName>Manual</fullName><default>false</default><label
        >Manual</label></value>
```

insert

```xml
            <value><fullName>Split</fullName><default>false</default><label
        >Split</label></value>
```

The whole file afterwards:

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Cost_Source__c</fullName>
    <label>Cost source</label>
    <type>Picklist</type>
    <required>false</required>
    <valueSet>
        <restricted>true</restricted>
        <valueSetDefinition>
            <sorted>false</sorted>
            <value><fullName>Bid</fullName><default>false</default><label
        >Bid</label></value>
            <value><fullName>History median</fullName><default
        >false</default><label>History median</label></value>
            <value><fullName>Manual</fullName><default>false</default><label
        >Manual</label></value>
            <value><fullName>Split</fullName><default>false</default><label
        >Split</label></value>
        </valueSetDefinition>
    </valueSet>
</CustomField>
```

`RFP_Lane__c` has no record types (its folder holds only `RFP_Lane__c.object-meta.xml` and `fields`), so no record-type picklist assignment needs the new value. No permission changes: a picklist value needs none (spec §8).

- [ ] **Step 14: Add the new members to `manifest/package.xml`**

Each insertion is anchored on a line's text. Keep the file's 8-space member indentation.

(a) ApexClass: after `        <members>TripRouteView</members>` (the last member before `<name>ApexClass</name>`), insert

```xml
        <members>FreightPlanReader</members>
        <members>SplitTestData</members>
        <members>SplitTestDataTest</members>
```

(b) CustomObject: after `        <members>Truck_Routing_Setting__mdt</members>` (the last member before `<name>CustomObject</name>`), insert

```xml
        <members>Intercompany_Carrier__mdt</members>
        <members>Handoff_Point__mdt</members>
```

(c) CustomMetadata: after `        <members>Truck_Routing_Setting.Default</members>`, insert

```xml
        <members>Intercompany_Carrier.Tpml_TP_Org</members>
        <members>Intercompany_Carrier.Lessard_Org</members>
        <members>Handoff_Point.Laredo_TX_US</members>
        <members>Handoff_Point.San_Diego_CA_US</members>
        <members>Handoff_Point.Calexico_CA_US</members>
```

(d) CustomField: after `        <members>Truck_Routing_Setting__mdt.Width_M__c</members>`, insert

```xml
        <members>Intercompany_Carrier__mdt.Carrier_Account_Id__c</members>
        <members>Intercompany_Carrier__mdt.Note__c</members>
        <members>Handoff_Point__mdt.Active__c</members>
        <members>Handoff_Point__mdt.Place_Key__c</members>
```

`RFP_Lane__c.Cost_Source__c` is already a member. Check:

```bash
cd /Users/iulian/Documents/Personal/PricingDepartemnt-phase8
xmllint --noout manifest/package.xml && echo xml-ok
grep -c '<members>FreightPlanReader</members>\|<members>SplitTestData</members>\|<members>SplitTestDataTest</members>' manifest/package.xml
grep -c '<members>Intercompany_Carrier__mdt</members>\|<members>Handoff_Point__mdt</members>' manifest/package.xml
grep -c '<members>Intercompany_Carrier\.\|<members>Handoff_Point\.' manifest/package.xml
grep -c '<members>Intercompany_Carrier__mdt\.\|<members>Handoff_Point__mdt\.' manifest/package.xml
npx prettier --check manifest/package.xml force-app/main/default/objects/Intercompany_Carrier__mdt force-app/main/default/objects/Handoff_Point__mdt force-app/main/default/customMetadata force-app/main/default/objects/RFP_Lane__c/fields/Cost_Source__c.field-meta.xml
```

Expected: `xml-ok`, then `3`, `2`, `5`, `4`, and `All matched files use Prettier code style!` (the XML above was run through the repo's Prettier config while planning).

- [ ] **Step 15: Deploy the metadata (no tests) and verify the org**

Run:

```bash
cd /Users/iulian/Documents/Personal/PricingDepartemnt-phase8
sf project deploy start -o sandbox -l NoTestRun --async --json \
  --source-dir force-app/main/default/objects/Intercompany_Carrier__mdt \
  --source-dir force-app/main/default/objects/Handoff_Point__mdt \
  --source-dir force-app/main/default/customMetadata/Intercompany_Carrier.Tpml_TP_Org.md-meta.xml \
  --source-dir force-app/main/default/customMetadata/Intercompany_Carrier.Lessard_Org.md-meta.xml \
  --source-dir force-app/main/default/customMetadata/Handoff_Point.Laredo_TX_US.md-meta.xml \
  --source-dir force-app/main/default/customMetadata/Handoff_Point.San_Diego_CA_US.md-meta.xml \
  --source-dir force-app/main/default/customMetadata/Handoff_Point.Calexico_CA_US.md-meta.xml \
  --source-dir force-app/main/default/objects/RFP_Lane__c/fields/Cost_Source__c.field-meta.xml \
  | python3 -c "import json,sys; s=sys.stdin.read(); d=json.loads(s[s.index('{'):]); r=d.get('result') or {}; print(r.get('id'), r.get('status'), d.get('message') or '')"
```

Expected: a deploy id (`0Af...`) and `Queued` or `InProgress`. Poll, repeating while the first word is `Queued`, `InProgress` or a wait-timeout error name:

```bash
sf project deploy report -o sandbox --job-id <id> -w 2 --json | python3 -c "import json,sys,collections; s=sys.stdin.read(); d=json.loads(s[s.index('{'):]); r=d.get('result') or {}; det=r.get('details') or {}; ok=det.get('componentSuccesses') or []; ok=ok if isinstance(ok,list) else [ok]; bad=det.get('componentFailures') or []; bad=bad if isinstance(bad,list) else [bad]; print(r.get('status') or d.get('name'), 'errors', r.get('numberComponentErrors')); print(dict(collections.Counter(c.get('componentType') for c in ok if c.get('componentType')))); [print(c.get('componentType'), c.get('fullName'), '->', c.get('problem')) for c in bad]"
```

Expected when done: `Succeeded errors 0`, then `'CustomField': 5`, `'CustomMetadata': 5` and `'CustomObject'` 2 or 3 (the CLI may list `RFP_Lane__c` as the parent of `Cost_Source__c`), and no failure lines. A record failing with `no CustomObject named Handoff_Point__mdt` or an unknown `<field>` means a Step 11 file name does not match the record's `<field>`: fix it and run this step again.

Then verify:

```bash
cd /Users/iulian/Documents/Personal/PricingDepartemnt-phase8
sf data query -o sandbox -q "SELECT QualifiedApiName, Label, PluralLabel FROM EntityDefinition WHERE QualifiedApiName IN ('Intercompany_Carrier__mdt','Handoff_Point__mdt') ORDER BY QualifiedApiName" -r human 2>&1 | grep -v Warning
sf data query -o sandbox -q "SELECT QualifiedApiName, DataType FROM FieldDefinition WHERE EntityDefinition.QualifiedApiName = 'Intercompany_Carrier__mdt' AND QualifiedApiName IN ('Carrier_Account_Id__c','Note__c')" -r human 2>&1 | grep -v Warning
sf data query -o sandbox -q "SELECT QualifiedApiName, DataType FROM FieldDefinition WHERE EntityDefinition.QualifiedApiName = 'Handoff_Point__mdt' AND QualifiedApiName IN ('Place_Key__c','Active__c')" -r human 2>&1 | grep -v Warning
sf data query -o sandbox -q "SELECT DeveloperName, Carrier_Account_Id__c FROM Intercompany_Carrier__mdt ORDER BY DeveloperName" -r human 2>&1 | grep -v Warning
sf data query -o sandbox -q "SELECT DeveloperName, Place_Key__c, Active__c FROM Handoff_Point__mdt ORDER BY DeveloperName" -r human 2>&1 | grep -v Warning
sf data query -o sandbox -q "SELECT Value, IsActive, IsDefaultValue FROM PicklistValueInfo WHERE EntityParticle.EntityDefinition.QualifiedApiName = 'RFP_Lane__c' AND EntityParticle.QualifiedApiName = 'Cost_Source__c'" -r human 2>&1 | grep -v Warning
sf data query -o sandbox -q "SELECT Key__c FROM Pricing_Place__c WHERE Key__c IN ('laredo|tx|us','san diego|ca|us','calexico|ca|us') ORDER BY Key__c" -r human 2>&1 | grep -v Warning
```

Expected. The DataType formats are the ones this org prints for existing fields: `Pricing_Department_Setting__mdt.Excluded_Contact_Ids__c` shows `Text(255)` and `Truck_Routing_Setting__mdt.Alternatives__c` shows `Checkbox`.

- EntityDefinition, 2 rows: `Handoff_Point__mdt | Handoff Point | Handoff Points` and `Intercompany_Carrier__mdt | Intercompany Carrier | Intercompany Carriers`.
- `Carrier_Account_Id__c | Text(18)`, `Note__c | Text(255)`; `Active__c | Checkbox`, `Place_Key__c | Text(120)`.
- 2 records: `Lessard_Org | 0011N00001JbQ7EQAV`, `Tpml_TP_Org | 0011N00001JcHnvQAF`.
- 3 records: `Calexico_CA_US | calexico|ca|us | true`, `Laredo_TX_US | laredo|tx|us | true`, `San_Diego_CA_US | san diego|ca|us | true`.
- 4 picklist rows `Bid`, `History median`, `Manual`, `Split`, all active, none default.
- 3 keys: `calexico|ca|us`, `laredo|tx|us`, `san diego|ca|us`.

If a record query prints `sObject type 'Handoff_Point__mdt' is not supported`, the deploy did not finish: poll again.

- [ ] **Step 16: Full PMD and commit**

Run:

```bash
cd /Users/iulian/Documents/Personal/PricingDepartemnt-phase8
/private/tmp/pmd_install/pmd-bin-7.15.0/bin/pmd check --dir force-app --rulesets config/pmd-ruleset.xml --minimum-priority 3 --format text --fail-on-violation; echo "pmd exit $?"
git add force-app/main/default/classes/FreightPlanReader.cls force-app/main/default/classes/FreightPlanReader.cls-meta.xml force-app/main/default/classes/SplitTestData.cls force-app/main/default/classes/SplitTestData.cls-meta.xml force-app/main/default/classes/SplitTestDataTest.cls force-app/main/default/classes/SplitTestDataTest.cls-meta.xml force-app/main/default/objects/Intercompany_Carrier__mdt force-app/main/default/objects/Handoff_Point__mdt force-app/main/default/customMetadata/Intercompany_Carrier.Tpml_TP_Org.md-meta.xml force-app/main/default/customMetadata/Intercompany_Carrier.Lessard_Org.md-meta.xml force-app/main/default/customMetadata/Handoff_Point.Laredo_TX_US.md-meta.xml force-app/main/default/customMetadata/Handoff_Point.San_Diego_CA_US.md-meta.xml force-app/main/default/customMetadata/Handoff_Point.Calexico_CA_US.md-meta.xml force-app/main/default/objects/RFP_Lane__c/fields/Cost_Source__c.field-meta.xml manifest/package.xml
git diff --quiet force-app/main/default/classes/PricingTestDataFactory.cls || git add force-app/main/default/classes/PricingTestDataFactory.cls
git diff --cached --name-only | wc -l
git commit -m "Add split test data, the freight plan reader, intercompany carriers, handoff points and the Split cost source"
git status --short
```

Expected: `pmd exit 0`; `20` staged files, or `19` on the update variant, where `PricingTestDataFactory.cls` is unchanged. That is 6 class files, the factory, 3 files per custom metadata type, 5 records, the picklist field and the manifest. The commit passes lint-staged (Prettier makes no change). `git status --short` afterwards lists only ` M .vscode/settings.json` and any untracked `* 2.*` duplicates, never staged. The message has no attribution trailer.

#### Contract notes (Task 1)

1. **`PricingTestDataFactory` changes in Task 1** (not in the contract's Task 1 file list). `createLoad`'s full form is private, so `SplitTestData.legLoad` cannot set `rtms__Carrier__c`, `rtms__Carrier_Quote_Total__c` and `rtms__Load_Status__c` at insert without a new public overload, `createLoad(Graph, Account, Account, rtms__Load__c template)`. The private method takes the template in place of `Decimal miles`; the phase 7 miles overload passes `new rtms__Load__c(rtms__Distance_Miles__c = miles)`. The deploy runs `PricingTestDataFactoryTest` and `LaneSearchServiceTest`, which calls every overload. If Step 8 selects the update variant, the factory change is reverted and nothing outside the contract's list changes.
2. **"Fixture DML before `Test.startTest()`" cannot hold for a split shipment.** The factory's class doc and `LaneSearchServiceTest` allow one `createLoad` before `Test.startTest()` after `createGraph()` and two inside it; three in one block hit 101 queries. A real split shipment is three loads, so `SplitTestDataTest` creates the customer load before `Test.startTest()` and both legs and `plan()` inside it. The code under test runs after them in the same block. The contract's "at most 3 plans with 2 legs and 4 quote loads" per test is not reachable with real loads: one test method holds one split shipment, or up to three quote loads, not both. Tasks 5, 6, 8 and 9 should put each scenario in its own test method and size it by the budget Step 9 writes into `SplitTestData`'s class comment. On branch B a second `plan()` call on the same loads costs one query and no load, which helps a test that needs two plan rows with the same legs.
3. **The measurement is read through a probe deploy, not a debug log.** PostProduc has no active trace flag (Tooling `TraceFlag` query, 2026-09-15), so a `System.debug` line in a deploy's test run cannot be read back. The budget test keeps the debug line and a permanent 20-query room assertion, and temporarily ends on `System.assert(false, budget)`. A deploy with a failing test saves nothing, and its failure message carries the numbers. Step 9 removes the probe before the real deploy.
4. **`resetPlans()` always sets `FreightPlanReader.rowsOverride = null`**, rather than being empty in branch A. That is the same no-op there, and the branch switch in Step 8 touches only `plan` (or `legLoad`).
5. **`SplitTestDataTest` has three methods:** the decision test, the budget test and an override test. The override test is needed for coverage: on branch A nothing sets `rowsOverride`, and `FreightPlanReader` would be at 2 of 3 lines, under 75 %.
6. **`legLoad` returns the factory's re-queried load** with the three fields set in memory as sent, so it costs no extra query. The decision test re-reads them from the org.
7. **Leg 2 is `Cancelled`** so the fixture proves that status sticks, which Tasks 5 and 8 need. `Cancelled` at insert passes every active `rtms__Load__c` validation rule (read 2026-09-15: `Prevent_Completed_Loads_from_Changing` needs `Prepaid__c`, `Cancel_Customer_Load_2` needs `Load_Cancel__c`), and `LoadCancelCascadeTrigger` fires only on update. If a cancelled leg is what makes the plan insert fail, rule 3 still applies (branch B), because branch B serves every later fixture.
8. **Evidence read while planning (read-only, 2026-09-15):**
   - `rtms__FreightPlanLoad__c` has one org trigger, `FreightPlanLoadTrigger`, and it is Inactive. `rtms__FreightPlan__c` has the managed `rtms.FreightPlan`. `rtms__Load__c` has managed `rtms.LoadUpsert` and `rtms3.CompensationLoadTrigger` plus the org's `LoadTrigger`, `LoadStatusTrigger`, `LoadFinancialTrigger`, `LoadARTrigger` and `LoadCancelCascadeTrigger`.
   - `rtms__In_Freight_Plan__c` is a formula, so junction inserts do not update the load.
   - Real legs carry `rtms__Customer_Load__c` false and `rtms__Carrier_Load2__c` true. The fixture leaves both at the factory's defaults, because no phase 8 query reads them.
9. **Descriptions** were added on the two custom metadata types (admin-facing text); the existing types have none. Labels, lengths, the default and the record values are the contract's.
10. **Branch B rows carry every plan field whatever the query selects.** Carriers to ask's names-only proof (Task 5) must stay on `LaneQueries.planSoql(..., false)` and on the `CarrierLeadResult` key set, never on row contents.


---

### Task 2: Lane key matcher extraction — `LaneKeyMatcher` and `LaneLoadFilters` behind a characterization test

**Files:**

- Create: `force-app/main/default/classes/LaneSearchQueryBuilderTest.cls`, `force-app/main/default/classes/LaneSearchQueryBuilderTest.cls-meta.xml` (characterization, Steps 2–3)
- Create: `force-app/main/default/classes/LaneKeyMatcherTest.cls`, `force-app/main/default/classes/LaneKeyMatcherTest.cls-meta.xml`
- Create: `force-app/main/default/classes/LaneKeyMatcher.cls`, `force-app/main/default/classes/LaneKeyMatcher.cls-meta.xml`
- Create: `force-app/main/default/classes/LaneLoadFilters.cls`, `force-app/main/default/classes/LaneLoadFilters.cls-meta.xml`
- Modify: `force-app/main/default/classes/LaneSearchQueryBuilder.cls` (whole file, Step 8: `addCity`, `addProvince`, `addZip3`, `requirePostalPrefix` and `laneLikePattern` leave; `addEnd` calls `LaneKeyMatcher.condition`; `LaneEnd` loses `likePrefix`, `likeSuffix`, `zip3FieldName` and gains `isOrigin`; `SELECT_CLAUSE`, `buildSoql`, `addRadius` and `escapeLike` are unchanged)
- Modify: `force-app/main/default/classes/LaneSearchFilters.cls` (whole file, Step 9: `addModeFilter`, `addEquipmentFilter` and `addHazmatFilter` leave; `addFilters` calls `LaneLoadFilters.add` between currency and the Market Test exclusion)
- Modify: `manifest/package.xml` (ApexClass members `LaneSearchQueryBuilderTest`, `LaneKeyMatcher`, `LaneKeyMatcherTest`, `LaneLoadFilters`, at the end of the ApexClass block, after the members Task 1 added and before `<name>ApexClass</name>`)

Not changed: `LaneSearchService`, `LaneSearchServiceTest`, `BidSearchQueryBuilder`, `BidSearchService`, `BidSearchServiceTest`, `PlaceNormalizer`, `LaneSearchRequest`.

**Interfaces:**

- Consumes:
  - `LaneSearchQueryBuilder.buildSoql(LaneSearchRequest req, Map<String, Object> binds, Map<String, Pricing_Place__c> places)` and `public static String escapeLike(String s)` (exist; `escapeLike` stays public and in place: `BidSearchQueryBuilder`, `RfpProjectController` and `LaneBenchmarkController` call it).
  - `PlaceNormalizer.cityLaneVariants(Pricing_Place__c place)` returning `Set<String>` of `"<spelling>, <Province__c>"` (exists).
  - `LaneSearchRequest.Precision` (`RADIUS`, `CITY`, `PROVINCE`, `ZIP3`), `LaneSearchRequest.Unit`, `LaneSearchRequest.Accepted`, and the request fields `originKey`, `destinationKey`, `originPrecision`, `destinationPrecision`, `originRadius`, `destinationRadius`, `radiusUnit`, `originZip3`, `destinationZip3`, `lookbackDays`, `currencyIsoCode`, `modes`, `equipmentCategories`, `equipmentTypes`, `hazmatOnly`, `acceptedFilter`, `rowLimit`, `includeStopGeolocation` (exist).
  - `LaneSearchExclusions.excludedContactIdsOverride` (`@TestVisible private static Set<String>`, exists) and `LaneSearchException` (exists).
  - `Pricing_Place__c.Key__c`, `City__c`, `Province__c`, `Country__c`, `Postal_Prefix__c`, `Spellings__c`, `Geolocation__Latitude__s`, `Geolocation__Longitude__s` (exist).
  - From Task 1: only the manifest position (its ApexClass members come first). No Task 1 class is used.
- Produces:
  - `public with sharing class LaneKeyMatcher`:
    - `public static String condition(String loadPath, Boolean isOrigin, String bindPrefix, LaneSearchRequest.Precision endPrecision, Pricing_Place__c place, String explicitZip3, Map<String, Object> binds)` — the contract's A1 signature (the fourth parameter is named `endPrecision`; see Contract notes 1). CITY and RADIUS put `bindPrefix + 'City'` = `List<String>` of patterns and return `loadPath + 'rtms__City_Lane__c LIKE :' + bindPrefix + 'City'`; PROVINCE puts `bindPrefix + 'Prov'` and returns `loadPath + 'rtms__State_Lane__c LIKE :' + bindPrefix + 'Prov'`; ZIP3 uses `explicitZip3` when not blank, else `place.Postal_Prefix__c` (blank: `LaneSearchException` `'Place ' + place.Key__c + ' has no postal prefix; pass originZip3'` or `destinationZip3`), puts `bindPrefix + 'Zip3'` and returns `loadPath + 'rtms__Zip3_Lane__c LIKE :' + bindPrefix + 'Zip3'`. Patterns are `escapeLike(value) + ':%'` for an origin, `'%:' + escapeLike(value)` for a destination. Returns `null`, binding nothing, when the end has no constraint: no place, unless the end is ZIP3 with an explicit prefix.
  - `public with sharing class LaneLoadFilters`:
    - `public static void add(LaneSearchRequest req, String loadPath, List<String> conditions, Map<String, Object> binds)` — appends, in this order and only when set, `loadPath + 'rtms__Mode__r.Name IN :modes'`; `'(' + loadPath + 'rtms__Equipment_Type__r.rtms__Category__c IN :cats OR ' + loadPath + 'rtms__Equipment_Type__r.Name IN :types)'` (or either half alone); `loadPath + 'rtms__Hazardous_Materials__c = true'`; binds `modes`, `cats`, `types`.
  - `LaneSearchQueryBuilderTest` with the private constant `SELECT_CLAUSE` holding the expected select. Task 4 edits that one constant when it replaces `Carrier_Att__c`.
  - The lane search's SOQL and bind names are byte-identical before and after this task (`LaneSearchQueryBuilderTest` passes in Step 3 on the old code and in Step 12 on the new).
  - Used later by `LaneQueries.laneConditions`, `LaneQueries.stateLaneConditions` and `LaneQueries.legConditions` (Tasks 5 and 9).

- [ ] **Step 1: Print the baselines**

Run: `git log --oneline -1 && ls force-app/main/default/classes/*Test.cls | wc -l && grep -c "^  @IsTest" force-app/main/default/classes/LaneSearchServiceTest.cls force-app/main/default/classes/BidSearchServiceTest.cls`

Expected: the Task 1 commit on `phase-8/carriers-and-split-lanes`; `27` test classes (26 plus Task 1's `SplitTestDataTest`); `LaneSearchServiceTest.cls:22` and `BidSearchServiceTest.cls:4`. Use the printed counts in Step 12 if they differ.

Then write a class-complexity report ruleset outside the repo and measure the two classes this task shrinks:

```bash
cat > /private/tmp/pmd_install/phase8-complexity.xml <<'XML'
<?xml version="1.0" encoding="UTF-8" ?>
<ruleset name="complexity report" xmlns="http://pmd.sourceforge.net/ruleset/2.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="http://pmd.sourceforge.net/ruleset/2.0.0 https://pmd.sourceforge.io/ruleset_2_0_0.xsd">
  <description>Prints every class cyclomatic complexity.</description>
  <rule ref="category/apex/design.xml/CyclomaticComplexity">
    <properties>
      <property name="classReportLevel" value="1" />
      <property name="methodReportLevel" value="1" />
    </properties>
  </rule>
</ruleset>
XML
/private/tmp/pmd_install/pmd-bin-7.15.0/bin/pmd check --dir force-app/main/default/classes/LaneSearchQueryBuilder.cls --dir force-app/main/default/classes/LaneSearchFilters.cls --rulesets /private/tmp/pmd_install/phase8-complexity.xml --format text --no-cache 2>/dev/null | grep "The class"
```

Expected (measured on `b847aec`, after phase 7's Market Test change):

```
…LaneSearchFilters.cls:10:	CyclomaticComplexity:	The class 'LaneSearchFilters' has a total cyclomatic complexity of 17 (highest 5).
…LaneSearchQueryBuilder.cls:12:	CyclomaticComplexity:	The class 'LaneSearchQueryBuilder' has a total cyclomatic complexity of 26 (highest 7).
```

- [ ] **Step 2: Write the characterization test**

This test pins what the lane search builds today: the exact SOQL string and the bind names for city, province, explicit ZIP3, ZIP3 from the place, a ZIP3 place without a prefix, an end without a place, radius on both ends with and without the stop geolocation, and every filter in its order, with the Market Test exclusion every lane search has carried since phase 7. Every expected string below was copied from `LaneSearchQueryBuilder.cls`, `LaneSearchFilters.cls` and `PlaceNormalizer.cityLaneVariants` as they stand at `b847aec`. `buildSoql` is pure, so the test inserts nothing.

Create `force-app/main/default/classes/LaneSearchQueryBuilderTest.cls`:

```apex
/**
 * Characterization of LaneSearchQueryBuilder.buildSoql: the exact SOQL string and bind names for
 * every lane precision and every filter, including the Market Test exclusion phase 7 added to every search. Phase 8 wrote it before moving the lane-key conditions
 * into LaneKeyMatcher and the mode, equipment and hazmat conditions into LaneLoadFilters, and ran it
 * green on the code as it was then, so the move is proved not to change the lane search by one
 * character (spec D10, R103). buildSoql is pure: the places live only in memory, no record is
 * inserted, and the excluded-contact override stands in for the custom metadata read.
 */
@IsTest
private class LaneSearchQueryBuilderTest {
  // Copied character by character from LaneSearchQueryBuilder.SELECT_CLAUSE.
  private static final String SELECT_CLAUSE =
    'SELECT Id, Name, rtms__Load__c, Origin__c, Destination__c, Mode__c, Equipment_Type__c, ' +
    'rtms__Load__r.rtms__Equipment_Type__r.rtms__Category__c, rtms__Load__r.rtms__Distance_Miles__c, ' +
    'Carrier_Name__c, Carrier_Contact__c, ' +
    'CurrencyIsoCode, rtms__Carrier_Total__c, Quote_Date__c, Hazmat__c, rtms__Accepted__c, Load_Status__c, Ops_Comments__c, ' +
    'Contact_Email__c, Contact_Phone__c, Carrier_Risk__c, Nb_of_loads__c, Carrier_Att__c, ' +
    'CreatedDate FROM rtms__CarrierQuote__c';
  private static final String WINDOW_90 = ' WHERE CreatedDate = LAST_N_DAYS:90 AND Contact_ID__c NOT IN :excluded';
  private static final String ORDER_AND_LIMIT = ' ORDER BY CreatedDate DESC LIMIT :rowLimitPlusOne';
  private static final String CITY_BOTH_ENDS = ' AND rtms__Load__r.rtms__City_Lane__c LIKE :oCity AND rtms__Load__r.rtms__City_Lane__c LIKE :dCity';
  // Every lane search leaves out Market Test quotes (phase 7); the condition sits between hazmat and accepted.
  private static final String NO_MARKET_TEST = ' AND (NOT Customer_Name__c LIKE :marketTest)';

  private static Map<String, Pricing_Place__c> places() {
    return new Map<String, Pricing_Place__c>{
      'montreal|qc|ca' => new Pricing_Place__c(
        Key__c = 'montreal|qc|ca',
        City__c = 'Montréal',
        Province__c = 'QC',
        Country__c = 'CA',
        Postal_Prefix__c = 'H1A',
        Geolocation__Latitude__s = 45.5019,
        Geolocation__Longitude__s = -73.5674
      ),
      'toronto|on|ca' => new Pricing_Place__c(
        Key__c = 'toronto|on|ca',
        City__c = 'Toronto',
        Province__c = 'ON',
        Country__c = 'CA',
        Postal_Prefix__c = 'M5V',
        Geolocation__Latitude__s = 43.6532,
        Geolocation__Longitude__s = -79.3832
      ),
      'nowhere|zz|ca' => new Pricing_Place__c(
        Key__c = 'nowhere|zz|ca',
        City__c = 'Nowhere',
        Province__c = 'ZZ',
        Country__c = 'CA'
      )
    };
  }

  /** Montréal to Toronto with every field at its declared default (CITY on both ends, 90 days, 2,000 rows). */
  private static LaneSearchRequest req() {
    LaneSearchExclusions.excludedContactIdsOverride = new Set<String>();
    LaneSearchRequest r = new LaneSearchRequest();
    r.originKey = 'montreal|qc|ca';
    r.destinationKey = 'toronto|on|ca';
    return r;
  }

  private static String build(LaneSearchRequest r, Map<String, Object> binds) {
    return LaneSearchQueryBuilder.buildSoql(r, binds, places());
  }

  @IsTest
  static void cityOnBothEndsMatchesTheCityLaneKey() {
    Map<String, Object> binds = new Map<String, Object>();
    String soql = build(req(), binds);
    System.assertEquals(
      SELECT_CLAUSE + WINDOW_90 + CITY_BOTH_ENDS + NO_MARKET_TEST + ORDER_AND_LIMIT,
      soql
    );
    System.assertEquals(
      new Set<String>{ 'excluded', 'oCity', 'dCity', 'marketTest', 'rowLimitPlusOne' },
      binds.keySet()
    );
    System.assertEquals(
      new Set<String>{ 'Montréal, QC:%', 'Montreal, QC:%' },
      new Set<String>((List<String>) binds.get('oCity')),
      'the place spelling and its accent-stripped variant, origin side'
    );
    System.assertEquals(
      new List<String>{ '%:Toronto, ON' },
      binds.get('dCity')
    );
    System.assertEquals(new Set<String>(), binds.get('excluded'));
    System.assertEquals(2001, binds.get('rowLimitPlusOne'));
    System.assertEquals('%Market Test%', binds.get('marketTest'));
  }

  @IsTest
  static void provinceOnBothEndsMatchesTheStateLaneKey() {
    LaneSearchRequest r = req();
    r.originPrecision = LaneSearchRequest.Precision.PROVINCE;
    r.destinationPrecision = LaneSearchRequest.Precision.PROVINCE;
    r.lookbackDays = 30;
    r.rowLimit = 50;
    Map<String, Object> binds = new Map<String, Object>();
    String soql = build(r, binds);
    System.assertEquals(
      SELECT_CLAUSE +
        ' WHERE CreatedDate = LAST_N_DAYS:30 AND Contact_ID__c NOT IN :excluded' +
        ' AND rtms__Load__r.rtms__State_Lane__c LIKE :oProv AND rtms__Load__r.rtms__State_Lane__c LIKE :dProv' +
        NO_MARKET_TEST +
        ORDER_AND_LIMIT,
      soql
    );
    System.assertEquals(
      new Set<String>{ 'excluded', 'oProv', 'dProv', 'marketTest', 'rowLimitPlusOne' },
      binds.keySet()
    );
    System.assertEquals('QC:%', binds.get('oProv'));
    System.assertEquals('%:ON', binds.get('dProv'));
    System.assertEquals(51, binds.get('rowLimitPlusOne'));
  }

  @IsTest
  static void zip3TakesTheExplicitPrefixOrThePlacePrefix() {
    LaneSearchRequest r = req();
    r.originKey = null; // an explicit prefix needs no place
    r.originPrecision = LaneSearchRequest.Precision.ZIP3;
    r.originZip3 = 'H2X';
    r.destinationPrecision = LaneSearchRequest.Precision.ZIP3;
    Map<String, Object> binds = new Map<String, Object>();
    String soql = build(r, binds);
    System.assertEquals(
      SELECT_CLAUSE +
        WINDOW_90 +
        ' AND rtms__Load__r.rtms__Zip3_Lane__c LIKE :oZip3 AND rtms__Load__r.rtms__Zip3_Lane__c LIKE :dZip3' +
        NO_MARKET_TEST +
        ORDER_AND_LIMIT,
      soql
    );
    System.assertEquals(
      new Set<String>{ 'excluded', 'oZip3', 'dZip3', 'marketTest', 'rowLimitPlusOne' },
      binds.keySet()
    );
    System.assertEquals('H2X:%', binds.get('oZip3'));
    System.assertEquals(
      '%:M5V',
      binds.get('dZip3'),
      'no explicit destination prefix: the place prefix'
    );

    r = req();
    r.originPrecision = LaneSearchRequest.Precision.ZIP3;
    r.originZip3 = 'H3B';
    binds = new Map<String, Object>();
    build(r, binds);
    System.assertEquals(
      'H3B:%',
      binds.get('oZip3'),
      'an explicit prefix wins over the place prefix H1A'
    );
  }

  @IsTest
  static void aZip3EndWhosePlaceHasNoPrefixNamesTheFieldToPass() {
    LaneSearchRequest r = req();
    r.destinationKey = 'nowhere|zz|ca';
    r.destinationPrecision = LaneSearchRequest.Precision.ZIP3;
    String message;
    try {
      build(r, new Map<String, Object>());
    } catch (LaneSearchException e) {
      message = e.getMessage();
    }
    System.assertEquals(
      'Place nowhere|zz|ca has no postal prefix; pass destinationZip3',
      message
    );
  }

  @IsTest
  static void anEndWithoutAPlaceAddsNoCondition() {
    LaneSearchRequest r = req();
    r.originKey = null;
    r.originPrecision = LaneSearchRequest.Precision.RADIUS;
    r.originRadius = 25;
    Map<String, Object> binds = new Map<String, Object>();
    String soql = build(r, binds);
    System.assertEquals(
      SELECT_CLAUSE +
        WINDOW_90 +
        ' AND rtms__Load__r.rtms__City_Lane__c LIKE :dCity' +
        NO_MARKET_TEST +
        ORDER_AND_LIMIT,
      soql
    );
    System.assertEquals(
      new Set<String>{ 'excluded', 'dCity', 'marketTest', 'rowLimitPlusOne' },
      binds.keySet()
    );

    r = req();
    r.destinationKey = 'unknown|zz|ca'; // not in the map: CITY adds nothing either
    binds = new Map<String, Object>();
    soql = build(r, binds);
    System.assertEquals(
      SELECT_CLAUSE +
        WINDOW_90 +
        ' AND rtms__Load__r.rtms__City_Lane__c LIKE :oCity' +
        NO_MARKET_TEST +
        ORDER_AND_LIMIT,
      soql
    );
    System.assertEquals(
      new Set<String>{ 'excluded', 'oCity', 'marketTest', 'rowLimitPlusOne' },
      binds.keySet()
    );
  }

  @IsTest
  static void radiusOnBothEndsChecksTheStopAccountAndTheStopGeolocation() {
    LaneSearchRequest r = req();
    r.originPrecision = LaneSearchRequest.Precision.RADIUS;
    r.originRadius = 25;
    r.destinationPrecision = LaneSearchRequest.Precision.RADIUS;
    r.destinationRadius = 50;
    Map<String, Object> binds = new Map<String, Object>();
    String soql = build(r, binds);
    System.assertEquals(
      SELECT_CLAUSE +
        WINDOW_90 +
        ' AND (DISTANCE(rtms__Load__r.rtms__First_Stop__r.rtms__Location2__r.ShippingAddress, GEOLOCATION(:oLat, :oLng), \'mi\') < :oRadius' +
        ' OR DISTANCE(rtms__Load__r.rtms__First_Stop__r.rtms__Geolocation__c, GEOLOCATION(:oLat, :oLng), \'mi\') < :oRadius)' +
        ' AND (DISTANCE(rtms__Load__r.rtms__Last_Stop__r.rtms__Location2__r.ShippingAddress, GEOLOCATION(:dLat, :dLng), \'mi\') < :dRadius' +
        ' OR DISTANCE(rtms__Load__r.rtms__Last_Stop__r.rtms__Geolocation__c, GEOLOCATION(:dLat, :dLng), \'mi\') < :dRadius)' +
        NO_MARKET_TEST +
        ORDER_AND_LIMIT,
      soql
    );
    System.assertEquals(
      new Set<String>{
        'excluded',
        'oLat',
        'oLng',
        'oRadius',
        'dLat',
        'dLng',
        'dRadius',
        'marketTest',
        'rowLimitPlusOne'
      },
      binds.keySet()
    );
    System.assertEquals(45.5019, binds.get('oLat'));
    System.assertEquals(-73.5674, binds.get('oLng'));
    System.assertEquals(25, binds.get('oRadius'));
    System.assertEquals(43.6532, binds.get('dLat'));
    System.assertEquals(-79.3832, binds.get('dLng'));
    System.assertEquals(50, binds.get('dRadius'));
  }

  @IsTest
  static void radiusWithoutStopGeolocationChecksTheStopAccountOnly() {
    LaneSearchRequest r = req();
    r.originPrecision = LaneSearchRequest.Precision.RADIUS;
    r.originRadius = 40;
    r.destinationPrecision = LaneSearchRequest.Precision.RADIUS;
    r.destinationRadius = 80;
    r.radiusUnit = LaneSearchRequest.Unit.KM;
    r.includeStopGeolocation = false;
    Map<String, Object> binds = new Map<String, Object>();
    String soql = build(r, binds);
    System.assertEquals(
      SELECT_CLAUSE +
        WINDOW_90 +
        ' AND DISTANCE(rtms__Load__r.rtms__First_Stop__r.rtms__Location2__r.ShippingAddress, GEOLOCATION(:oLat, :oLng), \'km\') < :oRadius' +
        ' AND DISTANCE(rtms__Load__r.rtms__Last_Stop__r.rtms__Location2__r.ShippingAddress, GEOLOCATION(:dLat, :dLng), \'km\') < :dRadius' +
        NO_MARKET_TEST +
        ORDER_AND_LIMIT,
      soql
    );
    System.assertEquals(
      new Set<String>{
        'excluded',
        'oLat',
        'oLng',
        'oRadius',
        'dLat',
        'dLng',
        'dRadius',
        'marketTest',
        'rowLimitPlusOne'
      },
      binds.keySet()
    );
  }

  @IsTest
  static void everyFilterFollowsTheLaneInItsFixedOrder() {
    LaneSearchRequest r = req();
    r.currencyIsoCode = 'CAD';
    r.modes = new List<String>{ 'Truckload' };
    r.equipmentCategories = new List<String>{ 'Van' };
    r.equipmentTypes = new List<String>{ 'Dry Van 53\'' };
    r.hazmatOnly = true;
    r.acceptedFilter = LaneSearchRequest.Accepted.ACCEPTED;
    Map<String, Object> binds = new Map<String, Object>();
    String soql = build(r, binds);
    System.assertEquals(
      SELECT_CLAUSE +
        WINDOW_90 +
        CITY_BOTH_ENDS +
        ' AND CurrencyIsoCode = :currencyCode' +
        ' AND rtms__Load__r.rtms__Mode__r.Name IN :modes' +
        ' AND (rtms__Load__r.rtms__Equipment_Type__r.rtms__Category__c IN :cats OR rtms__Load__r.rtms__Equipment_Type__r.Name IN :types)' +
        ' AND rtms__Load__r.rtms__Hazardous_Materials__c = true' +
        NO_MARKET_TEST +
        ' AND rtms__Accepted__c = true' +
        ORDER_AND_LIMIT,
      soql
    );
    System.assertEquals(
      new Set<String>{
        'excluded',
        'oCity',
        'dCity',
        'currencyCode',
        'modes',
        'cats',
        'types',
        'marketTest',
        'rowLimitPlusOne'
      },
      binds.keySet()
    );
    System.assertEquals('CAD', binds.get('currencyCode'));
    System.assertEquals(r.modes, binds.get('modes'));
    System.assertEquals(r.equipmentCategories, binds.get('cats'));
    System.assertEquals(r.equipmentTypes, binds.get('types'));
    System.assertEquals('%Market Test%', binds.get('marketTest'));
  }

  @IsTest
  static void categoriesAloneTypesAloneAndDeclined() {
    LaneSearchRequest r = req();
    r.equipmentCategories = new List<String>{ 'Van' };
    r.acceptedFilter = LaneSearchRequest.Accepted.DECLINED;
    Map<String, Object> binds = new Map<String, Object>();
    String soql = build(r, binds);
    System.assertEquals(
      SELECT_CLAUSE +
        WINDOW_90 +
        CITY_BOTH_ENDS +
        ' AND rtms__Load__r.rtms__Equipment_Type__r.rtms__Category__c IN :cats' +
        NO_MARKET_TEST +
        ' AND rtms__Accepted__c = false' +
        ORDER_AND_LIMIT,
      soql
    );
    System.assertEquals(
      new Set<String>{
        'excluded',
        'oCity',
        'dCity',
        'cats',
        'marketTest',
        'rowLimitPlusOne'
      },
      binds.keySet()
    );

    r = req();
    r.equipmentTypes = new List<String>{ 'Dry Van 53\'' };
    binds = new Map<String, Object>();
    soql = build(r, binds);
    System.assertEquals(
      SELECT_CLAUSE +
        WINDOW_90 +
        CITY_BOTH_ENDS +
        ' AND rtms__Load__r.rtms__Equipment_Type__r.Name IN :types' +
        NO_MARKET_TEST +
        ORDER_AND_LIMIT,
      soql
    );
    System.assertEquals(
      new Set<String>{
        'excluded',
        'oCity',
        'dCity',
        'types',
        'marketTest',
        'rowLimitPlusOne'
      },
      binds.keySet()
    );
  }
}
```

Create `force-app/main/default/classes/LaneSearchQueryBuilderTest.cls-meta.xml`:

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<ApexClass xmlns="http://soap.sforce.com/2006/04/metadata">
    <apiVersion>64.0</apiVersion>
    <status>Active</status>
</ApexClass>
```

- [ ] **Step 3: Deploy the characterization test on the unchanged code and see it PASS**

This is a characterization test, not a failing test: it describes the code as it is, so it must pass before anything moves. Nothing else is deployed with it.

Run: `sf project deploy start -o sandbox --source-dir force-app/main/default/classes/LaneSearchQueryBuilderTest.cls -l RunSpecifiedTests -t LaneSearchQueryBuilderTest --async --json | python3 -c "import json,sys; s=sys.stdin.read(); print(json.loads(s[s.index('{'):])['result']['id'])"`

Expected: a deploy id (`0Af…`). Poll, repeating until the status is `Succeeded` or `Failed` (each call waits at most 2 minutes):

Run: `sf project deploy report -o sandbox --job-id <id> -w 2 --json | python3 -c "import json,sys; s=sys.stdin.read(); j=json.loads(s[s.index('{'):]); r=j.get('result') or {}; d=r.get('details') or {}; L=lambda v: v if isinstance(v, list) else ([v] if v else []); print(r.get('status') or j.get('name'), 'tests', r.get('numberTestsCompleted'), '/', r.get('numberTestsTotal'), 'failures', r.get('numberTestErrors')); [print('COMPILE', c.get('fullName'), c.get('lineNumber'), c.get('problem')) for c in L(d.get('componentFailures'))]; [print('FAIL', f.get('name'), f.get('methodName'), '->', str(f.get('message'))[:300]) for f in L((d.get('runTestResult') or {}).get('failures'))]"`

Expected: `Succeeded tests 9 / 9 failures 0`, and no `COMPILE` or `FAIL` line.

If a `FAIL` line appears here, the test is wrong, not the builder: the builder is the reference at this step. Correct that expected string or bind set from the failure message (it prints both values), redeploy, and name the corrected case in the task report. Do not go on to Step 4 until this deploy shows 9 / 9 on the unchanged `LaneSearchQueryBuilder` and `LaneSearchFilters`.

Then record the test file's fingerprint; Step 13 checks that the extraction did not touch it:

Run: `shasum -a 256 force-app/main/default/classes/LaneSearchQueryBuilderTest.cls`

Expected: one hash line. Keep it for Step 13.

- [ ] **Step 4: Write the failing matcher test**

`LaneKeyMatcherTest` covers the shapes the lane search never builds: `rtms__Load__c` rows (`loadPath` `''`), a RADIUS end read as CITY, an end without a place, the missing-prefix message for both ends, LIKE escaping, and `LaneLoadFilters` with `''` and with categories or types alone.

Create `force-app/main/default/classes/LaneKeyMatcherTest.cls`:

```apex
/**
 * LaneKeyMatcher and LaneLoadFilters on their own, for the row shapes the lane search never builds:
 * rtms__Load__c rows (loadPath ''), a RADIUS end read as CITY, and a missing place. The lane search's
 * own shapes are pinned by LaneSearchQueryBuilderTest. Pure: no record is inserted.
 */
@IsTest
private class LaneKeyMatcherTest {
  private static Pricing_Place__c montreal() {
    return new Pricing_Place__c(
      Key__c = 'montreal|qc|ca',
      City__c = 'Montréal',
      Province__c = 'QC',
      Country__c = 'CA',
      Postal_Prefix__c = 'H1A'
    );
  }

  private static Pricing_Place__c toronto() {
    return new Pricing_Place__c(
      Key__c = 'toronto|on|ca',
      City__c = 'Toronto',
      Province__c = 'ON',
      Country__c = 'CA',
      Postal_Prefix__c = 'M5V'
    );
  }

  @IsTest
  static void cityOnALoadRowHasNoRelationshipPath() {
    Map<String, Object> binds = new Map<String, Object>();
    String origin = LaneKeyMatcher.condition(
      '',
      true,
      'o',
      LaneSearchRequest.Precision.CITY,
      montreal(),
      null,
      binds
    );
    String destination = LaneKeyMatcher.condition(
      '',
      false,
      'd',
      LaneSearchRequest.Precision.CITY,
      toronto(),
      null,
      binds
    );
    System.assertEquals('rtms__City_Lane__c LIKE :oCity', origin);
    System.assertEquals('rtms__City_Lane__c LIKE :dCity', destination);
    System.assertEquals(new Set<String>{ 'oCity', 'dCity' }, binds.keySet());
    System.assertEquals(
      new Set<String>{ 'Montréal, QC:%', 'Montreal, QC:%' },
      new Set<String>((List<String>) binds.get('oCity'))
    );
    System.assertEquals(
      new List<String>{ '%:Toronto, ON' },
      binds.get('dCity')
    );
  }

  @IsTest
  static void provinceAndZip3OnAQuoteRowGoThroughTheLoad() {
    Map<String, Object> binds = new Map<String, Object>();
    System.assertEquals(
      'rtms__Load__r.rtms__State_Lane__c LIKE :oProv',
      LaneKeyMatcher.condition(
        'rtms__Load__r.',
        true,
        'o',
        LaneSearchRequest.Precision.PROVINCE,
        montreal(),
        null,
        binds
      )
    );
    System.assertEquals(
      'rtms__Load__r.rtms__Zip3_Lane__c LIKE :dZip3',
      LaneKeyMatcher.condition(
        'rtms__Load__r.',
        false,
        'd',
        LaneSearchRequest.Precision.ZIP3,
        toronto(),
        null,
        binds
      )
    );
    System.assertEquals('QC:%', binds.get('oProv'));
    System.assertEquals('%:M5V', binds.get('dZip3'));
  }

  @IsTest
  static void anExplicitZip3WinsAndNeedsNoPlace() {
    Map<String, Object> binds = new Map<String, Object>();
    System.assertEquals(
      'rtms__Zip3_Lane__c LIKE :oZip3',
      LaneKeyMatcher.condition(
        '',
        true,
        'o',
        LaneSearchRequest.Precision.ZIP3,
        null,
        'H2X',
        binds
      )
    );
    LaneKeyMatcher.condition(
      '',
      false,
      'd',
      LaneSearchRequest.Precision.ZIP3,
      toronto(),
      'M4W',
      binds
    );
    System.assertEquals('H2X:%', binds.get('oZip3'));
    System.assertEquals(
      '%:M4W',
      binds.get('dZip3'),
      'the explicit prefix, not the place prefix M5V'
    );
  }

  @IsTest
  static void radiusReadsAsCity() {
    Map<String, Object> cityBinds = new Map<String, Object>();
    String city = LaneKeyMatcher.condition(
      '',
      true,
      'o',
      LaneSearchRequest.Precision.CITY,
      montreal(),
      null,
      cityBinds
    );
    Map<String, Object> radiusBinds = new Map<String, Object>();
    String radius = LaneKeyMatcher.condition(
      '',
      true,
      'o',
      LaneSearchRequest.Precision.RADIUS,
      montreal(),
      null,
      radiusBinds
    );
    System.assertEquals(city, radius);
    System.assertEquals(
      cityBinds,
      radiusBinds,
      'the same city patterns, and no latitude, longitude or radius bind'
    );
  }

  @IsTest
  static void noPlaceMeansNoConstraint() {
    Map<String, Object> binds = new Map<String, Object>();
    for (LaneSearchRequest.Precision p : LaneSearchRequest.Precision.values()) {
      System.assertEquals(
        null,
        LaneKeyMatcher.condition('', true, 'o', p, null, null, binds),
        String.valueOf(p)
      );
    }
    System.assertEquals(
      null,
      LaneKeyMatcher.condition(
        '',
        true,
        'o',
        LaneSearchRequest.Precision.CITY,
        null,
        'H2X',
        binds
      ),
      'an explicit prefix counts only on a ZIP3 end'
    );
    System.assert(binds.isEmpty(), 'nothing is bound: ' + binds);
  }

  @IsTest
  static void aZip3EndWithoutAPostalPrefixNamesTheFieldToPass() {
    Pricing_Place__c noPrefix = montreal();
    noPrefix.Postal_Prefix__c = null;
    List<String> messages = new List<String>();
    for (Boolean isOrigin : new List<Boolean>{ true, false }) {
      try {
        LaneKeyMatcher.condition(
          '',
          isOrigin,
          isOrigin ? 'o' : 'd',
          LaneSearchRequest.Precision.ZIP3,
          noPrefix,
          null,
          new Map<String, Object>()
        );
      } catch (LaneSearchException e) {
        messages.add(e.getMessage());
      }
    }
    System.assertEquals(
      new List<String>{
        'Place montreal|qc|ca has no postal prefix; pass originZip3',
        'Place montreal|qc|ca has no postal prefix; pass destinationZip3'
      },
      messages
    );
  }

  @IsTest
  static void likeWildcardsInASpellingAreEscaped() {
    Pricing_Place__c odd = new Pricing_Place__c(
      Key__c = 'st jean 100|qc|ca',
      City__c = 'St_Jean 100%',
      Province__c = 'QC'
    );
    Map<String, Object> binds = new Map<String, Object>();
    LaneKeyMatcher.condition(
      '',
      false,
      'd',
      LaneSearchRequest.Precision.CITY,
      odd,
      null,
      binds
    );
    System.assertEquals(
      new List<String>{ '%:St\\_Jean 100\\%, QC' },
      binds.get('dCity')
    );
  }

  @IsTest
  static void loadFiltersOnALoadRowHaveNoRelationshipPath() {
    LaneSearchRequest r = new LaneSearchRequest();
    r.modes = new List<String>{ 'Truckload' };
    r.equipmentCategories = new List<String>{ 'Van' };
    r.equipmentTypes = new List<String>{ 'Dry Van 53\'' };
    r.hazmatOnly = true;
    r.currencyIsoCode = 'CAD';
    r.acceptedFilter = LaneSearchRequest.Accepted.ACCEPTED;
    List<String> conditions = new List<String>();
    Map<String, Object> binds = new Map<String, Object>();
    LaneLoadFilters.add(r, '', conditions, binds);
    System.assertEquals(
      new List<String>{
        'rtms__Mode__r.Name IN :modes',
        '(rtms__Equipment_Type__r.rtms__Category__c IN :cats OR rtms__Equipment_Type__r.Name IN :types)',
        'rtms__Hazardous_Materials__c = true'
      },
      conditions,
      'currency and accepted are quote filters, and the Market Test exclusion a quote condition: never load filters'
    );
    System.assertEquals(
      new Set<String>{ 'modes', 'cats', 'types' },
      binds.keySet()
    );
    System.assertEquals(r.modes, binds.get('modes'));
    System.assertEquals(r.equipmentCategories, binds.get('cats'));
    System.assertEquals(r.equipmentTypes, binds.get('types'));
  }

  @IsTest
  static void loadFiltersTakeCategoriesOrTypesAloneAndNothingWhenUnset() {
    LaneSearchRequest cats = new LaneSearchRequest();
    cats.equipmentCategories = new List<String>{ 'Van' };
    List<String> conditions = new List<String>();
    Map<String, Object> binds = new Map<String, Object>();
    LaneLoadFilters.add(cats, 'rtms__Load__r.', conditions, binds);
    System.assertEquals(
      new List<String>{
        'rtms__Load__r.rtms__Equipment_Type__r.rtms__Category__c IN :cats'
      },
      conditions
    );
    System.assertEquals(new Set<String>{ 'cats' }, binds.keySet());

    LaneSearchRequest types = new LaneSearchRequest();
    types.equipmentTypes = new List<String>{ 'Dry Van 53\'' };
    conditions = new List<String>();
    binds = new Map<String, Object>();
    LaneLoadFilters.add(types, '', conditions, binds);
    System.assertEquals(
      new List<String>{ 'rtms__Equipment_Type__r.Name IN :types' },
      conditions
    );
    System.assertEquals(new Set<String>{ 'types' }, binds.keySet());

    // Field initializers (empty lists, hazmat false), then a JSON request that left them out (null).
    LaneSearchRequest unset = new LaneSearchRequest();
    LaneSearchRequest fromJson = (LaneSearchRequest) JSON.deserialize(
      '{"originKey":"montreal|qc|ca"}',
      LaneSearchRequest.class
    );
    conditions = new List<String>();
    binds = new Map<String, Object>();
    LaneLoadFilters.add(unset, '', conditions, binds);
    LaneLoadFilters.add(fromJson, '', conditions, binds);
    System.assert(conditions.isEmpty(), 'no condition: ' + conditions);
    System.assert(binds.isEmpty(), 'no bind: ' + binds);
  }
}
```

Create `force-app/main/default/classes/LaneKeyMatcherTest.cls-meta.xml`:

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<ApexClass xmlns="http://soap.sforce.com/2006/04/metadata">
    <apiVersion>64.0</apiVersion>
    <status>Active</status>
</ApexClass>
```

- [ ] **Step 5: Deploy the matcher test alone to see it fail to compile**

Run: `sf project deploy start -o sandbox --source-dir force-app/main/default/classes/LaneKeyMatcherTest.cls -l NoTestRun --async --json | python3 -c "import json,sys; s=sys.stdin.read(); print(json.loads(s[s.index('{'):])['result']['id'])"`

Expected: a deploy id. Poll until `Succeeded` or `Failed`:

Run: `sf project deploy report -o sandbox --job-id <id> -w 2 --json | python3 -c "import json,sys; s=sys.stdin.read(); j=json.loads(s[s.index('{'):]); r=j.get('result') or {}; d=r.get('details') or {}; L=lambda v: v if isinstance(v, list) else ([v] if v else []); print(r.get('status') or j.get('name'), 'tests', r.get('numberTestsCompleted'), '/', r.get('numberTestsTotal'), 'failures', r.get('numberTestErrors')); [print('COMPILE', c.get('fullName'), c.get('lineNumber'), c.get('problem')) for c in L(d.get('componentFailures'))]; [print('FAIL', f.get('name'), f.get('methodName'), '->', str(f.get('message'))[:300]) for f in L((d.get('runTestResult') or {}).get('failures'))]"`

Expected: `Failed tests 0 / 0 failures 0` (the counts may print as `None` on a `NoTestRun` deploy), then `COMPILE LaneKeyMatcherTest <line> Variable does not exist: LaneKeyMatcher` or `Invalid type: LaneKeyMatcher`. The same problem naming `LaneLoadFilters` is also expected. Neither class exists yet. Any other problem, for example `Variable does not exist: excludedContactIdsOverride` or a field on `Pricing_Place__c`, is a typo in the test: fix it before Step 6.

- [ ] **Step 6: Create `LaneKeyMatcher`**

The body is `addCity`, `addProvince`, `addZip3`, `requirePostalPrefix` and `laneLikePattern` from `LaneSearchQueryBuilder`, with the relationship path and the origin flag as parameters in place of the `LaneEnd` fields. The error message reads the place's `Key__c`, which equals the request key the search used: `LaneSearchService.loadPlaces` keys its map by `Key__c` and throws `Unknown place key` for any key it did not find exactly.

Create `force-app/main/default/classes/LaneKeyMatcher.cls`:

```apex
/**
 * One end of a lane as a Revenova lane-key condition: the city, province or postal-prefix LIKE
 * pattern for that end, bound under the end's bind prefix. Pure: no SOQL, no DML. Phase 8 moved
 * this out of LaneSearchQueryBuilder (its addCity, addProvince, addZip3, requirePostalPrefix and
 * laneLikePattern) so the lane search, CarrierLeadService and SplitLaneService match a lane the same
 * way (spec R103); LaneSearchQueryBuilderTest proves the search's SOQL did not change.
 *
 * loadPath is the relationship path from the queried row to its load: 'rtms__Load__r.' on
 * rtms__CarrierQuote__c and rtms__FreightPlanLoad__c rows, '' on rtms__Load__c rows. Only the lane
 * search draws a radius (LaneSearchQueryBuilder.addRadius, through the stops); here RADIUS reads as
 * CITY, because the deeper steps use a radius end's place city key (spec R83).
 */
public with sharing class LaneKeyMatcher {
  /**
   * The condition for one end, after putting its pattern into binds under bindPrefix + 'City',
   * 'Prov' or 'Zip3'; null when the end has no constraint (no place, and no explicit ZIP3 prefix on
   * a ZIP3 end). The parameter is endPrecision, not precision: Apex is case-insensitive, and the
   * same collision with the Precision enum is documented in LaneSearchRequest.validateRadius.
   */
  public static String condition(
    String loadPath,
    Boolean isOrigin,
    String bindPrefix,
    LaneSearchRequest.Precision endPrecision,
    Pricing_Place__c place,
    String explicitZip3,
    Map<String, Object> binds
  ) {
    if (endPrecision == LaneSearchRequest.Precision.ZIP3) {
      return zip3Condition(
        loadPath,
        isOrigin,
        bindPrefix,
        place,
        explicitZip3,
        binds
      );
    }
    if (place == null) {
      return null;
    }
    if (endPrecision == LaneSearchRequest.Precision.PROVINCE) {
      binds.put(bindPrefix + 'Prov', likePattern(isOrigin, place.Province__c));
      return loadPath + 'rtms__State_Lane__c LIKE :' + bindPrefix + 'Prov';
    }
    List<String> patterns = new List<String>();
    for (String v : PlaceNormalizer.cityLaneVariants(place)) {
      patterns.add(likePattern(isOrigin, v));
    }
    binds.put(bindPrefix + 'City', patterns);
    return loadPath + 'rtms__City_Lane__c LIKE :' + bindPrefix + 'City';
  }

  /** An explicit prefix needs no place; without one, the place's own prefix is required. */
  private static String zip3Condition(
    String loadPath,
    Boolean isOrigin,
    String bindPrefix,
    Pricing_Place__c place,
    String explicitZip3,
    Map<String, Object> binds
  ) {
    String prefix = explicitZip3;
    if (String.isBlank(prefix)) {
      if (place == null) {
        return null;
      }
      if (String.isBlank(place.Postal_Prefix__c)) {
        throw new LaneSearchException(
          'Place ' +
            place.Key__c +
            ' has no postal prefix; pass ' +
            (isOrigin == true ? 'originZip3' : 'destinationZip3')
        );
      }
      prefix = place.Postal_Prefix__c;
    }
    binds.put(bindPrefix + 'Zip3', likePattern(isOrigin, prefix));
    return loadPath + 'rtms__Zip3_Lane__c LIKE :' + bindPrefix + 'Zip3';
  }

  /** "value:%" for an origin, "%:value" for a destination - the shared shape of every lane LIKE pattern. */
  private static String likePattern(Boolean isOrigin, String rawValue) {
    String escaped = LaneSearchQueryBuilder.escapeLike(rawValue);
    return isOrigin == true ? escaped + ':%' : '%:' + escaped;
  }
}
```

Create `force-app/main/default/classes/LaneKeyMatcher.cls-meta.xml`:

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<ApexClass xmlns="http://soap.sforce.com/2006/04/metadata">
    <apiVersion>64.0</apiVersion>
    <status>Active</status>
</ApexClass>
```

- [ ] **Step 7: Create `LaneLoadFilters`**

The body is `addModeFilter`, `addEquipmentFilter` and `addHazmatFilter` from `LaneSearchFilters`, with `loadPath` in place of the literal `rtms__Load__r.`. The bind names do not change. Read-only proof, run in PostProduc on 2026-09-15: `SELECT Id FROM rtms__Load__c WHERE rtms__State_Lane__c LIKE 'QC:%' AND rtms__Zip3_Lane__c LIKE '%:M5V' AND rtms__City_Lane__c LIKE 'Montreal, QC:%' AND rtms__Mode__r.Name IN ('Truckload') AND (rtms__Equipment_Type__r.rtms__Category__c IN ('Van') OR rtms__Equipment_Type__r.Name IN ('Dry Van')) AND rtms__Hazardous_Materials__c = true AND CreatedDate = LAST_N_DAYS:30 LIMIT 1` and the same conditions through `rtms__Load__r.` on `rtms__FreightPlanLoad__c` (with `rtms__Type__c = 'Customer'`) both compile (status 0, 0 rows). So the conditions are valid SOQL with either `loadPath`.

Create `force-app/main/default/classes/LaneLoadFilters.cls`:

```apex
/**
 * The mode, equipment and hazmat conditions a lane request puts on a load. Pure: no SOQL, no DML.
 * Phase 8 moved them out of LaneSearchFilters (its addModeFilter, addEquipmentFilter and
 * addHazmatFilter) so the Carriers to ask and Split-lane services filter a quote's load, a split's
 * customer load and an estimate's leg load exactly as the lane search filters a quote's load (spec
 * R101); LaneSearchQueryBuilderTest proves the search's SOQL did not change.
 *
 * loadPath is the relationship path from the queried row to its load: 'rtms__Load__r.' on
 * rtms__CarrierQuote__c and rtms__FreightPlanLoad__c rows, '' on rtms__Load__c rows. The bind names
 * (modes, cats, types) are the same whatever the path. Currency, accepted and the Market Test
 * exclusion stay in LaneSearchFilters: they read quote fields, not load fields.
 */
public with sharing class LaneLoadFilters {
  public static void add(
    LaneSearchRequest req,
    String loadPath,
    List<String> conditions,
    Map<String, Object> binds
  ) {
    addMode(req, loadPath, conditions, binds);
    addEquipment(req, loadPath, conditions, binds);
    addHazmat(req, loadPath, conditions);
  }

  private static void addMode(
    LaneSearchRequest req,
    String loadPath,
    List<String> conditions,
    Map<String, Object> binds
  ) {
    if (req.modes != null && !req.modes.isEmpty()) {
      binds.put('modes', req.modes);
      conditions.add(loadPath + 'rtms__Mode__r.Name IN :modes');
    }
  }

  private static void addEquipment(
    LaneSearchRequest req,
    String loadPath,
    List<String> conditions,
    Map<String, Object> binds
  ) {
    Boolean hasCats =
      req.equipmentCategories != null && !req.equipmentCategories.isEmpty();
    Boolean hasTypes =
      req.equipmentTypes != null && !req.equipmentTypes.isEmpty();
    String byCategory =
      loadPath + 'rtms__Equipment_Type__r.rtms__Category__c IN :cats';
    String byType = loadPath + 'rtms__Equipment_Type__r.Name IN :types';
    if (hasCats && hasTypes) {
      binds.put('cats', req.equipmentCategories);
      binds.put('types', req.equipmentTypes);
      conditions.add('(' + byCategory + ' OR ' + byType + ')');
    } else if (hasCats) {
      binds.put('cats', req.equipmentCategories);
      conditions.add(byCategory);
    } else if (hasTypes) {
      binds.put('types', req.equipmentTypes);
      conditions.add(byType);
    }
  }

  private static void addHazmat(
    LaneSearchRequest req,
    String loadPath,
    List<String> conditions
  ) {
    if (req.hazmatOnly == true) {
      conditions.add(loadPath + 'rtms__Hazardous_Materials__c = true');
    }
  }
}
```

Create `force-app/main/default/classes/LaneLoadFilters.cls-meta.xml`:

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<ApexClass xmlns="http://soap.sforce.com/2006/04/metadata">
    <apiVersion>64.0</apiVersion>
    <status>Active</status>
</ApexClass>
```

- [ ] **Step 8: Switch `LaneSearchQueryBuilder` to `LaneKeyMatcher`**

`addEnd` now looks the place up first and sends every non-RADIUS end to `LaneKeyMatcher.condition` with `'rtms__Load__r.'`, adding the condition only when it is not null. A RADIUS end with a place goes to `addRadius`, which is unchanged. A ZIP3 end with an explicit prefix still needs no place, and an end without a place still adds nothing. The condition order, the bind names and every character of the SOQL stay the same.

Replace the whole of `force-app/main/default/classes/LaneSearchQueryBuilder.cls` with:

```apex
/**
 * Builds the dynamic SOQL (with bound values) that LaneSearchService.search() executes. Pure:
 * no SOQL, no DML - just string/condition assembly from a LaneSearchRequest and the places
 * LaneSearchService.loadPlaces() already resolved. Split out of LaneSearchService per the Task 7
 * review ruling ("split the class instead of suppressing"): LaneSearchService now only
 * orchestrates (validate, build, query, dedupe, aggregate); every precision branch that used to
 * push LaneSearchService's class-wide PMD complexity total past 40 lives here instead. Task 7's
 * fix round 1 found this class alone (lane-precision logic plus the filters) still totaled 44
 * against the 40 threshold; fix round 2 moved the currency/mode/equipment/hazmat/
 * accepted filters into their own class, LaneSearchFilters, called from buildSoql below. Phase 8
 * moved the city, province and postal-prefix conditions into LaneKeyMatcher, which the Carriers to
 * ask and Split-lane services share; only the radius (DISTANCE through the stops) stays here.
 * LaneSearchQueryBuilderTest pins the exact SOQL and bind names.
 */
public with sharing class LaneSearchQueryBuilder {
  private static final String SELECT_CLAUSE =
    'SELECT Id, Name, rtms__Load__c, Origin__c, Destination__c, Mode__c, Equipment_Type__c, ' +
    'rtms__Load__r.rtms__Equipment_Type__r.rtms__Category__c, rtms__Load__r.rtms__Distance_Miles__c, ' +
    'Carrier_Name__c, Carrier_Contact__c, ' +
    'CurrencyIsoCode, rtms__Carrier_Total__c, Quote_Date__c, Hazmat__c, rtms__Accepted__c, Load_Status__c, Ops_Comments__c, ' +
    'Contact_Email__c, Contact_Phone__c, Carrier_Risk__c, Nb_of_loads__c, Carrier_Att__c, ' +
    'CreatedDate FROM rtms__CarrierQuote__c';

  // Brief called this local/parameter "where", but WHERE is a reserved Apex identifier (compiler
  // cascade: "Unexpected token 'where'" etc. across this whole method); renamed to "conditions".
  public static String buildSoql(
    LaneSearchRequest req,
    Map<String, Object> binds,
    Map<String, Pricing_Place__c> places
  ) {
    List<String> conditions = new List<String>();
    conditions.add(
      'CreatedDate = LAST_N_DAYS:' + String.valueOf(req.lookbackDays)
    ); // validated positive integer, not user text
    binds.put('excluded', LaneSearchExclusions.excludedContactIdSet());
    conditions.add('Contact_ID__c NOT IN :excluded');
    addEnd(conditions, binds, req, originEnd(req), places);
    addEnd(conditions, binds, req, destinationEnd(req), places);
    LaneSearchFilters.addFilters(req, conditions, binds);
    binds.put('rowLimitPlusOne', req.rowLimit + 1);
    return SELECT_CLAUSE +
      ' WHERE ' +
      String.join(conditions, ' AND ') +
      ' ORDER BY CreatedDate DESC LIMIT :rowLimitPlusOne';
  }

  /**
   * Every per-end value addEnd and addRadius need, resolved once for origin or destination by
   * originEnd()/destinationEnd() below. Bundling these (rather than branching on an isOrigin flag
   * inside each helper) means the origin/destination choice is decided exactly once per search,
   * not re-decided in every helper - see those two builders' doc comment for why that matters for
   * PMD's class-wide complexity total.
   */
  private class LaneEnd {
    String key;
    Boolean isOrigin; // passed to LaneKeyMatcher, which shapes the LIKE pattern and error from it
    LaneSearchRequest.Precision precision;
    String explicitZip3;
    Decimal radius;
    String bindPrefix; // 'o' or 'd' - the SOQL bind-variable name prefix for this end
    String stopRel; // relationship path from rtms__CarrierQuote__c to this end's Stop
  }

  /**
   * originEnd()/destinationEnd() are the only places that decide "which side": every value they
   * set is a straight assignment, so neither method has a branch of its own. Task 5's single addEnd
   * re-derived each of these per call with its own isOrigin ternary (cyclomatic 18-21, suppressed).
   * Task 6 needed a real RADIUS branch on top of that, which would have pushed the class past PMD's
   * total-complexity threshold; resolving origin vs. destination exactly once here, instead of once
   * per helper, keeps every method below (addRadius, the largest, is at 6) with no suppression needed.
   */
  private static LaneEnd originEnd(LaneSearchRequest req) {
    LaneEnd e = new LaneEnd();
    e.key = req.originKey;
    e.isOrigin = true;
    e.precision = req.originPrecision;
    e.explicitZip3 = req.originZip3;
    e.radius = req.originRadius;
    e.bindPrefix = 'o';
    e.stopRel = 'rtms__Load__r.rtms__First_Stop__r';
    return e;
  }

  private static LaneEnd destinationEnd(LaneSearchRequest req) {
    LaneEnd e = new LaneEnd();
    e.key = req.destinationKey;
    e.isOrigin = false;
    e.precision = req.destinationPrecision;
    e.explicitZip3 = req.destinationZip3;
    e.radius = req.destinationRadius;
    e.bindPrefix = 'd';
    e.stopRel = 'rtms__Load__r.rtms__Last_Stop__r';
    return e;
  }

  // Per-precision dispatch. CITY, PROVINCE and ZIP3 (with an explicit prefix or the place's own)
  // go to LaneKeyMatcher, which returns null when the end has no constraint; RADIUS stays here.
  // buildSoql runs after LaneSearchRequest.validate(), which defaults a missing precision to CITY.
  private static void addEnd(
    List<String> conditions,
    Map<String, Object> binds,
    LaneSearchRequest req,
    LaneEnd e,
    Map<String, Pricing_Place__c> places
  ) {
    // places only ever holds non-blank keys (see loadPlaces), and Map.get(null) is a safe miss, so
    // a blank e.key already falls through to null here without a separate blank check.
    Pricing_Place__c place = places.get(e.key);
    if (e.precision != LaneSearchRequest.Precision.RADIUS) {
      String laneKey = LaneKeyMatcher.condition(
        'rtms__Load__r.',
        e.isOrigin,
        e.bindPrefix,
        e.precision,
        place,
        e.explicitZip3,
        binds
      );
      if (laneKey != null) {
        conditions.add(laneKey);
      }
    } else if (place != null) {
      addRadius(conditions, binds, req, e, place);
    }
  }

  // Bound decimals inside GEOLOCATION() work through Database.queryWithBinds in this org (API
  // v64.0, PostProduc sandbox, deploy 0AfbZ00000CnnzxSAB); the brief's
  // String.valueOf(decimal.setScale(6)) fallback was not needed.
  private static void addRadius(
    List<String> conditions,
    Map<String, Object> binds,
    LaneSearchRequest req,
    LaneEnd e,
    Pricing_Place__c place
  ) {
    if (
      place.Geolocation__Latitude__s == null ||
      place.Geolocation__Longitude__s == null
    ) {
      throw new LaneSearchException('Place ' + e.key + ' has no coordinates');
    }
    String unit = req.radiusUnit == LaneSearchRequest.Unit.KM ? 'km' : 'mi'; // enum-controlled literal, never user text
    binds.put(e.bindPrefix + 'Lat', place.Geolocation__Latitude__s);
    binds.put(e.bindPrefix + 'Lng', place.Geolocation__Longitude__s);
    binds.put(e.bindPrefix + 'Radius', e.radius);
    String geo =
      'GEOLOCATION(:' +
      e.bindPrefix +
      'Lat, :' +
      e.bindPrefix +
      'Lng)';
    String byAccount =
      'DISTANCE(' +
      e.stopRel +
      '.rtms__Location2__r.ShippingAddress, ' +
      geo +
      ', \'' +
      unit +
      '\') < :' +
      e.bindPrefix +
      'Radius';
    if (req.includeStopGeolocation) {
      String byStop =
        'DISTANCE(' +
        e.stopRel +
        '.rtms__Geolocation__c, ' +
        geo +
        ', \'' +
        unit +
        '\') < :' +
        e.bindPrefix +
        'Radius';
      conditions.add('(' + byAccount + ' OR ' + byStop + ')');
    } else {
      conditions.add(byAccount);
    }
  }

  /** Escapes SOQL LIKE wildcards in user-derived text. */
  public static String escapeLike(String s) {
    return s == null
      ? ''
      : s.replace('\\', '\\\\').replace('%', '\\%').replace('_', '\\_');
  }
}
```

- [ ] **Step 9: Switch `LaneSearchFilters` to `LaneLoadFilters`**

`addFilters` calls `LaneLoadFilters.add(req, 'rtms__Load__r.', conditions, binds)` where the three removed helpers were called. The order is still currency, mode, equipment, hazmat, the Market Test exclusion, accepted.

Replace the whole of `force-app/main/default/classes/LaneSearchFilters.cls` with:

```apex
/**
 * Task 7's currency/mode/equipment/hazmat/accepted filters, plus the Market Test exclusion. Pure: no SOQL, no DML -
 * just condition/bind assembly from a LaneSearchRequest, appended to the conditions/binds
 * LaneSearchQueryBuilder.buildSoql() is assembling. Split out of LaneSearchQueryBuilder per the
 * Task 7 review ruling ("split the filters out"): LaneSearchQueryBuilder alone (lane-precision
 * logic plus these filters in one class) totaled cyclomatic complexity 44 against PMD's 40
 * threshold even though no individual method was over its own per-method threshold; moving this
 * filter family into its own class-wide total resolves it without any suppression. Phase 8 moved
 * the mode, equipment and hazmat conditions (load fields) into LaneLoadFilters, which the Carriers
 * to ask and Split-lane services share; this class keeps the quote filters and the order.
 */
public with sharing class LaneSearchFilters {
  // addFilters itself stays a small dispatcher; one helper per filter so no single method carries
  // every branch. The order (currency, mode, equipment, hazmat, Market Test exclusion, accepted) is pinned
  // by LaneSearchQueryBuilderTest.
  public static void addFilters(
    LaneSearchRequest req,
    List<String> conditions,
    Map<String, Object> binds
  ) {
    addCurrencyFilter(req, conditions, binds);
    LaneLoadFilters.add(req, 'rtms__Load__r.', conditions, binds);
    addMarketTestExclusion(conditions, binds);
    addAcceptedFilter(req, conditions);
  }

  private static void addCurrencyFilter(
    LaneSearchRequest req,
    List<String> conditions,
    Map<String, Object> binds
  ) {
    if (String.isNotBlank(req.currencyIsoCode)) {
      binds.put('currencyCode', req.currencyIsoCode);
      conditions.add('CurrencyIsoCode = :currencyCode');
    }
  }

  /**
   * Quotes whose customer is a Market Test account are left out of every lane search (owner,
   * 2026-09-15): pricing reads carrier bids instead. A customer name is always set on quotes, so
   * NOT LIKE drops only the Market Test quotes (PostProduc, 90 days: 10,642 = 218 + 10,424).
   */
  private static void addMarketTestExclusion(
    List<String> conditions,
    Map<String, Object> binds
  ) {
    binds.put('marketTest', '%Market Test%');
    conditions.add('(NOT Customer_Name__c LIKE :marketTest)');
  }

  private static void addAcceptedFilter(
    LaneSearchRequest req,
    List<String> conditions
  ) {
    if (req.acceptedFilter == LaneSearchRequest.Accepted.ACCEPTED) {
      conditions.add('rtms__Accepted__c = true');
    } else if (req.acceptedFilter == LaneSearchRequest.Accepted.DECLINED) {
      conditions.add('rtms__Accepted__c = false');
    }
  }
}
```

- [ ] **Step 10: Add the classes to the manifest**

In `manifest/package.xml`, inside the `<types>` block whose `<name>` is `ApexClass`, directly before `<name>ApexClass</name>` (after the members Task 1 added):

```xml
        <members>LaneSearchQueryBuilderTest</members>
        <members>LaneKeyMatcher</members>
        <members>LaneKeyMatcherTest</members>
        <members>LaneLoadFilters</members>
```

Run: `grep -c -E "<members>(LaneSearchQueryBuilderTest|LaneKeyMatcher|LaneKeyMatcherTest|LaneLoadFilters)</members>" manifest/package.xml`

Expected: `4`.

- [ ] **Step 11: PMD and the complexity budget**

Run: `/private/tmp/pmd_install/pmd-bin-7.15.0/bin/pmd check --dir force-app --rulesets config/pmd-ruleset.xml --minimum-priority 3 --format text --fail-on-violation; echo "pmd exit $?"`

Expected: no violation lines, `pmd exit 0`. No suppression is added in this task.

Run: `/private/tmp/pmd_install/pmd-bin-7.15.0/bin/pmd check --dir force-app/main/default/classes/LaneSearchQueryBuilder.cls --dir force-app/main/default/classes/LaneSearchFilters.cls --dir force-app/main/default/classes/LaneKeyMatcher.cls --dir force-app/main/default/classes/LaneLoadFilters.cls --rulesets /private/tmp/pmd_install/phase8-complexity.xml --format text --no-cache 2>/dev/null | grep "The class"`

Expected: four lines with these totals. They were measured with PMD 7.15.0 on a copy of the tree holding exactly the code above:

```
…LaneKeyMatcher.cls:13:	CyclomaticComplexity:	The class 'LaneKeyMatcher' has a total cyclomatic complexity of 13 (highest 6).
…LaneLoadFilters.cls:13:	CyclomaticComplexity:	The class 'LaneLoadFilters' has a total cyclomatic complexity of 11 (highest 5).
…LaneSearchFilters.cls:12:	CyclomaticComplexity:	The class 'LaneSearchFilters' has a total cyclomatic complexity of 7 (highest 3).
…LaneSearchQueryBuilder.cls:15:	CyclomaticComplexity:	The class 'LaneSearchQueryBuilder' has a total cyclomatic complexity of 15 (highest 6).
```

`LaneSearchQueryBuilder` must be below the Step 1 figure (26) and `LaneSearchFilters` below 17. If either is not, a helper was left behind: remove it rather than add a suppression.

- [ ] **Step 12: Deploy the six classes and run the four tests**

`LaneSearchQueryBuilderTest` covers `LaneSearchQueryBuilder` and `LaneSearchFilters`. `LaneKeyMatcherTest` covers `LaneKeyMatcher` and `LaneLoadFilters`. `LaneSearchServiceTest` and `BidSearchServiceTest` prove the search's results did not move.

Run: `sf project deploy start -o sandbox --source-dir force-app/main/default/classes/LaneKeyMatcher.cls --source-dir force-app/main/default/classes/LaneLoadFilters.cls --source-dir force-app/main/default/classes/LaneSearchQueryBuilder.cls --source-dir force-app/main/default/classes/LaneSearchFilters.cls --source-dir force-app/main/default/classes/LaneSearchQueryBuilderTest.cls --source-dir force-app/main/default/classes/LaneKeyMatcherTest.cls -l RunSpecifiedTests -t LaneSearchQueryBuilderTest -t LaneKeyMatcherTest -t LaneSearchServiceTest -t BidSearchServiceTest --async --json | python3 -c "import json,sys; s=sys.stdin.read(); print(json.loads(s[s.index('{'):])['result']['id'])"`

Expected: a deploy id. Poll until `Succeeded` or `Failed`:

Run: `sf project deploy report -o sandbox --job-id <id> -w 2 --json | python3 -c "import json,sys; s=sys.stdin.read(); j=json.loads(s[s.index('{'):]); r=j.get('result') or {}; d=r.get('details') or {}; L=lambda v: v if isinstance(v, list) else ([v] if v else []); print(r.get('status') or j.get('name'), 'tests', r.get('numberTestsCompleted'), '/', r.get('numberTestsTotal'), 'failures', r.get('numberTestErrors')); [print('COMPILE', c.get('fullName'), c.get('lineNumber'), c.get('problem')) for c in L(d.get('componentFailures'))]; [print('FAIL', f.get('name'), f.get('methodName'), '->', str(f.get('message'))[:300]) for f in L((d.get('runTestResult') or {}).get('failures'))]"`

Expected: `Succeeded tests 44 / 44 failures 0`, from 9 `LaneSearchQueryBuilderTest` + 9 `LaneKeyMatcherTest` + 22 `LaneSearchServiceTest` + 4 `BidSearchServiceTest`. If Step 1 printed other counts for the last two, use those. If there is no `COMPILE` or `FAIL` line, the search is unchanged.

How to read a failure:
- A `LaneSearchQueryBuilderTest` failure means the extraction changed the search. The test passed in Step 3, so fix `LaneKeyMatcher`, `LaneLoadFilters` or `addEnd`, never the test. Typical causes: a missing `rtms__Load__r.` prefix, the pattern sides swapped (`isOrigin`), a condition added in a different order, or the error text.
- A `LaneKeyMatcherTest` failure means a `''`-path or RADIUS behaviour differs from this task's Interfaces.
- `LaneSearchServiceTest.placesWithoutCoordinatesOrAPostalPrefixThrow` failing on `destinationZip3` means the ZIP3 message lost the field name.

- [ ] **Step 13: Confirm the characterization test was not edited**

Run: `shasum -a 256 force-app/main/default/classes/LaneSearchQueryBuilderTest.cls`

Expected: the same hash as in Step 3. If it differs, the test was changed after it characterized the old code. Restore the Step 3 content, then redeploy (Step 12) before committing.

Run: `git status --short`

Expected: `M` for `LaneSearchQueryBuilder.cls`, `LaneSearchFilters.cls` and `manifest/package.xml`; `??` for the four new classes and their meta files. `.vscode/settings.json` and the `* 2.*` files show unstaged as before, if present.

- [ ] **Step 14: Commit**

```bash
git add force-app/main/default/classes/LaneSearchQueryBuilderTest.cls force-app/main/default/classes/LaneSearchQueryBuilderTest.cls-meta.xml force-app/main/default/classes/LaneKeyMatcherTest.cls force-app/main/default/classes/LaneKeyMatcherTest.cls-meta.xml force-app/main/default/classes/LaneKeyMatcher.cls force-app/main/default/classes/LaneKeyMatcher.cls-meta.xml force-app/main/default/classes/LaneLoadFilters.cls force-app/main/default/classes/LaneLoadFilters.cls-meta.xml force-app/main/default/classes/LaneSearchQueryBuilder.cls force-app/main/default/classes/LaneSearchFilters.cls manifest/package.xml
git commit -m "Move the lane key and load filter conditions into LaneKeyMatcher and LaneLoadFilters behind a characterization test"
```

Expected: lint-staged runs Prettier on the staged Apex and XML and changes nothing, because every class above was checked with the repo's `.prettierrc` and `prettier-plugin-apex`. The commit lands on `phase-8/carriers-and-split-lanes` with no attribution trailer.

#### Contract notes (Task 2)

1. **The fourth parameter of `LaneKeyMatcher.condition` is named `endPrecision`, not `precision`.** Apex is case-insensitive, and `LaneSearchRequest.validateRadius` records that a parameter named `precision` hides the `Precision` enum. The contract rule is that identifiers never collide case-insensitively. Apex calls are positional, so the signature's types and order are exactly A1's, and callers in Tasks 5 and 9 are unaffected.
2. **An explicit ZIP3 prefix counts only on a ZIP3 end.** A1 says `condition` returns null when there is a "null place and no explicit ZIP3". Read literally, a CITY or PROVINCE end with a prefix but no place could produce a ZIP3 condition. The search never does that: its `addEnd` looked at `explicitZip3` only when the precision was ZIP3. So `condition` returns null for a CITY, PROVINCE or RADIUS end without a place, whatever `explicitZip3` holds (`LaneKeyMatcherTest.noPlaceMeansNoConstraint`). That keeps the search byte-identical. `LaneQueries` (Tasks 5, 9) passes `req.originZip3` and `req.destinationZip3` with the request's own precision, so it matches the search too.
3. **The missing-prefix message reads `place.Key__c`** because `condition` receives no key. It is the same text the search produced from `e.key`: `loadPlaces` keys its map by `Key__c` and refuses any key it did not find exactly. Callers must therefore select `Key__c` on the places they pass. A10, A13 and A14 already do.
4. **A null precision now reads as CITY (through `LaneKeyMatcher`).** It used to fall through to `addRadius`. `buildSoql` runs only after `LaneSearchRequest.validate()`, whose `applyDefaults` sets CITY, so the search cannot reach that case. A null `isOrigin` reads as a destination (`== true`).
5. **Tests beyond the contract's list.** `LaneSearchQueryBuilderTest` has 9 cases; beyond the contract's list they cover:
   - the missing-prefix message, pinned in full;
   - an end without a place (RADIUS with no key, CITY with an unknown key);
   - an explicit prefix winning over the place prefix;
   - categories alone with DECLINED, and types alone, so every branch that moves into `LaneLoadFilters` is characterized.

   `LaneKeyMatcherTest` also covers LIKE escaping in a spelling and a JSON request with null filter lists.
6. **Complexity.** Measured with PMD 7.15.0 on a scratch copy of the tree:

   | Class | Before | After |
   | --- | --- | --- |
   | `LaneSearchQueryBuilder` | 26 | 15 |
   | `LaneSearchFilters` | 17 | 7 |
   | `LaneKeyMatcher` (new) | — | 13 |
   | `LaneLoadFilters` (new) | — | 11 |

   The project ruleset reports 0 violations on the whole `force-app`.
7. **`BidSearchQueryBuilder` is not switched to `LaneKeyMatcher`.** The contract does not ask for it. It matches `Benchmark_Rate__c`'s own lane fields under `bO`/`bD` bind names, and changing it would add risk to the bid search for no phase 8 reader.
8. **Where the SOQL was proved.** The new SOQL shapes (the load-filter and lane-key conditions with `loadPath` `''` on `rtms__Load__c`, and through `rtms__Load__r.` on `rtms__FreightPlanLoad__c`) were proved with the read-only queries quoted in Step 7. Nothing in this task runs them. `LaneQueries` (Tasks 5 and 9) is the first code that does.


---

### Task 3: Intercompany carriers, handoff points and exchange rates


**Files:**

- Create: `force-app/main/default/classes/IntercompanyCarriers.cls`, `force-app/main/default/classes/IntercompanyCarriers.cls-meta.xml`
- Create: `force-app/main/default/classes/IntercompanyCarriersTest.cls`, `force-app/main/default/classes/IntercompanyCarriersTest.cls-meta.xml`
- Create: `force-app/main/default/classes/HandoffPoints.cls`, `force-app/main/default/classes/HandoffPoints.cls-meta.xml`
- Create: `force-app/main/default/classes/HandoffPointsTest.cls`, `force-app/main/default/classes/HandoffPointsTest.cls-meta.xml`
- Create: `force-app/main/default/classes/ExchangeRates.cls`, `force-app/main/default/classes/ExchangeRates.cls-meta.xml`
- Create: `force-app/main/default/classes/ExchangeRatesTest.cls`, `force-app/main/default/classes/ExchangeRatesTest.cls-meta.xml`
- Modify: `manifest/package.xml` (ApexClass members `IntercompanyCarriers`, `IntercompanyCarriersTest`, `HandoffPoints`, `HandoffPointsTest`, `ExchangeRates`, `ExchangeRatesTest`, at the end of the ApexClass block, after the members Tasks 1 and 2 added and directly before `<name>ApexClass</name>`)
- Read, do not change: `force-app/main/default/classes/LaneSearchExclusions.cls` and `LaneSearchExclusionsTest.cls` (the override, parse and "log and skip" pattern these readers copy), `force-app/main/default/classes/MapboxTruckRouteTest.cls` (in-memory custom metadata rows built with `JSON.deserialize`, already compiled in this org)

**Interfaces:**

- Consumes:
  - Task 1: `Intercompany_Carrier__mdt` with `Carrier_Account_Id__c` Text(18) and its two records (`Intercompany_Carrier.Tpml_TP_Org`, `Intercompany_Carrier.Lessard_Org`); `Handoff_Point__mdt` with `Place_Key__c` Text(120) and `Active__c` Checkbox and its three records (`laredo|tx|us`, `san diego|ca|us`, `calexico|ca|us`, all active). All five records are deployed to PostProduc by Task 1.
  - The org: `DatedConversionRate` (`IsoCode` picklist, `StartDate` date, `NextStartDate` date, `ConversionRate` double 18,6). Verified read-only in PostProduc on 2026-09-15: `SELECT IsoCode, ConversionRate, StartDate, NextStartDate FROM DatedConversionRate WHERE IsoCode = 'USD' AND NextStartDate > 2025-08-11 ORDER BY StartDate` returns 51 rows, the first 2025-08-04 to 2025-08-13 at 0.7359, the last 2026-08-11 to 9999-12-31 at 0.7239; `CurrencyType` has CAD (corporate, 1) and USD (0.7443) active.
- Produces:
  - `public with sharing class IntercompanyCarriers`:
    - `@TestVisible private static Set<Id> idsOverride;`
    - `public static Set<Id> ids()` — a copy of `idsOverride` when it is set; otherwise the Account Ids parsed from `Intercompany_Carrier__mdt.getAll().values()`. Never null; 18-character Ids, so the 15- and 18-character forms of one account are one entry.
    - `@TestVisible private static Set<Id> parseIds(List<Intercompany_Carrier__mdt> records)` — keeps a trimmed `Carrier_Account_Id__c` of 15 or 18 characters whose `getSObjectType()` is `Account.SObjectType`; a blank, malformed or non-Account entry is skipped with `System.debug(LoggingLevel.WARN, ...)`, as `LaneSearchExclusions` does.
  - `public with sharing class HandoffPoints`:
    - `@TestVisible private static List<String> keysOverride;`
    - `public static List<String> activeKeys()` — a copy of `keysOverride` when it is set; otherwise the keys parsed from `Handoff_Point__mdt.getAll().values()`. Never null.
    - `@TestVisible private static List<String> parseKeys(List<Handoff_Point__mdt> records)` — `Place_Key__c` of the records whose `Active__c` is true, blank keys skipped, trimmed, lowercased, distinct, sorted.
  - `public with sharing class ExchangeRates`:
    - `public class Period { public Date startDate; public Date nextStartDate; public Decimal rate; public Period(Date startDate, Date nextStartDate, Decimal rate) }`
    - `@TestVisible private static List<Period> periodsOverride;`
    - `public static ExchangeRates usd(Date fromDate)` — the override when it is set (no query); otherwise one query, `SELECT IsoCode, ConversionRate, StartDate, NextStartDate FROM DatedConversionRate WHERE IsoCode = 'USD' AND NextStartDate > :fromDate WITH SYSTEM_MODE ORDER BY StartDate`.
    - `public Boolean hasRates()` — at least one period.
    - `public Decimal fromCad(Decimal cadAmount, Datetime loadCreated)` — `cadAmount * rate`, unrounded, with the rate of the period whose `startDate <= loadCreated.date() < nextStartDate` (in practice: the period with the latest start on or before the day); a day on or after the last start uses the last period; a day before the first period uses the first; `null` when `cadAmount` is null, `loadCreated` is null or there is no period.
    - `public Date latestStartUsed { get; private set; }` — the latest `startDate` of the periods conversions actually used; `null` until a conversion happens.
- Used by: Task 5 (`LaneQueries.quoteCountSoql` binds `IntercompanyCarriers.ids()` as `intercompany`; `CarrierLeadService` drops intercompany leg carriers), Task 8 (`SplitLaneService` skips shipments with an intercompany leg carrier; `ExchangeRates.usd(Date.today().addDays(-400))`, `hasRates()`, `fromCad` through `amountIn`, `latestStartUsed` as `rateStartDate`), Task 9 (`SplitEstimates` reads `HandoffPoints.activeKeys()`; `LaneQueries.legLoadSoql` binds `IntercompanyCarriers.ids()`).

- [ ] **Step 1: Confirm Task 1's custom metadata is in the org**

Run: `sf data query -o sandbox --json -q "SELECT DeveloperName, Carrier_Account_Id__c FROM Intercompany_Carrier__mdt LIMIT 1000" | python3 -c "import json,sys; s=sys.stdin.read(); d=json.loads(s[s.index('{'):]); r=d.get('result') or {}; print(d.get('status'), r.get('totalSize'), [{k: v for k, v in x.items() if k != 'attributes'} for x in (r.get('records') or [])], d.get('message'))"`

Expected: `0 2` and two records in any order, `Lessard_Org` with `0011N00001JbQ7EQAV` and `Tpml_TP_Org` with `0011N00001JcHnvQAF`.

Run: `sf data query -o sandbox --json -q "SELECT DeveloperName, Place_Key__c, Active__c FROM Handoff_Point__mdt LIMIT 1000" | python3 -c "import json,sys; s=sys.stdin.read(); d=json.loads(s[s.index('{'):]); r=d.get('result') or {}; print(d.get('status'), r.get('totalSize'), [{k: v for k, v in x.items() if k != 'attributes'} for x in (r.get('records') or [])], d.get('message'))"`

Expected: `0 3` and `Calexico_CA_US` / `calexico|ca|us`, `Laredo_TX_US` / `laredo|tx|us`, `San_Diego_CA_US` / `san diego|ca|us`, each with `Active__c` true. A `sObject type ... is not supported` message means Task 1 is not deployed: stop and finish Task 1. (The `LIMIT 1000` shape on a custom metadata query was checked read-only on `Pricing_Department_Setting__mdt` on 2026-09-15: status 0, 1 row.)

- [ ] **Step 2: Write the failing tests**

Create the six meta files, each with this content (`force-app/main/default/classes/IntercompanyCarriers.cls-meta.xml`, `IntercompanyCarriersTest.cls-meta.xml`, `HandoffPoints.cls-meta.xml`, `HandoffPointsTest.cls-meta.xml`, `ExchangeRates.cls-meta.xml`, `ExchangeRatesTest.cls-meta.xml`):

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<ApexClass xmlns="http://soap.sforce.com/2006/04/metadata">
    <apiVersion>64.0</apiVersion>
    <status>Active</status>
</ApexClass>
```

Create `force-app/main/default/classes/IntercompanyCarriersTest.cls`:

```apex
/**
 * No DML and no setup-object writes here, so the class runs in parallel with the rest of the suite.
 * Account Ids are built from the key prefix rather than written out: PMD's AvoidHardcodingId matches
 * Id-shaped literals, and the real intercompany Ids belong only in the custom metadata records.
 */
@IsTest(IsParallel=true)
private class IntercompanyCarriersTest {
  /** A syntactically valid 15-character Id of the given object: its key prefix and twelve characters. */
  private static String fakeId(Schema.SObjectType objectType, String twelve) {
    return objectType.getDescribe().getKeyPrefix() + twelve;
  }

  /** An in-memory record: custom metadata cannot be inserted in tests (the MapboxTruckRouteTest pattern). */
  private static Intercompany_Carrier__mdt mdtRow(String accountId) {
    return (Intercompany_Carrier__mdt) JSON.deserialize(
      JSON.serialize(
        new Map<String, Object>{ 'Carrier_Account_Id__c' => accountId }
      ),
      Intercompany_Carrier__mdt.class
    );
  }

  @IsTest
  static void idsComeFromTheDeployedRecords() {
    // Asserts the wiring (custom metadata -> parseIds), not the org's data, like LaneSearchExclusionsTest.
    IntercompanyCarriers.idsOverride = null;
    List<Intercompany_Carrier__mdt> records = [
      SELECT Carrier_Account_Id__c
      FROM Intercompany_Carrier__mdt
      LIMIT 1000
    ];

    Test.startTest();
    Set<Id> accountIds = IntercompanyCarriers.ids();
    Test.stopTest();

    System.assert(
      !records.isEmpty(),
      'The intercompany carrier records must be deployed'
    );
    System.assert(
      accountIds.equals(IntercompanyCarriers.parseIds(records)),
      'ids() must return exactly what the deployed records parse to'
    );
    System.assert(
      !accountIds.isEmpty(),
      'The deployed records must name at least one carrier account'
    );
    for (Id accountId : accountIds) {
      System.assertEquals(
        Account.SObjectType,
        accountId.getSObjectType(),
        'every intercompany carrier is an Account'
      );
    }
  }

  @IsTest
  static void parseKeepsAccountIdsOfBothLengthsAndSkipsTheRest() {
    String account15 = fakeId(Account.SObjectType, '00000000000A');
    String account18 = String.valueOf(Id.valueOf(account15));
    String otherAccount15 = fakeId(Account.SObjectType, '00000000000B');
    String contact15 = fakeId(Contact.SObjectType, '00000000000A');

    Test.startTest();
    Set<Id> parsed = IntercompanyCarriers.parseIds(
      new List<Intercompany_Carrier__mdt>{
        mdtRow(account15),
        mdtRow(account18),
        mdtRow('  ' + otherAccount15 + '  '),
        mdtRow(contact15),
        mdtRow('not-an-id'),
        mdtRow('001-not-an-id!!'),
        mdtRow(account15.left(14)),
        mdtRow(''),
        mdtRow(null),
        null
      }
    );
    Test.stopTest();

    System.assertEquals(
      2,
      parsed.size(),
      'Only the two accounts survive, the 15- and 18-character forms of one being one entry: ' +
      String.valueOf(parsed)
    );
    System.assert(
      parsed.contains(Id.valueOf(account18)),
      'the account given in both lengths is kept'
    );
    System.assert(
      parsed.contains(Id.valueOf(otherAccount15)),
      'a padded entry is trimmed and kept'
    );
    System.assert(
      !parsed.contains(Id.valueOf(contact15)),
      'a Contact Id is not a carrier account'
    );
  }

  @IsTest
  static void overrideWinsOverTheRecordsAndIsReturnedAsACopy() {
    // A fake Account Id that no deployed record holds, so a merge with the records would show.
    Id sentinel = Id.valueOf(fakeId(Account.SObjectType, '00000000000Z'));
    IntercompanyCarriers.idsOverride = new Set<Id>{ sentinel };

    Test.startTest();
    IntercompanyCarriers.ids().clear();
    Set<Id> accountIds = IntercompanyCarriers.ids();
    Test.stopTest();

    System.assertEquals(
      1,
      accountIds.size(),
      'the deployed records are not consulted when the override is set, and a caller cannot empty it'
    );
    System.assert(accountIds.contains(sentinel), 'the override is returned');
  }

  @IsTest
  static void idsIsNeverNullWithoutAValidRecord() {
    // Custom metadata cannot be inserted in a test, so a list with no valid entry is simulated by
    // parsing one and feeding the result back through the public entry point the services call.
    IntercompanyCarriers.idsOverride = IntercompanyCarriers.parseIds(
      new List<Intercompany_Carrier__mdt>{ mdtRow(''), mdtRow('not-an-id') }
    );

    Test.startTest();
    Set<Id> accountIds = IntercompanyCarriers.ids();
    Set<Id> fromNull = IntercompanyCarriers.parseIds(null);
    Test.stopTest();

    System.assertNotEquals(null, accountIds, 'never null');
    System.assertEquals(0, accountIds.size(), 'and empty');
    System.assertNotEquals(null, fromNull, 'no record list gives a set');
    System.assertEquals(0, fromNull.size(), 'an empty one');
  }
}
```

Create `force-app/main/default/classes/HandoffPointsTest.cls`:

```apex
/**
 * No DML and no setup-object writes here, so the class runs in parallel with the rest of the suite.
 */
@IsTest(IsParallel=true)
private class HandoffPointsTest {
  /** An in-memory record: custom metadata cannot be inserted in tests (the MapboxTruckRouteTest pattern). */
  private static Handoff_Point__mdt mdtRow(String placeKey, Boolean active) {
    Map<String, Object> fields = new Map<String, Object>{
      'Place_Key__c' => placeKey
    };
    if (active != null) {
      fields.put('Active__c', active);
    }
    return (Handoff_Point__mdt) JSON.deserialize(
      JSON.serialize(fields),
      Handoff_Point__mdt.class
    );
  }

  @IsTest
  static void activeKeysComeFromTheDeployedRecords() {
    // Asserts the wiring (custom metadata -> parseKeys), not which points an admin keeps active.
    HandoffPoints.keysOverride = null;
    List<Handoff_Point__mdt> records = [
      SELECT Place_Key__c, Active__c
      FROM Handoff_Point__mdt
      LIMIT 1000
    ];

    Test.startTest();
    List<String> placeKeys = HandoffPoints.activeKeys();
    Test.stopTest();

    System.assert(
      !records.isEmpty(),
      'The handoff point records must be deployed'
    );
    System.assertEquals(
      HandoffPoints.parseKeys(records),
      placeKeys,
      'activeKeys() must return exactly what the deployed records parse to'
    );
  }

  @IsTest
  static void parseKeepsActiveKeysTrimmedLowercasedDistinctAndSorted() {
    Test.startTest();
    List<String> placeKeys = HandoffPoints.parseKeys(
      new List<Handoff_Point__mdt>{
        mdtRow('  San Diego|CA|US ', true),
        mdtRow('laredo|tx|us', true),
        mdtRow('LAREDO|TX|US', true),
        mdtRow('calexico|ca|us', false),
        mdtRow('mexicali|bc|mx', null),
        mdtRow('   ', true),
        mdtRow(null, true),
        null
      }
    );
    Test.stopTest();

    System.assertEquals(
      new List<String>{ 'laredo|tx|us', 'san diego|ca|us' },
      placeKeys,
      'inactive, unset and blank records are dropped; keys are trimmed, lowercased, distinct and sorted'
    );
  }

  @IsTest
  static void overrideWinsOverTheRecordsAndIsReturnedAsACopy() {
    HandoffPoints.keysOverride = new List<String>{ 'override-only' };

    Test.startTest();
    HandoffPoints.activeKeys().clear();
    List<String> placeKeys = HandoffPoints.activeKeys();
    Test.stopTest();

    System.assertEquals(
      new List<String>{ 'override-only' },
      placeKeys,
      'the deployed records are not consulted when the override is set, and a caller cannot empty it'
    );
  }

  @IsTest
  static void activeKeysIsNeverNullWithoutAnActiveRecord() {
    HandoffPoints.keysOverride = HandoffPoints.parseKeys(
      new List<Handoff_Point__mdt>{ mdtRow('laredo|tx|us', false) }
    );

    Test.startTest();
    List<String> placeKeys = HandoffPoints.activeKeys();
    List<String> fromNull = HandoffPoints.parseKeys(null);
    Test.stopTest();

    System.assertNotEquals(null, placeKeys, 'never null');
    System.assertEquals(0, placeKeys.size(), 'and empty');
    System.assertNotEquals(null, fromNull, 'no record list gives a list');
    System.assertEquals(0, fromNull.size(), 'an empty one');
  }
}
```

Create `force-app/main/default/classes/ExchangeRatesTest.cls`:

```apex
/**
 * Rates come from ExchangeRates.periodsOverride, because DatedConversionRate rows cannot be inserted in
 * tests. One test reads the org's own rates without the override and checks the answer against its own
 * query, so it holds whether or not the org's dated rates are visible to tests. Amounts are compared at
 * scale 6 on both sides, so no assertion depends on a Decimal's scale. No DML here.
 */
@IsTest(IsParallel=true)
private class ExchangeRatesTest {
  private static final Date JAN_05 = Date.newInstance(2026, 1, 5);
  private static final Date JAN_12 = Date.newInstance(2026, 1, 12);
  private static final Date JAN_19 = Date.newInstance(2026, 1, 19);
  private static final Date OPEN_END = Date.newInstance(9999, 12, 31);

  /** Three weekly periods, the last one open-ended like Salesforce's latest dated rate. */
  private static List<ExchangeRates.Period> threeWeeks() {
    return new List<ExchangeRates.Period>{
      new ExchangeRates.Period(JAN_05, JAN_12, 0.70),
      new ExchangeRates.Period(JAN_12, JAN_19, 0.72),
      new ExchangeRates.Period(JAN_19, OPEN_END, 0.74)
    };
  }

  /** Noon in the running user's time zone, so Datetime.date() is the given day. */
  private static Datetime noonOn(
    Integer year,
    Integer month,
    Integer dayOfMonth
  ) {
    return Datetime.newInstance(year, month, dayOfMonth, 12, 0, 0);
  }

  private static void assertAmount(
    Decimal expected,
    Decimal actual,
    String message
  ) {
    System.assertNotEquals(null, actual, message + ': no amount');
    System.assertEquals(expected.setScale(6), actual.setScale(6), message);
  }

  @IsTest
  static void aLoadDayInsideAPeriodUsesThatPeriodsRateUnrounded() {
    ExchangeRates.periodsOverride = threeWeeks();

    Test.startTest();
    ExchangeRates rates = ExchangeRates.usd(Date.newInstance(2025, 12, 1));
    Integer queries = Limits.getQueries();
    Decimal usdAmount = rates.fromCad(1234.56, noonOn(2026, 1, 14));
    Test.stopTest();

    System.assertEquals(0, queries, 'the override is used without a query');
    System.assert(rates.hasRates(), 'three periods are rates');
    assertAmount(
      888.8832,
      usdAmount,
      '1,234.56 CAD on January 14 at 0.72, not rounded to cents'
    );
    System.assertEquals(
      JAN_12,
      rates.latestStartUsed,
      'the period used starts on January 12'
    );
  }

  @IsTest
  static void aNextStartDateBelongsToTheNextPeriod() {
    ExchangeRates.periodsOverride = threeWeeks();

    Test.startTest();
    ExchangeRates rates = ExchangeRates.usd(Date.newInstance(2025, 12, 1));
    Decimal dayBefore = rates.fromCad(1000, noonOn(2026, 1, 11));
    Decimal onTheBoundary = rates.fromCad(1000, noonOn(2026, 1, 12));
    Test.stopTest();

    assertAmount(700, dayBefore, 'January 11 is still in the first period');
    assertAmount(
      720,
      onTheBoundary,
      'January 12, the first period NextStartDate, is in the second period'
    );
    System.assertEquals(
      JAN_12,
      rates.latestStartUsed,
      'the boundary day used the second period'
    );
  }

  @IsTest
  static void aDayOnOrAfterTheLastStartUsesTheLastRate() {
    ExchangeRates.periodsOverride = threeWeeks();

    Test.startTest();
    ExchangeRates rates = ExchangeRates.usd(Date.newInstance(2025, 12, 1));
    Decimal onTheLastStart = rates.fromCad(1000, noonOn(2026, 1, 19));
    Decimal longAfter = rates.fromCad(1000, noonOn(2027, 6, 30));
    Test.stopTest();

    assertAmount(740, onTheLastStart, 'January 19 starts the last period');
    assertAmount(740, longAfter, 'a later day keeps the last rate');
    System.assertEquals(JAN_19, rates.latestStartUsed, 'the last period');
  }

  @IsTest
  static void aDayBeforeTheFirstPeriodUsesTheFirstRateInAnyListOrder() {
    List<ExchangeRates.Period> newestFirst = new List<ExchangeRates.Period>();
    List<ExchangeRates.Period> weeks = threeWeeks();
    for (Integer i = weeks.size() - 1; i >= 0; i--) {
      newestFirst.add(weeks[i]);
    }
    ExchangeRates.periodsOverride = newestFirst;

    Test.startTest();
    ExchangeRates rates = ExchangeRates.usd(Date.newInstance(2025, 12, 1));
    Decimal before = rates.fromCad(1000, noonOn(2025, 12, 20));
    Decimal inside = rates.fromCad(1000, noonOn(2026, 1, 13));
    Test.stopTest();

    assertAmount(700, before, 'December 20 is before the first period');
    assertAmount(720, inside, 'the list order does not change the period');
    System.assertEquals(
      JAN_12,
      rates.latestStartUsed,
      'the latest period used, whatever the list order'
    );
  }

  @IsTest
  static void aMissingAmountOrDateGivesNoAmountAndRecordsNothing() {
    ExchangeRates.periodsOverride = threeWeeks();

    Test.startTest();
    ExchangeRates rates = ExchangeRates.usd(Date.newInstance(2025, 12, 1));
    Decimal noAmount = rates.fromCad(null, noonOn(2026, 1, 14));
    Decimal noDate = rates.fromCad(1000, null);
    Test.stopTest();

    System.assertEquals(null, noAmount, 'a null CAD amount has no USD amount');
    System.assertEquals(null, noDate, 'a missing load date has no USD amount');
    System.assertEquals(
      null,
      rates.latestStartUsed,
      'no conversion happened, so no period was used'
    );
  }

  @IsTest
  static void noPeriodsMeansNoRates() {
    ExchangeRates.periodsOverride = new List<ExchangeRates.Period>();

    Test.startTest();
    ExchangeRates rates = ExchangeRates.usd(Date.newInstance(2025, 12, 1));
    Decimal usdAmount = rates.fromCad(1000, noonOn(2026, 1, 14));
    Test.stopTest();

    System.assert(!rates.hasRates(), 'no period is no rate');
    System.assertEquals(null, usdAmount, 'nothing to convert with');
    System.assertEquals(null, rates.latestStartUsed, 'no period used');
  }

  @IsTest
  static void latestStartUsedIsTheLatestPeriodActuallyUsed() {
    ExchangeRates.periodsOverride = threeWeeks();

    Test.startTest();
    ExchangeRates allThree = ExchangeRates.usd(Date.newInstance(2025, 12, 1));
    allThree.fromCad(100, noonOn(2026, 1, 20));
    allThree.fromCad(100, noonOn(2026, 1, 6));
    allThree.fromCad(100, noonOn(2026, 1, 13));
    ExchangeRates firstTwo = ExchangeRates.usd(Date.newInstance(2025, 12, 1));
    firstTwo.fromCad(100, noonOn(2026, 1, 6));
    firstTwo.fromCad(100, noonOn(2026, 1, 13));
    firstTwo.fromCad(null, noonOn(2026, 1, 25));
    Test.stopTest();

    System.assertEquals(
      JAN_19,
      allThree.latestStartUsed,
      'an earlier period used later does not move it back'
    );
    System.assertEquals(
      JAN_12,
      firstTwo.latestStartUsed,
      'a later period that no amount used does not count'
    );
  }

  @IsTest
  static void theOrgReadIsOneQueryAndAgreesWithTheOrgsRates() {
    ExchangeRates.periodsOverride = null;
    Date fromDate = Date.today().addDays(-400);
    Date todayDate = Date.today();
    Integer periodCount = [
      SELECT COUNT()
      FROM DatedConversionRate
      WHERE IsoCode = 'USD' AND NextStartDate > :fromDate
    ];
    List<DatedConversionRate> current = [
      SELECT ConversionRate, StartDate
      FROM DatedConversionRate
      WHERE
        IsoCode = 'USD'
        AND StartDate <= :todayDate
        AND NextStartDate > :todayDate
      LIMIT 1
    ];

    Test.startTest();
    ExchangeRates rates = ExchangeRates.usd(fromDate);
    Integer queries = Limits.getQueries();
    Decimal usdAmount = rates.fromCad(1000, System.now());
    Test.stopTest();

    System.assertEquals(1, queries, 'usd() reads the periods in one query');
    System.assertEquals(
      periodCount > 0,
      rates.hasRates(),
      'hasRates() says whether USD periods end after the read date'
    );
    if (current.isEmpty()) {
      System.assertEquals(
        null,
        usdAmount,
        'no USD period is visible, so there is no USD amount'
      );
    } else {
      assertAmount(
        1000 * current[0].ConversionRate,
        usdAmount,
        'today converts at the rate of the period holding today'
      );
      System.assertEquals(
        current[0].StartDate,
        rates.latestStartUsed,
        'and records that period start'
      );
    }
  }
}
```

- [ ] **Step 3: Deploy the tests alone and watch them fail to compile**

Run: `sf project deploy start -o sandbox --source-dir force-app/main/default/classes/IntercompanyCarriersTest.cls --source-dir force-app/main/default/classes/HandoffPointsTest.cls --source-dir force-app/main/default/classes/ExchangeRatesTest.cls -l NoTestRun --async --json | python3 -c "import json,sys; s=sys.stdin.read(); print(json.loads(s[s.index('{'):])['result']['id'])"`

Expected: one deploy job id (starts with `0Af`). Then poll with that id in place of `<id>`, repeating the command while the first word printed is `Pending` or `InProgress`:

`sf project deploy report -o sandbox --job-id <id> -w 2 --json | python3 -c "import json,sys; s=sys.stdin.read(); j=json.loads(s[s.index('{'):]); r=j.get('result') or j.get('data') or {}; d=r.get('details') or {}; t=d.get('runTestResult') or {}; L=lambda x: x if isinstance(x, list) else ([x] if x else []); print(r.get('status') or j.get('message'), 'tests', r.get('numberTestsCompleted'), '/', r.get('numberTestsTotal'), 'errors', r.get('numberTestErrors')); [print('COMPILE', c.get('fullName'), c.get('lineNumber'), c.get('problem')) for c in L(d.get('componentFailures'))]; [print('FAIL', f.get('methodName'), f.get('message')) for f in L(t.get('failures'))]; [print('COVERAGE', c.get('name'), c.get('numLocations'), 'lines,', c.get('numLocationsNotCovered'), 'not covered') for c in L(t.get('codeCoverage')) if c.get('name') in ('IntercompanyCarriers', 'HandoffPoints', 'ExchangeRates')]"`

Expected: `Failed tests 0 / 0 errors 0` (the counts may print as `None` on a `NoTestRun` deploy) followed by one `COMPILE` line per test class: `IntercompanyCarriersTest <line> Variable does not exist: IntercompanyCarriers`, `HandoffPointsTest <line> Variable does not exist: HandoffPoints`, `ExchangeRatesTest <line> Invalid type: ExchangeRates.Period` (or `Variable does not exist: ExchangeRates`). A problem naming `Intercompany_Carrier__mdt`, `Handoff_Point__mdt`, `Carrier_Account_Id__c`, `Place_Key__c` or `Active__c` means Task 1 is not deployed: stop and finish Task 1.

- [ ] **Step 4: Write the three readers and add them to the manifest**

Create `force-app/main/default/classes/IntercompanyCarriers.cls`:

```apex
/**
 * Carrier accounts of the company's own organizations (phase 8, spec D6 and R89), read from
 * Intercompany_Carrier__mdt so an admin edits the list in Setup without a deploy. Carriers to ask and
 * split-lane options leave these carriers out in their queries, because their quotes and leg costs are
 * internal pass-throughs. The account Ids live only in the custom metadata records, never in Apex.
 * Tests set idsOverride because custom metadata cannot be inserted in tests.
 */
public with sharing class IntercompanyCarriers {
  // Test hook: tests set this to control the list because custom metadata cannot be inserted in tests.
  @TestVisible
  private static Set<Id> idsOverride;

  /** The intercompany carrier Account Ids (18-character); never null. */
  public static Set<Id> ids() {
    if (idsOverride != null) {
      return new Set<Id>(idsOverride);
    }
    return parseIds(Intercompany_Carrier__mdt.getAll().values());
  }

  /**
   * Keeps each record's Carrier_Account_Id__c that is a 15- or 18-character Account Id, tolerating admin
   * data-entry mistakes: a blank, malformed or non-Account entry is logged and skipped rather than thrown.
   * Both lengths of the same account give one entry.
   */
  @TestVisible
  private static Set<Id> parseIds(List<Intercompany_Carrier__mdt> records) {
    Set<Id> accountIds = new Set<Id>();
    if (records == null) {
      return accountIds;
    }
    for (Intercompany_Carrier__mdt row : records) {
      Id accountId = accountIdOrNull(row?.Carrier_Account_Id__c);
      if (accountId == null) {
        System.debug(
          LoggingLevel.WARN,
          'Intercompany_Carrier: ignoring invalid Account Id "' +
            row?.Carrier_Account_Id__c +
            '"'
        );
        continue;
      }
      accountIds.add(accountId);
    }
    return accountIds;
  }

  private static Id accountIdOrNull(String raw) {
    String trimmed = raw == null ? '' : raw.trim();
    if (trimmed.length() != 15 && trimmed.length() != 18) {
      return null;
    }
    try {
      Id candidate = Id.valueOf(trimmed);
      return candidate.getSObjectType() == Account.SObjectType
        ? candidate
        : null;
    } catch (System.StringException e) {
      return null;
    }
  }
}
```

Create `force-app/main/default/classes/HandoffPoints.cls`:

```apex
/**
 * Handoff points for split-lane estimates (phase 8, spec D8), read from Handoff_Point__mdt so an admin
 * adds, edits or deactivates a point in Setup without a deploy. Each record's Place_Key__c is a
 * Pricing_Place__c.Key__c ('laredo|tx|us'). Tests set keysOverride because custom metadata cannot be
 * inserted in tests.
 */
public with sharing class HandoffPoints {
  // Test hook: tests set this to control the list because custom metadata cannot be inserted in tests.
  @TestVisible
  private static List<String> keysOverride;

  /** The place keys of the active handoff points: trimmed, lowercased, distinct and sorted; never null. */
  public static List<String> activeKeys() {
    if (keysOverride != null) {
      return new List<String>(keysOverride);
    }
    return parseKeys(Handoff_Point__mdt.getAll().values());
  }

  /** Active records only; a blank Place_Key__c is skipped. */
  @TestVisible
  private static List<String> parseKeys(List<Handoff_Point__mdt> records) {
    Set<String> distinctKeys = new Set<String>();
    if (records != null) {
      for (Handoff_Point__mdt row : records) {
        if (
          row == null ||
          row.Active__c != true ||
          String.isBlank(row.Place_Key__c)
        ) {
          continue;
        }
        distinctKeys.add(row.Place_Key__c.trim().toLowerCase());
      }
    }
    List<String> placeKeys = new List<String>(distinctKeys);
    placeKeys.sort();
    return placeKeys;
  }
}
```

Create `force-app/main/default/classes/ExchangeRates.cls`:

```apex
/**
 * USD dated exchange rates for split-lane amounts (phase 8, spec D7 and R109). Revenova stores leg costs
 * in CAD, the corporate currency; a USD DatedConversionRate row gives the USD that one CAD buys from its
 * StartDate until the day before its NextStartDate, so a USD amount is the CAD amount times the rate of
 * the period holding the load's day (a NextStartDate belongs to the next period). A day on or after the
 * last period's start uses the last rate; a day before the first period uses the first. usd() reads the
 * periods in one query; tests set periodsOverride because dated rates cannot be inserted in tests.
 */
public with sharing class ExchangeRates {
  // Test hook: tests set the periods because DatedConversionRate rows cannot be inserted in tests.
  @TestVisible
  private static List<Period> periodsOverride;

  private final List<Period> periods;
  // One lookup per distinct load day: a split read converts up to thousands of legs over about 365 days.
  private final Map<Date, Period> periodByDay = new Map<Date, Period>();

  /** The start date of the latest period any conversion used; null before the first conversion. */
  public Date latestStartUsed { get; private set; }

  public class Period {
    public Date startDate;
    public Date nextStartDate;
    public Decimal rate;

    public Period(Date startDate, Date nextStartDate, Decimal rate) {
      this.startDate = startDate;
      this.nextStartDate = nextStartDate;
      this.rate = rate;
    }
  }

  private ExchangeRates(List<Period> periods) {
    this.periods = periods == null ? new List<Period>() : periods;
  }

  /**
   * The USD periods that end after fromDate, oldest first. One query, unless periodsOverride is set.
   * System mode on purpose: exchange rates are org-wide reference data every pricer's amounts depend
   * on, not a user's record, and a restricted pricer must convert like everyone else.
   */
  public static ExchangeRates usd(Date fromDate) {
    if (periodsOverride != null) {
      return new ExchangeRates(new List<Period>(periodsOverride));
    }
    List<Period> periods = new List<Period>();
    for (DatedConversionRate row : [
      SELECT IsoCode, ConversionRate, StartDate, NextStartDate
      FROM DatedConversionRate
      WHERE IsoCode = 'USD' AND NextStartDate > :fromDate
      WITH SYSTEM_MODE
      ORDER BY StartDate
    ]) {
      periods.add(
        new Period(row.StartDate, row.NextStartDate, row.ConversionRate)
      );
    }
    return new ExchangeRates(periods);
  }

  public Boolean hasRates() {
    return !periods.isEmpty();
  }

  /**
   * cadAmount in USD at the rate of the period holding loadCreated's day (in the running user's time
   * zone), unrounded; null when cadAmount or loadCreated is null or there is no period. Each conversion
   * moves latestStartUsed forward when it used a later period.
   */
  public Decimal fromCad(Decimal cadAmount, Datetime loadCreated) {
    if (cadAmount == null || loadCreated == null || periods.isEmpty()) {
      return null;
    }
    Period used = periodFor(loadCreated.date());
    if (latestStartUsed == null || used.startDate > latestStartUsed) {
      latestStartUsed = used.startDate;
    }
    return cadAmount * used.rate;
  }

  /** The period with the latest start on or before day, else the earliest period; the list order does not matter. */
  private Period periodFor(Date day) {
    Period cached = periodByDay.get(day);
    if (cached != null) {
      return cached;
    }
    Period earliest;
    Period latestStarted;
    for (Period candidate : periods) {
      if (earliest == null || candidate.startDate < earliest.startDate) {
        earliest = candidate;
      }
      if (
        candidate.startDate <= day &&
        (latestStarted == null ||
        candidate.startDate > latestStarted.startDate)
      ) {
        latestStarted = candidate;
      }
    }
    Period chosen = latestStarted == null ? earliest : latestStarted;
    periodByDay.put(day, chosen);
    return chosen;
  }
}
```

Add the six members at the end of the ApexClass block of `manifest/package.xml`, directly before `<name>ApexClass</name>` (after whatever Tasks 1 and 2 added):

Run: `python3 -c "p='manifest/package.xml'; s=open(p).read(); a='        <name>ApexClass</name>'; assert s.count(a) == 1, 'ApexClass anchor'; m=''.join('        <members>' + n + '</members>\n' for n in ['IntercompanyCarriers', 'IntercompanyCarriersTest', 'HandoffPoints', 'HandoffPointsTest', 'ExchangeRates', 'ExchangeRatesTest']); open(p, 'w').write(s.replace(a, m + a))"`

The block then ends with:

```xml
        <members>IntercompanyCarriers</members>
        <members>IntercompanyCarriersTest</members>
        <members>HandoffPoints</members>
        <members>HandoffPointsTest</members>
        <members>ExchangeRates</members>
        <members>ExchangeRatesTest</members>
        <name>ApexClass</name>
```

Expected afterwards: `grep -c -E '<members>(IntercompanyCarriers|HandoffPoints|ExchangeRates)(Test)?</members>' manifest/package.xml` prints `6`.

- [ ] **Step 5: Deploy the six classes and run their tests**

Run: `sf project deploy start -o sandbox --source-dir force-app/main/default/classes/IntercompanyCarriers.cls --source-dir force-app/main/default/classes/IntercompanyCarriersTest.cls --source-dir force-app/main/default/classes/HandoffPoints.cls --source-dir force-app/main/default/classes/HandoffPointsTest.cls --source-dir force-app/main/default/classes/ExchangeRates.cls --source-dir force-app/main/default/classes/ExchangeRatesTest.cls -l RunSpecifiedTests -t IntercompanyCarriersTest -t HandoffPointsTest -t ExchangeRatesTest --async --json | python3 -c "import json,sys; s=sys.stdin.read(); print(json.loads(s[s.index('{'):])['result']['id'])"`

Then poll with the report command from Step 3 (same Python filter, the new job id), repeating while it prints `Pending` or `InProgress`.

Expected: `Succeeded tests 16 / 16 errors 0` (4 in `IntercompanyCarriersTest`, 4 in `HandoffPointsTest`, 8 in `ExchangeRatesTest`) and three `COVERAGE` lines, `IntercompanyCarriers`, `HandoffPoints` and `ExchangeRates`, `IntercompanyCarriers` and `HandoffPoints` with 0 lines not covered and `ExchangeRates` with at most 1 (the per-day cache hit in `periodFor`, which no test reaches because no test converts the same day twice on one instance); the org refuses a class below 75 %. If a test fails, the `FAIL` lines name the method and message; fix the class, not the assertion, unless the assertion contradicts the spec. If `theOrgReadIsOneQueryAndAgreesWithTheOrgsRates` fails, read its message: it compares `usd()` with the test's own `DatedConversionRate` queries, so it holds whether or not dated rates are visible to tests (PostProduc has 51 USD periods ending after 2025-08-11 and the current one starts 2026-08-11 at 0.7239, checked read-only on 2026-09-15). If `parseKeepsAccountIdsOfBothLengthsAndSkipsTheRest` fails with an uncaught exception from `Id.valueOf` on `'001-not-an-id!!'` that is not `System.StringException`, add that exception type to the catch in `IntercompanyCarriers.accountIdOrNull` (the class must log and skip, never throw) and redeploy. If the compile reports a conflict on `Period` (the standard fiscal `Period` object), stop and report: Apex resolves a class's own inner types before sObjects, so this is not expected, and renaming it changes a name Task 8 uses.

- [ ] **Step 6: PMD**

Run: `/private/tmp/pmd_install/pmd-bin-7.15.0/bin/pmd check --dir force-app/main/default/classes/IntercompanyCarriers.cls --dir force-app/main/default/classes/IntercompanyCarriersTest.cls --dir force-app/main/default/classes/HandoffPoints.cls --dir force-app/main/default/classes/HandoffPointsTest.cls --dir force-app/main/default/classes/ExchangeRates.cls --dir force-app/main/default/classes/ExchangeRatesTest.cls --rulesets config/pmd-ruleset.xml --minimum-priority 3 --format text --fail-on-violation --no-progress; echo "pmd exit $?"`

Expected: no violation lines, `pmd exit 0` (the six files as written were checked with PMD 7.15.0 and this ruleset in a scratch copy: 0 violations; the `WITH SYSTEM_MODE` query needs no `ApexCRUDViolation` suppression). Every test method asserts directly, not only through `assertAmount`, because `ApexUnitTestClassShouldHaveAsserts` does not look inside helpers.

Then the whole tree: `/private/tmp/pmd_install/pmd-bin-7.15.0/bin/pmd check --dir force-app --rulesets config/pmd-ruleset.xml --minimum-priority 3 --format text --fail-on-violation --no-progress; echo "pmd exit $?"`

Expected: `pmd exit 0`.

- [ ] **Step 7: Prettier**

Run: `npx prettier --check force-app/main/default/classes/IntercompanyCarriers.cls force-app/main/default/classes/IntercompanyCarriersTest.cls force-app/main/default/classes/HandoffPoints.cls force-app/main/default/classes/HandoffPointsTest.cls force-app/main/default/classes/ExchangeRates.cls force-app/main/default/classes/ExchangeRatesTest.cls force-app/main/default/classes/IntercompanyCarriers.cls-meta.xml force-app/main/default/classes/IntercompanyCarriersTest.cls-meta.xml force-app/main/default/classes/HandoffPoints.cls-meta.xml force-app/main/default/classes/HandoffPointsTest.cls-meta.xml force-app/main/default/classes/ExchangeRates.cls-meta.xml force-app/main/default/classes/ExchangeRatesTest.cls-meta.xml manifest/package.xml`

Expected: `All matched files use Prettier code style!` (the code above is already in the repository's Prettier format). lint-staged runs Prettier again on commit.

- [ ] **Step 8: Commit**

```bash
git add force-app/main/default/classes/IntercompanyCarriers.cls force-app/main/default/classes/IntercompanyCarriers.cls-meta.xml force-app/main/default/classes/IntercompanyCarriersTest.cls force-app/main/default/classes/IntercompanyCarriersTest.cls-meta.xml force-app/main/default/classes/HandoffPoints.cls force-app/main/default/classes/HandoffPoints.cls-meta.xml force-app/main/default/classes/HandoffPointsTest.cls force-app/main/default/classes/HandoffPointsTest.cls-meta.xml force-app/main/default/classes/ExchangeRates.cls force-app/main/default/classes/ExchangeRates.cls-meta.xml force-app/main/default/classes/ExchangeRatesTest.cls force-app/main/default/classes/ExchangeRatesTest.cls-meta.xml manifest/package.xml
git commit -m "Add readers for intercompany carriers, handoff points and USD dated exchange rates"
```

Expected: one commit with those 13 files; `git status --short` still shows `.vscode/settings.json` and the ` 2.` duplicates as modified or untracked, never staged. `git grep -n -E "0011N00001JcHnvQAF|0011N00001JbQ7EQAV" -- '*.cls'` prints nothing (the intercompany account Ids live only in the custom metadata records).

#### Contract notes (Task 3)

1. **In-memory custom metadata rows are built with `JSON.deserialize`, not field assignment.** The task brief suggested field assignment. The tests use the pattern `MapboxTruckRouteTest` already compiles in this org (`(Truck_Routing_Setting__mdt) JSON.deserialize(...)`), because the fields are `DeveloperControlled` and assigning to them in memory has not been proven here. The parse helpers read the fields directly, which works on deserialized rows (an absent field reads as null, as `TruckRoute.profileFrom` shows). `isSet` is not used.
2. **Parse helper names**: the contract leaves them open. They are `@TestVisible private static Set<Id> parseIds(List<Intercompany_Carrier__mdt> records)` and `@TestVisible private static List<String> parseKeys(List<Handoff_Point__mdt> records)`, both taking records so the wiring tests compare `ids()` and `activeKeys()` with a parse of the records the test reads itself (the `LaneSearchExclusionsTest` pattern, with no org Id in Apex).
3. **Overrides are returned as copies** (`new Set<Id>(idsOverride)`, `new List<String>(keysOverride)`), and so is the list `usd()` wraps. A caller that changes the result, such as Task 9 removing the origin and destination keys, cannot change the override or a later call. The org path returns a fresh set or list on every call anyway.
4. **`ExchangeRates.usd` reads in system mode** (`WITH SYSTEM_MODE` on the verified query, no other change to its shape). Restricted pricers are made from the `Standard User` or `Minimum Access - Salesforce` profile (`RfpTestDataFactory.restrictedUser`), user-mode read access to `DatedConversionRate` is not proven for them, and Tasks 8 and 9 run split options in USD for such users. Exchange rates are org-wide reference data, not records. PMD 7.15.0 accepts `WITH SYSTEM_MODE` without a suppression (checked). The class stays `public with sharing` as the contract says.
5. **`fromCad` also returns null when `loadCreated` is null.** The contract only covers a null amount and no periods; every load has a `CreatedDate`, so callers see no difference.
6. **Period lookup**: the period with the latest `startDate` on or before the day, else the earliest period. For Salesforce's contiguous dated periods (each `NextStartDate` is the next row's `StartDate`, and the last runs to 9999-12-31) this is exactly `startDate <= day < nextStartDate`, including "a NextStartDate belongs to the next period" and "after the last start uses the last". It does not depend on list order, which a test proves, and it is cached per distinct day, so converting thousands of legs costs at most about 365 scans of about 57 periods. `nextStartDate` is kept on `Period` as the contract says, but the lookup does not need it.
7. **DatedConversionRate visibility in tests could not be proven read-only** (drafting runs no Apex). `theOrgReadIsOneQueryAndAgreesWithTheOrgsRates` does not depend on it. It asserts that `usd()` uses exactly one query (`Limits.getQueries()` inside `Test.startTest`), that `hasRates()` agrees with the test's own `COUNT()` for the same window, and that today's amount uses the rate and start of the period holding today when the test's own query sees one (null otherwise). All three SOQL shapes were checked read-only on 2026-09-15 (51 periods; current 2026-08-11 at 0.7239).
8. **`ExchangeRates.Period` shares its name with the standard fiscal `Period` object.** Apex resolves a class's locally defined types before sObjects, so inside `ExchangeRates` the name means the inner class, and callers write `ExchangeRates.Period`. The name is kept as the contract says. Step 5 says to stop and report if the compile disagrees.
9. **Amount assertions compare `setScale(6)` on both sides** (`assertAmount`), so no test depends on a Decimal's scale. One amount (1,234.56 CAD × 0.72 = 888.8832) proves `fromCad` does not round to cents.
10. **Test classes are `@IsTest(IsParallel=true)`**: they do no DML, like `LaneSearchExclusionsTest`. That makes 16 new tests (4 + 4 + 8); the executor prints the running totals.
11. **Pre-existing manifest duplicate, not touched**: `manifest/package.xml` lists `<members>RouteMapUrl</members>` twice (phase 7). This task inserts its members by anchoring on `<name>ApexClass</name>`, not by line, and leaves the duplicate for Task 11 or the owner to remove.
12. **Unverified against the Apex compiler**: PMD 7.15.0 (exit 0) and Prettier (`--check` clean, repository config) parsed the six files in a scratch copy; only the Step 3 and Step 5 deploys compile them.


---

### Task 4: Results warning from the account flag

The red carrier warning on lane search rows (Lane Benchmark results and the RFP lane panel's history results, both drawn by `c-lane-benchmark-results`) stops reading the `Carrier_Att__c` formula. `CarrierWarning.text` rebuilds the same two texts in the same order from the carrier account's `Black_List__c` and the Transportation Profile's `Outstanding_Claim__c` on quote rows, and from `Benchmark_Rate__c.Carrier__r.Black_List__c` on bid rows (spec D5, §6, R90). The LWC does not change: `laneBenchmarkResults.js` `selectedFlags` already shows `row.carrier.attention` trimmed, and its Jest fixture already uses `" THE CARRIER IS BLACK-LISTED "`.

**Files:**

- Create: `force-app/main/default/classes/CarrierWarning.cls`, `force-app/main/default/classes/CarrierWarning.cls-meta.xml`
- Create: `force-app/main/default/classes/CarrierWarningTest.cls`, `force-app/main/default/classes/CarrierWarningTest.cls-meta.xml`
- Modify: `force-app/main/default/classes/LaneSearchQueryBuilder.cls` (`SELECT_CLAUSE` only: `Carrier_Att__c` becomes `rtms__Vendor__r.Black_List__c, rtms__Carrier_Service__r.rtms__Transportation_Profile__r.Outstanding_Claim__c`; Task 2's extraction is left as it is)
- Modify: `force-app/main/default/classes/LaneSearchService.cls` (`toRow`: the `r.carrier.attention` line)
- Modify: `force-app/main/default/classes/BidSearchQueryBuilder.cls` (`SELECT_CLAUSE`: adds `Carrier__r.Black_List__c`)
- Modify: `force-app/main/default/classes/BidSearchService.cls` (`toRow`: sets `r.carrier.attention`)
- Modify: `force-app/main/default/classes/LaneSearchQueryBuilderTest.cls` (Task 2's expected SELECT text, plus one new test)
- Modify: `force-app/main/default/classes/LaneSearchServiceTest.cls` (the clean-carrier assertion in `cityPrecisionMatchesOnlyThatCityAndToleratesAccents`, plus one new test)
- Modify: `force-app/main/default/classes/BidSearchServiceTest.cls` (one new test)
- Modify: `manifest/package.xml` (ApexClass members `CarrierWarning`, `CarrierWarningTest`)
- No change: `lwc/laneBenchmarkResults` (reads `carrier.attention` and trims it), `LaneSearchResult` (`CarrierDetail.attention` exists), permission sets (the services read in system mode; `Lane_Benchmark_User` keeps its unused read on `Carrier_Att__c`, since this phase makes no other permission change).

**Interfaces:**

- Consumes:
  - `Account.Black_List__c` (Checkbox, not a formula; verified in PostProduc), `rtms__TransportationProfile__c.Outstanding_Claim__c` (Checkbox, default false, in `force-app/main/default/objects`), `rtms__CarrierQuote__c.rtms__Vendor__c` and `rtms__Carrier_Service__c`, `rtms__CarrierService__c.rtms__Transportation_Profile__c`, `Benchmark_Rate__c.Carrier__c` (Lookup(Account), relationship `Carrier__r`).
  - `LaneSearchResult.CarrierDetail.attention` (String, exists).
  - `PricingTestDataFactory.createGraph()` (`Graph.vendor` is the quote's `rtms__Vendor__c`; `Graph.profile` is the Transportation Profile of `Graph.carrierService`), `PricingTestDataFactory.createLoad(Graph, Account, Account)`, `PricingTestDataFactory.buildQuote(Graph, rtms__Load__c, Decimal)`, `RfpTestDataFactory.createPlace`, `createProject`, `createLane`, `buildBid`, `hiddenCarrier()` (a Carrier record type account inserted with `Black_List__c = true`), all existing.
  - `LaneSearchQueryBuilderTest` as Task 2 leaves it: an exact expected SELECT (a string it compares with `buildSoql`'s output) that contains the text `Carrier_Att__c, ` at least once, and whatever test methods Task 2 wrote (this task only adds one).
- Produces:
  - `public with sharing class CarrierWarning` with `public static String text(Boolean blacklisted, Boolean underClaim)`: `((blacklisted == true ? ' THE CARRIER IS BLACK-LISTED ' : '') + (underClaim == true ? ' UNDER A CLAIM ' : '')).trim()`, or `null` when that is empty. The four results are `null`, `THE CARRIER IS BLACK-LISTED`, `UNDER A CLAIM` and `THE CARRIER IS BLACK-LISTED  UNDER A CLAIM` (two spaces).
  - `LaneSearchQueryBuilder` SELECT ends with `..., Carrier_Risk__c, Nb_of_loads__c, rtms__Vendor__r.Black_List__c, rtms__Carrier_Service__r.rtms__Transportation_Profile__r.Outstanding_Claim__c, CreatedDate FROM rtms__CarrierQuote__c`. Nothing in `force-app/main/default/classes` reads `Carrier_Att__c` any more.
  - Quote rows: `row.carrier.attention = CarrierWarning.text(q.rtms__Vendor__r?.Black_List__c, q.rtms__Carrier_Service__r?.rtms__Transportation_Profile__r?.Outstanding_Claim__c)`. Bid rows: `row.carrier.attention = CarrierWarning.text(b.Carrier__r?.Black_List__c, false)`.

- [ ] **Step 1: Write the failing CarrierWarning test**

The four flag combinations, with the exact strings the `Carrier_Att__c` formula gives today. A query returns that formula trimmed: PostProduc returns `UNDER A CLAIM` for a profile under a claim.

Create `force-app/main/default/classes/CarrierWarningTest.cls`:

```apex
@IsTest
private class CarrierWarningTest {
  @IsTest
  static void noFlagGivesNoWarning() {
    System.assertEquals(
      null,
      CarrierWarning.text(false, false),
      'a clean carrier has no warning'
    );
    System.assertEquals(
      null,
      CarrierWarning.text(null, null),
      'a flag the query did not reach (no vendor, no profile) counts as not set'
    );
  }

  @IsTest
  static void theBlacklistFlagAloneGivesTheBlacklistText() {
    System.assertEquals(
      'THE CARRIER IS BLACK-LISTED',
      CarrierWarning.text(true, false),
      'the formula text, trimmed'
    );
    System.assertEquals(
      'THE CARRIER IS BLACK-LISTED',
      CarrierWarning.text(true, null),
      'a bid row passes no claim flag'
    );
  }

  @IsTest
  static void theClaimFlagAloneGivesTheClaimText() {
    System.assertEquals(
      'UNDER A CLAIM',
      CarrierWarning.text(false, true),
      'the text a query of Carrier_Att__c returns today'
    );
  }

  @IsTest
  static void bothFlagsKeepTheFormulaOrderWithTwoSpacesBetween() {
    System.assertEquals(
      'THE CARRIER IS BLACK-LISTED  UNDER A CLAIM',
      CarrierWarning.text(true, true),
      'blacklist first, then claim; the inner spaces of both texts stay'
    );
  }
}
```

Create `force-app/main/default/classes/CarrierWarningTest.cls-meta.xml`:

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<ApexClass xmlns="http://soap.sforce.com/2006/04/metadata">
    <apiVersion>64.0</apiVersion>
    <status>Active</status>
</ApexClass>
```

- [ ] **Step 2: Deploy the test alone to see it fail to compile**

Run: `sf project deploy start -o sandbox --source-dir force-app/main/default/classes/CarrierWarningTest.cls -l NoTestRun --async --json | python3 -c "import json,sys; s=sys.stdin.read(); print(json.loads(s[s.index('{'):])['result']['id'])"`

Expected: a deploy id (`0Af...`). Then poll, repeating until the status is `Succeeded` or `Failed` (each call waits at most 2 minutes):

Run: `sf project deploy report -o sandbox --job-id <id> -w 2 --json | python3 -c "import json,sys; s=sys.stdin.read(); r=json.loads(s[s.index('{'):])['result']; print(r['status'], [d.get('problem') for d in r.get('details',{}).get('componentFailures',[])][:2])"`

Expected: `Failed` with `Invalid type: CarrierWarning`. The class does not exist yet.

- [ ] **Step 3: Extend the three search tests**

`LaneSearchQueryBuilderTest` (Task 2). First, point its exact expected SELECT at the two flags. Task 2 copied the builder's select, so it contains `Carrier_Att__c, `.

Run:

```bash
python3 - <<'PY'
p = 'force-app/main/default/classes/LaneSearchQueryBuilderTest.cls'
s = open(p).read()
n = s.count('Carrier_Att__c, ')
s = s.replace('Carrier_Att__c, ', 'rtms__Vendor__r.Black_List__c, rtms__Carrier_Service__r.rtms__Transportation_Profile__r.Outstanding_Claim__c, ')
open(p, 'w').write(s)
print('replaced', n)
PY
grep -c "Carrier_Att__c" force-app/main/default/classes/LaneSearchQueryBuilderTest.cls
```

Expected: `replaced 1`, then `0`. A number above 1 only means Task 2 repeated the SELECT in several tests; every copy is replaced. `replaced 0` means Task 2 is not in the tree: stop.

Then add this test to `LaneSearchQueryBuilderTest.cls`, directly before the class's closing `}`:

```apex
  /**
   * Phase 8 (Task 4): the select reads the two flags CarrierWarning joins, right before
   * CreatedDate, and no longer the Carrier_Att__c formula.
   */
  @IsTest
  static void selectReadsTheWarningFlagsInsteadOfTheFormula() {
    LaneSearchRequest request = new LaneSearchRequest();
    request.validate();
    String soql = LaneSearchQueryBuilder.buildSoql(
      request,
      new Map<String, Object>(),
      new Map<String, Pricing_Place__c>()
    );
    System.assert(
      soql.contains(
        ', Nb_of_loads__c, rtms__Vendor__r.Black_List__c, rtms__Carrier_Service__r.rtms__Transportation_Profile__r.Outstanding_Claim__c, CreatedDate FROM rtms__CarrierQuote__c WHERE '
      ),
      soql
    );
    System.assert(!soql.contains('Carrier_Att__c'), soql);
  }
```

`LaneSearchServiceTest.cls`. In `cityPrecisionMatchesOnlyThatCityAndToleratesAccents`, replace:

```apex
    System.assert(
      String.isBlank(r.rows[0].carrier.attention),
      'clean profile (no BlackList__c/Outstanding_Claim__c) has no attention flags'
    );
```

with:

```apex
    System.assertEquals(
      null,
      r.rows[0].carrier.attention,
      'a vendor that is not blacklisted, on a profile with no claim, has no warning'
    );
```

(An empty `Carrier_Att__c` already comes back as null in PostProduc, so this assertion passes before and after the change.) Then add the inner class and the test directly before the class's closing `}`:

```apex
  /**
   * Phase 8: builders for theWarningReadsTheVendorBlacklistAndTheProfileClaim. An inner class with
   * instance methods, so they stay out of this test class's PMD complexity total (37 of 40 before
   * phase 8).
   */
  private class WarningFixture {
    /**
     * A second carrier chain like the graph's (account, quote contact, Transportation Profile,
     * carrier service) on RfpTestDataFactory.hiddenCarrier(), which is inserted with
     * Black_List__c = true. The flag is set at insert on purpose: switching it on by an update
     * starts the org's Account_BlackList flow, which hands the account to another owner. A quote
     * keeps its vendor and its carrier service on the same account, as every quote in PostProduc
     * does.
     */
    rtms__CarrierService__c blacklistedCarrierService(
      PricingTestDataFactory.Graph g
    ) {
      Account carrier = RfpTestDataFactory.hiddenCarrier();
      Contact quoteContact = new Contact(
        FirstName = 'Blacklisted',
        LastName = 'Contact',
        AccountId = carrier.Id,
        Email = 'blacklisted.contact@example.invalid',
        Phone = '514-555-0101'
      );
      insert quoteContact;
      rtms__TransportationProfile__c carrierProfile = new rtms__TransportationProfile__c(
        Name = 'Blacklisted Carrier Profile',
        RecordTypeId = Schema.SObjectType.rtms__TransportationProfile__c
          .getRecordTypeInfosByDeveloperName()
          .get('Carrier')
          .getRecordTypeId(),
        rtms__Company_Risk__c = 'Acceptable',
        rtms__Carrier_Remit_To__c = carrier.Id
      );
      insert carrierProfile;
      rtms__CarrierService__c carrierService = new rtms__CarrierService__c(
        Name = 'Blacklisted Carrier Service',
        rtms__Carrier__c = carrier.Id,
        rtms__Mode__c = g.mode.Id,
        rtms__Transportation_Profile__c = carrierProfile.Id,
        rtms__Quote_Contact__c = quoteContact.Id,
        rtms__Minimum_Weight__c = 0,
        rtms__Maximum_Weight__c = 100000
      );
      insert carrierService;
      return carrierService;
    }

    /** Each row's warning by its total; the quotes of one test have distinct totals. */
    Map<Integer, String> warningsByTotal(LaneSearchResult result) {
      Map<Integer, String> byTotal = new Map<Integer, String>();
      for (LaneSearchResult.Row row : result.rows) {
        byTotal.put(row.carrierTotal.intValue(), row.carrier.attention);
      }
      return byTotal;
    }
  }

  /**
   * Phase 8: the red warning takes its blacklist text from the vendor account's Black_List__c and
   * keeps its claim text from the Transportation Profile's Outstanding_Claim__c (spec D5, R90).
   * Carrier_Att__c read the blacklist from the profile, so the blacklisted vendor showed nothing.
   * The second carrier chain is inserted before Test.startTest() and the load inside it: the chain
   * spends the budget one load outside would have used (PricingTestDataFactory class doc).
   */
  @IsTest
  static void theWarningReadsTheVendorBlacklistAndTheProfileClaim() {
    Fixture f = fixture();
    WarningFixture w = new WarningFixture();
    rtms__CarrierService__c blacklistedService = w.blacklistedCarrierService(
      f.g
    );
    Test.startTest();
    f.mtlTor = PricingTestDataFactory.createLoad(
      f.g,
      f.g.originLocation,
      f.g.destinationLocation
    );
    rtms__CarrierQuote__c blacklistedQuote = PricingTestDataFactory.buildQuote(
      f.g,
      f.mtlTor,
      2000
    );
    blacklistedQuote.rtms__Carrier_Service__c = blacklistedService.Id;
    blacklistedQuote.rtms__Vendor__c = blacklistedService.rtms__Carrier__c;
    blacklistedQuote.rtms__Quote_Contact__c = blacklistedService.rtms__Quote_Contact__c;
    insert new List<rtms__CarrierQuote__c>{
      PricingTestDataFactory.buildQuote(f.g, f.mtlTor, 1000),
      blacklistedQuote
    };
    Map<Integer, String> beforeClaims = w.warningsByTotal(
      LaneSearchService.search(req('montreal|qc|ca', 'toronto|on|ca'))
    );
    update new List<rtms__TransportationProfile__c>{
      new rtms__TransportationProfile__c(
        Id = f.g.profile.Id,
        Outstanding_Claim__c = true
      ),
      new rtms__TransportationProfile__c(
        Id = blacklistedService.rtms__Transportation_Profile__c,
        Outstanding_Claim__c = true
      )
    };
    Map<Integer, String> afterClaims = w.warningsByTotal(
      LaneSearchService.search(req('montreal|qc|ca', 'toronto|on|ca'))
    );
    Test.stopTest();

    System.assertEquals(
      new Set<Integer>{ 1000, 2000 },
      beforeClaims.keySet(),
      'both quotes are on the lane'
    );
    System.assertEquals(
      null,
      beforeClaims.get(1000),
      'the graph vendor is not blacklisted and its profile has no claim'
    );
    System.assertEquals(
      'THE CARRIER IS BLACK-LISTED',
      beforeClaims.get(2000),
      'the vendor account is blacklisted; its profile is not flagged'
    );
    System.assertEquals(
      'UNDER A CLAIM',
      afterClaims.get(1000),
      'the claim text still comes from the Transportation Profile'
    );
    System.assertEquals(
      'THE CARRIER IS BLACK-LISTED  UNDER A CLAIM',
      afterClaims.get(2000),
      'blacklist first, then the claim, as in the formula'
    );
  }
```

The fixture flips no Account flag by update. In PostProduc an update that turns `Black_List__c` on runs the `Account_BlackList` flow, which sets `OwnerId` and `Inactivity_Limit__c` and so runs `OwnershipEnforcer`. `hiddenCarrier()` sets the flag at insert instead, which neither flow handles. The profile update is safe: no active `rtms__TransportationProfile__c` validation rule reads `Outstanding_Claim__c`, and `Carrier_is_black_listed` needs the profile's own `BlackList__c`. Each new quote keeps `rtms__Vendor__c` equal to its carrier service's carrier, as all 2,000 recent PostProduc quotes do. `WarningFixture` is an inner class because `LaneSearchServiceTest` is at 37 of PMD's 40. With two static helpers it measured 41; with the inner class it measures 38.

`BidSearchServiceTest.cls`: add this test directly before `private static List<Decimal> ratesFor(`:

```apex
  /**
   * Phase 8: a bid whose carrier account is blacklisted carries the same warning text as a quote
   * row; a bid on a clean carrier account and a bid that only names its carrier carry none. A bid
   * has no Transportation Profile, so never the claim text (spec D5).
   */
  @IsTest
  static void aBlacklistedBidCarrierGetsTheWarning() {
    PricingTestDataFactory.Graph g = PricingTestDataFactory.createGraph();
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
    RFP_Lane__c lane = RfpTestDataFactory.createLane(
      RfpTestDataFactory.createProject(g.customer),
      mtl,
      tor
    );
    Benchmark_Rate__c blacklisted = RfpTestDataFactory.buildBid(lane, 1000);
    blacklisted.Carrier__c = RfpTestDataFactory.hiddenCarrier().Id;
    Benchmark_Rate__c clean = RfpTestDataFactory.buildBid(lane, 2000);
    clean.Carrier__c = g.vendor.Id;
    insert new List<Benchmark_Rate__c>{
      blacklisted,
      clean,
      RfpTestDataFactory.buildBid(lane, 3000)
    };
    LaneSearchRequest request = new LaneSearchRequest();
    request.originKey = mtl.Key__c;
    request.destinationKey = tor.Key__c;
    request.validate();

    Test.startTest();
    List<LaneSearchResult.Row> rows = BidSearchService.search(
      request,
      new Map<String, Pricing_Place__c>{ mtl.Key__c => mtl, tor.Key__c => tor },
      new BidSearchService.Outcome()
    );
    Test.stopTest();

    Map<Integer, String> warningByRate = new Map<Integer, String>();
    for (LaneSearchResult.Row r : rows) {
      warningByRate.put(r.carrierTotal.intValue(), r.carrier.attention);
    }
    System.assertEquals(
      new Set<Integer>{ 1000, 2000, 3000 },
      warningByRate.keySet(),
      'the three live bids on the lane'
    );
    System.assertEquals(
      'THE CARRIER IS BLACK-LISTED',
      warningByRate.get(1000),
      'the bid carrier account is blacklisted'
    );
    System.assertEquals(
      null,
      warningByRate.get(2000),
      'the graph vendor is not blacklisted'
    );
    System.assertEquals(
      null,
      warningByRate.get(3000),
      'a bid that only names its carrier has no account flag'
    );
  }
```

- [ ] **Step 4: Deploy the extended tests to see them fail**

Run: `sf project deploy start -o sandbox --source-dir force-app/main/default/classes/LaneSearchQueryBuilderTest.cls --source-dir force-app/main/default/classes/LaneSearchServiceTest.cls --source-dir force-app/main/default/classes/BidSearchServiceTest.cls -l RunSpecifiedTests -t LaneSearchQueryBuilderTest -t LaneSearchServiceTest -t BidSearchServiceTest --async --json | python3 -c "import json,sys; s=sys.stdin.read(); print(json.loads(s[s.index('{'):])['result']['id'])"`

Expected: a deploy id. Poll until the status is `Succeeded` or `Failed`:

Run: `sf project deploy report -o sandbox --job-id <id> -w 2 --json | python3 -c "import json,sys; s=sys.stdin.read(); r=json.loads(s[s.index('{'):])['result']; print(r['id'], r['status'], 'tests', r.get('numberTestsCompleted'), '/', r.get('numberTestsTotal'), 'failures', r.get('numberTestErrors')); [print(f['name'], f['methodName'], '->', f['message'][:160]) for f in r.get('details',{}).get('runTestResult',{}).get('failures',[])]"`

Expected: `Failed`, and only these failures:

- `LaneSearchQueryBuilderTest selectReadsTheWarningFlagsInsteadOfTheFormula -> System.AssertException: Assertion Failed: SELECT Id, Name, ...Carrier_Att__c, CreatedDate FROM rtms__CarrierQuote__c WHERE ...`
- the 8 Task 2 methods that compare the whole quote SOQL (every method except `aZip3EndWhosePlaceHasNoPrefixNamesTheFieldToPass`), each `Expected: SELECT ... rtms__Vendor__r.Black_List__c ..., Actual: SELECT ... Carrier_Att__c ...`, so 11 failures in all (1 new builder test, 8 characterization tests, 1 quote test, 1 bid test); a 12th failure is not expected
- `LaneSearchServiceTest theWarningReadsTheVendorBlacklistAndTheProfileClaim -> System.AssertException: Assertion Failed: the vendor account is blacklisted; its profile is not flagged: Expected: THE CARRIER IS BLACK-LISTED, Actual: null`
- `BidSearchServiceTest aBlacklistedBidCarrierGetsTheWarning -> System.AssertException: Assertion Failed: the bid carrier account is blacklisted: Expected: THE CARRIER IS BLACK-LISTED, Actual: null`

A `System.DmlException` from `WarningFixture.blacklistedCarrierService`, from the profile update or from the bid insert is not an expected failure. It means PostProduc automation refuses the fixture: stop and report the message; do not weaken the test.

- [ ] **Step 5: Write CarrierWarning**

Create `force-app/main/default/classes/CarrierWarning.cls`:

```apex
/**
 * Phase 8: the red carrier warning on lane search rows, shown by laneBenchmarkResults on Lane
 * Benchmark and in the RFP lane panel's history results. It used to be the
 * rtms__CarrierQuote__c.Carrier_Att__c formula, whose blacklist half reads the Transportation
 * Profile's BlackList__c (no quote in a year) while carriers are blacklisted on
 * Account.Black_List__c (548 accounts). The two texts and their order stay the formula's: the
 * blacklist flag now comes from the carrier account (a quote's rtms__Vendor__r, a bid's
 * Carrier__r), and the claim flag still comes from the quote's Transportation Profile (spec D5,
 * R90). Built here so quote rows and bid rows share one text and LaneSearchService keeps its PMD
 * complexity budget.
 */
public with sharing class CarrierWarning {
  private static final String BLACKLIST_TEXT = ' THE CARRIER IS BLACK-LISTED ';
  private static final String CLAIM_TEXT = ' UNDER A CLAIM ';

  /**
   * The formula's texts in its order, trimmed the way a query returns the formula ("UNDER A
   * CLAIM"), so both flags keep two spaces between the texts. A null flag counts as not set; null
   * when neither flag is set.
   */
  public static String text(Boolean blacklisted, Boolean underClaim) {
    String joined =
      (blacklisted == true ? BLACKLIST_TEXT : '') +
      (underClaim == true ? CLAIM_TEXT : '');
    String trimmed = joined.trim();
    return String.isEmpty(trimmed) ? null : trimmed;
  }
}
```

The constants are `BLACKLIST_TEXT` and `CLAIM_TEXT`, not `BLACKLISTED` or `UNDER_CLAIM`. Apex identifiers are case-insensitive, and the parameter `blacklisted` would collide with a constant `BLACKLISTED`.

Create `force-app/main/default/classes/CarrierWarning.cls-meta.xml`:

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<ApexClass xmlns="http://soap.sforce.com/2006/04/metadata">
    <apiVersion>64.0</apiVersion>
    <status>Active</status>
</ApexClass>
```

- [ ] **Step 6: Read the two flags in the searches and build the text**

`force-app/main/default/classes/LaneSearchQueryBuilder.cls`: replace:

```apex
public with sharing class LaneSearchQueryBuilder {
  private static final String SELECT_CLAUSE =
```

with:

```apex
public with sharing class LaneSearchQueryBuilder {
  // Phase 8: the vendor account's blacklist flag and the Transportation Profile's claim flag replace
  // the Carrier_Att__c formula, whose blacklist half read the profile; LaneSearchService.toRow joins
  // them with CarrierWarning.text (spec D5).
  private static final String SELECT_CLAUSE =
```

and replace:

```apex
    'Contact_Email__c, Contact_Phone__c, Carrier_Risk__c, Nb_of_loads__c, Carrier_Att__c, ' +
    'CreatedDate FROM rtms__CarrierQuote__c';
```

with:

```apex
    'Contact_Email__c, Contact_Phone__c, Carrier_Risk__c, Nb_of_loads__c, ' +
    'rtms__Vendor__r.Black_List__c, rtms__Carrier_Service__r.rtms__Transportation_Profile__r.Outstanding_Claim__c, ' +
    'CreatedDate FROM rtms__CarrierQuote__c';
```

Nothing else in `LaneSearchQueryBuilder` changes. Task 2's `LaneKeyMatcher` call in `addEnd` and the bind names stay as they are. The new select was run read-only in PostProduc on 2026-09-15 (the full clause, `LIMIT 3`, on quotes under a claim). It returned `rtms__Vendor__r.Black_List__c` false, `Outstanding_Claim__c` true and `Carrier_Att__c` `UNDER A CLAIM`.

`force-app/main/default/classes/LaneSearchService.cls`, in `toRow`: replace:

```apex
    r.carrier.attention = q.Carrier_Att__c;
```

with:

```apex
    // Phase 8: the vendor account's blacklist flag and the profile's claim flag (spec D5); a quote
    // with no vendor or no carrier service reads both as not set.
    r.carrier.attention = CarrierWarning.text(
      q.rtms__Vendor__r?.Black_List__c,
      q.rtms__Carrier_Service__r
        ?.rtms__Transportation_Profile__r
        ?.Outstanding_Claim__c
    );
```

PMD does not count the safe navigation operator. `LaneSearchService` stays at a class complexity of 28, as before (measured with PMD 7.15.0 on the changed file).

`force-app/main/default/classes/BidSearchQueryBuilder.cls`: replace:

```apex
public with sharing class BidSearchQueryBuilder {
  private static final String SELECT_CLAUSE =
    'SELECT Id, Name, RFP_Lane__c, RFP_Project__c, Carrier__c, Carrier_Name__c, Carrier_Display__c, ' +
```

with:

```apex
public with sharing class BidSearchQueryBuilder {
  // Phase 8: Carrier__r.Black_List__c feeds the bid row's carrier warning (BidSearchService.toRow).
  private static final String SELECT_CLAUSE =
    'SELECT Id, Name, RFP_Lane__c, RFP_Project__c, Carrier__c, Carrier__r.Black_List__c, Carrier_Name__c, Carrier_Display__c, ' +
```

`BidSearchQueryBuilderTest` still passes: it checks `startsWith('SELECT Id, Name, ')`. The bid select with `Carrier__r.Black_List__c` was run read-only in PostProduc. A bid without a carrier account returns `Carrier__r` null.

`force-app/main/default/classes/BidSearchService.cls`, in `toRow`: replace:

```apex
    r.carrier.contactPhone = b.Contact_Phone__c;
```

with:

```apex
    r.carrier.contactPhone = b.Contact_Phone__c;
    // Phase 8: the same warning as a quote row when the bid's carrier account is blacklisted; a bid
    // has no Transportation Profile, so no claim text (spec D5).
    r.carrier.attention = CarrierWarning.text(
      b.Carrier__r?.Black_List__c,
      false
    );
```

- [ ] **Step 7: Add the classes to the manifest**

In `manifest/package.xml`, inside the `<types>` block whose `<name>` is `ApexClass`, directly before `<name>ApexClass</name>` (after the members Tasks 1 to 3 added):

```xml
        <members>CarrierWarning</members>
        <members>CarrierWarningTest</members>
```

- [ ] **Step 8: Check that no code still reads the formula and that the screen needs no change**

Run: `grep -rnE "q\.Carrier_Att__c|Carrier_Att__c, '" force-app/main/default/classes; echo "grep exit $?"; grep -n "attention" force-app/main/default/lwc/laneBenchmarkResults/laneBenchmarkResults.js`

Expected: `grep exit 1` (no class selects or reads `Carrier_Att__c`; comments and the new test's `!soql.contains('Carrier_Att__c')` do not match), then lines 95 and 96, `return this.selected?.carrier?.attention` and `? this.selected.carrier.attention.trim()`. `c-lane-benchmark-results` shows `carrier.attention` as it is on Lane Benchmark and in `rfpLanePanel`, so no LWC or Jest file changes.

- [ ] **Step 9: Deploy the classes and run the tests**

First count the test methods the deploy runs:

Run: `for c in CarrierWarningTest LaneSearchQueryBuilderTest LaneSearchServiceTest BidSearchServiceTest BidSearchQueryBuilderTest LaneKeyMatcherTest; do echo "$c $(grep -c '^  @IsTest' force-app/main/default/classes/$c.cls)"; done`

Expected: `CarrierWarningTest 4`, `LaneSearchQueryBuilderTest 10`, `LaneSearchServiceTest 23`, `BidSearchServiceTest 5`, `BidSearchQueryBuilderTest 7`, `LaneKeyMatcherTest 9`; N = 58. When a printed count differs, use the printed numbers: N is their sum.

Each class this deploy carries has a covering test: `CarrierWarning` is covered by `CarrierWarningTest`; `LaneSearchQueryBuilder` by `LaneSearchQueryBuilderTest` and `LaneSearchServiceTest`; `LaneSearchService` by `LaneSearchServiceTest`; `BidSearchQueryBuilder` by `BidSearchQueryBuilderTest`; `BidSearchService` by `BidSearchServiceTest` and `LaneSearchServiceTest`. `LaneKeyMatcherTest` runs too, because the search builder calls `LaneKeyMatcher` since Task 2.

Run: `sf project deploy start -o sandbox --source-dir force-app/main/default/classes/CarrierWarning.cls --source-dir force-app/main/default/classes/CarrierWarningTest.cls --source-dir force-app/main/default/classes/LaneSearchQueryBuilder.cls --source-dir force-app/main/default/classes/LaneSearchService.cls --source-dir force-app/main/default/classes/BidSearchQueryBuilder.cls --source-dir force-app/main/default/classes/BidSearchService.cls --source-dir force-app/main/default/classes/LaneSearchQueryBuilderTest.cls --source-dir force-app/main/default/classes/LaneSearchServiceTest.cls --source-dir force-app/main/default/classes/BidSearchServiceTest.cls -l RunSpecifiedTests -t CarrierWarningTest -t LaneSearchQueryBuilderTest -t LaneSearchServiceTest -t BidSearchServiceTest -t BidSearchQueryBuilderTest -t LaneKeyMatcherTest --async --json | python3 -c "import json,sys; s=sys.stdin.read(); print(json.loads(s[s.index('{'):])['result']['id'])"`

Expected: a deploy id. Poll until the status is `Succeeded` or `Failed`:

Run: `sf project deploy report -o sandbox --job-id <id> -w 2 --json | python3 -c "import json,sys; s=sys.stdin.read(); r=json.loads(s[s.index('{'):])['result']; print(r['id'], r['status'], 'tests', r.get('numberTestsCompleted'), '/', r.get('numberTestsTotal'), 'failures', r.get('numberTestErrors')); [print(f['name'], f['methodName'], '->', f['message'][:160]) for f in r.get('details',{}).get('runTestResult',{}).get('failures',[])]"`

Expected: `Succeeded tests N / N failures 0`. The org enforces 75 % coverage per deployed class, so `Succeeded` also means each of the five classes is covered; a shortfall comes back as `Failed` with a code coverage message. If a test fails, fix the class, not the assertion, unless the assertion contradicts the spec. `Expected: THE CARRIER IS BLACK-LISTED, Actual: null` on the quote test means `toRow` still reads the formula or the select lacks `rtms__Vendor__r.Black_List__c`. The same message on the bid test means `BidSearchQueryBuilder` lacks `Carrier__r.Black_List__c`. `Actual: UNDER A CLAIM` where the two texts are expected means the vendor path is not read. `SObject row was retrieved via SOQL without querying the requested field` names the select path that is missing. `Too many SOQL queries: 101` in `theWarningReadsTheVendorBlacklistAndTheProfileClaim`: move the first `LaneSearchService.search` and the `beforeClaims` assertions into a second test method `theWarningReadsTheVendorBlacklist` (same fixture, no profile update), keep only the profile update and the second search in this one, and count that method in N.

- [ ] **Step 10: PMD and Prettier**

Run: `/private/tmp/pmd_install/pmd-bin-7.15.0/bin/pmd check --dir force-app --rulesets config/pmd-ruleset.xml --minimum-priority 3 --format text --fail-on-violation; echo "pmd exit $?"`

Expected: no violation lines, `pmd exit 0`. Measured on the changed classes with PMD 7.15.0: `CarrierWarning` 4, `LaneSearchService` 28 (unchanged), `BidSearchService` 14 (unchanged), `BidSearchQueryBuilder` 37 (unchanged), `LaneSearchServiceTest` 38 (was 37; `WarningFixture` 3 counts on its own), `BidSearchServiceTest` 13 (was 11), `CarrierWarningTest` 4. `LaneSearchQueryBuilder` does not change from Task 2. No suppression is added.

Run: `npx prettier --check force-app/main/default/classes/CarrierWarning.cls force-app/main/default/classes/CarrierWarningTest.cls force-app/main/default/classes/LaneSearchQueryBuilder.cls force-app/main/default/classes/LaneSearchService.cls force-app/main/default/classes/BidSearchQueryBuilder.cls force-app/main/default/classes/BidSearchService.cls force-app/main/default/classes/LaneSearchServiceTest.cls force-app/main/default/classes/BidSearchServiceTest.cls force-app/main/default/classes/LaneSearchQueryBuilderTest.cls`

Expected: `All matched files use Prettier code style!` The code above is Prettier's own output for these files. If it lists a file, lint-staged reformats it on commit; nothing else to do.

- [ ] **Step 11: Commit**

```bash
git add force-app/main/default/classes/CarrierWarning.cls force-app/main/default/classes/CarrierWarning.cls-meta.xml force-app/main/default/classes/CarrierWarningTest.cls force-app/main/default/classes/CarrierWarningTest.cls-meta.xml force-app/main/default/classes/LaneSearchQueryBuilder.cls force-app/main/default/classes/LaneSearchService.cls force-app/main/default/classes/BidSearchQueryBuilder.cls force-app/main/default/classes/BidSearchService.cls force-app/main/default/classes/LaneSearchQueryBuilderTest.cls force-app/main/default/classes/LaneSearchServiceTest.cls force-app/main/default/classes/BidSearchServiceTest.cls manifest/package.xml
git commit -m "Build the results carrier warning from the account blacklist flag"
```

Expected: lint-staged runs Prettier on the staged Apex, and the commit lands on `phase-8/carriers-and-split-lanes` with no attribution trailer. `git status --short` shows nothing from this task; `.vscode/settings.json` and any `* 2.*` file stay unstaged.

#### Contract notes (Task 4)

1. **The quote test builds a blacklisted carrier at insert and does not update `Graph.vendor`.** In PostProduc, an update that turns `Account.Black_List__c` on runs the active flow `Account_BlackList`. That flow sets `OwnerId` to a fixed user and `Inactivity_Limit__c` to 999, which runs `AccountOwnershipTrigger`/`OwnershipEnforcer` and its reclaim rules. The fixture is instead a second carrier chain on `RfpTestDataFactory.hiddenCarrier()` (inserted with `Black_List__c = true`, like the phase 6 sharing tests): a quote contact, a Transportation Profile and a carrier service. The quote keeps `rtms__Vendor__c` equal to its service's carrier, as on 2,000 of 2,000 recent quotes. Both halves of the warning are tested end to end. The claim half is not left to `CarrierWarningTest` alone: tests can set `Outstanding_Claim__c`, a plain Checkbox, by updating the profile, and no active profile validation rule reads it (`Carrier_is_black_listed` needs the profile's own `BlackList__c`). Checked read-only on 2026-09-15: validation rules on Account and Transportation Profile, the Account and profile flows, the trigger list.
2. **`LaneSearchServiceTest` was at a class complexity of 37 of 40**, a class the contract's budget list does not name. Two static helpers took it to 41. They live in the inner class `WarningFixture` (instance methods), which leaves the outer class at 38. Later tasks that extend `LaneSearchServiceTest` have 2 points left.
3. **The fixture's load, quotes, profile update and searches run inside `Test.startTest()`; the second carrier chain is created before it.** The contract rule is fixture DML before `Test.startTest()`, but `PricingTestDataFactory` documents that the graph, one more carrier chain and a load do not share one synchronous budget. The profile update between the two searches is the behaviour under test. No callout is involved.
4. **`LaneSearchQueryBuilderTest` is edited by content, not by line.** Task 2's draft was not available when this task was drafted. Step 3 replaces every `Carrier_Att__c, ` in the file, prints the count and checks that none is left, and the added method `selectReadsTheWarningFlagsInsteadOfTheFormula` uses no Task 2 helper. If Task 2 builds its expected SELECT without the literal `Carrier_Att__c, `, the assembler aligns Step 3 with Task 2's text.
5. **`CarrierWarning` has two private constants, `BLACKLIST_TEXT` and `CLAIM_TEXT`**, besides the contract's single method, named so they do not collide case-insensitively with the parameters. `BidSearchService` passes `false` for the claim flag, as the contract writes.
6. **SOQL proofs** (read-only, 2026-09-15, saved under `phase8-plan-drafts/soql/`): the full new quote select (`t04-quote-select.json`); the bid select with `Carrier__r.Black_List__c` (`t04-bid-select.json`); an empty `Carrier_Att__c` comes back null (`t04-att-empty.json`), so the stricter clean-carrier assertion is not among Step 4's failures. `Account.Black_List__c` is a Checkbox and not a formula (`t04-bl-field.json`).
7. **No permission change.** `Lane_Benchmark_User` keeps its read on `rtms__CarrierQuote__c.Carrier_Att__c`, which no code reads any more. The contract allows no other permission change this phase; removing it is left for a later cleanup.
8. **Counts:** this task adds 7 Apex tests (4 in `CarrierWarningTest`, 1 each in `LaneSearchQueryBuilderTest`, `LaneSearchServiceTest` and `BidSearchServiceTest`) and one roster class, `CarrierWarningTest`, which Task 11 adds to every roster site. No Jest change.


---

### Task 5: Carriers to ask stage 1 — `CarrierLeadResult`, `LaneQueries`, `CarrierLeadService.find` on the same lane

**Files:**

- Create: `force-app/main/default/classes/CarrierLeadResult.cls`, `force-app/main/default/classes/CarrierLeadResult.cls-meta.xml`
- Create: `force-app/main/default/classes/LaneQueries.cls`, `force-app/main/default/classes/LaneQueries.cls-meta.xml`
- Create: `force-app/main/default/classes/LaneQueriesTest.cls`, `force-app/main/default/classes/LaneQueriesTest.cls-meta.xml`
- Create: `force-app/main/default/classes/CarrierLeadService.cls`, `force-app/main/default/classes/CarrierLeadService.cls-meta.xml`
- Create: `force-app/main/default/classes/CarrierLeadServiceTest.cls`, `force-app/main/default/classes/CarrierLeadServiceTest.cls-meta.xml`
- Modify: `manifest/package.xml` (ApexClass members `CarrierLeadResult`, `LaneQueries`, `LaneQueriesTest`, `CarrierLeadService`, `CarrierLeadServiceTest`, directly before `<name>ApexClass</name>`, after the members Tasks 1 to 4 added)
- Unchanged: `LaneSearchService`, `LaneSearchQueryBuilder`, `LaneSearchFilters`, `LaneSearchRequest`, `LaneSearchExclusions` and every RFP class.

**Interfaces:**

- Consumes:
  - Task 1: `FreightPlanReader.read(String soql, Map<String, Object> binds)` (`public without sharing`; returns `rowsOverride` when it is not null, else `Database.queryWithBinds(soql, binds, AccessLevel.SYSTEM_MODE)`) and its `@TestVisible private static List<rtms__FreightPlan__c> rowsOverride`; `SplitTestData.carrier(String name, Boolean blacklisted)` (an inserted account of the `Carrier` record type), `SplitTestData.legLoad(PricingTestDataFactory.Graph g, Account origin, Account destination, Account carrierAccount, Decimal cadTotal, String status)`, `SplitTestData.plan(rtms__Load__c customerLoad, List<rtms__Load__c> legLoads)`, `SplitTestData.resetPlans()`.
  - Task 2: `LaneKeyMatcher.condition(String loadPath, Boolean isOrigin, String bindPrefix, LaneSearchRequest.Precision precision, Pricing_Place__c place, String explicitZip3, Map<String, Object> binds)` (binds `<prefix>City` as a `List<String>`, `<prefix>Prov` and `<prefix>Zip3` as a `String`; `null` when no constraint applies) and `LaneLoadFilters.add(LaneSearchRequest req, String loadPath, List<String> conditions, Map<String, Object> binds)` (mode, equipment, hazmat; binds `modes`, `cats`, `types`).
  - Task 3: `IntercompanyCarriers.ids()` (never null) and `@TestVisible private static Set<Id> idsOverride`.
  - Existing: `LaneSearchExclusions.excludedContactIdSet()` and `excludedContactIdsOverride` (15-character Contact Ids, as `Contact_ID__c` holds them); `LaneSearchRequest.applyDefaults()`, `Precision`, `Accepted`, `RowSource`; `PricingTestDataFactory.createGraph()`, `createLoad(Graph, Account, Account)`, `buildQuote(Graph, rtms__Load__c, Decimal)`; `RfpTestDataFactory.createPlace(city, prov, country, lat, lng, prefix)`.
- Produces:
  - `CarrierLeadResult` (plain `public class`): constants `SAME_LANE = 'Same lane'`, `STATE_LANE = 'State lane'`, `NONE = 'None'`, `SOURCE_QUOTE = 'Quote'`, `SOURCE_SPLIT_LEG = 'Split leg'`; `public class Lead { @AuraEnabled Id carrierId; String name; Integer loadsMoved = 0; Integer loadsQuoted = 0; Date lastSeen; List<String> sources = new List<String>(); Boolean blacklisted = false; Boolean canOpen = false; }` (every member `public` and `@AuraEnabled`); `@AuraEnabled public List<Lead> leads = new List<Lead>()`, `String stage = 'None'`, `String stateLaneLabel`, `Boolean truncated = false`. No amount field.
  - `LaneQueries` (`public with sharing`, no query): `public static final Map<String, String> COUNTRY_NAMES` (CA → Canada, US → United States, MX → Mexico); `public static final Integer GROUP_LIMIT = 50`; `public static LaneSearchRequest.Precision deepPrecision(LaneSearchRequest.Precision p)`; `public static List<String> laneConditions(LaneSearchRequest req, Pricing_Place__c origin, Pricing_Place__c destination, String loadPath, Map<String, Object> binds)`; `public static List<String> stateLaneConditions(LaneSearchRequest req, Pricing_Place__c origin, Pricing_Place__c destination, String loadPath, Map<String, Object> binds)` (binds `stateLane`, `oCountry`, `dCountry`; `null` with nothing bound when a `Province__c` is blank or a `Country__c` is not in `COUNTRY_NAMES`); `public static String quoteCountSoql(List<String> onLane, Integer days, Boolean movedOnly, Map<String, Object> binds)` (binds `excluded`, `marketTest`, `intercompany`; leaves out Market Test quotes; copies `onLane`); `public static String planSoql(List<String> customerConditions, Integer days, Integer planLimit, Boolean withAmounts)` (copies `customerConditions`). Task 9 adds `legConditions` and `legLoadSoql`.
  - `CarrierLeadService` (`public without sharing`): `public static CarrierLeadResult find(LaneSearchRequest req)` — stage 1 only; stage `None` when it finds no carrier. For Task 6, which adds stage 2 inside `find` and reuses them: `@TestVisible private static Integer rowReserve = 5000`; `@TestVisible private static List<CarrierLeadResult.Lead> ranked(List<CarrierLeadResult.Lead> leads, Boolean byQuoted)` (`true`: loads moved, loads quoted, last seen newest first with none last, name ignoring case; `false`: loads quoted skipped); `private static void countQuotes(List<String> onLane, Integer days, Map<String, Object> binds, Tally tally, CarrierLeadResult result)`; `private static void readLegs(List<String> onLane, Integer days, Map<String, Object> binds, Tally tally, CarrierLeadResult result)`; `private static Boolean stopEarly(CarrierLeadResult result)`; `private static void markReadable(CarrierLeadResult result)`; inner `private class Tally` (`isEmpty()`, `addQuoteGroups(List<AggregateResult>, Boolean moved)`, `addPlans(List<rtms__FreightPlan__c>, Set<Id> intercompany)`, `leads()`). PMD class complexity after this task: `CarrierLeadService` 24 of 40 (`Tally` 23 and `LeadOrder` 13 count on their own).

**Before you start:** Tasks 1 to 4 are committed and deployed to `sandbox`. The plan read, the lane matcher and the intercompany list come from them, and `CarrierLeadServiceTest` builds its plans only through `SplitTestData`, so it passes on whichever branch Task 1 proved.

- [ ] **Step 1: Check that Tasks 1 to 4 are in place and print the baseline**

Run: `ls force-app/main/default/classes/FreightPlanReader.cls force-app/main/default/classes/SplitTestData.cls force-app/main/default/classes/LaneKeyMatcher.cls force-app/main/default/classes/LaneLoadFilters.cls force-app/main/default/classes/IntercompanyCarriers.cls`

Expected: the five paths, no `No such file`.

Run: `grep -nE "static .*(read|rowsOverride|carrier|legLoad|plan|resetPlans|ids|idsOverride|condition|add)\(|rowsOverride;|idsOverride;" force-app/main/default/classes/FreightPlanReader.cls force-app/main/default/classes/SplitTestData.cls force-app/main/default/classes/IntercompanyCarriers.cls force-app/main/default/classes/LaneKeyMatcher.cls force-app/main/default/classes/LaneLoadFilters.cls`

Expected: the signatures listed under **Interfaces → Consumes**. Then read the class comment of `SplitTestData.cls` and note which branch Task 1 proved (A: plans inserted; B: rows built in memory); nothing below depends on it.

Run: `grep -n "RecordType" force-app/main/default/classes/SplitTestData.cls`

Expected: `carrier(...)` sets the `Carrier` record type. The test helper `quoter` gives such an account a carrier service, and the org's validation rule `Carrier_service_only_for_carriers` refuses a service whose account's record type is not named `Carrier`.

Run: `ls force-app/main/default/classes/*Test.cls | wc -l; ls force-app/main/default/classes/CarrierLeadResult.cls force-app/main/default/classes/LaneQueries.cls force-app/main/default/classes/CarrierLeadService.cls 2>&1 | grep -c "No such file"`

Expected: the test class count after Task 4 (print it; this task adds 2), then `3`: none of this task's classes exists yet.

- [ ] **Step 2: Write the failing `LaneQueriesTest`**

Create `force-app/main/default/classes/LaneQueriesTest.cls`:

```apex
@IsTest
private class LaneQueriesTest {
  private static final String NOT_CANCELLED = 'rtms__Load__r.rtms__Load_Status__c != \'Cancelled\'';

  private static Pricing_Place__c place(
    String city,
    String prov,
    String country,
    String prefix
  ) {
    return new Pricing_Place__c(
      City__c = city,
      Province__c = prov,
      Country__c = country,
      Postal_Prefix__c = prefix
    );
  }

  private static Pricing_Place__c montreal() {
    return place('Montreal', 'QC', 'CA', 'H1A');
  }

  private static Pricing_Place__c toronto() {
    return place('Toronto', 'ON', 'CA', 'M5V');
  }

  /** Mode, equipment and hazmat filters, plus every filter the deeper steps ignore (R101). */
  private static LaneSearchRequest filtered() {
    LaneSearchRequest req = new LaneSearchRequest();
    req.modes = new List<String>{ 'Truckload' };
    req.equipmentCategories = new List<String>{ 'Van' };
    req.equipmentTypes = new List<String>{ 'Dry Van 53\'' };
    req.hazmatOnly = true;
    req.currencyIsoCode = 'USD';
    req.lookbackDays = 30;
    req.acceptedFilter = LaneSearchRequest.Accepted.ACCEPTED;
    return req;
  }

  @IsTest
  static void laneConditionsMatchBothEndsAndKeepOnlyTheLoadFilters() {
    Map<String, Object> binds = new Map<String, Object>();
    List<String> conditions = LaneQueries.laneConditions(
      filtered(),
      montreal(),
      toronto(),
      'rtms__Load__r.',
      binds
    );
    System.assertEquals(
      new List<String>{
        'rtms__Load__r.rtms__City_Lane__c LIKE :oCity',
        'rtms__Load__r.rtms__City_Lane__c LIKE :dCity',
        'rtms__Load__r.rtms__Mode__r.Name IN :modes',
        '(rtms__Load__r.rtms__Equipment_Type__r.rtms__Category__c IN :cats OR rtms__Load__r.rtms__Equipment_Type__r.Name IN :types)',
        'rtms__Load__r.rtms__Hazardous_Materials__c = true',
        NOT_CANCELLED
      },
      conditions,
      'both ends, the mode, equipment and hazmat filters and a load that is not cancelled; no currency or accepted condition (quoteCountSoql adds the Market Test exclusion)'
    );
    System.assertEquals(
      new Set<String>{ 'oCity', 'dCity', 'modes', 'cats', 'types' },
      binds.keySet(),
      'no currency bind'
    );
    System.assertEquals(
      new List<String>{ 'Montreal, QC:%' },
      binds.get('oCity')
    );
    System.assertEquals(
      new List<String>{ '%:Toronto, ON' },
      binds.get('dCity')
    );
  }

  @IsTest
  static void laneConditionsOnLoadRowsUseNoPathAndARadiusEndUsesItsCityKey() {
    LaneSearchRequest radiusToProvince = new LaneSearchRequest();
    radiusToProvince.originPrecision = LaneSearchRequest.Precision.RADIUS;
    radiusToProvince.originRadius = 50;
    radiusToProvince.destinationPrecision = LaneSearchRequest.Precision.PROVINCE;
    Map<String, Object> binds = new Map<String, Object>();
    System.assertEquals(
      new List<String>{
        'rtms__City_Lane__c LIKE :oCity',
        'rtms__State_Lane__c LIKE :dProv',
        'rtms__Load_Status__c != \'Cancelled\''
      },
      LaneQueries.laneConditions(
        radiusToProvince,
        montreal(),
        toronto(),
        '',
        binds
      ),
      'a radius end is matched on its city key (R83); loads take no path'
    );
    System.assertEquals(
      new List<String>{ 'Montreal, QC:%' },
      binds.get('oCity')
    );
    System.assertEquals('%:ON', binds.get('dProv'));

    LaneSearchRequest byPostalPrefix = new LaneSearchRequest();
    byPostalPrefix.originPrecision = LaneSearchRequest.Precision.ZIP3;
    byPostalPrefix.destinationPrecision = LaneSearchRequest.Precision.ZIP3;
    byPostalPrefix.destinationZip3 = 'L5T';
    Map<String, Object> zipBinds = new Map<String, Object>();
    System.assertEquals(
      new List<String>{
        'rtms__Load__r.rtms__Zip3_Lane__c LIKE :oZip3',
        'rtms__Load__r.rtms__Zip3_Lane__c LIKE :dZip3',
        NOT_CANCELLED
      },
      LaneQueries.laneConditions(
        byPostalPrefix,
        montreal(),
        toronto(),
        'rtms__Load__r.',
        zipBinds
      )
    );
    System.assertEquals('H1A:%', zipBinds.get('oZip3'), 'the place prefix');
    System.assertEquals(
      '%:L5T',
      zipBinds.get('dZip3'),
      'the explicit prefix wins over the place'
    );
  }

  @IsTest
  static void deepPrecisionTurnsOnlyARadiusIntoACity() {
    System.assertEquals(
      LaneSearchRequest.Precision.CITY,
      LaneQueries.deepPrecision(LaneSearchRequest.Precision.RADIUS)
    );
    System.assertEquals(
      LaneSearchRequest.Precision.CITY,
      LaneQueries.deepPrecision(LaneSearchRequest.Precision.CITY)
    );
    System.assertEquals(
      LaneSearchRequest.Precision.PROVINCE,
      LaneQueries.deepPrecision(LaneSearchRequest.Precision.PROVINCE)
    );
    System.assertEquals(
      LaneSearchRequest.Precision.ZIP3,
      LaneQueries.deepPrecision(LaneSearchRequest.Precision.ZIP3)
    );
    System.assertEquals(null, LaneQueries.deepPrecision(null));
  }

  @IsTest
  static void stateLaneConditionsMatchTheStateLaneAndBothStopCountries() {
    LaneSearchRequest req = new LaneSearchRequest();
    req.modes = new List<String>{ 'Truckload' };
    req.currencyIsoCode = 'CAD';
    Map<String, Object> binds = new Map<String, Object>();
    System.assertEquals(
      new List<String>{
        'rtms__Load__r.rtms__State_Lane__c = :stateLane',
        'rtms__Load__r.rtms__First_Stop__r.rtms__Location2__r.ShippingCountry = :oCountry',
        'rtms__Load__r.rtms__Last_Stop__r.rtms__Location2__r.ShippingCountry = :dCountry',
        'rtms__Load__r.rtms__Mode__r.Name IN :modes',
        NOT_CANCELLED
      },
      LaneQueries.stateLaneConditions(
        req,
        montreal(),
        place('Monterrey', 'NL', 'MX', null),
        'rtms__Load__r.',
        binds
      )
    );
    System.assertEquals('QC:NL', binds.get('stateLane'));
    System.assertEquals('Canada', binds.get('oCountry'));
    System.assertEquals(
      'Mexico',
      binds.get('dCountry'),
      'NL is Nuevo León here, not Newfoundland: the stop country tells them apart'
    );

    Map<String, Object> loadBinds = new Map<String, Object>();
    List<String> onLoads = LaneQueries.stateLaneConditions(
      new LaneSearchRequest(),
      place('Laredo', 'TX', 'US', null),
      toronto(),
      '',
      loadBinds
    );
    System.assertEquals('rtms__State_Lane__c = :stateLane', onLoads[0]);
    System.assertEquals('TX:ON', loadBinds.get('stateLane'));
    System.assertEquals('United States', loadBinds.get('oCountry'));
    System.assertEquals('Canada', loadBinds.get('dCountry'));
  }

  @IsTest
  static void stateLaneConditionsAreNullWithoutAProvinceOrAKnownCountry() {
    LaneSearchRequest req = new LaneSearchRequest();
    Map<String, Object> binds = new Map<String, Object>();
    System.assertEquals(
      null,
      LaneQueries.stateLaneConditions(
        req,
        place('Montreal', ' ', 'CA', null),
        toronto(),
        'rtms__Load__r.',
        binds
      ),
      'blank origin province'
    );
    System.assertEquals(
      null,
      LaneQueries.stateLaneConditions(
        req,
        montreal(),
        place('Toronto', null, 'CA', null),
        'rtms__Load__r.',
        binds
      ),
      'blank destination province'
    );
    System.assertEquals(
      null,
      LaneQueries.stateLaneConditions(
        req,
        place('Paris', 'IF', 'FR', null),
        toronto(),
        'rtms__Load__r.',
        binds
      ),
      'a country outside CA, US and MX'
    );
    System.assertEquals(
      null,
      LaneQueries.stateLaneConditions(
        req,
        montreal(),
        place('Toronto', 'ON', null, null),
        'rtms__Load__r.',
        binds
      ),
      'no country'
    );
    System.assertEquals(
      null,
      LaneQueries.stateLaneConditions(req, null, toronto(), '', binds),
      'no place'
    );
    System.assert(binds.isEmpty(), 'nothing is bound without a state lane');
    System.assertEquals(
      new Map<String, String>{
        'CA' => 'Canada',
        'US' => 'United States',
        'MX' => 'Mexico'
      },
      LaneQueries.COUNTRY_NAMES
    );
  }

  @IsTest
  static void quoteCountSoqlGroupsDistinctLoadsByVendorWithTheRemovalsAndTheCap() {
    LaneSearchExclusions.excludedContactIdsOverride = new Set<String>{
      'an excluded contact'
    };
    // An Account Id that exists nowhere: the statement only binds it.
    Id intercompanyCarrier = Id.valueOf(
      Account.SObjectType.getDescribe().getKeyPrefix() + '000000000000'
    );
    IntercompanyCarriers.idsOverride = new Set<Id>{ intercompanyCarrier };
    List<String> onLane = new List<String>{
      'rtms__Load__r.rtms__City_Lane__c LIKE :oCity'
    };
    Map<String, Object> binds = new Map<String, Object>{
      'oCity' => new List<String>{ 'Montreal, QC:%' }
    };

    String quoted = LaneQueries.quoteCountSoql(onLane, 1095, false, binds);
    String moved = LaneQueries.quoteCountSoql(onLane, 365, true, binds);

    System.assertEquals(
      'SELECT rtms__Vendor__c, rtms__Vendor__r.Name vname, rtms__Vendor__r.Black_List__c bl, ' +
        'COUNT_DISTINCT(rtms__Load__c) loads, MAX(CreatedDate) lastSeen FROM rtms__CarrierQuote__c ' +
        'WHERE rtms__Load__r.rtms__City_Lane__c LIKE :oCity AND CreatedDate = LAST_N_DAYS:1095 ' +
        'AND Contact_ID__c NOT IN :excluded AND (NOT Customer_Name__c LIKE :marketTest) AND rtms__Vendor__c != null AND rtms__Vendor__c NOT IN :intercompany ' +
        'GROUP BY rtms__Vendor__c, rtms__Vendor__r.Name, rtms__Vendor__r.Black_List__c ' +
        'ORDER BY COUNT_DISTINCT(rtms__Load__c) DESC LIMIT 51',
      quoted
    );
    System.assertEquals(
      'SELECT rtms__Vendor__c, rtms__Vendor__r.Name vname, rtms__Vendor__r.Black_List__c bl, ' +
        'COUNT_DISTINCT(rtms__Load__c) loads, MAX(CreatedDate) lastSeen FROM rtms__CarrierQuote__c ' +
        'WHERE rtms__Load__r.rtms__City_Lane__c LIKE :oCity AND CreatedDate = LAST_N_DAYS:365 ' +
        'AND Contact_ID__c NOT IN :excluded AND (NOT Customer_Name__c LIKE :marketTest) AND rtms__Vendor__c != null AND rtms__Vendor__c NOT IN :intercompany ' +
        'AND rtms__Accepted__c = true ' +
        'GROUP BY rtms__Vendor__c, rtms__Vendor__r.Name, rtms__Vendor__r.Black_List__c ' +
        'ORDER BY COUNT_DISTINCT(rtms__Load__c) DESC LIMIT 51',
      moved
    );
    System.assertEquals(
      1,
      onLane.size(),
      'the lane conditions are copied, so both counts share them'
    );
    System.assertEquals(
      new Set<String>{ 'oCity', 'excluded', 'marketTest', 'intercompany' },
      binds.keySet()
    );
    System.assertEquals(
      LaneSearchExclusions.excludedContactIdSet(),
      binds.get('excluded')
    );
    System.assertEquals(IntercompanyCarriers.ids(), binds.get('intercompany'));
    System.assertEquals('%Market Test%', binds.get('marketTest'));
    System.assert(
      ((Set<Id>) binds.get('intercompany')).contains(intercompanyCarrier),
      'the intercompany list is bound as it is'
    );
    System.assertEquals(50, LaneQueries.GROUP_LIMIT);
    System.assert(
      !quoted.contains('Total') && !quoted.contains('Cost'),
      'names only'
    );
  }

  @IsTest
  static void planSoqlReadsTheLegsOfCustomerLoadsOnTheLaneWithoutAmountsUnlessAsked() {
    List<String> customerOnLane = new List<String>{
      'rtms__Load__r.rtms__City_Lane__c LIKE :oCity',
      NOT_CANCELLED
    };
    String withoutAmounts = LaneQueries.planSoql(
      customerOnLane,
      1095,
      500,
      false
    );
    String withAmounts = LaneQueries.planSoql(customerOnLane, 365, 1000, true);
    System.assertEquals(
      'SELECT Id, (SELECT rtms__Type__c, rtms__Number__c, rtms__Load__c, rtms__Load__r.CreatedDate, ' +
        'rtms__Load__r.rtms__Carrier__c, rtms__Load__r.rtms__Carrier__r.Name, ' +
        'rtms__Load__r.rtms__Carrier__r.Black_List__c, rtms__Load__r.rtms__Load_Status__c ' +
        'FROM rtms__Freight_Plan_Loads__r ORDER BY rtms__Number__c) FROM rtms__FreightPlan__c ' +
        'WHERE Id IN (SELECT rtms__Freight_Plan__c FROM rtms__FreightPlanLoad__c ' +
        'WHERE rtms__Type__c = \'Customer\' AND rtms__Load__r.rtms__City_Lane__c LIKE :oCity ' +
        'AND rtms__Load__r.rtms__Load_Status__c != \'Cancelled\' ' +
        'AND rtms__Load__r.CreatedDate = LAST_N_DAYS:1095) LIMIT 500',
      withoutAmounts
    );
    System.assert(
      !withoutAmounts.contains('Total') && !withoutAmounts.contains('Cost'),
      'Carriers to ask never selects an amount (R106)'
    );
    System.assertEquals(
      'SELECT Id, (SELECT rtms__Type__c, rtms__Number__c, rtms__Load__c, rtms__Load__r.CreatedDate, ' +
        'rtms__Load__r.rtms__Carrier__c, rtms__Load__r.rtms__Carrier__r.Name, ' +
        'rtms__Load__r.rtms__Carrier__r.Black_List__c, rtms__Load__r.rtms__Load_Status__c, ' +
        'rtms__Load__r.rtms__City_Lane__c, rtms__Load__r.rtms__Carrier_Quote_Total__c, ' +
        'rtms__Load__r.rtms__Last_Stop__r.rtms__Location2__r.Name ' +
        'FROM rtms__Freight_Plan_Loads__r ORDER BY rtms__Number__c) FROM rtms__FreightPlan__c ' +
        'WHERE Id IN (SELECT rtms__Freight_Plan__c FROM rtms__FreightPlanLoad__c ' +
        'WHERE rtms__Type__c = \'Customer\' AND rtms__Load__r.rtms__City_Lane__c LIKE :oCity ' +
        'AND rtms__Load__r.rtms__Load_Status__c != \'Cancelled\' ' +
        'AND rtms__Load__r.CreatedDate = LAST_N_DAYS:365) LIMIT 1000',
      withAmounts
    );
    System.assertEquals(
      2,
      customerOnLane.size(),
      'the customer conditions are copied'
    );
  }

  /**
   * Tests see none of the org's quotes or plans, so each statement returns nothing: running them
   * proves the dynamic SOQL and its binds compile, the binds inside the plan read's semi-join
   * included, whichever way Task 1 proved freight plans reach the tests.
   */
  @IsTest
  static void everyStatementRunsWithItsBinds() {
    LaneSearchExclusions.excludedContactIdsOverride = new Set<String>();
    IntercompanyCarriers.idsOverride = new Set<Id>();
    // The real plan query, not Task 1's in-memory rows (this test builds no plan fixture).
    FreightPlanReader.rowsOverride = null;
    Map<String, Object> laneBinds = new Map<String, Object>();
    List<String> onLane = LaneQueries.laneConditions(
      filtered(),
      montreal(),
      toronto(),
      'rtms__Load__r.',
      laneBinds
    );
    Map<String, Object> lanePlanBinds = laneBinds.clone();
    Map<String, Object> stateBinds = new Map<String, Object>();
    List<String> onStateLane = LaneQueries.stateLaneConditions(
      filtered(),
      montreal(),
      toronto(),
      'rtms__Load__r.',
      stateBinds
    );
    Map<String, Object> statePlanBinds = stateBinds.clone();
    Test.startTest();
    List<AggregateResult> quoted = Database.queryWithBinds(
      LaneQueries.quoteCountSoql(onLane, 1095, false, laneBinds),
      laneBinds,
      AccessLevel.SYSTEM_MODE
    );
    List<AggregateResult> movedOnStateLane = Database.queryWithBinds(
      LaneQueries.quoteCountSoql(onStateLane, 365, true, stateBinds),
      stateBinds,
      AccessLevel.SYSTEM_MODE
    );
    List<rtms__FreightPlan__c> lanePlans = FreightPlanReader.read(
      LaneQueries.planSoql(onLane, 1095, 500, false),
      lanePlanBinds
    );
    List<rtms__FreightPlan__c> statePlans = FreightPlanReader.read(
      LaneQueries.planSoql(onStateLane, 365, 1000, true),
      statePlanBinds
    );
    Test.stopTest();
    System.assertEquals(0, quoted.size(), 'the lane quote count ran');
    System.assertEquals(
      0,
      movedOnStateLane.size(),
      'the state-lane moved count ran'
    );
    System.assertEquals(0, lanePlans.size(), 'the lane plan read ran');
    System.assertEquals(
      0,
      statePlans.size(),
      'the state-lane plan read with amounts ran'
    );
  }
}
```

Create `force-app/main/default/classes/LaneQueriesTest.cls-meta.xml`:

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<ApexClass xmlns="http://soap.sforce.com/2006/04/metadata">
    <apiVersion>64.0</apiVersion>
    <status>Active</status>
</ApexClass>
```

The strings are the contract's: the lane conditions keep `LaneKeyMatcher`'s bind names (`oCity`, `dProv`, `oZip3`, ...) and `LaneLoadFilters`' conditions exactly as `LaneSearchFilters` wrote them before Task 2, and `planSoql` puts the customer conditions inside the semi-join after `rtms__Type__c = 'Customer'` and before the window. The quote count, the plan read without amounts, the plan read with the state lane and both stop countries, and the state-lane quote count were run read-only in PostProduc on 2026-09-15 with literal values in place of the binds (51 groups for QC:ON, 286 and 390 plans), so `everyStatementRunsWithItsBinds` only has to prove the binds.

- [ ] **Step 3: Deploy the test alone and watch it fail to compile**

Run: `sf project deploy start -o sandbox --source-dir force-app/main/default/classes/LaneQueriesTest.cls -l NoTestRun --async --json | python3 -c "import json,sys; s=sys.stdin.read(); print(json.loads(s[s.index('{'):])['result']['id'])"`

Expected: a deploy id (`0Af…`). Poll, repeating the command while it prints `InProgress`, `Pending` or a wait-timeout name:

Run: `sf project deploy report -o sandbox --job-id <id> -w 2 --json | python3 -c "import json,sys; s=sys.stdin.read(); j=json.loads(s[s.index('{'):]); r=j.get('result') or {}; cf=(r.get('details') or {}).get('componentFailures') or []; cf=cf if isinstance(cf,list) else [cf]; print(r.get('status') or j.get('name'), [(d.get('fullName'), d.get('problem')) for d in cf][:3])"`

Expected: `Failed` with a problem naming `LaneQueries` (`Invalid type: LaneQueries` or `Variable does not exist: LaneQueries`). A problem naming `LaneKeyMatcher`, `LaneLoadFilters`, `IntercompanyCarriers` or `FreightPlanReader` means an earlier task is not deployed: stop and report.

- [ ] **Step 4: Write `LaneQueries`**

Create `force-app/main/default/classes/LaneQueries.cls`:

```apex
/**
 * The statements Carriers to ask runs (phase 8, spec sections 3 and 8), and from Task 8 the ones
 * Split-lane options runs: the lane conditions on a load (each end through LaneKeyMatcher, the way
 * the first search matched it, a radius end on its place's city key, R83), the state-lane
 * conditions with both stop countries (R102), the grouped carrier quote count and the freight-plan
 * read with its carrier legs (R104). Pure: no query, no DML - strings and binds only, like
 * LaneSearchQueryBuilder. Only the request's place keys, precisions, postal prefixes and mode,
 * equipment and hazmat filters reach a condition; its lookback, currency, accepted and source
 * filters are ignored on purpose (R101), and quote counts leave out Market Test quotes as every
 * lane search does (phase 7, R110). loadPath is 'rtms__Load__r.' on
 * rtms__CarrierQuote__c and rtms__FreightPlanLoad__c rows and '' on rtms__Load__c rows.
 */
public with sharing class LaneQueries {
  /** Pricing_Place__c.Country__c codes and the names stop accounts hold in ShippingCountry. */
  public static final Map<String, String> COUNTRY_NAMES = new Map<String, String>{
    'CA' => 'Canada',
    'US' => 'United States',
    'MX' => 'Mexico'
  };
  /** Carriers per grouped count; the statement asks for one more, so a cut list can be told apart. */
  public static final Integer GROUP_LIMIT = 50;

  private static final String NOT_CANCELLED = 'rtms__Load_Status__c != \'Cancelled\'';
  private static final String QUOTE_COUNT_SELECT =
    'SELECT rtms__Vendor__c, rtms__Vendor__r.Name vname, rtms__Vendor__r.Black_List__c bl, ' +
    'COUNT_DISTINCT(rtms__Load__c) loads, MAX(CreatedDate) lastSeen FROM rtms__CarrierQuote__c WHERE ';
  private static final String QUOTE_COUNT_GROUP =
    ' GROUP BY rtms__Vendor__c, rtms__Vendor__r.Name, rtms__Vendor__r.Black_List__c' +
    ' ORDER BY COUNT_DISTINCT(rtms__Load__c) DESC LIMIT ';
  // Names only (R106): no amount field unless withAmounts, which Carriers to ask never passes.
  private static final String LEG_FIELDS =
    'rtms__Type__c, rtms__Number__c, rtms__Load__c, rtms__Load__r.CreatedDate, ' +
    'rtms__Load__r.rtms__Carrier__c, rtms__Load__r.rtms__Carrier__r.Name, ' +
    'rtms__Load__r.rtms__Carrier__r.Black_List__c, rtms__Load__r.rtms__Load_Status__c';
  private static final String AMOUNT_FIELDS =
    ', rtms__Load__r.rtms__City_Lane__c, rtms__Load__r.rtms__Carrier_Quote_Total__c, ' +
    'rtms__Load__r.rtms__Last_Stop__r.rtms__Location2__r.Name';

  /** The deeper steps never run a radius (R83): a radius end is matched on its place's city key. */
  public static LaneSearchRequest.Precision deepPrecision(
    LaneSearchRequest.Precision p
  ) {
    return p == LaneSearchRequest.Precision.RADIUS
      ? LaneSearchRequest.Precision.CITY
      : p;
  }

  /**
   * The lane's conditions on the load at loadPath: the origin end (binds prefixed 'o'), the
   * destination end ('d'), the mode, equipment and hazmat filters, and a load that is not cancelled.
   * An end with no place and no explicit postal prefix adds no condition.
   */
  public static List<String> laneConditions(
    LaneSearchRequest req,
    Pricing_Place__c origin,
    Pricing_Place__c destination,
    String loadPath,
    Map<String, Object> binds
  ) {
    List<String> conditions = new List<String>();
    addIfAny(
      conditions,
      LaneKeyMatcher.condition(
        loadPath,
        true,
        'o',
        deepPrecision(req.originPrecision),
        origin,
        req.originZip3,
        binds
      )
    );
    addIfAny(
      conditions,
      LaneKeyMatcher.condition(
        loadPath,
        false,
        'd',
        deepPrecision(req.destinationPrecision),
        destination,
        req.destinationZip3,
        binds
      )
    );
    LaneLoadFilters.add(req, loadPath, conditions, binds);
    conditions.add(loadPath + NOT_CANCELLED);
    return conditions;
  }

  /**
   * The state or province lane of the two places (stage 2): the load's rtms__State_Lane__c is
   * "<origin Province__c>:<destination Province__c>", its first stop account is in the origin's
   * country and its last stop account in the destination's (Revenova reuses two-letter state codes
   * across countries, and a blank stop country does not match), then the load filters and not
   * cancelled. null, with nothing bound, when a place has a blank Province__c or a Country__c
   * outside COUNTRY_NAMES.
   */
  public static List<String> stateLaneConditions(
    LaneSearchRequest req,
    Pricing_Place__c origin,
    Pricing_Place__c destination,
    String loadPath,
    Map<String, Object> binds
  ) {
    String originCountry = countryName(origin);
    String destinationCountry = countryName(destination);
    if (
      String.isBlank(origin?.Province__c) ||
      String.isBlank(destination?.Province__c) ||
      originCountry == null ||
      destinationCountry == null
    ) {
      return null;
    }
    binds.put('stateLane', origin.Province__c + ':' + destination.Province__c);
    binds.put('oCountry', originCountry);
    binds.put('dCountry', destinationCountry);
    List<String> conditions = new List<String>{
      loadPath + 'rtms__State_Lane__c = :stateLane',
      loadPath +
      'rtms__First_Stop__r.rtms__Location2__r.ShippingCountry = :oCountry',
      loadPath +
      'rtms__Last_Stop__r.rtms__Location2__r.ShippingCountry = :dCountry'
    };
    LaneLoadFilters.add(req, loadPath, conditions, binds);
    conditions.add(loadPath + NOT_CANCELLED);
    return conditions;
  }

  /**
   * Carrier quotes on the lane grouped by vendor, with the vendor's name and blacklist flag, the
   * distinct loads quoted (or moved, when movedOnly adds rtms__Accepted__c = true) and the latest
   * quote date, most loads first, GROUP_LIMIT + 1 groups at most. Adds the window, the excluded
   * contacts (quotes only, R89), the Market Test exclusion every lane search carries (phase 7, R110)
   * and the intercompany carriers (D6); binds 'excluded', 'marketTest' and 'intercompany'. onLane is
   * copied, so both counts can share it.
   */
  public static String quoteCountSoql(
    List<String> onLane,
    Integer days,
    Boolean movedOnly,
    Map<String, Object> binds
  ) {
    List<String> conditions = new List<String>(onLane);
    conditions.add('CreatedDate = LAST_N_DAYS:' + String.valueOf(days)); // the caller's constant, never user text
    binds.put('excluded', LaneSearchExclusions.excludedContactIdSet());
    conditions.add('Contact_ID__c NOT IN :excluded');
    binds.put('marketTest', '%Market Test%');
    conditions.add('(NOT Customer_Name__c LIKE :marketTest)');
    conditions.add('rtms__Vendor__c != null');
    binds.put('intercompany', IntercompanyCarriers.ids());
    conditions.add('rtms__Vendor__c NOT IN :intercompany');
    if (movedOnly == true) {
      conditions.add('rtms__Accepted__c = true');
    }
    return QUOTE_COUNT_SELECT +
      String.join(conditions, ' AND ') +
      QUOTE_COUNT_GROUP +
      String.valueOf(GROUP_LIMIT + 1);
  }

  /**
   * Freight plans whose customer load matches customerConditions (built with loadPath
   * 'rtms__Load__r.') and was created in the last `days` days, each with every junction row in
   * rtms__Number__c order - the customer row and the carrier legs - and the leg load's carrier,
   * blacklist flag and status. withAmounts adds the leg's city lane, CAD carrier total and last stop
   * account name (split history only). One query: SOQL refuses a semi-join from
   * rtms__FreightPlanLoad__c to itself (R104). customerConditions is copied.
   */
  public static String planSoql(
    List<String> customerConditions,
    Integer days,
    Integer planLimit,
    Boolean withAmounts
  ) {
    List<String> conditions = new List<String>{
      'rtms__Type__c = \'Customer\''
    };
    conditions.addAll(customerConditions);
    conditions.add(
      'rtms__Load__r.CreatedDate = LAST_N_DAYS:' + String.valueOf(days)
    );
    return 'SELECT Id, (SELECT ' +
      LEG_FIELDS +
      (withAmounts == true ? AMOUNT_FIELDS : '') +
      ' FROM rtms__Freight_Plan_Loads__r ORDER BY rtms__Number__c)' +
      ' FROM rtms__FreightPlan__c WHERE Id IN (SELECT rtms__Freight_Plan__c FROM rtms__FreightPlanLoad__c WHERE ' +
      String.join(conditions, ' AND ') +
      ') LIMIT ' +
      String.valueOf(planLimit);
  }

  private static void addIfAny(List<String> conditions, String condition) {
    if (condition != null) {
      conditions.add(condition);
    }
  }

  private static String countryName(Pricing_Place__c place) {
    return place == null ? null : COUNTRY_NAMES.get(place.Country__c);
  }
}
```

Create `force-app/main/default/classes/LaneQueries.cls-meta.xml` with the same content as the test's meta file (apiVersion 64.0, status Active).

`quoteCountSoql` and `planSoql` copy the list they are given, because `CarrierLeadService` passes the same lane conditions to both counts and to the plan read. `countryName` maps with `COUNTRY_NAMES.get(place.Country__c)`; `Map.get(null)` is a safe miss.

- [ ] **Step 5: Write the failing `CarrierLeadServiceTest`**

Create `force-app/main/default/classes/CarrierLeadServiceTest.cls`:

```apex
/**
 * Carriers to ask, stage 1 (phase 8, Task 5). Every freight plan goes through SplitTestData.plan,
 * so these tests hold whichever way Task 1 proved plans reach a test (inserted, or built in memory
 * for FreightPlanReader). PricingTestDataFactory's load automation is not bulkified (its class doc:
 * three createLoad() calls in one context passed 100 queries), so each test creates at most one load
 * before Test.startTest() - the one whose quotes or date Test.setCreatedDate moves, which works only
 * there - and at most two inside. Every test that expects a carrier to be left out keeps another
 * carrier on the same lane, so stage 1 is never empty and a later stage cannot change the answer.
 */
@IsTest
private class CarrierLeadServiceTest {
  private static final String LIVE = 'Delivered';
  private static final String CANCELLED = 'Cancelled';

  private class Fx {
    PricingTestDataFactory.Graph g;
    Account yard;
  }

  /** A carrier with its own profile, quote contact and carrier service: Revenova keeps a quote's vendor equal to its service's carrier. */
  private class Quoter {
    Account carrier;
    Contact contact;
    rtms__CarrierService__c service;
  }

  private static Fx fx() {
    Fx f = new Fx();
    f.g = PricingTestDataFactory.createGraph();
    // Legs end at a yard off the lane, as real legs do, so no quote the automation might give a leg
    // can reach the lane's quote counts (Task 1 asserts the automation gives legs none).
    f.yard = PricingTestDataFactory.createLocation(
      'Kingston Yard',
      'Kingston',
      'Ontario',
      'Canada',
      'K7K 1A1',
      44.2312,
      -76.486
    );
    places();
    return f;
  }

  /** Montreal and Toronto, the graph's lane ("Montreal, QC:Toronto, ON"), with no removal set. */
  private static void places() {
    RfpTestDataFactory.createPlace(
      'Montreal',
      'QC',
      'CA',
      45.5019,
      -73.5674,
      'H1A'
    );
    RfpTestDataFactory.createPlace(
      'Toronto',
      'ON',
      'CA',
      43.6532,
      -79.3832,
      'A1A'
    );
    LaneSearchExclusions.excludedContactIdsOverride = new Set<String>();
    IntercompanyCarriers.idsOverride = new Set<Id>();
    SplitTestData.resetPlans();
  }

  private static LaneSearchRequest montrealToToronto() {
    LaneSearchRequest req = new LaneSearchRequest();
    req.originKey = 'montreal|qc|ca';
    req.destinationKey = 'toronto|on|ca';
    return req;
  }

  private static rtms__Load__c laneLoad(Fx f) {
    return PricingTestDataFactory.createLoad(
      f.g,
      f.g.originLocation,
      f.g.destinationLocation
    );
  }

  private static rtms__Load__c leg(Fx f, Account carrier, String status) {
    return SplitTestData.legLoad(
      f.g,
      f.g.originLocation,
      f.yard,
      carrier,
      1000,
      status
    );
  }

  private static Quoter quoter(Fx f, Account carrier) {
    Quoter q = new Quoter();
    q.carrier = carrier;
    rtms__TransportationProfile__c profile = new rtms__TransportationProfile__c(
      Name = carrier.Name + ' Profile',
      RecordTypeId = Schema.SObjectType.rtms__TransportationProfile__c
        .getRecordTypeInfosByDeveloperName()
        .get('Carrier')
        .getRecordTypeId(),
      rtms__Company_Risk__c = 'Acceptable',
      rtms__Carrier_Remit_To__c = carrier.Id
    );
    insert profile;
    q.contact = new Contact(
      FirstName = 'Quote',
      LastName = carrier.Name,
      AccountId = carrier.Id,
      Email = 'quotes@example.invalid'
    );
    insert q.contact;
    q.service = new rtms__CarrierService__c(
      Name = carrier.Name + ' Service',
      rtms__Carrier__c = carrier.Id,
      rtms__Mode__c = f.g.mode.Id,
      rtms__Transportation_Profile__c = profile.Id,
      rtms__Quote_Contact__c = q.contact.Id,
      rtms__Minimum_Weight__c = 0,
      rtms__Maximum_Weight__c = 100000
    );
    insert q.service;
    return q;
  }

  /** An uninserted CAD quote on the load, by the quoter or, when it is null, by the graph's carrier. */
  private static rtms__CarrierQuote__c quote(
    Fx f,
    rtms__Load__c load,
    Quoter quotedBy,
    Boolean accepted
  ) {
    rtms__CarrierQuote__c q = PricingTestDataFactory.buildQuote(
      f.g,
      load,
      1000
    );
    if (quotedBy != null) {
      q.rtms__Carrier_Service__c = quotedBy.service.Id;
      q.rtms__Vendor__c = quotedBy.carrier.Id;
      q.rtms__Quote_Contact__c = quotedBy.contact.Id;
    }
    q.rtms__Accepted__c = accepted;
    return q;
  }

  private static CarrierLeadResult.Lead leadOf(
    CarrierLeadResult r,
    Id carrierId
  ) {
    for (CarrierLeadResult.Lead entry : r.leads) {
      if (entry.carrierId == carrierId) {
        return entry;
      }
    }
    return null;
  }

  private static CarrierLeadResult.Lead newLead(
    String name,
    Integer moved,
    Integer quoted,
    Date lastSeen
  ) {
    CarrierLeadResult.Lead entry = new CarrierLeadResult.Lead();
    entry.name = name;
    entry.loadsMoved = moved;
    entry.loadsQuoted = quoted;
    entry.lastSeen = lastSeen;
    return entry;
  }

  private static List<String> names(List<CarrierLeadResult.Lead> leads) {
    List<String> out = new List<String>();
    for (CarrierLeadResult.Lead entry : leads) {
      out.add(entry.name);
    }
    return out;
  }

  @IsTest
  static void quotesCountDistinctLoadsQuotedAndMovedPerCarrier() {
    Fx f = fx();
    Quoter black = quoter(f, SplitTestData.carrier('Black Freight', true));
    rtms__Load__c firstLoad = laneLoad(f);
    rtms__CarrierQuote__c acceptedQuote = quote(f, firstLoad, null, true);
    rtms__CarrierQuote__c declinedSameLoad = quote(f, firstLoad, null, false);
    rtms__CarrierQuote__c blackQuote = quote(f, firstLoad, black, false);
    insert new List<rtms__CarrierQuote__c>{
      acceptedQuote,
      declinedSameLoad,
      blackQuote
    };
    Datetime fortyDaysAgo = Datetime.now().addDays(-40);
    Test.setCreatedDate(acceptedQuote.Id, Datetime.now().addDays(-20));
    Test.setCreatedDate(declinedSameLoad.Id, Datetime.now().addDays(-5));
    Test.setCreatedDate(blackQuote.Id, fortyDaysAgo);
    Test.startTest();
    rtms__Load__c secondLoad = laneLoad(f);
    insert quote(f, secondLoad, null, false);
    CarrierLeadResult r = CarrierLeadService.find(montrealToToronto());
    Test.stopTest();

    System.assertEquals(CarrierLeadResult.SAME_LANE, r.stage);
    System.assertEquals(false, r.truncated);
    System.assertEquals(
      2,
      r.leads.size(),
      'the graph carrier and Black Freight'
    );
    CarrierLeadResult.Lead graphCarrier = r.leads[0];
    System.assertEquals(
      f.g.vendor.Id,
      graphCarrier.carrierId,
      'a load moved ranks first'
    );
    System.assertEquals('Test Carrier', graphCarrier.name);
    System.assertEquals(1, graphCarrier.loadsMoved, 'its accepted quote');
    System.assertEquals(
      2,
      graphCarrier.loadsQuoted,
      'three quotes on two loads count two loads'
    );
    System.assertEquals(
      Date.today(),
      graphCarrier.lastSeen,
      'its newest quote, made today on the second load'
    );
    System.assertEquals(
      new List<String>{ CarrierLeadResult.SOURCE_QUOTE },
      graphCarrier.sources
    );
    System.assertEquals(false, graphCarrier.blacklisted);
    System.assertEquals(
      true,
      graphCarrier.canOpen,
      'the running user reads the carrier account'
    );
    CarrierLeadResult.Lead blackCarrier = r.leads[1];
    System.assertEquals(black.carrier.Id, blackCarrier.carrierId);
    System.assertEquals('Black Freight', blackCarrier.name);
    System.assertEquals(0, blackCarrier.loadsMoved, 'its quote was declined');
    System.assertEquals(1, blackCarrier.loadsQuoted);
    System.assertEquals(fortyDaysAgo.date(), blackCarrier.lastSeen);
    System.assertEquals(
      true,
      blackCarrier.blacklisted,
      'Account.Black_List__c through rtms__Vendor__r (D5)'
    );
    System.assertEquals(true, blackCarrier.canOpen);
  }

  @IsTest
  static void splitLegCarriersCountFromTheirPlanAndMergeWithTheirQuotes() {
    Fx f = fx();
    Quoter alpha = quoter(f, SplitTestData.carrier('Alpha Freight', false));
    Account bravo = SplitTestData.carrier('Bravo Freight', true);
    rtms__Load__c customer = laneLoad(f);
    rtms__CarrierQuote__c alphaQuote = quote(f, customer, alpha, false);
    insert alphaQuote;
    Datetime tenDaysAgo = Datetime.now().addDays(-10);
    Test.setCreatedDate(customer.Id, tenDaysAgo);
    Test.setCreatedDate(alphaQuote.Id, Datetime.now().addDays(-60));
    Test.startTest();
    SplitTestData.plan(
      customer,
      new List<rtms__Load__c>{
        leg(f, alpha.carrier, LIVE),
        leg(f, bravo, LIVE)
      }
    );
    CarrierLeadResult r = CarrierLeadService.find(montrealToToronto());
    Test.stopTest();

    System.assertEquals(CarrierLeadResult.SAME_LANE, r.stage);
    System.assertEquals(2, r.leads.size(), 'the two leg carriers');
    CarrierLeadResult.Lead merged = r.leads[0];
    System.assertEquals(
      alpha.carrier.Id,
      merged.carrierId,
      'a leg and a quote rank above a leg alone'
    );
    System.assertEquals('Alpha Freight', merged.name);
    System.assertEquals(
      1,
      merged.loadsMoved,
      'its leg; its own quote was declined'
    );
    System.assertEquals(1, merged.loadsQuoted);
    System.assertEquals(
      tenDaysAgo.date(),
      merged.lastSeen,
      'the customer load date is later than its quote'
    );
    System.assertEquals(
      new List<String>{
        CarrierLeadResult.SOURCE_QUOTE,
        CarrierLeadResult.SOURCE_SPLIT_LEG
      },
      merged.sources
    );
    System.assertEquals(false, merged.blacklisted);
    CarrierLeadResult.Lead legOnly = r.leads[1];
    System.assertEquals(bravo.Id, legOnly.carrierId);
    System.assertEquals('Bravo Freight', legOnly.name);
    System.assertEquals(1, legOnly.loadsMoved);
    System.assertEquals(0, legOnly.loadsQuoted);
    System.assertEquals(
      tenDaysAgo.date(),
      legOnly.lastSeen,
      'a leg is dated by its customer load (R84)'
    );
    System.assertEquals(
      new List<String>{ CarrierLeadResult.SOURCE_SPLIT_LEG },
      legOnly.sources
    );
    System.assertEquals(
      true,
      legOnly.blacklisted,
      'Account.Black_List__c through the leg load carrier'
    );
    System.assertEquals(true, legOnly.canOpen);
  }

  @IsTest
  static void intercompanyCarriersAndTheExcludedContactAreLeftOut() {
    Fx f = fx();
    Quoter intercompanyQuotes = quoter(
      f,
      SplitTestData.carrier('Intercompany Quotes', false)
    );
    Account intercompanyLegs = SplitTestData.carrier(
      'Intercompany Legs',
      false
    );
    rtms__Load__c customer = laneLoad(f);
    insert new List<rtms__CarrierQuote__c>{
      quote(f, customer, intercompanyQuotes, false),
      quote(f, customer, null, true)
    };
    Test.startTest();
    SplitTestData.plan(
      customer,
      new List<rtms__Load__c>{
        leg(f, f.g.vendor, LIVE),
        leg(f, intercompanyLegs, LIVE)
      }
    );
    IntercompanyCarriers.idsOverride = new Set<Id>{
      intercompanyQuotes.carrier.Id,
      intercompanyLegs.Id
    };
    LaneSearchExclusions.excludedContactIdsOverride = new Set<String>{
      String.valueOf(f.g.quoteContact.Id).left(15)
    };
    CarrierLeadResult r = CarrierLeadService.find(montrealToToronto());
    Test.stopTest();

    System.assertEquals(
      null,
      leadOf(r, intercompanyQuotes.carrier.Id),
      'an intercompany vendor is left out of the quote counts (D6)'
    );
    System.assertEquals(
      null,
      leadOf(r, intercompanyLegs.Id),
      'an intercompany leg carrier is left out'
    );
    System.assertEquals(1, r.leads.size(), 'only the graph carrier is left');
    CarrierLeadResult.Lead kept = r.leads[0];
    System.assertEquals(f.g.vendor.Id, kept.carrierId);
    System.assertEquals(
      0,
      kept.loadsQuoted,
      'its accepted quote came from the excluded contact'
    );
    System.assertEquals(
      1,
      kept.loadsMoved,
      'its leg still counts: the contact setting applies to quotes only (R89)'
    );
    System.assertEquals(
      new List<String>{ CarrierLeadResult.SOURCE_SPLIT_LEG },
      kept.sources
    );
  }

  @IsTest
  static void cancelledLoadsAreLeftOutOfQuotesAndLegs() {
    Fx f = fx();
    Quoter onCancelled = quoter(
      f,
      SplitTestData.carrier('Cancelled Quotes', false)
    );
    Account cancelledLegCarrier = SplitTestData.carrier(
      'Cancelled Legs',
      false
    );
    // On the lane, so its quote meets every quote-count condition but the status; it is also the
    // plan's cancelled leg.
    rtms__Load__c cancelledLoad = SplitTestData.legLoad(
      f.g,
      f.g.originLocation,
      f.g.destinationLocation,
      cancelledLegCarrier,
      1000,
      CANCELLED
    );
    insert quote(f, cancelledLoad, onCancelled, false);
    Test.startTest();
    rtms__Load__c customer = laneLoad(f);
    SplitTestData.plan(
      customer,
      new List<rtms__Load__c>{ cancelledLoad, leg(f, f.g.vendor, LIVE) }
    );
    CarrierLeadResult r = CarrierLeadService.find(montrealToToronto());
    Test.stopTest();

    System.assertEquals(
      null,
      leadOf(r, onCancelled.carrier.Id),
      'a quote on a cancelled load does not count'
    );
    System.assertEquals(
      null,
      leadOf(r, cancelledLegCarrier.Id),
      'a cancelled leg does not count'
    );
    System.assertEquals(1, r.leads.size(), 'the live leg carrier');
    System.assertEquals(f.g.vendor.Id, r.leads[0].carrierId);
  }

  @IsTest
  static void quotesOlderThanThreeYearsAreLeftOut() {
    Fx f = fx();
    Quoter stale = quoter(f, SplitTestData.carrier('Stale Freight', false));
    rtms__Load__c load = laneLoad(f);
    rtms__CarrierQuote__c tooOld = quote(f, load, stale, true);
    rtms__CarrierQuote__c inWindow = quote(f, load, null, false);
    insert new List<rtms__CarrierQuote__c>{ tooOld, inWindow };
    Datetime thousandDaysAgo = Datetime.now().addDays(-1000);
    Test.setCreatedDate(tooOld.Id, Datetime.now().addDays(-1100));
    Test.setCreatedDate(inWindow.Id, thousandDaysAgo);
    Test.startTest();
    CarrierLeadResult r = CarrierLeadService.find(montrealToToronto());
    Test.stopTest();

    System.assertEquals(
      null,
      leadOf(r, stale.carrier.Id),
      'a quote from 1,100 days ago is outside the 3 years'
    );
    System.assertEquals(1, r.leads.size());
    System.assertEquals(f.g.vendor.Id, r.leads[0].carrierId);
    System.assertEquals(thousandDaysAgo.date(), r.leads[0].lastSeen);
  }

  @IsTest
  static void modeEquipmentAndHazmatApplyButCurrencyLookbackAcceptedAndSourceDoNot() {
    Fx f = fx();
    rtms__Load__c load = laneLoad(f); // Truckload, Dry Van 53' (Van), not hazmat
    rtms__CarrierQuote__c acceptedQuote = quote(f, load, null, true); // CAD
    insert acceptedQuote;
    Test.setCreatedDate(acceptedQuote.Id, Datetime.now().addDays(-30));
    LaneSearchRequest ignored = montrealToToronto();
    ignored.currencyIsoCode = 'USD';
    ignored.lookbackDays = 1;
    ignored.acceptedFilter = LaneSearchRequest.Accepted.DECLINED;
    ignored.sourceFilter = LaneSearchRequest.RowSource.BIDS;
    LaneSearchRequest matching = montrealToToronto();
    matching.modes = new List<String>{ 'Truckload' };
    matching.equipmentCategories = new List<String>{ 'Van' };
    LaneSearchRequest otherMode = montrealToToronto();
    otherMode.modes = new List<String>{ 'LTL' };
    LaneSearchRequest otherEquipment = montrealToToronto();
    otherEquipment.equipmentTypes = new List<String>{ 'Reefer 53\'' };
    LaneSearchRequest hazmatOnly = montrealToToronto();
    hazmatOnly.hazmatOnly = true;
    Test.startTest();
    CarrierLeadResult rIgnored = CarrierLeadService.find(ignored);
    CarrierLeadResult rMatching = CarrierLeadService.find(matching);
    CarrierLeadResult rOtherMode = CarrierLeadService.find(otherMode);
    CarrierLeadResult rOtherEquipment = CarrierLeadService.find(otherEquipment);
    CarrierLeadResult rHazmat = CarrierLeadService.find(hazmatOnly);
    Test.stopTest();

    System.assertEquals(
      1,
      rIgnored.leads.size(),
      'a CAD accepted quote from 30 days ago still counts for a USD, 1-day, declined-only, bids-only request (R101)'
    );
    System.assertEquals(1, rIgnored.leads[0].loadsMoved);
    System.assertEquals(1, rIgnored.leads[0].loadsQuoted);
    System.assertEquals(
      1,
      rMatching.leads.size(),
      'the load matches the mode and equipment'
    );
    System.assertEquals(0, rOtherMode.leads.size(), 'mode filter applies');
    System.assertEquals(CarrierLeadResult.NONE, rOtherMode.stage);
    System.assertEquals(
      0,
      rOtherEquipment.leads.size(),
      'equipment filter applies'
    );
    System.assertEquals(0, rHazmat.leads.size(), 'hazmat filter applies');
  }

  @IsTest
  static void aBlankKeyOrAMissingPlaceGivesNoneAfterOnlyThePlacesRead() {
    places();
    LaneSearchRequest blank = montrealToToronto();
    blank.destinationKey = '  ';
    LaneSearchRequest missing = montrealToToronto();
    missing.destinationKey = 'nowhere|zz|ca';
    Test.startTest();
    Integer atStart = Limits.getQueries();
    CarrierLeadResult rBlank = CarrierLeadService.find(blank);
    Integer afterBlank = Limits.getQueries();
    CarrierLeadResult rMissing = CarrierLeadService.find(missing);
    Integer afterMissing = Limits.getQueries();
    Test.stopTest();

    System.assertEquals(0, afterBlank - atStart, 'a blank key reads nothing');
    System.assertEquals(
      1,
      afterMissing - afterBlank,
      'a missing place stops after the places read'
    );
    for (
      CarrierLeadResult r : new List<CarrierLeadResult>{ rBlank, rMissing }
    ) {
      System.assertEquals(CarrierLeadResult.NONE, r.stage);
      System.assertEquals(0, r.leads.size());
      System.assertEquals(false, r.truncated);
    }
  }

  @IsTest
  static void theQueryRowCheckStopsBeforeTheFirstCountAndMarksTheListIncomplete() {
    places();
    CarrierLeadService.rowReserve = Limits.getLimitQueryRows() + 1;
    Test.startTest();
    Integer atStart = Limits.getQueries();
    CarrierLeadResult r = CarrierLeadService.find(montrealToToronto());
    Integer used = Limits.getQueries() - atStart;
    Test.stopTest();

    System.assertEquals(1, used, 'only the places read ran');
    System.assertEquals(true, r.truncated, 'The list may be incomplete');
    System.assertEquals(CarrierLeadResult.NONE, r.stage);
    System.assertEquals(0, r.leads.size());
  }

  @IsTest
  static void leadsRankByLoadsMovedThenLoadsQuotedThenLastSeenThenName() {
    Date yesterday = Date.today().addDays(-1);
    List<CarrierLeadResult.Lead> leads = new List<CarrierLeadResult.Lead>{
      newLead('Aaron', 1, 3, null),
      newLead('Bravo', 1, 3, yesterday),
      newLead('able', 1, 3, yesterday),
      newLead('Alpha', 1, 5, Date.today().addDays(-200)),
      newLead('Zulu', 2, 0, Date.today().addDays(-400))
    };
    System.assertEquals(
      new List<String>{ 'Zulu', 'Alpha', 'able', 'Bravo', 'Aaron' },
      names(CarrierLeadService.ranked(leads, true)),
      'loads moved, then loads quoted, then the newest last seen with none last, then the name ignoring case'
    );
    System.assertEquals(
      new List<String>{ 'Zulu', 'able', 'Bravo', 'Alpha', 'Aaron' },
      names(CarrierLeadService.ranked(leads, false)),
      'without loads quoted (stage 2): loads moved, then last seen, then the name'
    );
    System.assertEquals(
      'Aaron',
      leads[0].name,
      'ranked returns a new list and leaves its input alone'
    );
  }

  @IsTest
  static void aResultSerializesNamesAndCountsButNeverAnAmount() {
    CarrierLeadResult.Lead entry = new CarrierLeadResult.Lead();
    entry.carrierId = UserInfo.getUserId();
    entry.name = 'Alpha Freight';
    entry.loadsMoved = 3;
    entry.loadsQuoted = 4;
    entry.lastSeen = Date.today();
    entry.sources.add(CarrierLeadResult.SOURCE_QUOTE);
    entry.blacklisted = true;
    entry.canOpen = true;
    CarrierLeadResult result = new CarrierLeadResult();
    result.leads.add(entry);
    result.stage = CarrierLeadResult.STATE_LANE;
    result.stateLaneLabel = 'QC to ON';
    result.truncated = true;

    Map<String, Object> top = (Map<String, Object>) JSON.deserializeUntyped(
      JSON.serialize(result)
    );
    System.assertEquals(
      new Set<String>{ 'leads', 'stage', 'stateLaneLabel', 'truncated' },
      top.keySet(),
      'the result has no amount field (R106)'
    );
    Map<String, Object> firstLead = (Map<String, Object>) ((List<Object>) top.get(
      'leads'
    ))[0];
    System.assertEquals(
      new Set<String>{
        'carrierId',
        'name',
        'loadsMoved',
        'loadsQuoted',
        'lastSeen',
        'sources',
        'blacklisted',
        'canOpen'
      },
      firstLead.keySet(),
      'a lead has no amount field (R106)'
    );
    System.assertEquals(CarrierLeadResult.NONE, new CarrierLeadResult().stage);
  }
}
```

Create `force-app/main/default/classes/CarrierLeadServiceTest.cls-meta.xml` with the same content as the other meta files.

Why the fixtures look like this:

- **A quote by another carrier gets its own profile, contact and carrier service** (`quoter`). In 2,000 recent PostProduc quotes `rtms__Vendor__c` always equals `rtms__Carrier_Service__r.rtms__Carrier__c` and the managed trigger `rtms.CarrierQuoteUpsert` runs on every quote, so a quote that pointed its vendor away from its service could be rewritten. Each load has at most one accepted quote.
- **Loads**: the graph plus one load before `Test.startTest()` (the one whose quotes or date `Test.setCreatedDate` moves), and at most two loads, the plan and the calls inside. PricingTestDataFactory's class doc records that three `createLoad` calls in one context passed 100 queries.
- **Every test that expects a carrier to be left out keeps another carrier** on the same lane, so stage 1 is not empty and Task 6's stage 2 cannot change these answers. The mode, equipment and hazmat cases expect `None` because the one load fails the filter, which stage 2 applies too.
- **Plan filters are asserted on the SOQL string** (`LaneQueriesTest.planSoql...`): Task 1's branch B returns the plan rows whatever the semi-join says. Here, a cancelled leg and an intercompany leg carrier are left out by the leg loop, which runs on both branches.

- [ ] **Step 6: Deploy `LaneQueries` with both tests and watch the service test fail to compile**

Run: `sf project deploy start -o sandbox --source-dir force-app/main/default/classes/LaneQueries.cls --source-dir force-app/main/default/classes/LaneQueriesTest.cls --source-dir force-app/main/default/classes/CarrierLeadServiceTest.cls -l NoTestRun --async --json | python3 -c "import json,sys; s=sys.stdin.read(); print(json.loads(s[s.index('{'):])['result']['id'])"`

Expected: a deploy id. Poll with the report command from Step 3 (same Python filter, the new job id).

Expected: `Failed` with a problem naming `CarrierLeadResult` or `CarrierLeadService` in `CarrierLeadServiceTest` (`Invalid type`), and no problem in `LaneQueries` or `LaneQueriesTest`. A problem there (for example `Unexpected token`) is a typo in Step 2 or Step 4: fix it and repeat this step.

- [ ] **Step 7: Write `CarrierLeadResult` and `CarrierLeadService`**

Create `force-app/main/default/classes/CarrierLeadResult.cls`:

```apex
/**
 * What Carriers to ask returns (phase 8, spec section 3): the carriers that know a lane, by name,
 * with the lane's loads each moved and quoted, the day it was last seen there, where it was seen
 * (a carrier quote, a split leg), its blacklist flag and whether the user may open its account;
 * the stage that found them (the same lane, the state or province lane, or none); the state lane's
 * label for the stage 2 wording; and whether a cap or the query-row check cut the list. Names only:
 * no field here holds an amount (R106), and CarrierLeadServiceTest fails when a serialized key
 * appears that the spec does not list.
 */
public class CarrierLeadResult {
  public static final String SAME_LANE = 'Same lane';
  public static final String STATE_LANE = 'State lane';
  public static final String NONE = 'None';
  public static final String SOURCE_QUOTE = 'Quote';
  public static final String SOURCE_SPLIT_LEG = 'Split leg';

  /** One carrier. loadsMoved counts its accepted quote loads plus its split leg loads (R82). */
  public class Lead {
    @AuraEnabled
    public Id carrierId;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public Integer loadsMoved = 0;
    @AuraEnabled
    public Integer loadsQuoted = 0;
    @AuraEnabled
    public Date lastSeen;
    @AuraEnabled
    public List<String> sources = new List<String>();
    @AuraEnabled
    public Boolean blacklisted = false;
    @AuraEnabled
    public Boolean canOpen = false;
  }

  @AuraEnabled
  public List<Lead> leads = new List<Lead>();
  @AuraEnabled
  public String stage = NONE;
  @AuraEnabled
  public String stateLaneLabel;
  @AuraEnabled
  public Boolean truncated = false;
}
```

Create `force-app/main/default/classes/CarrierLeadService.cls`:

```apex
/**
 * Carriers to ask (phase 8, spec section 3): names the carriers that know a lane when the first
 * search found no carrier rate, never an amount (D4, R106). Stage 1, the same lane over the last
 * 3 years: two grouped carrier quote counts by rtms__Vendor__c - distinct loads quoted, and distinct
 * loads moved with rtms__Accepted__c = true, because SOQL has no conditional count (R107) - and the
 * carrier legs of freight plans whose customer load is on the lane (read through
 * FreightPlanReader), merged per carrier (sources Quote, Split leg) and ranked by loads moved, loads
 * quoted, last seen, then name (R82). Only the request's place keys, precisions, postal prefixes
 * and mode, equipment and hazmat filters apply (R101); LaneQueries builds every statement.
 * Intercompany carriers are left out by the quote counts and by the leg loop (D6); the excluded
 * contact applies to quotes only (R89). Before each read after the places, a query-row check stops
 * early and marks the list incomplete. One user-mode Account read decides each link.
 */
// Runs without sharing on purpose: carrier quotes and loads inherit Private load sharing, and pricing names every team's carriers, like LaneSearchService. Access is gated by the Lane Benchmark and RFP Tool permission sets; the Account link check is the one user-mode read.
public without sharing class CarrierLeadService {
  private static final String LOAD_PATH = 'rtms__Load__r.';
  private static final Integer SAME_LANE_DAYS = 1095;
  private static final Integer PLAN_LIMIT = 500;

  /** Query rows kept free before each read; a test raises it past the limit to force the early stop. */
  @TestVisible
  private static Integer rowReserve = 5000;

  public static CarrierLeadResult find(LaneSearchRequest req) {
    req.applyDefaults();
    CarrierLeadResult result = new CarrierLeadResult();
    Map<String, Pricing_Place__c> places = loadPlaces(req);
    Pricing_Place__c origin = places.get(req.originKey);
    Pricing_Place__c destination = places.get(req.destinationKey);
    if (origin == null || destination == null) {
      return result;
    }
    Tally sameLane = new Tally();
    Map<String, Object> binds = new Map<String, Object>();
    List<String> onLane = LaneQueries.laneConditions(
      req,
      origin,
      destination,
      LOAD_PATH,
      binds
    );
    // The plan read gets the lane binds only: quoteCountSoql adds 'excluded' and 'intercompany'.
    Map<String, Object> planBinds = binds.clone();
    countQuotes(onLane, SAME_LANE_DAYS, binds, sameLane, result);
    readLegs(onLane, SAME_LANE_DAYS, planBinds, sameLane, result);
    if (!sameLane.isEmpty()) {
      result.stage = CarrierLeadResult.SAME_LANE;
      result.leads = ranked(sameLane.leads(), true);
    }
    markReadable(result);
    return result;
  }

  /**
   * Stage 1 order (byQuoted true): loads moved, loads quoted, last seen (newest first, none last),
   * then the name ignoring case; with byQuoted false loads quoted is skipped (stage 2, R82). Returns
   * a new list.
   */
  @TestVisible
  private static List<CarrierLeadResult.Lead> ranked(
    List<CarrierLeadResult.Lead> leads,
    Boolean byQuoted
  ) {
    List<CarrierLeadResult.Lead> sorted = new List<CarrierLeadResult.Lead>(
      leads
    );
    sorted.sort(new LeadOrder(byQuoted));
    return sorted;
  }

  /** Both places by Key__c; empty, with no query, when either key is blank. */
  @SuppressWarnings(
    'PMD.ApexCRUDViolation'
  ) // system mode by design (see class comment)
  private static Map<String, Pricing_Place__c> loadPlaces(
    LaneSearchRequest req
  ) {
    Map<String, Pricing_Place__c> byKey = new Map<String, Pricing_Place__c>();
    if (String.isBlank(req.originKey) || String.isBlank(req.destinationKey)) {
      return byKey;
    }
    Set<String> keys = new Set<String>{ req.originKey, req.destinationKey };
    for (Pricing_Place__c p : [
      SELECT
        Key__c,
        City__c,
        Province__c,
        Country__c,
        Postal_Prefix__c,
        Spellings__c,
        Geolocation__Latitude__s,
        Geolocation__Longitude__s
      FROM Pricing_Place__c
      WHERE Key__c IN :keys
    ]) {
      byKey.put(p.Key__c, p);
    }
    return byKey;
  }

  /** The loads quoted count, then the loads moved count; each is skipped once the query-row check stops. */
  @SuppressWarnings(
    'PMD.ApexCRUDViolation'
  ) // system mode by design (see class comment); Database.queryWithBinds also counts as CRUD for PMD
  private static void countQuotes(
    List<String> onLane,
    Integer days,
    Map<String, Object> binds,
    Tally tally,
    CarrierLeadResult result
  ) {
    if (stopEarly(result)) {
      return;
    }
    String quotedSoql = LaneQueries.quoteCountSoql(onLane, days, false, binds);
    List<AggregateResult> quoted = Database.queryWithBinds(
      quotedSoql,
      binds,
      AccessLevel.SYSTEM_MODE
    );
    tally.addQuoteGroups(capped(quoted, result), false);
    if (stopEarly(result)) {
      return;
    }
    String movedSoql = LaneQueries.quoteCountSoql(onLane, days, true, binds);
    List<AggregateResult> moved = Database.queryWithBinds(
      movedSoql,
      binds,
      AccessLevel.SYSTEM_MODE
    );
    tally.addQuoteGroups(capped(moved, result), true);
  }

  /** The carrier legs of freight plans whose customer load matches onLane, as plain rows with no amount. */
  private static void readLegs(
    List<String> onLane,
    Integer days,
    Map<String, Object> binds,
    Tally tally,
    CarrierLeadResult result
  ) {
    if (stopEarly(result)) {
      return;
    }
    List<rtms__FreightPlan__c> plans = FreightPlanReader.read(
      LaneQueries.planSoql(onLane, days, PLAN_LIMIT, false),
      binds
    );
    if (plans.size() >= PLAN_LIMIT) {
      result.truncated = true;
    }
    tally.addPlans(plans, IntercompanyCarriers.ids());
  }

  /** A count that came back with GROUP_LIMIT + 1 groups was cut: the extra, smallest group is dropped. */
  private static List<AggregateResult> capped(
    List<AggregateResult> groups,
    CarrierLeadResult result
  ) {
    if (groups.size() > LaneQueries.GROUP_LIMIT) {
      groups.remove(groups.size() - 1);
      result.truncated = true;
    }
    return groups;
  }

  /** true, with the list marked incomplete, once no more than rowReserve query rows are left. */
  private static Boolean stopEarly(CarrierLeadResult result) {
    if (Limits.getQueryRows() > Limits.getLimitQueryRows() - rowReserve) {
      result.truncated = true;
      return true;
    }
    return false;
  }

  /** canOpen from one user-mode read: a carrier account the user cannot read shows its name without a link. */
  private static void markReadable(CarrierLeadResult result) {
    if (result.leads.isEmpty() || stopEarly(result)) {
      return;
    }
    Set<Id> carrierIds = new Set<Id>();
    for (CarrierLeadResult.Lead entry : result.leads) {
      carrierIds.add(entry.carrierId);
    }
    Map<Id, Account> readable;
    try {
      readable = new Map<Id, Account>(
        [SELECT Id FROM Account WHERE Id IN :carrierIds WITH USER_MODE]
      );
    } catch (Exception e) {
      // A caller with no read on Account at all gets an exception from the platform: no link.
      return;
    }
    for (CarrierLeadResult.Lead entry : result.leads) {
      entry.canOpen = readable.containsKey(entry.carrierId);
    }
  }

  /**
   * One stage's carriers while its reads come in. Quote groups set loads quoted and keep loads
   * moved apart; plan legs collect each carrier's distinct leg loads; leads() adds the two into
   * loads moved and lists the sources in the order Quote, Split leg. An inner class, so its branches
   * stay out of CarrierLeadService's PMD class complexity total.
   */
  private class Tally {
    private final Map<Id, CarrierLeadResult.Lead> byCarrier = new Map<Id, CarrierLeadResult.Lead>();
    private final Set<Id> quoteCarriers = new Set<Id>();
    private final Map<Id, Integer> movedQuoteLoads = new Map<Id, Integer>();
    private final Map<Id, Set<Id>> legLoads = new Map<Id, Set<Id>>();

    private Boolean isEmpty() {
      return byCarrier.isEmpty();
    }

    private void addQuoteGroups(List<AggregateResult> groups, Boolean moved) {
      for (AggregateResult row : groups) {
        CarrierLeadResult.Lead entry = entryFor(
          (Id) row.get('rtms__Vendor__c'),
          (String) row.get('vname'),
          (Boolean) row.get('bl')
        );
        quoteCarriers.add(entry.carrierId);
        Integer loads = (Integer) row.get('loads');
        if (moved) {
          movedQuoteLoads.put(entry.carrierId, loads);
        } else {
          entry.loadsQuoted = loads;
        }
        seen(entry, ((Datetime) row.get('lastSeen'))?.date());
      }
    }

    /**
     * Per plan, the customer row gives the date and each carrier leg whose load has a carrier off
     * the intercompany list and is not cancelled counts for that carrier. The child rows are read
     * with a for loop: reading a child list of more than 200 rows any other way throws.
     */
    private void addPlans(
      List<rtms__FreightPlan__c> plans,
      Set<Id> intercompany
    ) {
      for (rtms__FreightPlan__c plan : plans) {
        Date customerDate = null;
        List<rtms__FreightPlanLoad__c> legs = new List<rtms__FreightPlanLoad__c>();
        for (rtms__FreightPlanLoad__c row : plan.rtms__Freight_Plan_Loads__r) {
          if (row.rtms__Type__c == 'Customer') {
            customerDate = row.rtms__Load__r?.CreatedDate?.date();
          } else if (countsAsLeg(row, intercompany)) {
            legs.add(row);
          }
        }
        for (rtms__FreightPlanLoad__c leg : legs) {
          addLeg(leg, customerDate);
        }
      }
    }

    private Boolean countsAsLeg(
      rtms__FreightPlanLoad__c row,
      Set<Id> intercompany
    ) {
      rtms__Load__c legLoad = row.rtms__Load__r;
      return row.rtms__Type__c == 'Carrier' &&
        legLoad?.rtms__Carrier__c != null &&
        !intercompany.contains(legLoad.rtms__Carrier__c) &&
        legLoad.rtms__Load_Status__c != 'Cancelled';
    }

    private void addLeg(rtms__FreightPlanLoad__c leg, Date customerDate) {
      rtms__Load__c legLoad = leg.rtms__Load__r;
      CarrierLeadResult.Lead entry = entryFor(
        legLoad.rtms__Carrier__c,
        legLoad.rtms__Carrier__r?.Name,
        legLoad.rtms__Carrier__r?.Black_List__c
      );
      if (!legLoads.containsKey(entry.carrierId)) {
        legLoads.put(entry.carrierId, new Set<Id>());
      }
      legLoads.get(entry.carrierId).add(leg.rtms__Load__c);
      seen(entry, customerDate);
    }

    private CarrierLeadResult.Lead entryFor(
      Id carrierId,
      String name,
      Boolean blacklisted
    ) {
      CarrierLeadResult.Lead entry = byCarrier.get(carrierId);
      if (entry == null) {
        entry = new CarrierLeadResult.Lead();
        entry.carrierId = carrierId;
        entry.name = name;
        byCarrier.put(carrierId, entry);
      }
      entry.blacklisted = entry.blacklisted || blacklisted == true;
      return entry;
    }

    private void seen(CarrierLeadResult.Lead entry, Date seenOn) {
      if (
        seenOn != null && (entry.lastSeen == null || seenOn > entry.lastSeen)
      ) {
        entry.lastSeen = seenOn;
      }
    }

    private List<CarrierLeadResult.Lead> leads() {
      for (CarrierLeadResult.Lead entry : byCarrier.values()) {
        Set<Id> legs = legLoads.get(entry.carrierId) ?? new Set<Id>();
        entry.loadsMoved =
          (movedQuoteLoads.get(entry.carrierId) ?? 0) + legs.size();
        entry.sources = new List<String>();
        if (quoteCarriers.contains(entry.carrierId)) {
          entry.sources.add(CarrierLeadResult.SOURCE_QUOTE);
        }
        if (!legs.isEmpty()) {
          entry.sources.add(CarrierLeadResult.SOURCE_SPLIT_LEG);
        }
      }
      return byCarrier.values();
    }
  }

  /** The order ranked() sorts by; an inner class for the same complexity reason as Tally. */
  private class LeadOrder implements Comparator<CarrierLeadResult.Lead> {
    private final Boolean byQuoted;

    private LeadOrder(Boolean byQuoted) {
      this.byQuoted = byQuoted;
    }

    public Integer compare(CarrierLeadResult.Lead a, CarrierLeadResult.Lead b) {
      Integer diff = b.loadsMoved - a.loadsMoved;
      if (diff == 0 && byQuoted) {
        diff = b.loadsQuoted - a.loadsQuoted;
      }
      if (diff == 0) {
        diff = newestFirst(a.lastSeen, b.lastSeen);
      }
      if (diff == 0) {
        diff = nameKey(a).compareTo(nameKey(b));
      }
      return diff;
    }

    private Integer newestFirst(Date a, Date b) {
      if (a == b) {
        return 0;
      }
      if (a == null) {
        return 1;
      }
      if (b == null) {
        return -1;
      }
      return a > b ? -1 : 1;
    }

    private String nameKey(CarrierLeadResult.Lead entry) {
      return entry.name == null ? '' : entry.name.toLowerCase();
    }
  }
}
```

Create `force-app/main/default/classes/CarrierLeadResult.cls-meta.xml` and `force-app/main/default/classes/CarrierLeadService.cls-meta.xml` with the same content as the test's meta file (apiVersion 64.0, status Active).

How `find` reads (stage 1, at most 5 queries): the places (none when a key is blank), the loads quoted count, the loads moved count, the plan read (`FreightPlanReader`, no query when Task 1's override is set), and the user-mode Account read (none when there is no lead). Before each read after the places, `stopEarly` compares `Limits.getQueryRows()` with the limit less `rowReserve`; once it stops, every later read is skipped and `truncated` is set. `Tally` and `LeadOrder` are inner classes so their branches stay out of the outer class's complexity total, which Task 6 grows with stage 2.

- [ ] **Step 8: Add the classes to the manifest**

In `manifest/package.xml`, inside the `<types>` block whose `<name>` is `ApexClass`, directly before `<name>ApexClass</name>` (after the members Tasks 1 to 4 added):

```xml
        <members>CarrierLeadResult</members>
        <members>LaneQueries</members>
        <members>LaneQueriesTest</members>
        <members>CarrierLeadService</members>
        <members>CarrierLeadServiceTest</members>
```

Run: `grep -c -E "<members>(CarrierLeadResult|LaneQueries|LaneQueriesTest|CarrierLeadService|CarrierLeadServiceTest)</members>" manifest/package.xml`

Expected: `5`.

- [ ] **Step 9: Prettier, PMD and the names-only check**

Run: `npx prettier --check force-app/main/default/classes/CarrierLeadResult.cls force-app/main/default/classes/LaneQueries.cls force-app/main/default/classes/LaneQueriesTest.cls force-app/main/default/classes/CarrierLeadService.cls force-app/main/default/classes/CarrierLeadServiceTest.cls`

Expected: `All matched files use Prettier code style!` (the code above was formatted with the repo's `.prettierrc`).

Run: `/private/tmp/pmd_install/pmd-bin-7.15.0/bin/pmd check --dir force-app --rulesets config/pmd-ruleset.xml --minimum-priority 3 --format text --fail-on-violation; echo "pmd exit $?"`

Expected: no violation lines, `pmd exit 0`. The only suppressions this task adds are `ApexCRUDViolation` on `loadPlaces` and `countQuotes`, both system mode by design (class comment). The user-mode Account read needs none.

Print the class complexity totals:

```bash
cat > /private/tmp/pmd_install/cyclo-classes.xml <<'XML'
<?xml version="1.0"?>
<ruleset name="cyclo" xmlns="http://pmd.sourceforge.net/ruleset/2.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="http://pmd.sourceforge.net/ruleset/2.0.0 https://pmd.sourceforge.io/ruleset_2_0_0.xsd">
  <description>class totals</description>
  <rule ref="category/apex/design.xml/CyclomaticComplexity">
    <properties><property name="classReportLevel" value="1"/><property name="methodReportLevel" value="99"/></properties>
  </rule>
</ruleset>
XML
/private/tmp/pmd_install/pmd-bin-7.15.0/bin/pmd check --dir force-app/main/default/classes/CarrierLeadService.cls --dir force-app/main/default/classes/LaneQueries.cls --rulesets /private/tmp/pmd_install/cyclo-classes.xml --format text --no-cache 2>/dev/null | grep -o "class '[A-Za-z]*' has a total cyclomatic complexity of [0-9]*"
```

Expected: `CarrierLeadService` 24, `Tally` 23, `LeadOrder` 13, `LaneQueries` 16. Record the `CarrierLeadService` figure for Task 6, which adds stage 2 to that class.

Run: `grep -nE "Total|Cost|Decimal|Amount" force-app/main/default/classes/CarrierLeadResult.cls force-app/main/default/classes/CarrierLeadService.cls; echo "exit $?"`

Expected: no line, `exit 1`. Neither the result nor the service names an amount (R106). `LaneQueries` holds the amount fields only behind `withAmounts`, which Carriers to ask never passes.

- [ ] **Step 10: Deploy the five classes and run both test classes**

Each deployed class reaches 75 % from these two test classes: `LaneQueriesTest` and `CarrierLeadServiceTest` cover `LaneQueries`, and `CarrierLeadServiceTest` covers `CarrierLeadService` and `CarrierLeadResult`.

Run: `sf project deploy start -o sandbox --source-dir force-app/main/default/classes/CarrierLeadResult.cls --source-dir force-app/main/default/classes/LaneQueries.cls --source-dir force-app/main/default/classes/LaneQueriesTest.cls --source-dir force-app/main/default/classes/CarrierLeadService.cls --source-dir force-app/main/default/classes/CarrierLeadServiceTest.cls -l RunSpecifiedTests -t LaneQueriesTest -t CarrierLeadServiceTest --async --json | python3 -c "import json,sys; s=sys.stdin.read(); print(json.loads(s[s.index('{'):])['result']['id'])"`

Expected: a deploy id. Poll, repeating while it prints `InProgress`, `Pending` or a wait-timeout name:

Run: `sf project deploy report -o sandbox --job-id <id> -w 2 --json | python3 -c "import json,sys; s=sys.stdin.read(); j=json.loads(s[s.index('{'):]); r=j.get('result') or {}; d=r.get('details') or {}; t=d.get('runTestResult') or {}; L=lambda v: v if isinstance(v,list) else ([v] if v else []); print(r.get('status') or j.get('name'), 'tests', r.get('numberTestsCompleted'), '/', r.get('numberTestsTotal'), 'failures', r.get('numberTestErrors')); [print(x.get('fullName'), '->', x.get('problem')) for x in L(d.get('componentFailures'))]; [print(x.get('name'), x.get('methodName'), '->', (x.get('message') or '')[:160]) for x in L(t.get('failures'))]; [print('coverage', x.get('name'), '->', x.get('message')) for x in L(t.get('codeCoverageWarnings'))]"`

Expected: `Succeeded tests 18 / 18 failures 0` (8 in `LaneQueriesTest`, 10 in `CarrierLeadServiceTest`) and no `coverage` line. If a test fails, fix the class, not the assertion, unless the assertion contradicts the spec. Known failure shapes:

- **`LaneQueriesTest.everyStatementRunsWithItsBinds` fails with a `QueryException`.** A bind inside the semi-join or a field path is refused. The message names the token. Stop and report it, because Tasks 6 and 8 use the same plan read.
- **`Too many SOQL queries: 101` in `splitLegCarriersCountFromTheirPlanAndMergeWithTheirQuotes`, `intercompanyCarriersAndTheExcludedContactAreLeftOut` or `cancelledLoadsAreLeftOutOfQuotesAndLegs`.** Two `SplitTestData.legLoad` calls plus a plan cost more than the fresh 100 queries inside `Test.startTest()`. Split that test in two. Give each half one plan with a single carrier leg (Carriers to ask does not need two legs) and move the assertions about the other leg into the new method. Do not move a `Test.setCreatedDate` fixture inside `Test.startTest()`.
- **`Too many SOQL queries: 101` before `Test.startTest()`** (stack through `quoter`, `laneLoad`, `fx` or the quote insert, in `quotesCountDistinctLoadsQuotedAndMovedPerCarrier`, `quotesOlderThanThreeYearsAreLeftOut` or another test): move the `quoter(...)` and `SplitTestData.carrier(...)` calls for carriers whose quotes need no `Test.setCreatedDate` inside `Test.startTest()`; if the test still fails, split it so the block before `Test.startTest()` holds one quoter at most. Never move a `Test.setCreatedDate` fixture inside `Test.startTest()`.
- **`FIELD_CUSTOM_VALIDATION_EXCEPTION` naming `Carrier_service_only_for_carriers` in `quoter`.** `SplitTestData.carrier` does not set the `Carrier` record type (Step 1). Stop and report: `SplitTestData` belongs to Task 1.
- **The quote insert on the cancelled load is refused in `cancelledLoadsAreLeftOutOfQuotesAndLegs`.** A managed trigger refuses a quote on a cancelled load. Delete that test's `onCancelled` quoter, the quote insert and its `leadOf(r, onCancelled.carrier.Id)` assertion, and keep the leg half. `LaneQueriesTest.laneConditionsMatchBothEndsAndKeepOnlyTheLoadFilters` still proves that the quote counts carry the not-cancelled condition.
- **A `lastSeen` assertion off by one day.** The run crossed midnight in the running user's time zone: run the deploy again.

- [ ] **Step 11: Commit**

```bash
git add force-app/main/default/classes/CarrierLeadResult.cls force-app/main/default/classes/CarrierLeadResult.cls-meta.xml force-app/main/default/classes/LaneQueries.cls force-app/main/default/classes/LaneQueries.cls-meta.xml force-app/main/default/classes/LaneQueriesTest.cls force-app/main/default/classes/LaneQueriesTest.cls-meta.xml force-app/main/default/classes/CarrierLeadService.cls force-app/main/default/classes/CarrierLeadService.cls-meta.xml force-app/main/default/classes/CarrierLeadServiceTest.cls force-app/main/default/classes/CarrierLeadServiceTest.cls-meta.xml manifest/package.xml
git commit -m "Add Carriers to ask stage 1: carrier quote counts and split legs on the same lane, names only"
```

Expected: lint-staged runs Prettier on the staged Apex (no change) and the commit lands on `phase-8/carriers-and-split-lanes`. `git status --short` still shows `.vscode/settings.json` and the `* 2.*` files unstaged.

#### Contract notes (Task 5)

1. **`find` calls `req.applyDefaults()`, not `validate()`.** `JSON.deserialize` leaves precisions and filter lists null, and `applyDefaults()` fills them. `validate()` would also check the lookback, the radius and the request currency, which Carriers to ask ignores (R101), and the first search has already validated the same request. An explicit postal prefix is not uppercased, which changes nothing because SOQL `LIKE` ignores case. Task 6 keeps the same call, and Task 8's split service uses it too. A ZIP3 end without a postal prefix still throws `LaneSearchException` from `LaneKeyMatcher`, which Task 6's controller maps.
2. **The places read is static SOQL, like `LaneSearchService.loadPlaces`.** It runs in system mode in a `without sharing` class, and the contract's `Database.queryWithBinds` rule applies to the dynamic statements. A blank key returns stage `None` before any query. A missing place returns `None` after the places read, where `LaneSearchService` throws `Unknown place key`. The Account link check is static `SELECT Id FROM Account WHERE Id IN :carrierIds WITH USER_MODE`.
3. **The plan read uses a clone of the lane binds.** `laneConditions` runs once, and the plan read gets a copy of its binds taken before `quoteCountSoql` adds `excluded` and `intercompany`. The contract builds the lane conditions a second time into `binds2`. The conditions are identical either way, and no unused bind reaches the plan query.
4. **`quoteCountSoql`'s first parameter is named `onLane`, not `laneConditions`**, so it does not share its name with the static method `laneConditions` in the same class. Types and order are the contract's. Both builders copy the list they are given; `LaneQueriesTest` asserts it.
5. **`rowReserve` is new** (`@TestVisible private static Integer rowReserve = 5000`). It lets `theQueryRowCheckStopsBeforeTheFirstCountAndMarksTheListIncomplete` force the early stop; in production the check is the contract's `Limits.getQueryRows() > Limits.getLimitQueryRows() - 5000`. The check also runs before the Account read, so a stopped search shows names without links.
6. **Ranking lives in `ranked(leads, byQuoted)` with an inner `LeadOrder implements Comparator<CarrierLeadResult.Lead>`.** Task 6 calls `ranked(..., false)` for stage 2. "Name asc" compares the names lowercased, so "able" comes before "Bravo".
7. **Sources are set in `Tally.leads()`**, from which reads saw the carrier (a quote group, then a counted leg), so the order is always Quote, Split leg. `loadsMoved` is accepted quote loads plus distinct leg loads, as the contract says; a leg load that also carries an accepted quote by the same carrier counts twice. A plan without a Customer row leaves its legs' `lastSeen` unchanged.
8. **Two truncation paths are not exercised by a test.** A count returning `GROUP_LIMIT + 1` groups (`capped`) and a plan read returning 500 plans would need 51 carriers or 500 plans, far beyond the test budget. Both are one-line branches, and the query-row stop is tested.
9. **Test fixtures differ from "fixture DML before `Test.startTest()`".** Each test creates at most one load before `Test.startTest()` (the one `Test.setCreatedDate` needs) and at most two loads, the plan and the calls inside. The reason is PricingTestDataFactory's documented 100-query budget. No callout is involved, so DML before the calls inside `Test.startTest()` is safe. Each test builds at most one plan of two legs and uses at most two loads with quotes.
10. **A quote by a carrier other than the graph's gets its own transportation profile, contact and carrier service** (`quoter`), and each load has at most one accepted quote. PostProduc data shows vendor = service carrier on 2,000 of 2,000 quotes under the managed `rtms.CarrierQuoteUpsert` trigger. `rtms__CarrierService__c` has the validation rule `Carrier_service_only_for_carriers` (`rtms__Carrier__r.RecordType.Name != 'Carrier'`), so `SplitTestData.carrier` must create a `Carrier` record type account (checked in Step 1).
11. **Reserved words.** `by` is reserved in Apex (Prettier's Apex parser refused `Quoter by`), so the helper parameter is `quotedBy`. The code also avoids locals that shadow a type, a constant or an enum value case-insensitively (`lead`, `order`, `accepted`, `cancelled` next to the test constant `CANCELLED`, `zip3` next to `Precision.ZIP3`, `first`), and always writes the inner class as `CarrierLeadResult.Lead`.
12. **`LaneQueriesTest.everyStatementRunsWithItsBinds` sets `FreightPlanReader.rowsOverride = null` directly** so the real plan query runs on either branch. It builds no plan fixture, so the rule that plans go only through `SplitTestData` still holds.
13. **SOQL verified read-only in PostProduc on 2026-09-15** (`soql/t5-*.json`):
    - The stage 1 moved count with mode, equipment OR, status, `LAST_N_DAYS:1095`, `Contact_ID__c NOT IN`, vendor `!= null` and `NOT IN`, and accepted, `LIMIT 51`.
    - The plan read without amounts with mode, equipment OR, hazmat, status and `LAST_N_DAYS:1095` inside the semi-join.
    - The plan read with the state lane and both stop countries inside the semi-join.
    - The state-lane grouped count with both countries and a `Zip3` LIKE (51 groups for QC:ON, so the cap is reached in real data).

    The rules on `rtms__Load__c` block only changes to `Completed` (and a cancel flag without a reason), so the tests use `Delivered` and `Cancelled`.

**Open issues**

- The query cost of two `SplitTestData.legLoad` calls plus a plan inside one `Test.startTest()` block is not measured. Task 1 measures a plan; Step 10 gives the split if a test passes 100 queries.
- Whether Revenova accepts a carrier quote inserted on an already cancelled load is not known; Step 10 gives the fallback.
- Binds inside the plan read's semi-join (`LIKE :oCity` with a list, `IN :modes`) are proven only at the Step 10 deploy (`everyStatementRunsWithItsBinds`); the read-only CLI checks used literals.
- `CarrierLeadResult.Lead` shares its simple name with the standard `Lead` object. It is always written qualified; the Step 6 and Step 10 compiles are the proof.


---

### Task 6: Carriers to ask stage 2 and controller

Stage 2 of Carriers to ask (the state or province lane over the last year, with each end's stop country, top 10 by loads moved then last seen), the cacheable `CarrierLeadController.findCarrierLeads` the two screens call, class access in both permission sets, and the phase 8 security tests. Spec §3 (Stage 2, Removals, Each carrier shows), §6 (`CarrierLeadController`), §8 (limits and security), rulings R81, R82, R91, R95, R97, R101, R102.

**Files:**

- Modify: `force-app/main/default/classes/CarrierLeadService.cls` (whole file, Step 5: `find` hands over to stage 2 when stage 1 has no carrier; new `@TestVisible` seams `stateLaneLeads` and `stateLane`; the per-carrier merge in the inner class `Tally` and the ranking in the inner class `LeadOrder` serve both stages)
- Modify: `force-app/main/default/classes/CarrierLeadServiceTest.cls` (Step 1: five stage 2 test methods and their helpers appended before the class's closing brace; Task 5's tests stay as they are)
- Create: `force-app/main/default/classes/CarrierLeadController.cls`, `force-app/main/default/classes/CarrierLeadController.cls-meta.xml`
- Create: `force-app/main/default/classes/CarrierLeadControllerTest.cls`, `force-app/main/default/classes/CarrierLeadControllerTest.cls-meta.xml`
- Create: `force-app/main/default/classes/CarrierSplitSecurityTest.cls`, `force-app/main/default/classes/CarrierSplitSecurityTest.cls-meta.xml`
- Modify: `force-app/main/default/permissionsets/Lane_Benchmark_User.permissionset-meta.xml` (classAccesses `CarrierLeadController`, first in the alphabetical classAccesses list)
- Modify: `force-app/main/default/permissionsets/RFP_Tool_User.permissionset-meta.xml` (classAccesses `CarrierLeadController`, right after `BenchmarkRateService`)
- Modify: `manifest/package.xml` (ApexClass members `CarrierLeadController`, `CarrierLeadControllerTest`, `CarrierSplitSecurityTest`, at the end of the ApexClass block after the members Task 5 added)

**Interfaces:**

- Consumes:
  - Task 5: `CarrierLeadResult` (`Lead` with `carrierId`, `name`, `loadsMoved`, `loadsQuoted`, `lastSeen`, `sources`, `blacklisted`, `canOpen`; `leads`, `stage`, `stateLaneLabel`, `truncated`; constants `SAME_LANE`, `STATE_LANE`, `NONE`, `SOURCE_QUOTE`, `SOURCE_SPLIT_LEG`).
  - Task 5: `LaneQueries.GROUP_LIMIT` (50), `LaneQueries.laneConditions(LaneSearchRequest req, Pricing_Place__c origin, Pricing_Place__c destination, String loadPath, Map<String, Object> binds)`, `LaneQueries.stateLaneConditions(LaneSearchRequest req, Pricing_Place__c origin, Pricing_Place__c destination, String loadPath, Map<String, Object> binds)` (binds `stateLane`, `oCountry`, `dCountry`; `null` for a blank `Province__c` or a `Country__c` outside `COUNTRY_NAMES`), `LaneQueries.quoteCountSoql(List<String> laneConditions, Integer days, Boolean movedOnly, Map<String, Object> binds)` (aliases `vname`, `bl`, `loads`, `lastSeen`; binds `excluded` and `intercompany`; does not change the list it is given), `LaneQueries.planSoql(List<String> customerConditions, Integer days, Integer planLimit, Boolean withAmounts)`.
  - Task 5: `CarrierLeadService.find(LaneSearchRequest req)` with stage 1 as the contract (A10) states it, and `CarrierLeadServiceTest` with its stage 1 tests.
  - Task 3: `IntercompanyCarriers.ids()` and `@TestVisible IntercompanyCarriers.idsOverride`.
  - Task 2: `LaneKeyMatcher.condition(...)`, which throws the `LaneSearchException` "Place … has no postal prefix; pass originZip3" for a ZIP3 end with no prefix (used by the controller test).
  - Task 1: `FreightPlanReader.read(String soql, Map<String, Object> binds)`, `SplitTestData.carrier(String name, Boolean blacklisted)`, `SplitTestData.legLoad(PricingTestDataFactory.Graph g, Account origin, Account destination, Account carrierAccount, Decimal cadTotal, String status)`, `SplitTestData.plan(rtms__Load__c customerLoad, List<rtms__Load__c> legLoads)`, `SplitTestData.resetPlans()`.
  - Existing: `LaneSearchRequest` (`applyDefaults()`, `Precision`), `LaneSearchException`, `LaneSearchExclusions.excludedContactIdsOverride`, `PricingTestDataFactory.createGraph/createLocation/createLoad/buildQuote`, `RfpTestDataFactory.createPlace/restrictedUser/shareAccount/hiddenCarrier/hiddenFrom/sharingInputs`.
- Produces:
  - `CarrierLeadService` (`public without sharing`):
    - `public static CarrierLeadResult find(LaneSearchRequest req)` — stage 1 unchanged; when stage 1 has no carrier left after the removals and did not stop at the row guard, returns `stateLaneLeads(...)`.
    - `@TestVisible private static CarrierLeadResult stateLaneLeads(LaneSearchRequest req, Pricing_Place__c origin, Pricing_Place__c destination, CarrierLeadResult result)` — stage 2 alone: 365 days, quote counts and plan read on `stateLane` conditions, ranked loads moved desc, last seen desc (null last), name asc, top 10 (`truncated` untouched by the cut), `stage` `State lane` and `stateLaneLabel` `'<origin Province__c> to <destination Province__c>'` when a carrier is left, else `stage` stays `None`.
    - `@TestVisible private static List<String> stateLane(LaneSearchRequest req, Pricing_Place__c origin, Pricing_Place__c destination, Map<String, Object> binds)` — `null` when both precisions are `PROVINCE` or a `Province__c` is blank; otherwise `LaneQueries.stateLaneConditions(req, origin, destination, 'rtms__Load__r.', binds)` (itself `null` for a country outside CA, US, MX).
    - `@TestVisible private static Integer rowReserve = 5000` — the query-row guard's reserve.
    - `@TestVisible private static List<CarrierLeadResult.Lead> ranked(List<CarrierLeadResult.Lead> leads, Boolean byQuoted)` — kept from Task 5 (its ranking test calls it); `byQuoted` false is the stage 2 order.
  - `CarrierLeadController` (`public with sharing`): `@AuraEnabled(cacheable=true) public static CarrierLeadResult findCarrierLeads(String requestJson, Integer attempt)`; `@TestVisible private static final String UNREADABLE_REQUEST`. Task 7's `c-carrier-leads` imports `@salesforce/apex/CarrierLeadController.findCarrierLeads`.
  - Class access to `CarrierLeadController` in `Lane_Benchmark_User` and `RFP_Tool_User`.
  - `CarrierSplitSecurityTest` with `bothPermissionSetsGrantThePhaseEightControllers` (`CarrierLeadController` only; Task 9 checks `SplitLaneController` in its own `bothPermissionSetsOpenTheSplitController`).

- [ ] **Step 0: Print the baseline**

Run: `git log --oneline -1 && grep -c "@IsTest" force-app/main/default/classes/CarrierLeadServiceTest.cls force-app/main/default/classes/LaneQueriesTest.cls && /private/tmp/pmd_install/pmd-bin-7.15.0/bin/pmd check --dir force-app --rulesets config/pmd-ruleset.xml --minimum-priority 3 --format text --fail-on-violation; echo "pmd exit $?"`

Expected: Task 5's commit on top; the `@IsTest` count of each Task 5 test class (test methods plus 1 for the class annotation: write both down, Step 7 expects them plus 5 + 3 + 3 new tests); `pmd exit 0`.

- [ ] **Step 1: Write the failing tests**

Append these stage 2 tests and their helpers to `force-app/main/default/classes/CarrierLeadServiceTest.cls`, directly before the class's final closing brace. Every helper name starts with `stateLane` (or is the inner class `StateLaneCarrier`) so it cannot clash with Task 5's helpers. Each carrier quotes through its own carrier service and quote contact, as in Task 5's tests: on every recent PostProduc quote `rtms__Vendor__c` is the service's carrier, and the service's validation rule `Carrier_service_only_for_carriers` needs a `Carrier` record-type account (read-only check 2026-09-15). The carriers of a test are inserted one list per object, not through `SplitTestData.carrier` calls, so the Account and Revenova automation runs once before `Test.startTest()`; the top 10 test must build everything there, because `Test.setCreatedDate` is refused after `Test.startTest()`. A second load is created inside `Test.startTest()`, as `PricingTestDataFactory`'s class comment requires.

```apex
  // ---- Task 6: stage 2, the state or province lane ----

  /** No excluded contact; the intercompany list is the test's (custom metadata cannot be inserted). */
  private static void stateLaneSettings(Set<Id> intercompany) {
    IntercompanyCarriers.idsOverride = intercompany;
    LaneSearchExclusions.excludedContactIdsOverride = new Set<String>();
  }

  /** A carrier the way Revenova quotes it: account, quote contact, transportation profile, service. */
  private class StateLaneCarrier {
    Account carrierAccount;
    Contact quoteContact;
    rtms__TransportationProfile__c carrierProfile;
    rtms__CarrierService__c carrierService;
  }

  /**
   * Carriers keyed by name, one insert per object, each built like createGraph builds the graph's
   * vendor. A quote's rtms__Vendor__c is its carrier service's carrier on every recent PostProduc
   * quote, so each carrier quotes through its own service and contact (as in Task 5's tests). One
   * list per object keeps the Account and Revenova automation to one pass before Test.startTest().
   */
  private static Map<String, StateLaneCarrier> stateLaneCarriers(
    PricingTestDataFactory.Graph g,
    List<String> names
  ) {
    Map<String, StateLaneCarrier> byName = new Map<String, StateLaneCarrier>();
    List<Account> accounts = new List<Account>();
    for (String carrierName : names) {
      StateLaneCarrier c = new StateLaneCarrier();
      c.carrierAccount = new Account(
        Name = carrierName,
        RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
          .get('Carrier')
          .getRecordTypeId(),
        rtms__TMS_Type__c = 'Carrier (Ground)',
        CurrencyIsoCode = 'CAD'
      );
      byName.put(carrierName, c);
      accounts.add(c.carrierAccount);
    }
    insert accounts;
    List<Contact> contacts = new List<Contact>();
    List<rtms__TransportationProfile__c> profiles = new List<rtms__TransportationProfile__c>();
    for (StateLaneCarrier c : byName.values()) {
      c.quoteContact = new Contact(
        FirstName = 'Quote',
        LastName = c.carrierAccount.Name,
        AccountId = c.carrierAccount.Id,
        Email = 'quote' + contacts.size() + '@example.invalid',
        Phone = '514-555-0100'
      );
      c.carrierProfile = new rtms__TransportationProfile__c(
        Name = c.carrierAccount.Name + ' Profile',
        RecordTypeId = Schema.SObjectType.rtms__TransportationProfile__c.getRecordTypeInfosByDeveloperName()
          .get('Carrier')
          .getRecordTypeId(),
        rtms__Company_Risk__c = 'Acceptable',
        rtms__Carrier_Remit_To__c = c.carrierAccount.Id
      );
      contacts.add(c.quoteContact);
      profiles.add(c.carrierProfile);
    }
    insert contacts;
    insert profiles;
    List<rtms__CarrierService__c> services = new List<rtms__CarrierService__c>();
    for (StateLaneCarrier c : byName.values()) {
      c.carrierService = new rtms__CarrierService__c(
        Name = c.carrierAccount.Name + ' Service',
        rtms__Carrier__c = c.carrierAccount.Id,
        rtms__Mode__c = g.mode.Id,
        rtms__Transportation_Profile__c = c.carrierProfile.Id,
        rtms__Quote_Contact__c = c.quoteContact.Id,
        rtms__Minimum_Weight__c = 0,
        rtms__Maximum_Weight__c = 100000
      );
      services.add(c.carrierService);
    }
    insert services;
    return byName;
  }

  /** A quote by the given carrier, through its own service and contact; uninserted. */
  private static rtms__CarrierQuote__c stateLaneQuote(
    PricingTestDataFactory.Graph g,
    rtms__Load__c load,
    StateLaneCarrier carrier,
    Boolean accepted
  ) {
    rtms__CarrierQuote__c q = PricingTestDataFactory.buildQuote(g, load, 1000);
    q.rtms__Carrier_Service__c = carrier.carrierService.Id;
    q.rtms__Vendor__c = carrier.carrierAccount.Id;
    q.rtms__Quote_Contact__c = carrier.quoteContact.Id;
    q.rtms__Accepted__c = accepted;
    return q;
  }

  /** City precision on both ends (the LaneSearchRequest defaults). */
  private static LaneSearchRequest stateLaneRequest(
    String originKey,
    String destinationKey
  ) {
    LaneSearchRequest r = new LaneSearchRequest();
    r.originKey = originKey;
    r.destinationKey = destinationKey;
    return r;
  }

  private static List<String> stateLaneNames(CarrierLeadResult r) {
    List<String> names = new List<String>();
    for (CarrierLeadResult.Lead entry : r.leads) {
      names.add(entry.name);
    }
    return names;
  }

  /**
   * R81: stage 2 runs only when stage 1 has no carrier left after the removals. Laval to Toronto has
   * one quote (Alpha); Montréal to Toronto is on the same state lane QC:ON but not on that city
   * lane (Beta). Once Alpha is intercompany, stage 1 is empty and stage 2 names Beta.
   */
  @IsTest
  static void stateLaneRunsOnlyWhenTheSameLaneHasNoCarrierLeft() {
    stateLaneSettings(new Set<Id>());
    PricingTestDataFactory.Graph g = PricingTestDataFactory.createGraph();
    Account lavalCo = PricingTestDataFactory.createLocation(
      'Laval Co',
      'Laval',
      'Quebec',
      'Canada',
      'H7P 1T2',
      45.6066,
      -73.7124
    );
    RfpTestDataFactory.createPlace(
      'Laval',
      'QC',
      'CA',
      45.6066,
      -73.7124,
      'H7P'
    );
    RfpTestDataFactory.createPlace(
      'Toronto',
      'ON',
      'CA',
      43.6532,
      -79.3832,
      'M5V'
    );
    Map<String, StateLaneCarrier> carriers = stateLaneCarriers(
      g,
      new List<String>{ 'Alpha Lane Carrier', 'Beta State Carrier' }
    );
    rtms__Load__c montrealToronto = PricingTestDataFactory.createLoad(
      g,
      g.originLocation,
      g.destinationLocation
    );
    insert stateLaneQuote(
      g,
      montrealToronto,
      carriers.get('Beta State Carrier'),
      true
    );
    Test.startTest();
    rtms__Load__c lavalToronto = PricingTestDataFactory.createLoad(
      g,
      lavalCo,
      g.destinationLocation
    );
    insert stateLaneQuote(
      g,
      lavalToronto,
      carriers.get('Alpha Lane Carrier'),
      false
    );
    CarrierLeadResult sameLane = CarrierLeadService.find(
      stateLaneRequest('laval|qc|ca', 'toronto|on|ca')
    );
    IntercompanyCarriers.idsOverride = new Set<Id>{
      carriers.get('Alpha Lane Carrier').carrierAccount.Id
    };
    CarrierLeadResult afterRemoval = CarrierLeadService.find(
      stateLaneRequest('laval|qc|ca', 'toronto|on|ca')
    );
    Test.stopTest();
    System.assertEquals(
      CarrierLeadResult.SAME_LANE,
      sameLane.stage,
      JSON.serialize(sameLane)
    );
    System.assertEquals(
      new List<String>{ 'Alpha Lane Carrier' },
      stateLaneNames(sameLane),
      'stage 2 never mixes with stage 1'
    );
    System.assertEquals(
      null,
      sameLane.stateLaneLabel,
      'no state lane label on stage 1'
    );
    System.assertEquals(
      CarrierLeadResult.STATE_LANE,
      afterRemoval.stage,
      'an intercompany carrier leaves stage 1 empty: ' +
      JSON.serialize(afterRemoval)
    );
    System.assertEquals(
      new List<String>{ 'Beta State Carrier' },
      stateLaneNames(afterRemoval),
      'the intercompany carrier is left out of stage 2 as well'
    );
    System.assertEquals(
      'QC to ON',
      afterRemoval.stateLaneLabel,
      'the stage 2 wording names the state lane'
    );
    System.assertEquals(1, afterRemoval.leads[0].loadsMoved, 'accepted');
    System.assertEquals(1, afterRemoval.leads[0].loadsQuoted, 'quoted');
    System.assertEquals(
      new List<String>{ CarrierLeadResult.SOURCE_QUOTE },
      afterRemoval.leads[0].sources,
      'a quote source only'
    );
  }

  /**
   * R82 and R97: stage 2 ranks by loads moved, then last seen, and shows its top 10. Carrier 12
   * moved the load 12 days ago; Carrier 01 to 11 only quoted it, 1 to 11 days ago.
   */
  @IsTest
  static void stateLaneKeepsTheTopTenByLoadsMovedThenLastSeen() {
    PricingTestDataFactory.Graph g = PricingTestDataFactory.createGraph();
    RfpTestDataFactory.createPlace(
      'Laval',
      'QC',
      'CA',
      45.6066,
      -73.7124,
      'H7P'
    );
    RfpTestDataFactory.createPlace(
      'Toronto',
      'ON',
      'CA',
      43.6532,
      -79.3832,
      'M5V'
    );
    stateLaneSettings(new Set<Id>());
    List<String> names = new List<String>();
    for (Integer i = 1; i <= 12; i++) {
      names.add('Carrier ' + String.valueOf(i).leftPad(2, '0'));
    }
    Map<String, StateLaneCarrier> carriers = stateLaneCarriers(g, names);
    rtms__Load__c montrealToronto = PricingTestDataFactory.createLoad(
      g,
      g.originLocation,
      g.destinationLocation
    );
    List<rtms__CarrierQuote__c> quotes = new List<rtms__CarrierQuote__c>();
    for (Integer i = 1; i <= 12; i++) {
      quotes.add(
        stateLaneQuote(g, montrealToronto, carriers.get(names[i - 1]), i == 12)
      );
    }
    insert quotes;
    for (Integer i = 1; i <= 12; i++) {
      Test.setCreatedDate(quotes[i - 1].Id, Datetime.now().addDays(-i));
    }
    Test.startTest();
    CarrierLeadResult r = CarrierLeadService.find(
      stateLaneRequest('laval|qc|ca', 'toronto|on|ca')
    );
    Test.stopTest();
    System.assertEquals(
      CarrierLeadResult.STATE_LANE,
      r.stage,
      JSON.serialize(r)
    );
    System.assertEquals('QC to ON', r.stateLaneLabel, 'the label');
    System.assertEquals(
      new List<String>{
        'Carrier 12',
        'Carrier 01',
        'Carrier 02',
        'Carrier 03',
        'Carrier 04',
        'Carrier 05',
        'Carrier 06',
        'Carrier 07',
        'Carrier 08',
        'Carrier 09'
      },
      stateLaneNames(r),
      'loads moved first, then the latest quote; Carrier 10 and 11 fall past the top 10'
    );
    System.assertEquals(
      false,
      r.truncated,
      'the top 10 cut does not mark the list incomplete'
    );
    System.assertEquals(1, r.leads[0].loadsMoved, 'Carrier 12 moved it');
    System.assertEquals(
      Datetime.now().addDays(-1).date(),
      r.leads[1].lastSeen,
      'Carrier 01 was last seen a day ago'
    );
  }

  /**
   * R102: NL is both Newfoundland and Labrador and Nuevo León, so both loads below carry the state
   * lane NL:QC. Only the load whose first stop account is in Canada counts for Corner Brook, NL, CA.
   * A stop account with a blank ShippingCountry fails the same equality, so its load never counts
   * (spec §3); no extra load is built for it, to keep the fixture budget.
   */
  @IsTest
  static void stateLaneCountsOnlyLoadsWhoseStopsAreInEachPlacesCountry() {
    stateLaneSettings(new Set<Id>());
    PricingTestDataFactory.Graph g = PricingTestDataFactory.createGraph();
    Account newfoundland = PricingTestDataFactory.createLocation(
      'Newfoundland Co',
      'St. John\'s',
      'Newfoundland and Labrador',
      'Canada',
      'A1B 3T2',
      47.5615,
      -52.7126
    );
    Account nuevoLeon = PricingTestDataFactory.createLocation(
      'Nuevo Leon Co',
      'Monterrey',
      'Nuevo León',
      'Mexico',
      '64000',
      25.6866,
      -100.3161
    );
    RfpTestDataFactory.createPlace(
      'Corner Brook',
      'NL',
      'CA',
      48.949,
      -57.9503,
      'A2H'
    );
    RfpTestDataFactory.createPlace(
      'Montréal',
      'QC',
      'CA',
      45.5019,
      -73.5674,
      'H1A'
    );
    Map<String, StateLaneCarrier> carriers = stateLaneCarriers(
      g,
      new List<String>{ 'Canada Carrier', 'Mexico Carrier' }
    );
    rtms__Load__c fromCanada = PricingTestDataFactory.createLoad(
      g,
      newfoundland,
      g.originLocation
    );
    insert stateLaneQuote(
      g,
      fromCanada,
      carriers.get('Canada Carrier'),
      true
    );
    Test.startTest();
    rtms__Load__c fromMexico = PricingTestDataFactory.createLoad(
      g,
      nuevoLeon,
      g.originLocation
    );
    insert stateLaneQuote(
      g,
      fromMexico,
      carriers.get('Mexico Carrier'),
      true
    );
    CarrierLeadResult r = CarrierLeadService.find(
      stateLaneRequest('corner brook|nl|ca', 'montreal|qc|ca')
    );
    String mexicanStateLane = [
      SELECT rtms__State_Lane__c
      FROM rtms__Load__c
      WHERE Id = :fromMexico.Id
    ]
    .rtms__State_Lane__c;
    Test.stopTest();
    System.assertEquals(
      'NL:QC',
      mexicanStateLane,
      'precondition: the Mexican load carries the same state lane key'
    );
    System.assertEquals(
      CarrierLeadResult.STATE_LANE,
      r.stage,
      JSON.serialize(r)
    );
    System.assertEquals('NL to QC', r.stateLaneLabel, 'the label');
    System.assertEquals(
      new List<String>{ 'Canada Carrier' },
      stateLaneNames(r),
      'a load whose first stop is in Mexico is not on a Canadian NL lane'
    );
  }

  /**
   * Stage 2 counts the carrier legs of split shipments whose customer load is on the state lane,
   * dated by the customer load (R84). Called through stateLaneLeads, because a plan built by
   * SplitTestData in memory (Task 1, branch B) would also answer stage 1's plan read.
   */
  @IsTest
  static void stateLaneCountsTheLegsOfSplitShipments() {
    stateLaneSettings(new Set<Id>());
    PricingTestDataFactory.Graph g = PricingTestDataFactory.createGraph();
    Pricing_Place__c laval = RfpTestDataFactory.createPlace(
      'Laval',
      'QC',
      'CA',
      45.6066,
      -73.7124,
      'H7P'
    );
    Pricing_Place__c toronto = RfpTestDataFactory.createPlace(
      'Toronto',
      'ON',
      'CA',
      43.6532,
      -79.3832,
      'M5V'
    );
    Account legCarrier = SplitTestData.carrier('Leg Carrier', true);
    // The leg ends at a Quebec yard (state lane QC:QC), off QC:ON, so no quote the automation might
    // give a leg can reach the stage 2 quote counts (Task 1 asserts it gives legs none).
    Account yard = PricingTestDataFactory.createLocation(
      'Drummondville Yard',
      'Drummondville',
      'Quebec',
      'Canada',
      'J2C 1A1',
      45.8833,
      -72.4833
    );
    rtms__Load__c customerLoad = PricingTestDataFactory.createLoad(
      g,
      g.originLocation,
      g.destinationLocation
    );
    Test.startTest();
    rtms__Load__c leg = SplitTestData.legLoad(
      g,
      g.originLocation,
      yard,
      legCarrier,
      900,
      'Delivered'
    );
    SplitTestData.plan(customerLoad, new List<rtms__Load__c>{ leg });
    CarrierLeadResult r = CarrierLeadService.stateLaneLeads(
      stateLaneRequest(laval.Key__c, toronto.Key__c),
      laval,
      toronto,
      new CarrierLeadResult()
    );
    Date customerDay = [
      SELECT CreatedDate
      FROM rtms__Load__c
      WHERE Id = :customerLoad.Id
    ]
    .CreatedDate.date();
    Test.stopTest();
    SplitTestData.resetPlans();
    System.assertEquals(
      CarrierLeadResult.STATE_LANE,
      r.stage,
      JSON.serialize(r)
    );
    System.assertEquals(1, r.leads.size(), 'the leg carrier');
    CarrierLeadResult.Lead entry = r.leads[0];
    System.assertEquals('Leg Carrier', entry.name, 'by name');
    System.assertEquals(1, entry.loadsMoved, 'one leg load moved');
    System.assertEquals(0, entry.loadsQuoted, 'no quote');
    System.assertEquals(
      new List<String>{ CarrierLeadResult.SOURCE_SPLIT_LEG },
      entry.sources,
      'a split leg source only'
    );
    System.assertEquals(
      customerDay,
      entry.lastSeen,
      'dated by the customer load'
    );
    System.assertEquals(true, entry.blacklisted, 'the badge stays');
    System.assertEquals('QC to ON', r.stateLaneLabel, 'the label');
  }

  /**
   * Stage 2 is skipped when both ends used province keys (R95), when a place has a blank province,
   * and when a place's country has no stop country name (LaneQueries.COUNTRY_NAMES); a French place
   * then names nobody, without an error.
   */
  @IsTest
  static void stateLaneIsSkippedForProvinceEndsBlankProvincesAndOtherCountries() {
    stateLaneSettings(new Set<Id>());
    Pricing_Place__c quebec = new Pricing_Place__c(
      Key__c = 'laval|qc|ca',
      City__c = 'Laval',
      Province__c = 'QC',
      Country__c = 'CA'
    );
    Pricing_Place__c ontario = new Pricing_Place__c(
      Key__c = 'toronto|on|ca',
      City__c = 'Toronto',
      Province__c = 'ON',
      Country__c = 'CA'
    );
    Pricing_Place__c noProvince = new Pricing_Place__c(
      Key__c = 'nowhere||ca',
      City__c = 'Nowhere',
      Country__c = 'CA'
    );
    Pricing_Place__c paris = RfpTestDataFactory.createPlace(
      'Paris',
      'IDF',
      'FR',
      48.8566,
      2.3522,
      '750'
    );
    Pricing_Place__c toronto = RfpTestDataFactory.createPlace(
      'Toronto',
      'ON',
      'CA',
      43.6532,
      -79.3832,
      'M5V'
    );
    LaneSearchRequest cityEnds = stateLaneRequest(
      'laval|qc|ca',
      'toronto|on|ca'
    );
    LaneSearchRequest provinceEnds = stateLaneRequest(
      'laval|qc|ca',
      'toronto|on|ca'
    );
    provinceEnds.originPrecision = LaneSearchRequest.Precision.PROVINCE;
    provinceEnds.destinationPrecision = LaneSearchRequest.Precision.PROVINCE;
    LaneSearchRequest oneProvinceEnd = stateLaneRequest(
      'laval|qc|ca',
      'toronto|on|ca'
    );
    oneProvinceEnd.originPrecision = LaneSearchRequest.Precision.PROVINCE;
    Map<String, Object> binds = new Map<String, Object>();
    Test.startTest();
    List<String> conditions = CarrierLeadService.stateLane(
      cityEnds,
      quebec,
      ontario,
      binds
    );
    CarrierLeadResult french = CarrierLeadService.find(
      stateLaneRequest(paris.Key__c, toronto.Key__c)
    );
    Test.stopTest();
    System.assertNotEquals(null, conditions, 'city ends read the state lane');
    System.assert(
      conditions.contains('rtms__Load__r.rtms__State_Lane__c = :stateLane'),
      String.join(conditions, ' AND ')
    );
    System.assertEquals('QC:ON', binds.get('stateLane'), 'the state lane key');
    System.assertEquals('Canada', binds.get('oCountry'), 'origin country');
    System.assertEquals('Canada', binds.get('dCountry'), 'destination country');
    System.assertEquals(
      null,
      CarrierLeadService.stateLane(
        provinceEnds,
        quebec,
        ontario,
        new Map<String, Object>()
      ),
      'both ends on province keys: stage 1 already read that lane'
    );
    System.assertNotEquals(
      null,
      CarrierLeadService.stateLane(
        oneProvinceEnd,
        quebec,
        ontario,
        new Map<String, Object>()
      ),
      'one province end does not skip stage 2'
    );
    System.assertEquals(
      null,
      CarrierLeadService.stateLane(
        cityEnds,
        quebec,
        noProvince,
        new Map<String, Object>()
      ),
      'a blank destination province'
    );
    System.assertEquals(
      null,
      CarrierLeadService.stateLane(
        cityEnds,
        noProvince,
        ontario,
        new Map<String, Object>()
      ),
      'a blank origin province'
    );
    System.assertEquals(
      null,
      CarrierLeadService.stateLane(
        cityEnds,
        paris,
        ontario,
        new Map<String, Object>()
      ),
      'FR has no stop country name'
    );
    System.assertEquals(
      CarrierLeadResult.NONE,
      french.stage,
      JSON.serialize(french)
    );
    System.assertEquals(0, french.leads.size(), 'nobody');
    System.assertEquals(null, french.stateLaneLabel, 'no label');
  }
```

Create `force-app/main/default/classes/CarrierLeadControllerTest.cls`:

```apex
@IsTest
private class CarrierLeadControllerTest {
  private static final String LANE_JSON = '{"originKey":"montreal|qc|ca","destinationKey":"toronto|on|ca"}';

  /** No intercompany carrier and no excluded contact: tests never read the org's custom metadata. */
  private static void settings() {
    IntercompanyCarriers.idsOverride = new Set<Id>();
    LaneSearchExclusions.excludedContactIdsOverride = new Set<String>();
  }

  @IsTest
  static void anUnreadableRequestIsRefusedWithAShortMessage() {
    settings();
    Test.startTest();
    List<String> messages = new List<String>();
    for (String bad : new List<String>{ 'not json', '', 'null', null }) {
      try {
        CarrierLeadController.findCarrierLeads(bad, 0);
        messages.add('no exception for ' + bad);
      } catch (AuraHandledException e) {
        messages.add(e.getMessage());
      }
    }
    Test.stopTest();
    for (String message : messages) {
      System.assertEquals(
        CarrierLeadController.UNREADABLE_REQUEST,
        message,
        'every unreadable request gets the same message'
      );
    }
    System.assertEquals(4, messages.size(), 'four requests were tried');
  }

  @IsTest
  static void aLaneSearchExceptionReachesTheScreenAsItsMessage() {
    settings();
    // ZIP3 on an end whose place has no postal prefix and no typed prefix: LaneKeyMatcher refuses it.
    RfpTestDataFactory.createPlace(
      'Montréal',
      'QC',
      'CA',
      45.5019,
      -73.5674,
      null
    );
    RfpTestDataFactory.createPlace(
      'Toronto',
      'ON',
      'CA',
      43.6532,
      -79.3832,
      'M5V'
    );
    String message;
    Test.startTest();
    try {
      CarrierLeadController.findCarrierLeads(
        '{"originKey":"montreal|qc|ca","destinationKey":"toronto|on|ca","originPrecision":"ZIP3"}',
        0
      );
      message = 'no exception';
    } catch (AuraHandledException e) {
      message = e.getMessage();
    }
    Test.stopTest();
    System.assert(
      message.contains('has no postal prefix'),
      'the LaneSearchException text reaches the screen: ' + message
    );
  }

  @IsTest
  static void attemptIsIgnoredAndAnUnknownPlaceNamesNobody() {
    settings();
    PricingTestDataFactory.Graph g = PricingTestDataFactory.createGraph();
    RfpTestDataFactory.createPlace(
      'Montréal',
      'QC',
      'CA',
      45.5019,
      -73.5674,
      'H1A'
    );
    RfpTestDataFactory.createPlace(
      'Toronto',
      'ON',
      'CA',
      43.6532,
      -79.3832,
      'M5V'
    );
    rtms__Load__c load = PricingTestDataFactory.createLoad(
      g,
      g.originLocation,
      g.destinationLocation
    );
    rtms__CarrierQuote__c moved = PricingTestDataFactory.buildQuote(
      g,
      load,
      1000
    );
    moved.rtms__Accepted__c = true;
    insert moved;
    Test.startTest();
    CarrierLeadResult first = CarrierLeadController.findCarrierLeads(
      LANE_JSON,
      0
    );
    CarrierLeadResult retry = CarrierLeadController.findCarrierLeads(
      LANE_JSON,
      1
    );
    CarrierLeadResult noAttempt = CarrierLeadController.findCarrierLeads(
      LANE_JSON,
      null
    );
    CarrierLeadResult unknown = CarrierLeadController.findCarrierLeads(
      '{"originKey":"nowhere|zz|zz","destinationKey":"toronto|on|ca"}',
      0
    );
    Test.stopTest();
    System.assertEquals(
      CarrierLeadResult.SAME_LANE,
      first.stage,
      JSON.serialize(first)
    );
    System.assertEquals(1, first.leads.size(), 'the graph carrier');
    System.assertEquals('Test Carrier', first.leads[0].name, 'by name');
    System.assertEquals(1, first.leads[0].loadsMoved, 'one accepted quote');
    System.assertEquals(
      JSON.serialize(first),
      JSON.serialize(retry),
      'a Retry (attempt 1) gets the same answer'
    );
    System.assertEquals(
      JSON.serialize(first),
      JSON.serialize(noAttempt),
      'so does a call without attempt'
    );
    System.assertEquals(
      CarrierLeadResult.NONE,
      unknown.stage,
      'an unknown place key names nobody and is not an error'
    );
    System.assertEquals(0, unknown.leads.size(), 'no lead');
  }
}
```

Create `force-app/main/default/classes/CarrierLeadControllerTest.cls-meta.xml`:

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<ApexClass xmlns="http://soap.sforce.com/2006/04/metadata">
    <apiVersion>64.0</apiVersion>
    <status>Active</status>
</ApexClass>
```

Create `force-app/main/default/classes/CarrierSplitSecurityTest.cls`:

```apex
/**
 * Phase 8 security (spec §8). Carriers to ask reads quotes, loads and freight plans in system mode,
 * so a restricted pricer still gets carriers from records they cannot read, while the link to a
 * carrier account shows only when the caller can read that account in user mode. Class access is
 * read out of the permission set metadata, because Apex calling Apex does not enforce it. Task 9
 * adds the Split-lane options tests here.
 */
@IsTest
private class CarrierSplitSecurityTest {
  private static final String LANE_JSON = '{"originKey":"montreal|qc|ca","destinationKey":"toronto|on|ca"}';

  private class Fx {
    PricingTestDataFactory.Graph g;
    rtms__Load__c load;
  }

  /** The graph, the Montréal and Toronto places and one Montréal to Toronto load, owned by the admin. */
  private static Fx fx() {
    IntercompanyCarriers.idsOverride = new Set<Id>();
    LaneSearchExclusions.excludedContactIdsOverride = new Set<String>();
    Fx f = new Fx();
    f.g = PricingTestDataFactory.createGraph();
    RfpTestDataFactory.createPlace(
      'Montréal',
      'QC',
      'CA',
      45.5019,
      -73.5674,
      'H1A'
    );
    RfpTestDataFactory.createPlace(
      'Toronto',
      'ON',
      'CA',
      43.6532,
      -79.3832,
      'M5V'
    );
    f.load = PricingTestDataFactory.createLoad(
      f.g,
      f.g.originLocation,
      f.g.destinationLocation
    );
    return f;
  }

  /**
   * A carrier's own quote contact, transportation profile and carrier service, built like
   * PricingTestDataFactory.createGraph builds the graph's vendor: a quote's rtms__Vendor__c is its
   * service's carrier on every recent PostProduc quote.
   */
  private static rtms__CarrierService__c serviceFor(Fx f, Account carrier) {
    Contact quoteContact = new Contact(
      FirstName = 'Quote',
      LastName = carrier.Name,
      AccountId = carrier.Id,
      Email = 'hidden.quote@example.invalid',
      Phone = '514-555-0101'
    );
    insert quoteContact;
    rtms__TransportationProfile__c carrierProfile = new rtms__TransportationProfile__c(
      Name = carrier.Name + ' Profile',
      RecordTypeId = Schema.SObjectType.rtms__TransportationProfile__c.getRecordTypeInfosByDeveloperName()
        .get('Carrier')
        .getRecordTypeId(),
      rtms__Company_Risk__c = 'Acceptable',
      rtms__Carrier_Remit_To__c = carrier.Id
    );
    insert carrierProfile;
    rtms__CarrierService__c service = new rtms__CarrierService__c(
      Name = carrier.Name + ' Service',
      rtms__Carrier__c = carrier.Id,
      rtms__Mode__c = f.g.mode.Id,
      rtms__Transportation_Profile__c = carrierProfile.Id,
      rtms__Quote_Contact__c = quoteContact.Id,
      rtms__Minimum_Weight__c = 0,
      rtms__Maximum_Weight__c = 100000
    );
    insert service;
    return service;
  }

  /** A quote on the fixture load through the given carrier service; uninserted. */
  private static rtms__CarrierQuote__c quote(
    Fx f,
    rtms__CarrierService__c service,
    Boolean accepted
  ) {
    rtms__CarrierQuote__c q = PricingTestDataFactory.buildQuote(
      f.g,
      f.load,
      1000
    );
    q.rtms__Carrier_Service__c = service.Id;
    q.rtms__Vendor__c = service.rtms__Carrier__c;
    q.rtms__Quote_Contact__c = service.rtms__Quote_Contact__c;
    q.rtms__Accepted__c = accepted;
    return q;
  }

  private static CarrierLeadResult.Lead named(
    CarrierLeadResult r,
    String carrierName
  ) {
    for (CarrierLeadResult.Lead entry : r.leads) {
      if (entry.name == carrierName) {
        return entry;
      }
    }
    return null;
  }

  @IsTest
  static void theAccountLinkShowsOnlyForACarrierTheCallerCanRead() {
    User viewer = RfpTestDataFactory.restrictedUser('Lane_Benchmark_User');
    if (viewer == null) {
      System.assert(
        true,
        'no usable profile in this org; runAs coverage skipped (ledgered)'
      );
      return;
    }
    Fx f = fx();
    Account hidden = RfpTestDataFactory.hiddenCarrier();
    rtms__CarrierService__c hiddenService = serviceFor(f, hidden);
    Id hiddenId = hidden.Id;
    if (!RfpTestDataFactory.hiddenFrom(viewer, hiddenId)) {
      System.assert(
        true,
        'this org shares the hidden carrier ' +
          RfpTestDataFactory.sharingInputs(hiddenId) +
          '; account link coverage skipped (ledgered, R68)'
      );
      return;
    }
    Test.startTest();
    RfpTestDataFactory.shareAccount(f.g.vendor, viewer, 'Read');
    insert new List<rtms__CarrierQuote__c>{
      quote(f, f.g.carrierService, true),
      quote(f, hiddenService, false)
    };
    CarrierLeadResult seen;
    System.runAs(viewer) {
      seen = CarrierLeadController.findCarrierLeads(LANE_JSON, 0);
    }
    CarrierLeadResult admin = CarrierLeadController.findCarrierLeads(
      LANE_JSON,
      0
    );
    Test.stopTest();
    System.assertEquals(
      2,
      seen.leads.size(),
      'system mode names both carriers: ' + JSON.serialize(seen)
    );
    System.assertEquals(
      'Test Carrier',
      seen.leads[0].name,
      'the carrier that moved the load ranks first'
    );
    System.assertEquals(
      true,
      named(seen, 'Test Carrier').canOpen,
      'a carrier account the viewer can read opens'
    );
    CarrierLeadResult.Lead hiddenLead = named(seen, 'Hidden Carrier');
    System.assertEquals(
      false,
      hiddenLead.canOpen,
      'no link to an account the viewer cannot read'
    );
    System.assertEquals(
      true,
      hiddenLead.blacklisted,
      'the name still shows, with its badge'
    );
    System.assertEquals(
      true,
      named(admin, 'Hidden Carrier').canOpen,
      'the admin reads every account'
    );
  }

  @IsTest
  static void restrictedPricersStillGetCarriersFromPrivateQuotes() {
    User benchmark = RfpTestDataFactory.restrictedUser('Lane_Benchmark_User');
    User pricing = RfpTestDataFactory.restrictedUser('RFP_Tool_User');
    if (benchmark == null || pricing == null) {
      System.assert(
        true,
        'no usable profile in this org; runAs coverage skipped (ledgered)'
      );
      return;
    }
    Fx f = fx();
    Test.startTest();
    rtms__CarrierQuote__c moved = quote(f, f.g.carrierService, true);
    insert moved;
    Id quoteId = moved.Id;
    Integer visible;
    CarrierLeadResult benchmarkResult;
    CarrierLeadResult pricingResult;
    System.runAs(benchmark) {
      visible = [
        SELECT COUNT()
        FROM rtms__CarrierQuote__c
        WHERE Id = :quoteId
        WITH USER_MODE
      ];
      benchmarkResult = CarrierLeadController.findCarrierLeads(LANE_JSON, 0);
    }
    System.runAs(pricing) {
      pricingResult = CarrierLeadController.findCarrierLeads(LANE_JSON, 0);
    }
    Test.stopTest();
    System.assertEquals(
      0,
      visible,
      'precondition: the admin\'s quote is private to the Lane Benchmark user'
    );
    for (
      CarrierLeadResult r : new List<CarrierLeadResult>{
        benchmarkResult,
        pricingResult
      }
    ) {
      System.assertEquals(
        CarrierLeadResult.SAME_LANE,
        r.stage,
        JSON.serialize(r)
      );
      System.assertEquals(1, r.leads.size(), 'the graph carrier');
      System.assertEquals('Test Carrier', r.leads[0].name, 'by name');
      System.assertEquals(1, r.leads[0].loadsMoved, 'one accepted quote');
    }
  }

  /**
   * Class security is not enforced Apex to Apex, so the grant is read out of the metadata: a
   * controller missing here is the "You do not have access to the Apex class named ..." error a
   * pricer would hit in the browser. Task 9 checks SplitLaneController in its own test.
   */
  @IsTest
  static void bothPermissionSetsGrantThePhaseEightControllers() {
    List<String> permissionSets = new List<String>{
      'Lane_Benchmark_User',
      'RFP_Tool_User'
    };
    List<String> controllers = new List<String>{ 'CarrierLeadController' };
    List<SetupEntityAccess> grants = [
      SELECT Parent.Name, SetupEntityId
      FROM SetupEntityAccess
      WHERE Parent.Name IN :permissionSets AND SetupEntityType = 'ApexClass'
    ];
    Set<Id> classIds = new Set<Id>();
    for (SetupEntityAccess grant : grants) {
      classIds.add(grant.SetupEntityId);
    }
    Map<Id, ApexClass> classes = new Map<Id, ApexClass>(
      [SELECT Id, Name FROM ApexClass WHERE Id IN :classIds]
    );
    Set<String> granted = new Set<String>();
    for (SetupEntityAccess grant : grants) {
      granted.add(
        grant.Parent.Name + ':' + classes.get(grant.SetupEntityId).Name
      );
    }
    for (String permissionSet : permissionSets) {
      for (String controller : controllers) {
        System.assert(
          granted.contains(permissionSet + ':' + controller),
          permissionSet + ' grants no class access to ' + controller
        );
      }
    }
  }
}
```

Create `force-app/main/default/classes/CarrierSplitSecurityTest.cls-meta.xml`:

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<ApexClass xmlns="http://soap.sforce.com/2006/04/metadata">
    <apiVersion>64.0</apiVersion>
    <status>Active</status>
</ApexClass>
```

Why the security fixtures hold in PostProduc (read-only checks, 2026-09-15): no `rtms__Load__Share` row shares a load with the org-wide group (`Group.Type = 'Organization'`), and the largest rule share goes to `TMS Site Guest User Group`, so a new restricted user cannot read the admin's test load or its quote (the `visible` precondition). `Lane_Benchmark_User` grants Read on `rtms__CarrierQuote__c`, so that count returns 0 instead of throwing. The graph's vendor is shared with the viewer through `RfpTestDataFactory.shareAccount`, so its link does not depend on the carrier sharing rules. `hiddenFrom` runs after the hidden carrier's service is created, in case that automation changes its owner. `SELECT Parent.Name, SetupEntityId FROM SetupEntityAccess WHERE Parent.Name IN ('Lane_Benchmark_User','RFP_Tool_User') AND SetupEntityType = 'ApexClass'` compiles and returns 24 rows today.

- [ ] **Step 2: Deploy the tests alone to see them fail to compile**

Run: `sf project deploy start -o sandbox --source-dir force-app/main/default/classes/CarrierLeadServiceTest.cls --source-dir force-app/main/default/classes/CarrierLeadControllerTest.cls --source-dir force-app/main/default/classes/CarrierSplitSecurityTest.cls -l NoTestRun --async --json | python3 -c "import json,sys; s=sys.stdin.read(); print(json.loads(s[s.index('{'):])['result']['id'])"`

Expected: a deploy id (`0Af...`). Then poll, repeating until the status is `Succeeded` or `Failed` (each call waits at most 2 minutes):

Run: `sf project deploy report -o sandbox --job-id <id> -w 2 --json | python3 -c "import json,sys; s=sys.stdin.read(); r=json.loads(s[s.index('{'):])['result']; print(r['status'], [d.get('problem') for d in r.get('details',{}).get('componentFailures',[])][:3])"`

Expected: `Failed` with `Invalid type: CarrierLeadController` and `Method does not exist or incorrect signature: void stateLaneLeads(LaneSearchRequest, Pricing_Place__c, Pricing_Place__c, CarrierLeadResult) from the type CarrierLeadService` (or the same for `stateLane`). Neither exists yet, so nothing is deployed.

- [ ] **Step 3: Write the controller**

Create `force-app/main/default/classes/CarrierLeadController.cls`. The error mapping is `LaneBenchmarkController.search`'s, and its private `userError` helper is copied, because it is private there:

```apex
/**
 * Carriers to ask (phase 8, spec §6): the Lane Benchmark page and the RFP lane panel call this when
 * their first search found no carrier rate in the pricing currency. Thin, like
 * LaneBenchmarkController.search: it reads the request JSON and translates errors;
 * CarrierLeadService reads the place keys, precisions, postal prefixes and the mode, equipment and
 * hazmat filters, and does the work in system mode. No readable-project check, because no bid is
 * read. attempt is 0 on the first call and grows with each Retry, so a Retry is not answered from
 * the browser's cache of this cacheable method; the server ignores it (R91).
 */
public with sharing class CarrierLeadController {
  @TestVisible
  private static final String UNREADABLE_REQUEST = 'The search request could not be read. Please reset the filters and try again.';

  @AuraEnabled(cacheable=true)
  public static CarrierLeadResult findCarrierLeads(
    String requestJson,
    Integer attempt
  ) {
    LaneSearchRequest req;
    try {
      req = (LaneSearchRequest) JSON.deserialize(
        requestJson,
        LaneSearchRequest.class
      );
    } catch (Exception e) {
      throw userError(UNREADABLE_REQUEST);
    }
    if (req == null) {
      throw userError(UNREADABLE_REQUEST);
    }
    try {
      return CarrierLeadService.find(req);
    } catch (LaneSearchException e) {
      throw userError(e.getMessage());
    } catch (QueryException e) {
      throw userError(
        'The search took too long or returned too much data. Narrow the lookback or the radius and try again. (' +
          e.getMessage() +
          ')'
      );
    }
  }

  private static AuraHandledException userError(String message) {
    AuraHandledException e = new AuraHandledException(message);
    e.setMessage(message);
    return e;
  }
}
```

Create `force-app/main/default/classes/CarrierLeadController.cls-meta.xml`:

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<ApexClass xmlns="http://soap.sforce.com/2006/04/metadata">
    <apiVersion>64.0</apiVersion>
    <status>Active</status>
</ApexClass>
```

- [ ] **Step 4: Grant class access in both permission sets**

In `force-app/main/default/permissionsets/Lane_Benchmark_User.permissionset-meta.xml`, directly before the `<classAccesses>` block whose `<apexClass>` is `LaneBenchmarkController` (the first one), insert:

```xml
    <classAccesses>
        <apexClass>CarrierLeadController</apexClass>
        <enabled>true</enabled>
    </classAccesses>
```

In `force-app/main/default/permissionsets/RFP_Tool_User.permissionset-meta.xml`, directly after the `<classAccesses>` block whose `<apexClass>` is `BenchmarkRateService`, and before the one for `LaneBenchmarkController`, insert the same four lines. No other permission changes (the service, `CarrierLeadResult` and `LaneQueries` are reached Apex to Apex).

Run: `grep -c "<apexClass>CarrierLeadController</apexClass>" force-app/main/default/permissionsets/Lane_Benchmark_User.permissionset-meta.xml force-app/main/default/permissionsets/RFP_Tool_User.permissionset-meta.xml`

Expected: `...Lane_Benchmark_User.permissionset-meta.xml:1` and `...RFP_Tool_User.permissionset-meta.xml:1`.

- [ ] **Step 5: Add stage 2 to the service**

Replace the whole of `force-app/main/default/classes/CarrierLeadService.cls` with the file below. Stage 1 behaves exactly as Task 5 built it (contract A10): places by key, the two grouped quote counts and the plan read over 1,095 days, merge per carrier, ranking, the 50-group and 500-plan truncation, the query-row guard and the user-mode account link. What changes: `find` hands over to `stateLaneLeads` when stage 1 has no carrier and did not stop at the guard; `readStage`, `finish`, `Tally` and `LeadOrder` serve both stages (`LeadOrder(false)` drops loads quoted from the ranking); `stateLane` decides whether stage 2 applies. Task 5's committed tests use three members of this class: `find`, `@TestVisible ranked(List<CarrierLeadResult.Lead>, Boolean)` and `@TestVisible rowReserve`; the file below keeps all three with Task 5's signatures (`finish` ranks through `ranked`). Every public signature and `@TestVisible` member listed under Interfaces must end up as written here.

```apex
/**
 * Carriers to ask (phase 8, spec §3): the carriers that know a lane when the first search found no
 * carrier rate, by name and counts only. Stage 1 reads the same lane over 3 years: carrier quotes in
 * two grouped counts (loads quoted, loads moved; SOQL has no conditional count, R107) and the carrier
 * legs of freight plans whose customer load is on the lane, read through FreightPlanReader. Stage 2
 * runs only when stage 1 has no carrier left after the removals (R81): the same state or province
 * lane over the last 365 days, each end also in its place's country (R102), top 10 by loads moved
 * then last seen. Intercompany carriers are left out by the quote queries and while reading plan
 * legs; the excluded contacts apply to quotes only. No query here selects an amount (R106), and
 * CarrierLeadResult has no amount field. The per-carrier merge (Tally) and the ranking (LeadOrder)
 * are inner classes, so their branches stay out of this class's PMD complexity total.
 */
// Runs without sharing on purpose: carrier quotes inherit Private load sharing, like LaneSearchService. Access is gated by the Lane Benchmark and RFP permission sets; the account link alone is decided in user mode.
public without sharing class CarrierLeadService {
  @TestVisible
  private static final Integer SAME_LANE_DAYS = 1095;
  @TestVisible
  private static final Integer STATE_LANE_DAYS = 365;
  @TestVisible
  private static final Integer PLAN_LIMIT = 500;
  @TestVisible
  private static final Integer STATE_LANE_TOP = 10;
  private static final String LOAD_PATH = 'rtms__Load__r.';
  /** Query rows kept in reserve: before each query a stage stops once fewer remain (spec §8). */
  @TestVisible
  private static Integer rowReserve = 5000;

  public static CarrierLeadResult find(LaneSearchRequest req) {
    CarrierLeadResult result = new CarrierLeadResult();
    req.applyDefaults();
    Map<String, Pricing_Place__c> places = placesByKey(req);
    Pricing_Place__c origin = places.get(req.originKey);
    Pricing_Place__c destination = places.get(req.destinationKey);
    if (origin == null || destination == null) {
      return result;
    }
    Map<String, Object> quoteBinds = new Map<String, Object>();
    Map<String, Object> planBinds = new Map<String, Object>();
    Tally sameLane = readStage(
      LaneQueries.laneConditions(
        req,
        origin,
        destination,
        LOAD_PATH,
        quoteBinds
      ),
      LaneQueries.laneConditions(req, origin, destination, LOAD_PATH, planBinds),
      SAME_LANE_DAYS,
      quoteBinds,
      planBinds
    );
    if (sameLane.hasLeads() || sameLane.stopped) {
      return finish(result, sameLane, CarrierLeadResult.SAME_LANE, null);
    }
    result.truncated = sameLane.truncated;
    return stateLaneLeads(req, origin, destination, result);
  }

  /**
   * Stage 2 on its own: the state or province lane over 365 days, top 10, labelled "QC to ON". find
   * calls it only when stage 1 has no carrier; tests call it directly, so a freight plan fixture
   * (SplitTestData.plan) proves stage 2's leg count whichever way Task 1 proved plans are built.
   */
  @TestVisible
  private static CarrierLeadResult stateLaneLeads(
    LaneSearchRequest req,
    Pricing_Place__c origin,
    Pricing_Place__c destination,
    CarrierLeadResult result
  ) {
    Map<String, Object> quoteBinds = new Map<String, Object>();
    List<String> quoteConditions = stateLane(
      req,
      origin,
      destination,
      quoteBinds
    );
    if (quoteConditions == null) {
      return result;
    }
    Map<String, Object> planBinds = new Map<String, Object>();
    Tally stateLaneTally = readStage(
      quoteConditions,
      stateLane(req, origin, destination, planBinds),
      STATE_LANE_DAYS,
      quoteBinds,
      planBinds
    );
    finish(result, stateLaneTally, CarrierLeadResult.STATE_LANE, STATE_LANE_TOP);
    if (result.stage == CarrierLeadResult.STATE_LANE) {
      result.stateLaneLabel = origin.Province__c + ' to ' + destination.Province__c;
    }
    return result;
  }

  /**
   * Stage 2's conditions, or null when stage 2 does not apply: both ends of the first search used
   * province keys (stage 1 already read that lane, R95), a place has a blank Province__c, or
   * LaneQueries cannot map a place's Country__c to the country name a stop account holds.
   */
  @TestVisible
  private static List<String> stateLane(
    LaneSearchRequest req,
    Pricing_Place__c origin,
    Pricing_Place__c destination,
    Map<String, Object> binds
  ) {
    Boolean bothProvince =
      req.originPrecision == LaneSearchRequest.Precision.PROVINCE &&
      req.destinationPrecision == LaneSearchRequest.Precision.PROVINCE;
    if (
      bothProvince ||
      String.isBlank(origin.Province__c) ||
      String.isBlank(destination.Province__c)
    ) {
      return null;
    }
    return LaneQueries.stateLaneConditions(
      req,
      origin,
      destination,
      LOAD_PATH,
      binds
    );
  }

  /**
   * Stage 1 order (byQuoted true): loads moved, loads quoted, last seen (a missing date last),
   * name ignoring case; byQuoted false skips loads quoted (stage 2, R82). Returns a new list.
   */
  @TestVisible
  private static List<CarrierLeadResult.Lead> ranked(
    List<CarrierLeadResult.Lead> leads,
    Boolean byQuoted
  ) {
    List<CarrierLeadResult.Lead> sorted = new List<CarrierLeadResult.Lead>(
      leads
    );
    sorted.sort(new LeadOrder(byQuoted));
    return sorted;
  }

  /** The two grouped quote counts, then the plans with their legs; stops early near the row limit. */
  @SuppressWarnings(
    'PMD.ApexCRUDViolation'
  ) // system mode by design (see class comment); Database.queryWithBinds also counts as CRUD for PMD
  private static Tally readStage(
    List<String> quoteConditions,
    List<String> planConditions,
    Integer days,
    Map<String, Object> quoteBinds,
    Map<String, Object> planBinds
  ) {
    Tally tally = new Tally();
    String quotedSoql = LaneQueries.quoteCountSoql(
      quoteConditions,
      days,
      false,
      quoteBinds
    );
    String movedSoql = LaneQueries.quoteCountSoql(
      quoteConditions,
      days,
      true,
      quoteBinds
    );
    String plansSoql = LaneQueries.planSoql(
      planConditions,
      days,
      PLAN_LIMIT,
      false
    );
    if (tally.outOfRows()) {
      return tally;
    }
    tally.addGroups(
      (List<AggregateResult>) Database.queryWithBinds(
        quotedSoql,
        quoteBinds,
        AccessLevel.SYSTEM_MODE
      ),
      false
    );
    if (tally.outOfRows()) {
      return tally;
    }
    tally.addGroups(
      (List<AggregateResult>) Database.queryWithBinds(
        movedSoql,
        quoteBinds,
        AccessLevel.SYSTEM_MODE
      ),
      true
    );
    if (tally.outOfRows()) {
      return tally;
    }
    tally.addPlans(
      FreightPlanReader.read(plansSoql, planBinds),
      IntercompanyCarriers.ids()
    );
    return tally;
  }

  /** Ranks, cuts stage 2 to its top 10, and decides each account link with one user-mode read. */
  private static CarrierLeadResult finish(
    CarrierLeadResult result,
    Tally tally,
    String stage,
    Integer top
  ) {
    List<CarrierLeadResult.Lead> leads = ranked(tally.leads(), top == null);
    while (top != null && leads.size() > top) {
      leads.remove(leads.size() - 1);
    }
    result.truncated =
      result.truncated ||
      tally.truncated ||
      (top == null && tally.groupCapped);
    if (leads.isEmpty()) {
      return result;
    }
    result.stage = stage;
    result.leads = leads;
    if (tally.outOfRows()) {
      return result;
    }
    Set<Id> carrierIds = new Set<Id>();
    for (CarrierLeadResult.Lead entry : leads) {
      carrierIds.add(entry.carrierId);
    }
    Set<Id> readable = readableAccounts(carrierIds);
    for (CarrierLeadResult.Lead entry : leads) {
      entry.canOpen = readable.contains(entry.carrierId);
    }
    return result;
  }

  /**
   * The carrier accounts the caller can read in user mode (sharing and object access). A caller
   * with no read on Account at all gets an exception from the platform, and opens no link.
   */
  private static Set<Id> readableAccounts(Set<Id> accountIds) {
    Set<Id> readable = new Set<Id>();
    try {
      for (Account a : [
        SELECT Id
        FROM Account
        WHERE Id IN :accountIds
        WITH USER_MODE
      ]) {
        readable.add(a.Id);
      }
    } catch (Exception e) {
      return new Set<Id>();
    }
    return readable;
  }

  @SuppressWarnings(
    'PMD.ApexCRUDViolation'
  ) // system mode by design (see class comment)
  private static Map<String, Pricing_Place__c> placesByKey(
    LaneSearchRequest req
  ) {
    Map<String, Pricing_Place__c> byKey = new Map<String, Pricing_Place__c>();
    if (String.isBlank(req.originKey) || String.isBlank(req.destinationKey)) {
      return byKey;
    }
    Set<String> keys = new Set<String>{ req.originKey, req.destinationKey };
    for (Pricing_Place__c p : [
      SELECT
        Key__c,
        City__c,
        Province__c,
        Country__c,
        Postal_Prefix__c,
        Spellings__c,
        Geolocation__Latitude__s,
        Geolocation__Longitude__s
      FROM Pricing_Place__c
      WHERE Key__c IN :keys
    ]) {
      byKey.put(p.Key__c, p);
    }
    return byKey;
  }

  /**
   * One stage's carriers. Quote groups set loadsQuoted or loadsMoved and the latest quote date; plan
   * legs add distinct leg loads per carrier (a leg is a Carrier row whose load is not Cancelled and
   * whose carrier is set and not intercompany), dated by the plan's customer load (R84). leads()
   * adds the leg loads to loadsMoved and lists the sources in the order Quote, Split leg.
   */
  private class Tally {
    Map<Id, CarrierLeadResult.Lead> byCarrier = new Map<Id, CarrierLeadResult.Lead>();
    Set<Id> quoteCarriers = new Set<Id>();
    Map<Id, Set<Id>> legLoads = new Map<Id, Set<Id>>();
    Boolean truncated = false;
    // A 51st carrier group: marks stage 1 incomplete (it shows every carrier), never stage 2, whose
    // groups come back ordered by loads, so its top 10 is already exact.
    Boolean groupCapped = false;
    Boolean stopped = false;

    Boolean hasLeads() {
      return !byCarrier.isEmpty();
    }

    Boolean outOfRows() {
      if (Limits.getQueryRows() > Limits.getLimitQueryRows() - rowReserve) {
        stopped = true;
        truncated = true;
      }
      return stopped;
    }

    void addGroups(List<AggregateResult> groups, Boolean moved) {
      if (groups.size() > LaneQueries.GROUP_LIMIT) {
        groupCapped = true;
        groups.remove(groups.size() - 1);
      }
      for (AggregateResult g : groups) {
        CarrierLeadResult.Lead entry = leadFor(
          (Id) g.get('rtms__Vendor__c'),
          (String) g.get('vname'),
          (Boolean) g.get('bl')
        );
        Integer loads = (Integer) g.get('loads');
        if (moved) {
          entry.loadsMoved = loads;
        } else {
          entry.loadsQuoted = loads;
        }
        quoteCarriers.add(entry.carrierId);
        Datetime seen = (Datetime) g.get('lastSeen');
        see(entry, seen?.date());
      }
    }

    void addPlans(List<rtms__FreightPlan__c> plans, Set<Id> intercompany) {
      if (plans.size() >= PLAN_LIMIT) {
        truncated = true;
      }
      for (rtms__FreightPlan__c plan : plans) {
        addPlan(plan, intercompany);
      }
    }

    // A for loop over the child rows: reading a child list of more than 200 rows directly throws.
    void addPlan(rtms__FreightPlan__c plan, Set<Id> intercompany) {
      Date customerDate;
      List<rtms__FreightPlanLoad__c> legs = new List<rtms__FreightPlanLoad__c>();
      for (rtms__FreightPlanLoad__c row : plan.rtms__Freight_Plan_Loads__r) {
        if (row.rtms__Type__c == 'Customer') {
          customerDate = row.rtms__Load__r?.CreatedDate?.date();
        } else if (isLeg(row, intercompany)) {
          legs.add(row);
        }
      }
      for (rtms__FreightPlanLoad__c row : legs) {
        CarrierLeadResult.Lead entry = leadFor(
          row.rtms__Load__r.rtms__Carrier__c,
          row.rtms__Load__r.rtms__Carrier__r?.Name,
          row.rtms__Load__r.rtms__Carrier__r?.Black_List__c
        );
        if (!legLoads.containsKey(entry.carrierId)) {
          legLoads.put(entry.carrierId, new Set<Id>());
        }
        legLoads.get(entry.carrierId).add(row.rtms__Load__c);
        see(entry, customerDate);
      }
    }

    Boolean isLeg(rtms__FreightPlanLoad__c row, Set<Id> intercompany) {
      Id carrierId = row.rtms__Load__r?.rtms__Carrier__c;
      return row.rtms__Type__c == 'Carrier' &&
        carrierId != null &&
        !intercompany.contains(carrierId) &&
        row.rtms__Load__r.rtms__Load_Status__c != 'Cancelled';
    }

    CarrierLeadResult.Lead leadFor(
      Id carrierId,
      String carrierName,
      Boolean blacklisted
    ) {
      CarrierLeadResult.Lead existing = byCarrier.get(carrierId);
      if (existing == null) {
        existing = new CarrierLeadResult.Lead();
        existing.carrierId = carrierId;
        existing.name = carrierName;
        byCarrier.put(carrierId, existing);
      }
      existing.blacklisted = existing.blacklisted || blacklisted == true;
      return existing;
    }

    void see(CarrierLeadResult.Lead entry, Date day) {
      if (day != null && (entry.lastSeen == null || day > entry.lastSeen)) {
        entry.lastSeen = day;
      }
    }

    List<CarrierLeadResult.Lead> leads() {
      List<CarrierLeadResult.Lead> out = new List<CarrierLeadResult.Lead>();
      for (CarrierLeadResult.Lead entry : byCarrier.values()) {
        entry.sources = new List<String>();
        if (quoteCarriers.contains(entry.carrierId)) {
          entry.sources.add(CarrierLeadResult.SOURCE_QUOTE);
        }
        Set<Id> legs = legLoads.get(entry.carrierId);
        if (legs != null) {
          entry.loadsMoved += legs.size();
          entry.sources.add(CarrierLeadResult.SOURCE_SPLIT_LEG);
        }
        out.add(entry);
      }
      return out;
    }
  }

  /**
   * Stage 1 (thenQuoted true): loads moved, loads quoted, last seen (a missing date last), name.
   * Stage 2 (thenQuoted false): loads moved, last seen, name (R82).
   */
  private class LeadOrder implements Comparator<CarrierLeadResult.Lead> {
    private Boolean thenQuoted;

    LeadOrder(Boolean thenQuoted) {
      this.thenQuoted = thenQuoted;
    }

    public Integer compare(CarrierLeadResult.Lead a, CarrierLeadResult.Lead b) {
      if (a.loadsMoved != b.loadsMoved) {
        return b.loadsMoved - a.loadsMoved;
      }
      if (thenQuoted && a.loadsQuoted != b.loadsQuoted) {
        return b.loadsQuoted - a.loadsQuoted;
      }
      if (a.lastSeen != b.lastSeen) {
        return byDateDescending(a.lastSeen, b.lastSeen);
      }
      return (a.name == null ? '' : a.name.toLowerCase())
        .compareTo(b.name == null ? '' : b.name.toLowerCase());
    }

    private Integer byDateDescending(Date a, Date b) {
      if (a == null) {
        return 1;
      }
      if (b == null) {
        return -1;
      }
      return a > b ? -1 : 1;
    }
  }
}
```

- [ ] **Step 6: Add the classes to the manifest**

In `manifest/package.xml`, inside the `<types>` block whose `<name>` is `ApexClass`, directly before `<name>ApexClass</name>` (after the members Task 5 added):

```xml
        <members>CarrierLeadController</members>
        <members>CarrierLeadControllerTest</members>
        <members>CarrierSplitSecurityTest</members>
```

The `PermissionSet` block already lists `Lane_Benchmark_User` and `RFP_Tool_User`.

- [ ] **Step 7: Deploy the classes and permission sets and run the tests**

`LaneQueriesTest` runs as well: the org enforces 75 % coverage per deployed class, and the scoped deploy is checked against the tests that cover everything stage 2 calls.

Run: `sf project deploy start -o sandbox --source-dir force-app/main/default/classes/CarrierLeadService.cls --source-dir force-app/main/default/classes/CarrierLeadServiceTest.cls --source-dir force-app/main/default/classes/CarrierLeadController.cls --source-dir force-app/main/default/classes/CarrierLeadControllerTest.cls --source-dir force-app/main/default/classes/CarrierSplitSecurityTest.cls --source-dir force-app/main/default/permissionsets/Lane_Benchmark_User.permissionset-meta.xml --source-dir force-app/main/default/permissionsets/RFP_Tool_User.permissionset-meta.xml -l RunSpecifiedTests -t CarrierLeadServiceTest -t CarrierLeadControllerTest -t CarrierSplitSecurityTest -t LaneQueriesTest --async --json | python3 -c "import json,sys; s=sys.stdin.read(); print(json.loads(s[s.index('{'):])['result']['id'])"`

Expected: a deploy id. Poll until the status is `Succeeded` or `Failed`:

Run: `sf project deploy report -o sandbox --job-id <id> -w 2 --json | python3 -c "import json,sys; s=sys.stdin.read(); r=json.loads(s[s.index('{'):])['result']; print(r['id'], r['status'], 'tests', r.get('numberTestsCompleted'), '/', r.get('numberTestsTotal'), 'failures', r.get('numberTestErrors')); [print(f['name'], f['methodName'], '->', f['message'][:160]) for f in r.get('details',{}).get('runTestResult',{}).get('failures',[])]; [print(c['name'], c['numLocations'] - c['numLocationsNotCovered'], '/', c['numLocations']) for c in r.get('details',{}).get('runTestResult',{}).get('codeCoverage',[]) if c['name'] in ('CarrierLeadService','CarrierLeadController')]"`

Expected: `Succeeded tests N / N failures 0`, where N is Step 0's two Task 5 method counts plus 11 (5 `CarrierLeadServiceTest` + 3 `CarrierLeadControllerTest` + 3 `CarrierSplitSecurityTest`), and both classes above 75 % covered (the controller's `QueryException` branch is the only line left uncovered there). If a test fails, fix the class, not the assertion, unless the assertion contradicts the spec. Known failure shapes:

- `stateLaneKeepsTheTopTenByLoadsMovedThenLastSeen` with `Too many SOQL queries: 101` before `Test.startTest()`: the fixture is over budget. Build 11 carriers (`i <= 11` in both loops, Carrier 11 accepted), and expect `Carrier 11`, then `Carrier 01` to `Carrier 09` (Carrier 10 is cut). That is still a top 10 cut after the ranking. Do not move the quotes after `Test.startTest()`, because `Test.setCreatedDate` is refused there.
- `stateLaneCountsOnlyLoadsWhoseStopsAreInEachPlacesCountry` with `FIELD_INTEGRITY_EXCEPTION` on the Mexican location: the state picklist refused `Nuevo León`. In PostProduc `SELECT ShippingState FROM Account WHERE ShippingCountryCode = 'MX' AND ShippingStateCode = 'NL'` returns `Nuevo León`. Paste that exact spelling.
- `theAccountLinkShowsOnlyForACarrierTheCallerCanRead` with `canOpen` false for `Test Carrier`: the manual share did not reach the viewer. Check `RfpTestDataFactory.shareAccount` ran before the two `findCarrierLeads` calls. Do not drop the assertion.
- `Too many SOQL queries: 101` before `Test.startTest()` in a `CarrierSplitSecurityTest` method: move `Test.startTest()` up to right after `fx()` in that method (no fixture there needs `Test.setCreatedDate`).
- `restrictedPricersStillGetCarriersFromPrivateQuotes` failing its precondition (`visible` 1): PostProduc now shares test loads with every internal user. Ask the owner before changing the test; the leads assertions still hold.

- [ ] **Step 8: PMD**

Run: `/private/tmp/pmd_install/pmd-bin-7.15.0/bin/pmd check --dir force-app --rulesets config/pmd-ruleset.xml --minimum-priority 3 --format text --fail-on-violation; echo "pmd exit $?"`

Expected: no violation lines, `pmd exit 0`. The code above passed the same ruleset in copies outside the repo (2026-09-15). PMD 7.15.0 measured these class cyclomatic complexity totals against the budget of 40:

- `CarrierLeadService` 30; the inner classes `Tally` 27 and `LeadOrder` 12 count separately.
- `CarrierLeadController` 10.
- `CarrierSplitSecurityTest` 18.
- The stage 2 methods and helpers add 17 to `CarrierLeadServiceTest`.

The suppressions are two `ApexCRUDViolation`, on `readStage` and `placesByKey` (system mode, with a justification comment). If `CarrierLeadServiceTest` passes 40 together with Task 5's tests, move the `stateLane*` helpers into a private inner class used through an instance (`new StateLaneFixtures().carriers(g, names)`), because inner-class methods do not count toward the outer class. Do not raise the budget.

- [ ] **Step 9: Commit**

```bash
git add force-app/main/default/classes/CarrierLeadService.cls force-app/main/default/classes/CarrierLeadServiceTest.cls force-app/main/default/classes/CarrierLeadController.cls force-app/main/default/classes/CarrierLeadController.cls-meta.xml force-app/main/default/classes/CarrierLeadControllerTest.cls force-app/main/default/classes/CarrierLeadControllerTest.cls-meta.xml force-app/main/default/classes/CarrierSplitSecurityTest.cls force-app/main/default/classes/CarrierSplitSecurityTest.cls-meta.xml force-app/main/default/permissionsets/Lane_Benchmark_User.permissionset-meta.xml force-app/main/default/permissionsets/RFP_Tool_User.permissionset-meta.xml manifest/package.xml
git commit -m "Add Carriers to ask stage 2, CarrierLeadController and the phase 8 security tests"
```

Expected: lint-staged runs Prettier on the staged Apex and XML (it may reformat long lines; that is expected), and the commit lands on `phase-8/carriers-and-split-lanes`. `git status --short` still shows `.vscode/settings.json` and the `* 2.*` files unstaged. The commit has no attribution trailer.

#### Contract notes (Task 6)

1. **`CarrierLeadService` is given whole.** Task 5 was drafted at the same time, so its private helpers were not available to edit against. Stage 1 follows A10 line by line: 1,095 days, two grouped counts on one bind map, the plan read on a second bind map through `FreightPlanReader`, a merge per carrier, ranking, truncation at 51 groups or 500 plans, and the query-row guard before every query after the places read. The file keeps the three members Task 5's tests use (`find`, `ranked`, `rowReserve`) with Task 5's signatures, so those tests still compile and pass (Step 7 runs them).
2. **Two `@TestVisible` seams beyond the contract.**
   - `stateLaneLeads(req, origin, destination, result)` runs stage 2 alone. In Task 1's branch B, `FreightPlanReader.rowsOverride` answers every plan read, so a plan fixture would also fill stage 1 and `find` would never reach stage 2. Calling the seam proves the stage 2 leg count on either branch. The stage 2 plan SOQL filter is Task 5's `LaneQueriesTest` subject.
   - `stateLane(req, origin, destination, binds)` makes the skip rules testable without data: both precisions `PROVINCE`, a blank `Province__c`, a country outside CA/US/MX. Those skips cannot be told apart from an empty stage 2 by rows, because every carrier stage 2 finds with both ends on `PROVINCE`, stage 1 has already found.
3. **Stage 2 edge rules the contract leaves open.**
   - `stateLaneLabel` is set only when stage 2 names at least one carrier, so it appears only with `stage` `State lane`.
   - A stage 1 `truncated` (for example 500 plans that were all intercompany) carries into the stage 2 result.
   - Stage 2 does not run after the query-row guard stopped stage 1, since the guard returns what was found.
4. **The row-guard reserve is `@TestVisible private static Integer rowReserve = 5000`.** A test can set it to `Limits.getLimitQueryRows()` to force a stop; it is Task 5's hook, unchanged.
5. **`find` calls `req.applyDefaults()`, not `validate()`.** `JSON.deserialize` leaves precisions null. `validate()` would check the lookback and radius, which Carriers to ask ignores (R101). The first search has already validated the same request.
6. **Controller details.**
   - `CarrierLeadController` is `with sharing`, the contract's default for a new class; the service it calls stays `without sharing`.
   - It refuses a request that deserializes to null (the JSON text `null`) with the same message, where `LaneBenchmarkController.search` would throw a NullPointerException.
   - The message is a `@TestVisible` constant, `UNREADABLE_REQUEST`.
   - The `QueryException` text is copied word for word from the search, including its advice about lookback and radius.
7. **The account link read catches `Exception` and then opens no link.** `Lane_Benchmark_User` grants no Account permission. In PostProduc the Standard User profile does, but a Minimum Access user would make `WITH USER_MODE` throw.
8. **Quote fixtures give each carrier its own carrier service, quote contact and transportation profile,** as in Task 5. On recent quotes `rtms__Vendor__c` always equals the service's carrier. The validation rule `Carrier_service_only_for_carriers` needs the account's record type to be `Carrier`. The Contact rule `Check_CompanyId_Value` only checks a LinkedIn id these tests never set. Quote carriers are inserted one list per object rather than through `SplitTestData.carrier`, for the fixture budget. The leg carrier uses `SplitTestData.carrier`.
9. **The stop-country test uses NL, not QC.** State and country picklists are on in PostProduc (`Account.ShippingStateCode` exists), so a Mexican account cannot carry `Quebec`. `Newfoundland and Labrador` and `Nuevo León` both give `NL` in `PlaceNormalizer.provinceCode`, and the test first asserts the Mexican load's `rtms__State_Lane__c` is `NL:QC`.
10. **Only the first load of a test is created before `Test.startTest()`.** A second load is created inside, as `PricingTestDataFactory` requires (three in one context hit 101 queries). The contract's "fixture DML before Test.startTest()" holds for every other record. The two `CarrierSplitSecurityTest` data tests also create their account share and quotes inside `Test.startTest()` (none needs `Test.setCreatedDate`), because the restricted users, the graph and the carrier chains already fill the context before it.
11. **The top 10 test has no intercompany carrier,** to fit the budget. Stage 2's intercompany removal, and "a stage counts as empty after the removals", are covered by `stateLaneRunsOnlyWhenTheSameLaneHasNoCarrierLeft`.
12. **New SOQL shapes proven read-only in PostProduc 2026-09-15** (JSON under `scratchpad/phase8-plan-drafts/soql/`):
    - Plan semi-join with `rtms__State_Lane__c = 'NL:QC'` and both stop countries: 3 plans (`t6-plan-state.json`).
    - Grouped moved-quote count on `QC:ON` with both countries, the intercompany `NOT IN` and accepted, `LIMIT 51`: 51 groups (`t6-quote-state.json`).
    - `SetupEntityAccess` by `Parent.Name`: 24 rows (`t6-sea.json`).
    - The Mexican `Nuevo León` / `NL` spelling (`t6-mx.json`).
    - No load shared with the org-wide group (`t6-orgshare.json`).
    - The two validation rules (`t6-vr-cs.json`, `t6-vr-contact.json`).

**Open issues**

- **Stage 2 and the 50-group cap (controller ruling 2026-09-15).** On `QC:ON` the moved-quote count alone passes 50 groups in 365 days (51 rows at `LIMIT 51`). The groups come back ordered by distinct loads, so the top 10 by quote loads moved is exact; a 51st group therefore sets `Tally.groupCapped`, which `finish` turns into `truncated` only for stage 1 (`top` null). Stage 2 shows "The list may be incomplete." only after its 500-plan cap or the query-row guard. Cost if wrong: a carrier whose split legs alone would lift it into the top 10 can be missed without the note. No test in this task builds 51 carrier groups (note 8: each quote carrier needs its own carrier service, contact and profile). After Step 7, if the printed fixture budget leaves room for 51 quote carriers on one state-lane load, add `stateLaneIgnoresTheGroupCap` to `CarrierLeadServiceTest` (51 accepted quotes from 51 carriers on `QC:ON`; assert stage `State lane`, 10 leads and `truncated` false) in the Step 7 deploy; otherwise write "stage 2 group-cap rule untested (fixture budget)" in the report, and Task 11 carries it into the Outcome as a known issue.
- **The fixture budget is not measured yet.** Task 1 records the queries per `legLoad` and `plan`, and Step 7 gives the fallback for the top 10 test. `stateLaneCountsTheLegsOfSplitShipments` creates one load before `Test.startTest()` and one leg load plus the plan inside it.
- **A radius first search is not tested in stage 2.** Its city-key mapping (`deepPrecision`) sits in `LaneQueries` and is tested by Task 5; `stateLane` only checks for two `PROVINCE` ends.


---

### Task 7: Carriers to ask UI — `c/carrierLeadRules`, `c-carrier-leads`, Lane Benchmark, the RFP lane panel and the lane table's no rate tag

**Files:**

- Create: `force-app/main/default/lwc/carrierLeadRules/carrierLeadRules.js`, `carrierLeadRules.js-meta.xml`, `__tests__/carrierLeadRules.test.js`
- Create: `force-app/main/default/lwc/carrierLeads/carrierLeads.js`, `carrierLeads.html`, `carrierLeads.css`, `carrierLeads.js-meta.xml`, `__tests__/carrierLeads.test.js`
- Modify: `force-app/main/default/lwc/rfpLaneTable/rfpLaneTable.js` (`hasNoRate` after `historyTitle`, lines 76–91; `viewRows` line 273)
- Modify: `force-app/main/default/lwc/rfpLaneTable/rfpLaneTable.html` (History cell, lines 102–104)
- Modify: `force-app/main/default/lwc/rfpLaneTable/__tests__/rfpLaneTable.test.js` (`histOf` before line 112; the assertions at lines 203–205 and 259–261; one test after line 262)
- Modify: `force-app/main/default/lwc/laneBenchmark/laneBenchmark.js` (import after line 15; fields after line 51; getter after line 122; `runSearch` lines 268–272)
- Modify: `force-app/main/default/lwc/laneBenchmark/laneBenchmark.html` (the card after the statistics, line 105)
- Modify: `force-app/main/default/lwc/laneBenchmark/__tests__/laneBenchmark.test.js` (import after line 6; mock after line 45; `beforeEach` line 136; three tests before line 608)
- Modify: `force-app/main/default/lwc/rfpLanePanel/rfpLanePanel.js` (import after line 26; fields after line 133; getters after line 246; `syncFromLane` line 254; `loadHistory` lines 308–328)
- Modify: `force-app/main/default/lwc/rfpLanePanel/rfpLanePanel.html` (the card after the `history-scroll` block, lines 207–215)
- Modify: `force-app/main/default/lwc/rfpLanePanel/__tests__/rfpLanePanel.test.js` (import after line 8; mock after line 30; `beforeEach` line 149; a `describe("carriers to ask")` block before the last line, 822)
- Modify: `force-app/main/default/lwc/rfpTool/__tests__/rfpTool.test.js` (one `jest.mock` after line 133, keeping that file's "every Apex module the workbench tree imports is listed" rule)
- Modify: `manifest/package.xml` (`carrierLeadRules`, `carrierLeads` after `routeMap`, line 58)
- Unchanged, verified in Step 23: `force-app/main/default/lwc/rfpTool/rfpTool.js` (554 lines) and `force-app/main/default/lwc/rfpTool/rfpTool.html`

**Interfaces:**

- Consumes:
  - Task 6: `@salesforce/apex/CarrierLeadController.findCarrierLeads` — `findCarrierLeads({ requestJson, attempt })`, `@AuraEnabled(cacheable=true)`, returns `CarrierLeadResult` `{ leads: [{ carrierId, name, loadsMoved, loadsQuoted, lastSeen, sources, blacklisted, canOpen }], stage, stateLaneLabel, truncated }` with `stage` one of `Same lane`, `State lane`, `None` (`CarrierLeadResult.SAME_LANE`, `STATE_LANE`, `NONE`), `sources` items `Quote` / `Split leg`, and `lastSeen` serialized as an ISO date string (`"2026-07-30"`); a `LaneSearchException` or `QueryException` arrives as an `AuraHandledException` (`{ body: { message } }`). Class access on `Lane_Benchmark_User` and `RFP_Tool_User` (Task 6).
  - Existing: `LaneBenchmarkController.search` → `LaneSearchResult.statsByCurrency` `{ <code>: { count, countNonZero, min, max, avg, median, ratePerMileMedian } }`; `c/rfpPricing` `historyKey(lane)` and `historyRequest(lane)`; `c/laneBenchmarkFilters` `DEFAULT_FILTERS.currencyIsoCode` (`null` without a currency filter); `RFP_Lane__c.Hist_Status__c` (`Pending`, `Unresolved`, `No match`, `Done`, `Failed`) and `Hist_Median__c`.
- Produces:
  - `c/carrierLeadRules` (module without template): `hasBothKeys(requestJson)`, `noRate(statsByCurrency, currencyCode)`, `directMedian(statsByCurrency, currencyCode)` — Task 10 imports `hasBothKeys` and `directMedian`.
  - `c-carrier-leads`: `@api requestJson` (setter asks again when the value changes and is not blank), `@api currencyCode`; data-ids `leads-card`, `leads-loading`, `leads-error`, `leads-retry`, `leads-heading`, `leads-stage2`, `leads-empty`, `lead-row`, `lead-link`, `lead-name`, `lead-blacklisted`, `lead-counts`, `lead-sources`, `leads-truncated`.
  - `c-lane-benchmark`: fields `lastRequestJson` and `lastCurrency`, getter `showCarrierLeads`, and `<c-carrier-leads data-id="carrier-leads" request-json={lastRequestJson} currency-code={lastCurrency}>` between `c-lane-benchmark-stats` and the route map — Task 10 reuses `lastRequestJson` and `lastCurrency`.
  - `c-rfp-lane-panel`: fields `historyStats` and `historyLoaded`, getters `historyRequestJson` and `showCarrierLeads`, and `<c-carrier-leads data-id="carrier-leads" request-json={historyRequestJson} currency-code={currency}>` right after the `history-scroll` block — Task 10 reuses `historyRequestJson` and `historyStats`.
  - `c-rfp-lane-table`: every view row gets `noRate`; the History cell shows `<span data-id="no-rate-tag" class="slds-badge slds-m-left_xx-small">no rate</span>` when it is true.
  - `manifest/package.xml`: `LightningComponentBundle` members `carrierLeadRules` and `carrierLeads`.

**Before you start:** Task 6 is committed and deployed to `sandbox`: `c-carrier-leads` imports `CarrierLeadController.findCarrierLeads`, and a bundle that imports a missing Apex method fails to deploy (Step 24). Tasks 1–6 add no Jest test. Print the baselines this task's expected numbers build on:

Run: `npm run test:unit 2>&1 | grep -E "✕|^(Tests|Test Suites):"; wc -l force-app/main/default/lwc/laneBenchmark/laneBenchmark.js force-app/main/default/lwc/rfpLanePanel/rfpLanePanel.js force-app/main/default/lwc/rfpLaneTable/rfpLaneTable.js force-app/main/default/lwc/rfpTool/rfpTool.js`

Expected: no `✕` line, `Test Suites: 39 passed, 39 total`, `Tests: 363 passed, 363 total`; `352`, `592`, `493` and `554` lines. When your printed counts differ, carry your own numbers: this task adds 2 suites and 22 tests (rules 7, card 8, lane table 1, Lane Benchmark 3, lane panel 3). A warm Jest run takes about 5 s; a cold cache can take minutes, so start the full run with `run_in_background` (redirect to a log) and poll the log. Give every single-suite path a trailing slash (`lwc/laneBenchmark/`, `lwc/rfpTool/`): without it the pattern also runs `laneBenchmarkCsv`, `laneBenchmarkFilters`, … and `rfpToolbar`.

- [ ] **Step 1: `c/carrierLeadRules` — write the failing tests**

Create `force-app/main/default/lwc/carrierLeadRules/__tests__/carrierLeadRules.test.js`:

```js
import { hasBothKeys, noRate, directMedian } from "c/carrierLeadRules";

const STATS = {
  CAD: { count: 3, countNonZero: 2, median: 1950 },
  USD: { count: 1, countNonZero: 0, median: null }
};
const request = (originKey, destinationKey) =>
  JSON.stringify({ originKey, destinationKey, originPrecision: "CITY" });

describe("hasBothKeys", () => {
  it("is true only when both ends carry a place key", () => {
    expect(hasBothKeys(request("montreal|qc|ca", "toronto|on|ca"))).toBe(true);
    expect(hasBothKeys(request("montreal|qc|ca", null))).toBe(false);
    expect(hasBothKeys(request("  ", "toronto|on|ca"))).toBe(false);
    expect(
      hasBothKeys(JSON.stringify({ destinationKey: "toronto|on|ca" }))
    ).toBe(false);
  });
  it("is false for a blank or unreadable request", () => {
    expect(hasBothKeys(null)).toBe(false);
    expect(hasBothKeys(undefined)).toBe(false);
    expect(hasBothKeys("")).toBe(false);
    expect(hasBothKeys("{not json")).toBe(false);
    expect(hasBothKeys("null")).toBe(false);
  });
});

describe("noRate", () => {
  it("reads only the bucket of the currency it is given", () => {
    expect(noRate(STATS, "CAD")).toBe(false);
    // a bucket whose rows all have a 0 total, and a currency with no bucket
    expect(noRate(STATS, "USD")).toBe(true);
    expect(noRate(STATS, "MXN")).toBe(true);
  });
  it("looks at every bucket when no currency is given", () => {
    expect(noRate(STATS, null)).toBe(false);
    expect(noRate(STATS, "")).toBe(false);
    expect(noRate({ USD: { count: 2, countNonZero: 0 } }, undefined)).toBe(
      true
    );
  });
  it("counts missing statistics as no rate", () => {
    expect(noRate(null, "CAD")).toBe(true);
    expect(noRate(undefined, null)).toBe(true);
    expect(noRate({}, "CAD")).toBe(true);
    expect(noRate({}, null)).toBe(true);
  });
});

describe("directMedian", () => {
  it("gives the median of the priced bucket in that currency", () => {
    expect(directMedian(STATS, "CAD")).toBe(1950);
  });
  it("gives null without a priced bucket, a currency or statistics", () => {
    expect(directMedian(STATS, "USD")).toBeNull();
    expect(directMedian(STATS, "MXN")).toBeNull();
    expect(directMedian(STATS, null)).toBeNull();
    expect(directMedian(null, "CAD")).toBeNull();
  });
});
```

- [ ] **Step 2: Run them and watch them fail**

Run: `npm run test:unit -- force-app/main/default/lwc/carrierLeadRules/ 2>&1 | grep -E "Cannot find module|^(Tests|Test Suites):"`

Expected: `Cannot find module 'c/carrierLeadRules' from 'force-app/main/default/lwc/carrierLeadRules/__tests__/carrierLeadRules.test.js'`, `Test Suites: 1 failed, 1 total`, `Tests: 0 total`.

- [ ] **Step 3: Write the module**

Create `force-app/main/default/lwc/carrierLeadRules/carrierLeadRules.js`:

```js
/**
 * When Carriers to ask may run (spec §3, D2 and D3), decided from what the screen already has:
 * the request JSON its first search sent and that search's statsByCurrency. No Apex here.
 */

const filled = (value) => typeof value === "string" && value.trim() !== "";
const priced = (bucket) => !!bucket && bucket.countNonZero > 0;

/** True when the request names a place key on both ends; false for blank or unreadable JSON. */
export function hasBothKeys(requestJson) {
  if (!filled(requestJson)) {
    return false;
  }
  try {
    const request = JSON.parse(requestJson);
    return (
      !!request && filled(request.originKey) && filled(request.destinationKey)
    );
  } catch {
    return false;
  }
}

/**
 * True when the first search found no priced carrier rate (a total other than 0) in the pricing
 * currency (D2): that currency's bucket when a code is given, every bucket when it is blank.
 */
export function noRate(statsByCurrency, currencyCode) {
  if (!statsByCurrency) {
    return true;
  }
  if (filled(currencyCode)) {
    return !priced(statsByCurrency[currencyCode]);
  }
  return !Object.values(statsByCurrency).some((bucket) => priced(bucket));
}

/** The first search's median in that currency, or null when it has no priced rate there. */
export function directMedian(statsByCurrency, currencyCode) {
  const bucket =
    statsByCurrency && filled(currencyCode)
      ? statsByCurrency[currencyCode]
      : null;
  return priced(bucket) && bucket.median !== undefined ? bucket.median : null;
}
```

Create `force-app/main/default/lwc/carrierLeadRules/carrierLeadRules.js-meta.xml` (a module without a template, like `c/distanceUnit`):

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<LightningComponentBundle xmlns="http://soap.sforce.com/2006/04/metadata">
  <apiVersion>64.0</apiVersion>
  <isExposed>false</isExposed>
</LightningComponentBundle>
```

- [ ] **Step 4: Run the rules suite to pass**

Run: `npm run test:unit -- force-app/main/default/lwc/carrierLeadRules/ 2>&1 | grep -E "✕|^(Tests|Test Suites):"`

Expected: no `✕` line, `Test Suites: 1 passed, 1 total`, `Tests: 7 passed, 7 total`.

- [ ] **Step 5: `c-carrier-leads` — write the failing tests**

Create `force-app/main/default/lwc/carrierLeads/__tests__/carrierLeads.test.js`:

```js
import { createElement } from "lwc";
import CarrierLeads from "c/carrierLeads";
import findCarrierLeads from "@salesforce/apex/CarrierLeadController.findCarrierLeads";

jest.mock(
  "@salesforce/apex/CarrierLeadController.findCarrierLeads",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const flush = () => Promise.resolve().then(() => Promise.resolve());

const REQUEST = JSON.stringify({
  originKey: "montreal|qc|ca",
  destinationKey: "toronto|on|ca",
  originPrecision: "CITY",
  destinationPrecision: "CITY"
});
const OTHER_REQUEST = JSON.stringify({
  originKey: "montreal|qc|ca",
  destinationKey: "ottawa|on|ca",
  originPrecision: "CITY",
  destinationPrecision: "CITY"
});

const ACME = {
  carrierId: "001000000000001AAA",
  name: "Acme Transport",
  loadsMoved: 4,
  loadsQuoted: 9,
  lastSeen: "2026-07-30",
  sources: ["Quote", "Split leg"],
  blacklisted: false,
  canOpen: true
};
const FLETES = {
  carrierId: "001000000000002AAA",
  name: "Fletes Mex",
  loadsMoved: 0,
  loadsQuoted: 2,
  lastSeen: "2025-11-02",
  sources: ["Quote"],
  blacklisted: true,
  canOpen: false
};
/** A CarrierLeadResult as CarrierLeadController.findCarrierLeads returns it. */
const SAME_LANE = {
  leads: [ACME, FLETES],
  stage: "Same lane",
  stateLaneLabel: null,
  truncated: false
};

const field = (el, id) => el.shadowRoot.querySelector(`[data-id="${id}"]`);
const textOf = (el, id) => field(el, id).textContent.trim();
const rowsOf = (el) => el.shadowRoot.querySelectorAll('[data-id="lead-row"]');
const inRow = (row, id) => row.querySelector(`[data-id="${id}"]`);

async function mount(props = {}) {
  const el = createElement("c-carrier-leads", { is: CarrierLeads });
  Object.assign(el, { currencyCode: "CAD", requestJson: REQUEST, ...props });
  document.body.appendChild(el);
  await flush();
  return el;
}

describe("c-carrier-leads", () => {
  beforeEach(() => {
    findCarrierLeads.mockResolvedValue(SAME_LANE);
  });
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("shows a spinner while it asks for the lane's carriers with attempt 0", async () => {
    findCarrierLeads.mockReturnValue(new Promise(() => {}));
    const el = await mount();
    expect(findCarrierLeads).toHaveBeenCalledTimes(1);
    expect(findCarrierLeads).toHaveBeenCalledWith({
      requestJson: REQUEST,
      attempt: 0
    });
    expect(field(el, "leads-card").title).toBe("Carriers to ask");
    expect(field(el, "leads-loading")).not.toBeNull();
    expect(rowsOf(el).length).toBe(0);
    expect(field(el, "leads-empty")).toBeNull();
  });

  it("lists each carrier with its counts and sources, a link only when the account can be opened and a badge when blacklisted", async () => {
    const el = await mount();
    expect(field(el, "leads-loading")).toBeNull();
    expect(textOf(el, "leads-heading")).toBe(
      "No carrier rate on this lane in CAD. These carriers quoted or moved it before; amounts are not shown."
    );
    const rows = rowsOf(el);
    expect(rows.length).toBe(2);

    const link = inRow(rows[0], "lead-link");
    expect(link.textContent.trim()).toBe("Acme Transport");
    expect(link.getAttribute("href")).toBe(
      "/lightning/r/Account/001000000000001AAA/view"
    );
    expect(inRow(rows[0], "lead-name")).toBeNull();
    expect(inRow(rows[0], "lead-blacklisted")).toBeNull();
    expect(inRow(rows[0], "lead-counts").textContent.trim()).toBe(
      "4 moved · 9 quoted · last seen 2026-07-30"
    );
    expect(inRow(rows[0], "lead-sources").textContent.trim()).toBe(
      "Quote, Split leg"
    );

    // not readable by this user: the name as plain text, no link
    expect(inRow(rows[1], "lead-link")).toBeNull();
    expect(inRow(rows[1], "lead-name").textContent.trim()).toBe("Fletes Mex");
    expect(inRow(rows[1], "lead-blacklisted").textContent.trim()).toBe(
      "Blacklisted"
    );
    expect(inRow(rows[1], "lead-counts").textContent.trim()).toBe(
      "0 moved · 2 quoted · last seen 2025-11-02"
    );

    expect(field(el, "leads-stage2")).toBeNull();
    expect(field(el, "leads-empty")).toBeNull();
    expect(field(el, "leads-truncated")).toBeNull();
    expect(field(el, "leads-error")).toBeNull();
  });

  it("names no currency in the heading when the search had no currency filter", async () => {
    const el = await mount({ currencyCode: null });
    expect(textOf(el, "leads-heading")).toBe(
      "No carrier rate on this lane. These carriers quoted or moved it before; amounts are not shown."
    );
  });

  it("words a state lane answer as the top carriers on that lane", async () => {
    findCarrierLeads.mockResolvedValue({
      leads: [ACME],
      stage: "State lane",
      stateLaneLabel: "QC to ON",
      truncated: false
    });
    const el = await mount();
    expect(textOf(el, "leads-stage2")).toBe(
      "No carrier on this exact lane. Top carriers on QC to ON over the last year."
    );
    expect(field(el, "leads-heading")).toBeNull();
    expect(rowsOf(el).length).toBe(1);
  });

  it("says when no carrier was found, and when the list may be incomplete", async () => {
    findCarrierLeads.mockResolvedValue({
      leads: [],
      stage: "None",
      stateLaneLabel: null,
      truncated: true
    });
    const el = await mount();
    expect(textOf(el, "leads-empty")).toBe(
      "No carrier found on this lane or on its state or province lane."
    );
    expect(textOf(el, "leads-truncated")).toBe("The list may be incomplete.");
    expect(field(el, "leads-heading")).toBeNull();
    expect(field(el, "leads-stage2")).toBeNull();
    expect(rowsOf(el).length).toBe(0);
  });

  it("shows a failure with Retry, which asks again with the next attempt", async () => {
    findCarrierLeads
      .mockRejectedValueOnce({ body: { message: "Unknown place key" } })
      .mockRejectedValueOnce(new Error("Network down"))
      .mockResolvedValueOnce(SAME_LANE);
    const el = await mount();
    expect(textOf(el, "leads-error")).toBe("Unknown place key");
    expect(rowsOf(el).length).toBe(0);

    field(el, "leads-retry").click();
    await flush();
    expect(findCarrierLeads.mock.calls[1][0]).toEqual({
      requestJson: REQUEST,
      attempt: 1
    });
    expect(textOf(el, "leads-error")).toBe(
      "The carriers to ask could not be loaded."
    );

    field(el, "leads-retry").click();
    await flush();
    expect(findCarrierLeads.mock.calls[2][0]).toEqual({
      requestJson: REQUEST,
      attempt: 2
    });
    expect(field(el, "leads-error")).toBeNull();
    expect(rowsOf(el).length).toBe(2);

    // another lane starts again from attempt 0, so it can use the cache
    el.requestJson = OTHER_REQUEST;
    await flush();
    expect(findCarrierLeads.mock.calls[3][0]).toEqual({
      requestJson: OTHER_REQUEST,
      attempt: 0
    });
  });

  it("drops an answer that lands after the request changed", async () => {
    let releaseFirst;
    findCarrierLeads
      .mockReturnValueOnce(
        new Promise((resolve) => {
          releaseFirst = resolve;
        })
      )
      .mockResolvedValueOnce({
        leads: [FLETES],
        stage: "State lane",
        stateLaneLabel: "QC to ON",
        truncated: false
      });
    const el = await mount();
    el.requestJson = OTHER_REQUEST;
    await flush();
    releaseFirst(SAME_LANE);
    await flush();
    await flush();
    expect(findCarrierLeads).toHaveBeenCalledTimes(2);
    expect(findCarrierLeads.mock.calls[1][0].requestJson).toBe(OTHER_REQUEST);
    const rows = rowsOf(el);
    expect(rows.length).toBe(1);
    expect(inRow(rows[0], "lead-name").textContent.trim()).toBe("Fletes Mex");
    expect(field(el, "leads-stage2")).not.toBeNull();
  });

  it("asks again only when the request changes and is not blank", async () => {
    const el = await mount();
    el.requestJson = REQUEST;
    await flush();
    expect(findCarrierLeads).toHaveBeenCalledTimes(1);

    el.requestJson = "";
    await flush();
    expect(findCarrierLeads).toHaveBeenCalledTimes(1);
    expect(rowsOf(el).length).toBe(0);
    expect(field(el, "leads-loading")).toBeNull();
  });
});
```

- [ ] **Step 6: Run them and watch them fail**

Run: `npm run test:unit -- force-app/main/default/lwc/carrierLeads/ 2>&1 | grep -E "Cannot find module|^(Tests|Test Suites):"`

Expected: `Cannot find module 'c/carrierLeads' from 'force-app/main/default/lwc/carrierLeads/__tests__/carrierLeads.test.js'`, `Test Suites: 1 failed, 1 total`, `Tests: 0 total`.

- [ ] **Step 7: Write the card**

Create `force-app/main/default/lwc/carrierLeads/carrierLeads.js`:

```js
import { LightningElement, api } from "lwc";
import findCarrierLeads from "@salesforce/apex/CarrierLeadController.findCarrierLeads";

const STATE_LANE = "State lane";
const LOAD_FAILED = "The carriers to ask could not be loaded.";
const EMPTY_TEXT =
  "No carrier found on this lane or on its state or province lane.";

/**
 * Carriers to ask (spec §3 and §7): carrier names, never amounts, for a lane whose first search
 * found no carrier rate. The parent decides when the card shows (c/carrierLeadRules) and passes
 * the request JSON its first search sent; the card asks CarrierLeadController once per request.
 * The Apex method is cacheable, so the same request (a lane opened again) is served from the
 * browser cache; Retry sends attempt + 1 so it reaches the server.
 */
export default class CarrierLeads extends LightningElement {
  /** The code the heading names: the lane's currency, or Lane Benchmark's currency filter (null without one). */
  @api currencyCode;

  _requestJson = null;
  /** The CarrierLeadResult for the current request, null until it answers. */
  result = null;
  error = null;
  loading = false;
  /** 0 for a new request; each Retry adds 1. */
  attempt = 0;
  /** Bumped by every call; an answer carrying an older number is dropped. */
  seq = 0;

  @api
  get requestJson() {
    return this._requestJson;
  }
  set requestJson(value) {
    const next =
      typeof value === "string" && value.trim() !== "" ? value : null;
    if (next === this._requestJson) {
      return;
    }
    this._requestJson = next;
    this.attempt = 0;
    this.load();
  }

  async load() {
    const seq = ++this.seq;
    const requestJson = this._requestJson;
    this.result = null;
    this.error = null;
    if (!requestJson) {
      this.loading = false;
      return;
    }
    this.loading = true;
    try {
      const result = await findCarrierLeads({
        requestJson,
        attempt: this.attempt
      });
      if (seq === this.seq) {
        this.result = result || null;
      }
    } catch (e) {
      if (seq === this.seq) {
        this.error = (e && e.body && e.body.message) || LOAD_FAILED;
      }
    } finally {
      if (seq === this.seq) {
        this.loading = false;
      }
    }
  }

  handleRetry() {
    this.attempt += 1;
    this.load();
  }

  get leads() {
    return (this.result && this.result.leads) || [];
  }
  get hasLeads() {
    return this.leads.length > 0;
  }
  get isStateLane() {
    return !!this.result && this.result.stage === STATE_LANE;
  }
  get showHeading() {
    return this.hasLeads && !this.isStateLane;
  }
  get showStateLane() {
    return this.hasLeads && this.isStateLane;
  }
  get showEmpty() {
    return !!this.result && !this.hasLeads;
  }
  get truncated() {
    return !!(this.result && this.result.truncated);
  }
  get heading() {
    const code = this.currencyCode ? ` in ${this.currencyCode}` : "";
    return `No carrier rate on this lane${code}. These carriers quoted or moved it before; amounts are not shown.`;
  }
  get stateLaneText() {
    return `No carrier on this exact lane. Top carriers on ${this.result?.stateLaneLabel} over the last year.`;
  }
  get emptyText() {
    return EMPTY_TEXT;
  }
  /** One line per carrier: the link only when the user can read the account (lead.canOpen). */
  get leadRows() {
    return this.leads.map((lead, index) => ({
      key: lead.carrierId || `lead-${index}`,
      name: lead.name,
      canOpen: !!(lead.canOpen && lead.carrierId),
      url: `/lightning/r/Account/${lead.carrierId}/view`,
      blacklisted: !!lead.blacklisted,
      counts: `${lead.loadsMoved} moved · ${lead.loadsQuoted} quoted · last seen ${lead.lastSeen || "—"}`,
      sources: (lead.sources || []).join(", ")
    }));
  }
}
```

Create `force-app/main/default/lwc/carrierLeads/carrierLeads.html`:

```html
<template>
  <lightning-card
    data-id="leads-card"
    title="Carriers to ask"
    icon-name="standard:account"
  >
    <div class="slds-p-horizontal_medium">
      <template lwc:if={loading}>
        <div class="slds-is-relative leads-loading">
          <lightning-spinner
            data-id="leads-loading"
            size="small"
            alternative-text="Finding carriers to ask"
          ></lightning-spinner>
        </div>
      </template>
      <template lwc:if={error}>
        <div class="slds-grid slds-grid_vertical-align-center">
          <p data-id="leads-error" class="slds-text-color_error" role="alert">
            {error}
          </p>
          <lightning-button
            data-id="leads-retry"
            class="slds-m-left_x-small"
            label="Retry"
            onclick={handleRetry}
          ></lightning-button>
        </div>
      </template>
      <template lwc:if={showHeading}>
        <p data-id="leads-heading" class="slds-m-bottom_x-small">{heading}</p>
      </template>
      <template lwc:if={showStateLane}>
        <p data-id="leads-stage2" class="slds-m-bottom_x-small">
          {stateLaneText}
        </p>
      </template>
      <template lwc:if={showEmpty}>
        <p data-id="leads-empty" class="slds-text-color_weak">{emptyText}</p>
      </template>
      <template lwc:if={hasLeads}>
        <ul class="slds-has-dividers_bottom-space">
          <template for:each={leadRows} for:item="lead">
            <li key={lead.key} data-id="lead-row" class="slds-item">
              <template lwc:if={lead.canOpen}>
                <a
                  data-id="lead-link"
                  class="slds-text-title_bold"
                  href={lead.url}
                  target="_blank"
                  rel="noopener"
                  >{lead.name}</a
                >
              </template>
              <template lwc:else>
                <span data-id="lead-name" class="slds-text-title_bold"
                  >{lead.name}</span
                >
              </template>
              <template lwc:if={lead.blacklisted}>
                <span
                  data-id="lead-blacklisted"
                  class="slds-badge slds-theme_error slds-m-left_x-small"
                  >Blacklisted</span
                >
              </template>
              <p data-id="lead-counts" class="slds-text-body_small">
                {lead.counts}
              </p>
              <p
                data-id="lead-sources"
                class="slds-text-body_small slds-text-color_weak"
              >
                {lead.sources}
              </p>
            </li>
          </template>
        </ul>
      </template>
      <template lwc:if={truncated}>
        <p
          data-id="leads-truncated"
          class="slds-text-body_small slds-text-color_weak slds-m-top_x-small"
        >
          The list may be incomplete.
        </p>
      </template>
    </div>
  </lightning-card>
</template>
```

Create `force-app/main/default/lwc/carrierLeads/carrierLeads.css`:

```css
/* Room for the small spinner while the card has nothing else to show. */
.leads-loading {
  min-height: 3rem;
}
```

Create `force-app/main/default/lwc/carrierLeads/carrierLeads.js-meta.xml`:

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<LightningComponentBundle xmlns="http://soap.sforce.com/2006/04/metadata">
  <apiVersion>64.0</apiVersion>
  <isExposed>false</isExposed>
</LightningComponentBundle>
```

The card has no `c-help-hint`: `helpContent/__tests__/placement.test.js` lists the hint hosts in `EXPECTED` and `carrierLeads` is not one; Task 11 documents the card on the `lb-stats`, `rfp-pricing` and `rfp-inline` pages the existing hints already open.

- [ ] **Step 8: Run the card suite to pass**

Run: `npm run test:unit -- force-app/main/default/lwc/carrierLeads/ 2>&1 | grep -E "✕|^(Tests|Test Suites):"`

Expected: no `✕` line, `Test Suites: 1 passed, 1 total`, `Tests: 8 passed, 8 total`.

- [ ] **Step 9: Lane table — write the failing tests**

The History cell's text now ends with the tag on a Done lane without a median, so the two tests that read that cell's whole `textContent` switch to a helper that separates the text from the tag.

In `force-app/main/default/lwc/rfpLaneTable/__tests__/rfpLaneTable.test.js`, replace:

```js
const headerTexts = (el) =>
```

with:

```js
/** The History cell's text without its no rate tag, and the tag's text (null without one). */
function histOf(row) {
  const cell = row.querySelector('[data-id="hist"]');
  const tag = cell.querySelector('[data-id="no-rate-tag"]');
  return {
    text: cell.textContent.replace(tag ? tag.textContent : "", "").trim(),
    tag: tag ? tag.textContent.trim() : null
  };
}

const headerTexts = (el) =>
```

In `force-app/main/default/lwc/rfpLaneTable/__tests__/rfpLaneTable.test.js`, replace:

```js
    expect(rows[1].querySelector('[data-id="hist"]').textContent.trim()).toBe(
      "1 load + 1 bid · no median"
    );
```

with:

```js
    expect(histOf(rows[1])).toEqual({
      text: "1 load + 1 bid · no median",
      tag: "no rate"
    });
```

In `force-app/main/default/lwc/rfpLaneTable/__tests__/rfpLaneTable.test.js`, replace:

```js
    expect(
      rowsOf(el)[0].querySelector('[data-id="hist"]').textContent.trim()
    ).toBe("3 · no median");
  });
```

with:

```js
    expect(histOf(rowsOf(el)[0])).toEqual({
      text: "3 · no median",
      tag: "no rate"
    });
  });

  it("tags a lane with no rate when its history found no match or no priced median", async () => {
    const el = await mount({
      lanes: [
        {
          ...RESOLVED_LANE,
          Id: "a0L00000011",
          Hist_Status__c: "No match",
          Hist_Count__c: 0,
          Hist_Median__c: null
        },
        { ...RESOLVED_LANE, Id: "a0L00000012", Hist_Median__c: null },
        { ...RESOLVED_LANE, Id: "a0L00000013", Hist_Median__c: "" },
        { ...RESOLVED_LANE, Id: "a0L00000014" },
        {
          ...RESOLVED_LANE,
          Id: "a0L00000015",
          Hist_Status__c: "Pending",
          Hist_Median__c: null
        }
      ]
    });
    const rows = [...rowsOf(el)];
    expect(rows.map((row) => histOf(row).tag)).toEqual([
      "no rate",
      "no rate",
      "no rate",
      null,
      null
    ]);
    expect(histOf(rows[0]).text).toBe("No match");
    expect(histOf(rows[3]).text).toBe("2 · median 2000.00");
    expect(histOf(rows[4]).text).toBe("Pending");
  });
```

- [ ] **Step 10: Run the table suite and watch it fail**

Run: `npm run test:unit -- force-app/main/default/lwc/rfpLaneTable/ 2>&1 | grep -E "✕|^(Tests|Test Suites):"`

Expected: `✕ splits the history count into loads and bids once bids were counted`, `✕ says so when a Done snapshot found loads but no median`, `✕ tags a lane with no rate when its history found no match or no priced median`, `Tests: 3 failed, 24 passed, 27 total` (no cell has a `no-rate-tag` yet, so `histOf(...).tag` is `null`).

- [ ] **Step 11: Lane table — add the tag**

In `force-app/main/default/lwc/rfpLaneTable/rfpLaneTable.js`, replace:

```js
    ? `${parts.map(([k, v]) => `${k} ${v}`).join(" · ")}${precision}`
    : "";
}
```

with:

```js
    ? `${parts.map(([k, v]) => `${k} ${v}`).join(" · ")}${precision}`
    : "";
}

/**
 * The no rate tag (spec §7): the stored snapshot matched nothing (No match), or it matched rows
 * but none priced in the lane's currency (Done with a blank median).
 */
function hasNoRate(lane) {
  const median = lane.Hist_Median__c;
  return (
    lane.Hist_Status__c === "No match" ||
    (lane.Hist_Status__c === "Done" &&
      (median === null || median === undefined || median === ""))
  );
}
```

In `force-app/main/default/lwc/rfpLaneTable/rfpLaneTable.js`, replace:

```js
      histTitle: historyTitle(l),
```

with:

```js
      histTitle: historyTitle(l),
      noRate: hasNoRate(l),
```

In `force-app/main/default/lwc/rfpLaneTable/rfpLaneTable.html`, replace:

```html
            <td data-id="hist" class="slds-cell-wrap" title={r.histTitle}>
              {r.histText}
            </td>
```

with:

```html
            <td data-id="hist" class="slds-cell-wrap" title={r.histTitle}>
              {r.histText}
              <template lwc:if={r.noRate}>
                <span
                  data-id="no-rate-tag"
                  class="slds-badge slds-m-left_xx-small"
                  >no rate</span
                >
              </template>
            </td>
```

- [ ] **Step 12: Run the table suite to pass**

Run: `npm run test:unit -- force-app/main/default/lwc/rfpLaneTable/ 2>&1 | grep -E "✕|^(Tests|Test Suites):"`

Expected: no `✕` line, `Tests: 27 passed, 27 total`.

- [ ] **Step 13: Lane Benchmark — write the failing tests**

In `force-app/main/default/lwc/laneBenchmark/__tests__/laneBenchmark.test.js`, replace:

```js
import truckRoute from "@salesforce/apex/LaneBenchmarkController.truckRoute";
```

with:

```js
import truckRoute from "@salesforce/apex/LaneBenchmarkController.truckRoute";
import findCarrierLeads from "@salesforce/apex/CarrierLeadController.findCarrierLeads";
```

In `force-app/main/default/lwc/laneBenchmark/__tests__/laneBenchmark.test.js`, replace:

```js
jest.mock(
  "@salesforce/apex/LaneBenchmarkController.geocode",
  () => ({ default: jest.fn().mockResolvedValue([]) }),
  { virtual: true }
);
```

with:

```js
jest.mock(
  "@salesforce/apex/LaneBenchmarkController.geocode",
  () => ({ default: jest.fn().mockResolvedValue([]) }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/CarrierLeadController.findCarrierLeads",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
```

In `force-app/main/default/lwc/laneBenchmark/__tests__/laneBenchmark.test.js`, replace:

```js
    truckRoute.mockResolvedValue(ROUTE_VIEW);
  });
```

with:

```js
    truckRoute.mockResolvedValue(ROUTE_VIEW);
    findCarrierLeads.mockResolvedValue({
      leads: [],
      stage: "None",
      stateLaneLabel: null,
      truncated: false
    });
  });
```

In `force-app/main/default/lwc/laneBenchmark/__tests__/laneBenchmark.test.js`, replace:

```js
  it("starts from the saved unit, follows the distance unit channel and unsubscribes when removed", async () => {
```

with:

```js
  it("shows Carriers to ask under the statistics when the search has no rate in the currency filter", async () => {
    const el = await mount();
    pickLane(el);
    el.shadowRoot
      .querySelector("c-lane-benchmark-filters")
      .dispatchEvent(
        new CustomEvent("filterschange", { detail: { currencyIsoCode: "USD" } })
      );
    applySearch(el);
    await settle();
    // RESULT is priced in CAD only, so the USD filter has no rate
    const leads = el.shadowRoot.querySelector('[data-id="carrier-leads"]');
    expect(leads).not.toBeNull();
    const sent = search.mock.calls[0][0].requestJson;
    expect(leads.requestJson).toBe(sent);
    expect(leads.currencyCode).toBe("USD");
    expect(findCarrierLeads).toHaveBeenCalledWith({
      requestJson: sent,
      attempt: 0
    });
    const order = [
      ...el.shadowRoot.querySelectorAll(
        "c-lane-benchmark-stats, c-carrier-leads, c-route-map, c-lane-benchmark-results"
      )
    ].map((node) => node.tagName.toLowerCase());
    expect(order).toEqual([
      "c-lane-benchmark-stats",
      "c-carrier-leads",
      "c-route-map",
      "c-lane-benchmark-results"
    ]);
  });

  it("shows Carriers to ask without a filter only when no currency has a rate, and never without both place keys", async () => {
    const el = await mount();
    pickLane(el);
    applySearch(el);
    await settle();
    // no currency filter: the CAD rate counts
    expect(
      el.shadowRoot.querySelector("c-lane-benchmark-stats")
    ).not.toBeNull();
    expect(el.shadowRoot.querySelector('[data-id="carrier-leads"]')).toBeNull();

    search.mockResolvedValue({ ...RESULT, rows: [], statsByCurrency: {} });
    pick(el, "destination", {
      key: null,
      label: "",
      precision: "CITY",
      radius: null,
      unit: "MI"
    });
    applySearch(el);
    await settle();
    expect(search).toHaveBeenCalledTimes(2);
    expect(
      el.shadowRoot.querySelector("c-lane-benchmark-stats")
    ).not.toBeNull();
    expect(el.shadowRoot.querySelector('[data-id="carrier-leads"]')).toBeNull();
    expect(findCarrierLeads).not.toHaveBeenCalled();

    pickLane(el);
    applySearch(el);
    await settle();
    const leads = el.shadowRoot.querySelector('[data-id="carrier-leads"]');
    expect(leads).not.toBeNull();
    expect(leads.currencyCode).toBeNull();
    expect(findCarrierLeads).toHaveBeenCalledTimes(1);
    expect(findCarrierLeads.mock.calls[0][0].requestJson).toBe(
      search.mock.calls[2][0].requestJson
    );
  });

  it("keeps the statistics and results when Carriers to ask fails", async () => {
    findCarrierLeads.mockRejectedValue({ body: { message: "Carriers failed" } });
    const el = await mount();
    pickLane(el);
    el.shadowRoot
      .querySelector("c-lane-benchmark-filters")
      .dispatchEvent(
        new CustomEvent("filterschange", { detail: { currencyIsoCode: "USD" } })
      );
    applySearch(el);
    await settle();
    await settle();
    const leads = el.shadowRoot.querySelector('[data-id="carrier-leads"]');
    expect(leads).not.toBeNull();
    expect(
      leads.shadowRoot.querySelector('[data-id="leads-error"]')
    ).not.toBeNull();
    expect(
      el.shadowRoot.querySelector("c-lane-benchmark-stats")
    ).not.toBeNull();
    expect(
      el.shadowRoot.querySelector("c-lane-benchmark-results")
    ).not.toBeNull();
  });

  it("starts from the saved unit, follows the distance unit channel and unsubscribes when removed", async () => {
```

- [ ] **Step 14: Run the Lane Benchmark suite and watch it fail**

Run: `npm run test:unit -- force-app/main/default/lwc/laneBenchmark/ 2>&1 | grep -E "✕|^(Tests|Test Suites):"`

Expected: `✕ shows Carriers to ask under the statistics when the search has no rate in the currency filter`, `✕ shows Carriers to ask without a filter only when no currency has a rate, and never without both place keys`, `✕ keeps the statistics and results when Carriers to ask fails`, `Tests: 3 failed, 16 passed, 19 total` (the page renders no `c-carrier-leads` yet).

- [ ] **Step 15: Lane Benchmark — show the card**

In `force-app/main/default/lwc/laneBenchmark/laneBenchmark.js`, replace:

```js
import { readUnit } from "c/distanceUnit";
```

with:

```js
import { readUnit } from "c/distanceUnit";
import { hasBothKeys, noRate } from "c/carrierLeadRules";
```

In `force-app/main/default/lwc/laneBenchmark/laneBenchmark.js`, replace:

```js
  lastSearched = null;
```

with:

```js
  lastSearched = null;
  // Phase 8: the exact request JSON the last successful search sent and the currency filter it
  // ran with (null without one). Carriers to ask judges "no rate" in that currency (spec D2) and
  // asks about the lane that was searched, never about filter edits made since.
  lastRequestJson = null;
  lastCurrency = null;
```

In `force-app/main/default/lwc/laneBenchmark/laneBenchmark.js`, replace:

```js
    return !this.hasRouteMap || radius;
  }
```

with:

```js
    return !this.hasRouteMap || radius;
  }
  /** Carriers to ask: after a search with both place keys and no priced rate in its currency. */
  get showCarrierLeads() {
    return (
      this.hasResult &&
      hasBothKeys(this.lastRequestJson) &&
      noRate(this.statsByCurrency, this.lastCurrency)
    );
  }
```

In `force-app/main/default/lwc/laneBenchmark/laneBenchmark.js`, replace:

```js
    const svc = this.toServiceRequest();
    try {
      this.result = await search({ requestJson: JSON.stringify(svc) });
      // the search succeeded: keep it even if the map preview below fails
      this.lastSearched = { ...this.request };
```

with:

```js
    const svc = this.toServiceRequest();
    const requestJson = JSON.stringify(svc);
    try {
      this.result = await search({ requestJson });
      // the search succeeded: keep it even if the map preview below fails
      this.lastSearched = { ...this.request };
      this.lastRequestJson = requestJson;
      this.lastCurrency = svc.currencyIsoCode || null;
```

In `force-app/main/default/lwc/laneBenchmark/laneBenchmark.html`, replace:

```html
          onmarginchange={handleMargin}
        ></c-lane-benchmark-stats>
```

with:

```html
          onmarginchange={handleMargin}
        ></c-lane-benchmark-stats>
        <template lwc:if={showCarrierLeads}>
          <div class="slds-m-bottom_small">
            <c-carrier-leads
              data-id="carrier-leads"
              request-json={lastRequestJson}
              currency-code={lastCurrency}
            ></c-carrier-leads>
          </div>
        </template>
```

- [ ] **Step 16: Run the Lane Benchmark suite to pass**

Run: `npm run test:unit -- force-app/main/default/lwc/laneBenchmark/ 2>&1 | grep -E "✕|^(Tests|Test Suites):"`

Expected: no `✕` line, `Tests: 19 passed, 19 total`.

- [ ] **Step 17: Lane panel — write the failing tests**

In `force-app/main/default/lwc/rfpLanePanel/__tests__/rfpLanePanel.test.js`, replace:

```js
import laneRoute from "@salesforce/apex/RfpLaneController.laneRoute";
```

with:

```js
import laneRoute from "@salesforce/apex/RfpLaneController.laneRoute";
import findCarrierLeads from "@salesforce/apex/CarrierLeadController.findCarrierLeads";
```

In `force-app/main/default/lwc/rfpLanePanel/__tests__/rfpLanePanel.test.js`, replace:

```js
jest.mock(
  "@salesforce/apex/RfpLaneController.laneRoute",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
```

with:

```js
jest.mock(
  "@salesforce/apex/RfpLaneController.laneRoute",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/CarrierLeadController.findCarrierLeads",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
```

In `force-app/main/default/lwc/rfpLanePanel/__tests__/rfpLanePanel.test.js`, replace:

```js
    laneRoute.mockResolvedValue(null);
  });
```

with:

```js
    laneRoute.mockResolvedValue(null);
    findCarrierLeads.mockResolvedValue({
      leads: [],
      stage: "None",
      stateLaneLabel: null,
      truncated: false
    });
  });
```

In `force-app/main/default/lwc/rfpLanePanel/__tests__/rfpLanePanel.test.js`, replace:

```js
      expect(textOf(el, "lane-miles")).toBe("1,198 mi · from history");
    });
  });
});
```

with:

```js
      expect(textOf(el, "lane-miles")).toBe("1,198 mi · from history");
    });
  });

  describe("carriers to ask", () => {
    it("shows Carriers to ask under the history once it loads with no rate in the lane's currency", async () => {
      // HISTORY has no statistics bucket at all
      const el = await mount();
      const leads = field(el, "carrier-leads");
      expect(leads).not.toBeNull();
      const sent = search.mock.calls[0][0].requestJson;
      expect(leads.requestJson).toBe(sent);
      expect(leads.currencyCode).toBe("CAD");
      expect(findCarrierLeads).toHaveBeenCalledWith({
        requestJson: sent,
        attempt: 0
      });
      expect(
        field(el, "history-scroll").nextElementSibling.contains(leads)
      ).toBe(true);
    });

    it("judges the rate in the lane's own currency", async () => {
      search.mockResolvedValue({
        ...HISTORY,
        statsByCurrency: { CAD: { count: 1, countNonZero: 1, median: 1950 } }
      });
      const el = await mount();
      expect(field(el, "carrier-leads")).toBeNull();
      expect(findCarrierLeads).not.toHaveBeenCalled();

      el.lane = { ...LANE, Id: "a0L00000002", CurrencyIsoCode: "USD" };
      await flush();
      await flush();
      const leads = field(el, "carrier-leads");
      expect(leads).not.toBeNull();
      expect(leads.currencyCode).toBe("USD");
    });

    it("hides Carriers to ask while the history loads, after it fails and without both place keys", async () => {
      let releaseSearch;
      search.mockReturnValueOnce(
        new Promise((resolve) => {
          releaseSearch = resolve;
        })
      );
      const el = await mount();
      expect(field(el, "carrier-leads")).toBeNull();
      releaseSearch(HISTORY);
      await flush();
      await flush();
      expect(field(el, "carrier-leads")).not.toBeNull();

      // the previous lane's answer does not count for a lane still loading
      search.mockReturnValueOnce(new Promise(() => {}));
      el.lane = { ...LANE, Id: "a0L00000002" };
      await flush();
      expect(field(el, "carrier-leads")).toBeNull();

      search.mockRejectedValueOnce({ body: { message: "Search failed" } });
      el.lane = { ...LANE, Id: "a0L00000003" };
      await flush();
      await flush();
      expect(textOf(el, "panel-error")).toBe("Search failed");
      expect(field(el, "carrier-leads")).toBeNull();

      el.lane = { ...LANE, Id: "a0L00000004", Destination_Place__r: undefined };
      await flush();
      await flush();
      expect(field(el, "carrier-leads")).toBeNull();
      expect(findCarrierLeads).toHaveBeenCalledTimes(1);
    });
  });
});
```

- [ ] **Step 18: Run the panel suite and watch it fail**

Run: `npm run test:unit -- force-app/main/default/lwc/rfpLanePanel/ 2>&1 | grep -E "✕|^(Tests|Test Suites):"`

Expected: `✕ shows Carriers to ask under the history once it loads with no rate in the lane's currency`, `✕ judges the rate in the lane's own currency`, `✕ hides Carriers to ask while the history loads, after it fails and without both place keys`, `Tests: 3 failed, 35 passed, 38 total`.

- [ ] **Step 19: Lane panel — keep the history statistics and show the card**

In `force-app/main/default/lwc/rfpLanePanel/rfpLanePanel.js`, replace:

```js
} from "c/rfpPricing";
import { marginFor } from "c/marginMath";
```

with:

```js
} from "c/rfpPricing";
import { hasBothKeys, noRate } from "c/carrierLeadRules";
import { marginFor } from "c/marginMath";
```

In `force-app/main/default/lwc/rfpLanePanel/rfpLanePanel.js`, replace:

```js
  loadingHistory = false;
  bidSeq = 0;
```

with:

```js
  loadingHistory = false;
  /** The history search's statsByCurrency; Carriers to ask reads "no rate" from it (spec D2). */
  historyStats = null;
  /** True only once the history search answered for the current historySeq. */
  historyLoaded = false;
  bidSeq = 0;
```

In `force-app/main/default/lwc/rfpLanePanel/rfpLanePanel.js`, replace:

```js
    return !!(this._lane && this._lane.Hazmat__c);
  }
```

with:

```js
    return !!(this._lane && this._lane.Hazmat__c);
  }
  /** The request the history search sends, while both ends have a place key; else null. */
  get historyRequestJson() {
    return historyKey(this._lane) ? historyRequest(this._lane) : null;
  }
  /**
   * Carriers to ask shows once the history search has answered with no priced rate in the lane's
   * currency (spec D2, D3), never while a newer search is loading or after one failed.
   */
  get showCarrierLeads() {
    return (
      this.historyLoaded &&
      !this.loadingHistory &&
      noRate(this.historyStats, this.currency) &&
      hasBothKeys(this.historyRequestJson)
    );
  }
```

In `force-app/main/default/lwc/rfpLanePanel/rfpLanePanel.js`, replace:

```js
    this.bids = [];
    this.historyRows = [];
    this.routeView = null;
```

with:

```js
    this.bids = [];
    this.historyRows = [];
    this.historyStats = null;
    this.routeView = null;
```

In `force-app/main/default/lwc/rfpLanePanel/rfpLanePanel.js`, replace:

```js
    const seq = ++this.historySeq;
    if (!historyKey(this._lane)) {
      this.historyRows = [];
      this.truncated = false;
```

with:

```js
    const seq = ++this.historySeq;
    this.historyLoaded = false;
    if (!historyKey(this._lane)) {
      this.historyRows = [];
      this.historyStats = null;
      this.truncated = false;
```

In `force-app/main/default/lwc/rfpLanePanel/rfpLanePanel.js`, replace:

```js
      this.historyRows = (result && result.rows) || [];
      this.truncated = !!(result && result.truncated);
    } catch (e) {
      if (seq === this.historySeq) {
        this.historyRows = [];
```

with:

```js
      this.historyRows = (result && result.rows) || [];
      this.historyStats = (result && result.statsByCurrency) || null;
      this.truncated = !!(result && result.truncated);
      this.historyLoaded = true;
    } catch (e) {
      if (seq === this.historySeq) {
        this.historyRows = [];
        this.historyStats = null;
```

In `force-app/main/default/lwc/rfpLanePanel/rfpLanePanel.html`, replace:

```html
            destination-label={destinationLabel}
          ></c-lane-benchmark-results>
        </div>
      </div>
```

with:

```html
            destination-label={destinationLabel}
          ></c-lane-benchmark-results>
        </div>
      </div>
      <template lwc:if={showCarrierLeads}>
        <div class="slds-m-top_x-small">
          <c-carrier-leads
            data-id="carrier-leads"
            request-json={historyRequestJson}
            currency-code={currency}
          ></c-carrier-leads>
        </div>
      </template>
```

- [ ] **Step 20: Run the panel suite to pass**

Run: `npm run test:unit -- force-app/main/default/lwc/rfpLanePanel/ 2>&1 | grep -E "✕|^(Tests|Test Suites):"`

Expected: no `✕` line, `Tests: 38 passed, 38 total`.

- [ ] **Step 21: The workbench suite's Apex mock**

`c-rfp-tool` renders the lane panel for real, and the panel now renders `c-carrier-leads`, which imports `CarrierLeadController.findCarrierLeads`. That file lists every Apex module the workbench tree imports as a literal `jest.mock` (babel-plugin-jest-hoist hoists only literal calls).

In `force-app/main/default/lwc/rfpTool/__tests__/rfpTool.test.js`, replace:

```js
jest.mock(
  "@salesforce/apex/LaneBenchmarkController.geocode",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
```

with:

```js
jest.mock(
  "@salesforce/apex/LaneBenchmarkController.geocode",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/CarrierLeadController.findCarrierLeads",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
```

Run: `npm run test:unit -- force-app/main/default/lwc/rfpTool/ 2>&1 | grep -E "✕|^(Tests|Test Suites):"`

Expected: no `✕` line, `Test Suites: 1 passed, 1 total`, `Tests: 34 passed, 34 total`.

- [ ] **Step 22: Manifest**

In `manifest/package.xml`, replace:

```xml
        <members>routeMap</members>
        <name>LightningComponentBundle</name>
```

with:

```xml
        <members>routeMap</members>
        <members>carrierLeadRules</members>
        <members>carrierLeads</members>
        <name>LightningComponentBundle</name>
```

- [ ] **Step 23: Format, lint, the whole Jest run, and rfpTool untouched**

Run: `npx prettier --write force-app/main/default/lwc/carrierLeadRules force-app/main/default/lwc/carrierLeads force-app/main/default/lwc/laneBenchmark force-app/main/default/lwc/rfpLanePanel force-app/main/default/lwc/rfpLaneTable force-app/main/default/lwc/rfpTool/__tests__/rfpTool.test.js manifest/package.xml`

Expected: each file listed once; no content change (the blocks above are already in the repo's Prettier style; lint-staged runs the same on commit).

Run: `npx eslint force-app/main/default/lwc/carrierLeadRules force-app/main/default/lwc/carrierLeads force-app/main/default/lwc/laneBenchmark force-app/main/default/lwc/rfpLanePanel force-app/main/default/lwc/rfpLaneTable force-app/main/default/lwc/rfpTool; echo "eslint exit $?"`

Expected: no findings, `eslint exit 0`.

Run (with `run_in_background` and a log if the cache is cold): `npm run test:unit 2>&1 | grep -E "✕|^(Tests|Test Suites):"`

Expected: no `✕` line and no failed suite; `Test Suites: 41 passed, 41 total`, `Tests: 385 passed, 385 total` (the baseline printed before Step 1 plus 2 suites and 22 tests). The help `placement.test.js` suite still passes: no hint was added or moved.

Run: `git diff --stat -- force-app/main/default/lwc/rfpTool/rfpTool.js force-app/main/default/lwc/rfpTool/rfpTool.html; wc -l < force-app/main/default/lwc/rfpTool/rfpTool.js; wc -l force-app/main/default/lwc/laneBenchmark/laneBenchmark.js force-app/main/default/lwc/rfpLanePanel/rfpLanePanel.js force-app/main/default/lwc/rfpLaneTable/rfpLaneTable.js; git status --porcelain`

Expected: no diff-stat output for the two rfpTool files; `554`; `369`, `619`, `507`; `git status` lists the 11 modified files and the two new bundle folders this task names (` M .vscode/settings.json`, `?? node_modules` and untracked macOS duplicates named `* 2.*` may also appear and are never staged).

- [ ] **Step 24: Deploy the five bundles**

Task 6 is deployed to `sandbox` first (`CarrierLeadController.findCarrierLeads`): a bundle that imports a missing Apex method fails to deploy. The deploy carries LWC only, so it runs no Apex test; `__tests__/**` is in `.forceignore`, and `manifest/package.xml` is only read by the full manifest deploy (Task 11).

Run: `sf project deploy start -o sandbox -l NoTestRun --source-dir force-app/main/default/lwc/carrierLeadRules --source-dir force-app/main/default/lwc/carrierLeads --source-dir force-app/main/default/lwc/laneBenchmark --source-dir force-app/main/default/lwc/rfpLanePanel --source-dir force-app/main/default/lwc/rfpLaneTable --async --json | python3 -c "import json,sys; s=sys.stdin.read(); print(json.loads(s[s.index('{'):])['result']['id'])"`

Expected: a deploy id starting with `0Af`.

Run, repeating until the status is final: `sf project deploy report -o sandbox --job-id <id> -w 2 --json | python3 -c "import json,sys; s=sys.stdin.read(); r=json.loads(s[s.index('{'):])['result']; print(r['status'], r.get('numberComponentsDeployed'), '/', r.get('numberComponentsTotal'), (r.get('details') or {}).get('componentFailures'))"`

Expected: `Succeeded 5 / 5 None`. A `componentFailures` entry naming `CarrierLeadController` or `findCarrierLeads` means Task 6 is not in the org yet: deploy it, then repeat this step.

- [ ] **Step 25: Commit**

```bash
git add force-app/main/default/lwc/carrierLeadRules/carrierLeadRules.js force-app/main/default/lwc/carrierLeadRules/carrierLeadRules.js-meta.xml force-app/main/default/lwc/carrierLeadRules/__tests__/carrierLeadRules.test.js force-app/main/default/lwc/carrierLeads/carrierLeads.js force-app/main/default/lwc/carrierLeads/carrierLeads.html force-app/main/default/lwc/carrierLeads/carrierLeads.css force-app/main/default/lwc/carrierLeads/carrierLeads.js-meta.xml force-app/main/default/lwc/carrierLeads/__tests__/carrierLeads.test.js force-app/main/default/lwc/laneBenchmark/laneBenchmark.js force-app/main/default/lwc/laneBenchmark/laneBenchmark.html force-app/main/default/lwc/laneBenchmark/__tests__/laneBenchmark.test.js force-app/main/default/lwc/rfpLanePanel/rfpLanePanel.js force-app/main/default/lwc/rfpLanePanel/rfpLanePanel.html force-app/main/default/lwc/rfpLanePanel/__tests__/rfpLanePanel.test.js force-app/main/default/lwc/rfpLaneTable/rfpLaneTable.js force-app/main/default/lwc/rfpLaneTable/rfpLaneTable.html force-app/main/default/lwc/rfpLaneTable/__tests__/rfpLaneTable.test.js force-app/main/default/lwc/rfpTool/__tests__/rfpTool.test.js manifest/package.xml
git commit -m "Show Carriers to ask on Lane Benchmark and the RFP lane panel and tag lanes with no rate"
git show --stat HEAD | tail -22
```

Expected: the commit lists the 19 files above (8 created, 11 modified); `rfpTool.js`, `rfpTool.html` and `.vscode/settings.json` are not in it, and the message has no trailer.

#### Contract notes (Task 7)

1. **Which line goes with which stage.** The contract lists three texts without saying when each shows. The draft shows `leads-heading` only for an answer with leads whose stage is not `State lane` (in practice `Same lane`), `leads-stage2` instead of it for `State lane`, and `leads-empty` whenever an answer has no lead (the service returns stage `None` exactly then). `leads-truncated` can show under any of them.
2. **`lastSeen` can be null.** `CarrierLeadResult.Lead.lastSeen` is a nullable `Date` (Task 5 ranks "null last"), so `lead-counts` reads `last seen —` when it is null instead of `last seen null`. Every other count text is the contract's.
3. **The account link opens a new tab** (`target="_blank" rel="noopener"`). A plain `/lightning/r/Account/{carrierId}/view` anchor would leave the RFP workbench and lose a price the pricer has typed but not saved. The href is the contract's.
4. **Error wording.** The contract names no failure text: `leads-error` shows the Apex message (`e.body.message`, the `AuraHandledException` text from Task 6) or, without one, `The carriers to ask could not be loaded.`
5. **A blank `requestJson` clears the card** (result, error, spinner) and bumps the sequence without calling Apex, so a late answer for the previous request cannot land. The parents never pass a blank value while the card shows; the guard only covers the setter's contract ("reloads when the value changes and is non-blank").
6. **Two existing `rfpLaneTable` assertions change.** "splits the history count into loads and bids once bids were counted" and "says so when a Done snapshot found loads but no median" read the whole History cell's `textContent`, which now ends with the tag. They now use a `histOf(row)` helper (the cell's text without the tag, and the tag) and also assert the tag; the Pending, Unresolved and priced-median assertions are untouched because those rows get no tag.
7. **Tag class.** The no rate tag is `slds-badge slds-m-left_xx-small` (the contract says `slds-badge`), spaced like the Miles cell's `miles-tag`. The Blacklisted badge is `slds-badge slds-theme_error slds-m-left_x-small`. On both pages `c-carrier-leads` sits in a plain spacing `div` (`slds-m-bottom_small` on Lane Benchmark, like the route map's, and `slds-m-top_x-small` in the panel, like the route block's); `data-id="carrier-leads"` stays on the component itself.
8. **The lane panel's request string is recomputed from the lane.** `historyRequestJson` calls `historyRequest(this._lane)` on each render, so it equals the string `loadHistory` sent as long as the lane's `Hist_*` fields and `RFP_Project__c` are unchanged. A history run that changes only `Hist_Bid_Count__c` (to or from 0) changes the string without changing `historyKey`: the panel does not search again, but the card asks `findCarrierLeads` once more with a new cache key. The server ignores the source and bid fields (spec §3), so the answer is the same; this costs at most one extra call after a history run.
9. **Lane Benchmark keeps `lastRequestJson` and `lastCurrency` after a failed search or Clear saved filters.** `hasResult` is false then, so the card is hidden, and the next successful search overwrites both before anything renders. Clearing them would add lines without changing what the page shows.
10. **No help hint on the card** (see Step 7): `placement.test.js` stays unchanged and green; Task 11 writes the guide text.
11. **Line counts after this task** (measured in the scratch check): `rfpLanePanel.js` 592 → 619, `laneBenchmark.js` 352 → 369, `rfpLaneTable.js` 493 → 507; `rfpTool.js` stays at 554 and `rfpTool.html` does not change.
12. **Checked before hand-off.** Every Create block and every Replace/with pair in this task was applied to a scratch copy of the phase 8 tree (`44081a7`, with the repo's `node_modules`, `.prettierrc` and `eslint.config.js`). Every Replace anchor matched the current file exactly once. With only the test edits applied, the suites reported `Cannot find module` for the two new bundles, `3 failed, 24 passed, 27 total` (lane table), `2 failed, 16 passed, 18 total` (Lane Benchmark), `3 failed, 35 passed, 38 total` (lane panel) and `34 passed` (`rfpTool/`). With every step applied, the full run reported `Test Suites: 41 passed, 41 total`, `Tests: 384 passed, 384 total`; `npx eslint` exited 0 and `npx prettier --check` passed on every touched bundle. The Apex import is mocked in Jest, so nothing here depends on Tasks 1–6 until the deploy. The Lane Benchmark test `keeps the statistics and results when Carriers to ask fails` (spec §8: a failing card never holds back the first search's rates and rows) was added when the plan was assembled, after that check: Steps 14, 16 and 23 count it (Lane Benchmark 19 tests, 385 in all).


---

### Task 8: Split-lane history — `SplitLaneResult` and `SplitLaneService` (history groups, USD conversion)

**Files:**

- Create: `force-app/main/default/classes/SplitLaneResult.cls`, `force-app/main/default/classes/SplitLaneResult.cls-meta.xml`
- Create: `force-app/main/default/classes/SplitLaneService.cls`, `force-app/main/default/classes/SplitLaneService.cls-meta.xml`
- Create: `force-app/main/default/classes/SplitLaneServiceTest.cls`, `force-app/main/default/classes/SplitLaneServiceTest.cls-meta.xml`
- Modify: `manifest/package.xml` (ApexClass members `SplitLaneResult`, `SplitLaneService`, `SplitLaneServiceTest`, at the end of the ApexClass block, after the members Tasks 1 to 6 added and directly before `<name>ApexClass</name>`)

**Interfaces:**

- Consumes:
  - `FreightPlanReader.read(String soql, Map<String, Object> binds)` returning `List<rtms__FreightPlan__c>` with the child rows `rtms__Freight_Plan_Loads__r` (Task 1). Plans are read only through it.
  - `SplitTestData.carrier(String name, Boolean blacklisted)`, `SplitTestData.legLoad(PricingTestDataFactory.Graph g, Account origin, Account destination, Account carrierAccount, Decimal cadTotal, String status)`, `SplitTestData.plan(rtms__Load__c customerLoad, List<rtms__Load__c> legLoads)` (Task 1, branch A or B; every plan fixture below goes through `plan`).
  - `IntercompanyCarriers.ids()` and its `@TestVisible idsOverride` (`Set<Id>`); `ExchangeRates.usd(Date fromDate)`, `hasRates()`, `fromCad(Decimal cadAmount, Datetime loadCreated)`, `latestStartUsed`, `ExchangeRates.Period(Date startDate, Date nextStartDate, Decimal rate)` and its `@TestVisible periodsOverride` (`List<ExchangeRates.Period>`) (Task 3).
  - `LaneQueries.laneConditions(LaneSearchRequest req, Pricing_Place__c origin, Pricing_Place__c destination, String loadPath, Map<String, Object> binds)` and `LaneQueries.planSoql(List<String> customerConditions, Integer days, Integer planLimit, Boolean withAmounts)`; the bind names `oCity` and `dCity` come from `LaneKeyMatcher` (Tasks 2 and 5).
  - Existing: `LaneSearchRequest` (`applyDefaults()`, `originKey`, `destinationKey`), `PricingTestDataFactory.createGraph()`, `createLocation(name, city, province, country, postalCode, lat, lng)`, `createLoad(Graph, Account, Account)`, `RfpTestDataFactory.createPlace(city, prov, country, lat, lng, prefix)`.
- Produces:
  - `SplitLaneResult` (`public class`, all `@AuraEnabled`): `LegCarrier { Id carrierId; String name; Integer legsMoved = 0; Boolean blacklisted = false; }`, `Leg { Integer position; String laneLabel; List<LegCarrier> carriers; Decimal median; Integer pricedCount = 0; }`, `Option { String kind; String handoffLabel; Integer shipments = 0; List<Leg> legs; Decimal medianTotal; Integer pricedShipments = 0; Integer extraDistancePct; }`, `String currencyCode`, `Date rateStartDate`, `List<Option> options`, `Boolean truncated = false`, `String message`; constants `HISTORY = 'History'`, `ESTIMATE = 'Estimate'`. Every amount is at scale 2.
  - On `SplitLaneService` (`public without sharing`):
    - `public static SplitLaneResult options(LaneSearchRequest req, String currencyCode)` — a blank key gives the message `Both ends of the lane need a place.` with no query; a missing place the same after the one places read; in USD, no dated rate gives `No USD exchange rate is available.` and no plan read; otherwise one plan read (365 days, 1000 plans, with amounts), `truncated` at 1000 plans, the history groups, and `rateStartDate = rates?.latestStartUsed`. Task 9 adds the estimate call and its message after the history block, using the locals `origin`, `destination` and `rates`.
    - `public static Decimal median(List<Decimal> values)` — `null` for null or empty; odd count the middle value, even count the mean of the two middle values; `setScale(2)`.
    - `public static Decimal amountIn(String currencyCode, ExchangeRates rates, Decimal cadAmount, Datetime loadCreated)` — `USD`: `rates.fromCad(cadAmount, loadCreated)` (null without rates); otherwise `cadAmount`; unrounded.
    - `public class CarrierTally { public void add(Id carrierId, String name, Boolean blacklisted); public List<SplitLaneResult.LegCarrier> sorted(); }` — a null carrier is ignored; blacklisted when any added leg says so; sorted by `legsMoved` descending, then name ascending (case-insensitive). Task 9's `SplitEstimates` uses it.
    - Beyond the contract (see Contract notes 1 and 2): `public class LegRow` (`created`, `carrierId`, `carrierName`, `blacklisted`, `cityLane`, `status`, `cadTotal`, `stopName`; built from a leg load by the private outer `toLegRow(rtms__Load__c load)`, because Apex inner classes hold no static members), `@TestVisible private static List<SplitLaneResult.Option> groupHistory(List<List<LegRow>> shipments, String currencyCode, ExchangeRates rates)` and `@TestVisible private static String historySoql(LaneSearchRequest req, Pricing_Place__c origin, Pricing_Place__c destination, Map<String, Object> binds)`.

Test data budget. A split shipment is three loads, and `PricingTestDataFactory`'s class doc says the load automation is not bulkified: three `createLoad()` calls in one governor window reached 101 SOQL queries in `LaneSearchServiceTest.hazmatAcceptedAndExcludedContactFiltersNeverReturnMarketTestQuotes`. So each end-to-end test here builds one shipment. It creates one load before `Test.startTest()` and two inside it, the shape that test and `bidsMergeIntoRowsAndObeyTheSourceFilter` already pass with. Grouping, ordering, the R85 total and the exclusions run on shipments built in memory as `LegRow` lists through `groupHistory`, which inserts nothing and holds no plan fixture. The end-to-end tests prove that the plan rows `SplitTestData.plan` builds reach those `LegRow`s: dates, carriers, lanes, stop names and totals.

- [ ] **Step 1: Write the failing tests**

Print the baseline first; the executor records these counts and never trusts the plan's. Run: `ls force-app/main/default/classes/*Test.cls | wc -l; grep -c "@IsTest" force-app/main/default/classes/SplitTestDataTest.cls`

Expected: the number of test classes after Task 7 (Task 1 to Task 6 added 11 to the 26 of phase 7), and the `@IsTest` lines in `SplitTestDataTest` (its test count plus one for the class annotation). Note both numbers for Step 7.

Create `force-app/main/default/classes/SplitLaneServiceTest.cls`:

```apex
/**
 * Split-lane history (phase 8, Task 8). End-to-end tests build one shipment each through
 * SplitTestData (a customer load and two leg loads; three createLoad() calls do not fit one governor
 * window, see PricingTestDataFactory's class doc, so one load is made before Test.startTest() and two
 * inside it). Grouping, ordering, the R85 total and the left-out shipments run on shipments built in
 * memory through SplitLaneService.groupHistory.
 */
@IsTest
private class SplitLaneServiceTest {
  private static final String YARD = 'SFMN Park ITC Laredo yard';
  private static final String ESCOBEDO_LAREDO = 'General Escobedo, NL:Laredo, TX';
  private static final String LAREDO_ST_AUGUSTIN = 'Laredo, TX:St-Augustin-de-Desmaures, QC';
  private static Map<String, Id> fakeCarrierIds = new Map<String, Id>();

  /** The graph, a Monterrey plant, the Laredo yard, two leg carriers (Fletes Mex blacklisted) and the lane's two places. No load. */
  private class Fx {
    PricingTestDataFactory.Graph g;
    Account monterrey;
    Account laredoYard;
    Account qTransportes;
    Account fletes;
  }

  private static Fx fixture() {
    Fx f = new Fx();
    f.g = PricingTestDataFactory.createGraph();
    f.monterrey = PricingTestDataFactory.createLocation(
      'Monterrey Plant',
      'Monterrey',
      'Nuevo León',
      'Mexico',
      '64000',
      25.6866,
      -100.3161
    );
    f.laredoYard = PricingTestDataFactory.createLocation(
      YARD,
      'Laredo',
      'Texas',
      'United States',
      '78045',
      27.5306,
      -99.4803
    );
    f.qTransportes = SplitTestData.carrier('Q Transportes', false);
    f.fletes = SplitTestData.carrier('Fletes Mex', true);
    createLanePlaces();
    IntercompanyCarriers.idsOverride = new Set<Id>();
    return f;
  }

  private static void createLanePlaces() {
    RfpTestDataFactory.createPlace(
      'Monterrey',
      'NL',
      'MX',
      25.6866,
      -100.3161,
      '640'
    );
    RfpTestDataFactory.createPlace(
      'Toronto',
      'ON',
      'CA',
      43.6532,
      -79.3832,
      'M5V'
    );
  }

  private static LaneSearchRequest request(
    String originKey,
    String destinationKey
  ) {
    LaneSearchRequest r = new LaneSearchRequest();
    r.originKey = originKey;
    r.destinationKey = destinationKey;
    return r;
  }

  private static LaneSearchRequest monterreyToToronto() {
    return request('monterrey|nl|mx', 'toronto|on|ca');
  }

  /** A never inserted Account Id per carrier name: the grouping compares carrier Ids only. */
  private static Id fakeCarrierId(String name) {
    if (!fakeCarrierIds.containsKey(name)) {
      fakeCarrierIds.put(
        name,
        Id.valueOf(
          Account.SObjectType.getDescribe().getKeyPrefix() +
          String.valueOf(fakeCarrierIds.size() + 1).leftPad(12, '0')
        )
      );
    }
    return fakeCarrierIds.get(name);
  }

  /** A delivered leg created now, in memory: its carrier, city lane, last stop account name and CAD total. */
  private static SplitLaneService.LegRow leg(
    String carrier,
    String cityLane,
    String stopName,
    Decimal cadTotal
  ) {
    SplitLaneService.LegRow row = new SplitLaneService.LegRow();
    row.carrierId = fakeCarrierId(carrier);
    row.carrierName = carrier;
    row.cityLane = cityLane;
    row.stopName = stopName;
    row.cadTotal = cadTotal;
    row.status = 'Delivered';
    row.created = Datetime.now();
    return row;
  }

  private static List<SplitLaneService.LegRow> twoLegs(
    SplitLaneService.LegRow legOne,
    SplitLaneService.LegRow legTwo
  ) {
    return new List<SplitLaneService.LegRow>{ legOne, legTwo };
  }

  /**
   * One shipment Monterrey -> Laredo yard -> Toronto, end to end: the plan rows reach the history
   * with the handoff city from leg 1's lane, the yard from leg 1's last stop account, each leg's
   * carrier and blacklist flag, lane and CAD total. Then the same lane with leg 2's carrier on the
   * intercompany list has no group.
   */
  @IsTest
  static void historyReadsTheLanePlanWithItsHandoffCarriersAndCosts() {
    Fx f = fixture();
    rtms__Load__c customer = PricingTestDataFactory.createLoad(
      f.g,
      f.monterrey,
      f.g.destinationLocation
    );
    Test.startTest();
    rtms__Load__c toLaredo = SplitTestData.legLoad(
      f.g,
      f.monterrey,
      f.laredoYard,
      f.qTransportes,
      1200,
      'Delivered'
    );
    rtms__Load__c toToronto = SplitTestData.legLoad(
      f.g,
      f.laredoYard,
      f.g.destinationLocation,
      f.fletes,
      2400,
      'Delivered'
    );
    SplitTestData.plan(
      customer,
      new List<rtms__Load__c>{ toLaredo, toToronto }
    );
    SplitLaneResult inCad = SplitLaneService.options(
      monterreyToToronto(),
      'CAD'
    );
    IntercompanyCarriers.idsOverride = new Set<Id>{ f.fletes.Id };
    SplitLaneResult withIntercompanyLeg = SplitLaneService.options(
      monterreyToToronto(),
      'CAD'
    );
    Test.stopTest();

    System.assertEquals('CAD', inCad.currencyCode, 'the card currency');
    System.assertEquals(null, inCad.message, 'a group, no message');
    System.assertEquals(null, inCad.rateStartDate, 'no exchange rate in CAD');
    System.assertEquals(false, inCad.truncated, 'one plan');
    System.assertEquals(1, inCad.options.size(), 'one handoff group');
    SplitLaneResult.Option o = inCad.options[0];
    System.assertEquals('History', o.kind, 'a history group');
    System.assertEquals(
      'Laredo, TX · ' + YARD,
      o.handoffLabel,
      'city from leg 1 lane, yard from leg 1 last stop account'
    );
    System.assertEquals(1, o.shipments, 'one shipment');
    System.assertEquals(null, o.extraDistancePct, 'history has no distance');
    System.assertEquals(
      2,
      o.legs.size(),
      'the two carrier legs, not the customer row'
    );
    SplitLaneResult.Leg legOne = o.legs[0];
    System.assertEquals(1, legOne.position, 'leg 1');
    System.assertEquals(
      'Monterrey, NL → Laredo, TX',
      legOne.laneLabel,
      'leg 1 lane with an arrow'
    );
    System.assertEquals(1, legOne.carriers.size(), 'one leg 1 carrier');
    System.assertEquals(
      f.qTransportes.Id,
      legOne.carriers[0].carrierId,
      'the leg load carrier'
    );
    System.assertEquals('Q Transportes', legOne.carriers[0].name, 'its name');
    System.assertEquals(1, legOne.carriers[0].legsMoved, 'one leg moved');
    System.assertEquals(
      false,
      legOne.carriers[0].blacklisted,
      'not blacklisted'
    );
    System.assertEquals(1200.00, legOne.median, 'leg 1 CAD total');
    System.assertEquals(2, legOne.median.scale(), 'amounts at scale 2');
    System.assertEquals(1, legOne.pricedCount, 'one priced leg');
    SplitLaneResult.Leg legTwo = o.legs[1];
    System.assertEquals(2, legTwo.position, 'leg 2');
    System.assertEquals(
      'Laredo, TX → Toronto, ON',
      legTwo.laneLabel,
      'leg 2 lane with an arrow'
    );
    System.assertEquals(
      f.fletes.Id,
      legTwo.carriers[0].carrierId,
      'leg 2 carrier'
    );
    System.assertEquals(
      true,
      legTwo.carriers[0].blacklisted,
      'from the leg carrier Black_List__c'
    );
    System.assertEquals(2400.00, legTwo.median, 'leg 2 CAD total');
    System.assertEquals(3600.00, o.medianTotal, 'the shipment sum');
    System.assertEquals(1, o.pricedShipments, 'every leg priced');

    System.assertEquals(
      0,
      withIntercompanyLeg.options.size(),
      'a shipment with an intercompany leg carrier is left out'
    );
    System.assertEquals(
      null,
      withIntercompanyLeg.message,
      'Task 9 adds the no-option message'
    );
  }

  /**
   * USD: each leg's CAD total is converted at the dated rate of its own load's CreatedDate. Leg 1 was
   * created 60 days ago, inside the first period (0.80); leg 2 today, on or after the last period's
   * start (0.75). Test.setCreatedDate only works before Test.startTest(), so leg 1 is the load made
   * before it.
   */
  @IsTest
  static void usdConvertsEachLegAtTheRateOfItsLoadDate() {
    Fx f = fixture();
    rtms__Load__c toLaredo = SplitTestData.legLoad(
      f.g,
      f.monterrey,
      f.laredoYard,
      f.qTransportes,
      1000,
      'Delivered'
    );
    Test.setCreatedDate(toLaredo.Id, Datetime.now().addDays(-60));
    Date lastStart = Date.today().addDays(-30);
    ExchangeRates.periodsOverride = new List<ExchangeRates.Period>{
      new ExchangeRates.Period(Date.today().addDays(-400), lastStart, 0.80),
      new ExchangeRates.Period(lastStart, Date.newInstance(9999, 12, 31), 0.75)
    };
    Test.startTest();
    rtms__Load__c customer = PricingTestDataFactory.createLoad(
      f.g,
      f.monterrey,
      f.g.destinationLocation
    );
    rtms__Load__c toToronto = SplitTestData.legLoad(
      f.g,
      f.laredoYard,
      f.g.destinationLocation,
      f.fletes,
      2000,
      'Delivered'
    );
    SplitTestData.plan(
      customer,
      new List<rtms__Load__c>{ toLaredo, toToronto }
    );
    SplitLaneResult inUsd = SplitLaneService.options(
      monterreyToToronto(),
      'USD'
    );
    Test.stopTest();

    System.assertEquals('USD', inUsd.currencyCode, 'the card currency');
    System.assertEquals(null, inUsd.message, 'rates exist');
    System.assertEquals(1, inUsd.options.size(), 'one group');
    SplitLaneResult.Option o = inUsd.options[0];
    System.assertEquals(
      800.00,
      o.legs[0].median,
      '1000 CAD x 0.80, the period holding the leg load date'
    );
    System.assertEquals(
      1500.00,
      o.legs[1].median,
      '2000 CAD x 0.75, the last period'
    );
    System.assertEquals(2300.00, o.medianTotal, 'the converted legs summed');
    System.assertEquals(
      lastStart,
      inUsd.rateStartDate,
      'the start of the latest period used'
    );
  }

  @IsTest
  static void usdWithoutADatedRateGivesAMessageAndReadsNoPlan() {
    createLanePlaces();
    ExchangeRates.periodsOverride = new List<ExchangeRates.Period>();
    Test.startTest();
    Integer queriesAtStart = Limits.getQueries();
    SplitLaneResult inUsd = SplitLaneService.options(
      monterreyToToronto(),
      'USD'
    );
    Integer queriesUsed = Limits.getQueries() - queriesAtStart;
    Test.stopTest();
    System.assertEquals(
      'No USD exchange rate is available.',
      inUsd.message,
      'no dated USD rate'
    );
    System.assertEquals(0, inUsd.options.size(), 'no option');
    System.assertEquals('USD', inUsd.currencyCode, 'the card currency');
    System.assertEquals(null, inUsd.rateStartDate, 'no rate used');
    System.assertEquals(1, queriesUsed, 'the places read only, no plan read');
  }

  @IsTest
  static void aBlankKeyOrAnUnknownPlaceGivesAMessage() {
    createLanePlaces();
    Test.startTest();
    Integer queriesAtStart = Limits.getQueries();
    SplitLaneResult blankOrigin = SplitLaneService.options(
      request(' ', 'toronto|on|ca'),
      'CAD'
    );
    Integer blankQueries = Limits.getQueries() - queriesAtStart;
    SplitLaneResult unknownOrigin = SplitLaneService.options(
      request('nowhere|nl|mx', 'toronto|on|ca'),
      'CAD'
    );
    Integer unknownQueries =
      Limits.getQueries() -
      queriesAtStart -
      blankQueries;
    Test.stopTest();
    System.assertEquals(
      'Both ends of the lane need a place.',
      blankOrigin.message,
      'a blank key'
    );
    System.assertEquals(0, blankOrigin.options.size(), 'no option');
    System.assertEquals(0, blankQueries, 'a blank key reads nothing');
    System.assertEquals(
      'Both ends of the lane need a place.',
      unknownOrigin.message,
      'a key without a place'
    );
    System.assertEquals(0, unknownOrigin.options.size(), 'no option');
    System.assertEquals(1, unknownQueries, 'the places read only');
  }

  /**
   * The plan read the history runs, whichever way Task 1 builds plan rows: customer loads on the lane
   * over 365 days, at most 1000 plans, with each leg's amount, lane, status and last stop account.
   */
  @IsTest
  static void historyReadsAYearOfLanePlansWithTheirLegCosts() {
    Pricing_Place__c monterrey = new Pricing_Place__c(
      Key__c = 'monterrey|nl|mx',
      City__c = 'Monterrey',
      Province__c = 'NL',
      Country__c = 'MX',
      Postal_Prefix__c = '640'
    );
    Pricing_Place__c toronto = new Pricing_Place__c(
      Key__c = 'toronto|on|ca',
      City__c = 'Toronto',
      Province__c = 'ON',
      Country__c = 'CA',
      Postal_Prefix__c = 'M5V'
    );
    Map<String, Object> binds = new Map<String, Object>();
    String soql = SplitLaneService.historySoql(
      monterreyToToronto(),
      monterrey,
      toronto,
      binds
    );
    for (
      String part : new List<String>{
        'FROM rtms__FreightPlan__c',
        'rtms__Type__c = \'Customer\'',
        'rtms__Load__r.rtms__City_Lane__c LIKE :oCity',
        'rtms__Load__r.rtms__City_Lane__c LIKE :dCity',
        'rtms__Load__r.CreatedDate = LAST_N_DAYS:365',
        'rtms__Load__r.rtms__Load_Status__c != \'Cancelled\'',
        'rtms__Load__r.rtms__Carrier_Quote_Total__c',
        'rtms__Load__r.rtms__Last_Stop__r.rtms__Location2__r.Name',
        'LIMIT 1000'
      }
    ) {
      System.assert(soql.contains(part), 'missing ' + part + ' in ' + soql);
    }
    System.assert(
      binds.containsKey('oCity') && binds.containsKey('dCity'),
      'city binds for both ends: ' + binds.keySet()
    );
  }

  /**
   * Four shipments via the Laredo yard make one group. Shipment 3 writes the handoff in capitals and
   * still joins it; shipment 4's second leg has a zero total, so it is priced on leg 1 only and stays
   * out of the total. The total is the median of each fully priced shipment's own sum (R85): 5000,
   * while the two leg medians add up to 3600.
   */
  @IsTest
  static void shipmentsViaOneHandoffShareAGroupAndTheTotalIsTheMedianOfTheirSums() {
    SplitLaneService.LegRow blacklistedFletes = leg(
      'Fletes Mex',
      LAREDO_ST_AUGUSTIN,
      'Client DC',
      5000
    );
    blacklistedFletes.blacklisted = true;
    List<List<SplitLaneService.LegRow>> shipments = new List<List<SplitLaneService.LegRow>>{
      twoLegs(
        leg('Q Transportes', ESCOBEDO_LAREDO, YARD, 1000),
        leg('Fletes Mex', LAREDO_ST_AUGUSTIN, 'Client DC', 1000)
      ),
      twoLegs(
        leg('Q Transportes', ESCOBEDO_LAREDO, YARD, 2000),
        blacklistedFletes
      ),
      twoLegs(
        leg(
          'Xpress Norte',
          'Apodaca, NL:LAREDO, TX',
          'SFMN PARK ITC LAREDO YARD',
          3000
        ),
        leg('Maple Freight', LAREDO_ST_AUGUSTIN, 'Client DC', 2000)
      ),
      twoLegs(
        leg('Q Transportes', ESCOBEDO_LAREDO, YARD, 1200),
        leg('Nord Cartage', LAREDO_ST_AUGUSTIN, 'Client DC', 0)
      )
    };
    IntercompanyCarriers.idsOverride = new Set<Id>();

    List<SplitLaneResult.Option> groups = SplitLaneService.groupHistory(
      shipments,
      'CAD',
      null
    );

    System.assertEquals(1, groups.size(), 'one handoff, whatever its capitals');
    SplitLaneResult.Option o = groups[0];
    System.assertEquals('History', o.kind, 'a history group');
    System.assertEquals(
      'Laredo, TX · ' + YARD,
      o.handoffLabel,
      'the first spelling seen'
    );
    System.assertEquals(4, o.shipments, 'four shipments');
    SplitLaneResult.Leg legOne = o.legs[0];
    System.assertEquals(
      'General Escobedo, NL → Laredo, TX',
      legOne.laneLabel,
      'the most frequent leg 1 lane'
    );
    System.assertEquals(2, legOne.carriers.size(), 'two leg 1 carriers');
    System.assertEquals(
      'Q Transportes',
      legOne.carriers[0].name,
      'most legs first'
    );
    System.assertEquals(3, legOne.carriers[0].legsMoved, 'three legs');
    System.assertEquals(
      'Xpress Norte',
      legOne.carriers[1].name,
      'then one leg'
    );
    System.assertEquals(
      1600.00,
      legOne.median,
      'median of 1000, 1200, 2000 and 3000'
    );
    System.assertEquals(4, legOne.pricedCount, 'four priced legs');
    SplitLaneResult.Leg legTwo = o.legs[1];
    System.assertEquals(2, legTwo.position, 'leg 2');
    System.assertEquals(
      'Laredo, TX → St-Augustin-de-Desmaures, QC',
      legTwo.laneLabel,
      'leg 2 lane'
    );
    System.assertEquals(3, legTwo.carriers.size(), 'three leg 2 carriers');
    System.assertEquals('Fletes Mex', legTwo.carriers[0].name, 'two legs');
    System.assertEquals(2, legTwo.carriers[0].legsMoved, 'two legs moved');
    System.assertEquals(
      true,
      legTwo.carriers[0].blacklisted,
      'blacklisted on one of its legs'
    );
    System.assertEquals(
      'Maple Freight',
      legTwo.carriers[1].name,
      'then by name'
    );
    System.assertEquals(
      'Nord Cartage',
      legTwo.carriers[2].name,
      'a carrier without a priced total still shows'
    );
    System.assertEquals(
      2000.00,
      legTwo.median,
      'median of 1000, 2000 and 5000: a zero total is not priced'
    );
    System.assertEquals(3, legTwo.pricedCount, 'three priced legs');
    System.assertEquals(
      5000.00,
      o.medianTotal,
      'median of the shipment sums 2000, 7000 and 5000'
    );
    System.assertEquals(3, o.pricedShipments, 'shipment 4 has an unpriced leg');
    System.assertNotEquals(
      legOne.median + legTwo.median,
      o.medianTotal,
      'not the sum of the leg medians (R85)'
    );
  }

  /**
   * Left out, all via Laredo: a shipment with a cancelled leg, one with an intercompany leg carrier
   * and a plan with a single carrier leg. Laredo keeps its two good shipments and comes first; the
   * one-shipment groups follow by label. A three-leg shipment joins its two handoffs with an arrow; a
   * handoff without a stop account name is the city alone; a leg position without any priced total
   * shows its carrier with no median, and its group has no total.
   */
  @IsTest
  static void unusableShipmentsAreLeftOutAndGroupsAreOrdered() {
    SplitLaneService.LegRow cancelledLeg = leg(
      'Fletes Mex',
      LAREDO_ST_AUGUSTIN,
      'Client DC',
      2000
    );
    cancelledLeg.status = 'Cancelled';
    List<List<SplitLaneService.LegRow>> shipments = new List<List<SplitLaneService.LegRow>>{
      twoLegs(
        leg('Q Transportes', ESCOBEDO_LAREDO, YARD, 1000),
        leg('Fletes Mex', LAREDO_ST_AUGUSTIN, 'Client DC', 2000)
      ),
      twoLegs(
        leg('Baja Linea', 'Tijuana, BC:San Diego, CA', 'Otay Mesa yard', 800),
        leg('Pacific Haul', 'San Diego, CA:Vancouver, BC', 'Client DC', null)
      ),
      twoLegs(leg('Q Transportes', ESCOBEDO_LAREDO, YARD, 1000), cancelledLeg),
      twoLegs(
        leg('Tpml TP org', ESCOBEDO_LAREDO, YARD, 900),
        leg('Fletes Mex', LAREDO_ST_AUGUSTIN, 'Client DC', 2000)
      ),
      new List<SplitLaneService.LegRow>{
        leg(
          'Q Transportes',
          'General Escobedo, NL:St-Augustin-de-Desmaures, QC',
          'Client DC',
          3000
        )
      },
      twoLegs(
        leg('Baja Linea', 'Mexicali, BC:Calexico, CA', null, 700),
        leg('Desert Freight', 'Calexico, CA:Vancouver, BC', 'Client DC', 1500)
      ),
      new List<SplitLaneService.LegRow>{
        leg('Q Transportes', ESCOBEDO_LAREDO, YARD, 1000),
        leg('Tex Relay', 'Laredo, TX:Dallas, TX', 'Dallas cross dock', 600),
        leg('Fletes Mex', 'Dallas, TX:Toronto, ON', 'Client DC', 1800)
      },
      twoLegs(
        leg('Q Transportes', ESCOBEDO_LAREDO, YARD, 1400),
        leg('Fletes Mex', LAREDO_ST_AUGUSTIN, 'Client DC', 2200)
      )
    };
    IntercompanyCarriers.idsOverride = new Set<Id>{
      fakeCarrierId('Tpml TP org')
    };

    List<SplitLaneResult.Option> groups = SplitLaneService.groupHistory(
      shipments,
      'CAD',
      null
    );

    List<String> summary = new List<String>();
    for (SplitLaneResult.Option o : groups) {
      summary.add(o.handoffLabel + ' / ' + o.shipments);
    }
    System.assertEquals(
      new List<String>{
        'Laredo, TX · SFMN Park ITC Laredo yard / 2',
        'Calexico, CA / 1',
        'Laredo, TX · SFMN Park ITC Laredo yard → Dallas, TX · Dallas cross dock / 1',
        'San Diego, CA · Otay Mesa yard / 1'
      },
      summary,
      'most shipments first, then by label; cancelled, intercompany and one-leg shipments left out'
    );
    SplitLaneResult.Option laredo = groups[0];
    System.assertEquals(
      1200.00,
      laredo.legs[0].median,
      'median of 1000 and 1400 only'
    );
    System.assertEquals(3300.00, laredo.medianTotal, 'median of 3000 and 3600');
    SplitLaneResult.Option threeLegs = groups[2];
    System.assertEquals(3, threeLegs.legs.size(), 'three leg positions');
    System.assertEquals(3, threeLegs.legs[2].position, 'leg 3');
    System.assertEquals(
      'Dallas, TX → Toronto, ON',
      threeLegs.legs[2].laneLabel,
      'leg 3 lane'
    );
    System.assertEquals(3400.00, threeLegs.medianTotal, '1000 + 600 + 1800');
    SplitLaneResult.Option sanDiego = groups[3];
    SplitLaneResult.Leg unpricedLeg = sanDiego.legs[1];
    System.assertEquals(
      'Pacific Haul',
      unpricedLeg.carriers[0].name,
      'the carrier shows'
    );
    System.assertEquals(null, unpricedLeg.median, 'no priced total, no median');
    System.assertEquals(0, unpricedLeg.pricedCount, 'nothing priced');
    System.assertEquals(800.00, sanDiego.legs[0].median, 'leg 1 is priced');
    System.assertEquals(
      null,
      sanDiego.medianTotal,
      'no shipment has every leg priced'
    );
    System.assertEquals(0, sanDiego.pricedShipments, 'no priced shipment');
  }

  @IsTest
  static void medianTakesTheMiddleOrTheMeanOfTheTwoMiddlesAtScaleTwo() {
    System.assertEquals(
      200.00,
      SplitLaneService.median(new List<Decimal>{ 300, 100, 200 }),
      'odd count: the middle value'
    );
    System.assertEquals(
      250.00,
      SplitLaneService.median(new List<Decimal>{ 400, 100, 300, 200 }),
      'even count: the mean of the two middle values'
    );
    Decimal half = SplitLaneService.median(new List<Decimal>{ 1, 2 });
    System.assertEquals(1.50, half, 'the mean of 1 and 2');
    System.assertEquals(2, half.scale(), 'scale 2');
    System.assertEquals(
      2,
      SplitLaneService.median(new List<Decimal>{ 1234.5 }).scale(),
      'one value, scale 2'
    );
    System.assertEquals(
      null,
      SplitLaneService.median(new List<Decimal>()),
      'empty'
    );
    System.assertEquals(null, SplitLaneService.median(null), 'null');
    List<Decimal> input = new List<Decimal>{ 3, 1, 2 };
    SplitLaneService.median(input);
    System.assertEquals(3, input[0], 'the caller list keeps its order');
  }

  @IsTest
  static void amountInKeepsCadAndConvertsUsdAtTheLoadDate() {
    ExchangeRates.periodsOverride = new List<ExchangeRates.Period>{
      new ExchangeRates.Period(
        Date.newInstance(2026, 1, 5),
        Date.newInstance(2026, 1, 12),
        0.80
      ),
      new ExchangeRates.Period(
        Date.newInstance(2026, 1, 12),
        Date.newInstance(9999, 12, 31),
        0.75
      )
    };
    ExchangeRates rates = ExchangeRates.usd(Date.newInstance(2025, 12, 1));
    Datetime inFirstPeriod = Datetime.newInstanceGmt(2026, 1, 8, 12, 0, 0);
    System.assertEquals(
      1234.567,
      SplitLaneService.amountIn('CAD', rates, 1234.567, inFirstPeriod),
      'CAD is the stored amount, unrounded'
    );
    System.assertEquals(
      1234.567,
      SplitLaneService.amountIn('CAD', null, 1234.567, inFirstPeriod),
      'CAD needs no rate'
    );
    System.assertEquals(
      987.6536,
      SplitLaneService.amountIn('USD', rates, 1234.567, inFirstPeriod),
      'CAD x the rate of the period holding the load date, unrounded'
    );
    System.assertEquals(
      750.0,
      SplitLaneService.amountIn(
        'USD',
        rates,
        1000,
        Datetime.newInstanceGmt(2026, 3, 1, 12, 0, 0)
      ),
      'after the last period start: the last rate'
    );
    System.assertEquals(
      Date.newInstance(2026, 1, 12),
      rates.latestStartUsed,
      'the latest period used'
    );
    System.assertEquals(
      null,
      SplitLaneService.amountIn('USD', null, 1000, inFirstPeriod),
      'USD without rates has no amount'
    );
  }

  @IsTest
  static void carrierTallyCountsLegsAndSortsByLegsThenName() {
    SplitLaneService.CarrierTally tally = new SplitLaneService.CarrierTally();
    Id zeta = fakeCarrierId('Zeta Freight');
    Id alpha = fakeCarrierId('alpha Haul');
    Id busy = fakeCarrierId('Busy Lines');
    tally.add(zeta, 'Zeta Freight', false);
    tally.add(busy, 'Busy Lines', false);
    tally.add(alpha, 'alpha Haul', null);
    tally.add(busy, 'Busy Lines', true);
    tally.add(null, 'No Carrier', true);
    List<SplitLaneResult.LegCarrier> ranked = tally.sorted();
    System.assertEquals(3, ranked.size(), 'a leg without a carrier is ignored');
    System.assertEquals(busy, ranked[0].carrierId, 'most legs first');
    System.assertEquals(2, ranked[0].legsMoved, 'two legs');
    System.assertEquals(
      true,
      ranked[0].blacklisted,
      'blacklisted when any leg says so'
    );
    System.assertEquals(
      'alpha Haul',
      ranked[1].name,
      'then by name, ignoring case'
    );
    System.assertEquals(
      false,
      ranked[1].blacklisted,
      'a null flag is not blacklisted'
    );
    System.assertEquals('Zeta Freight', ranked[2].name, 'last by name');
    System.assertEquals(1, ranked[2].legsMoved, 'one leg');
    System.assertEquals(
      0,
      new SplitLaneService.CarrierTally().sorted().size(),
      'an empty tally'
    );
  }
}
```

Create `force-app/main/default/classes/SplitLaneServiceTest.cls-meta.xml`:

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<ApexClass xmlns="http://soap.sforce.com/2006/04/metadata">
    <apiVersion>64.0</apiVersion>
    <status>Active</status>
</ApexClass>
```

The ten tests are:

- `historyReadsTheLanePlanWithItsHandoffCarriersAndCosts` and `usdConvertsEachLegAtTheRateOfItsLoadDate` run end to end through `SplitTestData`, one shipment each.
- `usdWithoutADatedRateGivesAMessageAndReadsNoPlan` and `aBlankKeyOrAnUnknownPlaceGivesAMessage` count queries with `Limits.getQueries()`.
- `historyReadsAYearOfLanePlansWithTheirLegCosts` checks the plan SOQL string. On branch B, `FreightPlanReader.rowsOverride` ignores the lane and date filters, so this string is what proves them on both branches.
- `shipmentsViaOneHandoffShareAGroupAndTheTotalIsTheMedianOfTheirSums` and `unusableShipmentsAreLeftOutAndGroupsAreOrdered` group in-memory shipments.
- `medianTakesTheMiddleOrTheMeanOfTheTwoMiddlesAtScaleTwo`, `amountInKeepsCadAndConvertsUsdAtTheLoadDate` and `carrierTallyCountsLegsAndSortsByLegsThenName` test the helpers.

- [ ] **Step 2: Deploy the test alone to see it fail to compile**

Run: `sf project deploy start -o sandbox --source-dir force-app/main/default/classes/SplitLaneServiceTest.cls -l NoTestRun --async --json | python3 -c "import json,sys; s=sys.stdin.read(); print(json.loads(s[s.index('{'):])['result']['id'])"`

Expected: a deploy id (`0Af...`). Poll, repeating until the status is `Succeeded` or `Failed` (each call waits at most 2 minutes):

Run: `sf project deploy report -o sandbox --job-id <id> -w 2 --json | python3 -c "import json,sys; s=sys.stdin.read(); r=json.loads(s[s.index('{'):])['result']; print(r['status'], [d.get('problem') for d in r.get('details',{}).get('componentFailures',[])][:3])"`

Expected: `Failed` with `Invalid type: SplitLaneService` or `Invalid type: SplitLaneResult`, because neither class exists yet. `Invalid type: SplitTestData`, `IntercompanyCarriers`, `ExchangeRates` or `LaneQueries` means Task 1, 3 or 5 is not in the org. Stop and deploy that task first.

- [ ] **Step 3: Write the result type**

Create `force-app/main/default/classes/SplitLaneResult.cls`:

```apex
/**
 * What the split-lane card shows (phase 8, spec section 4): the currency of every amount, the start
 * date of the latest USD dated rate used (null in CAD), one Option per history group (Task 8) or
 * estimate (Task 9), whether the plan read reached its limit, and a message when the card has
 * nothing to show. Plain data, no logic. Every amount is at scale 2; the handoff cost is added on
 * the screen.
 */
public class SplitLaneResult {
  public static final String HISTORY = 'History';
  public static final String ESTIMATE = 'Estimate';

  @AuraEnabled
  public String currencyCode;
  @AuraEnabled
  public Date rateStartDate;
  @AuraEnabled
  public List<Option> options = new List<Option>();
  @AuraEnabled
  public Boolean truncated = false;
  @AuraEnabled
  public String message;

  /** A carrier on one leg position, with the legs it moved there. */
  public class LegCarrier {
    @AuraEnabled
    public Id carrierId;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public Integer legsMoved = 0;
    @AuraEnabled
    public Boolean blacklisted = false;
  }

  /** One leg position (1-based): its most frequent lane, its carriers and the median of its priced totals. */
  public class Leg {
    @AuraEnabled
    public Integer position;
    @AuraEnabled
    public String laneLabel;
    @AuraEnabled
    public List<LegCarrier> carriers = new List<LegCarrier>();
    @AuraEnabled
    public Decimal median;
    @AuraEnabled
    public Integer pricedCount = 0;
  }

  /** A history group (kind History) or an estimate through a handoff point (kind Estimate, Task 9). */
  public class Option {
    @AuraEnabled
    public String kind;
    @AuraEnabled
    public String handoffLabel;
    @AuraEnabled
    public Integer shipments = 0;
    @AuraEnabled
    public List<Leg> legs = new List<Leg>();
    @AuraEnabled
    public Decimal medianTotal;
    @AuraEnabled
    public Integer pricedShipments = 0;
    @AuraEnabled
    public Integer extraDistancePct;
  }
}
```

Create `force-app/main/default/classes/SplitLaneResult.cls-meta.xml` with the same content as the test's meta file (apiVersion 64.0, status Active).

- [ ] **Step 4: Write the service**

Create `force-app/main/default/classes/SplitLaneService.cls`:

```apex
/**
 * Split-lane options, history part (phase 8, spec section 4). The lane's Revenova freight plans over
 * the last 12 months, found through their customer load (LaneQueries.planSoql, read only through
 * FreightPlanReader), become shipments of carrier legs. A shipment is left out when it has fewer
 * than two carrier legs, a cancelled leg, or an intercompany carrier on a leg (R87). The rest are
 * grouped by their handoff sequence: after every leg but the last, the city after the last ':' of
 * the leg's rtms__City_Lane__c, then the leg's last stop account name (R105). Each group gives every
 * leg position its carriers (CarrierTally), its most frequent leg lane and the median of its priced
 * leg totals, and gives the group the median of the sums of the shipments whose legs are all priced,
 * not a sum of leg medians (R85). Leg totals are stored in CAD; in USD each one is converted at the
 * dated rate of its own load's CreatedDate before any median or sum (R109). Task 9 adds estimates
 * when history finds no group.
 *
 * The grouping lives in the inner classes HistoryGroups, ShipmentGroup and PositionTally, so their
 * branches stay out of this class's PMD complexity total (the phase 7 TripMilesService ruling).
 */
// Runs without sharing on purpose, like LaneSearchService: freight plans, loads and carrier quotes
// inherit Private load sharing, and a split benchmark reads every team's shipments. Access is gated
// by the Lane Benchmark and RFP Tool permission sets through SplitLaneController (Task 9).
public without sharing class SplitLaneService {
  private static final String USD = 'USD';
  private static final String CARRIER_ROW = 'Carrier';
  private static final String CANCELLED = 'Cancelled';
  private static final String LOAD_PATH = 'rtms__Load__r.';
  private static final String ARROW = ' → ';
  private static final String DOT = ' · ';
  private static final String NO_PLACE = 'Both ends of the lane need a place.';
  private static final String NO_USD_RATE = 'No USD exchange rate is available.';
  private static final Integer HISTORY_DAYS = 365;
  private static final Integer PLAN_LIMIT = 1000;
  private static final Integer RATE_LOOKBACK_DAYS = 400;

  /** One carrier leg of a shipment, as the history reads it from the leg load. Public so tests can group shipments built in memory. */
  public class LegRow {
    public Datetime created;
    public Id carrierId;
    public String carrierName;
    public Boolean blacklisted = false;
    public String cityLane;
    public String status;
    public Decimal cadTotal;
    public String stopName;
  }

  /** Distinct carriers of one leg position with the legs each moved; SplitEstimates (Task 9) uses it too. */
  public class CarrierTally {
    private final Map<Id, SplitLaneResult.LegCarrier> byCarrier = new Map<Id, SplitLaneResult.LegCarrier>();

    /** Counts one leg. A leg without a carrier is ignored; a carrier is blacklisted when any of its legs says so. */
    public void add(Id carrierId, String name, Boolean blacklisted) {
      if (carrierId == null) {
        return;
      }
      SplitLaneResult.LegCarrier carrier = byCarrier.get(carrierId);
      if (carrier == null) {
        carrier = new SplitLaneResult.LegCarrier();
        carrier.carrierId = carrierId;
        byCarrier.put(carrierId, carrier);
      }
      carrier.name = carrier.name ?? name;
      carrier.legsMoved++;
      carrier.blacklisted = carrier.blacklisted || blacklisted == true;
    }

    /** Most legs first, then by name ignoring case. */
    public List<SplitLaneResult.LegCarrier> sorted() {
      List<CarrierOrder> entries = new List<CarrierOrder>();
      for (SplitLaneResult.LegCarrier carrier : byCarrier.values()) {
        entries.add(new CarrierOrder(carrier));
      }
      entries.sort();
      List<SplitLaneResult.LegCarrier> ranked = new List<SplitLaneResult.LegCarrier>();
      for (CarrierOrder entry : entries) {
        ranked.add(entry.carrier);
      }
      return ranked;
    }
  }

  /**
   * The split-lane card's history for a lane, in CAD or USD (SplitLaneController refuses other
   * codes, Task 9). The request's place keys, precisions, postal prefixes and mode, equipment and
   * hazmat filters decide the lane (LaneQueries.laneConditions; a radius end uses its place's city
   * key); its lookback, currency, accepted and source filters are ignored (R101). A
   * blank key reads nothing; an unknown place reads only the places; USD without a dated rate reads
   * no plan.
   */
  public static SplitLaneResult options(
    LaneSearchRequest req,
    String currencyCode
  ) {
    req.applyDefaults();
    SplitLaneResult result = new SplitLaneResult();
    result.currencyCode = currencyCode;
    Map<String, Pricing_Place__c> places = loadPlaces(req);
    Pricing_Place__c origin = places.get(req.originKey);
    Pricing_Place__c destination = places.get(req.destinationKey);
    if (origin == null || destination == null) {
      result.message = NO_PLACE;
      return result;
    }
    ExchangeRates rates = currencyCode == USD
      ? ExchangeRates.usd(Date.today().addDays(-RATE_LOOKBACK_DAYS))
      : null;
    if (rates != null && !rates.hasRates()) {
      result.message = NO_USD_RATE;
      return result;
    }
    Map<String, Object> binds = new Map<String, Object>();
    List<rtms__FreightPlan__c> plans = FreightPlanReader.read(
      historySoql(req, origin, destination, binds),
      binds
    );
    result.truncated = plans.size() >= PLAN_LIMIT;
    List<List<LegRow>> shipments = new List<List<LegRow>>();
    for (rtms__FreightPlan__c plan : plans) {
      shipments.add(legRows(plan));
    }
    result.options = groupHistory(shipments, currencyCode, rates);
    result.rateStartDate = rates?.latestStartUsed;
    return result;
  }

  /** Null for null or empty; odd count the middle value, even count the mean of the two middle values; scale 2. The list is not changed. */
  public static Decimal median(List<Decimal> values) {
    if (values == null || values.isEmpty()) {
      return null;
    }
    List<Decimal> ordered = values.clone();
    ordered.sort();
    Integer n = ordered.size();
    Decimal middle = Math.mod(n, 2) == 1
      ? ordered[n / 2]
      : (ordered[n / 2 - 1] + ordered[n / 2]) / 2;
    return middle.setScale(2);
  }

  /** A stored CAD amount in the card currency: USD at the dated rate of the load's CreatedDate (null without rates), otherwise the CAD amount. Unrounded. */
  public static Decimal amountIn(
    String currencyCode,
    ExchangeRates rates,
    Decimal cadAmount,
    Datetime loadCreated
  ) {
    return currencyCode == USD
      ? rates?.fromCad(cadAmount, loadCreated)
      : cadAmount;
  }

  /** The plan read: a year of customer loads on the lane, at most PLAN_LIMIT plans, with the leg amounts, lanes and last stop accounts. */
  @TestVisible
  private static String historySoql(
    LaneSearchRequest req,
    Pricing_Place__c origin,
    Pricing_Place__c destination,
    Map<String, Object> binds
  ) {
    return LaneQueries.planSoql(
      LaneQueries.laneConditions(req, origin, destination, LOAD_PATH, binds),
      HISTORY_DAYS,
      PLAN_LIMIT,
      true
    );
  }

  /**
   * Groups shipments (each a list of carrier legs in plan order) into history options, most
   * shipments first. @TestVisible so tests group shipments built in memory: a split shipment is three
   * loads, and the load automation leaves room for one per test (PricingTestDataFactory's class doc).
   */
  @TestVisible
  private static List<SplitLaneResult.Option> groupHistory(
    List<List<LegRow>> shipments,
    String currencyCode,
    ExchangeRates rates
  ) {
    return new HistoryGroups(currencyCode, rates, IntercompanyCarriers.ids())
      .build(shipments);
  }

  // System mode by design (see the class comment): places are reference data every pricer reads.
  @SuppressWarnings('PMD.ApexCRUDViolation')
  private static Map<String, Pricing_Place__c> loadPlaces(
    LaneSearchRequest req
  ) {
    Map<String, Pricing_Place__c> byKey = new Map<String, Pricing_Place__c>();
    if (String.isBlank(req.originKey) || String.isBlank(req.destinationKey)) {
      return byKey;
    }
    Set<String> keys = new Set<String>{ req.originKey, req.destinationKey };
    for (Pricing_Place__c p : [
      SELECT
        Id,
        Key__c,
        City__c,
        Province__c,
        Country__c,
        Postal_Prefix__c,
        Spellings__c,
        Geolocation__Latitude__s,
        Geolocation__Longitude__s
      FROM Pricing_Place__c
      WHERE Key__c IN :keys
    ]) {
      byKey.put(p.Key__c, p);
    }
    return byKey;
  }

  /** The plan's Carrier rows as legs, in the reader's rtms__Number__c order; the Customer row is skipped. A for loop, because a child list over 200 rows read directly throws. */
  private static List<LegRow> legRows(rtms__FreightPlan__c plan) {
    List<LegRow> legs = new List<LegRow>();
    for (rtms__FreightPlanLoad__c row : plan.rtms__Freight_Plan_Loads__r) {
      if (row.rtms__Type__c == CARRIER_ROW) {
        legs.add(toLegRow(row.rtms__Load__r));
      }
    }
    return legs;
  }

  /** A leg load as a LegRow; the carrier and last stop relationships may be absent (no carrier, or a row built by JSON.deserialize). */
  private static LegRow toLegRow(rtms__Load__c load) {
    LegRow leg = new LegRow();
    leg.created = load.CreatedDate;
    leg.carrierId = load.rtms__Carrier__c;
    leg.carrierName = load.rtms__Carrier__r?.Name;
    leg.blacklisted = load.rtms__Carrier__r?.Black_List__c == true;
    leg.cityLane = load.rtms__City_Lane__c;
    leg.status = load.rtms__Load_Status__c;
    leg.cadTotal = load.rtms__Carrier_Quote_Total__c;
    leg.stopName = load.rtms__Last_Stop__r?.rtms__Location2__r?.Name;
    return leg;
  }

  private static String sortName(String name) {
    return name == null ? '' : name.toLowerCase();
  }

  /** Builds the history options from shipments for one card currency and one intercompany list. */
  private class HistoryGroups {
    private final String currencyCode;
    private final ExchangeRates rates;
    private final Set<Id> intercompany;

    private HistoryGroups(
      String currencyCode,
      ExchangeRates rates,
      Set<Id> intercompany
    ) {
      this.currencyCode = currencyCode;
      this.rates = rates;
      this.intercompany = intercompany;
    }

    private List<SplitLaneResult.Option> build(List<List<LegRow>> shipments) {
      Map<String, ShipmentGroup> byKey = new Map<String, ShipmentGroup>();
      for (List<LegRow> legs : shipments) {
        if (!usable(legs)) {
          continue;
        }
        String label = handoffLabel(legs);
        String key = legs.size() + '|' + label.toLowerCase();
        if (!byKey.containsKey(key)) {
          byKey.put(key, new ShipmentGroup(label, legs.size()));
        }
        byKey.get(key).add(legs, amounts(legs));
      }
      List<ShipmentGroup> ordered = byKey.values();
      ordered.sort();
      List<SplitLaneResult.Option> built = new List<SplitLaneResult.Option>();
      for (ShipmentGroup shipmentGroup : ordered) {
        built.add(shipmentGroup.toOption());
      }
      return built;
    }

    /** Two carrier legs or more, none cancelled and none moved by an intercompany carrier (R87). */
    private Boolean usable(List<LegRow> legs) {
      if (legs.size() < 2) {
        return false;
      }
      for (LegRow leg : legs) {
        if (leg.status == CANCELLED || intercompany.contains(leg.carrierId)) {
          return false;
        }
      }
      return true;
    }

    /** The handoffs after every leg but the last, joined with an arrow. */
    private String handoffLabel(List<LegRow> legs) {
      List<String> handoffs = new List<String>();
      for (Integer i = 0; i < legs.size() - 1; i++) {
        handoffs.add(handoff(legs[i]));
      }
      return String.join(handoffs, ARROW);
    }

    /** "Laredo, TX · SFMN Park ITC Laredo yard": the city after the last ':' of the leg lane, then the leg's last stop account name when it has one. */
    private String handoff(LegRow leg) {
      List<String> parts = new List<String>();
      String city = leg.cityLane == null
        ? ''
        : leg.cityLane.substringAfterLast(':').trim();
      if (String.isNotBlank(city)) {
        parts.add(city);
      }
      if (String.isNotBlank(leg.stopName)) {
        parts.add(leg.stopName.trim());
      }
      return String.join(parts, DOT);
    }

    /** Each leg's amount in the card currency; null when the leg has no CAD total above zero. */
    private List<Decimal> amounts(List<LegRow> legs) {
      List<Decimal> converted = new List<Decimal>();
      for (LegRow leg : legs) {
        converted.add(
          leg.cadTotal != null &&
            leg.cadTotal > 0
            ? SplitLaneService.amountIn(
                currencyCode,
                rates,
                leg.cadTotal,
                leg.created
              )
            : null
        );
      }
      return converted;
    }
  }

  /** One handoff sequence: its shipment count, a tally per leg position and the sums of its fully priced shipments. */
  private class ShipmentGroup implements Comparable {
    private final String label;
    private final List<PositionTally> positions = new List<PositionTally>();
    private final List<Decimal> sums = new List<Decimal>();
    private Integer shipments = 0;

    private ShipmentGroup(String label, Integer legCount) {
      this.label = label;
      for (Integer i = 1; i <= legCount; i++) {
        positions.add(new PositionTally(i));
      }
    }

    private void add(List<LegRow> legs, List<Decimal> amounts) {
      shipments++;
      Decimal shipmentSum = 0;
      for (Integer i = 0; i < legs.size(); i++) {
        positions[i].add(legs[i], amounts[i]);
        shipmentSum = shipmentSum == null ||
          amounts[i] == null
          ? null
          : shipmentSum + amounts[i];
      }
      if (shipmentSum != null) {
        sums.add(shipmentSum);
      }
    }

    private SplitLaneResult.Option toOption() {
      SplitLaneResult.Option built = new SplitLaneResult.Option();
      built.kind = SplitLaneResult.HISTORY;
      built.handoffLabel = label;
      built.shipments = shipments;
      for (PositionTally tally : positions) {
        built.legs.add(tally.toLeg());
      }
      built.medianTotal = SplitLaneService.median(sums);
      built.pricedShipments = sums.size();
      return built;
    }

    /** Most shipments first, then by handoff label ignoring case. */
    public Integer compareTo(Object other) {
      ShipmentGroup that = (ShipmentGroup) other;
      if (shipments != that.shipments) {
        return shipments > that.shipments ? -1 : 1;
      }
      return SplitLaneService.sortName(label)
        .compareTo(SplitLaneService.sortName(that.label));
    }
  }

  /** One leg position of a group: its carriers, its leg lanes by frequency and its priced amounts. */
  private class PositionTally {
    private final Integer position;
    private final CarrierTally carriers = new CarrierTally();
    private final List<Decimal> priced = new List<Decimal>();
    private final Map<String, Integer> laneCounts = new Map<String, Integer>();
    private final List<String> lanesInOrder = new List<String>();

    private PositionTally(Integer position) {
      this.position = position;
    }

    private void add(LegRow leg, Decimal amount) {
      carriers.add(leg.carrierId, leg.carrierName, leg.blacklisted);
      if (amount != null) {
        priced.add(amount);
      }
      if (String.isBlank(leg.cityLane)) {
        return;
      }
      if (!laneCounts.containsKey(leg.cityLane)) {
        laneCounts.put(leg.cityLane, 0);
        lanesInOrder.add(leg.cityLane);
      }
      laneCounts.put(leg.cityLane, laneCounts.get(leg.cityLane) + 1);
    }

    private SplitLaneResult.Leg toLeg() {
      SplitLaneResult.Leg built = new SplitLaneResult.Leg();
      built.position = position;
      built.laneLabel = mostFrequentLane();
      built.carriers = carriers.sorted();
      built.median = SplitLaneService.median(priced);
      built.pricedCount = priced.size();
      return built;
    }

    /** The leg lane seen most often at this position (ties: the first seen), with an arrow for its ':'. */
    private String mostFrequentLane() {
      String best;
      for (String lane : lanesInOrder) {
        if (best == null || laneCounts.get(lane) > laneCounts.get(best)) {
          best = lane;
        }
      }
      return best == null ? null : best.replace(':', ARROW);
    }
  }

  /** Sort wrapper for CarrierTally.sorted(): most legs first, then by name ignoring case. */
  private class CarrierOrder implements Comparable {
    private final SplitLaneResult.LegCarrier carrier;

    private CarrierOrder(SplitLaneResult.LegCarrier carrier) {
      this.carrier = carrier;
    }

    public Integer compareTo(Object other) {
      SplitLaneResult.LegCarrier that = ((CarrierOrder) other).carrier;
      if (carrier.legsMoved != that.legsMoved) {
        return carrier.legsMoved > that.legsMoved ? -1 : 1;
      }
      return SplitLaneService.sortName(carrier.name)
        .compareTo(SplitLaneService.sortName(that.name));
    }
  }
}
```

Create `force-app/main/default/classes/SplitLaneService.cls-meta.xml` with the same content as the test's meta file (apiVersion 64.0, status Active).

- [ ] **Step 5: Check the formatting**

Run: `npx prettier --check force-app/main/default/classes/SplitLaneResult.cls force-app/main/default/classes/SplitLaneService.cls force-app/main/default/classes/SplitLaneServiceTest.cls`

Expected: `All matched files use Prettier code style!` (the code above was formatted with the repo's `.prettierrc` and `prettier-plugin-apex`). If a file is listed, run the same command with `--write` in place of `--check`; lint-staged would make the same change on commit.

- [ ] **Step 6: Add the classes to the manifest**

In `manifest/package.xml`, inside the `<types>` block whose `<name>` is `ApexClass`, directly before `<name>ApexClass</name>` (after the members Tasks 1 to 6 added):

```xml
        <members>SplitLaneResult</members>
        <members>SplitLaneService</members>
        <members>SplitLaneServiceTest</members>
```

Run: `grep -c "<members>SplitLane" manifest/package.xml`

Expected: `3`.

- [ ] **Step 7: Deploy the three classes and run the tests**

`SplitTestDataTest` runs as well: it proves in the same deploy that the Task 1 plan builder still works, and `SplitLaneServiceTest` depends on that builder.

Run: `sf project deploy start -o sandbox --source-dir force-app/main/default/classes/SplitLaneResult.cls --source-dir force-app/main/default/classes/SplitLaneService.cls --source-dir force-app/main/default/classes/SplitLaneServiceTest.cls -l RunSpecifiedTests -t SplitLaneServiceTest -t SplitTestDataTest --async --json | python3 -c "import json,sys; s=sys.stdin.read(); print(json.loads(s[s.index('{'):])['result']['id'])"`

Expected: a deploy id. Poll until the status is `Succeeded` or `Failed`:

Run: `sf project deploy report -o sandbox --job-id <id> -w 2 --json | python3 -c "import json,sys; s=sys.stdin.read(); r=json.loads(s[s.index('{'):])['result']; t=r.get('details',{}).get('runTestResult',{}); print(r['id'], r['status'], 'tests', r.get('numberTestsCompleted'), '/', r.get('numberTestsTotal'), 'failures', r.get('numberTestErrors')); [print(f['name'], f['methodName'], '->', f['message'][:200]) for f in t.get('failures',[])]; [print('coverage', c['name'], int(c['numLocations']) - int(c['numLocationsNotCovered']), '/', c['numLocations']) for c in t.get('codeCoverage',[]) if c['name'] in ('SplitLaneService','SplitLaneResult')]; [print('component', d.get('fullName'), d.get('problem')) for d in r.get('details',{}).get('componentFailures',[])][:5]"`

Expected: `Succeeded`, tests `N / N` with `N` = 10 + the `SplitTestDataTest` test count from Step 1, and failures `0`. Coverage should be above 75 % for both classes: about 100 % for `SplitLaneResult` and above 90 % for `SplitLaneService`. The `truncated` branch at 1000 plans is covered only as a comparison.

If a test fails, fix the class, not the assertion, unless the assertion contradicts the spec. What each failure most likely means:

- `Too many SOQL queries: 101` in an end-to-end test means Task 1's `legLoad` costs more than `createLoad`. Keep the one-load-before / two-loads-inside split and do not add a load. Report it with the test name, and see Contract note 3.
- `Too many SOQL queries: 101` before `Test.startTest()` (stack through `fixture()`): move `f.qTransportes = SplitTestData.carrier('Q Transportes', false);` and `f.fletes = SplitTestData.carrier('Fletes Mex', true);` out of `fixture()` to the first lines after `Test.startTest()` in both end-to-end tests (carriers need no `Test.setCreatedDate`).
- `historyReadsTheLanePlanWithItsHandoffCarriersAndCosts` with 0 options on branch A means the semi-join did not match the customer load (`Monterrey, NL:Toronto, ON`). Check `LaneQueries.laneConditions` (Task 5) against the load's `rtms__City_Lane__c`.
- The same test with 3 legs means the Customer row was read as a leg.
- A handoff label without the yard means the plan row lacks `rtms__Last_Stop__r.rtms__Location2__r.Name`: Task 1 branch B's JSON, or `planSoql(..., true)`.
- `usdConvertsEachLegAtTheRateOfItsLoadDate` with 750.00 on leg 1 means the conversion did not use the leg load's `CreatedDate`: branch B must re-query the loads after `Test.setCreatedDate`.
- `rateStartDate` null in that test means `ExchangeRates.latestStartUsed` was not recorded (Task 3).

- [ ] **Step 8: PMD**

Run: `/private/tmp/pmd_install/pmd-bin-7.15.0/bin/pmd check --dir force-app --rulesets config/pmd-ruleset.xml --minimum-priority 3 --format text --fail-on-violation; echo "pmd exit $?"`

Expected: no violation lines, `pmd exit 0`. The only suppression this task adds is `ApexCRUDViolation` on `SplitLaneService.loadPlaces` (the places read in system mode). Measured on the code above, the complexity totals are:

| Class | Total cyclomatic complexity (budget 40) |
| --- | --- |
| `SplitLaneService` | 25 |
| `HistoryGroups` | 21 |
| `ShipmentGroup` | 12 |
| `PositionTally` | 11 |
| `CarrierTally` | 6 |
| `CarrierOrder` | 4 |

That leaves Task 9 room for the estimate call and its message in `options`. If PMD flags the class, move a private helper into an inner class; do not raise the budget.

- [ ] **Step 9: Commit**

```bash
git add force-app/main/default/classes/SplitLaneResult.cls force-app/main/default/classes/SplitLaneResult.cls-meta.xml force-app/main/default/classes/SplitLaneService.cls force-app/main/default/classes/SplitLaneService.cls-meta.xml force-app/main/default/classes/SplitLaneServiceTest.cls force-app/main/default/classes/SplitLaneServiceTest.cls-meta.xml manifest/package.xml
git commit -m "Add split-lane history: handoff groups, leg carriers and medians, USD at the dated rate"
```

Expected: lint-staged runs Prettier on the staged files (no change after Step 5) and the commit lands on `phase-8/carriers-and-split-lanes`. `git status --short` still shows `.vscode/settings.json` and the `* 2.*` files unstaged. The commit message has no trailer.

#### Contract notes (Task 8)

1. **`SplitLaneService.LegRow` and `@TestVisible groupHistory(List<List<LegRow>> shipments, String currencyCode, ExchangeRates rates)` are added.** The contract names neither.
   - `LegRow` holds a leg load's `CreatedDate`, carrier Id, name and `Black_List__c`, `rtms__City_Lane__c`, `rtms__Load_Status__c`, `rtms__Carrier_Quote_Total__c` and last stop account name. `options` maps each plan's Carrier rows into it (`legRows`, `toLegRow`), and the grouping reads nothing else.
   - The tests group shipments built in memory, because a split shipment is three loads. `PricingTestDataFactory`'s class doc and `LaneSearchServiceTest` record that three `createLoad()` calls in one governor window reached 101 SOQL queries. `bidsMergeIntoRowsAndObeyTheSourceFilter` needed its setup moved out of `Test.startTest()` for two loads (commit `53f1adc`).
   - The contract's "at most 3 plans with 2 legs" per test therefore cannot be met end to end. An in-memory `LegRow` list inserts nothing and is not a plan fixture: every plan the tests build still goes through `SplitTestData.plan`. `LegRow` is a public inner class, because Apex inner classes cannot hold static members (so no `LegRow.fromLoad`) and the tests set its fields.
2. **`@TestVisible historySoql(req, origin, destination, binds)` is added.** It returns `LaneQueries.planSoql(LaneQueries.laneConditions(req, origin, destination, 'rtms__Load__r.', binds), 365, 1000, true)`. On branch B, `FreightPlanReader.rowsOverride` ignores the lane and date filters, so the contract's rule applies: a test proves them on the SOQL string. It checks the lane, the year, the limit and the amount fields.
3. **Where fixture DML sits: one load before `Test.startTest()`, two inside it.** The end-to-end tests make two loads and call `SplitTestData.plan` inside `Test.startTest()`, which departs from "fixture DML before Test.startTest()". This is the shape `hazmatMarketTestAcceptedAndExcludedContactFilters` passes with (one load outside, two inside). The USD test makes leg 1 before `Test.startTest()` because `Test.setCreatedDate` is refused after it; the customer load and leg 2 go inside.
   - Not measured: Task 1's `legLoad` may add a follow-up update (branch A or B). If `Too many SOQL queries: 101` appears, report it with the test name; do not add a load.
   - Read-only check: no leg load belongs to two plans in the last 60 days (`soql/t8_leg_multi_plan.json`, totalSize 0). So the tests never reuse a load across plans to save inserts, which would be unrealistic and could be refused on branch A.
4. **`options` calls `req.applyDefaults()` first**, as Carriers to ask does (Task 6). A request deserialized from JSON has null precisions and lists until `applyDefaults()` runs, and `LaneLoadFilters.add` reads `modes`, `equipmentCategories` and `equipmentTypes`. `validate()` is not used: it would also check the lookback, the radius and the request currency, which the split card ignores (R101), and the first search has already validated the same request. `applyDefaults()` runs no query, so a blank key still reads nothing.
   - A blank key returns the message before the places read (0 queries).
   - An unknown key returns it after the one places read (1 query). `LaneSearchService.loadPlaces` throws in that case; this service returns the contract's message instead.
5. **Handoff label details.**
   - The city (text after the last `:`, trimmed) and the stop account name (trimmed) are joined with ` · ` and only the non-blank parts are kept, so a leg without a stop account gives `Calexico, CA`, never `Calexico, CA · `.
   - The group key is `<leg count>|<label lowercased>`, so shipments with different leg counts never share a group and positions always line up.
   - Label and carrier-name ordering ignore case. A carrier keeps the first non-null name it was added with.
6. **Amounts.**
   - A leg is priced when its CAD total is above 0 and its converted amount is not null.
   - `amountIn('USD', null, ...)` returns null through safe navigation. Any code other than `USD` returns the CAD amount; the controller refuses other codes (Task 9).
   - Sums are taken unrounded; `median` applies `setScale(2)` once. The tests pick values with no `.xx5` tie, so the rounding mode of `Decimal.setScale(2)` never matters.
7. **With no history group, Task 8 returns empty `options` and a null `message`.** Task 9 adds the estimate call and `No split shipment on this lane in the last 12 months, and no handoff point is close enough for an estimate.`, as the contract says. The messages are private constants in `SplitLaneService`, and the tests assert their literal text.
8. **`SplitLaneResult` is `public class`, like `LaneSearchResult`**, with no sharing keyword, because it has no query or DML. The `@AuraEnabled` fields, their initializers and the two constants are exactly the contract's.
9. **Inner classes call the outer helpers qualified** (`SplitLaneService.median`, `amountIn`, `sortName`). This is a precaution: the repo's inner classes (`LaneSearchQueryBuilder.LaneEnd`, `TripMilesService.Store`) read only outer constants, so nothing in the repo shows an unqualified call to an outer static method compiling. Sorting uses `Comparable` wrappers (`ShipmentGroup`, `CarrierOrder`), not `System.Comparator`, which the repo does not use yet.
10. **The ` → ` and ` · ` separators are literal UTF-8 in the Apex source.** The repo already compiles accented literals such as `'Montréal'`, and Prettier (`prettier-plugin-apex`) parsed all three files.
11. **The test places and locations are real values in PostProduc** (read-only checks in `soql/t8_mx_states.json` and `soql/t8_mx_us_locations.json`).
    - State and country picklists are on: `SELECT ShippingStateCode FROM Account` compiles.
    - `Nuevo León` / `Mexico` is a valid pair: 167 Monterrey-area accounts, state code NL.
    - Laredo accounts use `Texas` / `United States`.
    - `PlaceNormalizer.provinceCode` maps `Nuevo León` to `NL` and `Texas` to `TX`, so the loads get the lanes `Monterrey, NL:Toronto, ON`, `Monterrey, NL:Laredo, TX` and `Laredo, TX:Toronto, ON`.
12. **No new SOQL shape to prove.** The plan query is the contract's verified parent-child query with amounts (built by Task 5). The places read is `LaneSearchService.loadPlaces`'s field list plus `Id`.

**Open issues**

- The SOQL cost of `SplitTestData.legLoad` and of `SplitTestData.plan` on branch A (managed junction triggers) is unknown until Task 1 runs. The end-to-end tests have the smallest load count that still proves the row mapping. If they hit the limit, the in-memory grouping tests still cover the logic, and the mapping could move to a test that builds a plan with a single leg-bearing shipment and no second `options` call.
- Leg order relies on the child subquery's `ORDER BY rtms__Number__c` (branch A) and on `SplitTestData.plan` adding rows in `rtms__Number__c` order (branch B); `legRows` does not sort again.
- The rate day is `loadCreated.date()` in the running user's time zone (contract A5, Task 3). A load created near midnight on the first day of a new rate week can take the neighbouring week's rate.
- The `truncated` branch (1000 plans) has no test, because building 1000 plans is impossible under the load budget.


---

### Task 9: Split estimates and controller — `SplitEstimates`, the leg reads, `SplitLaneController` and its class access

**Files:**

- Create: `force-app/main/default/classes/SplitEstimates.cls`, `force-app/main/default/classes/SplitEstimates.cls-meta.xml`
- Create: `force-app/main/default/classes/SplitEstimatesTest.cls`, `force-app/main/default/classes/SplitEstimatesTest.cls-meta.xml`
- Create: `force-app/main/default/classes/SplitLaneController.cls`, `force-app/main/default/classes/SplitLaneController.cls-meta.xml`
- Create: `force-app/main/default/classes/SplitLaneControllerTest.cls`, `force-app/main/default/classes/SplitLaneControllerTest.cls-meta.xml`
- Modify: `force-app/main/default/classes/LaneQueries.cls` (two public static methods `legConditions` and `legLoadSoql`, added before the class's closing brace)
- Modify: `force-app/main/default/classes/LaneQueriesTest.cls` (two test methods, added before the class's closing brace)
- Modify: `force-app/main/default/classes/SplitLaneService.cls` (the constant `NO_OPTION_MESSAGE`, and in `options` the estimate call and the no-option message after the history block, before `rateStartDate` is set)
- Modify: `force-app/main/default/classes/SplitLaneServiceTest.cls` (three test methods, added before the class's closing brace)
- Modify: `force-app/main/default/classes/CarrierSplitSecurityTest.cls` (two test methods, added before the class's closing brace)
- Modify: `force-app/main/default/permissionsets/Lane_Benchmark_User.permissionset-meta.xml` and `force-app/main/default/permissionsets/RFP_Tool_User.permissionset-meta.xml` (class access `SplitLaneController`, in alphabetical place just before `TripRouteView`)
- Modify: `manifest/package.xml` (ApexClass members `SplitEstimates`, `SplitEstimatesTest`, `SplitLaneController`, `SplitLaneControllerTest`, directly before `<name>ApexClass</name>`)

Every anchor below is found by its text, never by a line number.

**Interfaces:**

- Consumes:
  - `LaneKeyMatcher.condition(String loadPath, Boolean isOrigin, String bindPrefix, LaneSearchRequest.Precision precision, Pricing_Place__c place, String explicitZip3, Map<String, Object> binds)` and `LaneLoadFilters.add(LaneSearchRequest req, String loadPath, List<String> conditions, Map<String, Object> binds)` (Task 2): with loadPath `''` they give `rtms__City_Lane__c LIKE :oCity` (a `List<String>` of patterns), `rtms__State_Lane__c LIKE :oProv`, `rtms__Zip3_Lane__c LIKE :oZip3`, `rtms__Mode__r.Name IN :modes`, `rtms__Equipment_Type__r.rtms__Category__c IN :cats`, `rtms__Hazardous_Materials__c = true`; RADIUS is matched as CITY; a blank postal prefix throws the `LaneSearchException` "Place <key> has no postal prefix; pass originZip3".
  - `IntercompanyCarriers.ids()` and `@TestVisible private static Set<Id> idsOverride`; `HandoffPoints.activeKeys()` and `@TestVisible private static List<String> keysOverride`; `ExchangeRates.usd(Date fromDate)`, `fromCad`, `latestStartUsed`, `ExchangeRates.Period(Date startDate, Date nextStartDate, Decimal rate)` and `@TestVisible private static List<ExchangeRates.Period> periodsOverride` (Task 3).
  - `LaneQueries.deepPrecision(LaneSearchRequest.Precision p)` and the class `LaneQueries`, `LaneQueriesTest` (Task 5).
  - `CarrierSplitSecurityTest` (Task 6).
  - `SplitLaneResult` (`Option`, `Leg`, `LegCarrier`, `ESTIMATE`, `HISTORY`, `options`, `message`, `currencyCode`, `rateStartDate`), `SplitLaneService.options(LaneSearchRequest req, String currencyCode)` with its locals `origin`, `destination`, `rates` and `result`, `SplitLaneService.median(List<Decimal> values)`, `SplitLaneService.amountIn(String currencyCode, ExchangeRates rates, Decimal cadAmount, Datetime loadCreated)`, `SplitLaneService.CarrierTally` (`add(Id carrierId, String name, Boolean blacklisted)`, `sorted()`), and the class `SplitLaneServiceTest` (Task 8).
  - `SplitTestData.carrier(String name, Boolean blacklisted)`, `SplitTestData.legLoad(PricingTestDataFactory.Graph g, Account origin, Account destination, Account carrierAccount, Decimal cadTotal, String status)`, `SplitTestData.plan(rtms__Load__c customerLoad, List<rtms__Load__c> legLoads)` (Task 1; either branch).
  - Existing: `TruckRoute.defaultProfile()`; `TripMilesService.approxMiles(Pricing_Place__c o, Pricing_Place__c d, TruckRoute.Profile p)` (great-circle miles × the Approx factor, `setScale(1)`, null without coordinates); `PlaceNormalizer.key(city, province, country)`; `PricingTestDataFactory.createGraph()` (`vendor` "Test Carrier", `destinationLocation` Toronto, Ontario, Canada, `mode` Truckload), `createLocation(name, city, province, country, postalCode, lat, lng)`, `createLoad(Graph, Account, Account)`; `RfpTestDataFactory.createPlace(city, prov, country, lat, lng, prefix)`, `restrictedUser(String permSetName)`; the permission sets `Lane_Benchmark_User` and `RFP_Tool_User`.
- Produces:
  - On `LaneQueries`:
    - `public static List<String> legConditions(LaneSearchRequest req, Pricing_Place__c fromPlace, LaneSearchRequest.Precision fromPrecision, String fromZip3, Pricing_Place__c toPlace, LaneSearchRequest.Precision toPrecision, String toZip3, Map<String, Object> binds)` — `[<from end with prefix 'o'>, <to end with prefix 'd'>, <mode, equipment, hazmat on the load>, "rtms__Load_Status__c != 'Cancelled'"]` with loadPath `''`; `null` when an end cannot be matched.
    - `public static String legLoadSoql(List<String> conditions, Integer days, Integer rowLimit, Map<String, Object> binds)` — `SELECT Id, CreatedDate, rtms__Carrier__c, rtms__Carrier__r.Name, rtms__Carrier__r.Black_List__c, rtms__Carrier_Quote_Total__c FROM rtms__Load__c WHERE <conditions> AND CreatedDate = LAST_N_DAYS:<days> AND rtms__Carrier__c != null AND rtms__Carrier_Quote_Total__c > 0 AND rtms__Carrier__c NOT IN :intercompany ORDER BY CreatedDate DESC LIMIT <rowLimit>`; puts the `intercompany` bind (`IntercompanyCarriers.ids()`); leaves `conditions` unchanged.
  - `public without sharing class SplitEstimates`:
    - `public static List<SplitLaneResult.Option> estimate(LaneSearchRequest req, Pricing_Place__c origin, Pricing_Place__c destination, String currencyCode, ExchangeRates rates)` — at most 3 `Estimate` options, least extra distance first (then place key), each with `handoffLabel` "<City__c>, <Province__c>", `extraDistancePct`, `shipments` 0, legs 1 and 2 (`laneLabel` "<from City__c>, <from Province__c> → <to City__c>, <to Province__c>", carriers through `CarrierTally`, `median`, `pricedCount`) and `medianTotal` = leg 1 median + leg 2 median when both are set. One place read plus two leg reads per point; no callout.
    - `@TestVisible private static final` `MAX_EXTRA` 0.10, `MAX_POINTS` 3, `LEG_DAYS` 365, `LEG_LIMIT` 500.
  - On `SplitLaneService`: `public static final String NO_OPTION_MESSAGE = 'No split shipment on this lane in the last 12 months, and no handoff point is close enough for an estimate.'`; `options` runs `SplitEstimates.estimate` only when history found no group, and sets `message` to `NO_OPTION_MESSAGE` when there is still no option.
  - `public with sharing class SplitLaneController` — `@AuraEnabled(cacheable=true) public static SplitLaneResult splitOptions(String requestJson, String currencyCode, Integer attempt)`: a `currencyCode` other than exactly `CAD` or `USD` throws `AuraHandledException` "Choose CAD or USD." before any query; unreadable JSON throws "The search request could not be read. Please reset the filters and try again."; `LaneSearchException` and `QueryException` become `AuraHandledException` as in `LaneBenchmarkController.search`; `attempt` is ignored.
  - Class access `SplitLaneController` in `Lane_Benchmark_User` and `RFP_Tool_User`.
  - Test classes `SplitEstimatesTest` (6 tests) and `SplitLaneControllerTest` (5 tests); `LaneQueriesTest` +2, `SplitLaneServiceTest` +3, `CarrierSplitSecurityTest` +2. The Apex roster reaches its phase 8 total of 40 classes here (Task 11 writes the roster sites).

Fixture budget (from `PricingTestDataFactory`'s class doc, `LaneSearchServiceTest.hazmatAcceptedAndExcludedContactFiltersNeverReturnMarketTestQuotes` and Tasks 1 and 8): the load automation is not bulkified, and three loads in one governor window reach 101 SOQL queries. Every test here builds at most one load before `Test.startTest()` and at most two inside it, and uses the graph's vendor ("Test Carrier") as a carrier wherever a second carrier account is not needed. Point selection, rounding and the SOQL shape run on places alone, without a load.

Distances used by the tests (great circle on a 3,958.7613 mi sphere × 1.2, each distance `setScale(1)`, computed for this plan):

| Lane | Direct | Via | Origin → point + point → destination | Extra | `extraDistancePct` |
| --- | --- | --- | --- | --- | --- |
| General Escobedo, NL (25.8000, -100.3167) → Toronto, ON (43.6532, -79.3832) | 2044.0 | Little Rock, AR (34.7465, -92.2896) | 937.6 + 1108.0 = 2045.6 | 0.078 % | 0 |
| | | Laredo, TX (27.5306, -99.4803) | 156.3 + 1893.6 = 2049.9 | 0.289 % | 0 |
| | | St. Louis, MO (38.6270, -90.1994) | 1276.6 + 792.6 = 2069.2 | 1.233 % | 1 |
| | | Chicago, IL (41.8781, -87.6298) | 1589.9 + 522.8 = 2112.7 | 3.361 % | 3 |
| | | San Diego, CA (32.7157, -117.1611) | 1344.4 + 2597.2 = 3941.6 | 92.84 % (dropped) | — |
| General Escobedo, NL → San Diego, CA | 1344.4 | Calexico, CA (32.6789, -115.4989) | 1235.8 + 116.0 = 1351.8 | 0.550 % | 1 (half up) |
| | | Laredo, TX | 156.3 + 1336.8 = 1493.1 | 11.06 % (dropped) | — |

The Approx factor cancels out of the ratio; only the one-decimal rounding of each distance depends on it, and no value above sits near a rounding edge. St-Augustin-de-Desmaures, QC (46.7406, -71.4583), the spec's browser-check destination, gives the same picture: via Laredo +0.27 %, via San Diego +72 %, via Calexico +65 %.

- [ ] **Step 1: Check that the earlier tasks are in place and nothing collides**

Run:

```bash
cd /Users/iulian/Documents/Personal/PricingDepartemnt-phase8 && git status --short && ls force-app/main/default/classes/{LaneKeyMatcher,LaneLoadFilters,IntercompanyCarriers,HandoffPoints,ExchangeRates,LaneQueries,LaneQueriesTest,CarrierSplitSecurityTest,SplitLaneResult,SplitLaneService,SplitLaneServiceTest,SplitTestData,FreightPlanReader}.cls && ls force-app/main/default/classes/SplitEstimates*.cls force-app/main/default/classes/SplitLaneController*.cls 2>&1 | head -2 && grep -n "legConditions\|legLoadSoql\|NO_OPTION_MESSAGE\|SplitEstimates" force-app/main/default/classes/LaneQueries.cls force-app/main/default/classes/SplitLaneService.cls; echo "grep exit $?"; grep -n "rateStartDate\|public static SplitLaneResult options\|return result;" force-app/main/default/classes/SplitLaneService.cls
```

Expected: `git status --short` lists only ` M .vscode/settings.json` and the untracked `* 2.*` duplicates (Task 8 is committed); the thirteen `.cls` paths print; the `SplitEstimates*`/`SplitLaneController*` listing prints `No such file or directory`; `grep exit 1` (no leg method, message constant or estimate call yet); the last grep prints the `options` signature, the line `result.rateStartDate = rates?.latestStartUsed;` and the `return result;` lines of `SplitLaneService`. Write down the line of the `rateStartDate` assignment: Step 9 inserts the estimate block just above it. If a class is missing, the task that creates it is not done: stop and report.

- [ ] **Step 2: Write the failing `SplitEstimatesTest`**

Create `force-app/main/default/classes/SplitEstimatesTest.cls`:

```apex
@IsTest
private class SplitEstimatesTest {
  private class Fx {
    PricingTestDataFactory.Graph g;
    Account escobedoDock;
    Account laredoYard;
    Pricing_Place__c escobedo;
    Pricing_Place__c laredo;
    Pricing_Place__c toronto;
  }

  /** An uninserted active place, keyed the way RfpTestDataFactory.createPlace keys it. */
  private static Pricing_Place__c place(
    String city,
    String prov,
    String country,
    Decimal lat,
    Decimal lng
  ) {
    return new Pricing_Place__c(
      Name = city + ', ' + prov,
      Key__c = PlaceNormalizer.key(city, prov, country),
      City__c = city,
      Province__c = prov,
      Country__c = country,
      Geolocation__Latitude__s = lat,
      Geolocation__Longitude__s = lng,
      Active__c = true,
      Source__c = 'Locations'
    );
  }

  private static LaneSearchRequest lane(
    Pricing_Place__c origin,
    Pricing_Place__c destination
  ) {
    LaneSearchRequest r = new LaneSearchRequest();
    r.originKey = origin.Key__c;
    r.destinationKey = destination.Key__c;
    return r;
  }

  /**
   * Leg lanes "General Escobedo, NL:Laredo, TX" and "Laredo, TX:Toronto, ON" (the graph's destination
   * location), with Laredo as the only handoff point. The tests add one load before Test.startTest()
   * and two inside it, the most PricingTestDataFactory's load automation allows (its class doc).
   */
  private static Fx legFixture() {
    Fx f = new Fx();
    f.g = PricingTestDataFactory.createGraph();
    f.escobedoDock = PricingTestDataFactory.createLocation(
      'Escobedo Dock',
      'General Escobedo',
      'Nuevo León',
      'Mexico',
      '66050',
      25.8000,
      -100.3167
    );
    f.laredoYard = PricingTestDataFactory.createLocation(
      'Laredo Yard',
      'Laredo',
      'Texas',
      'United States',
      '78045',
      27.5306,
      -99.4803
    );
    f.escobedo = place('General Escobedo', 'NL', 'MX', 25.8000, -100.3167);
    f.laredo = place('Laredo', 'TX', 'US', 27.5306, -99.4803);
    f.toronto = place('Toronto', 'ON', 'CA', 43.6532, -79.3832);
    insert new List<Pricing_Place__c>{ f.escobedo, f.laredo, f.toronto };
    HandoffPoints.keysOverride = new List<String>{ f.laredo.Key__c };
    IntercompanyCarriers.idsOverride = new Set<Id>();
    return f;
  }

  /** "<handoff label> +<extra distance> %" per option, in order. */
  private static List<String> labels(List<SplitLaneResult.Option> options) {
    List<String> out = new List<String>();
    for (SplitLaneResult.Option o : options) {
      out.add(o.handoffLabel + ' +' + o.extraDistancePct + ' %');
    }
    return out;
  }

  /** "<name> (<legs moved>)" per carrier, with ", blacklisted" when flagged. */
  private static List<String> names(SplitLaneResult.Leg oneLeg) {
    List<String> out = new List<String>();
    for (SplitLaneResult.LegCarrier c : oneLeg.carriers) {
      String flag = c.blacklisted ? ', blacklisted' : '';
      out.add(c.name + ' (' + c.legsMoved + flag + ')');
    }
    return out;
  }

  /**
   * Approx miles (great circle x 1.2, one decimal per distance) from General Escobedo, NL to Toronto,
   * ON: direct 2044.0; via Little Rock 937.6 + 1108.0 = 2045.6 (+0.08 %), Laredo 156.3 + 1893.6 =
   * 2049.9 (+0.29 %), St. Louis 1276.6 + 792.6 = 2069.2 (+1.23 %), Chicago 1589.9 + 522.8 = 2112.7
   * (+3.36 %) and San Diego 1344.4 + 2597.2 = 3941.6 (+92.8 %).
   */
  @IsTest
  static void pointsWithinTenPercentAreKeptLeastExtraFirstAtMostThree() {
    Pricing_Place__c escobedo = place(
      'General Escobedo',
      'NL',
      'MX',
      25.8000,
      -100.3167
    );
    Pricing_Place__c toronto = place('Toronto', 'ON', 'CA', 43.6532, -79.3832);
    Pricing_Place__c laredo = place('Laredo', 'TX', 'US', 27.5306, -99.4803);
    Pricing_Place__c littleRock = place(
      'Little Rock',
      'AR',
      'US',
      34.7465,
      -92.2896
    );
    Pricing_Place__c stLouis = place(
      'St. Louis',
      'MO',
      'US',
      38.6270,
      -90.1994
    );
    Pricing_Place__c chicago = place('Chicago', 'IL', 'US', 41.8781, -87.6298);
    Pricing_Place__c sanDiego = place(
      'San Diego',
      'CA',
      'US',
      32.7157,
      -117.1611
    );
    insert new List<Pricing_Place__c>{
      escobedo,
      toronto,
      laredo,
      littleRock,
      stLouis,
      chicago,
      sanDiego
    };
    // Both lane ends are in the list: kept, each would come first with +0.00 %.
    HandoffPoints.keysOverride = new List<String>{
      sanDiego.Key__c,
      chicago.Key__c,
      toronto.Key__c,
      laredo.Key__c,
      'nowhere|zz|zz',
      stLouis.Key__c,
      escobedo.Key__c,
      littleRock.Key__c
    };
    IntercompanyCarriers.idsOverride = new Set<Id>();
    Test.startTest();
    List<SplitLaneResult.Option> options = SplitEstimates.estimate(
      lane(escobedo, toronto),
      escobedo,
      toronto,
      'CAD',
      null
    );
    Integer callouts = Limits.getCallouts();
    Test.stopTest();
    System.assertEquals(
      new List<String>{
        'Little Rock, AR +0 %',
        'Laredo, TX +0 %',
        'St. Louis, MO +1 %'
      },
      labels(options),
      'least extra distance first, at most 3 (Chicago is the fourth); San Diego is over 10 %; both lane ends and a key without a place are left out'
    );
    SplitLaneResult.Option viaLittleRock = options[0];
    System.assertEquals(SplitLaneResult.ESTIMATE, viaLittleRock.kind);
    System.assertEquals(
      0,
      viaLittleRock.shipments,
      'an estimate has no shipment'
    );
    System.assertEquals(2, viaLittleRock.legs.size());
    System.assertEquals(1, viaLittleRock.legs[0].position);
    System.assertEquals(
      'General Escobedo, NL → Little Rock, AR',
      viaLittleRock.legs[0].laneLabel
    );
    System.assertEquals(2, viaLittleRock.legs[1].position);
    System.assertEquals(
      'Little Rock, AR → Toronto, ON',
      viaLittleRock.legs[1].laneLabel
    );
    System.assertEquals(
      0,
      viaLittleRock.legs[0].carriers.size(),
      'no load on the leg lane in this test'
    );
    System.assertEquals(null, viaLittleRock.legs[0].median);
    System.assertEquals(0, viaLittleRock.legs[0].pricedCount);
    System.assertEquals(
      null,
      viaLittleRock.medianTotal,
      'no priced leg, no total'
    );
    System.assertEquals(
      0,
      callouts,
      'distances come from the coordinates, never from Mapbox'
    );
  }

  /**
   * General Escobedo, NL to San Diego, CA: direct 1344.4; via Calexico 1235.8 + 116.0 = 1351.8, +0.55 %,
   * shown as +1 % (half up); via Laredo 156.3 + 1336.8 = 1493.1, +11.06 %, over 10 %. To Toronto via
   * Chicago: +3.36 %, shown as +3 %.
   */
  @IsTest
  static void extraDistanceIsRoundedHalfUpAndLaredoIsTooFarForSanDiego() {
    Pricing_Place__c escobedo = place(
      'General Escobedo',
      'NL',
      'MX',
      25.8000,
      -100.3167
    );
    Pricing_Place__c toronto = place('Toronto', 'ON', 'CA', 43.6532, -79.3832);
    Pricing_Place__c laredo = place('Laredo', 'TX', 'US', 27.5306, -99.4803);
    Pricing_Place__c calexico = place(
      'Calexico',
      'CA',
      'US',
      32.6789,
      -115.4989
    );
    Pricing_Place__c sanDiego = place(
      'San Diego',
      'CA',
      'US',
      32.7157,
      -117.1611
    );
    Pricing_Place__c chicago = place('Chicago', 'IL', 'US', 41.8781, -87.6298);
    insert new List<Pricing_Place__c>{
      escobedo,
      toronto,
      laredo,
      calexico,
      sanDiego,
      chicago
    };
    IntercompanyCarriers.idsOverride = new Set<Id>();
    Test.startTest();
    HandoffPoints.keysOverride = new List<String>{
      laredo.Key__c,
      calexico.Key__c,
      sanDiego.Key__c
    };
    List<SplitLaneResult.Option> toSanDiego = SplitEstimates.estimate(
      lane(escobedo, sanDiego),
      escobedo,
      sanDiego,
      'CAD',
      null
    );
    HandoffPoints.keysOverride = new List<String>{ chicago.Key__c };
    List<SplitLaneResult.Option> toToronto = SplitEstimates.estimate(
      lane(escobedo, toronto),
      escobedo,
      toronto,
      'CAD',
      null
    );
    Test.stopTest();
    System.assertEquals(
      new List<String>{ 'Calexico, CA +1 %' },
      labels(toSanDiego),
      'Laredo adds 11.06 % to this lane; San Diego is its destination'
    );
    System.assertEquals(
      new List<String>{ 'Chicago, IL +3 %' },
      labels(toToronto)
    );
  }

  @IsTest
  static void noActivePointNoCoordinatesOrNoPlaceMeansNoEstimate() {
    Pricing_Place__c escobedo = place(
      'General Escobedo',
      'NL',
      'MX',
      25.8000,
      -100.3167
    );
    Pricing_Place__c toronto = place('Toronto', 'ON', 'CA', 43.6532, -79.3832);
    Pricing_Place__c laredo = place('Laredo', 'TX', 'US', 27.5306, -99.4803);
    Pricing_Place__c unlocated = place(
      'Unlocated Yard',
      'TX',
      'US',
      null,
      null
    );
    insert new List<Pricing_Place__c>{ escobedo, toronto, laredo, unlocated };
    IntercompanyCarriers.idsOverride = new Set<Id>();
    Pricing_Place__c blindOrigin = escobedo.clone(false, true);
    blindOrigin.Geolocation__Latitude__s = null;
    Test.startTest();
    Integer queriesBefore = Limits.getQueries();
    HandoffPoints.keysOverride = new List<String>();
    List<SplitLaneResult.Option> noPoint = SplitEstimates.estimate(
      lane(escobedo, toronto),
      escobedo,
      toronto,
      'CAD',
      null
    );
    HandoffPoints.keysOverride = new List<String>{ laredo.Key__c };
    List<SplitLaneResult.Option> blind = SplitEstimates.estimate(
      lane(escobedo, toronto),
      blindOrigin,
      toronto,
      'CAD',
      null
    );
    Integer queriesAfterTwo = Limits.getQueries();
    HandoffPoints.keysOverride = new List<String>{
      unlocated.Key__c,
      'nowhere|zz|zz'
    };
    List<SplitLaneResult.Option> noUsablePlace = SplitEstimates.estimate(
      lane(escobedo, toronto),
      escobedo,
      toronto,
      'CAD',
      null
    );
    Integer queriesAfterThree = Limits.getQueries();
    Test.stopTest();
    System.assertEquals(0, noPoint.size(), 'no active handoff point');
    System.assertEquals(
      0,
      blind.size(),
      'an end without coordinates has no approximate distance'
    );
    System.assertEquals(
      queriesBefore,
      queriesAfterTwo,
      'neither case reads a place or a leg'
    );
    System.assertEquals(
      0,
      noUsablePlace.size(),
      'a point without coordinates, or a key without a place, is skipped'
    );
    System.assertEquals(
      queriesAfterTwo + 1,
      queriesAfterThree,
      'one place read and no leg read'
    );
  }

  @IsTest
  static void legReadsNameCarriersAndTakeMediansInTheCardCurrency() {
    Fx f = legFixture();
    Account crest = SplitTestData.carrier('Crest Freight', true);
    SplitTestData.legLoad(
      f.g,
      f.escobedoDock,
      f.laredoYard,
      f.g.vendor,
      1000,
      'Delivered'
    );
    Test.startTest();
    SplitTestData.legLoad(
      f.g,
      f.escobedoDock,
      f.laredoYard,
      f.g.vendor,
      1400,
      'Delivered'
    );
    SplitTestData.legLoad(
      f.g,
      f.laredoYard,
      f.g.destinationLocation,
      crest,
      3000,
      'Delivered'
    );
    List<SplitLaneResult.Option> cad = SplitEstimates.estimate(
      lane(f.escobedo, f.toronto),
      f.escobedo,
      f.toronto,
      'CAD',
      null
    );
    ExchangeRates.periodsOverride = new List<ExchangeRates.Period>{
      new ExchangeRates.Period(
        Date.today().addDays(-30),
        Date.newInstance(9999, 12, 31),
        0.72
      )
    };
    ExchangeRates rates = ExchangeRates.usd(Date.today().addDays(-400));
    List<SplitLaneResult.Option> usd = SplitEstimates.estimate(
      lane(f.escobedo, f.toronto),
      f.escobedo,
      f.toronto,
      'USD',
      rates
    );
    LaneSearchRequest intermodal = lane(f.escobedo, f.toronto);
    intermodal.modes = new List<String>{ 'Intermodal' };
    List<SplitLaneResult.Option> otherMode = SplitEstimates.estimate(
      intermodal,
      f.escobedo,
      f.toronto,
      'CAD',
      null
    );
    Integer callouts = Limits.getCallouts();
    Test.stopTest();
    System.assertEquals(1, cad.size());
    SplitLaneResult.Option viaLaredo = cad[0];
    System.assertEquals('Laredo, TX', viaLaredo.handoffLabel);
    System.assertEquals(
      'General Escobedo, NL → Laredo, TX',
      viaLaredo.legs[0].laneLabel
    );
    System.assertEquals(
      new List<String>{ 'Test Carrier (2)' },
      names(viaLaredo.legs[0]),
      'one carrier, two legs moved'
    );
    System.assertEquals(
      1200.00,
      viaLaredo.legs[0].median,
      'median of 1000 and 1400'
    );
    System.assertEquals(2, viaLaredo.legs[0].pricedCount);
    System.assertEquals(
      'Laredo, TX → Toronto, ON',
      viaLaredo.legs[1].laneLabel
    );
    System.assertEquals(
      new List<String>{ 'Crest Freight (1, blacklisted)' },
      names(viaLaredo.legs[1]),
      'a blacklisted carrier stays, flagged'
    );
    System.assertEquals(3000.00, viaLaredo.legs[1].median);
    System.assertEquals(1, viaLaredo.legs[1].pricedCount);
    System.assertEquals(
      4200.00,
      viaLaredo.medianTotal,
      'leg 1 median + leg 2 median'
    );
    System.assertEquals(
      864.00,
      usd[0].legs[0].median,
      'each CAD total x 0.72 before the median: 720 and 1008'
    );
    System.assertEquals(2160.00, usd[0].legs[1].median);
    System.assertEquals(3024.00, usd[0].medianTotal);
    System.assertEquals(Date.today().addDays(-30), rates.latestStartUsed);
    System.assertEquals(
      0,
      otherMode[0].legs[0].carriers.size(),
      'the mode filter applies to the leg loads'
    );
    System.assertEquals(0, otherMode[0].legs[1].carriers.size());
    System.assertEquals(null, otherMode[0].medianTotal);
    System.assertEquals(0, callouts, 'no Mapbox call');
  }

  @IsTest
  static void intercompanyAndCancelledLegLoadsAreLeftOutAndAnUnpricedLegGivesNoTotal() {
    Fx f = legFixture();
    SplitTestData.legLoad(
      f.g,
      f.escobedoDock,
      f.laredoYard,
      f.g.vendor,
      1000,
      'Delivered'
    );
    Test.startTest();
    Account sister = SplitTestData.carrier('Sister Org Carrier', false);
    IntercompanyCarriers.idsOverride = new Set<Id>{ sister.Id };
    SplitTestData.legLoad(
      f.g,
      f.escobedoDock,
      f.laredoYard,
      sister,
      800,
      'Delivered'
    );
    SplitTestData.legLoad(
      f.g,
      f.laredoYard,
      f.g.destinationLocation,
      f.g.vendor,
      3000,
      'Cancelled'
    );
    List<SplitLaneResult.Option> options = SplitEstimates.estimate(
      lane(f.escobedo, f.toronto),
      f.escobedo,
      f.toronto,
      'CAD',
      null
    );
    Test.stopTest();
    SplitLaneResult.Option viaLaredo = options[0];
    System.assertEquals(
      new List<String>{ 'Test Carrier (1)' },
      names(viaLaredo.legs[0]),
      'the intercompany carrier is left out'
    );
    System.assertEquals(
      1000.00,
      viaLaredo.legs[0].median,
      'with the intercompany load the median would be 900.00'
    );
    System.assertEquals(1, viaLaredo.legs[0].pricedCount);
    System.assertEquals(
      0,
      viaLaredo.legs[1].carriers.size(),
      'the only leg 2 load is cancelled'
    );
    System.assertEquals(null, viaLaredo.legs[1].median);
    System.assertEquals(0, viaLaredo.legs[1].pricedCount);
    System.assertEquals(
      null,
      viaLaredo.medianTotal,
      'a leg without a priced load leaves the estimate without a total'
    );
  }

  @IsTest
  static void legReadTakesTheMostRecent500MovedLoadsOfTheLastYear() {
    Pricing_Place__c escobedo = place(
      'General Escobedo',
      'NL',
      'MX',
      25.8000,
      -100.3167
    );
    Pricing_Place__c laredo = place('Laredo', 'TX', 'US', 27.5306, -99.4803);
    // Any Account Id will do: the SOQL is only built, never run.
    Id sisterOrg =
      Account.SObjectType.getDescribe().getKeyPrefix() +
      '00000000000' +
      '1';
    IntercompanyCarriers.idsOverride = new Set<Id>{ sisterOrg };
    Map<String, Object> binds = new Map<String, Object>();
    List<String> conditions = LaneQueries.legConditions(
      lane(escobedo, laredo),
      escobedo,
      LaneSearchRequest.Precision.CITY,
      null,
      laredo,
      LaneSearchRequest.Precision.CITY,
      null,
      binds
    );
    String soql = LaneQueries.legLoadSoql(
      conditions,
      SplitEstimates.LEG_DAYS,
      SplitEstimates.LEG_LIMIT,
      binds
    );
    System.assert(
      soql.endsWith(' ORDER BY CreatedDate DESC LIMIT 500'),
      'the most recent 500 per leg: ' + soql
    );
    System.assert(soql.contains('CreatedDate = LAST_N_DAYS:365'), soql);
    System.assert(
      soql.contains(
        'rtms__Carrier__c != null AND rtms__Carrier_Quote_Total__c > 0'
      ),
      'moved and priced only: ' + soql
    );
    System.assert(soql.contains('rtms__Load_Status__c != \'Cancelled\''), soql);
    System.assert(soql.contains('rtms__Carrier__c NOT IN :intercompany'), soql);
    System.assert(!soql.contains('rtms__Load__r.'), 'read on the load itself');
    System.assertEquals(new Set<Id>{ sisterOrg }, binds.get('intercompany'));
    System.assertEquals(0.10, SplitEstimates.MAX_EXTRA);
    System.assertEquals(3, SplitEstimates.MAX_POINTS);
  }
}
```

Create `force-app/main/default/classes/SplitEstimatesTest.cls-meta.xml`:

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<ApexClass xmlns="http://soap.sforce.com/2006/04/metadata">
    <apiVersion>64.0</apiVersion>
    <status>Active</status>
</ApexClass>
```

The distances behind the first three tests are in the table above. `legReadsNameCarriersAndTakeMediansInTheCardCurrency` expects leg 1 median (1000 + 1400) / 2 = 1200.00 with one carrier and two legs moved, leg 2 median 3000.00, total 4200.00; in USD at 0.72 every CAD total is converted before the median: (720 + 1008) / 2 = 864.00, 3000 × 0.72 = 2160.00, total 3024.00. The graph's mode is Truckload, so an Intermodal filter leaves both legs empty. `intercompanyAndCancelledLegLoadsAreLeftOutAndAnUnpricedLegGivesNoTotal` would give leg 1 a median of 900.00 if the intercompany load counted, and leg 2 a median of 3000.00 if the cancelled load counted.

- [ ] **Step 3: Write the failing `SplitLaneControllerTest`**

Create `force-app/main/default/classes/SplitLaneControllerTest.cls`:

```apex
@IsTest
private class SplitLaneControllerTest {
  /** The AuraHandledException message the call throws, or null when it returns. */
  private static String refusal(String requestJson, String currencyCode) {
    try {
      SplitLaneController.splitOptions(requestJson, currencyCode, 0);
      return null;
    } catch (AuraHandledException e) {
      return e.getMessage();
    }
  }

  @IsTest
  static void aCurrencyOtherThanCadOrUsdIsRefusedBeforeAnyQuery() {
    String lane = '{"originKey":"general escobedo|nl|mx","destinationKey":"toronto|on|ca"}';
    Test.startTest();
    String euro = refusal(lane, 'EUR');
    String none = refusal(lane, null);
    String blank = refusal(lane, '');
    String lower = refusal(lane, 'usd');
    Integer queries = Limits.getQueries();
    Test.stopTest();
    System.assertEquals('Choose CAD or USD.', euro);
    System.assertEquals('Choose CAD or USD.', none);
    System.assertEquals('Choose CAD or USD.', blank);
    System.assertEquals(
      'Choose CAD or USD.',
      lower,
      'the code is exact: the card sends CAD or USD'
    );
    System.assertEquals(0, queries, 'refused before any query');
  }

  @IsTest
  static void anUnreadableRequestIsAShortUserError() {
    String expected = 'The search request could not be read. Please reset the filters and try again.';
    System.assertEquals(expected, refusal('not json', 'CAD'));
    System.assertEquals(expected, refusal(null, 'USD'));
    System.assertEquals(expected, refusal('null', 'CAD'));
  }

  @IsTest
  static void theAttemptNumberIsIgnored() {
    String oneEnd = '{"originKey":"general escobedo|nl|mx","destinationKey":""}';
    Test.startTest();
    SplitLaneResult first = SplitLaneController.splitOptions(oneEnd, 'CAD', 0);
    SplitLaneResult retry = SplitLaneController.splitOptions(oneEnd, 'CAD', 3);
    Test.stopTest();
    System.assertEquals('Both ends of the lane need a place.', first.message);
    System.assertEquals(
      JSON.serialize(first),
      JSON.serialize(retry),
      'a Retry number changes only the cache key'
    );
  }

  @IsTest
  static void aLaneSearchErrorBecomesAUserError() {
    RfpTestDataFactory.createPlace(
      'General Escobedo',
      'NL',
      'MX',
      25.8000,
      -100.3167,
      null
    );
    RfpTestDataFactory.createPlace(
      'Toronto',
      'ON',
      'CA',
      43.6532,
      -79.3832,
      null
    );
    String zip3 = '{"originKey":"general escobedo|nl|mx","destinationKey":"toronto|on|ca","originPrecision":"ZIP3"}';
    Test.startTest();
    String message = refusal(zip3, 'CAD');
    Test.stopTest();
    System.assert(
      message != null && message.contains('has no postal prefix'),
      'the matcher\'s LaneSearchException reaches the card as its message: ' +
      message
    );
  }

  @IsTest
  static void usdReachesTheServiceAndComesBackOnTheResult() {
    RfpTestDataFactory.createPlace(
      'General Escobedo',
      'NL',
      'MX',
      25.8000,
      -100.3167,
      '660'
    );
    RfpTestDataFactory.createPlace(
      'Toronto',
      'ON',
      'CA',
      43.6532,
      -79.3832,
      'M5V'
    );
    HandoffPoints.keysOverride = new List<String>();
    IntercompanyCarriers.idsOverride = new Set<Id>();
    ExchangeRates.periodsOverride = new List<ExchangeRates.Period>{
      new ExchangeRates.Period(
        Date.today().addDays(-30),
        Date.newInstance(9999, 12, 31),
        0.72
      )
    };
    Test.startTest();
    SplitLaneResult result = SplitLaneController.splitOptions(
      '{"originKey":"general escobedo|nl|mx","destinationKey":"toronto|on|ca"}',
      'USD',
      0
    );
    Test.stopTest();
    System.assertEquals('USD', result.currencyCode);
    System.assertEquals(0, result.options.size());
    System.assertEquals(SplitLaneService.NO_OPTION_MESSAGE, result.message);
  }
}
```

Create `force-app/main/default/classes/SplitLaneControllerTest.cls-meta.xml`:

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<ApexClass xmlns="http://soap.sforce.com/2006/04/metadata">
    <apiVersion>64.0</apiVersion>
    <status>Active</status>
</ApexClass>
```

- [ ] **Step 4: Add the failing leg tests to `LaneQueriesTest`**

In `force-app/main/default/classes/LaneQueriesTest.cls`, insert these two methods directly before the class's final closing `}` (the last line of the file), after a blank line:

```apex
  @IsTest
  static void legConditionsMatchTheLoadItselfAtEachEndsPrecision() {
    Pricing_Place__c escobedo = new Pricing_Place__c(
      Key__c = 'general escobedo|nl|mx',
      City__c = 'General Escobedo',
      Province__c = 'NL',
      Country__c = 'MX',
      Postal_Prefix__c = '660'
    );
    Pricing_Place__c laredo = new Pricing_Place__c(
      Key__c = 'laredo|tx|us',
      City__c = 'Laredo',
      Province__c = 'TX',
      Country__c = 'US',
      Postal_Prefix__c = '780'
    );
    Map<String, Object> binds = new Map<String, Object>();
    List<String> provinceToCity = LaneQueries.legConditions(
      new LaneSearchRequest(),
      escobedo,
      LaneSearchRequest.Precision.PROVINCE,
      null,
      laredo,
      LaneSearchRequest.Precision.CITY,
      null,
      binds
    );
    System.assertEquals(
      new List<String>{
        'rtms__State_Lane__c LIKE :oProv',
        'rtms__City_Lane__c LIKE :dCity',
        'rtms__Load_Status__c != \'Cancelled\''
      },
      provinceToCity
    );
    System.assertEquals('NL:%', binds.get('oProv'));
    System.assertEquals(new List<String>{ '%:Laredo, TX' }, binds.get('dCity'));

    LaneSearchRequest filtered = new LaneSearchRequest();
    filtered.modes = new List<String>{ 'Truckload' };
    filtered.equipmentCategories = new List<String>{ 'Van' };
    filtered.hazmatOnly = true;
    Map<String, Object> zipBinds = new Map<String, Object>();
    List<String> zipToRadius = LaneQueries.legConditions(
      filtered,
      escobedo,
      LaneSearchRequest.Precision.ZIP3,
      '664',
      laredo,
      LaneSearchRequest.Precision.RADIUS,
      null,
      zipBinds
    );
    System.assertEquals(
      new List<String>{
        'rtms__Zip3_Lane__c LIKE :oZip3',
        'rtms__City_Lane__c LIKE :dCity',
        'rtms__Mode__r.Name IN :modes',
        'rtms__Equipment_Type__r.rtms__Category__c IN :cats',
        'rtms__Hazardous_Materials__c = true',
        'rtms__Load_Status__c != \'Cancelled\''
      },
      zipToRadius,
      'an explicit postal prefix wins; a radius end is matched by its city key; the filters sit on the load itself'
    );
    System.assertEquals('664:%', zipBinds.get('oZip3'));
    System.assertEquals(filtered.modes, zipBinds.get('modes'));
    System.assertEquals(filtered.equipmentCategories, zipBinds.get('cats'));

    System.assertEquals(
      null,
      LaneQueries.legConditions(
        new LaneSearchRequest(),
        null,
        LaneSearchRequest.Precision.CITY,
        null,
        laredo,
        LaneSearchRequest.Precision.CITY,
        null,
        new Map<String, Object>()
      ),
      'a leg is never read without both ends'
    );
  }

  @IsTest
  static void legLoadSoqlReadsTheMostRecentMovedLoadsWithoutIntercompanyCarriers() {
    // Any Account Id will do: the SOQL is only built, never run.
    Id sisterOrg =
      Account.SObjectType.getDescribe().getKeyPrefix() +
      '00000000000' +
      '1';
    IntercompanyCarriers.idsOverride = new Set<Id>{ sisterOrg };
    List<String> conditions = new List<String>{
      'rtms__City_Lane__c LIKE :oCity',
      'rtms__City_Lane__c LIKE :dCity'
    };
    Map<String, Object> binds = new Map<String, Object>();
    String soql = LaneQueries.legLoadSoql(conditions, 365, 500, binds);
    System.assertEquals(
      'SELECT Id, CreatedDate, rtms__Carrier__c, rtms__Carrier__r.Name, rtms__Carrier__r.Black_List__c, rtms__Carrier_Quote_Total__c ' +
        'FROM rtms__Load__c WHERE rtms__City_Lane__c LIKE :oCity AND rtms__City_Lane__c LIKE :dCity ' +
        'AND CreatedDate = LAST_N_DAYS:365 AND rtms__Carrier__c != null AND rtms__Carrier_Quote_Total__c > 0 ' +
        'AND rtms__Carrier__c NOT IN :intercompany ORDER BY CreatedDate DESC LIMIT 500',
      soql
    );
    System.assertEquals(
      2,
      conditions.size(),
      'the caller\'s list is not changed'
    );
    System.assertEquals(new Set<Id>{ sisterOrg }, binds.get('intercompany'));
  }
```

`LaneKeyMatcher` binds a city end as a `List<String>` of patterns (one pattern here, because "Laredo" has no accent) and a province or postal-prefix end as one `String`, as the search did before Task 2.

- [ ] **Step 5: Add the failing tests to `SplitLaneServiceTest` and `CarrierSplitSecurityTest`**

In `force-app/main/default/classes/SplitLaneServiceTest.cls`, insert these three methods directly before the class's final closing `}`, after a blank line:

```apex
  @IsTest
  static void aLaneWithoutSplitHistoryGetsEstimates() {
    Pricing_Place__c escobedo = RfpTestDataFactory.createPlace(
      'General Escobedo',
      'NL',
      'MX',
      25.8000,
      -100.3167,
      '660'
    );
    Pricing_Place__c laredo = RfpTestDataFactory.createPlace(
      'Laredo',
      'TX',
      'US',
      27.5306,
      -99.4803,
      '780'
    );
    Pricing_Place__c toronto = RfpTestDataFactory.createPlace(
      'Toronto',
      'ON',
      'CA',
      43.6532,
      -79.3832,
      'M5V'
    );
    HandoffPoints.keysOverride = new List<String>{ laredo.Key__c };
    IntercompanyCarriers.idsOverride = new Set<Id>();
    LaneSearchRequest req = new LaneSearchRequest();
    req.originKey = escobedo.Key__c;
    req.destinationKey = toronto.Key__c;
    Test.startTest();
    SplitLaneResult result = SplitLaneService.options(req, 'CAD');
    Test.stopTest();
    System.assertEquals(null, result.message);
    System.assertEquals(1, result.options.size(), 'one estimate, via Laredo');
    System.assertEquals(SplitLaneResult.ESTIMATE, result.options[0].kind);
    System.assertEquals('Laredo, TX', result.options[0].handoffLabel);
    System.assertEquals(0, result.options[0].shipments);
    System.assertEquals(
      'General Escobedo, NL → Laredo, TX',
      result.options[0].legs[0].laneLabel
    );
  }

  @IsTest
  static void aLaneWithSplitHistoryGetsNoEstimate() {
    PricingTestDataFactory.Graph g = PricingTestDataFactory.createGraph();
    Account escobedoDock = PricingTestDataFactory.createLocation(
      'Escobedo Dock',
      'General Escobedo',
      'Nuevo León',
      'Mexico',
      '66050',
      25.8000,
      -100.3167
    );
    Account laredoYard = PricingTestDataFactory.createLocation(
      'Laredo Yard',
      'Laredo',
      'Texas',
      'United States',
      '78045',
      27.5306,
      -99.4803
    );
    Pricing_Place__c escobedo = RfpTestDataFactory.createPlace(
      'General Escobedo',
      'NL',
      'MX',
      25.8000,
      -100.3167,
      '660'
    );
    Pricing_Place__c laredo = RfpTestDataFactory.createPlace(
      'Laredo',
      'TX',
      'US',
      27.5306,
      -99.4803,
      '780'
    );
    Pricing_Place__c toronto = RfpTestDataFactory.createPlace(
      'Toronto',
      'ON',
      'CA',
      43.6532,
      -79.3832,
      'M5V'
    );
    HandoffPoints.keysOverride = new List<String>{ laredo.Key__c };
    IntercompanyCarriers.idsOverride = new Set<Id>();
    rtms__Load__c customerLoad = PricingTestDataFactory.createLoad(
      g,
      escobedoDock,
      g.destinationLocation
    );
    Test.startTest();
    rtms__Load__c legOne = SplitTestData.legLoad(
      g,
      escobedoDock,
      laredoYard,
      g.vendor,
      1000,
      'Delivered'
    );
    rtms__Load__c legTwo = SplitTestData.legLoad(
      g,
      laredoYard,
      g.destinationLocation,
      g.vendor,
      3000,
      'Delivered'
    );
    SplitTestData.plan(customerLoad, new List<rtms__Load__c>{ legOne, legTwo });
    LaneSearchRequest req = new LaneSearchRequest();
    req.originKey = escobedo.Key__c;
    req.destinationKey = toronto.Key__c;
    SplitLaneResult result = SplitLaneService.options(req, 'CAD');
    Test.stopTest();
    System.assertEquals(1, result.options.size(), 'the history group only');
    System.assertEquals(
      SplitLaneResult.HISTORY,
      result.options[0].kind,
      'estimates run only when history finds no group'
    );
    System.assertEquals(1, result.options[0].shipments);
    System.assertEquals(null, result.message);
  }

  @IsTest
  static void noHistoryAndNoCloseHandoffPointGiveTheNoOptionMessage() {
    Pricing_Place__c escobedo = RfpTestDataFactory.createPlace(
      'General Escobedo',
      'NL',
      'MX',
      25.8000,
      -100.3167,
      '660'
    );
    Pricing_Place__c toronto = RfpTestDataFactory.createPlace(
      'Toronto',
      'ON',
      'CA',
      43.6532,
      -79.3832,
      'M5V'
    );
    Pricing_Place__c sanDiego = RfpTestDataFactory.createPlace(
      'San Diego',
      'CA',
      'US',
      32.7157,
      -117.1611,
      '921'
    );
    IntercompanyCarriers.idsOverride = new Set<Id>();
    LaneSearchRequest req = new LaneSearchRequest();
    req.originKey = escobedo.Key__c;
    req.destinationKey = toronto.Key__c;
    Test.startTest();
    HandoffPoints.keysOverride = new List<String>{ sanDiego.Key__c };
    SplitLaneResult tooFar = SplitLaneService.options(req, 'CAD');
    HandoffPoints.keysOverride = new List<String>();
    SplitLaneResult noPoint = SplitLaneService.options(req, 'CAD');
    Test.stopTest();
    String expected = 'No split shipment on this lane in the last 12 months, and no handoff point is close enough for an estimate.';
    System.assertEquals(expected, SplitLaneService.NO_OPTION_MESSAGE);
    System.assertEquals(0, tooFar.options.size(), 'San Diego adds 92.8 %');
    System.assertEquals(expected, tooFar.message);
    System.assertEquals(0, noPoint.options.size());
    System.assertEquals(expected, noPoint.message);
  }
```

In the same file, Task 8's `historyReadsTheLanePlanWithItsHandoffCarriersAndCosts` ends with a second `options` call on a lane whose only shipment has an intercompany leg. After Step 9 that call finds no history group and no handoff place (a test sees none), so it gets the no-option message. Replace:

```apex
    System.assertEquals(
      null,
      withIntercompanyLeg.message,
      'Task 9 adds the no-option message'
    );
```

with:

```apex
    System.assertEquals(
      SplitLaneService.NO_OPTION_MESSAGE,
      withIntercompanyLeg.message,
      'no history group and no handoff place in a test: the no-option message'
    );
```

In `force-app/main/default/classes/CarrierSplitSecurityTest.cls`, insert these two methods directly before the class's final closing `}`, after a blank line:

```apex
  @IsTest
  static void restrictedUsersGetSplitEstimatesFromLoadsTheyCannotOpen() {
    User viewer = RfpTestDataFactory.restrictedUser('Lane_Benchmark_User');
    User pricer = RfpTestDataFactory.restrictedUser('RFP_Tool_User');
    if (viewer == null || pricer == null) {
      System.assert(
        true,
        'no usable profile in this org; runAs coverage skipped (ledgered)'
      );
      return;
    }
    PricingTestDataFactory.Graph g = PricingTestDataFactory.createGraph();
    Account escobedoDock = PricingTestDataFactory.createLocation(
      'Escobedo Dock',
      'General Escobedo',
      'Nuevo León',
      'Mexico',
      '66050',
      25.8000,
      -100.3167
    );
    Account laredoYard = PricingTestDataFactory.createLocation(
      'Laredo Yard',
      'Laredo',
      'Texas',
      'United States',
      '78045',
      27.5306,
      -99.4803
    );
    Pricing_Place__c escobedo = RfpTestDataFactory.createPlace(
      'General Escobedo',
      'NL',
      'MX',
      25.8000,
      -100.3167,
      '660'
    );
    Pricing_Place__c laredo = RfpTestDataFactory.createPlace(
      'Laredo',
      'TX',
      'US',
      27.5306,
      -99.4803,
      '780'
    );
    Pricing_Place__c toronto = RfpTestDataFactory.createPlace(
      'Toronto',
      'ON',
      'CA',
      43.6532,
      -79.3832,
      'M5V'
    );
    HandoffPoints.keysOverride = new List<String>{ laredo.Key__c };
    IntercompanyCarriers.idsOverride = new Set<Id>();
    ExchangeRates.periodsOverride = new List<ExchangeRates.Period>{
      new ExchangeRates.Period(
        Date.today().addDays(-30),
        Date.newInstance(9999, 12, 31),
        0.72
      )
    };
    Test.startTest();
    SplitTestData.legLoad(
      g,
      escobedoDock,
      laredoYard,
      g.vendor,
      1000,
      'Delivered'
    );
    SplitTestData.legLoad(
      g,
      laredoYard,
      g.destinationLocation,
      g.vendor,
      3000,
      'Delivered'
    );
    String lane = JSON.serialize(
      new Map<String, Object>{
        'originKey' => escobedo.Key__c,
        'destinationKey' => toronto.Key__c
      }
    );
    SplitLaneResult seenByViewer;
    SplitLaneResult seenByPricer;
    System.runAs(viewer) {
      seenByViewer = SplitLaneController.splitOptions(lane, 'CAD', 0);
    }
    System.runAs(pricer) {
      seenByPricer = SplitLaneController.splitOptions(lane, 'USD', 0);
    }
    Test.stopTest();
    System.assertEquals(1, seenByViewer.options.size());
    SplitLaneResult.Option cad = seenByViewer.options[0];
    System.assertEquals('Laredo, TX', cad.handoffLabel);
    System.assertEquals('Test Carrier', cad.legs[0].carriers[0].name);
    System.assertEquals(
      4000.00,
      cad.medianTotal,
      'the admin\'s Private loads are read in system mode for a Lane Benchmark user'
    );
    System.assertEquals('USD', seenByPricer.currencyCode);
    System.assertEquals(
      2880.00,
      seenByPricer.options[0].medianTotal,
      'and for an RFP Tool user, in USD: 720 + 2160'
    );
    System.assertEquals(Date.today().addDays(-30), seenByPricer.rateStartDate);
  }

  @IsTest
  static void bothPermissionSetsOpenTheSplitController() {
    List<String> grantedTo = new List<String>();
    for (SetupEntityAccess access : [
      SELECT Parent.Name
      FROM SetupEntityAccess
      WHERE
        SetupEntityId IN (
          SELECT Id
          FROM ApexClass
          WHERE Name = 'SplitLaneController'
        )
        AND Parent.Name IN ('Lane_Benchmark_User', 'RFP_Tool_User')
      ORDER BY Parent.Name
    ]) {
      grantedTo.add(access.Parent.Name);
    }
    System.assertEquals(
      new List<String>{ 'Lane_Benchmark_User', 'RFP_Tool_User' },
      grantedTo
    );
  }
```

Run: `cd /Users/iulian/Documents/Personal/PricingDepartemnt-phase8 && grep -c "static void aLaneWithoutSplitHistoryGetsEstimates\|static void aLaneWithSplitHistoryGetsNoEstimate\|static void noHistoryAndNoCloseHandoffPointGiveTheNoOptionMessage\|static void restrictedUsersGetSplitEstimatesFromLoadsTheyCannotOpen\|static void bothPermissionSetsOpenTheSplitController\|static void legConditionsMatchTheLoadItselfAtEachEndsPrecision\|static void legLoadSoqlReadsTheMostRecentMovedLoadsWithoutIntercompanyCarriers" force-app/main/default/classes/SplitLaneServiceTest.cls force-app/main/default/classes/CarrierSplitSecurityTest.cls force-app/main/default/classes/LaneQueriesTest.cls`

Expected: `SplitLaneServiceTest.cls:3`, `CarrierSplitSecurityTest.cls:2`, `LaneQueriesTest.cls:2`. A higher count means a method name already existed: rename the method added here (append `Estimate` to its name) and run the grep again.

Run: `cd /Users/iulian/Documents/Personal/PricingDepartemnt-phase8 && grep -c "Task 9 adds the no-option message" force-app/main/default/classes/SplitLaneServiceTest.cls; grep -c "withIntercompanyLeg.message" force-app/main/default/classes/SplitLaneServiceTest.cls`

Expected: `0`, then `1` (Task 8's null-message assertion now expects `SplitLaneService.NO_OPTION_MESSAGE`).

- [ ] **Step 6: Deploy the tests alone and watch them fail to compile**

Run:

```bash
cd /Users/iulian/Documents/Personal/PricingDepartemnt-phase8 && sf project deploy start -o sandbox --source-dir force-app/main/default/classes/SplitEstimatesTest.cls --source-dir force-app/main/default/classes/SplitLaneControllerTest.cls --source-dir force-app/main/default/classes/LaneQueriesTest.cls --source-dir force-app/main/default/classes/SplitLaneServiceTest.cls --source-dir force-app/main/default/classes/CarrierSplitSecurityTest.cls -l NoTestRun --async --json | python3 -c "import json,sys; s=sys.stdin.read(); print(json.loads(s[s.index('{'):])['result']['id'])"
```

Expected: a deploy id (`0Af…`). Poll it, repeating while the first word is `Queued`, `Pending`, `InProgress` or a wait-timeout name:

```bash
sf project deploy report -o sandbox --job-id <id> -w 2 --json | python3 -c "import json,sys; s=sys.stdin.read(); j=json.loads(s[s.index('{'):]); r=j.get('result') or {}; d=r.get('details') or {}; t=d.get('runTestResult') or {}; L=lambda v: v if isinstance(v,list) else ([v] if v else []); print(r.get('status') or j.get('name'), 'tests', r.get('numberTestsCompleted'), '/', r.get('numberTestsTotal'), 'failures', r.get('numberTestErrors')); [print('COMPILE', x.get('fullName'), x.get('lineNumber'), '->', x.get('problem')) for x in L(d.get('componentFailures'))]; [print('FAIL', x.get('name'), x.get('methodName'), '->', (x.get('message') or '')[:200]) for x in L(t.get('failures'))]; [print('COVERAGE', x.get('name'), '->', x.get('message')) for x in L(t.get('codeCoverageWarnings'))]"
```

Expected: `Failed tests 0 / 0 failures 0` (the counts may print as `None`) and `COMPILE` lines such as `SplitEstimatesTest … Invalid type: SplitEstimates`, `SplitLaneControllerTest … Invalid type: SplitLaneController`, `LaneQueriesTest … Method does not exist or incorrect signature: void legConditions(…) from the type LaneQueries` and `SplitLaneServiceTest … Variable does not exist: NO_OPTION_MESSAGE`. A deploy fails as a whole, so nothing reaches the org. A `COMPILE` problem that names `SplitTestData`, `HandoffPoints`, `IntercompanyCarriers`, `ExchangeRates`, `SplitLaneResult` or `CarrierTally` means an earlier task is not deployed: stop and report.

- [ ] **Step 7: Add the leg methods to `LaneQueries`**

In `force-app/main/default/classes/LaneQueries.cls`, insert these two methods directly before the class's final closing `}`, after a blank line:

```apex
  /**
   * One leg lane on rtms__Load__c itself (no relationship path), for split estimates: the from end
   * at its precision (bind prefix 'o') and the to end at its precision ('d'), matched by
   * LaneKeyMatcher; the request's mode, equipment and hazmat filters; not cancelled. Null when an
   * end cannot be matched (no place and no explicit postal prefix), so a leg is never read without
   * both lane ends.
   */
  public static List<String> legConditions(
    LaneSearchRequest req,
    Pricing_Place__c fromPlace,
    LaneSearchRequest.Precision fromPrecision,
    String fromZip3,
    Pricing_Place__c toPlace,
    LaneSearchRequest.Precision toPrecision,
    String toZip3,
    Map<String, Object> binds
  ) {
    String fromEnd = LaneKeyMatcher.condition(
      '',
      true,
      'o',
      fromPrecision,
      fromPlace,
      fromZip3,
      binds
    );
    String toEnd = LaneKeyMatcher.condition(
      '',
      false,
      'd',
      toPrecision,
      toPlace,
      toZip3,
      binds
    );
    if (fromEnd == null || toEnd == null) {
      return null;
    }
    List<String> conditions = new List<String>{ fromEnd, toEnd };
    LaneLoadFilters.add(req, '', conditions, binds);
    conditions.add('rtms__Load_Status__c != \'Cancelled\'');
    return conditions;
  }

  /**
   * The leg load read: loads a carrier moved with a positive CAD carrier total (a split customer
   * load has none, so it never counts), created in the last days, without an intercompany carrier,
   * most recent first, at most rowLimit rows. Puts the 'intercompany' bind; the conditions list is
   * not changed.
   */
  public static String legLoadSoql(
    List<String> conditions,
    Integer days,
    Integer rowLimit,
    Map<String, Object> binds
  ) {
    List<String> clauses = new List<String>(conditions);
    clauses.add('CreatedDate = LAST_N_DAYS:' + String.valueOf(days));
    clauses.add('rtms__Carrier__c != null');
    clauses.add('rtms__Carrier_Quote_Total__c > 0');
    clauses.add('rtms__Carrier__c NOT IN :intercompany');
    binds.put('intercompany', IntercompanyCarriers.ids());
    return 'SELECT Id, CreatedDate, rtms__Carrier__c, rtms__Carrier__r.Name, rtms__Carrier__r.Black_List__c, rtms__Carrier_Quote_Total__c FROM rtms__Load__c WHERE ' +
      String.join(clauses, ' AND ') +
      ' ORDER BY CreatedDate DESC LIMIT ' +
      String.valueOf(rowLimit);
  }
```

The leg read is the shape verified read-only in PostProduc on 2026-09-15 with every filter this method can add (`rtms__Mode__r.Name IN (…)`, the equipment category-or-type pair, `rtms__Hazardous_Materials__c`, `rtms__Load_Status__c != 'Cancelled'`, `CreatedDate = LAST_N_DAYS:365`, `rtms__Carrier__c != null`, `rtms__Carrier_Quote_Total__c > 0`, `rtms__Carrier__c NOT IN (…)`, `ORDER BY CreatedDate DESC LIMIT 500`): 468 rows on "General Escobedo, NL:%" to "%:Laredo, TX", leg totals 1,138 to 1,248 CAD; the province and postal-prefix ends (`rtms__State_Lane__c LIKE 'NL:%'`, `rtms__Zip3_Lane__c LIKE '%:780'`) compile on `rtms__Load__c` as well.

- [ ] **Step 8: Create `SplitEstimates`**

Create `force-app/main/default/classes/SplitEstimates.cls`:

```apex
/**
 * Estimated split-lane options for a lane whose split history has no group (phase 8, spec §4
 * Estimates, D8, R86). The active handoff points (HandoffPoints), minus a point equal to either
 * end, are read by Key__c; a point is kept when origin -> point -> destination is at most 10 %
 * longer than origin -> destination in TripMilesService.approxMiles (the Approx factor cancels out
 * of the ratio), at most 3, least extra distance first. Each kept point reads its two leg lanes
 * from Revenova loads (LaneQueries.legConditions and legLoadSoql): moved loads with a positive CAD
 * carrier total, not cancelled, without an intercompany carrier, the most recent 500 per leg over
 * 365 days. Leg 1 keeps the origin end at the first search's precision (a radius end uses its
 * place's city key) and matches the point by city; leg 2 matches the point by city and keeps the
 * destination end's precision. Each leg shows its carriers and its median in the card's currency;
 * the estimate total is leg 1 median + leg 2 median, and the screen adds the typed handoff cost.
 * No callout: distances come from the places' coordinates, never from Mapbox.
 */
// Runs without sharing on purpose, like LaneSearchService: loads are Private and an estimate reads every team's moved loads on the leg lanes. Access is gated by the Lane Benchmark and RFP Tool permission sets.
public without sharing class SplitEstimates {
  @TestVisible
  private static final Decimal MAX_EXTRA = 0.10;
  @TestVisible
  private static final Integer MAX_POINTS = 3;
  @TestVisible
  private static final Integer LEG_DAYS = 365;
  @TestVisible
  private static final Integer LEG_LIMIT = 500;
  private static final String POINT_SOQL = 'SELECT Id, Key__c, City__c, Province__c, Country__c, Postal_Prefix__c, Spellings__c, Geolocation__Latitude__s, Geolocation__Longitude__s FROM Pricing_Place__c WHERE Key__c IN :pointKeys';

  /** One Estimate option per kept handoff point, least extra distance first; empty when none qualifies. */
  public static List<SplitLaneResult.Option> estimate(
    LaneSearchRequest req,
    Pricing_Place__c origin,
    Pricing_Place__c destination,
    String currencyCode,
    ExchangeRates rates
  ) {
    List<SplitLaneResult.Option> options = new List<SplitLaneResult.Option>();
    for (Candidate c : candidates(origin, destination)) {
      options.add(toOption(req, origin, destination, c, currencyCode, rates));
    }
    return options;
  }

  /** The qualifying points, sorted and cut to MAX_POINTS; no query when an end has no coordinates. */
  private static List<Candidate> candidates(
    Pricing_Place__c origin,
    Pricing_Place__c destination
  ) {
    List<Candidate> kept = new List<Candidate>();
    TruckRoute.Profile profile = TruckRoute.defaultProfile();
    Decimal direct = TripMilesService.approxMiles(origin, destination, profile);
    if (direct == null || direct == 0) {
      return kept;
    }
    for (Pricing_Place__c point : pointPlaces(origin, destination)) {
      Decimal extra = extraShare(origin, point, destination, direct, profile);
      if (extra != null && extra <= MAX_EXTRA) {
        kept.add(new Candidate(point, extra));
      }
    }
    kept.sort();
    while (kept.size() > MAX_POINTS) {
      kept.remove(kept.size() - 1);
    }
    return kept;
  }

  /** (origin -> point + point -> destination - direct) / direct; null when the point has no coordinates. */
  private static Decimal extraShare(
    Pricing_Place__c origin,
    Pricing_Place__c point,
    Pricing_Place__c destination,
    Decimal direct,
    TruckRoute.Profile profile
  ) {
    Decimal toPoint = TripMilesService.approxMiles(origin, point, profile);
    Decimal fromPoint = TripMilesService.approxMiles(
      point,
      destination,
      profile
    );
    if (toPoint == null || fromPoint == null) {
      return null;
    }
    return (toPoint + fromPoint - direct) / direct;
  }

  /** The places of the active handoff keys other than the two lane ends; no query when no key is left. */
  @SuppressWarnings(
    'PMD.ApexCRUDViolation'
  ) // system mode by design (see class comment); Database.queryWithBinds also counts as CRUD for PMD
  private static List<Pricing_Place__c> pointPlaces(
    Pricing_Place__c origin,
    Pricing_Place__c destination
  ) {
    Set<String> pointKeys = new Set<String>(HandoffPoints.activeKeys());
    pointKeys.remove(origin.Key__c?.toLowerCase());
    pointKeys.remove(destination.Key__c?.toLowerCase());
    if (pointKeys.isEmpty()) {
      return new List<Pricing_Place__c>();
    }
    return Database.queryWithBinds(
      POINT_SOQL,
      new Map<String, Object>{ 'pointKeys' => pointKeys },
      AccessLevel.SYSTEM_MODE
    );
  }

  private static SplitLaneResult.Option toOption(
    LaneSearchRequest req,
    Pricing_Place__c origin,
    Pricing_Place__c destination,
    Candidate c,
    String currencyCode,
    ExchangeRates rates
  ) {
    SplitLaneResult.Option estimated = new SplitLaneResult.Option();
    estimated.kind = SplitLaneResult.ESTIMATE;
    estimated.handoffLabel = placeLabel(c.point);
    estimated.extraDistancePct = (c.extra * 100)
      .setScale(0, RoundingMode.HALF_UP)
      .intValue();
    Map<String, Object> oneBinds = new Map<String, Object>();
    List<String> oneLane = LaneQueries.legConditions(
      req,
      origin,
      LaneQueries.deepPrecision(req.originPrecision),
      req.originZip3,
      c.point,
      LaneSearchRequest.Precision.CITY,
      null,
      oneBinds
    );
    Map<String, Object> twoBinds = new Map<String, Object>();
    List<String> twoLane = LaneQueries.legConditions(
      req,
      c.point,
      LaneSearchRequest.Precision.CITY,
      null,
      destination,
      LaneQueries.deepPrecision(req.destinationPrecision),
      req.destinationZip3,
      twoBinds
    );
    SplitLaneResult.Leg legOne = toLeg(
      1,
      origin,
      c.point,
      readLeg(oneLane, oneBinds),
      currencyCode,
      rates
    );
    SplitLaneResult.Leg legTwo = toLeg(
      2,
      c.point,
      destination,
      readLeg(twoLane, twoBinds),
      currencyCode,
      rates
    );
    estimated.legs = new List<SplitLaneResult.Leg>{ legOne, legTwo };
    if (legOne.median != null && legTwo.median != null) {
      estimated.medianTotal = (legOne.median + legTwo.median).setScale(2);
    }
    return estimated;
  }

  /** The leg's moved loads; none (and no query) when LaneQueries could not match both ends. */
  @SuppressWarnings(
    'PMD.ApexCRUDViolation'
  ) // system mode by design (see class comment); Database.queryWithBinds also counts as CRUD for PMD
  private static List<rtms__Load__c> readLeg(
    List<String> conditions,
    Map<String, Object> binds
  ) {
    if (conditions == null) {
      return new List<rtms__Load__c>();
    }
    String soql = LaneQueries.legLoadSoql(
      conditions,
      LEG_DAYS,
      LEG_LIMIT,
      binds
    );
    return Database.queryWithBinds(soql, binds, AccessLevel.SYSTEM_MODE);
  }

  /** Carriers with their legs moved, and the median of the loads' totals in the card's currency. */
  private static SplitLaneResult.Leg toLeg(
    Integer position,
    Pricing_Place__c fromPlace,
    Pricing_Place__c toPlace,
    List<rtms__Load__c> loads,
    String currencyCode,
    ExchangeRates rates
  ) {
    SplitLaneResult.Leg out = new SplitLaneResult.Leg();
    out.position = position;
    out.laneLabel = placeLabel(fromPlace) + ' → ' + placeLabel(toPlace);
    SplitLaneService.CarrierTally tally = new SplitLaneService.CarrierTally();
    List<Decimal> amounts = new List<Decimal>();
    for (rtms__Load__c load : loads) {
      tally.add(
        load.rtms__Carrier__c,
        load.rtms__Carrier__r?.Name,
        load.rtms__Carrier__r?.Black_List__c
      );
      Decimal amount = SplitLaneService.amountIn(
        currencyCode,
        rates,
        load.rtms__Carrier_Quote_Total__c,
        load.CreatedDate
      );
      if (amount != null) {
        amounts.add(amount);
      }
    }
    out.carriers = tally.sorted();
    out.median = SplitLaneService.median(amounts);
    out.pricedCount = amounts.size();
    return out;
  }

  private static String placeLabel(Pricing_Place__c place) {
    return place.City__c + ', ' + place.Province__c;
  }

  /** A handoff point that qualified, with its extra distance as a share of the direct distance. */
  private class Candidate implements Comparable {
    private final Pricing_Place__c point;
    private final Decimal extra;

    private Candidate(Pricing_Place__c point, Decimal extra) {
      this.point = point;
      this.extra = extra;
    }

    /** Least extra distance first; an equal share goes by place key, so the order never depends on the query. */
    public Integer compareTo(Object other) {
      Candidate that = (Candidate) other;
      if (extra != that.extra) {
        return extra < that.extra ? -1 : 1;
      }
      return point.Key__c.compareTo(that.point.Key__c);
    }
  }
}
```

Create `force-app/main/default/classes/SplitEstimates.cls-meta.xml`:

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<ApexClass xmlns="http://soap.sforce.com/2006/04/metadata">
    <apiVersion>64.0</apiVersion>
    <status>Active</status>
</ApexClass>
```

Every query sits in a helper outside a loop body (`pointPlaces`, `readLeg`), so PMD's `OperationWithLimitsInLoop` does not apply; `Candidate.compareTo` lives in an inner class, whose branches do not count toward the class total. The largest method, `candidates`, has a cyclomatic complexity of 7.

- [ ] **Step 9: Run the estimates in `SplitLaneService.options`**

In `force-app/main/default/classes/SplitLaneService.cls`, add the constant as the first member, directly below the line `public without sharing class SplitLaneService {`:

```apex
  public static final String NO_OPTION_MESSAGE = 'No split shipment on this lane in the last 12 months, and no handoff point is close enough for an estimate.';
```

Then, in `options`, replace (the `rateStartDate` line written down in Step 1 and the line above it):

```apex
    result.options = groupHistory(shipments, currencyCode, rates);
    result.rateStartDate = rates?.latestStartUsed;
```

with:

```apex
    result.options = groupHistory(shipments, currencyCode, rates);
    // Estimates only when history found no group (spec §4); they use the same places and rates.
    if (result.options.isEmpty()) {
      result.options = SplitEstimates.estimate(
        req,
        origin,
        destination,
        currencyCode,
        rates
      );
      if (result.options.isEmpty()) {
        result.message = NO_OPTION_MESSAGE;
      }
    }
    result.rateStartDate = rates?.latestStartUsed;
```

The block runs after `result.options` holds the history groups and before the rate date is read, because estimates convert amounts too.

The early returns Task 8 wrote stay as they are: a blank key or a missing place, and a USD card without a dated rate, return their own message before the plan read, so they never reach this block. `rates` is whatever Task 8 holds for a CAD card (`SplitLaneService.amountIn` never reads it in CAD).

Run: `cd /Users/iulian/Documents/Personal/PricingDepartemnt-phase8 && grep -n "NO_OPTION_MESSAGE\|SplitEstimates.estimate\|rateStartDate" force-app/main/default/classes/SplitLaneService.cls`

Expected: the constant line, the `SplitEstimates.estimate(` line, the `result.message = NO_OPTION_MESSAGE;` line, and after them the `rateStartDate` assignment, in that order of line numbers.

- [ ] **Step 10: Create `SplitLaneController`**

Create `force-app/main/default/classes/SplitLaneController.cls`:

```apex
/**
 * Aura/LWC entry point for the Split-lane options card (phase 8, spec §4 and §6). Thin: it refuses a
 * currency other than CAD or USD, reads the request JSON and turns search errors into short user
 * messages the way LaneBenchmarkController.search does; SplitLaneService does the work. attempt is
 * 0 on the first call and grows with each Retry, so a retry reaches the server past the cacheable
 * answer; the server ignores it. No readable-project check: no bid is read.
 */
public with sharing class SplitLaneController {
  @TestVisible
  private static final String CURRENCY_REFUSED = 'Choose CAD or USD.';
  @TestVisible
  private static final String UNREADABLE = 'The search request could not be read. Please reset the filters and try again.';

  @AuraEnabled(cacheable=true)
  public static SplitLaneResult splitOptions(
    String requestJson,
    String currencyCode,
    Integer attempt
  ) {
    requireCurrency(currencyCode);
    LaneSearchRequest req = readRequest(requestJson);
    try {
      return SplitLaneService.options(req, currencyCode);
    } catch (LaneSearchException e) {
      throw userError(e.getMessage());
    } catch (QueryException e) {
      throw userError(
        'The search took too long or returned too much data. Narrow the lookback or the radius and try again. (' +
          e.getMessage() +
          ')'
      );
    }
  }

  /** equals, not ==: Apex compares strings without case, and the card sends exactly CAD or USD. */
  private static void requireCurrency(String currencyCode) {
    if (!'CAD'.equals(currencyCode) && !'USD'.equals(currencyCode)) {
      throw userError(CURRENCY_REFUSED);
    }
  }

  private static LaneSearchRequest readRequest(String requestJson) {
    LaneSearchRequest req;
    try {
      req = (LaneSearchRequest) JSON.deserialize(
        requestJson,
        LaneSearchRequest.class
      );
    } catch (Exception e) {
      throw userError(UNREADABLE);
    }
    if (req == null) {
      throw userError(UNREADABLE);
    }
    return req;
  }

  private static AuraHandledException userError(String message) {
    AuraHandledException e = new AuraHandledException(message);
    e.setMessage(message);
    return e;
  }
}
```

Create `force-app/main/default/classes/SplitLaneController.cls-meta.xml`:

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<ApexClass xmlns="http://soap.sforce.com/2006/04/metadata">
    <apiVersion>64.0</apiVersion>
    <status>Active</status>
</ApexClass>
```

The currency check and the JSON read are helpers because PMD 7.15.0 measured a cyclomatic complexity of 10 (the method threshold) when both sat in `splitOptions`; split this way, the file has no violation.

- [ ] **Step 11: Give both permission sets access to the controller**

In `force-app/main/default/permissionsets/Lane_Benchmark_User.permissionset-meta.xml` and again in `force-app/main/default/permissionsets/RFP_Tool_User.permissionset-meta.xml`, replace

```xml
    <classAccesses>
        <apexClass>TripRouteView</apexClass>
```

with

```xml
    <classAccesses>
        <apexClass>SplitLaneController</apexClass>
        <enabled>true</enabled>
    </classAccesses>
    <classAccesses>
        <apexClass>TripRouteView</apexClass>
```

The block lands in alphabetical order: after `MapboxGeocoder` in `Lane_Benchmark_User`, after `RfpProjectController` in `RFP_Tool_User` (Task 6's `CarrierLeadController` sits higher up in both).

Run: `cd /Users/iulian/Documents/Personal/PricingDepartemnt-phase8 && for f in Lane_Benchmark_User RFP_Tool_User; do python3 -c "import xml.dom.minidom,sys; xml.dom.minidom.parse(sys.argv[1]); print('xml-ok')" force-app/main/default/permissionsets/$f.permissionset-meta.xml; grep -c "<apexClass>SplitLaneController</apexClass>" force-app/main/default/permissionsets/$f.permissionset-meta.xml; grep -o "<apexClass>[A-Za-z]*</apexClass>" force-app/main/default/permissionsets/$f.permissionset-meta.xml | sed 's/<[^>]*>//g' | tr '\n' ' '; echo; done`

Expected, for each file: `xml-ok`, `1`, and the class list in alphabetical order with `SplitLaneController` just before `TripRouteView`.

- [ ] **Step 12: Add the classes to the manifest**

In `manifest/package.xml`, replace

```xml
        <name>ApexClass</name>
```

with

```xml
        <members>SplitEstimates</members>
        <members>SplitEstimatesTest</members>
        <members>SplitLaneController</members>
        <members>SplitLaneControllerTest</members>
        <name>ApexClass</name>
```

Run: `cd /Users/iulian/Documents/Personal/PricingDepartemnt-phase8 && grep -c "<name>ApexClass</name>" manifest/package.xml && grep -B5 "<name>ApexClass</name>" manifest/package.xml && python3 -c "import xml.dom.minidom; xml.dom.minidom.parse('manifest/package.xml'); print('xml-ok')"`

Expected: `1`, then `<members>SplitLaneServiceTest</members>` (Task 8's last member) followed by the four new members and `<name>ApexClass</name>`, then `xml-ok`.

- [ ] **Step 13: PMD and Prettier**

Run: `cd /Users/iulian/Documents/Personal/PricingDepartemnt-phase8 && /private/tmp/pmd_install/pmd-bin-7.15.0/bin/pmd check --dir force-app --rulesets config/pmd-ruleset.xml --minimum-priority 3 --format text --fail-on-violation; echo "pmd exit $?"`

Expected: no violation lines, `pmd exit 0`. The four new or rewritten Apex bodies above were checked on scratch copies with PMD 7.15.0 and this ruleset (0 violations; the test fixtures build the fake intercompany Account Id from the key prefix because `AvoidHardcodingId` flags a 15-character literal). If PMD reports `CyclomaticComplexity` on `LaneQueries`, `SplitLaneService` or `CarrierSplitSecurityTest` (their totals come from Tasks 5, 6 and 8), move the reported method's branches into a private helper or, for `LaneQueries`, the null check of `legConditions` into a helper `bothEnds(String fromEnd, String toEnd)`; never raise the threshold or suppress.

Run: `cd /Users/iulian/Documents/Personal/PricingDepartemnt-phase8 && npx prettier --check force-app/main/default/classes/SplitEstimates.cls force-app/main/default/classes/SplitEstimatesTest.cls force-app/main/default/classes/SplitLaneController.cls force-app/main/default/classes/SplitLaneControllerTest.cls force-app/main/default/classes/LaneQueries.cls force-app/main/default/classes/LaneQueriesTest.cls force-app/main/default/classes/SplitLaneService.cls force-app/main/default/classes/SplitLaneServiceTest.cls force-app/main/default/classes/CarrierSplitSecurityTest.cls force-app/main/default/permissionsets/Lane_Benchmark_User.permissionset-meta.xml force-app/main/default/permissionsets/RFP_Tool_User.permissionset-meta.xml manifest/package.xml`

Expected: `All matched files use Prettier code style!`. If a file is listed, run the same command with `--write`, then `--check` again (Prettier only moves line breaks; lint-staged runs it again on commit).

- [ ] **Step 14: Count the tests, then deploy with them**

Run: `cd /Users/iulian/Documents/Personal/PricingDepartemnt-phase8 && for c in SplitEstimatesTest SplitLaneServiceTest SplitLaneControllerTest CarrierSplitSecurityTest LaneQueriesTest; do printf "%s " $c; grep -ci "^  @istest" force-app/main/default/classes/$c.cls; done`

Expected: `SplitEstimatesTest 6`, `SplitLaneControllerTest 5`, and for the other three their Task 8, Task 6 and Task 5 counts plus 3, 2 and 2. Add the five numbers: that sum is the expected test total below.

Run:

```bash
cd /Users/iulian/Documents/Personal/PricingDepartemnt-phase8 && sf project deploy start -o sandbox --source-dir force-app/main/default/classes/LaneQueries.cls --source-dir force-app/main/default/classes/LaneQueriesTest.cls --source-dir force-app/main/default/classes/SplitEstimates.cls --source-dir force-app/main/default/classes/SplitEstimatesTest.cls --source-dir force-app/main/default/classes/SplitLaneService.cls --source-dir force-app/main/default/classes/SplitLaneServiceTest.cls --source-dir force-app/main/default/classes/SplitLaneController.cls --source-dir force-app/main/default/classes/SplitLaneControllerTest.cls --source-dir force-app/main/default/classes/CarrierSplitSecurityTest.cls --source-dir force-app/main/default/permissionsets/Lane_Benchmark_User.permissionset-meta.xml --source-dir force-app/main/default/permissionsets/RFP_Tool_User.permissionset-meta.xml -l RunSpecifiedTests -t SplitEstimatesTest -t SplitLaneServiceTest -t SplitLaneControllerTest -t CarrierSplitSecurityTest -t LaneQueriesTest --async --json | python3 -c "import json,sys; s=sys.stdin.read(); print(json.loads(s[s.index('{'):])['result']['id'])"
```

Expected: a deploy id. Poll it, repeating while the first word is `Queued`, `Pending`, `InProgress` or a wait-timeout name (each call returns within about 2 minutes):

```bash
sf project deploy report -o sandbox --job-id <id> -w 2 --json | python3 -c "import json,sys; s=sys.stdin.read(); j=json.loads(s[s.index('{'):]); r=j.get('result') or {}; d=r.get('details') or {}; t=d.get('runTestResult') or {}; L=lambda v: v if isinstance(v,list) else ([v] if v else []); print(r.get('status') or j.get('name'), 'tests', r.get('numberTestsCompleted'), '/', r.get('numberTestsTotal'), 'failures', r.get('numberTestErrors')); [print('COMPILE', x.get('fullName'), x.get('lineNumber'), '->', x.get('problem')) for x in L(d.get('componentFailures'))]; [print('FAIL', x.get('name'), x.get('methodName'), '->', (x.get('message') or '')[:200]) for x in L(t.get('failures'))]; [print('COVERAGE', x.get('name'), '->', x.get('message')) for x in L(t.get('codeCoverageWarnings'))]"
```

Expected when done: `Succeeded tests <sum> / <sum> failures 0`, no `COMPILE`, `FAIL` or `COVERAGE` line (the org refuses a class under 75 %: `SplitEstimates` and `SplitLaneController` are covered by their own tests and the security test, `LaneQueries` by `LaneQueriesTest`, `SplitLaneService` by `SplitLaneServiceTest`). Record the job id. If a test fails, fix the class, not the assertion, unless the assertion contradicts the spec. Known failure shapes:

- `System.LimitException: Too many SOQL queries: 101` in a test that builds loads: that test's second context is over the load automation's budget. Move its `SplitTestData.carrier` call to the other side of `Test.startTest()` and deploy again; never add a load. If the limit still trips, compare with the measured budget in `SplitTestData`'s class comment (Task 1) and report.
- A `SplitLaneServiceTest.historyReadsTheLanePlanWithItsHandoffCarriersAndCosts` failure on `withIntercompanyLeg.message`: Step 5's replacement of Task 8's null-message assertion was skipped. Apply it; change nothing else in the test.
- `aLaneWithSplitHistoryGetsNoEstimate` returning an `Estimate` option: the Step 9 block runs before the history groups are in `result.options`; move it below them.
- `usdReachesTheServiceAndComesBackOnTheResult` or `restrictedUsersGetSplitEstimatesFromLoadsTheyCannotOpen` without a USD rate date: the Step 9 block sits below the `rateStartDate` assignment; move it above.
- `extraDistanceIsRoundedHalfUpAndLaredoIsTooFarForSanDiego` showing `Calexico, CA +0 %`: the percentage is truncated instead of rounded half up.

- [ ] **Step 15: Commit**

Run:

```bash
cd /Users/iulian/Documents/Personal/PricingDepartemnt-phase8 && git add force-app/main/default/classes/SplitEstimates.cls force-app/main/default/classes/SplitEstimates.cls-meta.xml force-app/main/default/classes/SplitEstimatesTest.cls force-app/main/default/classes/SplitEstimatesTest.cls-meta.xml force-app/main/default/classes/SplitLaneController.cls force-app/main/default/classes/SplitLaneController.cls-meta.xml force-app/main/default/classes/SplitLaneControllerTest.cls force-app/main/default/classes/SplitLaneControllerTest.cls-meta.xml force-app/main/default/classes/LaneQueries.cls force-app/main/default/classes/LaneQueriesTest.cls force-app/main/default/classes/SplitLaneService.cls force-app/main/default/classes/SplitLaneServiceTest.cls force-app/main/default/classes/CarrierSplitSecurityTest.cls force-app/main/default/permissionsets/Lane_Benchmark_User.permissionset-meta.xml force-app/main/default/permissionsets/RFP_Tool_User.permissionset-meta.xml manifest/package.xml && git commit -m "Add split-lane estimates through handoff points and the split-lane controller" && git status --short
```

Expected: one commit with 16 files on `phase-8/carriers-and-split-lanes`; lint-staged runs Prettier on the staged files (no change expected); `git status --short` still lists only ` M .vscode/settings.json` and the untracked `* 2.*` duplicates, never staged. No attribution trailer in the message.


#### Contract notes (Task 9)

1. **`SplitLaneController` is `public with sharing`.** A15 says "otherwise as A11" and names no sharing mode, so the contract's default applies. The work runs in `SplitLaneService` and `SplitEstimates`, which are `without sharing`, so the controller's mode changes nothing about what is read.
2. **The currency check uses `'CAD'.equals(currencyCode)`, not `==`.** Apex compares strings without case, so `==` would let `usd` through. `SplitLaneControllerTest` asserts that `usd`, `EUR`, blank and null are refused before any query. The card only ever sends `CAD` or `USD`.
3. **`splitOptions` delegates to two private helpers, `requireCurrency` and `readRequest`.** With both checks inline, PMD 7.15.0 measured the method's cyclomatic complexity at 10, which is the method threshold. The messages and exception mapping are exactly those of `LaneBenchmarkController.search`, including its QueryException text about "the lookback or the radius", even though the split card has fixed windows. The contract says "exactly as".
4. **`SplitEstimates` has four `@TestVisible private static final` constants beyond the contract:** `MAX_EXTRA` 0.10, `MAX_POINTS` 3, `LEG_DAYS` 365 and `LEG_LIMIT` 500. The "most recent 500" test builds the leg SOQL from the class's own values and asserts on its text, as the contract asks. The query itself runs in the tests that have loads.
5. **`LaneQueries.legConditions` returns `null` when either end cannot be matched** (`LaneKeyMatcher.condition` returns null for a null place with no explicit postal prefix). The contract is silent on this case. `SplitEstimates.readLeg` then reads nothing, so a leg is never read with only one lane end. In `estimate`, every end is a place that was read, so this is a guard only.
6. **Fixture DML is not all before `Test.startTest()`.** The contract rule cannot hold for three loads: `PricingTestDataFactory`'s load automation reaches 101 SOQL with three loads in one governor window. Tasks 1 and 8 found the same. So each test builds at most one load before `Test.startTest()` and at most two inside it, and uses the graph's vendor as a carrier where it can. `intercompanyAndCancelledLegLoadsAreLeftOutAndAnUnpricedLegGivesNoTotal` creates its intercompany carrier inside `Test.startTest()`.
7. **The 365-day window and the positive-total rule are proven on the SOQL text, not with extra loads.** An old load (`Test.setCreatedDate`) or a zero-total load would be a fourth load. The intercompany exclusion, the cancelled exclusion, the mode filter, blacklisted flags, medians, USD conversion and the unpriced leg are all proven on real loads.
8. **The point-selection tests add Little Rock AR, St. Louis MO and Chicago IL** through `HandoffPoints.keysOverride`. With only the three seeded points, no lane has four qualifying points, so "at most 3" and the ordering could not be tested. Every ratio is in the distance table, computed with the org's formula (great circle × 1.2, `setScale(1)` per distance). As the task brief asked, Laredo qualifies for General Escobedo → Toronto (+0.29 %) and San Diego does not (+92.8 %). Laredo also misses General Escobedo → San Diego (+11.06 %), and Calexico's +0.55 % shows the half-up rounding (+1 %).
9. **`SplitEstimates` reads handoff places with `Database.queryWithBinds(…, AccessLevel.SYSTEM_MODE)`.** This follows A10's query rule. A place equal to an end is dropped by comparing keys (`Key__c`, lowercased), before the query.
10. **`SplitEstimates.toOption` assigns `legs` as a new two-item list** instead of adding to the field. Task 8's summary lists `Option.legs` without an initializer, and a new list works either way.
11. **The Step 9 call site is an exact replacement of Task 8's two lines** `result.options = groupHistory(shipments, currencyCode, rates);` and `result.rateStartDate = rates?.latestStartUsed;` in `options`, whose locals `origin`, `destination`, `rates` and `result` the block uses. Step 1 prints the anchor, and Step 14 lists the failure shape when the block is misplaced.
12. **The two security tests go beyond the contract in their assertions.** `restrictedUsersGetSplitEstimatesFromLoadsTheyCannotOpen` asserts what the restricted users get (options, carriers and totals in CAD and USD). It does not assert that the loads are hidden from them. `rtms__Load__c` is Private (checked 2026-09-15), but a sharing rule could still share the admin's loads, and a hard visibility assertion would fail a deploy on org configuration (R68). `bothPermissionSetsOpenTheSplitController` reads `SetupEntityAccess`; that query shape was checked read-only in PostProduc.
13. **The `SplitLaneServiceTest` history test builds its customer load with `PricingTestDataFactory.createLoad`,** not `SplitTestData.legLoad`, because a customer load has no carrier and no total. Its two legs and the plan go through `SplitTestData`, as the contract requires.
14. **Fixture accounts use the state and country labels the org's picklists hold.** Account state and country picklists are on in PostProduc (`ShippingStateCode` exists). Mexican accounts store `Nuevo León` / `Mexico`, and US accounts `Texas` / `United States`. `PlaceNormalizer.provinceCode` turns them into `NL` and `TX` for the lane keys.

#### Open issues (Task 9)

- **Unmeasured SOQL for the first governor window.** The tests put two `createLocation` calls and one `SplitTestData.carrier` call before `Test.startTest()`, on top of `createGraph` and one load. `LaneSearchServiceTest` proves only one location plus one load. Step 14 gives the fallback if a test hits 101.
- **Tasks 5, 6 and 8 test-class shape.** If `CarrierSplitSecurityTest` (Task 6) or `SplitLaneServiceTest` (Task 8) uses `@TestSetup` data, it has not been checked against these methods. The added methods insert their own graph, places and loads. Their PMD class totals are also unknown here; Step 13 gives the split rule.
- **Null precision (resolved when the plan was assembled).** `SplitLaneService.options` runs `req.applyDefaults()` (Task 8), so `LaneQueries.deepPrecision` never receives a null precision from a request JSON without one.


---

### Task 10: Split-lane UI and Split cost — `c-split-lane-options`, the `Split` cost source, Lane Benchmark, the RFP lane panel and the Excel Cost source column

**Files:**

- Create: `force-app/main/default/lwc/splitLaneOptions/splitLaneOptions.js`
- Create: `force-app/main/default/lwc/splitLaneOptions/splitLaneOptions.html`
- Create: `force-app/main/default/lwc/splitLaneOptions/splitLaneOptions.css`
- Create: `force-app/main/default/lwc/splitLaneOptions/splitLaneOptions.js-meta.xml`
- Create: `force-app/main/default/lwc/splitLaneOptions/__tests__/splitLaneOptions.test.js`
- Modify: `force-app/main/default/lwc/rfpPricing/rfpPricing.js` (`SPLIT_SOURCE` after `SOURCES`; `costFor`)
- Modify: `force-app/main/default/lwc/rfpPricing/__tests__/rfpPricing.test.js` (import list; two tests after "reads the cost from the chosen source")
- Modify: `force-app/main/default/lwc/rfpLanePanel/rfpLanePanel.js` (the `c/rfpPricing` import; the `sourceOptions` field becomes a getter; `splitCost` field; `syncPricing`; `costNumber`; `handleUseAsCost` after `handleUseBest`)
- Modify: `force-app/main/default/lwc/rfpLanePanel/rfpLanePanel.html` (`c-split-lane-options` right after the `c-carrier-leads` block Task 7 added)
- Modify: `force-app/main/default/lwc/rfpLanePanel/__tests__/rfpLanePanel.test.js` (one import and one `jest.mock`; a `describe("split-lane options and the Split cost")` block before the file's last line)
- Modify: `force-app/main/default/lwc/laneBenchmark/laneBenchmark.js` (two getters right before `async connectedCallback()`; the `hasBothKeys` import Task 7 added is reused)
- Modify: `force-app/main/default/lwc/laneBenchmark/laneBenchmark.html` (`c-split-lane-options` right after `c-lane-benchmark-results`)
- Modify: `force-app/main/default/lwc/laneBenchmark/__tests__/laneBenchmark.test.js` (one import and one `jest.mock`; two tests before the file's last line)
- Modify: `force-app/main/default/lwc/rfpWorkbook/rfpWorkbook.js` (`OUR_COLUMNS`; the lane row)
- Modify: `force-app/main/default/lwc/rfpWorkbook/__tests__/rfpWorkbook.test.js` (two positional assertions; one test)
- Modify: `force-app/main/default/lwc/rfpTool/__tests__/rfpTool.test.js` (one `jest.mock` for `SplitLaneController.splitOptions`, keeping that file's "every Apex module the workbench tree imports is listed" convention)
- Modify: `manifest/package.xml` (`splitLaneOptions` in `LightningComponentBundle`)
- Unchanged, verified in Step 22: `force-app/main/default/lwc/rfpTool/rfpTool.js` (554 lines) and `force-app/main/default/lwc/rfpTool/rfpTool.html`

**Interfaces:**

- Consumes:
  - Task 1: `RFP_Lane__c.Cost_Source__c` accepts `Split` (restricted picklist, after `Manual`).
  - Task 7: `c/carrierLeadRules` — `hasBothKeys(requestJson)` and `directMedian(statsByCurrency, currencyCode)` (`stats[code].median` when `countNonZero > 0`, else `null`); `c-lane-benchmark` fields `lastRequestJson` (the exact string sent to `search`) and `lastCurrency` (the request currency at search time), its `showCarrierLeads` getter and its `import { hasBothKeys, noRate } from "c/carrierLeadRules"`; `c-rfp-lane-panel` field `historyStats` (the history search's `statsByCurrency`), getter `historyRequestJson` (`historyRequest(this._lane)` when `historyKey(this._lane)`, else `null`) and the `c-carrier-leads data-id="carrier-leads"` block after the `history-scroll` div; the `jest.mock` for `@salesforce/apex/CarrierLeadController.findCarrierLeads` in the `rfpTool`, `laneBenchmark` and `rfpLanePanel` suites; `carrierLeadRules` and `carrierLeads` in `manifest/package.xml`.
  - Task 8: `SplitLaneResult` as the page receives it — `{ currencyCode, rateStartDate ("YYYY-MM-DD" or null), options: [{ kind ("History" | "Estimate"), handoffLabel, shipments, legs: [{ position, laneLabel, carriers: [{ carrierId, name, legsMoved, blacklisted }], median, pricedCount }], medianTotal, pricedShipments, extraDistancePct }], truncated, message }`; every amount has two decimals and is `null` when there is none.
  - Task 9: `@salesforce/apex/SplitLaneController.splitOptions` — `splitOptions({ requestJson, currencyCode, attempt })` → `SplitLaneResult` (cacheable; `currencyCode` other than `CAD`/`USD` is refused with `Choose CAD or USD.`), deployed to `sandbox`.
  - Existing: `c/rfpPricing` `SOURCES`, `costFor`, `pricingDetail` (passes `Cost_Source__c` through and keeps `Selected_Bid__c` only for `Bid`); `c-rfp-lane-panel` `pricingchange` → `c-rfp-tool` → `RfpLaneController.saveLanePricing` (copies `posted.Cost_Source__c`, unchanged).
- Produces:
  - `c-split-lane-options` (new, not exposed): `@api requestJson` (getter/setter: a changed value closes the card and forgets its answers), `@api startCurrency`, `@api laneCurrency`, `@api statsByCurrency`, `@api allowUseAsCost` (default `false`); calls `splitOptions({ requestJson, currencyCode, attempt })` only after the `split-open` click; fires `useascost` with `detail: { cost: <Number, 2 decimals>, currencyCode }`; data-ids `split-open`, `split-card`, `split-loading`, `split-error`, `split-retry`, `split-currency-cad`, `split-currency-usd`, `split-rate-note`, `split-message`, `split-truncated`, `use-as-cost-off`, `option`, `option-title`, `leg-line`, `leg-blacklisted`, `handoff-cost`, `option-total`, `direct-median`, `use-as-cost`.
  - `c/rfpPricing`: `export const SPLIT_SOURCE = { label: "Split", value: "Split" }`; `costFor(source, { lane, bids, selectedBidId, manualCost, splitCost })`.
  - `c-rfp-lane-panel`: field `splitCost`, getter `sourceOptions`, handler `handleUseAsCost(event)`, `<c-split-lane-options data-id="split-options">` shown while `historyRequestJson` is set.
  - `c-lane-benchmark`: getters `showSplitOptions` and `splitStartCurrency`, `<c-split-lane-options data-id="split-options">` at the bottom of the results column.
  - `c/rfpWorkbook`: `OUR_COLUMNS` gains `Cost source` right after `Currency` (19 columns).
  - No new event reaches `c-rfp-tool`: Use as cost only fills the panel's editor, and Save price stays the one save.

**Before you start:** Tasks 7, 8 and 9 are committed and deployed to `sandbox`, and Task 1's `Split` value is in the org. Check:

Run: `grep -nE "export function (hasBothKeys|directMedian)" force-app/main/default/lwc/carrierLeadRules/carrierLeadRules.js; grep -cE "lastRequestJson|lastCurrency" force-app/main/default/lwc/laneBenchmark/laneBenchmark.js; grep -nE "historyStats =|get historyRequestJson" force-app/main/default/lwc/rfpLanePanel/rfpLanePanel.js; grep -n 'data-id="carrier-leads"' force-app/main/default/lwc/rfpLanePanel/rfpLanePanel.html; grep -l "CarrierLeadController.findCarrierLeads" force-app/main/default/lwc/rfpTool/__tests__/rfpTool.test.js force-app/main/default/lwc/laneBenchmark/__tests__/laneBenchmark.test.js force-app/main/default/lwc/rfpLanePanel/__tests__/rfpLanePanel.test.js; grep -c "<fullName>Split</fullName>" force-app/main/default/objects/RFP_Lane__c/fields/Cost_Source__c.field-meta.xml`

Expected: the two `export function` lines; a count of at least 4; the `historyStats` field and the `get historyRequestJson()` line; one `carrier-leads` line; the three test files; `1`.

Run: `sf data query -o sandbox --json -q "SELECT Name FROM ApexClass WHERE Name IN ('SplitLaneController','SplitLaneService','SplitEstimates')" | python3 -c "import json,sys; s=sys.stdin.read(); print(sorted(r['Name'] for r in json.loads(s[s.index('{'):])['result']['records']))"`

Expected: `['SplitEstimates', 'SplitLaneController', 'SplitLaneService']`. A missing class means Task 8 or 9 is not deployed: the new bundle imports `SplitLaneController.splitOptions` and will not deploy without it.

Run each Jest command on its own; `2>&1 | grep -E "✕|^(Tests|Test Suites):"` keeps the output short. After Task 7 the suites hold: `rfpLanePanel` 38, `laneBenchmark` 19, `rfpTool` 34, and the full run 41 suites / 385 tests (Tasks 8 and 9 add no Jest test). When your printed counts differ, carry your own numbers: this task adds 1 suite and 23 tests.

- [ ] **Step 1: Split-lane card — write the failing suite**

Create `force-app/main/default/lwc/splitLaneOptions/__tests__/splitLaneOptions.test.js`:

```js
import { createElement } from "lwc";
import SplitLaneOptions from "c/splitLaneOptions";
import splitOptions from "@salesforce/apex/SplitLaneController.splitOptions";

jest.mock(
  "@salesforce/apex/SplitLaneController.splitOptions",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const flush = () => Promise.resolve().then(() => Promise.resolve());
const settle = () => flush().then(flush);

const REQUEST = JSON.stringify({
  originKey: "general escobedo|nl|mx",
  destinationKey: "saint-augustin-de-desmaures|qc|ca",
  originPrecision: "CITY",
  destinationPrecision: "CITY"
});
const OTHER_REQUEST = JSON.stringify({
  originKey: "monterrey|nl|mx",
  destinationKey: "toronto|on|ca",
  originPrecision: "CITY",
  destinationPrecision: "CITY"
});

/** The first search's statistics: a priced CAD median, no priced USD row. */
const STATS = {
  CAD: { count: 5, countNonZero: 3, median: 5980 },
  USD: { count: 2, countNonZero: 0, median: null }
};

const carrier = (carrierId, name, legsMoved, blacklisted = false) => ({
  carrierId,
  name,
  legsMoved,
  blacklisted
});
const leg = (position, laneLabel, carriers, median, pricedCount) => ({
  position,
  laneLabel,
  carriers,
  median,
  pricedCount
});

/** SplitLaneResult with one history group, as SplitLaneController.splitOptions returns it. */
const historyResult = (currencyCode, [leg1Median, leg2Median, total]) => ({
  currencyCode,
  rateStartDate: currencyCode === "USD" ? "2026-08-11" : null,
  truncated: false,
  message: null,
  options: [
    {
      kind: "History",
      handoffLabel: "Laredo, TX · SFMN Park ITC Laredo yard",
      shipments: 34,
      legs: [
        leg(
          1,
          "General Escobedo, NL → Laredo, TX",
          [
            carrier("001000000000001AAA", "Q Transportes", 18),
            carrier("001000000000002AAA", "Fletes Mex", 9, true)
          ],
          leg1Median,
          27
        ),
        leg(
          2,
          "Laredo, TX → Saint-Augustin-de-Desmaures, QC",
          [carrier("001000000000003AAA", "Nordic Lines", 34)],
          leg2Median,
          31
        )
      ],
      medianTotal: total,
      pricedShipments: 31,
      extraDistancePct: null
    }
  ]
});
const HISTORY_CAD = historyResult("CAD", [1248.4, 5190, 6453.25]);
const HISTORY_USD = historyResult("USD", [903.72, 3757.04, 4671.51]);

/** Two estimates: Laredo with both legs priced, San Diego with an empty first leg. */
const estimateResult = (currencyCode, [leg1Median, leg2Median, total]) => ({
  currencyCode,
  rateStartDate: currencyCode === "USD" ? "2026-08-11" : null,
  truncated: false,
  message: null,
  options: [
    {
      kind: "Estimate",
      handoffLabel: "Laredo, TX",
      shipments: 0,
      legs: [
        leg(
          1,
          "Monterrey, NL → Laredo, TX",
          [carrier("001000000000001AAA", "Q Transportes", 12)],
          leg1Median,
          12
        ),
        leg(
          2,
          "Laredo, TX → Toronto, ON",
          [carrier("001000000000004AAA", "Maple Freight", 40)],
          leg2Median,
          40
        )
      ],
      medianTotal: total,
      pricedShipments: 0,
      extraDistancePct: 6
    },
    {
      kind: "Estimate",
      handoffLabel: "San Diego, CA",
      shipments: 0,
      legs: [
        leg(1, "Monterrey, NL → San Diego, CA", [], null, 0),
        leg(
          2,
          "San Diego, CA → Toronto, ON",
          [carrier("001000000000005AAA", "Pacific Haul", 3, true)],
          2100,
          3
        )
      ],
      medianTotal: null,
      pricedShipments: 0,
      extraDistancePct: 9
    }
  ]
});
const ESTIMATE_CAD = estimateResult("CAD", [900.1, 1500, 2400.1]);
const ESTIMATE_USD = estimateResult("USD", [651.58, 1085.85, 1737.43]);

const ESTIMATE_TITLES = [
  "Estimate via Laredo, TX · +6 % distance",
  "Estimate via San Diego, CA · +9 % distance"
];

const field = (el, id) => el.shadowRoot.querySelector(`[data-id="${id}"]`);
const all = (el, id) => [
  ...el.shadowRoot.querySelectorAll(`[data-id="${id}"]`)
];
const texts = (el, id) => all(el, id).map((n) => n.textContent.trim());
const inOption = (option, id) => option.querySelector(`[data-id="${id}"]`);
/** A leg line's words, without the Blacklisted badges that sit beside carriers. */
const legText = (line) =>
  [...line.querySelectorAll(".leg-text")].map((n) => n.textContent).join("");

async function mount(props = {}) {
  const el = createElement("c-split-lane-options", { is: SplitLaneOptions });
  Object.assign(el, {
    requestJson: REQUEST,
    startCurrency: "CAD",
    laneCurrency: "CAD",
    statsByCurrency: STATS,
    allowUseAsCost: true,
    ...props
  });
  document.body.appendChild(el);
  await flush();
  return el;
}

async function open(el) {
  field(el, "split-open").click();
  await settle();
}

function typeHandoff(option, value) {
  const input = inOption(option, "handoff-cost");
  input.value = value;
  input.dispatchEvent(new CustomEvent("change", { detail: { value } }));
}

describe("c-split-lane-options", () => {
  beforeEach(() => {
    splitOptions.mockImplementation(({ currencyCode }) =>
      Promise.resolve(currencyCode === "USD" ? HISTORY_USD : HISTORY_CAD)
    );
  });
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("shows only the Split-lane options button until it is clicked, then asks for the start currency", async () => {
    let release;
    splitOptions.mockReturnValueOnce(
      new Promise((resolve) => {
        release = resolve;
      })
    );
    const el = await mount();
    expect(field(el, "split-open").label).toBe("Split-lane options");
    expect(field(el, "split-card")).toBeNull();
    // Direct first (D1): nothing is asked before the click.
    expect(splitOptions).not.toHaveBeenCalled();

    field(el, "split-open").click();
    await flush();
    expect(field(el, "split-open")).toBeNull();
    expect(field(el, "split-card").title).toBe("Split-lane options");
    expect(field(el, "split-loading")).not.toBeNull();
    expect(splitOptions).toHaveBeenCalledTimes(1);
    expect(splitOptions).toHaveBeenCalledWith({
      requestJson: REQUEST,
      currencyCode: "CAD",
      attempt: 0
    });

    release(HISTORY_CAD);
    await settle();
    expect(field(el, "split-loading")).toBeNull();
    expect(all(el, "option").length).toBe(1);
  });

  it("starts in the start currency, asks each currency once and reuses the kept answer", async () => {
    const el = await mount({ startCurrency: "USD", laneCurrency: "USD" });
    await open(el);
    expect(splitOptions.mock.calls.map((c) => c[0].currencyCode)).toEqual([
      "USD"
    ]);
    const usd = field(el, "split-currency-usd");
    const cad = field(el, "split-currency-cad");
    expect(usd.getAttribute("aria-pressed")).toBe("true");
    expect(cad.getAttribute("aria-pressed")).toBe("false");
    expect(usd.className).toBe("slds-button slds-button_brand");
    expect(cad.className).toBe("slds-button slds-button_neutral");
    expect(texts(el, "option-total")).toEqual([
      "Total per shipment, median 4,672 USD (31 shipments)"
    ]);

    cad.click();
    await settle();
    expect(splitOptions).toHaveBeenCalledTimes(2);
    expect(splitOptions.mock.calls[1][0]).toEqual({
      requestJson: REQUEST,
      currencyCode: "CAD",
      attempt: 0
    });
    expect(cad.getAttribute("aria-pressed")).toBe("true");
    expect(usd.getAttribute("aria-pressed")).toBe("false");
    expect(texts(el, "option-total")).toEqual([
      "Total per shipment, median 6,453 CAD (31 shipments)"
    ]);

    usd.click();
    await settle();
    // The USD answer is kept: no third call.
    expect(splitOptions).toHaveBeenCalledTimes(2);
    expect(texts(el, "option-total")).toEqual([
      "Total per shipment, median 4,672 USD (31 shipments)"
    ]);

    // The currency already shown asks nothing either.
    usd.click();
    await settle();
    expect(splitOptions).toHaveBeenCalledTimes(2);
  });

  it("names the USD rate date in USD only", async () => {
    const el = await mount();
    await open(el);
    expect(field(el, "split-rate-note")).toBeNull();
    field(el, "split-currency-usd").click();
    await settle();
    expect(field(el, "split-rate-note").textContent.trim()).toBe(
      "Converted at the USD rate of 2026-08-11."
    );
  });

  it("titles a history group by its handoff and shipments, and an estimate by its extra distance", async () => {
    const history = await mount();
    await open(history);
    expect(texts(history, "option-title")).toEqual([
      "Via Laredo, TX · SFMN Park ITC Laredo yard · 34 shipments"
    ]);
    // Only an estimate takes a handoff cost.
    expect(field(history, "handoff-cost")).toBeNull();

    splitOptions.mockResolvedValueOnce(ESTIMATE_CAD);
    const estimate = await mount({ requestJson: OTHER_REQUEST });
    await open(estimate);
    expect(texts(estimate, "option-title")).toEqual(ESTIMATE_TITLES);
    expect(all(estimate, "handoff-cost").map((i) => i.label)).toEqual([
      "Handoff cost (CAD)",
      "Handoff cost (CAD)"
    ]);
  });

  it("lists each leg's carriers with legs moved, a Blacklisted badge and the median when there is one", async () => {
    const el = await mount();
    await open(el);
    const lines = all(el, "leg-line");
    expect(lines.map(legText)).toEqual([
      "Leg 1 General Escobedo, NL → Laredo, TX · Q Transportes (18), Fletes Mex (9) · median 1,248 CAD",
      "Leg 2 Laredo, TX → Saint-Augustin-de-Desmaures, QC · Nordic Lines (34) · median 5,190 CAD"
    ]);
    const badges = all(el, "leg-blacklisted");
    expect(badges.length).toBe(1);
    expect(badges[0].textContent.trim()).toBe("Blacklisted");
    expect(lines[0].contains(badges[0])).toBe(true);
    // Beside the carrier it belongs to.
    expect(badges[0].previousElementSibling.textContent).toBe("Fletes Mex (9)");

    splitOptions.mockResolvedValueOnce(ESTIMATE_CAD);
    el.requestJson = OTHER_REQUEST;
    await flush();
    await open(el);
    expect(all(el, "leg-line").map(legText)).toEqual([
      "Leg 1 Monterrey, NL → Laredo, TX · Q Transportes (12) · median 900 CAD",
      "Leg 2 Laredo, TX → Toronto, ON · Maple Freight (40) · median 1,500 CAD",
      "Leg 1 Monterrey, NL → San Diego, CA · no carrier found",
      "Leg 2 San Diego, CA → Toronto, ON · Pacific Haul (3) · median 2,100 CAD"
    ]);
    expect(all(el, "leg-blacklisted").length).toBe(1);
  });

  it("adds the typed handoff cost to an estimate: 0 counts, a blank or negative cost does not", async () => {
    splitOptions.mockResolvedValueOnce(ESTIMATE_CAD);
    const el = await mount();
    await open(el);
    const [laredo, sanDiego] = all(el, "option");
    expect(inOption(laredo, "option-total")).toBeNull();
    expect(inOption(laredo, "use-as-cost")).toBeNull();

    typeHandoff(laredo, "250");
    await flush();
    expect(inOption(laredo, "option-total").textContent.trim()).toBe(
      "Estimate total 2,650 CAD"
    );
    expect(inOption(laredo, "use-as-cost")).not.toBeNull();

    typeHandoff(laredo, "0");
    await flush();
    expect(inOption(laredo, "option-total").textContent.trim()).toBe(
      "Estimate total 2,400 CAD"
    );
    expect(inOption(laredo, "use-as-cost")).not.toBeNull();

    typeHandoff(laredo, "");
    await flush();
    expect(inOption(laredo, "option-total")).toBeNull();
    expect(inOption(laredo, "use-as-cost")).toBeNull();

    typeHandoff(laredo, "-5");
    await flush();
    expect(inOption(laredo, "option-total")).toBeNull();
    expect(inOption(laredo, "use-as-cost")).toBeNull();

    // A leg without a median leaves its estimate without a total, whatever is typed.
    typeHandoff(sanDiego, "100");
    await flush();
    expect(inOption(sanDiego, "option-total")).toBeNull();
    expect(inOption(sanDiego, "use-as-cost")).toBeNull();
  });

  it("sends the option's total, rounded to cents, with the card's currency on Use as cost", async () => {
    const el = await mount();
    const handler = jest.fn();
    el.addEventListener("useascost", handler);
    await open(el);
    inOption(all(el, "option")[0], "use-as-cost").click();
    expect(handler).toHaveBeenCalledTimes(1);
    expect(handler.mock.calls[0][0].detail).toEqual({
      cost: 6453.25,
      currencyCode: "CAD"
    });

    splitOptions.mockResolvedValueOnce(ESTIMATE_CAD);
    el.requestJson = OTHER_REQUEST;
    await flush();
    await open(el);
    const laredo = all(el, "option")[0];
    typeHandoff(laredo, "99.999");
    await flush();
    inOption(laredo, "use-as-cost").click();
    // 2400.10 + 99.999 = 2500.099, sent as 2500.10
    expect(handler.mock.calls[1][0].detail).toEqual({
      cost: 2500.1,
      currencyCode: "CAD"
    });
  });

  it("turns Use as cost off with a note while the card shows another currency than the lane's", async () => {
    const el = await mount();
    await open(el);
    expect(all(el, "use-as-cost").length).toBe(1);
    expect(field(el, "use-as-cost-off")).toBeNull();

    field(el, "split-currency-usd").click();
    await settle();
    expect(all(el, "use-as-cost").length).toBe(0);
    expect(field(el, "use-as-cost-off").textContent.trim()).toBe(
      "Switch to CAD to use a split cost."
    );

    field(el, "split-currency-cad").click();
    await settle();
    expect(all(el, "use-as-cost").length).toBe(1);
    expect(field(el, "use-as-cost-off")).toBeNull();
  });

  it("offers no Use as cost where the host does not allow it", async () => {
    const el = await mount({ allowUseAsCost: false, laneCurrency: undefined });
    await open(el);
    expect(all(el, "option").length).toBe(1);
    expect(all(el, "use-as-cost").length).toBe(0);
    field(el, "split-currency-usd").click();
    await settle();
    expect(field(el, "use-as-cost-off")).toBeNull();
  });

  it("clears a typed handoff cost when the currency switches", async () => {
    splitOptions.mockImplementation(({ currencyCode }) =>
      Promise.resolve(currencyCode === "USD" ? ESTIMATE_USD : ESTIMATE_CAD)
    );
    const el = await mount();
    await open(el);
    typeHandoff(all(el, "option")[0], "250");
    await flush();
    expect(texts(el, "option-total")).toEqual(["Estimate total 2,650 CAD"]);

    field(el, "split-currency-usd").click();
    await settle();
    expect(all(el, "handoff-cost").map((i) => i.value)).toEqual(["", ""]);
    expect(all(el, "handoff-cost")[0].label).toBe("Handoff cost (USD)");
    expect(field(el, "option-total")).toBeNull();

    field(el, "split-currency-cad").click();
    await settle();
    expect(all(el, "handoff-cost").map((i) => i.value)).toEqual(["", ""]);
    expect(field(el, "option-total")).toBeNull();
  });

  it("shows the first search's direct median in the card's currency, and nothing without one", async () => {
    const el = await mount();
    await open(el);
    expect(texts(el, "direct-median")).toEqual(["Direct median 5,980 CAD"]);
    field(el, "split-currency-usd").click();
    await settle();
    // The first search has no priced USD row.
    expect(all(el, "direct-median").length).toBe(0);

    // The lane panel's statistics are empty until its history search answers.
    const noStats = await mount({
      statsByCurrency: null,
      requestJson: OTHER_REQUEST
    });
    await open(noStats);
    expect(all(noStats, "option").length).toBe(1);
    expect(all(noStats, "direct-median").length).toBe(0);
  });

  it("shows the Apex message and retries with the next attempt", async () => {
    splitOptions.mockRejectedValueOnce({
      body: { message: "The lane could not be read right now." }
    });
    const el = await mount();
    await open(el);
    expect(field(el, "split-error").textContent.trim()).toBe(
      "The lane could not be read right now."
    );
    expect(field(el, "split-loading")).toBeNull();
    expect(all(el, "option").length).toBe(0);

    field(el, "split-retry").click();
    await settle();
    expect(splitOptions).toHaveBeenCalledTimes(2);
    expect(splitOptions.mock.calls[1][0]).toEqual({
      requestJson: REQUEST,
      currencyCode: "CAD",
      attempt: 1
    });
    expect(field(el, "split-error")).toBeNull();
    expect(field(el, "split-retry")).toBeNull();
    expect(all(el, "option").length).toBe(1);

    splitOptions.mockRejectedValueOnce(new Error("offline"));
    field(el, "split-currency-usd").click();
    await settle();
    expect(field(el, "split-error").textContent.trim()).toBe(
      "The split-lane options could not be loaded."
    );
  });

  it("shows the service message and the incomplete-list note", async () => {
    const message =
      "No split shipment on this lane in the last 12 months, and no handoff point is close enough for an estimate.";
    splitOptions.mockResolvedValueOnce({
      currencyCode: "CAD",
      rateStartDate: null,
      options: [],
      truncated: true,
      message
    });
    const el = await mount();
    await open(el);
    expect(field(el, "split-message").textContent.trim()).toBe(message);
    expect(field(el, "split-truncated").textContent.trim()).toBe(
      "The list may be incomplete."
    );
    expect(all(el, "option").length).toBe(0);
    expect(field(el, "use-as-cost-off")).toBeNull();
  });

  it("closes again for a new request and drops an answer that belongs to the old one", async () => {
    let release;
    splitOptions.mockReturnValueOnce(
      new Promise((resolve) => {
        release = resolve;
      })
    );
    const el = await mount();
    field(el, "split-open").click();
    await flush();
    el.requestJson = OTHER_REQUEST;
    await flush();
    expect(field(el, "split-card")).toBeNull();
    expect(field(el, "split-open")).not.toBeNull();

    splitOptions.mockResolvedValueOnce(ESTIMATE_CAD);
    await open(el);
    expect(splitOptions).toHaveBeenCalledTimes(2);
    expect(splitOptions.mock.calls[1][0]).toEqual({
      requestJson: OTHER_REQUEST,
      currencyCode: "CAD",
      attempt: 0
    });
    // The first lane's answer lands late: it must not replace this lane's.
    release(HISTORY_CAD);
    await settle();
    expect(texts(el, "option-title")).toEqual(ESTIMATE_TITLES);

    // The same request again changes nothing.
    el.requestJson = OTHER_REQUEST;
    await flush();
    expect(field(el, "split-card")).not.toBeNull();
  });
});
```

- [ ] **Step 2: Run it and watch it fail**

Run: `npm run test:unit -- force-app/main/default/lwc/splitLaneOptions 2>&1 | grep -E "✕|Cannot find module|^(Tests|Test Suites):"`

Expected: `Cannot find module 'c/splitLaneOptions'` and `Test Suites: 1 failed, 1 total` (the bundle does not exist yet, so no test runs).

- [ ] **Step 3: Split-lane card — the component**

Create `force-app/main/default/lwc/splitLaneOptions/splitLaneOptions.js-meta.xml`:

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<LightningComponentBundle xmlns="http://soap.sforce.com/2006/04/metadata">
  <apiVersion>64.0</apiVersion>
  <isExposed>false</isExposed>
</LightningComponentBundle>
```

Create `force-app/main/default/lwc/splitLaneOptions/splitLaneOptions.css` (the spinner is absolutely positioned, so its box needs a height):

```css
.split-loading {
  min-height: 3rem;
}
```

Create `force-app/main/default/lwc/splitLaneOptions/splitLaneOptions.js`:

```js
import { LightningElement, api } from "lwc";
import splitOptions from "@salesforce/apex/SplitLaneController.splitOptions";
import { directMedian } from "c/carrierLeadRules";

const BUTTON_ON = "slds-button slds-button_brand";
const BUTTON_OFF = "slds-button slds-button_neutral";
/** SplitLaneResult.ESTIMATE; any other kind is a history group (SplitLaneResult.HISTORY). */
const ESTIMATE = "Estimate";
const LOAD_FAILED = "The split-lane options could not be loaded.";
const AMOUNT = new Intl.NumberFormat("en-CA", { maximumFractionDigits: 0 });

const isNumber = (value) => typeof value === "number" && Number.isFinite(value);
/** "1,248 CAD": the card shows whole amounts, in its own currency. */
const amountText = (value, code) => `${AMOUNT.format(value)} ${code}`;

/** The handoff cost as typed: a number of 0 or more, else null (blank, junk or negative). */
function handoffNumber(text) {
  if (text === null || text === undefined) {
    return null;
  }
  const trimmed = String(text).trim();
  if (trimmed === "") {
    return null;
  }
  const n = Number(trimmed);
  return Number.isFinite(n) && n >= 0 ? n : null;
}

/**
 * An option's total per shipment in the card's currency, or null: a history
 * group's median total (R85), or an estimate's two leg medians plus the typed
 * handoff cost (D8). An estimate with a leg that has no median has no total.
 */
function optionTotal(option, handoffText) {
  if (!isNumber(option.medianTotal)) {
    return null;
  }
  if (option.kind !== ESTIMATE) {
    return option.medianTotal;
  }
  const handoff = handoffNumber(handoffText);
  return handoff === null ? null : option.medianTotal + handoff;
}

/**
 * One leg line: "Leg 1 <lane> · " then each carrier with its legs moved (a
 * blacklisted one gets its badge in the template), then " · median <amount>"
 * when the leg has priced loads. Separators live in the strings, because the
 * template compiler drops whitespace between tags.
 */
function legView(leg, code) {
  const carriers = leg.carriers || [];
  return {
    key: `leg-${leg.position}`,
    head: `Leg ${leg.position} ${leg.laneLabel} · ${carriers.length ? "" : "no carrier found"}`,
    carriers: carriers.map((c, i) => ({
      key: c.carrierId || `carrier-${i}`,
      text: `${c.name} (${c.legsMoved})`,
      blacklisted: c.blacklisted === true,
      separator: i < carriers.length - 1 ? ", " : ""
    })),
    tail: isNumber(leg.median)
      ? ` · median ${amountText(leg.median, code)}`
      : ""
  };
}

/**
 * Split-lane options for one lane request (spec §4): nothing is asked until
 * the pricer clicks the button (D1); the card then shows one currency at a
 * time, CAD or USD, and keeps each currency's answer for this request.
 */
export default class SplitLaneOptions extends LightningElement {
  /** "CAD" or "USD": the currency the card opens in; anything else opens in CAD. */
  @api startCurrency;
  /** The currency Use as cost works in: the RFP lane's. Unset on Lane Benchmark. */
  @api laneCurrency;
  /** The first search's statistics by currency, for the direct median (R96). */
  @api statsByCurrency;
  /** Only the RFP lane panel lets an option fill its price editor (D9). */
  @api allowUseAsCost = false;

  _requestJson = null;
  opened = false;
  /** The card's currency once opened: "CAD" or "USD". */
  currencyCode = null;
  /** SplitLaneResult by currency code, for the request on screen. */
  answers = {};
  /** The typed handoff cost by estimate option key, in the card's currency. */
  handoffCosts = {};
  loading = false;
  error = null;
  /** 0 on the first call and one more per Retry, so a retry reaches the server past the cache. */
  attempt = 0;
  /** Bumped per call: only the latest call moves the spinner or shows an error. */
  seq = 0;
  /** Bumped per new request: an answer for an earlier request is dropped. */
  generation = 0;

  /** The request the first search ran. A new one closes the card and forgets what it kept. */
  @api
  get requestJson() {
    return this._requestJson;
  }
  set requestJson(value) {
    const next = value || null;
    if (next === this._requestJson) {
      return;
    }
    this._requestJson = next;
    this.generation += 1;
    this.seq += 1;
    this.opened = false;
    this.currencyCode = null;
    this.answers = {};
    this.handoffCosts = {};
    this.loading = false;
    this.error = null;
    this.attempt = 0;
  }

  get cadClass() {
    return this.currencyCode === "CAD" ? BUTTON_ON : BUTTON_OFF;
  }
  get usdClass() {
    return this.currencyCode === "USD" ? BUTTON_ON : BUTTON_OFF;
  }
  get cadPressed() {
    return this.currencyCode === "CAD" ? "true" : "false";
  }
  get usdPressed() {
    return this.currencyCode === "USD" ? "true" : "false";
  }
  get result() {
    return (this.currencyCode && this.answers[this.currencyCode]) || null;
  }
  get hasOptions() {
    const r = this.result;
    return !!(r && r.options && r.options.length);
  }
  get message() {
    return (this.result && this.result.message) || null;
  }
  get truncated() {
    return !!(this.result && this.result.truncated);
  }
  get rateNote() {
    const r = this.result;
    return this.currencyCode === "USD" && r && r.rateStartDate
      ? `Converted at the USD rate of ${r.rateStartDate}.`
      : null;
  }
  get handoffLabel() {
    return `Handoff cost (${this.currencyCode})`;
  }
  /** Use as cost fills the lane's price editor, so only in the lane's own currency (R88). */
  get canUseAsCost() {
    return !!this.allowUseAsCost && this.currencyCode === this.laneCurrency;
  }
  get useAsCostOff() {
    return this.allowUseAsCost &&
      this.laneCurrency &&
      this.hasOptions &&
      !this.canUseAsCost
      ? `Switch to ${this.laneCurrency} to use a split cost.`
      : null;
  }
  get directMedianText() {
    const median = directMedian(this.statsByCurrency || {}, this.currencyCode);
    return isNumber(median)
      ? `Direct median ${amountText(median, this.currencyCode)}`
      : null;
  }
  get options() {
    const r = this.result;
    if (!r || !r.options) {
      return [];
    }
    const code = this.currencyCode;
    return r.options.map((option, index) => {
      const key = `${option.kind}-${index}`;
      const isEstimate = option.kind === ESTIMATE;
      const handoffText = this.handoffCosts[key] ?? "";
      const total = optionTotal(option, handoffText);
      let totalText = null;
      if (total !== null) {
        totalText = isEstimate
          ? `Estimate total ${amountText(total, code)}`
          : `Total per shipment, median ${amountText(total, code)} (${option.pricedShipments} shipments)`;
      }
      return {
        key,
        index,
        isEstimate,
        title: isEstimate
          ? `Estimate via ${option.handoffLabel} · +${option.extraDistancePct} % distance`
          : `Via ${option.handoffLabel} · ${option.shipments} shipments`,
        legs: (option.legs || []).map((leg) => legView(leg, code)),
        handoffText,
        totalText,
        canUse: this.canUseAsCost && total !== null
      };
    });
  }

  handleOpen() {
    this.opened = true;
    this.currencyCode = this.startCurrency === "USD" ? "USD" : "CAD";
    this.load();
  }
  handleCad() {
    this.pick("CAD");
  }
  handleUsd() {
    this.pick("USD");
  }

  /** Another currency: typed handoff costs are cleared, and a kept answer shows without a call. */
  pick(code) {
    if (code === this.currencyCode) {
      return;
    }
    this.currencyCode = code;
    this.handoffCosts = {};
    this.error = null;
    if (this.answers[code]) {
      this.seq += 1;
      this.loading = false;
      return;
    }
    this.load();
  }

  handleRetry() {
    this.attempt += 1;
    this.load();
  }

  handleHandoff(event) {
    this.handoffCosts = {
      ...this.handoffCosts,
      [event.currentTarget.dataset.option]: event.detail.value
    };
  }

  handleUseAsCost(event) {
    const r = this.result;
    const index = Number(event.currentTarget.dataset.index);
    const option = r && r.options ? r.options[index] : null;
    if (!option || !this.canUseAsCost) {
      return;
    }
    const total = optionTotal(
      option,
      this.handoffCosts[`${option.kind}-${index}`]
    );
    if (total === null) {
      return;
    }
    this.dispatchEvent(
      new CustomEvent("useascost", {
        detail: {
          cost: Math.round(total * 100) / 100,
          currencyCode: this.currencyCode
        }
      })
    );
  }

  async load() {
    const seq = ++this.seq;
    const generation = this.generation;
    const code = this.currencyCode;
    this.loading = true;
    this.error = null;
    try {
      const result = await splitOptions({
        requestJson: this._requestJson,
        currencyCode: code,
        attempt: this.attempt
      });
      if (generation === this.generation) {
        this.answers = { ...this.answers, [code]: result || { options: [] } };
      }
    } catch (e) {
      if (seq === this.seq) {
        this.error = (e && e.body && e.body.message) || LOAD_FAILED;
      }
    } finally {
      if (seq === this.seq) {
        this.loading = false;
      }
    }
  }
}
```

Create `force-app/main/default/lwc/splitLaneOptions/splitLaneOptions.html` (the CAD | USD buttons copy `c-distance-unit-toggle`'s `slds-button-group` with `aria-pressed`; the leg words sit in `.leg-text` spans with their separators inside the strings, because the LWC template compiler drops whitespace between tags):

```html
<template>
  <template lwc:if={opened}>
    <lightning-card
      data-id="split-card"
      title="Split-lane options"
      icon-name="standard:shipment"
    >
      <div
        slot="actions"
        class="slds-button-group"
        role="group"
        aria-label="Split-lane currency"
      >
        <button
          type="button"
          data-id="split-currency-cad"
          class={cadClass}
          aria-pressed={cadPressed}
          onclick={handleCad}
        >
          CAD
        </button>
        <button
          type="button"
          data-id="split-currency-usd"
          class={usdClass}
          aria-pressed={usdPressed}
          onclick={handleUsd}
        >
          USD
        </button>
      </div>
      <div class="slds-p-horizontal_medium">
        <template lwc:if={loading}>
          <div class="slds-is-relative split-loading">
            <lightning-spinner
              data-id="split-loading"
              size="small"
              alternative-text="Loading the split-lane options"
            ></lightning-spinner>
          </div>
        </template>
        <template lwc:if={error}>
          <p data-id="split-error" class="slds-text-color_error" role="alert">
            {error}
          </p>
          <lightning-button
            data-id="split-retry"
            class="slds-m-top_x-small"
            label="Retry"
            onclick={handleRetry}
          ></lightning-button>
        </template>
        <template lwc:if={rateNote}>
          <p
            data-id="split-rate-note"
            class="slds-text-body_small slds-text-color_weak"
          >
            {rateNote}
          </p>
        </template>
        <template lwc:if={message}>
          <p data-id="split-message" class="slds-text-color_weak">{message}</p>
        </template>
        <template lwc:if={truncated}>
          <p
            data-id="split-truncated"
            class="slds-text-body_small slds-text-color_weak"
          >
            The list may be incomplete.
          </p>
        </template>
        <template lwc:if={useAsCostOff}>
          <p
            data-id="use-as-cost-off"
            class="slds-text-body_small slds-text-color_weak"
          >
            {useAsCostOff}
          </p>
        </template>
        <template for:each={options} for:item="option">
          <div
            key={option.key}
            data-id="option"
            class="slds-box slds-box_x-small slds-m-top_x-small"
          >
            <p data-id="option-title" class="slds-text-title_bold">
              {option.title}
            </p>
            <template for:each={option.legs} for:item="leg">
              <p key={leg.key} data-id="leg-line" class="slds-text-body_small">
                <span class="leg-text">{leg.head}</span>
                <template for:each={leg.carriers} for:item="carrier">
                  <span key={carrier.key}>
                    <span class="leg-text">{carrier.text}</span>
                    <template lwc:if={carrier.blacklisted}>
                      <span
                        data-id="leg-blacklisted"
                        class="slds-badge slds-theme_error slds-m-left_x-small"
                        >Blacklisted</span
                      >
                    </template>
                    <span class="leg-text">{carrier.separator}</span>
                  </span>
                </template>
                <span class="leg-text">{leg.tail}</span>
              </p>
            </template>
            <template lwc:if={option.isEstimate}>
              <lightning-input
                data-id="handoff-cost"
                data-option={option.key}
                type="number"
                step="0.01"
                min="0"
                label={handoffLabel}
                value={option.handoffText}
                onchange={handleHandoff}
              ></lightning-input>
            </template>
            <template lwc:if={option.totalText}>
              <p
                data-id="option-total"
                class="slds-text-title_bold slds-m-top_xx-small"
              >
                {option.totalText}
              </p>
            </template>
            <template lwc:if={directMedianText}>
              <p
                data-id="direct-median"
                class="slds-text-body_small slds-text-color_weak"
              >
                {directMedianText}
              </p>
            </template>
            <template lwc:if={option.canUse}>
              <lightning-button
                data-id="use-as-cost"
                data-index={option.index}
                class="slds-m-top_xx-small"
                label="Use as cost"
                onclick={handleUseAsCost}
              ></lightning-button>
            </template>
          </div>
        </template>
      </div>
    </lightning-card>
  </template>
  <template lwc:else>
    <lightning-button
      data-id="split-open"
      class="slds-m-top_small"
      label="Split-lane options"
      onclick={handleOpen}
    ></lightning-button>
  </template>
</template>
```

- [ ] **Step 4: Run the card suite to pass**

Run: `npm run test:unit -- force-app/main/default/lwc/splitLaneOptions 2>&1 | grep -E "✕|^(Tests|Test Suites):"`

Expected: no `✕` line, `Test Suites: 1 passed, 1 total`, `Tests: 14 passed, 14 total`.

- [ ] **Step 5: Cost sources — write the failing tests**

In `force-app/main/default/lwc/rfpPricing/__tests__/rfpPricing.test.js`, replace the start of the import list:

```js
import {
  SOURCES,
  money,
```

with:

```js
import {
  SOURCES,
  SPLIT_SOURCE,
  money,
```

Then, right before the test `it("labels bid options with the carrier, rate and expiry", () => {`, add:

```js
  it("keeps Split out of the sources a pricer picks", () => {
    expect(SPLIT_SOURCE).toEqual({ label: "Split", value: "Split" });
    expect(SOURCES.map((s) => s.value)).not.toContain("Split");
  });

  it("reads a Split cost from the filled amount, then from the lane's stored cost", () => {
    const state = {
      lane: LANE,
      bids: [ACTIVE],
      selectedBidId: "a0B1",
      manualCost: "1750.25"
    };
    expect(costFor("Split", { ...state, splitCost: 6453.25 })).toBe(6453.25);
    expect(costFor("Split", { ...state, splitCost: 0 })).toBe(0);
    // Nothing filled yet: the cost the lane was saved with (LANE.Cost__c).
    expect(costFor("Split", state)).toBe(1000);
    expect(costFor("Split", { ...state, splitCost: null })).toBe(1000);
    expect(costFor("Split", { ...state, splitCost: Number.NaN })).toBe(1000);
    expect(costFor("Split", { ...state, splitCost: "6453.25" })).toBe(1000);
    expect(
      costFor("Split", { ...state, lane: { ...LANE, Cost__c: null } })
    ).toBeNull();
    expect(costFor("Split", { ...state, lane: null })).toBeNull();
    // The filled amount belongs to Split alone.
    expect(costFor("Manual", { ...state, splitCost: 6453.25 })).toBe(1750.25);
    expect(
      pricingDetail({
        laneId: "a0L1",
        source: "Split",
        selectedBidId: "a0B1",
        cost: 6450,
        marginText: "10",
        notes: ""
      })
    ).toEqual({
      laneId: "a0L1",
      Cost__c: 6450,
      Cost_Source__c: "Split",
      Selected_Bid__c: null,
      Margin__c: 10,
      Sell__c: 7095,
      Sell_Source__c: "Margin",
      Notes__c: null
    });
  });
```

- [ ] **Step 6: Run it and watch the two new tests fail**

Run: `npm run test:unit -- force-app/main/default/lwc/rfpPricing 2>&1 | grep -E "✕|^(Tests|Test Suites):"`

Expected: `✕ keeps Split out of the sources a pricer picks` (`SPLIT_SOURCE` is `undefined`) and `✕ reads a Split cost from the filled amount, then from the lane's stored cost` (`costFor("Split", …)` still falls through to the manual branch and returns `1750.25`), `Tests: 2 failed, 26 passed, 28 total`.

- [ ] **Step 7: Cost sources — `SPLIT_SOURCE` and `costFor`**

In `force-app/main/default/lwc/rfpPricing/rfpPricing.js`, replace:

```js
/** The three values RFP_Lane__c.Cost_Source__c accepts. */
export const SOURCES = [
  { label: "Bid", value: "Bid" },
  { label: "History median", value: "History median" },
  { label: "Manual", value: "Manual" }
];
```

with:

```js
/** The three cost sources a pricer picks; RFP_Lane__c.Cost_Source__c also accepts Split. */
export const SOURCES = [
  { label: "Bid", value: "Bid" },
  { label: "History median", value: "History median" },
  { label: "Manual", value: "Manual" }
];

/**
 * A cost filled from a split-lane option (Use as cost). It is never a source
 * to pick: the lane panel lists it only while it is the lane's source (R98).
 */
export const SPLIT_SOURCE = { label: "Split", value: "Split" };
```

Then replace the head of `costFor`:

```js
/** The cost the editor is currently showing, or null when it has none yet. */
export function costFor(source, { lane, bids, selectedBidId, manualCost }) {
  if (source === "Bid") {
    const picked = (bids || []).find((b) => b.Id === selectedBidId);
    return picked ? Number(picked.Rate__c) : null;
  }
  if (source === "History median") {
    const median = lane && lane.Hist_Median__c;
    return median === null || median === undefined ? null : Number(median);
  }
```

with:

```js
/** The cost the editor is currently showing, or null when it has none yet. */
export function costFor(
  source,
  { lane, bids, selectedBidId, manualCost, splitCost }
) {
  if (source === "Bid") {
    const picked = (bids || []).find((b) => b.Id === selectedBidId);
    return picked ? Number(picked.Rate__c) : null;
  }
  if (source === "History median") {
    const median = lane && lane.Hist_Median__c;
    return median === null || median === undefined ? null : Number(median);
  }
  if (source === "Split") {
    // The total Use as cost filled in; before that, the cost the lane was saved with.
    if (typeof splitCost === "number" && Number.isFinite(splitCost)) {
      return splitCost;
    }
    const stored = lane && lane.Cost__c;
    return stored === null || stored === undefined || stored === ""
      ? null
      : Number(stored);
  }
```

The manual branch after it is unchanged. `pricingDetail`, `inlineEdit` and `recompute` need no change: they pass `Cost_Source__c` through, and `Selected_Bid__c` stays `null` for any source but `Bid`.

- [ ] **Step 8: Run the pricing suite to pass**

Run: `npm run test:unit -- force-app/main/default/lwc/rfpPricing 2>&1 | grep -E "✕|^(Tests|Test Suites):"`

Expected: no `✕` line, `Tests: 28 passed, 28 total`.

- [ ] **Step 9: Lane panel — write the failing tests**

In `force-app/main/default/lwc/rfpLanePanel/__tests__/rfpLanePanel.test.js`, right after the line

```js
import laneRoute from "@salesforce/apex/RfpLaneController.laneRoute";
```

add:

```js
import splitOptions from "@salesforce/apex/SplitLaneController.splitOptions";
```

Replace Task 7's `jest.mock` for `CarrierLeadController.findCarrierLeads` (it occurs once in the file):

```js
jest.mock(
  "@salesforce/apex/CarrierLeadController.findCarrierLeads",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
```

with the same block followed by the split mock (the panel now renders the real `c-split-lane-options`, which imports it):

```js
jest.mock(
  "@salesforce/apex/CarrierLeadController.findCarrierLeads",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/SplitLaneController.splitOptions",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
```

Before the file's last line (`});`, which closes `describe("c-rfp-lane-panel")`), add:

```js
  describe("split-lane options and the Split cost", () => {
    const split = (el) => field(el, "split-options");
    const useAsCost = (el, cost) =>
      split(el).dispatchEvent(
        new CustomEvent("useascost", { detail: { cost, currencyCode: "CAD" } })
      );
    const sourceValues = (el) =>
      field(el, "cost-source").options.map((o) => o.value);

    it("hands the lane's history request, currency and statistics to the split card", async () => {
      const stats = {
        CAD: { count: 1, countNonZero: 1, median: 1950 },
        USD: { count: 1, countNonZero: 1, median: 1420 }
      };
      search.mockResolvedValue({ ...HISTORY, statsByCurrency: stats });
      const el = await mount({ lane: { ...LANE, CurrencyIsoCode: "USD" } });
      expect(split(el)).not.toBeNull();
      expect(split(el).requestJson).toBe(search.mock.calls[0][0].requestJson);
      expect(split(el).startCurrency).toBe("USD");
      expect(split(el).laneCurrency).toBe("USD");
      expect(split(el).statsByCurrency).toEqual(stats);
      expect(split(el).allowUseAsCost).toBe(true);
      // The card asks nothing until the pricer clicks it (D1).
      expect(splitOptions).not.toHaveBeenCalled();

      el.lane = { ...LANE, Id: "a0L00000002", Destination_Place__r: undefined };
      await flush();
      expect(split(el)).toBeNull();
    });

    it("fills the editor from a split option: source Split, bid cleared, cost locked, saved as a Split cost", async () => {
      getBids.mockResolvedValue([CHEAP_BID]);
      const el = await mount({
        lane: {
          ...LANE,
          Cost_Source__c: "Bid",
          Selected_Bid__c: "a0B00000001",
          Cost__c: 1800
        }
      });
      expect(field(el, "bid-select")).not.toBeNull();
      const handler = jest.fn();
      el.addEventListener("pricingchange", handler);

      useAsCost(el, 6450);
      await flush();
      expect(field(el, "cost-source").value).toBe("Split");
      expect(field(el, "bid-select")).toBeNull();
      expect(field(el, "cost").value).toBe(6450);
      expect(field(el, "cost").disabled).toBe(true);

      change(el, "margin", { value: "10" });
      await flush();
      field(el, "save-price").click();
      expect(handler).toHaveBeenCalledTimes(1);
      expect(handler.mock.calls[0][0].detail).toEqual({
        laneId: "a0L00000001",
        Cost__c: 6450,
        Cost_Source__c: "Split",
        Selected_Bid__c: null,
        Margin__c: 10,
        Sell__c: 7095,
        Sell_Source__c: "Margin",
        Notes__c: "Watch the ferry surcharge"
      });
    });

    it("offers Split as a cost source only while Split is the source", async () => {
      const el = await mount();
      expect(sourceValues(el)).toEqual(["Bid", "History median", "Manual"]);
      useAsCost(el, 2400);
      await flush();
      expect(sourceValues(el)).toEqual([
        "Bid",
        "History median",
        "Manual",
        "Split"
      ]);
      change(el, "cost-source", { value: "Manual" });
      await flush();
      expect(sourceValues(el)).toEqual(["Bid", "History median", "Manual"]);
      expect(field(el, "cost").disabled).toBe(false);
      expect(field(el, "cost").value).toBe("1500");
    });

    it("shows a lane saved with Split at its stored cost, and lets stored pricing replace a filled amount", async () => {
      const el = await mount({
        lane: { ...LANE, Cost_Source__c: "Split", Cost__c: 6400 }
      });
      expect(field(el, "cost-source").value).toBe("Split");
      expect(sourceValues(el)).toContain("Split");
      expect(field(el, "cost").value).toBe(6400);

      useAsCost(el, 6510.4);
      await flush();
      expect(field(el, "cost").value).toBe(6510.4);

      // A bulk action stored another Split cost on the lane on screen.
      el.lane = { ...LANE, Cost_Source__c: "Split", Cost__c: 6300 };
      await flush();
      expect(field(el, "cost").value).toBe(6300);

      useAsCost(el, 6999);
      await flush();
      // Another lane: nothing is filled for it yet.
      el.lane = {
        ...LANE,
        Id: "a0L00000002",
        Cost_Source__c: "Split",
        Cost__c: 5900
      };
      await flush();
      expect(field(el, "cost").value).toBe(5900);
    });
  });
```

The first test's lane is in USD and its statistics have a priced USD row, so Task 7's Carriers to ask stays hidden and the test reads only the split card.

- [ ] **Step 10: Run it and watch the four new tests fail**

Run: `npm run test:unit -- force-app/main/default/lwc/rfpLanePanel 2>&1 | grep -E "✕|^(Tests|Test Suites):"`

Expected: the four `split-lane options and the Split cost` tests marked `✕`: the first because `split-options` is `null` (`Received: null`), the second and third with `TypeError: Cannot read properties of null (reading 'dispatchEvent')`, the fourth because the source options are still `["Bid", "History median", "Manual"]`. `Tests: 4 failed, 38 passed, 42 total` (38 after Task 7).

- [ ] **Step 11: Lane panel — Use as cost and the Split source**

In `force-app/main/default/lwc/rfpLanePanel/rfpLanePanel.js`, in the `c/rfpPricing` import list replace

```js
  SOURCES,
  costFor,
```

with:

```js
  SOURCES,
  SPLIT_SOURCE,
  costFor,
```

Right after the line

```js
const ROUTE_UNAVAILABLE = "The truck route is not available right now.";
```

add:

```js
/** The source buttons while a split cost is the lane's source: Split shows as chosen, never as a pick (R98). */
const SOURCES_WITH_SPLIT = [...SOURCES, SPLIT_SOURCE];
```

Replace the field

```js
  sourceOptions = SOURCES;
```

with:

```js
  /**
   * The total Use as cost filled in from a split-lane option: null until then,
   * and again whenever syncPricing takes the stored pricing (a new lane, a price
   * save, an inline edit or a bulk action), so a stored Split cost reads Cost__c.
   */
  splitCost = null;
```

In `syncPricing`, replace

```js
  syncPricing() {
    const l = this._lane || {};
    this.costSource = l.Cost_Source__c || "Manual";
```

with:

```js
  syncPricing() {
    const l = this._lane || {};
    this.costSource = l.Cost_Source__c || "Manual";
    this.splitCost = null;
```

(`syncFromLane` calls `syncPricing`, so a new lane also drops the filled amount.) Right before the getter line

```js
  get isBidSource() {
```

add:

```js
  get sourceOptions() {
    return this.costSource === "Split" ? SOURCES_WITH_SPLIT : SOURCES;
  }
```

In the `costNumber` getter, replace

```js
      manualCost: this.manualCost
    });
```

with:

```js
      manualCost: this.manualCost,
      splitCost: this.splitCost
    });
```

Right before

```js
  handleRefreshRoute() {
```

add:

```js
  /**
   * A split-lane option's total becomes the cost, as choosing a bid does: the
   * source turns Split, any selected bid is cleared, and Save price stores it.
   */
  handleUseAsCost(event) {
    this.costSource = "Split";
    this.selectedBidId = null;
    this.splitCost = event.detail.cost;
  }
```

`costLocked` (`costSource !== "Manual"`), `costInputValue`, `pricing` and `handleSource` need no change: a Split cost is locked like any source but Manual, `pricingDetail` sends `Cost_Source__c: "Split"` with `Selected_Bid__c: null`, and choosing another source replaces Split.

In `force-app/main/default/lwc/rfpLanePanel/rfpLanePanel.html`, replace the end of Task 7's Carriers to ask block:

```html
            currency-code={currency}
          ></c-carrier-leads>
        </div>
      </template>
```

with:

```html
            currency-code={currency}
          ></c-carrier-leads>
        </div>
      </template>
      <template lwc:if={historyRequestJson}>
        <div data-id="split" class="slds-m-top_x-small">
          <c-split-lane-options
            data-id="split-options"
            request-json={historyRequestJson}
            start-currency={currency}
            lane-currency={currency}
            stats-by-currency={historyStats}
            allow-use-as-cost
            onuseascost={handleUseAsCost}
          ></c-split-lane-options>
        </div>
      </template>
```

In `force-app/main/default/lwc/rfpTool/__tests__/rfpTool.test.js`, replace Task 7's `jest.mock` for `CarrierLeadController.findCarrierLeads` (it occurs once in the file):

```js
jest.mock(
  "@salesforce/apex/CarrierLeadController.findCarrierLeads",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
```

with:

```js
jest.mock(
  "@salesforce/apex/CarrierLeadController.findCarrierLeads",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/SplitLaneController.splitOptions",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
```

- [ ] **Step 12: Run the panel and workbench suites to pass**

Run: `npm run test:unit -- force-app/main/default/lwc/rfpLanePanel/ force-app/main/default/lwc/rfpTool/ 2>&1 | grep -E "✕|^(Tests|Test Suites):"`

Expected: no `✕` line, `Test Suites: 2 passed, 2 total`, `Tests: 76 passed, 76 total` (panel 42, workbench 34; the trailing slashes keep `rfpToolbar` out). The workbench renders the real panel and card; the card asks nothing until clicked, so its mock is never called.

- [ ] **Step 13: Lane Benchmark — write the failing tests**

In `force-app/main/default/lwc/laneBenchmark/__tests__/laneBenchmark.test.js`, right after the line

```js
import truckRoute from "@salesforce/apex/LaneBenchmarkController.truckRoute";
```

add:

```js
import splitOptions from "@salesforce/apex/SplitLaneController.splitOptions";
```

Replace Task 7's `jest.mock` for `CarrierLeadController.findCarrierLeads` (it occurs once in the file):

```js
jest.mock(
  "@salesforce/apex/CarrierLeadController.findCarrierLeads",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
```

with:

```js
jest.mock(
  "@salesforce/apex/CarrierLeadController.findCarrierLeads",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/SplitLaneController.splitOptions",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
```

Before the file's last line (`});`, which closes `describe("c-lane-benchmark")`), add:

```js
  it("puts Split-lane options under the results once a search ran with both place keys", async () => {
    const el = await mount();
    const filters = () =>
      el.shadowRoot.querySelector("c-lane-benchmark-filters");
    const split = () =>
      el.shadowRoot.querySelector('[data-id="split-options"]');
    pickLane(el);
    filters().dispatchEvent(
      new CustomEvent("filterschange", { detail: { currencyIsoCode: "USD" } })
    );
    applySearch(el);
    await settle();
    expect(split()).not.toBeNull();
    expect(split().requestJson).toBe(search.mock.calls[0][0].requestJson);
    expect(split().startCurrency).toBe("USD");
    expect(split().statsByCurrency).toEqual(RESULT.statsByCurrency);
    // Lane Benchmark has no price editor to fill.
    expect(split().allowUseAsCost).toBe(false);
    // Direct first (D1): the card asks nothing before its button is clicked.
    expect(splitOptions).not.toHaveBeenCalled();
    // It sits at the bottom, after the results.
    expect(
      [
        ...el.shadowRoot.querySelectorAll(
          "c-lane-benchmark-results, c-split-lane-options"
        )
      ].map((n) => n.tagName.toLowerCase())
    ).toEqual(["c-lane-benchmark-results", "c-split-lane-options"]);

    // Without a currency filter the card opens in CAD.
    filters().dispatchEvent(
      new CustomEvent("filterschange", { detail: { currencyIsoCode: null } })
    );
    applySearch(el);
    await settle();
    expect(split().startCurrency).toBe("CAD");
    expect(split().requestJson).toBe(search.mock.calls[1][0].requestJson);
  });

  it("hides Split-lane options after a search with an end that has no place key", async () => {
    const el = await mount();
    pickLane(el);
    applySearch(el);
    await settle();
    expect(
      el.shadowRoot.querySelector('[data-id="split-options"]')
    ).not.toBeNull();
    pick(el, "destination", {
      key: null,
      label: "",
      precision: "CITY",
      radius: null,
      unit: "MI"
    });
    applySearch(el);
    await settle();
    expect(search).toHaveBeenCalledTimes(2);
    expect(el.shadowRoot.querySelector('[data-id="split-options"]')).toBeNull();
    expect(
      el.shadowRoot.querySelector("c-lane-benchmark-results").rows.length
    ).toBe(1);
  });
```

- [ ] **Step 14: Run it and watch the two new tests fail**

Run: `npm run test:unit -- force-app/main/default/lwc/laneBenchmark/__tests__ 2>&1 | grep -E "✕|^(Tests|Test Suites):"`

Expected: `✕ puts Split-lane options under the results once a search ran with both place keys` and `✕ hides Split-lane options after a search with an end that has no place key`, both at their first `not.toBeNull()` (`Received: null`); `Tests: 2 failed, 19 passed, 21 total` (19 after Task 7). The path ends in `__tests__` so the other `laneBenchmark*` suites do not run.

- [ ] **Step 15: Lane Benchmark — the split card under the results**

In `force-app/main/default/lwc/laneBenchmark/laneBenchmark.js`, right before

```js
  async connectedCallback() {
```

add:

```js
  /** Split-lane options need a place key on both ends of the search that ran (spec §4). */
  get showSplitOptions() {
    return this.hasResult && hasBothKeys(this.lastRequestJson);
  }
  /** The split card opens in the currency filter the search ran with, or in CAD without one. */
  get splitStartCurrency() {
    return this.lastCurrency === "USD" ? "USD" : "CAD";
  }
```

In `force-app/main/default/lwc/laneBenchmark/laneBenchmark.html`, right after

```html
        <c-lane-benchmark-results
          rows={rows}
          unit={unit}
          origin-label={request.originLabel}
          destination-label={request.destinationLabel}
        ></c-lane-benchmark-results>
```

add (inside the `hasResult` block, the last thing in the right column):

```html
        <template lwc:if={showSplitOptions}>
          <div class="slds-m-top_small">
            <c-split-lane-options
              data-id="split-options"
              request-json={lastRequestJson}
              start-currency={splitStartCurrency}
              stats-by-currency={statsByCurrency}
            ></c-split-lane-options>
          </div>
        </template>
```

No `laneCurrency` and no `allow-use-as-cost`: Lane Benchmark has no price editor (spec §7).

- [ ] **Step 16: Run the Lane Benchmark suite to pass**

Run: `npm run test:unit -- force-app/main/default/lwc/laneBenchmark/__tests__ 2>&1 | grep -E "✕|^(Tests|Test Suites):"`

Expected: no `✕` line, `Tests: 21 passed, 21 total`.

- [ ] **Step 17: Excel export — write the failing test**

In `force-app/main/default/lwc/rfpWorkbook/__tests__/rfpWorkbook.test.js`, in the first test ("keeps the customer's order and columns, appends ours, leaves unpriced cells empty"), the two fixed positions of Sell move by one column. Replace

```js
    expect(sheet[1][5]).toBe(1150);
```

with:

```js
    expect(sheet[1][2 + OUR_COLUMNS.indexOf("Sell")]).toBe(1150);
```

and replace

```js
    expect(sheet[2][5]).toBe("");
```

with:

```js
    expect(sheet[2][2 + OUR_COLUMNS.indexOf("Sell")]).toBe("");
```

Then, right before `it("names the file from customer, project and date", () => {`, add:

```js
  it("puts the cost source right after Currency, blank while the lane has no cost", () => {
    const sourced = [
      {
        Id: "c1",
        Row_Number__c: 1,
        Cost__c: 6453.25,
        Cost_Source__c: "Split",
        CurrencyIsoCode: "USD"
      },
      {
        Id: "c2",
        Row_Number__c: 2,
        Cost__c: 1800,
        Cost_Source__c: "Bid",
        CurrencyIsoCode: "CAD"
      },
      {
        Id: "c3",
        Row_Number__c: 3,
        Cost__c: 2000,
        Cost_Source__c: "History median",
        CurrencyIsoCode: "CAD"
      },
      {
        Id: "c4",
        Row_Number__c: 4,
        Cost__c: 900,
        Cost_Source__c: "Manual",
        CurrencyIsoCode: "CAD"
      },
      // A source left on a lane without a cost says nothing.
      {
        Id: "c5",
        Row_Number__c: 5,
        Cost__c: null,
        Cost_Source__c: "Manual",
        CurrencyIsoCode: "CAD"
      },
      {
        Id: "c6",
        Row_Number__c: 6,
        Cost__c: "",
        Cost_Source__c: "Split",
        CurrencyIsoCode: "CAD"
      },
      { Id: "c7", Row_Number__c: 7, CurrencyIsoCode: "CAD" }
    ];
    const { lanes: sheet } = buildSheets(sourced, [], {});
    const header = sheet[0];
    const at = header.indexOf("Currency");
    expect(header.slice(at - 1, at + 3)).toEqual([
      "Cost",
      "Currency",
      "Cost source",
      "Margin %"
    ]);
    expect(OUR_COLUMNS.length).toBe(19);
    expect(sheet.slice(1).map((row) => row[at + 1])).toEqual([
      "Split",
      "Bid",
      "History median",
      "Manual",
      "",
      "",
      ""
    ]);
    expect(sheet[1].slice(at - 1, at + 1)).toEqual([6453.25, "USD"]);
  });
```

- [ ] **Step 18: Run it and watch the new test fail**

Run: `npm run test:unit -- force-app/main/default/lwc/rfpWorkbook 2>&1 | grep -E "✕|^(Tests|Test Suites):"`

Expected: `✕ puts the cost source right after Currency, blank while the lane has no cost` (the header after Currency is still `Margin %`), `Tests: 1 failed, 6 passed, 7 total`. The two rewritten assertions pass before and after the change.

- [ ] **Step 19: Excel export — the Cost source column**

In `force-app/main/default/lwc/rfpWorkbook/rfpWorkbook.js`, in `OUR_COLUMNS` replace

```js
  "Cost",
  "Currency",
  "Margin %",
```

with:

```js
  "Cost",
  "Currency",
  "Cost source",
  "Margin %",
```

(`BID_HEADER` keeps its own `Currency` with nothing added.) Replace

```js
const priced = (l) => isNum(l.Cost__c);
```

with:

```js
const priced = (l) => isNum(l.Cost__c);

/** Bid, History median, Manual or Split; blank while the lane has no cost. */
function costSource(l) {
  return l.Cost__c === null || l.Cost__c === undefined || l.Cost__c === ""
    ? ""
    : cell(l.Cost_Source__c);
}
```

In `buildSheets`, in the lane row, replace

```js
        : cell(l.CurrencyIsoCode),
      cell(l.Margin__c),
```

with:

```js
        : cell(l.CurrencyIsoCode),
      costSource(l),
      cell(l.Margin__c),
```

- [ ] **Step 20: Run the workbook and export suites to pass**

Run: `npm run test:unit -- force-app/main/default/lwc/rfpWorkbook force-app/main/default/lwc/rfpExport 2>&1 | grep -E "✕|^(Tests|Test Suites):"`

Expected: no `✕` line, `Test Suites: 2 passed, 2 total`, `Tests: 15 passed, 15 total` (7 workbook, 8 export; the export suite reads only the Bids sheet, which is unchanged).

- [ ] **Step 21: Manifest**

In `manifest/package.xml`, right before `        <name>LightningComponentBundle</name>`, add:

```xml
        <members>splitLaneOptions</members>
```

Run: `grep -c "<members>splitLaneOptions</members>" manifest/package.xml`

Expected: `1`.

- [ ] **Step 22: Format, lint, the whole Jest run, and rfpTool untouched**

Run: `npx prettier --write force-app/main/default/lwc/splitLaneOptions force-app/main/default/lwc/rfpPricing force-app/main/default/lwc/rfpLanePanel force-app/main/default/lwc/laneBenchmark force-app/main/default/lwc/rfpWorkbook force-app/main/default/lwc/rfpTool/__tests__/rfpTool.test.js manifest/package.xml`

Expected: every file listed; the code above is already in Prettier's style, so `git diff` shows no formatting-only change (lint-staged runs the same on commit).

Run: `npx eslint force-app/main/default/lwc/splitLaneOptions force-app/main/default/lwc/rfpPricing force-app/main/default/lwc/rfpLanePanel force-app/main/default/lwc/laneBenchmark force-app/main/default/lwc/rfpWorkbook force-app/main/default/lwc/rfpTool; echo "eslint exit $?"`

Expected: no findings, `eslint exit 0`.

Run (in the background if it passes 2 minutes): `npm run test:unit 2>&1 | grep -E "✕|^(Tests|Test Suites):"`

Expected: no `✕` line and no failed suite; `Test Suites: 42 passed, 42 total`, `Tests: 408 passed, 408 total`: one suite more and 23 tests more than Task 7's 41 / 385 (`splitLaneOptions` 14, `rfpPricing` +2, `rfpLanePanel` +4, `laneBenchmark` +2, `rfpWorkbook` +1). When a fix round changed a suite, carry your own printed numbers. The help `placement.test.js` suite still passes: the new bundle has no `c-help-hint`, and the panel and Lane Benchmark keep theirs.

Run: `git diff --stat -- force-app/main/default/lwc/rfpTool/rfpTool.js force-app/main/default/lwc/rfpTool/rfpTool.html; wc -l < force-app/main/default/lwc/rfpTool/rfpTool.js; git status --porcelain`

Expected: no diff-stat output for the two rfpTool files, `554`, and `git status --porcelain` shows ` M` on the twelve modified files this task names and `?? force-app/main/default/lwc/splitLaneOptions/`; `?? node_modules`, ` M .vscode/settings.json` and untracked macOS duplicates named `* 2.*` may also appear and are never staged.

- [ ] **Step 23: Deploy the five bundles**

Tasks 7 and 9 are in `sandbox` (`c/carrierLeadRules`, `SplitLaneController.splitOptions`) and Task 1's `Split` value too (Before you start). `__tests__/**` is in `.forceignore`. No Apex changes, so no tests run.

Run: `sf project deploy start -o sandbox -l NoTestRun --source-dir force-app/main/default/lwc/splitLaneOptions --source-dir force-app/main/default/lwc/rfpPricing --source-dir force-app/main/default/lwc/rfpLanePanel --source-dir force-app/main/default/lwc/laneBenchmark --source-dir force-app/main/default/lwc/rfpWorkbook --async --json | python3 -c "import json,sys; s=sys.stdin.read(); print(json.loads(s[s.index('{'):])['result']['id'])"`

Expected: a deploy id starting with `0Af`.

Run, repeating until the status is final: `sf project deploy report -o sandbox --job-id <id> -w 2 --json | python3 -c "import json,sys; s=sys.stdin.read(); r=json.loads(s[s.index('{'):])['result']; print(r['status'], r.get('numberComponentsDeployed'), '/', r.get('numberComponentsTotal'), (r.get('details') or {}).get('componentFailures'))"`

Expected: `Succeeded 5 / 5 None`. A `componentFailures` entry naming `SplitLaneController.splitOptions`, `c:carrierLeadRules` or `c:carrierLeads` means Task 9 or Task 7 is not in the org yet: deploy it, then repeat this step.

Run: `sf data query -o sandbox --use-tooling-api --json -q "SELECT DeveloperName FROM LightningComponentBundle WHERE DeveloperName IN ('splitLaneOptions','rfpLanePanel','laneBenchmark')" | python3 -c "import json,sys; s=sys.stdin.read(); print(sorted(r['DeveloperName'] for r in json.loads(s[s.index('{'):])['result']['records']))"`

Expected: `['laneBenchmark', 'rfpLanePanel', 'splitLaneOptions']`.

- [ ] **Step 24: Commit**

```bash
git add force-app/main/default/lwc/splitLaneOptions/splitLaneOptions.js force-app/main/default/lwc/splitLaneOptions/splitLaneOptions.html force-app/main/default/lwc/splitLaneOptions/splitLaneOptions.css force-app/main/default/lwc/splitLaneOptions/splitLaneOptions.js-meta.xml force-app/main/default/lwc/splitLaneOptions/__tests__/splitLaneOptions.test.js force-app/main/default/lwc/rfpPricing/rfpPricing.js force-app/main/default/lwc/rfpPricing/__tests__/rfpPricing.test.js force-app/main/default/lwc/rfpLanePanel/rfpLanePanel.js force-app/main/default/lwc/rfpLanePanel/rfpLanePanel.html force-app/main/default/lwc/rfpLanePanel/__tests__/rfpLanePanel.test.js force-app/main/default/lwc/laneBenchmark/laneBenchmark.js force-app/main/default/lwc/laneBenchmark/laneBenchmark.html force-app/main/default/lwc/laneBenchmark/__tests__/laneBenchmark.test.js force-app/main/default/lwc/rfpWorkbook/rfpWorkbook.js force-app/main/default/lwc/rfpWorkbook/__tests__/rfpWorkbook.test.js force-app/main/default/lwc/rfpTool/__tests__/rfpTool.test.js manifest/package.xml
git commit -m "Add split-lane options, the Split cost source and the Excel cost source column"
git show --stat HEAD | tail -19
```

Expected: the commit lists the seventeen files above; `rfpTool.js`, `rfpTool.html` and `.vscode/settings.json` are not in it, and the message has no trailer.

#### Contract notes (Task 10)

1. **Drafted before Task 7's text existed.** Every Task 7 name used here comes from contract L1-L4: `hasBothKeys`, `directMedian`, `lastRequestJson`, `lastCurrency`, `historyStats`, `historyRequestJson`, the `data-id="carrier-leads"` block and the `CarrierLeadController.findCarrierLeads` mocks. The code in this task was run in a scratch copy of the LWC tree, with a stand-in for Task 7 built from those contract lines: all 14 card tests passed, the 6 panel and Lane Benchmark tests failed then passed, the 3 pricing/workbook tests failed then passed, and ESLint and Prettier were clean. If Task 7 ships different names, change only the anchors and getters in Steps 9-15. When the plan was assembled, these names, the Carriers to ask block in `rfpLanePanel.html`, the three `findCarrierLeads` mock blocks and the Blacklisted badge classes were checked against Task 7's final text, and Steps 3, 9, 11 and 13 now quote them exactly.
2. **`c-split-lane-options.requestJson` is a getter/setter.** The contract lists a plain `@api requestJson`. When the value changes, the card closes again and forgets its kept answers, typed handoff costs and `attempt`. Without this, the lane panel keeps the card mounted across lanes and would show the previous lane's options, and a new search would skip D1's click. An answer that lands for an earlier request is dropped (the `generation` counter; the last test proves it). `attempt` goes back to 0 for a new request.
3. **`splitCost` is reset in `syncPricing`,** which `syncFromLane` calls. That covers "reset when a lane loads" and also a stored pricing change on the lane on screen (a save, an inline edit, a bulk action or Copy pricing), so a stored Split cost reads `Cost__c` instead of a stale filled amount. The fourth panel test proves it.
4. **`startCurrency` is normalized:** anything but `USD` opens the card in CAD, because the controller refuses other codes. Lane Benchmark already passes `splitStartCurrency`; the lane panel passes the lane's currency, which is CAD or USD in this org.
5. **A leg with no carriers** reads `Leg {position} {laneLabel} · no carrier found`. The contract's leg-line format has no text for an empty carrier list, and an estimate leg can find no load.
6. **`use-as-cost-off` is one note per card** and shows only when the answer has options and `laneCurrency` is set. The contract gives no placement, and a note under a message-only answer would be noise. `direct-median` is shown in each option ("next to each option", spec §4). `directMedian` receives `statsByCurrency || {}`, because the panel's `historyStats` is `null` until its history search answers.
7. **The `leg-blacklisted` badge** uses Task 7's `lead-blacklisted` classes, `slds-badge slds-theme_error slds-m-left_x-small`, so both cards show the same badge (R94).
8. **`cell()` in `rfpWorkbook` is not a formula-injection guard.** It only turns `null`/`undefined` into `""`. Formula neutralizing lives in `laneBenchmarkCsv` (CSV), and the xlsx carries typed string cells (the existing "typed string cell, no apostrophe" assertion). The new cell still goes through `cell()` and holds only picklist values. Two fixed positions (`sheet[1][5]`, `sheet[2][5]`) in the first workbook test become `2 + OUR_COLUMNS.indexOf("Sell")`, because Sell moves one column right.
9. **Lane Benchmark's two getters go right before `async connectedCallback()`** rather than "after `showCarrierLeads`", so the anchor exists whatever Task 7's getter looks like.
10. **The panel's valueless `allow-use-as-cost` attribute** compiles to `props: { allowUseAsCost: true }` (checked with `@lwc/template-compiler`). The panel wraps the card in `<div data-id="split">`, like the route's `data-id="route"` wrapper.
11. **Jest totals are exact from Task 7's counts** (41 suites / 385 tests after Task 7, including the Lane Benchmark failure test added when the plan was assembled; 42 / 408 after this task). The executor still carries its own printed numbers. The suites Task 7 does not touch have exact counts (`rfpPricing` 28, `rfpWorkbook` 7, `rfpExport` 8, `splitLaneOptions` 14).
12. **A currency switch while a call is in flight** keeps that call's answer when it lands for the same request. Only the latest call moves the spinner or shows an error, so switching back never asks twice for an answer already on its way.


---

### Task 11: Docs, roster and final deploy

**Files:**

- Modify: `docs/help/en/lb-stats.md`, `docs/help/fr/lb-stats.md` (new `## Carriers to ask` and `## Split-lane options` sections inserted immediately before `## Duplicates` / `## Doublons`, after the phase 7 trip miles section)
- Modify: `docs/help/en/rfp-pricing.md`, `docs/help/fr/rfp-pricing.md` (a **Split** bullet appended to the `## Cost source` / `## Source du coût` list; new `## Carriers to ask`, `## Split-lane options` and `## Use as cost` sections appended after the last section, `## Results` / `## Résultats`, which is where the panel shows them)
- Modify: `docs/help/en/rfp-inline.md`, `docs/help/fr/rfp-inline.md` (new `## The no rate tag` / `## L'étiquette no rate` section appended after `## The Miles column` / `## La colonne Miles`)
- Modify: `docs/help/en/rfp-filters-export.md`, `docs/help/fr/rfp-filters-export.md` (the `## Export to Excel` paragraph names the **Cost source** column)
- Modify: `force-app/main/default/staticresources/helpCenter/en/{lb-stats,rfp-pricing,rfp-inline,rfp-filters-export}.html` and the four `fr/` twins (rebuilt by `npm run help:build`; no front matter changes, so `index.json` does not change)
- Modify: `README.md` — the Apex roster at its four sites, found by content (the inventory row `| Apex tests`, the `sf apex run test -n …` line and the `sf project deploy start -x manifest/package.xml … -o sandbox -l RunSpecifiedTests -t …` line under `## Working with the org`, and the production `sf project deploy start -o vscodeOrg …` line under `## Retired: Pricing Department page (phase 4)`); six inventory rows (four Apex, one Data, one UI; see Step 4); the two Security rows (`permissionsets/Lane_Benchmark_User`, `permissionsets/RFP_Tool_User`); new section `## Carriers to ask and split-lane options (phase 8)` between the end of `## Trip miles (phase 7)` and `## Help center (phase 5)`; three phase 8 bullets at the end of `## Known issues worth fixing`
- Modify: `.github/workflows/ci.yml` (the `--tests` roster of the `Validate deploy and run tests` step)
- Modify: `docs/superpowers/specs/2026-09-07-pricing-department-roadmap.md` (row 8 after row 7 of the phase table)
- Modify: `docs/superpowers/specs/2026-09-14-phase-8-carriers-and-split-lanes-design.md` (append `## 11. Outcome — phase 8` after `## 10. Rulings`)

**Interfaces:**

- Consumes (documents and deploys, does not call): Tasks 1–10 — `Intercompany_Carrier__mdt` (`Carrier_Account_Id__c`, `Note__c`; records `Intercompany_Carrier.Tpml_TP_Org`, `Intercompany_Carrier.Lessard_Org`), `Handoff_Point__mdt` (`Place_Key__c`, `Active__c`; records `Handoff_Point.Laredo_TX_US`, `Handoff_Point.San_Diego_CA_US`, `Handoff_Point.Calexico_CA_US`), `RFP_Lane__c.Cost_Source__c` value `Split`; Apex `LaneKeyMatcher.condition`, `LaneLoadFilters.add`, `IntercompanyCarriers.ids`, `HandoffPoints.activeKeys`, `ExchangeRates.usd` / `fromCad` / `latestStartUsed`, `CarrierWarning.text`, `CarrierLeadResult` (`SAME_LANE`, `STATE_LANE`, `NONE`, `SOURCE_QUOTE`, `SOURCE_SPLIT_LEG`), `LaneQueries` (`COUNTRY_NAMES`, `GROUP_LIMIT`, `laneConditions`, `stateLaneConditions`, `quoteCountSoql`, `planSoql`, `legConditions`, `legLoadSoql`), `FreightPlanReader.read`, `CarrierLeadService.find`, `CarrierLeadController.findCarrierLeads(String requestJson, Integer attempt)`, `SplitLaneResult` (`HISTORY`, `ESTIMATE`), `SplitLaneService.options` / `median` / `amountIn` / `CarrierTally`, `SplitEstimates.estimate`, `SplitLaneController.splitOptions(String requestJson, String currencyCode, Integer attempt)`, `SplitTestData`; LWC `c/carrierLeadRules` (`hasBothKeys`, `noRate`, `directMedian`), `c-carrier-leads`, `c-split-lane-options` (event `useascost`), `rfpPricing` `SPLIT_SOURCE` and `costFor(…, { splitCost })`, `rfpWorkbook` `OUR_COLUMNS` `Cost source`; the fourteen new test classes.
- Produces: none in code. The Apex roster becomes 40 classes, in this order at every site (README inventory row, `sf apex run test` line, sandbox deploy line, production deploy line, and `ci.yml` `--tests`): `LaneSearchExclusionsTest PlaceNormalizerTest PricingTestDataFactoryTest PlaceBuilderBatchTest LaneSearchServiceTest MapboxGeocoderTest LaneBenchmarkControllerTest LaneBenchmarkPlaceServiceTest RfpTestDataFactoryTest BenchmarkRateServiceTest BidSearchQueryBuilderTest BidSearchServiceTest RfpControllerTest RfpSecurityTest RfpBidAccessTest MapboxTruckRouteTest RouteMapUrlTest TripMilesServiceTest RfpImportServiceTest RfpLaneControllerTest RfpHistoryServiceTest RfpProjectControllerTest RfpBidControllerTest RfpPricingMathTest RfpBulkServiceTest RfpBulkControllerTest SplitTestDataTest LaneSearchQueryBuilderTest LaneKeyMatcherTest IntercompanyCarriersTest HandoffPointsTest ExchangeRatesTest CarrierWarningTest LaneQueriesTest CarrierLeadServiceTest CarrierLeadControllerTest CarrierSplitSecurityTest SplitLaneServiceTest SplitEstimatesTest SplitLaneControllerTest`.


- [ ] **Step 1: Guide — Reading the statistics (Carriers to ask and Split-lane options)**

Leave every front-matter block untouched in this task (the `hint` lines sit near the 240-character limit and `index.json` must not change).

In `docs/help/en/lb-stats.md`, insert immediately before `## Duplicates` (one blank line on each side):

```markdown
## Carriers to ask

When a search finds no priced carrier rate in the currency you filtered on (in any currency when **Currency** is All), and both ends are places from the list, a **Carriers to ask** card appears under **Statistics**, above the map. It names carriers that know the lane, so you know whom to ask for a price. It never shows an amount.

The heading reads "No carrier rate on this lane in CAD. These carriers quoted or moved it before; amounts are not shown." (without "in CAD" when no currency is filtered). Each carrier shows:

- its name, as a link to the carrier's account when you can open that account;
- **3 moved · 5 quoted · last seen 2026-07-08**: the loads it moved (accepted quotes and legs of split shipments) and the loads it quoted;
- where it was found: **Quote**, **Split leg** or both;
- a **Blacklisted** badge when the carrier's account is blacklisted. Blacklisted carriers stay in the list so you recognise them; do not ask them for a price.

The card first looks at the same lane over the last 3 years, with your search's precision on each end (a radius end uses its city) and its mode, equipment and hazmat filters; the lookback, currency, quote status and source filters do not apply, and Market Test quotes never count. When that finds nobody, it shows the top 10 carriers on the state or province lane over the last year, ranked by loads moved: "No carrier on this exact lane. Top carriers on QC to ON over the last year." That second step is skipped when both ends were searched by province or state. When neither step finds anyone, the card says "No carrier found on this lane or on its state or province lane." Trans-Pro's own intercompany carrier accounts are never listed.

"The list may be incomplete." means the card stopped early to stay within Salesforce limits. If the card cannot load, click **Retry**.

## Split-lane options

At the bottom of the page, under the results, **Split-lane options** shows how the lane has been moved in two or more legs by different carriers. Nothing is looked up until you click the button, so the direct results always come first. The button is hidden when an end is not a place from the list.

- **History**: split shipments on the lane over the last 12 months (by the customer load's date), grouped by handoff point, most shipments first: "Via Laredo, TX · SFMN Park ITC Laredo yard · 34 shipments". Each leg line gives the leg's lane, its carriers with the number of legs each one moved, and the leg's median cost: "Leg 1 General Escobedo, NL → Laredo, TX · Q Transportes (18), Fletes Mex (9) · median 1,248 CAD". "Total per shipment, median 6,453 CAD (31 shipments)" is the median of each shipment's own leg total, over the shipments whose legs all have a cost. A leg without a cost shows carrier names only. Shipments with a cancelled leg, or with an intercompany carrier on a leg, are left out.
- **Estimate**: when the lane has no split history, the card tries the active handoff points on the admin list (today Laredo TX, San Diego CA and Calexico CA) that add at most about 10 % distance, up to 3, closest first: "Estimate via Laredo, TX · +6 % distance". Each leg shows its carriers and the median cost of the loads moved on that leg over the last year. Type the yard, transload or cross-dock cost in **Handoff cost**: **Estimate total** is leg 1's median + leg 2's median + that cost. A leg without a cost gives no total. With neither history nor a close handoff point, the card says "No split shipment on this lane in the last 12 months, and no handoff point is close enough for an estimate."

The **CAD** and **USD** buttons in the card header switch every amount on the card. The card starts in the currency you filtered on, or in CAD. Leg costs are stored in CAD; in USD each load's cost is converted at Salesforce's USD exchange rate for that load's date, and the note "Converted at the USD rate of 2026-08-11." gives the start date of the latest rate used ("No USD exchange rate is available." when Salesforce has none). **Direct median 5,800 CAD** repeats your search's median from **Statistics** in the card's currency, for comparison; it is hidden when the search has no median in that currency. A blacklisted leg carrier carries the **Blacklisted** badge. "The list may be incomplete." and **Retry** work as in **Carriers to ask**. On Lane Benchmark the card is for information; to use a split cost, price the lane in the RFP Tool.
```

In `docs/help/fr/lb-stats.md`, insert immediately before `## Doublons` (one blank line on each side):

```markdown
## Carriers to ask

Quand une recherche ne trouve aucun tarif de transporteur avec un prix dans la devise filtrée (dans n'importe quelle devise quand **Currency** est à All), et que les deux extrémités sont des lieux de la liste, l'encadré **Carriers to ask** apparaît sous **Statistics**, au-dessus de la carte. Il nomme des transporteurs qui connaissent la voie, pour que vous sachiez à qui demander un prix. Il n'affiche jamais de montant.

L'en-tête se lit « No carrier rate on this lane in CAD. These carriers quoted or moved it before; amounts are not shown. » (sans « in CAD » quand aucune devise n'est filtrée). Chaque transporteur affiche :

- son nom, avec un lien vers le compte du transporteur quand vous pouvez ouvrir ce compte;
- **3 moved · 5 quoted · last seen 2026-07-08** : les chargements qu'il a transportés (cotations acceptées et tronçons d'envois fractionnés) et ceux qu'il a cotés;
- où il a été trouvé : **Quote**, **Split leg** ou les deux;
- le badge **Blacklisted** quand le compte du transporteur est sur la liste noire. Ces transporteurs restent dans la liste pour que vous les reconnaissiez; ne leur demandez pas de prix.

L'encadré cherche d'abord sur la même voie, sur les 3 dernières années, avec la précision de votre recherche à chaque extrémité (une extrémité par rayon utilise sa ville) et ses filtres de mode, d'équipement et de matières dangereuses; la période, la devise, le statut des cotations et la source ne s'appliquent pas, et les cotations Market Test ne comptent jamais. Si personne n'est trouvé, il affiche les 10 principaux transporteurs de la voie de province à province (ou d'État à État) sur la dernière année, classés selon les chargements transportés : « No carrier on this exact lane. Top carriers on QC to ON over the last year. » Cette deuxième étape est sautée quand les deux extrémités ont été cherchées par province ou par État. Si aucune étape ne trouve de transporteur, l'encadré indique « No carrier found on this lane or on its state or province lane. » Les comptes de transporteurs intersociétés de Trans-Pro ne sont jamais listés.

« The list may be incomplete. » signifie que l'encadré s'est arrêté plus tôt pour rester dans les limites de Salesforce. Si l'encadré ne se charge pas, cliquez sur **Retry**.

## Split-lane options

Au bas de la page, sous les résultats, **Split-lane options** montre comment la voie a été transportée en deux tronçons ou plus par des transporteurs différents. Rien n'est cherché avant que vous cliquiez sur le bouton : les résultats directs passent toujours en premier. Le bouton est masqué quand une extrémité n'est pas un lieu de la liste.

- **History** : les envois fractionnés sur la voie des 12 derniers mois (selon la date du chargement client), regroupés par point de transfert, du plus grand nombre d'envois au plus petit : « Via Laredo, TX · SFMN Park ITC Laredo yard · 34 shipments ». Chaque ligne de tronçon donne la voie du tronçon, ses transporteurs avec le nombre de tronçons que chacun a transportés, et le coût médian du tronçon : « Leg 1 General Escobedo, NL → Laredo, TX · Q Transportes (18), Fletes Mex (9) · median 1,248 CAD ». « Total per shipment, median 6,453 CAD (31 shipments) » est la médiane du total des tronçons de chaque envoi, calculée sur les envois dont tous les tronçons ont un coût. Un tronçon sans coût n'affiche que les noms des transporteurs. Les envois dont un tronçon est annulé, ou confié à un transporteur intersociétés, sont exclus.
- **Estimate** : quand la voie n'a aucun historique d'envoi fractionné, l'encadré essaie les points de transfert actifs de la liste gérée par l'administrateur (aujourd'hui Laredo TX, San Diego CA et Calexico CA) qui n'ajoutent pas plus d'environ 10 % de distance, jusqu'à 3, le plus proche en premier : « Estimate via Laredo, TX · +6 % distance ». Chaque tronçon affiche ses transporteurs et le coût médian des chargements transportés sur ce tronçon pendant la dernière année. Saisissez les frais de cour, de transbordement ou de cross-dock dans **Handoff cost** : **Estimate total** est la médiane du tronçon 1 + la médiane du tronçon 2 + ces frais. Un tronçon sans coût ne donne pas de total. Sans historique ni point de transfert assez proche, l'encadré indique « No split shipment on this lane in the last 12 months, and no handoff point is close enough for an estimate. »

Les boutons **CAD** et **USD** de l'en-tête de l'encadré changent tous ses montants. L'encadré s'ouvre dans la devise filtrée, ou en CAD. Les coûts des tronçons sont enregistrés en CAD; en USD, le coût de chaque chargement est converti au taux de change USD de Salesforce à la date de ce chargement, et la note « Converted at the USD rate of 2026-08-11. » donne la date de début du taux le plus récent utilisé (« No USD exchange rate is available. » quand Salesforce n'en a aucun). **Direct median 5,800 CAD** reprend la médiane des **Statistics** de votre recherche dans la devise de l'encadré, pour comparer; elle est masquée quand la recherche n'a pas de médiane dans cette devise. Un transporteur de tronçon sur la liste noire porte le badge **Blacklisted**. « The list may be incomplete. » et **Retry** fonctionnent comme dans **Carriers to ask**. Dans Lane Benchmark, l'encadré sert seulement à vous informer; pour utiliser un coût fractionné, tarifez la voie dans l'onglet RFP Tool.
```


- [ ] **Step 2: Guide — Pricing a lane, Editing in the table, Filters and export, then rebuild**

Run from the repo root (it appends the Split bullet to both Cost source lists and names the Cost source column in both export paragraphs, asserting each anchor is found once):

```bash
python3 - <<'PY'
from pathlib import Path

EDITS = {
    "docs/help/en/rfp-pricing.md": [(
        "- **Manual**: type the cost yourself.\n",
        "- **Manual**: type the cost yourself.\n"
        "- **Split**: the total of a split-lane option, filled by **Use as cost** (see below). It is not a choice you can pick: it shows only while it is the lane's source, after **Use as cost** or on a lane saved with it, and choosing another source replaces it.\n",
    )],
    "docs/help/fr/rfp-pricing.md": [(
        "- **Manual** : saisissez le coût vous-même.\n",
        "- **Manual** : saisissez le coût vous-même.\n"
        "- **Split** : le total d'une option de voie fractionnée, rempli par **Use as cost** (voir plus bas). Ce n'est pas un choix offert : il n'apparaît que lorsqu'il est la source de la voie, après **Use as cost** ou sur une voie enregistrée ainsi, et choisir une autre source le remplace.\n",
    )],
    "docs/help/en/rfp-filters-export.md": [(
        "**Lanes** (every lane with its history, cost, margin, sell, annual sell and sell source), **Bids**, and **Summary** (counts, total annual sell per currency, average margin, by mode). Open it in Excel or Numbers.",
        "**Lanes** (every lane with its history, cost, currency, cost source, margin, sell, annual sell and sell source), **Bids**, and **Summary** (counts, total annual sell per currency, average margin, by mode). On **Lanes**, **Cost source** comes right after **Currency** and reads Bid, History median, Manual or Split; it is blank when the lane has no cost. Open it in Excel or Numbers.",
    )],
    "docs/help/fr/rfp-filters-export.md": [(
        "**Lanes** (chaque voie avec son historique, coût, marge, prix de vente, vente annuelle et source du prix), **Bids**, et **Summary** (compteurs, vente annuelle totale par devise, marge moyenne, par mode). Ouvrez-le dans Excel ou Numbers.",
        "**Lanes** (chaque voie avec son historique, coût, devise, source du coût, marge, prix de vente, vente annuelle et source du prix), **Bids**, et **Summary** (compteurs, vente annuelle totale par devise, marge moyenne, par mode). Dans **Lanes**, la colonne **Cost source** suit **Currency** et indique Bid, History median, Manual ou Split; elle reste vide quand la voie n'a pas de coût. Ouvrez-le dans Excel ou Numbers.",
    )],
}
for name, edits in EDITS.items():
    path = Path(name)
    text = path.read_text(encoding="utf-8")
    for old, new in edits:
        found = text.count(old)
        assert found == 1, "%s: expected 1 of %r, found %d" % (name, old[:60], found)
        text = text.replace(old, new)
    path.write_text(text, encoding="utf-8")
    print("updated", name)
PY
```

Expected: four `updated …` lines, in the order of the script.

Append to `docs/help/en/rfp-pricing.md`, after the last line (the `## Results` paragraph, `…so you can see which quotes made the median.`), with one blank line before:

```markdown
## Carriers to ask

When the lane's history results have no priced carrier rate in the lane's currency, the panel shows **Carriers to ask** under them: carriers that quoted or moved the lane before, by name only, never with an amount. The heading reads "No carrier rate on this lane in USD. These carriers quoted or moved it before; amounts are not shown." It needs both ends resolved to places, and it runs when you open the lane, never during **Load history** (the table shows a **no rate** tag instead; see **Editing in the table**). The two steps (the same lane over 3 years, then the top 10 carriers on the state or province lane), the **Blacklisted** badge, the account link and **Retry** work as on Lane Benchmark (see **Reading the statistics**).

## Split-lane options

Under the history results (below **Carriers to ask** when it shows), click **Split-lane options** to see how the lane has been moved in legs, or estimates through a handoff point, as described in **Reading the statistics**. The card starts in the lane's currency, and **Direct median** is the median of the panel's history results in the card's currency.

## Use as cost

While the card shows the lane's currency, each option with a total has **Use as cost**. A history option uses its median total per shipment; an estimate uses its **Estimate total**, so type its **Handoff cost** first (0 is allowed). **Use as cost** puts that total in **Cost**, sets **Cost source** to **Split** and clears any selected bid; the margin and the sell follow as for any other cost. Nothing is saved until you click **Save price**. When you switch the card to the other currency, the button gives way to "Switch to USD to use a split cost." (on a USD lane; "Switch to CAD…" on a CAD lane). The identical lanes bar copies a Split cost like any other cost.
```

Append to `docs/help/fr/rfp-pricing.md`, after the last line (the `## Résultats` paragraph, `…pour voir quelles cotations ont fait la médiane.`), with one blank line before:

```markdown
## Carriers to ask

Quand les résultats d'historique de la voie n'ont aucun tarif de transporteur avec un prix dans la devise de la voie, le panneau affiche **Carriers to ask** sous ces résultats : les transporteurs qui ont déjà coté ou transporté la voie, par leur nom seulement, jamais avec un montant. L'en-tête se lit « No carrier rate on this lane in USD. These carriers quoted or moved it before; amounts are not shown. » Les deux extrémités doivent être associées à des lieux, et l'encadré se charge à l'ouverture de la voie, jamais pendant **Load history** (le tableau affiche plutôt l'étiquette **no rate**; voir **Modifier dans le tableau**). Les deux étapes (la même voie sur 3 ans, puis les 10 principaux transporteurs de la voie de province à province ou d'État à État), le badge **Blacklisted**, le lien vers le compte et **Retry** fonctionnent comme dans Lane Benchmark (voir **Lire les statistiques**).

## Split-lane options

Sous les résultats d'historique (après **Carriers to ask** quand il est affiché), cliquez sur **Split-lane options** pour voir comment la voie a été transportée en tronçons, ou des estimations par un point de transfert, comme l'explique **Lire les statistiques**. L'encadré s'ouvre dans la devise de la voie, et **Direct median** est la médiane des résultats d'historique du panneau dans la devise de l'encadré.

## Use as cost

Tant que l'encadré affiche la devise de la voie, chaque option qui a un total offre **Use as cost**. Une option d'historique utilise sa médiane du total par envoi; une estimation utilise son **Estimate total** : saisissez donc d'abord son **Handoff cost** (0 est accepté). **Use as cost** inscrit ce total dans **Cost**, met **Cost source** à **Split** et retire la soumission choisie; la marge et le prix de vente suivent comme pour tout autre coût. Rien n'est enregistré avant que vous cliquiez sur **Save price**. Quand vous passez l'encadré à l'autre devise, le bouton est remplacé par « Switch to USD to use a split cost. » (sur une voie en USD; « Switch to CAD… » sur une voie en CAD). La barre des voies identiques copie un coût Split comme n'importe quel autre coût.
```

Append to `docs/help/en/rfp-inline.md`, after the last line (the `## The Miles column` paragraph ending `…history run or page reload.`), with one blank line before:

```markdown
## The no rate tag

After **Load history**, the **History** cell shows a **no rate** tag when the lane has no priced carrier rate in its currency: the cell reads **No match**, or quotes matched but none had a price in the lane's currency (no median). Open the lane to see **Carriers to ask** and **Split-lane options** in the panel. Load history itself never looks for carriers.
```

Append to `docs/help/fr/rfp-inline.md`, after the last line (the `## La colonne Miles` paragraph ending `…chargement d'historique ou rechargement de la page.`), with one blank line before:

```markdown
## L'étiquette no rate

Après **Load history**, la cellule **History** affiche l'étiquette **no rate** quand la voie n'a aucun tarif de transporteur avec un prix dans sa devise : la cellule indique **No match**, ou des cotations correspondent mais aucune n'a de prix dans la devise de la voie (pas de médiane). Ouvrez la voie pour voir **Carriers to ask** et **Split-lane options** dans le panneau. **Load history** ne cherche jamais de transporteurs.
```

Run: `npm run help:build && npm run help:check`
Expected: `built 15 sections into force-app/main/default/staticresources/helpCenter`, then `helpCenter is up to date`.

Run: `git status --short force-app/main/default/staticresources/helpCenter docs/help`
Expected exactly these 16 lines, all ` M`: `docs/help/en/lb-stats.md`, `docs/help/en/rfp-filters-export.md`, `docs/help/en/rfp-inline.md`, `docs/help/en/rfp-pricing.md`, the four `docs/help/fr/` twins, `force-app/main/default/staticresources/helpCenter/en/lb-stats.html`, `.../en/rfp-filters-export.html`, `.../en/rfp-inline.html`, `.../en/rfp-pricing.html` and the four `.../fr/` twins. `index.json` is not listed.

Run: `cd force-app/main/default/staticresources/helpCenter && grep -c "<h3>Carriers to ask</h3>" en/lb-stats.html en/rfp-pricing.html fr/lb-stats.html fr/rfp-pricing.html; grep -c "<h3>Split-lane options</h3>" en/lb-stats.html fr/rfp-pricing.html; grep -c "<h3>Use as cost</h3>" en/rfp-pricing.html fr/rfp-pricing.html; grep -c "no rate" en/rfp-inline.html fr/rfp-inline.html; grep -c "Cost source" en/rfp-filters-export.html fr/rfp-filters-export.html; grep -c "<strong>Split</strong>" en/rfp-pricing.html fr/rfp-pricing.html; cd -`
Expected, as `file:count` lines (checked in a dry run on a copy of the branch): `1` for each file of the three heading greps (the sections render as `h3`); `2` for `en/rfp-inline.html` and `fr/rfp-inline.html` (the tag's heading and its paragraph); `1` for each `rfp-filters-export.html`; `2` for `en/rfp-pricing.html` and `fr/rfp-pricing.html` (the Split bullet and the Use as cost paragraph); the last line prints the repo root.

- [ ] **Step 3: Apex roster (README and CI) to 40 classes**

The fourteen new classes go after `RfpBulkControllerTest`, in this order, at all five sites. The anchors were counted on the branch before this task: the inventory row and the `sf apex run test` line hold their pair once each; the two deploy commands (`-o sandbox … -t …` under `## Working with the org` and `-o vscodeOrg …` under `## Retired: Pricing Department page (phase 4)`) hold `RfpBulkServiceTest RfpBulkControllerTest` twice in `README.md`, and `ci.yml` once. Run from the repo root:

```bash
python3 - <<'PY'
from pathlib import Path

NEW = ["SplitTestDataTest", "LaneSearchQueryBuilderTest", "LaneKeyMatcherTest",
       "IntercompanyCarriersTest", "HandoffPointsTest", "ExchangeRatesTest",
       "CarrierWarningTest", "LaneQueriesTest", "CarrierLeadServiceTest",
       "CarrierLeadControllerTest", "CarrierSplitSecurityTest", "SplitLaneServiceTest",
       "SplitEstimatesTest", "SplitLaneControllerTest"]
EDITS = {
    "README.md": [
        # the inventory table row "| Apex tests"
        ("`RfpBulkServiceTest`, `RfpBulkControllerTest` |",
         "`RfpBulkServiceTest`, `RfpBulkControllerTest`, " + ", ".join("`%s`" % n for n in NEW) + " |", 1),
        # sf apex run test
        ("-n RfpBulkServiceTest -n RfpBulkControllerTest -o sandbox",
         "-n RfpBulkServiceTest -n RfpBulkControllerTest " + " ".join("-n %s" % n for n in NEW) + " -o sandbox", 1),
        # the sandbox deploy command and the production deploy command
        ("RfpBulkServiceTest RfpBulkControllerTest",
         "RfpBulkServiceTest RfpBulkControllerTest " + " ".join(NEW), 2),
    ],
    ".github/workflows/ci.yml": [
        # --tests of "Validate deploy and run tests"
        ("RfpBulkServiceTest RfpBulkControllerTest",
         "RfpBulkServiceTest RfpBulkControllerTest " + " ".join(NEW), 1),
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

Expected: `updated README.md`, `updated .github/workflows/ci.yml`. (The `-n` line does not contain `RfpBulkServiceTest RfpBulkControllerTest` with a single space between the two names, so the third edit touches only the two deploy lines.)

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
         "RfpBulkControllerTest SplitTestDataTest LaneSearchQueryBuilderTest LaneKeyMatcherTest "
         "IntercompanyCarriersTest HandoffPointsTest ExchangeRatesTest CarrierWarningTest LaneQueriesTest "
         "CarrierLeadServiceTest CarrierLeadControllerTest CarrierSplitSecurityTest SplitLaneServiceTest "
         "SplitEstimatesTest SplitLaneControllerTest").split()
assert len(ORDER) == 40 and len(set(ORDER)) == 40
for name in ["README.md", ".github/workflows/ci.yml"]:
    for number, line in enumerate(open(name, encoding="utf-8"), 1):
        if "LaneSearchExclusionsTest" in line and "RfpBulkControllerTest" in line:
            names = re.findall(r"\b[A-Z]\w*Test\b", line)
            print(name, number, len(names), names == ORDER)
PY
```

Expected exactly five lines: `README.md 28 40 True`, `README.md 107 40 True`, `README.md 114 40 True`, `README.md 393 40 True`, `.github/workflows/ci.yml 59 40 True` (line numbers before Step 4 inserts its rows; the phase 8 plan's Global Constraints name the roster sites by content, not by line).

- [ ] **Step 4: README inventory rows, Security rows, the phase 8 section and Known issues**

Run from the repo root (it inserts six inventory rows (four Apex, one Data, one UI), extends the two Security rows, appends three Known issues bullets, and asserts each anchor is found once; Prettier realigns the table columns in Step 6):

```bash
python3 - <<'PY'
from pathlib import Path

path = Path("README.md")
lines = path.read_text(encoding="utf-8").split("\n")

APEX_ROWS = [
    "| Apex | `classes/LaneKeyMatcher`, `LaneLoadFilters`, `LaneQueries` | Phase 8: one lane end's lane-key condition for a precision and a load field path (moved out of `LaneSearchQueryBuilder`; the search SOQL is unchanged); the mode, equipment and hazmat conditions (moved out of `LaneSearchFilters`); the grouped quote counts, freight-plan and leg-load SOQL of the two new cards |",
    "| Apex | `classes/IntercompanyCarriers`, `HandoffPoints`, `ExchangeRates`, `CarrierWarning` | Phase 8: the intercompany carrier account Ids and the active handoff place keys from custom metadata; USD dated exchange rates applied per load date; the red results warning text from `Account.Black_List__c` and the Transportation Profile's `Outstanding_Claim__c` |",
    "| Apex | `classes/CarrierLeadController`, `CarrierLeadService`, `CarrierLeadResult`, `FreightPlanReader` | Phase 8: Carriers to ask, names only (same lane over 3 years, then the top 10 on the state or province lane over a year), read in system mode with one user-mode `Account` read for the links; `FreightPlanReader` reads freight plans with their legs in system mode |",
    "| Apex | `classes/SplitLaneController`, `SplitLaneService`, `SplitEstimates`, `SplitLaneResult`, `SplitTestData` | Phase 8: Split-lane options: freight-plan history over 12 months grouped by handoff, estimates through handoff points, amounts in CAD or USD; `SplitTestData` (`@IsTest`) builds carriers, leg loads and freight plans for the tests |",
]
DATA_ROW = "| Data | `objects/Intercompany_Carrier__mdt/*`, `objects/Handoff_Point__mdt/*`, `customMetadata/Intercompany_Carrier.*`, `customMetadata/Handoff_Point.*`, `objects/RFP_Lane__c/fields/Cost_Source__c` (value `Split`) | Phase 8: the intercompany carrier accounts hidden from both cards, the handoff points tried for estimates, and the Split cost source. See \"Carriers to ask and split-lane options (phase 8)\" below |"
UI_ROW = "| UI | `lwc/carrierLeadRules`, `carrierLeads`, `splitLaneOptions` | Phase 8: the no-rate, place-key and direct median rules; the Carriers to ask card; the Split-lane options card (CAD or USD, handoff cost, Use as cost). `laneBenchmark`, `rfpLanePanel`, `rfpLaneTable` (no rate tag), `rfpPricing` (Split) and `rfpWorkbook` (Cost source column) use them |"
ISSUES = [
    "- Carriers to ask and split-lane options (phase 8): USD amounts on the split card are only as current as Salesforce's weekly USD dated exchange rates; whether production keeps them current is to be confirmed.",
    "- Carriers to ask: stage 2 leaves out loads whose first or last stop account has a blank `ShippingCountry` (about 4 % of recent loads in PostProduc).",
    "- Split-lane options: a handoff group is named from the leg's lane and its last stop account, so one yard recorded under two account names shows as two groups.",
]


def index_of(predicate, label):
    hits = [i for i, line in enumerate(lines) if predicate(line)]
    assert len(hits) == 1, "%s: expected one anchor, found %d" % (label, len(hits))
    return hits[0]


i = index_of(lambda l: l.startswith("| Apex") and "`classes/TripMilesService`, `TripRouteView`" in l, "TripMilesService row")
lines[i + 1:i + 1] = APEX_ROWS
i = index_of(lambda l: l.startswith("| Data") and "`objects/Truck_Route__c/*`" in l, "Truck_Route data row")
lines[i + 1:i + 1] = [DATA_ROW]
i = index_of(lambda l: l.startswith("| UI") and "`lwc/distanceUnit`" in l, "distance unit UI row")
lines[i + 1:i + 1] = [UI_ROW]

i = index_of(lambda l: "`permissionsets/Lane_Benchmark_User`" in l and "Assign this to the pricing team" in l, "Lane_Benchmark_User row")
assert lines[i].count("Assign this to the pricing team") == 1
lines[i] = lines[i].replace(
    "Assign this to the pricing team",
    "Phase 8 adds class access to `CarrierLeadController` and `SplitLaneController`. Assign this to the pricing team",
)
i = index_of(lambda l: "`permissionsets/RFP_Tool_User`" in l and "class access to `TripRouteView`" in l, "RFP_Tool_User row")
assert lines[i].count("class access to `TripRouteView`") == 1
lines[i] = lines[i].replace(
    "class access to `TripRouteView`",
    "class access to `TripRouteView`; phase 8 adds class access to `CarrierLeadController` and `SplitLaneController`",
)

i = index_of(lambda l: l.startswith("- Trip miles: after a Province / state"), "last Trip miles known issue")
lines[i + 1:i + 1] = ISSUES

path.write_text("\n".join(lines), encoding="utf-8")
print("inventory updated")
PY
```

Expected: `inventory updated`.

Then insert this section immediately before `## Help center (phase 5)` (after the last paragraph of `## Trip miles (phase 7)`, which ends `Production is not deployed (owner decision, D8).`; one blank line on each side):

```markdown
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
incomplete."). Load history never runs it; the lane table shows a **no rate** tag read from
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

**Queries.** Carriers to ask makes about 5 queries for stage 1 (places, two quote counts,
plans with legs, the `Account` read) and 3 more for stage 2; split history makes the places
read and one plan query, plus one rate query in USD; estimates add the handoff places and at
most 6 leg reads. These are the spec's estimates; the browser check's debug log counts are
in the spec Outcome.

**Access.** `Lane_Benchmark_User` and `RFP_Tool_User` give class access to
`CarrierLeadController` and `SplitLaneController`; no object or field permission changed,
and the new picklist value needs none. Production is not deployed (owner decision, R108).
```

Run: `grep -c "^## Carriers to ask and split-lane options (phase 8)$" README.md && grep -c "CarrierLeadController" README.md && grep -n "^## " README.md | sed -n '/Trip miles (phase 7)/,/Help center (phase 5)/p'`
Expected: `1`; a number of at least `4`; then three heading lines in this order: `## Trip miles (phase 7)`, `## Carriers to ask and split-lane options (phase 8)`, `## Help center (phase 5)`.

- [ ] **Step 5: Roadmap row 8**

Run from the repo root:

```bash
python3 - <<'PY'
from datetime import date
from pathlib import Path

path = Path("docs/superpowers/specs/2026-09-07-pricing-department-roadmap.md")
lines = path.read_text(encoding="utf-8").split("\n")
hits = [i for i, l in enumerate(lines) if l.startswith("| 7 ") and "Trip miles" in l]
assert len(hits) == 1, "row 7 not found once: %d" % len(hits)
assert not any(l.startswith("| 8 ") for l in lines), "row 8 already exists"
lines.insert(hits[0] + 1, "| 8 | Carriers to ask and split lanes | Carriers to ask (carrier names only, never amounts, when a lane has no carrier rate: the same lane over 3 years, then the top 10 on the state or province lane) on Lane Benchmark and the RFP lane panel, with a no rate tag in the lane table; Split-lane options on click (freight-plan history by handoff point, estimates through Laredo, San Diego or Calexico, CAD or USD at dated rates) with Use as cost and the Split cost source; intercompany carriers and handoff points in custom metadata; the results warning's blacklist text from the carrier account | Done " + date.today().isoformat() + " (PostProduc; production untouched) |")
path.write_text("\n".join(lines), encoding="utf-8")
print("row 8 added")
PY
```

Expected: `row 8 added`. The row carries today's date; Step 8 corrects it if the final deploy lands on a later day.

- [ ] **Step 6: Format and full local gate**

Run: `npx prettier --write README.md .github/workflows/ci.yml docs/superpowers/specs/2026-09-07-pricing-department-roadmap.md docs/help/en/lb-stats.md docs/help/fr/lb-stats.md docs/help/en/rfp-pricing.md docs/help/fr/rfp-pricing.md docs/help/en/rfp-inline.md docs/help/fr/rfp-inline.md docs/help/en/rfp-filters-export.md docs/help/fr/rfp-filters-export.md && npm run help:build && npm run help:check`

Expected: Prettier lists the eleven files (it realigns the README inventory table and the roadmap table; `ci.yml` and the eight guide files report `(unchanged)`), then `built 15 sections into force-app/main/default/staticresources/helpCenter`, then `helpCenter is up to date`.

Run: `npm run lint && npm run prettier:verify && npm run help:check && npm run test:unit 2>&1 | grep -E "^(Tests|Test Suites):"; /private/tmp/pmd_install/pmd-bin-7.15.0/bin/pmd check --dir force-app --rulesets config/pmd-ruleset.xml --minimum-priority 3 --format text --fail-on-violation; echo "pmd exit $?"`

Expected: ESLint silent (it covers every `lwc/**/*.js`, including `carrierLeadRules`, `carrierLeads`, `splitLaneOptions`, `laneBenchmark`, `rfpLanePanel`, `rfpLaneTable`, `rfpPricing` and `rfpWorkbook`); Prettier `All matched files use Prettier code style!` (never format or stage `.vscode/settings.json`, any `* 2.*` file, `.ai-handover` or the `node_modules` symlink); `helpCenter is up to date`; Jest `Test Suites: 42 passed, 42 total` (39 at the end of phase 7 plus the `carrierLeadRules`, `carrierLeads` and `splitLaneOptions` suites) and `Tests: 408 passed, 408 total` (363 + 22 from Task 7 + 23 from Task 10; when a fix round changed a suite, carry your own printed number) — record it for the Outcome; `pmd exit 0`.

Run the Apex method count over the 40-class roster; it also compares the 24 classes this phase does not extend with their count at `b847aec` (phase 7 merged into this branch, 219 methods in 26 classes):

```bash
python3 - <<'PY'
import re, subprocess
OLD = ("LaneSearchExclusionsTest PlaceNormalizerTest PricingTestDataFactoryTest PlaceBuilderBatchTest "
       "LaneSearchServiceTest MapboxGeocoderTest LaneBenchmarkControllerTest LaneBenchmarkPlaceServiceTest "
       "RfpTestDataFactoryTest BenchmarkRateServiceTest BidSearchQueryBuilderTest BidSearchServiceTest "
       "RfpControllerTest RfpSecurityTest RfpBidAccessTest MapboxTruckRouteTest RouteMapUrlTest "
       "TripMilesServiceTest RfpImportServiceTest RfpLaneControllerTest RfpHistoryServiceTest "
       "RfpProjectControllerTest RfpBidControllerTest RfpPricingMathTest RfpBulkServiceTest "
       "RfpBulkControllerTest").split()
NEW = ("SplitTestDataTest LaneSearchQueryBuilderTest LaneKeyMatcherTest IntercompanyCarriersTest "
       "HandoffPointsTest ExchangeRatesTest CarrierWarningTest LaneQueriesTest CarrierLeadServiceTest "
       "CarrierLeadControllerTest CarrierSplitSecurityTest SplitLaneServiceTest SplitEstimatesTest "
       "SplitLaneControllerTest").split()
EXTENDED = {"LaneSearchServiceTest", "BidSearchServiceTest"}
METHOD = re.compile(r"@IsTest(?:\([^)]*\))?\s+(?:@\w+(?:\([^)]*\))?\s+)*(?:(?:private|public|global)\s+)?static\s+(?:testMethod\s+)?void\s", re.I)
def count(text):
    return len(METHOD.findall(text))
base_total = total = 0
for name in OLD:
    path = "force-app/main/default/classes/%s.cls" % name
    now = count(open(path, encoding="utf-8").read())
    base = count(subprocess.run(["git", "show", "b847aec:" + path], capture_output=True, text=True, check=True).stdout)
    base_total += base
    total += now
    flag = "extended" if name in EXTENDED else ("unchanged" if now == base else "CHANGED")
    print(name, base, now, flag)
for name in NEW:
    now = count(open("force-app/main/default/classes/%s.cls" % name, encoding="utf-8").read())
    total += now
    print(name, "new", now, "ok" if now > 0 else "EMPTY")
print("classes", len(OLD) + len(NEW), "base", base_total, "total", total)
PY
```

Expected: 40 class lines, then `classes 40 base 219 total T`. No line says `CHANGED` or `EMPTY`; `LaneSearchServiceTest` and `BidSearchServiceTest` print `extended` with a count above their base. T is the test total the second deploy in Step 7 must report; record T and each new class's count for the Outcome. A `CHANGED` line means a task edited a test class this phase does not own: find the commit (`git log --oneline 44081a7.. -- force-app/main/default/classes/<name>.cls`) and say why in the Outcome.

Run the phase's budget and scope checks:

```bash
git diff --stat b847aec -- force-app/main/default/classes/RfpLaneController.cls force-app/main/default/classes/RfpSecurityTest.cls force-app/main/default/classes/RfpBulkService.cls force-app/main/default/classes/LaneBenchmarkController.cls force-app/main/default/classes/RfpHistoryService.cls force-app/main/default/classes/LaneSearchRequest.cls force-app/main/default/classes/LaneSearchResult.cls force-app/main/default/lwc/rfpTool/rfpTool.js force-app/main/default/lwc/rfpTool/rfpTool.html; echo "frozen diff exit $?"; wc -l < force-app/main/default/lwc/rfpTool/rfpTool.js
```

Expected: no diff line, then `frozen diff exit 0`, then `554`.

```bash
python3 - <<'PY'
import re
xml = open("manifest/package.xml", encoding="utf-8").read()
members = {}
for block in re.findall(r"<types>(.*?)</types>", xml, re.S):
    kind = re.search(r"<name>(.*?)</name>", block).group(1)
    members[kind] = set(re.findall(r"<members>(.*?)</members>", block))
WANT = {
    "ApexClass": "LaneKeyMatcher LaneLoadFilters IntercompanyCarriers HandoffPoints ExchangeRates CarrierWarning "
                 "CarrierLeadResult LaneQueries FreightPlanReader CarrierLeadService CarrierLeadController "
                 "SplitLaneResult SplitLaneService SplitEstimates SplitLaneController SplitTestData "
                 "SplitTestDataTest LaneSearchQueryBuilderTest LaneKeyMatcherTest IntercompanyCarriersTest "
                 "HandoffPointsTest ExchangeRatesTest CarrierWarningTest LaneQueriesTest CarrierLeadServiceTest "
                 "CarrierLeadControllerTest CarrierSplitSecurityTest SplitLaneServiceTest SplitEstimatesTest "
                 "SplitLaneControllerTest".split(),
    "CustomObject": ["Intercompany_Carrier__mdt", "Handoff_Point__mdt"],
    "CustomField": ["Intercompany_Carrier__mdt.Carrier_Account_Id__c", "Intercompany_Carrier__mdt.Note__c",
                    "Handoff_Point__mdt.Place_Key__c", "Handoff_Point__mdt.Active__c", "RFP_Lane__c.Cost_Source__c"],
    "CustomMetadata": ["Intercompany_Carrier.Tpml_TP_Org", "Intercompany_Carrier.Lessard_Org",
                       "Handoff_Point.Laredo_TX_US", "Handoff_Point.San_Diego_CA_US", "Handoff_Point.Calexico_CA_US"],
    "LightningComponentBundle": ["carrierLeadRules", "carrierLeads", "splitLaneOptions"],
    "PermissionSet": ["Lane_Benchmark_User", "RFP_Tool_User"],
}
missing = [(k, m) for k, names in WANT.items() for m in names if m not in members.get(k, set())]
print("missing", missing)
print("members", sum(len(v) for v in members.values()))
PY
```

Expected: `missing []` and `members 324` (280 at `44081a7`, plus 30 Apex classes, 2 custom metadata types, 4 fields, 5 records and 3 bundles). A different member count is a finding to explain before the deploy.

```bash
NEW_CLASSES="LaneKeyMatcher LaneLoadFilters IntercompanyCarriers HandoffPoints ExchangeRates CarrierWarning CarrierLeadResult LaneQueries FreightPlanReader CarrierLeadService CarrierLeadController SplitLaneResult SplitLaneService SplitEstimates SplitLaneController"
cd force-app/main/default/classes
grep -nE "MapboxHttp|MapboxTruckRoute|MapboxGeocoder|new Http\(|HttpRequest|TPRO_KPI__c|getChars" $(for c in $NEW_CLASSES; do printf '%s.cls ' "$c"; done); echo "callout grep exit $?"
grep -nE "Total__c|Cost_|Decimal" CarrierLeadResult.cls CarrierLeadService.cls CarrierLeadController.cls; echo "amount grep exit $?"
grep -n "System.debug" $(for c in $NEW_CLASSES; do printf '%s.cls ' "$c"; done)
cd - > /dev/null
git grep -n -e 0011N00001JcHnvQAF -e 0011N00001JbQ7EQAV -- force-app
git grep -nE "pk\.[A-Za-z0-9_-]{20,}" -- . ; echo "token grep exit $?"
```

Expected: no line, then `callout grep exit 1` (no Mapbox class, no HTTP, no `TPRO_KPI__c`, no `getChars` in the phase's classes; the SplitEstimates comment that says distances never come from Mapbox does not match the class names); no line, then `amount grep exit 1` (Carriers to ask names no amount field; `LaneQueries.planSoql(…, false)` builds its SOQL without one, and `LaneQueriesTest` asserts it); the `System.debug` grep prints only `IntercompanyCarriers.cls` lines at `LoggingLevel.WARN`; the account-Id grep prints exactly two lines, one in `customMetadata/Intercompany_Carrier.Tpml_TP_Org.md-meta.xml` and one in `customMetadata/Intercompany_Carrier.Lessard_Org.md-meta.xml`; no token line, then `token grep exit 1`.

Run: `git status --short`
Expected: ` M` on exactly the eight guide files, the eight `helpCenter` HTML files, `README.md`, `.github/workflows/ci.yml` and the roadmap; plus the untracked `node_modules` symlink (and, if present, `.vscode/settings.json`, `* 2.*` files or `.ai-handover`), which stay out of every commit.

- [ ] **Step 7: Final deploy pair**

A deploy runs asynchronously and is polled in calls of at most two minutes (an agent idle for three minutes is stopped). Shell variables do not survive between tool calls: paste each job id literally where the command says `<job id>`.

First, the full manifest with no tests, so both permission sets (class access to `CarrierLeadController` and `SplitLaneController`), both custom metadata types and their five records, the `Split` picklist value and every class and bundle are in place before the tests run (README, "Working with the org": user-mode Apex needs its permission set in the org before a `RunSpecifiedTests` deploy).

Run: `sf project deploy start -o sandbox --manifest manifest/package.xml -l NoTestRun --async --json | python3 -c "import json,sys; s=sys.stdin.read(); r=json.loads(s[s.index('{'):])['result']; print(r['id'], r.get('status'))"`

Expected: a job id starting `0Af` and `Queued` or `InProgress`.

Poll (repeat the same command while the status is `Queued`, `Pending`, `InProgress` or `None`; a wait that ends before the deploy prints a timeout message, which also means run it again):

`sf project deploy report -o sandbox --job-id <job id> -w 2 --json | python3 -c "import json,sys; s=sys.stdin.read(); j=json.loads(s[s.index('{'):]); r=j.get('result') or {}; d=r.get('details') or {}; cf=d.get('componentFailures') or []; cf=cf if isinstance(cf,list) else [cf]; tf=(d.get('runTestResult') or {}).get('failures') or []; tf=tf if isinstance(tf,list) else [tf]; print(r.get('id'), r.get('status'), 'components', r.get('numberComponentsDeployed'), '/', r.get('numberComponentsTotal'), 'errors', r.get('numberComponentErrors'), 'tests', r.get('numberTestsCompleted'), '/', r.get('numberTestsTotal'), 'failures', r.get('numberTestErrors'), j.get('message') or ''); [print('COMPONENT', f.get('fullName'), '->', f.get('problem')) for f in cf]; [print('TEST', f.get('name'), f.get('methodName'), '->', (f.get('message') or '')[:200]) for f in tf]"`

Expected: `<job id> Succeeded components C / C errors 0 tests 0 / 0 failures 0`, with C = 325: phase 7's final NoTestRun deploy `0AfbZ00000CqYrWSAV` counted 281 for the manifest's 280 members, and Step 6 counted 324 members. Record the id and C; a different C is explained in the Outcome.

Second, the same manifest with the 40 test classes:

Run: `sf project deploy start -o sandbox -x manifest/package.xml --post-destructive-changes manifest/destructiveChangesPost.xml -l RunSpecifiedTests -t LaneSearchExclusionsTest PlaceNormalizerTest PricingTestDataFactoryTest PlaceBuilderBatchTest LaneSearchServiceTest MapboxGeocoderTest LaneBenchmarkControllerTest LaneBenchmarkPlaceServiceTest RfpTestDataFactoryTest BenchmarkRateServiceTest BidSearchQueryBuilderTest BidSearchServiceTest RfpControllerTest RfpSecurityTest RfpBidAccessTest MapboxTruckRouteTest RouteMapUrlTest TripMilesServiceTest RfpImportServiceTest RfpLaneControllerTest RfpHistoryServiceTest RfpProjectControllerTest RfpBidControllerTest RfpPricingMathTest RfpBulkServiceTest RfpBulkControllerTest SplitTestDataTest LaneSearchQueryBuilderTest LaneKeyMatcherTest IntercompanyCarriersTest HandoffPointsTest ExchangeRatesTest CarrierWarningTest LaneQueriesTest CarrierLeadServiceTest CarrierLeadControllerTest CarrierSplitSecurityTest SplitLaneServiceTest SplitEstimatesTest SplitLaneControllerTest --async --json | python3 -c "import json,sys; s=sys.stdin.read(); r=json.loads(s[s.index('{'):])['result']; print(r['id'], r.get('status'))"`

Expected: a new job id and `Queued` or `InProgress`. Poll it with the report command above until it finishes.

Expected: `<job id> Succeeded components C / C errors 0 tests T / T failures 0` (T from Step 6), and no `COMPONENT` or `TEST` line. `manifest/destructiveChangesPost.xml` is still the empty manifest, so nothing is deleted. A `TEST` line is a failure to fix in the task that owns that class, then both deploys run again. Record the id and the test total.

Verify the settings, the picklist, the class access and the exchange rates in the org (read-only; paste each command as is):

`sf data query -o sandbox -q "SELECT DeveloperName, Carrier_Account_Id__c, Note__c FROM Intercompany_Carrier__mdt ORDER BY DeveloperName" --json | python3 -c "import json,sys; s=sys.stdin.read(); [print(r['DeveloperName'], r['Carrier_Account_Id__c'], r['Note__c']) for r in json.loads(s[s.index('{'):])['result']['records']]"`

Expected two lines: `Lessard_Org 0011N00001JbQ7EQAV TRANS-PRO LOGISTIQUE - TPML- LESSARD ORG` and `Tpml_TP_Org 0011N00001JcHnvQAF Tpml (Trans-Pro Logistics)-TP org`.

`sf data query -o sandbox -q "SELECT Id, Name FROM Account WHERE Id IN ('0011N00001JcHnvQAF','0011N00001JbQ7EQAV') ORDER BY Name" --json | python3 -c "import json,sys; s=sys.stdin.read(); [print(r['Id'], r['Name']) for r in json.loads(s[s.index('{'):])['result']['records']]"`

Expected two lines: `0011N00001JcHnvQAF Tpml (Trans-Pro Logistics)-TP org` and `0011N00001JbQ7EQAV TRANS-PRO LOGISTIQUE - TPML- LESSARD ORG` (read in PostProduc on 2026-09-15 while planning; both accounts have `Black_List__c` false).

`sf data query -o sandbox -q "SELECT DeveloperName, Place_Key__c, Active__c FROM Handoff_Point__mdt ORDER BY DeveloperName" --json | python3 -c "import json,sys; s=sys.stdin.read(); [print(r['DeveloperName'], r['Place_Key__c'], r['Active__c']) for r in json.loads(s[s.index('{'):])['result']['records']]"`

Expected three lines: `Calexico_CA_US calexico|ca|us True`, `Laredo_TX_US laredo|tx|us True`, `San_Diego_CA_US san diego|ca|us True`.

`sf data query -o sandbox -q "SELECT Key__c, Geolocation__Latitude__s, Geolocation__Longitude__s FROM Pricing_Place__c WHERE Key__c IN ('laredo|tx|us','san diego|ca|us','calexico|ca|us') ORDER BY Key__c" --json | python3 -c "import json,sys; s=sys.stdin.read(); [print(r['Key__c'], r['Geolocation__Latitude__s'], r['Geolocation__Longitude__s']) for r in json.loads(s[s.index('{'):])['result']['records']]"`

Expected three lines with coordinates: `calexico|ca|us 32.683461 -115.421826`, `laredo|tx|us 27.618453 -99.509907`, `san diego|ca|us 32.662087 -117.035038` (read while planning; a place rebuild may move them slightly, but none may be blank, or `SplitEstimates` skips that point).

`sf sobject describe -s RFP_Lane__c -o sandbox --json | python3 -c "import json,sys; s=sys.stdin.read(); f=[x for x in json.loads(s[s.index('{'):])['result']['fields'] if x['name']=='Cost_Source__c'][0]; print('Cost_Source__c', [p['value'] for p in f['picklistValues'] if p['active']], 'restricted', f['restrictedPicklist'])"`

Expected: `Cost_Source__c ['Bid', 'History median', 'Manual', 'Split'] restricted True` (before this phase it printed the first three).

`sf data query -o sandbox -q "SELECT Parent.Name, SetupEntityId FROM SetupEntityAccess WHERE Parent.Name IN ('Lane_Benchmark_User','RFP_Tool_User') AND SetupEntityType = 'ApexClass' AND SetupEntityId IN (SELECT Id FROM ApexClass WHERE Name IN ('CarrierLeadController','SplitLaneController')) ORDER BY Parent.Name" --json | python3 -c "import json,sys; s=sys.stdin.read(); r=json.loads(s[s.index('{'):])['result']; print('rows', r['totalSize']); [print(x['Parent']['Name'], x['SetupEntityId']) for x in r['records']]"`

Expected: `rows 4`, then two `Lane_Benchmark_User` lines and two `RFP_Tool_User` lines, with the same two class Ids in each pair.

`sf data query -o sandbox -q "SELECT IsoCode, ConversionRate, StartDate, NextStartDate FROM DatedConversionRate WHERE IsoCode = 'USD' AND NextStartDate > 2026-08-01 ORDER BY StartDate" --json | python3 -c "import json,sys; s=sys.stdin.read(); [print(r['IsoCode'], r['ConversionRate'], r['StartDate'], r['NextStartDate']) for r in json.loads(s[s.index('{'):])['result']['records']]"`

Expected: three lines in PostProduc (read while planning): `USD 0.7203 2026-07-27 2026-08-03`, `USD 0.7211 2026-08-03 2026-08-11`, `USD 0.7239 2026-08-11 9999-12-31`. The last line's start date is the one the USD split card cites.

- [ ] **Step 8: Spec Outcome and the roadmap date**

Append to `docs/superpowers/specs/2026-09-14-phase-8-carriers-and-split-lanes-design.md`, after its last line (R109), with one blank line before:

```markdown
## 11. Outcome — phase 8 ((fill: date of the final deploy))

Branch `phase-8/carriers-and-split-lanes` from `main` at (fill: the main SHA the branch started from), with phase 7 merged in at `44081a7` and again at `b847aec` (its Market Test exclusion); spec (fill: SHA of the spec commit); plan (fill: SHA and message of the plan commit).

Commits: (fill: every commit on the branch after the plan, in order, as `` `sha` `` message (Task N), with a clause for any fix round); and this documentation commit, Document carriers to ask and split-lane options (phase 8) and record the outcome (Task 11: the guide's sections in English and French, the README section, inventory rows and 40-class roster, the CI roster, roadmap row 8, this Outcome).

**Freight-plan test data (Task 1):** (fill: branch A, tests insert `rtms__FreightPlan__c` and `rtms__FreightPlanLoad__c` rows and the leg load's `rtms__Carrier__c`, `rtms__Carrier_Quote_Total__c` and `rtms__Load_Status__c` stick; or branch B, `SplitTestData.plan` builds the parent-child rows in memory through `FreightPlanReader.rowsOverride` because (the managed trigger or validation that refused); with the deploy id of the proof.)

**Differences from the spec.**

1. `LaneSearchQueryBuilder`'s select reads `rtms__Vendor__r.Black_List__c` and `rtms__Carrier_Service__r.rtms__Transportation_Profile__r.Outstanding_Claim__c` in place of `Carrier_Att__c`, and a new `CarrierWarning.text` builds the warning for quote rows (called from `LaneSearchService.toRow`) and bid rows (called from `BidSearchService`, from `Carrier__r.Black_List__c`); §6 places the text in `LaneSearchService` (Task 4, so `LaneSearchService` keeps its budget).
2. The mode, equipment and hazmat conditions moved out of `LaneSearchFilters` into `LaneLoadFilters`, beside `LaneKeyMatcher` (§6 names only the matcher), so both cards apply them on any load path; `LaneSearchQueryBuilderTest` fixed the search's SOQL and binds before the move and passed unchanged after it (Task 2).
3. The plan reads carry LIMITs: 500 plans for Carriers to ask's split legs and 1,000 for split history; reaching one sets `truncated` ("The list may be incomplete."), as a 51st carrier group does in stage 1; stage 2 ignores the group cap because its top 10 is exact (§8 says "a LIMIT") (Tasks 5, 6, 8).
4. `ExchangeRates.usd` reads the USD periods from 400 days back, and a load dated before the first period read uses that period's rate (§4 names only dates after the last period) (Tasks 3, 8).
5. On Lane Benchmark the split card has no Use as cost (D9 names the lane panel) and starts in USD only when the currency filter is USD, otherwise CAD (§4) (Task 10).
6. Intercompany carriers are removed in SOQL from the quote counts and the estimate leg reads, but from freight-plan legs in Apex as the plan rows are read (`CarrierLeadService` Tally, `SplitLaneService` history), because a split shipment with an intercompany leg must be skipped whole (R87); stages still count as empty, and stage 2's top 10 is still taken, after the removal (§3 says "by the queries themselves") (Tasks 5, 8).
7. (fill: each further difference a task's contract notes, a controller ruling or a fix round introduced, with its task and commit; or delete this item.)

**PostProduc deploys**, all Succeeded unless noted: (fill: one entry per deploy with its id and what it carried: Task 1 metadata and the plan-insert proof; the scoped deploys of Tasks 2–10 with their test counts; any Failed attempt with its reason and the commit that fixed it). Final pair: (fill: NoTestRun id, C / C components, 0 errors), (fill: RunSpecifiedTests id, the 40 test classes, T / T, 0 failures).

**Settings verified in the org:** (fill: what the Step 7 queries printed: the two `Intercompany_Carrier__mdt` records and the account names their Ids resolve to, the three active `Handoff_Point__mdt` keys and their places' coordinates, the `Cost_Source__c` values, class access to `CarrierLeadController` and `SplitLaneController` in both permission sets, and the latest USD `DatedConversionRate` period.)

**Tests:** Apex (fill: T) / (fill: T) in the final RunSpecifiedTests deploy: 219 at the end of phase 7, plus (fill: each new class with its count, in roster order from `SplitTestDataTest` to `SplitLaneControllerTest`) and (fill: the methods added to `LaneSearchServiceTest` and `BidSearchServiceTest`); the other 24 classes unchanged. Jest (fill: suites) suites / (fill: tests) tests (39 / 363 at the end of phase 7; Task 7 (fill: suites and tests added), Task 10 (fill: suites and tests added)). PMD clean; `RfpLaneController`, `RfpSecurityTest`, `RfpBulkService`, `LaneBenchmarkController`, `RfpHistoryService`, `LaneSearchRequest` and `LaneSearchResult` untouched; `rfpTool.js` still 554 lines and `rfpTool.html` untouched.

**Query counts (debug log, browser check):** pending (controller).

**Known limits.** USD amounts on the split card depend on Salesforce's weekly USD dated exchange rates, and whether production keeps them current is to be confirmed (PostProduc's latest period starts 2026-08-11 at 0.7239); stage 2 leaves out loads whose stop account has a blank `ShippingCountry` (about 4 % of recent loads); freight-plan junction rows carry 2026 creation dates, so split dates come from the customer load (R84); a handoff group is named from the leg's lane and last stop account, so one yard under two account names shows as two groups; border and yard fees are rarely recorded, so an estimate's handoff cost is only what the pricer types; both cards serve repeated views from the cache of cacheable Apex and have no Refresh control (R91); `RfpLaneController`, `RfpSecurityTest` and `RfpBulkService` stay at PMD class complexity 39 of 40; (fill: anything else found while building or checking, or "nothing further").

**Review record.** (fill: per task, the review result and each fix round.)

**Browser check:** pending (controller)
```

Differences 1–6 are prefilled from this plan's contract: check each against the code as merged and correct any a fix round changed. Then replace every `(fill: …)` above with the real value, using what Steps 6 and 7 printed. The Outcome date is the date of the second Step 7 deploy; if roadmap row 8 (Step 5) carries an earlier date, change it to that date.

Run: `npx prettier --write docs/superpowers/specs/2026-09-14-phase-8-carriers-and-split-lanes-design.md docs/superpowers/specs/2026-09-07-pricing-department-roadmap.md && grep -c "(fill" docs/superpowers/specs/2026-09-14-phase-8-carriers-and-split-lanes-design.md docs/superpowers/specs/2026-09-07-pricing-department-roadmap.md`

Expected: both counts `0` (grep exits 1 when nothing matches, which is the pass here). A line still holding `(fill` is a review failure. `Query counts (debug log, browser check): pending (controller).` and `Browser check: pending (controller)` stay until Step 10.

- [ ] **Step 9: Commit**

```bash
git add docs/help/en/lb-stats.md docs/help/fr/lb-stats.md docs/help/en/rfp-pricing.md docs/help/fr/rfp-pricing.md docs/help/en/rfp-inline.md docs/help/fr/rfp-inline.md docs/help/en/rfp-filters-export.md docs/help/fr/rfp-filters-export.md force-app/main/default/staticresources/helpCenter/en/lb-stats.html force-app/main/default/staticresources/helpCenter/fr/lb-stats.html force-app/main/default/staticresources/helpCenter/en/rfp-pricing.html force-app/main/default/staticresources/helpCenter/fr/rfp-pricing.html force-app/main/default/staticresources/helpCenter/en/rfp-inline.html force-app/main/default/staticresources/helpCenter/fr/rfp-inline.html force-app/main/default/staticresources/helpCenter/en/rfp-filters-export.html force-app/main/default/staticresources/helpCenter/fr/rfp-filters-export.html README.md .github/workflows/ci.yml docs/superpowers/specs/2026-09-07-pricing-department-roadmap.md docs/superpowers/specs/2026-09-14-phase-8-carriers-and-split-lanes-design.md
git diff --cached --name-only
git commit -m "Document carriers to ask and split-lane options (phase 8) and record the outcome"
```

Expected: `git diff --cached --name-only` prints exactly those 20 paths and nothing named `node_modules`, `.vscode/settings.json`, `.ai-handover` or `* 2.*`. lint-staged runs Prettier on the staged Markdown, YAML and HTML (no change expected after Steps 6 and 8). `git log -1 --format=%B` shows the one-line message with no trailer.

- [ ] **Step 10: Browser check (controller, not the implementer)**

In PostProduc as the admin, in a fresh tab after the final deploy (hard reload once, Cmd+Shift+R). Both cards call cacheable Apex: a lane already opened in this browser session answers from the cache and writes no debug log, so each numbered check uses a lane not opened before in the session (or a new tab after a hard reload).

Before starting, open Setup → Debug Logs → **New** under User Trace Flags, pick the admin user, an expiry one hour ahead and the `SFDC_DevConsole` debug level, and save. After each check that says "log", list the newest logs and read the query counts of the one that ran the card's controller:

`sf apex list log -o sandbox --json | python3 -c "import json,sys; s=sys.stdin.read(); [print(r['Id'], r['StartTime'], r['Operation'], r['LogLength']) for r in sorted(json.loads(s[s.index('{'):])['result'], key=lambda x: x['StartTime'], reverse=True)[:6]]"`

`sf apex get log -o sandbox -i <log id> | grep -E "CODE_UNIT_STARTED.*(CarrierLeadController|SplitLaneController)|Number of SOQL queries|Number of query rows" | head -8`

Paste the log id literally. The log that ran a card shows its `CODE_UNIT_STARTED` line with `CarrierLeadController.findCarrierLeads` or `SplitLaneController.splitOptions`, and its `Number of SOQL queries: n out of 100` is the count to record. If no log carries either class name (the call came from the cache), record "cached" and move on.

1. **Split history (Lane Benchmark).** Search General Escobedo, NL → St-Augustin-de-Desmaures, QC (pick the `St-Augustin-de-Desmaures, QC` suggestion), both ends Exact city, lookback 90, Currency All. Scroll below the results: a **Split-lane options** button, and no split card yet. Click it: a spinner, then the card with **CAD** pressed (`aria-pressed` true) and at least one history option titled "Via Laredo, TX · SFMN Park ITC Laredo yard · N shipments" (PostProduc holds plans on this lane with leg 1 General Escobedo, NL → Laredo, TX by Q TRANSPORTES S.A. DE C.V.* and leg 2 Laredo, TX → St-Augustin-de-Desmaures, QC by Simconnect Freight Management), two leg lines "Leg 1 General Escobedo, NL → Laredo, TX · … (n) · median … CAD", and "Total per shipment, median … CAD (n shipments)". A "Direct median … CAD" line shows if the Statistics card has a CAD median, and nothing otherwise. Log: record the query count. Click **USD**: a spinner, amounts about 0.72 × the CAD ones, and "Converted at the USD rate of 2026-08-11."; log. Click **CAD** again: the CAD answer shows at once and no new log names `SplitLaneController`. Set Currency to USD, click **Apply**, then **Split-lane options**: the card starts with **USD** pressed. If the search itself had no priced rate, **Carriers to ask** also shows under Statistics: note it.
2. **Carriers to ask and the no rate tag (RFP Tool, CAD).** Open "Phase 3c browser check". Row 2 (Mississauga, ON → General Escobedo, NL, No match) shows a **no rate** badge in its History cell; a lane whose History cell has a median shows none. Open row 2: under the history results, the **Carriers to ask** card with the heading "No carrier rate on this lane in CAD. These carriers quoted or moved it before; amounts are not shown." and lead rows "n moved · n quoted · last seen YYYY-MM-DD" with their sources; or, when the same lane has no carrier, "No carrier on this exact lane. Top carriers on ON to NL over the last year." with at most 10 rows; or "No carrier found on this lane or on its state or province lane.". Record which. A carrier name that is a link opens `/lightning/r/Account/<Id>/view`; a **Blacklisted** badge shows beside a blacklisted carrier if any is listed (record "none listed" otherwise). No row shows an amount. Log: record the query count and whether stage 2 ran.
3. **Carriers to ask on Lane Benchmark.** Search Mississauga, ON → General Escobedo, NL (Exact city, lookback 90) with Currency CAD: if Statistics has no CAD median, the card shows under Statistics, above the map, with "… on this lane in CAD. …". Set Currency All and **Apply**: the heading has no currency code when no bucket has a priced rate, and the card is hidden when any bucket has one. Record both.
4. **Results warning.** Search GENERAL ESCOBEDO, NL → Florence, KY (Exact city, lookback 90, Currency All): result rows from Gl Logistics Co Llc (Especializados Lopez), a blacklisted account with accepted quotes on this lane up to 2026-07-08, show the red warning "THE CARRIER IS BLACK-LISTED"; a row whose Transportation Profile is under a claim still shows "UNDER A CLAIM".
5. **USD lane, estimate and Use as cost (RFP Tool).** Open "Cusma Test" and the lane Ramos Arizpe, CO → Cambridge, ON (USD, with a History median, so no **no rate** tag and no Carriers to ask card). Click **Split-lane options**: the card starts with **USD** pressed. PostProduc has no freight plan on this lane in the last 12 months (checked while planning), so expect "Estimate via Laredo, TX · +n % distance" with two leg lines, or the "No split shipment on this lane in the last 12 months, and no handoff point is close enough for an estimate." message (then use Apaseo el Grande, GT → Bowling Green, OH, also USD, and record the lane used). Log: record the query count. Type 250 in **Handoff cost (USD)**: "Estimate total … USD" appears when both legs have a median, and **Use as cost** beside it. Click **Use as cost**: the panel's **Cost** becomes that total (2 decimals), **Cost source** shows **Split** selected, any selected bid is cleared, and the margin and sell follow. Click **Save price**; reload the project and reopen the lane: the cost stays and **Cost source** still shows **Split**. Choose **Manual** as the source: **Split** leaves the choices (do not save; reload to discard). In the split card click **CAD**: the Handoff cost is cleared, no option shows **Use as cost**, and the card shows one note, "Switch to USD to use a split cost.". Click **USD** again: the USD answer shows at once.
6. **No rate in USD.** In "Cusma Test", Ramos Arizpe, CO → General Escobedo, NL (No match) shows the **no rate** badge; opening it shows **Carriers to ask** with "… on this lane in USD. …" (or the stage 2 or empty wording; record which).
7. **Retry.** Open Chrome DevTools → Network → Offline, then open a lane with a **no rate** badge not opened before in the session: the card shows its error and **Retry**. Go back Online and click **Retry**: the card loads (a new `attempt` bypasses the cache). Record the result or "not reproduced".
8. **Excel export.** On "Cusma Test", **Export to Excel**: the Lanes sheet has **Cost source** right after **Currency**, reading `Split` on the lane priced in check 5 and blank on lanes without a cost.
9. **Help tab.** In English, "Reading the statistics" shows "Carriers to ask" and "Split-lane options"; "Pricing a lane" shows the **Split** bullet and "Carriers to ask", "Split-lane options" and "Use as cost"; "Editing in the table" shows "The no rate tag"; "Filters, selection and export" names the Cost source column. In French, the same pages show the same headings, with "L'étiquette no rate".
10. **Console.** The browser console shows no error from `c-carrier-leads`, `c-split-lane-options`, `rfpLanePanel`, `rfpLaneTable` or `laneBenchmark`.

Delete the trace flag (Setup → Debug Logs). Record the results in the Outcome, replacing both "pending (controller)" lines (the query counts per check: Carriers to ask stage 1 and, where it ran, stage 2; split history in CAD and USD; the estimate), then commit:

```bash
git add docs/superpowers/specs/2026-09-14-phase-8-carriers-and-split-lanes-design.md
git commit -m "Record the phase 8 browser check"
```

#### Contract notes (Task 11)

1. **Five roster sites, found by content.** Besides the contract's four (the README "Apex tests" row, the `-t` list under "Working with the org", the production command and `ci.yml`), README also lists the roster in the `sf apex run test -n …` line under "Working with the org"; Step 3 updates all five and asserts each anchor's count (1, 1, 2 and 1) before writing. The fourteen classes are appended after `RfpBulkControllerTest` in the contract's order.
2. **README beyond the named section and roster.** Six inventory rows (four Apex, one Data, one UI), one clause on each Security row and three Known issues bullets are added, as phase 7's Task 11 did, so the inventory does not have to be fixed after the final review.
3. **Guide placement.** In `lb-stats` the two sections go before `## Duplicates`, after phase 7's trip miles section, following the right column's order (Statistics, Carriers to ask, map, results, split button). In `rfp-pricing` they are appended after `## Results`, the panel's own order (history results, Carriers to ask, Split-lane options). French headings keep the English UI names (as the French guide already does with `## Include RFP bids` and `## Export to Excel`), except `## L'étiquette no rate`. Cards are "encadré" in French, as in phase 7's `lb-stats`, so "carte" stays the map. Front matter is unchanged, so the build still reports 15 sections, `index.json` does not change and exactly eight HTML files change.
4. **The results warning (D5) is not in the guide.** No guide page mentions the red warning text today (checked with `grep -i "black\|claim\|warning"` over `docs/help`), so D5 is documented in the README section only. The guide does not name "Copy pricing" (no page uses that label); `rfp-pricing` refers to the identical lanes bar that `rfp-inline` documents.
5. **Counts are printed, not trusted.** The other task drafts were not readable when this task was drafted, so Step 6 prints the Apex total T (the base 219 over 26 classes at `44081a7` was measured, and the script checks that the 24 classes this phase does not extend still match it) and the Jest total. The expected 42 Jest suites, 324 manifest members and 325 deployed components are derived from the contract's file list (30 Apex classes, 2 custom metadata types, 4 fields, 5 records, 3 bundles; phase 7's final deploy counted 281 components for 280 members). A different number is explained in the Outcome, not forced.
6. **Deploy shape** follows phase 7's Task 11 Step 7 exactly: a full-manifest NoTestRun deploy, then the full manifest with the (empty) post-destructive manifest and `RunSpecifiedTests` over the 40 classes, both `--async` and polled with the same report parser.
7. **Queries proven read-only on 2026-09-15:** `SetupEntityAccess` joined to `ApexClass` (it returned both permission sets for `TripRouteView`), the `sf sobject describe` picklist parser (it printed `['Bid', 'History median', 'Manual'] restricted True`), the `Account` names of the two intercompany Ids, the handoff places' coordinates, the USD `DatedConversionRate` rows, the `sf apex list log` / `sf apex get log -i` flags, and the browser-check data: four freight plans on General Escobedo, NL → St-Augustin-de-Desmaures, QC via "SFMN Park ITC Laredo yard"; no plan on Ramos Arizpe, CO → Cambridge, ON; the "Cusma Test" USD lanes and "Phase 3c browser check" No match lanes; accepted quotes by the blacklisted Gl Logistics Co Llc (Especializados Lopez) on GENERAL ESCOBEDO, NL → Florence, KY. The two `__mdt` queries in Step 7 cannot run before Task 1 deploys the types; they are plain SOQL on the contract's field names.
8. **Outcome heading** is `## 11. Outcome — phase 8`, following the phase 8 spec's numbered sections (phase 7's spec has an unnumbered `## Outcome — phase 7`). The query-count and browser-check lines say "pending (controller)" without a fill marker, because Step 10 runs after the commit and the Step 8 grep must reach 0.
9. **README admin guidance vs. deploys.** The spec calls both lists admin-editable; the manifest carries the five records, so every full-manifest deploy overwrites them. The README says both: edit in Setup, and make the same change in the repo by pull request (the rule phase 7 set for `Truck_Routing_Setting.Default`). The weekly USD rates in production are stated as "to be confirmed", as in spec §2.
10. **Untracked files in this tree.** `node_modules` is an untracked symlink here (the tree's `git status` shows it); Steps 6 and 9 name it with `.vscode/settings.json`, `* 2.*` and `.ai-handover` as never staged.
11. **Scope checks added to the gate** (Step 6): the six frozen Apex classes plus `LaneSearchResult`, `rfpTool.js` and `rfpTool.html` show no diff against `b847aec`; no Mapbox class, HTTP, `TPRO_KPI__c` or `getChars` in the phase's classes; no amount field in Carriers to ask's classes; the two account Ids appear in `force-app` only in their custom metadata records; the Mapbox token grep stays empty.
12. **Dry run on a copy.** Steps 1–5 and the Step 8 append were run on a scratch copy of this branch's README, CI workflow, guide, roadmap, spec and help build (2026-09-15): every Python anchor assertion held, the roster check printed the five `40 True` lines at README 28, 107, 114, 393 and `ci.yml` 59, the README headings came out Trip miles → phase 8 → Help center, roadmap row 8 was added, the Outcome carried 21 fill markers, Prettier changed only the README and roadmap tables and left every guide file and the spec unchanged, and `help:build` reported 15 sections with exactly the eight expected HTML files changed and `index.json` untouched. The Step 2 grep counts were taken from that run.

<!-- prettier-ignore-end -->
