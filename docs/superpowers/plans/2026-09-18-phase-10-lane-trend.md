# Phase 10 Lane Trend Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show a pricer how a lane's market moved over time, as a monthly median/min/max chart on the Lane Benchmark page.

**Architecture:** A new `LaneTrendController.getTrend(requestJson)` (`cacheable=true`) over a `without sharing` `LaneTrendService`. The service reuses the **existing** query builders' WHERE assembly so the trend matches exactly the rows a search of the same lane matches — including phase 12's market-test filter (D7) — but with a narrow SELECT of only date, amount and currency. A `SELECT COUNT()` guard runs first and caps the read at 10,000 rows. Monthly buckets, medians, min and max are computed in Apex; a new `laneTrendChart` LWC draws hand-rolled inline SVG.

**Tech Stack:** Salesforce Apex (API 64.0), Lightning Web Components, Jest (`sfdx-lwc-jest`), PMD 7.15.0, SLDS design tokens. No charting library — Salesforce will not load a CDN script and D4 refuses to vendor one.

**Spec:** `docs/superpowers/specs/2026-09-17-phase-10-lane-trend-design.md` (amended 2026-09-18; decisions D1–D7)

## Global Constraints

- **TDD is required.** Every behaviour change starts with a test that is watched failing. Apex cannot do a pure RED — a test referencing a missing method fails to _deploy_ — so write the test plus a minimal compiling stub, deploy, watch the **assertion** fail, then implement.
- **`npm run pmd` must stay at 0 violations.** Class-wide cyclomatic complexity cap is 40; the project ruling (recorded in `LaneSearchFilters` and `LaneSearchRequest`) is **split the family into its own class, never suppress**. The repo has zero `ApexSOQLInjection` and zero `CyclomaticComplexity` suppressions.
- **Dynamic SOQL goes through `Database.queryWithBinds(soql, binds, AccessLevel.SYSTEM_MODE)`**, never bare `Database.query` — PMD flags any concatenation inside the latter. `SYSTEM_MODE` because these are `without sharing` services and spec §6 says the trend adds no new access path.
- **Apex reserved identifiers:** `where`, `from`, `when`, `select`, `limit`, `group` cannot be variable or parameter names. `LaneSearchQueryBuilder` records this the hard way ("Brief called this parameter `where` … renamed to `conditions`").
- **Jest baseline is 45 suites / 432 tests, all passing.** Never let that number drop.
- **Prettier runs on commit** via husky + lint-staged over `{cls,html,js,json,md,xml,…}`. Run `npx prettier --write` on touched files before committing to avoid a reformat inside the commit.
- **New Apex classes need a `.cls-meta.xml`** with `<apiVersion>64.0</apiVersion>` and `<status>Active</status>`, **and** an entry in `manifest/package.xml`.
- **Currency:** one at a time (D6). Never mix `CurrencyIsoCode` values on one axis.
- **Thin month = fewer than 3 rates** (D5): drawn hollow, skipped by the trend line, and excluded from the change percentage.
- **Row cap = 10,000** (spec §4). Over it, still draw from what was read and set `truncated`.
- **No AI attribution trailers** in commit messages. Subject line is imperative mood; the body explains _why_, in prose.
- Deploy target for verification is `sf ... --target-org sandbox` (PostProduc). It is **shared with other developers** — never refresh it, and prefer `NoTestRun` deploys plus a separate `sf apex run test`.

---

## File Structure

**Create:**

- `force-app/main/default/classes/LaneTrend.cls` (+ `-meta.xml`) — the result DTO: `LaneTrend` and the inner `LaneTrend.Point`. Data only, no logic, so both Apex and the LWC have one shape to agree on.
- `force-app/main/default/classes/LaneTrendService.cls` (+ `-meta.xml`) — the work: resolve places, guard, read both sources, bucket by month.
- `force-app/main/default/classes/LaneTrendServiceTest.cls` (+ `-meta.xml`)
- `force-app/main/default/classes/LaneTrendController.cls` (+ `-meta.xml`) — the one `@AuraEnabled` surface.
- `force-app/main/default/classes/LaneTrendControllerTest.cls` (+ `-meta.xml`)
- `force-app/main/default/lwc/laneTrendChart/laneTrendChart.js`, `.html`, `.js-meta.xml`
- `force-app/main/default/lwc/laneTrendChart/__tests__/laneTrendChart.test.js`
- `docs/help/en/lb-trend.md`, `docs/help/fr/lb-trend.md`

**Modify:**

- `force-app/main/default/classes/LaneSearchQueryBuilder.cls` — expose the WHERE assembly for reuse with a narrow SELECT.
- `force-app/main/default/classes/BidSearchQueryBuilder.cls` — same.
- `force-app/main/default/classes/LaneSearchService.cls` — `loadPlaces` becomes `public` (precedent: `RfpLaneController.lanesByIds`, `.one`).
- `force-app/main/default/lwc/laneBenchmark/laneBenchmark.html` — insert the card directly after `<c-lane-benchmark-stats>`.
- `force-app/main/default/lwc/laneBenchmark/__tests__/laneBenchmark.test.js` — assert placement.
- `manifest/package.xml`, `.github/workflows/ci.yml`, `README.md`, `scripts/help/*` output.

**Why this split:** the DTO is separate from the service so the LWC contract is readable in one file. The bucketing is a pure static inside `LaneTrendService` with no SOQL, so Task 1 is testable with an in-memory fixture and no org data. The two query builders keep ownership of their own WHERE text — the trend borrows it rather than re-deriving it, which is what makes D2 and D7 true by construction instead of by vigilance.

---

### Task 1: The result shape and monthly bucketing (pure, no SOQL)

**Files:**

- Create: `force-app/main/default/classes/LaneTrend.cls` (+ `-meta.xml`)
- Create: `force-app/main/default/classes/LaneTrendService.cls` (+ `-meta.xml`)
- Test: `force-app/main/default/classes/LaneTrendServiceTest.cls` (+ `-meta.xml`)

**Interfaces:**

- Consumes: `SplitLaneService.median(List<Decimal>)` → `Decimal` (public, scale 2, null for empty; does not mutate the list).
- Produces:
  - `LaneTrend` with `@AuraEnabled` fields `points` (`List<LaneTrend.Point>`), `currencyIsoCode` (`String`), `lookbackDays` (`Integer`), `monthSpan` (`Integer`), `truncated` (`Boolean`), `totalRates` (`Integer`), `overallMedian` (`Decimal`), `changePct` (`Decimal`), `firstLabel` (`String`), `lastLabel` (`String`).
  - `LaneTrend.Point` with `@AuraEnabled` fields `monthKey` (`String`, `'2026-03'`), `label` (`String`, `'Mar'`), `monthIndex` (`Integer`, 0-based from window start), `count` (`Integer`), `median` (`Decimal`), `minimum` (`Decimal`), `maximum` (`Decimal`), `thin` (`Boolean`).
  - `LaneTrendService.Sample` — `public Date sampleDate; public Decimal amount;` with constructor `Sample(Date sampleDate, Decimal amount)`. Named `sampleDate` because `when` and `date` read badly and `when` is reserved.
  - `LaneTrendService.bucket(List<Sample> samples, Date windowStart, Integer monthSpan)` → `List<LaneTrend.Point>`, `@TestVisible private static`.
  - `LaneTrendService.THIN_COUNT` = `3`, `LaneTrendService.ROW_CAP` = `10000` (both `public static final Integer`).

- [ ] **Step 1: Write the failing test**

Create `force-app/main/default/classes/LaneTrendServiceTest.cls`:

