/**
 * Data source for the Pricing Department page.
 * Runs WITHOUT SHARING on purpose: pricing must benchmark against every team's carrier quotes,
 * regardless of load ownership. Do not change to with sharing without a product decision.
 */
public without sharing class PricingDepartmentController {
  public class UniqueCarrierQuote {
    public rtms__CarrierQuote__c quote;

    public UniqueCarrierQuote(rtms__CarrierQuote__c quote) {
      this.quote = quote;
    }

    public Boolean equals(Object obj) {
      if (obj instanceof UniqueCarrierQuote) {
        UniqueCarrierQuote other = (UniqueCarrierQuote) obj;
        return (quote.CAD_Quote_Total__c == other.quote.CAD_Quote_Total__c &&
        quote.Carrier_Name__c == other.quote.Carrier_Name__c &&
        quote.Origin__c == other.quote.Origin__c &&
        quote.Destination__c == other.quote.Destination__c &&
        quote.Mode__c == other.quote.Mode__c &&
        quote.Equipment_Type__c == other.quote.Equipment_Type__c);
      }
      return false;
    }

    public Integer hashCode() {
      return (decimalHashCode(quote.CAD_Quote_Total__c) ^
      (quote.Carrier_Name__c == null ? 0 : quote.Carrier_Name__c.hashCode()) ^
      (quote.Origin__c == null ? 0 : quote.Origin__c.hashCode()) ^
      (quote.Destination__c == null ? 0 : quote.Destination__c.hashCode()) ^
      (quote.Mode__c == null ? 0 : quote.Mode__c.hashCode()) ^
      (quote.Equipment_Type__c == null
        ? 0
        : quote.Equipment_Type__c.hashCode()));
    }

    private Integer decimalHashCode(Decimal value) {
      return value == null ? 0 : value.toPlainString().hashCode();
    }
  }

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

  @AuraEnabled(cacheable=true)
  public static List<rtms__CarrierQuote__c> getCarrierQuotes(
    String originFilter,
    String destinationFilter,
    String modeFilter,
    String hazmatFilter,
    String priceDepFilter,
    String equipmentFilter,
    Integer dateRangeFilter,
    String acceptedQuotesFilter,
    String declinedQuotesFilter
  ) {
    String originFilterStr = createFilterString(originFilter);
    String destinationFilterStr = createFilterString(destinationFilter);
    String modeFilterStr = createFilterString(modeFilter);
    String hazmatFilterStr = createFilterString(hazmatFilter);
    String priceDepFilterStr = createFilterString(priceDepFilter);
    String equipmentFilterStr = createFilterString(equipmentFilter);
    String acceptedQuotesFilterStr = createFilterString(acceptedQuotesFilter);
    String declinedQuotesFilterStr = createFilterString(declinedQuotesFilter);
    Date startDate = Date.today().addDays(-dateRangeFilter);

    List<rtms__CarrierQuote__c> allCarrierQuotes = fetchCarrierQuotes(
      originFilterStr,
      destinationFilterStr,
      modeFilterStr,
      hazmatFilterStr,
      priceDepFilterStr,
      equipmentFilterStr,
      startDate,
      acceptedQuotesFilterStr,
      declinedQuotesFilterStr
    );

    Set<UniqueCarrierQuote> uniqueCarrierQuoteSet = new Set<UniqueCarrierQuote>();
    List<rtms__CarrierQuote__c> uniqueCarrierQuotes = new List<rtms__CarrierQuote__c>();

    for (rtms__CarrierQuote__c carrierQuote : allCarrierQuotes) {
      UniqueCarrierQuote uniqueCarrierQuote = new UniqueCarrierQuote(
        carrierQuote
      );
      if (!uniqueCarrierQuoteSet.contains(uniqueCarrierQuote)) {
        uniqueCarrierQuoteSet.add(uniqueCarrierQuote);
        uniqueCarrierQuotes.add(carrierQuote);
      }
    }

    return uniqueCarrierQuotes;
  }

  private static String createFilterString(String filter) {
    return '%' + filter + '%';
  }

  // system mode by design: the page benchmarks every team's quotes; access is gated by the
  // Pricing_Department_User permission set
  @SuppressWarnings('PMD.ApexCRUDViolation')
  private static List<rtms__CarrierQuote__c> fetchCarrierQuotes(
    String originFilterStr,
    String destinationFilterStr,
    String modeFilterStr,
    String hazmatFilterStr,
    String priceDepFilterStr,
    String equipmentFilterStr,
    Date startDate,
    String acceptedQuotesFilterStr,
    String declinedQuotesFilterStr
  ) {
    Set<String> excluded = excludedContactIds();
    return [
      SELECT
        Id,
        CAD_Quote_Total__c,
        Carrier_Contact__c,
        Contact_Email__c,
        Destination__c,
        Contact_Phone__c,
        Equipment_Type__c,
        Mode__c,
        Nb_Of_Pallets__c,
        Ops_Comments__c,
        Ship_Date__c,
        rtms__Carrier_Service__c,
        Name,
        rtms__Vendor__c,
        rtms__Vendor__r.Name,
        Contact_ID__c,
        Carrier_Name__c,
        Origin_Destination_Country__c,
        Hazmat__c,
        Customer_Name__c,
        Quote_Date__c,
        Origin__c,
        Load_Status__c,
        Accepted_quote__c,
        Decline_Quotes__c,
        rtms__Carrier_Total__c,
        CurrencyIsoCode,
        Carrier_Risk__c,
        Nb_of_loads__c,
        Carrier_Att__c,
        rtms__Load__c
      FROM rtms__CarrierQuote__c
      WHERE
        Origin__c LIKE :originFilterStr
        AND Destination__c LIKE :destinationFilterStr
        AND Mode__c LIKE :modeFilterStr
        AND Hazmat__c LIKE :hazmatFilterStr
        AND Customer_Name__c LIKE :priceDepFilterStr
        AND Equipment_Type__c LIKE :equipmentFilterStr
        AND Quote_Date__c >= :startDate
        AND Accepted_quote__c LIKE :acceptedQuotesFilterStr
        AND Decline_Quotes__c LIKE :declinedQuotesFilterStr
        AND Contact_ID__c NOT IN :excluded
      ORDER BY Quote_Date__c DESC
      LIMIT 500
    ];
  }
}
