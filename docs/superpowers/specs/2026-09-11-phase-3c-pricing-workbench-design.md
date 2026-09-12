# Phase 3c — RFP workbench pricing improvements (design)

Date: 2026-09-11. Roadmap: phase 3 (RFP tool), third increment after 3a (objects and bids) and 3b (workbench). Builds on `docs/superpowers/specs/2026-09-10-phase-3-rfp-tool-design.md` and its `## Outcome — 3b` section; nothing there is changed unless this document says so.

## 1. Goal

Make pricing 200 lanes fast. Today every lane is priced one at a time in the right panel, the sell price only follows the margin, the history radius is fixed at 50 km, and the panel scrolls away on long sheets. After 3c a pricer can:

1. type a sell price directly and have the margin follow it, or type a margin and have the sell follow it (per lane, last entry wins);
2. choose the radius a history run uses (and the radius the city-to-radius fallback uses);
3. push found medians and a margin onto every lane in one click;
4. edit cost, margin and sell straight in the lane row, spreadsheet style, saving on leaving the cell;
5. select lanes and apply one cost, one sell, one margin or one carrier rate to all of them, or delete them;
6. keep the pricing panel in view while scrolling the table;
7. filter and search the lane table;
8. get an annual sell column and a summary sheet in the export;
9. copy a priced lane onto its unpriced twins (same places, mode and equipment).

Everything is built for the `RFP_Tool_User` permission set in PostProduc (sf alias `sandbox`) only.

## 2. Decisions taken during brainstorming

| #   | Question              | Decision                                                                                                                                                       |
| --- | --------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| D1  | Manual sell vs margin | Linked. Typing a sell recomputes the margin; typing a margin recomputes the sell. The lane records which one drives (`Sell_Source__c`).                        |
| D2  | Radius                | One radius per history run, entered next to the precision picker, also used by the CITY → RADIUS fallback instead of the fixed 50 km.                          |
| D3  | Apply to all          | "Use median" applies only to lanes where a median was found. Lanes already costed from a bid or manually are skipped unless the pricer asks to overwrite them. |
| D4  | Inline editing        | Saves on leaving the cell. Enter and Tab save and move down the same column. Escape cancels.                                                                   |
| D5  | Bulk carrier          | Creates the same Benchmark Rate on each selected lane and selects it as the cost.                                                                              |
| D6  | Extras                | Filters and search on the lane table; delete selected lanes; annual sell and a Summary sheet in the export; same-lane auto copy.                               |
| D7  | Approach              | A: server-side bulk endpoints, one active inline cell, pure client modules (see §3).                                                                           |

## 3. Approaches considered

- **A (chosen).** New Apex `RfpBulkController` + `RfpBulkService` run every many-lane action in one call per 200 lanes. The lane table edits one cell at a time. Filters, twin detection and export additions are pure JS modules with Jest tests.
- **B (rejected).** Client loops over the existing single-lane endpoints: 200 round trips per action, no transaction for "same bid on N lanes", unclear partial-failure state.
- **C (rejected).** Replace `rfpLaneTable` with `lightning-datatable` inline edit: loses the inline place picker, the keyboard and aria work from 3b, and per-row saving states.

## 4. Data model

### 4.1 New field

`RFP_Lane__c.Sell_Source__c` — restricted picklist, values `Margin` (default) and `Manual`, generated through `scripts/metadata/gen_rfp_fields.py` (`picklist(L, "Sell_Source__c", "Sell source", ["Margin", "Manual"])`), registered in `manifest/package.xml`, editable + readable in `RFP_Tool_User` (no entry in `Lane_Benchmark_User`, which holds no `RFP_Lane__c` fields).

Meaning:

- `Margin`: the sell was derived from the cost and the margin. When the cost changes the sell is recomputed.
- `Manual`: the pricer typed the sell. When the cost changes the sell is kept and the margin is recomputed, so a quoted price never moves silently; the eroded margin becomes visible instead.

Lanes that exist before 3c have a null `Sell_Source__c`; null is read as `Margin` everywhere.

### 4.2 Precision string

`Hist_Precision__c` (Text 20) keeps `CITY` and `PROVINCE` and now stores `RADIUS-<n><KM|MI>` where `<n>` is the whole-number radius used, e.g. `RADIUS-150KM`, `RADIUS-75MI`. `RADIUS-50KM` written by 3b is already in this shape.

### 4.3 Permissions

