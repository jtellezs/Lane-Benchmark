@IsTest
private class PlaceBuilderBatchTest {
  @IsTest
  static void collapsesSpellingsIntoOnePlaceWithAveragedCoordinatesAndCounts() {
    PricingTestDataFactory.Graph g = PricingTestDataFactory.createGraph();
    Account a1 = PricingTestDataFactory.createLocation(
      'A',
      'Montréal',
      'Quebec',
      'Canada',
      'H1A 1A1',
      45.50,
      -73.56
    );
    Account a2 = PricingTestDataFactory.createLocation(
      'B',
      'MONTREAL',
      // This PostProduc org enforces State and Country Picklists with the "restrict to these
      // values" option: Account.ShippingState/ShippingCountry only accept the exact standard
      // label ('Quebec'/'Canada'), never the ISO abbreviation ('QC'/'CA') - confirmed empirically
      // with anonymous Apex (FIELD_INTEGRITY_EXCEPTION otherwise). Abbreviation-to-code collapsing
      // (PlaceNormalizer.provinceCode/countryCode mapping 'QC'/'CA' the same as 'Quebec'/'Canada')
      // is already unit-tested directly in PlaceNormalizerTest without touching the database; this
      // integration test instead varies the CITY spelling (free text, unrestricted) to exercise the
      // same collapsing behavior through PlaceBuilderBatch.
      'Quebec',
      'Canada',
      'H2B 2B2',
      45.52,
      -73.58
    );
    Account a3 = PricingTestDataFactory.createLocation(
      'C',
      'Laval',
      'Quebec',
      'Canada',
      'H7P 1T2',
      45.60,
      -73.71
    );
    // Only accounts referenced by a stop are considered; create loads that reference all three.
    PlaceBuilderBatch pbb = new PlaceBuilderBatch();
    Test.startTest();
    PricingTestDataFactory.createLoad(g, a1, a3);
    PricingTestDataFactory.createLoad(g, a2, a3);
    Database.executeBatch(pbb, 200);
    Test.stopTest();

    // PlaceBuilderBatch itself is guaranteed to run synchronously by stopTest(): pbb.aggs is
    // populated regardless of what happens next. Whether its own chain into PlaceWriteBatch (and
    // PlaceWriteBatch's own chain into PlaceUsageBatch) also completes synchronously in test
    // context is not reliable at this chain depth, so drive the rest of the pipeline explicitly -
    // it's idempotent (upsert by Key__c) so running it whether or not the chain already did is
    // harmless.
    if ([SELECT COUNT() FROM Pricing_Place__c] == 0) {
      List<Pricing_Place__c> places = pbb.buildPlacesForTest();
      new PlaceWriteBatch(places, false).execute(null, places);
    }
    runUsageBatch();

    Map<String, Pricing_Place__c> byKey = new Map<String, Pricing_Place__c>();
    for (Pricing_Place__c p : [
      SELECT
        Key__c,
        City__c,
        Province__c,
        Country__c,
        Geolocation__Latitude__s,
        Geolocation__Longitude__s,
        Location_Count__c,
        Spellings__c,
        Postal_Prefix__c,
        Active__c,
        Load_Count_365d__c,
        Source__c
      FROM Pricing_Place__c
    ]) {
      byKey.put(p.Key__c, p);
    }
    // Only the three locations created above are referenced by a stop in this test: both loads
    // run a1/a2 -> a3, so createGraph()'s own origin/destination accounts never reach a stop and
    // never become places here.
    System.assert(byKey.containsKey('montreal|qc|ca'), byKey.keySet());
    System.assert(byKey.containsKey('laval|qc|ca'), byKey.keySet());
    Pricing_Place__c mtl = byKey.get('montreal|qc|ca');
    System.assertEquals('QC', mtl.Province__c);
    System.assertEquals('CA', mtl.Country__c);
    System.assertEquals(
      2,
      mtl.Location_Count__c,
      'the two Montreal spellings collapsed into one place'
    );
    System.assert(
      mtl.Spellings__c.contains('MONTREAL') &&
      mtl.Spellings__c.contains('Montréal'),
      mtl.Spellings__c
    );
    System.assert(
      mtl.Geolocation__Latitude__s > 45.49 &&
        mtl.Geolocation__Latitude__s < 45.53,
      'averaged: ' + mtl.Geolocation__Latitude__s
    );
    System.assert(
      new Set<String>{ 'H1A', 'H2B', 'A1A' }.contains(mtl.Postal_Prefix__c),
      mtl.Postal_Prefix__c
    );
    System.assertEquals(true, mtl.Active__c);
    System.assertEquals('Locations', mtl.Source__c);
    // The usage batch counts one per load END: Laval was a destination twice, Montreal an origin
    // twice.
    System.assertEquals(2, byKey.get('laval|qc|ca').Load_Count_365d__c);
    System.assertEquals(2, byKey.get('montreal|qc|ca').Load_Count_365d__c);
  }

