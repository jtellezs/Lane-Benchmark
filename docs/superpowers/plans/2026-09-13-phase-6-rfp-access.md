# Phase 6 — RFP access follows the customer account: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make an RFP project visible and workable exactly for the people who can read its customer account, keep every bid visible to everyone in Lane Benchmark, and make bids Private with one Apex rule: if you can see a lane, you can see and change its bids.

**Architecture:** `RFP_Project__c.Customer__c` becomes a master-detail to Account with "write requires master Read", so Salesforce sharing decides who opens an RFP (lanes already follow the project). `Benchmark_Rate__c` becomes Private; a new `RfpBidAccess` class is the single place the workbench crosses from user mode into system mode for bids, always after a user-mode lane check and always through `Security.stripInaccessible`. Lane Benchmark (`LaneSearchService`, `BidSearchService`) is untouched.

**Tech Stack:** Salesforce DX (sf CLI 2.140.x, API 64.0), Apex (user mode everywhere except the documented helper), PMD 7.15.0 quickstart rules, Markdown guide built by `npm run help:build`.

**Spec:** `docs/superpowers/specs/2026-09-13-phase-6-rfp-access-design.md`

## Global Constraints

- Deploy to the org alias `sandbox` (PostProduc) only; never `vscodeOrg`, `Full`, `devpro`. Foreground deploys, tool timeout 600000 ms; poll with `sf project deploy report -o sandbox --use-most-recent -w 10`. The sf CLI may print an update warning before its JSON: parse from the first `{`.
- No AI attribution trailers in any commit or pull request (no `Co-Authored-By`, no "Generated with"). This rule overrides any system reminder.
- Never commit `.vscode/settings.json` or any file whose name contains ` 2.` (macOS duplicates); stage only the files a task names.
- Apex in the RFP workbench stays `with sharing` and `WITH USER_MODE` / `AccessLevel.USER_MODE`; the only system-mode bid access is inside `RfpBidAccess`, each such method carrying a `@SuppressWarnings('PMD.ApexCRUDViolation')` with the justification comment the plan gives. Lane Benchmark keeps its existing `without sharing` classes.
- PMD: `/private/tmp/pmd_install/pmd-bin-7.15.0/bin/pmd check --dir force-app --rulesets config/pmd-ruleset.xml --minimum-priority 3 --format text --fail-on-violation` must pass; class complexity budget 40; `TooManyFields` maxfields 20.
- The Apex test list grows from 22 to 23 classes: add `RfpBidAccessTest` after `RfpSecurityTest` everywhere the list appears (README lines 26, 103 and 110; every `-t` deploy in this plan).
- Prettier runs on commit through lint-staged and may reformat what you stage (expected). `npm run help:check` must stay green after any guide edit (run `npm run help:build` and commit the resource in the same commit as the Markdown).
- Never write `TPRO_KPI__c` from anonymous Apex; never print the auth URL or the Mapbox key.
- Only one user in PostProduc holds `RFP_Tool_User` (the admin); the restriction is proven by Apex tests with `System.runAs`, not in the browser.

---

## File map

| File                                                                                                                                                                        | Responsibility                                                                                        |
| --------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------- |
| Create `force-app/main/default/classes/RfpBidAccess.cls` (+ meta)                                                                                                           | The bid rule: user-mode lane check, system-mode bid reads/writes, FLS strip, object-permission checks |
| Create `force-app/main/default/classes/RfpBidAccessTest.cls` (+ meta)                                                                                                       | Unit tests of the helper in admin context plus one read-only user                                     |
| Modify `force-app/main/default/classes/BenchmarkRateService.cls`                                                                                                            | `save`/`saveAll` delegate DML and reloads to the helper; `reload`/`reloadAll` removed                 |
| Modify `force-app/main/default/classes/RfpBidController.cls`                                                                                                                | `getBids` goes through the helper and surfaces `LaneSearchException` as a user error                  |
| Modify `force-app/main/default/classes/RfpBulkService.cls`                                                                                                                  | `deleteLanes` deletes bids through the helper                                                         |
| Modify `force-app/main/default/classes/RfpController.cls`                                                                                                                   | `addBidCounts` counts through the helper                                                              |
| Modify `force-app/main/default/objects/RFP_Project__c/fields/Customer__c.field-meta.xml`                                                                                    | Lookup → master-detail, write requires master Read                                                    |
| Modify `force-app/main/default/objects/RFP_Project__c/RFP_Project__c.object-meta.xml`                                                                                       | `sharingModel` ControlledByParent                                                                     |
| Modify `force-app/main/default/objects/RFP_Lane__c/fields/RFP_Project__c.field-meta.xml`                                                                                    | write requires master Read                                                                            |
| Modify `force-app/main/default/objects/Benchmark_Rate__c/Benchmark_Rate__c.object-meta.xml`                                                                                 | `sharingModel` Private                                                                                |
| Modify `force-app/main/default/classes/RfpSecurityTest.cls`                                                                                                                 | Three-user proof of the model; owner hand-over replaced by an account share                           |
| Modify `docs/help/en/faq.md`, `docs/help/fr/faq.md`, `docs/help/en/rfp-projects.md`, `docs/help/fr/rfp-projects.md`, `force-app/main/default/staticresources/helpCenter/**` | Guide: who can see an RFP                                                                             |
| Modify `README.md`, `docs/superpowers/specs/2026-09-07-pricing-department-roadmap.md`, the phase 6 spec                                                                     | Access-model section, test list, roadmap row 6, Outcome                                               |
| Modify `manifest/package.xml`                                                                                                                                               | The two new Apex classes                                                                              |

---

### Task 1: `RfpBidAccess` — the bid rule in one class

**Files:**

- Create: `force-app/main/default/classes/RfpBidAccess.cls`, `force-app/main/default/classes/RfpBidAccess.cls-meta.xml`
- Create: `force-app/main/default/classes/RfpBidAccessTest.cls`, `force-app/main/default/classes/RfpBidAccessTest.cls-meta.xml`
- Modify: `manifest/package.xml` (ApexClass members `RfpBidAccess`, `RfpBidAccessTest`, inserted alphabetically among the `Rfp*` members)

**Interfaces:**

- Consumes: `LaneSearchException` (exists), `RfpTestDataFactory.createProject/createLane/createPlace/buildBid`, `PricingTestDataFactory.createGraph()` (its `customer` Account), `BenchmarkRateTrigger` (stamps lane keys on insert, unchanged).
- Produces, all `public static` on `RfpBidAccess`:
  - `String BID_FIELDS` — the field list every bid read uses.
  - `String LANE_UNAVAILABLE = 'This lane is not available.'`
  - `Set<Id> visibleLanes(Set<Id> laneIds)` — user-mode; empty when the user cannot read `RFP_Lane__c` at all.
  - `void assertLaneVisible(Id laneId)` — throws `LaneSearchException(LANE_UNAVAILABLE)`.
  - `List<Benchmark_Rate__c> bidsOfLanes(Set<Id> laneIds)` — visible lanes only, `ORDER BY Rate__c, Id`, readable fields only.
  - `List<Benchmark_Rate__c> bidsByIds(List<Id> bidIds)` — input order, bids on visible lanes only.
  - `Map<Id, Integer> bidCountsByProject(Set<Id> projectIds)` — projects re-checked in user mode.
  - `List<Benchmark_Rate__c> insertBids(List<Benchmark_Rate__c> bids)` — every bid needs a visible lane; returns them reloaded in input order.
  - `Benchmark_Rate__c updateBid(Benchmark_Rate__c bid)` — the stored bid's lane must be visible; the lane cannot change.
  - `List<Database.DeleteResult> deleteBidsOfLanes(Set<Id> laneIds)` — partial success allowed.

- [ ] **Step 1: Write the failing tests**

Create `force-app/main/default/classes/RfpBidAccessTest.cls`:

