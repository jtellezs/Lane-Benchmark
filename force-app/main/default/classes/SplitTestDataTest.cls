/**
 * Proves the phase 8 split fixtures in PostProduc: leg loads keep their carrier, CAD carrier total and
 * status; a plan built by SplitTestData.plan comes back through FreightPlanReader with the Customer
 * row first and the Carrier rows in rtms__Number__c order; and one split shipment leaves query room
 * for the code under test. PLAN_SOQL is the parent-child query verified in PostProduc on 2026-09-15,
 * written out by hand because LaneQueries.planSoql arrives in Task 5.
 */
@IsTest
private class SplitTestDataTest {
  private static final String PLAN_SOQL =
    'SELECT Id, (SELECT rtms__Number__c, rtms__Type__c, rtms__Load__c, rtms__Load__r.CreatedDate, ' +
    'rtms__Load__r.rtms__Carrier__c, rtms__Load__r.rtms__Carrier__r.Name, ' +
    'rtms__Load__r.rtms__Carrier__r.Black_List__c, rtms__Load__r.rtms__City_Lane__c, ' +
    'rtms__Load__r.rtms__Load_Status__c, rtms__Load__r.rtms__Carrier_Quote_Total__c, ' +
    'rtms__Load__r.rtms__Last_Stop__r.rtms__Location2__r.Name ' +
    'FROM rtms__Freight_Plan_Loads__r ORDER BY rtms__Number__c) ' +
    'FROM rtms__FreightPlan__c WHERE Id IN (SELECT rtms__Freight_Plan__c FROM rtms__FreightPlanLoad__c ' +
    'WHERE rtms__Type__c = \'Customer\' AND rtms__Load__r.rtms__City_Lane__c LIKE :oCity ' +
    'AND rtms__Load__r.CreatedDate = LAST_N_DAYS:365 ' +
    'AND rtms__Load__r.rtms__Load_Status__c != \'Cancelled\') LIMIT 10';

  private class Fixture {
    PricingTestDataFactory.Graph g;
    Account yard;
    Account blacklisted;
    rtms__Load__c customerLoad;
  }

  /**
   * Everything that runs before Test.startTest(): the graph (Montreal QC -> Toronto ON), the Kingston
   * yard where leg 1 ends, one blacklisted carrier and the customer load, which is the one createLoad
   * the factory's class doc lets run before Test.startTest().
   */
  private static Fixture fixture() {
    Fixture f = new Fixture();
    f.g = PricingTestDataFactory.createGraph();
    f.yard = PricingTestDataFactory.createLocation(
      'Kingston Yard',
      'Kingston',
      'Ontario',
      'Canada',
      'K7K 1A1',
      44.2312,
      -76.486
    );
    f.blacklisted = SplitTestData.carrier('Blacklisted Leg Carrier', true);
    f.customerLoad = PricingTestDataFactory.createLoad(
      f.g,
      f.g.originLocation,
      f.g.destinationLocation
    );
    return f;
  }

  private static String spent(Integer queriesBefore, Integer dmlBefore) {
    return (Limits.getQueries() - queriesBefore) +
      ' queries / ' +
      (Limits.getDmlStatements() - dmlBefore) +
      ' DML';
  }