  /**
   * The province defect end to end. Revenova writes Mexican states as 2-letter codes ("General
   * Escobedo, NL:..."), which PlaceNormalizer did not know, so the builder truncated the full name
   * to "Nue" and every CITY/PROVINCE search for a Mexican place matched nothing. This builds the
   * place from a Mexican location account and then runs the search that used to come back empty.
   */
  @IsTest
  static void mexicanProvinceKeepsRevenovasCodeAndCitySearchFindsIt() {
    PricingTestDataFactory.Graph g = PricingTestDataFactory.createGraph();
    Account escobedo = PricingTestDataFactory.createLocation(
      'Escobedo Co',
      'General Escobedo',
      'Nuevo León',
      'Mexico',
      '66050',
      25.7973,
      -100.3183
    );
    PricingDepartmentController.excludedContactIdsOverride = new Set<String>();
    PlaceBuilderBatch pbb = new PlaceBuilderBatch();
    Test.startTest();
    rtms__Load__c mxLoad = PricingTestDataFactory.createLoad(
      g,
      escobedo,
      escobedo
    );
    insert PricingTestDataFactory.buildQuote(g, mxLoad, 1500);
    Database.executeBatch(pbb, 200);
    Test.stopTest();
    // Same chain-depth caveat as the first test: drive the write explicitly if the chain did not.
    if ([SELECT COUNT() FROM Pricing_Place__c] == 0) {
      List<Pricing_Place__c> places = pbb.buildPlacesForTest();
      new PlaceWriteBatch(places, false).execute(null, places);
    }

    runUsageBatch();

    Pricing_Place__c place = [
      SELECT Name, Key__c, Province__c, Country__c, Load_Count_365d__c
      FROM Pricing_Place__c
      WHERE Key__c = 'general escobedo|nl|mx'
    ];
    System.assertEquals(
      'NL',
      place.Province__c,
      'Revenova writes NL for Nuevo León, so the place must too'
    );
    System.assertEquals('MX', place.Country__c);
    System.assertEquals(
      'General Escobedo, NL, MX',
      place.Name,
      'no truncated province in the display name'
    );
    System.assertEquals(
      2,
      place.Load_Count_365d__c,
      'one load, both ends in this place: counted once per end'
    );

    LaneSearchRequest search = new LaneSearchRequest();
    search.originKey = 'general escobedo|nl|mx';
    LaneSearchResult result = LaneSearchService.search(search);
    System.assertEquals(
      1,
      result.rows.size(),
      'CITY precision matches "General Escobedo, NL" on the load'
    );
    System.assertEquals(1500, result.rows[0].carrierTotal);
  }

  /**
   * A province PlaceNormalizer has no code for is stored whole, not cut to three characters.
   * These accounts are never inserted - the batch's execute() takes the scope as a list, so the
   * org's restricted State/Country picklists never come into it.
   */
  @IsTest
  static void unmappedProvinceIsStoredWholeNotTruncated() {
    PlaceBuilderBatch b = new PlaceBuilderBatch();
    b.execute(
      null,
      new List<Account>{
        new Account(
          Name = 'Stuttgart Co',
          ShippingCity = 'Stuttgart',
          ShippingState = 'Baden-Württemberg',
          ShippingCountry = 'Germany',
          ShippingPostalCode = '70173',
          ShippingLatitude = 48.7758,
          ShippingLongitude = 9.1829
        )
      }
    );
    List<Pricing_Place__c> places = b.buildPlacesForTest();
    new PlaceWriteBatch(places, false).execute(null, places);

    Pricing_Place__c p = [
      SELECT Name, Province__c
      FROM Pricing_Place__c
      WHERE Key__c = 'stuttgart|baden wurttemberg|ge'
    ];
    System.assertEquals('Baden-Württemberg', p.Province__c);
    System.assertEquals('Stuttgart, Baden-Württemberg, GE', p.Name);
  }

