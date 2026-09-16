/**
 * Characterization of LaneSearchQueryBuilder.buildSoql: the exact SOQL string and bind names for
 * every lane precision and every filter, including the Market Test exclusion phase 7 added to every search. Phase 8 wrote it before moving the lane-key conditions
 * into LaneKeyMatcher and the mode, equipment and hazmat conditions into LaneLoadFilters, and ran it
 * green on the code as it was then, so the move is proved not to change the lane search by one
 * character (spec D10, R103). buildSoql is pure: the places live only in memory, no record is
 * inserted, and the excluded-contact override stands in for the custom metadata read.
 */
@IsTest
private class LaneSearchQueryBuilderTest {
  // Copied character by character from LaneSearchQueryBuilder.SELECT_CLAUSE.
  private static final String SELECT_CLAUSE =
    'SELECT Id, Name, rtms__Load__c, Origin__c, Destination__c, Mode__c, Equipment_Type__c, ' +
    'rtms__Load__r.rtms__Equipment_Type__r.rtms__Category__c, rtms__Load__r.rtms__Distance_Miles__c, ' +
    'Carrier_Name__c, Carrier_Contact__c, ' +
    'CurrencyIsoCode, rtms__Carrier_Total__c, Quote_Date__c, Hazmat__c, rtms__Accepted__c, Load_Status__c, Ops_Comments__c, ' +
    'Contact_Email__c, Contact_Phone__c, Carrier_Risk__c, Nb_of_loads__c, rtms__Vendor__r.Black_List__c, rtms__Carrier_Service__r.rtms__Transportation_Profile__r.Outstanding_Claim__c, ' +
    'CreatedDate FROM rtms__CarrierQuote__c';
  private static final String WINDOW_90 = ' WHERE CreatedDate = LAST_N_DAYS:90 AND Contact_ID__c NOT IN :excluded';
  private static final String ORDER_AND_LIMIT = ' ORDER BY CreatedDate DESC LIMIT :rowLimitPlusOne';
  private static final String CITY_BOTH_ENDS = ' AND rtms__Load__r.rtms__City_Lane__c LIKE :oCity AND rtms__Load__r.rtms__City_Lane__c LIKE :dCity';
  // Every lane search leaves out Market Test quotes (phase 7); the condition sits between hazmat and accepted.
  private static final String NO_MARKET_TEST = ' AND (NOT Customer_Name__c LIKE :marketTest)';

  private static Map<String, Pricing_Place__c> places() {
    return new Map<String, Pricing_Place__c>{
      'montreal|qc|ca' => new Pricing_Place__c(
        Key__c = 'montreal|qc|ca',
        City__c = 'Montréal',
        Province__c = 'QC',
        Country__c = 'CA',
        Postal_Prefix__c = 'H1A',
        Geolocation__Latitude__s = 45.5019,
        Geolocation__Longitude__s = -73.5674
      ),
      'toronto|on|ca' => new Pricing_Place__c(
        Key__c = 'toronto|on|ca',
        City__c = 'Toronto',
        Province__c = 'ON',
        Country__c = 'CA',
        Postal_Prefix__c = 'M5V',
        Geolocation__Latitude__s = 43.6532,
        Geolocation__Longitude__s = -79.3832
      ),
      'nowhere|zz|ca' => new Pricing_Place__c(
        Key__c = 'nowhere|zz|ca',
        City__c = 'Nowhere',
        Province__c = 'ZZ',
        Country__c = 'CA'
      )
    };
  }

  /** Montréal to Toronto with every field at its declared default (CITY on both ends, 90 days, 2,000 rows). */
  private static LaneSearchRequest req() {
    LaneSearchExclusions.excludedContactIdsOverride = new Set<String>();
    LaneSearchRequest r = new LaneSearchRequest();
    r.originKey = 'montreal|qc|ca';
    r.destinationKey = 'toronto|on|ca';
    return r;
  }

  private static String build(LaneSearchRequest r, Map<String, Object> binds) {
    return LaneSearchQueryBuilder.buildSoql(r, binds, places());
  }

