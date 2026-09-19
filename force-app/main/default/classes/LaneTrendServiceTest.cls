/**
 * Phase 10. The bucketing is the part that can lie: a month whose median is wrong, or a month
 * invented where there were no rates, produces a chart a pricer will quote from.
 */
@IsTest
private class LaneTrendServiceTest {
  private static LaneTrendService.Sample s(String isoDate, Decimal amount) {
    return new LaneTrendService.Sample(Date.valueOf(isoDate), amount);
  }

  /** Independent of LaneTrendService.MONTH_LABELS (private there) so a test computing an expected
   * label is not just re-reading production's own constant back at itself. */
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

  private static String monthLabel(Date d) {
    return MONTH_LABELS[d.month() - 1];
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
      Date.newInstance(2026, 1, 1)
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
    System.assert(jan.median == 2000, 'January median: ' + jan.median);
    System.assert(jan.minimum == 1000, 'January minimum: ' + jan.minimum);
    System.assert(jan.maximum == 3000, 'January maximum: ' + jan.maximum);
    System.assertEquals(false, jan.thin, 'three rates is not thin');

    LaneTrend.Point mar = points[1];
    System.assertEquals('2026-03', mar.monthKey);
    System.assertEquals(
      2,
      mar.monthIndex,
      'March sits two months after the window start, so the gap is visible on the axis'
    );
    System.assert(mar.median == 700, 'March median: ' + mar.median);
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
      Date.newInstance(2026, 1, 1)
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
      Date.newInstance(2026, 1, 1)
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
      Date.newInstance(2026, 1, 1)
    );
    Test.stopTest();
    System.assertEquals(0, points.size());
  }

  @IsTest
  static void bucketsAcrossACalendarYearBoundary() {
    List<LaneTrendService.Sample> samples = new List<LaneTrendService.Sample>{
      s('2025-11-03', 1000),
      s('2025-11-10', 1100),
      s('2025-11-20', 1200),
      s('2025-12-01', 2000),
      s('2025-12-15', 2100),
      s('2025-12-28', 2200),
      s('2026-01-02', 3000),
      s('2026-01-15', 3100),
      s('2026-01-30', 3200)
    };

    Test.startTest();
    List<LaneTrend.Point> points = LaneTrendService.bucket(
      samples,
      Date.newInstance(2025, 11, 1)
    );
    Test.stopTest();

    System.assertEquals(
      3,
      points.size(),
      'three months, none thin, none skipped across the year boundary'
    );

    System.assertEquals(
      '2025-11',
      points[0].monthKey,
      'chronological order across the year boundary'
    );
    System.assertEquals(0, points[0].monthIndex, 'the window start month');
    System.assertEquals(
      '2025-12',
      points[1].monthKey,
      'chronological order across the year boundary'
    );
    System.assertEquals(
      1,
      points[1].monthIndex,
      'a lost *12 year term in monthsBetween would miscount once the window crosses a year'
    );
    System.assertEquals(
      '2026-01',
      points[2].monthKey,
      'chronological order across the year boundary'
    );
    System.assertEquals(
      2,
      points[2].monthIndex,
      'two months after the window start, crossing the year: a lost *12 year term would give -10'
    );
  }

  /**
   * monthKeyOf pads single-digit months so keys sort correctly as strings. Unpadded, '2026-10'
   * (October) would sort before '2026-2' (February) because the character comparison never
   * reaches the month digits: '1' < '2' at the position where they first differ. Crossing a year
   * boundary does not exercise this - the year digit differs first there - so this needs two
   * months in the same year, one single-digit and one double-digit.
   */
  @IsTest
  static void sortsASingleDigitMonthBeforeADoubleDigitOneInTheSameYear() {
    List<LaneTrendService.Sample> samples = new List<LaneTrendService.Sample>{
      s('2026-02-03', 1000),
      s('2026-02-10', 1100),
      s('2026-02-20', 1200),
      s('2026-10-01', 2000),
      s('2026-10-15', 2100),
      s('2026-10-28', 2200)
    };

    Test.startTest();
    List<LaneTrend.Point> points = LaneTrendService.bucket(
      samples,
      Date.newInstance(2026, 2, 1)
    );
    Test.stopTest();

    System.assertEquals(2, points.size());
    System.assertEquals(
      '2026-02',
      points[0].monthKey,
      'unpadded, "2026-10" would sort before "2026-2" and put October first'
    );
    System.assertEquals(0, points[0].monthIndex);
    System.assertEquals('2026-10', points[1].monthKey);
    System.assertEquals(8, points[1].monthIndex);
  }

  // ---------------------------------------------------------------------------------------------
  // trendFor: the middle layer that resolves places, counts before reading, reads both sources,
  // merges and buckets them. LaneTrendFixture builds real quote and/or bid rows on one lane -
  // Revenova's managed triggers (loads, quotes) and BenchmarkRateTrigger (bids) both need a valid
  // object graph, which is why this borrows PricingTestDataFactory/RfpTestDataFactory rather than
  // inventing one; see LaneSearchServiceTest and BenchmarkRateServiceTest for the same pattern.
  // ---------------------------------------------------------------------------------------------

  /**
   * Test-only fixture: a place pair plus quotes and/or bids on one lane, and the LaneSearchRequest
   * that targets it. One place pair per factory method call - Pricing_Place__c is unique per city,
   * so a test method that needs a second lane calls a different factory method (each picks its own
   * cities) rather than building the same pair twice.
   */
  private class LaneTrendFixture {
    String originKey;
    String destinationKey;
    /** Set by withQuotesInBothCurrencies(): how many of its quotes are CAD, for neverMixesCurrencies. */
    Integer cadQuoteCount;
    /** Set by withQuotesAndBids(): the quote and bid counts, so the two gate tests have a known split. */
    Integer quoteCount;
    Integer bidCount;

    LaneSearchRequest request() {
      LaneSearchRequest r = new LaneSearchRequest();
      r.originKey = originKey;
      r.destinationKey = destinationKey;
      return r;
    }
  }

  // Apex forbids static members on an inner class ("static can only be used on methods of a top
  // level type"), so the fixture's factory methods live here, on the outer test class, and build
  // instances of the inner LaneTrendFixture rather than being static methods of it.

  private static LaneTrendFixture forPlaces(
    Pricing_Place__c origin,
    Pricing_Place__c destination
  ) {
    LaneTrendFixture f = new LaneTrendFixture();
    f.originKey = PlaceNormalizer.key(
      origin.City__c,
      origin.Province__c,
      origin.Country__c
    );
    f.destinationKey = PlaceNormalizer.key(
      destination.City__c,
      destination.Province__c,
      destination.Country__c
    );
    // As LaneSearchServiceTest.fixture(): custom metadata cannot be inserted in a test, so the
    // contact-exclusion list is overridden to empty rather than left to read the org's setting.
    LaneSearchExclusions.excludedContactIdsOverride = new Set<String>();
    return f;
  }

  /** D7's own test needs a lane whose only rates are market test - built from bids alone, so
   * Market_Test__c = true is the only thing making Exclude empty it. The quote half of D7
   * (Customer_Name__c against the house account's name) is exercised by MarketTestFilter's own
   * tests; borrowing LaneSearchQueryBuilder.whereFor already carries it into the trend without
   * this fixture needing to touch the org's market-test account configuration.
   */
  private static LaneTrendFixture withMarketTestRatesOnly() {
    Pricing_Place__c origin = RfpTestDataFactory.createPlace(
      'Calgary',
      'AB',
      'CA',
      51.0447,
      -114.0719,
      'T2P'
    );
    Pricing_Place__c destination = RfpTestDataFactory.createPlace(
      'Edmonton',
      'AB',
      'CA',
      53.5461,
      -113.4938,
      'T5J'
    );
    LaneTrendFixture f = forPlaces(origin, destination);

    PricingTestDataFactory.Graph g = PricingTestDataFactory.createGraph();
    RFP_Project__c project = RfpTestDataFactory.createProject(g.customer);
    RFP_Lane__c lane = RfpTestDataFactory.createLane(
      project,
      origin,
      destination
    );
    List<Benchmark_Rate__c> bids = new List<Benchmark_Rate__c>();
    for (Integer i = 0; i < 3; i++) {
      Benchmark_Rate__c b = RfpTestDataFactory.buildBid(lane, 1000 + i * 50);
      b.Market_Test__c = true;
      bids.add(b);
    }
    insert bids;
    return f;
  }

  /** count quotes on one load, for anOversizedWindowIsFlaggedRatherThanThrown. */
  private static LaneTrendFixture withQuotes(Integer count) {
    Pricing_Place__c origin = RfpTestDataFactory.createPlace(
      'Winnipeg',
      'MB',
      'CA',
      49.8951,
      -97.1384,
      'R3C'
    );
    Pricing_Place__c destination = RfpTestDataFactory.createPlace(
      'Regina',
      'SK',
      'CA',
      50.4452,
      -104.6189,
      'S4P'
    );
    LaneTrendFixture f = forPlaces(origin, destination);

    PricingTestDataFactory.Graph g = PricingTestDataFactory.createGraph();
    Account originLoc = PricingTestDataFactory.createLocation(
      'Origin Co',
      'Winnipeg',
      'Manitoba',
      'Canada',
      'R3C 0A1',
      49.8951,
      -97.1384
    );
    Account destLoc = PricingTestDataFactory.createLocation(
      'Destination Co',
      'Regina',
      'Saskatchewan',
      'Canada',
      'S4P 0A1',
      50.4452,
      -104.6189
    );
    rtms__Load__c load = PricingTestDataFactory.createLoad(
      g,
      originLoc,
      destLoc
    );
    List<rtms__CarrierQuote__c> quotes = new List<rtms__CarrierQuote__c>();
    for (Integer i = 0; i < count; i++) {
      quotes.add(PricingTestDataFactory.buildQuote(g, load, 1000 + i * 10));
    }
    insert quotes;
    return f;
  }

  /** Two CAD quotes and one USD quote on the same lane, for neverMixesCurrencies. */
  private static LaneTrendFixture withQuotesInBothCurrencies() {
    Pricing_Place__c origin = RfpTestDataFactory.createPlace(
      'Saskatoon',
      'SK',
      'CA',
      52.1332,
      -106.67,
      'S7K'
    );
    Pricing_Place__c destination = RfpTestDataFactory.createPlace(
      'Brandon',
      'MB',
      'CA',
      49.8481,
      -99.95,
      'R7A'
    );
    LaneTrendFixture f = forPlaces(origin, destination);

    PricingTestDataFactory.Graph g = PricingTestDataFactory.createGraph();
    Account originLoc = PricingTestDataFactory.createLocation(
      'Origin Co',
      'Saskatoon',
      'Saskatchewan',
      'Canada',
      'S7K 0A1',
      52.1332,
      -106.67
    );
    Account destLoc = PricingTestDataFactory.createLocation(
      'Destination Co',
      'Brandon',
      'Manitoba',
      'Canada',
      'R7A 0A1',
      49.8481,
      -99.95
    );
    rtms__Load__c load = PricingTestDataFactory.createLoad(
      g,
      originLoc,
      destLoc
    );
    f.cadQuoteCount = 2;
    insert new List<rtms__CarrierQuote__c>{
      PricingTestDataFactory.buildQuote(g, load, 1000),
      PricingTestDataFactory.buildQuote(g, load, 1200),
      PricingTestDataFactory.buildQuote(g, load, 1500, 'USD')
    };
    return f;
  }

  /**
   * Both sources on one lane, with distinct known counts, so the two Ruling 9 gate tests (and
   * the both-gates-fire test) can prove each gate suppresses exactly one side and not the other.
   */
  private static LaneTrendFixture withQuotesAndBids() {
    Pricing_Place__c origin = RfpTestDataFactory.createPlace(
      'Halifax',
      'NS',
      'CA',
      44.6488,
      -63.5752,
      'B3H'
    );
    Pricing_Place__c destination = RfpTestDataFactory.createPlace(
      'Moncton',
      'NB',
      'CA',
      46.0878,
      -64.7782,
      'E1C'
    );
    LaneTrendFixture f = forPlaces(origin, destination);

    PricingTestDataFactory.Graph g = PricingTestDataFactory.createGraph();
    Account originLoc = PricingTestDataFactory.createLocation(
      'Origin Co',
      'Halifax',
      'Nova Scotia',
      'Canada',
      'B3H 0A1',
      44.6488,
      -63.5752
    );
    Account destLoc = PricingTestDataFactory.createLocation(
      'Destination Co',
      'Moncton',
      'New Brunswick',
      'Canada',
      'E1C 0A1',
      46.0878,
      -64.7782
    );
    rtms__Load__c load = PricingTestDataFactory.createLoad(
      g,
      originLoc,
      destLoc
    );
    f.quoteCount = 4;
    List<rtms__CarrierQuote__c> quotes = new List<rtms__CarrierQuote__c>();
    for (Integer i = 0; i < f.quoteCount; i++) {
      quotes.add(PricingTestDataFactory.buildQuote(g, load, 1000 + i * 10));
    }
    insert quotes;

    RFP_Project__c project = RfpTestDataFactory.createProject(g.customer);
    RFP_Lane__c lane = RfpTestDataFactory.createLane(
      project,
      origin,
      destination
    );
    f.bidCount = 3;
    List<Benchmark_Rate__c> bids = new List<Benchmark_Rate__c>();
    for (Integer i = 0; i < f.bidCount; i++) {
      bids.add(RfpTestDataFactory.buildBid(lane, 2000 + i * 10));
    }
    insert bids;
    return f;
  }

  /**
   * Ruling 11's fixture: one bid whose CreatedDate is now (so it matches the search's own
   * CreatedDate = LAST_N_DAYS WHERE, and whose Valid_From__c/Expires_On__c keep it "still valid"
   * too) but whose Valid_From__c - the field the chart buckets on - sits well outside the window.
   * This is the real-world shape D2/Ruling 11 describe: a row the search legitimately matches, on a
   * date the chart cannot place on its own axis. Benchmark_Rate__c.Valid_From__c is a plain field a
   * pricer sets by hand, unlike rtms__CarrierQuote__c.Quote_Date__c/Shipping_Date__c, which resolve
   * through a chain of non-writable formula fields (Shipping_Date__c ->
   * rtms__Load__r.rtms__Expected_Ship_Date2__c, confirmed non-createable/non-updateable via
   * `sf sobject describe rtms__Load__c`) - so a bid is the fixture that can actually construct this
   * shape directly instead of guessing at an undocumented managed-package field chain.
   */
  private static LaneTrendFixture withABidOutsideTheWindow() {
    Pricing_Place__c origin = RfpTestDataFactory.createPlace(
      'Kelowna',
      'BC',
      'CA',
      49.888,
      -119.496,
      'V1Y'
    );
    Pricing_Place__c destination = RfpTestDataFactory.createPlace(
      'Kamloops',
      'BC',
      'CA',
      50.6745,
      -120.3273,
      'V2C'
    );
    LaneTrendFixture f = forPlaces(origin, destination);

    PricingTestDataFactory.Graph g = PricingTestDataFactory.createGraph();
    RFP_Project__c project = RfpTestDataFactory.createProject(g.customer);
    RFP_Lane__c lane = RfpTestDataFactory.createLane(
      project,
      origin,
      destination
    );
    Benchmark_Rate__c bid = RfpTestDataFactory.buildBid(lane, 1000);
    bid.Valid_From__c = Date.today().addDays(-400);
    insert bid;
    return f;
  }

  /**
   * Reviewer finding (Important 3): every other fixture puts all its rates in one calendar month
   * (a quote's Quote_Date__c defaults to DATEVALUE(CreatedDate) = today; RfpTestDataFactory.buildBid
   * sets Valid_From__c = today), so summarise()'s two-or-more-solid-months half never runs in any of
   * them - solid.size() < 2 returns early every time. Three bids per month (never fewer than
   * THIN_COUNT, so none is thin) two calendar months apart, anchored on Date.today().addMonths()
   * rather than a fixed day offset so this is correct on every day of the year, not just the day it
   * was written.
   */
  private static LaneTrendFixture withBidsAcrossThreeMonths() {
    Pricing_Place__c origin = RfpTestDataFactory.createPlace(
      'Nanaimo',
      'BC',
      'CA',
      49.1659,
      -123.9401,
      'V9R'
    );
    Pricing_Place__c destination = RfpTestDataFactory.createPlace(
      'Victoria',
      'BC',
      'CA',
      48.4284,
      -123.3656,
      'V8W'
    );
    LaneTrendFixture f = forPlaces(origin, destination);

    PricingTestDataFactory.Graph g = PricingTestDataFactory.createGraph();
    RFP_Project__c project = RfpTestDataFactory.createProject(g.customer);
    RFP_Lane__c lane = RfpTestDataFactory.createLane(
      project,
      origin,
      destination
    );
    List<Benchmark_Rate__c> bids = new List<Benchmark_Rate__c>();
    bids.addAll(threeBidsOn(lane, Date.today().addMonths(-2), 1000));
    bids.addAll(threeBidsOn(lane, Date.today().addMonths(-1), 1100));
    bids.addAll(threeBidsOn(lane, Date.today(), 1300));
    insert bids;
    return f;
  }

  private static List<Benchmark_Rate__c> threeBidsOn(
    RFP_Lane__c lane,
    Date validFrom,
    Decimal rate
  ) {
    List<Benchmark_Rate__c> bids = new List<Benchmark_Rate__c>();
    for (Integer i = 0; i < 3; i++) {
      Benchmark_Rate__c bid = RfpTestDataFactory.buildBid(lane, rate);
      bid.Valid_From__c = validFrom;
      bids.add(bid);
    }
    return bids;
  }

  /**
   * Ruling 13's fixture: three bids well outside the window (Valid_From__c 400 days back, the same
   * construction withABidOutsideTheWindow() uses) and three inside it (Valid_From__c today), with a
   * cap of 3 - enough to admit exactly one group's rows, not both. DESC keeps the newest (in-window)
   * three; ASC would keep the oldest (out-of-window) three instead, which Ruling 11 then drops
   * entirely - the two-way discriminator Ruling 13's own test needs. Both groups satisfy the bid
   * WHERE's own validity check regardless of Valid_From__c, because buildBid's default
   * Expires_On__c (today + 30) is independent of it - the same fact withABidOutsideTheWindow()
   * already relies on.
   */
  private static LaneTrendFixture withOldAndNewBidsBeyondTheCap() {
    Pricing_Place__c origin = RfpTestDataFactory.createPlace(
      'Prince George',
      'BC',
      'CA',
      53.9171,
      -122.7497,
      'V2L'
    );
    Pricing_Place__c destination = RfpTestDataFactory.createPlace(
      'Fort St John',
      'BC',
      'CA',
      56.2499,
      -120.8529,
      'V1J'
    );
    LaneTrendFixture f = forPlaces(origin, destination);

    PricingTestDataFactory.Graph g = PricingTestDataFactory.createGraph();
    RFP_Project__c project = RfpTestDataFactory.createProject(g.customer);
    RFP_Lane__c lane = RfpTestDataFactory.createLane(
      project,
      origin,
      destination
    );
    List<Benchmark_Rate__c> bids = new List<Benchmark_Rate__c>();
    bids.addAll(threeBidsOn(lane, Date.today().addDays(-400), 1000));
    bids.addAll(threeBidsOn(lane, Date.today(), 2000));
    insert bids;
    return f;
  }

  /**
   * D7, and the test that makes it real rather than asserted: a lane whose only rates are
   * market-test plots them under Include and plots nothing under Exclude. Without this, the chart
   * and the median printed directly above it can describe different row sets.
   */
  @IsTest
  static void excludeMovesTheChart() {
    LaneTrendFixture f = withMarketTestRatesOnly();

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
    LaneTrendFixture f = withQuotes(5);
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
    System.assertEquals(
      2,
      trend.totalRates,
      'the read itself must be bound by the override (cap), not ROW_CAP - otherwise this test would ' +
        'still pass while the read quietly pulled all 5 rows and risked the very LimitException the ' +
        'guard exists to avoid'
    );
  }

  /**
   * Ruling 12: the LIMIT that backs the guard is per side, not a shared budget - readQuoteSamples
   * and readBidSamples each bind the same cap into their own :trendRowCap. So a request whose
   * combined total exceeds the cap but whose two sides individually stay under it never actually
   * loses a row, and truncated must say so - a warning that fires on a complete chart is one a
   * pricer learns to ignore.
   */
  @IsTest
  static void truncatedStaysFalseWhenOnlyTheCombinedTotalExceedsTheCap() {
    LaneTrendFixture f = withQuotesAndBids();
    LaneTrendService.rowCapOverride = 5;

    Test.startTest();
    LaneTrend trend = LaneTrendService.trendFor(f.request());
    Test.stopTest();

    System.assertEquals(
      false,
      trend.truncated,
      'quoteCount (' +
        f.quoteCount +
        ') and bidCount (' +
        f.bidCount +
        ') each individually stay under the cap of 5, even though their sum (' +
        (f.quoteCount + f.bidCount) +
        ') does not - neither side\'s own LIMIT was hit, so nothing was actually dropped'
    );
    System.assertEquals(
      f.quoteCount + f.bidCount,
      trend.totalRates,
      'every row from both sides made it into the chart, confirming nothing was truncated'
    );
  }

  /**
   * Reviewer finding (Important 1): >= at the truncated line survives every existing test, because
   * none of them puts a side's own count exactly AT the cap. A LIMIT of N returns every one of
   * exactly N matching rows - nothing is dropped - so a count equal to the cap must not warn.
   * quoteCount (4) == rowCapOverride (4) here pins that exact boundary.
   */
  @IsTest
  static void truncatedStaysFalseWhenASideExactlyMeetsTheCap() {
    LaneTrendFixture f = withQuotesAndBids();
    LaneTrendService.rowCapOverride = f.quoteCount;

    Test.startTest();
    LaneTrend trend = LaneTrendService.trendFor(f.request());
    Test.stopTest();

    System.assertEquals(
      false,
      trend.truncated,
      'quoteRows (' +
        f.quoteCount +
        ') is exactly the cap (' +
        f.quoteCount +
        '), so its own LIMIT returned every matching row - a >= here would wrongly warn'
    );
  }

  /**
   * Reviewer finding (Important 2): the oversized-window test above is quotes-only, and the
   * combined-total test keeps both sides under their cap, so `|| bidRows > cap` is never actually
   * exercised - deleting it outright leaves every existing test green. sourceFilter = BIDS closes
   * the quote gate (quoteRows forced to 0), isolating the bid half of the formula.
   */
  @IsTest
  static void truncatedFiresWhenOnlyTheBidSideExceedsItsOwnCap() {
    LaneTrendFixture f = withQuotesAndBids();
    LaneSearchRequest req = f.request();
    req.sourceFilter = LaneSearchRequest.RowSource.BIDS;
    LaneTrendService.rowCapOverride = 2;

    Test.startTest();
    LaneTrend trend = LaneTrendService.trendFor(req);
    Test.stopTest();

    System.assertEquals(
      true,
      trend.truncated,
      'bidRows (' +
        f.bidCount +
        ') exceeds the cap (2) with the quote side gated off entirely - only the bid half of the ' +
        'formula could have caught this'
    );
  }

  /** D6: one currency at a time, never two on one axis. */
  @IsTest
  static void neverMixesCurrencies() {
    LaneTrendFixture f = withQuotesInBothCurrencies();
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

  /**
   * Ruling 9: sourceFilter = BIDS switches the quote side off in LaneTrendService itself (there is
   * no null-returning query builder to hook into for quotes, unlike bids) - exactly as
   * LaneSearchService.search() does at its lines 29-32. Bids still count, so a leaked quote would
   * show up as more rows than bidCount alone.
   */
  @IsTest
  static void sourceFilterBidsProducesNoQuoteSamples() {
    LaneTrendFixture f = withQuotesAndBids();
    LaneSearchRequest req = f.request();
    req.sourceFilter = LaneSearchRequest.RowSource.BIDS;

    Test.startTest();
    LaneTrend trend = LaneTrendService.trendFor(req);
    Test.stopTest();

    System.assertEquals(
      f.bidCount,
      trend.totalRates,
      'the quote rows must not leak into a BIDS-only trend'
    );
  }

  /**
   * Ruling 8/9: BidSearchQueryBuilder.canMatchBids refuses a request whose sourceFilter is LOADS,
   * and LaneTrendQueries.bidSoql/.bidCountSoql signal that with a null return - LaneTrendService
   * must treat that as zero bid rows rather than deriving the rule itself. LOADS (not an accepted
   * filter) isolates the bid gate alone: the quote gate only fires on sourceFilter == BIDS, so
   * quotes still come through and prove they were never touched.
   */
  @IsTest
  static void aRequestThatCanMatchBidsRefusesProducesNoBidSamples() {
    LaneTrendFixture f = withQuotesAndBids();
    LaneSearchRequest req = f.request();
    req.sourceFilter = LaneSearchRequest.RowSource.LOADS;

    Test.startTest();
    LaneTrend trend = LaneTrendService.trendFor(req);
    Test.stopTest();

    System.assertEquals(
      f.quoteCount,
      trend.totalRates,
      'the bid rows must not leak into a LOADS-only trend'
    );
  }

  /**
   * When both gates fire at once (quote side off via sourceFilter == BIDS, bid side refused by
   * canMatchBids because acceptedFilter is not ANY_STATUS), trendFor returns an empty-but-valid
   * LaneTrend rather than throwing - and still carries the window it was asked for.
   */
  @IsTest
  static void bothGatesFiringLeavesAnEmptyTrendRatherThanThrowing() {
    LaneTrendFixture f = withQuotesAndBids();
    LaneSearchRequest req = f.request();
    req.sourceFilter = LaneSearchRequest.RowSource.BIDS;
    req.acceptedFilter = LaneSearchRequest.Accepted.ACCEPTED;

    Test.startTest();
    LaneTrend trend = LaneTrendService.trendFor(req);
    Test.stopTest();

    System.assertEquals(
      0,
      trend.totalRates,
      'both sides are gated off, so there is nothing to plot'
    );
    System.assert(trend.points.isEmpty(), 'no points when both gates fire');
    System.assertEquals(
      req.lookbackDays,
      trend.lookbackDays,
      'an empty trend still carries the window it was asked for'
    );
    System.assertNotEquals(
      null,
      trend.monthSpan,
      'the axis size is still set even when there is nothing to plot on it'
    );
  }

  /**
   * Ruling 11: a row can match the search's own WHERE (CreatedDate recent, still within its
   * validity window) and still bucket outside the chart's axis, because the WHERE filters on
   * CreatedDate while the chart buckets on Valid_From__c/Quote_Date__c. It must be dropped rather
   * than clamped onto the axis, and counted rather than silently vanishing - and the summary
   * (totalRates) must describe only what is actually plotted.
   */
  @IsTest
  static void aSampleOutsideTheWindowIsDroppedAndCounted() {
    LaneTrendFixture f = withABidOutsideTheWindow();

    Test.startTest();
    LaneTrend trend = LaneTrendService.trendFor(f.request());
    Test.stopTest();

    System.assertEquals(
      1,
      trend.outsideWindow,
      'the one bid sits 400 days before the window and must be counted, not silently dropped'
    );
    System.assertEquals(
      0,
      trend.totalRates,
      'the dropped row must not count toward the summary either, or the sentence under the chart would describe a row the chart does not draw'
    );
    System.assert(
      trend.points.isEmpty(),
      'nothing left to plot once the only row is outside the window'
    );
    System.assert(
      trend.overallMedian == null,
      'pre-fix this read 1000 (the dropped bid\'s own rate) - summarise must run on the kept ' +
        'samples only, not the merged list Ruling 11 drops from: ' +
        trend.overallMedian
    );
  }

  /**
   * Reviewer finding (Important 3): summarise()'s summary half - changePct, firstLabel, lastLabel,
   * overallMedian - has never run in any prior test, because every prior fixture puts all its rates
   * in one calendar month. Three months of rising rates pins the direction (and, incidentally, the
   * exact setScale(1) value): swap earliest and latest inside summarise and this flips sign and
   * fails.
   */
  @IsTest
  static void summariseComputesLabelsAndTheSignOfChangeAcrossMonths() {
    LaneTrendFixture f = withBidsAcrossThreeMonths();
    String expectedFirstLabel = monthLabel(Date.today().addMonths(-2));
    String expectedLastLabel = monthLabel(Date.today());

    Test.startTest();
    LaneTrend trend = LaneTrendService.trendFor(f.request());
    Test.stopTest();

    System.assertEquals(
      expectedFirstLabel,
      trend.firstLabel,
      'the earliest of the three solid months'
    );
    System.assertEquals(
      expectedLastLabel,
      trend.lastLabel,
      'the latest of the three solid months'
    );
    System.assert(
      trend.changePct == 30.0,
      'rates rose from a median of 1000 (earliest month) to 1300 (latest): (1300-1000)/1000*100 = ' +
        '30.0 - a swapped earliest/latest would read -23.1 instead: ' +
        trend.changePct
    );
    System.assert(
      trend.overallMedian == 1100,
      'nine rates (1000 x3, 1100 x3, 1300 x3): the middle value is 1100: ' +
      trend.overallMedian
    );
  }

  /**
   * Ruling 14: a blank request currency lets both CAD and USD through the query, and D6 forbids
   * plotting both on one axis. The chart must pick one - the currency with the more usable samples -
   * and say which on trend.currencyIsoCode rather than blending them into one meaningless median.
   */
  @IsTest
  static void blankCurrencyPicksTheOneWithMoreUsableSamples() {
    LaneTrendFixture f = withQuotesInBothCurrencies();
    LaneSearchRequest req = f.request();

    Test.startTest();
    LaneTrend trend = LaneTrendService.trendFor(req);
    Test.stopTest();

    System.assertEquals(
      'CAD',
      trend.currencyIsoCode,
      'CAD has ' +
        f.cadQuoteCount +
        ' usable samples against USD\'s 1 - the chart must say which currency it chose'
    );
    System.assertEquals(
      f.cadQuoteCount,
      trend.totalRates,
      'only the chosen currency\'s rows are plotted - the USD row must not leak into this median'
    );
  }

  /**
   * Ruling 13: DESC, not ASC. Three bids sit 400 days outside the window and three sit inside it;
   * rowCapOverride admits only one group's worth of rows. Under DESC (correct) the LIMIT keeps the
   * newest three - all in-window - so the chart still has points and nothing was dropped. Under ASC
   * (the reverted bug, checked by hand against this exact test before this method was trusted) the
   * LIMIT keeps the oldest three - all out-of-window - and Ruling 11 drops every one of them, so a
   * busy, truncated lane would go quiet on its most recent months while the page only says "may be
   * incomplete."
   */
  @IsTest
  static void orderingKeepsTheNewestRowsWithinTheCap() {
    LaneTrendFixture f = withOldAndNewBidsBeyondTheCap();
    LaneTrendService.rowCapOverride = 3;

    Test.startTest();
    LaneTrend trend = LaneTrendService.trendFor(f.request());
    Test.stopTest();

    System.assert(
      !trend.points.isEmpty(),
      'ASC ordering would let the LIMIT keep the three oldest (out-of-window) bids instead of the ' +
        'three newest, emptying the chart of its most recent month entirely - outsideWindow was ' +
        trend.outsideWindow
    );
    System.assertEquals(
      0,
      trend.outsideWindow,
      'the three rows the LIMIT actually kept must be the in-window ones, not the out-of-window ' +
      'ones ASC would have kept instead'
    );
  }
}