```apex
/**
 * Phase 10. The bucketing is the part that can lie: a month whose median is wrong, or a month
 * invented where there were no rates, produces a chart a pricer will quote from.
 */
@IsTest
private class LaneTrendServiceTest {
  private static LaneTrendService.Sample s(String isoDate, Decimal amount) {
    return new LaneTrendService.Sample(Date.valueOf(isoDate), amount);
  }

  @IsTest
  static void bucketsByCalendarMonthAndComputesMedianMinMax() {
    List<LaneTrendService.Sample> samples = new List<LaneTrendService.Sample>{
      s('2026-01-05', 1000),
      s('2026-01-20', 2000),
      s('2026-01-28', 3000),
      s('2026-03-02', 500),
      s('2026-03-09', 700),
      s('2026-03-30', 900)
    };

    Test.startTest();
    List<LaneTrend.Point> points = LaneTrendService.bucket(
      samples,
      Date.newInstance(2026, 1, 1),
      3
    );
    Test.stopTest();

    System.assertEquals(
      2,
      points.size(),
      'February had no rates, so it is a gap and not a zero'
    );
    LaneTrend.Point jan = points[0];
    System.assertEquals('2026-01', jan.monthKey);
    System.assertEquals(0, jan.monthIndex);
    System.assertEquals(3, jan.count);
    System.assertEquals(2000, jan.median);
    System.assertEquals(1000, jan.minimum);
    System.assertEquals(3000, jan.maximum);
    System.assertEquals(false, jan.thin, 'three rates is not thin');

    LaneTrend.Point mar = points[1];
    System.assertEquals('2026-03', mar.monthKey);
    System.assertEquals(
      2,
      mar.monthIndex,
      'March sits two months after the window start, so the gap is visible on the axis'
    );
    System.assertEquals(700, mar.median);
  }

  @IsTest
  static void marksAMonthThinBelowThreeRates() {
    List<LaneTrendService.Sample> samples = new List<LaneTrendService.Sample>{
      s('2026-01-05', 1000),
      s('2026-01-06', 1200),
      s('2026-02-05', 9999)
    };

    Test.startTest();
    List<LaneTrend.Point> points = LaneTrendService.bucket(
      samples,
      Date.newInstance(2026, 1, 1),
      2
    );
    Test.stopTest();

    System.assertEquals(true, points[0].thin, 'two rates do not make a market');
    System.assertEquals(true, points[1].thin, 'nor does one');
  }

  @IsTest
  static void ignoresSamplesWithNoDateOrNoAmount() {
    List<LaneTrendService.Sample> samples = new List<LaneTrendService.Sample>{
      s('2026-01-05', 1000),
      new LaneTrendService.Sample(null, 5000),
      new LaneTrendService.Sample(Date.newInstance(2026, 1, 9), null)
    };

    Test.startTest();
    List<LaneTrend.Point> points = LaneTrendService.bucket(
      samples,
      Date.newInstance(2026, 1, 1),
      1
    );
    Test.stopTest();

    System.assertEquals(1, points.size());
    System.assertEquals(
      1,
      points[0].count,
      'a rate with no date cannot be placed on a time axis, and one with no amount is not a rate'
    );
  }

  @IsTest
  static void anEmptyListProducesNoPointsRatherThanThrowing() {
    Test.startTest();
    List<LaneTrend.Point> points = LaneTrendService.bucket(
      new List<LaneTrendService.Sample>(),
      Date.newInstance(2026, 1, 1),
      6
    );
    Test.stopTest();
    System.assertEquals(0, points.size());
  }
}
```

- [ ] **Step 2: Write the DTO and a stub that compiles but returns nothing**

Create `force-app/main/default/classes/LaneTrend.cls`:

```apex
/**
 * Phase 10: one lane's market over time, as the page receives it.
 *
 * Data only. Every number is computed in Apex (D1) so the component formats and never calculates,
 * which is how LaneSearchResult.Stats already works. A month with no rates is absent rather than
 * zero, and monthIndex is what lets the chart draw that absence as a gap on a fixed axis.
 */
public class LaneTrend {
  @AuraEnabled
  public List<Point> points = new List<Point>();
  @AuraEnabled
  public String currencyIsoCode;
  @AuraEnabled
  public Integer lookbackDays;
  /** Months spanned by the window, so the axis is the window and not just the months with data. */
  @AuraEnabled
  public Integer monthSpan;
  @AuraEnabled
  public Boolean truncated = false;
  @AuraEnabled
  public Integer totalRates = 0;
  @AuraEnabled
  public Decimal overallMedian;
  /** Change between the first and last months that are not thin; null when fewer than two qualify. */
  @AuraEnabled
  public Decimal changePct;
  @AuraEnabled
  public String firstLabel;
  @AuraEnabled
  public String lastLabel;

  public class Point {
    @AuraEnabled
    public String monthKey;
    @AuraEnabled
    public String label;
    @AuraEnabled
    public Integer monthIndex;
    @AuraEnabled
    public Integer count;
    @AuraEnabled
    public Decimal median;
    @AuraEnabled
    public Decimal minimum;
    @AuraEnabled
    public Decimal maximum;
    /** Fewer than LaneTrendService.THIN_COUNT rates: drawn hollow, skipped by the line (D5). */
    @AuraEnabled
    public Boolean thin;
  }
}
```

Create `force-app/main/default/classes/LaneTrendService.cls` with only what Task 1 needs:

```apex
/**
 * Phase 10: bucketing a lane's rates into months.
 *
 * without sharing, like LaneSearchService and BidSearchService, because spec §6 requires the trend
 * to read through the same system-mode path the search uses and to expose no row a search of the
 * same lane would not.
 */
public without sharing class LaneTrendService {
  /** Spec §4: a three-year window holds more than a 90-day search, and this is its own transaction. */
  public static final Integer ROW_CAP = 10000;
  /** D5: three quotes do not make a market. */
  public static final Integer THIN_COUNT = 3;

  private static final List<String> MONTH_LABELS = new List<String>{
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec'
  };

  /** One rate on a date, which is all a bucket needs from either source. */
  public class Sample {
    public Date sampleDate;
    public Decimal amount;

    public Sample(Date sampleDate, Decimal amount) {
      this.sampleDate = sampleDate;
      this.amount = amount;
    }
  }

  @TestVisible
  private static List<LaneTrend.Point> bucket(
    List<Sample> samples,
    Date windowStart,
    Integer monthSpan
  ) {
    return new List<LaneTrend.Point>();
  }
}
```

Both need a `-meta.xml`:

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<ApexClass xmlns="http://soap.sforce.com/2006/04/metadata">
    <apiVersion>64.0</apiVersion>
    <status>Active</status>
</ApexClass>
```

Write one for `LaneTrend.cls-meta.xml`, `LaneTrendService.cls-meta.xml` and `LaneTrendServiceTest.cls-meta.xml`.

- [ ] **Step 3: Deploy and run the test to verify it fails on the assertion**

```bash
sf project deploy start \
  --source-dir force-app/main/default/classes/LaneTrend.cls \
  --source-dir force-app/main/default/classes/LaneTrendService.cls \
  --source-dir force-app/main/default/classes/LaneTrendServiceTest.cls \
  --target-org sandbox --test-level NoTestRun --wait 20
sf apex run test --tests LaneTrendServiceTest --target-org sandbox --result-format human --wait 20
```

Expected: FAIL on `bucketsByCalendarMonthAndComputesMedianMinMax` with
`System.AssertException: Assertion Failed: February had no rates, so it is a gap and not a zero — Expected: 2, Actual: 0`.
A compile error instead means the stub or the DTO is wrong — fix that and re-run until the **assertion** is what fails.

- [ ] **Step 4: Implement the bucketing**

Replace the `bucket` stub in `LaneTrendService.cls`:

```apex
  /**
   * One point per month that has rates, in month order, with the count, median, min and max of that
   * month's amounts. Months with no rates are absent (spec §7: gaps, not zeros), and monthIndex
   * carries the distance from the window start so the chart can show the gap.
   *
   * A sample with no date cannot be placed on a time axis, and one with no amount is not a rate;
   * both are dropped rather than counted as zero, which would drag a median toward nothing.
   */
  @TestVisible
  private static List<LaneTrend.Point> bucket(
    List<Sample> samples,
    Date windowStart,
    Integer monthSpan
  ) {
    Map<String, List<Decimal>> byMonth = new Map<String, List<Decimal>>();
    Map<String, Date> firstOfMonth = new Map<String, Date>();
    for (Sample sample : samples) {
      if (sample == null || sample.sampleDate == null || sample.amount == null) {
        continue;
      }
      String key = monthKeyOf(sample.sampleDate);
      if (!byMonth.containsKey(key)) {
        byMonth.put(key, new List<Decimal>());
        firstOfMonth.put(
          key,
          Date.newInstance(sample.sampleDate.year(), sample.sampleDate.month(), 1)
        );
      }
      byMonth.get(key).add(sample.amount);
    }

    List<String> keys = new List<String>(byMonth.keySet());
    keys.sort();

    List<LaneTrend.Point> points = new List<LaneTrend.Point>();
    for (String key : keys) {
      List<Decimal> amounts = byMonth.get(key);
      Date monthDate = firstOfMonth.get(key);
      LaneTrend.Point point = new LaneTrend.Point();
      point.monthKey = key;
      point.label = MONTH_LABELS[monthDate.month() - 1];
      point.monthIndex = monthsBetween(windowStart, monthDate);
      point.count = amounts.size();
      point.median = SplitLaneService.median(amounts);
      point.minimum = leastOf(amounts);
      point.maximum = greatestOf(amounts);
      point.thin = amounts.size() < THIN_COUNT;
      points.add(point);
    }
    return points;
  }

  private static String monthKeyOf(Date d) {
    return String.valueOf(d.year()) +
      '-' +
      (d.month() < 10 ? '0' : '') +
      String.valueOf(d.month());
  }

  private static Integer monthsBetween(Date from0, Date to0) {
    return (to0.year() - from0.year()) * 12 + (to0.month() - from0.month());
  }

  private static Decimal leastOf(List<Decimal> values) {
    Decimal least = values[0];
    for (Decimal v : values) {
      if (v < least) {
        least = v;
      }
    }
    return least;
  }

  private static Decimal greatestOf(List<Decimal> values) {
    Decimal greatest = values[0];
    for (Decimal v : values) {
      if (v > greatest) {
        greatest = v;
      }
    }
    return greatest;
  }
