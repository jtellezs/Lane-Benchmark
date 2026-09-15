@IsTest
private class LaneQueriesTest {
  private static final String NOT_CANCELLED = 'rtms__Load__r.rtms__Load_Status__c != \'Cancelled\'';

  private static Pricing_Place__c place(
    String city,
    String prov,
    String country,
    String prefix
  ) {
    return new Pricing_Place__c(
      City__c = city,
      Province__c = prov,
      Country__c = country,
      Postal_Prefix__c = prefix
    );
  }

  private static Pricing_Place__c montreal() {
    return place('Montreal', 'QC', 'CA', 'H1A');
  }

  private static Pricing_Place__c toronto() {
    return place('Toronto', 'ON', 'CA', 'M5V');
  }

  /** Mode, equipment and hazmat filters, plus every filter the deeper steps ignore (R101). */
  private static LaneSearchRequest filtered() {
    LaneSearchRequest req = new LaneSearchRequest();
    req.modes = new List<String>{ 'Truckload' };
    req.equipmentCategories = new List<String>{ 'Van' };
    req.equipmentTypes = new List<String>{ 'Dry Van 53\'' };
    req.hazmatOnly = true;
    req.currencyIsoCode = 'USD';
    req.lookbackDays = 30;
    req.acceptedFilter = LaneSearchRequest.Accepted.ACCEPTED;
    return req;
  }

  @IsTest
  static void laneConditionsMatchBothEndsAndKeepOnlyTheLoadFilters() {
    Map<String, Object> binds = new Map<String, Object>();
    List<String> conditions = LaneQueries.laneConditions(
      filtered(),
      montreal(),
      toronto(),
      'rtms__Load__r.',
      binds
    );
    System.assertEquals(
      new List<String>{
        'rtms__Load__r.rtms__City_Lane__c LIKE :oCity',
        'rtms__Load__r.rtms__City_Lane__c LIKE :dCity',
        'rtms__Load__r.rtms__Mode__r.Name IN :modes',
        '(rtms__Load__r.rtms__Equipment_Type__r.rtms__Category__c IN :cats OR rtms__Load__r.rtms__Equipment_Type__r.Name IN :types)',
        'rtms__Load__r.rtms__Hazardous_Materials__c = true',
        NOT_CANCELLED
      },
      conditions,
      'both ends, the mode, equipment and hazmat filters and a load that is not cancelled; no currency or accepted condition (quoteCountSoql adds the Market Test exclusion)'
    );
    System.assertEquals(
      new Set<String>{ 'oCity', 'dCity', 'modes', 'cats', 'types' },
      binds.keySet(),
      'no currency bind'
    );
    System.assertEquals(
      new List<String>{ 'Montreal, QC:%' },
      binds.get('oCity')
    );
    System.assertEquals(
      new List<String>{ '%:Toronto, ON' },
      binds.get('dCity')
    );
  }

  @IsTest
  static void laneConditionsOnLoadRowsUseNoPathAndARadiusEndUsesItsCityKey() {
    LaneSearchRequest radiusToProvince = new LaneSearchRequest();
    radiusToProvince.originPrecision = LaneSearchRequest.Precision.RADIUS;
    radiusToProvince.originRadius = 50;
    radiusToProvince.destinationPrecision = LaneSearchRequest.Precision.PROVINCE;
    Map<String, Object> binds = new Map<String, Object>();
    System.assertEquals(
      new List<String>{
        'rtms__City_Lane__c LIKE :oCity',
        'rtms__State_Lane__c LIKE :dProv',
        'rtms__Load_Status__c != \'Cancelled\''
      },
      LaneQueries.laneConditions(
        radiusToProvince,
        montreal(),
        toronto(),
        '',
        binds
      ),
      'a radius end is matched on its city key (R83); loads take no path'
    );
    System.assertEquals(
      new List<String>{ 'Montreal, QC:%' },
      binds.get('oCity')
    );
    System.assertEquals('%:ON', binds.get('dProv'));

    LaneSearchRequest byPostalPrefix = new LaneSearchRequest();
    byPostalPrefix.originPrecision = LaneSearchRequest.Precision.ZIP3;
    byPostalPrefix.destinationPrecision = LaneSearchRequest.Precision.ZIP3;
    byPostalPrefix.destinationZip3 = 'L5T';
    Map<String, Object> zipBinds = new Map<String, Object>();
    System.assertEquals(
      new List<String>{
        'rtms__Load__r.rtms__Zip3_Lane__c LIKE :oZip3',
        'rtms__Load__r.rtms__Zip3_Lane__c LIKE :dZip3',
        NOT_CANCELLED
      },
      LaneQueries.laneConditions(
        byPostalPrefix,
        montreal(),
        toronto(),
        'rtms__Load__r.',
        zipBinds
      )
    );
    System.assertEquals('H1A:%', zipBinds.get('oZip3'), 'the place prefix');
    System.assertEquals(
      '%:L5T',
      zipBinds.get('dZip3'),
      'the explicit prefix wins over the place'
    );
  }

