@IsTest
private class RfpBidControllerTest {
  @IsTest
  static void saveAndListBids() {
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
    RFP_Lane__c lane = RfpTestDataFactory.createLane(
      RfpTestDataFactory.createProject(g.customer),
      mtl,
      tor
    );
    String json =
      '{"RFP_Lane__c":"' +
      lane.Id +
      '","Carrier_Name__c":"New Carrier","Contact_Email__c":"a@b.invalid","Rate__c":1250,"CurrencyIsoCode":"CAD","Transit_Days__c":2}';
    Benchmark_Rate__c saved = RfpBidController.saveBid(json);
    System.assertEquals('New Carrier', saved.Carrier_Display__c);
    System.assertEquals('Active', saved.Status__c);
    RfpBidController.saveBid(
      '{"RFP_Lane__c":"' +
        lane.Id +
        '","Carrier__c":"' +
        g.vendor.Id +
        '","Rate__c":990,"CurrencyIsoCode":"CAD"}'
    );
    List<Benchmark_Rate__c> bids = RfpBidController.getBids(lane.Id);
    System.assertEquals(2, bids.size());
    System.assertEquals(990, bids[0].Rate__c, 'ordered by rate');
    try {
      RfpBidController.saveBid(
        '{"RFP_Lane__c":"' + lane.Id + '","Carrier_Name__c":"X"}'
      );
      System.assert(false, 'expected an error');
    } catch (AuraHandledException e) {
      System.assert(e.getMessage().contains('rate'), e.getMessage());
    }
  }

  // Not in the brief: added to satisfy the org's 75%-per-class deployment gate, which the brief
  // test above does not reach for RfpBidController (62.5%: the DmlException and generic Exception
  // catch branches of saveBid were never exercised).

  @IsTest
  static void saveBidWrapsTheValidationRuleAsUserError() {
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
    RFP_Lane__c lane = RfpTestDataFactory.createLane(
      RfpTestDataFactory.createProject(g.customer),
      mtl,
      tor
    );
    try {
      RfpBidController.saveBid(
        '{"RFP_Lane__c":"' +
          lane.Id +
          '","Rate__c":500,"CurrencyIsoCode":"CAD"}'
      );
      System.assert(false, 'expected an error');
    } catch (AuraHandledException e) {
      System.assert(e.getMessage().contains('carrier'), e.getMessage());
    }
  }

  /**
   * rfpBidForm posts "Carrier__c": null when an existing bid switches from a carrier account to a
   * typed name. The update must clear the lookup, or Carrier_Display__c keeps showing the account.
   * Both payloads carry every key rfpBidForm.handleSave sends, in its order (Id last, on an edit).
   */
  @IsTest
  static void switchingABidToATypedCarrierClearsTheAccount() {
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
    RFP_Lane__c lane = RfpTestDataFactory.createLane(
      RfpTestDataFactory.createProject(g.customer),
      mtl,
      tor
    );
    String rest =
      '"Contact_Name__c":null,"Contact_Email__c":null,"Contact_Phone__c":null,' +
      '"Rate__c":990,"CurrencyIsoCode":"CAD","Fuel_Surcharge__c":null,' +
      '"FSC_Included__c":false,"Transit_Days__c":null,"Valid_From__c":"' +
      String.valueOf(Date.today()) +
      '","Expires_On__c":"' +
      String.valueOf(Date.today().addDays(30)) +
      '","Notes__c":null';
    Benchmark_Rate__c saved = RfpBidController.saveBid(
      '{"RFP_Lane__c":"' +
        lane.Id +
        '","Carrier__c":"' +
        g.vendor.Id +
        '","Carrier_Name__c":null,' +
        rest +
        '}'
    );
    System.assertEquals(g.vendor.Id, saved.Carrier__c);
    System.assertEquals('Test Carrier', saved.Carrier_Display__c);
    Test.startTest();
    Benchmark_Rate__c switched = RfpBidController.saveBid(
      '{"RFP_Lane__c":"' +
        lane.Id +
        '","Carrier__c":null,"Carrier_Name__c":"Typed Carrier",' +
        rest +
        ',"Id":"' +
        saved.Id +
        '"}'
    );
    Test.stopTest();
    System.assertEquals(null, switched.Carrier__c, 'the account is cleared');
    System.assertEquals(
      'Typed Carrier',
      switched.Carrier_Display__c,
      'the typed name shows'
    );
    System.assertEquals(
      null,
      [SELECT Carrier__c FROM Benchmark_Rate__c WHERE Id = :saved.Id].Carrier__c
    );
  }

  @IsTest
  static void saveBidWrapsBadJsonAsUserError() {
    try {
      RfpBidController.saveBid('not valid json');
      System.assert(false, 'expected an error');
    } catch (AuraHandledException e) {
      System.assert(e.getMessage().contains('saved'), e.getMessage());
    }
  }

  @IsTest
  static void getBidsOnAnUnknownLaneIsAUserError() {
    Id fake =
      RFP_Lane__c.SObjectType.getDescribe().getKeyPrefix() + '000000000001';
    try {
      RfpBidController.getBids(fake);
      System.assert(false, 'expected AuraHandledException');
    } catch (AuraHandledException e) {
      System.assertEquals(RfpBidAccess.LANE_UNAVAILABLE, e.getMessage());
    }
  }
}
