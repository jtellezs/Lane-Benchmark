/**
 * Phase 9. The tests that matter here are the three that prove a market-test rate cannot be
 * confused with a bid somebody was never meant to see: an orphaned RFP bid (no project, no lane,
 * because deleting a customer account clears both) is never listed, never updatable and never
 * deletable through this service.
 */
@IsTest
private class MarketTestServiceTest {
  private static Pricing_Place__c origin;
  private static Pricing_Place__c destination;

  private static void lane() {
    origin = RfpTestDataFactory.createPlace(
      'Toronto',
      'ON',
      'CA',
      43.65,
      -79.38,
      'M5V'
    );
    destination = RfpTestDataFactory.createPlace(
      'Montreal',
      'QC',
      'CA',
      45.5,
      -73.57,
      'H3B'
    );
  }

  private static Benchmark_Rate__c posted(Decimal rate) {
    return new Benchmark_Rate__c(
      Carrier_Name__c = 'Ad Hoc Carrier',
      Rate__c = rate,
      CurrencyIsoCode = 'CAD'
    );
  }

  /** A bid whose customer account was deleted: both lookups cleared, so it looks like a rate. */
  private static Benchmark_Rate__c orphan() {
    Benchmark_Rate__c o = new Benchmark_Rate__c(
      Carrier_Name__c = 'Deleted Customer Carrier',
      Rate__c = 9999,
      CurrencyIsoCode = 'CAD',
      City_Lane__c = BenchmarkRateService.cityLane(origin, destination)
    );
    insert o;
    return o;
  }

  @IsTest
  static void aSavedRateCarriesTheMarkerTheLaneKeysAndNoRfpLinks() {
    lane();
    Test.startTest();
    Benchmark_Rate__c saved = MarketTestService.save(
      posted(2500),
      origin.Key__c,
      destination.Key__c
    );
    Test.stopTest();
    Benchmark_Rate__c stored = [
      SELECT
        Market_Test__c,
        City_Lane__c,
        State_Lane__c,
        Zip3_Lane__c,
        RFP_Lane__c,
        RFP_Project__c,
        Rate__c
      FROM Benchmark_Rate__c
      WHERE Id = :saved.Id
    ];
    System.assertEquals(
      true,
      stored.Market_Test__c,
      'the marker, not the absent lookups, is what identifies a market-test rate'
    );
    System.assertEquals(
      BenchmarkRateService.cityLane(origin, destination),
      stored.City_Lane__c,
      'without the lane keys no lane search would match it and it would never reach the median'
    );
    System.assertEquals(
      BenchmarkRateService.stateLane(origin, destination),
      stored.State_Lane__c
    );
    System.assertEquals(null, stored.RFP_Lane__c);
    System.assertEquals(null, stored.RFP_Project__c);
    System.assertEquals(2500, stored.Rate__c);
  }

  @IsTest
  static void ratesOfLaneNeverListsAnOrphanedBid() {
    lane();
    Benchmark_Rate__c mine = MarketTestService.save(
      posted(2500),
      origin.Key__c,
      destination.Key__c
    );
    Benchmark_Rate__c hidden = orphan();
    Test.startTest();
    List<Benchmark_Rate__c> rates = MarketTestService.ratesOfLane(
      origin.Key__c,
      destination.Key__c
    );
    Test.stopTest();
    System.assertEquals(
      1,
      rates.size(),
      'the orphan shares the lane and both null lookups: only the marker keeps it out'
    );
    System.assertEquals(mine.Id, rates[0].Id);
    System.assertNotEquals(hidden.Id, rates[0].Id);
  }

