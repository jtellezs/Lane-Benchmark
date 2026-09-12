@IsTest
private class RfpBulkServiceTest {
  private class Fx {
    RFP_Project__c p;
    RFP_Lane__c a;
    RFP_Lane__c b;
    RFP_Lane__c c;
  }

  /** Three Montréal→Toronto lanes: a (median 2000, uncosted), b (median 2500, manual cost 1800), c (no median). */
  private static Fx fx() {
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
    Fx f = new Fx();
    f.p = RfpTestDataFactory.createProject(g.customer);
    f.a = RfpTestDataFactory.createLane(f.p, mtl, tor);
    f.b = RfpTestDataFactory.createLane(f.p, mtl, tor);
    f.c = RfpTestDataFactory.createLane(f.p, mtl, tor);
    update new List<RFP_Lane__c>{
      new RFP_Lane__c(
        Id = f.a.Id,
        Hist_Median__c = 2000,
        Hist_Status__c = 'Done'
      ),
      new RFP_Lane__c(
        Id = f.b.Id,
        Hist_Median__c = 2500,
        Hist_Status__c = 'Done',
        Cost__c = 1800,
        Cost_Source__c = 'Manual',
        Sell__c = 2070
      )
    };
    return f;
  }

  private static RFP_Lane__c fetch(Id laneId) {
    return [
      SELECT
        Cost__c,
        Cost_Source__c,
        Selected_Bid__c,
        Margin__c,
        Sell__c,
        Sell_Source__c
      FROM RFP_Lane__c
      WHERE Id = :laneId
    ];
  }

  @IsTest
  static void applyMedianSkipsCostedLanesUnlessOverwrite() {
    Fx f = fx();
    List<Id> ids = new List<Id>{ f.a.Id, f.b.Id, f.c.Id };
    RfpBulkService.Result r = RfpBulkService.applyMedian(ids, false);
    System.assertEquals(1, r.updated);
    System.assertEquals(2, r.skipped);
    System.assert(r.skippedIds.contains(f.b.Id), 'costed manually');
    System.assert(r.skippedIds.contains(f.c.Id), 'no median');
    System.assertEquals(3, r.lanes.size(), 'refreshed lanes come back');
    RFP_Lane__c a = fetch(f.a.Id);
    System.assertEquals(2000, a.Cost__c);
    System.assertEquals('History median', a.Cost_Source__c);
    System.assertEquals(2300.00, a.Sell__c, 'lane margin 15 applied');
    System.assertEquals('Margin', a.Sell_Source__c);
    System.assertEquals(1800, fetch(f.b.Id).Cost__c, 'untouched');

    r = RfpBulkService.applyMedian(new List<Id>{ f.b.Id }, true);
    System.assertEquals(1, r.updated);
    System.assertEquals(2500, fetch(f.b.Id).Cost__c);
  }

  @IsTest
  static void applyMedianDropsTheSelectedBid() {
    Fx f = fx();
    Benchmark_Rate__c bid = BenchmarkRateService.save(
      RfpTestDataFactory.buildBid(f.a, 1000)
    );
    update new RFP_Lane__c(
      Id = f.a.Id,
      Cost__c = 1000,
      Cost_Source__c = 'Bid',
      Selected_Bid__c = bid.Id
    );
    RfpBulkService.Result r = RfpBulkService.applyMedian(
      new List<Id>{ f.a.Id },
      true
    );
    System.assertEquals(1, r.updated);
    RFP_Lane__c a = fetch(f.a.Id);
    System.assertEquals(2000, a.Cost__c);
    System.assertEquals('History median', a.Cost_Source__c);
    System.assertEquals(
      null,
      a.Selected_Bid__c,
      'the bid link goes with the bid cost'
    );
  }

  /** deleteLanes collects two DML passes: the cap and the tail must count both, not each pass. */
  @IsTest
  static void failuresAreCountedAcrossEveryDmlPass() {
    Fx f = fx();
    RfpBulkService.Context c = new RfpBulkService.Context();
    for (Integer i = 0; i < 7; i++) {
      c.noteFailure(f.a.Id, 'bid ' + i + ' could not be deleted');
    }
    for (Integer i = 0; i < 3; i++) {
      c.noteFailure(f.b.Id, 'lane ' + i + ' could not be deleted');
    }
    c.finish();
    c.finish();
    System.assertEquals(10, c.failedTotal);
    System.assertEquals(6, c.result.errors.size(), '5 listed and one tail');
    System.assertEquals(
      f.a.Id + ': bid 0 could not be deleted',
      c.result.errors[0]
    );
    System.assertEquals('… and 5 more', c.result.errors[5]);
  }

