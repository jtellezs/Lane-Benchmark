@IsTest
private class LaneBenchmarkControllerTest {
  private static Pricing_Place__c place(
    String city,
    String prov,
    String country,
    Decimal lat,
    Decimal lng,
    Decimal loads,
    String aliases
  ) {
    return new Pricing_Place__c(
      Name = city + ', ' + prov + ', ' + country,
      Key__c = PlaceNormalizer.key(city, prov, country),
      City__c = city,
      Province__c = prov,
      Country__c = country,
      Geolocation__Latitude__s = lat,
      Geolocation__Longitude__s = lng,
      Load_Count_365d__c = loads,
      Aliases__c = aliases,
      Active__c = true,
      Source__c = 'Locations',
      Postal_Prefix__c = 'H1A'
    );
  }

  @TestSetup
  static void places() {
    insert new List<Pricing_Place__c>{
      place(
        'Montréal',
        'QC',
        'CA',
        45.5019,
        -73.5674,
        900,
        'Mtl, Montreal-Nord'
      ),
      place('Montmagny', 'QC', 'CA', 46.98, -70.55, 12, null),
      place('Toronto', 'ON', 'CA', 43.6532, -79.3832, 800, null),
      place('Hidden', 'ON', 'CA', 43.0, -79.0, 5000, null)
    };
    Pricing_Place__c hidden = [
      SELECT Id
      FROM Pricing_Place__c
      WHERE City__c = 'Hidden'
    ];
    hidden.Active__c = false;
    update hidden;
  }

