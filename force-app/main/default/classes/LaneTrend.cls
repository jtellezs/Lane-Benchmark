/**
 * Phase 10: one lane's market over time, as the page receives it.
 *
 * Data only. Every number is computed in Apex (D1) so the component formats and never calculates,
 * which is how LaneSearchResult.Stats already works. A month with no rates is absent rather than
 * zero, and monthIndex is what lets the chart draw that absence as a gap on a fixed axis.
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
  /** Ruling 11: rows that matched the search's own WHERE but bucket outside this window - dated by
   * Quote_Date__c/Valid_From__c, not by the CreatedDate the WHERE filtered on - dropped rather than
   * clamped onto the axis, and counted here so the page can say so. */
  @AuraEnabled
  public Integer outsideWindow = 0;
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
