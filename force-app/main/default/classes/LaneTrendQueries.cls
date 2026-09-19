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
   * @TestVisible so LaneTrendControllerTest can prove getTrend's QueryException arm without an
   * object big enough for the platform to call a query non-selective. Set, and the count query
   * below asks for a column that does not exist, which Database.countQueryWithBinds answers with
   * the same QueryException a three-year RADIUS window on a busy province pair raises in
   * production - and it raises it from the count, which D3 runs first, so the row guard cannot
   * help. camelCase and not final, like LaneTrendService.rowCapOverride.
   */
  @TestVisible
  private static Boolean breakCountForTest = false;

  /**
   * Phase 10: the date, amount and currency of the same quote rows, and nothing else.
   *
   * CreatedDate, not Quote_Date__c (owner decision; the measurements and the reasoning are recorded
   * in the spec's 2026-09-19 amendment). The trend's axis means "when the
   * evidence arrived", and Quote_Date__c does not: it is the formula
   * IF(!ISBLANK(Shipping_Date__c), Shipping_Date__c, DATEVALUE(CreatedDate)) over
   * rtms__Load__r.rtms__Expected_Ship_Date2__c, so a quote on freight that has not shipped yet is
   * dated in the future - 7.0% of PostProduc's quotes over 30 days, concentrated in the current
   * month by construction. The ship date describes the freight; a quote solicited today is evidence
   * about today's market whenever the truck rolls. CreatedDate is also the field the borrowed WHERE
   * already filters on, so what the query admits and what the chart can place are now one field.
   *
   * Ruling 13: DESC, not ASC. When a lane is busy enough for the cap to bite, truncation should cost
   * the oldest months rather than the newest - the recent months are the ones a pricer reads, and a
   * chart that goes quiet on them while the page only says "may be incomplete" is the failure this
   * ordering exists to prevent. bucket() sorts its own month keys, so read order otherwise never
   * matters. No NULLS LAST is needed here, unlike elsewhere in the repo: CreatedDate is never null.
   */
  public static String quoteSoql(
    LaneSearchRequest req,
    Map<String, Object> binds,
    Map<String, Pricing_Place__c> places
  ) {
    return 'SELECT CreatedDate, rtms__Carrier_Total__c, CurrencyIsoCode' +
      ' FROM rtms__CarrierQuote__c WHERE ' +
      LaneSearchQueryBuilder.whereFor(req, binds, places) +
      ' ORDER BY CreatedDate DESC LIMIT :trendRowCap';
  }

  /**
   * Phase 10 D3: one query row, to decide whether the read above fits before running it. It projects
   * no date of its own, and needed no change when the bucketing moved to CreatedDate: the WHERE it
   * borrows has always filtered CreatedDate, which is the whole point of the move - the field that
   * decides which rows are counted is now the field that decides which month they land in.
   */
  public static String quoteCountSoql(
    LaneSearchRequest req,
    Map<String, Object> binds,
    Map<String, Pricing_Place__c> places
  ) {
    if (breakCountForTest == true) {
      return 'SELECT COUNT() FROM rtms__CarrierQuote__c WHERE No_Such_Column__c = 1';
    }
    return 'SELECT COUNT() FROM rtms__CarrierQuote__c WHERE ' +
      LaneSearchQueryBuilder.whereFor(req, binds, places);
  }

  /**
   * Phase 10: bids are bucketed on CreatedDate too, not on Valid_From__c (same owner decision - see
   * quoteSoql for the reasoning). BidSearchService still reports Valid_From__c as a
   * bid row's quote date in the results table, and the bid WHERE still uses it to decide whether a
   * bid is currently valid; neither of those is the trend's axis, which is when the rate was
   * recorded. Keeping both sources on one field is also what makes the two halves of a merged series
   * comparable: a bid dated by its validity period and a quote dated by its creation would have been
   * two different axes on one chart.
   *
   * Null when BidSearchQueryBuilder.canMatchBids(req) is false, mirroring buildSoql's own contract -
   * a request that can never match a bid search (see canMatchBids) must not produce a bid trend
   * either, or the chart would show bid rows the search itself excludes.
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
    return 'SELECT CreatedDate, Rate__c, CurrencyIsoCode' +
      ' FROM Benchmark_Rate__c WHERE ' +
      BidSearchQueryBuilder.whereFor(req, binds, places) +
      ' ORDER BY CreatedDate DESC LIMIT :trendRowCap';
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
