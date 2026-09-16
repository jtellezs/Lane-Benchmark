/**
 * Phase 3: bids (Benchmark_Rate__c) as a second row source for LaneSearchService. Runs the SOQL
 * BidSearchQueryBuilder builds, converts bids to LaneSearchResult.Row (bid != null marks them),
 * and merges them with the quote rows by CreatedDate descending. Lives in its own class so
 * LaneSearchService (already split twice for PMD) stays an orchestrator.
 */
public without sharing class BidSearchService {
  public class Outcome {
    public Boolean truncated = false;
  }

  @SuppressWarnings(
    'PMD.ApexCRUDViolation'
  ) // system mode by design, like LaneSearchService
  public static List<LaneSearchResult.Row> search(
    LaneSearchRequest req,
    Map<String, Pricing_Place__c> places,
    Outcome out
  ) {
    Map<String, Object> binds = new Map<String, Object>();
    String soql = BidSearchQueryBuilder.buildSoql(req, binds, places);
    List<LaneSearchResult.Row> rows = new List<LaneSearchResult.Row>();
    if (soql == null) {
      return rows;
    }
    List<Benchmark_Rate__c> bids = Database.queryWithBinds(
      soql,
      binds,
      AccessLevel.SYSTEM_MODE
    );
    out.truncated = bids.size() > req.rowLimit;
    if (out.truncated) {
      bids.remove(bids.size() - 1);
    }
    for (Benchmark_Rate__c b : bids) {
      rows.add(toRow(b));
    }
    return rows;
  }

  public static LaneSearchResult.Row toRow(Benchmark_Rate__c b) {
    LaneSearchResult.Row r = new LaneSearchResult.Row();
    r.quoteId = b.Id;
    r.quoteName = b.Name;
    r.origin = PlaceNormalizer.cityLaneSide(
      b.Origin_City__c,
      b.Origin_Province__c
    );
    r.destination = PlaceNormalizer.cityLaneSide(
      b.Destination_City__c,
      b.Destination_Province__c
    );
    r.mode = b.Mode__c;
    r.equipment = b.Equipment_Type__c;
    r.equipmentCategory = b.Equipment_Category__c;
    r.carrierName = b.Carrier_Display__c;
    r.contactName = b.Contact_Name__c;
    r.currencyIsoCode = b.CurrencyIsoCode;
    r.carrierTotal = b.Rate__c;
    r.quoteDate = b.Valid_From__c;
    r.hazmat = b.Hazmat__c;
    r.accepted = null;
    r.loadStatus = 'Bid';
    r.opsComments = b.Notes__c;
    r.createdDate = b.CreatedDate;
    r.carrier.contactEmail = b.Contact_Email__c;
    r.carrier.contactPhone = b.Contact_Phone__c;
    // Phase 8: the same warning as a quote row when the bid's carrier account is blacklisted; a bid
    // has no Transportation Profile, so no claim text (spec D5).
    r.carrier.attention = CarrierWarning.text(
      b.Carrier__r?.Black_List__c,
      false
    );
    r.bid = new LaneSearchResult.BidDetail();
    r.bid.rateId = b.Id;
    r.bid.expiresOn = b.Expires_On__c;
    r.bid.status = b.Status__c;
    r.bid.transitDays = b.Transit_Days__c;
    r.bid.fuelSurcharge = b.Fuel_Surcharge__c;
    r.bid.fscIncluded = b.FSC_Included__c;
    return r;
  }

  // Brief called this method "merge", but MERGE is a reserved Apex keyword (the MERGE DML
  // statement), so "public static ... merge(...)" does not compile ("Unexpected token" cascade,
  // the same class of collision documented on LaneSearchRequest's ANY_STATUS/acceptedFilter and
  // LaneSearchQueryBuilder's "conditions"/"endPrecision" renames); renamed to mergeRows. Tasks
  // referencing BidSearchService.merge must call BidSearchService.mergeRows instead.
  /** Both inputs are ordered by createdDate descending (their queries say so); linear merge, capped. */
  public static List<LaneSearchResult.Row> mergeRows(
    List<LaneSearchResult.Row> quotes,
    List<LaneSearchResult.Row> bids,
    Integer rowLimit
  ) {
    List<LaneSearchResult.Row> out = new List<LaneSearchResult.Row>();
    Integer i = 0;
    Integer j = 0;
    while (out.size() < rowLimit && (i < quotes.size() || j < bids.size())) {
      Boolean takeQuote =
        j >= bids.size() ||
        (i < quotes.size() &&
        !isNewer(bids[j].createdDate, quotes[i].createdDate));
      out.add(takeQuote ? quotes[i++] : bids[j++]);
    }
    return out;
  }

  /** true when a is strictly newer than b (null sorts last). */
  private static Boolean isNewer(Datetime a, Datetime b) {
    if (a == null) {
      return false;
    }
    return b == null || a > b;
  }

  public static String fingerprint(LaneSearchResult.Row r) {
    String base =
      String.valueOf(r.carrierTotal) +
      '|' +
      r.carrierName +
      '|' +
      r.origin +
      '|' +
      r.destination +
      '|' +
      r.mode +
      '|' +
      r.equipment;
    return r.bid == null ? base : base + '|bid:' + r.bid.rateId;
  }
}