```

Note `from0` / `to0`: `from` is a reserved Apex identifier (SOQL is embedded in the language), so it cannot name a parameter.

- [ ] **Step 5: Deploy and run the test to verify it passes**

```bash
sf project deploy start --source-dir force-app/main/default/classes --target-org sandbox --test-level NoTestRun --wait 20
sf apex run test --tests LaneTrendServiceTest --target-org sandbox --result-format human --wait 20
```

Expected: PASS, 4 methods, 0 failing.

- [ ] **Step 6: Check PMD and commit**

```bash
npm run pmd
npx prettier --write "force-app/main/default/classes/LaneTrend*.cls"
git add force-app/main/default/classes/LaneTrend.cls force-app/main/default/classes/LaneTrend.cls-meta.xml \
        force-app/main/default/classes/LaneTrendService.cls force-app/main/default/classes/LaneTrendService.cls-meta.xml \
        force-app/main/default/classes/LaneTrendServiceTest.cls force-app/main/default/classes/LaneTrendServiceTest.cls-meta.xml
git commit -m "Bucket a lane's rates into months, gaps and all

A month with no rates is absent from the series rather than present as a zero: a
zero is a rate of nothing, and it drags the median of the window toward a price
no carrier ever quoted. monthIndex carries how far each month sits from the start
of the window, so the chart can draw the absence as a gap instead of closing it.

Medians reuse SplitLaneService.median, which already rounds to scale 2 and leaves
its argument alone. A sample with no date cannot be placed on a time axis, and
one with no amount is not a rate; both are dropped."
```

Expected: PMD reports 0 violations. If it reports `CyclomaticComplexity` on `LaneTrendService`, do not suppress it — extract the bucketing helpers into their own class and say so in the commit.

---

### Task 2: Let the trend borrow the search's WHERE, and reuse its place resolution

Why this task exists: the trend must match **exactly** the rows a search of the same lane matches (D2), including phase 12's market-test filter (D7). Re-deriving conditions would make that a promise maintained by vigilance. Borrowing the builders' own WHERE assembly makes it true by construction. The quote and bid builders match lanes differently — quotes through `LaneQueries.laneConditions` with a `rtms__Load__r.` path, bids through `BidSearchQueryBuilder`'s own `addEnd` — so each builder exposes its own.

This is a **pure refactor**: no behaviour changes, and the existing builder tests are the proof. Do not add new assertions to them.

**Files:**

- Modify: `force-app/main/default/classes/LaneSearchQueryBuilder.cls`
- Modify: `force-app/main/default/classes/BidSearchQueryBuilder.cls`
- Modify: `force-app/main/default/classes/LaneSearchService.cls`

**Interfaces:**

- Consumes: `LaneQueries.laneConditions(...)`, `MarketTestFilter.forQuotes(...)`, `.forBids(...)`, `LaneSearchFilters.addFilters(...)` — all already in place.
- Produces:
  - `LaneSearchQueryBuilder.trendSoql(LaneSearchRequest req, Map<String, Object> binds, Map<String, Pricing_Place__c> places)` → `String`
  - `BidSearchQueryBuilder.trendSoql(LaneSearchRequest req, Map<String, Object> binds, Map<String, Pricing_Place__c> places)` → `String`
  - `LaneSearchQueryBuilder.trendCountSoql(...)`, `BidSearchQueryBuilder.trendCountSoql(...)` → `String` (`SELECT COUNT()` over the same WHERE)
  - `LaneSearchService.loadPlaces(LaneSearchRequest req)` → `Map<String, Pricing_Place__c>` (was `private`)

- [ ] **Step 1: Read both builders and locate the WHERE assembly**

```bash
sed -n '1,60p' force-app/main/default/classes/LaneSearchQueryBuilder.cls
grep -n "SELECT_CLAUSE\|String.join(conditions" force-app/main/default/classes/BidSearchQueryBuilder.cls
```

In each, `buildSoql` assembles a `List<String> conditions` and a `Map<String, Object> binds`, then concatenates `SELECT_CLAUSE + ' WHERE ' + String.join(conditions, ' AND ') + <order/limit>`. The refactor extracts the assembly up to and including `String.join`, leaving `buildSoql` to prepend its own SELECT and append its own ORDER/LIMIT. **Do not change the order in which conditions are added** — `LaneSearchQueryBuilderTest` and `BidSearchQueryBuilderTest` pin the exact SOQL text, and a reordering breaks them.

- [ ] **Step 2: Run the existing builder tests to record the green baseline**

```bash
sf apex run test --tests LaneSearchQueryBuilderTest --tests BidSearchQueryBuilderTest \
  --target-org sandbox --result-format human --wait 20
```

Expected: PASS. Write the method count down. This is the number that must not change.

- [ ] **Step 3: Extract the WHERE assembly in `LaneSearchQueryBuilder`**

Introduce a private `whereFor(req, binds, places)` that returns the joined condition text, have `buildSoql` call it, and add the two trend entries:

```apex
  /**
   * The condition text buildSoql uses, without its SELECT, ORDER BY or LIMIT — so the lane trend
   * can read the same rows through a narrower projection. Shared rather than re-derived: a trend
   * and a search of the same lane must agree about which quotes belong to it (phase 10 D2), and
   * this is what makes that true by construction rather than by vigilance.
   */
  private static String whereFor(
    LaneSearchRequest req,
    Map<String, Object> binds,
    Map<String, Pricing_Place__c> places
  ) {
    // Body moved verbatim out of buildSoql, ending at String.join(conditions, ' AND ').
    // Keep the order of condition additions exactly as it was.
  }

  /** Phase 10: the date, amount and currency of the same quote rows, and nothing else. */
  public static String trendSoql(
    LaneSearchRequest req,
    Map<String, Object> binds,
    Map<String, Pricing_Place__c> places
  ) {
    return 'SELECT Quote_Date__c, rtms__Carrier_Total__c, CurrencyIsoCode' +
      ' FROM rtms__CarrierQuote__c WHERE ' +
      whereFor(req, binds, places) +
      ' ORDER BY Quote_Date__c LIMIT :trendRowCap';
  }

  /** Phase 10 D3: one query row, to decide whether the read above fits before running it. */
  public static String trendCountSoql(
    LaneSearchRequest req,
    Map<String, Object> binds,
    Map<String, Pricing_Place__c> places
  ) {
    return 'SELECT COUNT() FROM rtms__CarrierQuote__c WHERE ' +
      whereFor(req, binds, places);
  }
```

`buildSoql` becomes `SELECT_CLAUSE + ' WHERE ' + whereFor(req, binds, places) + <its existing ORDER BY / LIMIT>`.

The caller puts `trendRowCap` into `binds`. Note `trendCountSoql` must **not** bind `trendRowCap`, because a `COUNT()` with no `LIMIT` never references it and an unused bind is harmless but an absent one is fatal — so bind it only for `trendSoql`.

- [ ] **Step 4: Do the same in `BidSearchQueryBuilder`**

```apex
  /** As LaneSearchQueryBuilder.whereFor: the bid conditions, for the trend to borrow (phase 10 D2). */
  private static String whereFor(
    LaneSearchRequest req,
    Map<String, Object> binds,
    Map<String, Pricing_Place__c> places
  ) {
    // Body moved verbatim out of buildSoql, ending at String.join(conditions, ' AND ').
  }

  /** Phase 10: bids are dated on Valid_From__c, which BidSearchService already treats as the quote date. */
  public static String trendSoql(
    LaneSearchRequest req,
    Map<String, Object> binds,
    Map<String, Pricing_Place__c> places
  ) {
    return 'SELECT Valid_From__c, Rate__c, CurrencyIsoCode' +
      ' FROM Benchmark_Rate__c WHERE ' +
      whereFor(req, binds, places) +
      ' ORDER BY Valid_From__c LIMIT :trendRowCap';
  }

  public static String trendCountSoql(
    LaneSearchRequest req,
    Map<String, Object> binds,
    Map<String, Pricing_Place__c> places
  ) {
    return 'SELECT COUNT() FROM Benchmark_Rate__c WHERE ' +
      whereFor(req, binds, places);
  }
