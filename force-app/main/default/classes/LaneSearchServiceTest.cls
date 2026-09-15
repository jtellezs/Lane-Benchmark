@IsTest
private class LaneSearchServiceTest {
  private static Pricing_Place__c place(
    String city,
    String prov,
    String country,
    Decimal lat,
    Decimal lng,
    String prefix,
    String spellings
  ) {
    return new Pricing_Place__c(
      Name = city + ', ' + prov,
      Key__c = PlaceNormalizer.key(city, prov, country),
      City__c = city,
      Province__c = prov,
      Country__c = country,
      Geolocation__Latitude__s = lat,
      Geolocation__Longitude__s = lng,
      Postal_Prefix__c = prefix,
      Spellings__c = spellings,
      Active__c = true
    );
  }

  private static LaneSearchRequest req(String originKey, String destKey) {
    LaneSearchRequest r = new LaneSearchRequest();
    r.originKey = originKey;
    r.destinationKey = destKey;
    return r;
  }

  /** Graph + places + two loads: Montreal->Toronto (quote 1000 CAD) and Laval->Toronto (quote 2000 CAD). */
  private class Fixture {
    PricingTestDataFactory.Graph g;
    rtms__Load__c mtlTor;
    rtms__Load__c lavalTor;
    Account laval;
  }

  private static Fixture fixture() {
    Fixture f = new Fixture();
    f.g = PricingTestDataFactory.createGraph();
    f.laval = PricingTestDataFactory.createLocation(
      'Laval Co',
      'Laval',
      'Quebec',
      'Canada',
      'H7P 1T2',
      45.6066,
      -73.7124
    );
    // The place carries ONLY the accented spelling; the factory writes "Montreal, QC" on the load,
    // so a CITY match here can only come from cityLaneVariants' accent-stripped variant.
    insert new List<Pricing_Place__c>{
      place('Montréal', 'QC', 'CA', 45.5019, -73.5674, 'H1A', null),
      place('Laval', 'QC', 'CA', 45.6066, -73.7124, 'H7P', null),
      place('Toronto', 'ON', 'CA', 43.6532, -79.3832, 'A1A', null)
    };
    LaneSearchExclusions.excludedContactIdsOverride = new Set<String>();
    return f;
  }

  private static void createLoadsAndQuotes(Fixture f) {
    f.mtlTor = PricingTestDataFactory.createLoad(
      f.g,
      f.g.originLocation,
      f.g.destinationLocation
    );
    f.lavalTor = PricingTestDataFactory.createLoad(
      f.g,
      f.laval,
      f.g.destinationLocation
    );
    insert new List<rtms__CarrierQuote__c>{
      PricingTestDataFactory.buildQuote(f.g, f.mtlTor, 1000),
      PricingTestDataFactory.buildQuote(f.g, f.lavalTor, 2000)
    };
  }

  @IsTest
  static void cityPrecisionMatchesOnlyThatCityAndToleratesAccents() {
    Fixture f = fixture();
    Test.startTest();
    createLoadsAndQuotes(f);
    // The place's only spelling is "Montréal"; the load says "Montreal, QC".
    LaneSearchResult r = LaneSearchService.search(
      req('montreal|qc|ca', 'toronto|on|ca')
    );
    Test.stopTest();
    System.assertEquals(1, r.rows.size(), 'only Montreal->Toronto');
    System.assertEquals(1000, r.rows[0].carrierTotal);
    System.assertEquals('CAD', r.rows[0].currencyIsoCode);
    System.assertEquals('Test Carrier', r.rows[0].carrierName);
    System.assertEquals(
      'quote.contact@example.invalid',
      r.rows[0].carrier.contactEmail
    );
    System.assertEquals('514-555-0100', r.rows[0].carrier.contactPhone);
    System.assertEquals(
      'Acceptable',
      r.rows[0].carrier.risk,
      'from rtms__Company_Risk__c on the transportation profile'
    );
    System.assertNotEquals(
      null,
      r.rows[0].carrier.loadCount,
      'from the vendor account Number_of_Loads__c (BlankAsZero formula)'
    );
    System.assert(
      String.isBlank(r.rows[0].carrier.attention),
      'clean profile (no BlackList__c/Outstanding_Claim__c) has no attention flags'
    );
  }

  @IsTest
  static void provincePrecisionMatchesBothQuebecOrigins() {
    Fixture f = fixture();
    Test.startTest();
    createLoadsAndQuotes(f);
    LaneSearchRequest q = req('montreal|qc|ca', 'toronto|on|ca');
    q.originPrecision = LaneSearchRequest.Precision.PROVINCE;
    LaneSearchResult r = LaneSearchService.search(q);
    Test.stopTest();
    System.assertEquals(2, r.rows.size());
  }

