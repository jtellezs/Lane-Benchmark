# Phase 11a — Lane index Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `Lane_Edge__c` — one row per normalised lane the company has priced, carrying how often it runs, how many distinct carriers moved it, its cost range and when it last moved — rebuilt by a batch that never curates.

**Architecture:** `LaneEdgeBatch` reads loads **ordered by `rtms__City_Lane__c`**, resolves each distinct key to a `Pricing_Place__c` pair through a variant map built once, folds each load into a running `LaneEdgeAgg`, and upserts a lane's row the moment the key changes — so only one lane is ever in memory. `LaneEdgeEnrichBatch` then folds in the sources that are cheap to read by key. Pure logic — key resolution and aggregation — lives in its own classes so it can be tested without an org and so no class approaches PMD's complexity ceiling.

**Tech Stack:** Salesforce Apex (API 64.0), `Database.Batchable` + `Database.Stateful`, PMD 7.15.0, `sfdx-lwc-jest` (not used in this plan — no UI here).

**Spec:** `docs/superpowers/specs/2026-09-17-phase-11-lane-index-design.md` — decisions D1-D8, **and the 2026-09-20 amendment, which re-measured three premises and changes the batch's shape. Read the amendment before Task 1.**

**Scope note:** the spec describes three subsystems — this index, the difficulty band, and composed lanes. This plan is the index only. It produces working, testable software on its own: a queryable index and a batch that rebuilds it. The two features read it and get their own plans, written once the index's real row count is known rather than guessed at now.

## Global Constraints

- **`npm run pmd` must report 0 violations.** PMD's class cyclomatic rule fires at **>= 40** — 39 means no room, not one point. `StdCyclomaticComplexity` separately caps a single **method** at 10. Measure with a throwaway ruleset at `classReportLevel` 1 rather than guessing; the gate prints nothing until a class is already over.
- **The repo has zero `CyclomaticComplexity` and zero `ApexSOQLInjection` suppressions.** Split a cohesive family into its own class instead. `@SuppressWarnings('PMD.ApexCRUDViolation')` **is** an established precedent for system-mode batches — `PlaceBuilderBatch` carries one with a class comment justifying it.
- **Reserved Apex identifiers** cannot name variables or parameters: `where`, `from`, `when`, `select`, `limit`, `group`, `currency`. Four of these cost deploys on phase 10.
- **Decimal assertions** use `==` inside `System.assert(...)`, never `System.assertEquals`, which is type- and scale-sensitive. Integer, String and Boolean use `assertEquals`.
- **Never bare `Database.query`.** Use `Database.queryWithBinds(soql, binds, AccessLevel.SYSTEM_MODE)`; `ApexSOQLInjection` fires on concatenation even when every part is a compile-time constant.
- **Every new class goes in `manifest/package.xml`.** A class on disk and absent from the manifest passes every local gate and then vanishes from a manifest-based deploy. Seven classes were in that state once.
- **The PostProduc sandbox is FULL and shared with other developers. Never refresh it.** Deploy with `--test-level NoTestRun` and run tests separately. Use the async form and poll; `--wait` has exceeded the tool timeout repeatedly here.
- **This plan writes tens of thousands of records into that shared org.** No batch runs against real data without the explicit go-ahead in Task 6, which exists precisely to make that a deliberate decision rather than a side effect.
- `npx prettier --write` on touched files. No AI attribution trailers on commits.

## File Structure

| File                                 | Responsibility                                                                                                                                      |
| ------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------- |
| `objects/Lane_Edge__c/` + `fields/*` | The index row. Ten fields from spec §3, plus `Key__c` as the external id the upsert keys on.                                                        |
| `classes/LaneEdgeKey.cls`            | Pure. Resolves a raw `rtms__City_Lane__c` string to a normalised origin/destination place-key pair, and builds the edge `Key__c`. No SOQL, no DML.  |
| `classes/LaneEdgeAgg.cls`            | Pure. One lane's accumulating aggregate: load counts, distinct carriers, cost percentiles, last-moved date. Folds a row in; emits a `Lane_Edge__c`. |
| `classes/LaneEdgeBatch.cls`          | Reads loads **ordered by their lane key**, folds each into a `LaneEdgeAgg`, and upserts a lane's row as soon as the key changes.                    |
| `classes/LaneEdgeEnrichBatch.cls`    | Folds in the sources that are cheap to read by key: quotes, `Benchmark_Rate__c` bids, freight plan legs.                                            |
| Tests, one per class                 | `LaneEdgeKeyTest`, `LaneEdgeAggTest`, `LaneEdgeBatchTest`, `LaneEdgeWriteBatchTest`, `LaneEdgeEnrichBatchTest`.                                     |

Key resolution and aggregation are separated from the batches on purpose: they hold all the arithmetic and all the edge cases, and they are the parts worth testing without an org. The batches are then thin enough to stay well clear of the complexity ceiling.

---

### Task 1: The `Lane_Edge__c` object

**Files:**

- Create: `force-app/main/default/objects/Lane_Edge__c/Lane_Edge__c.object-meta.xml`
- Create: `force-app/main/default/objects/Lane_Edge__c/fields/*.field-meta.xml` (12 files, table below)
- Modify: `manifest/package.xml`

**Interfaces:**

- Consumes: nothing.
- Produces: the `Lane_Edge__c` SObject and its API names, which every later task writes to or reads from. `Key__c` is the **external id** the upsert keys on — `Origin_Place_Key__c + '>' + Destination_Place_Key__c`.

There is no failing test to write first here: object metadata has no behaviour of its own, and Apex cannot reference a field that does not exist, so Task 2's tests are what prove this landed. Deploy it, then confirm by describe rather than by the deploy's own status field.

- [ ] **Step 1: Write the object**

`Lane_Edge__c.object-meta.xml`:

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<CustomObject xmlns="http://soap.sforce.com/2006/04/metadata">
    <deploymentStatus>Deployed</deploymentStatus>
    <description
  >One row per normalised lane the company has priced: how often it runs, how many distinct carriers moved it, its cost range and when it last moved. Derived and disposable (spec D8) - rebuilt by LaneEdgeBatch from loads, quotes, bids and freight legs, never curated, safe to drop.</description>
    <enableActivities>false</enableActivities>
    <enableHistory>false</enableHistory>
    <enableReports>true</enableReports>
    <enableSearch>false</enableSearch>
    <label>Lane Edge</label>
    <nameField>
        <label>Lane Edge Name</label>
        <type>AutoNumber</type>
        <displayFormat>LE-{00000000}</displayFormat>
    </nameField>
    <pluralLabel>Lane Edges</pluralLabel>
    <sharingModel>ReadWrite</sharingModel>
</CustomObject>
```

`AutoNumber` rather than a text name: nothing reads the Name, and a required text name would have to be populated on every one of tens of thousands of upserted rows for no benefit.

- [ ] **Step 2: Write the fields**

One worked example, then the table. `Key__c` is the one that carries `externalId`, and getting that wrong is what would turn the upsert into an insert-duplicates:

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Key__c</fullName>
    <description
  >originPlaceKey&gt;destinationPlaceKey, both normalised Pricing_Place__c keys. The upsert's external id, so a rebuild updates rather than duplicates.</description>
    <externalId>true</externalId>
    <label>Key</label>
    <length>255</length>
    <required>true</required>
    <type>Text</type>
    <unique>true</unique>
</CustomField>
```

The remaining eleven follow the same shape, differing only in the values below. Write each one out; none has any other setting.

