/**
 * Phase 10: one lane's market over time, as the page receives it.
 *
 * Data only. Every number is computed in Apex (D1) so the component formats and never calculates,
 * which is how LaneSearchResult.Stats already works. A month with no rates is absent rather than
 * zero, and monthIndex is what lets the chart draw that absence as a gap on a fixed axis.
 *
 * The months are CreatedDate months - when each rate was recorded (owner decision, recorded in the
 * spec's 2026-09-19 amendment) - so the axis reads as when the evidence arrived, not when the freight
 * is due to move.
 */
public class LaneTrend {
  @AuraEnabled
  public List<Point> points = new List<Point>();
  @AuraEnabled
  public String currencyIsoCode;
  @AuraEnabled
  public Integer lookbackDays;
  /** Months spanned by the window, so the axis is the window and not just the months with data. */
  @AuraEnabled
  public Integer monthSpan;
  @AuraEnabled
  public Boolean truncated = false;
  /**
   * How many rates the chart is drawn from: dated, priced and in currencyIsoCode. This is the
   * statistics card's countNonZero for the same rows, not its count - a zero carrier total is not a
   * price the market set, and the card has always excluded zeros from its median, min, max and avg
   * (LaneSearchService.stats). There is no companion count of what was left out: every row the query
   * admitted can be placed on the axis now that both are decided by CreatedDate, so the only rows
   * missing from this number are the undated, unpriced and zero ones (LaneTrendSummary.isUsable).
   */
  @AuraEnabled
  public Integer totalRates = 0;
  @AuraEnabled
  public Decimal overallMedian;
  /** Change between the first and last months that are not thin; null when fewer than two qualify. */
  @AuraEnabled
  public Decimal changePct;
  @AuraEnabled
  public String firstLabel;
  @AuraEnabled
  public String lastLabel;

  public class Point {
    @AuraEnabled
    public String monthKey;
    @AuraEnabled
    public String label;
    @AuraEnabled
    public Integer monthIndex;
    @AuraEnabled
    public Integer count;
    @AuraEnabled
    public Decimal median;
    @AuraEnabled
    public Decimal minimum;
    @AuraEnabled
    public Decimal maximum;
    /** Fewer than LaneTrendService.THIN_COUNT rates: drawn hollow, skipped by the line (D5). */
    @AuraEnabled
    public Boolean thin;
  }
}
