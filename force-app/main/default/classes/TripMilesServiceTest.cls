@IsTest
private class TripMilesServiceTest {
  // Two Directions routes, no notification: the truck route is kept (one request).
  private static final String TRUCK_BODY =
    '{"code":"Ok","waypoints":[],"routes":[' +
    '{"distance":540000.0,"duration":20160.0,"geometry":"_p~iF~ps|U_ulLnnqC_mqNvxq`@","legs":[]},' +
    '{"distance":563000.0,"duration":21600.0,"geometry":"_p~iF~ps|U_ulLnnqC","legs":[]}' +
    ']}';
  private static final String NO_ROUTE_BODY = '{"code":"NoRoute","message":"No route found","routes":[]}';

  private class Mock implements HttpCalloutMock {
    Integer status;
    String body;
    Integer calls = 0;
    Mock(Integer status, String body) {
      this.status = status;
      this.body = body;
    }
    public HttpResponse respond(HttpRequest req) {
      calls++;
      System.assert(
        req.getEndpoint()
          .startsWith('https://api.mapbox.com/directions/v5/mapbox/driving/'),
        'a Directions request'
      );
      HttpResponse r = new HttpResponse();
      r.setStatusCode(status);
      r.setBody(body);
      return r;
    }
  }

  private class Fx {
    Pricing_Place__c mtl;
    Pricing_Place__c tor;
    TruckRoute.Profile p;
  }

  private static Fx fx() {
    MapboxHttp.tokenOverride = 'pk.test';
    Fx f = new Fx();
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
    f.p = profile();
    return f;
  }

  private static TruckRoute.Profile profile() {
    TruckRoute.Profile p = new TruckRoute.Profile();
    p.heightM = 4.11;
    p.widthM = 2.6;
    p.weightT = 36.29;
    p.alternatives = true;
    p.approxFactor = 1.2;
    p.timeoutMs = 8000;
    return p;
  }

  private static Integer fakeLoads = 0;

  /** A quote row on a load of its own (a fresh fake rtms__Load__c Id). */
  private static LaneSearchResult.Row row(Decimal miles) {
    return row(fakeLoadId(), miles);
  }

  /** A quote row on the given load: pass the same Id twice for a load with two quotes. */
  private static LaneSearchResult.Row row(Id loadId, Decimal miles) {
    LaneSearchResult.Row r = new LaneSearchResult.Row();
    r.load.loadId = loadId;
    r.load.miles = miles;
    return r;
  }

  /** A well-formed, never inserted rtms__Load__c Id: medianMiles only compares load Ids. */
  private static Id fakeLoadId() {
    fakeLoads++;
    return Id.valueOf(
      rtms__Load__c.SObjectType.getDescribe().getKeyPrefix() +
      String.valueOf(fakeLoads).leftPad(12, '0')
    );
  }

  /** A route row for Montréal -> Toronto with the fixture's profile, not inserted. */
  private static Truck_Route__c built(Fx f, String routeType, Decimal miles) {
    return new Truck_Route__c(
      Origin_Place__c = f.mtl.Id,
      Destination_Place__c = f.tor.Id,
      Profile_Key__c = f.p.key(),
      Route_Key__c = TripMilesService.routeKey(f.mtl.Id, f.tor.Id, f.p),
      Status__c = 'Found',
      Route_Type__c = routeType,
      Miles__c = miles,
      Hours__c = 6.5,
      Routes_Json__c = '[{"miles":' +
        miles +
        ',"hours":6.5,"polyline5":"_p~iF~ps|U"}]',
      Checked_On__c = System.now().addDays(-3)
    );
  }

  private static Truck_Route__c stored(Fx f, String routeType, Decimal miles) {
    Truck_Route__c row = built(f, routeType, miles);
    insert row;
    return row;
  }

