/**
 * Lane search over rtms__CarrierQuote__c and (phase 3) Benchmark_Rate__c bids. Orchestrates a
 * search: validate the request, resolve places, build the dynamic SOQL for quotes
 * (LaneSearchQueryBuilder.buildSoql), run it, ask BidSearchService for the bid rows, merge both
 * row sources by CreatedDate descending, then dedupe and compute per-currency statistics. See
 * LaneSearchQueryBuilder for how precisions map onto Revenova's lane keys on the Load (CITY,
 * PROVINCE, ZIP3) or DISTANCE() through the stops (RADIUS), and for the
 * currency/mode/equipment/hazmat/accepted filters and the Market Test exclusion; BidSearchQueryBuilder mirrors that
 * for bids. BidSearchService lives in its own class so this stays an orchestrator (already split
 * twice for PMD).
 */
// Runs without sharing on purpose: pricing benchmarks every team's quotes. Access is gated by the Lane Benchmark permission sets.
// Task 7 review ruling: the SOQL-building logic (every precision/filter branch) was extracted
// into LaneSearchQueryBuilder so this class stays small enough that its PMD complexity total
// needs no suppression - see LaneSearchQueryBuilder's class doc.
public without sharing class LaneSearchService {
  @SuppressWarnings(
    'PMD.ApexCRUDViolation'
  ) // system mode by design (see class comment); Database.queryWithBinds also counts as CRUD for PMD
  public static LaneSearchResult search(LaneSearchRequest req) {
    req.validate();
    Map<String, Pricing_Place__c> places = loadPlaces(req);
    Map<String, Object> binds = new Map<String, Object>();
    String soql = LaneSearchQueryBuilder.buildSoql(req, binds, places);
    Long t0 = System.currentTimeMillis();
    // BidSearchQueryBuilder.canMatchBids already drops bids when sourceFilter is LOADS; the
    // mirror image (BIDS excludes quotes) has no query-builder side to hook into, since
    // LaneSearchQueryBuilder has no "can this ever match a load" concept - skip the query here.
    List<rtms__CarrierQuote__c> quotes = req.sourceFilter ==
      LaneSearchRequest.RowSource.BIDS
      ? new List<rtms__CarrierQuote__c>()
      : Database.queryWithBinds(soql, binds, AccessLevel.SYSTEM_MODE);
    LaneSearchResult result = new LaneSearchResult();
    Boolean quotesTruncated = quotes.size() > req.rowLimit;
    if (quotesTruncated) {
      quotes.remove(quotes.size() - 1);
    }
    List<LaneSearchResult.Row> quoteRows = new List<LaneSearchResult.Row>();
    for (rtms__CarrierQuote__c q : quotes) {
      quoteRows.add(toRow(q));
    }
    BidSearchService.Outcome bidOutcome = new BidSearchService.Outcome();
    List<LaneSearchResult.Row> bidRows = BidSearchService.search(
      req,
      places,
      bidOutcome
    );
    result.elapsedMs = (System.currentTimeMillis() - t0).intValue();
    result.truncated =
      quotesTruncated ||
      bidOutcome.truncated ||
      quoteRows.size() + bidRows.size() > req.rowLimit;
    collectRows(
      BidSearchService.mergeRows(quoteRows, bidRows, req.rowLimit),
      result
    );
    return result;
  }

  /**
   * Dedupes rows (a quote's fingerprint is carrier name, origin, destination, mode, equipment
   * and total, on rtms__Carrier_Total__c rather than the CAD-converted total so USD quotes
   * dedupe too; bid
   * rows never collapse - see BidSearchService.fingerprint) into result.rows/dedupedCount, and
   * rolls the surviving totals up into result.statsByCurrency. Phase 7: each currency's
   * ratePerMileMedian comes from the same surviving rows (Bucket.add), and result.medianMiles is
   * TripMilesService.medianMiles over result.rows, which counts each load once however many
   * surviving quotes it has.
   */
  private static void collectRows(
    List<LaneSearchResult.Row> rows,
    LaneSearchResult result
  ) {
    Set<String> seen = new Set<String>();
    Map<String, Bucket> byCurrency = new Map<String, Bucket>();
    for (LaneSearchResult.Row r : rows) {
      String fingerprint = BidSearchService.fingerprint(r);
      if (seen.contains(fingerprint)) {
        result.dedupedCount++;
        continue;
      }
      seen.add(fingerprint);
      result.rows.add(r);
      String cur = r.currencyIsoCode == null ? 'CAD' : r.currencyIsoCode;
      if (!byCurrency.containsKey(cur)) {
        byCurrency.put(cur, new Bucket());
      }
      byCurrency.get(cur).add(r);
    }
    for (String cur : byCurrency.keySet()) {
      Bucket b = byCurrency.get(cur);
      LaneSearchResult.Stats s = stats(b.totals);
      s.ratePerMileMedian = ratePerMileMedian(b.rates);
      result.statsByCurrency.put(cur, s);
    }
    result.medianMiles = TripMilesService.medianMiles(result.rows);
  }

  /**
   * Phase 7: one currency's surviving rows. totals feeds stats() exactly as before (a blank total
   * counts as zero); rates holds carrierTotal / load.miles for the rows where both are above zero,
   * so bids (no miles) and zero totals never pull the rate per mile down. An inner class, so its
   * branches stay out of LaneSearchService's PMD class complexity total.
   */
  private class Bucket {
    List<Decimal> totals = new List<Decimal>();
    List<Decimal> rates = new List<Decimal>();

    void add(LaneSearchResult.Row r) {
      totals.add(r.carrierTotal == null ? 0 : r.carrierTotal);
      Decimal miles = r.load?.miles;
      if (
        r.carrierTotal != null &&
        r.carrierTotal > 0 &&
        miles != null &&
        miles > 0
      ) {
        rates.add(r.carrierTotal / miles);
      }
    }
  }

  /**
   * Phase 7: the median rate per mile at scale 2 whatever the count (odd: the middle rate; even:
   * the mean of the two middle rates); null when no row had both a total and miles above zero.
   */
  @TestVisible
  private static Decimal ratePerMileMedian(List<Decimal> rates) {
    if (rates.isEmpty()) {
      return null;
    }
    rates.sort();
    Integer n = rates.size();
    Decimal middle = Math.mod(n, 2) == 1
      ? rates[n / 2]
      : (rates[n / 2 - 1] + rates[n / 2]) / 2;
    return middle.setScale(2);
  }

  /**
   * count includes zero totals; countNonZero and min/max/avg/median exclude them (matching the
   * phase 0 statistics). median: odd count is the middle value, even count is the mean of the two
   * middle values.
   */
  @TestVisible
  private static LaneSearchResult.Stats stats(List<Decimal> totals) {
    LaneSearchResult.Stats s = new LaneSearchResult.Stats();
    List<Decimal> nonZero = new List<Decimal>();
    for (Decimal t : totals) {
      s.count++;
      if (t != 0) {
        nonZero.add(t);
      }
    }
    s.countNonZero = nonZero.size();
    if (nonZero.isEmpty()) {
      return s;
    }
    nonZero.sort();
    Decimal sum = 0;
    for (Decimal t : nonZero) {
      sum += t;
    }
    s.min = nonZero[0];
    s.max = nonZero[nonZero.size() - 1];
    s.avg = (sum / nonZero.size()).setScale(2);
    Integer n = nonZero.size();
    s.median = Math.mod(n, 2) == 1
      ? nonZero[n / 2]
      : ((nonZero[n / 2 - 1] + nonZero[n / 2]) / 2).setScale(2);
    return s;
  }

  @SuppressWarnings(
    'PMD.ApexCRUDViolation'
  ) // system mode by design (see class comment)
  private static Map<String, Pricing_Place__c> loadPlaces(
    LaneSearchRequest req
  ) {
    Set<String> keys = new Set<String>();
    if (String.isNotBlank(req.originKey)) {
      keys.add(req.originKey);
    }
    if (String.isNotBlank(req.destinationKey)) {
      keys.add(req.destinationKey);
    }
    Map<String, Pricing_Place__c> byKey = new Map<String, Pricing_Place__c>();
    if (keys.isEmpty()) {
      return byKey;
    }
    for (Pricing_Place__c p : [
      SELECT
        Key__c,
        City__c,
        Province__c,
        Country__c,
        Geolocation__Latitude__s,
        Geolocation__Longitude__s,
        Postal_Prefix__c,
        Spellings__c
      FROM Pricing_Place__c
      WHERE Key__c IN :keys
    ]) {
      byKey.put(p.Key__c, p);
    }
    for (String k : keys) {
      if (!byKey.containsKey(k)) {
        throw new LaneSearchException('Unknown place key: ' + k);
      }
    }
    return byKey;
  }

  private static LaneSearchResult.Row toRow(rtms__CarrierQuote__c q) {
    LaneSearchResult.Row r = new LaneSearchResult.Row();
    r.quoteId = q.Id;
    r.quoteName = q.Name;
    r.load.loadId = q.rtms__Load__c;
    r.load.miles = q.rtms__Load__r?.rtms__Distance_Miles__c;
    r.origin = q.Origin__c;
    r.destination = q.Destination__c;
    r.mode = q.Mode__c;
    r.equipment = q.Equipment_Type__c;
    r.equipmentCategory = q.rtms__Load__r
      ?.rtms__Equipment_Type__r
      ?.rtms__Category__c;
    r.carrierName = q.Carrier_Name__c;
    r.contactName = q.Carrier_Contact__c;
    r.currencyIsoCode = q.CurrencyIsoCode;
    r.carrierTotal = q.rtms__Carrier_Total__c;
    r.quoteDate = q.Quote_Date__c;
    r.hazmat = q.Hazmat__c == 'Hazmat';
    r.accepted = q.rtms__Accepted__c;
    r.loadStatus = q.Load_Status__c;
    r.opsComments = q.Ops_Comments__c;
    r.createdDate = q.CreatedDate;
    r.carrier.contactEmail = q.Contact_Email__c;
    r.carrier.contactPhone = q.Contact_Phone__c;
    r.carrier.risk = q.Carrier_Risk__c;
    r.carrier.loadCount = q.Nb_of_loads__c;
    // Phase 8: the vendor account's blacklist flag and the profile's claim flag (spec D5); a quote
    // with no vendor or no carrier service reads both as not set.
    r.carrier.attention = CarrierWarning.text(
      q.rtms__Vendor__r?.Black_List__c,
      q.rtms__Carrier_Service__r
        ?.rtms__Transportation_Profile__r
        ?.Outstanding_Claim__c
    );
    return r;
  }
}
