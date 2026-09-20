/**
 * Phase 10: the lane trend's thin Apex surface. Almost everything here is delegation, so the
 * interesting behaviour is what happens at the edges - a request the page cannot serialise, and
 * LaneTrendService's own validation - which must read like LaneBenchmarkController.search's own
 * user errors (Ruling 16), and excludeProjectId, which must be normalised the same way search
 * normalises it before either one reaches the shared system-mode bid query (Ruling 17).
 */
@IsTest
private class LaneTrendControllerTest {
  /**
   * Test data belongs to its own test class (LaneTrendServiceTest's fixture is not shared), so this
   * is a small duplicate of that class's LaneTrendFixture/forPlaces/withQuotes shape, with its own
   * places to avoid a Pricing_Place__c DUPLICATE_VALUE against anything another method here builds.
   */
  private class LaneTrendFixture {
    String originKey;
    String destinationKey;

    LaneSearchRequest request() {
      LaneSearchRequest r = new LaneSearchRequest();
      r.originKey = originKey;
      r.destinationKey = destinationKey;
      return r;
    }
  }

  // Apex forbids static members on an inner class, so the fixture's factory methods live here on
  // the outer test class, as LaneTrendServiceTest's do.

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
    LaneSearchExclusions.excludedContactIdsOverride = new Set<String>();
    return f;
  }

  private static LaneTrendFixture withQuotes(Integer count) {
    Pricing_Place__c origin = RfpTestDataFactory.createPlace(
      'Halifax',
      'NS',
      'CA',
      44.6488,
      -63.5752,
      'B3J'
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
      'B3J 0A1',
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
    List<rtms__CarrierQuote__c> quotes = new List<rtms__CarrierQuote__c>();
    for (Integer i = 0; i < count; i++) {
      quotes.add(PricingTestDataFactory.buildQuote(g, load, 1000 + i * 10));
    }
    insert quotes;
    return f;
  }

  @IsTest
  static void returnsTheTrendForARequestThePageAlreadyHolds() {
    LaneTrendFixture f = withQuotes(4);
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
    } catch (AuraHandledException e) {
      threw = true;
      System.assertEquals(
        'The trend could not be read. Please reset the filters and try again.',
        e.getMessage(),
        'the page shows a sentence, not a parse error'
      );
    }
    Test.stopTest();
    System.assertEquals(true, threw);
  }

  /**
   * Ruling 16: LaneTrendService.trendFor validates first and throws LaneSearchException for a bad
   * lookback, row limit, radius, currency or zip3, exactly as LaneSearchRequest.validate() does for
   * LaneBenchmarkController.search. getTrend must convert it the same way, with the same message -
   * not the generic "could not be read" sentence above, which belongs to the JSON parse failure
   * only. Catching AuraHandledException specifically (not Exception) and asserting the field-
   * specific message with assertEquals means this goes red both if the catch is deleted (the raw
   * LaneSearchException, a different type, escapes the narrower catch and fails the whole test) and
   * if it is made to swallow (threw stays false).
   */
  @IsTest
  static void anInvalidRequestIsAUserErrorRatherThanAStackTrace() {
    LaneSearchRequest req = new LaneSearchRequest();
    req.rowLimit = 0;
    String requestJson = JSON.serialize(req);

    Boolean threw = false;
    Test.startTest();
    try {
      LaneTrendController.getTrend(requestJson);
    } catch (AuraHandledException e) {
      threw = true;
      System.assertEquals(
        'rowLimit must be between 1 and 2000',
        e.getMessage(),
        'the page shows the exact sentence LaneSearchRequest.validate() throws, not a generic error'
      );
    }
    Test.stopTest();
    System.assertEquals(true, threw);
  }

  /**
   * The trend runs the search's own WHERE - RADIUS DISTANCE() predicates included - over as much as
   * 1095 days where a search runs 90, so it is strictly likelier than the search to be refused by
   * the platform. LaneBenchmarkController.search already translates QueryException into a sentence
   * a pricer can act on; getTrend caught only LaneSearchException, so the same failure reached the
   * component's error line as a raw platform string on a page whose search had just worked. D3's
   * row guard cannot stand in for this: the guard's own COUNT() is the first query trendFor runs,
   * which is exactly where the throw comes from - so LaneTrendQueries.breakCountForTest breaks the
   * count, not the read.
   *
   * Mutation: delete the catch (QueryException) arm and the raw QueryException - a different type -
   * escapes the narrower catch (AuraHandledException) below, failing the whole method; make the arm
   * swallow instead and threw stays false. Either way this goes red.
   */
  @IsTest
  static void aQueryThePlatformRefusesIsAUserErrorRatherThanAPlatformString() {
    LaneTrendFixture f = withQuotes(1);
    String requestJson = JSON.serialize(f.request());
    LaneTrendQueries.breakCountForTest = true;

    Boolean threw = false;
    Test.startTest();
    try {
      LaneTrendController.getTrend(requestJson);
    } catch (AuraHandledException e) {
      threw = true;
      System.assertEquals(
        true,
        e.getMessage()
          .startsWith(
            'The trend took too long or returned too much data. Narrow the window or the radius and try again. ('
          ),
        'the page shows the advice LaneBenchmarkController.search already gives, with the platform detail in brackets, not instead of it: ' +
        e.getMessage()
      );
    }
    Test.stopTest();
    System.assertEquals(true, threw);
  }

  /**
   * Ruling 17: excludeProjectId binds into a system-mode bid query that LaneTrendService.trendFor
   * shares with LaneSearchService.search (BidSearchQueryBuilder.whereFor), so the trend must apply
   * LaneBenchmarkController.readableProject()'s own read check before delegating - otherwise a
   * caller who cannot read the project would still have its bids excluded (an access path the
   * search itself does not allow, spec §5/§6). Mirrors
   * LaneBenchmarkControllerTest.searchExcludesAProjectOnlyWhenTheCallerCanReadIt. Mutation: deleting
   * the normalisation line (exclusion always applied) drops viewerRates to 0; applying it backwards
   * (exclusion never applied) raises adminRates to 1 - either way one of the two assertEquals below
   * goes red.
   */
  @IsTest
  static void excludesAProjectsBidOnlyWhenTheCallerCanReadTheProject() {
    Pricing_Place__c origin = RfpTestDataFactory.createPlace(
      'Saint John',
      'NB',
      'CA',
      45.2733,
      -66.0633,
      'E2K'
    );
    Pricing_Place__c destination = RfpTestDataFactory.createPlace(
      'Fredericton',
      'NB',
      'CA',
      45.9636,
      -66.6431,
      'E3B'
    );
    LaneTrendFixture f = forPlaces(origin, destination);

    PricingTestDataFactory.Graph g = PricingTestDataFactory.createGraph();
    RFP_Project__c project = RfpTestDataFactory.createProject(g.customer);
    RFP_Lane__c lane = RfpTestDataFactory.createLane(
      project,
      origin,
      destination
    );
    BenchmarkRateService.save(RfpTestDataFactory.buildBid(lane, 1500));

    LaneSearchRequest req = f.request();
    req.sourceFilter = LaneSearchRequest.RowSource.BIDS;
    req.excludeProjectId = project.Id;
    String requestJson = JSON.serialize(req);

    User viewer = RfpTestDataFactory.restrictedUser('Lane_Benchmark_User');
    if (viewer == null) {
      System.assert(
        true,
        'no usable profile in this org; runAs coverage skipped (ledgered)'
      );
      return;
    }

    Test.startTest();
    Integer adminRates = LaneTrendController.getTrend(requestJson).totalRates;
    Integer viewerRates;
    System.runAs(viewer) {
      viewerRates = LaneTrendController.getTrend(requestJson).totalRates;
    }
    Test.stopTest();

    System.assertEquals(
      0,
      adminRates,
      'the admin can read the project, so the bid stays excluded'
    );
    System.assertEquals(
      1,
      viewerRates,
      'the viewer cannot read the project, so the exclusion does not apply'
    );
  }
}