  @IsTest
  static void planRowsKeepLegOrderCarrierTotalAndStatus() {
    Fixture f = fixture();
    Test.startTest();
    rtms__Load__c leg1 = SplitTestData.legLoad(
      f.g,
      f.g.originLocation,
      f.yard,
      f.g.vendor,
      1250.00,
      'Delivered'
    );
    rtms__Load__c leg2 = SplitTestData.legLoad(
      f.g,
      f.yard,
      f.g.destinationLocation,
      f.blacklisted,
      980.50,
      'Cancelled'
    );
    SplitTestData.plan(f.customerLoad, new List<rtms__Load__c>{ leg1, leg2 });
    Test.stopTest();

    List<Id> legIds = new List<Id>{ leg1.Id, leg2.Id };
    Map<Id, rtms__Load__c> stored = new Map<Id, rtms__Load__c>(
      [
        SELECT
          rtms__Carrier__c,
          rtms__Carrier_Quote_Total__c,
          rtms__Load_Status__c
        FROM rtms__Load__c
        WHERE Id IN :legIds
      ]
    );
    System.assertEquals(
      0,
      [
        SELECT COUNT()
        FROM rtms__CarrierQuote__c
        WHERE rtms__Load__c IN :legIds
      ],
      'a leg load gets no carrier quote from the automation, so leg fixtures never reach the quote counts'
    );
    System.assertEquals(
      f.g.vendor.Id,
      stored.get(leg1.Id).rtms__Carrier__c,
      'leg 1 keeps its carrier'
    );
    System.assertEquals(
      1250.00,
      stored.get(leg1.Id).rtms__Carrier_Quote_Total__c,
      'leg 1 keeps its CAD carrier total'
    );
    System.assertEquals(
      'Delivered',
      stored.get(leg1.Id).rtms__Load_Status__c,
      'leg 1 keeps its status'
    );
    System.assertEquals(
      f.blacklisted.Id,
      stored.get(leg2.Id).rtms__Carrier__c,
      'leg 2 keeps its carrier'
    );
    System.assertEquals(
      980.50,
      stored.get(leg2.Id).rtms__Carrier_Quote_Total__c,
      'leg 2 keeps its CAD carrier total'
    );
    System.assertEquals(
      'Cancelled',
      stored.get(leg2.Id).rtms__Load_Status__c,
      'leg 2 keeps its status'
    );

    List<rtms__FreightPlan__c> plans = FreightPlanReader.read(
      PLAN_SOQL,
      new Map<String, Object>{ 'oCity' => 'Montreal, QC:%' }
    );
    System.assertEquals(
      1,
      plans.size(),
      'one plan whose customer load is on the lane'
    );
    List<rtms__FreightPlanLoad__c> rows = new List<rtms__FreightPlanLoad__c>();
    for (rtms__FreightPlanLoad__c row : plans[0].rtms__Freight_Plan_Loads__r) {
      rows.add(row);
    }
    System.assertEquals(
      3,
      rows.size(),
      'the customer row and two carrier rows'
    );

    System.assertEquals(1, rows[0].rtms__Number__c, 'customer row first');
    System.assertEquals('Customer', rows[0].rtms__Type__c);
    System.assertEquals(f.customerLoad.Id, rows[0].rtms__Load__c);
    System.assertEquals(
      null,
      rows[0].rtms__Load__r.rtms__Carrier__c,
      'the customer load has no carrier'
    );
    System.assertEquals(
      'Montreal, QC:Toronto, ON',
      rows[0].rtms__Load__r.rtms__City_Lane__c
    );

    System.assertEquals(2, rows[1].rtms__Number__c, 'leg 1 second');
    System.assertEquals('Carrier', rows[1].rtms__Type__c);
    System.assertEquals(leg1.Id, rows[1].rtms__Load__c);
    System.assertEquals(f.g.vendor.Id, rows[1].rtms__Load__r.rtms__Carrier__c);
    System.assertEquals(
      'Test Carrier',
      rows[1].rtms__Load__r.rtms__Carrier__r.Name
    );
    System.assertEquals(
      false,
      rows[1].rtms__Load__r.rtms__Carrier__r.Black_List__c
    );
    System.assertEquals(
      1250.00,
      rows[1].rtms__Load__r.rtms__Carrier_Quote_Total__c
    );
    System.assertEquals(
      'Delivered',
      rows[1].rtms__Load__r.rtms__Load_Status__c
    );
    System.assertEquals(
      'Montreal, QC:Kingston, ON',
      rows[1].rtms__Load__r.rtms__City_Lane__c
    );
    System.assertEquals(
      'Kingston Yard',
      rows[1].rtms__Load__r.rtms__Last_Stop__r.rtms__Location2__r.Name,
      'the handoff yard is the last stop account of leg 1'
    );

    System.assertEquals(3, rows[2].rtms__Number__c, 'leg 2 third');
    System.assertEquals('Carrier', rows[2].rtms__Type__c);
    System.assertEquals(leg2.Id, rows[2].rtms__Load__c);
    System.assertEquals(
      f.blacklisted.Id,
      rows[2].rtms__Load__r.rtms__Carrier__c
    );
    System.assertEquals(
      'Blacklisted Leg Carrier',
      rows[2].rtms__Load__r.rtms__Carrier__r.Name
    );
    System.assertEquals(
      true,
      rows[2].rtms__Load__r.rtms__Carrier__r.Black_List__c
    );
    System.assertEquals(
      980.50,
      rows[2].rtms__Load__r.rtms__Carrier_Quote_Total__c
    );
    System.assertEquals(
      'Cancelled',
      rows[2].rtms__Load__r.rtms__Load_Status__c
    );
    System.assertEquals(
      'Kingston, ON:Toronto, ON',
      rows[2].rtms__Load__r.rtms__City_Lane__c
    );
    System.assertEquals(
      'Destination Co',
      rows[2].rtms__Load__r.rtms__Last_Stop__r.rtms__Location2__r.Name
    );
  }