  @IsTest
  static void cityOnBothEndsMatchesTheCityLaneKey() {
    Map<String, Object> binds = new Map<String, Object>();
    String soql = build(req(), binds);
    System.assertEquals(
      SELECT_CLAUSE +
        WINDOW_90 +
        CITY_BOTH_ENDS +
        NO_MARKET_TEST +
        ORDER_AND_LIMIT,
      soql
    );
    System.assertEquals(
      new Set<String>{
        'excluded',
        'oCity',
        'dCity',
        'marketTest',
        'rowLimitPlusOne'
      },
      binds.keySet()
    );
    System.assertEquals(
      new Set<String>{ 'Montréal, QC:%', 'Montreal, QC:%' },
      new Set<String>((List<String>) binds.get('oCity')),
      'the place spelling and its accent-stripped variant, origin side'
    );
    System.assertEquals(
      new List<String>{ '%:Toronto, ON' },
      binds.get('dCity')
    );
    System.assertEquals(new Set<String>(), binds.get('excluded'));
    System.assertEquals(2001, binds.get('rowLimitPlusOne'));
    System.assertEquals('%Market Test%', binds.get('marketTest'));
  }

  @IsTest
  static void provinceOnBothEndsMatchesTheStateLaneKey() {
    LaneSearchRequest r = req();
    r.originPrecision = LaneSearchRequest.Precision.PROVINCE;
    r.destinationPrecision = LaneSearchRequest.Precision.PROVINCE;
    r.lookbackDays = 30;
    r.rowLimit = 50;
    Map<String, Object> binds = new Map<String, Object>();
    String soql = build(r, binds);
    System.assertEquals(
      SELECT_CLAUSE +
        ' WHERE CreatedDate = LAST_N_DAYS:30 AND Contact_ID__c NOT IN :excluded' +
        ' AND rtms__Load__r.rtms__State_Lane__c LIKE :oProv AND rtms__Load__r.rtms__State_Lane__c LIKE :dProv' +
        NO_MARKET_TEST +
        ORDER_AND_LIMIT,
      soql
    );
    System.assertEquals(
      new Set<String>{
        'excluded',
        'oProv',
        'dProv',
        'marketTest',
        'rowLimitPlusOne'
      },
      binds.keySet()
    );
    System.assertEquals('QC:%', binds.get('oProv'));
    System.assertEquals('%:ON', binds.get('dProv'));
    System.assertEquals(51, binds.get('rowLimitPlusOne'));
  }

  @IsTest
  static void zip3TakesTheExplicitPrefixOrThePlacePrefix() {
    LaneSearchRequest r = req();
    r.originKey = null; // an explicit prefix needs no place
    r.originPrecision = LaneSearchRequest.Precision.ZIP3;
    r.originZip3 = 'H2X';
    r.destinationPrecision = LaneSearchRequest.Precision.ZIP3;
    Map<String, Object> binds = new Map<String, Object>();
    String soql = build(r, binds);
    System.assertEquals(
      SELECT_CLAUSE +
        WINDOW_90 +
        ' AND rtms__Load__r.rtms__Zip3_Lane__c LIKE :oZip3 AND rtms__Load__r.rtms__Zip3_Lane__c LIKE :dZip3' +
        NO_MARKET_TEST +
        ORDER_AND_LIMIT,
      soql
    );
    System.assertEquals(
      new Set<String>{
        'excluded',
        'oZip3',
        'dZip3',
        'marketTest',
        'rowLimitPlusOne'
      },
      binds.keySet()
    );
    System.assertEquals('H2X:%', binds.get('oZip3'));
    System.assertEquals(
      '%:M5V',
      binds.get('dZip3'),
      'no explicit destination prefix: the place prefix'
    );

    r = req();
    r.originPrecision = LaneSearchRequest.Precision.ZIP3;
    r.originZip3 = 'H3B';
    binds = new Map<String, Object>();
    build(r, binds);
    System.assertEquals(
      'H3B:%',
      binds.get('oZip3'),
      'an explicit prefix wins over the place prefix H1A'
    );
  }

  @IsTest
  static void aZip3EndWhosePlaceHasNoPrefixNamesTheFieldToPass() {
    LaneSearchRequest r = req();
    r.destinationKey = 'nowhere|zz|ca';
    r.destinationPrecision = LaneSearchRequest.Precision.ZIP3;
    String message;
    try {
      build(r, new Map<String, Object>());
    } catch (LaneSearchException e) {
      message = e.getMessage();
    }
    System.assertEquals(
      'Place nowhere|zz|ca has no postal prefix; pass destinationZip3',
      message
    );
  }

