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

  /** @TestVisible so a test can prove the guard without inserting 10,001 rows. camelCase, not final. */
  @TestVisible
  private static Integer rowCapOverride;

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
   * The lane's rates over the request's window, bucketed by month.
   *
   * The conditions are the search's own (D2) and therefore carry the market-test filter the pricer
   * set (D7), so this chart and the statistics card above it always describe the same rows. Both
   * sources are counted before either is read (D3): a COUNT() costs one query row, while reading
   * 10,000 rows to discover they were too many costs 10,000 - and a LimitException cannot be
   * caught.
   *
   * The two gates are asymmetric and both are honored, neither re-derived here (Ruling 8/9):
   * - bids switch off when LaneTrendQueries.bidSoql/.bidCountSoql return null (they encode
   *   BidSearchQueryBuilder.canMatchBids themselves), and that side's row count is then 0;
   * - quotes have no such builder-side signal, so trendFor skips the quote count and read itself
   *   when req.sourceFilter is BIDS, exactly as LaneSearchService.search() does at its lines 29-32.
   * If both gates fire, every count and read is skipped and this returns an empty-but-valid trend.
   */
  public static LaneTrend trendFor(LaneSearchRequest req) {
    req.validate();
    LaneTrend trend = new LaneTrend();
    trend.currencyIsoCode = req.currencyIsoCode;
    trend.lookbackDays = req.lookbackDays;
    Date windowStart = Date.today().addDays(-req.lookbackDays);
    Date windowStartMonth = Date.newInstance(
      windowStart.year(),
      windowStart.month(),
      1
    );
    trend.monthSpan = monthsBetween(windowStartMonth, Date.today()) + 1;

    Map<String, Pricing_Place__c> places = LaneSearchService.loadPlaces(req);
    Integer cap = rowCapOverride == null ? ROW_CAP : rowCapOverride;
    // Ruling 9: the quote side has no null-returning builder to hook into (unlike bids), so the
    // gate lives here - mirroring LaneSearchService.search(), which skips the query itself when
    // sourceFilter is BIDS.
    Boolean readQuotes = req.sourceFilter != LaneSearchRequest.RowSource.BIDS;

    Integer quoteRows = readQuotes ? countQuotes(req, places) : 0;
    Integer bidRows = countBids(req, places);
    // Ruling 12: the LIMIT is per side (readQuoteSamples/readBidSamples each bind their own
    // :trendRowCap), so nothing was actually dropped unless one side's own count exceeds it -
    // summing both sides against one cap warns even when each side read in full. quoteRows is
    // already 0 when the quote gate is closed (see above), so it can never exceed a positive cap on
    // its own and needs no separate readQuotes guard here.
    trend.truncated = quoteRows > cap || bidRows > cap;

    List<Sample> samples = new List<Sample>();
    if (readQuotes) {
      samples.addAll(readQuoteSamples(req, places, cap));
    }
    samples.addAll(readBidSamples(req, places, cap));

    // Ruling 19: one call, because Rulings 11 (drop what falls outside the window, and count it)
    // and 14 (never blend two currencies on one axis) have exactly one correct order and composing
    // them by hand here is what got that order wrong. LaneTrendScope partitions by window, chooses
    // the currency from what is actually plottable, and counts only that currency's out-of-window
    // rows - so trend.outsideWindow and the points below always describe the same population.
    List<Sample> plotted = LaneTrendScope.narrow(
      trend,
      samples,
      windowStartMonth
    );
    trend.points = bucket(plotted, windowStartMonth);
    LaneTrendSummary.summarise(trend, plotted);
    return trend;
  }

  private static Integer countQuotes(
    LaneSearchRequest req,
    Map<String, Pricing_Place__c> places
  ) {
    Map<String, Object> binds = new Map<String, Object>();
    return Database.countQueryWithBinds(
      LaneTrendQueries.quoteCountSoql(req, binds, places),
      binds,
      AccessLevel.SYSTEM_MODE
    );
  }

  /** Ruling 8: a null bidCountSoql IS the signal that this request can never match a bid - that side's count is 0, not derived here. */
  private static Integer countBids(
    LaneSearchRequest req,
    Map<String, Pricing_Place__c> places
  ) {
    Map<String, Object> binds = new Map<String, Object>();
    String soql = LaneTrendQueries.bidCountSoql(req, binds, places);
    return soql == null
      ? 0
      : Database.countQueryWithBinds(soql, binds, AccessLevel.SYSTEM_MODE);
  }

  private static List<Sample> readQuoteSamples(
    LaneSearchRequest req,
    Map<String, Pricing_Place__c> places,
    Integer cap
  ) {
    List<Sample> samples = new List<Sample>();
    Map<String, Object> binds = new Map<String, Object>{ 'trendRowCap' => cap };
    String soql = LaneTrendQueries.quoteSoql(req, binds, places);
    for (
      rtms__CarrierQuote__c q : (List<rtms__CarrierQuote__c>) Database.queryWithBinds(
        soql,
        binds,
        AccessLevel.SYSTEM_MODE
      )
    ) {
      samples.add(
        new Sample(q.Quote_Date__c, q.rtms__Carrier_Total__c, q.CurrencyIsoCode)
      );
    }
    return samples;
  }

  /** Ruling 8: a null bidSoql IS the signal that this request can never match a bid - no bid samples, not derived here. */
  private static List<Sample> readBidSamples(
    LaneSearchRequest req,
    Map<String, Pricing_Place__c> places,
    Integer cap
  ) {
    List<Sample> samples = new List<Sample>();
    Map<String, Object> binds = new Map<String, Object>{ 'trendRowCap' => cap };
    String soql = LaneTrendQueries.bidSoql(req, binds, places);
    if (soql == null) {
      return samples;
    }
    for (
      Benchmark_Rate__c b : (List<Benchmark_Rate__c>) Database.queryWithBinds(
        soql,
        binds,
        AccessLevel.SYSTEM_MODE
      )
    ) {
      samples.add(new Sample(b.Valid_From__c, b.Rate__c, b.CurrencyIsoCode));
    }
    return samples;
  }

  /** One rate on a date in a currency, which is all a bucket needs from either source. */
  public class Sample {
    public Date sampleDate;
    public Decimal amount;
    public String currencyIsoCode;

    /** Currency-less for Task 1's own bucket() tests, which predate D6/Ruling 14 and do not care. */
    public Sample(Date sampleDate, Decimal amount) {
      this(sampleDate, amount, null);
    }

    public Sample(Date sampleDate, Decimal amount, String currencyIsoCode) {
      this.sampleDate = sampleDate;
      this.amount = amount;
      this.currencyIsoCode = currencyIsoCode;
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
    Date windowStart
  ) {
    Map<String, List<Decimal>> byMonth = new Map<String, List<Decimal>>();
    Map<String, Date> firstOfMonth = new Map<String, Date>();
    for (Sample sample : samples) {
      if (!LaneTrendSummary.isUsable(sample)) {
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
