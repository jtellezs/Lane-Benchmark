@IsTest
private class RfpSecurityTest {
  /** Creates a user holding only the named permission set. Returns null when the org has no usable profile. */
  private static User restrictedUser(String permSetName) {
    return restrictedUser(new List<String>{ permSetName });
  }

  /** Creates a user holding only the named permission sets. Returns null when the org has no usable profile. */
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
      Username = 'rfp.' +
        System.currentTimeMillis() +
        '.' +
        permSetNames.size() +
        '@example.invalid',
      Email = 'rfp@example.invalid',
      LastName = 'Rfp',
      Alias = 'rfp',
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

  /**
   * Account is Private in this org and an RFP follows its account (phase 6): a manual share
   * on the customer is what lets a restricted user see, and with Read alone also work, the RFP.
   */
  private static void shareAccount(Account customer, User u, String level) {
    insert new AccountShare(
      AccountId = customer.Id,
      UserOrGroupId = u.Id,
      AccountAccessLevel = level,
      OpportunityAccessLevel = 'None',
      CaseAccessLevel = 'None',
      RowCause = 'Manual'
    );
  }

  private class Fx {
    PricingTestDataFactory.Graph g;
    Pricing_Place__c mtl;
    Pricing_Place__c laval;
    Pricing_Place__c tor;
    RFP_Lane__c lane;
  }
  private static Fx fx() {
    Fx f = new Fx();
    f.g = PricingTestDataFactory.createGraph();
    f.mtl = RfpTestDataFactory.createPlace(
      'Montréal',
      'QC',
      'CA',
      45.5019,
      -73.5674,
      'H1A'
    );
    f.laval = RfpTestDataFactory.createPlace(
      'Laval',
      'QC',
      'CA',
      45.6066,
      -73.7124,
      'H7P'
    );
    f.tor = RfpTestDataFactory.createPlace(
      'Toronto',
      'ON',
      'CA',
      43.6532,
      -79.3832,
      'M5V'
    );
    f.lane = RfpTestDataFactory.createLane(
      RfpTestDataFactory.createProject(f.g.customer),
      f.mtl,
      f.tor
    );
    LaneSearchExclusions.excludedContactIdsOverride = new Set<String>();
    return f;
  }
  private static LaneSearchRequest req(
    String o,
    String d,
    LaneSearchRequest.Precision p
  ) {
    LaneSearchRequest r = new LaneSearchRequest();
    r.originKey = o;
    r.destinationKey = d;
    r.originPrecision = p;
    r.destinationPrecision = p;
    if (p == LaneSearchRequest.Precision.RADIUS) {
      r.originRadius = 50;
      r.destinationRadius = 50;
      r.radiusUnit = LaneSearchRequest.Unit.KM;
    }
    r.sourceFilter = LaneSearchRequest.RowSource.BIDS;
    return r;
  }

  @IsTest
  static void bidIsFoundAtEveryPrecision() {
    Fx f = fx();
    BenchmarkRateService.save(RfpTestDataFactory.buildBid(f.lane, 1200));
    Test.startTest();
    LaneSearchResult city = LaneSearchService.search(
      req('montreal|qc|ca', 'toronto|on|ca', LaneSearchRequest.Precision.CITY)
    );
    LaneSearchResult prov = LaneSearchService.search(
      req('laval|qc|ca', 'toronto|on|ca', LaneSearchRequest.Precision.PROVINCE)
    );
    LaneSearchResult zip3 = LaneSearchService.search(
      req('montreal|qc|ca', 'toronto|on|ca', LaneSearchRequest.Precision.ZIP3)
    );
    LaneSearchResult radius = LaneSearchService.search(
      req('laval|qc|ca', 'toronto|on|ca', LaneSearchRequest.Precision.RADIUS)
    );
    Test.stopTest();
    System.assertEquals(1, city.rows.size(), 'CITY');
    System.assertEquals(
      1,
      prov.rows.size(),
      'PROVINCE (QC:ON matches from Laval)'
    );
    System.assertEquals(1, zip3.rows.size(), 'ZIP3 H1A:M5V');
    System.assertEquals(
      1,
      radius.rows.size(),
      'RADIUS 50 km from Laval reaches Montréal'
    );
    System.assertNotEquals(null, radius.rows[0].bid);
  }

