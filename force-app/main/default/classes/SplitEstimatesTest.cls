@IsTest
private class SplitEstimatesTest {
  private class Fx {
    PricingTestDataFactory.Graph g;
    Account escobedoDock;
    Account laredoYard;
    Pricing_Place__c escobedo;
    Pricing_Place__c laredo;
    Pricing_Place__c toronto;
  }

  /** An uninserted active place, keyed the way RfpTestDataFactory.createPlace keys it. */
  private static Pricing_Place__c place(
    String city,
    String prov,
    String country,
    Decimal lat,
    Decimal lng
  ) {
    return new Pricing_Place__c(
      Name = city + ', ' + prov,
      Key__c = PlaceNormalizer.key(city, prov, country),
      City__c = city,
      Province__c = prov,
      Country__c = country,
      Geolocation__Latitude__s = lat,
      Geolocation__Longitude__s = lng,
      Active__c = true,
      Source__c = 'Locations'
    );
  }

  private static LaneSearchRequest lane(
    Pricing_Place__c origin,
    Pricing_Place__c destination
  ) {
    LaneSearchRequest r = new LaneSearchRequest();
    r.originKey = origin.Key__c;
    r.destinationKey = destination.Key__c;
    return r;
  }

  /**
   * Leg lanes "General Escobedo, NL:Laredo, TX" and "Laredo, TX:Toronto, ON" (the graph's destination
   * location), with Laredo as the only handoff point. The tests add one load before Test.startTest()
   * and two inside it, the most PricingTestDataFactory's load automation allows (its class doc).
   */
  private static Fx legFixture() {
    Fx f = new Fx();
    f.g = PricingTestDataFactory.createGraph();
    f.escobedoDock = PricingTestDataFactory.createLocation(
      'Escobedo Dock',
      'General Escobedo',
      'Nuevo León',
      'Mexico',
      '66050',
      25.8000,
      -100.3167
    );
    f.laredoYard = PricingTestDataFactory.createLocation(
      'Laredo Yard',
      'Laredo',
      'Texas',
      'United States',
      '78045',
      27.5306,
      -99.4803
    );
    f.escobedo = place('General Escobedo', 'NL', 'MX', 25.8000, -100.3167);
    f.laredo = place('Laredo', 'TX', 'US', 27.5306, -99.4803);
    f.toronto = place('Toronto', 'ON', 'CA', 43.6532, -79.3832);
    insert new List<Pricing_Place__c>{ f.escobedo, f.laredo, f.toronto };
    HandoffPoints.keysOverride = new List<String>{ f.laredo.Key__c };
    IntercompanyCarriers.idsOverride = new Set<Id>();
    return f;
  }

  /** "<handoff label> +<extra distance> %" per option, in order. */
  private static List<String> labels(List<SplitLaneResult.Option> options) {
    List<String> out = new List<String>();
    for (SplitLaneResult.Option o : options) {
      out.add(o.handoffLabel + ' +' + o.extraDistancePct + ' %');
    }
    return out;
  }

  /** "<name> (<legs moved>)" per carrier, with ", blacklisted" when flagged. */
  private static List<String> names(SplitLaneResult.Leg oneLeg) {
    List<String> out = new List<String>();
    for (SplitLaneResult.LegCarrier c : oneLeg.carriers) {
      String flag = c.blacklisted ? ', blacklisted' : '';
      out.add(c.name + ' (' + c.legsMoved + flag + ')');
    }
    return out;
  }