  @IsTest
  static void zip3PrecisionUsesThePlacePrefixOrAnExplicitOne() {
    Fixture f = fixture();
    Test.startTest();
    createLoadsAndQuotes(f);
    LaneSearchRequest q = req('laval|qc|ca', null);
    q.originPrecision = LaneSearchRequest.Precision.ZIP3;
    LaneSearchResult byPlace = LaneSearchService.search(q);
    LaneSearchRequest q2 = req(null, null);
    q2.originPrecision = LaneSearchRequest.Precision.ZIP3;
    // Brief said 'H1A' (Montreal's real prefix), but the graph's default origin location is
    // geocoded with the generic test postal 'A1A 1A1' (see PricingTestDataFactory.location()),
    // so mtlTor's actual rtms__Zip3_Lane__c is "A1A:A1A", not "H1A:...". 'A1A' is the prefix that
    // actually reaches the load; verified via debug log 07LbZ00000FhO1iUAF.
    q2.originZip3 = 'A1A';
    LaneSearchResult explicit = LaneSearchService.search(q2);
    Test.stopTest();
    System.assertEquals(1, byPlace.rows.size());
    System.assertEquals(2000, byPlace.rows[0].carrierTotal);
    System.assertEquals(1, explicit.rows.size());
    System.assertEquals(1000, explicit.rows[0].carrierTotal);
  }

  @IsTest
  static void blankEndsMeanNoConstraintAndRowsAreNewestFirst() {
    Fixture f = fixture();
    // One load, two quotes: Test.setCreatedDate() is rejected once the test context has started,
    // and a single createLoad() fits the un-reset governor budget (see the factory's class doc).
    f.mtlTor = PricingTestDataFactory.createLoad(
      f.g,
      f.g.originLocation,
      f.g.destinationLocation
    );
    rtms__CarrierQuote__c older = PricingTestDataFactory.buildQuote(
      f.g,
      f.mtlTor,
      1000
    );
    rtms__CarrierQuote__c newer = PricingTestDataFactory.buildQuote(
      f.g,
      f.mtlTor,
      2000
    );
    insert new List<rtms__CarrierQuote__c>{ older, newer };
    Test.setCreatedDate(older.Id, Datetime.now().addDays(-10));
    Test.setCreatedDate(newer.Id, Datetime.now().addDays(-1));
    Test.startTest();
    LaneSearchResult r = LaneSearchService.search(req(null, null));
    Test.stopTest();
    System.assertEquals(2, r.rows.size());
    System.assertEquals(false, r.truncated);
    System.assertEquals(
      2000,
      r.rows[0].carrierTotal,
      'ORDER BY CreatedDate DESC puts the newer quote first'
    );
    System.assert(
      r.rows[0].createdDate > r.rows[1].createdDate,
      'the row carries the date it is ordered by'
    );
  }

  @IsTest
  static void invalidRequestsThrow() {
    fixture();
    LaneSearchRequest bad = req('nowhere|zz|zz', null);
    try {
      LaneSearchService.search(bad);
      System.assert(false, 'unknown key must throw');
    } catch (LaneSearchException e) {
      System.assert(e.getMessage().contains('nowhere|zz|zz'), e.getMessage());
    }
    LaneSearchRequest neg = req(null, null);
    neg.lookbackDays = 0;
    try {
      LaneSearchService.search(neg);
      System.assert(false, 'lookback must be positive');
    } catch (LaneSearchException e) {
      System.assert(e.getMessage().contains('lookbackDays'), e.getMessage());
    }
    LaneSearchRequest noRadius = req('montreal|qc|ca', null);
    noRadius.originPrecision = LaneSearchRequest.Precision.RADIUS;
    try {
      LaneSearchService.search(noRadius);
      System.assert(false, 'radius required');
    } catch (LaneSearchException e) {
      System.assert(e.getMessage().contains('originRadius'), e.getMessage());
    }
  }

  /**
   * Not in the brief: added because this org enforces per-class 75% coverage under
   * RunSpecifiedTests (deploy 0AfbZ00000CneztSAB's codeCoverageWarnings), and the brief's five
   * tests alone left LaneSearchRequest under the gate. rowLimit/currencyIsoCode/destinationRadius
   * are real validate() branches the brief wrote but never exercised.
   */
  @IsTest
  static void validateRejectsBadRowLimitCurrencyAndDestinationRadius() {
    LaneSearchRequest badRowLimit = req(null, null);
    badRowLimit.rowLimit = 0;
    try {
      LaneSearchService.search(badRowLimit);
      System.assert(false, 'rowLimit must be positive');
    } catch (LaneSearchException e) {
      System.assert(e.getMessage().contains('rowLimit'), e.getMessage());
    }

    LaneSearchRequest badCurrency = req(null, null);
    badCurrency.currencyIsoCode = 'EUR';
    try {
      LaneSearchService.search(badCurrency);
      System.assert(false, 'currencyIsoCode must be CAD, USD or null');
    } catch (LaneSearchException e) {
      System.assert(e.getMessage().contains('currencyIsoCode'), e.getMessage());
    }

    LaneSearchRequest noDestRadius = req('montreal|qc|ca', 'toronto|on|ca');
    noDestRadius.destinationPrecision = LaneSearchRequest.Precision.RADIUS;
    try {
      LaneSearchService.search(noDestRadius);
      System.assert(false, 'destination radius required');
    } catch (LaneSearchException e) {
      System.assert(
        e.getMessage().contains('destinationRadius'),
        e.getMessage()
      );
    }

    // Blank is not a bad currency: it means "both", the same as null.
    LaneSearchRequest blankCurrency = req(null, null);
    blankCurrency.currencyIsoCode = '   ';
    LaneSearchService.search(blankCurrency);

    LaneSearchRequest badZip3 = req(null, null);
    badZip3.originPrecision = LaneSearchRequest.Precision.ZIP3;
    badZip3.originZip3 = 'H1A2';
    try {
      LaneSearchService.search(badZip3);
      System.assert(false, 'originZip3 must be exactly 3 characters');
    } catch (LaneSearchException e) {
      System.assert(e.getMessage().contains('originZip3'), e.getMessage());
    }

    LaneSearchRequest lowerZip3 = req(null, null);
    lowerZip3.destinationPrecision = LaneSearchRequest.Precision.ZIP3;
    lowerZip3.destinationZip3 = ' h1a ';
    LaneSearchService.search(lowerZip3);
    System.assertEquals(
      'H1A',
      lowerZip3.destinationZip3,
      'a valid prefix is trimmed and uppercased in place'
    );
  }