  @IsTest
  static void oneSplitShipmentLeavesQueryRoomForTheCodeUnderTest() {
    Fixture f = fixture();
    Integer outerQueries = Limits.getQueries();
    String budget =
      'SplitTestData budget: before Test.startTest ' +
      outerQueries +
      ' queries / ' +
      Limits.getDmlStatements() +
      ' DML';
    Test.startTest();
    Integer queriesBefore = Limits.getQueries();
    Integer dmlBefore = Limits.getDmlStatements();
    rtms__Load__c leg1 = SplitTestData.legLoad(
      f.g,
      f.g.originLocation,
      f.yard,
      f.g.vendor,
      1250.00,
      'Delivered'
    );
    budget += '; legLoad 1 ' + spent(queriesBefore, dmlBefore);
    queriesBefore = Limits.getQueries();
    dmlBefore = Limits.getDmlStatements();
    rtms__Load__c leg2 = SplitTestData.legLoad(
      f.g,
      f.yard,
      f.g.destinationLocation,
      f.blacklisted,
      980.50,
      'Cancelled'
    );
    budget += '; legLoad 2 ' + spent(queriesBefore, dmlBefore);
    queriesBefore = Limits.getQueries();
    dmlBefore = Limits.getDmlStatements();
    SplitTestData.plan(f.customerLoad, new List<rtms__Load__c>{ leg1, leg2 });
    budget += '; plan ' + spent(queriesBefore, dmlBefore);
    Integer roomLeft = Limits.getLimitQueries() - Limits.getQueries();
    budget +=
      '; left inside Test.startTest ' +
      roomLeft +
      ' queries / ' +
      (Limits.getLimitDmlStatements() - Limits.getDmlStatements()) +
      ' DML';
    budget +=
      '; outer context after the fixture ' +
      (Limits.getLimitQueries() - outerQueries) +
      ' queries left';
    System.debug(LoggingLevel.INFO, budget);
    Test.stopTest();
    System.assert(
      roomLeft >= 20,
      'one split shipment must leave 20 queries for the code under test: ' +
      budget
    );
  }

  @IsTest
  static void readReturnsTheOverrideWithoutAQueryAndResetClearsIt() {
    FreightPlanReader.rowsOverride = new List<rtms__FreightPlan__c>{
      new rtms__FreightPlan__c()
    };
    Map<String, Object> binds = new Map<String, Object>{ 'none' => null };
    Integer queriesBefore = Limits.getQueries();
    List<rtms__FreightPlan__c> rows = FreightPlanReader.read(
      'SELECT Id FROM rtms__FreightPlan__c WHERE Id = :none',
      binds
    );
    System.assertEquals(
      queriesBefore,
      Limits.getQueries(),
      'the override answers without a query'
    );
    System.assert(
      rows === FreightPlanReader.rowsOverride,
      'read returns the override list itself'
    );
    SplitTestData.resetPlans();
    System.assertEquals(
      null,
      FreightPlanReader.rowsOverride,
      'resetPlans clears the override'
    );
    System.assertEquals(
      0,
      FreightPlanReader.read(
          'SELECT Id FROM rtms__FreightPlan__c WHERE Id = :none',
          binds
        )
        .size(),
      'after the reset the reader queries again'
    );
    System.assertEquals(
      queriesBefore + 1,
      Limits.getQueries(),
      'one query after the reset'
    );
  }
}
