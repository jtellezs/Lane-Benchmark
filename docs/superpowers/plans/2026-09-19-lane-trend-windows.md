# Lane Trend Windows Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Offer nine trend windows from one week to three years, each bucketed at a unit that makes it legible.

**Architecture:** Apex derives the bucket unit from `lookbackDays` and states it on the response (spec W1); the component renders whatever it is told. The bucketing calendar — how to key, label, count and threshold a day, a week or a month — moves out of `LaneTrendService` into a new `LaneTrendBuckets`, because the service sits at 39 against a PMD cap that fires at 40 and three-way dispatch would trip it. That split is forced, but it is also the right boundary: a unit calendar is one cohesive thing.

**Tech Stack:** Salesforce Apex (API 64.0), Lightning Web Components, Jest (`sfdx-lwc-jest`), PMD 7.15.0.

**Spec:** `docs/superpowers/specs/2026-09-19-lane-trend-windows-design.md` (decisions W1–W8)

## Global Constraints

- **`npm run pmd` must end at 0 violations.** The project's standing ruling is **split a cohesive family into its own class, never suppress** — the repo has zero `CyclomaticComplexity` and zero `ApexSOQLInjection` suppressions and that must stay true. **PMD's class rule fires at 40, so 39 is the highest safe total and there is no headroom at 39.** `LaneTrendService` is at 39 and `LaneTrendServiceTest` is at 39; neither may gain a method without a split.
- **Reserved Apex identifiers** may not name variables or parameters: `where`, `from`, `when`, `select`, `limit`, `group`, `currency`. Four of these have already cost deploys on this feature. Use `from0`/`to0`, `currencyCode`.
- **Decimal assertions** use `==` inside `System.assert(...)`; Integer, String and Boolean use `assertEquals`. Apex `assertEquals` is type- and scale-sensitive and medians come back at scale 2.
- **Dynamic SOQL** goes through `Database.queryWithBinds` / `countQueryWithBinds` with `AccessLevel.SYSTEM_MODE`, never bare `Database.query`. No task here changes a query.
- **TDD.** Jest gives a real RED. Apex cannot — a test referencing a missing member fails to _deploy_, a compile error rather than a failing test — so there: write the test plus a minimal compiling stub, deploy, watch the **assertion** fail, then implement.
- **Test honesty.** This feature has shipped four tests that could not fail for the reason they named. For every test, name in your report the mutation it catches, and distinguish evidence you **observed** from evidence you **traced**.
- **The org (`sandbox`, PostProduc) is shared with other developers.** Never refresh it. Deploy only the files you touch, always `--test-level NoTestRun`, and run tests as a separate async step. Confirm a deploy landed by reading `ApexClass.LastModifiedDate`, not the deploy status field, which has reported stale `InProgress` after success. Deploys take about 90 seconds and have taken 15 minutes at their worst.
- `npx prettier --write` on touched files before committing. Commit messages: imperative subject, prose body explaining _why_, **no AI attribution trailers**.
- Jest baseline is **46 suites / 456 tests**; Apex is **27/27** across `LaneTrendServiceTest` (20), `LaneTrendQueriesTest` (2) and `LaneTrendControllerTest` (5).

---

## File Structure

**Create:**

- `force-app/main/default/classes/LaneTrendBuckets.cls` (+ `-meta.xml`) — the unit calendar and the bucketing. Owns `unitFor`, `keyOf`, `labelOf`, `between`, `thinCountFor`, `bucket`. Pure: no SOQL, no DML.
- `force-app/main/default/classes/LaneTrendBucketsTest.cls` (+ `-meta.xml`)

**Modify:**

- `LaneTrendService.cls` — loses `bucket`, `monthKeyOf`, `monthsBetween`, `MONTH_LABELS` and `THIN_COUNT` to the new class; derives the unit; `ROW_CAP` 10,000 → 25,000
- `LaneTrend.cls` — `monthSpan` → `bucketSpan`, `Point.monthKey`/`monthIndex` → `bucketKey`/`bucketIndex`, plus `bucketUnit`
- `LaneTrendServiceTest.cls` — follows the renames
- `laneTrendChart.js` / `.html` — nine windows, renamed fields, label thinning, caption names the unit
- `laneTrendChart.test.js`
- `manifest/package.xml`, `README.md`, `docs/help/en/lb-trend.md`, `docs/help/fr/lb-trend.md`

**Why this split:** `bucket()` and its helpers are already a self-contained family — they take samples and a window and return points, touching nothing else. Moving them lets the unit dispatch live beside the keys and labels it varies, and drops `LaneTrendService` off the PMD cap so Task 3 can add the unit derivation without another split.

---

### Task 1: The unit calendar

**Files:**

- Create: `force-app/main/default/classes/LaneTrendBuckets.cls` (+ `-meta.xml`)
- Test: `force-app/main/default/classes/LaneTrendBucketsTest.cls` (+ `-meta.xml`)

**Interfaces:**

