/**
 * Lane search over rtms__CarrierQuote__c. One dynamic SOQL with bound values,
 * built from a LaneSearchRequest. Precisions map onto Revenova's lane keys on
 * the Load (CITY, PROVINCE, ZIP3) or DISTANCE() through the stops (RADIUS).
 */
// Runs without sharing on purpose: pricing benchmarks every team's quotes. Access is gated by the Lane Benchmark permission sets.
// Task 6 split addEnd's per-precision dispatch into addCity/addProvince/addZip3/addRadius, which
// brought the class below PMD's complexity threshold with no class-level suppression needed at
// the time. Task 7 adds addFilters (itself split into one small helper per filter, so no method
// - including addFilters - trips the per-method complexity threshold) plus collectRows/stats;
// every method stays small, but the class-wide total (a straight sum over all methods, which
// splitting into more methods cannot reduce) crosses PMD's total-complexity ceiling (68 vs. 40).
// Suppressed at the class level rather than left failing CI; see the task 7 report for the PMD
// output this was measured against.
@SuppressWarnings('PMD.CyclomaticComplexity')
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
    collectRows(quotes, result);
    return result;
  }

  /**
   * Dedupes quotes (same fingerprint as PricingDepartmentController.UniqueCarrierQuote, but on
   * rtms__Carrier_Total__c instead of the CAD-converted total, so USD quotes dedupe too) into
   * result.rows/dedupedCount, and rolls the surviving totals up into result.statsByCurrency.
   */
  private static void collectRows(
    List<rtms__CarrierQuote__c> quotes,
    LaneSearchResult result
  ) {
    Set<String> seen = new Set<String>();
    Map<String, List<Decimal>> totalsByCurrency = new Map<String, List<Decimal>>();
    for (rtms__CarrierQuote__c q : quotes) {
      String fingerprint =
        String.valueOf(q.rtms__Carrier_Total__c) +
        '|' +
        q.Carrier_Name__c +
        '|' +
        q.Origin__c +
        '|' +
        q.Destination__c +
        '|' +
        q.Mode__c +
        '|' +
        q.Equipment_Type__c;
      if (seen.contains(fingerprint)) {
        result.dedupedCount++;
        continue;
      }
      seen.add(fingerprint);
      result.rows.add(toRow(q));
      String cur = q.CurrencyIsoCode == null ? 'CAD' : q.CurrencyIsoCode;
      if (!totalsByCurrency.containsKey(cur)) {
        totalsByCurrency.put(cur, new List<Decimal>());
      }
      totalsByCurrency.get(cur)
        .add(q.rtms__Carrier_Total__c == null ? 0 : q.rtms__Carrier_Total__c);
    }
    for (String cur : totalsByCurrency.keySet()) {
      result.statsByCurrency.put(cur, stats(totalsByCurrency.get(cur)));
    }
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
    addEnd(conditions, binds, req, originEnd(req), places);
    addEnd(conditions, binds, req, destinationEnd(req), places);
    addFilters(req, conditions, binds);
    binds.put('rowLimitPlusOne', req.rowLimit + 1);
    return SELECT_CLAUSE +
      ' WHERE ' +
      String.join(conditions, ' AND ') +
      ' ORDER BY CreatedDate DESC LIMIT :rowLimitPlusOne';
  }

  // Task 7's currency/mode/equipment/hazmat/market-test/accepted filters, split out of buildSoql
  // (and further split below, one helper per filter) so no single method carries every branch;
  // addFilters itself stays a small dispatcher with no complexity suppression of its own.
  private static void addFilters(
    LaneSearchRequest req,
    List<String> conditions,
    Map<String, Object> binds
  ) {
    addCurrencyFilter(req, conditions, binds);
    addModeFilter(req, conditions, binds);
    addEquipmentFilter(req, conditions, binds);
    addHazmatFilter(req, conditions);
    addMarketTestFilter(req, conditions, binds);
    addAcceptedFilter(req, conditions);
  }

  private static void addCurrencyFilter(
    LaneSearchRequest req,
    List<String> conditions,
    Map<String, Object> binds
  ) {
    if (String.isNotBlank(req.currencyIsoCode)) {
      binds.put('currencyCode', req.currencyIsoCode);
      conditions.add('CurrencyIsoCode = :currencyCode');
    }
  }

  private static void addModeFilter(
    LaneSearchRequest req,
    List<String> conditions,
    Map<String, Object> binds
  ) {
    if (req.modes != null && !req.modes.isEmpty()) {
      binds.put('modes', req.modes);
      conditions.add('rtms__Load__r.rtms__Mode__r.Name IN :modes');
    }
  }

  private static void addEquipmentFilter(
    LaneSearchRequest req,
    List<String> conditions,
    Map<String, Object> binds
  ) {
    Boolean hasCats =
      req.equipmentCategories != null && !req.equipmentCategories.isEmpty();
    Boolean hasTypes =
      req.equipmentTypes != null && !req.equipmentTypes.isEmpty();
    if (hasCats && hasTypes) {
      binds.put('cats', req.equipmentCategories);
      binds.put('types', req.equipmentTypes);
      conditions.add(
        '(rtms__Load__r.rtms__Equipment_Type__r.rtms__Category__c IN :cats OR rtms__Load__r.rtms__Equipment_Type__r.Name IN :types)'
      );
    } else if (hasCats) {
      binds.put('cats', req.equipmentCategories);
      conditions.add(
        'rtms__Load__r.rtms__Equipment_Type__r.rtms__Category__c IN :cats'
      );
    } else if (hasTypes) {
      binds.put('types', req.equipmentTypes);
      conditions.add('rtms__Load__r.rtms__Equipment_Type__r.Name IN :types');
    }
  }

  private static void addHazmatFilter(
    LaneSearchRequest req,
    List<String> conditions
  ) {
    if (req.hazmatOnly == true) {
      conditions.add('rtms__Load__r.rtms__Hazardous_Materials__c = true');
    }
  }

  private static void addMarketTestFilter(
    LaneSearchRequest req,
    List<String> conditions,
    Map<String, Object> binds
  ) {
    if (req.marketTestOnly == true) {
      binds.put('marketTest', '%Market Test%');
      conditions.add('Customer_Name__c LIKE :marketTest');
    }
  }

  private static void addAcceptedFilter(
    LaneSearchRequest req,
    List<String> conditions
  ) {
    if (req.acceptedFilter == LaneSearchRequest.Accepted.ACCEPTED) {
      conditions.add('rtms__Accepted__c = true');
    } else if (req.acceptedFilter == LaneSearchRequest.Accepted.DECLINED) {
      conditions.add('rtms__Accepted__c = false');
    }
  }

  /**
   * Every per-end value addEnd and its helpers need, resolved once for origin or destination by
   * originEnd()/destinationEnd() below. Bundling these (rather than branching on an isOrigin flag
   * inside each helper) means the origin/destination choice is decided exactly once per search,
   * not re-decided in every helper - see those two builders' doc comment for why that matters for
   * PMD's class-wide complexity total.
   */
  private class LaneEnd {
    String key;
    LaneSearchRequest.Precision precision;
    String explicitZip3;
    Decimal radius;
    String bindPrefix; // 'o' or 'd' - the SOQL bind-variable name prefix for this end
    String stopRel; // relationship path from rtms__CarrierQuote__c to this end's Stop
    String likePrefix; // '' for an origin, '%:' for a destination
    String likeSuffix; // ':%' for an origin, '' for a destination
    String zip3FieldName; // 'originZip3' or 'destinationZip3', for the missing-prefix error
  }

  /**
   * originEnd()/destinationEnd() are the only places that decide "which side": every value they
   * set is a straight assignment, so neither method has a branch of its own. Task 5's single addEnd
   * re-derived each of these per call with its own isOrigin ternary (cyclomatic 18-21, suppressed).
   * Task 6 needed a real RADIUS branch on top of that, which would have pushed the class past PMD's
   * total-complexity threshold; resolving origin vs. destination exactly once here, instead of once
   * per helper, keeps every method below (addEnd, the largest, is at 7) with no suppression needed.
   */
  private static LaneEnd originEnd(LaneSearchRequest req) {
    LaneEnd e = new LaneEnd();
    e.key = req.originKey;
    e.precision = req.originPrecision;
    e.explicitZip3 = req.originZip3;
    e.radius = req.originRadius;
    e.bindPrefix = 'o';
    e.stopRel = 'rtms__Load__r.rtms__First_Stop__r';
    e.likePrefix = '';
    e.likeSuffix = ':%';
    e.zip3FieldName = 'originZip3';
    return e;
  }

  private static LaneEnd destinationEnd(LaneSearchRequest req) {
    LaneEnd e = new LaneEnd();
    e.key = req.destinationKey;
    e.precision = req.destinationPrecision;
    e.explicitZip3 = req.destinationZip3;
    e.radius = req.destinationRadius;
    e.bindPrefix = 'd';
    e.stopRel = 'rtms__Load__r.rtms__Last_Stop__r';
    e.likePrefix = '%:';
    e.likeSuffix = '';
    e.zip3FieldName = 'destinationZip3';
    return e;
  }

  private static void requirePostalPrefix(Pricing_Place__c place, LaneEnd e) {
    if (String.isBlank(place.Postal_Prefix__c)) {
      throw new LaneSearchException(
        'Place ' + e.key + ' has no postal prefix; pass ' + e.zip3FieldName
      );
    }
  }

  // Per-precision dispatch. Task 5 had this as one large method (cyclomatic 18-21, suppressed);
  // Task 6 splits each precision into its own helper below so addEnd stays a small dispatcher and
  // needs no complexity suppression.
  private static void addEnd(
    List<String> conditions,
    Map<String, Object> binds,
    LaneSearchRequest req,
    LaneEnd e,
    Map<String, Pricing_Place__c> places
  ) {
    if (
      e.precision == LaneSearchRequest.Precision.ZIP3 &&
      String.isNotBlank(e.explicitZip3)
    ) {
      addZip3(conditions, binds, e, e.explicitZip3);
      return;
    }
    // places only ever holds non-blank keys (see loadPlaces), and Map.get(null) is a safe miss, so
    // a blank e.key already falls through to null here without a separate blank check.
    Pricing_Place__c place = places.get(e.key);
    if (place == null) {
      return; // no constraint on this end
    }
    if (e.precision == LaneSearchRequest.Precision.CITY) {
      addCity(conditions, binds, e, place);
    } else if (e.precision == LaneSearchRequest.Precision.PROVINCE) {
      addProvince(conditions, binds, e, place);
    } else if (e.precision == LaneSearchRequest.Precision.ZIP3) {
      requirePostalPrefix(place, e);
      addZip3(conditions, binds, e, place.Postal_Prefix__c);
    } else {
      addRadius(conditions, binds, req, e, place);
    }
  }

  /** "value:%" for an origin, "%:value" for a destination - the shared shape of every lane LIKE pattern. */
  private static String laneLikePattern(LaneEnd e, String rawValue) {
    return e.likePrefix + escapeLike(rawValue) + e.likeSuffix;
  }

  private static void addCity(
    List<String> conditions,
    Map<String, Object> binds,
    LaneEnd e,
    Pricing_Place__c place
  ) {
    List<String> patterns = new List<String>();
    for (String v : PlaceNormalizer.cityLaneVariants(place)) {
      patterns.add(laneLikePattern(e, v));
    }
    binds.put(e.bindPrefix + 'City', patterns);
    conditions.add(
      'rtms__Load__r.rtms__City_Lane__c LIKE :' + e.bindPrefix + 'City'
    );
  }

  private static void addProvince(
    List<String> conditions,
    Map<String, Object> binds,
    LaneEnd e,
    Pricing_Place__c place
  ) {
    binds.put(e.bindPrefix + 'Prov', laneLikePattern(e, place.Province__c));
    conditions.add(
      'rtms__Load__r.rtms__State_Lane__c LIKE :' + e.bindPrefix + 'Prov'
    );
  }

  private static void addZip3(
    List<String> conditions,
    Map<String, Object> binds,
    LaneEnd e,
    String prefix
  ) {
    binds.put(e.bindPrefix + 'Zip3', laneLikePattern(e, prefix));
    conditions.add(
      'rtms__Load__r.rtms__Zip3_Lane__c LIKE :' + e.bindPrefix + 'Zip3'
    );
  }

  // Bound decimals inside GEOLOCATION() work through Database.queryWithBinds in this org (API
  // v64.0, PostProduc sandbox, deploy 0AfbZ00000CnnzxSAB); the brief's
  // String.valueOf(decimal.setScale(6)) fallback was not needed.
  private static void addRadius(
    List<String> conditions,
    Map<String, Object> binds,
    LaneSearchRequest req,
    LaneEnd e,
    Pricing_Place__c place
  ) {
    if (
      place.Geolocation__Latitude__s == null ||
      place.Geolocation__Longitude__s == null
    ) {
      throw new LaneSearchException('Place ' + e.key + ' has no coordinates');
    }
    String unit = req.radiusUnit == LaneSearchRequest.Unit.KM ? 'km' : 'mi'; // enum-controlled literal, never user text
    binds.put(e.bindPrefix + 'Lat', place.Geolocation__Latitude__s);
    binds.put(e.bindPrefix + 'Lng', place.Geolocation__Longitude__s);
    binds.put(e.bindPrefix + 'Radius', e.radius);
    String geo =
      'GEOLOCATION(:' +
      e.bindPrefix +
      'Lat, :' +
      e.bindPrefix +
      'Lng)';
    String byAccount =
      'DISTANCE(' +
      e.stopRel +
      '.rtms__Location2__r.ShippingAddress, ' +
      geo +
      ', \'' +
      unit +
      '\') < :' +
      e.bindPrefix +
      'Radius';
    if (req.includeStopGeolocation) {
      String byStop =
        'DISTANCE(' +
        e.stopRel +
        '.rtms__Geolocation__c, ' +
        geo +
        ', \'' +
        unit +
        '\') < :' +
        e.bindPrefix +
        'Radius';
      conditions.add('(' + byAccount + ' OR ' + byStop + ')');
    } else {
      conditions.add(byAccount);
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
