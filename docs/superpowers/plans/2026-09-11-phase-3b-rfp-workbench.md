# Phase 3b: RFP Workbench Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the RFP tool page: upload a customer lane file, map its columns, import lanes, load carrier-quote history per lane, price lanes (bid, median or manual cost plus margin), record carrier bids, and export the customer's file with our prices, on top of the 3a foundation.

**Architecture:** Four thin `@AuraEnabled` controllers (`RfpProjectController`, `RfpLaneController`, `RfpHistoryController`, `RfpBidController`) over two services (`RfpImportService`, `RfpHistoryService`) and the existing `BenchmarkRateService`/`LaneSearchService`. The browser parses the workbook with the org's `sheetJs` static resource (SheetJS 0.18.5) through pure modules (`rfpSheet`, `rfpHeaderGuess`, `rfpWorkbook`, `rfpMath`) that are Jest-tested without SheetJS. A container `rfpTool` routes between the project list and the workbench (`rfpUpload` → `rfpColumnMapper` → `rfpLaneTable` + `rfpLanePanel` + `rfpBidForm` + `rfpExport`). Lanes and bids travel to the browser as the SObjects themselves (queried in user mode), never as DTOs.

**Tech Stack:** Salesforce DX (API 64.0), Apex, LWC, Jest (`@salesforce/sfdx-lwc-jest`), ESLint (`@salesforce/eslint-config-lwc/recommended`), Prettier, PMD 7.15.0 quickstart P3, SheetJS 0.18.5 (org static resource `sheetJs`, not in the repo), PostProduc sandbox (alias `sandbox`).

**Spec:** `docs/superpowers/specs/2026-09-10-phase-3-rfp-tool-design.md` (sections Components, Flow, Error handling, Limits; "Implementation split" plan 3b; "Outcome — 3a" for what already exists).

## Global Constraints

- Only org alias `sandbox` (PostProduc). Never `vscodeOrg`, `Full`, `devpro`.
- Every deploy passes every test class with `-t`. Start of this plan: `PricingDepartmentControllerTest PlaceNormalizerTest PricingTestDataFactoryTest PlaceBuilderBatchTest LaneSearchServiceTest MapboxGeocoderTest LaneBenchmarkControllerTest LaneBenchmarkPlaceServiceTest RfpTestDataFactoryTest BenchmarkRateServiceTest BidSearchQueryBuilderTest BidSearchServiceTest RfpControllerTest`. Each task that adds a test class appends it to this list, to `.github/workflows/ci.yml` (`--tests` line) and to BOTH README commands and the README "Apex tests" row in the same commit.
- Deploy in the foreground: `sf project deploy start -x manifest/package.xml -o sandbox -l RunSpecifiedTests -t <list> -w 30`; poll `sf project deploy report -o sandbox -i <id> -w 10` in the foreground if it returns early; never wait on a background notification. When a permission set changes in the same deploy as new user-mode code, deploy the permission set first with `-l NoTestRun`, then the test-running deploy.
- PMD: `/private/tmp/pmd_install/pmd-bin-7.15.0/bin/pmd check --dir force-app --rulesets config/pmd-ruleset.xml --minimum-priority 3 --format text --fail-on-violation` exits 0 before every commit. Per-method cyclomatic ≤ 10, class total ≤ 40, `TooManyFields` ≤ 20: split, never suppress (the documented `PMD.ApexCRUDViolation` suppression is allowed only on system-mode phase 1 search code, not in RFP classes).
- Jest `npm test`, lint `npm run lint`, `npx prettier --check`; pre-commit hook must pass; never `--no-verify`. Commit messages carry no trailers.
- `@api` values mutated internally use get/set backing fields; every `setTimeout`/`setInterval` carries the one-line eslint-disable with a reason; base-component text is never asserted through `textContent`.
- RFP Apex runs in user mode: SOQL `WITH USER_MODE`, DML `Database.insert/update(records, AccessLevel.USER_MODE)` after `Security.stripInaccessible`. `LaneSearchService`/`BidSearchService` stay system mode by documented design. All SOQL bound; no user text concatenated.
- No secrets. `sheetJs` static resource stays org-side (owned by another team; version verified 0.18.5); referenced through `@salesforce/resourceUrl/sheetJs`.
- Implementers do not call the advisor tool, do not dispatch subagents, and re-retrieve `TransPro.app-meta.xml` from the org before editing it (Task 9).

## Rulings that amend the spec (recorded here, ledgered by the controller)