```

- [ ] **Step 5: Make `loadPlaces` shareable**

In `LaneSearchService.cls`, change the signature and add the comment that records why it is public — the same convention `RfpLaneController.lanesByIds` uses:

```apex
  /** Shared by LaneTrendService: the same places the search resolves, keyed as the request names them. */
  public static Map<String, Pricing_Place__c> loadPlaces(
    LaneSearchRequest req
  ) {
```

- [ ] **Step 6: Re-run the builder tests — the refactor is proven by them not changing**

```bash
sf project deploy start --source-dir force-app/main/default/classes --target-org sandbox --test-level NoTestRun --wait 20
sf apex run test --tests LaneSearchQueryBuilderTest --tests BidSearchQueryBuilderTest --tests LaneSearchServiceTest --tests BidSearchServiceTest \
  --target-org sandbox --result-format human --wait 20
npm run pmd
```

Expected: PASS with the same method count as Step 2, and PMD 0. If a builder now exceeds complexity 40, split rather than suppress.

- [ ] **Step 7: Commit**

```bash
npx prettier --write "force-app/main/default/classes/*QueryBuilder.cls" "force-app/main/default/classes/LaneSearchService.cls"
git add force-app/main/default/classes/LaneSearchQueryBuilder.cls force-app/main/default/classes/BidSearchQueryBuilder.cls force-app/main/default/classes/LaneSearchService.cls
git commit -m "Let the trend borrow the search's conditions instead of copying them

The lane trend has to match exactly the rows a search of the same lane matches,
market-test filter included. Re-deriving the conditions would make that a promise
kept by vigilance, and the two would drift the first time either side gained a
filter - which is precisely how the market-test filter came to mean two different
things on one control.

So each builder now exposes the condition text it already assembles, and the
trend prepends its own narrow SELECT. No condition moved and no order changed:
both builder tests pin the exact SOQL and still pass unaltered, which is the
proof this is a refactor. loadPlaces is public for the same reason
RfpLaneController.lanesByIds is."
```

---

### Task 3: Read both sources behind a row guard, and honor the filter

**Files:**

- Modify: `force-app/main/default/classes/LaneTrendService.cls`
- Test: `force-app/main/default/classes/LaneTrendServiceTest.cls`

**Interfaces:**

- Consumes: `LaneSearchQueryBuilder.trendSoql/trendCountSoql`, `BidSearchQueryBuilder.trendSoql/trendCountSoql`, `LaneSearchService.loadPlaces`, `LaneTrendService.bucket`, `SplitLaneService.median`.
- Produces: `LaneTrendService.trendFor(LaneSearchRequest req)` → `LaneTrend`.

- [ ] **Step 1: Write the failing tests**

Append to `LaneTrendServiceTest.cls`. These need real rows, so use the existing factories — check their exact names first with `grep -n "public static" force-app/main/default/classes/PricingTestDataFactory.cls` and follow what `LaneSearchServiceTest` does to build a lane's quotes; mirror that setup rather than inventing one.

```apex
  /**
   * D7, and the test that makes it real rather than asserted: a lane whose only rates are
   * market-test plots them under Include and plots nothing under Exclude. Without this, the chart
   * and the median printed directly above it can describe different row sets.
   */
  @IsTest
  static void excludeMovesTheChart() {
    LaneTrendFixture f = LaneTrendFixture.withMarketTestRatesOnly();

    LaneSearchRequest included = f.request();
    included.marketTestFilter = LaneSearchRequest.MarketTest.INCLUDE;
    LaneSearchRequest excluded = f.request();
    excluded.marketTestFilter = LaneSearchRequest.MarketTest.EXCLUDE;

    Test.startTest();
    LaneTrend withThem = LaneTrendService.trendFor(included);
    LaneTrend withoutThem = LaneTrendService.trendFor(excluded);
    Test.stopTest();

    System.assert(
      withThem.totalRates > 0,
      'Include plots the market-test rates: ' + withThem.totalRates
    );
    System.assertEquals(
      0,
      withoutThem.totalRates,
      'Exclude leaves the chart empty, because every rate on this lane is a market test'
    );
  }

  /** D3: the guard decides before the read, so an oversized window is flagged and not thrown. */
  @IsTest
  static void anOversizedWindowIsFlaggedRatherThanThrown() {
    LaneTrendFixture f = LaneTrendFixture.withQuotes(5);
    LaneTrendService.rowCapOverride = 2;

    Test.startTest();
    LaneTrend trend = LaneTrendService.trendFor(f.request());
    Test.stopTest();

    System.assertEquals(
      true,
      trend.truncated,
      'over the cap the chart is still drawn, and says so'
    );
    System.assert(
      !trend.points.isEmpty(),
      'a drawn-and-flagged chart beats a refused one'
    );
  }

  /** D6: one currency at a time, never two on one axis. */
  @IsTest
  static void neverMixesCurrencies() {
    LaneTrendFixture f = LaneTrendFixture.withQuotesInBothCurrencies();
    LaneSearchRequest req = f.request();
    req.currencyIsoCode = 'CAD';

    Test.startTest();
    LaneTrend trend = LaneTrendService.trendFor(req);
    Test.stopTest();

    System.assertEquals('CAD', trend.currencyIsoCode);
    System.assertEquals(
      f.cadQuoteCount,
      trend.totalRates,
      'the USD rows are another axis, not this one'
    );
  }
```

`LaneTrendFixture` is a small test-only helper you write inside `LaneTrendServiceTest` (an inner class, not a new file): it inserts a place pair plus quotes and/or `Benchmark_Rate__c` rows on one lane and exposes `request()` returning a `LaneSearchRequest` with `originKey`/`destinationKey` set to that pair. Copy the place and quote construction from `LaneSearchServiceTest` so the managed-trigger graph is valid.

- [ ] **Step 2: Add the compiling stub and the test seam**

In `LaneTrendService.cls`:

```apex
  /** @TestVisible so a test can prove the guard without inserting 10,001 rows. camelCase, not final. */
  @TestVisible
  private static Integer rowCapOverride;

  public static LaneTrend trendFor(LaneSearchRequest req) {
    return new LaneTrend();
  }
```

- [ ] **Step 3: Deploy and watch the assertions fail**

```bash
sf project deploy start --source-dir force-app/main/default/classes --target-org sandbox --test-level NoTestRun --wait 20
sf apex run test --tests LaneTrendServiceTest --target-org sandbox --result-format human --wait 20
```

Expected: the three new methods FAIL on their assertions (`Include plots the market-test rates: 0`, `over the cap the chart is still drawn, and says so`, `the USD rows are another axis, not this one`); the four Task 1 methods still PASS.

- [ ] **Step 4: Implement `trendFor`**

```apex
  /**
   * The lane's rates over the request's window, bucketed by month.
   *
   * The conditions are the search's own (D2) and therefore carry the market-test filter the pricer
   * set (D7), so this chart and the statistics card above it always describe the same rows. Both
   * sources are counted before either is read (D3): a COUNT() costs one query row, while reading
   * 10,000 rows to discover they were too many costs 10,000 - and a LimitException cannot be caught.
   */
  public static LaneTrend trendFor(LaneSearchRequest req) {
    LaneTrend trend = new LaneTrend();
    trend.currencyIsoCode = req.currencyIsoCode;
    trend.lookbackDays = req.lookbackDays;
    Date windowStart = Date.today().addDays(-req.lookbackDays);
    trend.monthSpan = monthsBetween(
      Date.newInstance(windowStart.year(), windowStart.month(), 1),
      Date.today()
    ) + 1;

    Map<String, Pricing_Place__c> places = LaneSearchService.loadPlaces(req);
    Integer cap = rowCapOverride == null ? ROW_CAP : rowCapOverride;

    Map<String, Object> quoteCountBinds = new Map<String, Object>();
    Integer quoteRows = Database.countQueryWithBinds(
      LaneSearchQueryBuilder.trendCountSoql(req, quoteCountBinds, places),
      quoteCountBinds,
      AccessLevel.SYSTEM_MODE
    );
    Map<String, Object> bidCountBinds = new Map<String, Object>();
    Integer bidRows = Database.countQueryWithBinds(
      BidSearchQueryBuilder.trendCountSoql(req, bidCountBinds, places),
      bidCountBinds,
      AccessLevel.SYSTEM_MODE
    );
    trend.truncated = quoteRows + bidRows > cap;

    List<Sample> samples = new List<Sample>();
    Map<String, Object> quoteBinds = new Map<String, Object>{
      'trendRowCap' => cap
    };
    String quoteSoql = LaneSearchQueryBuilder.trendSoql(req, quoteBinds, places);
    for (
      rtms__CarrierQuote__c q : (List<rtms__CarrierQuote__c>) Database.queryWithBinds(
        quoteSoql,
        quoteBinds,
        AccessLevel.SYSTEM_MODE
      )
    ) {
      samples.add(new Sample(q.Quote_Date__c, q.rtms__Carrier_Total__c));
    }

    Map<String, Object> bidBinds = new Map<String, Object>{
      'trendRowCap' => cap
    };
    String bidSoql = BidSearchQueryBuilder.trendSoql(req, bidBinds, places);
    for (
      Benchmark_Rate__c b : (List<Benchmark_Rate__c>) Database.queryWithBinds(
        bidSoql,
        bidBinds,
        AccessLevel.SYSTEM_MODE
      )
    ) {
      samples.add(new Sample(b.Valid_From__c, b.Rate__c));
    }

    trend.points = bucket(samples, Date.newInstance(windowStart.year(), windowStart.month(), 1), trend.monthSpan);
    summarise(trend, samples);
    return trend;
  }

  /**
   * The numbers the sentence under the chart is built from. Computed here rather than in the
   * component because the component formats and never calculates, as it already does for
   * LaneSearchResult.Stats. The change compares the first and last months that are not thin: two
   * quotes at either end would otherwise set the headline for a year.
   */
  private static void summarise(LaneTrend trend, List<Sample> samples) {
    List<Decimal> all = new List<Decimal>();
    for (Sample s : samples) {
      if (s != null && s.amount != null && s.sampleDate != null) {
        all.add(s.amount);
      }
    }
    trend.totalRates = all.size();
    trend.overallMedian = SplitLaneService.median(all);

    List<LaneTrend.Point> solid = new List<LaneTrend.Point>();
    for (LaneTrend.Point p : trend.points) {
      if (p.thin != true) {
        solid.add(p);
      }
    }
    if (solid.size() < 2) {
      return;
    }
    LaneTrend.Point earliest = solid[0];
    LaneTrend.Point latest = solid[solid.size() - 1];
    trend.firstLabel = earliest.label;
    trend.lastLabel = latest.label;
    if (earliest.median != null && earliest.median != 0) {
      trend.changePct = ((latest.median - earliest.median) / earliest.median * 100)
        .setScale(1);
    }
  }
```

If `Database.countQueryWithBinds` is unavailable on this API version, fall back to `Database.countQuery(soql)` with the binds inlined as a literal-free condition — but check first: it exists from API 55.

- [ ] **Step 5: Deploy and verify all seven methods pass**

```bash
sf project deploy start --source-dir force-app/main/default/classes --target-org sandbox --test-level NoTestRun --wait 20
sf apex run test --tests LaneTrendServiceTest --target-org sandbox --result-format human --wait 20
npm run pmd
```

Expected: PASS, 7 methods, 0 failing. PMD 0.

- [ ] **Step 6: Commit**

```bash
npx prettier --write "force-app/main/default/classes/LaneTrend*.cls"
git add force-app/main/default/classes/LaneTrendService.cls force-app/main/default/classes/LaneTrendServiceTest.cls
git commit -m "Read a lane's trend behind a count, and honor the filter above it

Both sources are counted before either is read. A COUNT() costs one query row;
discovering after reading 10,000 rows that there were too many costs 10,000, and
a LimitException cannot be caught, so the guard has to come first. Over the cap
the chart is still drawn from what was read and says it may be incomplete - a
drawn-and-flagged chart beats a refused one.

The conditions are the search's own, so the trend carries whatever Include,
Exclude or Only the pricer set. That is the point of D7: a chart describing a
different row set than the median printed directly above it is a chart that lies
without saying so. The test that proves it is a lane whose only rates are market
test - it plots under Include and plots nothing under Exclude."
```

---

### Task 4: The Apex surface

**Files:**

- Create: `force-app/main/default/classes/LaneTrendController.cls` (+ `-meta.xml`)
- Test: `force-app/main/default/classes/LaneTrendControllerTest.cls` (+ `-meta.xml`)

**Interfaces:**

- Consumes: `LaneTrendService.trendFor(LaneSearchRequest)`.
- Produces: `LaneTrendController.getTrend(String requestJson)` → `LaneTrend`, `@AuraEnabled(cacheable=true)`.

- [ ] **Step 1: Write the failing test**

Check how `MarketTestControllerTest` asserts an `AuraHandledException` and copy that shape.

```apex
@IsTest
private class LaneTrendControllerTest {
  @IsTest
  static void returnsTheTrendForARequestThePageAlreadyHolds() {
    LaneTrendFixtureShared f = LaneTrendFixtureShared.withQuotes(4);
    String requestJson = JSON.serialize(f.request());

    Test.startTest();
    LaneTrend trend = LaneTrendController.getTrend(requestJson);
    Test.stopTest();

    System.assertNotEquals(null, trend);
    System.assert(
      trend.totalRates > 0,
      'the lane has rates, so the chart has points'
    );
  }

  @IsTest
  static void unreadableJsonIsAUserErrorRatherThanAStackTrace() {
    Boolean threw = false;
    Test.startTest();
    try {
      LaneTrendController.getTrend('{not json');
    } catch (Exception e) {
      threw = true;
      System.assert(
        e.getMessage().contains('trend could not be read'),
        'the page shows a sentence, not a parse error: ' + e.getMessage()
      );
    }
    Test.stopTest();
    System.assertEquals(true, threw);
  }
}
```

If sharing a fixture between the two test classes is awkward, duplicate the small builder into `LaneTrendControllerTest` rather than creating a production-side helper — test data belongs in tests.

- [ ] **Step 2: Add the compiling stub, deploy, watch it fail**

```apex
public with sharing class LaneTrendController {
  @AuraEnabled(cacheable=true)
  public static LaneTrend getTrend(String requestJson) {
    return null;
  }
}
```

```bash
sf project deploy start --source-dir force-app/main/default/classes --target-org sandbox --test-level NoTestRun --wait 20
sf apex run test --tests LaneTrendControllerTest --target-org sandbox --result-format human --wait 20
```

Expected: FAIL on `System.assertNotEquals(null, trend)` and on the missing exception.

- [ ] **Step 3: Implement**

```apex
/**
 * Phase 10: the lane trend's only Apex surface.
 *
 * cacheable=true (spec §4) because a trend over closed months does not change minute to minute,
 * and because the request JSON is the cache key: flipping the market-test filter produces a
 * different key and therefore a redraw rather than the previous answer (D7).
 */
public with sharing class LaneTrendController {
  @AuraEnabled(cacheable=true)
  public static LaneTrend getTrend(String requestJson) {
    try {
      LaneSearchRequest req = (LaneSearchRequest) JSON.deserialize(
        requestJson,
        LaneSearchRequest.class
      );
      return LaneTrendService.trendFor(req);
    } catch (Exception e) {
      throw new AuraHandledException('The trend could not be read.');
    }
  }
}
```

Check what the other controllers do — if the project has a shared user-error helper for Lane Benchmark (as `RfpUserError` is for the RFP side), use that instead of a bare `AuraHandledException`, and match its message style. Grep: `grep -rn "AuraHandledException\|UserError" force-app/main/default/classes/LaneBenchmarkController.cls`.

- [ ] **Step 4: Deploy, verify PASS, check PMD, commit**

```bash
sf project deploy start --source-dir force-app/main/default/classes --target-org sandbox --test-level NoTestRun --wait 20
sf apex run test --tests LaneTrendControllerTest --tests LaneTrendServiceTest --target-org sandbox --result-format human --wait 20
npm run pmd
npx prettier --write "force-app/main/default/classes/LaneTrendController*.cls"
git add force-app/main/default/classes/LaneTrendController.cls force-app/main/default/classes/LaneTrendController.cls-meta.xml \
        force-app/main/default/classes/LaneTrendControllerTest.cls force-app/main/default/classes/LaneTrendControllerTest.cls-meta.xml
git commit -m "Give the lane trend its one Apex surface

Cacheable, because a trend over closed months does not change minute to minute -
and because the request JSON is the cache key, so flipping the market-test filter
asks a different question and gets a redraw rather than the previous answer.

A request the page cannot serialise, or a place key that no longer resolves, ends
as one sentence under the card. A parse error in a toast tells a pricer nothing
they can act on."
```

---

### Task 5: The component's data half — plumbing, window control, empty states

**Files:**

- Create: `force-app/main/default/lwc/laneTrendChart/laneTrendChart.js`
- Create: `force-app/main/default/lwc/laneTrendChart/laneTrendChart.html`
- Create: `force-app/main/default/lwc/laneTrendChart/laneTrendChart.js-meta.xml`
- Test: `force-app/main/default/lwc/laneTrendChart/__tests__/laneTrendChart.test.js`

**Interfaces:**

- Consumes: `@salesforce/apex/LaneTrendController.getTrend` — called imperatively (not via `@wire`) so the window control can re-ask.
- Produces: a component accepting `@api requestJson` and `@api currencyCode`, used as `<c-lane-trend-chart request-json={lastRequestJson} currency-code={lastCurrency}>`.

Mirror `lwc/marketTestRates/marketTestRates.js` exactly for the `requestJson` setter: a `_requestJson` backing field, an identity guard so an unchanged value does not refetch, and a `try/catch` around `JSON.parse` that leaves the card closed rather than breaking the page.

- [ ] **Step 1: Write the failing tests**

`force-app/main/default/lwc/laneTrendChart/__tests__/laneTrendChart.test.js`:

```javascript
import { createElement } from "lwc";
import LaneTrendChart from "c/laneTrendChart";
import getTrend from "@salesforce/apex/LaneTrendController.getTrend";

jest.mock(
  "@salesforce/apex/LaneTrendController.getTrend",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const settle = () => Promise.resolve().then(() => Promise.resolve());

const point = (over = {}) => ({
  monthKey: "2026-01",
  label: "Jan",
  monthIndex: 0,
  count: 8,
  median: 2400,
  minimum: 2000,
  maximum: 2900,
  thin: false,
  ...over
});

const trend = (over = {}) => ({
  points: [
    point(),
    point({ monthKey: "2026-02", label: "Feb", monthIndex: 1, median: 2550 })
  ],
  currencyIsoCode: "CAD",
  lookbackDays: 365,
  monthSpan: 12,
  truncated: false,
  totalRates: 16,
  overallMedian: 2450,
  changePct: 6.2,
  firstLabel: "Jan",
  lastLabel: "Feb",
  ...over
});

const requestJson = JSON.stringify({
  originKey: "montreal|qc|ca",
  destinationKey: "toronto|on|ca",
  lookbackDays: 365
});

async function open(result, json = requestJson) {
  getTrend.mockResolvedValue(result);
  const el = createElement("c-lane-trend-chart", { is: LaneTrendChart });
  el.currencyCode = "CAD";
  el.requestJson = json;
  document.body.appendChild(el);
  await settle();
  return el;
}

describe("c-lane-trend-chart", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("asks for the trend with the lookback the window control names", async () => {
    const el = await open(trend());
    expect(getTrend).toHaveBeenCalled();
    const sent = JSON.parse(getTrend.mock.calls[0][0].requestJson);
    expect(sent.lookbackDays).toBe(365);
    expect(
      el.shadowRoot.querySelector('[data-id="trend-summary"]')
    ).not.toBeNull();
  });

  it("re-asks with a new lookback when the window changes", async () => {
    const el = await open(trend());
    getTrend.mockClear();
    el.shadowRoot
      .querySelector('[data-id="window-3y"]')
      .dispatchEvent(new CustomEvent("click"));
    await settle();
    const sent = JSON.parse(getTrend.mock.calls[0][0].requestJson);
    expect(sent.lookbackDays).toBe(1095);
  });

  it("says so rather than drawing a frame when fewer than two months are usable", async () => {
    const el = await open(trend({ points: [point()], changePct: null }));
    expect(el.shadowRoot.querySelector("svg")).toBeNull();
    expect(
      el.shadowRoot.querySelector('[data-id="trend-empty"]').textContent
    ).toContain("not enough");
  });

  it("warns when the window was truncated", async () => {
    const el = await open(trend({ truncated: true }));
    expect(
      el.shadowRoot.querySelector('[data-id="trend-truncated"]').textContent
    ).toContain("may be incomplete");
  });

  it("stays closed when the request cannot be parsed", async () => {
    const el = await open(trend(), "{not json");
    expect(getTrend).not.toHaveBeenCalled();
    expect(el.shadowRoot.querySelector("svg")).toBeNull();
  });
});
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
npx jest force-app/main/default/lwc/laneTrendChart
```

Expected: FAIL — `Cannot find module 'c/laneTrendChart'`. Create the three component files as empty valid stubs, re-run, and confirm the failures become assertion failures rather than a missing module.

- [ ] **Step 3: Implement the JS**

```javascript
import { LightningElement, api, track } from "lwc";
import getTrend from "@salesforce/apex/LaneTrendController.getTrend";

const WINDOWS = [
  { key: "6m", label: "6 months", days: 182 },
  { key: "1y", label: "1 year", days: 365 },
  { key: "3y", label: "3 years", days: 1095 }
];

/**
 * Phase 10: how this lane's market moved. Imperative rather than @wire because the window control
 * asks the same question over a different span, and because the card must stay closed when there
 * is no lane yet rather than firing a call with nothing in it.
 */
export default class LaneTrendChart extends LightningElement {
  @api currencyCode;

  _requestJson = null;
  @track trend = null;
  windowKey = "1y";
  loading = false;
  error = null;

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
    this.load();
  }

  get windows() {
    return WINDOWS.map((w) => ({
      ...w,
      dataId: `window-${w.key}`,
      variant: w.key === this.windowKey ? "brand" : "neutral"
    }));
  }

  handleWindow(event) {
    const key = event.currentTarget.dataset.window;
    if (!key || key === this.windowKey) {
      return;
    }
    this.windowKey = key;
    this.load();
  }

  async load() {
    this.error = null;
    const request = this.parsedRequest();
    if (!request) {
      this.trend = null;
      return;
    }
    const days = WINDOWS.find((w) => w.key === this.windowKey).days;
    this.loading = true;
    try {
      this.trend = await getTrend({
        requestJson: JSON.stringify({ ...request, lookbackDays: days })
      });
    } catch (e) {
      this.trend = null;
      this.error = e?.body?.message || "The trend could not be read.";
    } finally {
      this.loading = false;
    }
  }

  parsedRequest() {
    if (!this._requestJson) {
      return null;
    }
    try {
      const request = JSON.parse(this._requestJson);
      return request.originKey && request.destinationKey ? request : null;
    } catch {
      // a request we cannot read leaves the card closed rather than breaking the page
      return null;
    }
  }

  get solidPoints() {
    return (this.trend?.points || []).filter((p) => !p.thin);
  }

  get hasEnough() {
    return this.solidPoints.length >= 2;
  }

  get isTruncated() {
    return this.trend?.truncated === true;
  }

  /** The sentence most pricers will read. Formats numbers Apex computed; does no maths. */
  get summary() {
    if (!this.trend || !this.hasEnough) {
      return "";
    }
    const t = this.trend;
    const direction =
      t.changePct === null || t.changePct === undefined
        ? ""
        : `, ${t.changePct >= 0 ? "up" : "down"} ${Math.abs(t.changePct)}% since ${t.firstLabel}`;
    return `${t.points.length} months, ${t.totalRates} rates, median ${t.overallMedian} ${t.currencyIsoCode}${direction}.`;
  }
}
```

`laneTrendChart.js-meta.xml`:

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<LightningComponentBundle xmlns="http://soap.sforce.com/2006/04/metadata">
    <apiVersion>64.0</apiVersion>
    <isExposed>false</isExposed>
</LightningComponentBundle>
```

