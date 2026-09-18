/**
 * Phase 12: the account a project falls back to when no customer was chosen.
 *
 * RFP_Project__c.Customer__c is a MasterDetail to Account, so a project with no customer cannot
 * exist and "a market test has no customer" has to mean something else: it belongs to the org's
 * Market Test account. RFP_Project__c is ControlledByParent, so sharing that one account is what
 * gives the whole pricing team the same market tests - no second access path to keep correct.
 *
 * Held as an id in Pricing_Department_Setting__mdt rather than matched by name, so renaming the
 * account breaks nothing.
 */
public with sharing class MarketTestSetting {
  @TestVisible
  private static Id accountIdOverride;
  /**
   * Forces "no account configured" in a test. A null override cannot mean that: it falls
   * through to the setting, and every org this runs in has one, so the branch that decides on
   * the marker alone would never be exercised.
   */
  @TestVisible
  private static Boolean suppressSetting = false;

  public static Id accountId() {
    if (suppressSetting == true) {
      return null;
    }
    if (accountIdOverride != null) {
      return accountIdOverride;
    }
    List<Pricing_Department_Setting__mdt> settings = [
      SELECT Market_Test_Account_Id__c
      FROM Pricing_Department_Setting__mdt
      WHERE DeveloperName = 'Default'
      LIMIT 1
    ];
    String value = settings.isEmpty()
      ? null
      : settings[0].Market_Test_Account_Id__c;
    return String.isBlank(value) ? null : (Id) value;
  }
}