`RFP_Tool_User`: `allowDelete` becomes `true` on `RFP_Lane__c` and on `Benchmark_Rate__c` (a lane's bids are deleted with the lane, §5.4). Nothing changes for `RFP_Project__c` (no delete) or for `Lane_Benchmark_User`.

### 4.4 Pricing math (shared rule)

Two decimals, half up, identical in Apex (`RfpPricingMath`) and JS (`c/marginMath`, already there for `suggestedSell`):

- `sellFor(cost, marginPct)` = round2(cost × (1 + marginPct / 100)); null when cost ≤ 0 or margin null.
- `marginFor(cost, sell)` = round2((sell / cost − 1) × 100); null when cost ≤ 0 or sell null; null when the result does not fit `Margin__c` (precision 5, scale 2: outside −999.99..999.99). A derived margin may be negative (sell below cost); the table shows it in red.

A typed margin (panel, inline, bulk) must be 0..100, as `parseMargin` already enforces. A typed cost or sell must be > 0.

**Recompute rule** (`RfpPricingMath.recompute(lane, defaultMargin)`), applied by every server action that sets a cost:

```
if lane.Sell_Source__c == 'Manual' and lane.Sell__c != null:
    lane.Margin__c = marginFor(lane.Cost__c, lane.Sell__c)
else:
    margin = lane.Margin__c ?? defaultMargin
    lane.Margin__c = margin
    lane.Sell__c = sellFor(lane.Cost__c, margin)
    lane.Sell_Source__c = 'Margin'
```

`defaultMargin` is the project's `Default_Margin__c` (import already copies it onto each lane, so it is only a fallback).

## 5. Apex

### 5.1 `RfpPricingMath` (new, `public with sharing`, pure)

`sellFor(Decimal, Decimal)`, `marginFor(Decimal, Decimal)`, `recompute(RFP_Lane__c, Decimal)` as in §4.4. `RfpPricingMathTest` proves the rounding on the same value table the Jest test for `c/marginMath` uses (parity: `cost 1234.56, margin 15 → 1419.74`; `cost 1000, sell 1150 → 15.00`; `cost 1000, sell 900 → −10.00`; `cost 0 → null`; `cost 3, sell 3.01 → 0.33`).

### 5.2 History radius

- `RfpHistoryController.loadHistory(List<Id> laneIds, String precision, Integer lookbackDays, Decimal radius, String radiusUnit)`.
- `RfpHistoryService.run(List<Id> laneIds, String precision, Integer lookbackDays, Decimal radius, String radiusUnit)`. Radius null or ≤ 0 → 50; > 500 → `LaneSearchException('Radius must be between 1 and 500.')`; unit anything but `MI` → `KM`. The whole-number radius (`radius.round()`) is used for the search and stamped as `RADIUS-<n><unit>`. Both the explicit RADIUS precision and the CITY → RADIUS fallback use it; the constant `FALLBACK_RADIUS_KM` goes away.
- Existing tests are updated for the five-argument signatures; new tests: fallback stamps `RADIUS-120KM` when called with 120/KM; `MI` is honoured; 600 is refused.

### 5.3 `BenchmarkRateService.saveAll(List<Benchmark_Rate__c>)` (new)

Same contract as `save` for a list: every bid needs `Rate__c`, `stripInaccessible(CREATABLE)`, one `Database.insert(list, AccessLevel.USER_MODE)` (all or none), returns the reloaded bids in input order. `save` stays as it is. `BenchmarkRateServiceTest` gains a three-bid case proving all three carry the lane keys the trigger stamps.

### 5.4 `RfpBulkService` (new) and `RfpBulkController` (new, thin `@AuraEnabled` wrappers)

Common contract:

- Input ids: 1..200, all lanes of one project; more than 200 → `RfpUserError.of('Apply to at most 200 lanes per call.')`. The client chunks larger sets.
- Every read and write is user mode (`lanesByIds`, `stripInaccessible`, `Database.update(list, false, AccessLevel.USER_MODE)`).
- Return type `RfpBulkService.Result { List<RFP_Lane__c> lanes; Integer updated; Integer skipped; List<Id> skippedIds; List<String> errors; }` — `lanes` are the refreshed lanes (`RfpLaneController.lanesByIds`, same field list as `getLanes`), `errors` hold at most five per-record messages (`Id + ': ' + message`, each cut to 160 chars) plus, when more failed, `'… and N more'`.
- Per-record DML failures do not abort the others (`allOrNone = false`), except `applyBid`, which runs inside a `Savepoint` and rolls back when the lane update fails, so no bid is left behind without the lane pointing at it.

Actions:

| Method                                  | Rule                                                                                                                                                                                                                                                                                                                                                                                                                                                                             |
| --------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `applyMedian(ids, overwrite)`           | Lanes with `Hist_Median__c != null`. A lane already costed (`Cost__c != null`) from `Bid` or `Manual` is skipped (counted, id listed) unless `overwrite`. Sets `Cost__c = Hist_Median__c`, `Cost_Source__c = 'History median'`, `Selected_Bid__c = null`, then §4.4 recompute.                                                                                                                                                                                                   |
| `applyPricing(ids, cost, sell, margin)` | At least one non-null; `sell` and `margin` together → user error. `cost` (> 0): `Cost__c = cost`, `Cost_Source__c = 'Manual'`, `Selected_Bid__c = null`, then recompute. `sell` (> 0): `Sell__c = sell`, `Sell_Source__c = 'Manual'`, `Margin__c = marginFor(Cost__c, sell)` (null when uncosted). `margin` (0..100): `Margin__c = margin`, `Sell_Source__c = 'Margin'`, `Sell__c = sellFor(Cost__c, margin)` (null while uncosted, so the margin is ready when a cost arrives). |
| `applyBid(ids, bidJson)`                | `bidJson` is a `Benchmark_Rate__c` template without `Id`/`RFP_Lane__c`. Lanes whose `CurrencyIsoCode` differs from the bid's are skipped (ruling R19 stands: no cross-currency cost). One bid per remaining lane via `saveAll`; then each lane gets `Cost__c = Rate__c`, `Cost_Source__c = 'Bid'`, `Selected_Bid__c = new bid`, recompute.                                                                                                                                       |
| `copyPricing(sourceLaneId, ids)`        | Copies `Cost__c`, `Cost_Source__c`, `Selected_Bid__c`, `Margin__c`, `Sell__c`, `Sell_Source__c` verbatim from the source lane onto the target lanes (the twin references the same bid record). Source not costed → user error.                                                                                                                                                                                                                                                   |
| `deleteLanes(ids)`                      | Deletes `Benchmark_Rate__c WHERE RFP_Lane__c IN :ids` first, then the lanes, both user mode, `allOrNone = false`. `Result.updated` = lanes deleted, `errors` as above, `lanes` = the lanes that still exist. Roll-ups on `RFP_Project__c` recompute on their own (master-detail).                                                                                                                                                                                                |

Class-size rule (PMD): the controller holds only the five wrappers and their try/catch; the service holds the logic, split so no method exceeds the cyclomatic cap of 10 (one private method per action plus `load`, `save`, `result` helpers). Tests: `RfpBulkServiceTest` (each action's happy path, skip path and cap; recompute under both sell sources; `applyBid` currency skip and Savepoint rollback proven by a lane made invalid), `RfpBulkControllerTest` (the user-error wrapping), and `RfpSecurityTest` gains `restrictedUserCanDeleteLanes`.

### 5.5 `RfpLaneController.saveLanePricing`

The whitelist gains `Sell_Source__c`; `LANE_FIELDS` gains `Sell_Source__c`. Nothing else changes.

## 6. Lightning web components

### 6.1 `c/marginMath` (existing pure module)

Gains `marginFor(cost, sell)` (§4.4). `parseMargin` unchanged.

### 6.2 `c/rfpPricing` (existing pure module)

- `pricingDetail` gains `sellSource` and an optional typed `sell`: with `sellSource === "Manual"` it sends the typed sell and the derived margin; otherwise the current behaviour plus `Sell_Source__c: "Margin"`.
- `inlineEdit(lane, field, text, defaultMargin)` → the same detail shape for a row edit (`field` ∈ `cost | margin | sell`), or `null` when the text is invalid (blank, not a number, cost/sell ≤ 0, margin outside 0..100). `cost` sets `Cost_Source__c: "Manual"`, `Selected_Bid__c: null`, then the §4.4 rule on the client; `margin` and `sell` as in `applyPricing`. `Notes__c` is carried from the lane.
- `parseRadius(precisionText)` → `{ radius, unit }` from `RADIUS-<n><KM|MI>` or `null`; `historyKey` and `historyRequest` use it (so a lane snapped at 150 km searches the panel at 150 km, and legacy `RADIUS-50KM` still works).
- `pricingFingerprint(lane)` → `Cost__c|Cost_Source__c|Selected_Bid__c|Margin__c|Sell__c|Sell_Source__c` joined, used by the panel setter (§6.5).

### 6.3 `c/rfpLaneFilter` (new pure module)

`STATUS_FILTERS` = all | unpriced | nomatch | unresolved | manual | selected, and `applyFilter(lanes, { status, text, selectedIds })`:

- `unpriced`: `Cost__c` null; `nomatch`: `Hist_Status__c === "No match"`; `unresolved`: either end unresolved; `manual`: `Cost_Source__c === "Manual"` or `Sell_Source__c === "Manual"`; `selected`: id in `selectedIds`.
- `text`: case-insensitive substring over origin and destination city, province and postal, and `Equipment_Type__c`. Blank matches all.

`siblings(lanes, lane)` → unpriced lanes (`Cost__c` null) other than `lane` with the same `Origin_Place__c`, `Destination_Place__c`, `Mode__c` and equipment (`Equipment_Type__c`, else `Equipment_Category__c`). Lanes with an unresolved end never match.

### 6.4 `c/rfpLaneTable` (existing)

New `@api`: `selectedIds` (array), `pendingIds` (array, rows being saved), `rowErrors` (object id → message), `defaultMargin`. New column 0: a checkbox per row (`data-id="row-check"`) and a header checkbox (`data-id="check-all"`) that toggles every row currently shown; both emit `selectionchange { laneIds }` with the full new selection (the parent owns it). Checkbox clicks and keys do not select the row (same `stopRowSelect` wrapper as the picker).

Inline editing of the Cost, Margin and Sell cells:

- State `editing = { laneId, field }` and `draft`. A click on one of the three cells, or Enter on a focused cell (`tabindex="0"`, `data-id="cell-cost|cell-margin|cell-sell"`), selects the row and opens one `lightning-input` (`data-id="cell-input"`, type number for cost and sell, text for margin, `step="0.01"`) in that cell; `renderedCallback` focuses it once per open.
- Enter, Tab, and blur commit; Escape cancels. Commit with an unchanged text just closes. Commit with a valid text emits `pricingchange` (detail from `inlineEdit`); an invalid text keeps the input open with `class="slds-has-error"` and `data-id="cell-error"` text under it. After Enter or Tab the same field opens on the next row shown (Shift+Tab: previous row); on the last row it just closes.
- The row's Status cell shows a small sync icon while its id is in `pendingIds` and a red icon with the message as title when `rowErrors[id]` is set; the text stays "Priced" once `Cost__c` is set.
- A negative margin gets `slds-text-color_error`. A `Sell_Source__c === "Manual"` lane shows a small "manual" tag after the sell.

### 6.5 `c/rfpLanePanel` (existing)

- Sell becomes an input (`data-id="sell"`, number). State `sellSource` (from the lane, default Margin) and `sellText`. Typing in Sell sets `sellSource = "Manual"` and shows the derived margin in the Margin input; typing in Margin sets `sellSource = "Margin"` and shows the derived sell. Changing the cost (source, bid, manual cost) applies the §4.4 rule on the client: Manual keeps the sell and re-derives the margin; Margin re-derives the sell. A small "Sell follows the margin" / "Margin follows the sell" line (`data-id="sell-mode"`) says which way the link runs.
- The `lane` setter also re-syncs the editor when the lane Id is the same but `pricingFingerprint` changed (an inline edit or a bulk action touched the lane on screen), so the panel never shows stale cost/margin/sell.
- `.lane-panel { min-height: 480px }` is removed; the sticky column (§6.7) replaces the reason it existed.

### 6.6 `c/rfpBulkBar` (new)

Rendered above the table once the workbench has lanes. `@api selectedCount, totalCount, currency, busy, project`. A scope toggle (`data-id="scope"`, radio buttons "Selected (N)" / "All lanes (M)"; Selected is disabled at 0 and the bar starts on All) and the actions:

| Control                                                                                                                                                                        | Emits `bulk` with `detail`                                           |
| ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | -------------------------------------------------------------------- |
| "Use median" button (`data-id="use-median"`)                                                                                                                                   | `{ action: "median", scope }`                                        |
| Margin % input + "Apply" (`data-id="margin"`, `apply-margin`)                                                                                                                  | `{ action: "pricing", scope, margin }`                               |
| Cost input + "Apply" (`cost`, `apply-cost`)                                                                                                                                    | `{ action: "pricing", scope, cost }`                                 |
| Sell input + "Apply" (`sell`, `apply-sell`)                                                                                                                                    | `{ action: "pricing", scope, sell }`                                 |
| "Add carrier rate" (`add-bid`) → opens `c-rfp-bid-form` with `lane-id` null and `currency`; its `save`                                                                         | `{ action: "bid", scope, bid }` (the form's bid minus `RFP_Lane__c`) |
| "Delete selected" (`delete`), Selected scope only, two clicks: the label turns into "Confirm: delete N lanes and their carrier rates" until the selection or the scope changes | `{ action: "delete", scope: "selected" }`                            |
| After a median run that skipped lanes: text "N lanes already costed from a bid or manually were left as they are" + "Overwrite them" (`overwrite`)                             | `{ action: "median", scope: "skipped", overwrite: true }`            |

Client validation mirrors the server (margin 0..100, cost and sell > 0) with a `data-id="bar-error"` line. All buttons are disabled while `busy`. `@api lastResult` (the summary text and skipped count) is what the bar renders after a run.

### 6.7 `c/rfpTool` (existing container)

- New state: `radius = 50`, `radiusUnit = "KM"` (inputs `data-id="radius"`, number 1..500, and `data-id="radius-unit"`, KM/MI, always visible, field-level help "Used for Radius precision, and when a city has no history"), `selectedIds = []`, `filter = { status: "all", text: "" }`, `pendingIds = []`, `rowErrors = {}`, `twinOffer = null`, `bulkResult = null`.
- `historyChunk` passes `radius` and `radiusUnit`.
- `visibleLanes` = `applyFilter(lanes, {...filter, selectedIds})`; the table gets `visibleLanes`; a filter bar (`data-id="filter-status"` combobox, `data-id="filter-text"` search input, "N of M lanes" text) sits above the table. Select-all toggles the visible set only.
- `handlePricingChange` marks the lane pending, saves, merges, clears pending or records `rowErrors[id]`; on success computes `siblings(lanes, saved)` and, when any, shows `data-id="twin-offer"`: "Apply the same cost and sell to N identical lanes" with Apply (→ `copyPricing`) and Dismiss. Concurrent inline saves on different lanes are allowed; a second save on a lane still pending is ignored.
- `handleBulk` resolves the id list (selected, all, or `bulkResult.skippedIds`), runs it 200 ids per call through `c/rfpBulk` (§6.8) with the existing progress bar and Stop, merges returned lanes, and for `delete` removes the ids from `lanes` and `selectedIds`. The summary line reads e.g. "Median applied to 143 lanes; 12 skipped; 2 failed".
- Sticky panel: `rfpTool.css` (new) gives the panel column `position: sticky; top: 0; align-self: flex-start; max-height: calc(100vh - 8rem); overflow-y: auto`. Jest cannot verify this; it is a browser check.
- `rfpTool.js` is at 399 lines; the bulk and filter logic lives in the modules below so the container lands around 520 lines. If it passes 560, the workbench toolbar (precision, lookback, radius, history buttons, export) moves into a `c/rfpToolbar` component in the same plan.

### 6.8 `c/rfpBulk` (new module, Apex-aware)

`runBulk({ action, ids, params, onProgress, isStopped })` chunks `ids` by 200, calls the matching `RfpBulkController` method per chunk (`series` from `c/rfpBatch`), and returns `{ lanes, updated, skipped, skippedIds, errors, failedChunks }`. A chunk that throws counts its ids as failed and the run carries on. `summaryText(action, result)` builds the one-line summary.

### 6.9 `c/rfpWorkbook` and `c/rfpExport`

- `OUR_COLUMNS` gains `"Annual sell"` after `"Sell"`: `Sell__c × Shipments_Per_Year__c`, blank when either is missing, and `"Sell source"` after it (`Manual` / `Margin`).
- `buildSheets` returns a third array `summary`: rows `["Lanes", n]`, `["Priced lanes", n]`, `["Unpriced lanes", n]`, `["No history match", n]`, `["Unresolved ends", n]`, one `["Total annual sell (CUR)", sum]` per currency present, `["Average margin %", avg over priced lanes, 2 dp]`, a blank row, then a `["Mode", "Lanes", "Priced", "Annual sell"]` table by `Mode__c` (blank mode shown as "(none)").
- `rfpExport` appends it as the sheet "Summary". Numbers are numbers; text cells stay typed strings (formula-injection rule unchanged).

## 7. Error handling

- Every Apex entry point throws `RfpUserError.of(...)` with a sentence; bulk per-record failures are returned in `Result.errors`, not thrown.
- The client shows: the container banner for a whole call failing; the row icon for an inline save failing; the bulk bar's `bar-error` for validation; the summary line for partial bulk failures.
- Deletion is the only destructive action: two-click confirm in the bar, Selected scope only, never offered for All.
- A bulk run cannot start while `busy`; inline saves are blocked while a bulk run or a history run is in flight (the cell shows "wait for the current run").

## 8. Security

- All SOQL/DML in user mode; `stripInaccessible` before every write; the `RFP_Tool_User` permission set is the only one widened (delete on lanes and bids, the new field).
- `applyBid` templates go through `BenchmarkRateService.saveAll`, which strips the service-maintained key fields the same way `save` does.
- Every new `@AuraEnabled` class needs a `classAccesses` entry in `RFP_Tool_User` in the task that creates it, the same standing rule as the manifest entry for a new bundle; `RfpSecurityTest` proves the grant by reading `SetupEntityAccess`, because class security is not enforced Apex to Apex and an Apex-to-Apex call would pass either way.
- `bidJson` and `laneJson` are deserialised into SObjects and re-copied field by field onto new records; nothing posted reaches SOQL text.
- Export: unchanged neutralisation (typed string cells).

## 9. Testing

- Apex: `RfpPricingMathTest`, `RfpBulkServiceTest`, `RfpBulkControllerTest` new; `RfpHistoryServiceTest`, `BenchmarkRateServiceTest`, `RfpLaneControllerTest`, `RfpSecurityTest` extended. RunSpecifiedTests list becomes 22 classes (the 19 plus the three new ones), mirrored in `.github/workflows/ci.yml` and both README commands and the README "Apex tests" row.
- Jest: new suites for `rfpLaneFilter`, `rfpBulk`, `rfpBulkBar`; extended suites for `marginMath`, `rfpPricing`, `rfpLaneTable` (checkboxes, one open cell, Enter moves down, Escape cancels, invalid text stays open, pending spinner, negative margin class), `rfpLanePanel` (sell input flips the mode, fingerprint re-sync), `rfpTool` (radius passed to `loadHistory`, filter narrows the table, bulk chunking, delete removes rows, twin offer), `rfpWorkbook` (annual sell, summary sheet).
- Browser checks (plan's last task, PostProduc): sticky panel while scrolling 200 lanes; inline edit keyboard flow; median-to-all with skipped/overwrite; bulk carrier on three selected lanes; delete selected; radius 150 km stamp; and the four 3b checks that were never done (Lane Benchmark "Bids only" filter, bid and manual pricing paths, existing-carrier bid, opening the exported workbook).

## 10. Delivery

- Branch off `main`; commits without any AI attribution trailer; PRs in both repos (`origin` personal, `tplm` work), merged only on `origin`, `main` then pushed to `tplm`.
- Deploy: full-manifest `-l NoTestRun` first (new field, permission set, classes), then `-l RunSpecifiedTests -t <22 classes>`; foreground only, `sf project deploy report -o sandbox --use-most-recent -w 10` to poll.
- Every new LWC bundle (`rfpLaneFilter`, `rfpBulk`, `rfpBulkBar`, and `rfpToolbar` if created) and every new class and field is registered in `manifest/package.xml` in the same task that creates it.
- Docs: README `## RFP Tool` section gains the 3c behaviours and limits; roadmap phase 3 row reads "Done 2026-09-11 (3a objects and bids; 3b workbench; 3c pricing)"; this spec gets an `## Outcome — 3c` section; memory file updated.

## 11. Out of scope

Deleting whole projects; cross-currency costing; bulk edit of notes, mode or equipment; per-lane radius; undo of bulk actions (the export before a bulk run is the backup); twin detection at import time; any change to `Lane_Benchmark_User`.

## 12. Rulings

- R24 `Sell_Source__c` null reads as `Margin`.
- R25 A derived margin may be negative and is shown in red; a typed margin stays 0..100.
- R26 `applyBid` skips lanes in another currency rather than costing them (R19 stands).
- R27 `copyPricing` copies the bid reference verbatim: the twin points at the source lane's bid.
- R28 Delete is two-click in the bar, Selected scope only, and takes the lanes' bids with them.
- R29 The radius box is always visible because the CITY fallback uses it.
- R30 The 200-id cap is per call; the client chunks, the server refuses more.

## Outcome — 3c (2026-09-12)

Branch `phase-3c/pricing-workbench` (off `main` at `adccb61`). Setup commits
`e0bd9eb` (this design), `8c7bc44` (the plan), `1aba5a2` (plan fixture and
helper names); task commits `062aa1f..c009537` (17 commits: `062aa1f`,
`3029958`, `98e6e2d`, `06daebe`, `fe4d75f`, `b0fadba`, `2a5ef7a`, `5c2f8b1`,
`1d0f02e`, `b0bcc41`, `aa217ca`, `ae7391b`, `11b2777`, `f82fcf8`, `6eb0575`,
`1f65b40`, `c009537`). This docs task (Task 13) lands on the same branch
after `c009537`. Every deploy below is to `sandbox`/PostProduc; ids and
counts are from the controller's ledger
(`.superpowers/sdd/2026-09-11-phase-3c-pricing-workbench/progress.md`)
except Task 13's, which are from the commands run for this task.

**Deploys and tests.**

| Task                                                            | Deploy id(s)                                                                                                       | What it proved                                                                                                               |
| --------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------- |
| 1 — `Sell_Source__c` field, `RFP_Tool_User` delete permission   | `0AfbZ00000CpW3lSAF`                                                                                               | Field and delete permissions deployed clean, 10/10 Apex tests                                                                |
| 2 — `RfpPricingMath` (Apex) and `c/marginMath` (JS)             | `0AfbZ00000CpWJtSAN`                                                                                               | Shared sell/margin math deployed, Apex 2/2, Jest 6/6                                                                         |
| 3 — radius precision and unit                                   | `0AfbZ00000CpWdFSAV`, `0AfbZ00000CpWgTSAV`; fix round `0AfbZ00000CpWi5SAF`                                         | Radius choice and the city-to-radius fallback deployed, Apex 8/8, Jest 200/200; the zero-radius-rounds-to-50 fix re-verified |
| 4 — `BenchmarkRateService.saveAll`                              | not logged in the ledger                                                                                           | `BenchmarkRateServiceTest` 9/9, PMD clean                                                                                    |
| 5 — `RfpBulkService` (median, pricing, copy, delete)            | `0AfbZ00000CpWzpSAF` (5/5); PMD restructuring `0AfbZ00000CpX4fSAF` (5/5); fix round `0AfbZ00000CpX9VSAV` (7/7)     | Bulk service deployed and re-verified through the PMD restructuring and the error-cap-across-DML-passes fix                  |
| 6 — `RfpBulkController` wrappers, delete permission             | `0AfbZ00000CpXW5SAN` (NoTestRun), `0AfbZ00000CpXXhSAN` (123/123); fix round `0AfbZ00000CpXZJSA3` (13/13)           | Bulk controller wrappers deployed; bid-deletion proof and the README "Apex tests" order fixed                                |
| 7 — pricing details, inline edit math, lane filter module       | — (LWC only)                                                                                                       | Jest 216/216, ESLint clean                                                                                                   |
| 8 — bulk runner module, bulk action bar                         | — (LWC only)                                                                                                       | Jest 230/230, ESLint clean                                                                                                   |
| 9 — lane selection, spreadsheet cells                           | — (LWC only)                                                                                                       | Jest 236/236, then 241/241 after the Enter-selects fix round                                                                 |
| 10 — pricing panel takes a sell price                           | — (LWC only)                                                                                                       | Jest 245/245, ESLint clean                                                                                                   |
| 11 — wire filters, selection, bulk actions, twins, sticky panel | `0AfbZ00000CpXnpSAF` (NoTestRun); fix round `0AfbZ00000CpXsfSAF`                                                   | Jest 250/250, then 258/258 after the doneIds-diff and unpriced-source-twin fixes                                             |
| 12 — export: annual sell, sell source, Summary sheet            | — (LWC only)                                                                                                       | Jest 13/13 in the two suites, ESLint clean                                                                                   |
| 13 — docs, final deploy with tests (this task)                  | `0AfbZ00000CpXvtSAF` (full-manifest NoTestRun); `0AfbZ00000CpXnqSAF` (full-manifest RunSpecifiedTests, 22 classes) | 241 components deployed, 0 errors; Apex 124/124 across the 22 classes; `npm test` 32 suites / 258 tests; PMD clean           |
| Final fix wave — class access, panel busy, rollback breadth     | `0AfbZ00000CpY7BSAV` (full-manifest NoTestRun); `0AfbZ00000CpY8nSAF` (full-manifest RunSpecifiedTests, 22 classes) | 241 components deployed, 0 errors; Apex 125/125 (the new class-access test included); Jest 32 suites / 260 tests; PMD clean  |

Final state: **Apex 124/124** tests across the 22-class `RunSpecifiedTests`
list (deploy `0AfbZ00000CpXnqSAF`), **Jest 32 suites / 258 tests**, **PMD
clean** with 0 violations at minimum priority 3, 0 component errors on both
final deploys.

**Rulings recorded during implementation** (ledger R31–R39, continuing the
numbering above; full text in the ledger):

- R31 (Task 3) — a radius that rounds to 0 (for example 0.4) now falls back
  to the 50 km/mi default instead of searching a zero-radius circle, the
  same fallback used for null or values at or below 0.
- R32 (Task 5) — the bulk error cap keeps a running failed total on
  `Context`, so the "… and N more" tail is correct when `collect` runs
  twice within one action instead of undercounting.
- R33 (Task 6) — the restricted-user `runAs` test has the admin create the
  project and lane and transfer `OwnerId` to the restricted user first,
  because a restricted user cannot insert a project referencing the
  admin's Account; the delete itself still runs inside `runAs`.
- R34 (Task 6) — `RfpBulkController`'s missing coverage was in its generic
  catch blocks, not in the wrapper methods; closed with a no-permission
  user test (`wrapsUnexpectedFailuresAsUserErrors`) rather than by calling
  every wrapper again.
- R35 (Task 6) — the security test's bid assertion was vacuous, because
  deleting a lane `SetNulls` the bid's `RFP_Lane__c` lookup rather than
  failing the bid; fixed to assert the bid is gone by Id with no errors
  returned.
- R36 (Task 9) — Enter on a focused cell now selects its row before
  opening it, so a click or a keyboard open emits exactly one select
  event; the cell also refocuses its `td` on close.
- R37 (Task 10) — the implementer's commit briefly carried a
  Co-Authored-By trailer against the user's standing no-trailer rule; the
  message was amended in place (content unchanged, a new SHA replacing
  `835f989`).
- R38 (Task 11) — `applyBulkResult`'s delete branch now diffs surviving
  lanes against `doneIds` (the ids of chunks that actually returned)
  instead of assuming every requested id is gone, so a failed or stopped
  delete chunk no longer hides lanes that still exist.
- R39 (Task 11) — `siblings()` no longer offers twins for an unpriced
  source lane; an unpriced source now returns no siblings.
- R40 (final fix wave) — `RFP_Tool_User` now grants class access to the
  four 3c classes (`RfpBulkController`, `RfpBulkService`,
  `RfpPricingInput`, `RfpPricingMath`), without which a user holding only
  that permission set hit "You do not have access to the Apex class named
  'RfpBulkController'" on every bulk action.
- R41 (final fix wave) — the lane panel takes a `busy` flag from the
  container and disables Save price during a chunked run, and a
  `pricingchange` that still arrives while busy now says "Wait for the
  current run to finish." on the banner instead of returning silently.
- R42 (final fix wave) — `applyBid`'s rollback catches `Exception` rather
  than only `DmlException`, so a non-DML failure between the bid save and
  the lane update also rolls the savepoint back.

**Known limits and deferred minors** (from the ledger's `minor (deferred)`
and `parked` lines, grouped by area).

Apex:

- Task 1: `Sell_Source__c` sits after `Sell__c` in the manifest and
  permission set, while the field files themselves sort `*_Source__c`
  fields before the base field (cosmetic, plan-mandated).
- Task 2: `marginFor`'s double rounding (divide at scale 8, then setScale 2) could theoretically differ from a direct rounding; unreachable with
  `Currency(16,2)` inputs.
- Task 3: `request()` re-narrows a unit string that is already
  normalised.
- Task 4: the `saveAll` order test would also pass a naive query-order
  return; the rate check is duplicated between `save` and `saveAll`; the
  class doc comment does not mention `saveAll`.
- Task 5: no test discriminates that `Selected_Bid__c` is cleared by
  `applyMedian`/`applyPricing`; `copyPricing` checks the source lane
  before the 200-id cap; error lines run to about 180 characters;
  `Context`'s doc comment is stale after the PMD move; `RfpBulkServiceTest`
  has no `runAs` coverage; the "sell above zero" message is untested.
- Task 5 (parked): `copyPricing` copies the source lane's
  `Selected_Bid__c` onto its twins verbatim; deleting the source lane then
  `SetNulls` the twin's bid while `Cost_Source__c` still reads `Bid`. Spec
  R27 chose the verbatim copy on purpose, so this stays a known limit
  rather than a fix.
- Task 6: the `strangerUser()` coverage test depends on the org's Standard
  User profile holding no RFP object permissions; a `saveAll` call is
  nested inside the `costFromBids` argument list; "No lane was updated"
  also covers a failed bid insert; `RfpPricingInput` is `with sharing`
  without doing any SOQL/DML of its own; the rollback only catches
  `DmlException`.

Lane table:

- Task 7: `pricingDetail` with a Manual sell source and a blank sell text
  yields a null Sell and Margin (guarded downstream by Task 10's
  `cannotSavePrice`); `equipmentOf` falls back to an empty string, so two
  equipment-less lanes could pair as siblings.
- Task 9: `viewRows` recomputes all 200 rows on every keystroke; `locked`
  does not close an editor that is already open; the header checkbox can
  drift for a tick if the parent defers echoing `selectedIds` (Task 11
  echoes it synchronously); minor `.cell` cursor and colour nits.

Container:

- Task 8: `runBulk`'s catch collapses a plain `Error`'s message down to "A
  chunk failed."; the singular `skippedNote` wording reads awkwardly.
- Task 11: a fully failed bulk run is only reported in the weak summary
  line; the panel has no locked/busy binding, so its edits can be
  silently dropped while a bulk run is in flight; a failed panel save on a
  lane the filter has hidden shows no error; scope "skipped" with no
  prior result is a dead click; `applyFilter` runs twice per render;
  `selectedId` is not cleared after deleting the open lane; several
  branches are untested (a second save on a pending lane, dismissing the
  twin offer, clearing `rowErrors`).

Export:

- Task 12: a legacy lane (a sell price with no `Sell_Source__c`) reading
  as "Margin" is untested; a lane with a sell price but no
  `CurrencyIsoCode` would key "Total annual sell (undefined)" in the
  Summary sheet (the org is multi-currency).

**Browser checks (controller, Chrome, PostProduc).** Not run by this task;
the controller runs them. Placeholder list, copied from the plan's Step 3:

1. Sticky panel: open a project with 60 or more lanes, scroll to the
   bottom, the panel is still visible and scrolls on its own. — pending
   (controller)
2. Inline edit: click a Cost cell, type, Enter opens the next row's Cost;
   Tab, Shift+Tab and Escape behave; a bad value shows red text and stays
   open. — pending (controller)
3. Panel sell: type a sell, margin follows; save; the table shows the
   "manual" tag. — pending (controller)
4. Bulk: Use median on All shows a summary and "Overwrite them"; Apply
   margin 18 on Selected (3 lanes); Add carrier rate on 3 selected lanes
   (bids appear in each lane's panel); Delete 2 selected lanes (two
   clicks). — pending (controller)
5. Radius 150 km plus Refresh history: hovering the History cell shows
   `RADIUS-150KM` for a fallback lane. — pending (controller)
6. Filters: Unpriced, then text "calg…"; select-all selects only the rows
   shown. — pending (controller)
7. Export opens in Excel/Numbers: three sheets, an Annual sell column,
   Summary totals. — pending (controller)
8. The four 3b leftovers below. — pending (controller)

The four 3b leftovers, still open from the 3b Outcome's "Not verified in
the browser" list:

1. The Lane Benchmark "Bids only" source filter. — pending (controller)
2. Pricing a lane from a bid, and pricing it from a manual cost. —
   pending (controller)
3. Recording a bid against an existing carrier Account. — pending
   (controller)
4. Opening the exported workbook in Excel. — pending (controller)
