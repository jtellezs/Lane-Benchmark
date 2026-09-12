@IsTest
private class RfpBulkControllerTest {
  @IsTest
  static void wrapsValidationAsUserErrors() {
    List<Id> none = new List<Id>();
    try {
      RfpBulkController.applyMedian(none, false);
      System.assert(false);
    } catch (AuraHandledException e) {
      System.assert(e.getMessage().contains('200'), e.getMessage());
    }
    try {
      RfpBulkController.applyPricing(none, null, null, null);
      System.assert(false);
    } catch (AuraHandledException e) {
      System.assert(e.getMessage().contains('Enter a cost'), e.getMessage());
    }
    try {
      RfpBulkController.applyBid(none, '{}');
      System.assert(false);
    } catch (AuraHandledException e) {
      System.assert(e.getMessage().contains('rate'), e.getMessage());
    }
    try {
      RfpBulkController.copyPricing(null, none);
      System.assert(false);
    } catch (AuraHandledException e) {
      System.assert(e.getMessage().containsIgnoreCase('cop'), e.getMessage());
    }
    try {
      RfpBulkController.deleteLanes(none);
      System.assert(false);
    } catch (AuraHandledException e) {
      System.assert(e.getMessage().contains('200'), e.getMessage());
    }
    try {
      RfpBulkController.applyBid(none, 'not json');
      System.assert(false);
    } catch (AuraHandledException e) {
      System.assert(e.getMessage().contains('could not'), e.getMessage());
    }
  }

  @IsTest
  static void happyPathReturnsTheResult() {
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
    RFP_Project__c p = RfpTestDataFactory.createProject(g.customer);
    RFP_Lane__c lane = RfpTestDataFactory.createLane(p, mtl, tor);
    RfpBulkService.Result r = RfpBulkController.applyPricing(
      new List<Id>{ lane.Id },
      1000,
      null,
      null
    );
    System.assertEquals(1, r.updated);
    System.assertEquals(1150.00, r.lanes[0].Sell__c);

    // Every other wrapper once on real data, so each success branch is exercised end to end.
    RFP_Lane__c second = RfpTestDataFactory.createLane(p, mtl, tor);
    update new RFP_Lane__c(
      Id = lane.Id,
      Hist_Median__c = 2000,
      Hist_Status__c = 'Done'
    );
    System.assertEquals(
      1,
      RfpBulkController.applyMedian(new List<Id>{ lane.Id }, true).updated
    );
    System.assertEquals(
      1,
      RfpBulkController.copyPricing(lane.Id, new List<Id>{ second.Id }).updated
    );
    System.assertEquals(
      1,
      RfpBulkController.applyBid(
          new List<Id>{ second.Id },
          '{"Carrier_Name__c":"Ctl","Rate__c":700,"CurrencyIsoCode":"CAD"}'
        )
        .updated
    );
    System.assertEquals(
      1,
      RfpBulkController.deleteLanes(new List<Id>{ second.Id }).updated
    );
  }

  /**
   * The four "could not" fallbacks. Only an unexpected (non-LaneSearchException) failure reaches
   * them, and the one the service can really hit is an access error: a user with no RFP_Lane__c
   * permission at all makes every action's user-mode SOQL throw before it can validate anything.
   */
  @IsTest
  static void wrapsUnexpectedFailuresAsUserErrors() {
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
    User stranger = strangerUser();
    if (stranger == null) {
      System.assert(
        true,
        'no usable profile in this org; runAs coverage skipped (ledgered)'
      );
      return;
    }
    List<Id> ids = new List<Id>{ lane.Id };
    Test.startTest();
    System.runAs(stranger) {
      try {
        RfpBulkController.applyMedian(ids, false);
        System.assert(false, 'expected a failure');
      } catch (AuraHandledException e) {
        System.assert(e.getMessage().contains('medians'), e.getMessage());
      }
      try {
        RfpBulkController.applyPricing(ids, 1000, null, null);
        System.assert(false, 'expected a failure');
      } catch (AuraHandledException e) {
        System.assert(
          e.getMessage().contains('could not be applied'),
          e.getMessage()
        );
      }
      try {
        RfpBulkController.copyPricing(lane.Id, ids);
        System.assert(false, 'expected a failure');
      } catch (AuraHandledException e) {
        System.assert(
          e.getMessage().contains('could not be copied'),
          e.getMessage()
        );
      }
      try {
        RfpBulkController.deleteLanes(ids);
        System.assert(false, 'expected a failure');
      } catch (AuraHandledException e) {
        System.assert(
          e.getMessage().contains('could not be deleted'),
          e.getMessage()
        );
      }
    }
    Test.stopTest();
  }

  /** A user holding no RFP permission set at all. Null when the org has no usable profile. */
  private static User strangerUser() {
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
      Username = 'bulk.' + System.currentTimeMillis() + '@example.invalid',
      Email = 'bulk@example.invalid',
      LastName = 'Bulk',
      Alias = 'bulk',
      TimeZoneSidKey = 'America/Toronto',
      LocaleSidKey = 'en_CA',
      EmailEncodingKey = 'UTF-8',
      LanguageLocaleKey = 'en_US'
    );
    System.runAs(new User(Id = UserInfo.getUserId())) {
      insert u;
    }
    return u;
  }
}