  @IsTest
  static void medianMilesTakesTheMiddleOfPositiveMiles() {
    System.assertEquals(
      412.5,
      TripMilesService.medianMiles(
        new List<LaneSearchResult.Row>{
          row(500.0),
          row(0),
          row(null),
          row(300.0),
          row(-20.0),
          row(412.5)
        }
      ),
      'odd count: the middle value; zero, negative and blank miles are ignored'
    );
    System.assertEquals(
      456.5,
      TripMilesService.medianMiles(
        new List<LaneSearchResult.Row>{
          row(610.0),
          row(300.0),
          row(500.0),
          row(413.0)
        }
      ),
      'even count: the mean of the two middle values'
    );
    System.assertEquals(
      333.4,
      TripMilesService.medianMiles(
        new List<LaneSearchResult.Row>{ row(333.36) }
      ),
      'one decimal'
    );
    System.assertEquals(
      null,
      TripMilesService.medianMiles(
        new List<LaneSearchResult.Row>{ row(0), row(null) }
      ),
      'no row has miles'
    );
    System.assertEquals(
      null,
      TripMilesService.medianMiles(new List<LaneSearchResult.Row>())
    );
    System.assertEquals(null, TripMilesService.medianMiles(null));
  }

  // Spec D1: the median is over the loads the search matched, so a load quoted by several carriers
  // counts once. Over rows, the first list would give 250 and the second 375.
  @IsTest
  static void medianMilesCountsEachLoadOnce() {
    Id quotedThrice = fakeLoadId();
    LaneSearchResult.Row withoutLoadGroup = new LaneSearchResult.Row();
    withoutLoadGroup.load = null;
    System.assertEquals(
      375.0,
      TripMilesService.medianMiles(
        new List<LaneSearchResult.Row>{
          row(quotedThrice, 250.0),
          row(quotedThrice, 250.0),
          row(quotedThrice, 250.0),
          row(500.0),
          row(null, 900.0),
          withoutLoadGroup
        }
      ),
      'two loads, 250 and 500: the load on three rows counts once; no load Id or load group, no count'
    );
    Id quotedTwice = fakeLoadId();
    System.assertEquals(
      500.0,
      TripMilesService.medianMiles(
        new List<LaneSearchResult.Row>{
          row(quotedTwice, 250.0),
          row(500.0),
          row(quotedTwice, 250.0),
          row(600.0)
        }
      ),
      'odd count of loads: the middle of 250, 500 and 600, not the mean of the two middle rows'
    );
    System.assertEquals(
      null,
      TripMilesService.medianMiles(
        new List<LaneSearchResult.Row>{ row(null, 300.0), row(null, 400.0) }
      ),
      'rows without a load Id give no median'
    );
  }

  @IsTest
  static void approxMilesIsTheGreatCircleTimesTheFactor() {
    Pricing_Place__c mtl = new Pricing_Place__c(
      Geolocation__Latitude__s = 45.5019,
      Geolocation__Longitude__s = -73.5674
    );
    Pricing_Place__c tor = new Pricing_Place__c(
      Geolocation__Latitude__s = 43.6532,
      Geolocation__Longitude__s = -79.3832
    );
    TruckRoute.Profile p = profile();
    System.assertEquals(
      376.0,
      TripMilesService.approxMiles(mtl, tor, p),
      '313.3 great-circle miles x 1.2'
    );
    p.approxFactor = 1;
    System.assertEquals(
      313.3,
      TripMilesService.approxMiles(mtl, tor, p),
      'the factor comes from the profile'
    );
    System.assertEquals(
      313.3,
      TripMilesService.approxMiles(tor, mtl, p),
      'the straight line is the same both ways'
    );
    Pricing_Place__c noLongitude = new Pricing_Place__c(
      Geolocation__Latitude__s = 45.5019
    );
    System.assertEquals(
      null,
      TripMilesService.approxMiles(noLongitude, tor, p)
    );
    System.assertEquals(null, TripMilesService.approxMiles(mtl, null, p));
  }

  @IsTest
  static void routeKeyIsOrderedAndFollowsTheTruck() {
    Fx f = fx();
    Id a = f.mtl.Id;
    Id b = f.tor.Id;
    TruckRoute.Profile p = profile();
    String key = TripMilesService.routeKey(a, b, p);
    System.assertEquals(
      String.valueOf(a) + ':' + String.valueOf(b) + ':h4.11w2.60t36.29',
      key
    );
    System.assertNotEquals(
      key,
      TripMilesService.routeKey(b, a, p),
      'direction matters'
    );
    p.heightM = 4.2;
    System.assertNotEquals(key, TripMilesService.routeKey(a, b, p), 'height');
    p = profile();
    p.widthM = 2.5;
    System.assertNotEquals(key, TripMilesService.routeKey(a, b, p), 'width');
    p = profile();
    p.weightT = 30;
    System.assertNotEquals(key, TripMilesService.routeKey(a, b, p), 'weight');
    System.assertEquals(null, TripMilesService.routeKey(null, b, profile()));
  }

