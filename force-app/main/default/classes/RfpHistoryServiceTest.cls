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

  // RfpHistoryController's generic catch: a non-LaneSearchException (here, a DmlException from
  // Database.update writing an out-of-range Hist_Lookback_Days__c - precision 5, scale 0, so
  // 999999 does not fit) surfaces as the fixed "could not be loaded" sentence, not the raw
  // platform error.
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
    try {
      RfpHistoryController.loadHistory(new List<Id>{ lane.Id }, 'CITY', 999999);
      System.assert(false, 'expected an error');
    } catch (AuraHandledException e) {
      System.assertEquals(
        'History could not be loaded for this chunk.',
        e.getMessage()
      );
    }
  }
}
