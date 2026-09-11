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
