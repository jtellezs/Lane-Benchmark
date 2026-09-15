/**
 * The statements Carriers to ask runs (phase 8, spec sections 3 and 8), and from Task 8 the ones
 * Split-lane options runs: the lane conditions on a load (each end through LaneKeyMatcher, the way
 * the first search matched it, a radius end on its place's city key, R83), the state-lane
 * conditions with both stop countries (R102), the grouped carrier quote count and the freight-plan
 * read with its carrier legs (R104). Pure: no query, no DML - strings and binds only, like
 * LaneSearchQueryBuilder. Only the request's place keys, precisions, postal prefixes and mode,
 * equipment and hazmat filters reach a condition; its lookback, currency, accepted and source
 * filters are ignored on purpose (R101), and quote counts leave out Market Test quotes as every
 * lane search does (phase 7, R110). loadPath is 'rtms__Load__r.' on
 * rtms__CarrierQuote__c and rtms__FreightPlanLoad__c rows and '' on rtms__Load__c rows.
 */
public with sharing class LaneQueries {
  /** Pricing_Place__c.Country__c codes and the names stop accounts hold in ShippingCountry. */
  public static final Map<String, String> COUNTRY_NAMES = new Map<String, String>{
    'CA' => 'Canada',
    'US' => 'United States',
    'MX' => 'Mexico'
  };
  /** Carriers per grouped count; the statement asks for one more, so a cut list can be told apart. */
  public static final Integer GROUP_LIMIT = 50;

  private static final String NOT_CANCELLED = 'rtms__Load_Status__c != \'Cancelled\'';
  private static final String QUOTE_COUNT_SELECT =
    'SELECT rtms__Vendor__c, rtms__Vendor__r.Name vname, rtms__Vendor__r.Black_List__c bl, ' +
    'COUNT_DISTINCT(rtms__Load__c) loads, MAX(CreatedDate) lastSeen FROM rtms__CarrierQuote__c WHERE ';
  private static final String QUOTE_COUNT_GROUP =
    ' GROUP BY rtms__Vendor__c, rtms__Vendor__r.Name, rtms__Vendor__r.Black_List__c' +
    ' ORDER BY COUNT_DISTINCT(rtms__Load__c) DESC LIMIT ';
  // Names only (R106): no amount field unless withAmounts, which Carriers to ask never passes.
  private static final String LEG_FIELDS =
    'rtms__Type__c, rtms__Number__c, rtms__Load__c, rtms__Load__r.CreatedDate, ' +
    'rtms__Load__r.rtms__Carrier__c, rtms__Load__r.rtms__Carrier__r.Name, ' +
    'rtms__Load__r.rtms__Carrier__r.Black_List__c, rtms__Load__r.rtms__Load_Status__c';
  private static final String AMOUNT_FIELDS =
    ', rtms__Load__r.rtms__City_Lane__c, rtms__Load__r.rtms__Carrier_Quote_Total__c, ' +
    'rtms__Load__r.rtms__Last_Stop__r.rtms__Location2__r.Name';

  /** The deeper steps never run a radius (R83): a radius end is matched on its place's city key. */
  public static LaneSearchRequest.Precision deepPrecision(
    LaneSearchRequest.Precision p
  ) {
    return p == LaneSearchRequest.Precision.RADIUS
      ? LaneSearchRequest.Precision.CITY
      : p;
  }

  /**
   * The lane's conditions on the load at loadPath: the origin end (binds prefixed 'o'), the
   * destination end ('d'), the mode, equipment and hazmat filters, and a load that is not cancelled.
   * An end with no place and no explicit postal prefix adds no condition.
   */
  public static List<String> laneConditions(
    LaneSearchRequest req,
    Pricing_Place__c origin,
    Pricing_Place__c destination,
    String loadPath,
    Map<String, Object> binds
  ) {
    List<String> conditions = new List<String>();
    addIfAny(
      conditions,
      LaneKeyMatcher.condition(
        loadPath,
        true,
        'o',
        deepPrecision(req.originPrecision),
        origin,
        req.originZip3,
        binds
      )
    );
    addIfAny(
      conditions,
      LaneKeyMatcher.condition(
        loadPath,
        false,
        'd',
        deepPrecision(req.destinationPrecision),
        destination,
        req.destinationZip3,
        binds
      )
    );
    LaneLoadFilters.add(req, loadPath, conditions, binds);
    conditions.add(loadPath + NOT_CANCELLED);
    return conditions;
  }

  /**
   * The state or province lane of the two places (stage 2): the load's rtms__State_Lane__c is
   * "<origin Province__c>:<destination Province__c>", its first stop account is in the origin's
   * country and its last stop account in the destination's (Revenova reuses two-letter state codes
   * across countries, and a blank stop country does not match), then the load filters and not
   * cancelled. null, with nothing bound, when a place has a blank Province__c or a Country__c
   * outside COUNTRY_NAMES.
   */
  public static List<String> stateLaneConditions(
    LaneSearchRequest req,
    Pricing_Place__c origin,
    Pricing_Place__c destination,
    String loadPath,
    Map<String, Object> binds
  ) {
    String originCountry = countryName(origin);
    String destinationCountry = countryName(destination);
    if (
      String.isBlank(origin?.Province__c) ||
      String.isBlank(destination?.Province__c) ||
      originCountry == null ||
      destinationCountry == null
    ) {
      return null;
    }
    binds.put('stateLane', origin.Province__c + ':' + destination.Province__c);
    binds.put('oCountry', originCountry);
    binds.put('dCountry', destinationCountry);
    List<String> conditions = new List<String>{
      loadPath + 'rtms__State_Lane__c = :stateLane',
      loadPath +
      'rtms__First_Stop__r.rtms__Location2__r.ShippingCountry = :oCountry',
      loadPath +
      'rtms__Last_Stop__r.rtms__Location2__r.ShippingCountry = :dCountry'
    };
    LaneLoadFilters.add(req, loadPath, conditions, binds);
    conditions.add(loadPath + NOT_CANCELLED);
    return conditions;
  }

  /**
   * Carrier quotes on the lane grouped by vendor, with the vendor's name and blacklist flag, the
   * distinct loads quoted (or moved, when movedOnly adds rtms__Accepted__c = true) and the latest
   * quote date, most loads first, GROUP_LIMIT + 1 groups at most. Adds the window, the excluded
   * contacts (quotes only, R89), the Market Test exclusion every lane search carries (phase 7, R110)
   * and the intercompany carriers (D6); binds 'excluded', 'marketTest' and 'intercompany'. onLane is
   * copied, so both counts can share it.
   */
  public static String quoteCountSoql(
    List<String> onLane,
    Integer days,
    Boolean movedOnly,
    Map<String, Object> binds
  ) {
    List<String> conditions = new List<String>(onLane);
    conditions.add('CreatedDate = LAST_N_DAYS:' + String.valueOf(days)); // the caller's constant, never user text
    binds.put('excluded', LaneSearchExclusions.excludedContactIdSet());
    conditions.add('Contact_ID__c NOT IN :excluded');
    binds.put('marketTest', '%Market Test%');
    conditions.add('(NOT Customer_Name__c LIKE :marketTest)');
    conditions.add('rtms__Vendor__c != null');
    binds.put('intercompany', IntercompanyCarriers.ids());
    conditions.add('rtms__Vendor__c NOT IN :intercompany');
    if (movedOnly == true) {
      conditions.add('rtms__Accepted__c = true');
    }
    return QUOTE_COUNT_SELECT +
      String.join(conditions, ' AND ') +
      QUOTE_COUNT_GROUP +
      String.valueOf(GROUP_LIMIT + 1);
  }

  /**
   * Freight plans whose customer load matches customerConditions (built with loadPath
   * 'rtms__Load__r.') and was created in the last `days` days, each with every junction row in
   * rtms__Number__c order - the customer row and the carrier legs - and the leg load's carrier,
   * blacklist flag and status. withAmounts adds the leg's city lane, CAD carrier total and last stop
   * account name (split history only). One query: SOQL refuses a semi-join from
   * rtms__FreightPlanLoad__c to itself (R104). customerConditions is copied.
   */
  public static String planSoql(
    List<String> customerConditions,
    Integer days,
    Integer planLimit,
    Boolean withAmounts
  ) {
    List<String> conditions = new List<String>{
      'rtms__Type__c = \'Customer\''
    };
    conditions.addAll(customerConditions);
    conditions.add(
      'rtms__Load__r.CreatedDate = LAST_N_DAYS:' + String.valueOf(days)
    );
    return 'SELECT Id, (SELECT ' +
      LEG_FIELDS +
      (withAmounts == true ? AMOUNT_FIELDS : '') +
      ' FROM rtms__Freight_Plan_Loads__r ORDER BY rtms__Number__c)' +
      ' FROM rtms__FreightPlan__c WHERE Id IN (SELECT rtms__Freight_Plan__c FROM rtms__FreightPlanLoad__c WHERE ' +
      String.join(conditions, ' AND ') +
      ') LIMIT ' +
      String.valueOf(planLimit);
  }

  private static void addIfAny(List<String> conditions, String condition) {
    if (condition != null) {
      conditions.add(condition);
    }
  }

  private static String countryName(Pricing_Place__c place) {
    return place == null ? null : COUNTRY_NAMES.get(place.Country__c);
  }
}