  @IsTest
  static void storedRoutesIgnoresARowWhosePlaceWasDeleted() {
    Fx f = fx();
    Truck_Route__c row = stored(f, 'Truck', 336.3);
    Map<String, Truck_Route__c> found = TripMilesService.storedRoutes(
      new Set<String>{ row.Route_Key__c, 'no:such:key' }
    );
    System.assertEquals(new Set<String>{ row.Route_Key__c }, found.keySet());
    System.assertEquals(336.3, found.get(row.Route_Key__c).Miles__c);
    delete f.tor;
    System.assertEquals(
      null,
      [SELECT Destination_Place__c FROM Truck_Route__c WHERE Id = :row.Id]
      .Destination_Place__c,
      'the lookup clears on delete'
    );
    System.assertEquals(
      0,
      TripMilesService.storedRoutes(new Set<String>{ row.Route_Key__c }).size(),
      'a row with a blank place is ignored'
    );
    System.assertEquals(
      0,
      TripMilesService.storedRoutes(new Set<String>()).size()
    );
    System.assertEquals(0, TripMilesService.storedRoutes(null).size());
  }

  @IsTest
  static void fromStoredRebuildsTheResult() {
    TruckRoute.Result r = TripMilesService.fromStored(
      new Truck_Route__c(
        Status__c = 'Found',
        Route_Type__c = 'Regular',
        Miles__c = 336.3,
        Hours__c = 5.6,
        Routes_Json__c = '[{"miles":336.3,"hours":5.6,"polyline5":"_p~iF~ps|U"},' +
          '{"miles":349.8,"hours":6.0,"polyline5":"_ulLnnqC"}]'
      )
    );
    System.assertEquals('Found', r.status);
    System.assertEquals('Regular', r.routeType);
    System.assertEquals(
      2,
      r.routes.size(),
      'main route first, then one alternative'
    );
    System.assertEquals(336.3, r.routes[0].miles);
    System.assertEquals(5.6, r.routes[0].hours);
    System.assertEquals('_p~iF~ps|U', r.routes[0].polyline5);
    System.assertEquals(349.8, r.routes[1].miles);
    TruckRoute.Result none = TripMilesService.fromStored(
      new Truck_Route__c(Status__c = 'No route', Routes_Json__c = '[]')
    );
    System.assertEquals('No route', none.status);
    System.assertEquals(null, none.routeType);
    System.assertEquals(0, none.routes.size());
    System.assertEquals(
      0,
      TripMilesService.fromStored(
          new Truck_Route__c(Status__c = 'Found', Routes_Json__c = 'not json')
        )
        .routes.size(),
      'unreadable JSON gives no routes instead of an error'
    );
    System.assertEquals(
      0,
      TripMilesService.fromStored(new Truck_Route__c(Status__c = 'No route'))
        .routes.size()
    );
  }

  @IsTest
  static void aStoredRouteWinsWithoutACallout() {
    Fx f = fx();
    stored(f, 'Regular', 336.3);
    Mock m = new Mock(200, TRUCK_BODY);
    Test.setMock(HttpCalloutMock.class, m);
    Test.startTest();
    TripMilesService.RouteOutcome out = TripMilesService.storedOrRoute(
      f.mtl,
      f.tor,
      f.p,
      false
    );
    Integer callouts = Limits.getCallouts();
    Test.stopTest();
    System.assertEquals(0, m.calls, 'no Mapbox request');
    System.assertEquals(0, callouts);
    System.assert(out.fromStore, 'served from Truck_Route__c');
    System.assertEquals(null, out.toSave, 'nothing to save');
    System.assertEquals('Found', out.result.status);
    System.assertEquals('Regular', out.result.routeType);
    System.assertEquals(336.3, out.result.routes[0].miles);
  }