| `fullName`                 | `type`     | Other settings                                                                                              | `description`                                                                                                                  |
| -------------------------- | ---------- | ----------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------ |
| `Origin_Place__c`          | `Lookup`   | `referenceTo` `Pricing_Place__c`, `relationshipName` `Origin_Lane_Edges`, `deleteConstraint` `SetNull`      | The origin, as a place.                                                                                                        |
| `Destination_Place__c`     | `Lookup`   | `referenceTo` `Pricing_Place__c`, `relationshipName` `Destination_Lane_Edges`, `deleteConstraint` `SetNull` | The destination, as a place.                                                                                                   |
| `Origin_Place_Key__c`      | `Text`     | `length` 120                                                                                                | The origin's normalised key, denormalised so a resolve does not need the lookup.                                               |
| `Destination_Place_Key__c` | `Text`     | `length` 120                                                                                                | The destination's normalised key.                                                                                              |
| `City_Lane__c`             | `Text`     | `length` 255                                                                                                | `City, ST:City, ST`, the spelling Revenova writes and `LaneKeyMatcher` matches.                                                |
| `State_Lane__c`            | `Text`     | `length` 80                                                                                                 | `ON:GA`. The province fallback the band uses when the city lane is too thin.                                                   |
| `Loads_Moved_365d__c`      | `Number`   | `precision` 9, `scale` 0                                                                                    | Loads delivered on this lane in the last 365 days.                                                                             |
| `Loads_Moved_3y__c`        | `Number`   | `precision` 9, `scale` 0                                                                                    | Loads delivered in the last three years.                                                                                       |
| `Carriers_Moved_3y__c`     | `Number`   | `precision` 9, `scale` 0                                                                                    | Distinct carriers that moved it - D5's main signal.                                                                            |
| `Median_Cost_CAD__c`       | `Number`   | `precision` 12, `scale` 2                                                                                   | Median total cost. D3: always shown with P25/P75, never alone.                                                                 |
| `P25_Cost_CAD__c`          | `Number`   | `precision` 12, `scale` 2                                                                                   | Lower quartile.                                                                                                                |
| `P75_Cost_CAD__c`          | `Number`   | `precision` 12, `scale` 2                                                                                   | Upper quartile.                                                                                                                |
| `Median_Rate_Per_Mile__c`  | `Number`   | `precision` 8, `scale` 4                                                                                    | Generalises across lanes, which is what the long tail needs.                                                                   |
| `Last_Moved_On__c`         | `Date`     | —                                                                                                           | Recency. A lane last run in 2023 is not a live lane.                                                                           |
| `Sources__c`               | `Text`     | `length` 100                                                                                                | Which of `loads`, `quotes`, `bids`, `legs` produced this row, comma separated.                                                 |
| `Built_On__c`              | `DateTime` | —                                                                                                           | When the batch last wrote this row. Spec §6: every card shows the index's build date, and a stale index is a correctness risk. |

`Sources__c` is a plain text list rather than a multi-select picklist: the set is fixed and small, and a picklist would need its values kept in step with the code that writes them in a second place.

- [ ] **Step 3: Add to the manifest**

Add to `manifest/package.xml`, in the `CustomObject` block, alphabetically:

```xml
<members>Lane_Edge__c</members>
```

- [ ] **Step 4: Deploy and confirm by describe, not by the deploy's status**

```bash
sf project deploy start --source-dir force-app/main/default/objects/Lane_Edge__c --target-org sandbox --test-level NoTestRun --async --json
```

Poll `SELECT Status FROM DeployRequest WHERE Id='<id>'` until it is not `Pending`/`InProgress`. Then confirm the fields actually exist:

```bash
sf sobject describe --sobject Lane_Edge__c --target-org sandbox --json | python3 -c "
import json,sys
fs={f['name']: f['type'] for f in json.load(sys.stdin)['result']['fields']}
want=['Key__c','Origin_Place__c','Destination_Place__c','Origin_Place_Key__c','Destination_Place_Key__c','City_Lane__c','State_Lane__c','Loads_Moved_365d__c','Loads_Moved_3y__c','Carriers_Moved_3y__c','Median_Cost_CAD__c','P25_Cost_CAD__c','P75_Cost_CAD__c','Median_Rate_Per_Mile__c','Last_Moved_On__c','Sources__c','Built_On__c']
missing=[w for w in want if w not in fs]
print('missing:', missing if missing else 'none')
print('Key__c externalId:', [f for f in json.load(open('/dev/null')) ] if False else '')
"
```

Expected: `missing: none`. Confirm separately that `Key__c` came back with `externalId: true` — a `Key__c` that deployed without it will upsert duplicates on the first rebuild and nothing before Task 6 would notice.

- [ ] **Step 5: Commit**

```bash
git add force-app/main/default/objects/Lane_Edge__c manifest/package.xml
git commit -m "Add Lane_Edge__c, one row per lane the company has priced

Keyed on the normalised place pair rather than on the raw spelling, so
Scarborough, ON and SCARBOROUGH ON are one edge. Key__c is the external id the
rebuild upserts against; without it a rebuild inserts duplicates rather than
updating, which nothing in the batch itself would notice.

AutoNumber name because nothing reads it, and a required text name would have to
be populated on every one of tens of thousands of upserted rows for no benefit."
```

---

### Task 2: `LaneEdgeKey` — one lane, whatever it is spelled like

**Files:**

- Create: `force-app/main/default/classes/LaneEdgeKey.cls` + `.cls-meta.xml`
- Create: `force-app/main/default/classes/LaneEdgeKeyTest.cls` + `.cls-meta.xml`
- Modify: `manifest/package.xml`

**Interfaces:**

- Consumes: `PlaceNormalizer.stripAccents(String)`, `PlaceNormalizer.cityLaneVariants(Pricing_Place__c)` — the latter already returns every `City, ST` spelling a place answers to, including accent-stripped forms, so this task must not build a second one.
- Produces, all `public static` on `LaneEdgeKey`:
  - `EDGE_JOIN` → `String` (`'>'`)
  - `sides(String cityLane)` → `List<String>` of exactly two, or `null`
  - `normalize(String side)` → `String`, or `null`
  - `variantIndex(List<Pricing_Place__c> places)` → `Map<String, String>` from normalised variant to `Pricing_Place__c.Key__c`
  - `edgeKey(String originPlaceKey, String destinationPlaceKey)` → `String`, or `null`
  - `resolve(String cityLane, Map<String, String> index)` → `String` edge key, or `null`

This is the piece that turns 49,592 distinct raw `rtms__City_Lane__c` strings into however many real lanes there are. It is pure — no SOQL, no DML — so every case below is testable without inserting a row, and the places in its tests are constructed in memory and never saved.

**Why the whole side is the lookup key, and not the province.** `BC` is British Columbia **and** Baja California. A resolver keyed on the province code would put `Vancouver, BC` and `Tijuana, BC` in the same country. Keying on the entire `city, province` string is what keeps them apart, and Task 2's last test is there to hold that.

Apex cannot do a pure RED: a test that references a missing class fails to **deploy**, which is a compile error rather than a failing test. So write the tests, add a stub that compiles, deploy, and confirm the tests fail **on their assertions**. Only then implement.

- [ ] **Step 1: Write the failing tests**

