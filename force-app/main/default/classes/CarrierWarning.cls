/**
 * Phase 8: the red carrier warning on lane search rows, shown by laneBenchmarkResults on Lane
 * Benchmark and in the RFP lane panel's history results. It used to be the
 * rtms__CarrierQuote__c.Carrier_Att__c formula, whose blacklist half reads the Transportation
 * Profile's BlackList__c (no quote in a year) while carriers are blacklisted on
 * Account.Black_List__c (548 accounts). The two texts and their order stay the formula's: the
 * blacklist flag now comes from the carrier account (a quote's rtms__Vendor__r, a bid's
 * Carrier__r), and the claim flag still comes from the quote's Transportation Profile (spec D5,
 * R90). Built here so quote rows and bid rows share one text and LaneSearchService keeps its PMD
 * complexity budget.
 */
public with sharing class CarrierWarning {
  private static final String BLACKLIST_TEXT = ' THE CARRIER IS BLACK-LISTED ';
  private static final String CLAIM_TEXT = ' UNDER A CLAIM ';

  /**
   * The formula's texts in its order, trimmed the way a query returns the formula ("UNDER A
   * CLAIM"), so both flags keep two spaces between the texts. A null flag counts as not set; null
   * when neither flag is set.
   */
  public static String text(Boolean blacklisted, Boolean underClaim) {
    String joined =
      (blacklisted == true ? BLACKLIST_TEXT : '') +
      (underClaim == true ? CLAIM_TEXT : '');
    String trimmed = joined.trim();
    return String.isEmpty(trimmed) ? null : trimmed;
  }
}