  /**
   * Every precision has to look at the correct side of Revenova's lane key, so each of these
   * asserts a count that differs by end against the same two loads (Montreal->Toronto and
   * Laval->Toronto): a request that matched both ends the same way would fail all four.
   */
  @IsTest
  static void destinationEndMatchesTheOtherSideOfTheProvinceAndZip3Lanes() {
    Fixture f = fixture();
    Test.startTest();
    createLoadsAndQuotes(f);
    LaneSearchRequest qcOrigin = req('montreal|qc|ca', null);
    qcOrigin.originPrecision = LaneSearchRequest.Precision.PROVINCE;
    LaneSearchRequest qcDestination = req(null, 'montreal|qc|ca');
    qcDestination.destinationPrecision = LaneSearchRequest.Precision.PROVINCE;
    LaneSearchRequest zipOrigin = req('toronto|on|ca', null);
    zipOrigin.originPrecision = LaneSearchRequest.Precision.ZIP3;
    LaneSearchRequest zipDestination = req(null, 'toronto|on|ca');
    zipDestination.destinationPrecision = LaneSearchRequest.Precision.ZIP3;
    LaneSearchResult qcFrom = LaneSearchService.search(qcOrigin);
    LaneSearchResult qcTo = LaneSearchService.search(qcDestination);
    LaneSearchResult zipFrom = LaneSearchService.search(zipOrigin);
    LaneSearchResult zipTo = LaneSearchService.search(zipDestination);
    Test.stopTest();
    System.assertEquals(2, qcFrom.rows.size(), 'both loads leave Quebec');
    System.assertEquals(
      0,
      qcTo.rows.size(),
      'neither load delivers in Quebec: "QC:%" must not match "%:QC"'
    );
    // Toronto's place prefix is A1A, the generic test postal the factory geocodes its own
    // locations with, so it is the origin prefix of Montreal->Toronto and the destination prefix
    // of both loads.
    System.assertEquals(1, zipFrom.rows.size(), 'only "A1A:..." matches');
    System.assertEquals(1000, zipFrom.rows[0].carrierTotal);
    System.assertEquals(2, zipTo.rows.size(), 'both loads end in "...:A1A"');
  }

  @IsTest
  static void destinationRadiusMeasuresFromTheDeliveryEnd() {
    Fixture f = fixture();
    Test.startTest();
    createLoadsAndQuotes(f);
    LaneSearchRequest fromToronto = req('toronto|on|ca', null);
    fromToronto.originPrecision = LaneSearchRequest.Precision.RADIUS;
    fromToronto.originRadius = 25;
    LaneSearchRequest toToronto = req(null, 'toronto|on|ca');
    toToronto.destinationPrecision = LaneSearchRequest.Precision.RADIUS;
    toToronto.destinationRadius = 25;
    LaneSearchResult origin = LaneSearchService.search(fromToronto);
    LaneSearchResult destination = LaneSearchService.search(toToronto);
    Test.stopTest();
    System.assertEquals(
      0,
      origin.rows.size(),
      'neither load picks up within 25 mi of Toronto'
    );
    System.assertEquals(
      2,
      destination.rows.size(),
      'both loads deliver in Toronto'
    );
  }

  /**
   * A place that never got coordinates or a postal prefix (a location account with neither) has to
   * say so rather than silently searching without that end's constraint. Both throws happen while
   * the SOQL is being built, so no load is needed.
   */
  @IsTest
  static void placesWithoutCoordinatesOrAPostalPrefixThrow() {
    fixture();
    insert place('Nowhere', 'ZZ', 'CA', null, null, null, null);

    LaneSearchRequest noCoordinates = req('nowhere|zz|ca', null);
    noCoordinates.originPrecision = LaneSearchRequest.Precision.RADIUS;
    noCoordinates.originRadius = 25;
    try {
      LaneSearchService.search(noCoordinates);
      System.assert(
        false,
        'a place with no coordinates cannot be a radius center'
      );
    } catch (LaneSearchException e) {
      System.assert(
        e.getMessage().contains('has no coordinates'),
        e.getMessage()
      );
    }

    LaneSearchRequest noPrefix = req(null, 'nowhere|zz|ca');
    noPrefix.destinationPrecision = LaneSearchRequest.Precision.ZIP3;
    try {
      LaneSearchService.search(noPrefix);
      System.assert(false, 'a place with no postal prefix cannot drive ZIP3');
    } catch (LaneSearchException e) {
      System.assert(
        e.getMessage().contains('has no postal prefix'),
        e.getMessage()
      );
      System.assert(
        e.getMessage().contains('destinationZip3'),
        'the message names the field that would fix it: ' + e.getMessage()
      );
    }
  }

