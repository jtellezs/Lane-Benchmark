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
    PlaceUsageBatch pub = new PlaceUsageBatch();
    pub.execute(
      null,
      [
        SELECT
          rtms__Location2__r.ShippingCity,
          rtms__Location2__r.ShippingState,
          rtms__Location2__r.ShippingCountry
        FROM rtms__Stop__c
        WHERE
          CreatedDate = LAST_N_DAYS:365
          AND rtms__Location2__c != NULL
          AND rtms__Location2__r.ShippingCity != NULL
      ]
    );
    List<Pricing_Place__c> updates = pub.buildUpdatesForTest();
    new PlaceWriteBatch(updates, false).execute(null, updates);

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
        Load_Count_365d__c
      FROM Pricing_Place__c
    ]) {
      byKey.put(p.Key__c, p);
    }
    // The graph's own two locations (Montreal/Toronto from createGraph) are also referenced by stops.
    System.assert(byKey.containsKey('montreal|qc|ca'), byKey.keySet());
    System.assert(byKey.containsKey('laval|qc|ca'), byKey.keySet());
    Pricing_Place__c mtl = byKey.get('montreal|qc|ca');
    System.assertEquals('QC', mtl.Province__c);
    System.assertEquals('CA', mtl.Country__c);
    System.assert(
      mtl.Location_Count__c >= 2,
      'both spellings plus the graph location: ' + mtl.Location_Count__c
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
    // Usage batch ran in finish(): Laval was a destination twice, Montreal an origin twice.
    System.assertEquals(2, byKey.get('laval|qc|ca').Load_Count_365d__c);
    System.assert(byKey.get('montreal|qc|ca').Load_Count_365d__c >= 2);
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
