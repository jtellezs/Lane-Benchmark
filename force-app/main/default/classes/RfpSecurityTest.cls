@IsTest
private class RfpSecurityTest {
  /**
   * The admin's bid on f.lane after f.lane is deleted with plain DML, as the record page does: the
   * set-null lookup clears the bid's RFP_Lane__c and its RFP_Project__c stays.
   */
  private static Id orphanedBid(Fx f) {
    Id bidId = BenchmarkRateService.save(
        RfpTestDataFactory.buildBid(f.lane, 900)
      )
      .Id;
    delete new RFP_Lane__c(Id = f.lane.Id);
    return bidId;
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
    User pricing = RfpTestDataFactory.restrictedUser('RFP_Tool_User');
    User viewer = RfpTestDataFactory.restrictedUser('Lane_Benchmark_User');
    if (pricing == null || viewer == null) {
      System.assert(
        true,
        'no usable profile in this org; runAs coverage skipped (ledgered)'
      );
      return;
    }
    RfpTestDataFactory.shareAccount(f.g.customer, pricing, 'Read');
    Test.startTest();
    Benchmark_Rate__c saved;
    Benchmark_Rate__c resaved;
    System.runAs(pricing) {
      saved = BenchmarkRateService.save(
        RfpTestDataFactory.buildBid(f.lane, 900)
      );
      // RFP_Tool_User grants read on these service-maintained keys but editable=false. The bid
      // DML runs in system mode since phase 6, so this re-save no longer proves an FLS strip: it
      // proves that a queried record carrying service-maintained fields is accepted and that the
      // trigger re-stamps them. RfpBidAccess's allow-list of caller-settable fields is what keeps
      // those fields off the write.
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
  static void readSharedUserDeletesLanesAndAColleaguesBids() {
    Fx f = fx();
    User pricing = RfpTestDataFactory.restrictedUser('RFP_Tool_User');
    if (pricing == null) {
      System.assert(
        true,
        'no usable profile in this org; runAs coverage skipped (ledgered)'
      );
      return;
    }
    // An RFP follows its account (phase 6): Read on the customer is what lets the restricted
    // user work the admin's project - delete its lanes and, through RfpBidAccess, its bids. The
    // admin records the bid, so the delete removes a colleague's Private bid, not the user's own.
    RFP_Project__c own = RfpTestDataFactory.createProject(f.g.customer);
    RFP_Lane__c lane = RfpTestDataFactory.createLane(own, f.mtl, f.tor);
    RfpTestDataFactory.shareAccount(f.g.customer, pricing, 'Read');
    Id laneId = lane.Id;
    Id bidId = BenchmarkRateService.save(RfpTestDataFactory.buildBid(lane, 900))
      .Id;
    Test.startTest();
    RfpBulkService.Result r;
    System.runAs(pricing) {
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
    User stranger = RfpTestDataFactory.restrictedUser(
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
    // A second customer, with a lane of its own, that the stranger is given Read on after the
    // absence checks below: a readable lane must not let them name a bid on a lane they cannot read.
    Account second = RfpTestDataFactory.secondCustomer();
    RFP_Lane__c readable = RfpTestDataFactory.createLane(
      RfpTestDataFactory.createProject(second),
      f.laval,
      f.tor
    );
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
      try {
        RfpLaneController.laneRoute(laneId, false);
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
      System.assertEquals(
        0,
        RfpBidAccess.bidsByIds(new List<Id>{ adminBid.Id }).size(),
        'the rule hides a bid whose lane the user cannot read'
      );
      try {
        RfpBulkService.Result removed = RfpBulkController.deleteLanes(
          new List<Id>{ laneId }
        );
        System.assertEquals(
          0,
          removed.updated,
          'no lane of an RFP the user cannot see is deleted'
        );
      } catch (AuraHandledException e) {
        System.assert(
          e.getMessage().contains('not available'),
          'a refused delete names the missing lane: ' + e.getMessage()
        );
      }
    }
    RfpTestDataFactory.shareAccount(second, stranger, 'Read');
    System.runAs(stranger) {
      try {
        RfpLaneController.saveLanePricing(
          JSON.serialize(
            new RFP_Lane__c(
              Id = readable.Id,
              Cost__c = 900,
              Cost_Source__c = 'Bid',
              Selected_Bid__c = adminBid.Id,
              Margin__c = 15,
              Sell__c = 1058.82,
              Sell_Source__c = 'Margin'
            )
          )
        );
        System.assert(false, 'expected AuraHandledException');
      } catch (AuraHandledException e) {
        System.assert(
          e.getMessage().contains('That bid is not available.'),
          e.getMessage()
        );
      }
    }
    Test.stopTest();
    System.assertEquals(
      1,
      [SELECT COUNT() FROM Benchmark_Rate__c WHERE Id = :adminBid.Id],
      'nothing was written by the refused calls'
    );
    System.assertEquals(
      1,
      [SELECT COUNT() FROM RFP_Lane__c WHERE Id = :laneId],
      'the lane survived the refused delete'
    );
    System.assertEquals(
      null,
      [SELECT Selected_Bid__c FROM RFP_Lane__c WHERE Id = :readable.Id]
      .Selected_Bid__c,
      'the readable lane did not take the hidden bid'
    );
  }

  /** Spec §5: Read on the account lets a user create a project and lanes, record a bid, and read a colleague's bid. */
  @IsTest
  static void readOnTheAccountLetsAUserCreateAProjectItsLanesAndBids() {
    Fx f = fx();
    User reader = RfpTestDataFactory.restrictedUser('RFP_Tool_User');
    if (reader == null) {
      System.assert(
        true,
        'no usable profile in this org; runAs coverage skipped (ledgered)'
      );
      return;
    }
    RfpTestDataFactory.shareAccount(f.g.customer, reader, 'Read');
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
      // The admin's Private bid on a readable lane is the reader's to edit.
      Benchmark_Rate__c edited = RfpBidController.saveBid(
        JSON.serialize(new Benchmark_Rate__c(Id = adminBid.Id, Rate__c = 925))
      );
      System.assertEquals(
        925,
        edited.Rate__c,
        'a colleague\'s bid on a readable lane is editable'
      );
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
      List<RFP_Lane__c> listed = RfpLaneController.getLanes(
        f.lane.RFP_Project__c
      );
      System.assertEquals(
        1,
        listed.size(),
        'the admin\'s project lists its lane'
      );
      System.assertEquals(f.lane.Id, listed[0].Id);
      System.assert(
        String.isNotBlank(listed[0].Selected_Bid__r?.Carrier_Display__c),
        'getLanes shows the carrier of a colleague\'s selected bid'
      );
      // Last: deleting the lane takes the admin's bid with it.
      RfpBulkService.Result removed = RfpBulkController.deleteLanes(
        new List<Id>{ f.lane.Id }
      );
      System.assertEquals(
        1,
        removed.updated,
        String.join(removed.errors, '; ')
      );
    }
    Test.stopTest();
    System.assertEquals(
      1,
      [SELECT COUNT() FROM Benchmark_Rate__c WHERE RFP_Lane__c = :newLaneId]
    );
    System.assertEquals(
      0,
      [SELECT COUNT() FROM Benchmark_Rate__c WHERE Id = :adminBid.Id],
      'the reader\'s lane delete removed the admin\'s bid'
    );
  }

  /**
   * Carrier__c is a lookup to Account, and Account is Private. The bid DML runs in system mode,
   * which skips the sharing check the platform makes on a lookup target, and the reload's
   * Carrier_Display__c would hand back the account's name. So a bid save may name a carrier
   * account only if the caller can read it in user mode (R66).
   */
  @IsTest
  static void aBidSaveNamesOnlyACarrierAccountTheCallerCanRead() {
    Fx f = fx();
    User pricing = RfpTestDataFactory.restrictedUser('RFP_Tool_User');
    if (pricing == null) {
      System.assert(
        true,
        'no usable profile in this org; runAs coverage skipped (ledgered)'
      );
      return;
    }
    RfpTestDataFactory.shareAccount(f.g.customer, pricing, 'Read');
    Account carrier = RfpTestDataFactory.hiddenCarrier();
    Id carrierId = carrier.Id;
    if (!RfpTestDataFactory.hiddenFrom(pricing, carrierId)) {
      System.assert(
        true,
        'this org shares the hidden carrier ' +
          RfpTestDataFactory.sharingInputs(carrierId) +
          '; carrier check coverage skipped (ledgered, R68)'
      );
      return;
    }
    Id laneId = f.lane.Id;
    // What rfpBidForm posts for a new bid on a carrier picked from the account lookup.
    String bidJson =
      '{"RFP_Lane__c":"' +
      laneId +
      '","Carrier__c":"' +
      carrierId +
      '","Carrier_Name__c":null,"Rate__c":880,"CurrencyIsoCode":"CAD"}';
    Test.startTest();
    System.runAs(pricing) {
      try {
        RfpBidController.saveBid(bidJson);
        System.assert(false, 'expected AuraHandledException');
      } catch (AuraHandledException e) {
        System.assertEquals('That carrier is not available.', e.getMessage());
      }
    }
    System.assertEquals(
      0,
      [SELECT COUNT() FROM Benchmark_Rate__c WHERE RFP_Lane__c = :laneId],
      'the refused save wrote no bid'
    );
    RfpTestDataFactory.shareAccount(carrier, pricing, 'Read');
    Benchmark_Rate__c saved;
    System.runAs(pricing) {
      saved = RfpBidController.saveBid(bidJson);
    }
    Test.stopTest();
    System.assertEquals(carrierId, saved.Carrier__c);
    System.assertEquals(
      'Hidden Carrier',
      saved.Carrier_Display__c,
      'with Read on the carrier account the same save succeeds and shows its name'
    );
    System.assertEquals(
      1,
      [SELECT COUNT() FROM Benchmark_Rate__c WHERE RFP_Lane__c = :laneId]
    );
  }

  /**
   * Only a changed carrier is checked: a colleague who cannot read the account on the admin's bid
   * still edits its rate, whether the carrier is left out of the post or resent unchanged (the
   * bid form resends it with every edit).
   */
  @IsTest
  static void aColleagueEditsTheRateOfABidWhoseCarrierTheyCannotRead() {
    Fx f = fx();
    User pricing = RfpTestDataFactory.restrictedUser('RFP_Tool_User');
    if (pricing == null) {
      System.assert(
        true,
        'no usable profile in this org; runAs coverage skipped (ledgered)'
      );
      return;
    }
    RfpTestDataFactory.shareAccount(f.g.customer, pricing, 'Read');
    Id carrierId = RfpTestDataFactory.hiddenCarrier().Id;
    if (!RfpTestDataFactory.hiddenFrom(pricing, carrierId)) {
      System.assert(
        true,
        'this org shares the hidden carrier ' +
          RfpTestDataFactory.sharingInputs(carrierId) +
          '; carrier check coverage skipped (ledgered, R68)'
      );
      return;
    }
    Benchmark_Rate__c posted = RfpTestDataFactory.buildBid(f.lane, 900);
    posted.Carrier__c = carrierId;
    posted.Carrier_Name__c = null;
    Id bidId = BenchmarkRateService.save(posted).Id;
    Id laneId = f.lane.Id;
    Test.startTest();
    Benchmark_Rate__c edited;
    Benchmark_Rate__c resent;
    System.runAs(pricing) {
      edited = RfpBidController.saveBid('{"Id":"' + bidId + '","Rate__c":925}');
      resent = RfpBidController.saveBid(
        '{"RFP_Lane__c":"' +
          laneId +
          '","Carrier__c":"' +
          carrierId +
          '","Carrier_Name__c":null,"Rate__c":930,"CurrencyIsoCode":"CAD","Id":"' +
          bidId +
          '"}'
      );
    }
    Test.stopTest();
    System.assertEquals(925, edited.Rate__c, 'the rate-only edit saves');
    System.assertEquals(
      930,
      resent.Rate__c,
      'an edit resending the unchanged carrier saves'
    );
    Benchmark_Rate__c stored = [
      SELECT Carrier__c, Rate__c
      FROM Benchmark_Rate__c
      WHERE Id = :bidId
    ];
    System.assertEquals(
      carrierId,
      stored.Carrier__c,
      'the carrier is unchanged'
    );
    System.assertEquals(930, stored.Rate__c);
  }

  /**
   * The update path of the carrier check (R66): a colleague editing the admin's bid cannot switch it
   * to a carrier account they cannot read. The stored carrier is the graph's vendor, which every
   * internal user can read in this org; only the posted, changed carrier is checked, and refused.
   */
  @IsTest
  static void aColleagueCannotSwitchABidToACarrierTheyCannotRead() {
    Fx f = fx();
    User pricing = RfpTestDataFactory.restrictedUser('RFP_Tool_User');
    if (pricing == null) {
      System.assert(
        true,
        'no usable profile in this org; runAs coverage skipped (ledgered)'
      );
      return;
    }
    RfpTestDataFactory.shareAccount(f.g.customer, pricing, 'Read');
    Id carrierId = RfpTestDataFactory.hiddenCarrier().Id;
    if (!RfpTestDataFactory.hiddenFrom(pricing, carrierId)) {
      System.assert(
        true,
        'this org shares the hidden carrier ' +
          RfpTestDataFactory.sharingInputs(carrierId) +
          '; carrier check coverage skipped (ledgered, R68)'
      );
      return;
    }
    Id vendorId = f.g.vendor.Id;
    Benchmark_Rate__c posted = RfpTestDataFactory.buildBid(f.lane, 900);
    posted.Carrier__c = vendorId;
    posted.Carrier_Name__c = null;
    Id bidId = BenchmarkRateService.save(posted).Id;
    Id laneId = f.lane.Id;
    Test.startTest();
    System.runAs(pricing) {
      try {
        RfpBidController.saveBid(
          '{"RFP_Lane__c":"' +
            laneId +
            '","Carrier__c":"' +
            carrierId +
            '","Carrier_Name__c":null,"Rate__c":950,"CurrencyIsoCode":"CAD","Id":"' +
            bidId +
            '"}'
        );
        System.assert(false, 'expected AuraHandledException');
      } catch (AuraHandledException e) {
        System.assert(
          e.getMessage().contains('That carrier is not available.'),
          e.getMessage()
        );
      }
    }
    Test.stopTest();
    Benchmark_Rate__c stored = [
      SELECT Carrier__c, Rate__c
      FROM Benchmark_Rate__c
      WHERE Id = :bidId
    ];
    System.assertEquals(
      vendorId,
      stored.Carrier__c,
      'the stored carrier is unchanged'
    );
    System.assertEquals(900, stored.Rate__c, 'and so is the rate');
  }

  /**
   * A lane deleted outside RfpBulkService.deleteLanes leaves its bids with no lane and their project
   * (R67). A Read-shared pricer copies the pricing of a lane whose selected bid lost its lane: the
   * project grants the bid, so the target lane takes it and shows its carrier.
   */
  @IsTest
  static void aReadSharedUserCopiesPricingWhoseSelectedBidLostItsLane() {
    Fx f = fx();
    User pricing = RfpTestDataFactory.restrictedUser('RFP_Tool_User');
    if (pricing == null) {
      System.assert(
        true,
        'no usable profile in this org; runAs coverage skipped (ledgered)'
      );
      return;
    }
    RfpTestDataFactory.shareAccount(f.g.customer, pricing, 'Read');
    RFP_Project__c project = new RFP_Project__c(Id = f.lane.RFP_Project__c);
    Id sourceId = RfpTestDataFactory.createLane(project, f.laval, f.tor).Id;
    Id targetId = RfpTestDataFactory.createLane(project, f.tor, f.mtl).Id;
    Id bidId = orphanedBid(f);
    update new RFP_Lane__c(
      Id = sourceId,
      Cost__c = 900,
      Cost_Source__c = 'Bid',
      Selected_Bid__c = bidId
    );
    Test.startTest();
    RfpBulkService.Result copied;
    System.runAs(pricing) {
      copied = RfpBulkController.copyPricing(
        sourceId,
        new List<Id>{ targetId }
      );
    }
    Test.stopTest();
    System.assertEquals(1, copied.updated, String.join(copied.errors, '; '));
    System.assertEquals(
      bidId,
      [SELECT Selected_Bid__c FROM RFP_Lane__c WHERE Id = :targetId]
      .Selected_Bid__c,
      'the target lane takes the bid whose lane is gone'
    );
    System.assertEquals(
      'Bid Carrier',
      copied.lanes[0].Selected_Bid__r?.Carrier_Display__c,
      'and shows its carrier to the pricer'
    );
  }

  /**
   * The project grant adds no access (R67): a stranger who can read a lane of another customer is
   * refused a bid whose lane is gone when they cannot read that bid's project.
   */
  @IsTest
  static void aStrangerCannotNameABidWhoseLaneIsGone() {
    Fx f = fx();
    User stranger = RfpTestDataFactory.restrictedUser(
      new List<String>{ 'RFP_Tool_User', 'Lane_Benchmark_User' }
    );
    if (stranger == null) {
      System.assert(
        true,
        'no usable profile in this org; runAs coverage skipped (ledgered)'
      );
      return;
    }
    Id bidId = orphanedBid(f);
    Account second = RfpTestDataFactory.secondCustomer();
    Id readableId = RfpTestDataFactory.createLane(
        RfpTestDataFactory.createProject(second),
        f.laval,
        f.tor
      )
      .Id;
    RfpTestDataFactory.shareAccount(second, stranger, 'Read');
    Test.startTest();
    System.runAs(stranger) {
      System.assertEquals(
        1,
        [SELECT COUNT() FROM RFP_Lane__c WHERE Id = :readableId WITH USER_MODE],
        'the stranger can read the lane they price'
      );
      try {
        RfpLaneController.saveLanePricing(
          JSON.serialize(
            new RFP_Lane__c(
              Id = readableId,
              Cost__c = 900,
              Cost_Source__c = 'Bid',
              Selected_Bid__c = bidId,
              Margin__c = 15,
              Sell__c = 1058.82,
              Sell_Source__c = 'Margin'
            )
          )
        );
        System.assert(false, 'expected AuraHandledException');
      } catch (AuraHandledException e) {
        System.assert(
          e.getMessage().contains('That bid is not available.'),
          e.getMessage()
        );
      }
    }
    Test.stopTest();
    System.assertEquals(
      null,
      [SELECT Selected_Bid__c FROM RFP_Lane__c WHERE Id = :readableId]
      .Selected_Bid__c,
      'the readable lane did not take the bid'
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
