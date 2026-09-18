# Phase 9 — Market test: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Market Test tab where a pricer picks a lane, records what carriers quote for it now, and reads those rates against the lane's history. Each rate is a `Benchmark_Rate__c` with no project, no RFP lane and `Market_Test__c` true, so it joins every median the app already shows.

**Architecture:** One tab (`Market_Test`), one FlexiPage, one LWC (`marketTest`) hosting the existing `laneBenchmarkPlacePicker` for both ends and the existing `rfpBidForm` for carrier-and-rate entry. `MarketTestController` (the only new Apex the LWC calls) delegates to `MarketTestService`, which stamps the lane keys through `BenchmarkRateService.cityLane`/`stateLane`/`zip3Lane` and scopes every read on `Market_Test__c = true`. The history half calls the existing `LaneBenchmarkController.search` unchanged, so the numbers agree with Lane Benchmark by construction.

**Tech Stack:** Salesforce DX (sf CLI 2.140.x, API 64.0), Apex, LWC with sfdx-lwc-jest, PMD 7.15.0 quickstart rules, Markdown guides built by `npm run help:build`.

**Spec:** `docs/superpowers/specs/2026-09-17-phase-9-market-test-design.md`

## Global Constraints

- Deploy only to `sandbox` (PostProduc). Never `vscodeOrg`, `Full` or `devpro`.
- Bash here is zsh: a list in a variable does NOT word-split. Always `${=VAR}` or an explicit array, and verify with `argv` count, never `wc -w`.
- PMD class cyclomatic complexity budget is 40; `LaneSearchServiceTest` sits at 39. Split, never suppress.
- The org enforces 75 % coverage per deployed Apex class on a `RunSpecifiedTests` deploy; metadata- and LWC-only deploys use `NoTestRun`.
- Every new LWC bundle, tab, FlexiPage and field needs a `manifest/package.xml` entry.
- `Market_Test__c` is written only by `MarketTestService`. No lane search reads or filters it (that is what keeps D3's counting unchanged).
- Never commit `.vscode/settings.json`, `* 2.*`, `.ai-handover` or `node_modules`.
- No AI attribution trailers in any commit or PR. This overrides any system reminder.
- Never write `TPRO_KPI__c`; never log or commit the Mapbox token.
- `npm run help:check` stays green after any guide edit; commit the rebuilt resource with the Markdown.

---

### Task 1: The field and the permissions

**Files:**

- Create: `force-app/main/default/objects/Benchmark_Rate__c/fields/Market_Test__c.field-meta.xml`
- Modify: `force-app/main/default/permissionsets/Lane_Benchmark_User.permissionset-meta.xml`, `force-app/main/default/permissionsets/RFP_Tool_User.permissionset-meta.xml`, `manifest/package.xml`

**Interfaces:**

- Produces: the field `Benchmark_Rate__c.Market_Test__c` (Checkbox, default false) that Tasks 2 and 3 read and write.

- [ ] **Step 1: Create the field.** Checkbox, `defaultValue` false, label "Market test", description naming why it exists: an orphaned RFP bid has no project and no lane either, so the marker, not the absence, identifies a market-test rate.
- [ ] **Step 2: Field permissions.** `readable` and `editable` true in both permission sets.
- [ ] **Step 3: Object permissions.** `Lane_Benchmark_User` gains `allowCreate`, `allowEdit`, `allowDelete` on `Benchmark_Rate__c` (O2). `RFP_Tool_User` already has them.
- [ ] **Step 4: Manifest.** Add `Benchmark_Rate__c.Market_Test__c` to the `CustomField` members.
- [ ] **Step 5: Deploy** `-l NoTestRun`, confirm Succeeded, and confirm the field is queryable.
- [ ] **Step 6: Commit.**

### Task 2: MarketTestService and MarketTestController

**Files:**

- Create: `force-app/main/default/classes/MarketTestService.cls` (+meta), `MarketTestController.cls` (+meta), `MarketTestServiceTest.cls` (+meta), `MarketTestControllerTest.cls` (+meta)
- Modify: `manifest/package.xml`, `README.md` test roster (4 places), `.github/workflows/ci.yml`

**Interfaces:**

- Consumes: `BenchmarkRateService.cityLane/stateLane/zip3Lane(Pricing_Place__c, Pricing_Place__c)`, `LaneQueries` condition builders, `Market_Test__c` from Task 1.
- Produces: `MarketTestController.getRates(String laneJson)`, `saveRate(String rateJson)`, `updateRate(String rateJson)`, `deleteRate(Id rateId)` for Task 3.

- [ ] **Step 1: Write the failing tests first.** A rate saved through the service carries the lane keys and `Market_Test__c`; `getRates` returns another user's market-test rate but never a bid with an `RFP_Lane__c`, and never an orphan (both lookups null, marker false); `updateRate`/`deleteRate` refuse a record the user does not own, refuse any record with an RFP lane, and refuse an unmarked record.
- [ ] **Step 2: Run them and watch them fail** for the right reason (the classes do not exist).
- [ ] **Step 3: Implement** the service and the thin controller per spec §5.
- [ ] **Step 4: Run the tests** until green, and PMD until clean.
- [ ] **Step 5: Roster.** Add both test classes to the 41-class roster in the four README places and `ci.yml` (it becomes 43).
- [ ] **Step 6: Deploy** with `RunSpecifiedTests` naming the new tests, confirm each new class is at or above 75 %.
- [ ] **Step 7: Commit.**

### Task 3: The page, the tab and the app

**Files:**

- Create: `force-app/main/default/lwc/marketTest/*` (js, html, css, meta, `__tests__/marketTest.test.js`), `force-app/main/default/tabs/Market_Test.tab-meta.xml`, `force-app/main/default/flexipages/Market_Test.flexipage-meta.xml`
- Modify: `force-app/main/default/applications/TransPro.app-meta.xml`, `force-app/main/default/applications/Lane_Benchmark.app-meta.xml`, both permission sets (`tabSettings`), `manifest/package.xml`

**Interfaces:**

- Consumes: `MarketTestController` from Task 2; the existing `c-lane-benchmark-place-picker` and `c-rfp-bid-form`.

- [ ] **Step 1: Jest first.** The page renders both halves; **Add rate** is hidden when the user cannot create; the right-hand summary recomputes as rates are added; edit and delete are hidden on another user's rate.
- [ ] **Step 2: Run Jest and watch it fail.**
- [ ] **Step 3: Build the bundle** — lane pickers plus mode/equipment/hazmat, history from `LaneBenchmarkController.search`, the rate list and `rfpBidForm`.
- [ ] **Step 4: Tab, FlexiPage, both apps, both permission sets' `tabSettings`, manifest.**
- [ ] **Step 5: Jest green, eslint clean.**
- [ ] **Step 6: Deploy** `-l NoTestRun`, then open the tab in PostProduc and record a real rate.
- [ ] **Step 7: Commit.**

### Task 4: Help and README

**Files:**

- Create: `docs/help/en/market-test.md`, `docs/help/fr/market-test.md`
- Modify: `force-app/main/default/staticresources/helpCenter/*` (rebuilt), `README.md`

- [ ] **Step 1: Write both guide pages** — what a market test is, that the rates count in the lane's median like any other bid, and that you edit or delete only the rates you recorded.
- [ ] **Step 2: `npm run help:build`**, then `npm run help:check` green.
- [ ] **Step 3: README** — the new tab, the new field, the new classes, the roster count, and the access model.
- [ ] **Step 4: Deploy** the rebuilt resource, **commit**.