  /**
   * Approx miles (great circle x 1.2, one decimal per distance) from General Escobedo, NL to Toronto,
   * ON: direct 2044.0; via Little Rock 937.6 + 1108.0 = 2045.6 (+0.08 %), Laredo 156.3 + 1893.6 =
   * 2049.9 (+0.29 %), St. Louis 1276.6 + 792.6 = 2069.2 (+1.23 %), Chicago 1589.9 + 522.8 = 2112.7
   * (+3.36 %) and San Diego 1344.4 + 2597.2 = 3941.6 (+92.8 %).
   */
  @IsTest
  static void pointsWithinTenPercentAreKeptLeastExtraFirstAtMostThree() {
    Pricing_Place__c escobedo = place(
      'General Escobedo',
      'NL',
      'MX',
      25.8000,
      -100.3167
    );
    Pricing_Place__c toronto = place('Toronto', 'ON', 'CA', 43.6532, -79.3832);
    Pricing_Place__c laredo = place('Laredo', 'TX', 'US', 27.5306, -99.4803);
    Pricing_Place__c littleRock = place(
      'Little Rock',
      'AR',
      'US',
      34.7465,
      -92.2896
    );
    Pricing_Place__c stLouis = place(
      'St. Louis',
      'MO',
      'US',
      38.6270,
      -90.1994
    );
    Pricing_Place__c chicago = place('Chicago', 'IL', 'US', 41.8781, -87.6298);
    Pricing_Place__c sanDiego = place(
      'San Diego',
      'CA',
      'US',
      32.7157,
      -117.1611
    );
    insert new List<Pricing_Place__c>{
      escobedo,
      toronto,
      laredo,
      littleRock,
      stLouis,
      chicago,
      sanDiego
    };
    // Both lane ends are in the list: kept, each would come first with +0.00 %.
    HandoffPoints.keysOverride = new List<String>{
      sanDiego.Key__c,
      chicago.Key__c,
      toronto.Key__c,
      laredo.Key__c,
      'nowhere|zz|zz',
      stLouis.Key__c,
      escobedo.Key__c,
      littleRock.Key__c
    };
    IntercompanyCarriers.idsOverride = new Set<Id>();
    Test.startTest();
    List<SplitLaneResult.Option> options = SplitEstimates.estimate(
      lane(escobedo, toronto),
      escobedo,
      toronto,
      'CAD',
      null
    );
    Integer callouts = Limits.getCallouts();
    Test.stopTest();
    System.assertEquals(
      new List<String>{
        'Little Rock, AR +0 %',
        'Laredo, TX +0 %',
        'St. Louis, MO +1 %'
      },
      labels(options),
      'least extra distance first, at most 3 (Chicago is the fourth); San Diego is over 10 %; both lane ends and a key without a place are left out'
    );
    SplitLaneResult.Option viaLittleRock = options[0];
    System.assertEquals(SplitLaneResult.ESTIMATE, viaLittleRock.kind);
    System.assertEquals(
      0,
      viaLittleRock.shipments,
      'an estimate has no shipment'
    );
    System.assertEquals(2, viaLittleRock.legs.size());
    System.assertEquals(1, viaLittleRock.legs[0].position);
    System.assertEquals(
      'General Escobedo, NL → Little Rock, AR',
      viaLittleRock.legs[0].laneLabel
    );
    System.assertEquals(2, viaLittleRock.legs[1].position);
    System.assertEquals(
      'Little Rock, AR → Toronto, ON',
      viaLittleRock.legs[1].laneLabel
    );
    System.assertEquals(
      0,
      viaLittleRock.legs[0].carriers.size(),
      'no load on the leg lane in this test'
    );
    System.assertEquals(null, viaLittleRock.legs[0].median);
    System.assertEquals(0, viaLittleRock.legs[0].pricedCount);
    System.assertEquals(
      null,
      viaLittleRock.medianTotal,
      'no priced leg, no total'
    );
    System.assertEquals(
      0,
      callouts,
      'distances come from the coordinates, never from Mapbox'
    );
  }

