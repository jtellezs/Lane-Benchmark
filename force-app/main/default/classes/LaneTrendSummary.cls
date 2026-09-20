/**
 * Phase 10 fix round 2 (reviewer finding, coordinator ruling): the summary half of the trend - the
 * numbers the sentence under the chart is built from - split out of LaneTrendService per the
 * project's ruling that a class over PMD's 40-point cyclomatic-complexity cap is split, not
 * suppressed (the same ruling behind LaneTrendQueries and MarketTestFilter). Ruling 14's currency
 * selection pushed LaneTrendService - which already resolves places, counts and reads both sources,
 * and buckets - past the cap; this class only computes, from a bucketed LaneTrend and the samples
 * that fed it. No SOQL, no DML, no sharing declaration needed.
 */
public class LaneTrendSummary {
  /**
   * The numbers the sentence under the chart is built from. Computed here rather than in the
   * component because the component formats and never calculates, as it already does for
   * LaneSearchResult.Stats. The change compares the first and last buckets that are not thin: two
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
   * Shared with LaneTrendBuckets.bucket() and LaneTrendScope: the trend's one drop rule. A sample
   * with no date cannot be placed on a time axis; one with no amount is not a rate; and one whose
   * amount is zero is not a price the market set.
   *
   * The zero is here to match the statistics card the chart sits under. LaneSearchService.stats()
   * computes its median, min, max and avg from non-zero totals only and reports the non-zero count
   * beside the raw one; the trend kept zeros, so every monthly median was pulled down by them and
   * every month containing one had its minimum pinned to 0 - which set the y axis floor to zero,
   * squashed the median line into the top of the frame, and printed a median the card directly above
   * contradicted. 2.9% of PostProduc's quotes over a year have a zero carrier total.
   *
   * It follows that a month of five rows of which three are zero is a month of two rates, and D5
   * calls that thin and draws it hollow. That is what D5 means: two priced quotes do not make a
   * market - the owner's ruling on that consequence, recorded in the spec's 2026-09-19 amendment.
   *
   * Public so LaneTrendBuckets.bucket() (a different class since Task 2) can reuse the same
   * rule rather than re-deriving it.
   */
  public static Boolean isUsable(LaneTrendService.Sample s) {
    return s != null &&
      s.sampleDate != null &&
      s.amount != null &&
      s.amount != 0;
  }

  /** Same drop rule as bucket(): see isUsable. */
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
