/**
 * Phase 10's own query shapes: the lane trend reads a narrower projection (date, amount, currency)
 * than a search does, but has to match exactly the same rows a search of the same lane would - so
 * each method here borrows the matching search builder's whereFor (LaneSearchQueryBuilder.whereFor
 * for quotes, BidSearchQueryBuilder.whereFor for bids) rather than re-deriving conditions of its
 * own (phase 10 D2). These four methods started out living on the two search builders themselves,
 * but BidSearchQueryBuilder's PMD cyclomatic-complexity total was already 37 of the 40 cap before
 * phase 10 touched it, and each new method's own baseline complexity would have pushed it to 40 -
 * the project's ruling (LaneSearchFilters, MarketTestFilter) is that a class over the cap is split
 * into another class, never suppressed. So the trend's own SELECT, ORDER BY and LIMIT (or its
 * absence, for the COUNT() variants) live here instead, and each search builder keeps owning only
 * its WHERE.
 */
public with sharing class LaneTrendQueries {
  /**
   * Phase 10: the date, amount and currency of the same quote rows, and nothing else.
   *
   * Ruling 13: DESC, not ASC. Ruling 11 drops rows LaneTrendService reads but whose bucketing date
   * falls outside the window, and those out-of-window rows sort oldest - ASC would let them consume
   * LIMIT slots ahead of the newest, in-window rows on a truncated lane, so a busy lane could end up
   * missing its most recent months while the page only says "may be incomplete." DESC keeps the
   * newest rows within the cap; bucket() sorts its own month keys, so read order otherwise never
   * matters.
   */
  public static String quoteSoql(
    LaneSearchRequest req,
    Map<String, Object> binds,
    Map<String, Pricing_Place__c> places
  ) {
    return 'SELECT Quote_Date__c, rtms__Carrier_Total__c, CurrencyIsoCode' +
      ' FROM rtms__CarrierQuote__c WHERE ' +
      LaneSearchQueryBuilder.whereFor(req, binds, places) +
      ' ORDER BY Quote_Date__c DESC LIMIT :trendRowCap';
  }

  /** Phase 10 D3: one query row, to decide whether the read above fits before running it. */
  public static String quoteCountSoql(
    LaneSearchRequest req,
    Map<String, Object> binds,
    Map<String, Pricing_Place__c> places
  ) {
    return 'SELECT COUNT() FROM rtms__CarrierQuote__c WHERE ' +
      LaneSearchQueryBuilder.whereFor(req, binds, places);
  }

  /**
   * Phase 10: bids are dated on Valid_From__c, which BidSearchService already treats as the quote
   * date. Null when BidSearchQueryBuilder.canMatchBids(req) is false, mirroring buildSoql's own
   * contract - a request that can never match a bid search (see canMatchBids) must not produce a
   * bid trend either, or the chart would show bid rows the search itself excludes.
   */
  public static String bidSoql(
    LaneSearchRequest req,
    Map<String, Object> binds,
    Map<String, Pricing_Place__c> places
  ) {
    if (!BidSearchQueryBuilder.canMatchBids(req)) {
      return null;
    }
    // Ruling 13: DESC for the same reason quoteSoql is - see its doc comment.
    return 'SELECT Valid_From__c, Rate__c, CurrencyIsoCode' +
      ' FROM Benchmark_Rate__c WHERE ' +
      BidSearchQueryBuilder.whereFor(req, binds, places) +
      ' ORDER BY Valid_From__c DESC LIMIT :trendRowCap';
  }

  /** As bidSoql: null under the same rule, so a null count is never mistaken for a real zero. */
  public static String bidCountSoql(
    LaneSearchRequest req,
    Map<String, Object> binds,
    Map<String, Pricing_Place__c> places
  ) {
    if (!BidSearchQueryBuilder.canMatchBids(req)) {
      return null;
    }
    return 'SELECT COUNT() FROM Benchmark_Rate__c WHERE ' +
      BidSearchQueryBuilder.whereFor(req, binds, places);
  }
}