  /**
   * General Escobedo, NL to San Diego, CA: direct 1344.4; via Calexico 1235.8 + 116.0 = 1351.8, +0.55 %,
   * shown as +1 % (half up); via Laredo 156.3 + 1336.8 = 1493.1, +11.06 %, over 10 %. To Toronto via
   * Chicago: +3.36 %, shown as +3 %.
   */
  @IsTest
  static void extraDistanceIsRoundedHalfUpAndLaredoIsTooFarForSanDiego() {
    Pricing_Place__c escobedo = place(
      'General Escobedo',
      'NL',
      'MX',
      25.8000,
      -100.3167
    );
    Pricing_Place__c toronto = place('Toronto', 'ON', 'CA', 43.6532, -79.3832);
    Pricing_Place__c laredo = place('Laredo', 'TX', 'US', 27.5306, -99.4803);
    Pricing_Place__c calexico = place(
      'Calexico',
      'CA',
      'US',
      32.6789,
      -115.4989
    );
    Pricing_Place__c sanDiego = place(
      'San Diego',
      'CA',
      'US',
      32.7157,
      -117.1611
    );
    Pricing_Place__c chicago = place('Chicago', 'IL', 'US', 41.8781, -87.6298);
    insert new List<Pricing_Place__c>{
      escobedo,
      toronto,
      laredo,
      calexico,
      sanDiego,
      chicago
    };
    IntercompanyCarriers.idsOverride = new Set<Id>();
    Test.startTest();
    HandoffPoints.keysOverride = new List<String>{
      laredo.Key__c,
      calexico.Key__c,
      sanDiego.Key__c
    };
    List<SplitLaneResult.Option> toSanDiego = SplitEstimates.estimate(
      lane(escobedo, sanDiego),
      escobedo,
      sanDiego,
      'CAD',
      null
    );
    HandoffPoints.keysOverride = new List<String>{ chicago.Key__c };
    List<SplitLaneResult.Option> toToronto = SplitEstimates.estimate(
      lane(escobedo, toronto),
      escobedo,
      toronto,
      'CAD',
      null
    );
    Test.stopTest();
    System.assertEquals(
      new List<String>{ 'Calexico, CA +1 %' },
      labels(toSanDiego),
      'Laredo adds 11.06 % to this lane; San Diego is its destination'
    );
    System.assertEquals(
      new List<String>{ 'Chicago, IL +3 %' },
      labels(toToronto)
    );
  }

  @IsTest
  static void noActivePointNoCoordinatesOrNoPlaceMeansNoEstimate() {
    Pricing_Place__c escobedo = place(
      'General Escobedo',
      'NL',
      'MX',
      25.8000,
      -100.3167
    );
    Pricing_Place__c toronto = place('Toronto', 'ON', 'CA', 43.6532, -79.3832);
    Pricing_Place__c laredo = place('Laredo', 'TX', 'US', 27.5306, -99.4803);
    Pricing_Place__c unlocated = place(
      'Unlocated Yard',
      'TX',
      'US',
      null,
      null
    );
    insert new List<Pricing_Place__c>{ escobedo, toronto, laredo, unlocated };
    IntercompanyCarriers.idsOverride = new Set<Id>();
    Pricing_Place__c blindOrigin = escobedo.clone(false, true);
    blindOrigin.Geolocation__Latitude__s = null;
    Test.startTest();
    Integer queriesBefore = Limits.getQueries();
    HandoffPoints.keysOverride = new List<String>();
    List<SplitLaneResult.Option> noPoint = SplitEstimates.estimate(
      lane(escobedo, toronto),
      escobedo,
      toronto,
      'CAD',
      null
    );
    HandoffPoints.keysOverride = new List<String>{ laredo.Key__c };
    List<SplitLaneResult.Option> blind = SplitEstimates.estimate(
      lane(escobedo, toronto),
      blindOrigin,
      toronto,
      'CAD',
      null
    );
    Integer queriesAfterTwo = Limits.getQueries();
    HandoffPoints.keysOverride = new List<String>{
      unlocated.Key__c,
      'nowhere|zz|zz'
    };
    List<SplitLaneResult.Option> noUsablePlace = SplitEstimates.estimate(
      lane(escobedo, toronto),
      escobedo,
      toronto,
      'CAD',
      null
    );
    Integer queriesAfterThree = Limits.getQueries();
    Test.stopTest();
    System.assertEquals(0, noPoint.size(), 'no active handoff point');
    System.assertEquals(
      0,
      blind.size(),
      'an end without coordinates has no approximate distance'
    );
    System.assertEquals(
      queriesBefore,
      queriesAfterTwo,
      'neither case reads a place or a leg'
    );
    System.assertEquals(
      0,
      noUsablePlace.size(),
      'a point without coordinates, or a key without a place, is skipped'
    );
    System.assertEquals(
      queriesAfterTwo + 1,
      queriesAfterThree,
      'one place read and no leg read'
    );
  }