  @IsTest
  static void readOnTheAccountIsEnoughToRecordABidAndLaneBenchmarkSeesIt() {
    Fx f = fx();
    User pricing = restrictedUser('RFP_Tool_User');
    User viewer = restrictedUser('Lane_Benchmark_User');
    if (pricing == null || viewer == null) {
      System.assert(
        true,
        'no usable profile in this org; runAs coverage skipped (ledgered)'
      );
      return;
    }
    shareAccount(f.g.customer, pricing, 'Read');
    Test.startTest();
    Benchmark_Rate__c saved;
    Benchmark_Rate__c resaved;
    System.runAs(pricing) {
      saved = BenchmarkRateService.save(
        RfpTestDataFactory.buildBid(f.lane, 900)
      );
      // RFP_Tool_User grants read on these service-maintained keys but editable=false;
      // resubmitting a record that carries them is exactly what an unhardened save() fails on
      // for a restricted user (FLS is checked against every populated field, not just changed
      // ones), and exactly what Security.stripInaccessible must clear before the DML.
      Benchmark_Rate__c queried = [
        SELECT Id, Rate__c, City_Lane__c, State_Lane__c, Zip3_Lane__c
        FROM Benchmark_Rate__c
        WHERE Id = :saved.Id
      ];
      queried.Rate__c = 950;
      resaved = BenchmarkRateService.save(queried);
    }
    Integer seen;
    System.runAs(viewer) {
      seen = LaneSearchService.search(
          req(
            'montreal|qc|ca',
            'toronto|on|ca',
            LaneSearchRequest.Precision.CITY
          )
        )
        .rows.size();
    }
    Test.stopTest();
    System.assertEquals(
      'Montréal, QC:Toronto, ON',
      [SELECT City_Lane__c FROM Benchmark_Rate__c WHERE Id = :saved.Id]
      .City_Lane__c
    );
    System.assertEquals(1, seen);
    System.assertEquals(950, resaved.Rate__c);
    System.assertEquals('Montréal, QC:Toronto, ON', resaved.City_Lane__c);
  }

  @IsTest
  static void rfpToolUserCanDeleteTheirLanesAndBids() {
    Fx f = fx();
    User pricing = restrictedUser('RFP_Tool_User');
    if (pricing == null) {
      System.assert(
        true,
        'no usable profile in this org; runAs coverage skipped (ledgered)'
      );
      return;
    }
    // An RFP follows its account (phase 6): Read on the customer is what lets the restricted
    // user work the admin's project - delete its lanes and, through RfpBidAccess, its bids.
    RFP_Project__c own = RfpTestDataFactory.createProject(f.g.customer);
    RFP_Lane__c lane = RfpTestDataFactory.createLane(own, f.mtl, f.tor);
    shareAccount(f.g.customer, pricing, 'Read');
    Id laneId = lane.Id;
    Test.startTest();
    RfpBulkService.Result r;
    Id bidId;
    System.runAs(pricing) {
      bidId = BenchmarkRateService.save(RfpTestDataFactory.buildBid(lane, 900))
        .Id;
      r = RfpBulkController.deleteLanes(new List<Id>{ laneId });
    }
    Test.stopTest();
    System.assertEquals(1, r.updated, String.join(r.errors, '; '));
    // deleteLanes collects the bid pass with count=false, and Benchmark_Rate__c.RFP_Lane__c is a
    // SetNull lookup: a bid the user may not delete would survive with a null lookup and every
    // count-by-lane assertion would still read 0. Assert on the bid's own Id, and on no errors.
    System.assert(r.errors.isEmpty(), String.join(r.errors, '; '));
    System.assertEquals(
      0,
      [SELECT COUNT() FROM RFP_Lane__c WHERE Id = :laneId]
    );
    System.assertEquals(
      0,
      [SELECT COUNT() FROM Benchmark_Rate__c WHERE Id = :bidId],
      'the bid itself is gone, not merely unlinked'
    );
    System.assertEquals(
      0,
      [SELECT COUNT() FROM Benchmark_Rate__c WHERE RFP_Lane__c = :laneId]
    );
  }

