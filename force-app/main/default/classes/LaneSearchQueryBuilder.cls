/**
 * Builds the dynamic SOQL (with bound values) that LaneSearchService.search() executes. Pure:
 * no SOQL, no DML - just string/condition assembly from a LaneSearchRequest and the places
 * LaneSearchService.loadPlaces() already resolved. Split out of LaneSearchService per the Task 7
 * review ruling ("split the class instead of suppressing"): LaneSearchService now only
 * orchestrates (validate, build, query, dedupe, aggregate); every precision branch that used to
 * push LaneSearchService's class-wide PMD complexity total past 40 lives here instead. Task 7's
 * fix round 1 found this class alone (lane-precision logic plus the filters) still totaled 44
 * against the 40 threshold; fix round 2 moved the currency/mode/equipment/hazmat/
 * accepted filters into their own class, LaneSearchFilters, called from buildSoql below. Phase 8
 * moved the city, province and postal-prefix conditions into LaneKeyMatcher, which the Carriers to
 * ask and Split-lane services share; only the radius (DISTANCE through the stops) stays here.
 * LaneSearchQueryBuilderTest pins the exact SOQL and bind names.
 */
public with sharing class LaneSearchQueryBuilder {
  // Phase 8: the vendor account's blacklist flag and the Transportation Profile's claim flag replace
  // the Carrier_Att__c formula, whose blacklist half read the profile; LaneSearchService.toRow joins
  // them with CarrierWarning.text (spec D5).
  private static final String SELECT_CLAUSE =
    'SELECT Id, Name, rtms__Load__c, Origin__c, Destination__c, Mode__c, Equipment_Type__c, ' +
    'rtms__Load__r.rtms__Equipment_Type__r.rtms__Category__c, rtms__Load__r.rtms__Distance_Miles__c, ' +
    'Carrier_Name__c, Carrier_Contact__c, ' +
    'CurrencyIsoCode, rtms__Carrier_Total__c, Quote_Date__c, Hazmat__c, rtms__Accepted__c, Load_Status__c, Ops_Comments__c, ' +
    'Contact_Email__c, Contact_Phone__c, Carrier_Risk__c, Nb_of_loads__c, ' +
    'rtms__Vendor__r.Black_List__c, rtms__Carrier_Service__r.rtms__Transportation_Profile__r.Outstanding_Claim__c, ' +
    'CreatedDate FROM rtms__CarrierQuote__c';

  public static String buildSoql(
    LaneSearchRequest req,
    Map<String, Object> binds,
    Map<String, Pricing_Place__c> places
  ) {
    binds.put('rowLimitPlusOne', req.rowLimit + 1);
    return SELECT_CLAUSE +
      ' WHERE ' +
      whereFor(req, binds, places) +
      ' ORDER BY CreatedDate DESC LIMIT :rowLimitPlusOne';
  }

  /**
   * The condition text buildSoql uses, without its SELECT, ORDER BY or LIMIT — so the lane trend
   * (LaneTrendQueries) can read the same rows through a narrower projection. Shared rather than
   * re-derived: a trend and a search of the same lane must agree about which quotes belong to it
   * (phase 10 D2), and this is what makes that true by construction rather than by vigilance.
   * Public not for headroom (this class is 16 of PMD's 40-point cap; BidSearchQueryBuilder, at 38,
   * is the one with none) but for symmetry - LaneTrendQueries needs the same entry point on both
   * the quote and the bid side, so both builders expose whereFor the same way even though only
   * the bid side's complexity forced the trend's queries into their own class.
   */
  // Brief called this local/parameter "where", but WHERE is a reserved Apex identifier (compiler
  // cascade: "Unexpected token 'where'" etc. across this whole method); renamed to "conditions".
  public static String whereFor(
    LaneSearchRequest req,
    Map<String, Object> binds,
    Map<String, Pricing_Place__c> places
  ) {
    List<String> conditions = new List<String>();
    conditions.add(
      'CreatedDate = LAST_N_DAYS:' + String.valueOf(req.lookbackDays)
    ); // validated positive integer, not user text
    binds.put('excluded', LaneSearchExclusions.excludedContactIdSet());
    conditions.add('Contact_ID__c NOT IN :excluded');
    addEnd(conditions, binds, req, originEnd(req), places);
    addEnd(conditions, binds, req, destinationEnd(req), places);
    LaneSearchFilters.addFilters(req, conditions, binds);
    return String.join(conditions, ' AND ');
  }

  /**
   * Every per-end value addEnd and addRadius need, resolved once for origin or destination by
   * originEnd()/destinationEnd() below. Bundling these (rather than branching on an isOrigin flag
   * inside each helper) means the origin/destination choice is decided exactly once per search,
   * not re-decided in every helper - see those two builders' doc comment for why that matters for
   * PMD's class-wide complexity total.
   */
  private class LaneEnd {
    String key;
    Boolean isOrigin; // passed to LaneKeyMatcher, which shapes the LIKE pattern and error from it
    LaneSearchRequest.Precision precision;
    String explicitZip3;
    Decimal radius;
    String bindPrefix; // 'o' or 'd' - the SOQL bind-variable name prefix for this end
    String stopRel; // relationship path from rtms__CarrierQuote__c to this end's Stop
  }

  /**
   * originEnd()/destinationEnd() are the only places that decide "which side": every value they
   * set is a straight assignment, so neither method has a branch of its own. Task 5's single addEnd
   * re-derived each of these per call with its own isOrigin ternary (cyclomatic 18-21, suppressed).
   * Task 6 needed a real RADIUS branch on top of that, which would have pushed the class past PMD's
   * total-complexity threshold; resolving origin vs. destination exactly once here, instead of once
   * per helper, keeps every method below (addRadius, the largest, is at 6) with no suppression needed.
   */
  private static LaneEnd originEnd(LaneSearchRequest req) {
    LaneEnd e = new LaneEnd();
    e.key = req.originKey;
    e.isOrigin = true;
    e.precision = req.originPrecision;
    e.explicitZip3 = req.originZip3;
    e.radius = req.originRadius;
    e.bindPrefix = 'o';
    e.stopRel = 'rtms__Load__r.rtms__First_Stop__r';
    return e;
  }

  private static LaneEnd destinationEnd(LaneSearchRequest req) {
    LaneEnd e = new LaneEnd();
    e.key = req.destinationKey;
    e.isOrigin = false;
    e.precision = req.destinationPrecision;
    e.explicitZip3 = req.destinationZip3;
    e.radius = req.destinationRadius;
    e.bindPrefix = 'd';
    e.stopRel = 'rtms__Load__r.rtms__Last_Stop__r';
    return e;
  }

  // Per-precision dispatch. CITY, PROVINCE and ZIP3 (with an explicit prefix or the place's own)
  // go to LaneKeyMatcher, which returns null when the end has no constraint; RADIUS stays here.
  // buildSoql runs after LaneSearchRequest.validate(), which defaults a missing precision to CITY.
  private static void addEnd(
    List<String> conditions,
    Map<String, Object> binds,
    LaneSearchRequest req,
    LaneEnd e,
    Map<String, Pricing_Place__c> places
  ) {
    // places only ever holds non-blank keys (see loadPlaces), and Map.get(null) is a safe miss, so
    // a blank e.key already falls through to null here without a separate blank check.
    Pricing_Place__c place = places.get(e.key);
    if (e.precision != LaneSearchRequest.Precision.RADIUS) {
      String laneKey = LaneKeyMatcher.condition(
        'rtms__Load__r.',
        e.isOrigin,
        e.bindPrefix,
        e.precision,
        place,
        e.explicitZip3,
        binds
      );
      if (laneKey != null) {
        conditions.add(laneKey);
      }
    } else if (place != null) {
      addRadius(conditions, binds, req, e, place);
    }
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
  public static String escapeLike(String s) {
    return s == null
      ? ''
      : s.replace('\\', '\\\\').replace('%', '\\%').replace('_', '\\_');
  }
}