  /** LIKE wildcards in a place's own spelling must not widen the search. */
  @IsTest
  static void escapeLikeNeutralizesWildcards() {
    System.assertEquals(
      'a\\%b\\_c',
      LaneSearchQueryBuilder.escapeLike('a%b_c')
    );
    System.assertEquals(
      '100\\% Pure',
      LaneSearchQueryBuilder.escapeLike('100% Pure')
    );
    System.assertEquals(
      'a\\\\b',
      LaneSearchQueryBuilder.escapeLike('a\\b'),
      'the escape character itself is escaped first'
    );
    System.assertEquals('', LaneSearchQueryBuilder.escapeLike(null));
    System.assertEquals(
      'Montreal, QC',
      LaneSearchQueryBuilder.escapeLike('Montreal, QC'),
      'ordinary text is untouched'
    );
  }

  @IsTest
  static void radiusPrecisionFindsNearbyOriginsAndRespectsTheRadius() {
    Fixture f = fixture();
    Test.startTest();
    createLoadsAndQuotes(f); // Montreal and Laval (about 10 mi apart) -> Toronto
    LaneSearchRequest wide = req('montreal|qc|ca', 'toronto|on|ca');
    wide.originPrecision = LaneSearchRequest.Precision.RADIUS;
    wide.originRadius = 25;
    LaneSearchResult both = LaneSearchService.search(wide);
    LaneSearchRequest tight = req('montreal|qc|ca', 'toronto|on|ca');
    tight.originPrecision = LaneSearchRequest.Precision.RADIUS;
    tight.originRadius = 3;
    LaneSearchResult onlyMtl = LaneSearchService.search(tight);
    Test.stopTest();
    System.assertEquals(
      2,
      both.rows.size(),
      'Laval is within 25 mi of Montreal'
    );
    System.assertEquals(1, onlyMtl.rows.size(), 'Laval is not within 3 mi');
    System.assertEquals(1000, onlyMtl.rows[0].carrierTotal);
  }

  /**
   * Not in the brief as written: Revenova's managed rtms__StopUpsert trigger blanks
   * rtms__City__c/rtms__Postal_Code__c/rtms__Geolocation__c on any stop that has
   * rtms__Location2__c (see PricingTestDataFactory.buildStop()'s doc comment), so nulling an
   * account's coordinates and expecting the stop's own geolocation to still be there (the brief's
   * original approach) cannot work. Instead this uses
   * PricingTestDataFactory.createLoadWithAdHocOrigin(), which builds a stop that never had
   * rtms__Location2__c in the first place, so the trigger has nothing tied to an Account to blank.
   */
  @IsTest
  static void radiusInKilometersAndStopGeolocationFallback() {
    Fixture f = fixture();
    Test.startTest();
    f.mtlTor = PricingTestDataFactory.createLoad(
      f.g,
      f.g.originLocation,
      f.g.destinationLocation
    );
    rtms__Load__c lavalAdHoc = PricingTestDataFactory.createLoadWithAdHocOrigin(
      f.g,
      'Laval',
      'Quebec',
      'H7P 1T2',
      45.6066,
      -73.7124,
      f.g.destinationLocation
    );
    insert new List<rtms__CarrierQuote__c>{
      PricingTestDataFactory.buildQuote(f.g, f.mtlTor, 1000),
      PricingTestDataFactory.buildQuote(f.g, lavalAdHoc, 2000)
    };
    rtms__Stop__c adHocOrigin = [
      SELECT rtms__Geolocation__Latitude__s, rtms__Geolocation__Longitude__s
      FROM rtms__Stop__c
      WHERE rtms__Load__c = :lavalAdHoc.Id AND rtms__Number__c = 1
    ];
    System.assertNotEquals(
      null,
      adHocOrigin.rtms__Geolocation__Latitude__s,
      'ad-hoc origin stop (no rtms__Location2__c) must keep its own geolocation for the fallback to work'
    );
    System.assertNotEquals(
      null,
      adHocOrigin.rtms__Geolocation__Longitude__s,
      'ad-hoc origin stop (no rtms__Location2__c) must keep its own geolocation for the fallback to work'
    );
    LaneSearchRequest km = req('montreal|qc|ca', null);
    km.originPrecision = LaneSearchRequest.Precision.RADIUS;
    km.originRadius = 40;
    km.radiusUnit = LaneSearchRequest.Unit.KM;
    LaneSearchResult withStops = LaneSearchService.search(km);
    km.includeStopGeolocation = false;
    LaneSearchResult accountsOnly = LaneSearchService.search(km);
    Test.stopTest();
    System.assertEquals(
      2,
      withStops.rows.size(),
      'ad-hoc Laval origin matched through its stop geolocation'
    );
    System.assertEquals(
      1,
      accountsOnly.rows.size(),
      'without the fallback only Montreal (account-based) matches'
    );
    System.assertEquals(1000, accountsOnly.rows[0].carrierTotal);
  }

