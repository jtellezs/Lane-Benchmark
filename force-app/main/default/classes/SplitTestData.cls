/**
 * Phase 8 fixtures for split shipments (Revenova freight plans): carrier accounts, leg loads with a
 * carrier, a CAD carrier total and a status, and freight plans that link one customer load (junction
 * row Number 1, Type Customer) to its carrier legs (Number 2, 3, ..., Type Carrier). Later tests build
 * plans ONLY through plan() and resetPlans(), and a test that must prove the plan SOQL's lane or date
 * filter asserts on the LaneQueries SOQL string instead of on rows, so every test works whichever
 * branch below holds.
 *
 * PLANS: inserted (branch A). Revenova's managed code lets a test insert rtms__FreightPlan__c and
 * rtms__FreightPlanLoad__c, so plan() inserts real rows, FreightPlanReader runs the real query and
 * resetPlans() has nothing to clear.
 * LEG FIELDS: at insert, through PricingTestDataFactory.createLoad(g, origin, destination, template).
 * BUDGET: measured by the probe deploy 0AfbZ00000Cqo9uSAB (SplitTestDataTest's "budget" debug line,
 * 2026-09-15): before Test.startTest 88
 * queries / 41 DML (createGraph, a yard, a carrier and the customer load; 12 queries left there);
 * legLoad 37 and 35 queries / 13 DML each; plan 4 queries / 3 DML; 24 queries / 121 DML left inside
 * Test.startTest. A test holds ONE real split shipment: its customer load before Test.startTest(),
 * both legLoad calls and plan() inside it, then the code under test within the queries left.
 */
@IsTest
public class SplitTestData {
  /** An inserted carrier account shaped like the graph's vendor, blacklisted or not. */
  public static Account carrier(String name, Boolean blacklisted) {
    Account a = new Account(
      Name = name,
      RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
        .get('Carrier')
        .getRecordTypeId(),
      rtms__TMS_Type__c = 'Carrier (Ground)',
      Black_List__c = blacklisted == true,
      CurrencyIsoCode = 'CAD'
    );
    insert a;
    return a;
  }

  /**
   * A leg load from origin to destination (stops and lane keys from PricingTestDataFactory) with its
   * carrier, CAD carrier total and status. The returned load carries the factory's re-queried fields
   * plus these three as sent; SplitTestDataTest proves the org keeps them.
   */
  public static rtms__Load__c legLoad(
    PricingTestDataFactory.Graph g,
    Account origin,
    Account destination,
    Account carrierAccount,
    Decimal cadTotal,
    String status
  ) {
    rtms__Load__c template = new rtms__Load__c(
      rtms__Carrier__c = carrierAccount == null ? null : carrierAccount.Id,
      rtms__Carrier_Quote_Total__c = cadTotal,
      rtms__Load_Status__c = status
    );
    rtms__Load__c load = PricingTestDataFactory.createLoad(
      g,
      origin,
      destination,
      template
    );
    load.rtms__Carrier__c = template.rtms__Carrier__c;
    load.rtms__Carrier_Quote_Total__c = cadTotal;
    load.rtms__Load_Status__c = status;
    return load;
  }

  /** Branch A: inserts the plan, the Customer row (Number 1) and one Carrier row per leg (Number 2, 3, ...). */
  public static rtms__FreightPlan__c plan(
    rtms__Load__c customerLoad,
    List<rtms__Load__c> legLoads
  ) {
    rtms__FreightPlan__c freightPlan = new rtms__FreightPlan__c();
    insert freightPlan;
    List<rtms__FreightPlanLoad__c> junctionRows = new List<rtms__FreightPlanLoad__c>{
      new rtms__FreightPlanLoad__c(
        rtms__Freight_Plan__c = freightPlan.Id,
        rtms__Load__c = customerLoad.Id,
        rtms__Type__c = 'Customer',
        rtms__Number__c = 1
      )
    };
    Integer position = 2;
    for (rtms__Load__c leg : legLoads) {
      junctionRows.add(
        new rtms__FreightPlanLoad__c(
          rtms__Freight_Plan__c = freightPlan.Id,
          rtms__Load__c = leg.Id,
          rtms__Type__c = 'Carrier',
          rtms__Number__c = position
        )
      );
      position++;
    }
    insert junctionRows;
    return freightPlan;
  }

  /** Clears the in-memory plans; harmless in branch A, where nothing sets them. */
  public static void resetPlans() {
    FreightPlanReader.rowsOverride = null;
  }
}
