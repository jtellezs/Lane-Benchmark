# Phase 3c — Pricing Workbench Implementation Plan

> Executed 2026-09-11/12. Task 1 (`Sell_Source__c` field, delete
> permission): final commit `062aa1f`. Task 2 (shared sell/margin math):
> final commit `3029958`. Task 3 (radius precision and unit): final commit
> `06daebe`. Task 4 (`BenchmarkRateService.saveAll`): final commit
> `fe4d75f`. Task 5 (`RfpBulkService`): final commit `2a5ef7a`. Task 6
> (`RfpBulkController`, delete permission): final commit `1d0f02e`. Task 7
> (pricing details, inline edit math, lane filter): final commit
> `b0bcc41`. Task 8 (bulk runner, bulk action bar): final commit
> `aa217ca`. Task 9 (lane selection, spreadsheet cells): final commit
> `11b2777`. Task 10 (panel sell price): final commit `f82fcf8`. Task 11
> (wire filters, selection, bulk, twins, sticky panel): final commit
> `c009537`. Task 12 (export annual sell, sell source, Summary sheet):
> final commit `1f65b40`. Task 13 (docs, final deploy with tests): this
> commit. Final fix wave (R40–R42): `e19f3a3`. Rulings
> made during execution are recorded in the spec's `## Outcome — 3c`
> section, not repeated here.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a pricer price 200 RFP lanes fast: linked sell/margin, a chosen history radius, bulk apply (median, margin, cost, sell, carrier rate, delete, copy to twins), spreadsheet-style inline editing, a sticky pricing panel, filters, and a richer export.

**Architecture:** One new `RFP_Lane__c.Sell_Source__c` field records whether the margin or the sell drives a lane. Shared pricing math lives in `RfpPricingMath` (Apex) and `c/marginMath` (JS). Many-lane actions run server-side in `RfpBulkService` behind thin `RfpBulkController` wrappers, 200 lanes per call, user mode, and the client chunks through `c/rfpBulk`. The lane table edits one cell at a time; filters, twin detection and export additions are pure modules.

**Tech Stack:** Salesforce DX (sf CLI 2.140.x, API 64.0), Apex user mode, LWC, Jest (`@salesforce/sfdx-lwc-jest`), ESLint 9, Prettier + Husky, PMD 7.15.0.

**Spec:** `docs/superpowers/specs/2026-09-11-phase-3c-pricing-workbench-design.md`

## Global Constraints

- Org: deploy, test and check ONLY in PostProduc, sf alias `sandbox` (user `ienescu@trans-pro.com.postproduc`). Never `vscodeOrg`, `Full`, `devpro`.
- Git: branch `phase-3c/pricing-workbench` (already exists, off `main`). Commit messages carry NO trailer of any kind (no `Co-Authored-By`, no "Generated with"). Never `--no-verify`. Never commit `.vscode/settings.json`.
- Deploys run in the foreground with Bash `timeout: 600000`; poll with `sf project deploy report -o sandbox --use-most-recent -w 10`. A deploy that adds a field, permission set change or class goes as full manifest `-l NoTestRun` first; tests run afterwards.
- RunSpecifiedTests list (22 classes, keep this exact order everywhere it is mirrored: `.github/workflows/ci.yml`, README "Apex tests" row, README `sf apex run test` and `sf project deploy start` commands): `PricingDepartmentControllerTest PlaceNormalizerTest PricingTestDataFactoryTest PlaceBuilderBatchTest LaneSearchServiceTest MapboxGeocoderTest LaneBenchmarkControllerTest LaneBenchmarkPlaceServiceTest RfpTestDataFactoryTest BenchmarkRateServiceTest BidSearchQueryBuilderTest BidSearchServiceTest RfpControllerTest RfpSecurityTest RfpImportServiceTest RfpLaneControllerTest RfpHistoryServiceTest RfpProjectControllerTest RfpBidControllerTest RfpPricingMathTest RfpBulkServiceTest RfpBulkControllerTest`. Every class needs ≥ 75 % coverage under RunSpecifiedTests.
- Apex: `public with sharing`; every SOQL `WITH USER_MODE` or `Database.queryWithBinds(..., AccessLevel.USER_MODE)`; every DML `Security.stripInaccessible` + `AccessLevel.USER_MODE`; user-facing errors through `RfpUserError.of(...)`; `LaneSearchException` for validation inside services. Never write `TPRO_KPI__c`. No secrets in git or logs.
- PMD: `/private/tmp/pmd_install/pmd-bin-7.15.0/bin/pmd check --dir force-app --rulesets config/pmd-ruleset.xml --minimum-priority 3 --format text --fail-on-violation` must pass. Method cyclomatic ≤ 10, class ≤ 40; split, never suppress (the only existing suppression is `BenchmarkRateService.loadLanes`).
- ESLint: `npx eslint force-app` clean; the only allowed `eslint-disable` is `setTimeout` with a reason. No `await` in loops (use `series` from `c/rfpBatch`).
- Jest: `npm test` (all suites) green at the end of every task. `npx prettier --check` is enforced by the pre-commit hook.
- Every new LWC bundle, Apex class and custom field is added to `manifest/package.xml` in the task that creates it (a missing entry silently never deploys).
- Pricing math: two decimals, half up; sell = cost × (1 + margin/100); margin = (sell/cost − 1) × 100; typed margin 0..100; typed cost and sell > 0; derived margin may be negative; `Sell_Source__c` null means `Margin`.
- Copy: field labels and button text exactly as written in the tasks. Money is shown with two decimals and no grouping.
- Export must keep formula-injection neutralisation (typed string cells; never prefix an apostrophe).

---

## File map

| File                                                                                       | Responsibility                                                                                                 |
| ------------------------------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------- |
| `force-app/main/default/objects/RFP_Lane__c/fields/Sell_Source__c.field-meta.xml` (new)    | Margin / Manual picklist                                                                                       |
| `scripts/metadata/gen_rfp_fields.py`                                                       | one new `picklist(...)` line (record of the field)                                                             |
| `force-app/main/default/permissionsets/RFP_Tool_User.permissionset-meta.xml`               | delete on lanes and bids; FLS for the new field                                                                |
| `force-app/main/default/classes/RfpPricingMath.cls` (+Test) (new)                          | sellFor / marginFor / recompute                                                                                |
| `force-app/main/default/classes/RfpHistoryService.cls`, `RfpHistoryController.cls` (+Test) | radius + unit parameters, `RADIUS-<n><unit>` stamp                                                             |
| `force-app/main/default/classes/BenchmarkRateService.cls` (+Test)                          | `saveAll`                                                                                                      |
| `force-app/main/default/classes/RfpBulkService.cls` (+Test) (new)                          | applyMedian / applyPricing / applyBid / copyPricing / deleteLanes                                              |
| `force-app/main/default/classes/RfpBulkController.cls` (+Test) (new)                       | `@AuraEnabled` wrappers                                                                                        |
| `force-app/main/default/classes/RfpLaneController.cls` (+Test)                             | `Sell_Source__c` in `LANE_FIELDS` and the save whitelist                                                       |
| `force-app/main/default/classes/RfpSecurityTest.cls`                                       | restricted user can delete lanes                                                                               |
| `force-app/main/default/lwc/marginMath/`                                                   | `marginFor`                                                                                                    |
| `force-app/main/default/lwc/rfpPricing/`                                                   | `parseMoney`, `parseRadius`, `pricingDetail` with sell source, `inlineEdit`, `recompute`, `pricingFingerprint` |
| `force-app/main/default/lwc/rfpLaneFilter/` (new)                                          | `STATUS_FILTERS`, `applyFilter`, `siblings`                                                                    |
| `force-app/main/default/lwc/rfpBulk/` (new)                                                | `runBulk`, `applyBulkResult`, `summaryText`                                                                    |
| `force-app/main/default/lwc/rfpBulkBar/` (new)                                             | scope toggle + bulk actions UI                                                                                 |
| `force-app/main/default/lwc/rfpLaneTable/`                                                 | checkboxes, inline cells, pending/error marks                                                                  |
| `force-app/main/default/lwc/rfpLanePanel/`                                                 | sell input, link direction, fingerprint re-sync                                                                |
| `force-app/main/default/lwc/rfpTool/`                                                      | radius inputs, filter bar, bulk bar, selection, pending, twin offer, sticky CSS                                |
| `force-app/main/default/lwc/rfpWorkbook/`, `rfpExport/`                                    | Annual sell, Sell source, Summary sheet                                                                        |
| `manifest/package.xml`, `.github/workflows/ci.yml`, `README.md`, roadmap, spec Outcome     | registration and docs                                                                                          |

---

### Task 1: `Sell_Source__c` field, permissions, lane controller whitelist

**Files:**

- Create: `force-app/main/default/objects/RFP_Lane__c/fields/Sell_Source__c.field-meta.xml`
- Modify: `scripts/metadata/gen_rfp_fields.py` (after the `percent(L, "Margin__c", ...)` line, ~143)
- Modify: `force-app/main/default/permissionsets/RFP_Tool_User.permissionset-meta.xml` (objectPermissions for `RFP_Lane__c` and `Benchmark_Rate__c`, ~lines 72–89; add one fieldPermissions block next to `RFP_Lane__c.Sell__c`, ~line 353)
- Modify: `manifest/package.xml` (CustomField members, next to `RFP_Lane__c.Sell__c`, ~line 242)
- Modify: `force-app/main/default/classes/RfpLaneController.cls` (`LANE_FIELDS`, `saveLanePricing`)
- Test: `force-app/main/default/classes/RfpLaneControllerTest.cls`

**Interfaces:**

- Produces: `RFP_Lane__c.Sell_Source__c` (picklist `Margin` default | `Manual`), readable/editable by `RFP_Tool_User`; `RFP_Tool_User` may delete `RFP_Lane__c` and `Benchmark_Rate__c`; `RfpLaneController.saveLanePricing` accepts and returns `Sell_Source__c`; `RfpLaneController.lanesByIds` / `getLanes` return `Sell_Source__c`.

- [ ] **Step 1: Add the field to the generator and write the metadata**

Add after the `percent(L, "Margin__c", "Margin %")` line in `scripts/metadata/gen_rfp_fields.py`:

```python
picklist(L, "Sell_Source__c", "Sell source", ["Margin", "Manual"])
```

Then run `python3 scripts/metadata/gen_rfp_fields.py` and check `git status --short`: the only changes must be the script and the new file `force-app/main/default/objects/RFP_Lane__c/fields/Sell_Source__c.field-meta.xml`. If the generator touched any other field file, run `git checkout -- force-app/main/default/objects` and write the new file by hand with exactly this content:

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Sell_Source__c</fullName>
    <label>Sell source</label>
    <type>Picklist</type>
    <required>false</required>
    <valueSet>
        <restricted>true</restricted>
        <valueSetDefinition>
            <sorted>false</sorted>
            <value><fullName>Margin</fullName><default>true</default><label
        >Margin</label></value>
            <value><fullName>Manual</fullName><default>false</default><label
        >Manual</label></value>
        </valueSetDefinition>
    </valueSet>
</CustomField>
```

- [ ] **Step 2: Permission set and manifest**

In `RFP_Tool_User.permissionset-meta.xml` change `<allowDelete>false</allowDelete>` to `true` inside the two `objectPermissions` blocks whose `<object>` is `RFP_Lane__c` and `Benchmark_Rate__c` (leave `RFP_Project__c` and every other object alone). Add, right after the `RFP_Lane__c.Sell__c` fieldPermissions block:

```xml
<fieldPermissions>
        <editable>true</editable>
        <field>RFP_Lane__c.Sell_Source__c</field>
        <readable>true</readable>
    </fieldPermissions>
```

In `manifest/package.xml` add `        <members>RFP_Lane__c.Sell_Source__c</members>` right after `        <members>RFP_Lane__c.Sell__c</members>`.

- [ ] **Step 3: Failing Apex test**

Add to `RfpLaneControllerTest.cls`:

```apex
  @IsTest
  static void saveLanePricingRoundTripsSellSource() {
    Fx f = fx();
    String laneJson =
      '{"Id":"' +
      f.lane.Id +
      '","Cost__c":1000,"Cost_Source__c":"Manual","Margin__c":50,"Sell__c":1500,"Sell_Source__c":"Manual"}';
    RFP_Lane__c out = RfpLaneController.saveLanePricing(laneJson);
    System.assertEquals('Manual', out.Sell_Source__c);
    System.assertEquals(
      'Manual',
      [SELECT Sell_Source__c FROM RFP_Lane__c WHERE Id = :f.lane.Id]
      .Sell_Source__c
    );
    System.assertEquals(
      'Manual',
      RfpLaneController.getLanes(f.lane.RFP_Project__c)[0].Sell_Source__c
    );
  }
```

- [ ] **Step 4: Implement**

In `RfpLaneController.cls`, `LANE_FIELDS`: change `Margin__c, Sell__c, Notes__c, CurrencyIsoCode` to `Margin__c, Sell__c, Sell_Source__c, Notes__c, CurrencyIsoCode`. In `saveLanePricing` add `Sell_Source__c = posted.Sell_Source__c,` after `Sell__c = posted.Sell__c,`.

- [ ] **Step 5: Deploy (field first) and run the test**

```bash
sf project deploy start -x manifest/package.xml -o sandbox -l NoTestRun -w 30
sf apex run test -n RfpLaneControllerTest -n RfpSecurityTest -o sandbox -w 10 -r human
```

Expected: deploy Succeeded; both classes pass (the existing `saveLanePricingWhitelistsFields` still passes because a lane inserted without `Sell_Source__c` defaults to `Margin`).

- [ ] **Step 6: PMD, then commit**

```bash
/private/tmp/pmd_install/pmd-bin-7.15.0/bin/pmd check --dir force-app --rulesets config/pmd-ruleset.xml --minimum-priority 3 --format text --fail-on-violation
git add scripts/metadata/gen_rfp_fields.py force-app/main/default/objects/RFP_Lane__c/fields/Sell_Source__c.field-meta.xml force-app/main/default/permissionsets/RFP_Tool_User.permissionset-meta.xml manifest/package.xml force-app/main/default/classes/RfpLaneController.cls force-app/main/default/classes/RfpLaneControllerTest.cls
git commit -m "Add Sell_Source__c to RFP lanes and let RFP_Tool_User delete lanes and bids"
```

---

### Task 2: Shared pricing math (Apex + JS)

**Files:**

- Create: `force-app/main/default/classes/RfpPricingMath.cls`, `.cls-meta.xml`, `RfpPricingMathTest.cls`, `.cls-meta.xml`
- Modify: `manifest/package.xml` (ApexClass members, after `RfpBidControllerTest`)
- Modify: `force-app/main/default/lwc/marginMath/marginMath.js`
- Test: `force-app/main/default/lwc/marginMath/__tests__/marginMath.test.js`

**Interfaces:**

- Produces (Apex): `RfpPricingMath.sellFor(Decimal cost, Decimal marginPct) : Decimal`, `RfpPricingMath.marginFor(Decimal cost, Decimal sell) : Decimal`, `RfpPricingMath.recompute(RFP_Lane__c lane, Decimal defaultMargin) : void` (mutates `Margin__c`, `Sell__c`, `Sell_Source__c`).
- Produces (JS): `marginFor(cost, sell)` from `c/marginMath` (next to the existing `parseMargin`, `suggestedSell`).

- [ ] **Step 1: Failing Apex test**

`RfpPricingMathTest.cls` (meta xml: copy `RfpUserError.cls-meta.xml`, API 64.0):

```apex
@IsTest
private class RfpPricingMathTest {
  @IsTest
  static void sellAndMarginRoundHalfUpToCents() {
    System.assertEquals(1419.74, RfpPricingMath.sellFor(1234.56, 15));
    System.assertEquals(1150.00, RfpPricingMath.sellFor(1000, 15));
    System.assertEquals(null, RfpPricingMath.sellFor(0, 15));
    System.assertEquals(null, RfpPricingMath.sellFor(1000, null));
    System.assertEquals(15.00, RfpPricingMath.marginFor(1000, 1150));
    System.assertEquals(-10.00, RfpPricingMath.marginFor(1000, 900));
    System.assertEquals(0.33, RfpPricingMath.marginFor(3, 3.01));
    System.assertEquals(null, RfpPricingMath.marginFor(0, 100));
    System.assertEquals(null, RfpPricingMath.marginFor(1000, null));
    System.assertEquals(
      null,
      RfpPricingMath.marginFor(1, 100000),
      'does not fit Margin__c'
    );
  }

  @IsTest
  static void recomputeFollowsTheSellSource() {
    RFP_Lane__c byMargin = new RFP_Lane__c(Cost__c = 2000, Margin__c = 20);
    RfpPricingMath.recompute(byMargin, 15);
    System.assertEquals(2400.00, byMargin.Sell__c);
    System.assertEquals('Margin', byMargin.Sell_Source__c);

    RFP_Lane__c noMargin = new RFP_Lane__c(Cost__c = 2000);
    RfpPricingMath.recompute(noMargin, 15);
    System.assertEquals(15, noMargin.Margin__c, 'project default used');
    System.assertEquals(2300.00, noMargin.Sell__c);

    RFP_Lane__c manual = new RFP_Lane__c(
      Cost__c = 2000,
      Sell__c = 3000,
      Sell_Source__c = 'Manual',
      Margin__c = 15
    );
    RfpPricingMath.recompute(manual, 15);
    System.assertEquals(3000, manual.Sell__c, 'a typed sell never moves');
    System.assertEquals(50.00, manual.Margin__c);
    System.assertEquals('Manual', manual.Sell_Source__c);

    RFP_Lane__c manualNoSell = new RFP_Lane__c(
      Cost__c = 2000,
      Sell_Source__c = 'Manual',
      Margin__c = 10
    );
    RfpPricingMath.recompute(manualNoSell, 15);
    System.assertEquals(
      2200.00,
      manualNoSell.Sell__c,
      'no sell yet: margin drives'
    );
    System.assertEquals('Margin', manualNoSell.Sell_Source__c);
  }
}
```

- [ ] **Step 2: Implement `RfpPricingMath.cls`**

```apex
/**
 * The sell/margin arithmetic of the RFP workbench (spec §4.4). c/marginMath mirrors it on the
 * client; RfpPricingMathTest and marginMath.test.js assert the same value table.
 */
public with sharing class RfpPricingMath {
  /** Margin__c is Percent(5,2): anything beyond ±999.99 cannot be stored. */
  private static final Decimal MARGIN_LIMIT = 999.99;

  public static Decimal sellFor(Decimal cost, Decimal marginPct) {
    if (cost == null || cost <= 0 || marginPct == null) {
      return null;
    }
    return (cost * (1 + marginPct / 100)).setScale(2, RoundingMode.HALF_UP);
  }

  public static Decimal marginFor(Decimal cost, Decimal sell) {
    if (cost == null || cost <= 0 || sell == null) {
      return null;
    }
    Decimal m = (sell.divide(cost, 8, RoundingMode.HALF_UP) - 1) * 100;
    m = m.setScale(2, RoundingMode.HALF_UP);
    return m.abs() > MARGIN_LIMIT ? null : m;
  }

  /**
   * After a cost change: a Manual sell stays and the margin follows it; otherwise the margin
   * (or the project default) stays and the sell follows it.
   */
  public static void recompute(RFP_Lane__c lane, Decimal defaultMargin) {
    if (lane.Sell_Source__c == 'Manual' && lane.Sell__c != null) {
      lane.Margin__c = marginFor(lane.Cost__c, lane.Sell__c);
      return;
    }
    Decimal margin = lane.Margin__c == null ? defaultMargin : lane.Margin__c;
    lane.Margin__c = margin;
    lane.Sell__c = sellFor(lane.Cost__c, margin);
    lane.Sell_Source__c = 'Margin';
  }
}
```

Add `<members>RfpPricingMath</members>` and `<members>RfpPricingMathTest</members>` after `<members>RfpBidControllerTest</members>` in the manifest.

- [ ] **Step 3: Deploy and run**

```bash
sf project deploy start -m ApexClass:RfpPricingMath -m ApexClass:RfpPricingMathTest -o sandbox -l RunSpecifiedTests -t RfpPricingMathTest -w 30
```

Expected: Succeeded, 2/2 tests.

- [ ] **Step 4: Failing Jest test**

Append to `marginMath.test.js`:

```js
import { marginFor } from "c/marginMath";