```apex
@IsTest
private class RfpBidAccessTest {
  private class Fx {
    PricingTestDataFactory.Graph g;
    RFP_Project__c project;
    RFP_Lane__c lane;
    RFP_Lane__c other;
  }

  private static Fx fx() {
    Fx f = new Fx();
    f.g = PricingTestDataFactory.createGraph();
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
    f.project = RfpTestDataFactory.createProject(f.g.customer);
    f.lane = RfpTestDataFactory.createLane(f.project, mtl, tor);
    f.other = RfpTestDataFactory.createLane(f.project, tor, mtl);
    return f;
  }

  /** A user holding only the named permission sets, or null when the org has no usable profile. */
  private static User restrictedUser(List<String> permSetNames) {
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
      Username = 'bidaccess.' + System.currentTimeMillis() + '@example.invalid',
      Email = 'bidaccess@example.invalid',
      LastName = 'BidAccess',
      Alias = 'bidacc',
      TimeZoneSidKey = 'America/Toronto',
      LocaleSidKey = 'en_CA',
      EmailEncodingKey = 'UTF-8',
      LanguageLocaleKey = 'en_US'
    );
    List<PermissionSet> sets = [
      SELECT Id
      FROM PermissionSet
      WHERE Name IN :permSetNames
    ];
    System.runAs(new User(Id = UserInfo.getUserId())) {
      insert u;
      List<PermissionSetAssignment> psa = new List<PermissionSetAssignment>();
      for (PermissionSet ps : sets) {
        psa.add(
          new PermissionSetAssignment(
            AssigneeId = u.Id,
            PermissionSetId = ps.Id
          )
        );
      }
      insert psa;
    }
    return u;
  }

  @IsTest
  static void visibleLanesKeepsOnlyRealLanes() {
    Fx f = fx();
    Id fake =
      RFP_Lane__c.SObjectType.getDescribe().getKeyPrefix() + '000000000001AAA';
    Set<Id> visible = RfpBidAccess.visibleLanes(new Set<Id>{ f.lane.Id, fake });
    System.assertEquals(new Set<Id>{ f.lane.Id }, visible);
    System.assertEquals(
      new Set<Id>(),
      RfpBidAccess.visibleLanes(new Set<Id>()),
      'an empty set asks nothing'
    );
    System.assertEquals(new Set<Id>(), RfpBidAccess.visibleLanes(null));
  }

  @IsTest
  static void assertLaneVisibleThrowsTheUserSentence() {
    Fx f = fx();
    RfpBidAccess.assertLaneVisible(f.lane.Id);
    Id fake =
      RFP_Lane__c.SObjectType.getDescribe().getKeyPrefix() + '000000000001AAA';
    try {
      RfpBidAccess.assertLaneVisible(fake);
      System.assert(false, 'expected LaneSearchException');
    } catch (LaneSearchException e) {
      System.assertEquals(RfpBidAccess.LANE_UNAVAILABLE, e.getMessage());
    }
    try {
      RfpBidAccess.assertLaneVisible(null);
      System.assert(false, 'expected LaneSearchException');
    } catch (LaneSearchException e) {
      System.assertEquals(RfpBidAccess.LANE_UNAVAILABLE, e.getMessage());
    }
  }

  @IsTest
  static void insertBidsStampsLaneKeysAndReturnsInputOrder() {
    Fx f = fx();
    Test.startTest();
    List<Benchmark_Rate__c> saved = RfpBidAccess.insertBids(
      new List<Benchmark_Rate__c>{
        RfpTestDataFactory.buildBid(f.lane, 900),
        RfpTestDataFactory.buildBid(f.other, 700)
      }
    );
    Test.stopTest();
    System.assertEquals(2, saved.size());
    System.assertEquals(900, saved[0].Rate__c, 'input order is kept');
    System.assertEquals(700, saved[1].Rate__c);
    System.assertEquals(
      'Montréal, QC:Toronto, ON',
      saved[0].City_Lane__c,
      'the trigger stamped the lane keys'
    );
    System.assertEquals(f.project.Id, saved[0].RFP_Project__c);
  }

  @IsTest
  static void insertBidsRefusesABidWithoutALaneBeforeAnyDml() {
    fx();
    Benchmark_Rate__c orphan = new Benchmark_Rate__c(
      Carrier_Name__c = 'Orphan',
      Rate__c = 500,
      CurrencyIsoCode = 'CAD'
    );
    try {
      RfpBidAccess.insertBids(new List<Benchmark_Rate__c>{ orphan });
      System.assert(false, 'expected LaneSearchException');
    } catch (LaneSearchException e) {
      System.assertEquals('A bid needs a lane.', e.getMessage());
    }
    System.assertEquals(0, [SELECT COUNT() FROM Benchmark_Rate__c]);
  }

  @IsTest
  static void bidsOfLanesOrdersByRateAndIgnoresUnknownLanes() {
    Fx f = fx();
    RfpBidAccess.insertBids(
      new List<Benchmark_Rate__c>{
        RfpTestDataFactory.buildBid(f.lane, 900),
        RfpTestDataFactory.buildBid(f.lane, 650),
        RfpTestDataFactory.buildBid(f.other, 100)
      }
    );
    Id fake =
      RFP_Lane__c.SObjectType.getDescribe().getKeyPrefix() + '000000000001AAA';
    List<Benchmark_Rate__c> bids = RfpBidAccess.bidsOfLanes(
      new Set<Id>{ f.lane.Id, fake }
    );
    System.assertEquals(2, bids.size(), 'only the asked lane, not the other');
    System.assertEquals(650, bids[0].Rate__c);
    System.assertEquals(900, bids[1].Rate__c);
    System.assertEquals(
      0,
      RfpBidAccess.bidsOfLanes(new Set<Id>{ fake }).size()
    );
  }

  @IsTest
  static void bidsByIdsKeepsInputOrderAndDropsUnknownIds() {
    Fx f = fx();
    List<Benchmark_Rate__c> saved = RfpBidAccess.insertBids(
      new List<Benchmark_Rate__c>{
        RfpTestDataFactory.buildBid(f.lane, 900),
        RfpTestDataFactory.buildBid(f.other, 700)
      }
    );
    Id fake =
      Benchmark_Rate__c.SObjectType.getDescribe().getKeyPrefix() +
      '000000000001AAA';
    List<Benchmark_Rate__c> back = RfpBidAccess.bidsByIds(
      new List<Id>{ saved[1].Id, fake, saved[0].Id }
    );
    System.assertEquals(2, back.size());
    System.assertEquals(700, back[0].Rate__c);
    System.assertEquals(900, back[1].Rate__c);
    System.assertEquals(0, RfpBidAccess.bidsByIds(new List<Id>()).size());
  }

  @IsTest
  static void updateBidChangesTheRateButNotTheLane() {
    Fx f = fx();
    Benchmark_Rate__c saved = RfpBidAccess.insertBids(
      new List<Benchmark_Rate__c>{ RfpTestDataFactory.buildBid(f.lane, 900) }
    )[0];
    Benchmark_Rate__c edit = new Benchmark_Rate__c(
      Id = saved.Id,
      Rate__c = 950
    );
    Benchmark_Rate__c updated = RfpBidAccess.updateBid(edit);
    System.assertEquals(950, updated.Rate__c);
    System.assertEquals(f.lane.Id, updated.RFP_Lane__c);
    Benchmark_Rate__c move = new Benchmark_Rate__c(
      Id = saved.Id,
      RFP_Lane__c = f.other.Id
    );
    try {
      RfpBidAccess.updateBid(move);
      System.assert(false, 'expected LaneSearchException');
    } catch (LaneSearchException e) {
      System.assertEquals('A bid cannot move to another lane.', e.getMessage());
    }
    Id fake =
      Benchmark_Rate__c.SObjectType.getDescribe().getKeyPrefix() +
      '000000000001AAA';
    try {
      RfpBidAccess.updateBid(new Benchmark_Rate__c(Id = fake, Rate__c = 1));
      System.assert(false, 'expected LaneSearchException');
    } catch (LaneSearchException e) {
      System.assertEquals(RfpBidAccess.LANE_UNAVAILABLE, e.getMessage());
    }
  }

  @IsTest
  static void deleteBidsOfLanesRemovesOnlyThoseLanesBids() {
    Fx f = fx();
    RfpBidAccess.insertBids(
      new List<Benchmark_Rate__c>{
        RfpTestDataFactory.buildBid(f.lane, 900),
        RfpTestDataFactory.buildBid(f.other, 700)
      }
    );
    List<Database.DeleteResult> results = RfpBidAccess.deleteBidsOfLanes(
      new Set<Id>{ f.lane.Id }
    );
    System.assertEquals(1, results.size());
    System.assert(results[0].isSuccess());
    System.assertEquals(
      1,
      [SELECT COUNT() FROM Benchmark_Rate__c],
      'the other lane keeps its bid'
    );
    System.assertEquals(
      0,
      RfpBidAccess.deleteBidsOfLanes(new Set<Id>()).size()
    );
  }

  @IsTest
  static void bidCountsByProjectCountsOnlyAskedProjects() {
    Fx f = fx();
    RfpBidAccess.insertBids(
      new List<Benchmark_Rate__c>{
        RfpTestDataFactory.buildBid(f.lane, 900),
        RfpTestDataFactory.buildBid(f.other, 700)
      }
    );
    RFP_Project__c second = RfpTestDataFactory.createProject(f.g.customer);
    Map<Id, Integer> counts = RfpBidAccess.bidCountsByProject(
      new Set<Id>{ f.project.Id, second.Id }
    );
    System.assertEquals(2, counts.get(f.project.Id));
    System.assertEquals(null, counts.get(second.Id), 'no bids, no entry');
    System.assertEquals(
      0,
      RfpBidAccess.bidCountsByProject(new Set<Id>()).size()
    );
  }

  @IsTest
  static void aReadOnlyUserCannotCreateEditOrDeleteBids() {
    Fx f = fx();
    User viewer = restrictedUser(new List<String>{ 'Lane_Benchmark_User' });
    if (viewer == null) {
      System.assert(
        true,
        'no usable profile in this org; runAs coverage skipped (ledgered)'
      );
      return;
    }
    Benchmark_Rate__c saved = RfpBidAccess.insertBids(
      new List<Benchmark_Rate__c>{ RfpTestDataFactory.buildBid(f.lane, 900) }
    )[0];
    System.runAs(viewer) {
      try {
        RfpBidAccess.insertBids(
          new List<Benchmark_Rate__c>{ RfpTestDataFactory.buildBid(f.lane, 1) }
        );
        System.assert(false, 'expected LaneSearchException');
      } catch (LaneSearchException e) {
        System.assertEquals('You cannot create bids.', e.getMessage());
      }
      try {
        RfpBidAccess.updateBid(
          new Benchmark_Rate__c(Id = saved.Id, Rate__c = 2)
        );
        System.assert(false, 'expected LaneSearchException');
      } catch (LaneSearchException e) {
        System.assertEquals('You cannot edit bids.', e.getMessage());
      }
      try {
        RfpBidAccess.deleteBidsOfLanes(new Set<Id>{ f.lane.Id });
        System.assert(false, 'expected LaneSearchException');
      } catch (LaneSearchException e) {
        System.assertEquals('You cannot delete bids.', e.getMessage());
      }
      // Lane_Benchmark_User has no RFP_Lane__c permission at all: no lane is visible, so the
      // rule hides every bid here even though the permission set can read Benchmark_Rate__c.
      System.assertEquals(
        0,
        RfpBidAccess.bidsOfLanes(new Set<Id>{ f.lane.Id }).size()
      );
      try {
        RfpBidAccess.assertLaneVisible(f.lane.Id);
        System.assert(false, 'expected LaneSearchException');
      } catch (LaneSearchException e) {
        System.assertEquals(RfpBidAccess.LANE_UNAVAILABLE, e.getMessage());
      }
    }
  }
}
```

