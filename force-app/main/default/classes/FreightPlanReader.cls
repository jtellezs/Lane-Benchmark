/**
 * Reads Revenova freight plans with their junction rows (rtms__Freight_Plan_Loads__r) for Carriers to
 * ask (CarrierLeadService) and Split-lane options (SplitLaneService). Both services read plans only
 * through this class, so a test can hand them plan rows through rowsOverride when Revenova's managed
 * code refuses test inserts (see SplitTestData's class comment for the branch that holds). Callers
 * iterate the child rows with a for loop: reading a child list of more than 200 rows directly throws.
 */
// Runs without sharing on purpose, like LaneSearchService: loads inherit Private sharing and pricing reads every team's split shipments. Access is gated by the Lane Benchmark and RFP Tool permission sets.
public without sharing class FreightPlanReader {
  // Test hook: tests set this (through SplitTestData) because freight plans may not be insertable in tests.
  @TestVisible
  private static List<rtms__FreightPlan__c> rowsOverride;

  /** The plans soql selects, in system mode; the override instead when a test set one. */
  @SuppressWarnings(
    'PMD.ApexCRUDViolation'
  ) // system mode by design (see class comment); Database.queryWithBinds also counts as CRUD for PMD
  public static List<rtms__FreightPlan__c> read(
    String soql,
    Map<String, Object> binds
  ) {
    if (rowsOverride != null) {
      return rowsOverride;
    }
    return Database.queryWithBinds(soql, binds, AccessLevel.SYSTEM_MODE);
  }
}