```apex
@IsTest
private class LaneEdgeKeyTest {
  /** In memory only - cityLaneVariants reads these three fields and nothing else, so no insert. */
  private static Pricing_Place__c place(
    String key,
    String city,
    String province,
    String spellings
  ) {
    return new Pricing_Place__c(
      Key__c = key,
      City__c = city,
      Province__c = province,
      Spellings__c = spellings
    );
  }

  @IsTest
  static void splitsALaneIntoItsTwoSides() {
    List<String> parts = LaneEdgeKey.sides(
      'Scarborough, ON:Lithia Springs, GA'
    );
    System.assertEquals(2, parts.size());
    System.assertEquals('Scarborough, ON', parts[0]);
    System.assertEquals('Lithia Springs, GA', parts[1]);
  }

  @IsTest
  static void anythingThatIsNotTwoSidesIsNotALane() {
    System.assertEquals(
      null,
      LaneEdgeKey.sides('Scarborough, ON'),
      'one side is a place, not a lane'
    );
    System.assertEquals(
      null,
      LaneEdgeKey.sides('a, ON:b, GA:c, TX'),
      'three sides is not a lane this index can hold'
    );
    System.assertEquals(null, LaneEdgeKey.sides(':b, GA'), 'an empty origin');
    System.assertEquals(null, LaneEdgeKey.sides(null));
    System.assertEquals(null, LaneEdgeKey.sides('   '));
  }

  @IsTest
  static void everySpellingOfOneSideNormalisesToOneString() {
    String canonical = LaneEdgeKey.normalize('Montreal, QC');
    System.assertEquals(
      canonical,
      LaneEdgeKey.normalize('Montréal, QC'),
      'an accent is a spelling, not a different place'
    );
    System.assertEquals(
      canonical,
      LaneEdgeKey.normalize('MONTREAL, QC'),
      'case is a spelling too'
    );
    System.assertEquals(
      canonical,
      LaneEdgeKey.normalize('  Montreal ,   QC  '),
      'and so is whatever spacing the source put around the comma'
    );
  }

  @IsTest
  static void aLaneKnowsWhichWayItRuns() {
    String out = LaneEdgeKey.edgeKey('montreal|qc|ca', 'toronto|on|ca');
    String back = LaneEdgeKey.edgeKey('toronto|on|ca', 'montreal|qc|ca');
    System.assert(
      out != back,
      'Montreal to Toronto is not the same lane as Toronto to Montreal: they are ' +
      'priced separately and a single undirected edge would average them together'
    );
    System.assertEquals(null, LaneEdgeKey.edgeKey('montreal|qc|ca', null));
  }

  @IsTest
  static void resolvesBothSidesThroughTheVariantIndex() {
    Map<String, String> index = LaneEdgeKey.variantIndex(
      new List<Pricing_Place__c>{
        place('montreal|qc|ca', 'Montréal', 'QC', 'Montreal\nMONTREAL'),
        place('toronto|on|ca', 'Toronto', 'ON', null)
      }
    );

    System.assertEquals(
      'montreal|qc|ca>toronto|on|ca',
      LaneEdgeKey.resolve('Montreal, QC:Toronto, ON', index)
    );
    System.assertEquals(
      'montreal|qc|ca>toronto|on|ca',
      LaneEdgeKey.resolve('MONTREAL, QC:Toronto, ON', index),
      'a spelling listed in Spellings__c resolves to the same edge'
    );
    System.assertEquals(
      null,
      LaneEdgeKey.resolve('Montreal, QC:Nowhere, ZZ', index),
      'a side with no place is not an edge - the batch skips it rather than inventing one'
    );
  }

  /**
   * The province code alone cannot say which country a side is in: BC is British Columbia and
   * Baja California. Resolving on the whole "city, province" string is what keeps them apart.
   *
   * Mutation: key variantIndex on place.Province__c instead of the full variant - both places
   * collapse onto one entry and one of these two assertions fails.
   */
  @IsTest
  static void twoPlacesSharingAProvinceCodeStayTwoPlaces() {
    Map<String, String> index = LaneEdgeKey.variantIndex(
      new List<Pricing_Place__c>{
        place('vancouver|bc|ca', 'Vancouver', 'BC', null),
        place('tijuana|bc|mx', 'Tijuana', 'BC', null)
      }
    );

    System.assertEquals(
      'vancouver|bc|ca>tijuana|bc|mx',
      LaneEdgeKey.resolve('Vancouver, BC:Tijuana, BC', index),
      'BC is two provinces in two countries; the city is what tells them apart'
    );
    System.assertEquals(
      'tijuana|bc|mx>vancouver|bc|ca',
      LaneEdgeKey.resolve('Tijuana, BC:Vancouver, BC', index)
    );
  }
}
```

- [ ] **Step 2: Add the stub that compiles, deploy, and watch the assertions fail**

```apex
public without sharing class LaneEdgeKey {
  public static final String EDGE_JOIN = '>';

  public static List<String> sides(String cityLane) {
    return null;
  }

  public static String normalize(String side) {
    return null;
  }

  public static Map<String, String> variantIndex(
    List<Pricing_Place__c> places
  ) {
    return new Map<String, String>();
  }

  public static String edgeKey(
    String originPlaceKey,
    String destinationPlaceKey
  ) {
    return null;
  }

  public static String resolve(String cityLane, Map<String, String> index) {
    return null;
  }
}
```

```bash
sf project deploy start --source-dir force-app/main/default/classes/LaneEdgeKey.cls --source-dir force-app/main/default/classes/LaneEdgeKeyTest.cls --target-org sandbox --test-level NoTestRun --async --json
sf apex run test --tests LaneEdgeKeyTest --target-org sandbox --json
```

Poll `SELECT Status, MethodsFailed FROM ApexTestRunResult WHERE AsyncApexJobId='<id>'`, then read the messages from `ApexTestResult`. Expected: **6 of 6 fail on assertions**, not on compilation — `splitsALaneIntoItsTwoSides` should report a null dereference or a size mismatch rather than "Method does not exist". Record the exact text; a method failing for a compile reason means the stub is wrong, not the test.

- [ ] **Step 3: Implement**

```apex
/**
 * Turns a raw rtms__City_Lane__c string into the normalised place pair that identifies one lane.
 *
 * Revenova writes "Scarborough, ON:Lithia Springs, GA" and the same place appears under several
 * spellings, so 49,592 distinct raw strings are far fewer real lanes. Resolution goes through the
 * variant set PlaceNormalizer already builds for the search, rather than a second one here: two
 * spellings-to-place mappings that can disagree is the drift this app keeps correcting.
 *
 * Pure: no SOQL, no DML. The caller reads places once and passes the index in.
 */
public without sharing class LaneEdgeKey {
  public static final String EDGE_JOIN = '>';
  private static final String SIDE_SEPARATOR = ':';

  /** The two halves of a lane, or null for anything that is not exactly two non-empty halves. */
  public static List<String> sides(String cityLane) {
    if (String.isBlank(cityLane)) {
      return null;
    }
    List<String> parts = cityLane.split(SIDE_SEPARATOR);
    if (parts.size() != 2) {
      return null;
    }
    String origin = parts[0].trim();
    String destination = parts[1].trim();
    if (String.isBlank(origin) || String.isBlank(destination)) {
      return null;
    }
    return new List<String>{ origin, destination };
  }

  /** Case, accents and spacing around the comma are spellings, not different places. */
  public static String normalize(String side) {
    if (String.isBlank(side)) {
      return null;
    }
    return PlaceNormalizer.stripAccents(side)
      .toLowerCase()
      .normalizeSpace()
      .replaceAll('\\s*,\\s*', ', ');
  }

  /** Every spelling a place answers to, mapped to that place's key. */
  public static Map<String, String> variantIndex(
    List<Pricing_Place__c> places
  ) {
    Map<String, String> index = new Map<String, String>();
    if (places == null) {
      return index;
    }
    for (Pricing_Place__c p : places) {
      if (String.isBlank(p.Key__c)) {
        continue;
      }
      for (String variant : PlaceNormalizer.cityLaneVariants(p)) {
        String normalized = normalize(variant);
        if (normalized != null) {
          index.put(normalized, p.Key__c);
        }
      }
    }
    return index;
  }

  /** Directional on purpose: the two directions of a lane are priced separately. */
  public static String edgeKey(
    String originPlaceKey,
    String destinationPlaceKey
  ) {
    if (String.isBlank(originPlaceKey) || String.isBlank(destinationPlaceKey)) {
      return null;
    }
    return originPlaceKey + EDGE_JOIN + destinationPlaceKey;
  }

  /** Null when either side has no place: the batch skips it rather than inventing an edge. */
  public static String resolve(String cityLane, Map<String, String> index) {
    List<String> parts = sides(cityLane);
    if (parts == null || index == null) {
      return null;
    }
    return edgeKey(
      index.get(normalize(parts[0])),
      index.get(normalize(parts[1]))
    );
  }
}
```

- [ ] **Step 4: Deploy, confirm green, check PMD**

```bash
sf project deploy start --source-dir force-app/main/default/classes/LaneEdgeKey.cls --target-org sandbox --test-level NoTestRun --async --json
sf apex run test --tests LaneEdgeKeyTest --target-org sandbox --json
npm run pmd
```

Expected: 6 of 6 pass, PMD 0. Confirm the deploy landed by reading `ApexClass.LastModifiedDate`, not the deploy's status field, which has reported a stale `InProgress` well after success on this org.

- [ ] **Step 5: Commit**

