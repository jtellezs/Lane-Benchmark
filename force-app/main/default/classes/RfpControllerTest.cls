@IsTest
private class RfpControllerTest {
  @IsTest
  static void projectsForAccountSummarisesLanesBidsAndFiles() {
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
    lane.Cost__c = 1000;
    lane.Sell__c = 1150;
    update lane;
    RfpTestDataFactory.createLane(p, tor, mtl);
    BenchmarkRateService.save(RfpTestDataFactory.buildBid(lane, 1000));
    ContentVersion cv = new ContentVersion(
      Title = 'lanes.xlsx',
      PathOnClient = 'lanes.xlsx',
      VersionData = Blob.valueOf('x')
    );
    insert cv;
    Id docId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id]
    .ContentDocumentId;
    insert new ContentDocumentLink(
      ContentDocumentId = docId,
      LinkedEntityId = p.Id,
      ShareType = 'V'
    );

    Test.startTest();
    List<RfpController.ProjectSummary> out = RfpController.projectsForAccount(
      g.customer.Id
    );
    Test.stopTest();

    System.assertEquals(1, out.size());
    System.assertEquals('Test RFP', out[0].name);
    System.assertEquals('Draft', out[0].status);
    System.assertEquals(2, out[0].laneCount);
    System.assertEquals(1, out[0].costedCount);
    System.assertEquals(1, out[0].soldCount);
    System.assertEquals(1, out[0].bidCount);
    System.assertEquals(new List<String>{ 'lanes.xlsx' }, out[0].fileNames);
    System.assertEquals(
      0,
      RfpController.projectsForAccount(g.vendor.Id).size()
    );
  }
}