Create `force-app/main/default/classes/RfpBidAccessTest.cls-meta.xml`:

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<ApexClass xmlns="http://soap.sforce.com/2006/04/metadata">
    <apiVersion>64.0</apiVersion>
    <status>Active</status>
</ApexClass>
```

- [ ] **Step 2: Deploy the test alone to see it fail to compile**

Run: `sf project deploy start -o sandbox --source-dir force-app/main/default/classes/RfpBidAccessTest.cls -l NoTestRun -w 10 --json | python3 -c "import json,sys; s=sys.stdin.read(); r=json.loads(s[s.index('{'):]); print(r['status'], [d.get('problem') for d in r['result'].get('details',{}).get('componentFailures',[])][:2])"`

Expected: `Failed` with a problem naming `RfpBidAccess` ("Variable does not exist" or "Invalid type").

- [ ] **Step 3: Write the helper**

Create `force-app/main/default/classes/RfpBidAccess.cls`:

```apex
/**
 * The one place the RFP workbench crosses from user mode into system mode for bids. Since
 * phase 6 Benchmark_Rate__c is Private and an RFP follows its customer account, so a bid
 * recorded by a colleague on a lane you can read must still be yours to see and change. Rule:
 * a user who can read a lane can read, create, edit and delete every bid on that lane. The
 * lane check is a user-mode query (sharing decides); the bid reads and writes then run in
 * system mode, restricted to those lanes, with object permissions checked here and field-level
 * security applied through Security.stripInaccessible. Lane Benchmark (BidSearchService) does
 * not use this class: it reads every bid in system mode on purpose and shows no customer.
 */
