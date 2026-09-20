/**
 * Phase 10, extended by the lane trend windows feature: bucketing a lane's rates by day, week or
 * month - whichever LaneTrendBuckets.unitFor derives from the window (spec W1).
 *
 * Both sources are bucketed on CreatedDate - when the rate was recorded, not when the freight moves
 * (owner decision, recorded in the spec's 2026-09-19 amendment; see LaneTrendQueries.quoteSoql for
 * the measurement and the reasoning). Because that is also the field the borrowed WHERE filters on,
 * every row this class reads is a row the axis can hold.
 *
 * without sharing, like LaneSearchService and BidSearchService, because spec §6 requires the trend
 * to read through the same system-mode path the search uses and to expose no row a search of the
 * same lane would not.
 */
public without sharing class LaneTrendService {
  /**
   * W5: 25,000 per side, on a measurement. A three-year read of the widest search in the org -
   * 11,499 rows - cost 1,554,051 bytes of the 6,000,000 heap and 11,499 of 50,000 query rows, so
   * the old cap of 10,000, not the platform, is what stopped a three-year window. 25,000 covers
   * five years of that search with about twice the margin on both limits.
   */
  public static final Integer ROW_CAP = 25000;
  /** @TestVisible so a test can prove the guard without inserting 25,001 rows. camelCase, not final. */
  @TestVisible
  private static Integer rowCapOverride;

  /**
   * The lane's rates over the request's window, bucketed by the unit LaneTrendBuckets.unitFor
   * derives from it (spec W1).
   *
   * The conditions are the search's own (D2) and therefore carry the market-test filter the pricer
   * set (D7), so this chart and the statistics card above it always describe the same rows. Both
   * sources are counted before either is read (D3): a COUNT() costs one query row, while reading
   * 25,000 rows to discover they were too many costs 25,000 - and a LimitException cannot be
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
    String unit = LaneTrendBuckets.unitFor(req.lookbackDays);
    trend.bucketUnit = unit;
    Date windowStart = Date.today().addDays(-req.lookbackDays);
    Date windowStartBucket = LaneTrendBuckets.startOf(windowStart, unit);
    trend.bucketSpan =
      LaneTrendBuckets.between(windowStartBucket, Date.today(), unit) + 1;

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

    // Ruling 14: one currency, chosen here rather than blended, and named on the trend so the
    // caption says which. Ruling 11's window partition used to run alongside this and is gone: the
    // rows read are dated by the same field the WHERE filtered, so none of them can fall outside the
    // axis - see LaneTrendScope's class comment for why a guard that can never fire was removed
    // rather than kept.
    List<Sample> plotted = LaneTrendScope.narrow(trend, samples);
    trend.points = LaneTrendBuckets.bucket(plotted, windowStartBucket, unit);
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
        new Sample(
          q.CreatedDate.date(),
          q.rtms__Carrier_Total__c,
          q.CurrencyIsoCode
        )
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
      samples.add(
        new Sample(b.CreatedDate.date(), b.Rate__c, b.CurrencyIsoCode)
      );
    }
    return samples;
  }

  /**
   * One rate on a date in a currency, which is all a bucket needs from either source.
   *
   * sampleDate is a Date, because a bucket - day, week or month alike - has no use for a time of
   * day, while both sources' CreatedDate is a Datetime - hence the .date() in the two readers above.
   * That conversion
   * resolves in the running user's time zone, which is the same zone the query's own LAST_N_DAYS
   * boundary is evaluated in, so the day a row is admitted on and the day it is bucketed on agree.
   */
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
}