  @IsTest
  static void anEndWithoutAPlaceAddsNoCondition() {
    LaneSearchRequest r = req();
    r.originKey = null;
    r.originPrecision = LaneSearchRequest.Precision.RADIUS;
    r.originRadius = 25;
    Map<String, Object> binds = new Map<String, Object>();
    String soql = build(r, binds);
    System.assertEquals(
      SELECT_CLAUSE +
        WINDOW_90 +
        ' AND rtms__Load__r.rtms__City_Lane__c LIKE :dCity' +
        NO_MARKET_TEST +
        ORDER_AND_LIMIT,
      soql
    );
    System.assertEquals(
      new Set<String>{ 'excluded', 'dCity', 'marketTest', 'rowLimitPlusOne' },
      binds.keySet()
    );

    r = req();
    r.destinationKey = 'unknown|zz|ca'; // not in the map: CITY adds nothing either
    binds = new Map<String, Object>();
    soql = build(r, binds);
    System.assertEquals(
      SELECT_CLAUSE +
        WINDOW_90 +
        ' AND rtms__Load__r.rtms__City_Lane__c LIKE :oCity' +
        NO_MARKET_TEST +
        ORDER_AND_LIMIT,
      soql
    );
    System.assertEquals(
      new Set<String>{ 'excluded', 'oCity', 'marketTest', 'rowLimitPlusOne' },
      binds.keySet()
    );
  }

  @IsTest
  static void radiusOnBothEndsChecksTheStopAccountAndTheStopGeolocation() {
    LaneSearchRequest r = req();
    r.originPrecision = LaneSearchRequest.Precision.RADIUS;
    r.originRadius = 25;
    r.destinationPrecision = LaneSearchRequest.Precision.RADIUS;
    r.destinationRadius = 50;
    Map<String, Object> binds = new Map<String, Object>();
    String soql = build(r, binds);
    System.assertEquals(
      SELECT_CLAUSE +
        WINDOW_90 +
        ' AND (DISTANCE(rtms__Load__r.rtms__First_Stop__r.rtms__Location2__r.ShippingAddress, GEOLOCATION(:oLat, :oLng), \'mi\') < :oRadius' +
        ' OR DISTANCE(rtms__Load__r.rtms__First_Stop__r.rtms__Geolocation__c, GEOLOCATION(:oLat, :oLng), \'mi\') < :oRadius)' +
        ' AND (DISTANCE(rtms__Load__r.rtms__Last_Stop__r.rtms__Location2__r.ShippingAddress, GEOLOCATION(:dLat, :dLng), \'mi\') < :dRadius' +
        ' OR DISTANCE(rtms__Load__r.rtms__Last_Stop__r.rtms__Geolocation__c, GEOLOCATION(:dLat, :dLng), \'mi\') < :dRadius)' +
        NO_MARKET_TEST +
        ORDER_AND_LIMIT,
      soql
    );
    System.assertEquals(
      new Set<String>{
        'excluded',
        'oLat',
        'oLng',
        'oRadius',
        'dLat',
        'dLng',
        'dRadius',
        'marketTest',
        'rowLimitPlusOne'
      },
      binds.keySet()
    );
    System.assertEquals(45.5019, binds.get('oLat'));
    System.assertEquals(-73.5674, binds.get('oLng'));
    System.assertEquals(25, binds.get('oRadius'));
    System.assertEquals(43.6532, binds.get('dLat'));
    System.assertEquals(-79.3832, binds.get('dLng'));
    System.assertEquals(50, binds.get('dRadius'));
  }

  @IsTest
  static void radiusWithoutStopGeolocationChecksTheStopAccountOnly() {
    LaneSearchRequest r = req();
    r.originPrecision = LaneSearchRequest.Precision.RADIUS;
    r.originRadius = 40;
    r.destinationPrecision = LaneSearchRequest.Precision.RADIUS;
    r.destinationRadius = 80;
    r.radiusUnit = LaneSearchRequest.Unit.KM;
    r.includeStopGeolocation = false;
    Map<String, Object> binds = new Map<String, Object>();
    String soql = build(r, binds);
    System.assertEquals(
      SELECT_CLAUSE +
        WINDOW_90 +
        ' AND DISTANCE(rtms__Load__r.rtms__First_Stop__r.rtms__Location2__r.ShippingAddress, GEOLOCATION(:oLat, :oLng), \'km\') < :oRadius' +
        ' AND DISTANCE(rtms__Load__r.rtms__Last_Stop__r.rtms__Location2__r.ShippingAddress, GEOLOCATION(:dLat, :dLng), \'km\') < :dRadius' +
        NO_MARKET_TEST +
        ORDER_AND_LIMIT,
      soql
    );
    System.assertEquals(
      new Set<String>{
        'excluded',
        'oLat',
        'oLng',
        'oRadius',
        'dLat',
        'dLng',
        'dRadius',
        'marketTest',
        'rowLimitPlusOne'
      },
      binds.keySet()
    );
  }

