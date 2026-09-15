/**
 * Carrier accounts of the company's own organizations (phase 8, spec D6 and R89), read from
 * Intercompany_Carrier__mdt so an admin edits the list in Setup without a deploy. Carriers to ask and
 * split-lane options leave these carriers out in their queries, because their quotes and leg costs are
 * internal pass-throughs. The account Ids live only in the custom metadata records, never in Apex.
 * Tests set idsOverride because custom metadata cannot be inserted in tests.
 */
public with sharing class IntercompanyCarriers {
  // Test hook: tests set this to control the list because custom metadata cannot be inserted in tests.
  @TestVisible
  private static Set<Id> idsOverride;

  /** The intercompany carrier Account Ids (18-character); never null. */
  public static Set<Id> ids() {
    if (idsOverride != null) {
      return new Set<Id>(idsOverride);
    }
    return parseIds(Intercompany_Carrier__mdt.getAll().values());
  }

  /**
   * Keeps each record's Carrier_Account_Id__c that is a 15- or 18-character Account Id, tolerating admin
   * data-entry mistakes: a blank, malformed or non-Account entry is logged and skipped rather than thrown.
   * Both lengths of the same account give one entry.
   */
  @TestVisible
  private static Set<Id> parseIds(List<Intercompany_Carrier__mdt> records) {
    Set<Id> accountIds = new Set<Id>();
    if (records == null) {
      return accountIds;
    }
    for (Intercompany_Carrier__mdt row : records) {
      Id accountId = accountIdOrNull(row?.Carrier_Account_Id__c);
      if (accountId == null) {
        System.debug(
          LoggingLevel.WARN,
          'Intercompany_Carrier: ignoring invalid Account Id "' +
            row?.Carrier_Account_Id__c +
            '"'
        );
        continue;
      }
      accountIds.add(accountId);
    }
    return accountIds;
  }

  private static Id accountIdOrNull(String raw) {
    String trimmed = raw == null ? '' : raw.trim();
    if (trimmed.length() != 15 && trimmed.length() != 18) {
      return null;
    }
    try {
      Id candidate = Id.valueOf(trimmed);
      return candidate.getSObjectType() == Account.SObjectType
        ? candidate
        : null;
    } catch (System.StringException e) {
      return null;
    }
  }
}
