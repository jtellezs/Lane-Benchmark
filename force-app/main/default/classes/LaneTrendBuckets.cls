/**
 * Spec W1: which unit a window buckets by, and how that unit keys, labels, counts and thresholds.
 *
 * Split out of LaneTrendService rather than added to it: that class sits at 39 against a PMD class
 * cap that fires at 40, and three-way unit dispatch would trip it. The project's ruling is to split
 * a cohesive family out rather than suppress, as LaneSearchFilters, MarketTestFilter,
 * LaneTrendQueries, LaneTrendSummary and LaneTrendScope each already did.
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

  /** Day up to a month, week up to a quarter, month beyond: every window lands near 7 to 37 points. */
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

  private static String pad(Integer n) {
    return (n < 10 ? '0' : '') + String.valueOf(n);
  }
}
