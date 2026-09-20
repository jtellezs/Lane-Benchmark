@IsTest
private class RfpBidAccessTest {
  private class Fx {
    PricingTestDataFactory.Graph g;
    Pricing_Place__c mtl;
    Pricing_Place__c tor;
    RFP_Project__c project;
    RFP_Lane__c lane;
    RFP_Lane__c other;
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
    f.tor = RfpTestDataFactory.createPlace(
      'Toronto',
      'ON',
      'CA',
      43.6532,
      -79.3832,
      'M5V'
    );
    f.project = RfpTestDataFactory.createProject(f.g.customer);
    f.lane = RfpTestDataFactory.createLane(f.project, f.mtl, f.tor);
    f.other = RfpTestDataFactory.createLane(f.project, f.tor, f.mtl);
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
    // An explicit null lane is a move too: the system-mode update would orphan the bid.
    Benchmark_Rate__c orphaning = new Benchmark_Rate__c(
      Id = saved.Id,
      RFP_Lane__c = null,
      Rate__c = 975
    );
    try {
      RfpBidAccess.updateBid(orphaning);
      System.assert(false, 'expected LaneSearchException');
    } catch (LaneSearchException e) {
      System.assertEquals('A bid cannot move to another lane.', e.getMessage());
    }
    Benchmark_Rate__c kept = [
      SELECT RFP_Lane__c, Rate__c
      FROM Benchmark_Rate__c
      WHERE Id = :saved.Id
    ];
    System.assertEquals(f.lane.Id, kept.RFP_Lane__c, 'the bid keeps its lane');
    System.assertEquals(950, kept.Rate__c, 'and nothing of the refused edit');
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
      // Phase 9 (commit 9c05a02, "Add the Market_Test__c marker and the permissions it needs")
      // gave Lane_Benchmark_User create, edit and delete on Benchmark_Rate__c, because a market
      // test rate IS a Benchmark_Rate__c and a pricer has to be able to add one. So the object
      // gates - Gate.create/edit/remove, which only ask isCreateable/isUpdateable/isDeletable -
      // no longer refuse this user, and asserting that they do (as this test did until 2026-09-20,
      // failing unnoticed ever since phase 9) tests a boundary the app deliberately moved.
      //
      // What actually keeps a Lane Benchmark pricer out of another team's RFP bids is lane
      // visibility, and that is what this now asserts on all three verbs.
      try {
        RfpBidAccess.insertBids(
          new List<Benchmark_Rate__c>{ RfpTestDataFactory.buildBid(f.lane, 1) }
        );
        System.assert(false, 'expected LaneSearchException');
      } catch (LaneSearchException e) {
        System.assertEquals(
          'A bid needs a lane.',
          e.getMessage(),
          'the lane is stripped by stripInaccessible before the lane gate sees it, because this ' +
          'user cannot read RFP_Lane__c at all - so the bid arrives with no lane to attach to'
        );
      }
      try {
        RfpBidAccess.updateBid(
          new Benchmark_Rate__c(Id = saved.Id, Rate__c = 2)
        );
        System.assert(false, 'expected LaneSearchException');
      } catch (LaneSearchException e) {
        System.assertEquals(
          RfpBidAccess.LANE_UNAVAILABLE,
          e.getMessage(),
          'the stored bid does have a lane, so updateBid gets as far as assertLaneVisible - and ' +
          'that is the gate that refuses'
        );
      }
      // Delete refuses by finding nothing rather than by throwing: deleteBidsOfLanes asks
      // bidsOfLanes first, and no lane of this one is visible, so there is nothing to delete. It
      // fails safe, but silently - worth asserting precisely because a silent no-op is the kind of
      // protection someone later mistakes for a missing check.
      System.assertEquals(
        0,
        RfpBidAccess.deleteBidsOfLanes(new Set<Id>{ f.lane.Id }).size(),
        'deletes nothing, because no bid of an invisible lane is visible to delete'
      );
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