  @IsTest
  static void statsAreComputedPerCurrencyWithMedianAndZerosCounted() {
    Fixture f = fixture();
    Test.startTest();
    f.mtlTor = PricingTestDataFactory.createLoad(
      f.g,
      f.g.originLocation,
      f.g.destinationLocation
    );
    insert new List<rtms__CarrierQuote__c>{
      PricingTestDataFactory.buildQuote(f.g, f.mtlTor, 1000, 'CAD'),
      PricingTestDataFactory.buildQuote(f.g, f.mtlTor, 3000, 'CAD'),
      PricingTestDataFactory.buildQuote(f.g, f.mtlTor, 2000, 'CAD'),
      PricingTestDataFactory.buildQuote(f.g, f.mtlTor, 0, 'CAD'),
      PricingTestDataFactory.buildQuote(f.g, f.mtlTor, 800, 'USD'),
      PricingTestDataFactory.buildQuote(f.g, f.mtlTor, 1200, 'USD')
    };
    LaneSearchResult all = LaneSearchService.search(req(null, null));
    LaneSearchRequest usdOnly = req(null, null);
    usdOnly.currencyIsoCode = 'USD';
    LaneSearchResult usd = LaneSearchService.search(usdOnly);
    Test.stopTest();
    LaneSearchResult.Stats cad = all.statsByCurrency.get('CAD');
    System.assertEquals(4, cad.count);
    System.assertEquals(3, cad.countNonZero);
    System.assertEquals(1000, cad.min);
    System.assertEquals(3000, cad.max);
    System.assertEquals(2000, cad.avg);
    System.assertEquals(2000, cad.median, 'odd count: middle value');
    LaneSearchResult.Stats us = all.statsByCurrency.get('USD');
    System.assertEquals(2, us.count);
    System.assertEquals(
      1000,
      us.median,
      'even count: mean of the two middle values'
    );
    System.assertEquals(2, usd.rows.size());
    System.assertEquals(false, usd.statsByCurrency.containsKey('CAD'));
  }

  @IsTest
  static void modeAndEquipmentFiltersCombine() {
    Fixture f = fixture();
    rtms__Mode__c ltl = PricingTestDataFactory.createMode('LTL');
    rtms__EquipmentType__c reefer = PricingTestDataFactory.createEquipment(
      'Reefer 53\'',
      'Reefer'
    );
    Test.startTest();
    rtms__Load__c van = PricingTestDataFactory.createLoad(
      f.g,
      f.g.originLocation,
      f.g.destinationLocation
    );
    rtms__Load__c ltlLoad = PricingTestDataFactory.createLoad(
      f.g,
      f.g.originLocation,
      f.g.destinationLocation,
      ltl
    );
    ltlLoad.rtms__Equipment_Type__c = reefer.Id;
    update ltlLoad;
    insert new List<rtms__CarrierQuote__c>{
      PricingTestDataFactory.buildQuote(f.g, van, 1000),
      PricingTestDataFactory.buildQuote(f.g, ltlLoad, 500)
    };
    LaneSearchRequest byMode = req(null, null);
    byMode.modes = new List<String>{ 'LTL' };
    LaneSearchRequest byCategory = req(null, null);
    byCategory.equipmentCategories = new List<String>{ 'Van' };
    LaneSearchRequest byType = req(null, null);
    byType.equipmentTypes = new List<String>{ 'Reefer 53\'' };
    LaneSearchRequest catOrType = req(null, null);
    catOrType.equipmentCategories = new List<String>{ 'Van' };
    catOrType.equipmentTypes = new List<String>{ 'Reefer 53\'' };
    LaneSearchResult m = LaneSearchService.search(byMode);
    LaneSearchResult c = LaneSearchService.search(byCategory);
    LaneSearchResult t = LaneSearchService.search(byType);
    LaneSearchResult ct = LaneSearchService.search(catOrType);
    Test.stopTest();
    System.assertEquals(1, m.rows.size());
    System.assertEquals(500, m.rows[0].carrierTotal);
    System.assertEquals(1, c.rows.size());
    System.assertEquals(1000, c.rows[0].carrierTotal);
    System.assertEquals(1, t.rows.size());
    System.assertEquals(500, t.rows[0].carrierTotal);
    System.assertEquals(2, ct.rows.size(), 'categories OR types');
  }