`isExposed` is `false` because this is a child of `laneBenchmark`, not something dropped on a page — the same as `rfpLaneTemplate`.

- [ ] **Step 4: Implement the HTML shell (no SVG yet — that is Task 6)**

```html
<template>
  <article class="slds-card slds-m-bottom_small">
    <div class="slds-card__header slds-grid">
      <h2 class="slds-card__header-title slds-text-heading_small">
        Lane trend
      </h2>
      <div class="slds-no-flex">
        <template for:each="{windows}" for:item="w">
          <button
            key="{w.key}"
            data-id="{w.dataId}"
            data-window="{w.key}"
            class="slds-button slds-button_neutral slds-m-left_xx-small"
            onclick="{handleWindow}"
          >
            {w.label}
          </button>
        </template>
      </div>
    </div>
    <div class="slds-card__body slds-card__body_inner">
      <template lwc:if="{error}">
        <p data-id="trend-error" role="alert" class="slds-text-color_error">
          {error}
        </p>
      </template>
      <template lwc:elseif="{hasEnough}">
        <!-- Task 6 draws the chart here -->
        <p data-id="trend-summary" class="slds-text-body_regular">{summary}</p>
        <template lwc:if="{isTruncated}">
          <p
            data-id="trend-truncated"
            class="slds-text-color_weak slds-text-body_small"
          >
            The trend may be incomplete. Narrow the window to see all of it.
          </p>
        </template>
      </template>
      <template lwc:else>
        <p data-id="trend-empty" class="slds-text-color_weak">
          There is not enough history on this lane to show a trend yet.
        </p>
      </template>
    </div>
  </article>
</template>
```

