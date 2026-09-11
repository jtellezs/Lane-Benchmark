@IsTest
private class RfpHistoryServiceTest {
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
    PricingDepartmentController.excludedContactIdsOverride = new Set<String>();
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
      90
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
      'RADIUS-50KM',
      byId.get(nearby.Id).Hist_Precision__c,
      'fell back to radius'
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
      RfpHistoryService.run(ids, 'CITY', 90);
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
      RfpHistoryController.loadHistory(ids, 'CITY', 90);
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
    PricingDepartmentController.excludedContactIdsOverride = new Set<String>();
    RFP_Project__c p = RfpTestDataFactory.createProject(g.customer);
    RFP_Lane__c a = RfpTestDataFactory.createLane(p, mtl, tor);
    RFP_Lane__c b = RfpTestDataFactory.createLane(p, mtl, tor);
    List<RFP_Lane__c> out = RfpHistoryService.run(
      new List<Id>{ a.Id, b.Id },
      'CITY',
      999999
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
    PricingDepartmentController.excludedContactIdsOverride = new Set<String>();
    RFP_Project__c p = RfpTestDataFactory.createProject(g.customer);
    RFP_Lane__c lane = RfpTestDataFactory.createLane(p, nowhere, tor);
    List<RFP_Lane__c> out = RfpHistoryService.run(
      new List<Id>{ lane.Id },
      'PROVINCE',
      90
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
    PricingDepartmentController.excludedContactIdsOverride = new Set<String>();
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
      90
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
    PricingDepartmentController.excludedContactIdsOverride = new Set<String>();
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
        RfpHistoryController.loadHistory(new List<Id>{ lane.Id }, 'CITY', 90);
        System.assert(false, 'expected an error');
      } catch (AuraHandledException e) {
        System.assertEquals(
          'History could not be loaded for this chunk.',
          e.getMessage()
        );
      }
    }
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