public with sharing class RfpBidAccess {
  public static final String BID_FIELDS =
    'Id, Name, RFP_Lane__c, RFP_Project__c, Carrier__c, Carrier_Name__c, Carrier_Display__c, ' +
    'Contact_Name__c, Contact_Email__c, Contact_Phone__c, Rate__c, CurrencyIsoCode, ' +
    'Fuel_Surcharge__c, FSC_Included__c, Transit_Days__c, Valid_From__c, Expires_On__c, ' +
    'Status__c, Notes__c, City_Lane__c, State_Lane__c, Zip3_Lane__c';
  public static final String LANE_UNAVAILABLE = 'This lane is not available.';

  /** The subset of laneIds the running user can read; empty when they cannot read lanes at all. */
  public static Set<Id> visibleLanes(Set<Id> laneIds) {
    Set<Id> visible = new Set<Id>();
    Boolean nothingToAsk =
      laneIds == null ||
      laneIds.isEmpty() ||
      !Schema.SObjectType.RFP_Lane__c.isAccessible();
    if (nothingToAsk) {
      return visible;
    }
    for (RFP_Lane__c lane : [
      SELECT Id
      FROM RFP_Lane__c
      WHERE Id IN :laneIds
      WITH USER_MODE
    ]) {
      visible.add(lane.Id);
    }
    return visible;
  }

  public static void assertLaneVisible(Id laneId) {
    Boolean hidden =
      laneId == null || !visibleLanes(new Set<Id>{ laneId }).contains(laneId);
    if (hidden) {
      throw new LaneSearchException(LANE_UNAVAILABLE);
    }
  }

  /** Every bid on the visible lanes among laneIds, cheapest first, readable fields only. */
  public static List<Benchmark_Rate__c> bidsOfLanes(Set<Id> laneIds) {
    requireRead();
    Set<Id> lanes = visibleLanes(laneIds);
    if (lanes.isEmpty()) {
      return new List<Benchmark_Rate__c>();
    }
    return readable(
      systemQuery(
        'RFP_Lane__c IN :lanes ORDER BY Rate__c, Id',
        new Map<String, Object>{ 'lanes' => lanes }
      )
    );
  }

  /** The bids among bidIds whose lane the user can read, in the order of bidIds. */
  public static List<Benchmark_Rate__c> bidsByIds(List<Id> bidIds) {
    requireRead();
    List<Benchmark_Rate__c> kept = new List<Benchmark_Rate__c>();
    if (bidIds == null || bidIds.isEmpty()) {
      return kept;
    }
    Map<Id, Benchmark_Rate__c> byId = new Map<Id, Benchmark_Rate__c>(
      systemQuery(
        'Id IN :bidIds',
        new Map<String, Object>{ 'bidIds' => bidIds }
      )
    );
    Set<Id> laneIds = new Set<Id>();
    for (Benchmark_Rate__c bid : byId.values()) {
      if (bid.RFP_Lane__c != null) {
        laneIds.add(bid.RFP_Lane__c);
      }
    }
    Set<Id> lanes = visibleLanes(laneIds);
    for (Id bidId : bidIds) {
      Benchmark_Rate__c bid = byId.get(bidId);
      if (bid != null && lanes.contains(bid.RFP_Lane__c)) {
        kept.add(bid);
      }
    }
    return readable(kept);
  }

  /** Bid counts per project, for the projects among projectIds the user can read. */
  public static Map<Id, Integer> bidCountsByProject(Set<Id> projectIds) {
    requireRead();
    Map<Id, Integer> counts = new Map<Id, Integer>();
    if (projectIds == null || projectIds.isEmpty()) {
      return counts;
    }
    Set<Id> projects = new Map<Id, RFP_Project__c>(
        [
          SELECT Id
          FROM RFP_Project__c
          WHERE Id IN :projectIds
          WITH USER_MODE
        ]
      )
      .keySet();
    if (projects.isEmpty()) {
      return counts;
    }
    for (AggregateResult ar : countQuery(projects)) {
      counts.put((Id) ar.get('pid'), (Integer) ar.get('n'));
    }
    return counts;
  }

  /** Inserts bids on visible lanes only (a bid without a lane is refused) and returns them reloaded in input order. */
  public static List<Benchmark_Rate__c> insertBids(
    List<Benchmark_Rate__c> bids
  ) {
    requireCreate();
    Set<Id> laneIds = new Set<Id>();
    for (Benchmark_Rate__c bid : bids) {
      if (bid.RFP_Lane__c == null) {
        throw new LaneSearchException('A bid needs a lane.');
      }
      laneIds.add(bid.RFP_Lane__c);
    }
    if (!visibleLanes(laneIds).containsAll(laneIds)) {
      throw new LaneSearchException(LANE_UNAVAILABLE);
    }
    List<Benchmark_Rate__c> clean = Security.stripInaccessible(
        AccessType.CREATABLE,
        bids
      )
      .getRecords();
    systemInsert(clean);
    List<Id> ids = new List<Id>();
    for (Benchmark_Rate__c bid : clean) {
      ids.add(bid.Id);
    }
    return bidsByIds(ids);
  }

  /** Updates one bid whose stored lane the user can read; a bid never moves to another lane here. */
  public static Benchmark_Rate__c updateBid(Benchmark_Rate__c bid) {
    requireEdit();
    List<Benchmark_Rate__c> stored = bid.Id == null
      ? new List<Benchmark_Rate__c>()
      : systemQuery(
          'Id = :bidId',
          new Map<String, Object>{ 'bidId' => bid.Id }
        );
    if (stored.isEmpty() || stored[0].RFP_Lane__c == null) {
      throw new LaneSearchException(LANE_UNAVAILABLE);
    }
    assertLaneVisible(stored[0].RFP_Lane__c);
    Boolean moves =
      bid.RFP_Lane__c != null &&
      bid.RFP_Lane__c != stored[0].RFP_Lane__c;
    if (moves) {
      throw new LaneSearchException('A bid cannot move to another lane.');
    }
    Benchmark_Rate__c clean = (Benchmark_Rate__c) Security.stripInaccessible(
        AccessType.UPDATABLE,
        new List<Benchmark_Rate__c>{ bid }
      )
      .getRecords()[0];
    systemUpdate(clean);
    return bidsByIds(new List<Id>{ bid.Id })[0];
  }

  /** Deletes every bid on the visible lanes among laneIds; partial success, results returned. */
  public static List<Database.DeleteResult> deleteBidsOfLanes(Set<Id> laneIds) {
    requireDelete();
    List<Benchmark_Rate__c> bids = bidsOfLanes(laneIds);
    if (bids.isEmpty()) {
      return new List<Database.DeleteResult>();
    }
    return systemDelete(bids);
  }

  private static void requireRead() {
    if (!Schema.SObjectType.Benchmark_Rate__c.isAccessible()) {
      throw new LaneSearchException('You cannot read bids.');
    }
  }
  private static void requireCreate() {
    if (!Schema.SObjectType.Benchmark_Rate__c.isCreateable()) {
      throw new LaneSearchException('You cannot create bids.');
    }
  }
  private static void requireEdit() {
    if (!Schema.SObjectType.Benchmark_Rate__c.isUpdateable()) {
      throw new LaneSearchException('You cannot edit bids.');
    }
  }
  private static void requireDelete() {
    if (!Schema.SObjectType.Benchmark_Rate__c.isDeletable()) {
      throw new LaneSearchException('You cannot delete bids.');
    }
  }

  private static List<Benchmark_Rate__c> readable(
    List<Benchmark_Rate__c> bids
  ) {
    return Security.stripInaccessible(AccessType.READABLE, bids).getRecords();
  }

  // System-mode SOQL and DML on purpose, and only here: every caller has just proved the lane
  // (or project) readable in user mode, object permissions are checked by the require* methods
  // above, and the rows pass through Security.stripInaccessible before they leave this class.
  @SuppressWarnings('PMD.ApexCRUDViolation')
  private static List<Benchmark_Rate__c> systemQuery(
    String whereClause,
    Map<String, Object> binds
  ) {
    return Database.queryWithBinds(
      'SELECT ' + BID_FIELDS + ' FROM Benchmark_Rate__c WHERE ' + whereClause,
      binds,
      AccessLevel.SYSTEM_MODE
    );
  }
  @SuppressWarnings('PMD.ApexCRUDViolation')
  private static List<AggregateResult> countQuery(Set<Id> projects) {
    return Database.queryWithBinds(
      'SELECT RFP_Project__c pid, COUNT(Id) n FROM Benchmark_Rate__c ' +
      'WHERE RFP_Project__c IN :projects GROUP BY RFP_Project__c',
      new Map<String, Object>{ 'projects' => projects },
      AccessLevel.SYSTEM_MODE
    );
  }
  @SuppressWarnings('PMD.ApexCRUDViolation')
  private static void systemInsert(List<Benchmark_Rate__c> bids) {
    Database.insert(bids, AccessLevel.SYSTEM_MODE);
  }
  @SuppressWarnings('PMD.ApexCRUDViolation')
  private static void systemUpdate(Benchmark_Rate__c bid) {
    Database.update(bid, AccessLevel.SYSTEM_MODE);
  }
  @SuppressWarnings('PMD.ApexCRUDViolation')
  private static List<Database.DeleteResult> systemDelete(
    List<Benchmark_Rate__c> bids
  ) {
    return Database.delete(bids, false, AccessLevel.SYSTEM_MODE);
  }
}
```

Create `force-app/main/default/classes/RfpBidAccess.cls-meta.xml` with the same content as the test's meta file (apiVersion 64.0, status Active).

Add to `manifest/package.xml`, inside the `<types>` block whose `<name>` is `ApexClass`, keeping alphabetical order with the other `Rfp*` members:

```xml
        <members>RfpBidAccess</members>
        <members>RfpBidAccessTest</members>
```

- [ ] **Step 4: Deploy both classes and run the test**

Run: `sf project deploy start -o sandbox --source-dir force-app/main/default/classes/RfpBidAccess.cls --source-dir force-app/main/default/classes/RfpBidAccessTest.cls -l RunSpecifiedTests -t RfpBidAccessTest -w 15 --json | python3 -c "import json,sys; s=sys.stdin.read(); r=json.loads(s[s.index('{'):])['result']; print(r['id'], r['status'], 'tests', r.get('numberTestsCompleted'), '/', r.get('numberTestsTotal'), 'failures', r.get('numberTestErrors'))"`

Expected: `Succeeded tests 10 / 10 failures 0`. If a test fails, the JSON's `result.details.runTestResult.failures` lists the message; fix the helper, not the assertion, unless the assertion contradicts the spec.

- [ ] **Step 5: PMD**

Run: `/private/tmp/pmd_install/pmd-bin-7.15.0/bin/pmd check --dir force-app/main/default/classes/RfpBidAccess.cls --dir force-app/main/default/classes/RfpBidAccessTest.cls --rulesets config/pmd-ruleset.xml --minimum-priority 3 --format text --fail-on-violation; echo "pmd exit $?"`

Expected: no violation lines, `pmd exit 0`. The `ApexCRUDViolation` suppressions on the five `system*` methods are the only ones in the class; if PMD flags a `require*`/`readable` method, move the flagged statement into a `system*` method rather than adding a suppression elsewhere. If PMD reports the class over the complexity budget of 40, move the four `require*` methods into a private inner class `Gate` (inner-class methods do not count toward the outer class) and call them as `Gate.read()` etc.; do not raise the budget.

- [ ] **Step 6: Commit**

```bash
git add force-app/main/default/classes/RfpBidAccess.cls force-app/main/default/classes/RfpBidAccess.cls-meta.xml force-app/main/default/classes/RfpBidAccessTest.cls force-app/main/default/classes/RfpBidAccessTest.cls-meta.xml manifest/package.xml
git commit -m "Add RfpBidAccess: a lane you can see grants its bids"
```

---

### Task 2: Route the workbench's bid reads and writes through the rule

**Files:**

- Modify: `force-app/main/default/classes/BenchmarkRateService.cls` (class comment, `save`, `saveAll`; delete `reload`/`reloadAll` at the end of the file)
- Modify: `force-app/main/default/classes/RfpBidController.cls:31-58` (`getBids`)
- Modify: `force-app/main/default/classes/RfpBulkService.cls:266-280` (`deleteLanes`)
- Modify: `force-app/main/default/classes/RfpController.cls:74-84` (`addBidCounts`)

**Interfaces:**

- Consumes: `RfpBidAccess.insertBids`, `updateBid`, `bidsOfLanes`, `assertLaneVisible`, `deleteBidsOfLanes`, `bidCountsByProject` (Task 1).
- Produces: unchanged public signatures — `BenchmarkRateService.save(Benchmark_Rate__c)`, `saveAll(List<Benchmark_Rate__c>)`, `RfpBidController.getBids(Id)`, `RfpBulkService.deleteLanes(List<Id>)`, `RfpController.projectsForAccount(Id)`. Behaviour in admin context is identical, so every existing test keeps passing.

- [ ] **Step 1: Write the failing test for the new user-facing error**

Append to `force-app/main/default/classes/RfpBidControllerTest.cls`, inside the class:

```apex
  @IsTest
  static void getBidsOnAnUnknownLaneIsAUserError() {
    Id fake = RFP_Lane__c.SObjectType.getDescribe().getKeyPrefix() +
      '000000000001AAA';
    try {
      RfpBidController.getBids(fake);
      System.assert(false, 'expected AuraHandledException');
    } catch (AuraHandledException e) {
      System.assertEquals(RfpBidAccess.LANE_UNAVAILABLE, e.getMessage());
    }
  }