  @IsTest
  static void updateBidAcceptsARecordQueriedWithoutTheLaneField() {
    Fx f = fx();
    Benchmark_Rate__c saved = RfpBidAccess.insertBids(
      new List<Benchmark_Rate__c>{ RfpTestDataFactory.buildBid(f.lane, 900) }
    )[0];
    // A record page or a re-save hands back a record queried without RFP_Lane__c;
    // reading that field on it would throw SObjectException.
    Benchmark_Rate__c queried = [
      SELECT Id, Rate__c, City_Lane__c
      FROM Benchmark_Rate__c
      WHERE Id = :saved.Id
    ];
    queried.Rate__c = 925;
    Benchmark_Rate__c updated = RfpBidAccess.updateBid(queried);
    System.assertEquals(925, updated.Rate__c);
    System.assertEquals(
      f.lane.Id,
      updated.RFP_Lane__c,
      'the lane is unchanged'
    );
  }

  @IsTest
  static void attachSelectedBidsFillsTheRelationshipOnALaneQueriedWithoutIt() {
    Fx f = fx();
    Benchmark_Rate__c saved = RfpBidAccess.insertBids(
      new List<Benchmark_Rate__c>{ RfpTestDataFactory.buildBid(f.lane, 900) }
    )[0];
    f.lane.Selected_Bid__c = saved.Id;
    update f.lane;
    // The lane as a user-mode read hands it back when the bid is another user's Private one:
    // the Id is there, the traversal is not.
    List<RFP_Lane__c> lanes = [
      SELECT Id, Selected_Bid__c
      FROM RFP_Lane__c
      WHERE Id = :f.lane.Id
    ];
    List<RFP_Lane__c> filled = RfpBidAccess.attachSelectedBids(lanes);
    System.assertEquals(1, filled.size());
    System.assertNotEquals(
      null,
      filled[0].Selected_Bid__r,
      'the relationship is filled'
    );
    System.assertEquals(saved.Id, filled[0].Selected_Bid__r.Id);
    System.assertEquals(
      'Bid Carrier',
      filled[0].Selected_Bid__r.Carrier_Display__c,
      'the carrier the lane panel and the export need'
    );
  }

  @IsTest
  static void attachSelectedBidsLeavesALaneWithoutASelectedBidAlone() {
    Fx f = fx();
    List<RFP_Lane__c> lanes = [
      SELECT Id, Selected_Bid__c
      FROM RFP_Lane__c
      WHERE Id = :f.lane.Id
    ];
    List<RFP_Lane__c> back = RfpBidAccess.attachSelectedBids(lanes);
    System.assertEquals(1, back.size());
    System.assertEquals(null, back[0].Selected_Bid__c);
    System.assertEquals(
      0,
      RfpBidAccess.attachSelectedBids(new List<RFP_Lane__c>()).size(),
      'an empty list comes back empty'
    );
  }

  @IsTest
  static void detachAndApplyCarryTheSelectedBidPastTheCrossReferenceCheck() {
    Fx f = fx();
    Benchmark_Rate__c saved = RfpBidAccess.insertBids(
      new List<Benchmark_Rate__c>{ RfpTestDataFactory.buildBid(f.lane, 900) }
    )[0];
    List<RFP_Lane__c> updates = new List<RFP_Lane__c>{
      new RFP_Lane__c(
        Id = f.lane.Id,
        Cost__c = 900,
        Selected_Bid__c = saved.Id
      ),
      new RFP_Lane__c(Id = f.other.Id, Cost__c = 700)
    };
    List<RFP_Lane__c> deferred = RfpBidAccess.detachSelectedBids(updates);
    System.assertEquals(1, deferred.size(), 'only the update naming a bid');
    System.assertEquals(f.lane.Id, deferred[0].Id);
    System.assertEquals(saved.Id, deferred[0].Selected_Bid__c);
    System.assertEquals(
      null,
      updates[0].Selected_Bid__c,
      'the field is nulled on the update that runs in user mode'
    );
    update updates;
    RfpBidAccess.applySelectedBids(deferred);
    RFP_Lane__c stored = [
      SELECT Selected_Bid__c
      FROM RFP_Lane__c
      WHERE Id = :f.lane.Id
    ];
    System.assertEquals(
      saved.Id,
      stored.Selected_Bid__c,
      'the bid is written back'
    );
  }

