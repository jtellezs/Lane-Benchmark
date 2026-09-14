@IsTest
private class BenchmarkRateServiceTest {
  private class Fx {
    PricingTestDataFactory.Graph g;
    Pricing_Place__c mtl;
    Pricing_Place__c tor;
    RFP_Project__c project;
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
    return f;
  }

  @IsTest
  static void saveCopiesLaneKeysFromThePlaces() {
    Fx f = fx();
    Test.startTest();
    Benchmark_Rate__c saved = BenchmarkRateService.save(
      RfpTestDataFactory.buildBid(f.lane, 1500)
    );
    Test.stopTest();
    Benchmark_Rate__c b = [
      SELECT
        RFP_Project__c,
        City_Lane__c,
        State_Lane__c,
        Zip3_Lane__c,
        Origin_City__c,
        Origin_Province__c,
        Origin_Country__c,
        Origin_Place__c,
        Origin_Geolocation__Latitude__s,
        Destination_Geolocation__Longitude__s,
        Mode__c,
        Equipment_Category__c,
        Equipment_Type__c,
        Valid_From__c,
        Expires_On__c,
        Carrier_Display__c,
        Status__c
      FROM Benchmark_Rate__c
      WHERE Id = :saved.Id
    ];
    System.assertEquals(f.project.Id, b.RFP_Project__c);
    System.assertEquals('Montréal, QC:Toronto, ON', b.City_Lane__c);
    System.assertEquals('QC:ON', b.State_Lane__c);
    System.assertEquals('H1A:M5V', b.Zip3_Lane__c);
    System.assertEquals('Montréal', b.Origin_City__c);
    System.assertEquals(f.mtl.Id, b.Origin_Place__c);
    System.assertEquals(45.5019, b.Origin_Geolocation__Latitude__s);
    System.assertEquals(-79.3832, b.Destination_Geolocation__Longitude__s);
    System.assertEquals('Truckload', b.Mode__c);
    System.assertEquals('Van', b.Equipment_Category__c);
    System.assertEquals('Bid Carrier', b.Carrier_Display__c);
    System.assertEquals('Active', b.Status__c);
  }

  @IsTest
  static void saveDefaultsDatesAndUpdatesInPlace() {
    Fx f = fx();
    Benchmark_Rate__c bid = RfpTestDataFactory.buildBid(f.lane, 1500);
    bid.Valid_From__c = null;
    bid.Expires_On__c = null;
    Benchmark_Rate__c saved = BenchmarkRateService.save(bid);
    System.assertEquals(Date.today(), saved.Valid_From__c);
    System.assertEquals(Date.today().addDays(30), saved.Expires_On__c);
    saved.Rate__c = 1600;
    Benchmark_Rate__c again = BenchmarkRateService.save(saved);
    System.assertEquals(saved.Id, again.Id);
    System.assertEquals(
      1600,
      [SELECT Rate__c FROM Benchmark_Rate__c WHERE Id = :saved.Id].Rate__c
    );
    System.assertEquals(1, [SELECT COUNT() FROM Benchmark_Rate__c]);
  }

  @IsTest
  static void saveRejectsMissingRateAndMissingCarrier() {
    Fx f = fx();
    Benchmark_Rate__c noRate = RfpTestDataFactory.buildBid(f.lane, null);
    try {
      BenchmarkRateService.save(noRate);
      System.assert(false, 'expected an exception');
    } catch (LaneSearchException e) {
      System.assert(e.getMessage().contains('rate'), e.getMessage());
    }
    Benchmark_Rate__c noCarrier = RfpTestDataFactory.buildBid(f.lane, 900);
    noCarrier.Carrier_Name__c = null;
    try {
      BenchmarkRateService.save(noCarrier);
      System.assert(false, 'expected the validation rule');
    } catch (DmlException e) {
      System.assert(e.getMessage().contains('carrier'), e.getMessage());
    }
  }

