/**
 * Handoff points for split-lane estimates (phase 8, spec D8), read from Handoff_Point__mdt so an admin
 * adds, edits or deactivates a point in Setup without a deploy. Each record's Place_Key__c is a
 * Pricing_Place__c.Key__c ('laredo|tx|us'). Tests set keysOverride because custom metadata cannot be
 * inserted in tests.
 */
public with sharing class HandoffPoints {
  // Test hook: tests set this to control the list because custom metadata cannot be inserted in tests.
  @TestVisible
  private static List<String> keysOverride;

  /** The place keys of the active handoff points: trimmed, lowercased, distinct and sorted; never null. */
  public static List<String> activeKeys() {
    if (keysOverride != null) {
      return new List<String>(keysOverride);
    }
    return parseKeys(Handoff_Point__mdt.getAll().values());
  }

  /** Active records only; a blank Place_Key__c is skipped. */
  @TestVisible
  private static List<String> parseKeys(List<Handoff_Point__mdt> records) {
    Set<String> distinctKeys = new Set<String>();
    if (records != null) {
      for (Handoff_Point__mdt row : records) {
        if (
          row == null ||
          row.Active__c != true ||
          String.isBlank(row.Place_Key__c)
        ) {
          continue;
        }
        distinctKeys.add(row.Place_Key__c.trim().toLowerCase());
      }
    }
    List<String> placeKeys = new List<String>(distinctKeys);
    placeKeys.sort();
    return placeKeys;
  }
}