  @IsTest
  static void applySelectedBidsSkipsALaneWhosePricingUpdateWasRefused() {
    Fx f = fx();
    List<Benchmark_Rate__c> saved = RfpBidAccess.insertBids(
      new List<Benchmark_Rate__c>{
        RfpTestDataFactory.buildBid(f.lane, 900),
        RfpTestDataFactory.buildBid(f.other, 700)
      }
    );
    List<RFP_Lane__c> deferred = new List<RFP_Lane__c>{
      new RFP_Lane__c(Id = f.lane.Id, Selected_Bid__c = saved[0].Id),
      new RFP_Lane__c(Id = f.other.Id, Selected_Bid__c = saved[1].Id)
    };
    // Database.SaveResult has no constructor; JSON is the only way to stage a refused row.
    List<Database.SaveResult> results = new List<Database.SaveResult>{
      (Database.SaveResult) JSON.deserialize(
        '{"success":false,"id":"' + f.lane.Id + '"}',
        Database.SaveResult.class
      ),
      (Database.SaveResult) JSON.deserialize(
        '{"success":true,"id":"' + f.other.Id + '"}',
        Database.SaveResult.class
      )
    };
    RfpBidAccess.applySelectedBids(deferred, results);
    List<Id> bothLanes = new List<Id>{ f.lane.Id, f.other.Id };
    Map<Id, RFP_Lane__c> stored = new Map<Id, RFP_Lane__c>(
      [SELECT Id, Selected_Bid__c FROM RFP_Lane__c WHERE Id IN :bothLanes]
    );
    System.assertEquals(
      null,
      stored.get(f.lane.Id).Selected_Bid__c,
      'the lane whose pricing update was refused keeps no bid'
    );
    System.assertEquals(
      saved[1].Id,
      stored.get(f.other.Id).Selected_Bid__c,
      'the lane that saved gets its bid'
    );
  }

  @IsTest
  static void applySelectedBidsWritesNothingWhenEveryPricingUpdateFailed() {
    Fx f = fx();
    Benchmark_Rate__c saved = RfpBidAccess.insertBids(
      new List<Benchmark_Rate__c>{ RfpTestDataFactory.buildBid(f.lane, 900) }
    )[0];
    RfpBidAccess.applySelectedBids(
      new List<RFP_Lane__c>{
        new RFP_Lane__c(Id = f.lane.Id, Selected_Bid__c = saved.Id)
      },
      new List<Database.SaveResult>{
        (Database.SaveResult) JSON.deserialize(
          '{"success":false,"id":"' + f.lane.Id + '"}',
          Database.SaveResult.class
        )
      }
    );
    RFP_Lane__c stored = [
      SELECT Selected_Bid__c
      FROM RFP_Lane__c
      WHERE Id = :f.lane.Id
    ];
    System.assertEquals(
      null,
      stored.Selected_Bid__c,
      'nothing is written back'
    );
  }

  @IsTest
  static void detachSelectedBidsRefusesABidTheRuleHides() {
    Fx f = fx();
    Id fake =
      Benchmark_Rate__c.SObjectType.getDescribe().getKeyPrefix() +
      '000000000001';
    try {
      RfpBidAccess.detachSelectedBids(
        new List<RFP_Lane__c>{
          new RFP_Lane__c(Id = f.lane.Id, Selected_Bid__c = fake)
        }
      );
      System.assert(false, 'expected LaneSearchException');
    } catch (LaneSearchException e) {
      System.assertEquals('That bid is not available.', e.getMessage());
    }
    System.assertEquals(
      0,
      RfpBidAccess.detachSelectedBids(new List<RFP_Lane__c>()).size(),
      'nothing to defer for an empty list'
    );
  }