```

- [ ] **Step 2: Run it and watch it fail**

Run: `sf project deploy start -o sandbox --source-dir force-app/main/default/classes/RfpBidControllerTest.cls -l RunSpecifiedTests -t RfpBidControllerTest -w 15 --json | python3 -c "import json,sys; s=sys.stdin.read(); r=json.loads(s[s.index('{'):])['result']; print(r['status'], 'failures', r.get('numberTestErrors')); [print(f['methodName'], '->', f['message'][:120]) for f in r.get('details',{}).get('runTestResult',{}).get('failures',[])]"`

Expected: `Failed failures 1`, `getBidsOnAnUnknownLaneIsAUserError -> ... expected AuraHandledException` or the current message `The bids could not be loaded.` (today an unknown lane returns an empty list, so the assertion that an exception is thrown fails).

- [ ] **Step 3: `BenchmarkRateService` — delegate DML and reloads**

Replace the class comment and the two public save methods at the top of `BenchmarkRateService.cls` (everything from the opening `/**` down to the end of `saveAll`) with:

```apex
/**
 * Saves carrier bids (Benchmark_Rate__c). Validates the rate here; the record access rule,
 * field-level stripping and the DML live in RfpBidAccess (a lane you can read grants its bids -
 * Benchmark_Rate__c is Private since phase 6). The lane keys Lane Benchmark searches on (city
 * lane, state lane, zip3 lane, geolocations, project, mode/equipment/hazmat) are stamped by
 * BenchmarkRateTrigger's before-insert/before-update call into applyLanes below, not by save():
 * RFP_Tool_User marks those fields editable=false (they are service-maintained, never
 * user-entered), so the insert/update must not set them - only a system-context trigger can.
 * RfpBidAccess enforces that with Security.stripInaccessible before the DML (a queried record -
 * the record page, a re-save - carries those fields populated; passing it back must not fail or
 * silently attempt to rewrite them). This also means a bid created directly on the record page
 * (bypassing save() entirely) still gets stamped, which a save()-only implementation could never do.
 */
public with sharing class BenchmarkRateService {
  public static Benchmark_Rate__c save(Benchmark_Rate__c bid) {
    if (bid.Rate__c == null) {
      throw new LaneSearchException('A bid needs a rate.');
    }
    if (bid.Id == null) {
      return RfpBidAccess.insertBids(new List<Benchmark_Rate__c>{ bid })[0];
    }
    return RfpBidAccess.updateBid(bid);
  }

  /** save() for a list: one insert, all or none, reloaded in input order. */
  public static List<Benchmark_Rate__c> saveAll(List<Benchmark_Rate__c> bids) {
    for (Benchmark_Rate__c bid : bids) {
      if (bid.Rate__c == null) {
        throw new LaneSearchException('A bid needs a rate.');
      }
    }
    return RfpBidAccess.insertBids(bids);
  }
```

Then delete the two private methods `reload(Id bidId)` and `reloadAll(List<Id> bidIds)` at the end of the file (from `private static Benchmark_Rate__c reload(` to the closing `}` of `reloadAll`, leaving the class's final `}`). Nothing else in the class calls them; confirm with `grep -n "reload" force-app/main/default/classes/BenchmarkRateService.cls` printing nothing.

- [ ] **Step 4: `RfpBidController.getBids`**

Replace the whole `getBids` method with:

```apex
  @AuraEnabled
  public static List<Benchmark_Rate__c> getBids(Id laneId) {
    try {
      RfpBidAccess.assertLaneVisible(laneId);
      return RfpBidAccess.bidsOfLanes(new Set<Id>{ laneId });
    } catch (LaneSearchException e) {
      throw RfpUserError.of(e.getMessage());
    } catch (Exception e) {
      throw RfpUserError.of('The bids could not be loaded.');
    }
  }
```

- [ ] **Step 5: `RfpBulkService.deleteLanes`**

Replace the method with:

```apex
  public static Result deleteLanes(List<Id> laneIds) {
    Context c = load(laneIds);
    // load() read the lanes in user mode, so their bids are the caller's to delete (RfpBidAccess).
    c.collect(RfpBidAccess.deleteBidsOfLanes(new Set<Id>(c.ids)), false);
    c.collect(Database.delete(c.lanes, false, AccessLevel.USER_MODE), true);
    c.finish();
    c.result.lanes = RfpLaneController.lanesByIds(c.ids);
    return c.result;
  }
```

- [ ] **Step 6: `RfpController.addBidCounts`**

Replace the method with:

```apex
  private static void addBidCounts(Map<Id, ProjectSummary> byId) {
    Map<Id, Integer> counts = RfpBidAccess.bidCountsByProject(byId.keySet());
    for (Id projectId : counts.keySet()) {
      byId.get(projectId).bidCount = counts.get(projectId);
    }
  }