- [ ] **Step 5: Run the tests to verify they pass**

```bash
npx jest force-app/main/default/lwc/laneTrendChart
npm run lint
```

Expected: PASS, 5 tests. Note the truncated test needs `hasEnough` true, which `trend()` satisfies with two solid points.

- [ ] **Step 6: Commit**

```bash
npx prettier --write "force-app/main/default/lwc/laneTrendChart/**"
git add force-app/main/default/lwc/laneTrendChart
git commit -m "Ask for a lane's trend, and say when there is not enough of one

Imperative rather than wired: the window control asks the same question over a
different span, and a card with no lane yet should stay shut rather than call
with nothing in it. A request that will not parse leaves it shut too.

Fewer than two months that are not thin draws no frame and says so. An empty
chart frame invites a reader to see a trend that is not there, which is worse
than a sentence admitting there is none."
```

---

### Task 6: The component's drawing half — SVG, hollow thin months, band, hidden table

**Files:**

- Modify: `force-app/main/default/lwc/laneTrendChart/laneTrendChart.js`
- Modify: `force-app/main/default/lwc/laneTrendChart/laneTrendChart.html`
- Test: `force-app/main/default/lwc/laneTrendChart/__tests__/laneTrendChart.test.js`

**Interfaces:**

- Produces: a `geometry` getter returning `{ viewBox, line, band, dots: [{ cx, cy, thin, title, r, className }], axis: [{ x, label }], gridY: [{ y, label }] }`. All positions are computed in JS from the Apex numbers — this is layout, not statistics.

