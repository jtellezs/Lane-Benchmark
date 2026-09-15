@IsTest
private class RfpHistoryServiceTest {
  /**
   * Phase 7, ruling R73: Load history never asks Mapbox for a route. The tests set a token
   * (MapboxHttp.tokenOverride), so a stray route request would really reach this mock, and its
   * AssertException - which no catch block in the service can swallow - fails the test right there.
   */
  private class NoRouteCallMock implements HttpCalloutMock {
    Integer calls = 0;
    public HttpResponse respond(HttpRequest req) {
      calls++;
      System.assert(false, 'Load history must not call Mapbox');
      return null;
    }
  }

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
    LaneSearchExclusions.excludedContactIdsOverride = new Set<String>();
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
      90,
      120,
      'KM',
      true
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
      'RADIUS-120KM',
      byId.get(nearby.Id).Hist_Precision__c,
      'fell back to the radius the run was given'
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
      RfpHistoryService.run(ids, 'CITY', 90, null, null, true);
      System.assert(false, 'expected an exception');
    } catch (LaneSearchException e) {
      System.assert(e.getMessage().contains('10'), e.getMessage());
    }
  }

  // RfpHistoryController coverage: the >10-lane error surfaces through loadHistory as an
  // AuraHandledException carrying LaneSearchException's message, same as RfpLaneController's
  // wrappers do for their own oversized-batch errors.
  @IsTest
  static void controllerWrapsTooManyLanesAsUserError() {
    List<Id> ids = new List<Id>();
    for (Integer i = 0; i < 11; i++) {
      ids.add('a00000000000' + String.valueOf(200 + i));
    }
    try {
      RfpHistoryController.loadHistory(ids, 'CITY', 90, null, null, true);
      System.assert(false, 'expected an error');
    } catch (AuraHandledException e) {
      System.assert(e.getMessage().contains('10'), e.getMessage());
    }
  }

  // Review round 1, finding 1: Database.update(allOrNone=false) plus a best-effort second pass
  // (RfpHistoryService.saveSnapshots) means a DML failure on a lane (here: an out-of-range
  // Hist_Lookback_Days__c - precision 5, scale 0, so 999999 does not fit either lane) marks that
  // lane Hist_Status__c = 'Failed' and both lanes still come back from run(), instead of the old
  // all-or-nothing Database.update aborting the whole call with an uncaught DmlException and
  // discarding every lane's snapshot in the chunk.
  @IsTest
  static void dmlFailureMarksLanesFailedInsteadOfThrowing() {
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
    LaneSearchExclusions.excludedContactIdsOverride = new Set<String>();
    RFP_Project__c p = RfpTestDataFactory.createProject(g.customer);
    RFP_Lane__c a = RfpTestDataFactory.createLane(p, mtl, tor);
    RFP_Lane__c b = RfpTestDataFactory.createLane(p, mtl, tor);
    List<RFP_Lane__c> out = RfpHistoryService.run(
      new List<Id>{ a.Id, b.Id },
      'CITY',
      999999,
      null,
      null,
      true
    );
    Map<Id, RFP_Lane__c> byId = new Map<Id, RFP_Lane__c>(out);
    System.assertEquals(
      2,
      out.size(),
      'lanes are still returned, not discarded'
    );
    System.assertEquals('Failed', byId.get(a.Id).Hist_Status__c);
    System.assertEquals('Failed', byId.get(b.Id).Hist_Status__c);
  }

  // Review round 1, finding 2: a search that legitimately returns zero rows (no exception, no
  // CITY-only fallback since precision is PROVINCE) must land on 'No match' through the ternary
  // in snapshot(), not through a caught exception. 'Nowhere, ZZ' has no coordinates, which
  // PROVINCE never needs, so no exception is possible either.
  @IsTest
  static void noMatchAtProvinceNeedsNoCoordinatesAndNoFallback() {
    Pricing_Place__c nowhere = RfpTestDataFactory.createPlace(
      'Nowhere',
      'ZZ',
      'CA',
      null,
      null,
      'Z9Z'
    );
    Pricing_Place__c tor = RfpTestDataFactory.createPlace(
      'Toronto',
      'ON',
      'CA',
      43.6532,
      -79.3832,
      'M5V'
    );
    PricingTestDataFactory.Graph g = PricingTestDataFactory.createGraph();
    LaneSearchExclusions.excludedContactIdsOverride = new Set<String>();
    RFP_Project__c p = RfpTestDataFactory.createProject(g.customer);
    RFP_Lane__c lane = RfpTestDataFactory.createLane(p, nowhere, tor);
    List<RFP_Lane__c> out = RfpHistoryService.run(
      new List<Id>{ lane.Id },
      'PROVINCE',
      90,
      null,
      null,
      true
    );
    RFP_Lane__c result = out[0];
    System.assertEquals('No match', result.Hist_Status__c);
    System.assertEquals(0, result.Hist_Count__c);
    System.assertEquals('PROVINCE', result.Hist_Precision__c);
  }

  // Final review I4 / ruling R19: fill() used to fall back to the first currency bucket when the
  // lane's own currency had none, so a USD median landed on a CAD lane and the pricer marked up a
  // US-dollar number as if it were Canadian. Only the lane's own bucket is read now: the rows are
  // still counted and the status is still 'Done', but every statistic stays null - which
  // rfpLaneTable already shows as "N · no median".
  @IsTest
  static void aForeignCurrencyBucketNeverFillsTheLaneStats() {
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
    LaneSearchExclusions.excludedContactIdsOverride = new Set<String>();
    RFP_Project__c p = RfpTestDataFactory.createProject(g.customer); // CAD
    RFP_Lane__c lane = RfpTestDataFactory.createLane(p, mtl, tor); // CAD
    Test.startTest();
    rtms__Load__c load = PricingTestDataFactory.createLoad(
      g,
      g.originLocation,
      g.destinationLocation
    );
    insert PricingTestDataFactory.buildQuote(g, load, 2500, 'USD');
    List<RFP_Lane__c> out = RfpHistoryService.run(
      new List<Id>{ lane.Id },
      'CITY',
      90,
      null,
      null,
      true
    );
    Test.stopTest();
    RFP_Lane__c result = out[0];
    System.assertEquals(
      'Done',
      result.Hist_Status__c,
      'a row was found, so the snapshot is done'
    );
    System.assertEquals(1, result.Hist_Count__c);
    System.assertEquals('CITY', result.Hist_Precision__c);
    System.assertEquals(
      null,
      result.Hist_Median__c,
      'no CAD bucket, so no median is stored'
    );
    System.assertEquals(null, result.Hist_Min__c);
    System.assertEquals(null, result.Hist_Average__c);
    System.assertEquals(null, result.Hist_Max__c);
  }

  // RfpHistoryController's generic catch: a non-LaneSearchException (here, a lane read/update
  // denied by CRUD under AccessLevel.USER_MODE for a user holding only Lane_Benchmark_User,
  // which grants no RFP_Lane__c access at all) surfaces as the fixed "could not be loaded"
  // sentence, not the raw platform error. Same restrictedUser() shape as RfpSecurityTest.
  @IsTest
  static void controllerWrapsAnUnexpectedFailureAsGenericUserError() {
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
    LaneSearchExclusions.excludedContactIdsOverride = new Set<String>();
    RFP_Project__c p = RfpTestDataFactory.createProject(g.customer);
    RFP_Lane__c lane = RfpTestDataFactory.createLane(p, mtl, tor);
    User viewer = restrictedUser('Lane_Benchmark_User');
    if (viewer == null) {
      System.assert(
        true,
        'no usable profile in this org; runAs coverage skipped (ledgered)'
      );
      return;
    }
    System.runAs(viewer) {
      try {
        RfpHistoryController.loadHistory(
          new List<Id>{ lane.Id },
          'CITY',
          90,
          null,
          null,
          true
        );
        System.assert(false, 'expected an error');
      } catch (AuraHandledException e) {
        System.assertEquals(
          'History could not be loaded for this chunk.',
          e.getMessage()
        );
      }
    }
  }

  @IsTest
  static void radiusUsesTheGivenUnitAndRefusesMoreThan500() {
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
    LaneSearchExclusions.excludedContactIdsOverride = new Set<String>();
    RFP_Project__c p = RfpTestDataFactory.createProject(g.customer);
    RFP_Lane__c lane = RfpTestDataFactory.createLane(p, mtl, tor);
    rtms__Load__c load = PricingTestDataFactory.createLoad(
      g,
      g.originLocation,
      g.destinationLocation
    );
    insert PricingTestDataFactory.buildQuote(g, load, 1000);
    Test.startTest();
    List<RFP_Lane__c> out = RfpHistoryService.run(
      new List<Id>{ lane.Id },
      'RADIUS',
      90,
      75.4,
      'MI',
      true
    );
    try {
      RfpHistoryService.run(
        new List<Id>{ lane.Id },
        'RADIUS',
        90,
        600,
        'KM',
        true
      );
      System.assert(false, 'expected an exception');
    } catch (LaneSearchException e) {
      System.assert(e.getMessage().contains('500'), e.getMessage());
    }
    List<RFP_Lane__c> zero = RfpHistoryService.run(
      new List<Id>{ lane.Id },
      'RADIUS',
      90,
      0.4,
      'KM',
      true
    );
    Test.stopTest();
    System.assertEquals(
      'RADIUS-75MI',
      out[0].Hist_Precision__c,
      'whole number, unit kept'
    );
    System.assertEquals('Done', out[0].Hist_Status__c);
    System.assertEquals(
      'RADIUS-50KM',
      zero[0].Hist_Precision__c,
      'a radius that rounds to 0 falls back to the 50 km default'
    );
  }

  // Phase 3d. The four tests below cover the bid side of a snapshot: what is counted, whose bids
  // are left out, what the toggle turns off, and that an expired bid inside the lookback counts.

  @IsTest
  static void countsAnotherProjectsBidAlongsideTheLoads() {
    Fixture f = fixture();
    insert RfpTestDataFactory.buildBid(f.otherLane, 2000);
    Test.startTest();
    addLoads(f.g, 1000, 3000);
    List<RFP_Lane__c> out = RfpHistoryService.run(
      new List<Id>{ f.lane.Id },
      'CITY',
      90,
      null,
      null,
      true
    );
    Test.stopTest();
    System.assertEquals('Done', out[0].Hist_Status__c);
    System.assertEquals(3, out[0].Hist_Count__c, 'two loads and one bid');
    System.assertEquals(1, out[0].Hist_Bid_Count__c);
    System.assertEquals(
      2000,
      out[0].Hist_Median__c,
      'the median runs over the loads and the bid together'
    );
  }

  // Ruling R46: the bids on the project being priced are the pricer's own inputs - the panel
  // already lists them - so a run over one of its lanes must not count them as market evidence.
  @IsTest
  static void leavesThePricedProjectsOwnBidsOut() {
    Fixture f = fixture();
    insert RfpTestDataFactory.buildBid(f.lane, 2000);
    Test.startTest();
    addLoads(f.g, 1000, 3000);
    List<RFP_Lane__c> out = RfpHistoryService.run(
      new List<Id>{ f.lane.Id },
      'CITY',
      90,
      null,
      null,
      true
    );
    Test.stopTest();
    System.assertEquals('Done', out[0].Hist_Status__c);
    System.assertEquals(2, out[0].Hist_Count__c, 'the loads only');
    System.assertEquals(0, out[0].Hist_Bid_Count__c);
  }

  @IsTest
  static void theToggleOffLeavesEveryBidOut() {
    Fixture f = fixture();
    insert RfpTestDataFactory.buildBid(f.otherLane, 2000);
    Test.startTest();
    addLoads(f.g, 1000, 3000);
    List<RFP_Lane__c> out = RfpHistoryService.run(
      new List<Id>{ f.lane.Id },
      'CITY',
      90,
      null,
      null,
      false
    );
    Test.stopTest();
    System.assertEquals('Done', out[0].Hist_Status__c);
    System.assertEquals(2, out[0].Hist_Count__c, 'the loads only');
    System.assertEquals(0, out[0].Hist_Bid_Count__c);
  }

  // Ruling R45: an old RFP's bids have almost always expired (30-day default validity) and are
  // exactly the quotes the pricer asked for; the lookback is what bounds their relevance.
  @IsTest
  static void countsAnExpiredBidInsideTheLookback() {
    Fixture f = fixture();
    Benchmark_Rate__c expired = RfpTestDataFactory.buildBid(f.otherLane, 2000);
    // save() only defaults these when they are null and never refuses a past date.
    expired.Valid_From__c = Date.today().addDays(-40);
    expired.Expires_On__c = Date.today().addDays(-10);
    insert expired;
    Test.startTest();
    List<RFP_Lane__c> out = RfpHistoryService.run(
      new List<Id>{ f.lane.Id },
      'CITY',
      90,
      null,
      null,
      true
    );
    Test.stopTest();
    System.assertEquals('Done', out[0].Hist_Status__c);
    System.assertEquals(1, out[0].Hist_Count__c);
    System.assertEquals(1, out[0].Hist_Bid_Count__c);
    System.assertEquals(2000, out[0].Hist_Median__c);
  }

  // Phase 7. The six tests below cover the trip miles a run writes on each lane: History, a stored
  // Truck or Regular route, a stored No route, Approx and No coordinates - never with a callout.

  // Rulings R70 and R75: billed PC*Miler miles are what the company invoices on, so the history
  // median wins even when a truck route is already stored for the pair, and the hours that route
  // left on the lane are cleared.
  @IsTest
  static void historyMilesOutrankAStoredTruckRoute() {
    Fixture f = fixture();
    storedRoute(
      f.mtl,
      f.tor,
      TruckRoute.defaultProfile(),
      'Found',
      'Truck',
      336.4,
      4.1
    );
    update new RFP_Lane__c(
      Id = f.lane.Id,
      Miles__c = 336.4,
      Miles_Source__c = 'Truck route',
      Route_Hours__c = 4.1
    );
    NoRouteCallMock mock = new NoRouteCallMock();
    Test.setMock(HttpCalloutMock.class, mock);
    MapboxHttp.tokenOverride = 'pk.test';
    Test.startTest();
    addLoadWithMiles(f.g, 347.5, 1000, 3000);
    List<RFP_Lane__c> out = RfpHistoryService.run(
      new List<Id>{ f.lane.Id },
      'CITY',
      90,
      null,
      null,
      true
    );
    Integer callouts = Limits.getCallouts();
    Test.stopTest();
    System.assertEquals(0, callouts, 'Load history makes no callout');
    System.assertEquals(0, mock.calls);
    System.assertEquals('Done', out[0].Hist_Status__c);
    System.assertEquals(2, out[0].Hist_Count__c);
    System.assertEquals(
      347.5,
      out[0].Miles__c,
      'the median billed miles of the matched loads'
    );
    System.assertEquals('History', out[0].Miles_Source__c);
    System.assertEquals(
      null,
      out[0].Route_Hours__c,
      'the stored route\'s hours are cleared'
    );
  }

  // Ruling R70: the miles come from the search the run actually used. Laval -> Toronto finds
  // nothing at CITY precision and falls back to RADIUS, where the Montréal -> Toronto load matches.
  @IsTest
  static void historyMilesComeFromTheRadiusFallback() {
    PricingTestDataFactory.Graph g = PricingTestDataFactory.createGraph();
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
    LaneSearchExclusions.excludedContactIdsOverride = new Set<String>();
    RFP_Lane__c nearby = RfpTestDataFactory.createLane(
      RfpTestDataFactory.createProject(g.customer),
      laval,
      tor
    );
    NoRouteCallMock mock = new NoRouteCallMock();
    Test.setMock(HttpCalloutMock.class, mock);
    MapboxHttp.tokenOverride = 'pk.test';
    Test.startTest();
    addLoadWithMiles(g, 351.0, 1000, 3000);
    List<RFP_Lane__c> out = RfpHistoryService.run(
      new List<Id>{ nearby.Id },
      'CITY',
      90,
      120,
      'KM',
      true
    );
    Integer callouts = Limits.getCallouts();
    Test.stopTest();
    System.assertEquals(0, callouts);
    System.assertEquals(0, mock.calls);
    System.assertEquals('RADIUS-120KM', out[0].Hist_Precision__c);
    System.assertEquals('Done', out[0].Hist_Status__c);
    System.assertEquals(351.0, out[0].Miles__c);
    System.assertEquals('History', out[0].Miles_Source__c);
    System.assertEquals(null, out[0].Route_Hours__c);
  }

  // Spec D4: with no billed miles, a lane takes the route stored for its ordered place pair and the
  // current truck - its miles, its hours, and whether Mapbox had to fall back to a regular route.
  // Direction matters (R71): Montréal -> Toronto and Toronto -> Montréal are two rows.
  @IsTest
  static void storedTruckAndRegularRoutesFillLanesWithoutHistory() {
    Fixture f = fixture();
    RFP_Lane__c back = RfpTestDataFactory.createLane(
      RfpTestDataFactory.createProject(f.g.customer),
      f.tor,
      f.mtl
    );
    storedRoute(
      f.mtl,
      f.tor,
      TruckRoute.defaultProfile(),
      'Found',
      'Truck',
      336.4,
      4.1
    );
    storedRoute(
      f.tor,
      f.mtl,
      TruckRoute.defaultProfile(),
      'Found',
      'Regular',
      339.8,
      4.3
    );
    NoRouteCallMock mock = new NoRouteCallMock();
    Test.setMock(HttpCalloutMock.class, mock);
    MapboxHttp.tokenOverride = 'pk.test';
    Test.startTest();
    List<RFP_Lane__c> out = RfpHistoryService.run(
      new List<Id>{ f.lane.Id, back.Id },
      'CITY',
      90,
      null,
      null,
      true
    );
    Integer callouts = Limits.getCallouts();
    Test.stopTest();
    System.assertEquals(0, callouts, 'a stored route is read, never requested');
    System.assertEquals(0, mock.calls);
    Map<Id, RFP_Lane__c> byId = new Map<Id, RFP_Lane__c>(out);
    RFP_Lane__c there = byId.get(f.lane.Id);
    System.assertEquals(
      'No match',
      there.Hist_Status__c,
      'no loads, so no history miles'
    );
    System.assertEquals(336.4, there.Miles__c);
    System.assertEquals('Truck route', there.Miles_Source__c);
    System.assertEquals(4.1, there.Route_Hours__c);
    RFP_Lane__c home = byId.get(back.Id);
    System.assertEquals(339.8, home.Miles__c);
    System.assertEquals('Regular route', home.Miles_Source__c);
    System.assertEquals(4.3, home.Route_Hours__c);
  }

  // Spec section 7: Mapbox found no road even without truck limits (across water, say). The stored
  // answer is kept - no Approx miles for a trip no road makes - and the miles of an earlier run go.
  @IsTest
  static void aStoredNoRouteLeavesTheMilesBlank() {
    Fixture f = fixture();
    storedRoute(
      f.mtl,
      f.tor,
      TruckRoute.defaultProfile(),
      'No route',
      null,
      null,
      null
    );
    update new RFP_Lane__c(
      Id = f.lane.Id,
      Miles__c = 376.0,
      Miles_Source__c = 'Approx'
    );
    NoRouteCallMock mock = new NoRouteCallMock();
    Test.setMock(HttpCalloutMock.class, mock);
    MapboxHttp.tokenOverride = 'pk.test';
    Test.startTest();
    List<RFP_Lane__c> out = RfpHistoryService.run(
      new List<Id>{ f.lane.Id },
      'CITY',
      90,
      null,
      null,
      true
    );
    Integer callouts = Limits.getCallouts();
    Test.stopTest();
    System.assertEquals(0, callouts);
    System.assertEquals(0, mock.calls);
    System.assertEquals('No route', out[0].Miles_Source__c);
    System.assertEquals(
      null,
      out[0].Miles__c,
      'the Approx miles of an earlier run are cleared'
    );
    System.assertEquals(null, out[0].Route_Hours__c);
  }

  // Spec D1 and D7: no billed miles and no stored route for this direction and this truck, so the
  // straight line x 1.2. Montréal (45.5019, -73.5674) -> Toronto (43.6532, -79.3832) is 313.335 mi
  // on a 3,958.7613 mi sphere; x 1.2 = 376.002, one decimal 376.0. The reverse direction's route
  // and a route stored for a lower truck (3.5 m) must not be used (R71).
  @IsTest
  static void approxMilesWhenNoRouteIsStoredForThisTruckAndDirection() {
    Fixture f = fixture();
    storedRoute(
      f.tor,
      f.mtl,
      TruckRoute.defaultProfile(),
      'Found',
      'Truck',
      339.8,
      4.3
    );
    TruckRoute.Profile lowTruck = new TruckRoute.Profile();
    lowTruck.heightM = 3.5;
    lowTruck.widthM = 2.6;
    lowTruck.weightT = 36.29;
    storedRoute(f.mtl, f.tor, lowTruck, 'Found', 'Truck', 341.2, 4.4);
    NoRouteCallMock mock = new NoRouteCallMock();
    Test.setMock(HttpCalloutMock.class, mock);
    MapboxHttp.tokenOverride = 'pk.test';
    Test.startTest();
    List<RFP_Lane__c> out = RfpHistoryService.run(
      new List<Id>{ f.lane.Id },
      'CITY',
      90,
      null,
      null,
      true
    );
    Integer callouts = Limits.getCallouts();
    Test.stopTest();
    System.assertEquals(0, callouts);
    System.assertEquals(0, mock.calls);
    System.assertEquals('Approx', out[0].Miles_Source__c);
    System.assertEquals(376.0, out[0].Miles__c);
    System.assertEquals(
      TripMilesService.approxMiles(f.mtl, f.tor, TruckRoute.defaultProfile()),
      out[0].Miles__c,
      'the same number Lane Benchmark and the lane panel compute'
    );
    System.assertEquals(null, out[0].Route_Hours__c);
  }

  // A place without coordinates gives no Approx miles. An unresolved lane (a place missing) gets
  // the same answer instead of keeping miles from an earlier run (phase 7 plan, Task 6 notes).
  @IsTest
  static void lanesWithoutCoordinatesOrAPlaceGetNoCoordinates() {
    PricingTestDataFactory.Graph g = PricingTestDataFactory.createGraph();
    Pricing_Place__c nowhere = RfpTestDataFactory.createPlace(
      'Nowhere',
      'ZZ',
      'CA',
      null,
      null,
      'Z9Z'
    );
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
    LaneSearchExclusions.excludedContactIdsOverride = new Set<String>();
    RFP_Project__c p = RfpTestDataFactory.createProject(g.customer);
    RFP_Lane__c noCoords = RfpTestDataFactory.createLane(p, nowhere, tor);
    RFP_Lane__c unresolved = RfpTestDataFactory.createLane(p, mtl, tor);
    unresolved.Destination_Place__c = null;
    unresolved.Destination_Resolved__c = false;
    unresolved.Miles__c = 376.0;
    unresolved.Miles_Source__c = 'Approx';
    update unresolved;
    NoRouteCallMock mock = new NoRouteCallMock();
    Test.setMock(HttpCalloutMock.class, mock);
    MapboxHttp.tokenOverride = 'pk.test';
    Test.startTest();
    List<RFP_Lane__c> out = RfpHistoryService.run(
      new List<Id>{ noCoords.Id, unresolved.Id },
      'CITY',
      90,
      null,
      null,
      true
    );
    Integer callouts = Limits.getCallouts();
    Test.stopTest();
    System.assertEquals(0, callouts);
    System.assertEquals(0, mock.calls);
    Map<Id, RFP_Lane__c> byId = new Map<Id, RFP_Lane__c>(out);
    System.assertEquals(
      'No match',
      byId.get(noCoords.Id).Hist_Status__c,
      'the radius fallback threw: no coordinates'
    );
    System.assertEquals(null, byId.get(noCoords.Id).Miles__c);
    System.assertEquals(
      'No coordinates',
      byId.get(noCoords.Id).Miles_Source__c
    );
    System.assertEquals('Unresolved', byId.get(unresolved.Id).Hist_Status__c);
    System.assertEquals(
      null,
      byId.get(unresolved.Id).Miles__c,
      'an unresolved lane keeps no miles from an earlier run'
    );
    System.assertEquals(
      'No coordinates',
      byId.get(unresolved.Id).Miles_Source__c
    );
    System.assertEquals(null, byId.get(unresolved.Id).Route_Hours__c);
  }

  private class Fixture {
    PricingTestDataFactory.Graph g;
    Pricing_Place__c mtl;
    Pricing_Place__c tor;
    RFP_Lane__c lane;
    RFP_Lane__c otherLane;
  }

  /**
   * Montréal -> Toronto twice: once on the project a run prices, once on a second project whose
   * bids are the "another RFP" evidence phase 3d counts. The two places stay on the fixture for
   * the phase 7 trip-miles tests (route keys and Approx miles).
   */
  private static Fixture fixture() {
    Fixture f = new Fixture();
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
    LaneSearchExclusions.excludedContactIdsOverride = new Set<String>();
    f.lane = RfpTestDataFactory.createLane(
      RfpTestDataFactory.createProject(f.g.customer),
      f.mtl,
      f.tor
    );
    f.otherLane = RfpTestDataFactory.createLane(
      RfpTestDataFactory.createProject(f.g.customer),
      f.mtl,
      f.tor
    );
    return f;
  }

  /** The two Revenova carrier quotes a CITY match finds on Montréal -> Toronto. */
  private static void addLoads(
    PricingTestDataFactory.Graph g,
    Decimal low,
    Decimal high
  ) {
    rtms__Load__c load = PricingTestDataFactory.createLoad(
      g,
      g.originLocation,
      g.destinationLocation
    );
    insert new List<rtms__CarrierQuote__c>{
      PricingTestDataFactory.buildQuote(g, load, low),
      PricingTestDataFactory.buildQuote(g, load, high)
    };
  }

  /**
   * addLoads with the load's billed miles (rtms__Distance_Miles__c, which PC*Miler fills in
   * production), through Task 5's createLoad overload that sets them before the insert. Revenova's
   * managed rtms__LoadUpsert trigger runs on every load save (ApexTrigger query, PostProduc,
   * 2026-09-14), so the miles are read back: a failure on that assertion means the trigger rewrote
   * them, not that the history run is wrong.
   */
  private static void addLoadWithMiles(
    PricingTestDataFactory.Graph g,
    Decimal miles,
    Decimal low,
    Decimal high
  ) {
    rtms__Load__c load = PricingTestDataFactory.createLoad(
      g,
      g.originLocation,
      g.destinationLocation,
      miles
    );
    System.assertEquals(
      miles,
      [SELECT rtms__Distance_Miles__c FROM rtms__Load__c WHERE Id = :load.Id]
      .rtms__Distance_Miles__c,
      'the load keeps its billed miles'
    );
    insert new List<rtms__CarrierQuote__c>{
      PricingTestDataFactory.buildQuote(g, load, low),
      PricingTestDataFactory.buildQuote(g, load, high)
    };
  }

  /**
   * A Truck_Route__c row the way TripMilesService.save stores one: both places set (storedRoutes
   * ignores a row with a blank place) and the key from TripMilesService.routeKey, never built by
   * hand. The polyline is a two-point placeholder; a history run never draws it.
   */
  private static void storedRoute(
    Pricing_Place__c origin,
    Pricing_Place__c destination,
    TruckRoute.Profile profile,
    String status,
    String routeType,
    Decimal miles,
    Decimal hours
  ) {
    List<Map<String, Object>> routes = new List<Map<String, Object>>();
    if (miles != null) {
      routes.add(
        new Map<String, Object>{
          'miles' => miles,
          'hours' => hours,
          'polyline5' => '{avtGfs_`MjahJv{nb@'
        }
      );
    }
    insert new Truck_Route__c(
      Origin_Place__c = origin.Id,
      Destination_Place__c = destination.Id,
      Profile_Key__c = profile.key(),
      Route_Key__c = TripMilesService.routeKey(
        origin.Id,
        destination.Id,
        profile
      ),
      Status__c = status,
      Route_Type__c = routeType,
      Miles__c = miles,
      Hours__c = hours,
      Routes_Json__c = JSON.serialize(routes),
      Checked_On__c = Datetime.now()
    );
  }

  /** Same shape as RfpSecurityTest.restrictedUser: a user holding only the named permission
   * set. Returns null when the org has no usable profile. */
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
      Username = 'rfphist.' + System.currentTimeMillis() + '@example.invalid',
      Email = 'rfphist@example.invalid',
      LastName = 'RfpHist',
      Alias = 'rfphist',
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
}