  @IsTest
  static void deepPrecisionTurnsOnlyARadiusIntoACity() {
    System.assertEquals(
      LaneSearchRequest.Precision.CITY,
      LaneQueries.deepPrecision(LaneSearchRequest.Precision.RADIUS)
    );
    System.assertEquals(
      LaneSearchRequest.Precision.CITY,
      LaneQueries.deepPrecision(LaneSearchRequest.Precision.CITY)
    );
    System.assertEquals(
      LaneSearchRequest.Precision.PROVINCE,
      LaneQueries.deepPrecision(LaneSearchRequest.Precision.PROVINCE)
    );
    System.assertEquals(
      LaneSearchRequest.Precision.ZIP3,
      LaneQueries.deepPrecision(LaneSearchRequest.Precision.ZIP3)
    );
    System.assertEquals(null, LaneQueries.deepPrecision(null));
  }

  @IsTest
  static void stateLaneConditionsMatchTheStateLaneAndBothStopCountries() {
    LaneSearchRequest req = new LaneSearchRequest();
    req.modes = new List<String>{ 'Truckload' };
    req.currencyIsoCode = 'CAD';
    Map<String, Object> binds = new Map<String, Object>();
    System.assertEquals(
      new List<String>{
        'rtms__Load__r.rtms__State_Lane__c = :stateLane',
        'rtms__Load__r.rtms__First_Stop__r.rtms__Location2__r.ShippingCountry = :oCountry',
        'rtms__Load__r.rtms__Last_Stop__r.rtms__Location2__r.ShippingCountry = :dCountry',
        'rtms__Load__r.rtms__Mode__r.Name IN :modes',
        NOT_CANCELLED
      },
      LaneQueries.stateLaneConditions(
        req,
        montreal(),
        place('Monterrey', 'NL', 'MX', null),
        'rtms__Load__r.',
        binds
      )
    );
    System.assertEquals('QC:NL', binds.get('stateLane'));
    System.assertEquals('Canada', binds.get('oCountry'));
    System.assertEquals(
      'Mexico',
      binds.get('dCountry'),
      'NL is Nuevo León here, not Newfoundland: the stop country tells them apart'
    );

    Map<String, Object> loadBinds = new Map<String, Object>();
    List<String> onLoads = LaneQueries.stateLaneConditions(
      new LaneSearchRequest(),
      place('Laredo', 'TX', 'US', null),
      toronto(),
      '',
      loadBinds
    );
    System.assertEquals('rtms__State_Lane__c = :stateLane', onLoads[0]);
    System.assertEquals('TX:ON', loadBinds.get('stateLane'));
    System.assertEquals('United States', loadBinds.get('oCountry'));
    System.assertEquals('Canada', loadBinds.get('dCountry'));
  }

  @IsTest
  static void stateLaneConditionsAreNullWithoutAProvinceOrAKnownCountry() {
    LaneSearchRequest req = new LaneSearchRequest();
    Map<String, Object> binds = new Map<String, Object>();
    System.assertEquals(
      null,
      LaneQueries.stateLaneConditions(
        req,
        place('Montreal', ' ', 'CA', null),
        toronto(),
        'rtms__Load__r.',
        binds
      ),
      'blank origin province'
    );
    System.assertEquals(
      null,
      LaneQueries.stateLaneConditions(
        req,
        montreal(),
        place('Toronto', null, 'CA', null),
        'rtms__Load__r.',
        binds
      ),
      'blank destination province'
    );
    System.assertEquals(
      null,
      LaneQueries.stateLaneConditions(
        req,
        place('Paris', 'IF', 'FR', null),
        toronto(),
        'rtms__Load__r.',
        binds
      ),
      'a country outside CA, US and MX'
    );
    System.assertEquals(
      null,
      LaneQueries.stateLaneConditions(
        req,
        montreal(),
        place('Toronto', 'ON', null, null),
        'rtms__Load__r.',
        binds
      ),
      'no country'
    );
    System.assertEquals(
      null,
      LaneQueries.stateLaneConditions(req, null, toronto(), '', binds),
      'no place'
    );
    System.assert(binds.isEmpty(), 'nothing is bound without a state lane');
    System.assertEquals(
      new Map<String, String>{
        'CA' => 'Canada',
        'US' => 'United States',
        'MX' => 'Mexico'
      },
      LaneQueries.COUNTRY_NAMES
    );
  }