```bash
git add force-app/main/default/classes/LaneEdgeKey.cls force-app/main/default/classes/LaneEdgeKey.cls-meta.xml force-app/main/default/classes/LaneEdgeKeyTest.cls force-app/main/default/classes/LaneEdgeKeyTest.cls-meta.xml manifest/package.xml
git commit -m "Resolve a raw lane string to the place pair that identifies the lane

Revenova writes City, ST:City, ST and the same place appears under several
spellings, so 49,592 distinct raw strings are far fewer real lanes. Resolution
goes through the variant set PlaceNormalizer already builds for the search
rather than a second mapping here, because two spellings-to-place mappings that
can disagree is the drift this app keeps correcting.

Keyed on the whole city-and-province side rather than the province code: BC is
British Columbia and Baja California, and a province-keyed resolver would put
Vancouver and Tijuana in the same country."
```

---

### Task 3: `LaneEdgeAgg` — one lane's evidence, accumulated

**Files:**

- Create: `force-app/main/default/classes/LaneEdgeAgg.cls` + `.cls-meta.xml`
- Create: `force-app/main/default/classes/LaneEdgeAggTest.cls` + `.cls-meta.xml`
- Modify: `manifest/package.xml`

**Interfaces:**

- Consumes: `SplitLaneService.median(List<Decimal>)` — only in a test, to pin agreement.
- Produces, on `LaneEdgeAgg`:
  - `public LaneEdgeAgg(String edgeKey, String originPlaceKey, String destinationPlaceKey)`
  - `public void foldLoad(Date movedOn, Id carrierId, Decimal cost, Decimal miles, Date horizon365)` → `void`
  - `public void addSource(String source)` → `void`
  - `public Lane_Edge__c toRow(Datetime builtOn)` → `Lane_Edge__c`
  - `public String cityLane`, `public String stateLane` — set by the caller from the first load seen
  - `public static Decimal percentile(List<Decimal> values, Decimal fraction)` → `Decimal`

Pure apart from constructing an unsaved `Lane_Edge__c`. All of the arithmetic lives here so the batch stays thin.

**Measured facts this must handle.** Of the 318,465 loads carrying a lane key: **91.0%** have `rtms3__Delivery_Date__c`, **86.7%** have `rtms__Carrier__c`, **97.7%** have `rtms__Distance_Miles__c`, **87.5%** have `rtms__Carrier_Quote_Total__c`. So roughly one load in eight has no carrier. It still moved — it counts as a load — but it cannot add to the distinct-carrier count that D5 makes the main signal. Silently counting it as a carrier would inflate exactly the number the band leans on.

**Percentiles must agree with the median already in the app.** `SplitLaneService.median` averages the middle two values on an even list and returns `setScale(2)`. A nearest-rank percentile would disagree with it at 0.5, so two parts of the same page would report different medians for the same rates. Linear interpolation agrees exactly: at fraction 0.5 it returns the middle element for an odd list and the average of the middle two for an even one. Task 3's fourth test pins that, and it is the test to keep if any are ever trimmed.

- [ ] **Step 1: Write the failing tests**

```apex
@IsTest
private class LaneEdgeAggTest {
  private static final Date TODAY = Date.newInstance(2026, 9, 20);
  private static final Date HORIZON_365 = TODAY.addDays(-365);

  private static LaneEdgeAgg agg() {
    return new LaneEdgeAgg(
      'montreal|qc|ca>toronto|on|ca',
      'montreal|qc|ca',
      'toronto|on|ca'
    );
  }

  @IsTest
  static void countsTheRecentWindowSeparatelyFromTheWholeHistory() {
    LaneEdgeAgg a = agg();
    a.foldLoad(TODAY.addDays(-30), null, null, null, HORIZON_365);
    a.foldLoad(TODAY.addDays(-200), null, null, null, HORIZON_365);
    a.foldLoad(TODAY.addDays(-800), null, null, null, HORIZON_365);

    Lane_Edge__c row = a.toRow(Datetime.now());
    System.assertEquals(
      2,
      row.Loads_Moved_365d__c,
      'the 800-day-old load is history, not a sign the lane runs now'
    );
    System.assertEquals(3, row.Loads_Moved_3y__c);
  }

  @IsTest
  static void countsEachCarrierOnceHoweverOftenItRuns() {
    LaneEdgeAgg a = agg();
    Id carrierA = TestIds.account(1);
    Id carrierB = TestIds.account(2);
    a.foldLoad(TODAY.addDays(-10), carrierA, null, null, HORIZON_365);
    a.foldLoad(TODAY.addDays(-11), carrierA, null, null, HORIZON_365);
    a.foldLoad(TODAY.addDays(-12), carrierA, null, null, HORIZON_365);
    a.foldLoad(TODAY.addDays(-13), carrierB, null, null, HORIZON_365);

    System.assertEquals(
      2,
      a.toRow(Datetime.now()).Carriers_Moved_3y__c,
      'four loads, two carriers: D5 measures who can cover the lane, not how ' +
      'many times the busiest one did'
    );
  }

  @IsTest
  static void aLoadWithNoCarrierStillMovedButAddsNoCarrier() {
    LaneEdgeAgg a = agg();
    a.foldLoad(TODAY.addDays(-5), TestIds.account(1), null, null, HORIZON_365);
    a.foldLoad(TODAY.addDays(-6), null, null, null, HORIZON_365);

    Lane_Edge__c row = a.toRow(Datetime.now());
    System.assertEquals(2, row.Loads_Moved_3y__c, 'both loads moved');
    System.assertEquals(
      1,
      row.Carriers_Moved_3y__c,
      'one load in eight has no carrier in this org; counting it as one would ' +
      'inflate the exact number the band leans on'
    );
  }

  /**
   * Mutation: switch percentile to nearest-rank (return ordered[position.round()]) - the even-list
   * assertion fails, because nearest-rank gives 200 or 300 where the median gives 250.
   */
  @IsTest
  static void theHalfwayPercentileIsTheMedianTheRestOfTheAppAlreadyComputes() {
    List<Decimal> even = new List<Decimal>{ 100, 200, 300, 400 };
    List<Decimal> odd = new List<Decimal>{ 100, 200, 300 };

    System.assert(
      LaneEdgeAgg.percentile(even, 0.5) == SplitLaneService.median(even),
      'an even list: the app averages the middle two, so this must too, or two ' +
      'parts of one page report different medians for the same rates'
    );
    System.assert(
      LaneEdgeAgg.percentile(odd, 0.5) == SplitLaneService.median(odd),
      'and an odd list'
    );
    System.assert(
      LaneEdgeAgg.percentile(even, 0.5) == 250.00,
      'stated outright so this cannot pass by both sides being wrong together'
    );
  }

  @IsTest
  static void theQuartilesBracketTheMedian() {
    List<Decimal> values = new List<Decimal>{ 100, 200, 300, 400 };
    System.assert(LaneEdgeAgg.percentile(values, 0.25) == 175.00);
    System.assert(LaneEdgeAgg.percentile(values, 0.75) == 325.00);
    System.assertEquals(
      null,
      LaneEdgeAgg.percentile(new List<Decimal>(), 0.5),
      'no rates is not a cost of zero'
    );
  }

  @IsTest
  static void reportsTheCostRangeAndTheRatePerMile() {
    LaneEdgeAgg a = agg();
    a.foldLoad(TODAY.addDays(-1), null, 1000, 500, HORIZON_365);
    a.foldLoad(TODAY.addDays(-2), null, 2000, 500, HORIZON_365);
    a.foldLoad(TODAY.addDays(-3), null, 3000, 500, HORIZON_365);
    a.foldLoad(TODAY.addDays(-4), null, 4000, 500, HORIZON_365);

    Lane_Edge__c row = a.toRow(Datetime.now());
    System.assert(row.Median_Cost_CAD__c == 2500.00);
    System.assert(row.P25_Cost_CAD__c == 1750.00);
    System.assert(row.P75_Cost_CAD__c == 3250.00);
    System.assert(
      row.Median_Rate_Per_Mile__c == 5.00,
      '2500 over 500 miles - the per-mile median is taken over the loads, not ' +
      'derived from the two medians, because a lane mixes distances'
    );
  }

  @IsTest
  static void aLoadWithNoCostOrNoMilesContributesNeitherRatherThanAZero() {
    LaneEdgeAgg a = agg();
    a.foldLoad(TODAY.addDays(-1), null, 1000, 500, HORIZON_365);
    a.foldLoad(TODAY.addDays(-2), null, null, 500, HORIZON_365);
    a.foldLoad(TODAY.addDays(-3), null, 3000, 0, HORIZON_365);

    Lane_Edge__c row = a.toRow(Datetime.now());
    System.assert(
      row.Median_Cost_CAD__c == 2000.00,
      'the costed loads are 1000 and 3000; the one without a cost is not a zero'
    );
    System.assert(
      row.Median_Rate_Per_Mile__c == 2.00,
      'only the 1000-over-500 load has both, and zero miles is not a divisor'
    );
  }

  @IsTest
  static void reportsWhenItLastMovedAndWhatBuiltIt() {
    LaneEdgeAgg a = agg();
    a.foldLoad(Date.newInstance(2025, 1, 5), null, null, null, HORIZON_365);
    a.foldLoad(Date.newInstance(2026, 3, 9), null, null, null, HORIZON_365);
    a.foldLoad(Date.newInstance(2024, 7, 1), null, null, null, HORIZON_365);
    a.addSource('loads');
    a.addSource('quotes');
    a.addSource('loads');
    a.cityLane = 'Montreal, QC:Toronto, ON';
    a.stateLane = 'QC:ON';

    Datetime builtOn = Datetime.newInstance(2026, 9, 20, 3, 0, 0);
    Lane_Edge__c row = a.toRow(builtOn);
    System.assertEquals(Date.newInstance(2026, 3, 9), row.Last_Moved_On__c);
    System.assertEquals('montreal|qc|ca>toronto|on|ca', row.Key__c);
    System.assertEquals('montreal|qc|ca', row.Origin_Place_Key__c);
    System.assertEquals('Montreal, QC:Toronto, ON', row.City_Lane__c);
    System.assertEquals('QC:ON', row.State_Lane__c);
    System.assertEquals(builtOn, row.Built_On__c);
    System.assertEquals(
      'loads,quotes',
      row.Sources__c,
      'each source named once and in a stable order, so a rebuild that changed ' +
      'nothing does not look like a change'
    );
  }

  @IsTest
  static void aLoadWithNoDateIsNotCountedAsMovingToday() {
    LaneEdgeAgg a = agg();
    a.foldLoad(null, TestIds.account(1), 1000, 100, HORIZON_365);

    Lane_Edge__c row = a.toRow(Datetime.now());
    System.assertEquals(
      null,
      row.Last_Moved_On__c,
      'nine percent of loads have no delivery date; a null is unknown, not now'
    );
    System.assertEquals(0, row.Loads_Moved_365d__c);
    System.assertEquals(
      1,
      row.Loads_Moved_3y__c,
      'it still moved, and its cost still counts - only its recency is unknown'
    );
    System.assert(row.Median_Cost_CAD__c == 1000.00);
  }
}
```

