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
    System.assertEquals(0, s.failed);
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

  /**
   * Final review C1: a spreadsheet cell is as long as the customer made it, and toLane used to
   * copy it verbatim into fields narrower than the data - a 60-character mode threw
   * STRING_TOO_LONG and, with an all-or-nothing insert, took the whole 200-row chunk with it.
   * Every free-text field is now cut to its own schema length.
   */
  @IsTest
  static void cutsOverLongCellsToTheFieldLength() {
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
    RFP_Project__c p = RfpTestDataFactory.createProject(g.customer);
    String mode60 = 'M'.repeat(60);
    String category60 = 'C'.repeat(60);
    String equipment100 = 'E'.repeat(100);
    String commodity300 = 'X'.repeat(300);
    String unit30 = 'U'.repeat(30);
    String postal20 = 'H1A 1B2 EXTRA LONG!!'; // 20 characters; the field holds 12
    RfpImportService.ImportRow r = row(
      1,
      'Montreal',
      'QC',
      'CA',
      postal20,
      'Toronto',
      'ON',
      'CA',
      null
    );
    r.mode = mode60;
    r.equipmentCategory = category60;
    r.equipmentType = equipment100;
    r.commodity = commodity300;
    r.quantityUnit = unit30;
    Test.startTest();
    RfpImportService.Summary s = RfpImportService.importRows(
      p.Id,
      new List<RfpImportService.ImportRow>{ r }
    );
    Test.stopTest();
    System.assertEquals(1, s.imported, 'the over-long row still imports');
    System.assertEquals(0, s.failed);
    RFP_Lane__c lane = [
      SELECT
        Mode__c,
        Equipment_Category__c,
        Equipment_Type__c,
        Commodity__c,
        Quantity_Unit__c,
        Origin_Postal__c
      FROM RFP_Lane__c
      WHERE RFP_Project__c = :p.Id
    ];
    System.assertEquals(mode60.left(40), lane.Mode__c, 'Mode__c is Text(40)');
    System.assertEquals(40, lane.Mode__c.length());
    System.assertEquals(category60.left(40), lane.Equipment_Category__c);
    System.assertEquals(equipment100.left(80), lane.Equipment_Type__c);
    System.assertEquals(commodity300.left(255), lane.Commodity__c);
    System.assertEquals(unit30.left(20), lane.Quantity_Unit__c);
    System.assertEquals(
      postal20.left(12),
      lane.Origin_Postal__c,
      'Origin_Postal__c is Text(12)'
    );
  }

  /**
   * Final review C1, second half: the insert runs allOrNone = false, so a row the platform still
   * refuses (here Quantity__c = 10^18 against a Number(12,2) field, a per-row
   * NUMBER_OUTSIDE_VALID_RANGE) is counted into Summary.failed while its neighbours land.
   */
  @IsTest
  static void countsARefusedRowAndKeepsTheRest() {
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
    RFP_Project__c p = RfpTestDataFactory.createProject(g.customer);
    List<RfpImportService.ImportRow> rows = new List<RfpImportService.ImportRow>{
      row(1, 'Montreal', 'QC', 'CA', null, 'Toronto', 'ON', 'CA', null),
      row(2, 'Montreal', 'QC', 'CA', null, 'Toronto', 'ON', 'CA', null),
      row(3, 'Montreal', 'QC', 'CA', null, 'Toronto', 'ON', 'CA', null)
    };
    rows[1].quantity = 1000000000000000000L;
    Test.startTest();
    RfpImportService.Summary s = RfpImportService.importRows(p.Id, rows);
    Test.stopTest();
    System.assertEquals(2, s.imported, 'the good rows still land');
    System.assertEquals(1, s.failed);
    System.assertEquals(0, s.skipped);
    List<RFP_Lane__c> lanes = [
      SELECT Row_Number__c
      FROM RFP_Lane__c
      WHERE RFP_Project__c = :p.Id
      ORDER BY Row_Number__c
    ];
    System.assertEquals(2, lanes.size());
    System.assertEquals(1, lanes[0].Row_Number__c);
    System.assertEquals(
      3,
      lanes[1].Row_Number__c,
      'row 2 failed on its own, row 3 was not discarded with it'
    );
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