- Consumes: nothing.
- Produces, all `public static` on `LaneTrendBuckets`:
  - `DAY` / `WEEK` / `MONTH` — `public static final String`, values `'day'`, `'week'`, `'month'`
  - `unitFor(Integer lookbackDays)` → `String`
  - `keyOf(Date d, String unit)` → `String`
  - `labelOf(Date d, String unit)` → `String`
  - `between(Date from0, Date to0, String unit)` → `Integer`
  - `thinCountFor(String unit)` → `Integer`
  - `startOfWeek(Date d)` → `Date` (Monday of `d`'s week)

- [ ] **Step 1: Write the failing test**

Create `force-app/main/default/classes/LaneTrendBucketsTest.cls`:

```apex
/**
 * Spec W1 and W3. The keys are the part that can lie: they are sorted as strings to put the
 * chart in chronological order, so a key that sorts differently than it reads puts a month in
 * the wrong place with nothing red.
 */
@IsTest
private class LaneTrendBucketsTest {
  @IsTest
  static void mapsEachWindowToTheUnitThatKeepsItLegible() {
    System.assertEquals(LaneTrendBuckets.DAY, LaneTrendBuckets.unitFor(7));
    System.assertEquals(LaneTrendBuckets.DAY, LaneTrendBuckets.unitFor(14));
    System.assertEquals(LaneTrendBuckets.DAY, LaneTrendBuckets.unitFor(30));
    System.assertEquals(LaneTrendBuckets.WEEK, LaneTrendBuckets.unitFor(60));
    System.assertEquals(LaneTrendBuckets.WEEK, LaneTrendBuckets.unitFor(90));
    System.assertEquals(LaneTrendBuckets.MONTH, LaneTrendBuckets.unitFor(182));
    System.assertEquals(LaneTrendBuckets.MONTH, LaneTrendBuckets.unitFor(365));
    System.assertEquals(LaneTrendBuckets.MONTH, LaneTrendBuckets.unitFor(730));
    System.assertEquals(LaneTrendBuckets.MONTH, LaneTrendBuckets.unitFor(1095));
  }

  @IsTest
  static void everyUnitsKeySortsAsStringExactlyAsItSortsInTime() {
    // The chart's order comes from keys.sort() on strings, so a key whose lexical order differs
    // from its chronological order silently reorders the axis.
    List<String> dayKeys = new List<String>{
      LaneTrendBuckets.keyOf(
        Date.newInstance(2026, 1, 9),
        LaneTrendBuckets.DAY
      ),
      LaneTrendBuckets.keyOf(
        Date.newInstance(2025, 12, 31),
        LaneTrendBuckets.DAY
      ),
      LaneTrendBuckets.keyOf(
        Date.newInstance(2026, 1, 10),
        LaneTrendBuckets.DAY
      )
    };
    dayKeys.sort();
    System.assertEquals(
      new List<String>{ '2025-12-31', '2026-01-09', '2026-01-10' },
      dayKeys,
      'a day key must zero-pad both month and day, or the 9th sorts after the 10th'
    );

    List<String> monthKeys = new List<String>{
      LaneTrendBuckets.keyOf(
        Date.newInstance(2026, 10, 5),
        LaneTrendBuckets.MONTH
      ),
      LaneTrendBuckets.keyOf(
        Date.newInstance(2026, 2, 5),
        LaneTrendBuckets.MONTH
      )
    };
    monthKeys.sort();
    System.assertEquals(
      new List<String>{ '2026-02', '2026-10' },
      monthKeys,
      'unpadded, October would sort before February'
    );
  }

  @IsTest
  static void aWeekKeyIsItsMondayWhateverTheRunningUsersLocale() {
    // Apex Date.toStartOfWeek() follows the running user's locale, so Sunday-first users would
    // get a different bucket for the same rate. The anchor arithmetic here does not.
    Date wed = Date.newInstance(2026, 9, 16);
    Date sun = Date.newInstance(2026, 9, 20);
    Date mon = Date.newInstance(2026, 9, 14);
    System.assertEquals(mon, LaneTrendBuckets.startOfWeek(wed));
    System.assertEquals(
      mon,
      LaneTrendBuckets.startOfWeek(sun),
      'Sunday belongs to the week that started the Monday before it'
    );
    System.assertEquals(
      '2026-09-14',
      LaneTrendBuckets.keyOf(sun, LaneTrendBuckets.WEEK)
    );
  }

  @IsTest
  static void countsTheDistanceBetweenTwoDatesInEachUnit() {
    Date from0 = Date.newInstance(2025, 11, 1);
    System.assertEquals(
      2,
      LaneTrendBuckets.between(
        from0,
        Date.newInstance(2026, 1, 1),
        LaneTrendBuckets.MONTH
      ),
      'a lost *12 year term would give -10 here'
    );
    System.assertEquals(
      61,
      LaneTrendBuckets.between(
        from0,
        Date.newInstance(2026, 1, 1),
        LaneTrendBuckets.DAY
      )
    );
    System.assertEquals(
      2,
      LaneTrendBuckets.between(
        Date.newInstance(2026, 9, 14),
        Date.newInstance(2026, 9, 30),
        LaneTrendBuckets.WEEK
      ),
      'Mondays 14th, 21st, 28th: the 30th falls in the third week, index 2'
    );
  }

  @IsTest
  static void theThinThresholdScalesWithTheBucket() {
    System.assertEquals(
      3,
      LaneTrendBuckets.thinCountFor(LaneTrendBuckets.MONTH)
    );
    System.assertEquals(
      2,
      LaneTrendBuckets.thinCountFor(LaneTrendBuckets.WEEK)
    );
    System.assertEquals(
      1,
      LaneTrendBuckets.thinCountFor(LaneTrendBuckets.DAY),
      'W3: a day needs one rate, so no daily bucket is ever thin'
    );
  }
}
```

- [ ] **Step 2: Write a stub that compiles**

Create `force-app/main/default/classes/LaneTrendBuckets.cls`:

```apex
/**
 * Spec W1: which unit a window buckets by, and how that unit keys, labels, counts and thresholds.
 *
 * Split out of LaneTrendService rather than added to it: that class sits at 39 against a PMD class
 * cap that fires at 40, and three-way unit dispatch would trip it. The project's ruling is to split
 * a cohesive family out rather than suppress, as LaneSearchFilters, MarketTestFilter,
 * LaneTrendQueries, LaneTrendSummary and LaneTrendScope each already did.
 *
 * Every key is lexically sortable, because the chart's chronological order comes from sorting the
 * keys as strings. A key that sorts differently than it reads reorders the axis with nothing red.
 */
public with sharing class LaneTrendBuckets {
  public static final String DAY = 'day';
  public static final String WEEK = 'week';
  public static final String MONTH = 'month';

  public static String unitFor(Integer lookbackDays) {
    return MONTH;
  }

  public static String keyOf(Date d, String unit) {
    return '';
  }

  public static String labelOf(Date d, String unit) {
    return '';
  }

  public static Integer between(Date from0, Date to0, String unit) {
    return 0;
  }

  public static Integer thinCountFor(String unit) {
    return 3;
  }

  public static Date startOfWeek(Date d) {
    return d;
  }
}
```

Both new classes need a `-meta.xml`:

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<ApexClass xmlns="http://soap.sforce.com/2006/04/metadata">
    <apiVersion>64.0</apiVersion>
    <status>Active</status>
</ApexClass>
```

- [ ] **Step 3: Deploy and watch the assertions fail**

```bash
sf project deploy start \
  --source-dir force-app/main/default/classes/LaneTrendBuckets.cls \
  --source-dir force-app/main/default/classes/LaneTrendBucketsTest.cls \
  --target-org sandbox --test-level NoTestRun --wait 20
sf apex run test --tests LaneTrendBucketsTest --target-org sandbox --json
```

Poll with `sf data query --target-org sandbox --use-tooling-api --query "SELECT Status FROM ApexTestRunResult WHERE AsyncApexJobId='<id>'"` until Status is not `Processing`, then read per-method rows from `ApexTestResult` on the same `AsyncApexJobId`.

Expected: all five methods FAIL on assertions — `unitFor(7)` returns `month`, `keyOf` returns empty, and so on. A compile error instead means the stub is wrong; fix it and re-run until the **assertions** are what fail.

- [ ] **Step 4: Implement**

Replace the stub bodies:

```apex
  // 1900-01-01 was a Monday, so the remainder of the day count from it is the number of days
  // since that week's Monday. Date.toStartOfWeek() is not used: it follows the running user's
  // locale, so a Sunday-first user would bucket the same rate into a different week.
  private static final Date WEEK_ANCHOR = Date.newInstance(1900, 1, 1);

  private static final List<String> MONTH_LABELS = new List<String>{
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  };

  /** Day up to a month, week up to a quarter, month beyond: every window lands near 7 to 37 points. */
  public static String unitFor(Integer lookbackDays) {
    if (lookbackDays == null || lookbackDays <= 31) {
      return DAY;
    }
    return lookbackDays <= 92 ? WEEK : MONTH;
  }

  public static Date startOfWeek(Date d) {
    return d.addDays(-Math.mod(WEEK_ANCHOR.daysBetween(d), 7));
  }

  /** The bucket a date belongs to, as a string that sorts chronologically. */
  public static String keyOf(Date d, String unit) {
    if (unit == MONTH) {
      return String.valueOf(d.year()) + '-' + pad(d.month());
    }
    Date start = unit == WEEK ? startOfWeek(d) : d;
    return String.valueOf(start.year()) +
      '-' +
      pad(start.month()) +
      '-' +
      pad(start.day());
  }

  /** Short enough to sit under a 15-unit axis slot; the component adds the year where it changes. */
  public static String labelOf(Date d, String unit) {
    if (unit == MONTH) {
      return MONTH_LABELS[d.month() - 1];
    }
    Date start = unit == WEEK ? startOfWeek(d) : d;
    return String.valueOf(start.day()) + ' ' + MONTH_LABELS[start.month() - 1];
  }

  public static Integer between(Date from0, Date to0, String unit) {
    if (unit == MONTH) {
      return (to0.year() - from0.year()) * 12 + (to0.month() - from0.month());
    }
    if (unit == WEEK) {
      return startOfWeek(from0).daysBetween(startOfWeek(to0)) / 7;
    }
    return from0.daysBetween(to0);
  }

  /** W3. A day needs one rate, so no daily bucket is ever thin - at that zoom the reader is
   * looking at individual activity rather than a market median. */
  public static Integer thinCountFor(String unit) {
    if (unit == DAY) {
      return 1;
    }
    return unit == WEEK ? 2 : 3;
  }

  private static String pad(Integer n) {
    return (n < 10 ? '0' : '') + String.valueOf(n);
  }
```

- [ ] **Step 5: Deploy and verify green**

Same two commands as Step 3. Expected: 5 methods, 0 failing.

- [ ] **Step 6: Check PMD and commit**

```bash
npm run pmd
npx prettier --write "force-app/main/default/classes/LaneTrendBuckets*.cls"
git add force-app/main/default/classes/LaneTrendBuckets.cls force-app/main/default/classes/LaneTrendBuckets.cls-meta.xml \
        force-app/main/default/classes/LaneTrendBucketsTest.cls force-app/main/default/classes/LaneTrendBucketsTest.cls-meta.xml
git commit -m "Give the trend a calendar that knows more units than the month

A window of one week cannot be bucketed by month: it is one bucket, and a chart
of one point is not a trend. So the bucket has to follow the window, and the
thing that knows how to key, label, count and threshold a day, a week or a month
is one cohesive family - which is why it is its own class rather than three more
branches inside a service already sitting at PMD's cap.

Every key sorts as a string exactly as it sorts in time, because that string
sort is what puts the chart in order. Unpadded, October would sort before
February and the ninth after the tenth.

A week is anchored to the Monday of 1900-01-01 rather than to
Date.toStartOfWeek(), which follows the running user's locale - a Sunday-first
user would otherwise bucket the same rate into a different week than a
Monday-first one, on the same data."
```

Do **not** add these classes to `manifest/package.xml` — Task 6 owns that file.

---

### Task 2: Move bucketing into the calendar, and rename the months out of the DTO

**Files:**

- Modify: `force-app/main/default/classes/LaneTrendBuckets.cls`
- Modify: `force-app/main/default/classes/LaneTrend.cls`
- Modify: `force-app/main/default/classes/LaneTrendService.cls`
- Modify: `force-app/main/default/classes/LaneTrendServiceTest.cls`
- Modify: `force-app/main/default/lwc/laneTrendChart/laneTrendChart.js`
- Modify: `force-app/main/default/lwc/laneTrendChart/__tests__/laneTrendChart.test.js`

**Interfaces:**

- Consumes: everything Task 1 produced; `LaneTrendSummary.isUsable(LaneTrendService.Sample)`, `SplitLaneService.median(List<Decimal>)`.
- Produces:
  - `LaneTrendBuckets.bucket(List<LaneTrendService.Sample> samples, Date windowStart, String unit)` → `List<LaneTrend.Point>`
  - `LaneTrend.bucketSpan` (was `monthSpan`), `LaneTrend.bucketUnit` (new, `String`)
  - `LaneTrend.Point.bucketKey` (was `monthKey`), `LaneTrend.Point.bucketIndex` (was `monthIndex`)

This task is a **rename plus a move**, and the rename crosses Apex and JavaScript in one interface. Do it in one commit: a half-applied rename leaves the component reading a field Apex no longer sends, and nothing would be red because Jest mocks Apex.

- [ ] **Step 1: Record the green baseline**

```bash
npx jest
sf apex run test --tests LaneTrendServiceTest --tests LaneTrendBucketsTest --target-org sandbox --json
```

Write down the counts: Jest 46 suites / 456 tests, `LaneTrendServiceTest` 20, `LaneTrendBucketsTest` 5. These must hold at the end — this task changes names, not behaviour.

- [ ] **Step 2: Move `bucket` and its helpers**

Cut `bucket`, `leastOf` and `greatestOf` from `LaneTrendService.cls` into `LaneTrendBuckets.cls`, and delete `monthKeyOf`, `monthsBetween`, `MONTH_LABELS` and `THIN_COUNT` from the service — Task 1 already has their replacements. The moved `bucket` gains a unit and uses the calendar:

```apex
  /**
   * One point per bucket that has rates, in order, with the count, median, min and max of that
   * bucket's amounts. Buckets with no rates are absent (gaps, not zeros), and bucketIndex carries
   * the distance from the window start so the chart can draw the absence.
   */
  public static List<LaneTrend.Point> bucket(
    List<LaneTrendService.Sample> samples,
    Date windowStart,
    String unit
  ) {
    Map<String, List<Decimal>> byBucket = new Map<String, List<Decimal>>();
    Map<String, Date> startOfBucket = new Map<String, Date>();
    for (LaneTrendService.Sample sample : samples) {
      if (!LaneTrendSummary.isUsable(sample)) {
        continue;
      }
      String key = keyOf(sample.sampleDate, unit);
      if (!byBucket.containsKey(key)) {
        byBucket.put(key, new List<Decimal>());
        startOfBucket.put(key, startOf(sample.sampleDate, unit));
      }
      byBucket.get(key).add(sample.amount);
    }

    List<String> keys = new List<String>(byBucket.keySet());
    keys.sort();

    Integer thinAt = thinCountFor(unit);
    List<LaneTrend.Point> points = new List<LaneTrend.Point>();
    for (String key : keys) {
      List<Decimal> amounts = byBucket.get(key);
      Date bucketStart = startOfBucket.get(key);
      LaneTrend.Point point = new LaneTrend.Point();
      point.bucketKey = key;
      point.label = labelOf(bucketStart, unit);
      point.bucketIndex = between(windowStart, bucketStart, unit);
      point.count = amounts.size();
      point.median = SplitLaneService.median(amounts);
      point.minimum = leastOf(amounts);
      point.maximum = greatestOf(amounts);
      point.thin = amounts.size() < thinAt;
      points.add(point);
    }
    return points;
  }

  /** The first moment of the bucket a date falls in: its day, its week's Monday, or its 1st. */
  public static Date startOf(Date d, String unit) {
    if (unit == MONTH) {
      return Date.newInstance(d.year(), d.month(), 1);
    }
    return unit == WEEK ? startOfWeek(d) : d;
  }
```

`LaneTrendService.trendFor` now calls `LaneTrendBuckets.bucket(plotted, windowStartBucket, unit)`. Leave the unit hard-coded to `LaneTrendBuckets.MONTH` for this task — Task 3 derives it. Renaming and deriving in one commit makes a failure ambiguous.

- [ ] **Step 3: Rename the DTO fields**

In `LaneTrend.cls`: `monthSpan` → `bucketSpan`, `Point.monthKey` → `bucketKey`, `Point.monthIndex` → `bucketIndex`, and add:

```apex
  /** 'day', 'week' or 'month' - what one point covers (spec W1). The component reads this to
   * name its counts, and to decide how to label the axis. */
  @AuraEnabled
  public String bucketUnit;
```

Update every comment that says "month" about these fields. A field named for months that holds days is the defect this feature has corrected eight times in comments, test names and a help page; do not add a ninth.

- [ ] **Step 4: Follow the rename into the component**

In `laneTrendChart.js`, `monthSpan` → `bucketSpan` and `monthIndex` → `bucketIndex` in `hasValidSpan`, `geometry` and their comments. In the test file, the `trend()` and `point()` factories rename the same fields. Nothing else changes yet.

- [ ] **Step 5: Verify nothing moved but names**

```bash
npx jest
npm run pmd
sf project deploy start --source-dir force-app/main/default/classes --target-org sandbox --test-level NoTestRun --wait 20
sf apex run test --tests LaneTrendServiceTest --tests LaneTrendBucketsTest --tests LaneTrendControllerTest --target-org sandbox --json
```

Expected: the same counts as Step 1, PMD 0, and `LaneTrendService` now **below** 39 since it lost `bucket`. Report its new number — Task 3 needs the headroom.

Grep for stragglers before committing: `grep -rn "monthSpan\|monthKey\|monthIndex" force-app/` must return nothing.

- [ ] **Step 6: Commit**

```bash
npx prettier --write "force-app/main/default/classes/LaneTrend*.cls" "force-app/main/default/lwc/laneTrendChart/**"
git add force-app/main/default/classes/LaneTrend.cls force-app/main/default/classes/LaneTrendService.cls \
        force-app/main/default/classes/LaneTrendBuckets.cls force-app/main/default/classes/LaneTrendServiceTest.cls \
        force-app/main/default/lwc/laneTrendChart
git commit -m "Stop calling a bucket a month, and move the bucketing to the calendar

The fields were named when every bucket was a month. They are about to hold days
and weeks, and a field whose name states something its value contradicts is the
defect this feature has already corrected eight times over in comments, test
names and a help page. So monthSpan, monthKey and monthIndex become bucketSpan,
bucketKey and bucketIndex, and the response now says which unit it used.

The bucketing itself moves in beside the keys and labels it varies by. That also
takes LaneTrendService back off PMD's class cap, which is what lets the next
change add the unit derivation without another split.

Names and a move only: the same tests pass in the same numbers, which is the
proof."
```

---

### Task 3: Derive the unit, and raise the cap

**Files:**

- Modify: `force-app/main/default/classes/LaneTrendService.cls`
- Test: `force-app/main/default/classes/LaneTrendServiceTest.cls`

**Interfaces:**

- Consumes: `LaneTrendBuckets.unitFor`, `.startOf`, `.between`, `.bucket`.
- Produces: `trendFor` sets `trend.bucketUnit` and buckets by it; `LaneTrendService.ROW_CAP` = `25000`.

- [ ] **Step 1: Write the failing tests**

Append to `LaneTrendServiceTest.cls`. Use `Test.setCreatedDate(id, datetime)` to place rows — it is the supported way to backdate a record in a test, and both sources bucket on `CreatedDate`.

```apex
  /**
   * W1: the unit follows the window, and the response says which it used. Without this the caption
   * would name a count of "months" that were days.
   */
  @IsTest
  static void aShortWindowBucketsByDayAndSaysSo() {
    LaneTrendFixture f = LaneTrendFixture.withQuotes(3);
    LaneSearchRequest req = f.request();
    req.lookbackDays = 7;

    Test.startTest();
    LaneTrend trend = LaneTrendService.trendFor(req);
    Test.stopTest();

    System.assertEquals(
      LaneTrendBuckets.DAY,
      trend.bucketUnit,
      'a one-week window cannot be bucketed by month: it would be one point'
    );
  }

  @IsTest
  static void aLongWindowStillBucketsByMonth() {
    LaneTrendFixture f = LaneTrendFixture.withQuotes(3);
    LaneSearchRequest req = f.request();
    req.lookbackDays = 365;

    Test.startTest();
    LaneTrend trend = LaneTrendService.trendFor(req);
    Test.stopTest();

    System.assertEquals(LaneTrendBuckets.MONTH, trend.bucketUnit);
  }

  /** W5: measured, not guessed - 11,499 rows cost 26% of heap, so the old cap was the only thing
   * stopping a three-year window. */
  @IsTest
  static void theRowCapIsTwentyFiveThousand() {
    System.assertEquals(25000, LaneTrendService.ROW_CAP);
  }
```

- [ ] **Step 2: Deploy and watch them fail**

Expected: `aShortWindowBucketsByDayAndSaysSo` fails with `Expected: day, Actual: null` (nothing sets `bucketUnit` yet), and `theRowCapIsTwentyFiveThousand` fails with `Expected: 25000, Actual: 10000`. `aLongWindowStillBucketsByMonth` will also fail on null, which is expected — it is the pair that proves the derivation varies rather than returning one constant.

- [ ] **Step 3: Implement**

In `LaneTrendService.trendFor`, replace the month-specific window arithmetic:

```apex
    String unit = LaneTrendBuckets.unitFor(req.lookbackDays);
    trend.bucketUnit = unit;
    Date windowStart = Date.today().addDays(-req.lookbackDays);
    Date windowStartBucket = LaneTrendBuckets.startOf(windowStart, unit);
    trend.bucketSpan =
      LaneTrendBuckets.between(windowStartBucket, Date.today(), unit) + 1;
```

and pass the unit through to `LaneTrendBuckets.bucket(plotted, windowStartBucket, unit)`. Change `ROW_CAP` to `25000` and update its comment to cite the measurement:

```apex
  /**
   * W5: 25,000 per side, on a measurement. A three-year read of the widest search in the org -
   * 11,499 rows - cost 1,554,051 bytes of the 6,000,000 heap and 11,499 of 50,000 query rows, so
   * the old cap of 10,000, not the platform, is what stopped a three-year window. 25,000 covers
   * five years of that search with about twice the margin on both limits.
   */
  public static final Integer ROW_CAP = 25000;
```

- [ ] **Step 4: Deploy, verify green, check PMD**

```bash
sf project deploy start --source-dir force-app/main/default/classes --target-org sandbox --test-level NoTestRun --wait 20
sf apex run test --tests LaneTrendServiceTest --tests LaneTrendBucketsTest --target-org sandbox --json
npm run pmd
```

Expected: 23 + 5 methods, 0 failing, PMD 0. If `LaneTrendService` is back at 40, split rather than suppress and say so in your report.

- [ ] **Step 5: Commit**

```bash
npx prettier --write "force-app/main/default/classes/LaneTrend*.cls"
git add force-app/main/default/classes/LaneTrendService.cls force-app/main/default/classes/LaneTrendServiceTest.cls
git commit -m "Let the window choose its own bucket, and lift a cap that was too low

Apex derives the unit and states it on the response rather than the component
asking for one. A unit chosen in two places is a unit two places can disagree
about, which is how the market-test filter came to mean two different things on
one control.

The cap goes from ten thousand to twenty-five thousand on a measurement: a
three-year read of the widest search in the org costs 1,554,051 bytes of the six
million heap and 11,499 of fifty thousand query rows. The old cap, not the
platform, is what stopped three years."
```

---

### Task 4: Nine windows, and a caption that names its unit

**Files:**

- Modify: `force-app/main/default/lwc/laneTrendChart/laneTrendChart.js`
- Test: `force-app/main/default/lwc/laneTrendChart/__tests__/laneTrendChart.test.js`

**Interfaces:**

- Consumes: `trend.bucketUnit` from Task 3.
- Produces: a nine-entry `WINDOWS`; the summary sentence reads the unit.

Pure Jest — runs locally in seconds, no org.

- [ ] **Step 1: Write the failing tests**

```javascript
it("offers all nine windows, shortest first", async () => {
  const el = await open(trend());
  const keys = [...el.shadowRoot.querySelectorAll("[data-window]")].map(
    (b) => b.dataset.window
  );
  expect(keys).toEqual(["1w", "2w", "1m", "2m", "3m", "6m", "1y", "2y", "3y"]);
});

it("sends each window its own lookback", async () => {
  const el = await open(trend());
  const sent = async (key) => {
    getTrend.mockClear();
    el.shadowRoot
      .querySelector(`[data-id="window-${key}"]`)
      .dispatchEvent(new CustomEvent("click"));
    await settle();
    return JSON.parse(getTrend.mock.calls[0][0].requestJson).lookbackDays;
  };
  expect(await sent("1w")).toBe(7);
  expect(await sent("3m")).toBe(90);
  expect(await sent("3y")).toBe(1095);
});

it("names the unit in the caption, so a count of days is not read as months", async () => {
  const el = await open(
    trend({
      bucketUnit: "day",
      points: [point(), point({ bucketKey: "2026-01-02", bucketIndex: 1 })]
    })
  );
  expect(
    el.shadowRoot.querySelector('[data-id="trend-summary"]').textContent
  ).toContain("2 days");
});
```

- [ ] **Step 2: Run to verify they fail**

```bash
npx jest force-app/main/default/lwc/laneTrendChart
```

Expected: the first fails with two keys instead of nine; the third fails because the caption says "2 months".

- [ ] **Step 3: Implement**

```javascript
const WINDOWS = [
  { key: "1w", label: "1 week", days: 7 },
  { key: "2w", label: "2 weeks", days: 14 },
  { key: "1m", label: "1 month", days: 30 },
  { key: "2m", label: "2 months", days: 60 },
  { key: "3m", label: "3 months", days: 90 },
  { key: "6m", label: "6 months", days: 182 },
  { key: "1y", label: "1 year", days: 365 },
  { key: "2y", label: "2 years", days: 730 },
  { key: "3y", label: "3 years", days: 1095 }
];

// W8: the caption counts buckets that carry rates (Ruling 22) and now says which kind they are.
const UNIT_NOUN = { day: "days", week: "weeks", month: "months" };
```

and in the `summary` getter, replace the hard-coded `months` with `UNIT_NOUN[t.bucketUnit] || "buckets"`.

- [ ] **Step 4: Verify and commit**

```bash
npx jest
npm run lint
npx prettier --write "force-app/main/default/lwc/laneTrendChart/**"
git add force-app/main/default/lwc/laneTrendChart
git commit -m "Offer nine windows, from a week to three years

The shortest three are bucketed by day, the next two by week and the rest by
month, so every one of them lands near seven to thirty-seven points rather than
one. The caption says which unit it counted: a chart of thirty days that
captioned itself thirty months would be the same false statement the fields were
just renamed to avoid.

On a lane at half a rate a day the shortest windows will often show very little.
Adaptive bucketing makes them legible, not populated - that is the honest limit
and the help page says so."
```

---

### Task 5: Thin the axis labels, and show the year where it changes

**Files:**

- Modify: `force-app/main/default/lwc/laneTrendChart/laneTrendChart.js`
- Test: `force-app/main/default/lwc/laneTrendChart/__tests__/laneTrendChart.test.js`

**Interfaces:**

- Consumes: `geometry`, `Point.bucketKey` (whose first four characters are the year, for every unit).
- Produces: `geometry.axis` carries at most ~12 entries.

W4: 37 monthly labels at three years and 30 daily labels at one month both collide at 11px in a 572-unit plot.

- [ ] **Step 1: Write the failing tests**

```javascript
const manyPoints = (n) =>
  Array.from({ length: n }, (_, i) =>
    point({
      bucketKey: `2026-${String((i % 12) + 1).padStart(2, "0")}`,
      bucketIndex: i,
      label: "Jan"
    })
  );

it("never draws more than about a dozen axis labels, however many buckets there are", async () => {
  const el = await open(
    trend({ points: manyPoints(37), bucketSpan: 37, bucketUnit: "month" })
  );
  const labels = el.shadowRoot.querySelectorAll('[data-id="axis-label"]');
  expect(labels.length).toBeGreaterThan(0);
  expect(labels.length).toBeLessThanOrEqual(12);
});

it("shows the year on the first label of each year, so three Januaries are distinguishable", async () => {
  const el = await open(
    trend({
      bucketUnit: "month",
      bucketSpan: 14,
      points: [
        point({ bucketKey: "2025-12", bucketIndex: 0, label: "Dec" }),
        point({ bucketKey: "2026-01", bucketIndex: 1, label: "Jan" })
      ]
    })
  );
  const texts = [
    ...el.shadowRoot.querySelectorAll('[data-id="axis-label"]')
  ].map((t) => t.textContent.trim());
  expect(texts.some((t) => t.includes("2026"))).toBe(true);
});
```

- [ ] **Step 2: Run to verify they fail**

Expected: the first fails with 37 labels; the second fails because no label contains a year.

- [ ] **Step 3: Implement**

In the `geometry` getter, replace the axis mapping. Give every `<text>` in the template `data-id="axis-label"`.

```javascript
const MAX_AXIS_LABELS = 12;

// W4: 37 monthly labels at three years, or 30 daily ones at a month, collide at 11px in a
// 572-unit plot. Show at most a dozen, evenly spaced, and carry the year on the first label
// of each year so three Januaries are not indistinguishable. bucketKey starts with the year
// for every unit, which is what makes this work without a second field.
const step = Math.ceil(points.length / MAX_AXIS_LABELS);
let lastYear = null;
const axis = [];
points.forEach((p, i) => {
  if (i % step !== 0) {
    return;
  }
  const year = p.bucketKey.slice(0, 4);
  axis.push({
    key: p.bucketKey,
    x: x(p.bucketIndex),
    label: year === lastYear ? p.label : `${p.label} ${year}`
  });
  lastYear = year;
});
```

and return `axis` in place of the previous mapping.

- [ ] **Step 4: Verify and commit**

```bash
npx jest
npm run lint
npx prettier --write "force-app/main/default/lwc/laneTrendChart/**"
git add force-app/main/default/lwc/laneTrendChart
git commit -m "Thin the axis, and say which year a January belongs to

Thirty-seven labels across a 572-unit plot puts them fifteen units apart at
eleven-pixel type, and month-only labels repeat, so a three-year chart showed
Jan three times with nothing to tell them apart. At most a dozen labels now,
evenly spaced, with the year carried on the first label of each year.

The alternative raised was numbering the buckets so a smaller number meant
nearer today. It was rejected in the spec: it turns a question about November
into arithmetic, hands a screen reader a bare number instead of a month, and
does not fix crowding anyway."
```

---

### Task 6: The paperwork

**Files:**

- Modify: `manifest/package.xml`, `README.md`, `docs/help/en/lb-trend.md`, `docs/help/fr/lb-trend.md`
- Modify: `.github/workflows/ci.yml`

- [ ] **Step 1: Manifest and CI roster**

Add `LaneTrendBuckets` and `LaneTrendBucketsTest` to the `ApexClass` block of `manifest/package.xml`, alphabetically — they sort **before** `LaneTrendController`. Add `LaneTrendBucketsTest` to the `--tests` list in `.github/workflows/ci.yml` and to the four README roster places (`grep -n "LaneTrendServiceTest" README.md`).

Verify with a loop that every class on disk has exactly one manifest entry:

```bash
for c in $(ls force-app/main/default/classes/LaneTrend*.cls | sed 's|.*/||;s|\.cls||'); do
  printf "%-26s " "$c"; grep -c "<members>$c</members>" manifest/package.xml
done
```

Every line must read `1`. A class on disk and absent from the manifest passes every local gate and then silently vanishes from a manifest-based deploy — seven of this feature's classes were in that state once already.

- [ ] **Step 2: Help pages**

Update `docs/help/en/lb-trend.md` and `docs/help/fr/lb-trend.md` together — **both, in the same commit.** A previous wave corrected the English page and left the French one asserting the retired behaviour, and `npm run help:check` did not catch it because it verifies markdown against HTML **per language**: two mutually consistent French files that are both wrong pass cleanly.

Cover: the nine windows; that short windows group by day, middling ones by week and long ones by month; that a hollow point means too few rates _for that bucket size_ — three for a month, two for a week — and that at day buckets nothing is marked thin because a single rate is all a day has; and that on a quiet lane the shortest windows will show very little.

Keep UI labels in English on the French page, matching that file's existing convention.

```bash
npm run help:build
npm run help:check
```

- [ ] **Step 3: README row**

Update the lane-trend row to say the bucket follows the window. Edit it deliberately — a blind find-and-replace on a class name once injected four names into an unrelated sentence in this file. Check `git diff README.md` and confirm the churn beyond your edit is only prettier re-padding the table.

- [ ] **Step 4: Full verification and commit**

```bash
npm run pmd && npx jest && npm run lint && npm run help:check
sf project deploy start --manifest manifest/package.xml --target-org sandbox --test-level NoTestRun --wait 30
sf apex run test --tests LaneTrendBucketsTest --tests LaneTrendServiceTest --tests LaneTrendControllerTest --tests LaneTrendQueriesTest --target-org sandbox --json
```

Then deploy the component and page so the feature is actually visible, and **look at it**:

```bash
sf project deploy start --target-org sandbox --test-level NoTestRun --wait 20 \
  --source-dir force-app/main/default/lwc/laneTrendChart \
  --source-dir force-app/main/default/staticresources/helpCenter
```

Open Lane Benchmark, run a lane, and step through the windows. Confirm the axis is legible at 1 month and at 3 years, that the caption names the right unit, and that nine buttons do not break the card header. Report what you saw. This feature once passed every automated gate while rendering nothing on the page, because no one had loaded it.

```bash
git add -A
git commit -m "Record the bucket calendar, and tell pricers what the windows do

Both help pages in one commit, deliberately: help:check verifies markdown
against HTML per language, so a correction made in English and skipped in French
passes cleanly with the French page asserting the opposite of the code. That has
happened once on this feature already."
```

---

## Self-Review

**Spec coverage:**

| Spec                                                              | Task                                                                                                                                                                                       |
| ----------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| W1 — bucket follows window, Apex decides, unit on the response    | 1 (`unitFor`), 3 (derivation + `bucketUnit`)                                                                                                                                               |
| W2 — nine windows                                                 | 4                                                                                                                                                                                          |
| W3 — thin scales per unit; no daily bucket ever thin              | 1 (`thinCountFor`), 2 (`bucket` uses it)                                                                                                                                                   |
| W4 — ≤12 axis labels, year where it changes                       | 5                                                                                                                                                                                          |
| W5 — `ROW_CAP` 10,000 → 25,000                                    | 3                                                                                                                                                                                          |
| W6 — truncation loses the oldest                                  | **No task.** W5 keeps real searches under the cap, so nothing changes; the spec records the hazard for whoever raises a window beyond five years. Called out rather than silently dropped. |
| W7 — rename `monthSpan`/`monthKey`/`monthIndex`, add `bucketUnit` | 2                                                                                                                                                                                          |
| W8 — caption names the unit                                       | 4                                                                                                                                                                                          |
| §3 — nine buttons may wrap                                        | 6 (browser check)                                                                                                                                                                          |

**Placeholder scan:** none. Two steps say "read the existing file and follow it" (the README roster, the French help convention) rather than inventing structure, and each names the file and the thing to copy.

**Type consistency:** `LaneTrendBuckets` members are `DAY`/`WEEK`/`MONTH`, `unitFor`, `keyOf`, `labelOf`, `between`, `thinCountFor`, `startOfWeek`, `startOf`, `bucket` — spelled identically in Tasks 1, 2 and 3. `bucketSpan`/`bucketKey`/`bucketIndex`/`bucketUnit` are spelled identically in Tasks 2, 3, 4 and 5. `bucket()` takes `(samples, windowStart, unit)` in both the task that writes it and the task that calls it.

**One correction made during review:** Task 1 originally had `bucket()` in its interface block, but `bucket` needs `LaneTrendSummary.isUsable` and `SplitLaneService.median`, which makes it a move rather than a new function — it now belongs to Task 2, where the move is proven by unchanged test counts. Task 1 is the calendar only.