  @IsTest
  static void hazmatMarketTestAcceptedAndExcludedContactFilters() {
    Fixture f = fixture();
    Account marketTest = f.g.customer.clone(false, true, false, false);
    marketTest.Name = 'Market Test';
    insert marketTest;
    // "plain" is created here, outside Test.startTest(), and haz/mt inside it: three
    // non-bulkified createLoad() calls all inside one Test.startTest() block exceeded the
    // 100-SOQL-query synchronous limit (hit 101) - see PricingTestDataFactory's class doc
    // ("wraps the LATER createLoad() calls in Test.startTest()"), which only promises a fresh
    // governor budget for calls after the first.
    rtms__Load__c plain = PricingTestDataFactory.createLoad(
      f.g,
      f.g.originLocation,
      f.g.destinationLocation
    );
    Test.startTest();
    rtms__Load__c haz = PricingTestDataFactory.createLoad(
      f.g,
      f.g.originLocation,
      f.g.destinationLocation,
      true
    );
    rtms__Load__c mt = PricingTestDataFactory.createLoad(
      f.g,
      f.g.originLocation,
      f.g.destinationLocation,
      marketTest
    );
    rtms__CarrierQuote__c accepted = PricingTestDataFactory.buildQuote(
      f.g,
      plain,
      1000
    );
    accepted.rtms__Accepted__c = true;
    insert new List<rtms__CarrierQuote__c>{
      accepted,
      PricingTestDataFactory.buildQuote(f.g, haz, 2000),
      PricingTestDataFactory.buildQuote(f.g, mt, 3000)
    };
    LaneSearchRequest h = req(null, null);
    h.hazmatOnly = true;
    LaneSearchRequest m = req(null, null);
    m.marketTestOnly = true;
    LaneSearchRequest a = req(null, null);
    a.acceptedFilter = LaneSearchRequest.Accepted.ACCEPTED;
    LaneSearchRequest d = req(null, null);
    d.acceptedFilter = LaneSearchRequest.Accepted.DECLINED;
    LaneSearchResult rh = LaneSearchService.search(h);
    LaneSearchResult rm = LaneSearchService.search(m);
    LaneSearchResult ra = LaneSearchService.search(a);
    LaneSearchResult rd = LaneSearchService.search(d);
    LaneSearchExclusions.excludedContactIdsOverride = new Set<String>{
      String.valueOf(f.g.quoteContact.Id).left(15)
    };
    LaneSearchResult none = LaneSearchService.search(req(null, null));
    Test.stopTest();
    System.assertEquals(2000, rh.rows[0].carrierTotal);
    System.assertEquals(1, rh.rows.size());
    System.assertEquals(3000, rm.rows[0].carrierTotal);
    System.assertEquals(1, rm.rows.size());
    System.assertEquals(1, ra.rows.size());
    System.assertEquals(1000, ra.rows[0].carrierTotal);
    System.assertEquals(2, rd.rows.size());
    System.assertEquals(
      0,
      none.rows.size(),
      'excluded contact hides every quote from that contact'
    );
  }

  @IsTest
  static void identicalQuotesAreDedupedAndCountedAndTruncationIsFlagged() {
    Fixture f = fixture();
    Test.startTest();
    f.mtlTor = PricingTestDataFactory.createLoad(
      f.g,
      f.g.originLocation,
      f.g.destinationLocation
    );
    List<rtms__CarrierQuote__c> qs = new List<rtms__CarrierQuote__c>();
    for (Integer i = 0; i < 5; i++) {
      qs.add(PricingTestDataFactory.buildQuote(f.g, f.mtlTor, 1000)); // identical
    }
    qs.add(PricingTestDataFactory.buildQuote(f.g, f.mtlTor, 1500));
    insert qs;
    LaneSearchResult r = LaneSearchService.search(req(null, null));
    LaneSearchRequest small = req(null, null);
    small.rowLimit = 2;
    LaneSearchResult capped = LaneSearchService.search(small);
    Test.stopTest();
    System.assertEquals(
      2,
      r.rows.size(),
      'five identical collapse to one, plus the 1500'
    );
    System.assertEquals(4, r.dedupedCount);
    System.assertEquals(true, capped.truncated);
    System.assertEquals(
      2,
      capped.rows.size() + capped.dedupedCount,
      'cap applies before dedupe'
    );
  }

  @IsTest
  static void lookbackWindowIsRespected() {
    Fixture f = fixture();
    // Load/quote creation and Test.setCreatedDate() happen before Test.startTest(): the
    // platform rejects Test.setCreatedDate() once the test context has started
    // ("Use Test.setCreatedDate() only before Test.startTest()."), and a single createLoad()
    // call fits comfortably in the un-reset governor budget without needing the fresh one
    // Test.startTest() provides for the LATER calls (see PricingTestDataFactory's class doc).
    f.mtlTor = PricingTestDataFactory.createLoad(
      f.g,
      f.g.originLocation,
      f.g.destinationLocation
    );
    rtms__CarrierQuote__c recent = PricingTestDataFactory.buildQuote(
      f.g,
      f.mtlTor,
      1000
    );
    rtms__CarrierQuote__c old = PricingTestDataFactory.buildQuote(
      f.g,
      f.mtlTor,
      2000
    );
    insert new List<rtms__CarrierQuote__c>{ recent, old };
    Test.setCreatedDate(recent.Id, Datetime.now().addDays(-2));
    Test.setCreatedDate(old.Id, Datetime.now().addDays(-400));
    Test.startTest();
    LaneSearchRequest ninety = req(null, null);
    LaneSearchRequest twoYears = req(null, null);
    twoYears.lookbackDays = 730;
    LaneSearchResult r90 = LaneSearchService.search(ninety);
    LaneSearchResult r730 = LaneSearchService.search(twoYears);
    Test.stopTest();
    System.assertEquals(1, r90.rows.size());
    System.assertEquals(2, r730.rows.size(), 'any lookback is accepted');
  }