  @IsTest
  static void plainInsertIsStampedByTheTrigger() {
    Fx f = fx();
    Benchmark_Rate__c bid = RfpTestDataFactory.buildBid(f.lane, 1000);
    Test.startTest();
    insert bid;
    Test.stopTest();
    Benchmark_Rate__c b = [
      SELECT
        RFP_Project__c,
        City_Lane__c,
        State_Lane__c,
        Zip3_Lane__c,
        Origin_Place__c,
        Origin_Geolocation__Latitude__s,
        Destination_Geolocation__Longitude__s,
        Valid_From__c,
        Expires_On__c
      FROM Benchmark_Rate__c
      WHERE Id = :bid.Id
    ];
    System.assertEquals(f.project.Id, b.RFP_Project__c);
    System.assertEquals('Montréal, QC:Toronto, ON', b.City_Lane__c);
    System.assertEquals('QC:ON', b.State_Lane__c);
    System.assertEquals('H1A:M5V', b.Zip3_Lane__c);
    System.assertEquals(f.mtl.Id, b.Origin_Place__c);
    System.assertEquals(45.5019, b.Origin_Geolocation__Latitude__s);
    System.assertEquals(-79.3832, b.Destination_Geolocation__Longitude__s);
    System.assertEquals(Date.today(), b.Valid_From__c);
    System.assertEquals(Date.today().addDays(30), b.Expires_On__c);
  }

  @IsTest
  static void bulkInsertStampsEveryBidWithOneLaneQuery() {
    Fx f = fx();
    List<Benchmark_Rate__c> bids = new List<Benchmark_Rate__c>();
    for (Integer i = 0; i < 200; i++) {
      bids.add(RfpTestDataFactory.buildBid(f.lane, 1000 + i));
    }
    Test.startTest();
    Integer before = Limits.getQueries();
    insert bids;
    Integer after = Limits.getQueries();
    Test.stopTest();
    System.assert(
      after - before <= 3,
      'expected the trigger to run one lane query for the whole batch, used ' +
      (after - before)
    );
    System.assertEquals(
      200,
      [
        SELECT COUNT()
        FROM Benchmark_Rate__c
        WHERE City_Lane__c = 'Montréal, QC:Toronto, ON'
      ]
    );
  }

  @IsTest
  static void updateKeepsAManuallyChangedEquipmentTypeAndStillFixesKeys() {
    Fx f = fx();
    Benchmark_Rate__c bid = RfpTestDataFactory.buildBid(f.lane, 1000);
    insert bid;
    Benchmark_Rate__c toUpdate = [
      SELECT Id, Equipment_Type__c
      FROM Benchmark_Rate__c
      WHERE Id = :bid.Id
    ];
    toUpdate.Equipment_Type__c = 'Reefer 53\'';
    Test.startTest();
    update toUpdate;
    Test.stopTest();
    Benchmark_Rate__c b = [
      SELECT Equipment_Type__c, City_Lane__c, State_Lane__c, Zip3_Lane__c
      FROM Benchmark_Rate__c
      WHERE Id = :bid.Id
    ];
    System.assertEquals('Reefer 53\'', b.Equipment_Type__c);
    System.assertEquals('Montréal, QC:Toronto, ON', b.City_Lane__c);
    System.assertEquals('QC:ON', b.State_Lane__c);
    System.assertEquals('H1A:M5V', b.Zip3_Lane__c);
  }

  @IsTest
  static void saveUpdateStripsServiceMaintainedFields() {
    Fx f = fx();
    Benchmark_Rate__c saved = BenchmarkRateService.save(
      RfpTestDataFactory.buildBid(f.lane, 1500)
    );
    // A queried record carries City_Lane__c etc.; passing it back must not fail or rewrite them.
    Benchmark_Rate__c queried = [
      SELECT Id, Rate__c, City_Lane__c, State_Lane__c, Zip3_Lane__c
      FROM Benchmark_Rate__c
      WHERE Id = :saved.Id
    ];
    queried.Rate__c = 1600;
    Benchmark_Rate__c again = BenchmarkRateService.save(queried);
    System.assertEquals(1600, again.Rate__c);
    System.assertEquals(
      'Montréal, QC:Toronto, ON',
      again.City_Lane__c,
      'keys re-stamped by the trigger, not by save'
    );
  }

