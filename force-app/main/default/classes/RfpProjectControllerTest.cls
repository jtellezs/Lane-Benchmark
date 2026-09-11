@IsTest
private class RfpProjectControllerTest {
  @IsTest
  static void projectCrudMappingAndTypeahead() {
    PricingTestDataFactory.Graph g = PricingTestDataFactory.createGraph();
    String payload =
      '{"Name":"Q4 lanes","Customer__c":"' +
      g.customer.Id +
      '","Status__c":"Draft","Default_Margin__c":12,"CurrencyIsoCode":"CAD","Column_Mapping__c":"{\\"originCity\\":\\"From\\"}"}';
    RFP_Project__c p = RfpProjectController.saveProject(payload);
    System.assertEquals('Q4 lanes', p.Name);
    System.assertEquals(12, p.Default_Margin__c);
    p.Status__c = 'Pricing';
    RFP_Project__c again = RfpProjectController.saveProject(
      JSON.serialize(
        new Map<String, Object>{ 'Id' => p.Id, 'Status__c' => 'Pricing' }
      )
    );
    System.assertEquals('Pricing', again.Status__c);
    System.assertEquals(
      'Q4 lanes',
      again.Name,
      'partial JSON keeps other fields'
    );
    System.assertEquals(1, RfpProjectController.listProjects().size());
    System.assertEquals(
      '{"originCity":"From"}',
      RfpProjectController.columnMappingFor(g.customer.Id)
    );
    System.assertEquals(
      null,
      RfpProjectController.columnMappingFor(g.vendor.Id)
    );
    List<RfpProjectController.AccountOption> customers = RfpProjectController.searchAccounts(
      'Test Cust',
      'customer'
    );
    System.assertEquals(1, customers.size());
    System.assertEquals(g.customer.Id, customers[0].id);
    System.assertEquals(
      0,
      RfpProjectController.searchAccounts('Test Cust', 'carrier').size()
    );
    System.assertEquals(
      0,
      RfpProjectController.searchAccounts('T', 'customer').size(),
      'two characters minimum'
    );
  }

  @IsTest
  static void attachFileLinksTheDocument() {
    PricingTestDataFactory.Graph g = PricingTestDataFactory.createGraph();
    RFP_Project__c p = RfpTestDataFactory.createProject(g.customer);
    Id docId = RfpProjectController.attachFile(
      p.Id,
      'lanes.xlsx',
      EncodingUtil.base64Encode(Blob.valueOf('bytes'))
    );
    System.assertEquals(
      1,
      [
        SELECT COUNT()
        FROM ContentDocumentLink
        WHERE LinkedEntityId = :p.Id AND ContentDocumentId = :docId
      ]
    );
    System.assertEquals(
      'lanes.xlsx',
      [SELECT Source_File_Name__c FROM RFP_Project__c WHERE Id = :p.Id]
      .Source_File_Name__c
    );
    try {
      RfpProjectController.attachFile(p.Id, 'big.xlsx', 'A'.repeat(4200001));
      System.assert(false, 'expected an error');
    } catch (AuraHandledException e) {
      System.assert(e.getMessage().contains('3 MB'), e.getMessage());
    }
  }
}