1. `lightning-file-upload` cannot hand the bytes to the browser. `rfpUpload` uses a plain `<input type="file">` read by `FileReader` (parse with SheetJS) and sends base64 to `RfpProjectController.attachFile(projectId, fileName, base64)`, which inserts `ContentVersion` + `ContentDocumentLink` in user mode. Client-side cap 3 MB.
2. History runs 10 lanes per call with `rowLimit` 500 (not 20 / 2000): each lane is up to two searches (CITY, then RADIUS 50 km fallback) and a busy lane at 2000 rows is megabytes of heap. `LaneSearchException` per lane (for example a place without coordinates) → `Hist_Status__c = 'No match'`; any other exception → `'Failed'`; a chunk never fails as a whole.
3. `getLanes` never returns `Raw_Row__c`; `getRawRows(projectId, offset)` pages 500 rows for export only.
4. Import rows use nested `RowEnd origin/destination` objects (TooManyFields). Lanes and bids go to the LWC as SObjects (`RFP_Lane__c`, `Benchmark_Rate__c`), queried in user mode.
5. `RfpController` keeps only `projectsForAccount`; the workbench methods live in `RfpProjectController`, `RfpLaneController`, `RfpHistoryController`, `RfpBidController` (each thin, each registered in `RFP_Tool_User.classAccesses` in the commit that creates it).
6. `BenchmarkRateService.save` strips non-writable fields with `Security.stripInaccessible` before user-mode DML (the 3a deferral). `saveLanePricing` updates only `Cost__c, Cost_Source__c, Selected_Bid__c, Margin__c, Sell__c, Notes__c`. Place fixes go through `resolveLaneEnd(laneId, side, placeKey)`.
7. Export writes strings as typed `xlsx` string cells (SheetJS type `s`), never evaluated by Excel, so no apostrophe prefix (the spec's CSV-style guard would put literal quotes into customer cells). The workbook is built by a pure `rfpWorkbook.buildSheets` (arrays of arrays) and written with `XLSX.write(wb, { type: "array" })` → `Blob` → the attach-anchor/deferred-revoke download pattern from `laneBenchmarkResults` (not `XLSX.writeFile`).
8. Sell price reuses `c/marginMath.suggestedSell`; `rfpMath` adds `bestBid` only. `slug()` is exported from `c/laneBenchmarkCsv` for the export file name.
9. Mode/equipment from the spreadsheet are free text and rarely match Revenova names, so history searches carry no mode/equipment filter in 3b (recorded as a deferral).
10. Postal-prefix resolution picks, among places sharing the prefix (and the row's country when known), the one with the highest `Load_Count_365d__c`. When a row has no country, the city key is tried for CA, then US, then MX.
11. The carrier and customer lookups are Apex typeaheads (`RfpProjectController.searchAccounts(term, kind)` filtered by record type), rendered with the same list markup as `laneBenchmarkPlacePicker` — `lightning-record-picker` has no Jest stub in this project.
12. `rfpProjectsForAccount` retargets its row click to `standard__navItemPage` `{ apiName: "RFP_Tool", state: { c__projectId } }`; `rfpTool` reads `c__projectId` from `CurrentPageReference`.
13. runAs tests: a test-only user is created inside `System.runAs(new User(Id = UserInfo.getUserId()))` to avoid `MIXED_DML_OPERATION`; the profile is `Standard User` if it exists, else `Minimum Access - Salesforce`; if neither exists or no license is free, the runAs class is skipped and the ledger says so.

> **Defects found in this plan's verbatim code during execution:**
>
> - Task 1's runAs test (`rfpToolUserOnlyCanSaveABidAndLaneBenchmarkUserSeesIt`) never asserted the field `save()` strips, so the suite passed even with the `Security.stripInaccessible` strip reverted; fixed by having the runAs test re-save a queried bid under the restricted user and assert `Rate__c`/`City_Lane__c`, with discrimination proven by deploying once with the fix reverted (fix round 1).
> - Task 2's `resolveLaneEnd` set `Hist_Status__c = 'Pending'` regardless of the other end's resolution state, so resolving one end of a still-unresolved lane wrongly marked it ready for history; fixed to set `'Pending'` only when the other end is already resolved, else `'Unresolved'` (Ruling R4).
> - Task 3's history-write DML used `allOrNone = true`, so one lane failing inside a 10-lane chunk discarded the history snapshot for every lane in that chunk; fixed to `allOrNone = false` with a best-effort `Hist_Status__c = 'Failed'` flip on the ids that failed (Ruling R6). The review also found the `'Failed'` and legitimate `'No match'` branches untested; a PROVINCE no-match test was added, though the generic `'Failed'` catch inside `snapshot()` stays untested — no cheap trigger for it (Ruling R7).
> - Task 4's `listProjects` returned `Column_Mapping__c`/`Notes__c` (long text fields) for every one of up to 200 rows in the project list; fixed by splitting a `LIST_FIELDS` set from `DETAIL_FIELDS` (Ruling R8).
> - Task 5's `rfpWorkbook.buildSheets` selected-bid column match was untested; a test using real bid and lane ids was added (Ruling R10).
> - Task 2's `toLane` copied every mapped spreadsheet cell into the lane verbatim, into fields narrower than the data (`Mode__c` Text(40), `Equipment_Category__c` Text(40), `Quantity_Unit__c` Text(20), `Origin_Postal__c`/`Destination_Postal__c` Text(12)), and the insert was all-or-nothing: one 60-character mode threw STRING_TOO_LONG and discarded the whole 200-row chunk. Fixed by cutting every free-text field to its own schema length in `toLane` (and giving `trimmed()` the cap as a parameter) and by running the insert with `allOrNone = false`, counting the rows the platform still refuses into a new `Summary.failed` the container shows next to `imported` (final review C1).
> - Task 3's history statistics fell back to the first currency bucket when the lane's own `CurrencyIsoCode` had none (`s = r.statsByCurrency.values()[0]` in `RfpHistoryService.fill`), so a USD median could be stamped on a CAD lane and marked up as if it were Canadian. Fixed to read only the lane's own bucket, leaving min/median/average/max null when it is absent while the count and the `Done` status stand (final review I4, Ruling R19).
> - The plan's constraint that `sheetJs` "stays org-side" and resolves through a bare `@salesforce/resourceUrl/sheetJs` reference was wrong: the org's `sheetJs` StaticResource belongs to the EN6IA managed package, so the reference cannot resolve, and Task 9's deploy rolled back twice on "Invalid reference sheetJs of type resourceUrl" before the cause was found. Fixed by vendoring SheetJS Community Edition 0.18.5 (Apache-2.0, 881,727 bytes, matching the org copy) as a repo-owned `sheetJs` static resource, registered in the manifest (Ruling R16).

---

## File structure

| Path                                                                                                                                                                                                       | Responsibility                                                    |
| ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------- |
| `force-app/main/default/classes/BenchmarkRateService.cls` (modify)                                                                                                                                         | `save` strips non-writable fields                                 |
| `force-app/main/default/classes/RfpSecurityTest.cls`                                                                                                                                                       | runAs tests; end-to-end PROVINCE/ZIP3/RADIUS bid searches         |
| `force-app/main/default/classes/RfpImportService.cls` (+Test), `RfpLaneController.cls` (+Test)                                                                                                             | Import rows → lanes; lane list; pricing; end resolution; raw rows |
| `force-app/main/default/classes/RfpHistoryService.cls` (+Test), `RfpHistoryController.cls`                                                                                                                 | History snapshots                                                 |
| `force-app/main/default/classes/RfpProjectController.cls` (+Test), `RfpBidController.cls` (+Test)                                                                                                          | Projects, mapping, typeahead, file attach; bids                   |
| `force-app/main/default/lwc/rfpHeaderGuess`, `rfpSheet`, `rfpWorkbook`, `rfpMath`                                                                                                                          | Pure modules                                                      |
| `force-app/main/default/lwc/rfpUpload`, `rfpColumnMapper`, `rfpLaneTable`, `rfpLanePanel`, `rfpBidForm`, `rfpAccountPicker`, `rfpProjectList`, `rfpExport`, `rfpTool`                                      | UI                                                                |
| `force-app/main/default/lwc/laneBenchmarkCsv/laneBenchmarkCsv.js` (modify)                                                                                                                                 | export `slug`                                                     |
| `force-app/main/default/lwc/rfpProjectsForAccount/rfpProjectsForAccount.js` (modify)                                                                                                                       | navigation retarget                                               |
| `force-app/main/default/flexipages/RFP_Tool.flexipage-meta.xml`, `tabs/RFP_Tool.tab-meta.xml`, `applications/Lane_Benchmark.app-meta.xml` (modify), `applications/TransPro.app-meta.xml` (retrieve+modify) | Navigation                                                        |
| `force-app/main/default/permissionsets/RFP_Tool_User.permissionset-meta.xml` (modify)                                                                                                                      | classAccesses, tabSettings, applicationVisibilities               |
| `manifest/package.xml`, `.github/workflows/ci.yml`, `README.md`, spec Outcome, roadmap                                                                                                                     | Registration and docs                                             |

---

### Task 1: Harden `save()`, runAs tests, end-to-end precision tests

**Files:**

- Modify: `force-app/main/default/classes/BenchmarkRateService.cls` (`save`)
- Modify: `force-app/main/default/classes/BenchmarkRateServiceTest.cls` (one test)
- Create: `force-app/main/default/classes/RfpSecurityTest.cls` (+meta)
- Modify: manifest, CI/README lists

**Interfaces:**

- `BenchmarkRateService.save(Benchmark_Rate__c bid)` keeps its signature; internally `Security.stripInaccessible(AccessType.CREATABLE|UPDATABLE, ...)` before USER_MODE DML.
- Produces: `RfpSecurityTest.restrictedUser(String permSetName)` pattern reused by later tests (private in this class; later tasks copy the eight lines rather than share).

- [ ] **Step 1: Failing tests**

Add to `BenchmarkRateServiceTest`:

```apex
  @IsTest
  static void saveUpdateStripsServiceMaintainedFields() {
    Fx f = fx();
    Benchmark_Rate__c saved = BenchmarkRateService.save(RfpTestDataFactory.buildBid(f.lane, 1500));
    // A queried record carries City_Lane__c etc.; passing it back must not fail or rewrite them.
    Benchmark_Rate__c queried = [SELECT Id, Rate__c, City_Lane__c, State_Lane__c, Zip3_Lane__c FROM Benchmark_Rate__c WHERE Id = :saved.Id];
    queried.Rate__c = 1600;
    Benchmark_Rate__c again = BenchmarkRateService.save(queried);
    System.assertEquals(1600, again.Rate__c);
    System.assertEquals('Montréal, QC:Toronto, ON', again.City_Lane__c, 'keys re-stamped by the trigger, not by save');
  }
```

Create `RfpSecurityTest`:

```apex
@IsTest
private class RfpSecurityTest {
  /** Creates a user holding only the named permission set. Returns null when the org has no usable profile. */
  private static User restrictedUser(String permSetName) {
    List<Profile> profiles = [
      SELECT Id
      FROM Profile
      WHERE Name IN ('Standard User', 'Minimum Access - Salesforce')
      ORDER BY Name DESC
      LIMIT 1
    ];
    if (profiles.isEmpty()) {
      return null;
    }
    User u = new User(
      ProfileId = profiles[0].Id,
      Username = 'rfp.' + System.currentTimeMillis() + '@example.invalid',
      Email = 'rfp@example.invalid',
      LastName = 'Rfp',
      Alias = 'rfp',
      TimeZoneSidKey = 'America/Toronto',
      LocaleSidKey = 'en_CA',
      EmailEncodingKey = 'UTF-8',
      LanguageLocaleKey = 'en_US'
    );
    PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = :permSetName];
    System.runAs(new User(Id = UserInfo.getUserId())) {
      insert u;
      insert new PermissionSetAssignment(
        AssigneeId = u.Id,
        PermissionSetId = ps.Id
      );
    }
    return u;
  }

  private class Fx {
    PricingTestDataFactory.Graph g;
    Pricing_Place__c mtl;
    Pricing_Place__c laval;
    Pricing_Place__c tor;
    RFP_Lane__c lane;
  }
  private static Fx fx() {
    Fx f = new Fx();
    f.g = PricingTestDataFactory.createGraph();
    f.mtl = RfpTestDataFactory.createPlace(
      'Montréal',
      'QC',
      'CA',
      45.5019,
      -73.5674,
      'H1A'
    );
    f.laval = RfpTestDataFactory.createPlace(
      'Laval',
      'QC',
      'CA',
      45.6066,
      -73.7124,
      'H7P'
    );
    f.tor = RfpTestDataFactory.createPlace(
      'Toronto',
      'ON',
      'CA',
      43.6532,
      -79.3832,
      'M5V'
    );
    f.lane = RfpTestDataFactory.createLane(
      RfpTestDataFactory.createProject(f.g.customer),
      f.mtl,
      f.tor
    );
    PricingDepartmentController.excludedContactIdsOverride = new Set<String>();
    return f;
  }
  private static LaneSearchRequest req(
    String o,
    String d,
    LaneSearchRequest.Precision p
  ) {
    LaneSearchRequest r = new LaneSearchRequest();
    r.originKey = o;
    r.destinationKey = d;
    r.originPrecision = p;
    r.destinationPrecision = p;
    if (p == LaneSearchRequest.Precision.RADIUS) {
      r.originRadius = 50;
      r.destinationRadius = 50;
      r.radiusUnit = LaneSearchRequest.Unit.KM;
    }
    r.sourceFilter = LaneSearchRequest.RowSource.BIDS;
    return r;
  }

  @IsTest
  static void bidIsFoundAtEveryPrecision() {
    Fx f = fx();
    BenchmarkRateService.save(RfpTestDataFactory.buildBid(f.lane, 1200));
    Test.startTest();
    LaneSearchResult city = LaneSearchService.search(
      req('montreal|qc|ca', 'toronto|on|ca', LaneSearchRequest.Precision.CITY)
    );
    LaneSearchResult prov = LaneSearchService.search(
      req('laval|qc|ca', 'toronto|on|ca', LaneSearchRequest.Precision.PROVINCE)
    );
    LaneSearchResult zip3 = LaneSearchService.search(
      req('montreal|qc|ca', 'toronto|on|ca', LaneSearchRequest.Precision.ZIP3)
    );
    LaneSearchResult radius = LaneSearchService.search(
      req('laval|qc|ca', 'toronto|on|ca', LaneSearchRequest.Precision.RADIUS)
    );
    Test.stopTest();
    System.assertEquals(1, city.rows.size(), 'CITY');
    System.assertEquals(
      1,
      prov.rows.size(),
      'PROVINCE (QC:ON matches from Laval)'
    );
    System.assertEquals(1, zip3.rows.size(), 'ZIP3 H1A:M5V');
    System.assertEquals(
      1,
      radius.rows.size(),
      'RADIUS 50 km from Laval reaches Montréal'
    );
    System.assertNotEquals(null, radius.rows[0].bid);
  }

  @IsTest
  static void rfpToolUserOnlyCanSaveABidAndLaneBenchmarkUserSeesIt() {
    Fx f = fx();
    User pricing = restrictedUser('RFP_Tool_User');
    User viewer = restrictedUser('Lane_Benchmark_User');
    if (pricing == null || viewer == null) {
      System.assert(
        true,
        'no usable profile in this org; runAs coverage skipped (ledgered)'
      );
      return;
    }
    Test.startTest();
    Benchmark_Rate__c saved;
    System.runAs(pricing) {
      saved = BenchmarkRateService.save(
        RfpTestDataFactory.buildBid(f.lane, 900)
      );
    }
    Integer seen;
    System.runAs(viewer) {
      seen = LaneSearchService.search(
          req(
            'montreal|qc|ca',
            'toronto|on|ca',
            LaneSearchRequest.Precision.CITY
          )
        )
        .rows.size();
    }
    Test.stopTest();
    System.assertEquals(
      'Montréal, QC:Toronto, ON',
      [SELECT City_Lane__c FROM Benchmark_Rate__c WHERE Id = :saved.Id]
      .City_Lane__c
    );
    System.assertEquals(1, seen);
  }
}
```

Note: the lane fixture's project is created by the deploying user; the restricted user only needs create on `Benchmark_Rate__c` (granted) and read on the lane (`RFP_Tool_User` grants read). If the org's sharing for `RFP_Lane__c` hides the lane from the restricted user (it is Public Read/Write via its parent), report it.

- [ ] **Step 2: Implement**

In `BenchmarkRateService.save`:

```apex
  public static Benchmark_Rate__c save(Benchmark_Rate__c bid) {
    if (bid.Rate__c == null) {
      throw new LaneSearchException('A bid needs a rate.');
    }
    Boolean isInsert = bid.Id == null;
    // Drop every field the running user may not write (the trigger re-stamps the service-maintained ones).
    SObjectAccessDecision decision = Security.stripInaccessible(
      isInsert ? AccessType.CREATABLE : AccessType.UPDATABLE,
      new List<Benchmark_Rate__c>{ bid }
    );
    Benchmark_Rate__c clean = (Benchmark_Rate__c) decision.getRecords()[0];
    if (isInsert) {
      Database.insert(clean, AccessLevel.USER_MODE);
    } else {
      Database.update(clean, AccessLevel.USER_MODE);
    }
    return reload(clean.Id);
  }
```

(`stripInaccessible` keeps `Id` on update.) Update the class doc comment: save strips, the trigger stamps.

- [ ] **Step 3: Register, deploy, PMD, commit**

Manifest `ApexClass` `RfpSecurityTest`; CI/README lists (14 classes). Deploy (expected Succeeded; count reported). Commit: `Strip non-writable bid fields in save(); add runAs and precision coverage for bids`.

---

### Task 2: RfpImportService and RfpLaneController

**Files:**

- Create: `force-app/main/default/classes/RfpImportService.cls` (+meta), `RfpImportServiceTest.cls` (+meta), `RfpLaneController.cls` (+meta), `RfpLaneControllerTest.cls` (+meta)
- Modify: `force-app/main/default/permissionsets/RFP_Tool_User.permissionset-meta.xml` (classAccesses `RfpImportService`, `RfpLaneController`), manifest, CI/README lists

**Interfaces:**

- `RfpImportService.ImportRow { Integer rowNumber; RowEnd origin; RowEnd destination; String mode; String equipmentCategory; String equipmentType; String commodity; Decimal quantity; String quantityUnit; Integer shipmentsPerYear; Decimal fuelSurcharge; Boolean fscIncluded; Boolean hazmat; String raw; }` and `RowEnd { String city; String province; String country; String postal; }` — deserialized from the LWC JSON.
- `RfpImportService.Summary { Integer imported = 0; Integer skipped = 0; Integer unresolvedEnds = 0; }` (`@AuraEnabled` fields).
- `public static Summary importRows(Id projectId, List<ImportRow> rows)` — user mode; ≤ 200 rows per call (throws `LaneSearchException` above 200).
- `RfpLaneController`: `@AuraEnabled public static RfpImportService.Summary importLanes(Id projectId, String rowsJson)`; `@AuraEnabled(cacheable=false) public static List<RFP_Lane__c> getLanes(Id projectId)` (all fields except `Raw_Row__c`, plus `Origin_Place__r.Key__c`, `Destination_Place__r.Key__c`, `Selected_Bid__r.Carrier_Display__c`; `ORDER BY Row_Number__c`; `LIMIT 2000`); `getRawRows(Id projectId, Integer offset)` (`Id, Row_Number__c, Raw_Row__c`, `LIMIT 500 OFFSET :offset`); `saveLanePricing(String laneJson)` → whitelist update, returns the lane as `getLanes` shapes it; `resolveLaneEnd(Id laneId, String side, String placeKey)` (`side` = `origin` | `destination`) → copies City/Province/Country/Postal from the place, sets the lookup and `*_Resolved__c = true`, `Hist_Status__c = 'Pending'`, returns the lane. All errors → `AuraHandledException` via a private `userError` (copy the two-line setMessage pattern from `RfpController`).

- [ ] **Step 1: Failing tests**

`RfpImportServiceTest`:

```apex
@IsTest
private class RfpImportServiceTest {
  private static RfpImportService.ImportRow row(
    Integer n,
    String oCity,
    String oProv,
    String oCountry,
    String oPostal,
    String dCity,
    String dProv,
    String dCountry,
    String dPostal
  ) {
    RfpImportService.ImportRow r = new RfpImportService.ImportRow();
    r.rowNumber = n;
    r.origin = new RfpImportService.RowEnd();
    r.origin.city = oCity;
    r.origin.province = oProv;
    r.origin.country = oCountry;
    r.origin.postal = oPostal;
    r.destination = new RfpImportService.RowEnd();
    r.destination.city = dCity;
    r.destination.province = dProv;
    r.destination.country = dCountry;
    r.destination.postal = dPostal;
    r.raw = '{"Origin":"' + oCity + '"}';
    return r;
  }

  @IsTest
  static void resolvesByCityThenPostalAndFlagsTheRest() {
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
    Pricing_Place__c laval = RfpTestDataFactory.createPlace(
      'Laval',
      'QC',
      'CA',
      45.6066,
      -73.7124,
      'H7P'
    );
    laval.Load_Count_365d__c = 40;
    Pricing_Place__c lavalWest = RfpTestDataFactory.createPlace(
      'Laval-Ouest',
      'QC',
      'CA',
      45.55,
      -73.85,
      'H7P'
    );
    lavalWest.Load_Count_365d__c = 3;
    update new List<Pricing_Place__c>{ laval, lavalWest };
    RFP_Project__c p = RfpTestDataFactory.createProject(g.customer);
    p.CurrencyIsoCode = 'USD';
    update p;
    List<RfpImportService.ImportRow> rows = new List<RfpImportService.ImportRow>{
      row(1, 'Montreal', 'Quebec', 'Canada', null, 'TORONTO', 'ON', null, null), // city keys; blank country tries CA first
      row(2, null, null, 'CA', 'H7P 1T2', 'Toronto', 'ON', 'CA', null), // postal prefix -> Laval (highest load count)
      row(3, 'Nowhere', 'ZZ', 'CA', null, 'Toronto', 'ON', 'CA', null), // unresolved origin
      row(4, null, null, null, null, null, null, null, null) // skipped
    };
    rows[0].mode = 'Truckload';
    rows[0].quantity = 2;
    rows[0].fscIncluded = true;
    Test.startTest();
    RfpImportService.Summary s = RfpImportService.importRows(p.Id, rows);
    Test.stopTest();
    System.assertEquals(3, s.imported);
    System.assertEquals(1, s.skipped);
    System.assertEquals(1, s.unresolvedEnds);
    List<RFP_Lane__c> lanes = [
      SELECT
        Row_Number__c,
        Origin_Place__r.Key__c,
        Destination_Place__r.Key__c,
        Origin_Resolved__c,
        Destination_Resolved__c,
        Origin_City__c,
        Origin_Province__c,
        Origin_Country__c,
        Hist_Status__c,
        Margin__c,
        CurrencyIsoCode,
        Mode__c,
        Quantity__c,
        Customer_FSC_Included__c,
        Raw_Row__c
      FROM RFP_Lane__c
      WHERE RFP_Project__c = :p.Id
      ORDER BY Row_Number__c
    ];
    System.assertEquals('montreal|qc|ca', lanes[0].Origin_Place__r.Key__c);
    System.assertEquals('toronto|on|ca', lanes[0].Destination_Place__r.Key__c);
    System.assertEquals(
      'QC',
      lanes[0].Origin_Province__c,
      'province normalized to the code'
    );
    System.assertEquals('CA', lanes[0].Origin_Country__c);
    System.assertEquals('Pending', lanes[0].Hist_Status__c);
    System.assertEquals(15, lanes[0].Margin__c);
    System.assertEquals('USD', lanes[0].CurrencyIsoCode);
    System.assertEquals('Truckload', lanes[0].Mode__c);
    System.assertEquals(2, lanes[0].Quantity__c);
    System.assertEquals(true, lanes[0].Customer_FSC_Included__c);
    System.assert(lanes[0].Raw_Row__c.contains('Montreal'));
    System.assertEquals(
      'laval|qc|ca',
      lanes[1].Origin_Place__r.Key__c,
      'postal prefix picks the busiest place'
    );
    System.assertEquals(false, lanes[2].Origin_Resolved__c);
    System.assertEquals('Unresolved', lanes[2].Hist_Status__c);
  }

  @IsTest
  static void rejectsMoreThan200Rows() {
    PricingTestDataFactory.Graph g = PricingTestDataFactory.createGraph();
    RFP_Project__c p = RfpTestDataFactory.createProject(g.customer);
    List<RfpImportService.ImportRow> rows = new List<RfpImportService.ImportRow>();
    for (Integer i = 0; i < 201; i++) {
      rows.add(row(i + 1, 'A', 'QC', 'CA', null, 'B', 'ON', 'CA', null));
    }
    try {
      RfpImportService.importRows(p.Id, rows);
      System.assert(false, 'expected an exception');
    } catch (LaneSearchException e) {
      System.assert(e.getMessage().contains('200'), e.getMessage());
    }
  }
}
```

`RfpLaneControllerTest`:

```apex
@IsTest
private class RfpLaneControllerTest {
  private class Fx {
    PricingTestDataFactory.Graph g;
    RFP_Project__c project;
    RFP_Lane__c lane;
    Pricing_Place__c mtl;
    Pricing_Place__c tor;
  }
  private static Fx fx() {
    Fx f = new Fx();
    f.g = PricingTestDataFactory.createGraph();
    f.mtl = RfpTestDataFactory.createPlace(
      'Montréal',
      'QC',
      'CA',
      45.5019,
      -73.5674,
      'H1A'
    );
    f.tor = RfpTestDataFactory.createPlace(
      'Toronto',
      'ON',
      'CA',
      43.6532,
      -79.3832,
      'M5V'
    );
    f.project = RfpTestDataFactory.createProject(f.g.customer);
    f.lane = RfpTestDataFactory.createLane(f.project, f.mtl, f.tor);
    return f;
  }

  @IsTest
  static void importGetLanesAndRawRowsRoundTrip() {
    Fx f = fx();
    String rowsJson = '[{"rowNumber":7,"origin":{"city":"Montreal","province":"QC","country":"CA"},"destination":{"city":"Toronto","province":"ON","country":"CA"},"raw":"{\\"A\\":\\"x\\"}"}]';
    RfpImportService.Summary s = RfpLaneController.importLanes(
      f.project.Id,
      rowsJson
    );
    System.assertEquals(1, s.imported);
    List<RFP_Lane__c> lanes = RfpLaneController.getLanes(f.project.Id);
    System.assertEquals(2, lanes.size());
    System.assertEquals('montreal|qc|ca', lanes[1].Origin_Place__r.Key__c);
    System.assert(
      !lanes[1].isSet('Raw_Row__c'),
      'getLanes excludes Raw_Row__c'
    );
    List<RFP_Lane__c> raw = RfpLaneController.getRawRows(f.project.Id, 0);
    System.assertEquals(2, raw.size());
    System.assertEquals('{"A":"x"}', raw[1].Raw_Row__c);
  }

  @IsTest
  static void saveLanePricingWhitelistsFields() {
    Fx f = fx();
    String laneJson =
      '{"Id":"' +
      f.lane.Id +
      '","Cost__c":1000,"Cost_Source__c":"Manual","Margin__c":20,"Sell__c":1200,"Notes__c":"n","Origin_City__c":"HACKED","Hist_Count__c":99}';
    RFP_Lane__c out = RfpLaneController.saveLanePricing(laneJson);
    RFP_Lane__c db = [
      SELECT
        Cost__c,
        Cost_Source__c,
        Margin__c,
        Sell__c,
        Notes__c,
        Origin_City__c,
        Hist_Count__c
      FROM RFP_Lane__c
      WHERE Id = :f.lane.Id
    ];
    System.assertEquals(1000, db.Cost__c);
    System.assertEquals('Manual', db.Cost_Source__c);
    System.assertEquals(20, db.Margin__c);
    System.assertEquals(1200, db.Sell__c);
    System.assertEquals('n', db.Notes__c);
    System.assertEquals(
      'Montréal',
      db.Origin_City__c,
      'non-pricing fields ignored'
    );
    System.assertEquals(null, db.Hist_Count__c);
    System.assertEquals(1200, out.Sell__c);
  }

  @IsTest
  static void resolveLaneEndCopiesThePlaceAndResetsHistory() {
    Fx f = fx();
    Pricing_Place__c laval = RfpTestDataFactory.createPlace(
      'Laval',
      'QC',
      'CA',
      45.6066,
      -73.7124,
      'H7P'
    );
    f.lane.Hist_Status__c = 'Done';
    update f.lane;
    RFP_Lane__c out = RfpLaneController.resolveLaneEnd(
      f.lane.Id,
      'origin',
      'laval|qc|ca'
    );
    System.assertEquals(laval.Id, out.Origin_Place__c);
    System.assertEquals('Laval', out.Origin_City__c);
    System.assertEquals('H7P', out.Origin_Postal__c);
    System.assertEquals(true, out.Origin_Resolved__c);
    System.assertEquals('Pending', out.Hist_Status__c);
    try {
      RfpLaneController.resolveLaneEnd(f.lane.Id, 'sideways', 'laval|qc|ca');
      System.assert(false, 'expected an error');
    } catch (AuraHandledException e) {
      System.assert(e.getMessage().contains('origin'), e.getMessage());
    }
  }
}
```

- [ ] **Step 2: Implement `RfpImportService`**

```apex
/**
 * Turns mapped spreadsheet rows into RFP_Lane__c records (user mode). Each end is resolved to a
 * Pricing_Place__c by city|province|country key first (trying CA, US, MX when the row has no
 * country), then by postal prefix (busiest place wins). Ends that resolve nowhere are flagged so
 * the workbench can ask for a manual pick.
 */
public with sharing class RfpImportService {
  public class RowEnd {
    public String city;
    public String province;
    public String country;
    public String postal;
  }
  public class ImportRow {
    public Integer rowNumber;
    public RowEnd origin;
    public RowEnd destination;
    public String mode;
    public String equipmentCategory;
    public String equipmentType;
    public String commodity;
    public Decimal quantity;
    public String quantityUnit;
    public Integer shipmentsPerYear;
    public Decimal fuelSurcharge;
    public Boolean fscIncluded;
    public Boolean hazmat;
    public String raw;
  }
  public class Summary {
    @AuraEnabled
    public Integer imported = 0;
    @AuraEnabled
    public Integer skipped = 0;
    @AuraEnabled
    public Integer unresolvedEnds = 0;
  }
  private static final List<String> COUNTRY_ORDER = new List<String>{
    'CA',
    'US',
    'MX'
  };
  private static final Integer MAX_ROWS = 200;

  public static Summary importRows(Id projectId, List<ImportRow> rows) {
    if (rows.size() > MAX_ROWS) {
      throw new LaneSearchException(
        'Import at most ' + MAX_ROWS + ' rows per call.'
      );
    }
    RFP_Project__c project = [
      SELECT Id, Default_Margin__c, CurrencyIsoCode
      FROM RFP_Project__c
      WHERE Id = :projectId
      WITH USER_MODE
    ];
    Summary s = new Summary();
    Resolver resolver = new Resolver(rows);
    List<RFP_Lane__c> lanes = new List<RFP_Lane__c>();
    for (ImportRow r : rows) {
      if (isEmpty(r.origin) && isEmpty(r.destination)) {
        s.skipped++;
        continue;
      }
      RFP_Lane__c lane = toLane(project, r);
      s.unresolvedEnds += applyEnd(lane, r.origin, resolver, true);
      s.unresolvedEnds += applyEnd(lane, r.destination, resolver, false);
      lane.Hist_Status__c = lane.Origin_Resolved__c &&
        lane.Destination_Resolved__c
        ? 'Pending'
        : 'Unresolved';
      lanes.add(lane);
    }
    List<SObject> clean = Security.stripInaccessible(
        AccessType.CREATABLE,
        lanes
      )
      .getRecords();
    Database.insert(clean, AccessLevel.USER_MODE);
    s.imported = clean.size();
    return s;
  }

  private static Boolean isEmpty(RowEnd e) {
    return e == null || (String.isBlank(e.city) && String.isBlank(e.postal));
  }

  private static RFP_Lane__c toLane(RFP_Project__c project, ImportRow r) {
    return new RFP_Lane__c(
      RFP_Project__c = project.Id,
      Row_Number__c = r.rowNumber,
      Raw_Row__c = r.raw,
      Mode__c = r.mode,
      Equipment_Category__c = r.equipmentCategory,
      Equipment_Type__c = r.equipmentType,
      Commodity__c = r.commodity,
      Quantity__c = r.quantity,
      Quantity_Unit__c = r.quantityUnit,
      Shipments_Per_Year__c = r.shipmentsPerYear,
      Customer_Fuel_Surcharge__c = r.fuelSurcharge,
      Customer_FSC_Included__c = r.fscIncluded == true,
      Hazmat__c = r.hazmat == true,
      Margin__c = project.Default_Margin__c,
      CurrencyIsoCode = project.CurrencyIsoCode
    );
  }

  /** Returns 1 when the end stays unresolved, else 0. */
  private static Integer applyEnd(
    RFP_Lane__c lane,
    RowEnd e,
    Resolver resolver,
    Boolean isOrigin
  ) {
    Pricing_Place__c place = resolver.resolve(e);
    String city = place != null ? place.City__c : trimmed(e?.city);
    String province = place != null
      ? place.Province__c
      : PlaceNormalizer.provinceCode(trimmed(e?.province));
    String country = place != null
      ? place.Country__c
      : PlaceNormalizer.countryCode(trimmed(e?.country));
    String postal = place != null && String.isBlank(e?.postal)
      ? place.Postal_Prefix__c
      : trimmed(e?.postal);
    if (isOrigin) {
      lane.Origin_City__c = city;
      lane.Origin_Province__c = province;
      lane.Origin_Country__c = country;
      lane.Origin_Postal__c = postal;
      lane.Origin_Place__c = place?.Id;
      lane.Origin_Resolved__c = place != null;
    } else {
      lane.Destination_City__c = city;
      lane.Destination_Province__c = province;
      lane.Destination_Country__c = country;
      lane.Destination_Postal__c = postal;
      lane.Destination_Place__c = place?.Id;
      lane.Destination_Resolved__c = place != null;
    }
    return place == null ? 1 : 0;
  }

  private static String trimmed(String s) {
    return s == null ? null : s.trim().left(80);
  }

  /** Two bulk queries per import call: all candidate city keys, then all postal prefixes. */
  private class Resolver {
    private Map<String, Pricing_Place__c> byKey = new Map<String, Pricing_Place__c>();
    private Map<String, Pricing_Place__c> byPrefix = new Map<String, Pricing_Place__c>();

    Resolver(List<ImportRow> rows) {
      Set<String> keys = new Set<String>();
      Set<String> prefixes = new Set<String>();
      for (ImportRow r : rows) {
        collect(r.origin, keys, prefixes);
        collect(r.destination, keys, prefixes);
      }
      if (!keys.isEmpty()) {
        for (Pricing_Place__c p : [
          SELECT
            Id,
            Key__c,
            City__c,
            Province__c,
            Country__c,
            Postal_Prefix__c,
            Load_Count_365d__c
          FROM Pricing_Place__c
          WHERE Key__c IN :keys AND Active__c = TRUE
          WITH USER_MODE
        ]) {
          byKey.put(p.Key__c, p);
        }
      }
      if (!prefixes.isEmpty()) {
        for (Pricing_Place__c p : [
          SELECT
            Id,
            Key__c,
            City__c,
            Province__c,
            Country__c,
            Postal_Prefix__c,
            Load_Count_365d__c
          FROM Pricing_Place__c
          WHERE Postal_Prefix__c IN :prefixes AND Active__c = TRUE
          WITH USER_MODE
          ORDER BY Load_Count_365d__c DESC NULLS LAST
        ]) {
          String k = p.Country__c + '|' + p.Postal_Prefix__c;
          if (!byPrefix.containsKey(k)) {
            byPrefix.put(k, p); // first = busiest, thanks to ORDER BY
          }
        }
      }
    }

    private void collect(RowEnd e, Set<String> keys, Set<String> prefixes) {
      if (e == null) {
        return;
      }
      for (String k : candidateKeys(e)) {
        keys.add(k);
      }
      String prefix = prefixOf(e.postal);
      if (prefix != null) {
        prefixes.add(prefix);
      }
    }

    Pricing_Place__c resolve(RowEnd e) {
      if (e == null) {
        return null;
      }
      for (String k : candidateKeys(e)) {
        if (byKey.containsKey(k)) {
          return byKey.get(k);
        }
      }
      String prefix = prefixOf(e.postal);
      if (prefix == null) {
        return null;
      }
      String country = PlaceNormalizer.countryCode(e.country);
      List<String> countries = String.isBlank(country)
        ? COUNTRY_ORDER
        : new List<String>{ country };
      for (String c : countries) {
        if (byPrefix.containsKey(c + '|' + prefix)) {
          return byPrefix.get(c + '|' + prefix);
        }
      }
      return null;
    }
  }

  private static List<String> candidateKeys(RowEnd e) {
    List<String> out = new List<String>();
    if (e == null || String.isBlank(e.city)) {
      return out;
    }
    String country = PlaceNormalizer.countryCode(e.country);
    if (String.isNotBlank(country)) {
      out.add(PlaceNormalizer.key(e.city, e.province, country));
      return out;
    }
    for (String c : COUNTRY_ORDER) {
      out.add(PlaceNormalizer.key(e.city, e.province, c));
    }
    return out;
  }

  private static String prefixOf(String postal) {
    if (String.isBlank(postal)) {
      return null;
    }
    String p = postal.replace(' ', '').toUpperCase();
    return p.length() < 3 ? null : p.left(3);
  }
}
```

If PMD reports the class over 40, move `Resolver` into its own top-level class `RfpPlaceResolver` (same code) — record it.

- [ ] **Step 3: Implement `RfpLaneController`**

```apex
/** Lane-side @AuraEnabled entry points of the RFP workbench (user mode). */
public with sharing class RfpLaneController {
  private static final String LANE_FIELDS =
    'Id, Name, RFP_Project__c, Row_Number__c, Origin_City__c, Origin_Province__c, Origin_Country__c, Origin_Postal__c, ' +
    'Origin_Place__c, Origin_Place__r.Key__c, Origin_Resolved__c, Destination_City__c, Destination_Province__c, ' +
    'Destination_Country__c, Destination_Postal__c, Destination_Place__c, Destination_Place__r.Key__c, Destination_Resolved__c, ' +
    'Mode__c, Equipment_Category__c, Equipment_Type__c, Commodity__c, Quantity__c, Quantity_Unit__c, Shipments_Per_Year__c, ' +
    'Hazmat__c, Customer_Fuel_Surcharge__c, Customer_FSC_Included__c, Hist_Count__c, Hist_Min__c, Hist_Median__c, ' +
    'Hist_Average__c, Hist_Max__c, Hist_Precision__c, Hist_Lookback_Days__c, Hist_As_Of__c, Hist_Status__c, Cost__c, ' +
    'Cost_Source__c, Selected_Bid__c, Selected_Bid__r.Carrier_Display__c, Margin__c, Sell__c, Notes__c, CurrencyIsoCode';

  @AuraEnabled
  public static RfpImportService.Summary importLanes(
    Id projectId,
    String rowsJson
  ) {
    try {
      List<RfpImportService.ImportRow> rows = (List<RfpImportService.ImportRow>) JSON.deserialize(
        rowsJson,
        List<RfpImportService.ImportRow>.class
      );
      return RfpImportService.importRows(projectId, rows);
    } catch (LaneSearchException e) {
      throw userError(e.getMessage());
    } catch (Exception e) {
      throw userError('The lanes could not be imported. ' + safe(e));
    }
  }

  @AuraEnabled
  public static List<RFP_Lane__c> getLanes(Id projectId) {
    try {
      return Database.queryWithBinds(
        'SELECT ' +
          LANE_FIELDS +
          ' FROM RFP_Lane__c WHERE RFP_Project__c = :projectId ORDER BY Row_Number__c LIMIT 2000',
        new Map<String, Object>{ 'projectId' => projectId },
        AccessLevel.USER_MODE
      );
    } catch (Exception e) {
      throw userError('The lanes could not be loaded. ' + safe(e));
    }
  }

  @AuraEnabled
  public static List<RFP_Lane__c> getRawRows(Id projectId, Integer offset) {
    try {
      Integer off = offset == null ? 0 : offset;
      return [
        SELECT Id, Row_Number__c, Raw_Row__c
        FROM RFP_Lane__c
        WHERE RFP_Project__c = :projectId
        WITH USER_MODE
        ORDER BY Row_Number__c
        LIMIT 500
        OFFSET :off
      ];
    } catch (Exception e) {
      throw userError('The original rows could not be loaded. ' + safe(e));
    }
  }

  @AuraEnabled
  public static RFP_Lane__c saveLanePricing(String laneJson) {
    try {
      RFP_Lane__c posted = (RFP_Lane__c) JSON.deserialize(
        laneJson,
        RFP_Lane__c.class
      );
      RFP_Lane__c lane = new RFP_Lane__c(
        Id = posted.Id,
        Cost__c = posted.Cost__c,
        Cost_Source__c = posted.Cost_Source__c,
        Selected_Bid__c = posted.Selected_Bid__c,
        Margin__c = posted.Margin__c,
        Sell__c = posted.Sell__c,
        Notes__c = posted.Notes__c
      );
      Database.update(
        Security.stripInaccessible(
            AccessType.UPDATABLE,
            new List<RFP_Lane__c>{ lane }
          )
          .getRecords()[0],
        AccessLevel.USER_MODE
      );
      return one(posted.Id);
    } catch (Exception e) {
      throw userError('The lane price could not be saved. ' + safe(e));
    }
  }

  @AuraEnabled
  public static RFP_Lane__c resolveLaneEnd(
    Id laneId,
    String side,
    String placeKey
  ) {
    if (side != 'origin' && side != 'destination') {
      throw userError('side must be origin or destination');
    }
    try {
      Pricing_Place__c place = [
        SELECT Id, City__c, Province__c, Country__c, Postal_Prefix__c
        FROM Pricing_Place__c
        WHERE Key__c = :placeKey
        WITH USER_MODE
        LIMIT 1
      ];
      RFP_Lane__c lane = new RFP_Lane__c(
        Id = laneId,
        Hist_Status__c = 'Pending'
      );
      if (side == 'origin') {
        lane.Origin_City__c = place.City__c;
        lane.Origin_Province__c = place.Province__c;
        lane.Origin_Country__c = place.Country__c;
        lane.Origin_Postal__c = place.Postal_Prefix__c;
        lane.Origin_Place__c = place.Id;
        lane.Origin_Resolved__c = true;
      } else {
        lane.Destination_City__c = place.City__c;
        lane.Destination_Province__c = place.Province__c;
        lane.Destination_Country__c = place.Country__c;
        lane.Destination_Postal__c = place.Postal_Prefix__c;
        lane.Destination_Place__c = place.Id;
        lane.Destination_Resolved__c = true;
      }
      Database.update(
        Security.stripInaccessible(
            AccessType.UPDATABLE,
            new List<RFP_Lane__c>{ lane }
          )
          .getRecords()[0],
        AccessLevel.USER_MODE
      );
      return one(laneId);
    } catch (AuraHandledException e) {
      throw e;
    } catch (Exception e) {
      throw userError('The place could not be applied. ' + safe(e));
    }
  }

  private static RFP_Lane__c one(Id laneId) {
    return (RFP_Lane__c) Database.queryWithBinds(
      'SELECT ' + LANE_FIELDS + ' FROM RFP_Lane__c WHERE Id = :laneId',
      new Map<String, Object>{ 'laneId' => laneId },
      AccessLevel.USER_MODE
    )[0];
  }

  /** Platform messages can carry field names but never SOQL; keep the first sentence only. */
  private static String safe(Exception e) {
    String m = e.getMessage();
    return m == null ? '' : m.substringBefore('.').left(160);
  }

  private static AuraHandledException userError(String message) {
    AuraHandledException e = new AuraHandledException(message);
    e.setMessage(message);
    return e;
  }
}
```

(`Database.queryWithBinds` with a constant field list and bound Id is not user-text SOQL. `isSet('Raw_Row__c')` on a queried SObject is false when the field was not selected.)

- [ ] **Step 4: Permission set, register, deploy, PMD, commit**

`RFP_Tool_User` classAccesses gains `RfpImportService` and `RfpLaneController` (alphabetical). Manifest ApexClass members (four classes). CI/README lists (16 classes). Deploy (permission set first with NoTestRun if the test deploy fails on class access). Commit: `Add RfpImportService and RfpLaneController: import, list, price and resolve RFP lanes`.

---

### Task 3: RfpHistoryService and RfpHistoryController

**Files:**

- Create: `RfpHistoryService.cls` (+meta), `RfpHistoryServiceTest.cls` (+meta), `RfpHistoryController.cls` (+meta)
- Modify: `RFP_Tool_User` classAccesses (`RfpHistoryService`, `RfpHistoryController`), manifest, CI/README lists

**Interfaces:**

- `public static List<RFP_Lane__c> RfpHistoryService.run(List<Id> laneIds, String precision, Integer lookbackDays)` — ≤ 10 ids (throws `LaneSearchException` above); `precision` ∈ `CITY | PROVINCE | RADIUS` (RADIUS = 50 km both ends); writes `Hist_*` on each lane in user mode and returns the lanes as `RfpLaneController.getLanes` shapes them (call `RfpLaneController`'s query through a new public static `RfpLaneController.lanesByIds(List<Id>)` added in this task).
- Snapshot rule: `LaneSearchRequest` with `sourceFilter = LOADS`, `rowLimit = 500`, no mode/equipment filters. Stats come from the lane's `CurrencyIsoCode` bucket when present in `statsByCurrency`, else from the first bucket. `Hist_Count__c = result.rows.size()`; `Hist_Min/Median/Average/Max` from that bucket (`min/median/avg/max`); `Hist_Precision__c` = `'CITY'`, `'PROVINCE'` or `'RADIUS-50KM'`; `Hist_Lookback_Days__c`; `Hist_As_Of__c = now`; `Hist_Status__c` = `'Done'` (rows > 0), `'No match'` (0 rows after the fallback, or a `LaneSearchException`), `'Failed'` (any other exception), `'Unresolved'` (an end has no place). CITY with 0 rows → retry as RADIUS 50 km (only when `precision == 'CITY'`).
- `RfpHistoryController.loadHistory(List<Id> laneIds, String precision, Integer lookbackDays)` `@AuraEnabled` → `RfpHistoryService.run` with `userError` wrapping.

- [ ] **Step 1: Failing test**

```apex
@IsTest
private class RfpHistoryServiceTest {
  @IsTest
  static void snapshotsCityFallsBackToRadiusAndFlagsUnresolved() {
    PricingTestDataFactory.Graph g = PricingTestDataFactory.createGraph();
    Pricing_Place__c mtl = RfpTestDataFactory.createPlace(
      'Montréal',
      'QC',
      'CA',
      45.5019,
      -73.5674,
      'H1A'
    );
    Pricing_Place__c laval = RfpTestDataFactory.createPlace(
      'Laval',
      'QC',
      'CA',
      45.6066,
      -73.7124,
      'H7P'
    );
    Pricing_Place__c tor = RfpTestDataFactory.createPlace(
      'Toronto',
      'ON',
      'CA',
      43.6532,
      -79.3832,
      'M5V'
    );
    Pricing_Place__c nowhere = RfpTestDataFactory.createPlace(
      'Nowhere',
      'ZZ',
      'CA',
      null,
      null,
      'Z9Z'
    );
    PricingDepartmentController.excludedContactIdsOverride = new Set<String>();
    RFP_Project__c p = RfpTestDataFactory.createProject(g.customer);
    RFP_Lane__c direct = RfpTestDataFactory.createLane(p, mtl, tor); // CITY hit
    RFP_Lane__c nearby = RfpTestDataFactory.createLane(p, laval, tor); // CITY miss, RADIUS hit (Laval->Montréal 15 km)
    RFP_Lane__c noCoords = RfpTestDataFactory.createLane(p, nowhere, tor); // RADIUS throws (no coordinates) -> No match
    RFP_Lane__c unresolved = RfpTestDataFactory.createLane(p, mtl, tor);
    unresolved.Destination_Place__c = null;
    unresolved.Destination_Resolved__c = false;
    update unresolved;
    Test.startTest();
    rtms__Load__c load = PricingTestDataFactory.createLoad(
      g,
      g.originLocation,
      g.destinationLocation
    ); // Montreal->Toronto
    insert new List<rtms__CarrierQuote__c>{
      PricingTestDataFactory.buildQuote(g, load, 1000),
      PricingTestDataFactory.buildQuote(g, load, 3000)
    };
    List<RFP_Lane__c> out = RfpHistoryService.run(
      new List<Id>{ direct.Id, nearby.Id, noCoords.Id, unresolved.Id },
      'CITY',
      90
    );
    Test.stopTest();
    Map<Id, RFP_Lane__c> byId = new Map<Id, RFP_Lane__c>(out);
    System.assertEquals('Done', byId.get(direct.Id).Hist_Status__c);
    System.assertEquals(2, byId.get(direct.Id).Hist_Count__c);
    System.assertEquals(1000, byId.get(direct.Id).Hist_Min__c);
    System.assertEquals(2000, byId.get(direct.Id).Hist_Median__c);
    System.assertEquals(3000, byId.get(direct.Id).Hist_Max__c);
    System.assertEquals('CITY', byId.get(direct.Id).Hist_Precision__c);
    System.assertEquals(90, byId.get(direct.Id).Hist_Lookback_Days__c);
    System.assertNotEquals(null, byId.get(direct.Id).Hist_As_Of__c);
    System.assertEquals(
      'RADIUS-50KM',
      byId.get(nearby.Id).Hist_Precision__c,
      'fell back to radius'
    );
    System.assertEquals('Done', byId.get(nearby.Id).Hist_Status__c);
    System.assertEquals(
      'No match',
      byId.get(noCoords.Id).Hist_Status__c,
      'radius fallback threw: no coordinates'
    );
    System.assertEquals('Unresolved', byId.get(unresolved.Id).Hist_Status__c);
  }

  @IsTest
  static void rejectsMoreThanTenLanes() {
    List<Id> ids = new List<Id>();
    for (Integer i = 0; i < 11; i++) {
      ids.add('a00000000000' + String.valueOf(100 + i));
    }
    try {
      RfpHistoryService.run(ids, 'CITY', 90);
      System.assert(false, 'expected an exception');
    } catch (LaneSearchException e) {
      System.assert(e.getMessage().contains('10'), e.getMessage());
    }
  }
}
```

(The factory graph's origin/destination locations are Montreal and Toronto, so the direct lane's CITY search matches through `cityLaneVariants`; the Laval lane at CITY finds nothing and the RADIUS retry from Laval reaches the Montreal stop. The fake Ids in the second test never hit the database because the size check comes first.)

- [ ] **Step 2: Implement**

`RfpHistoryService`:

```apex
/** Writes carrier-quote history snapshots onto RFP lanes, ten lanes per call (user-mode DML). */
public with sharing class RfpHistoryService {
  private static final Integer MAX_LANES = 10;
  private static final Integer ROW_LIMIT = 500;
  private static final Decimal FALLBACK_RADIUS_KM = 50;

  public static List<RFP_Lane__c> run(
    List<Id> laneIds,
    String precision,
    Integer lookbackDays
  ) {
    if (laneIds == null || laneIds.size() > MAX_LANES) {
      throw new LaneSearchException(
        'Load history for at most ' + MAX_LANES + ' lanes per call.'
      );
    }
    Integer days = lookbackDays == null || lookbackDays < 1 ? 90 : lookbackDays;
    List<RFP_Lane__c> lanes = RfpLaneController.lanesByIds(laneIds);
    List<RFP_Lane__c> updates = new List<RFP_Lane__c>();
    for (RFP_Lane__c lane : lanes) {
      updates.add(snapshot(lane, precision, days));
    }
    Database.update(
      Security.stripInaccessible(AccessType.UPDATABLE, updates).getRecords(),
      AccessLevel.USER_MODE
    );
    return RfpLaneController.lanesByIds(laneIds);
  }

  private static RFP_Lane__c snapshot(
    RFP_Lane__c lane,
    String precision,
    Integer days
  ) {
    RFP_Lane__c u = new RFP_Lane__c(
      Id = lane.Id,
      Hist_Lookback_Days__c = days,
      Hist_As_Of__c = Datetime.now(),
      Hist_Count__c = 0,
      Hist_Min__c = null,
      Hist_Median__c = null,
      Hist_Average__c = null,
      Hist_Max__c = null
    );
    if (
      lane.Origin_Place__r?.Key__c == null ||
      lane.Destination_Place__r?.Key__c == null
    ) {
      u.Hist_Status__c = 'Unresolved';
      u.Hist_Precision__c = null;
      return u;
    }
    try {
      String used = precision;
      LaneSearchResult r = LaneSearchService.search(
        request(lane, precision, days)
      );
      if (r.rows.isEmpty() && precision == 'CITY') {
        used = 'RADIUS';
        r = LaneSearchService.search(request(lane, used, days));
      }
      fill(u, r, lane.CurrencyIsoCode);
      u.Hist_Precision__c = used == 'RADIUS' ? 'RADIUS-50KM' : used;
      u.Hist_Status__c = r.rows.isEmpty() ? 'No match' : 'Done';
    } catch (LaneSearchException e) {
      u.Hist_Status__c = 'No match';
    } catch (Exception e) {
      u.Hist_Status__c = 'Failed';
    }
    return u;
  }

  private static LaneSearchRequest request(
    RFP_Lane__c lane,
    String precision,
    Integer days
  ) {
    LaneSearchRequest req = new LaneSearchRequest();
    req.originKey = lane.Origin_Place__r.Key__c;
    req.destinationKey = lane.Destination_Place__r.Key__c;
    req.lookbackDays = days;
    req.rowLimit = ROW_LIMIT;
    req.sourceFilter = LaneSearchRequest.RowSource.LOADS;
    if (precision == 'RADIUS') {
      req.originPrecision = LaneSearchRequest.Precision.RADIUS;
      req.destinationPrecision = LaneSearchRequest.Precision.RADIUS;
      req.originRadius = FALLBACK_RADIUS_KM;
      req.destinationRadius = FALLBACK_RADIUS_KM;
      req.radiusUnit = LaneSearchRequest.Unit.KM;
    } else if (precision == 'PROVINCE') {
      req.originPrecision = LaneSearchRequest.Precision.PROVINCE;
      req.destinationPrecision = LaneSearchRequest.Precision.PROVINCE;
    } else {
      req.originPrecision = LaneSearchRequest.Precision.CITY;
      req.destinationPrecision = LaneSearchRequest.Precision.CITY;
    }
    return req;
  }

  private static void fill(
    RFP_Lane__c u,
    LaneSearchResult r,
    String currencyCode
  ) {
    u.Hist_Count__c = r.rows.size();
    if (r.statsByCurrency.isEmpty()) {
      return;
    }
    LaneSearchResult.Stats s = r.statsByCurrency.get(currencyCode);
    if (s == null) {
      s = r.statsByCurrency.values()[0];
    }
    u.Hist_Min__c = s.min;
    u.Hist_Median__c = s.median;
    u.Hist_Average__c = s.avg;
    u.Hist_Max__c = s.max;
  }
}
```

Add to `RfpLaneController`:

```apex
  /** Shared by RfpHistoryService: the same field list as getLanes, for a set of Ids. */
  public static List<RFP_Lane__c> lanesByIds(List<Id> laneIds) {
    return Database.queryWithBinds(
      'SELECT ' + LANE_FIELDS + ' FROM RFP_Lane__c WHERE Id IN :laneIds ORDER BY Row_Number__c',
      new Map<String, Object>{ 'laneIds' => laneIds },
      AccessLevel.USER_MODE
    );
  }
```

`RfpHistoryController`:

```apex
public with sharing class RfpHistoryController {
  @AuraEnabled
  public static List<RFP_Lane__c> loadHistory(
    List<Id> laneIds,
    String precision,
    Integer lookbackDays
  ) {
    try {
      return RfpHistoryService.run(laneIds, precision, lookbackDays);
    } catch (LaneSearchException e) {
      throw userError(e.getMessage());
    } catch (Exception e) {
      throw userError('History could not be loaded for this chunk.');
    }
  }

  private static AuraHandledException userError(String message) {
    AuraHandledException e = new AuraHandledException(message);
    e.setMessage(message);
    return e;
  }
}
```

- [ ] **Step 3: Register, deploy, PMD, commit**

Permission set classAccesses (`RfpHistoryController`, `RfpHistoryService`), manifest, CI/README lists (17 classes: add `RfpHistoryServiceTest`). Deploy. Commit: `Add RfpHistoryService: per-lane carrier-quote snapshots with a radius fallback`.

---

### Task 4: RfpProjectController and RfpBidController

**Files:**

- Create: `RfpProjectController.cls` (+meta, +Test), `RfpBidController.cls` (+meta, +Test)
- Modify: `RFP_Tool_User` classAccesses, manifest, CI/README lists

**Interfaces (all `@AuraEnabled`, user mode, `userError` wrapping):**

- `RfpProjectController.listProjects()` → `List<RFP_Project__c>` (`Id, Name, Customer__c, Customer__r.Name, Status__c, Due_Date__c, Default_Margin__c, CurrencyIsoCode, Lane_Count__c, Costed_Count__c, Sold_Count__c, Source_File_Name__c, LastModifiedDate`, `ORDER BY LastModifiedDate DESC LIMIT 200`).
- `getProject(Id projectId)` → the same fields plus `Column_Mapping__c, Notes__c`.
- `saveProject(String projectJson)` → upsert of `Name, Customer__c, Status__c, Due_Date__c, Default_Margin__c, CurrencyIsoCode, Notes__c, Column_Mapping__c, Source_File_Name__c` (whitelist as in `saveLanePricing`), returns `getProject`.
- `columnMappingFor(Id accountId)` → `String` (the latest project of that customer with a non-blank `Column_Mapping__c`, else null).
- `searchAccounts(String term, String kind)` → `List<AccountOption { Id id; String name; String city; }>`; `kind` = `customer` (record types `Customer, New_Customer`) or `carrier` (`Carrier, New_Carrier`); `term` ≥ 2 chars, `Name LIKE :('%' + escaped + '%')`, `LIMIT 10`, `ORDER BY Name`.
- `attachFile(Id projectId, String fileName, String base64)` → inserts `ContentVersion(Title = fileName, PathOnClient = fileName, VersionData = EncodingUtil.base64Decode(base64))` and `ContentDocumentLink(LinkedEntityId = projectId, ShareType = 'V', Visibility = 'AllUsers')`, updates `Source_File_Name__c`, returns the `ContentDocumentId`. Rejects base64 longer than 4,200,000 characters (≈ 3 MB) with a user sentence.
- `RfpBidController.saveBid(String bidJson)` → `BenchmarkRateService.save((Benchmark_Rate__c) JSON.deserialize(bidJson, Benchmark_Rate__c.class))`; `getBids(Id laneId)` → `List<Benchmark_Rate__c>` (`Id, Name, Carrier__c, Carrier_Display__c, Contact_Name__c, Contact_Email__c, Contact_Phone__c, Rate__c, CurrencyIsoCode, Fuel_Surcharge__c, FSC_Included__c, Transit_Days__c, Valid_From__c, Expires_On__c, Status__c, Notes__c`, `ORDER BY Rate__c`).

- [ ] **Step 1: Failing tests**

```apex
@IsTest
private class RfpProjectControllerTest {
  @IsTest
  static void projectCrudMappingAndTypeahead() {
    PricingTestDataFactory.Graph g = PricingTestDataFactory.createGraph();
    String json =
      '{"Name":"Q4 lanes","Customer__c":"' +
      g.customer.Id +
      '","Status__c":"Draft","Default_Margin__c":12,"CurrencyIsoCode":"CAD","Column_Mapping__c":"{\\"originCity\\":\\"From\\"}"}';
    RFP_Project__c p = RfpProjectController.saveProject(json);
    System.assertEquals('Q4 lanes', p.Name);
    System.assertEquals(12, p.Default_Margin__c);
    p.Status__c = 'Pricing';
    RFP_Project__c again = RfpProjectController.saveProject(
      JSON.serialize(
        new Map<String, Object>{ 'Id' => p.Id, 'Status__c' => 'Pricing' }
      )
    );
    System.assertEquals('Pricing', again.Status__c);
    System.assertEquals(
      'Q4 lanes',
      again.Name,
      'partial JSON keeps other fields'
    );
    System.assertEquals(1, RfpProjectController.listProjects().size());
    System.assertEquals(
      '{"originCity":"From"}',
      RfpProjectController.columnMappingFor(g.customer.Id)
    );
    System.assertEquals(
      null,
      RfpProjectController.columnMappingFor(g.vendor.Id)
    );
    List<RfpProjectController.AccountOption> customers = RfpProjectController.searchAccounts(
      'Test Cust',
      'customer'
    );
    System.assertEquals(1, customers.size());
    System.assertEquals(g.customer.Id, customers[0].id);
    System.assertEquals(
      0,
      RfpProjectController.searchAccounts('Test Cust', 'carrier').size()
    );
    System.assertEquals(
      0,
      RfpProjectController.searchAccounts('T', 'customer').size(),
      'two characters minimum'
    );
  }

  @IsTest
  static void attachFileLinksTheDocument() {
    PricingTestDataFactory.Graph g = PricingTestDataFactory.createGraph();
    RFP_Project__c p = RfpTestDataFactory.createProject(g.customer);
    Id docId = RfpProjectController.attachFile(
      p.Id,
      'lanes.xlsx',
      EncodingUtil.base64Encode(Blob.valueOf('bytes'))
    );
    System.assertEquals(
      1,
      [
        SELECT COUNT()
        FROM ContentDocumentLink
        WHERE LinkedEntityId = :p.Id AND ContentDocumentId = :docId
      ]
    );
    System.assertEquals(
      'lanes.xlsx',
      [SELECT Source_File_Name__c FROM RFP_Project__c WHERE Id = :p.Id]
      .Source_File_Name__c
    );
    try {
      RfpProjectController.attachFile(p.Id, 'big.xlsx', 'A'.repeat(4200001));
      System.assert(false, 'expected an error');
    } catch (AuraHandledException e) {
      System.assert(e.getMessage().contains('3 MB'), e.getMessage());
    }
  }
}
```

```apex
@IsTest
private class RfpBidControllerTest {
  @IsTest
  static void saveAndListBids() {
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
    String json =
      '{"RFP_Lane__c":"' +
      lane.Id +
      '","Carrier_Name__c":"New Carrier","Contact_Email__c":"a@b.invalid","Rate__c":1250,"CurrencyIsoCode":"CAD","Transit_Days__c":2}';
    Benchmark_Rate__c saved = RfpBidController.saveBid(json);
    System.assertEquals('New Carrier', saved.Carrier_Display__c);
    System.assertEquals('Active', saved.Status__c);
    RfpBidController.saveBid(
      '{"RFP_Lane__c":"' +
        lane.Id +
        '","Carrier__c":"' +
        g.vendor.Id +
        '","Rate__c":990,"CurrencyIsoCode":"CAD"}'
    );
    List<Benchmark_Rate__c> bids = RfpBidController.getBids(lane.Id);
    System.assertEquals(2, bids.size());
    System.assertEquals(990, bids[0].Rate__c, 'ordered by rate');
    try {
      RfpBidController.saveBid(
        '{"RFP_Lane__c":"' + lane.Id + '","Carrier_Name__c":"X"}'
      );
      System.assert(false, 'expected an error');
    } catch (AuraHandledException e) {
      System.assert(e.getMessage().contains('rate'), e.getMessage());
    }
  }
}
```

- [ ] **Step 2: Implement**

`RfpProjectController` (full):

```apex
public with sharing class RfpProjectController {
  public class AccountOption {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String city;
  }
  private static final String PROJECT_FIELDS =
    'Id, Name, Customer__c, Customer__r.Name, Status__c, Due_Date__c, Default_Margin__c, CurrencyIsoCode, ' +
    'Lane_Count__c, Costed_Count__c, Sold_Count__c, Source_File_Name__c, LastModifiedDate, Column_Mapping__c, Notes__c';
  private static final Integer MAX_BASE64 = 4200000;

  @AuraEnabled
  public static List<RFP_Project__c> listProjects() {
    try {
      return Database.queryWithBinds(
        'SELECT ' +
          PROJECT_FIELDS +
          ' FROM RFP_Project__c ORDER BY LastModifiedDate DESC LIMIT 200',
        new Map<String, Object>(),
        AccessLevel.USER_MODE
      );
    } catch (Exception e) {
      throw userError('RFP projects could not be loaded.');
    }
  }

  @AuraEnabled
  public static RFP_Project__c getProject(Id projectId) {
    try {
      return one(projectId);
    } catch (Exception e) {
      throw userError('The RFP project could not be loaded.');
    }
  }

  @AuraEnabled
  public static RFP_Project__c saveProject(String projectJson) {
    try {
      RFP_Project__c posted = (RFP_Project__c) JSON.deserialize(
        projectJson,
        RFP_Project__c.class
      );
      Map<String, Object> fields = (Map<String, Object>) JSON.deserializeUntyped(
        projectJson
      );
      RFP_Project__c p = new RFP_Project__c(Id = posted.Id);
      for (
        String f : new List<String>{
          'Name',
          'Customer__c',
          'Status__c',
          'Due_Date__c',
          'Default_Margin__c',
          'CurrencyIsoCode',
          'Notes__c',
          'Column_Mapping__c',
          'Source_File_Name__c'
        }
      ) {
        if (fields.containsKey(f)) {
          p.put(f, posted.get(f));
        }
      }
      SObject clean = Security.stripInaccessible(
          p.Id == null ? AccessType.CREATABLE : AccessType.UPDATABLE,
          new List<RFP_Project__c>{ p }
        )
        .getRecords()[0];
      if (p.Id == null) {
        Database.insert(clean, AccessLevel.USER_MODE);
      } else {
        Database.update(clean, AccessLevel.USER_MODE);
      }
      return one(clean.Id);
    } catch (Exception e) {
      throw userError('The RFP project could not be saved. ' + safe(e));
    }
  }

  @AuraEnabled
  public static String columnMappingFor(Id accountId) {
    try {
      List<RFP_Project__c> ps = [
        SELECT Column_Mapping__c
        FROM RFP_Project__c
        WHERE Customer__c = :accountId AND Column_Mapping__c != NULL
        WITH USER_MODE
        ORDER BY LastModifiedDate DESC
        LIMIT 1
      ];
      return ps.isEmpty() ? null : ps[0].Column_Mapping__c;
    } catch (Exception e) {
      throw userError('The saved column mapping could not be loaded.');
    }
  }

  @AuraEnabled
  public static List<AccountOption> searchAccounts(String term, String kind) {
    List<AccountOption> out = new List<AccountOption>();
    if (term == null || term.trim().length() < 2) {
      return out;
    }
    List<String> types = kind == 'carrier'
      ? new List<String>{ 'Carrier', 'New_Carrier' }
      : new List<String>{ 'Customer', 'New_Customer' };
    String pattern = '%' + LaneSearchQueryBuilder.escapeLike(term.trim()) + '%';
    try {
      for (Account a : [
        SELECT Id, Name, BillingCity
        FROM Account
        WHERE Name LIKE :pattern AND RecordType.DeveloperName IN :types
        WITH USER_MODE
        ORDER BY Name
        LIMIT 10
      ]) {
        AccountOption o = new AccountOption();
        o.id = a.Id;
        o.name = a.Name;
        o.city = a.BillingCity;
        out.add(o);
      }
      return out;
    } catch (Exception e) {
      throw userError('Accounts could not be searched.');
    }
  }

  @AuraEnabled
  public static Id attachFile(Id projectId, String fileName, String base64) {
    if (base64 == null || base64.length() > MAX_BASE64) {
      throw userError(
        'The file is larger than 3 MB. Split it and upload the parts.'
      );
    }
    try {
      ContentVersion cv = new ContentVersion(
        Title = fileName,
        PathOnClient = fileName,
        VersionData = EncodingUtil.base64Decode(base64)
      );
      Database.insert(cv, AccessLevel.USER_MODE);
      Id docId = [
        SELECT ContentDocumentId
        FROM ContentVersion
        WHERE Id = :cv.Id
        WITH USER_MODE
      ]
      .ContentDocumentId;
      Database.insert(
        new ContentDocumentLink(
          ContentDocumentId = docId,
          LinkedEntityId = projectId,
          ShareType = 'V',
          Visibility = 'AllUsers'
        ),
        AccessLevel.USER_MODE
      );
      Database.update(
        new RFP_Project__c(
          Id = projectId,
          Source_File_Name__c = fileName.left(255)
        ),
        AccessLevel.USER_MODE
      );
      return docId;
    } catch (Exception e) {
      throw userError('The file could not be attached. ' + safe(e));
    }
  }

  private static RFP_Project__c one(Id projectId) {
    return (RFP_Project__c) Database.queryWithBinds(
      'SELECT ' + PROJECT_FIELDS + ' FROM RFP_Project__c WHERE Id = :projectId',
      new Map<String, Object>{ 'projectId' => projectId },
      AccessLevel.USER_MODE
    )[0];
  }
  private static String safe(Exception e) {
    String m = e.getMessage();
    return m == null ? '' : m.substringBefore('.').left(160);
  }
  private static AuraHandledException userError(String message) {
    AuraHandledException e = new AuraHandledException(message);
    e.setMessage(message);
    return e;
  }
}
```

`RfpBidController` (full):

```apex
public with sharing class RfpBidController {
  @AuraEnabled
  public static Benchmark_Rate__c saveBid(String bidJson) {
    try {
      return BenchmarkRateService.save(
        (Benchmark_Rate__c) JSON.deserialize(bidJson, Benchmark_Rate__c.class)
      );
    } catch (LaneSearchException e) {
      throw userError(e.getMessage());
    } catch (DmlException e) {
      throw userError(e.getDmlMessage(0));
    } catch (Exception e) {
      throw userError('The bid could not be saved.');
    }
  }

  @AuraEnabled
  public static List<Benchmark_Rate__c> getBids(Id laneId) {
    try {
      return [
        SELECT
          Id,
          Name,
          Carrier__c,
          Carrier_Display__c,
          Contact_Name__c,
          Contact_Email__c,
          Contact_Phone__c,
          Rate__c,
          CurrencyIsoCode,
          Fuel_Surcharge__c,
          FSC_Included__c,
          Transit_Days__c,
          Valid_From__c,
          Expires_On__c,
          Status__c,
          Notes__c
        FROM Benchmark_Rate__c
        WHERE RFP_Lane__c = :laneId
        WITH USER_MODE
        ORDER BY Rate__c
      ];
    } catch (Exception e) {
      throw userError('The bids could not be loaded.');
    }
  }

  private static AuraHandledException userError(String message) {
    AuraHandledException e = new AuraHandledException(message);
    e.setMessage(message);
    return e;
  }
}
```

- [ ] **Step 3: Register, deploy, PMD, commit**

Permission set classAccesses (`RfpBidController`, `RfpProjectController`); manifest; CI/README lists (19 classes: `RfpProjectControllerTest`, `RfpBidControllerTest`). If `saveProject`'s loop pushes the class total past 40, move `searchAccounts`/`attachFile` into `RfpProjectFileController` and register it. Deploy (permission set first, NoTestRun). Commit: `Add RfpProjectController and RfpBidController`.

---

### Task 5: Pure modules — rfpHeaderGuess, rfpSheet, rfpWorkbook, rfpMath; export slug

**Files:**

- Create: `force-app/main/default/lwc/rfpHeaderGuess/rfpHeaderGuess.js` (+`__tests__`), `rfpSheet/rfpSheet.js` (+tests), `rfpWorkbook/rfpWorkbook.js` (+tests), `rfpMath/rfpMath.js` (+tests); each with a minimal `.js-meta.xml` (`isExposed` false) — copy `marginMath`'s.
- Modify: `force-app/main/default/lwc/laneBenchmarkCsv/laneBenchmarkCsv.js` (export `slug`).

**Interfaces:**

- `rfpHeaderGuess`: `export const TARGETS = [{ key: "originCity", label: "Origin city", required: "originCity" }, ...]` for keys `originCity, originProvince, originCountry, originPostal, destinationCity, destinationProvince, destinationCountry, destinationPostal, mode, equipmentCategory, equipmentType, commodity, quantity, quantityUnit, shipmentsPerYear, fuelSurcharge, fscIncluded, hazmat`; `export function guess(headers)` → `{ [targetKey]: header }` for headers it recognises; `export function missingRequired(mapping)` → `[]` when (`originCity` and `destinationCity`) or (`originPostal` and `destinationPostal`) are mapped, else the list of what is missing.
- `rfpSheet`: `export function parse(workbook, sheetToJson)` → `{ headers: string[], rows: string[][] }` from the first sheet (`sheetToJson(ws, { header: 1, raw: false, defval: "" })`; first non-empty row = headers; trailing empty rows dropped; throws `Error("The sheet is empty")` / `Error("No header row")`); `export function toImportRows(headers, rows, mapping, startRow = 1)` → `ImportRow[]` JSON-ready objects (`rowNumber`, nested `origin`/`destination`, numbers parsed, `fscIncluded`/`hazmat` from yes/true/1/x, `raw` = JSON of `{header: value}`); `export const MAX_ROWS = 2000`.
- `rfpWorkbook`: `export const OUR_COLUMNS = ["Cost", "Currency", "Margin %", "Sell", "Fuel surcharge", "FSC included", "Transit days", "Bid carrier", "Notes"]`; `export function buildSheets(lanes, rawRows, bidsByLaneId)` → `{ lanes: any[][], bids: any[][] }` where `lanes` = original headers + `OUR_COLUMNS`, one row per lane in `Row_Number__c` order, values from `Raw_Row__c` JSON, unpriced cells `""`, numbers as numbers; `bids` sheet header `["Lane row", "Carrier", "Contact", "Email", "Phone", "Rate", "Currency", "Fuel surcharge", "FSC included", "Transit days", "Valid from", "Expires on", "Status", "Notes"]`; `export function exportFileName(customerName, projectName, date)` → `<slug>-<slug>-<yyyymmdd>.xlsx` using `slug` from `c/laneBenchmarkCsv`.
- `rfpMath`: `export function bestBid(bids, currency)` → the active bid with the lowest `Rate__c` in `currency` (or null); `export function otherCurrencyCount(bids, currency)`.

- [ ] **Step 1: Failing tests** (one file per module; representative cases)

`rfpHeaderGuess.test.js`:

```javascript
import { guess, missingRequired, TARGETS } from "c/rfpHeaderGuess";

describe("rfpHeaderGuess", () => {
  it("recognises common headers case-insensitively", () => {
    const m = guess([
      "Origin City",
      "Orig State",
      "O Zip",
      "Dest City",
      "Destination Province",
      "Dest. Postal Code",
      "Mode",
      "Equip",
      "Commodity",
      "Qty",
      "Annual Shipments",
      "FSC",
      "FSC Included",
      "Hazmat"
    ]);
    expect(m.originCity).toBe("Origin City");
    expect(m.originProvince).toBe("Orig State");
    expect(m.originPostal).toBe("O Zip");
    expect(m.destinationCity).toBe("Dest City");
    expect(m.destinationProvince).toBe("Destination Province");
    expect(m.destinationPostal).toBe("Dest. Postal Code");
    expect(m.mode).toBe("Mode");
    expect(m.equipmentType).toBe("Equip");
    expect(m.quantity).toBe("Qty");
    expect(m.shipmentsPerYear).toBe("Annual Shipments");
    expect(m.fuelSurcharge).toBe("FSC");
    expect(m.fscIncluded).toBe("FSC Included");
    expect(m.hazmat).toBe("Hazmat");
  });
  it("never maps one header to two targets and reports required gaps", () => {
    const m = guess(["From", "To"]);
    expect(m.originCity).toBe("From");
    expect(m.destinationCity).toBe("To");
    expect(missingRequired(m)).toEqual([]);
    expect(missingRequired({ originCity: "From" })).toEqual([
      "destinationCity"
    ]);
    expect(
      missingRequired({ originPostal: "A", destinationPostal: "B" })
    ).toEqual([]);
    expect(missingRequired({})).toEqual(["originCity", "destinationCity"]);
    expect(TARGETS.map((t) => t.key)).toContain("quantityUnit");
  });
});
```

`rfpSheet.test.js`:

```javascript
import { parse, toImportRows, MAX_ROWS } from "c/rfpSheet";

const wb = (aoa) => ({ SheetNames: ["Lanes"], Sheets: { Lanes: aoa } });
const sheetToJson = (ws) => ws;

describe("rfpSheet", () => {
  it("parses headers and rows, dropping empty trailing rows", () => {
    const { headers, rows } = parse(
      wb([
        [],
        ["From", "To", "Qty"],
        ["Montreal", "Toronto", "2"],
        ["", "", ""]
      ]),
      sheetToJson
    );
    expect(headers).toEqual(["From", "To", "Qty"]);
    expect(rows).toEqual([["Montreal", "Toronto", "2"]]);
  });
  it("throws on an empty sheet", () => {
    expect(() => parse(wb([]), sheetToJson)).toThrow("empty");
  });
  it("builds import rows with nested ends, numbers and flags", () => {
    const rows = toImportRows(
      ["From", "From ST", "To", "Qty", "FSC incl", "Haz"],
      [["Montreal", "QC", "Toronto", "2.5", "Yes", "x"]],
      {
        originCity: "From",
        originProvince: "From ST",
        destinationCity: "To",
        quantity: "Qty",
        fscIncluded: "FSC incl",
        hazmat: "Haz"
      }
    );
    expect(rows[0]).toEqual({
      rowNumber: 1,
      origin: { city: "Montreal", province: "QC", country: "", postal: "" },
      destination: { city: "Toronto", province: "", country: "", postal: "" },
      mode: "",
      equipmentCategory: "",
      equipmentType: "",
      commodity: "",
      quantity: 2.5,
      quantityUnit: "",
      shipmentsPerYear: null,
      fuelSurcharge: null,
      fscIncluded: true,
      hazmat: true,
      raw: JSON.stringify({
        From: "Montreal",
        "From ST": "QC",
        To: "Toronto",
        Qty: "2.5",
        "FSC incl": "Yes",
        Haz: "x"
      })
    });
    expect(MAX_ROWS).toBe(2000);
  });
});
```

`rfpWorkbook.test.js`:

```javascript
import { buildSheets, OUR_COLUMNS, exportFileName } from "c/rfpWorkbook";

describe("rfpWorkbook", () => {
  const lanes = [
    {
      Id: "l2",
      Row_Number__c: 2,
      Cost__c: null,
      Sell__c: null,
      Margin__c: 15,
      CurrencyIsoCode: "CAD",
      Notes__c: ""
    },
    {
      Id: "l1",
      Row_Number__c: 1,
      Cost__c: 1000,
      Sell__c: 1150,
      Margin__c: 15,
      CurrencyIsoCode: "CAD",
      Notes__c: "=SUM(A1)",
      Selected_Bid__r: { Carrier_Display__c: "Acme" }
    }
  ];
  const raw = [
    {
      Id: "l1",
      Row_Number__c: 1,
      Raw_Row__c: JSON.stringify({ From: "Montreal", To: "Toronto" })
    },
    {
      Id: "l2",
      Row_Number__c: 2,
      Raw_Row__c: JSON.stringify({ From: "Laval", To: "Ottawa" })
    }
  ];
  const bids = {
    l1: [
      {
        Carrier_Display__c: "Acme",
        Contact_Name__c: "Jo",
        Contact_Email__c: "j@a.test",
        Contact_Phone__c: null,
        Rate__c: 1000,
        CurrencyIsoCode: "CAD",
        Fuel_Surcharge__c: 50,
        FSC_Included__c: false,
        Transit_Days__c: 2,
        Valid_From__c: "2026-09-11",
        Expires_On__c: "2026-10-11",
        Status__c: "Active",
        Notes__c: null
      }
    ]
  };

  it("keeps the customer's order and columns, appends ours, leaves unpriced cells empty", () => {
    const { lanes: sheet, bids: bidSheet } = buildSheets(lanes, raw, bids);
    expect(sheet[0]).toEqual(["From", "To", ...OUR_COLUMNS]);
    expect(sheet[1].slice(0, 2)).toEqual(["Montreal", "Toronto"]);
    expect(sheet[1][2]).toBe(1000);
    expect(sheet[1][5]).toBe(1150);
    expect(sheet[1][9]).toBe("Acme");
    expect(sheet[1][10]).toBe("=SUM(A1)"); // typed string cell, no apostrophe
    expect(sheet[2][2]).toBe("");
    expect(sheet[2][5]).toBe("");
    expect(bidSheet[0][0]).toBe("Lane row");
    expect(bidSheet[1]).toEqual([
      1,
      "Acme",
      "Jo",
      "j@a.test",
      "",
      1000,
      "CAD",
      50,
      "No",
      2,
      "2026-09-11",
      "2026-10-11",
      "Active",
      ""
    ]);
  });
  it("names the file from customer, project and date", () => {
    expect(
      exportFileName("Costco Canada", "Q4 Lanes", new Date(2026, 8, 11))
    ).toBe("costco-canada-q4-lanes-20260911.xlsx");
  });
});
```

`rfpMath.test.js`:

```javascript
import { bestBid, otherCurrencyCount } from "c/rfpMath";

describe("rfpMath", () => {
  const bids = [
    { Id: "a", Rate__c: 1200, CurrencyIsoCode: "CAD", Status__c: "Active" },
    { Id: "b", Rate__c: 900, CurrencyIsoCode: "CAD", Status__c: "Expired" },
    { Id: "c", Rate__c: 1000, CurrencyIsoCode: "CAD", Status__c: "Active" },
    { Id: "d", Rate__c: 500, CurrencyIsoCode: "USD", Status__c: "Active" }
  ];
  it("picks the lowest active bid in the project currency", () => {
    expect(bestBid(bids, "CAD").Id).toBe("c");
    expect(bestBid([], "CAD")).toBeNull();
    expect(otherCurrencyCount(bids, "CAD")).toBe(1);
  });
});
```

- [ ] **Step 2: Implement**

`rfpHeaderGuess.js`:

```javascript
export const TARGETS = [
  { key: "originCity", label: "Origin city" },
  { key: "originProvince", label: "Origin state/province" },
  { key: "originCountry", label: "Origin country" },
  { key: "originPostal", label: "Origin postal" },
  { key: "destinationCity", label: "Destination city" },
  { key: "destinationProvince", label: "Destination state/province" },
  { key: "destinationCountry", label: "Destination country" },
  { key: "destinationPostal", label: "Destination postal" },
  { key: "mode", label: "Mode" },
  { key: "equipmentCategory", label: "Equipment category" },
  { key: "equipmentType", label: "Equipment type" },
  { key: "commodity", label: "Commodity" },
  { key: "quantity", label: "Quantity" },
  { key: "quantityUnit", label: "Quantity unit" },
  { key: "shipmentsPerYear", label: "Shipments per year" },
  { key: "fuelSurcharge", label: "Fuel surcharge" },
  { key: "fscIncluded", label: "FSC included" },
  { key: "hazmat", label: "Hazmat" }
];

const ORIGIN = /^(origin|orig|o|from|pickup|pu|ship ?from|shipper)\b/;
const DEST = /^(destination|dest|d|to|delivery|del|ship ?to|consignee|cons)\b/;
const norm = (h) =>
  String(h || "")
    .toLowerCase()
    .replace(/[._-]/g, " ")
    .replace(/\s+/g, " ")
    .trim();

function endTarget(h, side) {
  const rest = h.replace(side === "origin" ? ORIGIN : DEST, "").trim();
  if (/^(city|town)?$/.test(rest) || /\bcity\b/.test(rest))
    return `${side}City`;
  if (/\b(state|province|prov|st)\b/.test(rest)) return `${side}Province`;
  if (/\bcountry\b/.test(rest)) return `${side}Country`;
  if (/\b(zip|postal|post code|postcode|pc)\b/.test(rest))
    return `${side}Postal`;
  return null;
}

function targetFor(header) {
  const h = norm(header);
  if (!h) return null;
  if (/^(fsc|fuel) (incl|included)/.test(h) || /^fsc included/.test(h))
    return "fscIncluded";
  if (/^(fsc|fuel surcharge|fuel)$/.test(h)) return "fuelSurcharge";
  if (/^haz/.test(h)) return "hazmat";
  if (/^(mode|service|transport mode)$/.test(h)) return "mode";
  if (/equipment category|equip category|category/.test(h))
    return "equipmentCategory";
  if (/^(equipment|equip|equipment type|trailer)$/.test(h))
    return "equipmentType";
  if (/^(commodity|product|goods)$/.test(h)) return "commodity";
  if (/^(qty|quantity|volume|pallets|weight)$/.test(h)) return "quantity";
  if (/^(unit|uom|qty unit|quantity unit)$/.test(h)) return "quantityUnit";
  if (/(annual|yearly|per year|shipments|loads)/.test(h))
    return "shipmentsPerYear";
  if (ORIGIN.test(h)) return endTarget(h, "origin");
  if (DEST.test(h)) return endTarget(h, "destination");
  return null;
}

export function guess(headers) {
  const mapping = {};
  (headers || []).forEach((header) => {
    const t = targetFor(header);
    if (t && !mapping[t]) mapping[t] = header;
  });
  return mapping;
}

export function missingRequired(mapping) {
  const m = mapping || {};
  if (m.originCity && m.destinationCity) return [];
  if (m.originPostal && m.destinationPostal) return [];
  const out = [];
  if (!m.originCity) out.push("originCity");
  if (!m.destinationCity) out.push("destinationCity");
  return out;
}
```

`rfpSheet.js`:

```javascript
export const MAX_ROWS = 2000;

const isEmptyRow = (r) => !r || r.every((c) => String(c ?? "").trim() === "");

export function parse(workbook, sheetToJson) {
  const name = workbook?.SheetNames?.[0];
  if (!name) throw new Error("The sheet is empty");
  const aoa =
    sheetToJson(workbook.Sheets[name], { header: 1, raw: false, defval: "" }) ||
    [];
  const first = aoa.findIndex((r) => !isEmptyRow(r));
  if (first < 0) throw new Error("The sheet is empty");
  const headers = aoa[first].map((h) => String(h ?? "").trim());
  if (!headers.some((h) => h)) throw new Error("No header row");
  const rows = aoa
    .slice(first + 1)
    .map((r) => headers.map((_, i) => String(r?.[i] ?? "").trim()));
  while (rows.length && isEmptyRow(rows[rows.length - 1])) rows.pop();
  return { headers, rows };
}

const num = (v) => {
  const s = String(v ?? "").replace(/[$,\s]/g, "");
  if (s === "") return null;
  const n = Number(s);
  return Number.isFinite(n) ? n : null;
};
const flag = (v) =>
  /^(y|yes|true|1|x|incl|included)$/i.test(String(v ?? "").trim());

export function toImportRows(headers, rows, mapping, startRow = 1) {
  const idx = {};
  Object.keys(mapping || {}).forEach((k) => {
    const i = headers.indexOf(mapping[k]);
    if (i >= 0) idx[k] = i;
  });
  const pick = (r, k) => (k in idx ? String(r[idx[k]] ?? "").trim() : "");
  return rows.map((r, n) => {
    const raw = {};
    headers.forEach((h, i) => {
      if (h) raw[h] = r[i] ?? "";
    });
    return {
      rowNumber: startRow + n,
      origin: {
        city: pick(r, "originCity"),
        province: pick(r, "originProvince"),
        country: pick(r, "originCountry"),
        postal: pick(r, "originPostal")
      },
      destination: {
        city: pick(r, "destinationCity"),
        province: pick(r, "destinationProvince"),
        country: pick(r, "destinationCountry"),
        postal: pick(r, "destinationPostal")
      },
      mode: pick(r, "mode"),
      equipmentCategory: pick(r, "equipmentCategory"),
      equipmentType: pick(r, "equipmentType"),
      commodity: pick(r, "commodity"),
      quantity: num(pick(r, "quantity")),
      quantityUnit: pick(r, "quantityUnit"),
      shipmentsPerYear:
        num(pick(r, "shipmentsPerYear")) === null
          ? null
          : Math.round(num(pick(r, "shipmentsPerYear"))),
      fuelSurcharge: num(pick(r, "fuelSurcharge")),
      fscIncluded: flag(pick(r, "fscIncluded")),
      hazmat: flag(pick(r, "hazmat")),
      raw: JSON.stringify(raw)
    };
  });
}
```

`rfpWorkbook.js`:

```javascript
import { slug } from "c/laneBenchmarkCsv";

export const OUR_COLUMNS = [
  "Cost",
  "Currency",
  "Margin %",
  "Sell",
  "Fuel surcharge",
  "FSC included",
  "Transit days",
  "Bid carrier",
  "Notes"
];
const BID_HEADER = [
  "Lane row",
  "Carrier",
  "Contact",
  "Email",
  "Phone",
  "Rate",
  "Currency",
  "Fuel surcharge",
  "FSC included",
  "Transit days",
  "Valid from",
  "Expires on",
  "Status",
  "Notes"
];

const cell = (v) => (v === null || v === undefined ? "" : v);
const yesNo = (b) => (b ? "Yes" : "No");

export function buildSheets(lanes, rawRows, bidsByLaneId) {
  const rawById = {};
  (rawRows || []).forEach((r) => {
    try {
      rawById[r.Id] = JSON.parse(r.Raw_Row__c || "{}");
    } catch (e) {
      rawById[r.Id] = {};
    }
  });
  const ordered = [...(lanes || [])].sort(
    (a, b) => (a.Row_Number__c || 0) - (b.Row_Number__c || 0)
  );
  const headers = [];
  ordered.forEach((l) =>
    Object.keys(rawById[l.Id] || {}).forEach((h) => {
      if (!headers.includes(h)) headers.push(h);
    })
  );
  const laneSheet = [[...headers, ...OUR_COLUMNS]];
  const bidSheet = [BID_HEADER];
  ordered.forEach((l) => {
    const raw = rawById[l.Id] || {};
    const best = (bidsByLaneId?.[l.Id] || []).find(
      (b) => b.Id === l.Selected_Bid__c
    );
    laneSheet.push([
      ...headers.map((h) => cell(raw[h])),
      cell(l.Cost__c),
      l.Cost__c === null || l.Cost__c === undefined
        ? ""
        : cell(l.CurrencyIsoCode),
      cell(l.Margin__c),
      cell(l.Sell__c),
      cell(best?.Fuel_Surcharge__c),
      best ? yesNo(best.FSC_Included__c) : "",
      cell(best?.Transit_Days__c),
      cell(l.Selected_Bid__r?.Carrier_Display__c),
      cell(l.Notes__c)
    ]);
    (bidsByLaneId?.[l.Id] || []).forEach((b) => {
      bidSheet.push([
        l.Row_Number__c,
        cell(b.Carrier_Display__c),
        cell(b.Contact_Name__c),
        cell(b.Contact_Email__c),
        cell(b.Contact_Phone__c),
        cell(b.Rate__c),
        cell(b.CurrencyIsoCode),
        cell(b.Fuel_Surcharge__c),
        yesNo(b.FSC_Included__c),
        cell(b.Transit_Days__c),
        cell(b.Valid_From__c),
        cell(b.Expires_On__c),
        cell(b.Status__c),
        cell(b.Notes__c)
      ]);
    });
  });
  return { lanes: laneSheet, bids: bidSheet };
}

export function exportFileName(customerName, projectName, date) {
  const d = date || new Date();
  const ymd = `${d.getFullYear()}${String(d.getMonth() + 1).padStart(2, "0")}${String(d.getDate()).padStart(2, "0")}`;
  return `${slug(customerName)}-${slug(projectName)}-${ymd}.xlsx`;
}
```

`rfpMath.js`:

```javascript
export function bestBid(bids, currency) {
  const active = (bids || []).filter(
    (b) =>
      b.Status__c !== "Expired" &&
      b.CurrencyIsoCode === currency &&
      b.Rate__c !== null &&
      b.Rate__c !== undefined
  );
  if (!active.length) return null;
  return active.reduce((best, b) =>
    Number(b.Rate__c) < Number(best.Rate__c) ? b : best
  );
}

export function otherCurrencyCount(bids, currency) {
  return (bids || []).filter((b) => b.CurrencyIsoCode !== currency).length;
}
```

`laneBenchmarkCsv.js`: change `function slug(` to `export function slug(` (no other change).

- [ ] **Step 3: Test, lint, commit**

`npm test`, `npm run lint`, prettier. Commit: `Add RFP pure modules: header guessing, sheet parsing, workbook building, best bid`.

---

### Task 6: rfpUpload and rfpColumnMapper

**Files:**

- Create: `force-app/main/default/lwc/rfpUpload/*` (+tests), `rfpColumnMapper/*` (+tests)

**Interfaces:**

- `c-rfp-upload`: `@api projectId`; on file choice: size check (> 3 MB → error text), `FileReader.readAsArrayBuffer`; `loadScript(this, sheetJs)` once (`import sheetJs from "@salesforce/resourceUrl/sheetJs"`; `import { loadScript } from "lightning/platformResourceLoader"`); `window.XLSX.read(new Uint8Array(buffer), { type: "array" })`; `parse(workbook, window.XLSX.utils.sheet_to_json)`; > `MAX_ROWS` rows → error text "Split the file; the workbench handles 2,000 lanes"; then `attachFile({ projectId, fileName, base64 })` (base64 from the same buffer) and dispatch `parsed` `{ fileName, headers, rows }`. A `data-id="status"` line shows "Reading…", "Attaching…", errors (`data-id="error"`).
- `c-rfp-column-mapper`: `@api headers`, `@api sampleRows` (first three rows), `@api mapping` (get/set backing `_mapping`); renders one `lightning-combobox` per `TARGETS` entry (`data-target="<key>"`, options = "— none —" + headers); emits `mappingchange { mapping }` on each change; "Import" button (`data-id="import"`) disabled while `missingRequired(mapping)` is non-empty, with the missing labels listed in `data-id="missing"`; emits `import { mapping }`.

- [ ] **Step 1: Failing tests**

`rfpUpload.test.js` (mock `@salesforce/resourceUrl/sheetJs` virtually to `"/sheetjs"`, mock `attachFile` Apex to resolve `"069x"`, and stub `window.XLSX = { read: jest.fn(() => WB), utils: { sheet_to_json: jest.fn(() => AOA) } }`; `loadScript` stub resolves):

```javascript
it("parses a chosen file, attaches it and emits the rows", async () => {
  const el = mount("a0P1");
  const parsed = jest.fn();
  el.addEventListener("parsed", parsed);
  const input = el.shadowRoot.querySelector('input[type="file"]');
  const file = new File([new Uint8Array([1, 2, 3])], "lanes.xlsx");
  Object.defineProperty(input, "files", { value: [file] });
  input.dispatchEvent(new Event("change"));
  await flush();
  await flush();
  await flush();
  expect(attachFile).toHaveBeenCalledWith(
    expect.objectContaining({ projectId: "a0P1", fileName: "lanes.xlsx" })
  );
  expect(parsed.mock.calls[0][0].detail.headers).toEqual(["From", "To"]);
  expect(parsed.mock.calls[0][0].detail.rows.length).toBe(1);
});
it("refuses a file over 3 MB without calling Apex", async () => {
  const el = mount("a0P1");
  const input = el.shadowRoot.querySelector('input[type="file"]');
  Object.defineProperty(input, "files", {
    value: [{ name: "big.xlsx", size: 3 * 1024 * 1024 + 1 }]
  });
  input.dispatchEvent(new Event("change"));
  await flush();
  expect(
    el.shadowRoot.querySelector('[data-id="error"]').textContent
  ).toContain("3 MB");
  expect(attachFile).not.toHaveBeenCalled();
});
```

(In jsdom, `FileReader.readAsArrayBuffer` works on a `File`; if it does not resolve in the test, replace `file.arrayBuffer()`-based reading: implement `readBuffer(file)` as `file.arrayBuffer ? file.arrayBuffer() : new Promise(FileReader…)` and note it.)

`rfpColumnMapper.test.js`:

```javascript
it("pre-fills from the mapping, lists missing required targets and enables Import when satisfied", async () => {
  const el = mount({
    headers: ["From", "To", "Qty"],
    sampleRows: [["Montreal", "Toronto", "2"]],
    mapping: { originCity: "From" }
  });
  expect(el.shadowRoot.querySelector('[data-target="originCity"]').value).toBe(
    "From"
  );
  expect(
    el.shadowRoot.querySelector('[data-id="missing"]').textContent
  ).toContain("Destination city");
  expect(el.shadowRoot.querySelector('[data-id="import"]').disabled).toBe(true);
  const handler = jest.fn();
  el.addEventListener("mappingchange", handler);
  change(el, '[data-target="destinationCity"]', "To");
  await flush();
  expect(handler.mock.calls[0][0].detail.mapping.destinationCity).toBe("To");
  expect(el.shadowRoot.querySelector('[data-id="import"]').disabled).toBe(
    false
  );
  const imp = jest.fn();
  el.addEventListener("import", imp);
  el.shadowRoot.querySelector('[data-id="import"]').click();
  expect(imp.mock.calls[0][0].detail.mapping).toEqual({
    originCity: "From",
    destinationCity: "To"
  });
});
```

- [ ] **Step 2: Implement**

`rfpUpload.js`:

```javascript
import { LightningElement, api } from "lwc";
import { loadScript } from "lightning/platformResourceLoader";
import sheetJs from "@salesforce/resourceUrl/sheetJs";
import attachFile from "@salesforce/apex/RfpProjectController.attachFile";
import { parse, MAX_ROWS } from "c/rfpSheet";

const MAX_BYTES = 3 * 1024 * 1024;

export default class RfpUpload extends LightningElement {
  @api projectId;
  status = "";
  error = null;
  sheetReady = null;

  get accept() {
    return ".xlsx,.xlsm,.xls,.csv";
  }

  async handleFile(event) {
    const file = event.target.files && event.target.files[0];
    if (!file) return;
    this.error = null;
    if (file.size > MAX_BYTES) {
      this.error =
        "The file is larger than 3 MB. Split it and upload the parts.";
      return;
    }
    try {
      this.status = "Reading…";
      const buffer = await this.readBuffer(file);
      await this.ensureSheetJs();
      const workbook = window.XLSX.read(new Uint8Array(buffer), {
        type: "array"
      });
      const { headers, rows } = parse(
        workbook,
        window.XLSX.utils.sheet_to_json
      );
      if (rows.length > MAX_ROWS) {
        throw new Error("Split the file; the workbench handles 2,000 lanes");
      }
      this.status = "Attaching…";
      await attachFile({
        projectId: this.projectId,
        fileName: file.name,
        base64: toBase64(buffer)
      });
      this.status = `${file.name}: ${rows.length} rows`;
      this.dispatchEvent(
        new CustomEvent("parsed", {
          detail: { fileName: file.name, headers, rows }
        })
      );
    } catch (e) {
      this.status = "";
      this.error =
        e?.body?.message || e?.message || "The file could not be read.";
    }
  }

  readBuffer(file) {
    if (typeof file.arrayBuffer === "function") return file.arrayBuffer();
    return new Promise((resolve, reject) => {
      const r = new FileReader();
      r.onload = () => resolve(r.result);
      r.onerror = () => reject(new Error("The file could not be read."));
      r.readAsArrayBuffer(file);
    });
  }

  ensureSheetJs() {
    if (window.XLSX) return Promise.resolve();
    if (!this.sheetReady) this.sheetReady = loadScript(this, sheetJs);
    return this.sheetReady;
  }
}

function toBase64(buffer) {
  const bytes = new Uint8Array(buffer);
  let binary = "";
  for (let i = 0; i < bytes.length; i += 0x8000) {
    binary += String.fromCharCode.apply(null, bytes.subarray(i, i + 0x8000));
  }
  return window.btoa(binary);
}
```

`rfpUpload.html`:

```html
<template>
  <div class="slds-form-element">
    <label class="slds-form-element__label" for="file"
      >Lane file (.xlsx, .xlsm, .xls, .csv — up to 3 MB, 2,000 lanes)</label
    >
    <div class="slds-form-element__control">
      <input id="file" type="file" accept="{accept}" onchange="{handleFile}" />
    </div>
    <template lwc:if="{status}"
      ><p data-id="status" class="slds-text-color_weak slds-m-top_xx-small">
        {status}
      </p></template
    >
    <template lwc:if="{error}"
      ><p data-id="error" class="slds-text-color_error slds-m-top_xx-small">
        {error}
      </p></template
    >
  </div>
</template>
```

`rfpColumnMapper.js`:

```javascript
import { LightningElement, api } from "lwc";
import { TARGETS, missingRequired } from "c/rfpHeaderGuess";

export default class RfpColumnMapper extends LightningElement {
  @api headers = [];
  @api sampleRows = [];
  _mapping = {};
  @api
  get mapping() {
    return this._mapping;
  }
  set mapping(v) {
    this._mapping = { ...(v || {}) };
  }

  get options() {
    return [
      { label: "— none —", value: "" },
      ...(this.headers || []).map((h) => ({ label: h, value: h }))
    ];
  }
  get targets() {
    return TARGETS.map((t) => ({
      ...t,
      value: this._mapping[t.key] || "",
      sample: this.sampleFor(this._mapping[t.key])
    }));
  }
  sampleFor(header) {
    const i = (this.headers || []).indexOf(header);
    if (i < 0) return "";
    return (this.sampleRows || [])
      .map((r) => r[i])
      .filter((v) => v !== "" && v !== undefined)
      .slice(0, 3)
      .join(" · ");
  }
  get missing() {
    return missingRequired(this._mapping).map(
      (k) => TARGETS.find((t) => t.key === k).label
    );
  }
  get missingText() {
    return this.missing.length
      ? `Map ${this.missing.join(" and ")} (or both postal columns) to import.`
      : "";
  }
  get cannotImport() {
    return this.missing.length > 0;
  }

  handleChange(event) {
    const key = event.target.dataset.target;
    const next = { ...this._mapping };
    if (event.detail.value) next[key] = event.detail.value;
    else delete next[key];
    this._mapping = next;
    this.dispatchEvent(
      new CustomEvent("mappingchange", { detail: { mapping: { ...next } } })
    );
  }
  handleImport() {
    this.dispatchEvent(
      new CustomEvent("import", { detail: { mapping: { ...this._mapping } } })
    );
  }
}
```

`rfpColumnMapper.html`:

```html
<template>
  <div class="slds-grid slds-wrap slds-gutters_small">
    <template for:each="{targets}" for:item="t">
      <div
        key="{t.key}"
        class="slds-col slds-size_1-of-2 slds-p-bottom_x-small"
      >
        <lightning-combobox
          data-target="{t.key}"
          label="{t.label}"
          value="{t.value}"
          options="{options}"
          onchange="{handleChange}"
        ></lightning-combobox>
        <p class="slds-text-color_weak slds-text-body_small">{t.sample}</p>
      </div>
    </template>
  </div>
  <template lwc:if="{missingText}"
    ><p data-id="missing" class="slds-text-color_error">
      {missingText}
    </p></template
  >
  <lightning-button
    data-id="import"
    variant="brand"
    label="Import lanes"
    disabled="{cannotImport}"
    onclick="{handleImport}"
  ></lightning-button>
</template>
```

- [ ] **Step 3: Test, lint, commit** — `Add rfpUpload and rfpColumnMapper`.

---

### Task 7: rfpLaneTable, rfpBidForm, rfpAccountPicker, rfpLanePanel

**Files:**

- Create: the four bundles (+tests). `rfpAccountPicker` is the typeahead used by `rfpBidForm` (carrier) and by `rfpProjectList` in Task 8 (customer).

**Interfaces:**

- `c-rfp-account-picker`: `@api label`, `@api kind` (`customer` | `carrier`), `@api value` (Id, get/set), `@api valueLabel`; debounced (250 ms, eslint-disable line) `searchAccounts({ term, kind })`; list of options (`data-id="option"`), pick → `accountchange { id, name }`; clear button → `accountchange { id: null, name: "" }`.
- `c-rfp-lane-table`: `@api lanes` (get/set → `_lanes`), `@api selectedId`, `@api currency`; one row per lane (`data-id="lane-row"`, `data-lane-id`): row #, origin (city, province; a `c-lane-benchmark-place-picker` inline when `!Origin_Resolved__c`), destination (same), mode, equipment, history (`Hist_Count__c` and `Hist_Median__c`, title with min/avg/max; status text for Pending/Failed/No match/Unresolved), cost, margin, sell, status text (`Cost__c` ? "Priced" : ""). Events: `select { laneId }` on row click; `resolveend { laneId, side, key }` from the picker's `placechange` (only when `key` is set).
- `c-rfp-bid-form`: `@api laneId`, `@api currency` (default), `@api bid` (edit; get/set); fields: carrier picker OR "Carrier not in the system" toggle (`data-id="new-carrier"`) revealing `Carrier_Name__c`, `Contact_Name__c`, `Contact_Email__c`, `Contact_Phone__c`; `Rate__c`, `CurrencyIsoCode` (CAD/USD), `Fuel_Surcharge__c`, `FSC_Included__c`, `Transit_Days__c`, `Valid_From__c` (default today), `Expires_On__c` (default today + 30), `Notes__c`. Save (`data-id="save"`) validates rate > 0 and carrier-or-name, then emits `save { bid }` (a plain object with `RFP_Lane__c` set); Cancel emits `cancel`.
- `c-rfp-lane-panel`: `@api lane` (get/set), `@api project`; loads bids via `getBids({ laneId })` and history rows via `LaneBenchmarkController.search` (JSON request: keys from `Origin_Place__r.Key__c`/`Destination_Place__r.Key__c`, precision from `Hist_Precision__c` (`RADIUS-50KM` → RADIUS 50 km both ends), lookback `Hist_Lookback_Days__c || 90`, `sourceFilter: "LOADS"`, `rowLimit: 500`) rendered through `c-lane-benchmark-results`; pricing editor: radio `Cost source` (Bid / History median / Manual) with a bid select (`data-id="bid-select"`), a manual cost input, margin input (`c/marginMath.parseMargin`), computed sell (`suggestedSell`); "Save price" emits `pricingchange { laneId, Cost__c, Cost_Source__c, Selected_Bid__c, Margin__c, Sell__c, Notes__c }`; "Add carrier rate" opens `c-rfp-bid-form`; on its `save`, calls `saveBid({ bidJson })`, refreshes bids, emits `bidsaved { laneId }`; a "Use as cost" hint (`data-id="best-bid-hint"`) appears when `bestBid(bids, currency)` is cheaper than the current cost; `otherCurrencyCount > 0` shows "n bids in another currency are not compared".

- [ ] **Step 1: Failing tests** (essential cases per bundle)

`rfpLaneTable.test.js`: renders one row per lane with history text ("2 · median 2,000.00" via `toLocaleString`? keep plain `toFixed(2)`), shows a picker only for unresolved ends, emits `select` on row click and `resolveend` when the picker emits `placechange` with a key.

`rfpBidForm.test.js`: Save is blocked with an error (`data-id="form-error"`) when rate is empty; with the new-carrier toggle on and a name plus rate, Save emits a bid whose `Carrier_Name__c` is set and `Carrier__c` is null; dates default (Valid_From today, Expires_On +30 as ISO `yyyy-mm-dd`).

`rfpAccountPicker.test.js`: typing "Acm" calls `searchAccounts` after 250 ms with `{ term: "Acm", kind: "carrier" }`, clicking an option emits `accountchange { id, name }`.

`rfpLanePanel.test.js`: mounting with a resolved lane calls `getBids` and `search` (payload has `sourceFilter: "LOADS"` and both keys); choosing "History median" sets the cost to `Hist_Median__c` and "Save price" emits `pricingchange` with `Sell__c = suggestedSell(cost, margin)`; when a cheaper active bid exists the hint renders; after `c-rfp-bid-form` emits `save`, `saveBid` is called and `bidsaved` is emitted.

- [ ] **Step 2: Implement** — follow the interfaces above; reuse `laneBenchmarkPlacePicker`'s list markup for the account picker; every `@api` mutated internally goes through a backing field; the 250 ms debounce carries `// eslint-disable-next-line @lwc/lwc/no-async-operation -- debounce the typeahead`. Panel search payload:

```javascript
  historyRequest() {
    const l = this._lane;
    const radius = l.Hist_Precision__c === "RADIUS-50KM";
    const precision = radius ? "RADIUS" : l.Hist_Precision__c || "CITY";
    return JSON.stringify({
      originKey: l.Origin_Place__r?.Key__c,
      destinationKey: l.Destination_Place__r?.Key__c,
      originPrecision: precision,
      destinationPrecision: precision,
      originRadius: radius ? 50 : null,
      destinationRadius: radius ? 50 : null,
      radiusUnit: "KM",
      lookbackDays: l.Hist_Lookback_Days__c || 90,
      sourceFilter: "LOADS",
      rowLimit: 500,
      includeStopGeolocation: true
    });
  }
```

- [ ] **Step 3: Test, lint, commit** — `Add the RFP lane table, lane panel, bid form and account picker`.

---

### Task 8: rfpProjectList, rfpExport, rfpTool container, navigation retarget

**Files:**

- Create: `rfpProjectList/*`, `rfpExport/*`, `rfpTool/*` (+tests; `rfpTool.js-meta.xml` exposed to `lightning__AppPage` and `lightning__HomePage`, masterLabel "RFP Tool")
- Modify: `rfpProjectsForAccount/rfpProjectsForAccount.js` (+test)

**Interfaces:**

- `c-rfp-project-list`: loads `listProjects()`; table rows (`data-id="project-row"`, click → `open { projectId }`); "New project" form: name, customer (`c-rfp-account-picker kind="customer"`), due date, currency (CAD/USD), default margin (15); Create → `saveProject({ projectJson })` then `open`.
- `c-rfp-export`: `@api project`, `@api lanes`, `@api bidsByLaneId`; button "Export to Excel"; when no lane has `Cost__c`, a confirm text with a second button ("Export anyway", `data-id="export-anyway"`); on export: page `getRawRows` (offset 0, 500, … until fewer than 500), `buildSheets`, `ensureSheetJs` (same helper as upload — put it in a tiny shared module `c/rfpSheetLoader` exporting `ensureSheetJs(component)`; `rfpUpload` switches to it), `XLSX.utils.book_new/aoa_to_sheet/book_append_sheet`, `XLSX.write(wb, { bookType: "xlsx", type: "array" })` → `Blob` → attached anchor + deferred revoke; file name from `exportFileName(project.Customer__r.Name, project.Name, new Date())`.
- `c-rfp-tool`: `@wire(CurrentPageReference)` → `state.c__projectId` opens that project; views: `list` | `upload` | `map` | `workbench`. Workbench holds `project`, `lanes` (from `getLanes`), `selectedId`, `bidsByLaneId` (filled lazily by the panel's `bidsaved`/on export via `getBids` per lane — for export fetch bids for lanes with `Selected_Bid__c` only), history toolbar: precision (`CITY`/`PROVINCE`/`RADIUS`), lookback (number), "Load history" (runs over lanes with `Hist_Status__c` in Pending/Unresolved-resolved-now or all when "Refresh history"), "Retry failed", "Stop"; runs `loadHistory({ laneIds: chunk(10), precision, lookbackDays })` sequentially, merging returned lanes into `lanes`, with a `lightning-progress-bar`; import runs `importLanes` in chunks of 200 with progress and a summary line, then loads lanes. `pricingchange` → `saveLanePricing({ laneJson })` and merge; `resolveend` → `resolveLaneEnd({ laneId, side, placeKey })` and merge, then history for that lane.
- `rfpProjectsForAccount.handleOpen` → `this[NavigationMixin.Navigate]({ type: "standard__navItemPage", attributes: { apiName: "RFP_Tool" }, state: { c__projectId: id } })`.

- [ ] **Step 1: Failing tests** (essential): project list renders rows and opens; new-project Create calls `saveProject` with the JSON containing `Customer__c` and emits `open`; export builds and downloads (mock `window.XLSX` with `write` returning `new Uint8Array(2)`; assert `Blob` created and `getRawRows` paged: first call returns 500 rows, second 3 → called twice); export-anyway path when no cost; container: with `c__projectId` in the page reference it calls `getProject` + `getLanes` and shows the workbench; "Load history" chunks 23 pending lanes into 10/10/3 calls in order and merges the returned snapshots; import chunks 450 rows into 200/200/50; navigation retarget test asserts the `Navigate` call payload (NavigationMixin stub records calls: `getNavigateCalledWith` from `lightning/navigation` stub).

- [ ] **Step 2: Implement** per the interfaces; history loop:

```javascript
  async runHistory(laneIds) {
    this.stopRequested = false;
    this.progress = { done: 0, total: laneIds.length };
    for (let i = 0; i < laneIds.length && !this.stopRequested; i += 10) {
      const chunk = laneIds.slice(i, i + 10);
      try {
        const updated = await loadHistory({ laneIds: chunk, precision: this.precision, lookbackDays: this.lookbackDays });
        this.mergeLanes(updated);
      } catch (e) {
        this.mergeLanes(chunk.map((id) => ({ ...this.laneById(id), Hist_Status__c: "Failed" })));
        this.error = e?.body?.message || "History failed for a chunk; use Retry failed.";
      }
      this.progress = { done: Math.min(i + 10, laneIds.length), total: laneIds.length };
    }
  }
```

- [ ] **Step 3: Test, lint, commit** — `Add the RFP tool container, project list and Excel export; open projects from the Account component`.

---

### Task 9: Tab, page, apps, permission set; deploy; browser checks

**Files:**

- Create: `force-app/main/default/flexipages/RFP_Tool.flexipage-meta.xml` (copy `Lane_Benchmark`'s with `rfpTool`/`c_rfpTool`, masterLabel "RFP Tool"), `tabs/RFP_Tool.tab-meta.xml` (label "RFP Tool", description "RFP Tool: price customer lane requests", motif `Custom80: Motorcycle`)
- Modify: `applications/Lane_Benchmark.app-meta.xml` (add `<tabs>RFP_Tool</tabs>` after `Lane_Benchmark`), `applications/TransPro.app-meta.xml` (**re-retrieve first**: `sf project retrieve start -m CustomApplication:TransPro -o sandbox`, prettier it, `git diff` it — if the org copy differs from the repo beyond formatting, keep the org's version and report the difference — then append `<tabs>RFP_Tool</tabs>` last), `permissionsets/RFP_Tool_User.permissionset-meta.xml` (`applicationVisibilities` `Lane_Benchmark` visible; `tabSettings` `RFP_Tool` Visible; also `Lane_Benchmark` tab Visible so the app makes sense), `manifest/package.xml` (`FlexiPage:RFP_Tool`, `CustomTab:RFP_Tool`)

- [ ] **Step 1: Metadata, deploy** (permission set first with NoTestRun, then the full test deploy with the 19-class list). Expected Succeeded.
- [ ] **Step 2: Browser checks (controller, recorded in the spec Outcome by Task 10):** open the RFP Tool tab in Trans-Pro; create a project for a customer; upload a small anonymized `.xlsx` (≥ 20 lanes, one unresolved city, one postal-only row); map; import; load history (CITY 90 days) and see Done/No match/Unresolved statuses; fix an unresolved end with the inline picker; price three lanes (bid, median, manual); add a new-carrier bid and an existing-carrier bid; export and open the file; open the project from the customer Account component once the admin has placed it (or via URL `c__projectId`); confirm the bid appears in Lane Benchmark (Source = Bids only).
- [ ] **Step 3: Commit** — `Add the RFP Tool tab, page and app entries`.

---

### Task 10: Docs and outcome

- README: `## RFP Tool (phase 3b)` — how to open it, the flow (project → upload → map → import → history → price → bids → export), limits (3 MB, 2,000 lanes, 10 lanes per history call, 500 rows), the `sheetJs` org coupling (static resource owned elsewhere, version 0.18.5, referenced by name), the typeaheads, where the file is stored (Files on the project), the custom permission; update "What is in here" and the test lists (19 classes, verify only).
- Spec: `## Outcome — 3b (<date>)`: commits, deploy ids and counts per task, Jest count, rulings 1–13 plus every ledger ruling, browser-check results, deferred items.
- Roadmap: phase 3 row → "Done <date>"; phase 4 next.
- Plan header: defects found in verbatim code.
- Commit: `Document the RFP workbench (phase 3b) and record its outcome`.

---

## Self-review

**Spec coverage (3b scope).** Controller methods (spec list): `listProjects`, `getProject`, `saveProject`, `importLanes`, `getLanes`, `loadHistory`, `saveLanePricing`, `saveBid`, `getBids`, `columnMappingFor` — Tasks 2–4 (split across four controllers, ruling 5) plus `attachFile`, `searchAccounts`, `getRawRows`, `resolveLaneEnd`. `RfpImportService` (normalize, resolve by key then postal, flags, margin, raw): Task 2. `RfpHistoryService` (request per lane, LOADS, snapshot, CITY→RADIUS fallback, statuses): Task 3 (10 per call, ruling 2). LWC bundles: `rfpTool` (8), `rfpProjectList` (8), `rfpUpload` (6, ruling 1), `rfpColumnMapper` (6), `rfpLaneTable` (7), `rfpLanePanel` (7), `rfpBidForm` (7, typeahead ruling 11), `rfpExport` (8, ruling 7), `rfpMath` (5), plus `rfpHeaderGuess`/`rfpSheet`/`rfpWorkbook`/`rfpAccountPicker`. Navigation (tab, page, both apps): Task 9. Flow steps 1–9: Tasks 6–9. Error handling table: upload errors (6), missing mapping (6), skipped rows (2), unresolved ends (2, 7, 8), chunk failure + retry (8), bid validation (7 + rule), mixed currencies (7), export confirmation (8), AuraHandledException everywhere (2–4). Limits: 2,000 rows (5/6), 200 per import (2), 10 per history (3), 500 raw rows (2/8), SheetJS version verified (0.18.5). 3a deferrals: save() strip, precision tests, runAs (Task 1). Docs: Task 10.

**Placeholders.** None: every Apex class and pure module is written in full; the UI bundles of Tasks 7–8 specify interfaces, events, payloads and the essential tests, with the two non-obvious pieces (history request, history loop) written out.

**Type consistency.** `ImportRow`/`RowEnd` shape identical in `rfpSheet.toImportRows` output, `RfpLaneController.importLanes` JSON and `RfpImportService`. `LANE_FIELDS` includes `Origin_Place__r.Key__c`/`Destination_Place__r.Key__c` used by `RfpHistoryService` and the panel, and `Selected_Bid__r.Carrier_Display__c` used by `rfpWorkbook`. `saveLanePricing` whitelist = the `pricingchange` payload. `getBids` fields = `rfpWorkbook` bid sheet and `rfpMath` inputs. `searchAccounts(term, kind)` = `rfpAccountPicker`. `loadHistory(laneIds, precision, lookbackDays)` = the container loop. `attachFile(projectId, fileName, base64)` = `rfpUpload`. `Hist_Precision__c` values `CITY`/`PROVINCE`/`RADIUS-50KM` consistent between service, panel and table.