  @IsTest
  static void everyFilterFollowsTheLaneInItsFixedOrder() {
    LaneSearchRequest r = req();
    r.currencyIsoCode = 'CAD';
    r.modes = new List<String>{ 'Truckload' };
    r.equipmentCategories = new List<String>{ 'Van' };
    r.equipmentTypes = new List<String>{ 'Dry Van 53\'' };
    r.hazmatOnly = true;
    r.acceptedFilter = LaneSearchRequest.Accepted.ACCEPTED;
    Map<String, Object> binds = new Map<String, Object>();
    String soql = build(r, binds);
    System.assertEquals(
      SELECT_CLAUSE +
        WINDOW_90 +
        CITY_BOTH_ENDS +
        ' AND CurrencyIsoCode = :currencyCode' +
        ' AND rtms__Load__r.rtms__Mode__r.Name IN :modes' +
        ' AND (rtms__Load__r.rtms__Equipment_Type__r.rtms__Category__c IN :cats OR rtms__Load__r.rtms__Equipment_Type__r.Name IN :types)' +
        ' AND rtms__Load__r.rtms__Hazardous_Materials__c = true' +
        NO_MARKET_TEST +
        ' AND rtms__Accepted__c = true' +
        ORDER_AND_LIMIT,
      soql
    );
    System.assertEquals(
      new Set<String>{
        'excluded',
        'oCity',
        'dCity',
        'currencyCode',
        'modes',
        'cats',
        'types',
        'marketTest',
        'rowLimitPlusOne'
      },
      binds.keySet()
    );
    System.assertEquals('CAD', binds.get('currencyCode'));
    System.assertEquals(r.modes, binds.get('modes'));
    System.assertEquals(r.equipmentCategories, binds.get('cats'));
    System.assertEquals(r.equipmentTypes, binds.get('types'));
    System.assertEquals('%Market Test%', binds.get('marketTest'));
  }

  @IsTest
  static void categoriesAloneTypesAloneAndDeclined() {
    LaneSearchRequest r = req();
    r.equipmentCategories = new List<String>{ 'Van' };
    r.acceptedFilter = LaneSearchRequest.Accepted.DECLINED;
    Map<String, Object> binds = new Map<String, Object>();
    String soql = build(r, binds);
    System.assertEquals(
      SELECT_CLAUSE +
        WINDOW_90 +
        CITY_BOTH_ENDS +
        ' AND rtms__Load__r.rtms__Equipment_Type__r.rtms__Category__c IN :cats' +
        NO_MARKET_TEST +
        ' AND rtms__Accepted__c = false' +
        ORDER_AND_LIMIT,
      soql
    );
    System.assertEquals(
      new Set<String>{
        'excluded',
        'oCity',
        'dCity',
        'cats',
        'marketTest',
        'rowLimitPlusOne'
      },
      binds.keySet()
    );

    r = req();
    r.equipmentTypes = new List<String>{ 'Dry Van 53\'' };
    binds = new Map<String, Object>();
    soql = build(r, binds);
    System.assertEquals(
      SELECT_CLAUSE +
        WINDOW_90 +
        CITY_BOTH_ENDS +
        ' AND rtms__Load__r.rtms__Equipment_Type__r.Name IN :types' +
        NO_MARKET_TEST +
        ORDER_AND_LIMIT,
      soql
    );
    System.assertEquals(
      new Set<String>{
        'excluded',
        'oCity',
        'dCity',
        'types',
        'marketTest',
        'rowLimitPlusOne'
      },
      binds.keySet()
    );
  }

  /**
   * Phase 8: the select reads the two flags CarrierWarning joins, right before
   * CreatedDate, and no longer the Carrier_Att__c formula.
   */
  @IsTest
  static void selectReadsTheWarningFlagsInsteadOfTheFormula() {
    LaneSearchRequest request = new LaneSearchRequest();
    request.validate();
    String soql = LaneSearchQueryBuilder.buildSoql(
      request,
      new Map<String, Object>(),
      new Map<String, Pricing_Place__c>()
    );
    System.assert(
      soql.contains(
        ', Nb_of_loads__c, rtms__Vendor__r.Black_List__c, rtms__Carrier_Service__r.rtms__Transportation_Profile__r.Outstanding_Claim__c, CreatedDate FROM rtms__CarrierQuote__c WHERE '
      ),
      soql
    );
    System.assert(!soql.contains('Carrier_Att__c'), soql);
  }
}
