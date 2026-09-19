/**
 * Phase 10 fix round 2 (reviewer finding, coordinator ruling): the summary half of the trend - the
 * numbers the sentence under the chart is built from - split out of LaneTrendService per the
 * project's ruling that a class over PMD's 40-point cyclomatic-complexity cap is split, not
 * suppressed (the same ruling behind LaneTrendQueries and MarketTestFilter). Ruling 14's currency
 * selection pushed LaneTrendService - which already resolves places, counts and reads both sources,
 * drops out-of-window rows and buckets - past the cap; this class only computes, from a bucketed
 * LaneTrend and the samples that fed it. No SOQL, no DML, no sharing declaration needed.
 */
public class LaneTrendSummary {
  /**
   * The numbers the sentence under the chart is built from. Computed here rather than in the
   * component because the component formats and never calculates, as it already does for
   * LaneSearchResult.Stats. The change compares the first and last months that are not thin: two
   * quotes at either end would otherwise set the headline for a year.
   */
  public static void summarise(
    LaneTrend trend,
    List<LaneTrendService.Sample> samples
  ) {
    List<Decimal> all = usableAmounts(samples);
    trend.totalRates = all.size();
    trend.overallMedian = SplitLaneService.median(all);

    List<LaneTrend.Point> solid = solidPoints(trend.points);
    if (solid.size() < 2) {
      return;
    }
    LaneTrend.Point earliest = solid[0];
    LaneTrend.Point latest = solid[solid.size() - 1];
    trend.firstLabel = earliest.label;
    trend.lastLabel = latest.label;
    Boolean canDivide = earliest.median != null && earliest.median != 0;
    if (canDivide) {
      trend.changePct = ((latest.median - earliest.median) /
        earliest.median *
        100)
        .setScale(1);
    }
  }

  /**
   * Shared with LaneTrendService.bucket(): a sample with no date cannot be placed on a time axis,
   * and one with no amount is not a rate. Public so bucket() (which stays in LaneTrendService,
   * where the SOQL is read) can reuse the same rule rather than re-deriving it.
   */
  public static Boolean isUsable(LaneTrendService.Sample s) {
    return s != null && s.sampleDate != null && s.amount != null;
  }

  /** Same drop rule as bucket(): a sample with no date or no amount is not a rate. */
  private static List<Decimal> usableAmounts(
    List<LaneTrendService.Sample> samples
  ) {
    List<Decimal> amounts = new List<Decimal>();
    for (LaneTrendService.Sample s : samples) {
      if (isUsable(s)) {
        amounts.add(s.amount);
      }
    }
    return amounts;
  }

  private static List<LaneTrend.Point> solidPoints(
    List<LaneTrend.Point> points
  ) {
    List<LaneTrend.Point> solid = new List<LaneTrend.Point>();
    for (LaneTrend.Point p : points) {
      if (p.thin != true) {
        solid.add(p);
      }
    }
    return solid;
  }
}