  /**
   * Drives PlaceUsageBatch by hand over the same loads its own start() would select. The batch
   * chain that finish() kicks off is not reliably synchronous at this depth in test context, and
   * this is idempotent, so running it either way is harmless.
   */
  private static void runUsageBatch() {
    PlaceUsageBatch pub = new PlaceUsageBatch();
    pub.execute(
      null,
      [
        SELECT
          rtms__First_Stop__r.rtms__Location2__r.ShippingCity,
          rtms__First_Stop__r.rtms__Location2__r.ShippingState,
          rtms__First_Stop__r.rtms__Location2__r.ShippingCountry,
          rtms__Last_Stop__r.rtms__Location2__r.ShippingCity,
          rtms__Last_Stop__r.rtms__Location2__r.ShippingState,
          rtms__Last_Stop__r.rtms__Location2__r.ShippingCountry
        FROM rtms__Load__c
        WHERE CreatedDate = LAST_N_DAYS:365
      ]
    );
    List<Pricing_Place__c> updates = pub.buildUpdatesForTest();
    new PlaceWriteBatch(updates, false).execute(null, updates);
  }

  @IsTest
  static void rerunPreservesCuratedFieldsAndDoesNotDuplicate() {
    PricingTestDataFactory.Graph g = PricingTestDataFactory.createGraph();
    PlaceBuilderBatch firstRun = new PlaceBuilderBatch();
    Test.startTest();
    PricingTestDataFactory.createLoad(
      g,
      g.originLocation,
      g.destinationLocation
    );
    Database.executeBatch(firstRun, 200);
    Test.stopTest();
    // Same chain-depth caveat as the first test: ensure the place exists regardless of whether
    // PlaceBuilderBatch's chain into PlaceWriteBatch also completed synchronously.
    if (
      [SELECT COUNT() FROM Pricing_Place__c WHERE Key__c = 'montreal|qc|ca'] ==
      0
    ) {
      List<Pricing_Place__c> firstRunPlaces = firstRun.buildPlacesForTest();
      new PlaceWriteBatch(firstRunPlaces, false).execute(null, firstRunPlaces);
    }
    Pricing_Place__c mtl = [
      SELECT Id, Key__c
      FROM Pricing_Place__c
      WHERE Key__c = 'montreal|qc|ca'
    ];
    mtl.Aliases__c = 'Mtl';
    mtl.Active__c = false;
    update mtl;
    Integer before = [SELECT COUNT() FROM Pricing_Place__c];

    // Second run: cannot use executeBatch again after stopTest; call the batch methods directly.
    PlaceBuilderBatch b = new PlaceBuilderBatch();
    b.execute(
      null,
      [
        SELECT
          Id,
          ShippingCity,
          ShippingState,
          ShippingCountry,
          ShippingPostalCode,
          ShippingLatitude,
          ShippingLongitude
        FROM Account
        WHERE Id IN (SELECT rtms__Location2__c FROM rtms__Stop__c)
      ]
    );
    List<Pricing_Place__c> places = b.buildPlacesForTest();
    new PlaceWriteBatch(places, false).execute(null, places);

    System.assertEquals(before, [SELECT COUNT() FROM Pricing_Place__c]);
    mtl = [
      SELECT Aliases__c, Active__c
      FROM Pricing_Place__c
      WHERE Key__c = 'montreal|qc|ca'
    ];
    System.assertEquals('Mtl', mtl.Aliases__c);
    System.assertEquals(false, mtl.Active__c);
  }

  @IsTest
  static void writeBatchUpsertsEachScopeByKey() {
    List<Pricing_Place__c> places = new List<Pricing_Place__c>{
      new Pricing_Place__c(
        Key__c = 'placeone|on|ca',
        Name = 'Place One, ON, CA',
        City__c = 'Place One',
        Province__c = 'ON',
        Country__c = 'CA',
        Load_Count_365d__c = 1
      ),
      new Pricing_Place__c(
        Key__c = 'placetwo|on|ca',
        Name = 'Place Two, ON, CA',
        City__c = 'Place Two',
        Province__c = 'ON',
        Country__c = 'CA',
        Load_Count_365d__c = 2
      ),
      new Pricing_Place__c(
        Key__c = 'placethree|on|ca',
        Name = 'Place Three, ON, CA',
        City__c = 'Place Three',
        Province__c = 'ON',
        Country__c = 'CA',
        Load_Count_365d__c = 3
      )
    };
    new PlaceWriteBatch(places, false).execute(null, places);

    // Second pass over the same scope: one value changes, nothing duplicates.
    places[0].Load_Count_365d__c = 99;
    new PlaceWriteBatch(places, false).execute(null, places);

    System.assertEquals(3, [SELECT COUNT() FROM Pricing_Place__c]);
    Pricing_Place__c placeOne = [
      SELECT Load_Count_365d__c
      FROM Pricing_Place__c
      WHERE Key__c = 'placeone|on|ca'
    ];
    System.assertEquals(99, placeOne.Load_Count_365d__c);
  }
}