`TestIds.account(n)` is a helper that fabricates a distinct Account Id without DML. If the repo has no such helper, add one to this test class as a private static method:

```apex
  private static Integer idSeed = 1;
  private static Id account(Integer n) {
    return Id.valueOf('001000000000' + String.valueOf(100000 + n).substring(1) + 'AAA');
  }
```

and call it `account(1)` rather than `TestIds.account(1)`. Check first with `grep -rn "class TestIds" force-app` and follow whatever is already there rather than adding a second helper.

- [ ] **Step 2: Stub, deploy, watch the assertions fail**

Give every method a body that compiles and returns a null, zero or empty `Lane_Edge__c`, deploy, and run `LaneEdgeAggTest`. Expected: **9 of 9 fail on assertions**, none on compilation. Record the text of two of them.

- [ ] **Step 3: Implement**

```apex
/**
 * One lane's accumulating evidence: how often it ran, who moved it, what it cost and when it last
 * moved. Folded a load at a time by LaneEdgeBatch, then emitted as an unsaved Lane_Edge__c.
 *
 * Nulls are unknowns, never zeros. Measured in PostProduc on 2026-09-20 across the 318,465 loads
 * carrying a lane key: 9% have no delivery date, 13% no carrier, 12% no cost. A load with no
 * carrier still moved - it counts as a load - but it cannot add to the distinct-carrier count that
 * D5 makes the band's main signal, and counting it would inflate exactly that number.
 */
public class LaneEdgeAgg {
  public String cityLane;
  public String stateLane;

  private final String edgeKey;
  private final String originPlaceKey;
  private final String destinationPlaceKey;
  private Integer loads365 = 0;
  private Integer loads3y = 0;
  private final Set<Id> carriers = new Set<Id>();
  private final List<Decimal> costs = new List<Decimal>();
  private final List<Decimal> perMile = new List<Decimal>();
  private Date lastMovedOn;
  private final Set<String> sources = new Set<String>();

  public LaneEdgeAgg(
    String edgeKey,
    String originPlaceKey,
    String destinationPlaceKey
  ) {
    this.edgeKey = edgeKey;
    this.originPlaceKey = originPlaceKey;
    this.destinationPlaceKey = destinationPlaceKey;
  }

  public void foldLoad(
    Date movedOn,
    Id carrierId,
    Decimal cost,
    Decimal miles,
    Date horizon365
  ) {
    loads3y++;
    if (movedOn != null) {
      if (movedOn >= horizon365) {
        loads365++;
      }
      if (lastMovedOn == null || movedOn > lastMovedOn) {
        lastMovedOn = movedOn;
      }
    }
    if (carrierId != null) {
      carriers.add(carrierId);
    }
    if (cost != null) {
      costs.add(cost);
      if (miles != null && miles > 0) {
        perMile.add(cost / miles);
      }
    }
  }

  public void addSource(String source) {
    if (String.isNotBlank(source)) {
      sources.add(source);
    }
  }

  /**
   * Linear interpolation, not nearest rank, so that at 0.5 this returns exactly what
   * SplitLaneService.median returns - the middle of an odd list, the average of the middle two of
   * an even one. Two medians on one page that disagree is worse than either being slightly off.
   */
  public static Decimal percentile(List<Decimal> values, Decimal fraction) {
    if (values == null || values.isEmpty()) {
      return null;
    }
    List<Decimal> ordered = values.clone();
    ordered.sort();
    Integer n = ordered.size();
    if (n == 1) {
      return ordered[0].setScale(2);
    }
    Decimal position = fraction * (n - 1);
    Integer lower = position.intValue();
    Integer upper = lower + 1 < n ? lower + 1 : lower;
    Decimal share = position - lower;
    return (ordered[lower] + (ordered[upper] - ordered[lower]) * share)
      .setScale(2);
  }

  public Lane_Edge__c toRow(Datetime builtOn) {
    List<String> named = new List<String>(sources);
    named.sort();
    return new Lane_Edge__c(
      Key__c = edgeKey,
      Origin_Place_Key__c = originPlaceKey,
      Destination_Place_Key__c = destinationPlaceKey,
      City_Lane__c = cityLane,
      State_Lane__c = stateLane,
      Loads_Moved_365d__c = loads365,
      Loads_Moved_3y__c = loads3y,
      Carriers_Moved_3y__c = carriers.size(),
      Median_Cost_CAD__c = percentile(costs, 0.5),
      P25_Cost_CAD__c = percentile(costs, 0.25),
      P75_Cost_CAD__c = percentile(costs, 0.75),
      Median_Rate_Per_Mile__c = percentile(perMile, 0.5),
      Last_Moved_On__c = lastMovedOn,
      Sources__c = String.join(named, ','),
      Built_On__c = builtOn
    );
  }
}
```

`Median_Rate_Per_Mile__c` is the median **of the per-load rates**, not `Median_Cost_CAD__c` divided by a median distance: a lane mixes distances, and dividing one median by another is not the median of the ratios.