- [ ] **Step 1: Write the failing tests**

Append to the existing test file:

```javascript
it("draws one dot per month and leaves thin months hollow and off the line", async () => {
  const el = await open(
    trend({
      points: [
        point({
          monthKey: "2026-01",
          label: "Jan",
          monthIndex: 0,
          median: 2000,
          count: 9
        }),
        point({
          monthKey: "2026-02",
          label: "Feb",
          monthIndex: 1,
          median: 9999,
          count: 1,
          thin: true
        }),
        point({
          monthKey: "2026-03",
          label: "Mar",
          monthIndex: 2,
          median: 2200,
          count: 7
        })
      ]
    })
  );
  const dots = el.shadowRoot.querySelectorAll('[data-id="trend-dot"]');
  expect(dots).toHaveLength(3);
  const hollow = el.shadowRoot.querySelectorAll(
    '[data-id="trend-dot"][data-thin="true"]'
  );
  expect(hollow).toHaveLength(1);

  // the line joins Jan to Mar directly: a month standing on one quote must not bend it
  const line = el.shadowRoot.querySelector('[data-id="trend-line"]');
  expect(line.getAttribute("points").trim().split(/\s+/)).toHaveLength(2);
});

it("carries the same numbers in a table for screen readers and copying", async () => {
  const el = await open(trend());
  const rows = el.shadowRoot.querySelectorAll('[data-id="trend-row"]');
  expect(rows).toHaveLength(2);
  expect(rows[0].textContent).toContain("Jan");
  expect(rows[0].textContent).toContain("2400");
  expect(
    el.shadowRoot.querySelector('[data-id="trend-table"]').className
  ).toContain("slds-assistive-text");
});

it("titles and describes the figure so it is not an unlabelled picture", async () => {
  const el = await open(trend());
  const svg = el.shadowRoot.querySelector("svg");
  expect(svg.getAttribute("role")).toBe("img");
  expect(el.shadowRoot.querySelector("svg title").textContent).toContain(
    "Lane trend"
  );
  expect(svg.getAttribute("aria-labelledby")).toBeTruthy();
});
```

- [ ] **Step 2: Run to verify failure**

```bash
npx jest force-app/main/default/lwc/laneTrendChart
```

Expected: FAIL — no `svg` element yet, so `trend-dot` queries return empty and `svg.getAttribute` throws on null.

- [ ] **Step 3: Add the geometry getter**

```javascript
const VIEW_W = 640;
const VIEW_H = 220;
const PAD_L = 56;
const PAD_R = 12;
const PAD_T = 12;
const PAD_B = 28;

  /**
   * Positions only. Every statistic was computed in Apex; this turns numbers into coordinates.
   * The x axis is the whole window (monthSpan), not just the months that have rates, so a gap in
   * the history reads as a gap rather than being closed up.
   */
  get geometry() {
    const points = this.trend?.points || [];
    if (!this.hasEnough) {
      return null;
    }
    const span = Math.max(this.trend.monthSpan || points.length, 2);
    const lows = points.map((p) => p.minimum);
    const highs = points.map((p) => p.maximum);
    const low = Math.min(...lows);
    const high = Math.max(...highs);
    const range = high - low || 1;

    const x = (i) => PAD_L + ((VIEW_W - PAD_L - PAD_R) * i) / (span - 1);
    const y = (v) => PAD_T + (VIEW_H - PAD_T - PAD_B) * (1 - (v - low) / range);

    const dots = points.map((p) => ({
      key: p.monthKey,
      cx: x(p.monthIndex),
      cy: y(p.median),
      thin: p.thin === true,
      title: `${p.label}: median ${p.median} ${this.trend.currencyIsoCode}, ${p.count} rates`
    }));

    const line = points
      .filter((p) => !p.thin)
      .map((p) => `${x(p.monthIndex)},${y(p.median)}`)
      .join(" ");

    const top = points.map((p) => `${x(p.monthIndex)},${y(p.maximum)}`);
    const bottom = points
      .slice()
      .reverse()
      .map((p) => `${x(p.monthIndex)},${y(p.minimum)}`);
    const band = top.concat(bottom).join(" ");

    return {
      viewBox: `0 0 ${VIEW_W} ${VIEW_H}`,
      line,
      band,
      dots,
      axis: points.map((p) => ({ key: p.monthKey, x: x(p.monthIndex), label: p.label })),
      gridY: [
        { key: "hi", y: y(high), label: String(Math.round(high)) },
        { key: "lo", y: y(low), label: String(Math.round(low)) }
      ]
    };
  }

  get tableRows() {
    return (this.trend?.points || []).map((p) => ({
      key: p.monthKey,
      label: p.label,
      count: p.count,
      median: p.median,
      minimum: p.minimum,
      maximum: p.maximum
    }));
  }

  get figureTitle() {
    return `Lane trend, ${this.trend?.currencyIsoCode || ""}`;
  }
```

- [ ] **Step 4: Draw it in the HTML**

Replace the `<!-- Task 6 draws the chart here -->` comment:

```html
<template lwc:if="{geometry}">
  <svg
    role="img"
    aria-labelledby="trend-title"
    viewBox="{geometry.viewBox}"
    class="slds-m-bottom_x-small"
    style="width: 100%; height: auto"
  >
    <title id="trend-title">{figureTitle}</title>
    <polygon
      data-id="trend-band"
      points="{geometry.band}"
      fill="var(--slds-g-color-palette-blue-90, #d8e6fe)"
      stroke="none"
    ></polygon>
    <template for:each="{geometry.gridY}" for:item="g">
      <text
        key="{g.key}"
        x="8"
        y="{g.y}"
        font-size="11"
        fill="var(--slds-g-color-neutral-base-50, #747474)"
      >
        {g.label}
      </text>
    </template>
    <polyline
      data-id="trend-line"
      points="{geometry.line}"
      fill="none"
      stroke="var(--slds-g-color-accent-base-50, #0176d3)"
      stroke-width="2"
    ></polyline>
    <template for:each="{geometry.dots}" for:item="d">
      <circle
        key="{d.key}"
        data-id="trend-dot"
        data-thin="{d.thin}"
        cx="{d.cx}"
        cy="{d.cy}"
        r="4"
        stroke="var(--slds-g-color-accent-base-50, #0176d3)"
        stroke-width="2"
        fill="{dotFill}"
      >
        <title>{d.title}</title>
      </circle>
    </template>
    <template for:each="{geometry.axis}" for:item="a">
      <text
        key="{a.key}"
        x="{a.x}"
        y="212"
        font-size="11"
        text-anchor="middle"
        fill="var(--slds-g-color-neutral-base-50, #747474)"
      >
        {a.label}
      </text>
    </template>
  </svg>
  <table data-id="trend-table" class="slds-assistive-text">
    <caption>
      {figureTitle}
    </caption>
    <thead>
      <tr>
        <th>Month</th>
        <th>Rates</th>
        <th>Median</th>
        <th>Lowest</th>
        <th>Highest</th>
      </tr>
    </thead>
    <tbody>
      <template for:each="{tableRows}" for:item="r">
        <tr key="{r.key}" data-id="trend-row">
          <td>{r.label}</td>
          <td>{r.count}</td>
          <td>{r.median}</td>
          <td>{r.minimum}</td>
          <td>{r.maximum}</td>
        </tr>
      </template>
    </tbody>
  </table>
</template>
```

LWC templates cannot call expressions, so a per-dot fill needs resolving in JS. Give each dot a `fill` property in the `geometry` getter instead of `dotFill`: `fill: p.thin ? "var(--slds-g-color-neutral-base-100, #ffffff)" : "var(--slds-g-color-accent-base-50, #0176d3)"`, and bind `fill={d.fill}`. Hollow means white-filled with the stroke still drawn, which is what makes a thin month visibly provisional.

- [ ] **Step 5: Run the tests and the full suite**

```bash
npx jest force-app/main/default/lwc/laneTrendChart
npx jest
npm run lint
```