  /** A user holding only the named permission set (as RfpSecurityTest.restrictedUser), or null when the org has no usable profile. */
  private static User restrictedUser(String permSetName) {
    return restrictedUser(new List<String>{ permSetName });
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
      Username = 'lanebench.' +
        System.currentTimeMillis() +
        '.' +
        permSetNames.size() +
        '@example.invalid',
      Email = 'lanebench@example.invalid',
      LastName = 'LaneBench',
      Alias = 'lbench',
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

  /** Mapbox Directions stand-in: one canned answer for every request; counts calls, keeps the last endpoint. */
  private class DirectionsMock implements HttpCalloutMock {
    Integer status;
    String body;
    Integer calls = 0;
    String lastEndpoint;
    DirectionsMock(Integer status, String body) {
      this.status = status;
      this.body = body;
    }
    public HttpResponse respond(HttpRequest req) {
      calls++;
      lastEndpoint = req.getEndpoint();
      System.assert(
        lastEndpoint.startsWith(
          MapboxHttp.BASE + '/directions/v5/mapbox/driving/'
        ),
        'a Directions request'
      );
      HttpResponse r = new HttpResponse();
      r.setStatusCode(status);
      r.setBody(body);
      return r;
    }
  }

  /** Two routes: 540,000 m in 19,800 s (335.5 mi, 5.5 h), then 560,000 m in 21,000 s (348.0 mi, 5.8 h). */
  private static final String FOUND = '{"code":"Ok","routes":[{"distance":540000,"duration":19800,"geometry":"_p~iF~ps|U_ulLnnqC_mqNvxq`@","legs":[{"notifications":[]}]},{"distance":560000,"duration":21000,"geometry":"_p~iF~ps|U_ulLnnqC","legs":[{"notifications":[]}]}],"waypoints":[]}';

  @IsTest
  static void searchPlacesMatchesNormalizedPrefixAndAliasesOrderedByLoads() {
    List<LaneBenchmarkController.PlaceOption> byPrefix = LaneBenchmarkController.searchPlaces(
      'mont',
      10
    );
    System.assertEquals(2, byPrefix.size());
    System.assertEquals('montreal|qc|ca', byPrefix[0].key, 'more loads first');
    System.assertEquals('Montréal, QC, CA', byPrefix[0].label);
    System.assertEquals(900, byPrefix[0].loadCount);
    List<LaneBenchmarkController.PlaceOption> byAlias = LaneBenchmarkController.searchPlaces(
      'mtl',
      10
    );
    System.assertEquals(1, byAlias.size());
    System.assertEquals('montreal|qc|ca', byAlias[0].key);
    System.assertEquals(
      0,
      LaneBenchmarkController.searchPlaces('h', 10).size(),
      'terms under 2 chars return nothing'
    );
    System.assertEquals(
      0,
      LaneBenchmarkController.searchPlaces('hidden', 10).size(),
      'inactive places are hidden'
    );
    System.assertEquals(
      1,
      LaneBenchmarkController.searchPlaces('mont', 1).size(),
      'limit honored'
    );
  }

  @IsTest
  static void searchDeserializesJsonKeepsDefaultsAndTranslatesErrors() {
    LaneSearchExclusions.excludedContactIdsOverride = new Set<String>();
    LaneSearchResult r = LaneBenchmarkController.search(
      '{"originKey":"montreal|qc|ca","destinationKey":"toronto|on|ca"}'
    );
    System.assertNotEquals(null, r);
    System.assertEquals(0, r.rows.size(), 'no quotes in this test org context');
    try {
      LaneBenchmarkController.search('{"originKey":"nowhere|zz|zz"}');
      System.assert(false, 'unknown key must surface as AuraHandledException');
    } catch (AuraHandledException e) {
      System.assert(e.getMessage().contains('nowhere|zz|zz'), e.getMessage());
    }
    try {
      LaneBenchmarkController.search('{"lookbackDays":0}');
      System.assert(false);
    } catch (AuraHandledException e) {
      System.assert(e.getMessage().contains('lookbackDays'), e.getMessage());
    }
    try {
      LaneBenchmarkController.search('not json');
      System.assert(false);
    } catch (AuraHandledException e) {
      System.assert(
        e.getMessage().toLowerCase().contains('request'),
        e.getMessage()
      );
    }
  }

  @IsTest
  static void filterOptionsListEnabledModesAndEquipmentByCategory() {
    PricingTestDataFactory.createMode('LTL');
    PricingTestDataFactory.createEquipment('Reefer 53\'', 'Reefer');
    PricingTestDataFactory.createEquipment('Dry Van 53\'', 'Van');
    rtms__EquipmentType__c noCat = PricingTestDataFactory.createEquipment(
      'Mystery',
      null
    );
    LaneBenchmarkController.FilterOptions o = LaneBenchmarkController.getFilterOptions();
    System.assert(o.modes.contains('LTL'), o.modes);
    System.assert(o.equipmentByCategory.get('Reefer').contains('Reefer 53\''));
    System.assert(
      o.equipmentByCategory.get('Other').contains('Mystery'),
      'null category grouped as Other'
    );
    System.assertEquals(new List<String>{ 'CAD', 'USD' }, o.currencies);
  }

  @IsTest
  static void geocodeStoresMapboxPlacesWithoutDowngradingExistingOnes() {
    MapboxGeocoder.GeoResult existing = new MapboxGeocoder.GeoResult();
    existing.name = 'Montréal, Quebec, Canada';
    existing.city = 'Montréal';
    existing.province = 'QC';
    existing.country = 'CA';
    existing.lat = 45.5;
    existing.lng = -73.5;
    MapboxGeocoder.GeoResult fresh = new MapboxGeocoder.GeoResult();
    fresh.name = 'Saguenay, Quebec, Canada';
    fresh.city = 'Saguenay';
    fresh.province = 'QC';
    fresh.country = 'CA';
    fresh.lat = 48.4279;
    fresh.lng = -71.0656;
    LaneBenchmarkController.geocoderOverride = new List<MapboxGeocoder.GeoResult>{
      existing,
      fresh
    };
    Test.startTest();
    List<LaneBenchmarkController.PlaceOption> out = LaneBenchmarkController.geocode(
      'anything',
      null
    );
    Test.stopTest();
    System.assertEquals(2, out.size());
    Pricing_Place__c mtl = [
      SELECT Source__c, Load_Count_365d__c
      FROM Pricing_Place__c
      WHERE Key__c = 'montreal|qc|ca'
    ];
    System.assertEquals('Locations', mtl.Source__c, 'existing place untouched');
    System.assertEquals(900, mtl.Load_Count_365d__c);
    Pricing_Place__c sag = [
      SELECT
        Source__c,
        City__c,
        Province__c,
        Country__c,
        Geolocation__Latitude__s,
        Active__c,
        Name
      FROM Pricing_Place__c
      WHERE Key__c = 'saguenay|qc|ca'
    ];
    System.assertEquals('Mapbox', sag.Source__c);
    System.assertEquals('Saguenay, QC, CA', sag.Name);
    System.assertEquals(48.4279, sag.Geolocation__Latitude__s);
    System.assertEquals(true, sag.Active__c);
    try {
      LaneBenchmarkController.geocode('ab', null);
      System.assert(false);
    } catch (AuraHandledException e) {
      System.assert(e.getMessage().contains('3'), e.getMessage());
    }
  }

  @IsTest
  static void mapPreviewUrlUsesPlaceCoordinatesAndRadii() {
    TPRO_KPI__c s = TPRO_KPI__c.getOrgDefaults();
    s.Mapbox_Api_Key__c = 'pk.test';
    upsert s;
    String url = LaneBenchmarkController.mapPreviewUrl(
      'montreal|qc|ca',
      50,
      'toronto|on|ca',
      100,
      'MI'
    );
    System.assert(url != null && url.contains('access_token=pk.test'), url);
    System.assertEquals(
      null,
      LaneBenchmarkController.mapPreviewUrl(null, null, null, null, 'MI'),
      'no radius end -> no map'
    );
    System.assertEquals(
      null,
      LaneBenchmarkController.mapPreviewUrl(
        'montreal|qc|ca',
        null,
        'toronto|on|ca',
        null,
        'MI'
      )
    );
  }

  /**
   * excludeProjectId binds into a system-mode bid query, so honouring it for a project the caller
   * cannot read would let two searches reveal which bids belong to an RFP they cannot see (spec
   * §5: that RFP does not exist for them). The exclusion counts only for a readable project. The
   * Lane_Benchmark_User has no RFP_Project__c read at all; the stranger holds RFP_Tool_User too, so
   * only the user-mode sharing check (no share on the customer) keeps the exclusion off for them.
   */
  @IsTest
  static void searchExcludesAProjectOnlyWhenTheCallerCanReadIt() {
    LaneSearchExclusions.excludedContactIdsOverride = new Set<String>();
    User viewer = restrictedUser('Lane_Benchmark_User');
    User stranger = restrictedUser(
      new List<String>{ 'RFP_Tool_User', 'Lane_Benchmark_User' }
    );
    if (viewer == null || stranger == null) {
      System.assert(
        true,
        'no usable profile in this org; runAs coverage skipped (ledgered)'
      );
      return;
    }
    PricingTestDataFactory.Graph g = PricingTestDataFactory.createGraph();
    Pricing_Place__c mtl = [
      SELECT Id, City__c, Province__c, Country__c, Postal_Prefix__c
      FROM Pricing_Place__c
      WHERE Key__c = 'montreal|qc|ca'
    ];
    Pricing_Place__c tor = [
      SELECT Id, City__c, Province__c, Country__c, Postal_Prefix__c
      FROM Pricing_Place__c
      WHERE Key__c = 'toronto|on|ca'
    ];
    RFP_Project__c project = RfpTestDataFactory.createProject(g.customer);
    RFP_Lane__c lane = RfpTestDataFactory.createLane(project, mtl, tor);
    BenchmarkRateService.save(RfpTestDataFactory.buildBid(lane, 1200));
    String requestJson =
      '{"originKey":"montreal|qc|ca","destinationKey":"toronto|on|ca",' +
      '"sourceFilter":"BIDS","excludeProjectId":"' +
      project.Id +
      '"}';
    Test.startTest();
    Integer viewerRows;
    System.runAs(viewer) {
      viewerRows = LaneBenchmarkController.search(requestJson).rows.size();
    }
    Id projectId = project.Id;
    Integer strangerProjects;
    Integer strangerRows;
    System.runAs(stranger) {
      strangerProjects = [
        SELECT COUNT()
        FROM RFP_Project__c
        WHERE Id = :projectId
        WITH USER_MODE
      ];
      strangerRows = LaneBenchmarkController.search(requestJson).rows.size();
    }
    Integer adminRows = LaneBenchmarkController.search(requestJson).rows.size();
    Test.stopTest();
    System.assertEquals(
      1,
      viewerRows,
      'a project the caller cannot read excludes nothing'
    );
    System.assertEquals(
      0,
      strangerProjects,
      'precondition: RFP read, but no share on the project\'s customer'
    );
    System.assertEquals(
      1,
      strangerRows,
      'a project hidden by sharing excludes nothing'
    );
    System.assertEquals(
      0,
      adminRows,
      'a project the caller can read keeps its exclusion'
    );
  }

  // ---- phase 7: truckRoute ----

  @IsTest
  static void truckRouteRoutesTwoPlaceKeysStoresTheRouteAndReusesIt() {
    MapboxHttp.tokenOverride = 'pk.test';
    DirectionsMock mock = new DirectionsMock(200, FOUND);
    Test.setMock(HttpCalloutMock.class, mock);
    Test.startTest();
    TripRouteView view = LaneBenchmarkController.truckRoute(
      'montreal|qc|ca',
      'toronto|on|ca',
      false
    );
    TripRouteView again = LaneBenchmarkController.truckRoute(
      'montreal|qc|ca',
      'toronto|on|ca',
      false
    );
    Test.stopTest();
    System.assertEquals('Found', view.status, 'message: ' + view.message);
    System.assertEquals('Truck', view.routeType);
    System.assertEquals('Truck route', view.source);
    System.assertEquals(335.5, view.miles);
    System.assertEquals(5.5, view.hours);
    System.assertEquals(2, view.routes.size());
    System.assert(
      view.mapUrl != null &&
        view.mapUrl.contains('pin-s-a+0070d2') &&
        view.mapUrl.contains('access_token=pk.test'),
      'pins, route and token in the static map'
    );
    System.assertEquals(null, view.lane, 'Lane Benchmark writes no lane');
    System.assertEquals(
      1,
      mock.calls,
      'the second search is answered by the store'
    );
    System.assertEquals(335.5, again.miles);
    Id mtlId = [SELECT Id FROM Pricing_Place__c WHERE Key__c = 'montreal|qc|ca']
    .Id;
    Id torId = [SELECT Id FROM Pricing_Place__c WHERE Key__c = 'toronto|on|ca']
    .Id;
    String key = TripMilesService.routeKey(
      mtlId,
      torId,
      TruckRoute.defaultProfile()
    );
    Truck_Route__c row = [
      SELECT Origin_Place__c, Destination_Place__c, Status__c, Miles__c
      FROM Truck_Route__c
      WHERE Route_Key__c = :key
    ];
    System.assertEquals(mtlId, row.Origin_Place__c);
    System.assertEquals(torId, row.Destination_Place__c);
    System.assertEquals('Found', row.Status__c);
    System.assertEquals(335.5, row.Miles__c);
    System.assertEquals(
      0,
      [SELECT COUNT() FROM Truck_Route__c WHERE Origin_Place__c = :torId],
      'direction matters: nothing stored for Toronto to Montréal'
    );
  }

  @IsTest
  static void truckRouteWithAnUnknownOrUnlocatedPlaceIsUnavailable() {
    insert place('Nowhere', 'QC', 'CA', null, null, 0, null);
    MapboxHttp.tokenOverride = 'pk.test';
    DirectionsMock mock = new DirectionsMock(200, FOUND);
    Test.setMock(HttpCalloutMock.class, mock);
    Test.startTest();
    List<TripRouteView> views = new List<TripRouteView>{
      LaneBenchmarkController.truckRoute(
        'nowhere|zz|zz',
        'toronto|on|ca',
        false
      ),
      LaneBenchmarkController.truckRoute(
        'montreal|qc|ca',
        'nowhere|qc|ca',
        true
      ),
      LaneBenchmarkController.truckRoute(null, 'toronto|on|ca', false)
    };
    Test.stopTest();
    System.assertEquals(0, mock.calls, 'no coordinates, no request');
    for (TripRouteView view : views) {
      System.assertEquals('Unavailable', view.status);
      System.assertEquals(TripRouteView.NO_COORDINATES, view.message);
      System.assertEquals(null, view.mapUrl, 'the radius preview stays');
    }
    Id mtlId = [SELECT Id FROM Pricing_Place__c WHERE Key__c = 'montreal|qc|ca']
    .Id;
    System.assertEquals(
      0,
      [SELECT COUNT() FROM Truck_Route__c WHERE Origin_Place__c = :mtlId]
    );
  }

  /**
   * A Lane Benchmark user, who holds no RFP permission and only Read on Truck_Route__c, gets and
   * stores a truck route (the save runs past CRUD in TripMilesService).
   */
  @IsTest
  static void aLaneBenchmarkUserGetsATruckRoute() {
    User viewer = restrictedUser('Lane_Benchmark_User');
    if (viewer == null) {
      System.assert(
        true,
        'no usable profile in this org; runAs coverage skipped (ledgered)'
      );
      return;
    }
    MapboxHttp.tokenOverride = 'pk.test';
    DirectionsMock mock = new DirectionsMock(200, FOUND);
    Test.setMock(HttpCalloutMock.class, mock);
    Test.startTest();
    TripRouteView view;
    System.runAs(viewer) {
      view = LaneBenchmarkController.truckRoute(
        'montreal|qc|ca',
        'toronto|on|ca',
        false
      );
    }
    Test.stopTest();
    System.assertEquals('Found', view.status, 'message: ' + view.message);
    System.assertEquals(335.5, view.miles);
    System.assertNotEquals(null, view.mapUrl);
    System.assertEquals(1, mock.calls);
    Id mtlId = [SELECT Id FROM Pricing_Place__c WHERE Key__c = 'montreal|qc|ca']
    .Id;
    System.assertEquals(
      1,
      [SELECT COUNT() FROM Truck_Route__c WHERE Origin_Place__c = :mtlId]
    );
  }
}