- [ ] **Step 4: Deploy, confirm green, check PMD and complexity**

```bash
sf apex run test --tests LaneEdgeAggTest --target-org sandbox --json
npm run pmd
```

Expected 9 of 9 pass, PMD 0. Report `LaneEdgeAgg`'s measured complexity — `foldLoad` alone carries six branches, so check the **per-method** ceiling of 10 as well as the class's 40.

- [ ] **Step 5: Commit**

```bash
git add force-app/main/default/classes/LaneEdgeAgg* manifest/package.xml
git commit -m "Accumulate one lane's evidence, treating a missing value as unknown

Nulls are unknowns, not zeros, and the difference is load-bearing: of the
318,465 loads carrying a lane key, 9% have no delivery date, 13% no carrier and
12% no cost. A load with no carrier still moved, so it counts as a load, but it
adds no carrier - counting it would inflate the distinct-carrier figure the
difficulty band leans on hardest.

Percentiles interpolate rather than taking a nearest rank, so that the halfway
percentile is exactly the median SplitLaneService already computes. Two medians
on one page that disagree would be worse than either being slightly off."
```

---

### Task 4: `LaneEdgeBatch` — build the index without holding it in memory

**Files:**

- Create: `force-app/main/default/classes/LaneEdgeBatch.cls` + `.cls-meta.xml`
- Create: `force-app/main/default/classes/LaneEdgeBatchTest.cls` + `.cls-meta.xml`
- Modify: `manifest/package.xml`

**Interfaces:**

- Consumes: `LaneEdgeKey.variantIndex`, `LaneEdgeKey.resolve`, `LaneEdgeKey.sides`, `LaneEdgeAgg`.
- Produces: `LaneEdgeBatch implements Database.Batchable<SObject>, Database.Stateful`, constructed as `new LaneEdgeBatch()` and run with `Database.executeBatch(new LaneEdgeBatch(), 2000)`. Exposes `@TestVisible Integer rowsWritten` so a test can assert what it wrote without re-querying.

**The constraint that decides this design, measured rather than assumed.** The obvious shape — accumulate every lane in `Database.Stateful` memory, write at the end, as `PlaceBuilderBatch` does — **does not fit this org**. Across the 318,465 loads carrying a lane key, holding every cost is about 5.1 MB of `Decimal` and every carrier id about 9.9 MB of `Id`; async Apex allows 12 MB of heap. The place batch gets away with it because there are thousands of places, not hundreds of thousands of loads.

So this batch orders its query by the lane key and writes a lane out as soon as it sees a different one. Memory is then one lane's worth — the busiest province pair runs about 3,839 loads a year and a city lane is far smaller — and the rows upserted per scope can never exceed the scope size, so the 10,000-DML-row limit that forced the place dictionary into a second batch is not reachable here. **That is why this plan has no write batch and the place dictionary does; do not "restore" the missing one.**

- [ ] **Step 1: Write the failing tests**

```apex
@IsTest
private class LaneEdgeBatchTest {
  /**
   * Two places and four loads: three on Montreal->Toronto, one on the reverse. Inserted, because a
   * batch reads from the database - this is the one class here that needs real rows.
   */
  @TestSetup
  static void data() {
    List<Pricing_Place__c> places = new List<Pricing_Place__c>{
      new Pricing_Place__c(
        Key__c = 'montreal|qc|ca',
        Name = 'Montreal, QC, CA',
        City__c = 'Montreal',
        Province__c = 'QC',
        Country__c = 'CA'
      ),
      new Pricing_Place__c(
        Key__c = 'toronto|on|ca',
        Name = 'Toronto, ON, CA',
        City__c = 'Toronto',
        Province__c = 'ON',
        Country__c = 'CA'
      )
    };
    insert places;

    Account carrier = new Account(Name = 'Test Carrier');
    insert carrier;

    List<rtms__Load__c> loads = new List<rtms__Load__c>();
    for (Integer i = 0; i < 3; i++) {
      loads.add(
        new rtms__Load__c(
          rtms__City_Lane__c = 'Montreal, QC:Toronto, ON',
          rtms__State_Lane__c = 'QC:ON',
          rtms3__Delivery_Date__c = Date.today().addDays(-10 - i),
          rtms__Carrier__c = carrier.Id,
          rtms__Carrier_Quote_Total__c = 1000 + (i * 1000),
          rtms__Distance_Miles__c = 500
        )
      );
    }
    loads.add(
      new rtms__Load__c(
        rtms__City_Lane__c = 'Toronto, ON:Montreal, QC',
        rtms__State_Lane__c = 'ON:QC',
        rtms3__Delivery_Date__c = Date.today().addDays(-20),
        rtms__Carrier__c = carrier.Id,
        rtms__Carrier_Quote_Total__c = 9000,
        rtms__Distance_Miles__c = 500
      )
    );
    insert loads;
  }

  @IsTest
  static void buildsOneEdgePerDirectionWithItsOwnEvidence() {
    Test.startTest();
    Database.executeBatch(new LaneEdgeBatch(), 2000);
    Test.stopTest();

    Map<String, Lane_Edge__c> byKey = new Map<String, Lane_Edge__c>();
    for (Lane_Edge__c e : [
      SELECT
        Key__c,
        Loads_Moved_3y__c,
        Carriers_Moved_3y__c,
        Median_Cost_CAD__c,
        City_Lane__c,
        State_Lane__c,
        Sources__c
      FROM Lane_Edge__c
    ]) {
      byKey.put(e.Key__c, e);
    }

    System.assertEquals(
      2,
      byKey.size(),
      'the two directions are two lanes, not one averaged together'
    );

    Lane_Edge__c out = byKey.get('montreal|qc|ca>toronto|on|ca');
    System.assertEquals(3, out.Loads_Moved_3y__c);
    System.assertEquals(1, out.Carriers_Moved_3y__c);
    System.assert(out.Median_Cost_CAD__c == 2000.00);
    System.assertEquals('Montreal, QC:Toronto, ON', out.City_Lane__c);
    System.assertEquals('QC:ON', out.State_Lane__c);
    System.assertEquals('loads', out.Sources__c);

    System.assert(
      byKey.get('toronto|on|ca>montreal|qc|ca').Median_Cost_CAD__c == 9000.00,
      'the reverse lane keeps its own cost - if the two directions had been ' +
      'folded together this would be 2000 or 3000'
    );
  }

  @IsTest
  static void aSecondRunUpdatesRatherThanDuplicating() {
    Test.startTest();
    Database.executeBatch(new LaneEdgeBatch(), 2000);
    Test.stopTest();

    // A second synchronous pass over the same data, the way a nightly rebuild would.
    LaneEdgeBatch again = new LaneEdgeBatch();
    again.buildVariantIndex();
    again.execute(
      null,
      [
        SELECT
          rtms__City_Lane__c,
          rtms__State_Lane__c,
          rtms3__Delivery_Date__c,
          rtms__Carrier__c,
          rtms__Carrier_Quote_Total__c,
          rtms__Distance_Miles__c
        FROM rtms__Load__c
        ORDER BY rtms__City_Lane__c NULLS LAST
      ]
    );
    again.finish(null);

    System.assertEquals(
      2,
      [SELECT COUNT() FROM Lane_Edge__c],
      'Key__c is the external id, so a rebuild updates; without externalId this ' +
      'is 4 and nothing else in the batch would notice'
    );
  }

  @IsTest
  static void aLaneWhoseSidesAreNotPlacesIsSkippedRatherThanInvented() {
    insert new rtms__Load__c(
      rtms__City_Lane__c = 'Nowhere, ZZ:Elsewhere, YY',
      rtms3__Delivery_Date__c = Date.today().addDays(-5)
    );

    Test.startTest();
    Database.executeBatch(new LaneEdgeBatch(), 2000);
    Test.stopTest();

    System.assertEquals(
      2,
      [SELECT COUNT() FROM Lane_Edge__c],
      'an unresolvable lane produces no edge; inventing a place here would put ' +
      'a lane in the index that no search can ever match'
    );
  }
}
```

- [ ] **Step 2: Stub, deploy, watch the assertions fail**