  /**
   * R67 grants a bid whose lane is gone through its RFP_Project__c, which adds no access only while
   * that project is service-maintained: BenchmarkRateTrigger stamps it from the lane in system
   * context and RFP_Tool_User cannot write it. A pricer who owns a bid and can read another project
   * edits the bid in user mode, as the record page or the API does: clearing its lane while pointing
   * it at that project leaves the bid on the project its lane had, and a bid inserted without a
   * lane cannot name a project either. Asserted on the stored rows, so a refused write and a
   * stripped field both pass, and a written project fails.
   */
  @IsTest
  static void aPricerCannotPointABidAtAnotherProject() {
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
    RFP_Project__c other = RfpTestDataFactory.createProject(f.g.customer);
    List<String> refusals = new List<String>();
    Id bidId;
    Test.startTest();
    System.runAs(pricing) {
      System.assertEquals(
        1,
        [
          SELECT COUNT()
          FROM RFP_Project__c
          WHERE Id = :other.Id
          WITH USER_MODE
        ],
        'the pricer can read the other project, so no sharing check refuses the lookup'
      );
      bidId = BenchmarkRateService.save(
          RfpTestDataFactory.buildBid(f.lane, 900)
        )
        .Id;
      Database.update(
        new Benchmark_Rate__c(Id = bidId, Rate__c = 950),
        AccessLevel.USER_MODE
      );
      try {
        Database.update(
          new Benchmark_Rate__c(
            Id = bidId,
            RFP_Lane__c = null,
            RFP_Project__c = other.Id
          ),
          AccessLevel.USER_MODE
        );
      } catch (DmlException e) {
        refusals.add(e.getMessage());
      }
      try {
        Database.insert(
          new Benchmark_Rate__c(
            RFP_Project__c = other.Id,
            Carrier_Name__c = 'Laneless Carrier',
            Rate__c = 1,
            CurrencyIsoCode = 'CAD'
          ),
          AccessLevel.USER_MODE
        );
      } catch (DmlException e) {
        refusals.add(e.getMessage());
      }
    }
    Test.stopTest();
    Benchmark_Rate__c stored = [
      SELECT RFP_Project__c, Rate__c
      FROM Benchmark_Rate__c
      WHERE Id = :bidId
    ];
    System.assertEquals(
      950,
      stored.Rate__c,
      'the pricer can edit the bid in user mode'
    );
    System.assertEquals(
      f.project.Id,
      stored.RFP_Project__c,
      'the bid keeps the project its lane had; refusals: ' +
      String.join(refusals, ' | ')
    );
    System.assertEquals(
      0,
      [SELECT COUNT() FROM Benchmark_Rate__c WHERE RFP_Project__c = :other.Id],
      'no bid was pointed at or created on the other project'
    );
  }

  @IsTest
  static void saveAllInsertsEveryBidWithItsLaneKeys() {
    Fx f = fx();
    RFP_Lane__c a = f.lane;
    RFP_Lane__c b = RfpTestDataFactory.createLane(f.project, f.mtl, f.tor);
    List<Benchmark_Rate__c> saved = BenchmarkRateService.saveAll(
      new List<Benchmark_Rate__c>{
        RfpTestDataFactory.buildBid(a, 1000),
        RfpTestDataFactory.buildBid(b, 1100),
        RfpTestDataFactory.buildBid(a, 1200)
      }
    );
    System.assertEquals(3, saved.size());
    System.assertEquals(1000, saved[0].Rate__c, 'input order kept');
    System.assertEquals(1200, saved[2].Rate__c);
    System.assertEquals(a.Id, saved[2].RFP_Lane__c);
    System.assertEquals(
      'Montréal, QC:Toronto, ON',
      saved[1].City_Lane__c,
      'trigger stamped'
    );
    try {
      BenchmarkRateService.saveAll(
        new List<Benchmark_Rate__c>{ new Benchmark_Rate__c(RFP_Lane__c = a.Id) }
      );
      System.assert(false, 'expected an exception');
    } catch (LaneSearchException e) {
      System.assert(e.getMessage().contains('rate'), e.getMessage());
    }
  }

  @IsTest
  static void laneKeyHelpersMatchTheLoadFormat() {
    Pricing_Place__c o = new Pricing_Place__c(
      City__c = 'Laval',
      Province__c = 'QC',
      Postal_Prefix__c = 'H7P'
    );
    Pricing_Place__c d = new Pricing_Place__c(
      City__c = 'Oshawa',
      Province__c = 'ON',
      Postal_Prefix__c = 'L1J'
    );
    System.assertEquals(
      'Laval, QC:Oshawa, ON',
      BenchmarkRateService.cityLane(o, d)
    );
    System.assertEquals('QC:ON', BenchmarkRateService.stateLane(o, d));
    System.assertEquals('H7P:L1J', BenchmarkRateService.zip3Lane(o, d));
  }
}
