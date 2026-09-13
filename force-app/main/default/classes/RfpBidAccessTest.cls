@IsTest
private class RfpBidAccessTest {
  private class Fx {
    PricingTestDataFactory.Graph g;
    RFP_Project__c project;
    RFP_Lane__c lane;
    RFP_Lane__c other;
  }

  private static Fx fx() {
    Fx f = new Fx();
    f.g = PricingTestDataFactory.createGraph();
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
    f.project = RfpTestDataFactory.createProject(f.g.customer);
    f.lane = RfpTestDataFactory.createLane(f.project, mtl, tor);
    f.other = RfpTestDataFactory.createLane(f.project, tor, mtl);
    return f;
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
      Username = 'bidaccess.' + System.currentTimeMillis() + '@example.invalid',
      Email = 'bidaccess@example.invalid',
      LastName = 'BidAccess',
      Alias = 'bidacc',
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

  @IsTest
  static void visibleLanesKeepsOnlyRealLanes() {
    Fx f = fx();
    Id fake =
      RFP_Lane__c.SObjectType.getDescribe().getKeyPrefix() + '000000000001';
    Set<Id> visible = RfpBidAccess.visibleLanes(new Set<Id>{ f.lane.Id, fake });
    System.assertEquals(new Set<Id>{ f.lane.Id }, visible);
    System.assertEquals(
      new Set<Id>(),
      RfpBidAccess.visibleLanes(new Set<Id>()),
      'an empty set asks nothing'
    );
    System.assertEquals(new Set<Id>(), RfpBidAccess.visibleLanes(null));
  }

  @IsTest
  static void assertLaneVisibleThrowsTheUserSentence() {
    Fx f = fx();
    RfpBidAccess.assertLaneVisible(f.lane.Id);
    Id fake =
      RFP_Lane__c.SObjectType.getDescribe().getKeyPrefix() + '000000000001';
    try {
      RfpBidAccess.assertLaneVisible(fake);
      System.assert(false, 'expected LaneSearchException');
    } catch (LaneSearchException e) {
      System.assertEquals(RfpBidAccess.LANE_UNAVAILABLE, e.getMessage());
    }
    try {
      RfpBidAccess.assertLaneVisible(null);
      System.assert(false, 'expected LaneSearchException');
    } catch (LaneSearchException e) {
      System.assertEquals(RfpBidAccess.LANE_UNAVAILABLE, e.getMessage());
    }
  }

  @IsTest
  static void insertBidsStampsLaneKeysAndReturnsInputOrder() {
    Fx f = fx();
    Test.startTest();
    List<Benchmark_Rate__c> saved = RfpBidAccess.insertBids(
      new List<Benchmark_Rate__c>{
        RfpTestDataFactory.buildBid(f.lane, 900),
        RfpTestDataFactory.buildBid(f.other, 700)
      }
    );
    Test.stopTest();
    System.assertEquals(2, saved.size());
    System.assertEquals(900, saved[0].Rate__c, 'input order is kept');
    System.assertEquals(700, saved[1].Rate__c);
    System.assertEquals(
      'Montréal, QC:Toronto, ON',
      saved[0].City_Lane__c,
      'the trigger stamped the lane keys'
    );
    System.assertEquals(f.project.Id, saved[0].RFP_Project__c);
  }

  @IsTest
  static void insertBidsRefusesABidWithoutALaneBeforeAnyDml() {
    fx();
    Benchmark_Rate__c orphan = new Benchmark_Rate__c(
      Carrier_Name__c = 'Orphan',
      Rate__c = 500,
      CurrencyIsoCode = 'CAD'
    );
    try {
      RfpBidAccess.insertBids(new List<Benchmark_Rate__c>{ orphan });
      System.assert(false, 'expected LaneSearchException');
    } catch (LaneSearchException e) {
      System.assertEquals('A bid needs a lane.', e.getMessage());
    }
    System.assertEquals(0, [SELECT COUNT() FROM Benchmark_Rate__c]);
  }

  @IsTest
  static void bidsOfLanesOrdersByRateAndIgnoresUnknownLanes() {
    Fx f = fx();
    RfpBidAccess.insertBids(
      new List<Benchmark_Rate__c>{
        RfpTestDataFactory.buildBid(f.lane, 900),
        RfpTestDataFactory.buildBid(f.lane, 650),
        RfpTestDataFactory.buildBid(f.other, 100)
      }
    );
    Id fake =
      RFP_Lane__c.SObjectType.getDescribe().getKeyPrefix() + '000000000001';
    List<Benchmark_Rate__c> bids = RfpBidAccess.bidsOfLanes(
      new Set<Id>{ f.lane.Id, fake }
    );
    System.assertEquals(2, bids.size(), 'only the asked lane, not the other');
    System.assertEquals(650, bids[0].Rate__c);
    System.assertEquals(900, bids[1].Rate__c);
    System.assertEquals(
      0,
      RfpBidAccess.bidsOfLanes(new Set<Id>{ fake }).size()
    );
  }

  @IsTest
  static void bidsByIdsKeepsInputOrderAndDropsUnknownIds() {
    Fx f = fx();
    List<Benchmark_Rate__c> saved = RfpBidAccess.insertBids(
      new List<Benchmark_Rate__c>{
        RfpTestDataFactory.buildBid(f.lane, 900),
        RfpTestDataFactory.buildBid(f.other, 700)
      }
    );
    Id fake =
      Benchmark_Rate__c.SObjectType.getDescribe().getKeyPrefix() +
      '000000000001';
    List<Benchmark_Rate__c> back = RfpBidAccess.bidsByIds(
      new List<Id>{ saved[1].Id, fake, saved[0].Id }
    );
    System.assertEquals(2, back.size());
    System.assertEquals(700, back[0].Rate__c);
    System.assertEquals(900, back[1].Rate__c);
    System.assertEquals(0, RfpBidAccess.bidsByIds(new List<Id>()).size());
  }

  @IsTest
  static void updateBidChangesTheRateButNotTheLane() {
    Fx f = fx();
    Benchmark_Rate__c saved = RfpBidAccess.insertBids(
      new List<Benchmark_Rate__c>{ RfpTestDataFactory.buildBid(f.lane, 900) }
    )[0];
    Benchmark_Rate__c edit = new Benchmark_Rate__c(
      Id = saved.Id,
      Rate__c = 950
    );
    Benchmark_Rate__c updated = RfpBidAccess.updateBid(edit);
    System.assertEquals(950, updated.Rate__c);
    System.assertEquals(f.lane.Id, updated.RFP_Lane__c);
    Benchmark_Rate__c move = new Benchmark_Rate__c(
      Id = saved.Id,
      RFP_Lane__c = f.other.Id
    );
    try {
      RfpBidAccess.updateBid(move);
      System.assert(false, 'expected LaneSearchException');
    } catch (LaneSearchException e) {
      System.assertEquals('A bid cannot move to another lane.', e.getMessage());
    }
    Id fake =
      Benchmark_Rate__c.SObjectType.getDescribe().getKeyPrefix() +
      '000000000001';
    try {
      RfpBidAccess.updateBid(new Benchmark_Rate__c(Id = fake, Rate__c = 1));
      System.assert(false, 'expected LaneSearchException');
    } catch (LaneSearchException e) {
      System.assertEquals(RfpBidAccess.LANE_UNAVAILABLE, e.getMessage());
    }
  }

  @IsTest
  static void deleteBidsOfLanesRemovesOnlyThoseLanesBids() {
    Fx f = fx();
    RfpBidAccess.insertBids(
      new List<Benchmark_Rate__c>{
        RfpTestDataFactory.buildBid(f.lane, 900),
        RfpTestDataFactory.buildBid(f.other, 700)
      }
    );
    List<Database.DeleteResult> results = RfpBidAccess.deleteBidsOfLanes(
      new Set<Id>{ f.lane.Id }
    );
    System.assertEquals(1, results.size());
    System.assert(results[0].isSuccess());
    System.assertEquals(
      1,
      [SELECT COUNT() FROM Benchmark_Rate__c],
      'the other lane keeps its bid'
    );
    System.assertEquals(
      0,
      RfpBidAccess.deleteBidsOfLanes(new Set<Id>()).size()
    );
  }

  @IsTest
  static void bidCountsByProjectCountsOnlyAskedProjects() {
    Fx f = fx();
    RfpBidAccess.insertBids(
      new List<Benchmark_Rate__c>{
        RfpTestDataFactory.buildBid(f.lane, 900),
        RfpTestDataFactory.buildBid(f.other, 700)
      }
    );
    RFP_Project__c second = RfpTestDataFactory.createProject(f.g.customer);
    Map<Id, Integer> counts = RfpBidAccess.bidCountsByProject(
      new Set<Id>{ f.project.Id, second.Id }
    );
    System.assertEquals(2, counts.get(f.project.Id));
    System.assertEquals(null, counts.get(second.Id), 'no bids, no entry');
    System.assertEquals(
      0,
      RfpBidAccess.bidCountsByProject(new Set<Id>()).size()
    );
  }

  @IsTest
  static void aReadOnlyUserCannotCreateEditOrDeleteBids() {
    Fx f = fx();
    User viewer = restrictedUser(new List<String>{ 'Lane_Benchmark_User' });
    if (viewer == null) {
      System.assert(
        true,
        'no usable profile in this org; runAs coverage skipped (ledgered)'
      );
      return;
    }
    Benchmark_Rate__c saved = RfpBidAccess.insertBids(
      new List<Benchmark_Rate__c>{ RfpTestDataFactory.buildBid(f.lane, 900) }
    )[0];
    System.runAs(viewer) {
      try {
        RfpBidAccess.insertBids(
          new List<Benchmark_Rate__c>{ RfpTestDataFactory.buildBid(f.lane, 1) }
        );
        System.assert(false, 'expected LaneSearchException');
      } catch (LaneSearchException e) {
        System.assertEquals('You cannot create bids.', e.getMessage());
      }
      try {
        RfpBidAccess.updateBid(
          new Benchmark_Rate__c(Id = saved.Id, Rate__c = 2)
        );
        System.assert(false, 'expected LaneSearchException');
      } catch (LaneSearchException e) {
        System.assertEquals('You cannot edit bids.', e.getMessage());
      }
      try {
        RfpBidAccess.deleteBidsOfLanes(new Set<Id>{ f.lane.Id });
        System.assert(false, 'expected LaneSearchException');
      } catch (LaneSearchException e) {
        System.assertEquals('You cannot delete bids.', e.getMessage());
      }
      // Lane_Benchmark_User has no RFP_Lane__c permission at all: no lane is visible, so the
      // rule hides every bid here even though the permission set can read Benchmark_Rate__c.
      System.assertEquals(
        0,
        RfpBidAccess.bidsOfLanes(new Set<Id>{ f.lane.Id }).size()
      );
      try {
        RfpBidAccess.assertLaneVisible(f.lane.Id);
        System.assert(false, 'expected LaneSearchException');
      } catch (LaneSearchException e) {
        System.assertEquals(RfpBidAccess.LANE_UNAVAILABLE, e.getMessage());
      }
    }
  }
}
