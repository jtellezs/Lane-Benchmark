/**
 * What is wrong with the cost/sell/margin a pricer typed, before any lane is touched. Split out of
 * RfpBulkService so the bulk actions and the rules their numbers must satisfy stay separately
 * readable (and the action class stays inside PMD's complexity budget).
 */
public with sharing class RfpPricingInput {
  /** The first thing wrong with the typed numbers, or null when they can be applied. */
  public static String problem(Decimal cost, Decimal sell, Decimal margin) {
    Boolean nothingTyped = cost == null && sell == null && margin == null;
    if (nothingTyped) {
      return 'Enter a cost, a sell or a margin.';
    }
    Boolean sellAndMargin = sell != null && margin != null;
    if (sellAndMargin) {
      return 'Enter a sell or a margin, not both.';
    }
    Boolean costTooLow = cost != null && cost <= 0;
    if (costTooLow) {
      return 'The cost must be above zero.';
    }
    Boolean sellTooLow = sell != null && sell <= 0;
    if (sellTooLow) {
      return 'The sell must be above zero.';
    }
    Boolean marginOutOfRange = margin != null && (margin < 0 || margin > 100);
    if (marginOutOfRange) {
      return 'The margin must be between 0 and 100.';
    }
    return null;
  }
}