  /** Spec §5: without access to the account the RFP is absent everywhere, yet its bid still counts in Lane Benchmark. */
  @IsTest
  static void withoutAccountAccessTheRfpIsAbsentButLaneBenchmarkStillCountsItsBid() {
    Fx f = fx();
    User stranger = restrictedUser(
      new List<String>{ 'RFP_Tool_User', 'Lane_Benchmark_User' }
    );
    if (stranger == null) {
      System.assert(
        true,
        'no usable profile in this org; runAs coverage skipped (ledgered)'
      );
      return;
    }
    Benchmark_Rate__c adminBid = BenchmarkRateService.save(
      RfpTestDataFactory.buildBid(f.lane, 900)
    );
    Id laneId = f.lane.Id;
    Id accountId = f.g.customer.Id;
    Test.startTest();
    System.runAs(stranger) {
      System.assertEquals(
        0,
        [SELECT COUNT() FROM RFP_Project__c WITH USER_MODE],
        'no project on an account the user cannot read'
      );
      System.assertEquals(
        0,
        [SELECT COUNT() FROM RFP_Lane__c WHERE Id = :laneId WITH USER_MODE]
      );
      System.assertEquals(
        0,
        RfpController.projectsForAccount(accountId).size()
      );
      try {
        RfpBidController.getBids(laneId);
        System.assert(false, 'expected AuraHandledException');
      } catch (AuraHandledException e) {
        System.assertEquals(RfpBidAccess.LANE_UNAVAILABLE, e.getMessage());
      }
      try {
        RfpBidController.saveBid(
          JSON.serialize(RfpTestDataFactory.buildBid(f.lane, 800))
        );
        System.assert(false, 'expected AuraHandledException');
      } catch (AuraHandledException e) {
        System.assertEquals(RfpBidAccess.LANE_UNAVAILABLE, e.getMessage());
      }
      LaneSearchResult found = LaneSearchService.search(
        req('montreal|qc|ca', 'toronto|on|ca', LaneSearchRequest.Precision.CITY)
      );
      System.assertEquals(
        1,
        found.rows.size(),
        'Lane Benchmark still sees the bid'
      );
    }
    Test.stopTest();
    System.assertEquals(
      1,
      [SELECT COUNT() FROM Benchmark_Rate__c WHERE Id = :adminBid.Id],
      'nothing was written by the refused calls'
    );
  }

