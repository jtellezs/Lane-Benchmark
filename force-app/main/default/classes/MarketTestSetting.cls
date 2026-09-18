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
  @TestVisible
  private static String accountNameOverride;
  /** 'Market Test' is the answer when nothing is configured, as phase 7 matched it. */
  @TestVisible
  private static final String DEFAULT_NAME = 'Market Test';
  private static String cachedName;
  private static Boolean nameResolved = false;

  public static Id accountId() {
    if (suppressSetting == true) {
      return null;
    }
    if (accountIdOverride != null) {
      return accountIdOverride;
    }
    // getInstance rather than SOQL, as LaneSearchExclusions reads the same record: custom
    // metadata is not subject to CRUD, and the typed accessor costs no query against the limit.
    Pricing_Department_Setting__mdt setting = Pricing_Department_Setting__mdt.getInstance(
      'Default'
    );
    String value = setting == null ? null : setting.Market_Test_Account_Id__c;
    return String.isBlank(value) ? null : (Id) value;
  }

  /**
   * The house account's current name, for the one place that has to match on a name:
   * rtms__CarrierQuote__c carries Customer_Name__c and no account lookup, so the quote half of the
   * Lane Benchmark market-test filter has nothing else to match on (phase 12 review, finding #3).
   *
   * Read from the account the setting points at rather than written as a literal, so renaming the
   * account moves the quote half with the bid half instead of leaving the two disagreeing. Falls
   * back to the literal when nothing is configured or the account cannot be read, because a quote
   * has no marker to fall back to and an id would match nothing. Cached: the filter asks once per
   * search, and one name costs one query per transaction at most.
   */
  public static String accountName() {
    if (accountNameOverride != null) {
      return accountNameOverride;
    }
    if (nameResolved) {
      return cachedName;
    }
    nameResolved = true;
    cachedName = DEFAULT_NAME;
    Id house = accountId();
    if (house != null) {
      List<Account> found = [
        SELECT Name
        FROM Account
        WHERE Id = :house
        WITH USER_MODE
        LIMIT 1
      ];
      if (!found.isEmpty() && String.isNotBlank(found[0].Name)) {
        cachedName = found[0].Name;
      }
    }
    return cachedName;
  }
}