  @IsTest
  static void legReadsNameCarriersAndTakeMediansInTheCardCurrency() {
    Fx f = legFixture();
    SplitTestData.legLoad(
      f.g,
      f.escobedoDock,
      f.laredoYard,
      f.g.vendor,
      1000,
      'Delivered'
    );
    Test.startTest();
    // Made inside Test.startTest(): before it, the fixture and one load leave no room for a carrier (101 queries).
    Account crest = SplitTestData.carrier('Crest Freight', true);
    SplitTestData.legLoad(
      f.g,
      f.escobedoDock,
      f.laredoYard,
      f.g.vendor,
      1400,
      'Delivered'
    );
    SplitTestData.legLoad(
      f.g,
      f.laredoYard,
      f.g.destinationLocation,
      crest,
      3000,
      'Delivered'
    );
    List<SplitLaneResult.Option> cad = SplitEstimates.estimate(
      lane(f.escobedo, f.toronto),
      f.escobedo,
      f.toronto,
      'CAD',
      null
    );
    ExchangeRates.periodsOverride = new List<ExchangeRates.Period>{
      new ExchangeRates.Period(
        Date.today().addDays(-30),
        Date.newInstance(9999, 12, 31),
        0.72
      )
    };
    ExchangeRates rates = ExchangeRates.usd(Date.today().addDays(-400));
    List<SplitLaneResult.Option> usd = SplitEstimates.estimate(
      lane(f.escobedo, f.toronto),
      f.escobedo,
      f.toronto,
      'USD',
      rates
    );
    LaneSearchRequest intermodal = lane(f.escobedo, f.toronto);
    intermodal.modes = new List<String>{ 'Intermodal' };
    List<SplitLaneResult.Option> otherMode = SplitEstimates.estimate(
      intermodal,
      f.escobedo,
      f.toronto,
      'CAD',
      null
    );
    Integer callouts = Limits.getCallouts();
    Test.stopTest();
    System.assertEquals(1, cad.size());
    SplitLaneResult.Option viaLaredo = cad[0];
    System.assertEquals('Laredo, TX', viaLaredo.handoffLabel);
    System.assertEquals(
      'General Escobedo, NL → Laredo, TX',
      viaLaredo.legs[0].laneLabel
    );
    System.assertEquals(
      new List<String>{ 'Test Carrier (2)' },
      names(viaLaredo.legs[0]),
      'one carrier, two legs moved'
    );
    System.assertEquals(
      1200.00,
      viaLaredo.legs[0].median,
      'median of 1000 and 1400'
    );
    System.assertEquals(2, viaLaredo.legs[0].pricedCount);
    System.assertEquals(
      'Laredo, TX → Toronto, ON',
      viaLaredo.legs[1].laneLabel
    );
    System.assertEquals(
      new List<String>{ 'Crest Freight (1, blacklisted)' },
      names(viaLaredo.legs[1]),
      'a blacklisted carrier stays, flagged'
    );
    System.assertEquals(3000.00, viaLaredo.legs[1].median);
    System.assertEquals(1, viaLaredo.legs[1].pricedCount);
    System.assertEquals(
      4200.00,
      viaLaredo.medianTotal,
      'leg 1 median + leg 2 median'
    );
    System.assertEquals(
      864.00,
      usd[0].legs[0].median,
      'each CAD total x 0.72 before the median: 720 and 1008'
    );
    System.assertEquals(2160.00, usd[0].legs[1].median);
    System.assertEquals(3024.00, usd[0].medianTotal);
    System.assertEquals(Date.today().addDays(-30), rates.latestStartUsed);
    System.assertEquals(
      0,
      otherMode[0].legs[0].carriers.size(),
      'the mode filter applies to the leg loads'
    );
    System.assertEquals(0, otherMode[0].legs[1].carriers.size());
    System.assertEquals(null, otherMode[0].medianTotal);
    System.assertEquals(0, callouts, 'no Mapbox call');
  }