  @IsTest
  static void applyDefaultsFillsNullFields() {
    LaneSearchRequest req = (LaneSearchRequest) JSON.deserialize(
      '{}',
      LaneSearchRequest.class
    );
    System.assertEquals(
      null,
      req.lookbackDays,
      'JSON.deserialize does not run field initializers'
    );
    req.validate();
    System.assertEquals(90, req.lookbackDays);
    System.assertEquals(LaneSearchRequest.Precision.CITY, req.originPrecision);
    System.assertEquals(2000, req.rowLimit);
    System.assertNotEquals(null, req.modes);
    System.assertEquals(0, req.modes.size());
  }

  @IsTest
  static void bidsMergeIntoRowsAndObeyTheSourceFilter() {
    Fixture f = fixture();
    Pricing_Place__c mtl = [
      SELECT Id, City__c, Province__c, Country__c, Postal_Prefix__c
      FROM Pricing_Place__c
      WHERE Key__c = 'montreal|qc|ca'
    ];
    Pricing_Place__c tor = [
      SELECT Id, City__c, Province__c, Country__c, Postal_Prefix__c
      FROM Pricing_Place__c
      WHERE Key__c = 'toronto|on|ca'
    ];
    RFP_Lane__c lane = RfpTestDataFactory.createLane(
      RfpTestDataFactory.createProject(f.g.customer),
      mtl,
      tor
    );
    BenchmarkRateService.save(RfpTestDataFactory.buildBid(lane, 1200));
    Benchmark_Rate__c expired = RfpTestDataFactory.buildBid(lane, 999);
    expired.Valid_From__c = Date.today().addDays(-60);
    expired.Expires_On__c = Date.today().addDays(-1);
    BenchmarkRateService.save(expired);

    Test.startTest();
    createLoadsAndQuotes(f);

    LaneSearchResult all = LaneSearchService.search(
      req('montreal|qc|ca', 'toronto|on|ca')
    );
    LaneSearchRequest loadsOnly = req('montreal|qc|ca', 'toronto|on|ca');
    loadsOnly.sourceFilter = LaneSearchRequest.RowSource.LOADS;
    LaneSearchResult loads = LaneSearchService.search(loadsOnly);
    LaneSearchRequest bidsOnly = req('montreal|qc|ca', 'toronto|on|ca');
    bidsOnly.sourceFilter = LaneSearchRequest.RowSource.BIDS;
    LaneSearchResult bids = LaneSearchService.search(bidsOnly);
    Test.stopTest();

    System.assertEquals(2, all.rows.size(), 'one quote + one active bid');
    System.assertEquals(1, loads.rows.size());
    System.assertEquals(null, loads.rows[0].bid);
    System.assertEquals(
      2,
      bids.rows.size(),
      'active and expired bids, no quotes'
    );
    Set<String> statuses = new Set<String>{
      bids.rows[0].bid.status,
      bids.rows[1].bid.status
    };
    System.assert(
      statuses.contains('Expired') && statuses.contains('Active'),
      statuses
    );
    System.assertEquals(
      2,
      all.statsByCurrency.get('CAD').count,
      'stats count both sources'
    );
    System.assertEquals(1100, all.statsByCurrency.get('CAD').avg);
  }

