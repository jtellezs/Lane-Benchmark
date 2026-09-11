@IsTest
private class RfpTestDataFactoryTest {
  @IsTest
  static void buildersCreateAConsistentGraph() {
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
    Benchmark_Rate__c bid = RfpTestDataFactory.buildBid(lane, 1234.56);

    System.assertEquals('montreal|qc|ca', mtl.Key__c);
    System.assertEquals(
      'Draft',
      [SELECT Status__c FROM RFP_Project__c WHERE Id = :p.Id].Status__c
    );
    RFP_Lane__c saved = [
      SELECT
        Origin_City__c,
        Origin_Province__c,
        Origin_Country__c,
        Destination_City__c,
        Origin_Place__c,
        Destination_Place__c,
        Origin_Resolved__c,
        Margin__c,
        RFP_Project__c
      FROM RFP_Lane__c
      WHERE Id = :lane.Id
    ];
    System.assertEquals('Montréal', saved.Origin_City__c);
    System.assertEquals('QC', saved.Origin_Province__c);
    System.assertEquals('CA', saved.Origin_Country__c);
    System.assertEquals(tor.Id, saved.Destination_Place__c);
    System.assertEquals(true, saved.Origin_Resolved__c);
    System.assertEquals(15, saved.Margin__c);
    System.assertEquals(p.Id, saved.RFP_Project__c);
    System.assertEquals(null, bid.Id, 'buildBid does not insert');
    System.assertEquals(lane.Id, bid.RFP_Lane__c);
    System.assertEquals(Date.today().addDays(30), bid.Expires_On__c);
  }
}