  @IsTest
  static void quoteCountSoqlGroupsDistinctLoadsByVendorWithTheRemovalsAndTheCap() {
    LaneSearchExclusions.excludedContactIdsOverride = new Set<String>{
      'an excluded contact'
    };
    // An Account Id that exists nowhere: the statement only binds it.
    Id intercompanyCarrier = Id.valueOf(
      Account.SObjectType.getDescribe().getKeyPrefix() + '000000000000'
    );
    IntercompanyCarriers.idsOverride = new Set<Id>{ intercompanyCarrier };
    List<String> onLane = new List<String>{
      'rtms__Load__r.rtms__City_Lane__c LIKE :oCity'
    };
    Map<String, Object> binds = new Map<String, Object>{
      'oCity' => new List<String>{ 'Montreal, QC:%' }
    };

    String quoted = LaneQueries.quoteCountSoql(onLane, 1095, false, binds);
    String moved = LaneQueries.quoteCountSoql(onLane, 365, true, binds);

    System.assertEquals(
      'SELECT rtms__Vendor__c, rtms__Vendor__r.Name vname, rtms__Vendor__r.Black_List__c bl, ' +
        'COUNT_DISTINCT(rtms__Load__c) loads, MAX(CreatedDate) lastSeen FROM rtms__CarrierQuote__c ' +
        'WHERE rtms__Load__r.rtms__City_Lane__c LIKE :oCity AND CreatedDate = LAST_N_DAYS:1095 ' +
        'AND Contact_ID__c NOT IN :excluded AND (NOT Customer_Name__c LIKE :marketTest) AND rtms__Vendor__c != null AND rtms__Vendor__c NOT IN :intercompany ' +
        'GROUP BY rtms__Vendor__c, rtms__Vendor__r.Name, rtms__Vendor__r.Black_List__c ' +
        'ORDER BY COUNT_DISTINCT(rtms__Load__c) DESC LIMIT 51',
      quoted
    );
    System.assertEquals(
      'SELECT rtms__Vendor__c, rtms__Vendor__r.Name vname, rtms__Vendor__r.Black_List__c bl, ' +
        'COUNT_DISTINCT(rtms__Load__c) loads, MAX(CreatedDate) lastSeen FROM rtms__CarrierQuote__c ' +
        'WHERE rtms__Load__r.rtms__City_Lane__c LIKE :oCity AND CreatedDate = LAST_N_DAYS:365 ' +
        'AND Contact_ID__c NOT IN :excluded AND (NOT Customer_Name__c LIKE :marketTest) AND rtms__Vendor__c != null AND rtms__Vendor__c NOT IN :intercompany ' +
        'AND rtms__Accepted__c = true ' +
        'GROUP BY rtms__Vendor__c, rtms__Vendor__r.Name, rtms__Vendor__r.Black_List__c ' +
        'ORDER BY COUNT_DISTINCT(rtms__Load__c) DESC LIMIT 51',
      moved
    );
    System.assertEquals(
      1,
      onLane.size(),
      'the lane conditions are copied, so both counts share them'
    );
    System.assertEquals(
      new Set<String>{ 'oCity', 'excluded', 'marketTest', 'intercompany' },
      binds.keySet()
    );
    System.assertEquals(
      LaneSearchExclusions.excludedContactIdSet(),
      binds.get('excluded')
    );
    System.assertEquals(IntercompanyCarriers.ids(), binds.get('intercompany'));
    System.assertEquals('%Market Test%', binds.get('marketTest'));
    System.assert(
      ((Set<Id>) binds.get('intercompany')).contains(intercompanyCarrier),
      'the intercompany list is bound as it is'
    );
    System.assertEquals(50, LaneQueries.GROUP_LIMIT);
    System.assert(
      !quoted.contains('Total') && !quoted.contains('Cost'),
      'names only'
    );
  }