  @IsTest
  static void ratesOfLaneShowsARateAnotherUserRecorded() {
    lane();
    User other = RfpTestDataFactory.restrictedUser('RFP_Tool_User');
    if (other == null) {
      return;
    }
    Benchmark_Rate__c theirs;
    System.runAs(other) {
      theirs = MarketTestService.save(
        posted(2100),
        origin.Key__c,
        destination.Key__c
      );
    }
    Test.startTest();
    List<Benchmark_Rate__c> rates = MarketTestService.ratesOfLane(
      origin.Key__c,
      destination.Key__c
    );
    Test.stopTest();
    System.assertEquals(
      1,
      rates.size(),
      'a lane\'s market-test rates are shared knowledge, like the median already is'
    );
    System.assertEquals(theirs.Id, rates[0].Id);
  }

  @IsTest
  static void updateRefusesARateTheRunningUserDoesNotOwn() {
    lane();
    User other = RfpTestDataFactory.restrictedUser('RFP_Tool_User');
    if (other == null) {
      return;
    }
    Benchmark_Rate__c theirs;
    System.runAs(other) {
      theirs = MarketTestService.save(
        posted(2100),
        origin.Key__c,
        destination.Key__c
      );
    }
    String message = '';
    Test.startTest();
    try {
      MarketTestService.updateRate(
        new Benchmark_Rate__c(Id = theirs.Id, Rate__c = 1)
      );
    } catch (LaneSearchException e) {
      message = e.getMessage();
    }
    Test.stopTest();
    System.assertEquals(MarketTestService.NOT_YOURS, message);
    System.assertEquals(
      2100,
      [SELECT Rate__c FROM Benchmark_Rate__c WHERE Id = :theirs.Id].Rate__c,
      'the refused update changed nothing'
    );
  }

  @IsTest
  static void updateRefusesARecordWithoutTheMarker() {
    lane();
    Benchmark_Rate__c hidden = orphan();
    String message = '';
    Test.startTest();
    try {
      MarketTestService.updateRate(
        new Benchmark_Rate__c(Id = hidden.Id, Rate__c = 1)
      );
    } catch (LaneSearchException e) {
      message = e.getMessage();
    }
    Test.stopTest();
    System.assertEquals(
      MarketTestService.NOT_YOURS,
      message,
      'an orphaned bid is owned by the running user here and still refused: the marker decides'
    );
  }

  @IsTest
  static void deleteRefusesABidThatCarriesAnRfpLane() {
    lane();
    // Mirrors PricingTestDataFactory's customer: this org validates the billing address and
    // its state against the country picklist, so a bare Account insert is rejected.
    Account customer = new Account(
      Name = 'Market Test Customer',
      RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
        .get('Customer')
        ?.getRecordTypeId(),
      rtms__TMS_Type__c = 'Customer',
      Industry = 'Other',
      BillingStreet = '1 Test St',
      BillingCity = 'Montreal',
      BillingState = 'Quebec',
      BillingPostalCode = 'H1A 1A1',
      BillingCountry = 'Canada',
      CurrencyIsoCode = 'CAD'
    );
    insert customer;
    RFP_Project__c project = RfpTestDataFactory.createProject(customer);
    RFP_Lane__c rfpLane = RfpTestDataFactory.createLane(
      project,
      origin,
      destination
    );
    Benchmark_Rate__c bid = RfpTestDataFactory.buildBid(rfpLane, 3300);
    insert bid;
    String message = '';
    Test.startTest();
    try {
      MarketTestService.deleteRate(bid.Id);
    } catch (LaneSearchException e) {
      message = e.getMessage();
    }
    Test.stopTest();
    System.assertEquals(MarketTestService.NOT_YOURS, message);
    System.assertEquals(
      1,
      [SELECT COUNT() FROM Benchmark_Rate__c WHERE Id = :bid.Id],
      'an RFP bid is never deleted through the market test page'
    );
  }

  @IsTest
  static void bothEndsAreRequired() {
    lane();
    String message = '';
    Test.startTest();
    try {
      MarketTestService.ratesOfLane(origin.Key__c, null);
    } catch (LaneSearchException e) {
      message = e.getMessage();
    }
    Test.stopTest();
    System.assertEquals(MarketTestService.NO_PLACES, message);
  }
}