The stub needs `start`, `execute`, `finish`, `buildVariantIndex` and `rowsWritten` so the tests compile. Have `execute` do nothing. Expected: **3 of 3 fail on assertions** — the first on `0 != 2` rather than on a missing method.

- [ ] **Step 3: Implement**

```apex
/**
 * Builds Lane_Edge__c from loads: one row per normalised lane, per direction.
 *
 * Ordered by the lane key and written out the moment the key changes, which is the whole design.
 * Accumulating every lane in stateful memory - the shape PlaceBuilderBatch uses - does not fit this
 * org: the 318,465 loads carrying a lane key hold about 5.1 MB of cost Decimals and 9.9 MB of
 * carrier Ids against a 12 MB async heap. One lane at a time fits with room to spare, and the rows
 * upserted per scope can never exceed the scope size, so the DML row limit that forced the place
 * dictionary into a second batch is out of reach here.
 */
// Runs without sharing on purpose: the index describes every team's freight. Reads are gated by
// permission set on whatever reads Lane_Edge__c, not here.
public without sharing class LaneEdgeBatch implements Database.Batchable<SObject>, Database.Stateful {
  @TestVisible
  private Integer rowsWritten = 0;
  private Map<String, String> variantIndex;
  private LaneEdgeAgg current;
  private String currentKey;
  private final Datetime builtOn = Datetime.now();
  private final Date horizon365 = Date.today().addDays(-365);

  @SuppressWarnings(
    'PMD.ApexCRUDViolation'
  ) // system mode by design (see class comment)
  @TestVisible
  private void buildVariantIndex() {
    variantIndex = LaneEdgeKey.variantIndex(
      [
        SELECT Key__c, City__c, Province__c, Spellings__c
        FROM Pricing_Place__c
        WHERE Key__c != NULL
      ]
    );
  }

  @SuppressWarnings(
    'PMD.ApexCRUDViolation'
  ) // system mode by design (see class comment)
  public Database.QueryLocator start(Database.BatchableContext bc) {
    buildVariantIndex();
    return Database.getQueryLocator(
      [
        SELECT
          rtms__City_Lane__c,
          rtms__State_Lane__c,
          rtms3__Delivery_Date__c,
          rtms__Carrier__c,
          rtms__Carrier_Quote_Total__c,
          rtms__Distance_Miles__c
        FROM rtms__Load__c
        WHERE rtms__City_Lane__c != NULL
        ORDER BY rtms__City_Lane__c NULLS LAST
      ]
    );
  }

  public void execute(Database.BatchableContext bc, List<rtms__Load__c> scope) {
    List<Lane_Edge__c> ready = new List<Lane_Edge__c>();
    for (rtms__Load__c load : scope) {
      String edge = LaneEdgeKey.resolve(load.rtms__City_Lane__c, variantIndex);
      if (edge == null) {
        continue;
      }
      if (edge != currentKey) {
        if (current != null) {
          ready.add(current.toRow(builtOn));
        }
        current = newAgg(edge, load);
        currentKey = edge;
      }
      current.foldLoad(
        load.rtms3__Delivery_Date__c,
        load.rtms__Carrier__c,
        load.rtms__Carrier_Quote_Total__c,
        load.rtms__Distance_Miles__c,
        horizon365
      );
    }
    write(ready);
  }

  public void finish(Database.BatchableContext bc) {
    if (current != null) {
      write(new List<Lane_Edge__c>{ current.toRow(builtOn) });
      current = null;
      currentKey = null;
    }
  }

  private LaneEdgeAgg newAgg(String edge, rtms__Load__c load) {
    List<String> parts = edge.split(LaneEdgeKey.EDGE_JOIN);
    LaneEdgeAgg agg = new LaneEdgeAgg(edge, parts[0], parts[1]);
    agg.cityLane = load.rtms__City_Lane__c;
    agg.stateLane = load.rtms__State_Lane__c;
    agg.addSource('loads');
    return agg;
  }

  @SuppressWarnings(
    'PMD.ApexCRUDViolation'
  ) // system mode by design (see class comment)
  private void write(List<Lane_Edge__c> rows) {
    if (rows.isEmpty()) {
      return;
    }
    upsert rows Key__c;
    rowsWritten += rows.size();
  }
}
```

`EDGE_JOIN` is `'>'`, which `String.split` treats as a regex — `>` is not a regex metacharacter, so this is safe. Do not change `EDGE_JOIN` to something like `|` or `.` without changing this split.

A lane that spans a scope boundary is carried in `current` across transactions because the class is `Database.Stateful`, and `finish` writes the last one. A lane that is _entirely_ within one scope is written inside `execute`.

- [ ] **Step 4: Deploy, run, check PMD**

```bash
sf apex run test --tests LaneEdgeBatchTest --target-org sandbox --json
npm run pmd
```

Expected 3 of 3 pass, PMD 0. **Do not run this batch against real org data yet** — that is Task 6, deliberately.

- [ ] **Step 5: Commit**

```bash
git add force-app/main/default/classes/LaneEdgeBatch* manifest/package.xml
git commit -m "Build the lane index one lane at a time, not one org at a time

Ordering the query by the lane key and writing a row the moment the key changes
is the whole design, and it is forced by measurement: the 318,465 loads carrying
a lane key hold about 5.1 MB of cost Decimals and 9.9 MB of carrier Ids, against
a 12 MB async heap. Accumulating the org the way PlaceBuilderBatch does would not
fit - the place batch gets away with it because there are thousands of places,
not hundreds of thousands of loads.

One lane at a time also caps rows per scope at the scope size, so the DML row
limit that forced the place dictionary into a second write batch is out of reach
here. That is why this has no write batch and the place dictionary does."
```

---

### Task 5: `LaneEdgeEnrichBatch` — the other three sources

**Files:**

- Create: `force-app/main/default/classes/LaneEdgeEnrichBatch.cls` + `.cls-meta.xml`
- Create: `force-app/main/default/classes/LaneEdgeEnrichBatchTest.cls` + `.cls-meta.xml`
- Modify: `manifest/package.xml`

**Interfaces:**

- Consumes: `LaneEdgeKey.resolve`, `Lane_Edge__c` as written by Task 4.
- Produces: `LaneEdgeEnrichBatch implements Database.Batchable<SObject>, Database.Stateful`, chained from `LaneEdgeBatch.finish` once Task 6 has proved the build runs.

**What this adds, and what it honestly cannot.** D2 names four sources. Loads are Task 4. This task folds in the other three by their stored keys:

- **Quotes** (`rtms__CarrierQuote__c`) reach a lane through their load, and add `quotes` to `Sources__c`. They do **not** change the carrier count: a carrier that quoted is not a carrier that moved it, and D5 is explicit that quote count measures the company's process rather than the market.
- **`Benchmark_Rate__c` bids** already carry `City_Lane__c`, so they resolve directly. **Measured 2026-09-20: this object holds one record.** The fold is written and tested anyway, because it is the only thing that will catch the fold breaking before RFP work populates the object — but the plan does not pretend it contributes data today, and neither should any README sentence written in Task 6.
- **Freight plan legs** are phase 8's source for proven multi-leg moves, read the way `FreightPlanReader` already reads them.

The enrichment never lowers a count and never overwrites a load-derived median; it only adds sources and fills a field that is null.

- [ ] **Step 1: Write the failing test**

