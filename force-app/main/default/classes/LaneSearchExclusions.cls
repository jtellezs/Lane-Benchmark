/**
 * Contact Ids whose carrier quotes are hidden from every lane search, from Pricing_Department_Setting__mdt.Default; tests set excludedContactIdsOverride because custom metadata cannot be inserted in tests.
 */
public with sharing class LaneSearchExclusions {
  // Test hook: tests set this to control exclusions because custom metadata cannot be inserted in tests.
  @TestVisible
  private static Set<String> excludedContactIdsOverride;

  /**
   * Contact Ids whose quotes are hidden, from Pricing_Department_Setting__mdt.Default.
   * Contact_ID__c is a formula returning the 15-character id, so both forms are included.
   */
  @TestVisible
  private static Set<String> excludedContactIds() {
    if (excludedContactIdsOverride != null) {
      return excludedContactIdsOverride;
    }
    Pricing_Department_Setting__mdt setting = Pricing_Department_Setting__mdt.getInstance(
      'Default'
    );
    return parseExcludedContactIds(
      setting == null ? null : setting.Excluded_Contact_Ids__c
    );
  }

  /** Shared with LaneSearchService so both read the same custom metadata and honor the test override. */
  public static Set<String> excludedContactIdSet() {
    return excludedContactIds();
  }

  /**
   * Parses a comma-separated list of Contact Ids, tolerating admin data-entry mistakes:
   * malformed or wrong-length entries are logged and skipped rather than thrown.
   */
  @TestVisible
  private static Set<String> parseExcludedContactIds(String raw) {
    Set<String> ids = new Set<String>();
    if (String.isBlank(raw)) {
      return ids;
    }
    for (String entry : raw.split(',')) {
      String trimmed = entry.trim();
      if (String.isBlank(trimmed)) {
        continue;
      }
      Boolean isValid = false;
      if (trimmed.length() == 15 || trimmed.length() == 18) {
        try {
          Id contactId = Id.valueOf(trimmed);
          if (contactId.getSObjectType() == Contact.SObjectType) {
            ids.add(String.valueOf(contactId));
            ids.add(String.valueOf(contactId).left(15));
            isValid = true;
          }
        } catch (System.StringException e) {
          isValid = false;
        }
      }
      if (!isValid) {
        System.debug(
          LoggingLevel.WARN,
          'Pricing_Department_Setting.Default: ignoring invalid Contact Id "' +
            trimmed +
            '"'
        );
      }
    }
    return ids;
  }
}
