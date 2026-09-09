/**
 * Lane search over rtms__CarrierQuote__c. One dynamic SOQL with bound values,
 * built from a LaneSearchRequest. Precisions map onto Revenova's lane keys on
 * the Load (CITY, PROVINCE, ZIP3) or DISTANCE() through the stops (RADIUS).
 */
// Runs without sharing on purpose: pricing benchmarks every team's quotes. Access is gated by the Lane Benchmark permission sets.
// Class-level complexity driven by addEnd's per-precision dispatch (see its own suppression below);
// Task 6 adds the RADIUS branch there before any extraction into smaller helpers is worthwhile.
@SuppressWarnings('PMD.StdCyclomaticComplexity')
public without sharing class LaneSearchService {
  private static final String SELECT_CLAUSE =
    'SELECT Id, Name, rtms__Load__c, Origin__c, Destination__c, Mode__c, Equipment_Type__c, ' +
    'rtms__Load__r.rtms__Equipment_Type__r.rtms__Category__c, Carrier_Name__c, Carrier_Contact__c, ' +
    'CurrencyIsoCode, rtms__Carrier_Total__c, Quote_Date__c, Hazmat__c, rtms__Accepted__c, Load_Status__c, Ops_Comments__c, ' +
    'CreatedDate FROM rtms__CarrierQuote__c';

  @SuppressWarnings(
    'PMD.ApexCRUDViolation'
  ) // system mode by design (see class comment); Database.queryWithBinds also counts as CRUD for PMD
  public static LaneSearchResult search(LaneSearchRequest req) {
    req.validate();
    Map<String, Pricing_Place__c> places = loadPlaces(req);
    Map<String, Object> binds = new Map<String, Object>();
    String soql = buildSoql(req, binds, places);
    Long t0 = System.currentTimeMillis();
    List<rtms__CarrierQuote__c> quotes = Database.queryWithBinds(
      soql,
      binds,
      AccessLevel.SYSTEM_MODE
    );
    LaneSearchResult result = new LaneSearchResult();
    result.elapsedMs = System.currentTimeMillis() - t0;
    result.truncated = quotes.size() > req.rowLimit;
    if (result.truncated) {
      quotes.remove(quotes.size() - 1);
    }
    for (rtms__CarrierQuote__c q : quotes) {
      result.rows.add(toRow(q));
    }
    return result;
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

  // Brief called this local/parameter "where", but WHERE is a reserved Apex identifier (compiler
  // cascade: "Unexpected token 'where'" etc. across this whole method); renamed to "conditions".
  @TestVisible
  private static String buildSoql(
    LaneSearchRequest req,
    Map<String, Object> binds,
    Map<String, Pricing_Place__c> places
  ) {
    List<String> conditions = new List<String>();
    conditions.add(
      'CreatedDate = LAST_N_DAYS:' + String.valueOf(req.lookbackDays)
    ); // validated positive integer, not user text
    binds.put('excluded', PricingDepartmentController.excludedContactIdSet());
    conditions.add('Contact_ID__c NOT IN :excluded');
    addEnd(conditions, binds, req, places, true);
    addEnd(conditions, binds, req, places, false);
    // Task 7 adds currency, modes, equipment, hazmat, market test, accepted here.
    binds.put('rowLimitPlusOne', req.rowLimit + 1);
    return SELECT_CLAUSE +
      ' WHERE ' +
      String.join(conditions, ' AND ') +
      ' ORDER BY CreatedDate DESC LIMIT :rowLimitPlusOne';
  }

  // Brief-specified per-precision dispatch (explicit ZIP3, CITY, PROVINCE, ZIP3-by-place, RADIUS
  // stub); Task 6 adds the real RADIUS branch here before extracting per-precision helpers is
  // worthwhile.
  @SuppressWarnings('PMD.CyclomaticComplexity, PMD.StdCyclomaticComplexity')
  private static void addEnd(
    List<String> conditions,
    Map<String, Object> binds,
    LaneSearchRequest req,
    Map<String, Pricing_Place__c> places,
    Boolean isOrigin
  ) {
    String key = isOrigin ? req.originKey : req.destinationKey;
    LaneSearchRequest.Precision precision = isOrigin
      ? req.originPrecision
      : req.destinationPrecision;
    String explicitZip3 = isOrigin ? req.originZip3 : req.destinationZip3;
    String side = isOrigin ? 'o' : 'd';
    Pricing_Place__c place = String.isBlank(key) ? null : places.get(key);
    if (
      precision == LaneSearchRequest.Precision.ZIP3 &&
      String.isNotBlank(explicitZip3)
    ) {
      binds.put(
        side + 'Zip3',
        isOrigin
          ? escapeLike(explicitZip3) + ':%'
          : '%:' + escapeLike(explicitZip3)
      );
      conditions.add('rtms__Load__r.rtms__Zip3_Lane__c LIKE :' + side + 'Zip3');
      return;
    }
    if (place == null) {
      return; // no constraint on this end
    }
    if (precision == LaneSearchRequest.Precision.CITY) {
      List<String> patterns = new List<String>();
      for (String v : PlaceNormalizer.cityLaneVariants(place)) {
        patterns.add(isOrigin ? escapeLike(v) + ':%' : '%:' + escapeLike(v));
      }
      binds.put(side + 'City', patterns);
      conditions.add('rtms__Load__r.rtms__City_Lane__c LIKE :' + side + 'City');
    } else if (precision == LaneSearchRequest.Precision.PROVINCE) {
      binds.put(
        side + 'Prov',
        isOrigin
          ? escapeLike(place.Province__c) + ':%'
          : '%:' + escapeLike(place.Province__c)
      );
      conditions.add(
        'rtms__Load__r.rtms__State_Lane__c LIKE :' + side + 'Prov'
      );
    } else if (precision == LaneSearchRequest.Precision.ZIP3) {
      if (String.isBlank(place.Postal_Prefix__c)) {
        throw new LaneSearchException(
          'Place ' +
            key +
            ' has no postal prefix; pass ' +
            (isOrigin ? 'originZip3' : 'destinationZip3')
        );
      }
      binds.put(
        side + 'Zip3',
        isOrigin
          ? escapeLike(place.Postal_Prefix__c) + ':%'
          : '%:' + escapeLike(place.Postal_Prefix__c)
      );
      conditions.add('rtms__Load__r.rtms__Zip3_Lane__c LIKE :' + side + 'Zip3');
    } else {
      throw new LaneSearchException(
        'RADIUS precision is implemented in Task 6'
      );
    }
  }

  /** Escapes SOQL LIKE wildcards in user-derived text. */
  @TestVisible
  private static String escapeLike(String s) {
    return s == null
      ? ''
      : s.replace('\\', '\\\\').replace('%', '\\%').replace('_', '\\_');
  }

  private static LaneSearchResult.Row toRow(rtms__CarrierQuote__c q) {
    LaneSearchResult.Row r = new LaneSearchResult.Row();
    r.quoteId = q.Id;
    r.quoteName = q.Name;
    r.loadId = q.rtms__Load__c;
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
    return r;
  }
}