  @IsTest
  static void applyPricingCostMarginAndSell() {
    Fx f = fx();
    List<Id> ids = new List<Id>{ f.a.Id, f.c.Id };
    RfpBulkService.applyPricing(ids, 1000, null, null);
    RFP_Lane__c a = fetch(f.a.Id);
    System.assertEquals(1000, a.Cost__c);
    System.assertEquals('Manual', a.Cost_Source__c);
    System.assertEquals(1150.00, a.Sell__c);

    RfpBulkService.applyPricing(ids, null, null, 20);
    a = fetch(f.a.Id);
    System.assertEquals(20, a.Margin__c);
    System.assertEquals(1200.00, a.Sell__c);
    System.assertEquals('Margin', a.Sell_Source__c);

    RfpBulkService.applyPricing(ids, null, 1500, null);
    a = fetch(f.a.Id);
    System.assertEquals(1500, a.Sell__c);
    System.assertEquals('Manual', a.Sell_Source__c);
    System.assertEquals(50.00, a.Margin__c, 'margin follows the typed sell');

    RfpBulkService.applyPricing(ids, 2000, null, null);
    a = fetch(f.a.Id);
    System.assertEquals(
      1500,
      a.Sell__c,
      'a manual sell survives a cost change'
    );
    System.assertEquals(-25.00, a.Margin__c);
  }

  @IsTest
  static void applyPricingValidates() {
    Fx f = fx();
    List<Id> ids = new List<Id>{ f.a.Id };
    assertRefused(ids, null, null, null, 'cost');
    assertRefused(ids, null, 100, 10, 'not both');
    assertRefused(ids, 0, null, null, 'zero');
    assertRefused(ids, null, null, 101, '100');
    List<Id> many = new List<Id>();
    for (Integer i = 0; i < 201; i++) {
      many.add(f.a.Id);
    }
    assertRefused(many, 100, null, null, '200');
    System.assertEquals(
      null,
      fetch(f.a.Id).Cost__c,
      'a refused call writes nothing'
    );
  }

  private static void assertRefused(
    List<Id> ids,
    Decimal cost,
    Decimal sell,
    Decimal margin,
    String fragment
  ) {
    try {
      RfpBulkService.applyPricing(ids, cost, sell, margin);
      System.assert(false, 'expected a refusal for ' + fragment);
    } catch (LaneSearchException e) {
      System.assert(
        e.getMessage().containsIgnoreCase(fragment),
        e.getMessage()
      );
    }
  }

  @IsTest
  static void copyPricingCopiesTheSixPricingFields() {
    Fx f = fx();
    Benchmark_Rate__c bid = BenchmarkRateService.save(
      RfpTestDataFactory.buildBid(f.a, 1700)
    );
    update new RFP_Lane__c(
      Id = f.a.Id,
      Cost__c = 1700,
      Cost_Source__c = 'Bid',
      Selected_Bid__c = bid.Id,
      Margin__c = 10,
      Sell__c = 1870,
      Sell_Source__c = 'Margin'
    );
    RfpBulkService.Result r = RfpBulkService.copyPricing(
      f.a.Id,
      new List<Id>{ f.c.Id, f.a.Id }
    );
    System.assertEquals(1, r.updated, 'the source itself is not a target');
    RFP_Lane__c c = fetch(f.c.Id);
    System.assertEquals(1700, c.Cost__c);
    System.assertEquals('Bid', c.Cost_Source__c);
    System.assertEquals(bid.Id, c.Selected_Bid__c);
    System.assertEquals(10, c.Margin__c);
    System.assertEquals(1870, c.Sell__c);
    System.assertEquals('Margin', c.Sell_Source__c);
    update new RFP_Lane__c(Id = f.c.Id, Cost__c = null);
    try {
      RfpBulkService.copyPricing(f.c.Id, new List<Id>{ f.a.Id });
      System.assert(false, 'expected a refusal');
    } catch (LaneSearchException e) {
      System.assert(e.getMessage().contains('no cost'), e.getMessage());
    }
  }

  @IsTest
  static void deleteLanesTakesTheirBids() {
    Fx f = fx();
    BenchmarkRateService.save(RfpTestDataFactory.buildBid(f.a, 900));
    BenchmarkRateService.save(RfpTestDataFactory.buildBid(f.b, 950));
    RfpBulkService.Result r = RfpBulkService.deleteLanes(
      new List<Id>{ f.a.Id }
    );
    System.assertEquals(1, r.updated);
    System.assertEquals(0, r.lanes.size(), 'nothing left of the ids given');
    System.assertEquals(
      0,
      [SELECT COUNT() FROM Benchmark_Rate__c WHERE RFP_Lane__c = :f.a.Id]
    );
    System.assertEquals(
      1,
      [SELECT COUNT() FROM Benchmark_Rate__c WHERE RFP_Lane__c = :f.b.Id],
      'other lanes keep theirs'
    );
    System.assertEquals(
      2,
      [SELECT COUNT() FROM RFP_Lane__c WHERE RFP_Project__c = :f.p.Id]
    );
  }
}