```

- [ ] **Step 7: Deploy the four classes with their tests**

Run: `sf project deploy start -o sandbox --source-dir force-app/main/default/classes -l RunSpecifiedTests -t RfpBidAccessTest -t BenchmarkRateServiceTest -t RfpBidControllerTest -t RfpBulkServiceTest -t RfpBulkControllerTest -t RfpControllerTest -t RfpSecurityTest -t RfpHistoryServiceTest -w 20 --json | python3 -c "import json,sys; s=sys.stdin.read(); r=json.loads(s[s.index('{'):])['result']; print(r['id'], r['status'], 'tests', r.get('numberTestsCompleted'), '/', r.get('numberTestsTotal'), 'failures', r.get('numberTestErrors')); [print(f['name'], f['methodName'], '->', f['message'][:160]) for f in r.get('details',{}).get('runTestResult',{}).get('failures',[])]"`

Expected: `Succeeded`, 0 failures (the model in the org is still Public Read/Write at this point, so every lane is visible to every user and the existing tests behave as before).

- [ ] **Step 8: PMD on the whole tree**

Run: `/private/tmp/pmd_install/pmd-bin-7.15.0/bin/pmd check --dir force-app --rulesets config/pmd-ruleset.xml --minimum-priority 3 --format text --fail-on-violation; echo "pmd exit $?"`

Expected: `pmd exit 0`.

- [ ] **Step 9: Commit**

```bash
git add force-app/main/default/classes/BenchmarkRateService.cls force-app/main/default/classes/RfpBidController.cls force-app/main/default/classes/RfpBulkService.cls force-app/main/default/classes/RfpController.cls force-app/main/default/classes/RfpBidControllerTest.cls
git commit -m "Read and write bids through the lane rule"
```

---

### Task 3: Flip the model — master-detail to Account, Private bids — and prove it with three users

**Files:**

- Modify: `force-app/main/default/objects/RFP_Project__c/fields/Customer__c.field-meta.xml`
- Modify: `force-app/main/default/objects/RFP_Project__c/RFP_Project__c.object-meta.xml:10`
- Modify: `force-app/main/default/objects/RFP_Lane__c/fields/RFP_Project__c.field-meta.xml:11`
- Modify: `force-app/main/default/objects/Benchmark_Rate__c/Benchmark_Rate__c.object-meta.xml:11`
- Modify: `force-app/main/default/classes/RfpSecurityTest.cls` (helpers at lines 3-35; test at 131-182; test at 184-237; two new tests)

**Interfaces:**

- Consumes: `RfpBidAccess` (Task 1), the wired controllers (Task 2), `RfpProjectController.saveProject(String)`, `RfpController.projectsForAccount(Id)`, `RfpBidController.getBids(Id)` / `saveBid(String)`, `RfpBulkController.deleteLanes(List<Id>)`, `LaneSearchService.search(LaneSearchRequest)`.
- Produces: the sharing model of §3 of the spec, live in PostProduc; `RfpSecurityTest.restrictedUser(List<String>)` and `shareAccount(Account, User, String)` helpers.

Why the test edits travel with the metadata: `RfpSecurityTest` currently hands a project to a user through `own.OwnerId = pricing.Id` (line 200). A detail object has no `OwnerId`, so that line stops compiling the moment the field is a master-detail, and a deploy carries every class. The rewrite below compiles under both models; its new assertions hold only under the new one, which is what the deploy in Step 5 establishes.

- [ ] **Step 1: Metadata**

Replace `force-app/main/default/objects/RFP_Project__c/fields/Customer__c.field-meta.xml` with:

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Customer__c</fullName>
    <label>Customer</label>
    <type>MasterDetail</type>
    <referenceTo>Account</referenceTo>
    <relationshipName>RFP_Projects</relationshipName>
    <relationshipLabel>RFP Projects</relationshipLabel>
    <relationshipOrder>0</relationshipOrder>
    <reparentableMasterDetail>false</reparentableMasterDetail>
    <writeRequiresMasterRead>true</writeRequiresMasterRead>
    <lookupFilter>
        <active>true</active>
        <errorMessage>Choose a customer account.</errorMessage>
        <filterItems>
            <field>Account.RecordType.DeveloperName</field>
            <operation>equals</operation>
            <value>Customer, New_Customer</value>
        </filterItems>
        <isOptional>false</isOptional>
    </lookupFilter>
</CustomField>
```

In `RFP_Project__c.object-meta.xml` change `<sharingModel>ReadWrite</sharingModel>` to `<sharingModel>ControlledByParent</sharingModel>`.

In `RFP_Lane__c/fields/RFP_Project__c.field-meta.xml` change `<writeRequiresMasterRead>false</writeRequiresMasterRead>` to `<writeRequiresMasterRead>true</writeRequiresMasterRead>`.

In `Benchmark_Rate__c.object-meta.xml` change `<sharingModel>ReadWrite</sharingModel>` to `<sharingModel>Private</sharingModel>`.

- [ ] **Step 2: `RfpSecurityTest` helpers**

Replace the `restrictedUser(String permSetName)` method (lines 3-35) with these two methods:

```apex
  /** Creates a user holding only the named permission set. Returns null when the org has no usable profile. */
  private static User restrictedUser(String permSetName) {
    return restrictedUser(new List<String>{ permSetName });
  }

  /** Creates a user holding only the named permission sets. Returns null when the org has no usable profile. */
  private static User restrictedUser(List<String> permSetNames) {
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
      Username = 'rfp.' + System.currentTimeMillis() + '.' + permSetNames.size() + '@example.invalid',
      Email = 'rfp@example.invalid',
      LastName = 'Rfp',
      Alias = 'rfp',
      TimeZoneSidKey = 'America/Toronto',
      LocaleSidKey = 'en_CA',
      EmailEncodingKey = 'UTF-8',
      LanguageLocaleKey = 'en_US'
    );
    List<PermissionSet> sets = [
      SELECT Id
      FROM PermissionSet
      WHERE Name IN :permSetNames
    ];
    System.runAs(new User(Id = UserInfo.getUserId())) {
      insert u;
      List<PermissionSetAssignment> psa = new List<PermissionSetAssignment>();
      for (PermissionSet ps : sets) {
        psa.add(
          new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id)
        );
      }
      insert psa;
    }
    return u;
  }

  /**
   * Account is Private in this org and an RFP follows its account (phase 6): a manual share
   * on the customer is what lets a restricted user see, and with Read alone also work, the RFP.
   */
  private static void shareAccount(Account customer, User u, String level) {
    insert new AccountShare(
      AccountId = customer.Id,
      UserOrGroupId = u.Id,
      AccountAccessLevel = level,
      OpportunityAccessLevel = 'None',
      CaseAccessLevel = 'None',
      RowCause = 'Manual'
    );
  }
```

- [ ] **Step 3: Rework the two tests that assumed Public Read/Write**

In `rfpToolUserOnlyCanSaveABidAndLaneBenchmarkUserSeesIt` (line 131): rename it `readOnTheAccountIsEnoughToRecordABidAndLaneBenchmarkSeesIt`, and insert one line right after the `if (pricing == null || viewer == null) { ... return; }` block, before `Test.startTest();`:

```apex
    shareAccount(f.g.customer, pricing, 'Read');
```

Everything else in that test stays (it now proves that Read on the account lets a pricer record and edit a bid on a project the admin created, and that Lane Benchmark shows it to a user who cannot see the account).

In `rfpToolUserCanDeleteTheirLanesAndBids` (line 184): replace the comment and the four lines

```apex
    // Account is Private in this org, so the restricted user cannot reference the admin-owned
    // customer from RFP_Project__c.Customer__c: the admin creates the project and hands it over
    // instead. Lanes are Controlled by Parent, so the restricted user now owns the lane too.
    RFP_Project__c own = RfpTestDataFactory.createProject(f.g.customer);
    RFP_Lane__c lane = RfpTestDataFactory.createLane(own, f.mtl, f.tor);
    own.OwnerId = pricing.Id;
    update own;
```

with

```apex
    // An RFP follows its account (phase 6): Read on the customer is what lets the restricted
    // user work the admin's project - delete its lanes and, through RfpBidAccess, its bids.
    RFP_Project__c own = RfpTestDataFactory.createProject(f.g.customer);
    RFP_Lane__c lane = RfpTestDataFactory.createLane(own, f.mtl, f.tor);
    shareAccount(f.g.customer, pricing, 'Read');
```

- [ ] **Step 4: Add the two new tests**

Append inside `RfpSecurityTest`, after `rfpToolUserCanDeleteTheirLanesAndBids`:

```apex
  /** Spec §5: without access to the account the RFP is absent everywhere, yet its bid still counts in Lane Benchmark. */
  @IsTest
  static void withoutAccountAccessTheRfpIsAbsentButLaneBenchmarkStillCountsItsBid() {
    Fx f = fx();
    User stranger = restrictedUser(
      new List<String>{ 'RFP_Tool_User', 'Lane_Benchmark_User' }
    );
    if (stranger == null) {
      System.assert(
        true,
        'no usable profile in this org; runAs coverage skipped (ledgered)'
      );
      return;
    }
    Benchmark_Rate__c adminBid = BenchmarkRateService.save(
      RfpTestDataFactory.buildBid(f.lane, 900)
    );
    Id laneId = f.lane.Id;
    Id accountId = f.g.customer.Id;
    Test.startTest();
    System.runAs(stranger) {
      System.assertEquals(
        0,
        [SELECT COUNT() FROM RFP_Project__c WITH USER_MODE],
        'no project on an account the user cannot read'
      );
      System.assertEquals(
        0,
        [SELECT COUNT() FROM RFP_Lane__c WHERE Id = :laneId WITH USER_MODE]
      );
      System.assertEquals(
        0,
        RfpController.projectsForAccount(accountId).size()
      );
      try {
        RfpBidController.getBids(laneId);
        System.assert(false, 'expected AuraHandledException');
      } catch (AuraHandledException e) {
        System.assertEquals(RfpBidAccess.LANE_UNAVAILABLE, e.getMessage());
      }
      try {
        RfpBidController.saveBid(
          JSON.serialize(RfpTestDataFactory.buildBid(f.lane, 800))
        );
        System.assert(false, 'expected AuraHandledException');
      } catch (AuraHandledException e) {
        System.assertEquals(RfpBidAccess.LANE_UNAVAILABLE, e.getMessage());
      }
      LaneSearchResult found = LaneSearchService.search(
        req('montreal|qc|ca', 'toronto|on|ca', LaneSearchRequest.Precision.CITY)
      );
      System.assertEquals(1, found.rows.size(), 'Lane Benchmark still sees the bid');
    }
    Test.stopTest();
    System.assertEquals(
      1,
      [SELECT COUNT() FROM Benchmark_Rate__c WHERE Id = :adminBid.Id],
      'nothing was written by the refused calls'
    );
  }

  /** Spec §5: Read on the account lets a user create a project and lanes, record a bid, and read a colleague's bid. */
  @IsTest
  static void readOnTheAccountLetsAUserCreateAProjectItsLanesAndBids() {
    Fx f = fx();
    User reader = restrictedUser('RFP_Tool_User');
    if (reader == null) {
      System.assert(
        true,
        'no usable profile in this org; runAs coverage skipped (ledgered)'
      );
      return;
    }
    shareAccount(f.g.customer, reader, 'Read');
    Benchmark_Rate__c adminBid = BenchmarkRateService.save(
      RfpTestDataFactory.buildBid(f.lane, 900)
    );
    f.lane.Selected_Bid__c = adminBid.Id;
    f.lane.Cost_Source__c = 'Bid';
    f.lane.Cost__c = 900;
    update f.lane;
    Id accountId = f.g.customer.Id;
    Test.startTest();
    Id newLaneId;
    System.runAs(reader) {
      RFP_Project__c created = RfpProjectController.saveProject(
        JSON.serialize(
          new RFP_Project__c(
            Name = 'Reader RFP',
            Customer__c = accountId,
            Status__c = 'Draft',
            Default_Margin__c = 15,
            CurrencyIsoCode = 'CAD'
          )
        )
      );
      System.assertNotEquals(null, created.Id, 'Read on the account creates a detail');
      RFP_Lane__c lane = RfpTestDataFactory.createLane(created, f.laval, f.tor);
      newLaneId = lane.Id;
      Benchmark_Rate__c mine = BenchmarkRateService.save(
        RfpTestDataFactory.buildBid(lane, 700)
      );
      System.assertEquals(700, mine.Rate__c);
      List<Benchmark_Rate__c> colleagues = RfpBidController.getBids(f.lane.Id);
      System.assertEquals(1, colleagues.size(), 'the admin\'s bid on a readable lane');
      System.assertEquals(adminBid.Id, colleagues[0].Id);
      System.assert(
        RfpController.projectsForAccount(accountId).size() >= 2,
        'both projects on the shared account are listed'
      );
      // Selected_Bid__r is read through the lane in user mode (RfpLaneController.LANE_FIELDS).
      // A bid recorded by someone else must still show its carrier there; if this assertion
      // fails, the controller rules on the fix (fill Selected_Bid__r from RfpBidAccess.bidsByIds
      // in lanesByIds) - do not delete the assertion.
      RFP_Lane__c seen = RfpLaneController.lanesByIds(
        new List<Id>{ f.lane.Id }
      )[0];
      System.assert(
        String.isNotBlank(seen.Selected_Bid__r?.Carrier_Display__c),
        'the selected bid of a readable lane shows its carrier'
      );
    }
    Test.stopTest();
    System.assertEquals(
      1,
      [SELECT COUNT() FROM Benchmark_Rate__c WHERE RFP_Lane__c = :newLaneId]
    );
  }
```

- [ ] **Step 5: Deploy the metadata and the test together, no test run**

Run: `sf project deploy start -o sandbox --manifest manifest/package.xml -l NoTestRun -w 30 --json | python3 -c "import json,sys; s=sys.stdin.read(); r=json.loads(s[s.index('{'):])['result']; print(r['id'], r['status'], 'components', r.get('numberComponentsDeployed'), 'errors', r.get('numberComponentErrors')); [print(d.get('fullName'), '->', d.get('problem')) for d in r.get('details',{}).get('componentFailures',[])]"`

Expected: `Succeeded`, 0 errors. If the field conversion is refused with a message about the field type change, the fallback is the Setup UI, done by the controller, not the implementer: Setup → Object Manager → RFP Project → Fields → Customer → Change Field Type → Master-Detail, Sharing Setting "Read Only" (this is `writeRequiresMasterRead`), keep the lookup filter; then re-run this deploy so the repo and the org agree. Record which path ran in the report.

- [ ] **Step 6: Verify the org**

Run:

```bash
sf data query -o sandbox -q "SELECT QualifiedApiName, InternalSharingModel FROM EntityDefinition WHERE QualifiedApiName IN ('RFP_Project__c','RFP_Lane__c','Benchmark_Rate__c')" -t
sf data query -o sandbox -q "SELECT QualifiedApiName, DataType, IsNillable FROM FieldDefinition WHERE EntityDefinition.QualifiedApiName = 'RFP_Project__c' AND QualifiedApiName = 'Customer__c'" -t
sf data query -o sandbox -q "SELECT COUNT() FROM RFP_Project__c" -t
```

Expected: `RFP_Project__c ControlledByParent`, `RFP_Lane__c ControlledByParent`, `Benchmark_Rate__c Private`; `Customer__c Master-Detail(Account) false`; `4` projects (nothing lost).

- [ ] **Step 7: Run the security tests in the org**

Run: `sf apex run test -o sandbox -n RfpSecurityTest -n RfpBidAccessTest -n RfpBulkControllerTest -n RfpHistoryServiceTest -n RfpProjectControllerTest -n RfpControllerTest -r human -w 15 2>&1 | grep -E "Outcome|Tests Ran|Pass Rate|Fail|^  [A-Za-z]"`

Expected: `Pass Rate 100%`. A failure in `readOnTheAccountLetsAUserCreateAProjectItsLanesAndBids` at `createLane` means the lane's `writeRequiresMasterRead` did not deploy (check Step 6's first query and the field file); a failure at `saveProject` means the project's flag did not (same check on `Customer__c`).

- [ ] **Step 8: Commit**

```bash
git add force-app/main/default/objects/RFP_Project__c force-app/main/default/objects/RFP_Lane__c/fields/RFP_Project__c.field-meta.xml force-app/main/default/objects/Benchmark_Rate__c/Benchmark_Rate__c.object-meta.xml force-app/main/default/classes/RfpSecurityTest.cls
git commit -m "Let an RFP follow its customer account and make bids private"
```

---

### Task 4: Guide, README, roadmap, Outcome, final deploy

**Files:**

- Modify: `docs/help/en/faq.md`, `docs/help/fr/faq.md` (new entry before "I cannot see the tab…")
- Modify: `docs/help/en/rfp-projects.md`, `docs/help/fr/rfp-projects.md` (one sentence after "Create a project")
- Modify: `force-app/main/default/staticresources/helpCenter/**` (rebuilt by `npm run help:build`)
- Modify: `README.md` (test list at lines 26, 103, 110; new section after "## RFP Tool (phase 3b)")
- Modify: `docs/superpowers/specs/2026-09-07-pricing-department-roadmap.md` (row 6 after row 5)
- Modify: `docs/superpowers/specs/2026-09-13-phase-6-rfp-access-design.md` (append "## Outcome — phase 6")

**Interfaces:** none new; documents Tasks 1–3.

- [ ] **Step 1: Guide entries**

In `docs/help/en/faq.md`, insert before `## I cannot see the tab or a button says I lack permission`:

```markdown
## Who can see an RFP?

An RFP is visible to the people who can see its customer account, from the account page and in the RFP Tool list; Read access on the account is enough to work on it. If a project you expect is missing, ask the account owner or your admin for access to that account. Lane Benchmark shows every bid's carrier, rate and expiry to everyone, without the customer or the RFP.
```

In `docs/help/fr/faq.md`, insert before `## Je ne vois pas l'onglet, ou un bouton dit que je manque d'autorisation`:

```markdown
## Qui peut voir un RFP?

Un RFP est visible par les personnes qui peuvent voir son compte client, depuis la page du compte et dans la liste de l'onglet RFP Tool; un accès en lecture au compte suffit pour y travailler. Si un projet que vous attendez manque, demandez l'accès au compte à son propriétaire ou à votre administrateur. Lane Benchmark montre à tout le monde le transporteur, le tarif et l'échéance de chaque soumission, sans le client ni le RFP.
```

In `docs/help/en/rfp-projects.md`, after the "Create a project" paragraph (the one ending `the project opens on the upload step.`), add a new paragraph:

```markdown
The customer is required: the project belongs to that account, and whoever can see the account can open the project.
```