  /** Spec §5: Read on the account lets a user create a project and lanes, record a bid, and read a colleague's bid. */
  @IsTest
  static void readOnTheAccountLetsAUserCreateAProjectItsLanesAndBids() {
    Fx f = fx();
    User reader = restrictedUser('RFP_Tool_User');
    if (reader == null) {
      System.assert(
        true,
        'no usable profile in this org; runAs coverage skipped (ledgered)'
      );
      return;
    }
    shareAccount(f.g.customer, reader, 'Read');
    Benchmark_Rate__c adminBid = BenchmarkRateService.save(
      RfpTestDataFactory.buildBid(f.lane, 900)
    );
    f.lane.Selected_Bid__c = adminBid.Id;
    f.lane.Cost_Source__c = 'Bid';
    f.lane.Cost__c = 900;
    update f.lane;
    Id accountId = f.g.customer.Id;
    Test.startTest();
    Id newLaneId;
    System.runAs(reader) {
      RFP_Project__c created = RfpProjectController.saveProject(
        JSON.serialize(
          new RFP_Project__c(
            Name = 'Reader RFP',
            Customer__c = accountId,
            Status__c = 'Draft',
            Default_Margin__c = 15,
            CurrencyIsoCode = 'CAD'
          )
        )
      );
      System.assertNotEquals(
        null,
        created.Id,
        'Read on the account creates a detail'
      );
      RFP_Lane__c lane = RfpTestDataFactory.createLane(created, f.laval, f.tor);
      newLaneId = lane.Id;
      Benchmark_Rate__c mine = BenchmarkRateService.save(
        RfpTestDataFactory.buildBid(lane, 700)
      );
      System.assertEquals(700, mine.Rate__c);
      List<Benchmark_Rate__c> colleagues = RfpBidController.getBids(f.lane.Id);
      System.assertEquals(
        1,
        colleagues.size(),
        'the admin\'s bid on a readable lane'
      );
      System.assertEquals(adminBid.Id, colleagues[0].Id);
      System.assert(
        RfpController.projectsForAccount(accountId).size() >= 2,
        'both projects on the shared account are listed'
      );
      // A colleague's bid as this lane's cost source: the lane save must accept it (the bid is
      // readable through the lane rule even though the user cannot read it under sharing).
      RFP_Lane__c priced = RfpLaneController.saveLanePricing(
        JSON.serialize(
          new RFP_Lane__c(
            Id = f.lane.Id,
            Cost__c = 900,
            Cost_Source__c = 'Bid',
            Selected_Bid__c = adminBid.Id,
            Margin__c = 15,
            Sell__c = 1058.82,
            Sell_Source__c = 'Margin'
          )
        )
      );
      System.assertEquals(
        adminBid.Id,
        priced.Selected_Bid__c,
        'a colleague\'s bid can be the cost source'
      );
      System.assert(
        String.isNotBlank(priced.Selected_Bid__r?.Carrier_Display__c),
        'and its carrier shows on the saved lane'
      );
      // Copying that pricing onto the reader's own lane carries the colleague's bid along.
      RfpBulkService.Result copied = RfpBulkController.copyPricing(
        f.lane.Id,
        new List<Id>{ newLaneId }
      );
      System.assertEquals(1, copied.updated, String.join(copied.errors, '; '));
      System.assertEquals(
        adminBid.Id,
        copied.lanes[0].Selected_Bid__c,
        'copyPricing keeps the colleague\'s bid'
      );
      // Selected_Bid__r is read through the lane in user mode (RfpLaneController.LANE_FIELDS).
      // A bid recorded by someone else must still show its carrier there; if this assertion
      // fails, the controller rules on the fix (fill Selected_Bid__r from RfpBidAccess.bidsByIds
      // in lanesByIds) - do not delete the assertion.
      RFP_Lane__c seen = RfpLaneController.lanesByIds(
        new List<Id>{ f.lane.Id }
      )[0];
      System.assert(
        String.isNotBlank(seen.Selected_Bid__r?.Carrier_Display__c),
        'the selected bid of a readable lane shows its carrier'
      );
    }
    Test.stopTest();
    System.assertEquals(
      1,
      [SELECT COUNT() FROM Benchmark_Rate__c WHERE RFP_Lane__c = :newLaneId]
    );
  }

  /**
   * Class security is not enforced Apex to Apex, so calling a controller from a test proves
   * nothing about the permission set. Read the grant out of the metadata instead: a workbench
   * controller missing here is the "You do not have access to the Apex class named ..." error
   * the pricing team hits in the browser on every bulk action.
   */
  @IsTest
  static void rfpToolUserHasClassAccessToEveryWorkbenchController() {
    PermissionSet ps = [
      SELECT Id
      FROM PermissionSet
      WHERE Name = 'RFP_Tool_User'
    ];
    Set<Id> ids = new Set<Id>();
    for (SetupEntityAccess a : [
      SELECT SetupEntityId
      FROM SetupEntityAccess
      WHERE ParentId = :ps.Id AND SetupEntityType = 'ApexClass'
    ]) {
      ids.add(a.SetupEntityId);
    }
    Set<String> granted = new Set<String>();
    for (ApexClass c : [SELECT Id, Name FROM ApexClass WHERE Id IN :ids]) {
      granted.add(c.Name);
    }
    for (
      String name : new List<String>{
        'RfpBulkController',
        'RfpBulkService',
        'RfpBidController',
        'RfpLaneController',
        'RfpHistoryController',
        'RfpProjectController'
      }
    ) {
      System.assert(
        granted.contains(name),
        'RFP_Tool_User grants no class access to ' + name
      );
    }
  }
}