  /**
   * A lane deleted outside RfpBulkService.deleteLanes (the record page) leaves its bids with a
   * null RFP_Lane__c (set-null lookup); a bid that has lost its RFP_Project__c too (its project
   * deleted, or the field cleared by an admin) is granted to nobody, neither through a lane nor
   * through a project (R67). A lane that still points at such a bid must keep saving its margin,
   * sell and notes: the stored Selected_Bid__c carried forward unchanged is neither validated nor
   * deferred (R63). Both lookups are cleared, so a detach that validated the unchanged value would
   * refuse this save; with the project kept, R67 would grant the bid and hide that defect.
   */
  @IsTest
  static void anUnchangedSelectedBidWhoseLaneIsGoneStillSaves() {
    Fx f = fx();
    Benchmark_Rate__c saved = RfpBidAccess.insertBids(
      new List<Benchmark_Rate__c>{ RfpTestDataFactory.buildBid(f.lane, 900) }
    )[0];
    update new RFP_Lane__c(
      Id = f.other.Id,
      Cost__c = 900,
      Cost_Source__c = 'Bid',
      Selected_Bid__c = saved.Id
    );
    update new Benchmark_Rate__c(
      Id = saved.Id,
      RFP_Lane__c = null,
      RFP_Project__c = null
    );
    List<RFP_Lane__c> updates = new List<RFP_Lane__c>{
      new RFP_Lane__c(
        Id = f.other.Id,
        Selected_Bid__c = saved.Id,
        Margin__c = 20
      )
    };
    Test.startTest();
    List<RFP_Lane__c> deferred = RfpBidAccess.detachSelectedBids(updates);
    RFP_Lane__c priced = RfpLaneController.saveLanePricing(
      JSON.serialize(
        new RFP_Lane__c(
          Id = f.other.Id,
          Cost__c = 900,
          Cost_Source__c = 'Bid',
          Selected_Bid__c = saved.Id,
          Margin__c = 20,
          Sell__c = 1125,
          Sell_Source__c = 'Margin'
        )
      )
    );
    Test.stopTest();
    System.assertEquals(
      0,
      deferred.size(),
      'an unchanged selected bid is not deferred'
    );
    System.assertEquals(
      saved.Id,
      updates[0].Selected_Bid__c,
      'it stays on the update untouched'
    );
    System.assertEquals(20, priced.Margin__c, 'the new margin is saved');
    System.assertEquals(
      saved.Id,
      priced.Selected_Bid__c,
      'the lane keeps its selected bid'
    );
    System.assertEquals(
      saved.Id,
      [SELECT Selected_Bid__c FROM RFP_Lane__c WHERE Id = :f.other.Id]
      .Selected_Bid__c
    );
  }

  /**
   * A lane deleted with plain DML (the record page) clears its bids' RFP_Lane__c (set-null lookup)
   * and leaves their RFP_Project__c. Such a bid is granted through its project (R67): bidsByIds
   * returns it, and copying the pricing of a lane that selected it carries it to another lane, whose
   * carrier the attach then fills. A bid with neither a lane nor a project stays hidden.
   */
  @IsTest
  static void aBidWhoseLaneIsGoneIsGrantedThroughItsProject() {
    Fx f = fx();
    RFP_Lane__c target = RfpTestDataFactory.createLane(f.project, f.mtl, f.tor);
    Benchmark_Rate__c saved = RfpBidAccess.insertBids(
      new List<Benchmark_Rate__c>{ RfpTestDataFactory.buildBid(f.lane, 900) }
    )[0];
    update new RFP_Lane__c(
      Id = f.other.Id,
      Cost__c = 900,
      Cost_Source__c = 'Bid',
      Selected_Bid__c = saved.Id
    );
    delete new RFP_Lane__c(Id = f.lane.Id);
    Benchmark_Rate__c orphan = [
      SELECT RFP_Lane__c, RFP_Project__c
      FROM Benchmark_Rate__c
      WHERE Id = :saved.Id
    ];
    System.assertEquals(null, orphan.RFP_Lane__c, 'the lane lookup is cleared');
    System.assertEquals(
      f.project.Id,
      orphan.RFP_Project__c,
      'the project lookup stays'
    );
    Test.startTest();
    List<Benchmark_Rate__c> back = RfpBidAccess.bidsByIds(
      new List<Id>{ saved.Id }
    );
    RfpBulkService.Result copied = RfpBulkService.copyPricing(
      f.other.Id,
      new List<Id>{ target.Id }
    );
    Test.stopTest();
    System.assertEquals(1, back.size(), 'the project grants the bid');
    System.assertEquals(saved.Id, back[0].Id);
    System.assertEquals(1, copied.updated, String.join(copied.errors, '; '));
    System.assertEquals(
      saved.Id,
      [SELECT Selected_Bid__c FROM RFP_Lane__c WHERE Id = :target.Id]
      .Selected_Bid__c,
      'the target lane takes the bid whose lane is gone'
    );
    List<RFP_Lane__c> filled = RfpBidAccess.attachSelectedBids(
      [SELECT Id, Selected_Bid__c FROM RFP_Lane__c WHERE Id = :target.Id]
    );
    System.assertEquals(
      'Bid Carrier',
      filled[0].Selected_Bid__r?.Carrier_Display__c,
      'the attach fills the carrier of the target lane'
    );
    update new Benchmark_Rate__c(Id = saved.Id, RFP_Project__c = null);
    System.assertEquals(
      0,
      RfpBidAccess.bidsByIds(new List<Id>{ saved.Id }).size(),
      'a bid with neither a lane nor a project is granted to nobody'
    );
  }

