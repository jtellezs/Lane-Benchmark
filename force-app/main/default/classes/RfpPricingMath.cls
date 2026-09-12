/**
 * The sell/margin arithmetic of the RFP workbench (spec §4.4). c/marginMath mirrors it on the
 * client; RfpPricingMathTest and marginMath.test.js assert the same value table.
 */
public with sharing class RfpPricingMath {
  /** Margin__c is Percent(5,2): anything beyond ±999.99 cannot be stored. */
  private static final Decimal MARGIN_LIMIT = 999.99;

  public static Decimal sellFor(Decimal cost, Decimal marginPct) {
    if (cost == null || cost <= 0 || marginPct == null) {
      return null;
    }
    return (cost * (1 + marginPct / 100)).setScale(2, RoundingMode.HALF_UP);
  }

  public static Decimal marginFor(Decimal cost, Decimal sell) {
    if (cost == null || cost <= 0 || sell == null) {
      return null;
    }
    Decimal m = (sell.divide(cost, 8, RoundingMode.HALF_UP) - 1) * 100;
    m = m.setScale(2, RoundingMode.HALF_UP);
    return m.abs() > MARGIN_LIMIT ? null : m;
  }

  /**
   * After a cost change: a Manual sell stays and the margin follows it; otherwise the margin
   * (or the project default) stays and the sell follows it.
   */
  public static void recompute(RFP_Lane__c lane, Decimal defaultMargin) {
    if (lane.Sell_Source__c == 'Manual' && lane.Sell__c != null) {
      lane.Margin__c = marginFor(lane.Cost__c, lane.Sell__c);
      return;
    }
    Decimal margin = lane.Margin__c == null ? defaultMargin : lane.Margin__c;
    lane.Margin__c = margin;
    lane.Sell__c = sellFor(lane.Cost__c, margin);
    lane.Sell_Source__c = 'Margin';
  }
}
