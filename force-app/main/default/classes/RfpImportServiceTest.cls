@IsTest
private class RfpImportServiceTest {
  private static RfpImportService.ImportRow row(
    Integer n,
    String oCity,
    String oProv,
    String oCountry,
    String oPostal,
    String dCity,
    String dProv,
    String dCountry,
    String dPostal
  ) {
    RfpImportService.ImportRow r = new RfpImportService.ImportRow();
    r.rowNumber = n;
    r.origin = new RfpImportService.RowEnd();
    r.origin.city = oCity;
    r.origin.province = oProv;
    r.origin.country = oCountry;
    r.origin.postal = oPostal;
    r.destination = new RfpImportService.RowEnd();
    r.destination.city = dCity;
    r.destination.province = dProv;
    r.destination.country = dCountry;
    r.destination.postal = dPostal;
    r.raw = '{"Origin":"' + oCity + '"}';
    return r;
  }

  @IsTest
  static void resolvesByCityThenPostalAndFlagsTheRest() {
    PricingTestDataFactory.Graph g = PricingTestDataFactory.createGraph();
    RfpTestDataFactory.createPlace(
      'Montréal',
      'QC',
      'CA',
      45.5019,
      -73.5674,
      'H1A'
    );
    RfpTestDataFactory.createPlace(
      'Toronto',
      'ON',
      'CA',
      43.6532,
      -79.3832,
      'M5V'
    );
    Pricing_Place__c laval = RfpTestDataFactory.createPlace(
      'Laval',
      'QC',
      'CA',
      45.6066,
      -73.7124,
      'H7P'
    );
    laval.Load_Count_365d__c = 40;
    Pricing_Place__c lavalWest = RfpTestDataFactory.createPlace(
      'Laval-Ouest',
      'QC',
      'CA',
      45.55,
      -73.85,
      'H7P'
    );
    lavalWest.Load_Count_365d__c = 3;
    update new List<Pricing_Place__c>{ laval, lavalWest };
    RFP_Project__c p = RfpTestDataFactory.createProject(g.customer);
    p.CurrencyIsoCode = 'USD';
    update p;
    List<RfpImportService.ImportRow> rows = new List<RfpImportService.ImportRow>{
      row(1, 'Montreal', 'Quebec', 'Canada', null, 'TORONTO', 'ON', null, null), // city keys; blank country tries CA first
      row(2, null, null, 'CA', 'H7P 1T2', 'Toronto', 'ON', 'CA', null), // postal prefix -> Laval (highest load count)
      row(3, 'Nowhere', 'ZZ', 'CA', null, 'Toronto', 'ON', 'CA', null), // unresolved origin
      row(4, null, null, null, null, null, null, null, null) // skipped
    };
    rows[0].mode = 'Truckload';
    rows[0].quantity = 2;
    rows[0].fscIncluded = true;
    Test.startTest();
    RfpImportService.Summary s = RfpImportService.importRows(p.Id, rows);
    Test.stopTest();
    System.assertEquals(3, s.imported);
    System.assertEquals(1, s.skipped);
    System.assertEquals(1, s.unresolvedEnds);
    List<RFP_Lane__c> lanes = [
      SELECT
        Row_Number__c,
        Origin_Place__r.Key__c,
        Destination_Place__r.Key__c,
        Origin_Resolved__c,
        Destination_Resolved__c,
        Origin_City__c,
        Origin_Province__c,
        Origin_Country__c,
        Hist_Status__c,
        Margin__c,
        CurrencyIsoCode,
        Mode__c,
        Quantity__c,
        Customer_FSC_Included__c,
        Raw_Row__c
      FROM RFP_Lane__c
      WHERE RFP_Project__c = :p.Id
      ORDER BY Row_Number__c
    ];
    System.assertEquals('montreal|qc|ca', lanes[0].Origin_Place__r.Key__c);
    System.assertEquals('toronto|on|ca', lanes[0].Destination_Place__r.Key__c);
    System.assertEquals(
      'QC',
      lanes[0].Origin_Province__c,
      'province normalized to the code'
    );
    System.assertEquals('CA', lanes[0].Origin_Country__c);
    System.assertEquals('Pending', lanes[0].Hist_Status__c);
    System.assertEquals(15, lanes[0].Margin__c);
    System.assertEquals('USD', lanes[0].CurrencyIsoCode);
    System.assertEquals('Truckload', lanes[0].Mode__c);
    System.assertEquals(2, lanes[0].Quantity__c);
    System.assertEquals(true, lanes[0].Customer_FSC_Included__c);
    System.assert(lanes[0].Raw_Row__c.contains('Montreal'));
    System.assertEquals(
      'laval|qc|ca',
      lanes[1].Origin_Place__r.Key__c,
      'postal prefix picks the busiest place'
    );
    System.assertEquals(false, lanes[2].Origin_Resolved__c);
    System.assertEquals('Unresolved', lanes[2].Hist_Status__c);
  }

  @IsTest
  static void rejectsMoreThan200Rows() {
    PricingTestDataFactory.Graph g = PricingTestDataFactory.createGraph();
    RFP_Project__c p = RfpTestDataFactory.createProject(g.customer);
    List<RfpImportService.ImportRow> rows = new List<RfpImportService.ImportRow>();
    for (Integer i = 0; i < 201; i++) {
      rows.add(row(i + 1, 'A', 'QC', 'CA', null, 'B', 'ON', 'CA', null));
    }
    try {
      RfpImportService.importRows(p.Id, rows);
      System.assert(false, 'expected an exception');
    } catch (LaneSearchException e) {
      System.assert(e.getMessage().contains('200'), e.getMessage());
    }
  }
}