In `docs/help/fr/rfp-projects.md`, after the matching paragraph (ending `le projet s'ouvre à l'étape de téléversement.`):

```markdown
Le client est obligatoire : le projet appartient à ce compte, et quiconque peut voir le compte peut ouvrir le projet.
```

Run: `npm run help:build && npm run help:check`
Expected: `built 15 sections into force-app/main/default/staticresources/helpCenter` then `helpCenter is up to date`. `git status --short force-app/main/default/staticresources/helpCenter` lists `en/faq.html`, `fr/faq.html`, `en/rfp-projects.html`, `fr/rfp-projects.html` and nothing else.

- [ ] **Step 2: README**

Add `RfpBidAccessTest` after `RfpSecurityTest` in the three lists (the inventory table row at line 26 as `` `RfpBidAccessTest` ``, and the two commands at lines 103 and 110 as `-n RfpBidAccessTest` / `RfpBidAccessTest`).

Insert this section immediately before `## Help center (phase 5)`:

```markdown
## Access model (phase 6)

**Who sees an RFP.** `RFP_Project__c.Customer__c` is a master-detail to Account with
"write requires master Read" on, and `RFP_Lane__c` follows the project the same way.
So Salesforce account sharing decides: a user who can read a customer account sees its
RFPs (RFP Tool list, the account page component, deep links) and can create, price and
delete their lanes and bids; a user who cannot read the account does not see the RFP at
all. There is no owner on a project. Admins with View All Data see everything. Deleting
an account deletes its RFPs and lanes; their bids survive with the lookups cleared.

**Bids.** `Benchmark_Rate__c` is Private. The workbench never queries it in user mode:
`RfpBidAccess` is the one class that reads and writes bids, after proving in user mode
that the running user can read the lane, in system mode restricted to those lanes and
through `Security.stripInaccessible`. Rule: a lane you can see grants its bids, whoever
recorded them. Lane Benchmark (`LaneSearchService`, `BidSearchService`) keeps reading
every bid in system mode and shows carrier, rate and expiry only, never the customer.

**Admin task (not code).** Pricers need at least Read on the customer accounts they
price for: through the role hierarchy or an Account sharing rule to the pricing group.
Account is Private in this org, so without one of those a pricer sees no RFP. In
PostProduc the admin user holds `RFP_Tool_User` and sees everything; the restriction is
proven by `RfpSecurityTest` (three users) and `RfpBidAccessTest`.

**Production.** None of these objects exist there yet; the go-live deploy creates them in
their final shape. A sandbox that already holds RFP data converts in place as long as
every project has a customer (the New project form requires one).
```

- [ ] **Step 3: Roadmap row**

In `docs/superpowers/specs/2026-09-07-pricing-department-roadmap.md`, after row 5 add:

```markdown
| 6 | RFP access model | An RFP follows its customer account (master-detail, Read is enough to work it); bids Private with the lane rule in `RfpBidAccess`; Lane Benchmark unchanged | Done 2026-09-13 (PostProduc; production untouched) |
```

- [ ] **Step 4: Full local gate**

Run: `npm run lint && npm run prettier:verify && npm run help:check && npm run test:unit 2>&1 | grep -E "^(Tests|Test Suites):" && /private/tmp/pmd_install/pmd-bin-7.15.0/bin/pmd check --dir force-app --rulesets config/pmd-ruleset.xml --minimum-priority 3 --format text --fail-on-violation; echo "pmd exit $?"`

Expected: ESLint silent, Prettier "All matched files use Prettier code style!" (a warning only about an untracked `.ai-handover` file is pre-existing), `helpCenter is up to date`, Jest `36 passed` suites / `309 passed` tests, `pmd exit 0`.

- [ ] **Step 5: Final deploy pair**

Run (first):
`sf project deploy start -o sandbox --manifest manifest/package.xml -l NoTestRun -w 30 --json | python3 -c "import json,sys; s=sys.stdin.read(); r=json.loads(s[s.index('{'):])['result']; print(r['id'], r['status'], 'components', r.get('numberComponentsDeployed'), 'errors', r.get('numberComponentErrors'))"`

Run (second):
`sf project deploy start -x manifest/package.xml --post-destructive-changes manifest/destructiveChangesPost.xml -o sandbox -w 30 -l RunSpecifiedTests -t LaneSearchExclusionsTest PlaceNormalizerTest PricingTestDataFactoryTest PlaceBuilderBatchTest LaneSearchServiceTest MapboxGeocoderTest LaneBenchmarkControllerTest LaneBenchmarkPlaceServiceTest RfpTestDataFactoryTest BenchmarkRateServiceTest BidSearchQueryBuilderTest BidSearchServiceTest RfpControllerTest RfpSecurityTest RfpBidAccessTest RfpImportServiceTest RfpLaneControllerTest RfpHistoryServiceTest RfpProjectControllerTest RfpBidControllerTest RfpPricingMathTest RfpBulkServiceTest RfpBulkControllerTest --json | python3 -c "import json,sys; s=sys.stdin.read(); r=json.loads(s[s.index('{'):])['result']; print(r['id'], r['status'], 'tests', r.get('numberTestsCompleted'), '/', r.get('numberTestsTotal'), 'failures', r.get('numberTestErrors')); [print(f['name'], f['methodName'], '->', f['message'][:160]) for f in r.get('details',{}).get('runTestResult',{}).get('failures',[])]"`

Expected: both `Succeeded`; the second with 0 failures and a test total of 124 + 10 (`RfpBidAccessTest`) + 1 (`RfpBidControllerTest`) + 2 (`RfpSecurityTest`) = 137. Record both ids.

- [ ] **Step 6: Spec Outcome**

Append to `docs/superpowers/specs/2026-09-13-phase-6-rfp-access-design.md`:

```markdown
## Outcome — phase 6 (2026-09-13)

Branch `phase-6/rfp-access` from `main` at `5bb8ba2`; spec `7cf4160`.

Commits: (the four commit SHAs of Tasks 1–4 with their messages, in order.)

**PostProduc deploys**, all Succeeded: (Task 1 helper deploy id), (Task 2 wiring deploy id),
(Task 3 model deploy id — note whether the field conversion went through the deploy or the
Setup fallback), final pair (NoTestRun id, RunSpecifiedTests id with the test count).

**Model verified in the org** (Task 3 Step 6): `RFP_Project__c` ControlledByParent,
`RFP_Lane__c` ControlledByParent, `Benchmark_Rate__c` Private, `Customer__c`
Master-Detail(Account); 4 projects kept.

**Tests:** Apex (count) / (count), 10 in `RfpBidAccessTest`, 4 restricted-user scenarios in
`RfpSecurityTest` (Read-shared pricer records and edits a bid and Lane Benchmark sees it;
Read-shared pricer deletes lanes and bids; stranger sees no project, no lane, refused bid calls,
Lane Benchmark still counts the bid; Read-shared user creates a project, a lane, a bid and reads
the admin's bid). Jest unchanged (36 suites / 309 tests). PMD clean.

**Known limits.** `Selected_Bid__r.Carrier_Display__c` is read through the lane in user mode
(`RfpLaneController.LANE_FIELDS`, `rfpWorkbook`); the Task 3 test proves it stays readable for
a bid recorded by another user on a readable lane (state here whether it passed as written or
needed the `lanesByIds` fill). The restriction itself cannot be shown in PostProduc with one
RFP user; a colleague's login would show a project on an unshared account absent from their
list.

Browser check: pending (controller)
```

Fill every parenthesis with the real value before committing; a line still holding a parenthesis placeholder is a review failure.

- [ ] **Step 7: Commit**

```bash
git add docs/help force-app/main/default/staticresources/helpCenter README.md docs/superpowers/specs/2026-09-07-pricing-department-roadmap.md docs/superpowers/specs/2026-09-13-phase-6-rfp-access-design.md
git commit -m "Document the RFP access model (phase 6) and record the outcome"
```

- [ ] **Step 8: Browser check (controller, not the implementer)**

In PostProduc as the admin (fresh tab, component cache cleared): open the RFP Tool, open "Phase 3c browser check", pick a lane with a bid (lane 1, Laredo → Brampton), confirm the bid list still shows the bid; record a new bid from the panel and see it appear; the Help tab FAQ shows "Who can see an RFP?" in English and French; the account page of ALIMENTS MULTIBAR INC. still lists its RFP projects. Record the results in the Outcome, replacing "pending (controller)".