  @IsTest
  static void intercompanyAndCancelledLegLoadsAreLeftOutAndAnUnpricedLegGivesNoTotal() {
    Fx f = legFixture();
    SplitTestData.legLoad(
      f.g,
      f.escobedoDock,
      f.laredoYard,
      f.g.vendor,
      1000,
      'Delivered'
    );
    Test.startTest();
    Account sister = SplitTestData.carrier('Sister Org Carrier', false);
    IntercompanyCarriers.idsOverride = new Set<Id>{ sister.Id };
    SplitTestData.legLoad(
      f.g,
      f.escobedoDock,
      f.laredoYard,
      sister,
      800,
      'Delivered'
    );
    SplitTestData.legLoad(
      f.g,
      f.laredoYard,
      f.g.destinationLocation,
      f.g.vendor,
      3000,
      'Cancelled'
    );
    List<SplitLaneResult.Option> options = SplitEstimates.estimate(
      lane(f.escobedo, f.toronto),
      f.escobedo,
      f.toronto,
      'CAD',
      null
    );
    Test.stopTest();
    SplitLaneResult.Option viaLaredo = options[0];
    System.assertEquals(
      new List<String>{ 'Test Carrier (1)' },
      names(viaLaredo.legs[0]),
      'the intercompany carrier is left out'
    );
    System.assertEquals(
      1000.00,
      viaLaredo.legs[0].median,
      'with the intercompany load the median would be 900.00'
    );
    System.assertEquals(1, viaLaredo.legs[0].pricedCount);
    System.assertEquals(
      0,
      viaLaredo.legs[1].carriers.size(),
      'the only leg 2 load is cancelled'
    );
    System.assertEquals(null, viaLaredo.legs[1].median);
    System.assertEquals(0, viaLaredo.legs[1].pricedCount);
    System.assertEquals(
      null,
      viaLaredo.medianTotal,
      'a leg without a priced load leaves the estimate without a total'
    );
  }

  @IsTest
  static void legReadTakesTheMostRecent500MovedLoadsOfTheLastYear() {
    Pricing_Place__c escobedo = place(
      'General Escobedo',
      'NL',
      'MX',
      25.8000,
      -100.3167
    );
    Pricing_Place__c laredo = place('Laredo', 'TX', 'US', 27.5306, -99.4803);
    // Any Account Id will do: the SOQL is only built, never run.
    Id sisterOrg =
      Account.SObjectType.getDescribe().getKeyPrefix() +
      '00000000000' +
      '1';
    IntercompanyCarriers.idsOverride = new Set<Id>{ sisterOrg };
    Map<String, Object> binds = new Map<String, Object>();
    List<String> conditions = LaneQueries.legConditions(
      lane(escobedo, laredo),
      escobedo,
      LaneSearchRequest.Precision.CITY,
      null,
      laredo,
      LaneSearchRequest.Precision.CITY,
      null,
      binds
    );
    String soql = LaneQueries.legLoadSoql(
      conditions,
      SplitEstimates.LEG_DAYS,
      SplitEstimates.LEG_LIMIT,
      binds
    );
    System.assert(
      soql.endsWith(' ORDER BY CreatedDate DESC LIMIT 500'),
      'the most recent 500 per leg: ' + soql
    );
    System.assert(soql.contains('CreatedDate = LAST_N_DAYS:365'), soql);
    System.assert(
      soql.contains(
        'rtms__Carrier__c != null AND rtms__Carrier_Quote_Total__c > 0'
      ),
      'moved and priced only: ' + soql
    );
    System.assert(soql.contains('rtms__Load_Status__c != \'Cancelled\''), soql);
    System.assert(soql.contains('rtms__Carrier__c NOT IN :intercompany'), soql);
    System.assert(!soql.contains('rtms__Load__r.'), 'read on the load itself');
    System.assertEquals(new Set<Id>{ sisterOrg }, binds.get('intercompany'));
    System.assertEquals(0.10, SplitEstimates.MAX_EXTRA);
    System.assertEquals(3, SplitEstimates.MAX_POINTS);
  }
}
