/**
 * Spec W1: which unit a window buckets by, how that unit keys, labels, counts and thresholds - and,
 * since Task 2, the bucketing itself. bucket() used to live on LaneTrendService, but that class sits
 * near a PMD class complexity cap and the unit it varies by belongs beside the calendar that defines
 * the unit, not beside the query that reads the rows. The project's ruling is to split a cohesive
 * family out rather than suppress, as LaneSearchFilters, MarketTestFilter, LaneTrendQueries,
 * LaneTrendSummary and LaneTrendScope each already did.
 *
 * Every key is lexically sortable, because the chart's chronological order comes from sorting the
 * keys as strings. A key that sorts differently than it reads reorders the axis with nothing red.
 */
public with sharing class LaneTrendBuckets {
  public static final String DAY = 'day';
  public static final String WEEK = 'week';
  public static final String MONTH = 'month';

  // 1900-01-01 was a Monday, so the remainder of the day count from it is the number of days
  // since that week's Monday. Date.toStartOfWeek() is not used: it follows the running user's
  // locale, so a Sunday-first user would bucket the same rate into a different week.
  private static final Date WEEK_ANCHOR = Date.newInstance(1900, 1, 1);

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

  /**
   * Day up to a month, week up to a quarter, month beyond: every window lands near 7 to 37 points.
   *
   * The two cutoffs are pinned to the calendar, not chosen freely: 31 is the longest possible
   * calendar month (Jan/Mar/May/Jul/Aug/Oct/Dec), so it is the only cutoff under which every real
   * one-month window classifies as DAY - 30 would misclassify a 31-day month as WEEK. 92 is the
   * longest possible span of three consecutive calendar months (e.g. Jun 1 - Sep 1), so it is the
   * only cutoff under which every real three-month window classifies as WEEK - 91 would
   * misclassify several real three-month spans as MONTH. See LaneTrendBucketsTest's
   * pinsTheDayWeekAndWeekMonthBoundariesToTheLongestRealCalendarSpan.
   */
  public static String unitFor(Integer lookbackDays) {
    if (lookbackDays == null || lookbackDays <= 31) {
      return DAY;
    }
    return lookbackDays <= 92 ? WEEK : MONTH;
  }

  public static Date startOfWeek(Date d) {
    return d.addDays(-Math.mod(WEEK_ANCHOR.daysBetween(d), 7));
  }

  /** The bucket a date belongs to, as a string that sorts chronologically. */
  public static String keyOf(Date d, String unit) {
    if (unit == MONTH) {
      return String.valueOf(d.year()) + '-' + pad(d.month());
    }
    Date start = unit == WEEK ? startOfWeek(d) : d;
    return String.valueOf(start.year()) +
      '-' +
      pad(start.month()) +
      '-' +
      pad(start.day());
  }

  /** Short enough to sit under a 15-unit axis slot; the component adds the year where it changes. */
  public static String labelOf(Date d, String unit) {
    if (unit == MONTH) {
      return MONTH_LABELS[d.month() - 1];
    }
    Date start = unit == WEEK ? startOfWeek(d) : d;
    return String.valueOf(start.day()) + ' ' + MONTH_LABELS[start.month() - 1];
  }

  /**
   * For MONTH this ignores day-of-month entirely, so it is only meaningful when both dates are
   * already aligned to a bucket boundary - it is not a general calendar-distance function. Task 2
   * relies on this: bucketIndex = between(windowStart, bucketStart, unit), where bucketStart is
   * itself bucket-aligned.
   */
  public static Integer between(Date from0, Date to0, String unit) {
    if (unit == MONTH) {
      return (to0.year() - from0.year()) * 12 + (to0.month() - from0.month());
    }
    if (unit == WEEK) {
      return startOfWeek(from0).daysBetween(startOfWeek(to0)) / 7;
    }
    return from0.daysBetween(to0);
  }

  /** W3. A day needs one rate, so no daily bucket is ever thin - at that zoom the reader is
   * looking at individual activity rather than a market median. */
  public static Integer thinCountFor(String unit) {
    if (unit == DAY) {
      return 1;
    }
    return unit == WEEK ? 2 : 3;
  }

  /**
   * One point per bucket that has rates, in order, with the count, median, min and max of that
   * bucket's amounts. Buckets with no rates are absent (gaps, not zeros), and bucketIndex carries
   * the distance from the window start so the chart can draw the absence.
   */
  public static List<LaneTrend.Point> bucket(
    List<LaneTrendService.Sample> samples,
    Date windowStart,
    String unit
  ) {
    Map<String, List<Decimal>> byBucket = new Map<String, List<Decimal>>();
    Map<String, Date> startOfBucket = new Map<String, Date>();
    for (LaneTrendService.Sample sample : samples) {
      if (!LaneTrendSummary.isUsable(sample)) {
        continue;
      }
      String key = keyOf(sample.sampleDate, unit);
      if (!byBucket.containsKey(key)) {
        byBucket.put(key, new List<Decimal>());
        startOfBucket.put(key, startOf(sample.sampleDate, unit));
      }
      byBucket.get(key).add(sample.amount);
    }

    List<String> keys = new List<String>(byBucket.keySet());
    keys.sort();

    Integer thinAt = thinCountFor(unit);
    List<LaneTrend.Point> points = new List<LaneTrend.Point>();
    for (String key : keys) {
      List<Decimal> amounts = byBucket.get(key);
      Date bucketStart = startOfBucket.get(key);
      LaneTrend.Point point = new LaneTrend.Point();
      point.bucketKey = key;
      point.label = labelOf(bucketStart, unit);
      point.bucketIndex = between(windowStart, bucketStart, unit);
      point.count = amounts.size();
      point.median = SplitLaneService.median(amounts);
      point.minimum = leastOf(amounts);
      point.maximum = greatestOf(amounts);
      point.thin = amounts.size() < thinAt;
      points.add(point);
    }
    return points;
  }

  /** The first moment of the bucket a date falls in: its day, its week's Monday, or its 1st. */
  public static Date startOf(Date d, String unit) {
    if (unit == MONTH) {
      return Date.newInstance(d.year(), d.month(), 1);
    }
    return unit == WEEK ? startOfWeek(d) : d;
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

  private static String pad(Integer n) {
    return (n < 10 ? '0' : '') + String.valueOf(n);
  }
}