  @IsTest
  static void planSoqlReadsTheLegsOfCustomerLoadsOnTheLaneWithoutAmountsUnlessAsked() {
    List<String> customerOnLane = new List<String>{
      'rtms__Load__r.rtms__City_Lane__c LIKE :oCity',
      NOT_CANCELLED
    };
    String withoutAmounts = LaneQueries.planSoql(
      customerOnLane,
      1095,
      500,
      false
    );
    String withAmounts = LaneQueries.planSoql(customerOnLane, 365, 1000, true);
    System.assertEquals(
      'SELECT Id, (SELECT rtms__Type__c, rtms__Number__c, rtms__Load__c, rtms__Load__r.CreatedDate, ' +
        'rtms__Load__r.rtms__Carrier__c, rtms__Load__r.rtms__Carrier__r.Name, ' +
        'rtms__Load__r.rtms__Carrier__r.Black_List__c, rtms__Load__r.rtms__Load_Status__c ' +
        'FROM rtms__Freight_Plan_Loads__r ORDER BY rtms__Number__c) FROM rtms__FreightPlan__c ' +
        'WHERE Id IN (SELECT rtms__Freight_Plan__c FROM rtms__FreightPlanLoad__c ' +
        'WHERE rtms__Type__c = \'Customer\' AND rtms__Load__r.rtms__City_Lane__c LIKE :oCity ' +
        'AND rtms__Load__r.rtms__Load_Status__c != \'Cancelled\' ' +
        'AND rtms__Load__r.CreatedDate = LAST_N_DAYS:1095) LIMIT 500',
      withoutAmounts
    );
    System.assert(
      !withoutAmounts.contains('Total') && !withoutAmounts.contains('Cost'),
      'Carriers to ask never selects an amount (R106)'
    );
    System.assertEquals(
      'SELECT Id, (SELECT rtms__Type__c, rtms__Number__c, rtms__Load__c, rtms__Load__r.CreatedDate, ' +
        'rtms__Load__r.rtms__Carrier__c, rtms__Load__r.rtms__Carrier__r.Name, ' +
        'rtms__Load__r.rtms__Carrier__r.Black_List__c, rtms__Load__r.rtms__Load_Status__c, ' +
        'rtms__Load__r.rtms__City_Lane__c, rtms__Load__r.rtms__Carrier_Quote_Total__c, ' +
        'rtms__Load__r.rtms__Last_Stop__r.rtms__Location2__r.Name ' +
        'FROM rtms__Freight_Plan_Loads__r ORDER BY rtms__Number__c) FROM rtms__FreightPlan__c ' +
        'WHERE Id IN (SELECT rtms__Freight_Plan__c FROM rtms__FreightPlanLoad__c ' +
        'WHERE rtms__Type__c = \'Customer\' AND rtms__Load__r.rtms__City_Lane__c LIKE :oCity ' +
        'AND rtms__Load__r.rtms__Load_Status__c != \'Cancelled\' ' +
        'AND rtms__Load__r.CreatedDate = LAST_N_DAYS:365) LIMIT 1000',
      withAmounts
    );
    System.assertEquals(
      2,
      customerOnLane.size(),
      'the customer conditions are copied'
    );
  }

  /**
   * Tests see none of the org's quotes or plans, so each statement returns nothing: running them
   * proves the dynamic SOQL and its binds compile, the binds inside the plan read's semi-join
   * included, whichever way Task 1 proved freight plans reach the tests.
   */
  @IsTest
  static void everyStatementRunsWithItsBinds() {
    LaneSearchExclusions.excludedContactIdsOverride = new Set<String>();
    IntercompanyCarriers.idsOverride = new Set<Id>();
    // The real plan query, not Task 1's in-memory rows (this test builds no plan fixture).
    FreightPlanReader.rowsOverride = null;
    Map<String, Object> laneBinds = new Map<String, Object>();
    List<String> onLane = LaneQueries.laneConditions(
      filtered(),
      montreal(),
      toronto(),
      'rtms__Load__r.',
      laneBinds
    );
    Map<String, Object> lanePlanBinds = laneBinds.clone();
    Map<String, Object> stateBinds = new Map<String, Object>();
    List<String> onStateLane = LaneQueries.stateLaneConditions(
      filtered(),
      montreal(),
      toronto(),
      'rtms__Load__r.',
      stateBinds
    );
    Map<String, Object> statePlanBinds = stateBinds.clone();
    Test.startTest();
    List<AggregateResult> quoted = Database.queryWithBinds(
      LaneQueries.quoteCountSoql(onLane, 1095, false, laneBinds),
      laneBinds,
      AccessLevel.SYSTEM_MODE
    );
    List<AggregateResult> movedOnStateLane = Database.queryWithBinds(
      LaneQueries.quoteCountSoql(onStateLane, 365, true, stateBinds),
      stateBinds,
      AccessLevel.SYSTEM_MODE
    );
    List<rtms__FreightPlan__c> lanePlans = FreightPlanReader.read(
      LaneQueries.planSoql(onLane, 1095, 500, false),
      lanePlanBinds
    );
    List<rtms__FreightPlan__c> statePlans = FreightPlanReader.read(
      LaneQueries.planSoql(onStateLane, 365, 1000, true),
      statePlanBinds
    );
    Test.stopTest();
    System.assertEquals(0, quoted.size(), 'the lane quote count ran');
    System.assertEquals(
      0,
      movedOnStateLane.size(),
      'the state-lane moved count ran'
    );
    System.assertEquals(0, lanePlans.size(), 'the lane plan read ran');
    System.assertEquals(
      0,
      statePlans.size(),
      'the state-lane plan read with amounts ran'
    );
  }
}