  @IsTest
  static void anotherTruckDoesNotReuseTheStoredRoute() {
    Fx f = fx();
    stored(f, 'Truck', 336.3);
    f.p.heightM = 4.3;
    Mock m = new Mock(200, TRUCK_BODY);
    Test.setMock(HttpCalloutMock.class, m);
    Test.startTest();
    TripMilesService.RouteOutcome out = TripMilesService.storedOrRoute(
      f.mtl,
      f.tor,
      f.p,
      false
    );
    Test.stopTest();
    System.assertEquals(1, m.calls, 'a new profile key asks Mapbox');
    System.assert(!out.fromStore);
    System.assertEquals(
      TripMilesService.routeKey(f.mtl.Id, f.tor.Id, f.p),
      out.toSave.Route_Key__c
    );
    System.assert(
      out.toSave.Profile_Key__c.startsWith('h4.30'),
      out.toSave.Profile_Key__c
    );
  }

  @IsTest
  static void refreshAsksMapboxAndReplacesTheStoredRow() {
    Fx f = fx();
    Truck_Route__c old = stored(f, 'Regular', 999.9);
    Mock m = new Mock(200, TRUCK_BODY);
    Test.setMock(HttpCalloutMock.class, m);
    Test.startTest();
    TripMilesService.RouteOutcome out = TripMilesService.storedOrRoute(
      f.mtl,
      f.tor,
      f.p,
      true
    );
    TripMilesService.save(new List<Truck_Route__c>{ out.toSave });
    Test.stopTest();
    System.assertEquals(
      1,
      m.calls,
      'one request: the truck route had no violation'
    );
    System.assert(!out.fromStore);
    System.assertEquals('Found', out.result.status);
    System.assertEquals('Truck', out.result.routeType);
    System.assertEquals(2, out.result.routes.size());
    Truck_Route__c s = out.toSave;
    System.assertEquals(old.Route_Key__c, s.Route_Key__c);
    System.assertEquals(f.p.key(), s.Profile_Key__c);
    System.assertEquals(f.mtl.Id, s.Origin_Place__c);
    System.assertEquals(f.tor.Id, s.Destination_Place__c);
    System.assertEquals('Found', s.Status__c);
    System.assertEquals('Truck', s.Route_Type__c);
    System.assertEquals(335.5, s.Miles__c, '540,000 m');
    System.assertEquals(5.6, s.Hours__c, '20,160 s');
    System.assertNotEquals(null, s.Checked_On__c);
    List<TruckRoute.Line> lines = (List<TruckRoute.Line>) JSON.deserialize(
      s.Routes_Json__c,
      List<TruckRoute.Line>.class
    );
    System.assertEquals(2, lines.size());
    System.assertEquals('_p~iF~ps|U_ulLnnqC_mqNvxq`@', lines[0].polyline5);
    System.assertEquals(349.8, lines[1].miles);
    System.assertEquals(6.0, lines[1].hours);
    List<Truck_Route__c> rows = [
      SELECT Id, Status__c, Miles__c, Route_Type__c, Routes_Json__c
      FROM Truck_Route__c
    ];
    System.assertEquals(1, rows.size(), 'the refresh replaced the row');
    System.assertEquals(old.Id, rows[0].Id);
    System.assertEquals(335.5, rows[0].Miles__c);
    System.assertEquals('Truck', rows[0].Route_Type__c);
    System.assertEquals(
      2,
      TripMilesService.fromStored(rows[0]).routes.size(),
      'the saved JSON reads back'
    );
  }

  @IsTest
  static void noRouteIsSavedWithoutMiles() {
    Fx f = fx();
    Mock m = new Mock(200, NO_ROUTE_BODY);
    Test.setMock(HttpCalloutMock.class, m);
    Test.startTest();
    TripMilesService.RouteOutcome out = TripMilesService.storedOrRoute(
      f.mtl,
      f.tor,
      f.p,
      false
    );
    TripMilesService.save(new List<Truck_Route__c>{ out.toSave });
    Test.stopTest();
    System.assertEquals(2, m.calls, 'the truck request, then the regular one');
    System.assertEquals('No route', out.result.status);
    Truck_Route__c row = [
      SELECT Status__c, Route_Type__c, Miles__c, Hours__c, Routes_Json__c
      FROM Truck_Route__c
    ];
    System.assertEquals('No route', row.Status__c);
    System.assertEquals(null, row.Route_Type__c);
    System.assertEquals(null, row.Miles__c);
    System.assertEquals(null, row.Hours__c);
    System.assertEquals('[]', row.Routes_Json__c);
  }

