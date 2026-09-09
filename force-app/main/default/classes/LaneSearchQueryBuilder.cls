/**
 * Builds the dynamic SOQL (with bound values) that LaneSearchService.search() executes. Pure:
 * no SOQL, no DML - just string/condition assembly from a LaneSearchRequest and the places
 * LaneSearchService.loadPlaces() already resolved. Split out of LaneSearchService per the Task 7
 * review ruling ("split the class instead of suppressing"): LaneSearchService now only
 * orchestrates (validate, build, query, dedupe, aggregate); every precision branch that used to
 * push LaneSearchService's class-wide PMD complexity total past 40 lives here instead. Task 7's
 * fix round 1 found this class alone (lane-precision logic plus the filters) still totaled 44
 * against the 40 threshold; fix round 2 moved the currency/mode/equipment/hazmat/market-test/
 * accepted filters into their own class, LaneSearchFilters, called from buildSoql below.
 */
public with sharing class LaneSearchQueryBuilder {
  private static final String SELECT_CLAUSE =
    'SELECT Id, Name, rtms__Load__c, Origin__c, Destination__c, Mode__c, Equipment_Type__c, ' +
    'rtms__Load__r.rtms__Equipment_Type__r.rtms__Category__c, Carrier_Name__c, Carrier_Contact__c, ' +
    'CurrencyIsoCode, rtms__Carrier_Total__c, Quote_Date__c, Hazmat__c, rtms__Accepted__c, Load_Status__c, Ops_Comments__c, ' +
    'CreatedDate FROM rtms__CarrierQuote__c';

  // Brief called this local/parameter "where", but WHERE is a reserved Apex identifier (compiler
  // cascade: "Unexpected token 'where'" etc. across this whole method); renamed to "conditions".
  public static String buildSoql(
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
    LaneSearchFilters.addFilters(req, conditions, binds);
    binds.put('rowLimitPlusOne', req.rowLimit + 1);
    return SELECT_CLAUSE +
      ' WHERE ' +
      String.join(conditions, ' AND ') +
      ' ORDER BY CreatedDate DESC LIMIT :rowLimitPlusOne';
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
}
