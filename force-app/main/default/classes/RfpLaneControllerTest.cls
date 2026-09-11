@IsTest
private class RfpLaneControllerTest {
  private class Fx {
    PricingTestDataFactory.Graph g;
    RFP_Project__c project;
    RFP_Lane__c lane;
    Pricing_Place__c mtl;
    Pricing_Place__c tor;
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
  static void importGetLanesAndRawRowsRoundTrip() {
    Fx f = fx();
    String rowsJson = '[{"rowNumber":7,"origin":{"city":"Montreal","province":"QC","country":"CA"},"destination":{"city":"Toronto","province":"ON","country":"CA"},"raw":"{\\"A\\":\\"x\\"}"}]';
    RfpImportService.Summary s = RfpLaneController.importLanes(
      f.project.Id,
      rowsJson
    );
    System.assertEquals(1, s.imported);
    List<RFP_Lane__c> lanes = RfpLaneController.getLanes(f.project.Id);
    System.assertEquals(2, lanes.size());
    System.assertEquals('montreal|qc|ca', lanes[1].Origin_Place__r.Key__c);
    System.assert(
      !lanes[1].isSet('Raw_Row__c'),
      'getLanes excludes Raw_Row__c'
    );
    List<RFP_Lane__c> raw = RfpLaneController.getRawRows(f.project.Id, 0);
    System.assertEquals(2, raw.size());
    System.assertEquals('{"A":"x"}', raw[1].Raw_Row__c);
  }

  @IsTest
  static void saveLanePricingWhitelistsFields() {
    Fx f = fx();
    String laneJson =
      '{"Id":"' +
      f.lane.Id +
      '","Cost__c":1000,"Cost_Source__c":"Manual","Margin__c":20,"Sell__c":1200,"Notes__c":"n","Origin_City__c":"HACKED","Hist_Count__c":99}';
    RFP_Lane__c out = RfpLaneController.saveLanePricing(laneJson);
    RFP_Lane__c db = [
      SELECT
        Cost__c,
        Cost_Source__c,
        Margin__c,
        Sell__c,
        Notes__c,
        Origin_City__c,
        Hist_Count__c
      FROM RFP_Lane__c
      WHERE Id = :f.lane.Id
    ];
    System.assertEquals(1000, db.Cost__c);
    System.assertEquals('Manual', db.Cost_Source__c);
    System.assertEquals(20, db.Margin__c);
    System.assertEquals(1200, db.Sell__c);
    System.assertEquals('n', db.Notes__c);
    System.assertEquals(
      'Montréal',
      db.Origin_City__c,
      'non-pricing fields ignored'
    );
    System.assertEquals(null, db.Hist_Count__c);
    System.assertEquals(1200, out.Sell__c);
  }

  @IsTest
  static void resolveLaneEndCopiesThePlaceAndResetsHistory() {
    Fx f = fx();
    Pricing_Place__c laval = RfpTestDataFactory.createPlace(
      'Laval',
      'QC',
      'CA',
      45.6066,
      -73.7124,
      'H7P'
    );
    f.lane.Hist_Status__c = 'Done';
    update f.lane;
    RFP_Lane__c out = RfpLaneController.resolveLaneEnd(
      f.lane.Id,
      'origin',
      'laval|qc|ca'
    );
    System.assertEquals(laval.Id, out.Origin_Place__c);
    System.assertEquals('Laval', out.Origin_City__c);
    System.assertEquals('H7P', out.Origin_Postal__c);
    System.assertEquals(true, out.Origin_Resolved__c);
    System.assertEquals('Pending', out.Hist_Status__c);
    try {
      RfpLaneController.resolveLaneEnd(f.lane.Id, 'sideways', 'laval|qc|ca');
      System.assert(false, 'expected an error');
    } catch (AuraHandledException e) {
      System.assert(e.getMessage().contains('origin'), e.getMessage());
    }
  }

  @IsTest
  static void resolveLaneEndKeepsHistStatusUnresolvedUntilBothEndsAreResolved() {
    Fx f = fx();
    f.lane.Destination_Place__c = null;
    f.lane.Destination_Resolved__c = false;
    f.lane.Hist_Status__c = 'Unresolved';
    update f.lane;
    RFP_Lane__c afterOrigin = RfpLaneController.resolveLaneEnd(
      f.lane.Id,
      'origin',
      'montreal|qc|ca'
    );
    System.assertEquals(true, afterOrigin.Origin_Resolved__c);
    System.assertEquals(
      'Unresolved',
      afterOrigin.Hist_Status__c,
      'destination is still unresolved'
    );
    RFP_Lane__c afterDestination = RfpLaneController.resolveLaneEnd(
      f.lane.Id,
      'destination',
      'toronto|on|ca'
    );
    System.assertEquals(true, afterDestination.Destination_Resolved__c);
    System.assertEquals('Pending', afterDestination.Hist_Status__c);
  }

  // The methods below are not in the brief: they exist to satisfy the org's 75%-per-class
  // deployment gate, which the three brief tests above do not reach for RfpLaneController
  // (74.0%: the destination branch of resolveLaneEnd and every try/catch wrapper were
  // untested) or for RfpUserError (57.1%: safe() was never called).

  @IsTest
  static void resolveLaneEndAppliesTheDestinationSide() {
    Fx f = fx();
    Pricing_Place__c laval = RfpTestDataFactory.createPlace(
      'Laval',
      'QC',
      'CA',
      45.6066,
      -73.7124,
      'H7P'
    );
    RFP_Lane__c out = RfpLaneController.resolveLaneEnd(
      f.lane.Id,
      'destination',
      'laval|qc|ca'
    );
    System.assertEquals(laval.Id, out.Destination_Place__c);
    System.assertEquals('Laval', out.Destination_City__c);
    System.assertEquals('H7P', out.Destination_Postal__c);
    System.assertEquals(true, out.Destination_Resolved__c);
  }

  @IsTest
  static void importLanesWrapsTooManyRowsAsUserError() {
    Fx f = fx();
    List<Object> rows = new List<Object>();
    for (Integer i = 0; i < 201; i++) {
      rows.add(
        new Map<String, Object>{
          'rowNumber' => i + 1,
          'origin' => new Map<String, Object>{
            'city' => 'A',
            'province' => 'QC',
            'country' => 'CA'
          },
          'destination' => new Map<String, Object>{
            'city' => 'B',
            'province' => 'ON',
            'country' => 'CA'
          }
        }
      );
    }
    try {
      RfpLaneController.importLanes(f.project.Id, JSON.serialize(rows));
      System.assert(false, 'expected an error');
    } catch (AuraHandledException e) {
      System.assert(e.getMessage().contains('200'), e.getMessage());
    }
  }

  @IsTest
  static void importLanesWrapsBadJsonAsUserError() {
    Fx f = fx();
    try {
      RfpLaneController.importLanes(f.project.Id, 'not valid json');
      System.assert(false, 'expected an error');
    } catch (AuraHandledException e) {
      System.assert(e.getMessage().contains('imported'), e.getMessage());
    }
  }
}