  /** OwnerId is not caller-settable: a posted owner never reaches the system-mode update. */
  @IsTest
  static void updateBidIgnoresAPostedOwner() {
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
    Test.startTest();
    Benchmark_Rate__c updated = RfpBidAccess.updateBid(
      new Benchmark_Rate__c(Id = saved.Id, OwnerId = viewer.Id, Rate__c = 950)
    );
    Test.stopTest();
    System.assertEquals(950, updated.Rate__c, 'the rate is saved');
    System.assertEquals(
      UserInfo.getUserId(),
      [SELECT OwnerId FROM Benchmark_Rate__c WHERE Id = :saved.Id].OwnerId,
      'the owner is unchanged'
    );
  }

  /**
   * Proves the trigger stamp: BenchmarkRateTrigger overwrites RFP_Project__c with the lane's project
   * on every save, so this passes whether or not RFP_Project__c is on the allow-list.
   * settableFieldsLeaveOutEveryServiceMaintainedField proves the allow-list itself.
   */
  @IsTest
  static void insertBidsTakesTheProjectFromTheLaneNotTheCaller() {
    Fx f = fx();
    RFP_Project__c elsewhere = RfpTestDataFactory.createProject(f.g.customer);
    Benchmark_Rate__c posted = RfpTestDataFactory.buildBid(f.lane, 900);
    posted.RFP_Project__c = elsewhere.Id;
    Test.startTest();
    Benchmark_Rate__c saved = RfpBidAccess.insertBids(
      new List<Benchmark_Rate__c>{ posted }
    )[0];
    Test.stopTest();
    System.assertEquals(
      f.project.Id,
      saved.RFP_Project__c,
      'the lane\'s project, not the posted one'
    );
    System.assertEquals(
      f.project.Id,
      [SELECT RFP_Project__c FROM Benchmark_Rate__c WHERE Id = :saved.Id]
      .RFP_Project__c
    );
  }

  /**
   * The allow-list itself. The trigger re-stamps the project and the lane keys on every save, so a
   * service-maintained field wrongly added to SETTABLE_FIELDS would hide behind it in every
   * behaviour test. Compared lower-cased, the casing Rows.posted gives the populated keys.
   * RFP_Lane__c is deliberately not on the list: Rows.settable appends it on insert only, so an
   * update never writes the lane; the insert below carries it.
   */
  @IsTest
  static void settableFieldsLeaveOutEveryServiceMaintainedField() {
    Set<String> settable = new Set<String>(
      String.join(RfpBidAccess.SETTABLE_FIELDS, ',').toLowerCase().split(',')
    );
    Set<String> leaked = new Set<String>{
      'ownerid',
      'rfp_project__c',
      'city_lane__c',
      'state_lane__c',
      'zip3_lane__c',
      'origin_geolocation__c',
      'origin_geolocation__latitude__s',
      'origin_geolocation__longitude__s',
      'destination_geolocation__c',
      'destination_geolocation__latitude__s',
      'destination_geolocation__longitude__s'
    };
    leaked.retainAll(settable);
    System.assertEquals(
      new Set<String>(),
      leaked,
      'service-maintained fields must not be caller-settable'
    );
    System.assert(settable.contains('carrier__c'), 'the carrier is settable');
    System.assert(settable.contains('rate__c'), 'the rate is settable');
    System.assert(
      !settable.contains('rfp_lane__c'),
      'the lane is appended on insert only, never listed for an update'
    );
    Fx f = fx();
    Benchmark_Rate__c saved = RfpBidAccess.insertBids(
      new List<Benchmark_Rate__c>{ RfpTestDataFactory.buildBid(f.lane, 900) }
    )[0];
    System.assertEquals(
      f.lane.Id,
      saved.RFP_Lane__c,
      'an insert carries RFP_Lane__c'
    );
  }
}