  /**
   * Phase 7: a load row carries its load's billed miles and a bid row carries none, so the bid
   * never enters medianMiles or the rate per mile. Same shape as
   * bidsMergeIntoRowsAndObeyTheSourceFilter: the lane and its bid are saved before Test.startTest,
   * the two loads inside it.
   */
  @IsTest
  static void loadRowsCarryTheirMilesAndBidRowsDoNot() {
    Fixture f = fixture();
    Pricing_Place__c mtl = [
      SELECT Id, City__c, Province__c, Country__c, Postal_Prefix__c
      FROM Pricing_Place__c
      WHERE Key__c = 'montreal|qc|ca'
    ];
    Pricing_Place__c tor = [
      SELECT Id, City__c, Province__c, Country__c, Postal_Prefix__c
      FROM Pricing_Place__c
      WHERE Key__c = 'toronto|on|ca'
    ];
    RFP_Lane__c lane = RfpTestDataFactory.createLane(
      RfpTestDataFactory.createProject(f.g.customer),
      mtl,
      tor
    );
    BenchmarkRateService.save(RfpTestDataFactory.buildBid(lane, 1200));

    Test.startTest();
    f.mtlTor = PricingTestDataFactory.createLoad(
      f.g,
      f.g.originLocation,
      f.g.destinationLocation,
      250.0
    );
    f.lavalTor = PricingTestDataFactory.createLoad(
      f.g,
      f.laval,
      f.g.destinationLocation,
      500.0
    );
    insert new List<rtms__CarrierQuote__c>{
      PricingTestDataFactory.buildQuote(f.g, f.mtlTor, 1000),
      PricingTestDataFactory.buildQuote(f.g, f.lavalTor, 3000)
    };
    LaneSearchResult r = LaneSearchService.search(req(null, null));
    Test.stopTest();

    System.assertEquals(3, r.rows.size(), 'two quotes and the active bid');
    Map<Integer, LaneSearchResult.Row> byTotal = new Map<Integer, LaneSearchResult.Row>();
    for (LaneSearchResult.Row row : r.rows) {
      byTotal.put(row.carrierTotal.intValue(), row);
    }
    LaneSearchResult.Row bidRow = byTotal.get(1200);
    System.assertNotEquals(null, bidRow.bid, 'the 1200 row is the bid');
    System.assertNotEquals(null, bidRow.load, 'every row has a load group');
    System.assertEquals(null, bidRow.load.miles, 'a bid has no load miles');
    System.assertEquals(null, bidRow.load.loadId);
    System.assertEquals(250, byTotal.get(1000).load.miles);
    System.assertEquals(f.mtlTor.Id, byTotal.get(1000).load.loadId);
    System.assertEquals(500, byTotal.get(3000).load.miles);
    System.assertEquals(f.lavalTor.Id, byTotal.get(3000).load.loadId);
    System.assertEquals(
      375,
      r.medianMiles,
      'two loads with miles: the mean of 250 and 500; the bid is left out'
    );
    LaneSearchResult.Stats cad = r.statsByCurrency.get('CAD');
    System.assertEquals(
      3,
      cad.count,
      'the bid still counts in the price stats'
    );
    System.assertEquals(
      5,
      cad.ratePerMileMedian,
      '1000/250 = 4.00 and 3000/500 = 6.00; the bid has no miles'
    );
    System.assertEquals(2, cad.ratePerMileMedian.scale());
  }

  /**
   * Phase 7: medianMiles counts each load once however many quotes it has (spec D1), a zero total
   * stays out of the rate per mile, and each currency gets its own rate per mile.
   */
  @IsTest
  static void medianMilesAndRatePerMileSkipZeroTotalsAndSplitByCurrency() {
    Fixture f = fixture();
    Test.startTest();
    f.mtlTor = PricingTestDataFactory.createLoad(
      f.g,
      f.g.originLocation,
      f.g.destinationLocation,
      250.0
    );
    f.lavalTor = PricingTestDataFactory.createLoad(
      f.g,
      f.laval,
      f.g.destinationLocation,
      500.0
    );
    List<rtms__Load__c> stored = [
      SELECT rtms__Distance_Miles__c
      FROM rtms__Load__c
      WHERE Id IN :new List<Id>{ f.mtlTor.Id, f.lavalTor.Id }
      ORDER BY rtms__Distance_Miles__c
    ];
    System.assertEquals(
      250,
      stored[0].rtms__Distance_Miles__c,
      'the miles set at insert survive the load and stop automation'
    );
    System.assertEquals(500, stored[1].rtms__Distance_Miles__c);
    insert new List<rtms__CarrierQuote__c>{
      PricingTestDataFactory.buildQuote(f.g, f.mtlTor, 1000, 'CAD'),
      PricingTestDataFactory.buildQuote(f.g, f.mtlTor, 0, 'CAD'),
      PricingTestDataFactory.buildQuote(f.g, f.mtlTor, 500, 'USD'),
      PricingTestDataFactory.buildQuote(f.g, f.lavalTor, 3000, 'CAD'),
      PricingTestDataFactory.buildQuote(f.g, f.lavalTor, 1500, 'USD')
    };
    LaneSearchResult r = LaneSearchService.search(req(null, null));
    Test.stopTest();

    System.assertEquals(5, r.rows.size(), 'no two quotes share a fingerprint');
    System.assertEquals(
      375.0,
      r.medianMiles,
      'five quotes on two loads: each load counts once, so the mean of 250 and 500, not the middle row'
    );
    LaneSearchResult.Stats cad = r.statsByCurrency.get('CAD');
    System.assertEquals(3, cad.count);
    System.assertEquals(2, cad.countNonZero);
    System.assertEquals(
      5,
      cad.ratePerMileMedian,
      '4.00 and 6.00; with the zero total it would be the middle of 0, 4 and 6'
    );
    System.assertEquals(
      2.5,
      r.statsByCurrency.get('USD').ratePerMileMedian,
      '500/250 = 2.00 and 1500/500 = 3.00, apart from the CAD rows'
    );
  }

  @IsTest
  static void ratePerMileMedianIsScaleTwoAndNullWhenEmpty() {
    Decimal odd = LaneSearchService.ratePerMileMedian(
      new List<Decimal>{ 3.5, 1.25, 2 }
    );
    System.assertEquals(2, odd, 'odd count: the middle rate');
    System.assertEquals(
      2,
      odd.scale(),
      'scale 2 even for a whole middle value'
    );
    System.assertEquals(
      5,
      LaneSearchService.ratePerMileMedian(new List<Decimal>{ 6, 4 }),
      'even count: the mean of the two middle rates'
    );
    System.assertEquals(
      null,
      LaneSearchService.ratePerMileMedian(new List<Decimal>()),
      'no rate, no median'
    );
  }
}
