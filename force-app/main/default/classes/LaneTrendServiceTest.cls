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

  /**
   * The zero is the boundary that matters, and it was the one this method did not have: a null date
   * and a null amount were both pinned, but a real zero-total row - 2.9% of PostProduc's quotes over
   * a year - passed straight through into the median LaneSearchService.stats() excludes it from, and
   * pinned that month's minimum to 0, which anchors the chart's y axis at zero and squashes the
   * median line into the top of the frame.
   *
   * Mutation: drop `amount != 0` from LaneTrendSummary.isUsable and both assertions below go red -
   * count reads 2 and minimum reads 0.
   */
  @IsTest
  static void ignoresSamplesWithNoDateNoAmountOrAZeroAmount() {
    List<LaneTrendService.Sample> samples = new List<LaneTrendService.Sample>{
      s('2026-01-05', 1000),
      new LaneTrendService.Sample(null, 5000),
      new LaneTrendService.Sample(Date.newInstance(2026, 1, 9), null),
      s('2026-01-12', 0)
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
      'a rate with no date cannot be placed on a time axis, one with no amount is not a rate, and a zero total is not a price the market set'
    );
    System.assert(
      points[0].minimum == 1000,
      'a kept zero would pin this month\'s minimum - and with it the chart\'s y axis - to 0: ' +
      points[0].minimum
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
   * One bid recorded now whose Valid_From__c sits 400 days back: a rate the search matches on
   * CreatedDate, still valid (buildBid's Expires_On__c is today + 30, independent of Valid_From__c),
   * and dated - by the field the trend used to bucket on - far off the left of the axis.
   *
   * This is the shape the removed window partition silently deleted, and the only shape that can
   * distinguish the two candidate bucketing fields on a writable date. Benchmark_Rate__c.Valid_From__c
   * is a plain field a pricer sets by hand, unlike rtms__CarrierQuote__c.Quote_Date__c /
   * Shipping_Date__c, which resolve through a chain of non-writable formula fields (Shipping_Date__c
   * -> rtms__Load__r.rtms__Expected_Ship_Date2__c, confirmed non-createable/non-updateable via
   * `sf sobject describe rtms__Load__c`) - so a bid is the fixture that can construct it directly
   * instead of guessing at an undocumented managed-package field chain.
   */
  private static LaneTrendFixture withABidWhoseValidFromIsLongPast() {
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
   * Reviewer finding (Important 3): every other fixture puts all its rates in one calendar month, so
   * summarise()'s two-or-more-solid-months half never runs in any of them - solid.size() < 2 returns
   * early every time. Three bids per month (never fewer than THIN_COUNT, so none is thin) in three
   * consecutive calendar months, anchored on Date.today().addMonths() rather than a fixed day offset
   * so this is correct on every day of the year, not just the day it was written.
   *
   * Placed by CreatedDate, which is what the trend buckets on: Valid_From__c no longer decides which
   * month a rate lands in, so setting it here would place nothing. CreatedDate is not writable, and
   * Test.setCreatedDate is the supported way to put a record in a past month - see createdOn().
   * Two months back is at most 62 days, so all three groups still sit inside the request's default
   * 90-day window and none is filtered out by the search's own WHERE.
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
    List<Benchmark_Rate__c> twoMonthsBack = threeBidsOn(
      lane,
      Date.today(),
      1000,
      'CAD'
    );
    List<Benchmark_Rate__c> oneMonthBack = threeBidsOn(
      lane,
      Date.today(),
      1100,
      'CAD'
    );
    List<Benchmark_Rate__c> bids = new List<Benchmark_Rate__c>();
    bids.addAll(twoMonthsBack);
    bids.addAll(oneMonthBack);
    bids.addAll(threeBidsOn(lane, Date.today(), 1300, 'CAD'));
    insert bids;
    createdOn(twoMonthsBack, Date.today().addMonths(-2));
    createdOn(oneMonthBack, Date.today().addMonths(-1));
    return f;
  }

  /**
   * Puts already-inserted records in a past month, which is the only way a fixture can now choose a
   * bucket: the trend buckets on CreatedDate, CreatedDate is not writable, and Test.setCreatedDate
   * is the supported substitute. It needs an Id, so callers insert first and place afterwards.
   *
   * Noon local rather than midnight, so the Datetime.date() the service buckets with and the
   * LAST_N_DAYS boundary the query filters with agree on the day whatever the running user's time
   * zone is. There is deliberately no future-dating counterpart: CreatedDate cannot be set ahead of
   * now, which is half of why the trend buckets on it.
   */
  private static void createdOn(List<Benchmark_Rate__c> bids, Date day) {
    Datetime at = Datetime.newInstance(day, Time.newInstance(12, 0, 0, 0));
    for (Benchmark_Rate__c b : bids) {
      Test.setCreatedDate(b.Id, at);
    }
  }

  /**
   * Three bids valid from the same day, in one currency. Valid_From__c decides only whether the bid
   * search's own validity check matches the row; which month the chart buckets it into is decided by
   * CreatedDate, so a fixture that wants a past month calls createdOn() after inserting.
   *
   * currencyCode is a parameter rather than a
   * second overload because Ruling 19's and Ruling 20's fixtures both need a non-CAD group, and an
   * overload's own method body would have cost this test class a cyclomatic-complexity point it
   * does not have (35 of PMD's 39-point ceiling before this round). "currency" is a reserved Apex
   * identifier, hence currencyCode - see LaneTrendScope.samplesInCurrency.
   */
  private static List<Benchmark_Rate__c> threeBidsOn(
    RFP_Lane__c lane,
    Date validFrom,
    Decimal rate,
    String currencyCode
  ) {
    List<Benchmark_Rate__c> bids = new List<Benchmark_Rate__c>();
    for (Integer i = 0; i < 3; i++) {
      Benchmark_Rate__c bid = RfpTestDataFactory.buildBid(lane, rate);
      bid.Valid_From__c = validFrom;
      bid.CurrencyIsoCode = currencyCode;
      bids.add(bid);
    }
    return bids;
  }

  /**
   * Ruling 13's fixture: three bids created thirteen months ago and three created now, with a cap of
   * 3 - enough to admit exactly one group's rows, not both. Both groups are inside the window the
   * test asks for (1095 days), which is what makes this a test of ORDER BY rather than of filtering:
   * DESC spends the cap on the newest months, ASC on the oldest, and a truncated chart that goes
   * quiet on the months a pricer actually reads is the failure Ruling 13 exists to prevent. Both
   * groups satisfy the bid WHERE's own validity check, because buildBid's Valid_From__c (today) and
   * Expires_On__c (today + 30) are independent of CreatedDate.
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
    List<Benchmark_Rate__c> earlier = threeBidsOn(
      lane,
      Date.today(),
      1000,
      'CAD'
    );
    List<Benchmark_Rate__c> bids = new List<Benchmark_Rate__c>();
    bids.addAll(earlier);
    bids.addAll(threeBidsOn(lane, Date.today(), 2000, 'CAD'));
    insert bids;
    createdOn(earlier, Date.today().addMonths(-13));
    return f;
  }

  /**
   * Ruling 20's fixture: an exact tie - three usable CAD bids and three usable USD bids, all inside
   * the window, all on the same day. Which currency wins is arbitrary; that the same one wins every
   * run is not, and nothing in the majority count itself can break this tie.
   */
  private static LaneTrendFixture withATieBetweenTwoCurrencies() {
    Pricing_Place__c origin = RfpTestDataFactory.createPlace(
      'Lethbridge',
      'AB',
      'CA',
      49.6956,
      -112.8451,
      'T1J'
    );
    Pricing_Place__c destination = RfpTestDataFactory.createPlace(
      'Medicine Hat',
      'AB',
      'CA',
      50.0405,
      -110.6764,
      'T1A'
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
    bids.addAll(threeBidsOn(lane, Date.today(), 1000, 'CAD'));
    bids.addAll(threeBidsOn(lane, Date.today(), 7000, 'USD'));
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
   * The successor to the window partition, and the guard that replaces it: a row the search's WHERE
   * matched is a row the chart can place, because the trend now buckets on the very field that WHERE
   * filters (CreatedDate). This fixture is the shape that used to be silently deleted - a bid the
   * search legitimately matches whose Valid_From__c sits 400 days back - and the axis position is
   * asserted, not just the presence of a point.
   *
   * Mutations: bucket on Valid_From__c again (the old behaviour) and monthIndex reads about -13,
   * far off the left of the axis; re-add a post-read window partition on top of CreatedDate
   * bucketing and it changes nothing, which is the point - but bucket on Valid_From__c *with* the
   * partition, the exact pre-fix code, and totalRates reads 0.
   */
  @IsTest
  static void aRowTheSearchMatchedIsAlwaysPlacedOnTheAxis() {
    LaneTrendFixture f = withABidWhoseValidFromIsLongPast();

    Test.startTest();
    LaneTrend trend = LaneTrendService.trendFor(f.request());
    Test.stopTest();

    System.assertEquals(
      1,
      trend.totalRates,
      'the bid matched the search\'s own CreatedDate window, so the chart must count it rather than delete the freshest evidence it has'
    );
    System.assertEquals(
      1,
      trend.points.size(),
      'one rate, one month, one point'
    );
    System.assertEquals(
      trend.monthSpan - 1,
      trend.points[0].monthIndex,
      'the evidence arrived this month - the last slot on the axis - whatever Valid_From__c says about when the freight moves'
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
   * Ruling 13: DESC, not ASC. Three bids were created thirteen months ago and three now; the window
   * is three years, so the WHERE admits all six and rowCapOverride admits only three. Truncation is
   * therefore certain, and the only question is which months' worth of evidence survives it. DESC
   * spends the cap on the newest rows; ASC spends it on the oldest, and a busy lane would go quiet on
   * exactly the months a pricer reads while the page only says "may be incomplete."
   *
   * Mutation: change ORDER BY CreatedDate DESC to ASC in LaneTrendQueries.bidSoql and the surviving
   * month is the one thirteen months back, so the monthIndex assertion below goes red.
   */
  @IsTest
  static void orderingKeepsTheNewestRowsWithinTheCap() {
    LaneTrendFixture f = withOldAndNewBidsBeyondTheCap();
    LaneSearchRequest req = f.request();
    req.lookbackDays = 1095;
    LaneTrendService.rowCapOverride = 3;

    Test.startTest();
    LaneTrend trend = LaneTrendService.trendFor(req);
    Test.stopTest();

    System.assertEquals(
      true,
      trend.truncated,
      'six rows against a cap of three: the chart must say it may be incomplete'
    );
    System.assertEquals(
      1,
      trend.points.size(),
      'the three rows that fitted the cap all came from one month'
    );
    System.assertEquals(
      trend.monthSpan - 1,
      trend.points[0].monthIndex,
      'the surviving month must be the current one - ASC would have spent the cap on bids created thirteen months ago and left the recent months blank'
    );
    System.assertEquals(
      3,
      trend.totalRates,
      'exactly the three rows the cap admitted are plotted and summarised'
    );
  }

  /**
   * Ruling 20: three usable CAD samples against three usable USD samples is an exact tie, and
   * nothing in the counts themselves can break it. Unsorted, the winner is the first key the count
   * map yields - Apex's Map<String, Integer> was observed to iterate in insertion order, i.e. the
   * order the rows came back from SOQL, and rows tied on the ORDER BY key have no guaranteed order -
   * so the same lane could render as CAD one run and USD the next. The tie-break is deliberately
   * alphabetical: which currency wins is arbitrary, that the same one wins every time is not, and
   * the chart states the currency it plotted so a stable arbitrary pick misleads nobody.
   *
   * Honest about its own strength: this passed against the pre-fix code too (CAD happened to come
   * back first), so it is not a demonstrated red. What it does catch deterministically is a
   * tie-break that resolves the other way - > relaxed to >= over the sorted codes picks USD, and
   * this fails.
   */
  @IsTest
  static void aTieBetweenCurrenciesPicksTheAlphabeticallyFirst() {
    LaneTrendFixture f = withATieBetweenTwoCurrencies();

    Test.startTest();
    LaneTrend trend = LaneTrendService.trendFor(f.request());
    Test.stopTest();

    System.assertEquals(
      'CAD',
      trend.currencyIsoCode,
      'CAD and USD hold three usable samples each: the tie must resolve alphabetically rather than ' +
      'by whatever order the count map happens to iterate in'
    );
    System.assertEquals(
      3,
      trend.totalRates,
      'one currency only - six rates here would mean CAD and USD had been blended onto one axis'
    );
  }
}
