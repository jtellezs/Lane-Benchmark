/**
 * Phase 10: bucketing a lane's rates into months.
 *
 * without sharing, like LaneSearchService and BidSearchService, because spec §6 requires the trend
 * to read through the same system-mode path the search uses and to expose no row a search of the
 * same lane would not.
 */
public without sharing class LaneTrendService {
  /** Spec §4: a three-year window holds more than a 90-day search, and this is its own transaction. */
  public static final Integer ROW_CAP = 10000;
  /** D5: three quotes do not make a market. */
  public static final Integer THIN_COUNT = 3;

  private static final List<String> MONTH_LABELS = new List<String>{
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec'
  };

  /** One rate on a date, which is all a bucket needs from either source. */
  public class Sample {
    public Date sampleDate;
    public Decimal amount;

    public Sample(Date sampleDate, Decimal amount) {
      this.sampleDate = sampleDate;
      this.amount = amount;
    }
  }

  /**
   * One point per month that has rates, in month order, with the count, median, min and max of that
   * month's amounts. Months with no rates are absent (spec §7: gaps, not zeros), and monthIndex
   * carries the distance from the window start so the chart can show the gap.
   *
   * A sample with no date cannot be placed on a time axis, and one with no amount is not a rate;
   * both are dropped rather than counted as zero, which would drag a median toward nothing.
   */
  @TestVisible
  private static List<LaneTrend.Point> bucket(
    List<Sample> samples,
    Date windowStart,
    Integer monthSpan
  ) {
    Map<String, List<Decimal>> byMonth = new Map<String, List<Decimal>>();
    Map<String, Date> firstOfMonth = new Map<String, Date>();
    for (Sample sample : samples) {
      if (
        sample == null ||
        sample.sampleDate == null ||
        sample.amount == null
      ) {
        continue;
      }
      String key = monthKeyOf(sample.sampleDate);
      if (!byMonth.containsKey(key)) {
        byMonth.put(key, new List<Decimal>());
        firstOfMonth.put(
          key,
          Date.newInstance(
            sample.sampleDate.year(),
            sample.sampleDate.month(),
            1
          )
        );
      }
      byMonth.get(key).add(sample.amount);
    }

    List<String> keys = new List<String>(byMonth.keySet());
    keys.sort();

    List<LaneTrend.Point> points = new List<LaneTrend.Point>();
    for (String key : keys) {
      List<Decimal> amounts = byMonth.get(key);
      Date monthDate = firstOfMonth.get(key);
      LaneTrend.Point point = new LaneTrend.Point();
      point.monthKey = key;
      point.label = MONTH_LABELS[monthDate.month() - 1];
      point.monthIndex = monthsBetween(windowStart, monthDate);
      point.count = amounts.size();
      point.median = SplitLaneService.median(amounts);
      point.minimum = leastOf(amounts);
      point.maximum = greatestOf(amounts);
      point.thin = amounts.size() < THIN_COUNT;
      points.add(point);
    }
    return points;
  }

  private static String monthKeyOf(Date d) {
    return String.valueOf(d.year()) +
      '-' +
      (d.month() < 10 ? '0' : '') +
      String.valueOf(d.month());
  }

  private static Integer monthsBetween(Date from0, Date to0) {
    return (to0.year() - from0.year()) * 12 + (to0.month() - from0.month());
  }

  private static Decimal leastOf(List<Decimal> values) {
    Decimal least = values[0];
    for (Decimal v : values) {
      if (v < least) {
        least = v;
      }
    }
    return least;
  }

  private static Decimal greatestOf(List<Decimal> values) {
    Decimal greatest = values[0];
    for (Decimal v : values) {
      if (v > greatest) {
        greatest = v;
      }
    }
    return greatest;
  }
}