  @IsTest
  static void unavailableGivesNothingToSave() {
    Fx f = fx();
    Mock m = new Mock(401, '{"message":"Not Authorized - Invalid Token"}');
    Test.setMock(HttpCalloutMock.class, m);
    Test.startTest();
    TripMilesService.RouteOutcome out = TripMilesService.storedOrRoute(
      f.mtl,
      f.tor,
      f.p,
      false
    );
    TripMilesService.RouteOutcome noCoordinates = TripMilesService.storedOrRoute(
      f.mtl,
      new Pricing_Place__c(Id = f.tor.Id),
      f.p,
      true
    );
    TripMilesService.RouteOutcome noPlace = TripMilesService.storedOrRoute(
      null,
      f.tor,
      f.p,
      false
    );
    Test.stopTest();
    System.assertEquals(1, m.calls, 'only the first call reached Mapbox');
    System.assertEquals('Unavailable', out.result.status);
    System.assertEquals(TruckRoute.UNAVAILABLE, out.result.message);
    System.assertEquals(null, out.toSave);
    System.assert(!out.fromStore);
    System.assertEquals('Unavailable', noCoordinates.result.status);
    System.assertEquals(null, noCoordinates.toSave);
    System.assertEquals('Unavailable', noPlace.result.status);
    System.assertEquals(TruckRoute.UNAVAILABLE, noPlace.result.message);
    System.assertEquals(0, [SELECT COUNT() FROM Truck_Route__c]);
  }

  @IsTest
  static void saveUpsertsOnTheRouteKey() {
    Fx f = fx();
    TripMilesService.save(new List<Truck_Route__c>{ built(f, 'Truck', 336.3) });
    TripMilesService.save(
      new List<Truck_Route__c>{ built(f, 'Regular', 350.1) }
    );
    TripMilesService.save(new List<Truck_Route__c>());
    TripMilesService.save(null);
    List<Truck_Route__c> rows = [
      SELECT Miles__c, Route_Type__c
      FROM Truck_Route__c
      WHERE Route_Key__c = :TripMilesService.routeKey(f.mtl.Id, f.tor.Id, f.p)
    ];
    System.assertEquals(
      1,
      rows.size(),
      'the second save updated the first row'
    );
    System.assertEquals(350.1, rows[0].Miles__c);
    System.assertEquals('Regular', rows[0].Route_Type__c);
  }

  @IsTest
  static void aPricerRefreshesARouteAColleagueSaved() {
    Fx f = fx();
    Truck_Route__c old = stored(f, 'Truck', 336.3);
    User pricer = RfpTestDataFactory.restrictedUser('RFP_Tool_User');
    if (pricer == null) {
      System.assert(
        true,
        'no usable profile in this org; runAs coverage skipped (ledgered)'
      );
      return;
    }
    Integer seen;
    System.runAs(pricer) {
      seen = TripMilesService.storedRoutes(new Set<String>{ old.Route_Key__c })
        .size();
      TripMilesService.save(
        new List<Truck_Route__c>{ built(f, 'Regular', 350.1) }
      );
    }
    System.assertEquals(
      1,
      seen,
      'Public Read Only: the pricer reads the route'
    );
    Truck_Route__c after = [
      SELECT Id, OwnerId, Miles__c, Route_Type__c
      FROM Truck_Route__c
      WHERE Route_Key__c = :old.Route_Key__c
    ];
    System.assertEquals(old.Id, after.Id, 'updated, not duplicated');
    System.assertEquals(350.1, after.Miles__c);
    System.assertEquals('Regular', after.Route_Type__c);
    System.assertEquals(
      UserInfo.getUserId(),
      after.OwnerId,
      'the row still belongs to the admin who saved it first'
    );
  }
}