```apex
@IsTest
private class LaneEdgeEnrichBatchTest {
  @TestSetup
  static void data() {
    insert new Lane_Edge__c(
      Key__c = 'montreal|qc|ca>toronto|on|ca',
      Origin_Place_Key__c = 'montreal|qc|ca',
      Destination_Place_Key__c = 'toronto|on|ca',
      City_Lane__c = 'Montreal, QC:Toronto, ON',
      Loads_Moved_3y__c = 3,
      Carriers_Moved_3y__c = 1,
      Median_Cost_CAD__c = 2000,
      Sources__c = 'loads'
    );
    insert new Benchmark_Rate__c(
      City_Lane__c = 'Montreal, QC:Toronto, ON',
      Rate__c = 2400
    );
  }

  @IsTest
  static void namesTheBidSourceWithoutDisturbingWhatTheLoadsSaid() {
    Test.startTest();
    Database.executeBatch(new LaneEdgeEnrichBatch(), 200);
    Test.stopTest();

    Lane_Edge__c e = [
      SELECT
        Sources__c,
        Loads_Moved_3y__c,
        Carriers_Moved_3y__c,
        Median_Cost_CAD__c
      FROM Lane_Edge__c
      WHERE Key__c = 'montreal|qc|ca>toronto|on|ca'
    ];
    System.assert(
      e.Sources__c.contains('bids'),
      'the bid source is named, so a reader can tell what produced the row'
    );
    System.assert(
      e.Sources__c.contains('loads'),
      'and the source that was already there survives'
    );
    System.assertEquals(
      1,
      e.Carriers_Moved_3y__c,
      'a bid is not a carrier that moved the lane - D5 counts moves, not offers'
    );
    System.assert(
      e.Median_Cost_CAD__c == 2000.00,
      'and the load-derived median is not overwritten by a bid'
    );
  }
}
```

Check `Benchmark_Rate__c`'s required fields with `sf sobject describe --sobject Benchmark_Rate__c` before writing the insert above; if `Rate__c` is not the field name or others are required, follow the object rather than this snippet, and say so in your report.

- [ ] **Step 2: Stub, deploy, watch it fail on the `contains('bids')` assertion**

- [ ] **Step 3: Implement**

The batch reads `Benchmark_Rate__c` ordered by `City_Lane__c`, resolves each to an edge key through the same variant index, collects the distinct edge keys per scope, queries those `Lane_Edge__c` rows by `Key__c`, adds `bids` to `Sources__c` where absent, and upserts. Quotes and legs follow the same shape against their own objects; write them as separate private methods on this class, and if the class approaches PMD's ceiling, split the leg fold into `LaneEdgeLegs` rather than suppressing.

- [ ] **Step 4: Deploy, confirm green, PMD 0, commit**

```bash
git add force-app/main/default/classes/LaneEdgeEnrichBatch* manifest/package.xml
git commit -m "Fold the bid, quote and leg sources into the index by their stored keys

Each source is named in Sources__c so a reader can tell what produced a row, and
none of them touches the carrier count: a carrier that quoted or bid is not a
carrier that moved the lane, and D5 counts moves because quote count measures
this company's process rather than the market.

Benchmark_Rate__c holds one record in PostProduc today, so the bid fold adds
nothing yet. It is written and tested anyway - it is the only thing that will
catch the fold breaking before RFP work populates the object."
```

---

### Task 6: The first real run, measured — and the documentation

**Files:**

- Modify: `manifest/package.xml`, `README.md`, `.github/workflows/ci.yml`
- Create: `docs/help/en/lb-index.md`, `docs/help/fr/lb-index.md`

**This task writes tens of thousands of records into a sandbox that is FULL and shared with other developers. Do not start it without saying so and getting a clear go-ahead.** Everything before this point is reversible; this is the step that puts real rows in someone else's org.

- [ ] **Step 1: Confirm the manifest lists every new class**

```bash
for c in $(ls force-app/main/default/classes/LaneEdge*.cls | sed 's|.*/||;s|\.cls||'); do
  printf "%-26s " "$c"; grep -c "<members>$c</members>" manifest/package.xml
done
```

Every line must read `1`. A class on disk and absent from the manifest passes every local gate and then vanishes from a manifest-based deploy.

- [ ] **Step 2: Measure before writing**

Run in anonymous Apex, and report the number before going further:

```apex
Map<String, String> index = LaneEdgeKey.variantIndex(
  [SELECT Key__c, City__c, Province__c, Spellings__c FROM Pricing_Place__c WHERE Key__c != NULL]
);
Set<String> edges = new Set<String>();
Integer unresolved = 0;
for (AggregateResult ar : [
  SELECT rtms__City_Lane__c lane FROM rtms__Load__c
  WHERE rtms__City_Lane__c != NULL GROUP BY rtms__City_Lane__c LIMIT 50000
]) {
  String edge = LaneEdgeKey.resolve((String) ar.get('lane'), index);
  if (edge == null) { unresolved++; } else { edges.add(edge); }
}
System.debug('variants=' + index.size() + ' edges=' + edges.size() + ' unresolved=' + unresolved);
```

This is the number the spec's amendment says to measure: 49,592 distinct raw strings is the **upper bound**, and this says what they collapse to. A high `unresolved` count means the place dictionary does not cover the lanes the loads actually run, which is a finding worth stopping for rather than building an index that silently omits them.

- [ ] **Step 3: Run the batch, and measure what it cost**

```apex
Database.executeBatch(new LaneEdgeBatch(), 2000);
```

Then, from `AsyncApexJob`, record `TotalJobItems`, `NumberOfErrors` and elapsed time, and from a debug log on one execute, the query rows and heap used. Spec §7 asks for exactly this. Report all of it.

- [ ] **Step 4: Verify the index against a lane you can check by hand**

Pick the busiest province pair, read its `Lane_Edge__c` row, and confirm `Loads_Moved_3y__c` matches a direct `SELECT COUNT()` over the same lane's loads. An index that disagrees with the data it was built from is worse than no index.

- [ ] **Step 5: README, CI and both help pages**

Add a `Lane_Edge__c` row and a `LaneEdge*` classes row to the README inventory, add the new test classes to `.github/workflows/ci.yml`'s `--tests` list and to the README's test roster, and write both help pages **in the same commit**.

`npm run help:check` verifies markdown against HTML **per language**, so an English page written and a French one skipped both pass cleanly. Write both, and read the French one rather than trusting the gate — that has already been wrong once on this project.

The help pages say what the index is and, per spec §6, that every card shows the build date because a stale index is a correctness risk rather than only a freshness one.

- [ ] **Step 6: All gates, then commit**

```bash
npm run pmd && npx jest && npm run lint && npm run help:check
```

```bash
git add -A
git commit -m "Record the lane index, and what building it actually cost

Numbers from the first real run rather than from the plan's estimate, so the
next person sizing a batch against this org has a measurement to start from."
```

---

## Self-Review

**Spec coverage.** D1 one materialised index — Tasks 1, 4. D2 sources from what the org has — Tasks 4, 5, with the amendment's finding that bids hold one row stated rather than glossed. D3 always a range — Task 3 writes P25/median/P75 and Task 1 gives them fields. D5 carriers not quotes — Task 3's carrier set, and Task 5 explicitly refuses to let a quote or bid raise it. D8 derived and disposable — Task 1's description, and Task 4's rebuild-updates test. **D4 (two hops), D6 (a band not a score) and D7 (composed never outranks direct) have no task here and are not gaps: they belong to the two feature plans this index unblocks.** Spec §4 and §5 likewise.

**Placeholder scan.** One deliberate deviation: Task 5's Step 3 describes the quote and leg folds in prose rather than in full code, because their shape is identical to the bid fold written out above it and the objects they read (`rtms__CarrierQuote__c`'s path to a lane, `FreightPlanReader`'s legs) need checking against the org before code is written for them. That is named in the step rather than hidden. Task 1's field table is the actual content — exact types, precisions and scales, with one field written out in full as the worked example.

**Type consistency.** `LaneEdgeKey.EDGE_JOIN` is `'>'` in Task 2 and is what Task 4 splits on. `LaneEdgeAgg`'s constructor takes `(edgeKey, originPlaceKey, destinationPlaceKey)` in Task 3 and is called that way in Task 4. `foldLoad(Date, Id, Decimal, Decimal, Date)` matches its call site. `Key__c` is the external id in Task 1 and is what Task 4's `upsert rows Key__c` and its duplicate test rely on.

**One risk this plan does not resolve.** `Database.getQueryLocator` with `ORDER BY` over 318,465 rows is the load-bearing assumption of Task 4, and it is untested against this org's data until Task 6. If the locator refuses the ordering or the query times out, the design falls back to two passes — counts first, percentiles per lane — at a real cost in run time. Task 6's Step 3 is where that is found out, which is why it comes before the documentation rather than after.