describe("marginFor", () => {
  it("mirrors RfpPricingMath.marginFor", () => {
    expect(marginFor(1000, 1150)).toBe(15);
    expect(marginFor(1000, 900)).toBe(-10);
    expect(marginFor(3, 3.01)).toBe(0.33);
    expect(marginFor(1000, 1000)).toBe(0);
  });
  it("returns null without a positive cost, without a sell, or beyond ±999.99", () => {
    expect(marginFor(0, 100)).toBeNull();
    expect(marginFor(null, 100)).toBeNull();
    expect(marginFor(1000, null)).toBeNull();
    expect(marginFor(1, 100000)).toBeNull();
  });
});
```

(Merge the import into the existing first import line: `import { parseMargin, suggestedSell, marginFor } from "c/marginMath";`.) Also add to the existing `suggestedSell` test: `expect(suggestedSell(1234.56, 15)).toBe(1419.74);`.

- [ ] **Step 5: Implement in `marginMath.js`**

```js
/** Half-up on the absolute value, so -12.345 rounds to -12.35 like Apex HALF_UP. */
export function marginFor(cost, sell) {
  if (typeof cost !== "number" || !(cost > 0)) return null;
  if (typeof sell !== "number" || !Number.isFinite(sell)) return null;
  const raw = (sell / cost - 1) * 100;
  const rounded = Math.round(Math.abs(raw) * 100) / 100;
  const m = raw < 0 ? -rounded : rounded;
  if (Math.abs(m) > 999.99) return null;
  return m === 0 ? 0 : m;
}
```

- [ ] **Step 6: Test, lint, commit**

```bash
npx jest force-app/main/default/lwc/marginMath && npx eslint force-app/main/default/lwc/marginMath
git add force-app/main/default/classes/RfpPricingMath* force-app/main/default/lwc/marginMath manifest/package.xml
git commit -m "Add the shared sell/margin math in Apex and JS"
```

---

### Task 3: History radius (Apex, `c/rfpPricing`, `c/rfpTool` inputs)

**Files:**

- Modify: `force-app/main/default/classes/RfpHistoryService.cls`, `RfpHistoryController.cls`
- Modify: `force-app/main/default/classes/RfpHistoryServiceTest.cls` (every `run(` and `loadHistory(` call)
- Modify: `force-app/main/default/lwc/rfpPricing/rfpPricing.js` (+ test), `force-app/main/default/lwc/rfpTool/rfpTool.js`, `rfpTool.html` (+ test)

**Interfaces:**

- Produces: `RfpHistoryService.run(List<Id> laneIds, String precision, Integer lookbackDays, Decimal radius, String radiusUnit)`; `RfpHistoryController.loadHistory(List<Id> laneIds, String precision, Integer lookbackDays, Decimal radius, String radiusUnit)`; `Hist_Precision__c` = `RADIUS-<n>KM|MI`; `parseRadius(text) → { radius, unit } | null` in `c/rfpPricing`; `rfpTool` state `radius` (default 50) and `radiusUnit` (default `"KM"`), inputs `data-id="radius"` and `data-id="radius-unit"`.

- [ ] **Step 1: Update the Apex tests (failing until the signature exists)**

In `RfpHistoryServiceTest.cls`:

- Every `RfpHistoryService.run(<ids>, 'CITY', 90)` becomes `RfpHistoryService.run(<ids>, 'CITY', 90, null, null)`; every `RfpHistoryController.loadHistory(<ids>, 'CITY', 90)` becomes `RfpHistoryController.loadHistory(<ids>, 'CITY', 90, null, null)`. (The multi-line calls at lines ~57, ~146, ~187, ~232 too.)
- In `snapshotsCityFallsBackToRadiusAndFlagsUnresolved` change that one `run(...)` call to pass `120, 'KM'` instead of `null, null`, and change the expected precision of `nearby` from `'RADIUS-50KM'` to `'RADIUS-120KM'` with message `'fell back to the radius the run was given'`.
- Add:

```apex
  @IsTest
  static void radiusUsesTheGivenUnitAndRefusesMoreThan500() {
    PricingTestDataFactory.Graph g = PricingTestDataFactory.createGraph();
    Pricing_Place__c mtl = RfpTestDataFactory.createPlace('Montréal', 'QC', 'CA', 45.5019, -73.5674, 'H1A');
    Pricing_Place__c tor = RfpTestDataFactory.createPlace('Toronto', 'ON', 'CA', 43.6532, -79.3832, 'M5V');
    PricingDepartmentController.excludedContactIdsOverride = new Set<String>();
    RFP_Project__c p = RfpTestDataFactory.createProject(g.customer);
    RFP_Lane__c lane = RfpTestDataFactory.createLane(p, mtl, tor);
    rtms__Load__c load = PricingTestDataFactory.createLoad(g, g.originLocation, g.destinationLocation);
    insert PricingTestDataFactory.buildQuote(g, load, 1000);
    Test.startTest();
    List<RFP_Lane__c> out = RfpHistoryService.run(new List<Id>{ lane.Id }, 'RADIUS', 90, 75.4, 'MI');
    try {
      RfpHistoryService.run(new List<Id>{ lane.Id }, 'RADIUS', 90, 600, 'KM');
      System.assert(false, 'expected an exception');
    } catch (LaneSearchException e) {
      System.assert(e.getMessage().contains('500'), e.getMessage());
    }
    Test.stopTest();
    System.assertEquals('RADIUS-75MI', out[0].Hist_Precision__c, 'whole number, unit kept');
    System.assertEquals('Done', out[0].Hist_Status__c);
  }
```

(`PricingTestDataFactory.createLoad(g, g.originLocation, g.destinationLocation)` and `buildQuote(g, load, rate)` are the calls the first test in this file already uses.)

- [ ] **Step 2: Implement the service and controller**

`RfpHistoryService.cls`: delete `FALLBACK_RADIUS_KM`; add

```apex
  private static final Integer DEFAULT_RADIUS = 50;
  private static final Integer MAX_RADIUS = 500;
```

Replace `run`:

```apex
  public static List<RFP_Lane__c> run(
    List<Id> laneIds,
    String precision,
    Integer lookbackDays,
    Decimal radius,
    String radiusUnit
  ) {
    if (laneIds == null || laneIds.size() > MAX_LANES) {
      throw new LaneSearchException(
        'Load history for at most ' + MAX_LANES + ' lanes per call.'
      );
    }
    Integer days = lookbackDays == null || lookbackDays < 1 ? 90 : lookbackDays;
    Integer km = radiusOf(radius);
    String unit = radiusUnit == 'MI' ? 'MI' : 'KM';
    List<RFP_Lane__c> lanes = RfpLaneController.lanesByIds(laneIds);
    List<RFP_Lane__c> updates = new List<RFP_Lane__c>();
    for (RFP_Lane__c lane : lanes) {
      updates.add(snapshot(lane, precision, days, km, unit));
    }
    saveSnapshots(updates);
    return RfpLaneController.lanesByIds(laneIds);
  }

  /** Null or non-positive means the 50 km default; anything above 500 is refused, not clamped. */
  private static Integer radiusOf(Decimal radius) {
    if (radius == null || radius <= 0) {
      return DEFAULT_RADIUS;
    }
    if (radius > MAX_RADIUS) {
      throw new LaneSearchException('Radius must be between 1 and ' + MAX_RADIUS + '.');
    }
    return radius.round().intValue();
  }
```

`snapshot(RFP_Lane__c lane, String precision, Integer days, Integer radius, String unit)`: pass `radius, unit` into both `request(...)` calls and stamp `u.Hist_Precision__c = used == 'RADIUS' ? 'RADIUS-' + radius + unit : used;`. `request(RFP_Lane__c lane, String precision, Integer days, Integer radius, String unit)`: in the RADIUS branch `req.originRadius = radius; req.destinationRadius = radius; req.radiusUnit = unit == 'MI' ? LaneSearchRequest.Unit.MI : LaneSearchRequest.Unit.KM;`. Update the class doc comment's mention of 50 km.

`RfpHistoryController.loadHistory(List<Id> laneIds, String precision, Integer lookbackDays, Decimal radius, String radiusUnit)` forwards all five.

- [ ] **Step 3: Deploy and test**

```bash
sf project deploy start -m ApexClass:RfpHistoryService -m ApexClass:RfpHistoryController -m ApexClass:RfpHistoryServiceTest -o sandbox -l RunSpecifiedTests -t RfpHistoryServiceTest -w 30
```

Expected: Succeeded, all tests pass, `RADIUS-120KM` and `RADIUS-75MI` asserted.

- [ ] **Step 4: Failing Jest tests for `c/rfpPricing`**

Add to `rfpPricing.test.js`:

```js
import { parseRadius } from "c/rfpPricing";

describe("parseRadius", () => {
  it("reads the radius and unit out of the precision stamp", () => {
    expect(parseRadius("RADIUS-50KM")).toEqual({ radius: 50, unit: "KM" });
    expect(parseRadius("RADIUS-120MI")).toEqual({ radius: 120, unit: "MI" });
  });
  it("is null for city, province, blanks and junk", () => {
    expect(parseRadius("CITY")).toBeNull();
    expect(parseRadius("PROVINCE")).toBeNull();
    expect(parseRadius(null)).toBeNull();
    expect(parseRadius("RADIUS-KM")).toBeNull();
  });
});

describe("historyRequest with a stamped radius", () => {
  it("searches at the radius the snapshot used", () => {
    const req = JSON.parse(
      historyRequest({
        Origin_Place__r: { Key__c: "a" },
        Destination_Place__r: { Key__c: "b" },
        Hist_Precision__c: "RADIUS-150MI",
        Hist_Lookback_Days__c: 60
      })
    );
    expect(req.originPrecision).toBe("RADIUS");
    expect(req.originRadius).toBe(150);
    expect(req.destinationRadius).toBe(150);
    expect(req.radiusUnit).toBe("MI");
  });
});
```

(Merge imports with the file's existing `import { ... } from "c/rfpPricing"`.)

- [ ] **Step 5: Implement in `rfpPricing.js`**

```js
/** `RADIUS-<n><KM|MI>` as written by RfpHistoryService, else null. */
export function parseRadius(text) {
  const m = /^RADIUS-(\d+)(KM|MI)$/.exec(text || "");
  return m ? { radius: Number(m[1]), unit: m[2] } : null;
}

export function historyRequest(lane) {
  const r = parseRadius(lane.Hist_Precision__c);
  const precision = r ? "RADIUS" : lane.Hist_Precision__c || "CITY";
  return JSON.stringify({
    originKey: lane.Origin_Place__r?.Key__c,
    destinationKey: lane.Destination_Place__r?.Key__c,
    originPrecision: precision,
    destinationPrecision: precision,
    originRadius: r ? r.radius : null,
    destinationRadius: r ? r.radius : null,
    radiusUnit: r ? r.unit : "KM",
    lookbackDays: lane.Hist_Lookback_Days__c || 90,
    sourceFilter: "LOADS",
    rowLimit: 500,
    includeStopGeolocation: true
  });
}
```

- [ ] **Step 6: Failing Jest test for `c/rfpTool`**

Add to `rfpTool.test.js` (inside the existing describe, using its `mount`, `field`, `settle` helpers and the existing `getProject`/`getLanes`/`loadHistory` mocks the way the "runs history in chunks" test does):

```js
it("passes the radius and unit to every history chunk", async () => {
  loadHistory.mockImplementation(async ({ laneIds }) =>
    laneIds.map((Id) => ({ ...pendingLane(1), Id, Hist_Status__c: "Done" }))
  );
  const el = await openFromUrl(lanes(2));
  field(el, "radius").dispatchEvent(
    new CustomEvent("change", { detail: { value: "150" } })
  );
  field(el, "radius-unit").dispatchEvent(
    new CustomEvent("change", { detail: { value: "MI" } })
  );
  field(el, "load-history").click();
  await settle();
  expect(loadHistory).toHaveBeenCalledTimes(1);
  expect(loadHistory.mock.calls[0][0]).toMatchObject({
    precision: "CITY",
    lookbackDays: 90,
    radius: 150,
    radiusUnit: "MI"
  });
});
it("falls back to 50 km when the radius box is emptied", async () => {
  loadHistory.mockResolvedValue([]);
  const el = await openFromUrl(lanes(1));
  field(el, "radius").dispatchEvent(
    new CustomEvent("change", { detail: { value: "" } })
  );
  field(el, "load-history").click();
  await settle();
  expect(loadHistory.mock.calls[0][0].radius).toBe(50);
  expect(loadHistory.mock.calls[0][0].radiusUnit).toBe("KM");
});
```

`openFromUrl(laneList)`, `settle`, `field`, `lanes` and `pendingLane` already exist in this test file.

- [ ] **Step 7: Implement in `rfpTool`**

`rfpTool.js`: add constants and state

```js
const UNITS = [
  { label: "km", value: "KM" },
  { label: "mi", value: "MI" }
];
const DEFAULT_RADIUS = 50;
const MAX_RADIUS = 500;
```

```js
  radius = DEFAULT_RADIUS;
  radiusUnit = "KM";

  get unitOptions() {
    return UNITS;
  }
  handleRadius(event) {
    const n = Number(event.detail.value);
    this.radius =
      Number.isFinite(n) && n >= 1 && n <= MAX_RADIUS
        ? Math.round(n)
        : DEFAULT_RADIUS;
  }
  handleRadiusUnit(event) {
    this.radiusUnit = event.detail.value === "MI" ? "MI" : "KM";
  }
```

and in `historyChunk` pass `radius: this.radius, radiusUnit: this.radiusUnit` to `loadHistory`.

`rfpTool.html`, right after the `lookback` column:

```html
<div class="slds-col">
  <lightning-input
    data-id="radius"
    type="number"
    min="1"
    max="500"
    label="Radius"
    field-level-help="Used for Radius precision, and when a city has no history of its own."
    value="{radius}"
    onchange="{handleRadius}"
  ></lightning-input>
</div>
<div class="slds-col">
  <lightning-combobox
    data-id="radius-unit"
    label="Unit"
    value="{radiusUnit}"
    options="{unitOptions}"
    onchange="{handleRadiusUnit}"
  ></lightning-combobox>
</div>
```

- [ ] **Step 8: Test, lint, deploy LWC, commit**

```bash
npx jest force-app/main/default/lwc/rfpPricing force-app/main/default/lwc/rfpTool && npx eslint force-app/main/default/lwc
sf project deploy start -m LightningComponentBundle:rfpPricing -m LightningComponentBundle:rfpTool -o sandbox -l NoTestRun -w 30
git add force-app/main/default/classes/RfpHistory* force-app/main/default/lwc/rfpPricing force-app/main/default/lwc/rfpTool
git commit -m "Let the pricer choose the history radius and unit"
```

---

### Task 4: `BenchmarkRateService.saveAll`

**Files:**

- Modify: `force-app/main/default/classes/BenchmarkRateService.cls`
- Test: `force-app/main/default/classes/BenchmarkRateServiceTest.cls`

**Interfaces:**

- Produces: `BenchmarkRateService.saveAll(List<Benchmark_Rate__c> bids) : List<Benchmark_Rate__c>` — inserts all (all or none, user mode, stripInaccessible CREATABLE), returns reloaded bids in input order, throws `LaneSearchException('A bid needs a rate.')` if any rate is null.

- [ ] **Step 1: Failing test**

Add to `BenchmarkRateServiceTest.cls` (use the same fixture helpers the file already uses to get a project, two places and lanes; the factory call is `RfpTestDataFactory.createLane(project, origin, destination)` and `RfpTestDataFactory.buildBid(lane, rate)`):

```apex
  @IsTest
  static void saveAllInsertsEveryBidWithItsLaneKeys() {
    Fx f = fx();
    RFP_Lane__c a = f.lane;
    RFP_Lane__c b = RfpTestDataFactory.createLane(f.project, f.mtl, f.tor);
    List<Benchmark_Rate__c> saved = BenchmarkRateService.saveAll(
      new List<Benchmark_Rate__c>{
        RfpTestDataFactory.buildBid(a, 1000),
        RfpTestDataFactory.buildBid(b, 1100),
        RfpTestDataFactory.buildBid(a, 1200)
      }
    );
    System.assertEquals(3, saved.size());
    System.assertEquals(1000, saved[0].Rate__c, 'input order kept');
    System.assertEquals(1200, saved[2].Rate__c);
    System.assertEquals(a.Id, saved[2].RFP_Lane__c);
    System.assertEquals('Montréal, QC:Toronto, ON', saved[1].City_Lane__c, 'trigger stamped');
    try {
      BenchmarkRateService.saveAll(
        new List<Benchmark_Rate__c>{ new Benchmark_Rate__c(RFP_Lane__c = a.Id) }
      );
      System.assert(false, 'expected an exception');
    } catch (LaneSearchException e) {
      System.assert(e.getMessage().contains('rate'), e.getMessage());
    }
  }
```

- [ ] **Step 2: Implement**

Add to `BenchmarkRateService.cls`:

```apex
  /** save() for a list: one user-mode insert, all or none, reloaded in input order. */
  public static List<Benchmark_Rate__c> saveAll(List<Benchmark_Rate__c> bids) {
    for (Benchmark_Rate__c bid : bids) {
      if (bid.Rate__c == null) {
        throw new LaneSearchException('A bid needs a rate.');
      }
    }
    List<Benchmark_Rate__c> clean = Security.stripInaccessible(
        AccessType.CREATABLE,
        bids
      )
      .getRecords();
    Database.insert(clean, AccessLevel.USER_MODE);
    List<Id> ids = new List<Id>();
    for (Benchmark_Rate__c bid : clean) {
      ids.add(bid.Id);
    }
    Map<Id, Benchmark_Rate__c> byId = new Map<Id, Benchmark_Rate__c>(
      reloadAll(ids)
    );
    List<Benchmark_Rate__c> ordered = new List<Benchmark_Rate__c>();
    for (Id bidId : ids) {
      ordered.add(byId.get(bidId));
    }
    return ordered;
  }
```

Change `reload(Id bidId)` to `return reloadAll(new List<Id>{ bidId })[0];` and turn its query into `reloadAll(List<Id> bidIds)` with `WHERE Id IN :bidIds WITH USER_MODE` (same field list).

- [ ] **Step 3: Deploy, test, PMD, commit**

```bash
sf project deploy start -m ApexClass:BenchmarkRateService -m ApexClass:BenchmarkRateServiceTest -o sandbox -l RunSpecifiedTests -t BenchmarkRateServiceTest -w 30
/private/tmp/pmd_install/pmd-bin-7.15.0/bin/pmd check --dir force-app --rulesets config/pmd-ruleset.xml --minimum-priority 3 --format text --fail-on-violation
git add force-app/main/default/classes/BenchmarkRateService*
git commit -m "Add BenchmarkRateService.saveAll for one-insert bulk bids"
```

---

### Task 5: `RfpBulkService` — median, pricing, copy, delete

**Files:**

- Create: `force-app/main/default/classes/RfpBulkService.cls` (+meta), `RfpBulkServiceTest.cls` (+meta)
- Modify: `manifest/package.xml` (after `RfpPricingMathTest`)

**Interfaces:**

- Consumes: `RfpPricingMath.recompute/sellFor/marginFor` (Task 2), `RfpLaneController.lanesByIds(List<Id>)`.
- Produces: `RfpBulkService.MAX_LANES = 200`; `RfpBulkService.Result { lanes, updated, skipped, skippedIds, errors }` (all `@AuraEnabled`); `applyMedian(List<Id>, Boolean overwrite)`, `applyPricing(List<Id>, Decimal cost, Decimal sell, Decimal margin)`, `copyPricing(Id sourceLaneId, List<Id>)`, `deleteLanes(List<Id>)`, each returning `Result`; validation failures throw `LaneSearchException`. Task 6 adds `applyBid` to this same class and uses its private helpers `load`, `skip`, `pricingCopy`, `save(Context, Boolean allOrNone)`, `Context.defaultMarginFor(lane)`.

- [ ] **Step 1: Failing tests**

`RfpBulkServiceTest.cls`:

```apex
@IsTest
private class RfpBulkServiceTest {
  private class Fx {
    RFP_Project__c p;
    RFP_Lane__c a;
    RFP_Lane__c b;
    RFP_Lane__c c;
  }

  /** Three Montréal→Toronto lanes: a (median 2000, uncosted), b (median 2500, manual cost 1800), c (no median). */
  private static Fx fx() {
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
    Fx f = new Fx();
    f.p = RfpTestDataFactory.createProject(g.customer);
    f.a = RfpTestDataFactory.createLane(f.p, mtl, tor);
    f.b = RfpTestDataFactory.createLane(f.p, mtl, tor);
    f.c = RfpTestDataFactory.createLane(f.p, mtl, tor);
    update new List<RFP_Lane__c>{
      new RFP_Lane__c(
        Id = f.a.Id,
        Hist_Median__c = 2000,
        Hist_Status__c = 'Done'
      ),
      new RFP_Lane__c(
        Id = f.b.Id,
        Hist_Median__c = 2500,
        Hist_Status__c = 'Done',
        Cost__c = 1800,
        Cost_Source__c = 'Manual',
        Sell__c = 2070
      )
    };
    return f;
  }

  private static RFP_Lane__c fetch(Id laneId) {
    return [
      SELECT
        Cost__c,
        Cost_Source__c,
        Selected_Bid__c,
        Margin__c,
        Sell__c,
        Sell_Source__c
      FROM RFP_Lane__c
      WHERE Id = :laneId
    ];
  }

  @IsTest
  static void applyMedianSkipsCostedLanesUnlessOverwrite() {
    Fx f = fx();
    List<Id> ids = new List<Id>{ f.a.Id, f.b.Id, f.c.Id };
    RfpBulkService.Result r = RfpBulkService.applyMedian(ids, false);
    System.assertEquals(1, r.updated);
    System.assertEquals(2, r.skipped);
    System.assert(r.skippedIds.contains(f.b.Id), 'costed manually');
    System.assert(r.skippedIds.contains(f.c.Id), 'no median');
    System.assertEquals(3, r.lanes.size(), 'refreshed lanes come back');
    RFP_Lane__c a = fetch(f.a.Id);
    System.assertEquals(2000, a.Cost__c);
    System.assertEquals('History median', a.Cost_Source__c);
    System.assertEquals(2300.00, a.Sell__c, 'lane margin 15 applied');
    System.assertEquals('Margin', a.Sell_Source__c);
    System.assertEquals(1800, fetch(f.b.Id).Cost__c, 'untouched');

    r = RfpBulkService.applyMedian(new List<Id>{ f.b.Id }, true);
    System.assertEquals(1, r.updated);
    System.assertEquals(2500, fetch(f.b.Id).Cost__c);
  }

  @IsTest
  static void applyPricingCostMarginAndSell() {
    Fx f = fx();
    List<Id> ids = new List<Id>{ f.a.Id, f.c.Id };
    RfpBulkService.applyPricing(ids, 1000, null, null);
    RFP_Lane__c a = fetch(f.a.Id);
    System.assertEquals(1000, a.Cost__c);
    System.assertEquals('Manual', a.Cost_Source__c);
    System.assertEquals(1150.00, a.Sell__c);

    RfpBulkService.applyPricing(ids, null, null, 20);
    a = fetch(f.a.Id);
    System.assertEquals(20, a.Margin__c);
    System.assertEquals(1200.00, a.Sell__c);
    System.assertEquals('Margin', a.Sell_Source__c);

    RfpBulkService.applyPricing(ids, null, 1500, null);
    a = fetch(f.a.Id);
    System.assertEquals(1500, a.Sell__c);
    System.assertEquals('Manual', a.Sell_Source__c);
    System.assertEquals(50.00, a.Margin__c, 'margin follows the typed sell');

    RfpBulkService.applyPricing(ids, 2000, null, null);
    a = fetch(f.a.Id);
    System.assertEquals(
      1500,
      a.Sell__c,
      'a manual sell survives a cost change'
    );
    System.assertEquals(-25.00, a.Margin__c);
  }

  @IsTest
  static void applyPricingValidates() {
    Fx f = fx();
    List<Id> ids = new List<Id>{ f.a.Id };
    assertRefused(ids, null, null, null, 'cost');
    assertRefused(ids, null, 100, 10, 'not both');
    assertRefused(ids, 0, null, null, 'zero');
    assertRefused(ids, null, null, 101, '100');
    List<Id> many = new List<Id>();
    for (Integer i = 0; i < 201; i++) {
      many.add(f.a.Id);
    }
    assertRefused(many, 100, null, null, '200');
  }

  private static void assertRefused(
    List<Id> ids,
    Decimal cost,
    Decimal sell,
    Decimal margin,
    String fragment
  ) {
    try {
      RfpBulkService.applyPricing(ids, cost, sell, margin);
      System.assert(false, 'expected a refusal for ' + fragment);
    } catch (LaneSearchException e) {
      System.assert(
        e.getMessage().containsIgnoreCase(fragment),
        e.getMessage()
      );
    }
  }

  @IsTest
  static void copyPricingCopiesTheSixPricingFields() {
    Fx f = fx();
    Benchmark_Rate__c bid = BenchmarkRateService.save(
      RfpTestDataFactory.buildBid(f.a, 1700)
    );
    update new RFP_Lane__c(
      Id = f.a.Id,
      Cost__c = 1700,
      Cost_Source__c = 'Bid',
      Selected_Bid__c = bid.Id,
      Margin__c = 10,
      Sell__c = 1870,
      Sell_Source__c = 'Margin'
    );
    RfpBulkService.Result r = RfpBulkService.copyPricing(
      f.a.Id,
      new List<Id>{ f.c.Id, f.a.Id }
    );
    System.assertEquals(1, r.updated, 'the source itself is not a target');
    RFP_Lane__c c = fetch(f.c.Id);
    System.assertEquals(1700, c.Cost__c);
    System.assertEquals('Bid', c.Cost_Source__c);
    System.assertEquals(bid.Id, c.Selected_Bid__c);
    System.assertEquals(10, c.Margin__c);
    System.assertEquals(1870, c.Sell__c);
    System.assertEquals('Margin', c.Sell_Source__c);
    update new RFP_Lane__c(Id = f.c.Id, Cost__c = null);
    try {
      RfpBulkService.copyPricing(f.c.Id, new List<Id>{ f.a.Id });
      System.assert(false, 'expected a refusal');
    } catch (LaneSearchException e) {
      System.assert(e.getMessage().contains('no cost'), e.getMessage());
    }
  }

  @IsTest
  static void deleteLanesTakesTheirBids() {
    Fx f = fx();
    BenchmarkRateService.save(RfpTestDataFactory.buildBid(f.a, 900));
    BenchmarkRateService.save(RfpTestDataFactory.buildBid(f.b, 950));
    RfpBulkService.Result r = RfpBulkService.deleteLanes(
      new List<Id>{ f.a.Id }
    );
    System.assertEquals(1, r.updated);
    System.assertEquals(0, r.lanes.size(), 'nothing left of the ids given');
    System.assertEquals(
      0,
      [SELECT COUNT() FROM Benchmark_Rate__c WHERE RFP_Lane__c = :f.a.Id]
    );
    System.assertEquals(
      1,
      [SELECT COUNT() FROM Benchmark_Rate__c WHERE RFP_Lane__c = :f.b.Id],
      'other lanes keep theirs'
    );
    System.assertEquals(
      2,
      [SELECT COUNT() FROM RFP_Lane__c WHERE RFP_Project__c = :f.p.Id]
    );
  }
}
```

- [ ] **Step 2: Implement `RfpBulkService.cls`**

```apex
/**
 * Many-lane pricing actions of the RFP workbench (spec §5.4): one call prices, copies or deletes
 * up to 200 lanes in user mode. Validation failures are LaneSearchExceptions (the controller turns
 * them into user errors); per-record DML failures land in Result.errors and never abort the rest.
 */
public with sharing class RfpBulkService {
  public static final Integer MAX_LANES = 200;
  private static final Integer MAX_ERRORS = 5;

  public class Result {
    @AuraEnabled
    public List<RFP_Lane__c> lanes = new List<RFP_Lane__c>();
    @AuraEnabled
    public Integer updated = 0;
    @AuraEnabled
    public Integer skipped = 0;
    @AuraEnabled
    public List<Id> skippedIds = new List<Id>();
    @AuraEnabled
    public List<String> errors = new List<String>();
  }

  /** Everything one action needs: the lanes as read, their projects' default margins, and what to write. */
  private class Context {
    List<Id> ids;
    List<RFP_Lane__c> lanes;
    Map<Id, Decimal> defaultMarginByProject = new Map<Id, Decimal>();
    List<RFP_Lane__c> updates = new List<RFP_Lane__c>();
    Result result = new Result();

    Decimal defaultMarginFor(RFP_Lane__c lane) {
      return defaultMarginByProject.get(lane.RFP_Project__c);
    }
  }

  public static Result applyMedian(List<Id> laneIds, Boolean overwrite) {
    Context c = load(laneIds);
    for (RFP_Lane__c lane : c.lanes) {
      Boolean costedElsewhere =
        lane.Cost__c != null &&
        lane.Cost_Source__c != 'History median';
      if (
        lane.Hist_Median__c == null || (costedElsewhere && overwrite != true)
      ) {
        skip(c, lane);
        continue;
      }
      RFP_Lane__c u = pricingCopy(lane);
      u.Cost__c = lane.Hist_Median__c;
      u.Cost_Source__c = 'History median';
      u.Selected_Bid__c = null;
      RfpPricingMath.recompute(u, c.defaultMarginFor(lane));
      c.updates.add(u);
    }
    return save(c, false);
  }

  public static Result applyPricing(
    List<Id> laneIds,
    Decimal cost,
    Decimal sell,
    Decimal margin
  ) {
    validatePricing(cost, sell, margin);
    Context c = load(laneIds);
    for (RFP_Lane__c lane : c.lanes) {
      RFP_Lane__c u = pricingCopy(lane);
      if (cost != null) {
        u.Cost__c = cost;
        u.Cost_Source__c = 'Manual';
        u.Selected_Bid__c = null;
        RfpPricingMath.recompute(u, c.defaultMarginFor(lane));
      }
      if (sell != null) {
        u.Sell__c = sell;
        u.Sell_Source__c = 'Manual';
        u.Margin__c = RfpPricingMath.marginFor(u.Cost__c, sell);
      }
      if (margin != null) {
        u.Margin__c = margin;
        u.Sell_Source__c = 'Margin';
        u.Sell__c = RfpPricingMath.sellFor(u.Cost__c, margin);
      }
      c.updates.add(u);
    }
    return save(c, false);
  }

  private static void validatePricing(
    Decimal cost,
    Decimal sell,
    Decimal margin
  ) {
    if (cost == null && sell == null && margin == null) {
      throw new LaneSearchException('Enter a cost, a sell or a margin.');
    }
    if (sell != null && margin != null) {
      throw new LaneSearchException('Enter a sell or a margin, not both.');
    }
    if (cost != null && cost <= 0) {
      throw new LaneSearchException('The cost must be above zero.');
    }
    if (sell != null && sell <= 0) {
      throw new LaneSearchException('The sell must be above zero.');
    }
    if (margin != null && (margin < 0 || margin > 100)) {
      throw new LaneSearchException('The margin must be between 0 and 100.');
    }
  }

  public static Result copyPricing(Id sourceLaneId, List<Id> laneIds) {
    List<RFP_Lane__c> sources = RfpLaneController.lanesByIds(
      new List<Id>{ sourceLaneId }
    );
    if (sources.isEmpty() || sources[0].Cost__c == null) {
      throw new LaneSearchException('The source lane has no cost to copy.');
    }
    RFP_Lane__c source = sources[0];
    Context c = load(laneIds);
    for (RFP_Lane__c lane : c.lanes) {
      if (lane.Id == source.Id) {
        continue;
      }
      RFP_Lane__c u = pricingCopy(source);
      u.Id = lane.Id;
      c.updates.add(u);
    }
    return save(c, false);
  }

  public static Result deleteLanes(List<Id> laneIds) {
    Context c = load(laneIds);
    List<Benchmark_Rate__c> bids = [
      SELECT Id
      FROM Benchmark_Rate__c
      WHERE RFP_Lane__c IN :c.ids
      WITH USER_MODE
    ];
    if (!bids.isEmpty()) {
      collect(c, Database.delete(bids, false, AccessLevel.USER_MODE), false);
    }
    collect(c, Database.delete(c.lanes, false, AccessLevel.USER_MODE), true);
    c.result.lanes = RfpLaneController.lanesByIds(c.ids);
    return c.result;
  }

  // ---- shared helpers (Task 6 reuses them for applyBid) ----

  private static Context load(List<Id> laneIds) {
    if (laneIds == null || laneIds.isEmpty() || laneIds.size() > MAX_LANES) {
      throw new LaneSearchException(
        'Apply to at most ' + MAX_LANES + ' lanes per call.'
      );
    }
    Context c = new Context();
    c.ids = new List<Id>(new Set<Id>(laneIds));
    c.lanes = RfpLaneController.lanesByIds(c.ids);
    Set<Id> projectIds = new Set<Id>();
    for (RFP_Lane__c lane : c.lanes) {
      projectIds.add(lane.RFP_Project__c);
    }
    for (RFP_Project__c p : [
      SELECT Id, Default_Margin__c
      FROM RFP_Project__c
      WHERE Id IN :projectIds
      WITH USER_MODE
    ]) {
      c.defaultMarginByProject.put(p.Id, p.Default_Margin__c);
    }
    return c;
  }

  private static void skip(Context c, RFP_Lane__c lane) {
    c.result.skipped++;
    c.result.skippedIds.add(lane.Id);
  }

  /** The six pricing fields as currently stored, so recompute() sees the lane's real state. */
  private static RFP_Lane__c pricingCopy(RFP_Lane__c lane) {
    return new RFP_Lane__c(
      Id = lane.Id,
      Cost__c = lane.Cost__c,
      Cost_Source__c = lane.Cost_Source__c,
      Selected_Bid__c = lane.Selected_Bid__c,
      Margin__c = lane.Margin__c,
      Sell__c = lane.Sell__c,
      Sell_Source__c = lane.Sell_Source__c
    );
  }

  /** Writes c.updates; allOrNone=true is for callers holding a Savepoint (applyBid). */
  private static Result save(Context c, Boolean allOrNone) {
    if (!c.updates.isEmpty()) {
      List<RFP_Lane__c> clean = Security.stripInaccessible(
          AccessType.UPDATABLE,
          c.updates
        )
        .getRecords();
      collect(
        c,
        Database.update(clean, allOrNone, AccessLevel.USER_MODE),
        true
      );
    }
    c.result.lanes = RfpLaneController.lanesByIds(c.ids);
    return c.result;
  }

  private static void collect(
    Context c,
    List<Database.SaveResult> results,
    Boolean count
  ) {
    Integer failed = 0;
    for (Database.SaveResult r : results) {
      if (r.isSuccess()) {
        if (count) {
          c.result.updated++;
        }
        continue;
      }
      failed++;
      if (c.result.errors.size() < MAX_ERRORS) {
        c.result.errors.add(
          r.getId() + ': ' + r.getErrors()[0].getMessage().left(160)
        );
      }
    }
    if (failed > MAX_ERRORS) {
      c.result.errors.add('… and ' + (failed - MAX_ERRORS) + ' more');
    }
  }

  private static void collect(
    Context c,
    List<Database.DeleteResult> results,
    Boolean count
  ) {
    Integer failed = 0;
    for (Database.DeleteResult r : results) {
      if (r.isSuccess()) {
        if (count) {
          c.result.updated++;
        }
        continue;
      }
      failed++;
      if (c.result.errors.size() < MAX_ERRORS) {
        c.result.errors.add(
          r.getId() + ': ' + r.getErrors()[0].getMessage().left(160)
        );
      }
    }
    if (failed > MAX_ERRORS) {
      c.result.errors.add('… and ' + (failed - MAX_ERRORS) + ' more');
    }
  }
}
```

If PMD flags the two `collect` overloads as duplicated logic, fold the shared tail into `private static void noteFailure(Context c, Id recordId, String message)` and a `finishErrors(Context c, Integer failed)`; keep the two overloads thin. Add `<members>RfpBulkService</members>` and `<members>RfpBulkServiceTest</members>` to the manifest after `RfpPricingMathTest`.

- [ ] **Step 3: Deploy, test, PMD, commit**

```bash
sf project deploy start -m ApexClass:RfpBulkService -m ApexClass:RfpBulkServiceTest -o sandbox -l RunSpecifiedTests -t RfpBulkServiceTest -w 30
/private/tmp/pmd_install/pmd-bin-7.15.0/bin/pmd check --dir force-app --rulesets config/pmd-ruleset.xml --minimum-priority 3 --format text --fail-on-violation
git add force-app/main/default/classes/RfpBulkService* manifest/package.xml
git commit -m "Add RfpBulkService: median, pricing, copy and delete for up to 200 lanes"
```

---

### Task 6: `applyBid`, `RfpBulkController`, security test, CI/README test list

**Files:**

- Modify: `force-app/main/default/classes/RfpBulkService.cls`, `RfpBulkServiceTest.cls`
- Create: `force-app/main/default/classes/RfpBulkController.cls` (+meta), `RfpBulkControllerTest.cls` (+meta)
- Modify: `force-app/main/default/classes/RfpSecurityTest.cls`, `manifest/package.xml`, `.github/workflows/ci.yml` (line ~58), `README.md` (line ~27 "Apex tests" row, ~101 `sf apex run test`, ~108 `sf project deploy start`)

**Interfaces:**

- Consumes: Task 5 helpers, `BenchmarkRateService.saveAll` (Task 4).
- Produces: `RfpBulkService.applyBid(List<Id> laneIds, String bidJson) : Result`; `RfpBulkController.applyMedian(List<Id> laneIds, Boolean overwrite)`, `applyPricing(List<Id> laneIds, Decimal cost, Decimal sell, Decimal margin)`, `applyBid(List<Id> laneIds, String bidJson)`, `copyPricing(Id sourceLaneId, List<Id> laneIds)`, `deleteLanes(List<Id> laneIds)` — all `@AuraEnabled`, returning `RfpBulkService.Result`, throwing `AuraHandledException` via `RfpUserError`.

- [ ] **Step 1: Failing tests**

Add to `RfpBulkServiceTest.cls`:

```apex
  @IsTest
  static void applyBidCreatesOneBidPerLaneAndSkipsOtherCurrencies() {
    Fx f = fx();
    update new RFP_Lane__c(Id = f.c.Id, CurrencyIsoCode = 'USD');
    String bidJson = '{"Carrier_Name__c":"Bulk Carrier","Contact_Name__c":"Sam","Rate__c":1200,"CurrencyIsoCode":"CAD","FSC_Included__c":true,"Transit_Days__c":2}';
    RfpBulkService.Result r = RfpBulkService.applyBid(new List<Id>{ f.a.Id, f.b.Id, f.c.Id }, bidJson);
    System.assertEquals(2, r.updated);
    System.assertEquals(1, r.skipped, 'USD lane skipped');
    System.assertEquals(f.c.Id, r.skippedIds[0]);
    List<Benchmark_Rate__c> bids = [SELECT RFP_Lane__c, City_Lane__c, Rate__c, Carrier_Name__c FROM Benchmark_Rate__c WHERE RFP_Project__c = :f.p.Id];
    System.assertEquals(2, bids.size());
    System.assertEquals('Montréal, QC:Toronto, ON', bids[0].City_Lane__c, 'trigger stamped the keys');
    RFP_Lane__c a = fetch(f.a.Id);
    System.assertEquals(1200, a.Cost__c);
    System.assertEquals('Bid', a.Cost_Source__c);
    System.assertNotEquals(null, a.Selected_Bid__c);
    System.assertEquals(1380.00, a.Sell__c);
    RFP_Lane__c b = fetch(f.b.Id);
    System.assertEquals(
      1380.00,
      b.Sell__c,
      'b had no Sell_Source__c: the margin drives, sell recomputed from the bid'
    );
  }

  @IsTest
  static void applyBidRollsBackTheBidsWhenTheLanesCannotBeUpdated() {
    Fx f = fx();
    // Sell__c is Currency(16,2): 99,999,999,999,999 × 1.15 has 15 integer digits and does not fit,
    // so the lane update fails after the bids were inserted - the Savepoint must undo the bids.
    String bidJson = '{"Carrier_Name__c":"Huge","Rate__c":99999999999999,"CurrencyIsoCode":"CAD"}';
    try {
      RfpBulkService.applyBid(new List<Id>{ f.a.Id }, bidJson);
      System.assert(false, 'expected a failure');
    } catch (LaneSearchException e) {
      System.assert(e.getMessage().contains('No lane was updated'), e.getMessage());
    }
    System.assertEquals(0, [SELECT COUNT() FROM Benchmark_Rate__c WHERE RFP_Lane__c = :f.a.Id], 'rolled back');
    try {
      RfpBulkService.applyBid(new List<Id>{ f.a.Id }, '{"Carrier_Name__c":"x"}');
      System.assert(false, 'expected a failure');
    } catch (LaneSearchException e) {
      System.assert(e.getMessage().contains('rate'), e.getMessage());
    }
  }
```

`RfpBulkControllerTest.cls` (five wrappers, one try/catch each, asserting the `AuraHandledException` message):

```apex
@IsTest
private class RfpBulkControllerTest {
  @IsTest
  static void wrapsValidationAsUserErrors() {
    List<Id> none = new List<Id>();
    try {
      RfpBulkController.applyMedian(none, false);
      System.assert(false);
    } catch (AuraHandledException e) {
      System.assert(e.getMessage().contains('200'), e.getMessage());
    }
    try {
      RfpBulkController.applyPricing(none, null, null, null);
      System.assert(false);
    } catch (AuraHandledException e) {
      System.assert(e.getMessage().contains('Enter a cost'), e.getMessage());
    }
    try {
      RfpBulkController.applyBid(none, '{}');
      System.assert(false);
    } catch (AuraHandledException e) {
      System.assert(e.getMessage().contains('rate'), e.getMessage());
    }
    try {
      RfpBulkController.copyPricing(null, none);
      System.assert(false);
    } catch (AuraHandledException e) {
      System.assert(e.getMessage().containsIgnoreCase('cop'), e.getMessage());
    }
    try {
      RfpBulkController.deleteLanes(none);
      System.assert(false);
    } catch (AuraHandledException e) {
      System.assert(e.getMessage().contains('200'), e.getMessage());
    }
    try {
      RfpBulkController.applyBid(none, 'not json');
      System.assert(false);
    } catch (AuraHandledException e) {
      System.assert(e.getMessage().contains('could not'), e.getMessage());
    }
  }

  @IsTest
  static void happyPathReturnsTheResult() {
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
    RFP_Project__c p = RfpTestDataFactory.createProject(g.customer);
    RFP_Lane__c lane = RfpTestDataFactory.createLane(p, mtl, tor);
    RfpBulkService.Result r = RfpBulkController.applyPricing(
      new List<Id>{ lane.Id },
      1000,
      null,
      null
    );
    System.assertEquals(1, r.updated);
    System.assertEquals(1150.00, r.lanes[0].Sell__c);
  }
}
```

Prettier will reformat the one-line try/catch blocks; that is fine.

Add to `RfpSecurityTest.cls`. `RFP_Project__c` is Public Read/Write and lanes are Controlled by Parent, so a non-owner can edit but not delete: the project and lane are created inside `runAs(pricing)` so the restricted user owns them (the graph, places and account come from the admin fixture `Fx { g, mtl, laval, tor, lane }` and are only read):

```apex
  @IsTest
  static void rfpToolUserCanDeleteTheirLanesAndBids() {
    Fx f = fx();
    User pricing = restrictedUser('RFP_Tool_User');
    if (pricing == null) {
      System.assert(
        true,
        'no usable profile in this org; runAs coverage skipped (ledgered)'
      );
      return;
    }
    Test.startTest();
    RfpBulkService.Result r;
    Id laneId;
    System.runAs(pricing) {
      RFP_Project__c own = RfpTestDataFactory.createProject(f.g.customer);
      RFP_Lane__c lane = RfpTestDataFactory.createLane(own, f.mtl, f.tor);
      laneId = lane.Id;
      BenchmarkRateService.save(RfpTestDataFactory.buildBid(lane, 900));
      r = RfpBulkController.deleteLanes(new List<Id>{ laneId });
    }
    Test.stopTest();
    System.assertEquals(1, r.updated, String.join(r.errors, '; '));
    System.assertEquals(0, [SELECT COUNT() FROM RFP_Lane__c WHERE Id = :laneId]);
    System.assertEquals(
      0,
      [SELECT COUNT() FROM Benchmark_Rate__c WHERE RFP_Lane__c = :laneId]
    );
  }
```

- [ ] **Step 2: Implement `applyBid` in `RfpBulkService.cls`**

```apex
  /**
   * One bid per lane from the same template, then the lanes pick it as their cost. Two DMLs in one
   * Savepoint: if the lane update fails the bids are rolled back too, so no bid is left behind
   * without a lane pointing at it (allOrNone on the lane update for the same reason).
   */
  public static Result applyBid(List<Id> laneIds, String bidJson) {
    Benchmark_Rate__c template = (Benchmark_Rate__c) JSON.deserialize(
      bidJson,
      Benchmark_Rate__c.class
    );
    if (template.Rate__c == null || template.Rate__c <= 0) {
      throw new LaneSearchException('A bid needs a rate above zero.');
    }
    Context c = load(laneIds);
    List<Benchmark_Rate__c> bids = new List<Benchmark_Rate__c>();
    List<RFP_Lane__c> targets = new List<RFP_Lane__c>();
    for (RFP_Lane__c lane : c.lanes) {
      if (
        template.CurrencyIsoCode != null &&
        lane.CurrencyIsoCode != template.CurrencyIsoCode
      ) {
        skip(c, lane);
        continue;
      }
      Benchmark_Rate__c bid = template.clone(false, true);
      bid.RFP_Lane__c = lane.Id;
      bids.add(bid);
      targets.add(lane);
    }
    if (bids.isEmpty()) {
      return save(c, false);
    }
    Savepoint sp = Database.setSavepoint();
    try {
      List<Benchmark_Rate__c> saved = BenchmarkRateService.saveAll(bids);
      for (Integer i = 0; i < saved.size(); i++) {
        RFP_Lane__c u = pricingCopy(targets[i]);
        u.Cost__c = saved[i].Rate__c;
        u.Cost_Source__c = 'Bid';
        u.Selected_Bid__c = saved[i].Id;
        RfpPricingMath.recompute(u, c.defaultMarginFor(targets[i]));
        c.updates.add(u);
      }
      return save(c, true);
    } catch (DmlException e) {
      Database.rollback(sp);
      throw new LaneSearchException(
        'No lane was updated: ' + RfpUserError.safe(e)
      );
    }
  }
```

`RfpBulkController.cls`:

```apex
/** @AuraEnabled wrappers over RfpBulkService: user errors out, RfpBulkService.Result back. */
public with sharing class RfpBulkController {
  @AuraEnabled
  public static RfpBulkService.Result applyMedian(
    List<Id> laneIds,
    Boolean overwrite
  ) {
    try {
      return RfpBulkService.applyMedian(laneIds, overwrite);
    } catch (LaneSearchException e) {
      throw RfpUserError.of(e.getMessage());
    } catch (Exception e) {
      throw RfpUserError.of(
        'The medians could not be applied. ' + RfpUserError.safe(e)
      );
    }
  }

  @AuraEnabled
  public static RfpBulkService.Result applyPricing(
    List<Id> laneIds,
    Decimal cost,
    Decimal sell,
    Decimal margin
  ) {
    try {
      return RfpBulkService.applyPricing(laneIds, cost, sell, margin);
    } catch (LaneSearchException e) {
      throw RfpUserError.of(e.getMessage());
    } catch (Exception e) {
      throw RfpUserError.of(
        'The pricing could not be applied. ' + RfpUserError.safe(e)
      );
    }
  }

  @AuraEnabled
  public static RfpBulkService.Result applyBid(
    List<Id> laneIds,
    String bidJson
  ) {
    try {
      return RfpBulkService.applyBid(laneIds, bidJson);
    } catch (LaneSearchException e) {
      throw RfpUserError.of(e.getMessage());
    } catch (Exception e) {
      throw RfpUserError.of(
        'The carrier rate could not be added. ' + RfpUserError.safe(e)
      );
    }
  }

  @AuraEnabled
  public static RfpBulkService.Result copyPricing(
    Id sourceLaneId,
    List<Id> laneIds
  ) {
    try {
      return RfpBulkService.copyPricing(sourceLaneId, laneIds);
    } catch (LaneSearchException e) {
      throw RfpUserError.of(e.getMessage());
    } catch (Exception e) {
      throw RfpUserError.of(
        'The pricing could not be copied. ' + RfpUserError.safe(e)
      );
    }
  }

  @AuraEnabled
  public static RfpBulkService.Result deleteLanes(List<Id> laneIds) {
    try {
      return RfpBulkService.deleteLanes(laneIds);
    } catch (LaneSearchException e) {
      throw RfpUserError.of(e.getMessage());
    } catch (Exception e) {
      throw RfpUserError.of(
        'The lanes could not be deleted. ' + RfpUserError.safe(e)
      );
    }
  }
}
```

`copyPricing(null, ...)` either reaches the "no cost" branch (`lanesByIds(new List<Id>{ null })` is empty) or fails inside the query; both surface as an `AuraHandledException` whose message contains "cop" ("no cost to copy" or "could not be copied"), which is what the test asserts.

Manifest: `<members>RfpBulkController</members>`, `<members>RfpBulkControllerTest</members>` after `RfpBulkServiceTest`. CI (`ci.yml` `--tests` line) and README (the "Apex tests" row, the `sf apex run test -n …` command, the `sf project deploy start … -t …` command): append ` RfpPricingMathTest RfpBulkServiceTest RfpBulkControllerTest` (README `-n` form: `-n RfpPricingMathTest -n RfpBulkServiceTest -n RfpBulkControllerTest`), matching the Global Constraints order exactly.

- [ ] **Step 3: Deploy everything, run the full specified list, PMD, commit**

```bash
sf project deploy start -x manifest/package.xml -o sandbox -l NoTestRun -w 30
sf project deploy start -x manifest/package.xml -o sandbox -l RunSpecifiedTests -t PricingDepartmentControllerTest PlaceNormalizerTest PricingTestDataFactoryTest PlaceBuilderBatchTest LaneSearchServiceTest MapboxGeocoderTest LaneBenchmarkControllerTest LaneBenchmarkPlaceServiceTest RfpTestDataFactoryTest BenchmarkRateServiceTest BidSearchQueryBuilderTest BidSearchServiceTest RfpControllerTest RfpSecurityTest RfpImportServiceTest RfpLaneControllerTest RfpHistoryServiceTest RfpProjectControllerTest RfpBidControllerTest RfpPricingMathTest RfpBulkServiceTest RfpBulkControllerTest -w 30
/private/tmp/pmd_install/pmd-bin-7.15.0/bin/pmd check --dir force-app --rulesets config/pmd-ruleset.xml --minimum-priority 3 --format text --fail-on-violation
git add force-app/main/default/classes/RfpBulk* force-app/main/default/classes/RfpSecurityTest.cls manifest/package.xml .github/workflows/ci.yml README.md
git commit -m "Add bulk carrier rates, the RfpBulkController wrappers and the delete permission test"
```

Expected: both deploys Succeeded; every class ≥ 75 %; record the deploy id in the report.

---

### Task 7: `c/rfpPricing` sell source + inline edits, `c/rfpLaneFilter`

**Files:**

- Modify: `force-app/main/default/lwc/rfpPricing/rfpPricing.js` (+ test), `force-app/main/default/lwc/rfpLanePanel/__tests__/rfpLanePanel.test.js` (two assertions)
- Create: `force-app/main/default/lwc/rfpLaneFilter/rfpLaneFilter.js`, `rfpLaneFilter.js-meta.xml` (copy `rfpBatch.js-meta.xml`), `__tests__/rfpLaneFilter.test.js`
- Modify: `manifest/package.xml` (LWC members, after `rfpWorkbook`)

**Interfaces:**

- Consumes: `marginFor`, `parseMargin`, `suggestedSell` from `c/marginMath`.
- Produces (`c/rfpPricing`): `parseMoney(text) → number > 0 | null`; `pricingDetail({ laneId, source, selectedBidId, cost, marginText, notes, sellSource, sellText })` → `{ laneId, Cost__c, Cost_Source__c, Selected_Bid__c, Margin__c, Sell__c, Sell_Source__c, Notes__c }`; `recompute(detail, defaultMargin) → detail`; `inlineEdit(lane, field, text, defaultMargin) → detail | null` with `field ∈ "cost" | "margin" | "sell"`; `pricingFingerprint(lane) → string`.
- Produces (`c/rfpLaneFilter`): `STATUS_FILTERS` (combobox options), `applyFilter(lanes, { status, text, selectedIds }) → lanes`, `siblings(lanes, lane) → lanes`.

- [ ] **Step 1: Failing tests for `c/rfpPricing`**

```js
import {
  pricingDetail,
  inlineEdit,
  recompute,
  pricingFingerprint,
  parseMoney
} from "c/rfpPricing";

const LANE = {
  Id: "a0L1",
  Cost__c: 1000,
  Cost_Source__c: "History median",
  Selected_Bid__c: null,
  Margin__c: 15,
  Sell__c: 1150,
  Sell_Source__c: "Margin",
  Notes__c: "n"
};

describe("pricingDetail with a sell source", () => {
  it("derives the sell from the margin when the margin drives", () => {
    const d = pricingDetail({
      laneId: "a0L1",
      source: "Manual",
      cost: 1000,
      marginText: "20",
      notes: "",
      sellSource: "Margin",
      sellText: "999"
    });
    expect(d).toMatchObject({
      Margin__c: 20,
      Sell__c: 1200,
      Sell_Source__c: "Margin"
    });
  });
  it("keeps the typed sell and derives the margin when the sell drives", () => {
    const d = pricingDetail({
      laneId: "a0L1",
      source: "Manual",
      cost: 1000,
      marginText: "20",
      notes: "",
      sellSource: "Manual",
      sellText: "1500"
    });
    expect(d).toMatchObject({
      Margin__c: 50,
      Sell__c: 1500,
      Sell_Source__c: "Manual"
    });
  });
});

describe("inlineEdit", () => {
  it("a typed margin recomputes the sell", () => {
    expect(inlineEdit(LANE, "margin", "20", 15)).toMatchObject({
      laneId: "a0L1",
      Margin__c: 20,
      Sell__c: 1200,
      Sell_Source__c: "Margin",
      Cost__c: 1000,
      Notes__c: "n"
    });
  });
  it("a typed sell flips the lane to Manual and derives the margin", () => {
    expect(inlineEdit(LANE, "sell", "900", 15)).toMatchObject({
      Sell__c: 900,
      Sell_Source__c: "Manual",
      Margin__c: -10
    });
  });
  it("a typed cost becomes a manual cost and follows the sell source", () => {
    expect(inlineEdit(LANE, "cost", "2000", 15)).toMatchObject({
      Cost__c: 2000,
      Cost_Source__c: "Manual",
      Selected_Bid__c: null,
      Sell__c: 2300,
      Margin__c: 15
    });
    const manual = { ...LANE, Sell_Source__c: "Manual", Sell__c: 1500 };
    expect(inlineEdit(manual, "cost", "2000", 15)).toMatchObject({
      Cost__c: 2000,
      Sell__c: 1500,
      Margin__c: -25,
      Sell_Source__c: "Manual"
    });
  });
  it("uses the project default margin when the lane has none", () => {
    expect(inlineEdit({ Id: "a0L2" }, "cost", "100", 12)).toMatchObject({
      Margin__c: 12,
      Sell__c: 112
    });
  });
  it("rejects blanks, junk, non-positive money and out-of-range margins", () => {
    expect(inlineEdit(LANE, "cost", "", 15)).toBeNull();
    expect(inlineEdit(LANE, "cost", "abc", 15)).toBeNull();
    expect(inlineEdit(LANE, "sell", "0", 15)).toBeNull();
    expect(inlineEdit(LANE, "margin", "101", 15)).toBeNull();
    expect(inlineEdit(LANE, "notes", "x", 15)).toBeNull();
  });
});

describe("recompute / fingerprint / parseMoney", () => {
  it("recompute mirrors RfpPricingMath.recompute", () => {
    expect(
      recompute(
        { Cost__c: 2000, Margin__c: null, Sell__c: null, Sell_Source__c: null },
        15
      )
    ).toMatchObject({ Margin__c: 15, Sell__c: 2300, Sell_Source__c: "Margin" });
  });
  it("fingerprint changes with any of the six pricing fields", () => {
    const a = pricingFingerprint(LANE);
    expect(pricingFingerprint({ ...LANE, Notes__c: "other" })).toBe(a);
    expect(pricingFingerprint({ ...LANE, Sell__c: 1151 })).not.toBe(a);
    expect(pricingFingerprint(null)).toBe(pricingFingerprint(undefined));
  });
  it("parseMoney", () => {
    expect(parseMoney("12.5")).toBe(12.5);
    expect(parseMoney(" 7 ")).toBe(7);
    expect(parseMoney("0")).toBeNull();
    expect(parseMoney("")).toBeNull();
    expect(parseMoney(null)).toBeNull();
  });
});
```

Update the existing `pricingDetail` tests in the file: the returned object now also carries `Sell_Source__c: "Margin"` (use `toMatchObject` or add the key).

- [ ] **Step 2: Implement in `rfpPricing.js`**

Change the first import to `import { parseMargin, suggestedSell, marginFor } from "c/marginMath";` and add / replace:

```js
/** A positive amount typed by the pricer, else null. */
export function parseMoney(text) {
  if (text === null || text === undefined) return null;
  const s = String(text).trim();
  if (s === "") return null;
  const n = Number(s);
  return Number.isFinite(n) && n > 0 ? n : null;
}

const PRICING_FIELDS = [
  "Cost__c",
  "Cost_Source__c",
  "Selected_Bid__c",
  "Margin__c",
  "Sell__c",
  "Sell_Source__c"
];

/** Changes whenever one of the six pricing fields does; the panel re-syncs on it. */
export function pricingFingerprint(lane) {
  return PRICING_FIELDS.map((f) => lane?.[f] ?? "").join("|");
}

/** Mirrors RfpPricingMath.recompute after a cost change. */
export function recompute(detail, defaultMargin) {
  if (detail.Sell_Source__c === "Manual" && detail.Sell__c !== null) {
    return { ...detail, Margin__c: marginFor(detail.Cost__c, detail.Sell__c) };
  }
  const margin = detail.Margin__c ?? defaultMargin ?? null;
  return {
    ...detail,
    Margin__c: margin,
    Sell__c: suggestedSell(detail.Cost__c, margin),
    Sell_Source__c: "Margin"
  };
}

/** Exactly the fields RfpLaneController.saveLanePricing whitelists. */
export function pricingDetail({
  laneId,
  source,
  selectedBidId,
  cost,
  marginText,
  notes,
  sellSource,
  sellText
}) {
  const manual = sellSource === "Manual";
  const costValue = cost === undefined ? null : cost;
  const sell = manual ? parseMoney(sellText) : null;
  const margin = manual ? marginFor(costValue, sell) : parseMargin(marginText);
  return {
    laneId,
    Cost__c: costValue,
    Cost_Source__c: source,
    Selected_Bid__c: source === "Bid" ? selectedBidId || null : null,
    Margin__c: margin,
    Sell__c: manual ? sell : suggestedSell(costValue, margin),
    Sell_Source__c: manual ? "Manual" : "Margin",
    Notes__c: notes || null
  };
}

/**
 * One edited cell → the whole pricing detail to save (the controller writes every
 * whitelisted field, so the untouched ones travel along). Null when the text is
 * not a usable value; the caller keeps the cell open.
 */
export function inlineEdit(lane, field, text, defaultMargin) {
  const base = {
    laneId: lane.Id,
    Cost__c: lane.Cost__c ?? null,
    Cost_Source__c: lane.Cost_Source__c || "Manual",
    Selected_Bid__c: lane.Selected_Bid__c || null,
    Margin__c: lane.Margin__c ?? null,
    Sell__c: lane.Sell__c ?? null,
    Sell_Source__c: lane.Sell_Source__c || "Margin",
    Notes__c: lane.Notes__c || null
  };
  if (field === "margin") {
    const margin = parseMargin(text);
    if (margin === null) return null;
    return {
      ...base,
      Margin__c: margin,
      Sell_Source__c: "Margin",
      Sell__c: suggestedSell(base.Cost__c, margin)
    };
  }
  const value = parseMoney(text);
  if (value === null) return null;
  if (field === "sell") {
    return {
      ...base,
      Sell__c: value,
      Sell_Source__c: "Manual",
      Margin__c: marginFor(base.Cost__c, value)
    };
  }
  if (field !== "cost") return null;
  return recompute(
    {
      ...base,
      Cost__c: value,
      Cost_Source__c: "Manual",
      Selected_Bid__c: null
    },
    defaultMargin
  );
}
```

- [ ] **Step 3: Failing tests for `c/rfpLaneFilter`**

```js
import { STATUS_FILTERS, applyFilter, siblings } from "c/rfpLaneFilter";

const lane = (over) => ({
  Id: over.Id,
  Origin_City__c: "Montreal",
  Origin_Province__c: "QC",
  Origin_Postal__c: "H1A",
  Origin_Resolved__c: true,
  Origin_Place__c: "p1",
  Destination_City__c: "Toronto",
  Destination_Province__c: "ON",
  Destination_Postal__c: "M5V",
  Destination_Resolved__c: true,
  Destination_Place__c: "p2",
  Mode__c: "Truckload",
  Equipment_Type__c: "Dry Van 53'",
  Hist_Status__c: "Done",
  Cost__c: 1000,
  ...over
});

const L = [
  lane({ Id: "1" }),
  lane({ Id: "2", Cost__c: null, Hist_Status__c: "No match" }),
  lane({
    Id: "3",
    Destination_Resolved__c: false,
    Destination_Place__c: null,
    Destination_City__c: "Nowhere",
    Destination_Postal__c: null,
    Hist_Status__c: "Unresolved",
    Cost__c: null
  }),
  lane({ Id: "4", Cost_Source__c: "Manual" }),
  lane({ Id: "5", Sell_Source__c: "Manual", Equipment_Type__c: "Reefer" })
];

describe("applyFilter", () => {
  it("offers the six statuses in order", () => {
    expect(STATUS_FILTERS.map((o) => o.value)).toEqual([
      "all",
      "unpriced",
      "nomatch",
      "unresolved",
      "manual",
      "selected"
    ]);
  });
  it("filters by status", () => {
    const ids = (f) => applyFilter(L, f).map((l) => l.Id);
    expect(ids({ status: "all" })).toEqual(["1", "2", "3", "4", "5"]);
    expect(ids({ status: "unpriced" })).toEqual(["2", "3"]);
    expect(ids({ status: "nomatch" })).toEqual(["2"]);
    expect(ids({ status: "unresolved" })).toEqual(["3"]);
    expect(ids({ status: "manual" })).toEqual(["4", "5"]);
    expect(ids({ status: "selected", selectedIds: ["5", "1"] })).toEqual([
      "1",
      "5"
    ]);
  });
  it("searches places and equipment, case-insensitively", () => {
    const ids = (text) =>
      applyFilter(L, { status: "all", text }).map((l) => l.Id);
    expect(ids("nowhere")).toEqual(["3"]);
    expect(ids("REEFER")).toEqual(["5"]);
    expect(ids("m5v")).toEqual(["1", "2", "4", "5"]);
    expect(ids("  ")).toHaveLength(5);
  });
  it("tolerates missing lanes and options", () => {
    expect(applyFilter(null)).toEqual([]);
    expect(applyFilter(L, {})).toHaveLength(5);
  });
});

describe("siblings", () => {
  it("finds unpriced lanes with the same places, mode and equipment", () => {
    const twins = [
      lane({ Id: "a" }),
      lane({ Id: "b", Cost__c: null }),
      lane({ Id: "c", Cost__c: null, Mode__c: "LTL" }),
      lane({
        Id: "d",
        Cost__c: null,
        Equipment_Type__c: null,
        Equipment_Category__c: "Dry Van 53'"
      }),
      lane({ Id: "e", Cost__c: null, Destination_Place__c: "p9" })
    ];
    expect(siblings(twins, twins[0]).map((l) => l.Id)).toEqual(["b", "d"]);
  });
  it("never matches from or to an unresolved lane", () => {
    expect(siblings(L, L[2])).toEqual([]);
    expect(siblings(null, L[0])).toEqual([]);
  });
});
```

- [ ] **Step 4: Implement `rfpLaneFilter.js`**

```js
/**
 * Pure helpers for the lane table's filter bar and the "same lane" copy offer.
 * Nothing here touches Apex or the DOM.
 */
export const STATUS_FILTERS = [
  { label: "All lanes", value: "all" },
  { label: "Unpriced", value: "unpriced" },
  { label: "No history match", value: "nomatch" },
  { label: "Unresolved ends", value: "unresolved" },
  { label: "Manual cost or sell", value: "manual" },
  { label: "Selected", value: "selected" }
];

const unpriced = (l) => l.Cost__c === null || l.Cost__c === undefined;

const MATCHERS = {
  all: () => true,
  unpriced,
  nomatch: (l) => l.Hist_Status__c === "No match",
  unresolved: (l) => !l.Origin_Resolved__c || !l.Destination_Resolved__c,
  manual: (l) => l.Cost_Source__c === "Manual" || l.Sell_Source__c === "Manual",
  selected: (l, selected) => selected.has(l.Id)
};

const TEXT_FIELDS = [
  "Origin_City__c",
  "Origin_Province__c",
  "Origin_Postal__c",
  "Destination_City__c",
  "Destination_Province__c",
  "Destination_Postal__c",
  "Equipment_Type__c"
];

export function applyFilter(
  lanes,
  { status = "all", text = "", selectedIds = [] } = {}
) {
  const match = MATCHERS[status] || MATCHERS.all;
  const selected = new Set(selectedIds || []);
  const needle = (text || "").trim().toLowerCase();
  return (lanes || []).filter(
    (l) =>
      match(l, selected) &&
      (!needle ||
        TEXT_FIELDS.some((f) =>
          String(l[f] || "")
            .toLowerCase()
            .includes(needle)
        ))
  );
}

const equipmentOf = (l) => l.Equipment_Type__c || l.Equipment_Category__c || "";

/**
 * The unpriced lanes that are the same lane again: same two places, same mode,
 * same equipment. An unresolved end has no place, so it never pairs.
 */
export function siblings(lanes, lane) {
  if (!lane || !lane.Origin_Place__c || !lane.Destination_Place__c) {
    return [];
  }
  return (lanes || []).filter(
    (l) =>
      l.Id !== lane.Id &&
      unpriced(l) &&
      l.Origin_Place__c === lane.Origin_Place__c &&
      l.Destination_Place__c === lane.Destination_Place__c &&
      (l.Mode__c || "") === (lane.Mode__c || "") &&
      equipmentOf(l) === equipmentOf(lane)
  );
}
```

Add `<members>rfpLaneFilter</members>` after `<members>rfpWorkbook</members>` in the manifest.

- [ ] **Step 5: Test, lint, commit**

```bash
npx jest force-app/main/default/lwc/rfpPricing force-app/main/default/lwc/rfpLaneFilter force-app/main/default/lwc/rfpLanePanel && npx eslint force-app/main/default/lwc
git add force-app/main/default/lwc/rfpPricing force-app/main/default/lwc/rfpLaneFilter force-app/main/default/lwc/rfpLanePanel/__tests__ manifest/package.xml
git commit -m "Add sell-source pricing details, inline edit math and the lane filter module"
```

Before running: the two `toEqual` assertions on a `pricingchange` detail in `rfpLanePanel/__tests__/rfpLanePanel.test.js` (~lines 187 and 358) gain `Sell_Source__c: "Margin"`, since every detail now carries it. Add that test file to the commit.

---

### Task 8: `c/rfpBulk` module and `c/rfpBulkBar` component

**Files:**

- Create: `force-app/main/default/lwc/rfpBulk/rfpBulk.js`, `.js-meta.xml`, `__tests__/rfpBulk.test.js`
- Create: `force-app/main/default/lwc/rfpBulkBar/rfpBulkBar.js`, `.html`, `.js-meta.xml` (copy `rfpLaneTable.js-meta.xml`), `__tests__/rfpBulkBar.test.js`
- Modify: `manifest/package.xml` (after `rfpLaneFilter`)

**Interfaces:**

- Consumes: `RfpBulkController.*` (Task 6), `chunk`, `series` from `c/rfpBatch`, `parseMargin` from `c/marginMath`, `parseMoney` from `c/rfpPricing`, `c-rfp-bid-form` (`@api laneId, currency, bid`; emits `save { bid }`, `cancel`).
- Produces (`c/rfpBulk`): `BULK_CHUNK = 200`; `runBulk({ action, ids, params, onProgress, isStopped }) → Promise<{ action, lanes, updated, skipped, skippedIds, errors, failedIds }>` with `action ∈ median | pricing | bid | copy | delete`; `applyBulkResult(lanes, selectedIds, result) → { lanes, selectedIds }`; `summaryText(result) → string`.
- Produces (`c-rfp-bulk-bar`): `@api selectedCount, totalCount, currency, busy, lastResult`; emits `bulk` with `detail = { action, scope, cost?, sell?, margin?, bid?, overwrite? }`, `scope ∈ selected | all | skipped`.

- [ ] **Step 1: Failing tests for `c/rfpBulk`**

```js
import applyMedian from "@salesforce/apex/RfpBulkController.applyMedian";
import applyPricing from "@salesforce/apex/RfpBulkController.applyPricing";
import deleteLanes from "@salesforce/apex/RfpBulkController.deleteLanes";
import { runBulk, applyBulkResult, summaryText, BULK_CHUNK } from "c/rfpBulk";

jest.mock(
  "@salesforce/apex/RfpBulkController.applyMedian",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/RfpBulkController.applyPricing",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/RfpBulkController.applyBid",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/RfpBulkController.copyPricing",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/RfpBulkController.deleteLanes",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const ids = (n) => Array.from({ length: n }, (_, i) => `a0L${i + 1}`);

describe("runBulk", () => {
  beforeEach(() => jest.clearAllMocks());

  it("chunks by 200 and folds the results together", async () => {
    applyMedian.mockImplementation(async ({ laneIds }) => ({
      lanes: laneIds.map((Id) => ({ Id, Cost__c: 1 })),
      updated: laneIds.length - 1,
      skipped: 1,
      skippedIds: [laneIds[0]],
      errors: []
    }));
    const progress = [];
    const r = await runBulk({
      action: "median",
      ids: ids(450),
      params: { overwrite: true },
      onProgress: (n) => progress.push(n)
    });
    expect(applyMedian).toHaveBeenCalledTimes(3);
    expect(applyMedian.mock.calls[0][0]).toEqual({
      laneIds: ids(450).slice(0, BULK_CHUNK),
      overwrite: true
    });
    expect(r.updated).toBe(447);
    expect(r.skipped).toBe(3);
    expect(r.skippedIds).toEqual(["a0L1", "a0L201", "a0L401"]);
    expect(r.lanes).toHaveLength(450);
    expect(progress).toEqual([200, 200, 50]);
  });

  it("a failing chunk counts its ids as failed and the run carries on", async () => {
    applyPricing
      .mockRejectedValueOnce({
        body: { message: "The margin must be between 0 and 100." }
      })
      .mockResolvedValueOnce({
        lanes: [],
        updated: 1,
        skipped: 0,
        skippedIds: [],
        errors: []
      });
    const r = await runBulk({
      action: "pricing",
      ids: ids(201),
      params: { margin: 10 }
    });
    expect(applyPricing.mock.calls[0][0]).toEqual({
      laneIds: ids(200),
      cost: null,
      sell: null,
      margin: 10
    });
    expect(r.failedIds).toHaveLength(200);
    expect(r.updated).toBe(1);
    expect(r.errors[0]).toBe("The margin must be between 0 and 100.");
  });

  it("stops between chunks when asked", async () => {
    deleteLanes.mockResolvedValue({
      lanes: [],
      updated: 200,
      skipped: 0,
      skippedIds: [],
      errors: []
    });
    let stop = false;
    const r = await runBulk({
      action: "delete",
      ids: ids(400),
      onProgress: () => {
        stop = true;
      },
      isStopped: () => stop
    });
    expect(deleteLanes).toHaveBeenCalledTimes(1);
    expect(r.updated).toBe(200);
  });

  it("refuses an unknown action", async () => {
    await expect(runBulk({ action: "nope", ids: ids(1) })).rejects.toThrow(
      "Unknown bulk action"
    );
  });
});

describe("applyBulkResult / summaryText", () => {
  const lanes = [
    { Id: "a", Cost__c: null },
    { Id: "b", Cost__c: null },
    { Id: "c" }
  ];
  it("merges returned lanes for pricing actions", () => {
    const out = applyBulkResult(lanes, ["a", "c"], {
      action: "median",
      lanes: [{ Id: "a", Cost__c: 5 }],
      updated: 1,
      skipped: 0,
      skippedIds: [],
      errors: [],
      failedIds: []
    });
    expect(out.lanes[0]).toEqual({ Id: "a", Cost__c: 5 });
    expect(out.lanes[1]).toEqual({ Id: "b", Cost__c: null });
    expect(out.selectedIds).toEqual(["a", "c"]);
  });
  it("drops deleted lanes from the list and the selection", () => {
    const out = applyBulkResult(lanes, ["a", "b", "c"], {
      action: "delete",
      lanes: [{ Id: "b", Cost__c: null }],
      updated: 2,
      skipped: 0,
      skippedIds: [],
      errors: [],
      failedIds: [],
      ids: ["a", "b", "c"]
    });
    expect(out.lanes.map((l) => l.Id)).toEqual(["b"]);
    expect(out.selectedIds).toEqual(["b"]);
  });
  it("words the summary", () => {
    expect(
      summaryText({
        action: "median",
        updated: 143,
        skipped: 12,
        failedIds: [],
        errors: []
      })
    ).toBe("Median applied to 143 lanes; 12 skipped");
    expect(
      summaryText({
        action: "delete",
        updated: 1,
        skipped: 0,
        failedIds: ["x"],
        errors: ["boom"]
      })
    ).toBe("Deleted 1 lane; 1 failed; boom");
    expect(
      summaryText({
        action: "bid",
        updated: 3,
        skipped: 0,
        failedIds: [],
        errors: []
      })
    ).toBe("Carrier rate added to 3 lanes");
  });
});
```

- [ ] **Step 2: Implement `rfpBulk.js`**

```js
/**
 * Runs one RfpBulkController action over any number of lane ids, 200 per call
 * (the server refuses more), folding the per-call results into one. A chunk
 * that throws counts its ids as failed; the run carries on with the next one.
 */
import applyMedian from "@salesforce/apex/RfpBulkController.applyMedian";
import applyPricing from "@salesforce/apex/RfpBulkController.applyPricing";
import applyBid from "@salesforce/apex/RfpBulkController.applyBid";
import copyPricing from "@salesforce/apex/RfpBulkController.copyPricing";
import deleteLanes from "@salesforce/apex/RfpBulkController.deleteLanes";
import { chunk, series, mergeLanes } from "c/rfpBatch";

export const BULK_CHUNK = 200;

const CALLS = {
  median: (laneIds, p) => applyMedian({ laneIds, overwrite: !!p.overwrite }),
  pricing: (laneIds, p) =>
    applyPricing({
      laneIds,
      cost: p.cost ?? null,
      sell: p.sell ?? null,
      margin: p.margin ?? null
    }),
  bid: (laneIds, p) => applyBid({ laneIds, bidJson: JSON.stringify(p.bid) }),
  copy: (laneIds, p) => copyPricing({ sourceLaneId: p.sourceLaneId, laneIds }),
  delete: (laneIds) => deleteLanes({ laneIds })
};

const VERBS = {
  median: "Median applied to",
  pricing: "Pricing applied to",
  bid: "Carrier rate added to",
  copy: "Pricing copied to",
  delete: "Deleted"
};

export async function runBulk({
  action,
  ids,
  params = {},
  onProgress,
  isStopped
}) {
  const call = CALLS[action];
  if (!call) {
    throw new Error(`Unknown bulk action: ${action}`);
  }
  const total = {
    action,
    ids: ids || [],
    lanes: [],
    updated: 0,
    skipped: 0,
    skippedIds: [],
    errors: [],
    failedIds: []
  };
  await series(chunk(ids, BULK_CHUNK), async (part) => {
    if (isStopped && isStopped()) {
      return;
    }
    try {
      const r = await call(part, params);
      total.lanes.push(...(r.lanes || []));
      total.updated += r.updated || 0;
      total.skipped += r.skipped || 0;
      total.skippedIds.push(...(r.skippedIds || []));
      total.errors.push(...(r.errors || []));
    } catch (e) {
      total.failedIds.push(...part);
      total.errors.push((e && e.body && e.body.message) || "A chunk failed.");
    }
    if (onProgress) {
      onProgress(part.length);
    }
  });
  return total;
}

/**
 * Folds a run's outcome into the lanes on screen. Deleted lanes are the ids the
 * run was given that did not come back; they leave the list and the selection.
 */
export function applyBulkResult(lanes, selectedIds, result) {
  if (result.action !== "delete") {
    return { lanes: mergeLanes(lanes, result.lanes), selectedIds };
  }
  const survivors = new Set((result.lanes || []).map((l) => l.Id));
  const gone = new Set((result.ids || []).filter((id) => !survivors.has(id)));
  return {
    lanes: (lanes || []).filter((l) => !gone.has(l.Id)),
    selectedIds: (selectedIds || []).filter((id) => !gone.has(id))
  };
}

export function summaryText(r) {
  const n = r.updated || 0;
  const parts = [
    `${VERBS[r.action] || "Applied to"} ${n} lane${n === 1 ? "" : "s"}`
  ];
  if (r.skipped) {
    parts.push(`${r.skipped} skipped`);
  }
  const failed = (r.failedIds || []).length;
  if (failed) {
    parts.push(`${failed} failed`);
  }
  if (r.errors && r.errors.length) {
    parts.push(r.errors[0]);
  }
  return parts.join("; ");
}
```

Note `runBulk`'s `total.ids` is the full id list handed in, so `applyBulkResult` can work out deletions; the test for `applyBulkResult` passes `ids` explicitly.

- [ ] **Step 3: Failing tests for `c-rfp-bulk-bar`**

```js
import { createElement } from "lwc";
import RfpBulkBar from "c/rfpBulkBar";

// c-rfp-bid-form pulls in c-rfp-account-picker, which imports Apex.
jest.mock(
  "@salesforce/apex/RfpProjectController.searchAccounts",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const flush = () => Promise.resolve().then(() => Promise.resolve());
const field = (el, id) => el.shadowRoot.querySelector(`[data-id="${id}"]`);

async function mount(props = {}) {
  const el = createElement("c-rfp-bulk-bar", { is: RfpBulkBar });
  Object.assign(
    el,
    { selectedCount: 0, totalCount: 10, currency: "CAD" },
    props
  );
  document.body.appendChild(el);
  await flush();
  return el;
}
const lastBulk = (spy) => spy.mock.calls[spy.mock.calls.length - 1][0].detail;

describe("c-rfp-bulk-bar", () => {
  afterEach(() => {
    while (document.body.firstChild)
      document.body.removeChild(document.body.firstChild);
  });

  it("starts on All lanes and disables Selected at zero", async () => {
    const el = await mount();
    expect(field(el, "scope-all").variant).toBe("brand");
    expect(field(el, "scope-selected").disabled).toBe(true);
    expect(field(el, "scope-selected").label).toBe("Selected (0)");
    expect(field(el, "delete")).toBeNull();
  });

  it("emits median for the chosen scope", async () => {
    const el = await mount({ selectedCount: 3 });
    const spy = jest.fn();
    el.addEventListener("bulk", spy);
    field(el, "use-median").click();
    expect(lastBulk(spy)).toEqual({ action: "median", scope: "all" });
    field(el, "scope-selected").click();
    await flush();
    field(el, "use-median").click();
    expect(lastBulk(spy)).toEqual({ action: "median", scope: "selected" });
  });

  it("validates and emits pricing values", async () => {
    const el = await mount({ selectedCount: 2 });
    const spy = jest.fn();
    el.addEventListener("bulk", spy);
    field(el, "margin").dispatchEvent(
      new CustomEvent("change", { detail: { value: "120" } })
    );
    field(el, "apply-margin").click();
    await flush();
    expect(spy).not.toHaveBeenCalled();
    expect(field(el, "bar-error").textContent).toContain("0 and 100");
    field(el, "margin").dispatchEvent(
      new CustomEvent("change", { detail: { value: "18" } })
    );
    field(el, "apply-margin").click();
    expect(lastBulk(spy)).toEqual({
      action: "pricing",
      scope: "all",
      margin: 18
    });
    field(el, "cost").dispatchEvent(
      new CustomEvent("change", { detail: { value: "1250.5" } })
    );
    field(el, "apply-cost").click();
    expect(lastBulk(spy)).toEqual({
      action: "pricing",
      scope: "all",
      cost: 1250.5
    });
    field(el, "sell").dispatchEvent(
      new CustomEvent("change", { detail: { value: "0" } })
    );
    field(el, "apply-sell").click();
    await flush();
    expect(field(el, "bar-error").textContent).toContain("above zero");
  });

  it("deletes only the selection and only on the second click", async () => {
    const el = await mount({ selectedCount: 4 });
    const spy = jest.fn();
    el.addEventListener("bulk", spy);
    field(el, "scope-selected").click();
    await flush();
    const del = field(el, "delete");
    expect(del.label).toBe("Delete selected");
    del.click();
    await flush();
    expect(spy).not.toHaveBeenCalled();
    expect(field(el, "delete").label).toBe(
      "Confirm: delete 4 lanes and their carrier rates"
    );
    field(el, "delete").click();
    expect(lastBulk(spy)).toEqual({ action: "delete", scope: "selected" });
    el.selectedCount = 0;
    await flush();
    expect(field(el, "delete")).toBeNull();
    expect(field(el, "scope-all").variant).toBe("brand");
  });

  it("adds the same carrier rate through the bid form", async () => {
    const el = await mount({ selectedCount: 2 });
    const spy = jest.fn();
    el.addEventListener("bulk", spy);
    field(el, "add-bid").click();
    await flush();
    const form = el.shadowRoot.querySelector("c-rfp-bid-form");
    expect(form).not.toBeNull();
    expect(form.currency).toBe("CAD");
    form.dispatchEvent(
      new CustomEvent("save", {
        detail: {
          bid: {
            RFP_Lane__c: null,
            Carrier_Name__c: "ACME",
            Rate__c: 900,
            CurrencyIsoCode: "CAD"
          }
        }
      })
    );
    await flush();
    expect(lastBulk(spy)).toEqual({
      action: "bid",
      scope: "all",
      bid: { Carrier_Name__c: "ACME", Rate__c: 900, CurrencyIsoCode: "CAD" }
    });
    expect(el.shadowRoot.querySelector("c-rfp-bid-form")).toBeNull();
  });

  it("offers to overwrite the lanes a median run skipped", async () => {
    const el = await mount({
      lastResult: {
        action: "median",
        updated: 5,
        skipped: 2,
        skippedIds: ["a", "b"],
        errors: [],
        failedIds: []
      }
    });
    const spy = jest.fn();
    el.addEventListener("bulk", spy);
    expect(field(el, "skipped-note").textContent).toContain(
      "2 lanes already costed"
    );
    field(el, "overwrite").click();
    expect(lastBulk(spy)).toEqual({
      action: "median",
      scope: "skipped",
      overwrite: true
    });
  });

  it("disables every action while busy", async () => {
    const el = await mount({ busy: true, selectedCount: 1 });
    [
      "use-median",
      "apply-margin",
      "apply-cost",
      "apply-sell",
      "add-bid"
    ].forEach((id) => expect(field(el, id).disabled).toBe(true));
  });
});
```

- [ ] **Step 4: Implement `rfpBulkBar.js` and `.html`**

```js
import { LightningElement, api } from "lwc";
import { parseMargin } from "c/marginMath";
import { parseMoney } from "c/rfpPricing";

/**
 * The bulk actions above the lane table: pick a scope (the selection or every
 * lane), then push a median, a margin, a cost, a sell or a carrier rate onto it,
 * or delete the selection. The bar only emits `bulk`; rfpTool runs the calls.
 */
export default class RfpBulkBar extends LightningElement {
  @api totalCount = 0;
  @api currency = "CAD";
  @api busy = false;
  @api lastResult = null;

  _selectedCount = 0;
  scope = "all";
  marginText = "";
  costText = "";
  sellText = "";
  showBidForm = false;
  confirmingDelete = false;
  error = null;

  @api
  get selectedCount() {
    return this._selectedCount;
  }
  set selectedCount(value) {
    this._selectedCount = value || 0;
    // A changed selection is a new decision: the delete confirm starts over,
    // and an empty selection can only mean every lane.
    this.confirmingDelete = false;
    if (!this._selectedCount) {
      this.scope = "all";
    }
  }

  get isSelectedScope() {
    return this.scope === "selected";
  }
  get selectedLabel() {
    return `Selected (${this._selectedCount})`;
  }
  get allLabel() {
    return `All lanes (${this.totalCount || 0})`;
  }
  get selectedVariant() {
    return this.isSelectedScope ? "brand" : "neutral";
  }
  get allVariant() {
    return this.isSelectedScope ? "neutral" : "brand";
  }
  get noSelection() {
    return !this._selectedCount;
  }
  get deleteLabel() {
    const n = this._selectedCount;
    return this.confirmingDelete
      ? `Confirm: delete ${n} lane${n === 1 ? "" : "s"} and ${n === 1 ? "its" : "their"} carrier rates`
      : "Delete selected";
  }
  get costLabel() {
    return `Cost (${this.currency})`;
  }
  get sellLabel() {
    return `Sell (${this.currency})`;
  }
  get skippedCount() {
    const r = this.lastResult;
    return r && r.action === "median" && r.skippedIds ? r.skippedIds.length : 0;
  }
  get skippedNote() {
    const n = this.skippedCount;
    return `${n} lane${n === 1 ? "" : "s"} already costed from a bid or manually ${n === 1 ? "was" : "were"} left as ${n === 1 ? "it is" : "they are"}`;
  }

  handleScopeSelected() {
    this.scope = "selected";
    this.confirmingDelete = false;
  }
  handleScopeAll() {
    this.scope = "all";
    this.confirmingDelete = false;
  }
  handleMargin(event) {
    this.marginText = event.detail.value;
  }
  handleCost(event) {
    this.costText = event.detail.value;
  }
  handleSell(event) {
    this.sellText = event.detail.value;
  }

  emit(detail) {
    this.error = null;
    this.dispatchEvent(
      new CustomEvent("bulk", { detail: { scope: this.scope, ...detail } })
    );
  }

  handleUseMedian() {
    this.emit({ action: "median" });
  }
  handleApplyMargin() {
    const margin = parseMargin(this.marginText);
    if (margin === null) {
      this.error = "The margin must be between 0 and 100.";
      return;
    }
    this.emit({ action: "pricing", margin });
  }
  handleApplyCost() {
    const cost = parseMoney(this.costText);
    if (cost === null) {
      this.error = "The cost must be above zero.";
      return;
    }
    this.emit({ action: "pricing", cost });
  }
  handleApplySell() {
    const sell = parseMoney(this.sellText);
    if (sell === null) {
      this.error = "The sell must be above zero.";
      return;
    }
    this.emit({ action: "pricing", sell });
  }
  handleOverwrite() {
    this.error = null;
    this.dispatchEvent(
      new CustomEvent("bulk", {
        detail: { action: "median", scope: "skipped", overwrite: true }
      })
    );
  }
  handleDelete() {
    if (!this.confirmingDelete) {
      this.confirmingDelete = true;
      return;
    }
    this.confirmingDelete = false;
    this.dispatchEvent(
      new CustomEvent("bulk", {
        detail: { action: "delete", scope: "selected" }
      })
    );
  }
  handleAddBid() {
    this.error = null;
    this.showBidForm = true;
  }
  handleCancelBid() {
    this.showBidForm = false;
  }
  handleSaveBid(event) {
    const bid = { ...event.detail.bid };
    delete bid.RFP_Lane__c;
    this.showBidForm = false;
    this.emit({ action: "bid", bid });
  }
}
```

```html
<template>
  <div class="slds-box slds-box_x-small slds-m-bottom_x-small">
    <div
      class="slds-grid slds-wrap slds-grid_vertical-align-end slds-gutters_x-small"
    >
      <div class="slds-col">
        <lightning-button-group>
          <lightning-button
            data-id="scope-selected"
            label="{selectedLabel}"
            variant="{selectedVariant}"
            disabled="{noSelection}"
            onclick="{handleScopeSelected}"
          ></lightning-button>
          <lightning-button
            data-id="scope-all"
            label="{allLabel}"
            variant="{allVariant}"
            onclick="{handleScopeAll}"
          ></lightning-button>
        </lightning-button-group>
      </div>
      <div class="slds-col">
        <lightning-button
          data-id="use-median"
          label="Use median"
          title="Cost each lane from its history median (lanes costed from a bid or by hand are left alone)"
          disabled="{busy}"
          onclick="{handleUseMedian}"
        ></lightning-button>
      </div>
      <div class="slds-col">
        <lightning-input
          data-id="margin"
          label="Margin %"
          value="{marginText}"
          onchange="{handleMargin}"
        ></lightning-input>
      </div>
      <div class="slds-col">
        <lightning-button
          data-id="apply-margin"
          label="Apply margin"
          disabled="{busy}"
          onclick="{handleApplyMargin}"
        ></lightning-button>
      </div>
      <div class="slds-col">
        <lightning-input
          data-id="cost"
          type="number"
          step="0.01"
          label="{costLabel}"
          value="{costText}"
          onchange="{handleCost}"
        ></lightning-input>
      </div>
      <div class="slds-col">
        <lightning-button
          data-id="apply-cost"
          label="Apply cost"
          disabled="{busy}"
          onclick="{handleApplyCost}"
        ></lightning-button>
      </div>
      <div class="slds-col">
        <lightning-input
          data-id="sell"
          type="number"
          step="0.01"
          label="{sellLabel}"
          value="{sellText}"
          onchange="{handleSell}"
        ></lightning-input>
      </div>
      <div class="slds-col">
        <lightning-button
          data-id="apply-sell"
          label="Apply sell"
          disabled="{busy}"
          onclick="{handleApplySell}"
        ></lightning-button>
      </div>
      <div class="slds-col">
        <lightning-button
          data-id="add-bid"
          label="Add carrier rate"
          disabled="{busy}"
          onclick="{handleAddBid}"
        ></lightning-button>
      </div>
      <template lwc:if="{isSelectedScope}">
        <div class="slds-col">
          <lightning-button
            data-id="delete"
            variant="destructive"
            label="{deleteLabel}"
            disabled="{busy}"
            onclick="{handleDelete}"
          ></lightning-button>
        </div>
      </template>
    </div>
    <template lwc:if="{error}">
      <p
        data-id="bar-error"
        class="slds-text-color_error slds-m-top_xx-small"
        role="alert"
      >
        {error}
      </p>
    </template>
    <template lwc:if="{skippedCount}">
      <p
        data-id="skipped-note"
        class="slds-text-color_weak slds-m-top_xx-small"
      >
        {skippedNote}
        <lightning-button
          data-id="overwrite"
          class="slds-m-left_x-small"
          label="Overwrite them"
          disabled="{busy}"
          onclick="{handleOverwrite}"
        ></lightning-button>
      </p>
    </template>
    <template lwc:if="{showBidForm}">
      <div class="slds-m-top_x-small">
        <c-rfp-bid-form
          currency="{currency}"
          onsave="{handleSaveBid}"
          oncancel="{handleCancelBid}"
        ></c-rfp-bid-form>
      </div>
    </template>
  </div>
</template>
```

Add `<members>rfpBulk</members>` and `<members>rfpBulkBar</members>` after `rfpLaneFilter` in the manifest.

- [ ] **Step 5: Test, lint, commit**

```bash
npx jest force-app/main/default/lwc/rfpBulk force-app/main/default/lwc/rfpBulkBar && npx eslint force-app/main/default/lwc
git add force-app/main/default/lwc/rfpBulk force-app/main/default/lwc/rfpBulkBar manifest/package.xml
git commit -m "Add the bulk runner module and the bulk action bar"
```

---

### Task 9: Lane table — selection checkboxes, inline cells, row marks

**Files:**

- Modify: `force-app/main/default/lwc/rfpLaneTable/rfpLaneTable.js`, `.html`, `.css`
- Test: `force-app/main/default/lwc/rfpLaneTable/__tests__/rfpLaneTable.test.js`

**Interfaces:**

- Consumes: `inlineEdit(lane, field, text, defaultMargin)` from `c/rfpPricing`.
- Produces: new `@api selectedIds` (array), `pendingIds` (array), `rowErrors` (object), `defaultMargin` (number), `locked` (boolean); events `selectionchange { laneIds }` and `pricingchange { laneId, Cost__c, Cost_Source__c, Selected_Bid__c, Margin__c, Sell__c, Sell_Source__c, Notes__c }` (same shape the panel emits). Existing `select` / `resolveend` unchanged. The `td`s keep `data-id="cost|margin|sell"` and gain `data-field`.

- [ ] **Step 1: Failing tests**

Add to `rfpLaneTable.test.js` (reuse `mount`, `rowsOf`, `flush`, `RESOLVED_LANE`, `UNRESOLVED_LANE`):

```js
const cellOf = (row, field) => row.querySelector(`[data-id="${field}"]`);
const inputIn = (el) => el.shadowRoot.querySelector('[data-id="cell-input"]');
const key = (target, k, extra = {}) =>
  target.dispatchEvent(
    new KeyboardEvent("keydown", {
      key: k,
      bubbles: true,
      cancelable: true,
      ...extra
    })
  );

describe("selection", () => {
  it("emits the whole selection on a row checkbox and on the header checkbox", async () => {
    const el = await mount({ selectedIds: ["a0L00000002"] });
    const spy = jest.fn();
    el.addEventListener("selectionchange", spy);
    const select = jest.fn();
    el.addEventListener("select", select);
    const checks = el.shadowRoot.querySelectorAll('[data-id="row-check"]');
    expect(checks[1].checked).toBe(true);
    checks[0].click();
    expect(spy.mock.calls[0][0].detail.laneIds).toEqual([
      "a0L00000002",
      "a0L00000001"
    ]);
    expect(select).not.toHaveBeenCalled();
    el.shadowRoot.querySelector('[data-id="check-all"]').click();
    expect(spy.mock.calls[1][0].detail.laneIds).toEqual([
      "a0L00000002",
      "a0L00000001"
    ]);
    el.selectedIds = ["a0L00000001", "a0L00000002"];
    await flush();
    expect(el.shadowRoot.querySelector('[data-id="check-all"]').checked).toBe(
      true
    );
    el.shadowRoot.querySelector('[data-id="check-all"]').click();
    expect(spy.mock.calls[2][0].detail.laneIds).toEqual([]);
  });
});

describe("inline editing", () => {
  it("opens one cell on click, saves on Enter and moves down the column", async () => {
    const el = await mount({ defaultMargin: 15 });
    const spy = jest.fn();
    el.addEventListener("pricingchange", spy);
    cellOf(rowsOf(el)[0], "margin").click();
    await flush();
    const input = inputIn(el);
    expect(input).not.toBeNull();
    expect(input.value).toBe("15");
    expect(
      el.shadowRoot.querySelectorAll('[data-id="cell-input"]').length
    ).toBe(1);
    input.dispatchEvent(new CustomEvent("change", { detail: { value: "20" } }));
    key(input, "Enter");
    await flush();
    expect(spy).toHaveBeenCalledTimes(1);
    expect(spy.mock.calls[0][0].detail).toMatchObject({
      laneId: "a0L00000001",
      Margin__c: 20,
      Sell__c: 2280,
      Sell_Source__c: "Margin"
    });
    const next = inputIn(el);
    expect(next).not.toBeNull();
    expect(rowsOf(el)[1].contains(next)).toBe(true);
  });

  it("Tab saves and moves down; Escape cancels without saving", async () => {
    const el = await mount({ defaultMargin: 15 });
    const spy = jest.fn();
    el.addEventListener("pricingchange", spy);
    cellOf(rowsOf(el)[0], "sell").click();
    await flush();
    inputIn(el).dispatchEvent(
      new CustomEvent("change", { detail: { value: "2500" } })
    );
    key(inputIn(el), "Tab");
    await flush();
    expect(spy.mock.calls[0][0].detail).toMatchObject({
      Sell__c: 2500,
      Sell_Source__c: "Manual",
      Margin__c: 31.58
    });
    key(inputIn(el), "Escape");
    await flush();
    expect(inputIn(el)).toBeNull();
    expect(spy).toHaveBeenCalledTimes(1);
  });

  it("keeps an invalid value open with an error, and an unchanged value just closes", async () => {
    const el = await mount({ defaultMargin: 15 });
    const spy = jest.fn();
    el.addEventListener("pricingchange", spy);
    cellOf(rowsOf(el)[0], "cost").click();
    await flush();
    inputIn(el).dispatchEvent(
      new CustomEvent("change", { detail: { value: "-5" } })
    );
    key(inputIn(el), "Enter");
    await flush();
    expect(inputIn(el)).not.toBeNull();
    expect(
      el.shadowRoot.querySelector('[data-id="cell-error"]').textContent
    ).toContain("above zero");
    expect(spy).not.toHaveBeenCalled();
    inputIn(el).dispatchEvent(
      new CustomEvent("change", { detail: { value: "1900" } })
    );
    key(inputIn(el), "Enter");
    await flush();
    expect(spy).not.toHaveBeenCalled();
  });

  it("Enter on a focused cell opens it, blur commits, and a locked table ignores clicks", async () => {
    const el = await mount({ defaultMargin: 15 });
    const spy = jest.fn();
    el.addEventListener("pricingchange", spy);
    const cell = cellOf(rowsOf(el)[1], "cost");
    key(cell, "Enter");
    await flush();
    expect(inputIn(el)).not.toBeNull();
    inputIn(el).dispatchEvent(
      new CustomEvent("change", { detail: { value: "800" } })
    );
    inputIn(el).dispatchEvent(new CustomEvent("blur"));
    await flush();
    expect(spy.mock.calls[0][0].detail).toMatchObject({
      laneId: "a0L00000002",
      Cost__c: 800,
      Cost_Source__c: "Manual",
      Margin__c: 15,
      Sell__c: 920
    });
    expect(inputIn(el)).toBeNull();
    el.locked = true;
    await flush();
    cellOf(rowsOf(el)[0], "cost").click();
    await flush();
    expect(inputIn(el)).toBeNull();
  });

  it("marks pending rows, errors, negative margins and manual sells", async () => {
    const el = await mount({
      lanes: [
        { ...RESOLVED_LANE, Margin__c: -5, Sell_Source__c: "Manual" },
        UNRESOLVED_LANE
      ],
      pendingIds: ["a0L00000001"],
      rowErrors: { a0L00000002: "The lane price could not be saved." }
    });
    const rows = rowsOf(el);
    expect(rows[0].querySelector('[data-id="row-pending"]')).not.toBeNull();
    expect(rows[1].querySelector('[data-id="row-error"]').title).toContain(
      "could not be saved"
    );
    expect(
      cellOf(rows[0], "margin").classList.contains("slds-text-color_error")
    ).toBe(true);
    expect(
      rows[0].querySelector('[data-id="manual-tag"]').textContent.trim()
    ).toBe("manual");
  });
});
```

`Sell 2500 on cost 1900 → margin 31.58` (2500/1900 − 1 = 0.315789…).

- [ ] **Step 2: Implement `rfpLaneTable.js`**

Add the import `import { inlineEdit } from "c/rfpPricing";` and the constants/messages:

```js
const EDITABLE = ["cost", "margin", "sell"];
const ERRORS = {
  cost: "Enter a cost above zero",
  sell: "Enter a sell above zero",
  margin: "Margin must be 0 to 100"
};
const rawText = (lane, field) => {
  const v = { cost: lane.Cost__c, margin: lane.Margin__c, sell: lane.Sell__c }[
    field
  ];
  return v === null || v === undefined ? "" : String(v);
};
```

New `@api` properties and state:

```js
  @api pendingIds = [];
  @api rowErrors = {};
  @api defaultMargin;
  @api locked = false;

  _selectedIds = [];
  @api
  get selectedIds() {
    return this._selectedIds;
  }
  set selectedIds(value) {
    this._selectedIds = value || [];
  }

  editing = null; // { laneId, field }
  draft = "";
  cellError = null;
  focusPending = false;

  renderedCallback() {
    if (!this.focusPending) {
      return;
    }
    this.focusPending = false;
    const input = this.template.querySelector('[data-id="cell-input"]');
    if (input) {
      input.focus();
    }
  }

  get allChecked() {
    const selected = new Set(this._selectedIds);
    return this._lanes.length > 0 && this._lanes.every((l) => selected.has(l.Id));
  }
```

Extend `viewRows` (keep every existing key) with:

```js
      checked: selected.has(l.Id),
      pending: pending.has(l.Id),
      error: (this.rowErrors || {})[l.Id] || null,
      marginClass:
        "slds-text-align_right cell" +
        (l.Margin__c !== null && l.Margin__c !== undefined && l.Margin__c < 0
          ? " slds-text-color_error"
          : ""),
      manualSell: l.Sell_Source__c === "Manual",
      editingCost: this.isEditing(l.Id, "cost"),
      editingMargin: this.isEditing(l.Id, "margin"),
      editingSell: this.isEditing(l.Id, "sell")
```

with `const selected = new Set(this._selectedIds); const pending = new Set(this.pendingIds || []);` at the top of the getter and

```js
  isEditing(laneId, field) {
    return !!this.editing && this.editing.laneId === laneId && this.editing.field === field;
  }
```

Selection handlers:

```js
  handleRowCheck(event) {
    const laneId = event.currentTarget.dataset.laneId;
    const next = event.currentTarget.checked
      ? [...this._selectedIds.filter((id) => id !== laneId), laneId]
      : this._selectedIds.filter((id) => id !== laneId);
    this.emitSelection(next);
  }
  /** Toggles the rows currently shown; ids the table does not show are left as they are. */
  handleCheckAll() {
    const shown = this._lanes.map((l) => l.Id);
    const next = this.allChecked
      ? this._selectedIds.filter((id) => !shown.includes(id))
      : [...this._selectedIds, ...shown.filter((id) => !this._selectedIds.includes(id))];
    this.emitSelection(next);
  }
  emitSelection(laneIds) {
    this.dispatchEvent(new CustomEvent("selectionchange", { detail: { laneIds } }));
  }
```

Inline editing:

```js
  handleCellClick(event) {
    this.open(event.currentTarget.dataset);
  }
  handleCellKey(event) {
    if (event.target !== event.currentTarget || event.key !== "Enter") {
      return;
    }
    event.preventDefault();
    event.stopPropagation();
    this.open(event.currentTarget.dataset);
  }
  open({ laneId, field }) {
    if (this.locked || !EDITABLE.includes(field)) {
      return;
    }
    if (this.isEditing(laneId, field)) {
      return;
    }
    const lane = this._lanes.find((l) => l.Id === laneId);
    if (!lane) {
      return;
    }
    this.editing = { laneId, field };
    this.draft = rawText(lane, field);
    this.cellError = null;
    this.focusPending = true;
  }
  handleDraft(event) {
    this.draft = event.detail.value;
  }
  handleInputKey(event) {
    event.stopPropagation();
    if (event.key === "Escape") {
      event.preventDefault();
      this.close();
    } else if (event.key === "Enter" || event.key === "Tab") {
      event.preventDefault();
      this.commit(event.shiftKey ? -1 : 1);
    }
  }
  handleInputBlur(event) {
    const { laneId, field } = event.currentTarget.dataset;
    // A commit that already moved on leaves a blur behind on the old input.
    if (!this.isEditing(laneId, field)) {
      return;
    }
    if (!this.commit(0)) {
      this.close(); // an unusable value is dropped on blur rather than trapping focus
    }
  }
  close() {
    this.editing = null;
    this.draft = "";
    this.cellError = null;
  }
  /**
   * Saves the draft and moves `step` rows down the same column (0 = just
   * close). Returns false when the draft is unusable; the cell stays open
   * with the reason under it.
   */
  commit(step) {
    const { laneId, field } = this.editing;
    const index = this._lanes.findIndex((l) => l.Id === laneId);
    const lane = this._lanes[index];
    const text = String(this.draft ?? "").trim();
    if (text !== rawText(lane, field)) {
      const detail = inlineEdit(lane, field, text, this.defaultMargin);
      if (!detail) {
        this.cellError = ERRORS[field];
        return false;
      }
      this.dispatchEvent(new CustomEvent("pricingchange", { detail }));
    }
    const next = this._lanes[index + step];
    this.close();
    if (step !== 0 && next) {
      this.open({ laneId: next.Id, field });
    }
    return true;
  }
```

Cell clicks must still select the row (the `tr` handler runs after the cell's, which is what we want), but Enter inside the cell must not: `handleCellKey` stops propagation, and `handleRowKey` already ignores events whose target is not the row.

- [ ] **Step 3: Update `rfpLaneTable.html`**

Header: add before `#`:

```html
<th scope="col" class="w-2">
  <input
    type="checkbox"
    data-id="check-all"
    aria-label="Select every lane shown"
    checked="{allChecked}"
    onclick="{stopRowSelect}"
    onchange="{handleCheckAll}"
  />
</th>
```

First cell of each row:

```html
<td class="check-cell" onclick="{stopRowSelect}" onkeydown="{stopRowSelect}">
  <input
    type="checkbox"
    data-id="row-check"
    data-lane-id="{r.id}"
    aria-label="Select this lane"
    checked="{r.checked}"
    onchange="{handleRowCheck}"
  />
</td>
```

Replace the three pricing cells:

```html
<td
  data-id="cost"
  data-field="cost"
  data-lane-id="{r.id}"
  class="slds-text-align_right cell"
  tabindex="0"
  onclick="{handleCellClick}"
  onkeydown="{handleCellKey}"
>
  <template lwc:if="{r.editingCost}">
    <lightning-input
      data-id="cell-input"
      data-field="cost"
      data-lane-id="{r.id}"
      type="number"
      step="0.01"
      variant="label-hidden"
      label="Cost"
      value="{draft}"
      onchange="{handleDraft}"
      onkeydown="{handleInputKey}"
      onblur="{handleInputBlur}"
    ></lightning-input>
    <template lwc:if="{cellError}"
      ><div
        data-id="cell-error"
        class="slds-text-color_error slds-text-body_small"
      >
        {cellError}
      </div></template
    >
  </template>
  <template lwc:else>{r.costText}</template>
</td>
<td
  data-id="margin"
  data-field="margin"
  data-lane-id="{r.id}"
  class="{r.marginClass}"
  tabindex="0"
  onclick="{handleCellClick}"
  onkeydown="{handleCellKey}"
>
  <template lwc:if="{r.editingMargin}">
    <lightning-input
      data-id="cell-input"
      data-field="margin"
      data-lane-id="{r.id}"
      type="text"
      variant="label-hidden"
      label="Margin %"
      value="{draft}"
      onchange="{handleDraft}"
      onkeydown="{handleInputKey}"
      onblur="{handleInputBlur}"
    ></lightning-input>
    <template lwc:if="{cellError}"
      ><div
        data-id="cell-error"
        class="slds-text-color_error slds-text-body_small"
      >
        {cellError}
      </div></template
    >
  </template>
  <template lwc:else>{r.marginText}</template>
</td>
<td
  data-id="sell"
  data-field="sell"
  data-lane-id="{r.id}"
  class="slds-text-align_right cell"
  tabindex="0"
  onclick="{handleCellClick}"
  onkeydown="{handleCellKey}"
>
  <template lwc:if="{r.editingSell}">
    <lightning-input
      data-id="cell-input"
      data-field="sell"
      data-lane-id="{r.id}"
      type="number"
      step="0.01"
      variant="label-hidden"
      label="Sell"
      value="{draft}"
      onchange="{handleDraft}"
      onkeydown="{handleInputKey}"
      onblur="{handleInputBlur}"
    ></lightning-input>
    <template lwc:if="{cellError}"
      ><div
        data-id="cell-error"
        class="slds-text-color_error slds-text-body_small"
      >
        {cellError}
      </div></template
    >
  </template>
  <template lwc:else>
    {r.sellText}
    <template lwc:if="{r.manualSell}"
      ><span data-id="manual-tag" class="slds-badge slds-m-left_xx-small"
        >manual</span
      ></template
    >
  </template>
</td>
<td data-id="status">
  <template lwc:if="{r.pending}">
    <lightning-icon
      data-id="row-pending"
      icon-name="utility:sync"
      size="xx-small"
      alternative-text="Saving"
    ></lightning-icon>
  </template>
  <template lwc:if="{r.error}">
    <lightning-icon
      data-id="row-error"
      icon-name="utility:error"
      variant="error"
      size="xx-small"
      alternative-text="Save failed"
      title="{r.error}"
    ></lightning-icon>
  </template>
  {r.statusText}
</td>
```

Prettier will spread these onto multiple lines. `lightning-icon` `title` is a standard attribute and survives to the host element (the test reads it). `rfpLaneTable.css`: add `.w-2 { width: 2rem; } .cell { cursor: text; } .cell:focus { outline: 2px solid #0176d3; outline-offset: -2px; } .check-cell { cursor: default; }`.

- [ ] **Step 4: Test, lint, commit**

```bash
npx jest force-app/main/default/lwc/rfpLaneTable && npx eslint force-app/main/default/lwc
git add force-app/main/default/lwc/rfpLaneTable
git commit -m "Add lane selection and spreadsheet-style cost, margin and sell cells to the lane table"
```

---

### Task 10: Lane panel — sell input, link direction, fingerprint re-sync

**Files:**

- Modify: `force-app/main/default/lwc/rfpLanePanel/rfpLanePanel.js`, `.html`, `.css`
- Test: `force-app/main/default/lwc/rfpLanePanel/__tests__/rfpLanePanel.test.js`

**Interfaces:**

- Consumes: `pricingDetail` with `sellSource`/`sellText`, `pricingFingerprint`, `parseMoney` from `c/rfpPricing`; `marginFor`, `suggestedSell` from `c/marginMath`.
- Produces: `pricingchange` detail now carries `Sell_Source__c`; `data-id="sell"` is a `lightning-input`; `data-id="sell-mode"` text.

- [ ] **Step 1: Failing tests**

Add to `rfpLanePanel.test.js` (its `LANE` has Cost 1500, Cost_Source Manual, no Margin):

```js
describe("linked sell and margin", () => {
  it("typing a sell flips the lane to Manual and shows the derived margin", async () => {
    const el = await mount();
    field(el, "margin").dispatchEvent(
      new CustomEvent("change", { detail: { value: "20" } })
    );
    await flush();
    expect(field(el, "sell").value).toBe(1800);
    expect(field(el, "sell-mode").textContent).toContain(
      "Sell follows the margin"
    );
    field(el, "sell").dispatchEvent(
      new CustomEvent("change", { detail: { value: "2250" } })
    );
    await flush();
    expect(field(el, "margin").value).toBe("50");
    expect(field(el, "sell-mode").textContent).toContain(
      "Margin follows the sell"
    );
    const spy = jest.fn();
    el.addEventListener("pricingchange", spy);
    field(el, "save-price").click();
    expect(spy.mock.calls[0][0].detail).toMatchObject({
      Cost__c: 1500,
      Sell__c: 2250,
      Margin__c: 50,
      Sell_Source__c: "Manual"
    });
  });

  it("a cost change keeps a manual sell and re-derives the margin", async () => {
    const el = await mount();
    field(el, "sell").dispatchEvent(
      new CustomEvent("change", { detail: { value: "2000" } })
    );
    field(el, "cost").dispatchEvent(
      new CustomEvent("change", { detail: { value: "1000" } })
    );
    await flush();
    expect(field(el, "sell").value).toBe(2000);
    expect(field(el, "margin").value).toBe("100");
  });

  it("cannot save a manual sell that is blank", async () => {
    const el = await mount();
    field(el, "sell").dispatchEvent(
      new CustomEvent("change", { detail: { value: "" } })
    );
    await flush();
    expect(field(el, "save-price").disabled).toBe(true);
  });

  it("re-syncs when the same lane comes back with different pricing", async () => {
    const el = await mount();
    el.lane = {
      ...LANE,
      Cost__c: 1700,
      Margin__c: 10,
      Sell__c: 1870,
      Sell_Source__c: "Margin"
    };
    await flush();
    expect(field(el, "cost").value).toBe("1700");
    expect(field(el, "margin").value).toBe("10");
    expect(field(el, "sell").value).toBe(1870);
  });
});
```

`mount(props)`, `field(el, id)` and `flush()` already exist in this file. The existing tests that read `data-id="sell"` as a span must now read `.value` of the input.

- [ ] **Step 2: Implement**

`rfpLanePanel.js`: imports gain `pricingFingerprint, parseMoney` from `c/rfpPricing` and `import { marginFor, suggestedSell, parseMargin } from "c/marginMath";`. State: `sellSource = "Margin"; sellText = "";`. Setter:

```js
  set lane(value) {
    const laneChanged = laneIdOf(value) !== laneIdOf(this._lane);
    const pricingChanged =
      pricingFingerprint(value) !== pricingFingerprint(this._lane);
    const previousHistoryKey = historyKey(this._lane);
    this._lane = value || null;
    if (laneChanged) {
      this.syncFromLane();
      this.loadBids();
    } else if (pricingChanged) {
      // An inline edit or a bulk action touched the lane on screen: the editor
      // must show what is stored now, not what it showed before the change.
      this.syncPricing();
    }
    if (laneChanged || historyKey(this._lane) !== previousHistoryKey) {
      this.loadHistory();
    }
  }
```

Split `syncFromLane()` so its pricing part is `syncPricing()` (called from `syncFromLane` too), adding:

```js
this.sellSource = l.Sell_Source__c === "Manual" ? "Manual" : "Margin";
this.sellText =
  l.Sell__c === null || l.Sell__c === undefined ? "" : String(l.Sell__c);
```

Handlers:

```js
  get isManualSell() {
    return this.sellSource === "Manual";
  }
  get sellMode() {
    return this.isManualSell ? "Margin follows the sell" : "Sell follows the margin";
  }
  get sellValue() {
    return this.isManualSell ? this.sellText : this.pricing.Sell__c;
  }
  get marginValue() {
    if (!this.isManualSell) {
      return this.marginText;
    }
    const m = marginFor(this.costNumber, parseMoney(this.sellText));
    return m === null ? "" : String(m);
  }
  get cannotSavePrice() {
    return (
      this.costNumber === null ||
      (this.isManualSell && parseMoney(this.sellText) === null)
    );
  }
  handleMargin(event) {
    this.marginText = event.detail.value;
    this.sellSource = "Margin";
  }
  handleSell(event) {
    this.sellText = event.detail.value;
    this.sellSource = "Manual";
  }
```

`pricing` getter passes `sellSource: this.sellSource, sellText: this.sellText`. Remove the old `sellText` getter (the money string) — the input shows `sellValue`. Under `Margin` the margin input keeps showing `marginText`; under `Manual` it shows the derived value and stays editable (typing in it flips back). Nothing else in the cost-change path needs code: with `Manual` the derived margin recomputes through the getters; with `Margin` the sell recomputes through `pricing`.

`rfpLanePanel.html`: the margin input uses `value={marginValue}`; replace the static Sell `<p>` with

```html
<div class="slds-col slds-size_1-of-3">
  <lightning-input
    data-id="sell"
    type="number"
    step="0.01"
    min="0"
    label="{sellLabel}"
    value="{sellValue}"
    onchange="{handleSell}"
  ></lightning-input>
</div>
<div class="slds-col slds-size_1-of-1">
  <p data-id="sell-mode" class="slds-text-body_small slds-text-color_weak">
    {sellMode}
  </p>
</div>
```

with `get sellLabel() { return \`Sell (${this.currency})\`; }`. `rfpLanePanel.css`: delete the `.lane-panel { min-height: 480px }`rule (keep`position: relative`) and the `.sell` rule.

- [ ] **Step 3: Test, lint, commit**

```bash
npx jest force-app/main/default/lwc/rfpLanePanel && npx eslint force-app/main/default/lwc
git add force-app/main/default/lwc/rfpLanePanel
git commit -m "Let the pricing panel take a sell price and keep it in step with the table"
```

---

### Task 11: `c/rfpTool` wiring — filters, selection, bulk, twin offer, sticky panel

**Files:**

- Modify: `force-app/main/default/lwc/rfpTool/rfpTool.js`, `.html`
- Create: `force-app/main/default/lwc/rfpTool/rfpTool.css`
- Test: `force-app/main/default/lwc/rfpTool/__tests__/rfpTool.test.js`

**Interfaces:**

- Consumes: `applyFilter`, `STATUS_FILTERS`, `siblings` (`c/rfpLaneFilter`); `runBulk`, `applyBulkResult`, `summaryText` (`c/rfpBulk`); `c-rfp-bulk-bar` (`bulk` event); `c-rfp-lane-table` new props/events (Task 9).
- Produces: the finished workbench.

- [ ] **Step 1: Failing tests**

Add to `rfpTool.test.js` (mock the five `RfpBulkController` modules at the top like the other Apex mocks; import `applyMedian`, `applyPricing`, `copyPricing`, `deleteLanes`; `openFromUrl(laneList)`, `settle`, `field`, `child`, `lanes`, `pendingLane` already exist in the file — `openFromUrl` sets the `getLanes` mock itself and opens project `a0P1` through the page reference):

```js
it("filters the table and selects only the rows shown", async () => {
  const el = await openFromUrl([
    { ...pendingLane(1), Cost__c: 100 },
    { ...pendingLane(2), Destination_City__c: "Calgary" },
    pendingLane(3)
  ]);
  field(el, "filter-status").dispatchEvent(
    new CustomEvent("change", { detail: { value: "unpriced" } })
  );
  await settle();
  let table = child(el, "c-rfp-lane-table");
  expect(table.lanes.map((l) => l.Id)).toEqual(["a0L2", "a0L3"]);
  expect(field(el, "filter-count").textContent).toContain("2 of 3");
  field(el, "filter-text").dispatchEvent(
    new CustomEvent("change", { detail: { value: "calg" } })
  );
  await settle();
  table = child(el, "c-rfp-lane-table");
  expect(table.lanes.map((l) => l.Id)).toEqual(["a0L2"]);
  table.dispatchEvent(
    new CustomEvent("selectionchange", { detail: { laneIds: ["a0L2"] } })
  );
  await settle();
  expect(child(el, "c-rfp-bulk-bar").selectedCount).toBe(1);
  expect(child(el, "c-rfp-bulk-bar").totalCount).toBe(3);
});

it("runs a bulk action over the chosen scope and merges the lanes back", async () => {
  applyMedian.mockResolvedValue({
    lanes: [{ ...pendingLane(1), Cost__c: 2000 }],
    updated: 1,
    skipped: 2,
    skippedIds: ["a0L2", "a0L3"],
    errors: []
  });
  const el = await openFromUrl(lanes(3));
  child(el, "c-rfp-bulk-bar").dispatchEvent(
    new CustomEvent("bulk", { detail: { action: "median", scope: "all" } })
  );
  await settle();
  expect(applyMedian).toHaveBeenCalledWith({
    laneIds: ["a0L1", "a0L2", "a0L3"],
    overwrite: false
  });
  expect(child(el, "c-rfp-lane-table").lanes[0].Cost__c).toBe(2000);
  expect(field(el, "summary").textContent).toContain(
    "Median applied to 1 lane; 2 skipped"
  );
  expect(child(el, "c-rfp-bulk-bar").lastResult.skippedIds).toEqual([
    "a0L2",
    "a0L3"
  ]);
  child(el, "c-rfp-bulk-bar").dispatchEvent(
    new CustomEvent("bulk", {
      detail: { action: "median", scope: "skipped", overwrite: true }
    })
  );
  await settle();
  expect(applyMedian).toHaveBeenLastCalledWith({
    laneIds: ["a0L2", "a0L3"],
    overwrite: true
  });
});

it("deletes the selection and drops the rows", async () => {
  deleteLanes.mockResolvedValue({
    lanes: [],
    updated: 2,
    skipped: 0,
    skippedIds: [],
    errors: []
  });
  const el = await openFromUrl(lanes(3));
  child(el, "c-rfp-lane-table").dispatchEvent(
    new CustomEvent("selectionchange", {
      detail: { laneIds: ["a0L1", "a0L3"] }
    })
  );
  await settle();
  child(el, "c-rfp-bulk-bar").dispatchEvent(
    new CustomEvent("bulk", { detail: { action: "delete", scope: "selected" } })
  );
  await settle();
  expect(deleteLanes).toHaveBeenCalledWith({ laneIds: ["a0L1", "a0L3"] });
  expect(child(el, "c-rfp-lane-table").lanes.map((l) => l.Id)).toEqual([
    "a0L2"
  ]);
  expect(child(el, "c-rfp-bulk-bar").selectedCount).toBe(0);
});

it("marks a row pending while an inline save runs and offers the twins afterwards", async () => {
  const twin = {
    ...pendingLane(2),
    Origin_Place__c: "p1",
    Destination_Place__c: "p2",
    Mode__c: "TL"
  };
  let release;
  saveLanePricing.mockImplementation(
    () =>
      new Promise((r) => {
        release = r;
      })
  );
  copyPricing.mockResolvedValue({
    lanes: [{ ...twin, Cost__c: 900 }],
    updated: 1,
    skipped: 0,
    skippedIds: [],
    errors: []
  });
  const el = await openFromUrl([
    {
      ...pendingLane(1),
      Origin_Place__c: "p1",
      Destination_Place__c: "p2",
      Mode__c: "TL"
    },
    twin
  ]);
  child(el, "c-rfp-lane-table").dispatchEvent(
    new CustomEvent("pricingchange", {
      detail: {
        laneId: "a0L1",
        Cost__c: 900,
        Cost_Source__c: "Manual",
        Selected_Bid__c: null,
        Margin__c: 15,
        Sell__c: 1035,
        Sell_Source__c: "Margin",
        Notes__c: null
      }
    })
  );
  await settle();
  expect(child(el, "c-rfp-lane-table").pendingIds).toEqual(["a0L1"]);
  release({
    ...pendingLane(1),
    Origin_Place__c: "p1",
    Destination_Place__c: "p2",
    Mode__c: "TL",
    Cost__c: 900,
    Sell__c: 1035
  });
  await settle();
  expect(child(el, "c-rfp-lane-table").pendingIds).toEqual([]);
  expect(field(el, "twin-offer").textContent).toContain("1 identical lane");
  field(el, "twin-apply").click();
  await settle();
  expect(copyPricing).toHaveBeenCalledWith({
    sourceLaneId: "a0L1",
    laneIds: ["a0L2"]
  });
  expect(field(el, "twin-offer")).toBeNull();
  expect(child(el, "c-rfp-lane-table").lanes[1].Cost__c).toBe(900);
});

it("records a failed inline save on the row instead of the banner", async () => {
  saveLanePricing.mockRejectedValue({
    body: { message: "The lane price could not be saved. Boom" }
  });
  const el = await openFromUrl(lanes(1));
  child(el, "c-rfp-lane-table").dispatchEvent(
    new CustomEvent("pricingchange", {
      detail: {
        laneId: "a0L1",
        Cost__c: 1,
        Cost_Source__c: "Manual",
        Selected_Bid__c: null,
        Margin__c: 15,
        Sell__c: 1.15,
        Sell_Source__c: "Margin",
        Notes__c: null
      }
    })
  );
  await settle();
  expect(child(el, "c-rfp-lane-table").rowErrors.a0L1).toContain("Boom");
});
```

Keep the existing "saves pricing from the panel" test passing: a `pricingchange` from the panel goes through the same handler.

- [ ] **Step 2: Implement `rfpTool.js`**

Imports: `import { applyFilter, STATUS_FILTERS, siblings } from "c/rfpLaneFilter"; import { runBulk, applyBulkResult, summaryText } from "c/rfpBulk";`. State:

```js
  selectedIds = [];
  filter = { status: "all", text: "" };
  pendingIds = [];
  rowErrors = {};
  twinOffer = null; // { sourceLaneId, laneIds }
  bulkResult = null;

  get statusOptions() {
    return STATUS_FILTERS;
  }
  get visibleLanes() {
    return applyFilter(this.lanes, { ...this.filter, selectedIds: this.selectedIds });
  }
  get filterCount() {
    return `${this.visibleLanes.length} of ${this.lanes.length} lanes`;
  }
  get selectedCount() {
    return this.selectedIds.length;
  }
  get defaultMargin() {
    return this.project ? this.project.Default_Margin__c : null;
  }
  get twinText() {
    const n = this.twinOffer ? this.twinOffer.laneIds.length : 0;
    return `Apply the same cost and sell to ${n} identical lane${n === 1 ? "" : "s"}?`;
  }

  handleFilterStatus(event) {
    this.filter = { ...this.filter, status: event.detail.value };
  }
  handleFilterText(event) {
    this.filter = { ...this.filter, text: event.detail.value };
  }
  handleSelectionChange(event) {
    this.selectedIds = event.detail.laneIds || [];
  }
  handleTwinDismiss() {
    this.twinOffer = null;
  }
  handleTwinApply() {
    const { sourceLaneId, laneIds } = this.twinOffer;
    this.twinOffer = null;
    this.bulk({ action: "copy", scope: "ids", ids: laneIds, params: { sourceLaneId } });
  }
```

Rewrite `handlePricingChange` and `loadLanes` (a reload clears the selection and errors):

```js
  async loadLanes() {
    this.lanes = (await getLanes({ projectId: this.projectId })) || [];
    this.selectedIds = [];
    this.pendingIds = [];
    this.rowErrors = {};
    this.twinOffer = null;
    this.bulkResult = null;
  }

  /**
   * One lane's save, from the panel or from a table cell. Several lanes may be
   * saving at once (a quick Enter-Enter-Enter down a column); a lane already
   * saving ignores a second request until the first returns.
   */
  async handlePricingChange(event) {
    const { laneId, ...fields } = event.detail;
    if (this.busy || this.pendingIds.includes(laneId)) {
      return;
    }
    this.pendingIds = [...this.pendingIds, laneId];
    this.rowErrors = { ...this.rowErrors, [laneId]: undefined };
    try {
      const lane = await saveLanePricing({ laneJson: JSON.stringify({ Id: laneId, ...fields }) });
      this.lanes = mergeLanes(this.lanes, lane);
      const twins = siblings(this.lanes, lane);
      this.twinOffer = twins.length ? { sourceLaneId: laneId, laneIds: twins.map((l) => l.Id) } : null;
    } catch (e) {
      this.rowErrors = { ...this.rowErrors, [laneId]: apexMessage(e, "The price could not be saved.") };
    } finally {
      this.pendingIds = this.pendingIds.filter((id) => id !== laneId);
    }
  }

  handleBulk(event) {
    const { action, scope, ...params } = event.detail;
    const ids =
      scope === "selected"
        ? this.selectedIds
        : scope === "skipped"
          ? (this.bulkResult && this.bulkResult.skippedIds) || []
          : this.lanes.map((l) => l.Id);
    this.bulk({ action, scope, ids, params });
  }

  /** Every many-lane call goes through here: progress bar, Stop, merge, summary. */
  async bulk({ action, ids, params }) {
    if (this.busy || !ids.length) {
      return;
    }
    this.stopRequested = false;
    this.busy = true;
    this.error = null;
    this.twinOffer = null;
    this.progress = { done: 0, total: ids.length };
    try {
      const result = await runBulk({
        action,
        ids,
        params,
        onProgress: (n) => {
          this.progress = { done: this.progress.done + n, total: ids.length };
        },
        isStopped: () => this.stopRequested
      });
      const next = applyBulkResult(this.lanes, this.selectedIds, result);
      this.lanes = next.lanes;
      this.selectedIds = next.selectedIds;
      this.bulkResult = result;
      this.summary = summaryText(result);
    } finally {
      this.busy = false;
    }
  }
```

The panel's `rowErrors` entry set to `undefined` clears an old error without deleting keys in place (LWC tracks the new object). `pendingIds` non-empty or `busy` → the table is `locked` only while `busy` (a bulk or history run); individual pending rows are not locked table-wide.

- [ ] **Step 3: Update `rfpTool.html` and add `rfpTool.css`**

Inside the workbench block, after the summary paragraph and before the lanes grid:

```html
<c-rfp-bulk-bar
  selected-count="{selectedCount}"
  total-count="{lanes.length}"
  currency="{currency}"
  busy="{busy}"
  last-result="{bulkResult}"
  onbulk="{handleBulk}"
></c-rfp-bulk-bar>

<div
  class="slds-grid slds-wrap slds-grid_vertical-align-end slds-gutters_x-small slds-m-bottom_x-small"
>
  <div class="slds-col">
    <lightning-combobox
      data-id="filter-status"
      label="Show"
      value="{filter.status}"
      options="{statusOptions}"
      onchange="{handleFilterStatus}"
    ></lightning-combobox>
  </div>
  <div class="slds-col">
    <lightning-input
      data-id="filter-text"
      type="search"
      label="Search origin, destination, equipment"
      value="{filter.text}"
      onchange="{handleFilterText}"
    ></lightning-input>
  </div>
  <div class="slds-col">
    <span data-id="filter-count" class="slds-text-color_weak"
      >{filterCount}</span
    >
  </div>
</div>

<template lwc:if="{twinOffer}">
  <div
    data-id="twin-offer"
    class="slds-notify slds-notify_alert slds-theme_info slds-m-bottom_x-small"
    role="status"
  >
    <span>{twinText}</span>
    <lightning-button
      data-id="twin-apply"
      class="slds-m-left_x-small"
      label="Apply"
      variant="brand"
      disabled="{busy}"
      onclick="{handleTwinApply}"
    ></lightning-button>
    <lightning-button
      data-id="twin-dismiss"
      class="slds-m-left_x-small"
      label="Not now"
      onclick="{handleTwinDismiss}"
    ></lightning-button>
  </div>
</template>
```

The table element gains `lanes={visibleLanes} selected-ids={selectedIds} pending-ids={pendingIds} row-errors={rowErrors} default-margin={defaultMargin} locked={busy} onselectionchange={handleSelectionChange} onpricingchange={handlePricingChange}`. The panel column `div` gets `class="slds-col slds-size_1-of-1 slds-large-size_4-of-12 panel-col"`.

`rfpTool.css`:

```css
/* The pricing panel stays in view while the lane table scrolls underneath it.
   align-self keeps the grid from stretching the sticky item to the table's
   height (a stretched item has nowhere to stick). */
.panel-col {
  position: sticky;
  top: 0;
  align-self: flex-start;
  max-height: calc(100vh - 8rem);
  overflow-y: auto;
}
```

- [ ] **Step 4: Full Jest, lint, deploy the LWC, commit**

```bash
npm test && npx eslint force-app
sf project deploy start -x manifest/package.xml -o sandbox -l NoTestRun -w 30
git add force-app/main/default/lwc/rfpTool
git commit -m "Wire filters, selection, bulk actions, the twin offer and the sticky panel into the workbench"
```

`rfpTool.js` is expected to land around 520 lines; that is accepted for this container (the orchestration lives in `c/rfpBulk` and `c/rfpLaneFilter`). If it passes 560, move the toolbar (precision, lookback, radius, unit, the three history buttons, upload, export) into a `c/rfpToolbar` component in this task and register it in the manifest.

---

### Task 12: Export — Annual sell, Sell source, Summary sheet

**Files:**

- Modify: `force-app/main/default/lwc/rfpWorkbook/rfpWorkbook.js` (+ test), `force-app/main/default/lwc/rfpExport/rfpExport.js`

**Interfaces:**

- Produces: `OUR_COLUMNS` = `["Cost","Currency","Margin %","Sell","Annual sell","Sell source","Fuel surcharge","FSC included","Transit days","Bid carrier","Notes"]`; `buildSheets(lanes, rawRows, bidsByLaneId)` → `{ lanes, bids, summary }`; `rfpExport` writes a third sheet "Summary".

- [ ] **Step 1: Failing tests**

Add to `rfpWorkbook.test.js`:

```js
describe("annual sell and summary", () => {
  const lanes = [
    {
      Id: "1",
      Row_Number__c: 1,
      Mode__c: "Truckload",
      Cost__c: 1000,
      Margin__c: 15,
      Sell__c: 1150,
      Sell_Source__c: "Margin",
      Shipments_Per_Year__c: 52,
      CurrencyIsoCode: "CAD",
      Origin_Resolved__c: true,
      Destination_Resolved__c: true,
      Hist_Status__c: "Done"
    },
    {
      Id: "2",
      Row_Number__c: 2,
      Mode__c: "Truckload",
      Cost__c: 2000,
      Margin__c: 25,
      Sell__c: 2500,
      Sell_Source__c: "Manual",
      Shipments_Per_Year__c: 10,
      CurrencyIsoCode: "USD",
      Origin_Resolved__c: true,
      Destination_Resolved__c: true,
      Hist_Status__c: "Done"
    },
    {
      Id: "3",
      Row_Number__c: 3,
      Mode__c: "",
      Cost__c: null,
      Sell__c: null,
      Shipments_Per_Year__c: 4,
      CurrencyIsoCode: "CAD",
      Origin_Resolved__c: true,
      Destination_Resolved__c: false,
      Hist_Status__c: "No match"
    }
  ];
  const raw = lanes.map((l) => ({
    Id: l.Id,
    Raw_Row__c: JSON.stringify({ Lane: l.Id })
  }));

  it("adds Annual sell and Sell source after Sell", () => {
    const { lanes: sheet } = buildSheets(lanes, raw, {});
    const header = sheet[0];
    expect(
      header.slice(header.indexOf("Sell"), header.indexOf("Sell") + 3)
    ).toEqual(["Sell", "Annual sell", "Sell source"]);
    const row = (i) =>
      Object.fromEntries(header.map((h, j) => [h, sheet[i][j]]));
    expect(row(1)["Annual sell"]).toBe(59800);
    expect(row(1)["Sell source"]).toBe("Margin");
    expect(row(2)["Sell source"]).toBe("Manual");
    expect(row(3)["Annual sell"]).toBe("");
    expect(row(3)["Sell source"]).toBe("");
  });

  it("builds the summary sheet", () => {
    const { summary } = buildSheets(lanes, raw, {});
    expect(summary).toEqual([
      ["Lanes", 3],
      ["Priced lanes", 2],
      ["Unpriced lanes", 1],
      ["No history match", 1],
      ["Unresolved ends", 1],
      ["Total annual sell (CAD)", 59800],
      ["Total annual sell (USD)", 25000],
      ["Average margin %", 20],
      [],
      ["Mode", "Lanes", "Priced", "Annual sell"],
      ["Truckload", 2, 2, 84800],
      ["(none)", 1, 0, 0]
    ]);
  });
});
```

- [ ] **Step 2: Implement in `rfpWorkbook.js`**

`OUR_COLUMNS` becomes `["Cost", "Currency", "Margin %", "Sell", "Annual sell", "Sell source", "Fuel surcharge", "FSC included", "Transit days", "Bid carrier", "Notes"]`. Add:

```js
const isNum = (v) => typeof v === "number" && Number.isFinite(v);
const annualSell = (l) =>
  isNum(l.Sell__c) && isNum(l.Shipments_Per_Year__c)
    ? Math.round(l.Sell__c * l.Shipments_Per_Year__c * 100) / 100
    : "";
const sellSource = (l) =>
  l.Sell__c === null || l.Sell__c === undefined
    ? ""
    : l.Sell_Source__c === "Manual"
      ? "Manual"
      : "Margin";
const priced = (l) => isNum(l.Cost__c);

function summarySheet(ordered) {
  const rows = [
    ["Lanes", ordered.length],
    ["Priced lanes", ordered.filter(priced).length],
    ["Unpriced lanes", ordered.filter((l) => !priced(l)).length],
    [
      "No history match",
      ordered.filter((l) => l.Hist_Status__c === "No match").length
    ],
    [
      "Unresolved ends",
      ordered.filter((l) => !l.Origin_Resolved__c || !l.Destination_Resolved__c)
        .length
    ]
  ];
  const byCurrency = {};
  ordered.forEach((l) => {
    const a = annualSell(l);
    if (a !== "") {
      byCurrency[l.CurrencyIsoCode] = (byCurrency[l.CurrencyIsoCode] || 0) + a;
    }
  });
  Object.keys(byCurrency)
    .sort()
    .forEach((c) =>
      rows.push([
        `Total annual sell (${c})`,
        Math.round(byCurrency[c] * 100) / 100
      ])
    );
  const margins = ordered
    .filter((l) => priced(l) && isNum(l.Margin__c))
    .map((l) => l.Margin__c);
  rows.push([
    "Average margin %",
    margins.length
      ? Math.round(
          (margins.reduce((s, m) => s + m, 0) / margins.length) * 100
        ) / 100
      : ""
  ]);
  rows.push([]);
  rows.push(["Mode", "Lanes", "Priced", "Annual sell"]);
  const modes = {};
  ordered.forEach((l) => {
    const key = l.Mode__c || "(none)";
    const m = modes[key] || (modes[key] = { lanes: 0, priced: 0, annual: 0 });
    m.lanes++;
    if (priced(l)) m.priced++;
    const a = annualSell(l);
    if (a !== "") m.annual += a;
  });
  Object.keys(modes).forEach((k) =>
    rows.push([
      k,
      modes[k].lanes,
      modes[k].priced,
      Math.round(modes[k].annual * 100) / 100
    ])
  );
  return rows;
}
```

In `buildSheets`, the lane row gains `annualSell(l), sellSource(l)` right after `cell(l.Sell__c)`, and the function returns `{ lanes: laneSheet, bids: bidSheet, summary: summarySheet(ordered) }`. Mode order is first-seen order (the test's lanes are in row order). `rfpExport.run()` appends `XLSX.utils.book_append_sheet(book, XLSX.utils.aoa_to_sheet(sheets.summary), "Summary");` after the Bids sheet.

- [ ] **Step 3: Test, lint, commit**

```bash
npx jest force-app/main/default/lwc/rfpWorkbook force-app/main/default/lwc/rfpExport && npx eslint force-app/main/default/lwc
git add force-app/main/default/lwc/rfpWorkbook force-app/main/default/lwc/rfpExport
git commit -m "Add annual sell, sell source and a Summary sheet to the RFP export"
```

---

### Task 13: Docs, final deploy with tests, browser checks

**Files:**

- Modify: `README.md` (`## RFP Tool (phase 3b)` section, ~line 410: add a `### Phase 3c — pricing` subsection), `docs/superpowers/specs/2026-09-07-pricing-department-roadmap.md` (phase 3 row), `docs/superpowers/specs/2026-09-11-phase-3c-pricing-workbench-design.md` (append `## Outcome — 3c`), this plan (defects blockquote if any)

- [ ] **Step 1: README subsection** (after the 3b limits list, before `## Known issues worth fixing`):

```markdown
### Phase 3c — pricing

- **Sell and margin are linked.** Typing a margin recomputes the sell; typing a sell recomputes the margin and marks the lane `Sell source = Manual`. A Manual sell survives later cost changes (the margin moves instead). Lanes saved before 3c read as Margin.
- **Radius.** The "Radius" box (1–500, km or mi, default 50 km) is used for Radius precision and for the city → radius fallback; the snapshot stamps `RADIUS-<n>KM|MI` in `Hist_Precision__c`.
- **Bulk bar.** Scope "Selected (N)" or "All lanes (M)"; Use median (skips lanes costed from a bid or by hand, then offers "Overwrite them"), Apply margin / cost / sell, Add carrier rate (one Benchmark Rate per lane, selected as the cost; lanes in another currency are skipped), Delete selected (two clicks; takes the lanes' carrier rates). Every action runs 200 lanes per Apex call (`RfpBulkController`), user mode, with a progress bar and Stop.
- **Inline editing.** Click or press Enter on a Cost, Margin or Sell cell; Enter/Tab save and move down the column, Shift+Tab up, Escape cancels, leaving the cell saves. A row shows a sync icon while saving and a red icon (hover for the reason) when the save failed.
- **Filters.** Show: all / unpriced / no history match / unresolved ends / manual cost or sell / selected, plus a text search on origin, destination and equipment. "Select all" selects the rows shown.
- **Twins.** After a lane is priced, unpriced lanes with the same two places, mode and equipment are offered "Apply the same cost and sell to N identical lanes" (`copyPricing`: the twin points at the same bid).
- **Export.** New columns Annual sell (sell × shipments per year) and Sell source; a third sheet, Summary (counts, total annual sell per currency, average margin, by mode).
- **Permissions.** `RFP_Tool_User` can now delete `RFP_Lane__c` and `Benchmark_Rate__c`.
```

Roadmap phase 3 row: `Done 2026-09-11 (3a objects and bids; 3b workbench; 3c pricing)`. Spec Outcome: deploy ids, Jest count, rulings made during execution, what the browser checks found.

- [ ] **Step 2: Final deploy with the 22-class run**

```bash
sf project deploy start -x manifest/package.xml -o sandbox -l NoTestRun -w 30
sf project deploy start -x manifest/package.xml -o sandbox -l RunSpecifiedTests -t PricingDepartmentControllerTest PlaceNormalizerTest PricingTestDataFactoryTest PlaceBuilderBatchTest LaneSearchServiceTest MapboxGeocoderTest LaneBenchmarkControllerTest LaneBenchmarkPlaceServiceTest RfpTestDataFactoryTest BenchmarkRateServiceTest BidSearchQueryBuilderTest BidSearchServiceTest RfpControllerTest RfpSecurityTest RfpImportServiceTest RfpLaneControllerTest RfpHistoryServiceTest RfpProjectControllerTest RfpBidControllerTest RfpPricingMathTest RfpBulkServiceTest RfpBulkControllerTest -w 30
npm test
/private/tmp/pmd_install/pmd-bin-7.15.0/bin/pmd check --dir force-app --rulesets config/pmd-ruleset.xml --minimum-priority 3 --format text --fail-on-violation
```

- [ ] **Step 3: Browser checks (controller, Chrome, PostProduc)** — record each as pass / fail in the spec Outcome:

1. Sticky panel: open a project with ≥ 60 lanes, scroll to the bottom, the panel is still visible and scrolls on its own.
2. Inline edit: click a Cost cell, type, Enter → next row's Cost opens; Tab / Shift+Tab / Escape behave; a bad value shows the red text and stays open.
3. Panel sell: type a sell, margin follows; save; the table shows the "manual" tag.
4. Bulk: Use median on All → summary + "Overwrite them"; Apply margin 18 on Selected (3 lanes); Add carrier rate on 3 selected lanes (bids appear in each lane's panel); Delete 2 selected lanes (two clicks).
5. Radius 150 km + Refresh history → hover History cell shows `RADIUS-150KM` for a fallback lane.
6. Filters: Unpriced, then text "calg…", select-all selects only shown rows.
7. Export opens in Excel/Numbers: three sheets, Annual sell column, Summary totals.
8. The four 3b leftovers: Lane Benchmark "Bids only" filter, bid + manual pricing paths from the panel, existing-carrier bid, opening the exported workbook.

- [ ] **Step 4: Commit docs**

```bash
git add README.md docs/superpowers/specs/2026-09-07-pricing-department-roadmap.md docs/superpowers/specs/2026-09-11-phase-3c-pricing-workbench-design.md docs/superpowers/plans/2026-09-11-phase-3c-pricing-workbench.md
git commit -m "Document the phase 3c pricing workbench and record its outcome"
```

Then finishing: push `phase-3c/pricing-workbench` to `origin` first, then `tplm`; open PRs on both; merge only on `origin` after CI (lwc / apex / pmd) is green; push `main` to `tplm`.

---

## Self-review notes

- Spec §4.1–4.4 → Tasks 1, 2. §5.2 → Task 3. §5.3 → Task 4. §5.4 → Tasks 5, 6 (the spec's `applyMargin` was folded into `applyPricing(margin)` before this plan was written). §5.5 → Task 1. §6.1–6.3 → Tasks 2, 7. §6.4 → Task 9. §6.5 → Task 10. §6.6 → Task 8. §6.7 → Tasks 3, 11. §6.8 → Task 8. §6.9 → Task 12. §7–§10 → Tasks 6, 11, 13.
- Spec §6.6 said the delete confirm resets after 5 s; this plan resets it when the selection or scope changes instead (no timer, no `setTimeout` disable). Spec §6.4 said "spinner"; a `utility:sync` icon is used (a `lightning-spinner` is absolutely positioned and would sit over the row). Spec §6.7 said ~450 lines for `rfpTool.js`; Task 11 accepts ~520 and names the fallback. The spec is amended to match.
- Names used across tasks: `RfpBulkService.Result` (Tasks 5, 6, 8, 11), `runBulk`/`applyBulkResult`/`summaryText` (8, 11), `inlineEdit`/`recompute`/`pricingFingerprint`/`parseMoney` (7, 9, 10), `applyFilter`/`siblings`/`STATUS_FILTERS` (7, 11), `selectionchange`/`pricingchange`/`bulk` events (8, 9, 10, 11), `loadHistory(laneIds, precision, lookbackDays, radius, radiusUnit)` (3).