Expected: 8 tests pass in this bundle, and the whole suite is 46 suites / 440 tests with none failing. If the total dropped, something else broke — fix before committing.

- [ ] **Step 6: Commit**

```bash
npx prettier --write "force-app/main/default/lwc/laneTrendChart/**"
git add force-app/main/default/lwc/laneTrendChart
git commit -m "Draw the lane trend by hand, thin months included but not trusted

No charting library: Salesforce will not load a script from a CDN, so a library
means vendoring a static resource the app carries forever, and a monthly series
is a few hundred lines of SVG. sheetJs stays the only vendored library.

A month standing on one or two quotes is drawn hollow and left off the line
entirely, so it cannot bend a trend it has no authority over. The x axis spans
the whole window rather than only the months with rates, so a quiet stretch reads
as the gap it was. Colours come from SLDS tokens with hex fallbacks, so the chart
survives both themes, and the same numbers are repeated in an assistive-text
table - a picture of a median is no use to a screen reader, or to anyone who
wants to paste it into a quote."
```

---

### Task 7: Put the card on the page, and finish the paperwork

**Files:**

- Modify: `force-app/main/default/lwc/laneBenchmark/laneBenchmark.html`
- Test: `force-app/main/default/lwc/laneBenchmark/__tests__/laneBenchmark.test.js`
- Modify: `manifest/package.xml`, `.github/workflows/ci.yml`, `README.md`
- Create: `docs/help/en/lb-trend.md`, `docs/help/fr/lb-trend.md`

- [ ] **Step 1: Write the failing placement test**

Read the existing `laneBenchmark.test.js` first for its harness (how it performs a search and awaits results), then add:

```javascript
it("puts the lane trend directly under the statistics card", async () => {
  const el = await searchAndSettle();
  const cards = [
    ...el.shadowRoot.querySelectorAll(
      "c-lane-benchmark-stats, c-lane-trend-chart"
    )
  ];
  expect(cards.map((c) => c.tagName.toLowerCase())).toEqual([
    "c-lane-benchmark-stats",
    "c-lane-trend-chart"
  ]);
  expect(
    el.shadowRoot.querySelector("c-lane-trend-chart").requestJson
  ).toBeTruthy();
});
```

- [ ] **Step 2: Run to verify it fails**

```bash
npx jest force-app/main/default/lwc/laneBenchmark
```

Expected: FAIL — the array has one entry, because `c-lane-trend-chart` is not on the page.

- [ ] **Step 3: Insert the card**

In `laneBenchmark.html`, immediately after the closing `</c-lane-benchmark-stats>` and before `<c-lane-benchmark-selling`:

```html
<c-lane-trend-chart
  data-id="lane-trend"
  request-json="{lastRequestJson}"
  currency-code="{lastCurrency}"
></c-lane-trend-chart>
```

Those are the same two properties `c-market-test-rates` already receives, so no new state is needed on `laneBenchmark`.

- [ ] **Step 4: Verify and run the whole suite**

```bash
npx jest
npm run lint
```

Expected: all suites pass.

- [ ] **Step 5: Roster and manifest**

Add to `manifest/package.xml` in the `ApexClass` block: `LaneTrend`, `LaneTrendService`, `LaneTrendServiceTest`, `LaneTrendController`, `LaneTrendControllerTest`. Add `laneTrendChart` to the `LightningComponentBundle` block.

Add `LaneTrendServiceTest` and `LaneTrendControllerTest` to the `--tests` list in `.github/workflows/ci.yml`, and to the four places in `README.md` that carry the test roster (lines ~32, ~142, ~149, ~428 — find them with `grep -n "CarrierSplitLimitsTest" README.md`).

**Do not** do this with a blind find-and-replace on an existing class name. Phase 12's roster edit did exactly that and injected four class names into an unrelated sentence about carrier caps. Edit each of the four places deliberately and check `git diff README.md` before committing.

Add a README inventory row for the new pieces next to the other Lane Benchmark entries, describing `LaneTrendController`/`LaneTrendService`/`laneTrendChart` and noting that the trend borrows the search's conditions so it honors the market-test filter.

- [ ] **Step 6: Help pages**

Create `docs/help/en/lb-trend.md` and `docs/help/fr/lb-trend.md` following the shape of the existing `lb-stats.md` (read it first — the build script expects a specific front-matter and heading structure). Cover: what the chart shows, what a hollow point means, what the window control does, that the trend follows the market-test filter, and what "may be incomplete" means. Then:

```bash
npm run help:build
npm run help:check
```

Expected: `help:check` reports the resource is up to date. Register the new pages wherever the help index lists sections — check `scripts/help/build.mjs` and the existing section list, and confirm the section count the README cites is updated.

- [ ] **Step 7: Full verification, then commit**

```bash
npm run pmd
npx jest
npm run lint
npm run help:check
sf project deploy start --manifest manifest/package.xml --target-org sandbox --test-level NoTestRun --wait 30
sf apex run test --tests LaneTrendServiceTest --tests LaneTrendControllerTest --tests LaneSearchQueryBuilderTest \
  --tests BidSearchQueryBuilderTest --tests LaneSearchServiceTest --tests BidSearchServiceTest \
  --target-org sandbox --result-format human --wait 30
```

Expected: PMD 0, Jest green, help in sync, Apex green. Remember the `apex` job in CI is a skip branch on this repository — it passes in seconds without doing anything, so this local org run is the only real Apex proof.

```bash
git add -A
git commit -m "Show the lane trend under the statistics it explains

The card sits directly under the statistics card, so the page reads in the order
a pricer thinks: what is the median, then how did it move. It takes the same two
properties the market test card already takes, so the page needed no new state.

The help pages say what a hollow point means and that the trend follows the
market-test filter, because a chart that quietly answers a different question
than the filter above it is the thing D7 exists to prevent."
```

---

## Self-Review

**Spec coverage:**

| Spec                                              | Task                                             |
| ------------------------------------------------- | ------------------------------------------------ |
| D1 server-side buckets                            | 1, 3                                             |
| D2 reuse the lane match                           | 2 (borrowed WHERE), 3                            |
| D3 row guard before reading                       | 3 (`anOversizedWindowIsFlaggedRatherThanThrown`) |
| D4 hand-drawn SVG, no library                     | 6                                                |
| D5 show n, thin months hollow and off the line    | 1 (`thin`), 6 (fill + line filter)               |
| D6 one currency at a time                         | 3 (`neverMixesCurrencies`)                       |
| D7 honor the market-test filter                   | 2, 3 (`excludeMovesTheChart`)                    |
| §3 placement under statistics                     | 7                                                |
| §3 window control 6m/1y/3y, default 1y            | 5                                                |
| §3 summary sentence                               | 3 (numbers), 5 (`summary`)                       |
| §3 fewer than two usable months says so           | 5                                                |
| §4 `getTrend`, cacheable                          | 4                                                |
| §4 10,000 cap                                     | 1 (`ROW_CAP`), 3                                 |
| §5 viewBox, SLDS tokens, title/desc, hidden table | 6                                                |
| §6 `truncated` surfaces as a note                 | 5                                                |
| §7 Apex tests                                     | 1, 3                                             |
| §7 Jest tests                                     | 5, 6                                             |
| §7 browser check in PostProduc                    | **Not a task** — see below                       |
| §8 out of scope                                   | Nothing built                                    |

**Gap accepted deliberately:** spec §7's third bullet asks for a browser check in PostProduc on a busy lane over three years, with the query-row cost read from a debug log. That is a manual verification, not code, so it has no task. It must still happen before the phase is called done — run it after Task 7 and record the measured row cost. If it exceeds the cap on a real busy province pair, the cap is wrong and Task 3's `ROW_CAP` needs revisiting.

**Placeholder scan:** no TBDs. Two steps deliberately say "read the existing file first and mirror it" (Task 3's fixture, Task 7's help front-matter and `laneBenchmark.test.js` harness) rather than inventing structure that may not match — each names the exact file to read and the exact thing to copy.

**Type consistency:** `LaneTrend.Point` fields are `monthKey`/`label`/`monthIndex`/`count`/`median`/`minimum`/`maximum`/`thin` in Tasks 1, 3, 5 and 6 alike. `bucket(samples, windowStart, monthSpan)` has the same three arguments in Tasks 1 and 3. `trendSoql`/`trendCountSoql` take `(req, binds, places)` in Tasks 2 and 3. `Sample(sampleDate, amount)` is consistent. `minimum`/`maximum` are used rather than `min`/`max` throughout, because `min` and `max` read as functions.

**One correction applied during review:** Task 6's first draft bound `fill={dotFill}` on a per-dot circle, which cannot work — LWC templates do not evaluate expressions, and a single getter cannot vary per iteration. Step 4 now says to put `fill` on each dot inside the `geometry` getter and bind `fill={d.fill}`.
