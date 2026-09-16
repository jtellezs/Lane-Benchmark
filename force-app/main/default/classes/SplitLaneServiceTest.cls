/**
 * Split-lane history (phase 8). End-to-end tests build one shipment each through
 * SplitTestData (a customer load and two leg loads; three createLoad() calls do not fit one governor
 * window, see PricingTestDataFactory's class doc, so one load is made before Test.startTest() and two
 * inside it). The graph's own carrier (Test Carrier, not blacklisted) moves leg 1 and the blacklisted
 * Fletes Mex is made inside Test.startTest(): a Carrier account costs 21-23 queries (6-8 when
 * blacklisted), and the graph, two locations and one load already take 90 of the 100 queries before
 * Test.startTest() (measured 2026-09-15; the rest of each test takes 86-88 inside it). Grouping,
 * ordering, the R85 total and the left-out shipments run on shipments built in memory through
 * SplitLaneService.groupHistory.
 */
@IsTest
private class SplitLaneServiceTest {
  private static final String YARD = 'SFMN Park ITC Laredo yard';
  private static final String ESCOBEDO_LAREDO = 'General Escobedo, NL:Laredo, TX';
  private static final String LAREDO_ST_AUGUSTIN = 'Laredo, TX:St-Augustin-de-Desmaures, QC';
  private static Map<String, Id> fakeCarrierIds = new Map<String, Id>();

  /** The graph (its carrier moves leg 1), a Monterrey plant, the Laredo yard and the lane's two places. No load; each test makes the blacklisted Fletes Mex inside Test.startTest(). */
  private class Fx {
    PricingTestDataFactory.Graph g;
    Account monterrey;
    Account laredoYard;
    Account fletes;
  }

  private static Fx fixture() {
    Fx f = new Fx();
    f.g = PricingTestDataFactory.createGraph();
    f.monterrey = PricingTestDataFactory.createLocation(
      'Monterrey Plant',
      'Monterrey',
      'Nuevo León',
      'Mexico',
      '64000',
      25.6866,
      -100.3161
    );
    f.laredoYard = PricingTestDataFactory.createLocation(
      YARD,
      'Laredo',
      'Texas',
      'United States',
      '78045',
      27.5306,
      -99.4803
    );
    createLanePlaces();
    IntercompanyCarriers.idsOverride = new Set<Id>();
    return f;
  }

  private static void createLanePlaces() {
    RfpTestDataFactory.createPlace(
      'Monterrey',
      'NL',
      'MX',
      25.6866,
      -100.3161,
      '640'
    );
    RfpTestDataFactory.createPlace(
      'Toronto',
      'ON',
      'CA',
      43.6532,
      -79.3832,
      'M5V'
    );
  }

  private static LaneSearchRequest request(
    String originKey,
    String destinationKey
  ) {
    LaneSearchRequest r = new LaneSearchRequest();
    r.originKey = originKey;
    r.destinationKey = destinationKey;
    return r;
  }

  private static LaneSearchRequest monterreyToToronto() {
    return request('monterrey|nl|mx', 'toronto|on|ca');
  }

  /** A never inserted Account Id per carrier name: the grouping compares carrier Ids only. */
  private static Id fakeCarrierId(String name) {
    if (!fakeCarrierIds.containsKey(name)) {
      fakeCarrierIds.put(
        name,
        Id.valueOf(
          Account.SObjectType.getDescribe().getKeyPrefix() +
          String.valueOf(fakeCarrierIds.size() + 1).leftPad(12, '0')
        )
      );
    }
    return fakeCarrierIds.get(name);
  }

  /** A delivered leg created now, in memory: its carrier, city lane, last stop account name and CAD total. */
  private static SplitLaneService.LegRow leg(
    String carrier,
    String cityLane,
    String stopName,
    Decimal cadTotal
  ) {
    SplitLaneService.LegRow row = new SplitLaneService.LegRow();
    row.carrierId = fakeCarrierId(carrier);
    row.carrierName = carrier;
    row.cityLane = cityLane;
    row.stopName = stopName;
    row.cadTotal = cadTotal;
    row.status = 'Delivered';
    row.created = Datetime.now();
    return row;
  }

  private static List<SplitLaneService.LegRow> twoLegs(
    SplitLaneService.LegRow legOne,
    SplitLaneService.LegRow legTwo
  ) {
    return new List<SplitLaneService.LegRow>{ legOne, legTwo };
  }

  /**
   * One shipment Monterrey -> Laredo yard -> Toronto, end to end: the plan rows reach the history
   * with the handoff city from leg 1's lane, the yard from leg 1's last stop account, each leg's
   * carrier and blacklist flag, lane and CAD total. Then the same lane with leg 2's carrier on the
   * intercompany list has no group.
   */
  @IsTest
  static void historyReadsTheLanePlanWithItsHandoffCarriersAndCosts() {
    Fx f = fixture();
    rtms__Load__c customer = PricingTestDataFactory.createLoad(
      f.g,
      f.monterrey,
      f.g.destinationLocation
    );
    Test.startTest();
    f.fletes = SplitTestData.carrier('Fletes Mex', true);
    rtms__Load__c toLaredo = SplitTestData.legLoad(
      f.g,
      f.monterrey,
      f.laredoYard,
      f.g.vendor,
      1200,
      'Delivered'
    );
    rtms__Load__c toToronto = SplitTestData.legLoad(
      f.g,
      f.laredoYard,
      f.g.destinationLocation,
      f.fletes,
      2400,
      'Delivered'
    );
    SplitTestData.plan(
      customer,
      new List<rtms__Load__c>{ toLaredo, toToronto }
    );
    SplitLaneResult inCad = SplitLaneService.options(
      monterreyToToronto(),
      'CAD'
    );
    IntercompanyCarriers.idsOverride = new Set<Id>{ f.fletes.Id };
    SplitLaneResult withIntercompanyLeg = SplitLaneService.options(
      monterreyToToronto(),
      'CAD'
    );
    Test.stopTest();

    System.assertEquals('CAD', inCad.currencyCode, 'the card currency');
    System.assertEquals(null, inCad.message, 'a group, no message');
    System.assertEquals(null, inCad.rateStartDate, 'no exchange rate in CAD');
    System.assertEquals(false, inCad.truncated, 'one plan');
    System.assertEquals(1, inCad.options.size(), 'one handoff group');
    SplitLaneResult.Option o = inCad.options[0];
    System.assertEquals('History', o.kind, 'a history group');
    System.assertEquals(
      'Laredo, TX · ' + YARD,
      o.handoffLabel,
      'city from leg 1 lane, yard from leg 1 last stop account'
    );
    System.assertEquals(1, o.shipments, 'one shipment');
    System.assertEquals(null, o.extraDistancePct, 'history has no distance');
    System.assertEquals(
      2,
      o.legs.size(),
      'the two carrier legs, not the customer row'
    );
    SplitLaneResult.Leg legOne = o.legs[0];
    System.assertEquals(1, legOne.position, 'leg 1');
    System.assertEquals(
      'Monterrey, NL → Laredo, TX',
      legOne.laneLabel,
      'leg 1 lane with an arrow'
    );
    System.assertEquals(1, legOne.carriers.size(), 'one leg 1 carrier');
    System.assertEquals(
      f.g.vendor.Id,
      legOne.carriers[0].carrierId,
      'the leg load carrier'
    );
    System.assertEquals('Test Carrier', legOne.carriers[0].name, 'its name');
    System.assertEquals(1, legOne.carriers[0].legsMoved, 'one leg moved');
    System.assertEquals(
      false,
      legOne.carriers[0].blacklisted,
      'not blacklisted'
    );
    System.assertEquals(1200.00, legOne.median, 'leg 1 CAD total');
    System.assertEquals(2, legOne.median.scale(), 'amounts at scale 2');
    System.assertEquals(1, legOne.pricedCount, 'one priced leg');
    SplitLaneResult.Leg legTwo = o.legs[1];
    System.assertEquals(2, legTwo.position, 'leg 2');
    System.assertEquals(
      'Laredo, TX → Toronto, ON',
      legTwo.laneLabel,
      'leg 2 lane with an arrow'
    );
    System.assertEquals(
      f.fletes.Id,
      legTwo.carriers[0].carrierId,
      'leg 2 carrier'
    );
    System.assertEquals(
      true,
      legTwo.carriers[0].blacklisted,
      'from the leg carrier Black_List__c'
    );
    System.assertEquals(2400.00, legTwo.median, 'leg 2 CAD total');
    System.assertEquals(3600.00, o.medianTotal, 'the shipment sum');
    System.assertEquals(1, o.pricedShipments, 'every leg priced');

    System.assertEquals(
      0,
      withIntercompanyLeg.options.size(),
      'a shipment with an intercompany leg carrier is left out'
    );
    System.assertEquals(
      SplitLaneService.NO_OPTION_MESSAGE,
      withIntercompanyLeg.message,
      'no history group and no handoff place in a test: the no-option message'
    );
  }

  /**
   * USD: each leg's CAD total is converted at the dated rate of its own load's CreatedDate. Leg 1 was
   * created 60 days ago, inside the first period (0.80); leg 2 today, on or after the last period's
   * start (0.75). Test.setCreatedDate only works before Test.startTest(), so leg 1 is the load made
   * before it.
   */
  @IsTest
  static void usdConvertsEachLegAtTheRateOfItsLoadDate() {
    Fx f = fixture();
    rtms__Load__c toLaredo = SplitTestData.legLoad(
      f.g,
      f.monterrey,
      f.laredoYard,
      f.g.vendor,
      1000,
      'Delivered'
    );
    Test.setCreatedDate(toLaredo.Id, Datetime.now().addDays(-60));
    Date lastStart = Date.today().addDays(-30);
    ExchangeRates.periodsOverride = new List<ExchangeRates.Period>{
      new ExchangeRates.Period(Date.today().addDays(-400), lastStart, 0.80),
      new ExchangeRates.Period(lastStart, Date.newInstance(9999, 12, 31), 0.75)
    };
    Test.startTest();
    f.fletes = SplitTestData.carrier('Fletes Mex', true);
    rtms__Load__c customer = PricingTestDataFactory.createLoad(
      f.g,
      f.monterrey,
      f.g.destinationLocation
    );
    rtms__Load__c toToronto = SplitTestData.legLoad(
      f.g,
      f.laredoYard,
      f.g.destinationLocation,
      f.fletes,
      2000,
      'Delivered'
    );
    SplitTestData.plan(
      customer,
      new List<rtms__Load__c>{ toLaredo, toToronto }
    );
    SplitLaneResult inUsd = SplitLaneService.options(
      monterreyToToronto(),
      'USD'
    );
    Test.stopTest();

    System.assertEquals('USD', inUsd.currencyCode, 'the card currency');
    System.assertEquals(null, inUsd.message, 'rates exist');
    System.assertEquals(1, inUsd.options.size(), 'one group');
    SplitLaneResult.Option o = inUsd.options[0];
    System.assertEquals(
      800.00,
      o.legs[0].median,
      '1000 CAD x 0.80, the period holding the leg load date'
    );
    System.assertEquals(
      1500.00,
      o.legs[1].median,
      '2000 CAD x 0.75, the last period'
    );
    System.assertEquals(2300.00, o.medianTotal, 'the converted legs summed');
    System.assertEquals(
      lastStart,
      inUsd.rateStartDate,
      'the start of the latest period used'
    );
  }

  @IsTest
  static void usdWithoutADatedRateGivesAMessageAndReadsNoPlan() {
    createLanePlaces();
    ExchangeRates.periodsOverride = new List<ExchangeRates.Period>();
    Test.startTest();
    Integer queriesAtStart = Limits.getQueries();
    SplitLaneResult inUsd = SplitLaneService.options(
      monterreyToToronto(),
      'USD'
    );
    Integer queriesUsed = Limits.getQueries() - queriesAtStart;
    Test.stopTest();
    System.assertEquals(
      'No USD exchange rate is available.',
      inUsd.message,
      'no dated USD rate'
    );
    System.assertEquals(0, inUsd.options.size(), 'no option');
    System.assertEquals('USD', inUsd.currencyCode, 'the card currency');
    System.assertEquals(null, inUsd.rateStartDate, 'no rate used');
    System.assertEquals(1, queriesUsed, 'the places read only, no plan read');
  }

  @IsTest
  static void aBlankKeyOrAnUnknownPlaceGivesAMessage() {
    createLanePlaces();
    Test.startTest();
    Integer queriesAtStart = Limits.getQueries();
    SplitLaneResult blankOrigin = SplitLaneService.options(
      request(' ', 'toronto|on|ca'),
      'CAD'
    );
    Integer blankQueries = Limits.getQueries() - queriesAtStart;
    SplitLaneResult unknownOrigin = SplitLaneService.options(
      request('nowhere|nl|mx', 'toronto|on|ca'),
      'CAD'
    );
    Integer unknownQueries =
      Limits.getQueries() -
      queriesAtStart -
      blankQueries;
    Test.stopTest();
    System.assertEquals(
      'Both ends of the lane need a place.',
      blankOrigin.message,
      'a blank key'
    );
    System.assertEquals(0, blankOrigin.options.size(), 'no option');
    System.assertEquals(0, blankQueries, 'a blank key reads nothing');
    System.assertEquals(
      'Both ends of the lane need a place.',
      unknownOrigin.message,
      'a key without a place'
    );
    System.assertEquals(0, unknownOrigin.options.size(), 'no option');
    System.assertEquals(1, unknownQueries, 'the places read only');
  }

  /**
   * The plan read the history runs, whether plan rows are inserted or built in memory: customer loads on the lane
   * over 365 days, at most 1000 plans, with each leg's amount, lane, status and last stop account.
   */
  @IsTest
  static void historyReadsAYearOfLanePlansWithTheirLegCosts() {
    Pricing_Place__c monterrey = new Pricing_Place__c(
      Key__c = 'monterrey|nl|mx',
      City__c = 'Monterrey',
      Province__c = 'NL',
      Country__c = 'MX',
      Postal_Prefix__c = '640'
    );
    Pricing_Place__c toronto = new Pricing_Place__c(
      Key__c = 'toronto|on|ca',
      City__c = 'Toronto',
      Province__c = 'ON',
      Country__c = 'CA',
      Postal_Prefix__c = 'M5V'
    );
    Map<String, Object> binds = new Map<String, Object>();
    String soql = SplitLaneService.historySoql(
      monterreyToToronto(),
      monterrey,
      toronto,
      binds
    );
    for (
      String part : new List<String>{
        'FROM rtms__FreightPlan__c',
        'rtms__Type__c = \'Customer\'',
        'rtms__Load__r.rtms__City_Lane__c LIKE :oCity',
        'rtms__Load__r.rtms__City_Lane__c LIKE :dCity',
        'rtms__Load__r.CreatedDate = LAST_N_DAYS:365',
        'rtms__Load__r.rtms__Load_Status__c != \'Cancelled\'',
        'rtms__Load__r.rtms__Carrier_Quote_Total__c',
        'rtms__Load__r.rtms__Last_Stop__r.rtms__Location2__r.Name',
        'LIMIT 1000'
      }
    ) {
      System.assert(soql.contains(part), 'missing ' + part + ' in ' + soql);
    }
    System.assert(
      binds.containsKey('oCity') && binds.containsKey('dCity'),
      'city binds for both ends: ' + binds.keySet()
    );
  }

  /**
   * Four shipments via the Laredo yard make one group. Shipment 3 writes the handoff in capitals and
   * still joins it; shipment 4's second leg has a zero total, so it is priced on leg 1 only and stays
   * out of the total. The total is the median of each fully priced shipment's own sum (R85): 5000,
   * while the two leg medians add up to 3600.
   */
  @IsTest
  static void shipmentsViaOneHandoffShareAGroupAndTheTotalIsTheMedianOfTheirSums() {
    SplitLaneService.LegRow blacklistedFletes = leg(
      'Fletes Mex',
      LAREDO_ST_AUGUSTIN,
      'Client DC',
      5000
    );
    blacklistedFletes.blacklisted = true;
    List<List<SplitLaneService.LegRow>> shipments = new List<List<SplitLaneService.LegRow>>{
      twoLegs(
        leg('Q Transportes', ESCOBEDO_LAREDO, YARD, 1000),
        leg('Fletes Mex', LAREDO_ST_AUGUSTIN, 'Client DC', 1000)
      ),
      twoLegs(
        leg('Q Transportes', ESCOBEDO_LAREDO, YARD, 2000),
        blacklistedFletes
      ),
      twoLegs(
        leg(
          'Xpress Norte',
          'Apodaca, NL:LAREDO, TX',
          'SFMN PARK ITC LAREDO YARD',
          3000
        ),
        leg('Maple Freight', LAREDO_ST_AUGUSTIN, 'Client DC', 2000)
      ),
      twoLegs(
        leg('Q Transportes', ESCOBEDO_LAREDO, YARD, 1200),
        leg('Nord Cartage', LAREDO_ST_AUGUSTIN, 'Client DC', 0)
      )
    };
    IntercompanyCarriers.idsOverride = new Set<Id>();

    List<SplitLaneResult.Option> groups = SplitLaneService.groupHistory(
      shipments,
      'CAD',
      null
    );

    System.assertEquals(1, groups.size(), 'one handoff, whatever its capitals');
    SplitLaneResult.Option o = groups[0];
    System.assertEquals('History', o.kind, 'a history group');
    System.assertEquals(
      'Laredo, TX · ' + YARD,
      o.handoffLabel,
      'the first spelling seen'
    );
    System.assertEquals(4, o.shipments, 'four shipments');
    SplitLaneResult.Leg legOne = o.legs[0];
    System.assertEquals(
      'General Escobedo, NL → Laredo, TX',
      legOne.laneLabel,
      'the most frequent leg 1 lane'
    );
    System.assertEquals(2, legOne.carriers.size(), 'two leg 1 carriers');
    System.assertEquals(
      'Q Transportes',
      legOne.carriers[0].name,
      'most legs first'
    );
    System.assertEquals(3, legOne.carriers[0].legsMoved, 'three legs');
    System.assertEquals(
      'Xpress Norte',
      legOne.carriers[1].name,
      'then one leg'
    );
    System.assertEquals(
      1600.00,
      legOne.median,
      'median of 1000, 1200, 2000 and 3000'
    );
    System.assertEquals(4, legOne.pricedCount, 'four priced legs');
    SplitLaneResult.Leg legTwo = o.legs[1];
    System.assertEquals(2, legTwo.position, 'leg 2');
    System.assertEquals(
      'Laredo, TX → St-Augustin-de-Desmaures, QC',
      legTwo.laneLabel,
      'leg 2 lane'
    );
    System.assertEquals(3, legTwo.carriers.size(), 'three leg 2 carriers');
    System.assertEquals('Fletes Mex', legTwo.carriers[0].name, 'two legs');
    System.assertEquals(2, legTwo.carriers[0].legsMoved, 'two legs moved');
    System.assertEquals(
      true,
      legTwo.carriers[0].blacklisted,
      'blacklisted on one of its legs'
    );
    System.assertEquals(
      'Maple Freight',
      legTwo.carriers[1].name,
      'then by name'
    );
    System.assertEquals(
      'Nord Cartage',
      legTwo.carriers[2].name,
      'a carrier without a priced total still shows'
    );
    System.assertEquals(
      2000.00,
      legTwo.median,
      'median of 1000, 2000 and 5000: a zero total is not priced'
    );
    System.assertEquals(3, legTwo.pricedCount, 'three priced legs');
    System.assertEquals(
      5000.00,
      o.medianTotal,
      'median of the shipment sums 2000, 7000 and 5000'
    );
    System.assertEquals(3, o.pricedShipments, 'shipment 4 has an unpriced leg');
    System.assertNotEquals(
      legOne.median + legTwo.median,
      o.medianTotal,
      'not the sum of the leg medians (R85)'
    );
  }

  /**
   * Left out, all via Laredo: a shipment with a cancelled leg, one with an intercompany leg carrier
   * and a plan with a single carrier leg. Laredo keeps its two good shipments and comes first; the
   * one-shipment groups follow by label. A three-leg shipment joins its two handoffs with an arrow; a
   * handoff without a stop account name is the city alone; a leg position without any priced total
   * shows its carrier with no median, and its group has no total.
   */
  @IsTest
  static void unusableShipmentsAreLeftOutAndGroupsAreOrdered() {
    SplitLaneService.LegRow cancelledLeg = leg(
      'Fletes Mex',
      LAREDO_ST_AUGUSTIN,
      'Client DC',
      2000
    );
    cancelledLeg.status = 'Cancelled';
    List<List<SplitLaneService.LegRow>> shipments = new List<List<SplitLaneService.LegRow>>{
      twoLegs(
        leg('Q Transportes', ESCOBEDO_LAREDO, YARD, 1000),
        leg('Fletes Mex', LAREDO_ST_AUGUSTIN, 'Client DC', 2000)
      ),
      twoLegs(
        leg('Baja Linea', 'Tijuana, BC:San Diego, CA', 'Otay Mesa yard', 800),
        leg('Pacific Haul', 'San Diego, CA:Vancouver, BC', 'Client DC', null)
      ),
      twoLegs(leg('Q Transportes', ESCOBEDO_LAREDO, YARD, 1000), cancelledLeg),
      twoLegs(
        leg('Tpml TP org', ESCOBEDO_LAREDO, YARD, 900),
        leg('Fletes Mex', LAREDO_ST_AUGUSTIN, 'Client DC', 2000)
      ),
      new List<SplitLaneService.LegRow>{
        leg(
          'Q Transportes',
          'General Escobedo, NL:St-Augustin-de-Desmaures, QC',
          'Client DC',
          3000
        )
      },
      twoLegs(
        leg('Baja Linea', 'Mexicali, BC:Calexico, CA', null, 700),
        leg('Desert Freight', 'Calexico, CA:Vancouver, BC', 'Client DC', 1500)
      ),
      new List<SplitLaneService.LegRow>{
        leg('Q Transportes', ESCOBEDO_LAREDO, YARD, 1000),
        leg('Tex Relay', 'Laredo, TX:Dallas, TX', 'Dallas cross dock', 600),
        leg('Fletes Mex', 'Dallas, TX:Toronto, ON', 'Client DC', 1800)
      },
      twoLegs(
        leg('Q Transportes', ESCOBEDO_LAREDO, YARD, 1400),
        leg('Fletes Mex', LAREDO_ST_AUGUSTIN, 'Client DC', 2200)
      )
    };
    IntercompanyCarriers.idsOverride = new Set<Id>{
      fakeCarrierId('Tpml TP org')
    };

    List<SplitLaneResult.Option> groups = SplitLaneService.groupHistory(
      shipments,
      'CAD',
      null
    );

    List<String> summary = new List<String>();
    for (SplitLaneResult.Option o : groups) {
      summary.add(o.handoffLabel + ' / ' + o.shipments);
    }
    System.assertEquals(
      new List<String>{
        'Laredo, TX · SFMN Park ITC Laredo yard / 2',
        'Calexico, CA / 1',
        'Laredo, TX · SFMN Park ITC Laredo yard → Dallas, TX · Dallas cross dock / 1',
        'San Diego, CA · Otay Mesa yard / 1'
      },
      summary,
      'most shipments first, then by label; cancelled, intercompany and one-leg shipments left out'
    );
    SplitLaneResult.Option laredo = groups[0];
    System.assertEquals(
      1200.00,
      laredo.legs[0].median,
      'median of 1000 and 1400 only'
    );
    System.assertEquals(3300.00, laredo.medianTotal, 'median of 3000 and 3600');
    SplitLaneResult.Option threeLegs = groups[2];
    System.assertEquals(3, threeLegs.legs.size(), 'three leg positions');
    System.assertEquals(3, threeLegs.legs[2].position, 'leg 3');
    System.assertEquals(
      'Dallas, TX → Toronto, ON',
      threeLegs.legs[2].laneLabel,
      'leg 3 lane'
    );
    System.assertEquals(3400.00, threeLegs.medianTotal, '1000 + 600 + 1800');
    SplitLaneResult.Option sanDiego = groups[3];
    SplitLaneResult.Leg unpricedLeg = sanDiego.legs[1];
    System.assertEquals(
      'Pacific Haul',
      unpricedLeg.carriers[0].name,
      'the carrier shows'
    );
    System.assertEquals(null, unpricedLeg.median, 'no priced total, no median');
    System.assertEquals(0, unpricedLeg.pricedCount, 'nothing priced');
    System.assertEquals(800.00, sanDiego.legs[0].median, 'leg 1 is priced');
    System.assertEquals(
      null,
      sanDiego.medianTotal,
      'no shipment has every leg priced'
    );
    System.assertEquals(0, sanDiego.pricedShipments, 'no priced shipment');
  }

  @IsTest
  static void medianTakesTheMiddleOrTheMeanOfTheTwoMiddlesAtScaleTwo() {
    System.assertEquals(
      200.00,
      SplitLaneService.median(new List<Decimal>{ 300, 100, 200 }),
      'odd count: the middle value'
    );
    System.assertEquals(
      250.00,
      SplitLaneService.median(new List<Decimal>{ 400, 100, 300, 200 }),
      'even count: the mean of the two middle values'
    );
    Decimal half = SplitLaneService.median(new List<Decimal>{ 1, 2 });
    System.assertEquals(1.50, half, 'the mean of 1 and 2');
    System.assertEquals(2, half.scale(), 'scale 2');
    System.assertEquals(
      2,
      SplitLaneService.median(new List<Decimal>{ 1234.5 }).scale(),
      'one value, scale 2'
    );
    System.assertEquals(
      null,
      SplitLaneService.median(new List<Decimal>()),
      'empty'
    );
    System.assertEquals(null, SplitLaneService.median(null), 'null');
    List<Decimal> input = new List<Decimal>{ 3, 1, 2 };
    SplitLaneService.median(input);
    System.assertEquals(3, input[0], 'the caller list keeps its order');
  }

  @IsTest
  static void amountInKeepsCadAndConvertsUsdAtTheLoadDate() {
    ExchangeRates.periodsOverride = new List<ExchangeRates.Period>{
      new ExchangeRates.Period(
        Date.newInstance(2026, 1, 5),
        Date.newInstance(2026, 1, 12),
        0.80
      ),
      new ExchangeRates.Period(
        Date.newInstance(2026, 1, 12),
        Date.newInstance(9999, 12, 31),
        0.75
      )
    };
    ExchangeRates rates = ExchangeRates.usd(Date.newInstance(2025, 12, 1));
    Datetime inFirstPeriod = Datetime.newInstanceGmt(2026, 1, 8, 12, 0, 0);
    System.assertEquals(
      1234.567,
      SplitLaneService.amountIn('CAD', rates, 1234.567, inFirstPeriod),
      'CAD is the stored amount, unrounded'
    );
    System.assertEquals(
      1234.567,
      SplitLaneService.amountIn('CAD', null, 1234.567, inFirstPeriod),
      'CAD needs no rate'
    );
    System.assertEquals(
      987.6536,
      SplitLaneService.amountIn('USD', rates, 1234.567, inFirstPeriod),
      'CAD x the rate of the period holding the load date, unrounded'
    );
    System.assertEquals(
      750.0,
      SplitLaneService.amountIn(
        'USD',
        rates,
        1000,
        Datetime.newInstanceGmt(2026, 3, 1, 12, 0, 0)
      ),
      'after the last period start: the last rate'
    );
    System.assertEquals(
      Date.newInstance(2026, 1, 12),
      rates.latestStartUsed,
      'the latest period used'
    );
    System.assertEquals(
      null,
      SplitLaneService.amountIn('USD', null, 1000, inFirstPeriod),
      'USD without rates has no amount'
    );
  }

  @IsTest
  static void carrierTallyCountsLegsAndSortsByLegsThenName() {
    SplitLaneService.CarrierTally tally = new SplitLaneService.CarrierTally();
    Id zeta = fakeCarrierId('Zeta Freight');
    Id alpha = fakeCarrierId('alpha Haul');
    Id busy = fakeCarrierId('Busy Lines');
    tally.add(zeta, 'Zeta Freight', false);
    tally.add(busy, 'Busy Lines', false);
    tally.add(alpha, 'alpha Haul', null);
    tally.add(busy, 'Busy Lines', true);
    tally.add(null, 'No Carrier', true);
    List<SplitLaneResult.LegCarrier> ranked = tally.sorted();
    System.assertEquals(3, ranked.size(), 'a leg without a carrier is ignored');
    System.assertEquals(busy, ranked[0].carrierId, 'most legs first');
    System.assertEquals(2, ranked[0].legsMoved, 'two legs');
    System.assertEquals(
      true,
      ranked[0].blacklisted,
      'blacklisted when any leg says so'
    );
    System.assertEquals(
      'alpha Haul',
      ranked[1].name,
      'then by name, ignoring case'
    );
    System.assertEquals(
      false,
      ranked[1].blacklisted,
      'a null flag is not blacklisted'
    );
    System.assertEquals('Zeta Freight', ranked[2].name, 'last by name');
    System.assertEquals(1, ranked[2].legsMoved, 'one leg');
    System.assertEquals(
      0,
      new SplitLaneService.CarrierTally().sorted().size(),
      'an empty tally'
    );
  }

  @IsTest
  static void aLaneWithoutSplitHistoryGetsEstimates() {
    Pricing_Place__c escobedo = RfpTestDataFactory.createPlace(
      'General Escobedo',
      'NL',
      'MX',
      25.8000,
      -100.3167,
      '660'
    );
    Pricing_Place__c laredo = RfpTestDataFactory.createPlace(
      'Laredo',
      'TX',
      'US',
      27.5306,
      -99.4803,
      '780'
    );
    Pricing_Place__c toronto = RfpTestDataFactory.createPlace(
      'Toronto',
      'ON',
      'CA',
      43.6532,
      -79.3832,
      'M5V'
    );
    HandoffPoints.keysOverride = new List<String>{ laredo.Key__c };
    IntercompanyCarriers.idsOverride = new Set<Id>();
    LaneSearchRequest req = new LaneSearchRequest();
    req.originKey = escobedo.Key__c;
    req.destinationKey = toronto.Key__c;
    Test.startTest();
    SplitLaneResult result = SplitLaneService.options(req, 'CAD');
    Test.stopTest();
    System.assertEquals(null, result.message);
    System.assertEquals(1, result.options.size(), 'one estimate, via Laredo');
    System.assertEquals(SplitLaneResult.ESTIMATE, result.options[0].kind);
    System.assertEquals('Laredo, TX', result.options[0].handoffLabel);
    System.assertEquals(0, result.options[0].shipments);
    System.assertEquals(
      'General Escobedo, NL → Laredo, TX',
      result.options[0].legs[0].laneLabel
    );
  }

  @IsTest
  static void aLaneWithSplitHistoryGetsNoEstimate() {
    PricingTestDataFactory.Graph g = PricingTestDataFactory.createGraph();
    Account escobedoDock = PricingTestDataFactory.createLocation(
      'Escobedo Dock',
      'General Escobedo',
      'Nuevo León',
      'Mexico',
      '66050',
      25.8000,
      -100.3167
    );
    Account laredoYard = PricingTestDataFactory.createLocation(
      'Laredo Yard',
      'Laredo',
      'Texas',
      'United States',
      '78045',
      27.5306,
      -99.4803
    );
    Pricing_Place__c escobedo = RfpTestDataFactory.createPlace(
      'General Escobedo',
      'NL',
      'MX',
      25.8000,
      -100.3167,
      '660'
    );
    Pricing_Place__c laredo = RfpTestDataFactory.createPlace(
      'Laredo',
      'TX',
      'US',
      27.5306,
      -99.4803,
      '780'
    );
    Pricing_Place__c toronto = RfpTestDataFactory.createPlace(
      'Toronto',
      'ON',
      'CA',
      43.6532,
      -79.3832,
      'M5V'
    );
    HandoffPoints.keysOverride = new List<String>{ laredo.Key__c };
    IntercompanyCarriers.idsOverride = new Set<Id>();
    rtms__Load__c customerLoad = PricingTestDataFactory.createLoad(
      g,
      escobedoDock,
      g.destinationLocation
    );
    Test.startTest();
    rtms__Load__c legOne = SplitTestData.legLoad(
      g,
      escobedoDock,
      laredoYard,
      g.vendor,
      1000,
      'Delivered'
    );
    rtms__Load__c legTwo = SplitTestData.legLoad(
      g,
      laredoYard,
      g.destinationLocation,
      g.vendor,
      3000,
      'Delivered'
    );
    SplitTestData.plan(customerLoad, new List<rtms__Load__c>{ legOne, legTwo });
    LaneSearchRequest req = new LaneSearchRequest();
    req.originKey = escobedo.Key__c;
    req.destinationKey = toronto.Key__c;
    SplitLaneResult result = SplitLaneService.options(req, 'CAD');
    Test.stopTest();
    System.assertEquals(1, result.options.size(), 'the history group only');
    System.assertEquals(
      SplitLaneResult.HISTORY,
      result.options[0].kind,
      'estimates run only when history finds no group'
    );
    System.assertEquals(1, result.options[0].shipments);
    System.assertEquals(null, result.message);
  }

  @IsTest
  static void noHistoryAndNoCloseHandoffPointGiveTheNoOptionMessage() {
    Pricing_Place__c escobedo = RfpTestDataFactory.createPlace(
      'General Escobedo',
      'NL',
      'MX',
      25.8000,
      -100.3167,
      '660'
    );
    Pricing_Place__c toronto = RfpTestDataFactory.createPlace(
      'Toronto',
      'ON',
      'CA',
      43.6532,
      -79.3832,
      'M5V'
    );
    Pricing_Place__c sanDiego = RfpTestDataFactory.createPlace(
      'San Diego',
      'CA',
      'US',
      32.7157,
      -117.1611,
      '921'
    );
    IntercompanyCarriers.idsOverride = new Set<Id>();
    LaneSearchRequest req = new LaneSearchRequest();
    req.originKey = escobedo.Key__c;
    req.destinationKey = toronto.Key__c;
    Test.startTest();
    HandoffPoints.keysOverride = new List<String>{ sanDiego.Key__c };
    SplitLaneResult tooFar = SplitLaneService.options(req, 'CAD');
    HandoffPoints.keysOverride = new List<String>();
    SplitLaneResult noPoint = SplitLaneService.options(req, 'CAD');
    Test.stopTest();
    String expected = 'No split shipment on this lane in the last 12 months, and no handoff point is close enough for an estimate.';
    System.assertEquals(expected, SplitLaneService.NO_OPTION_MESSAGE);
    System.assertEquals(0, tooFar.options.size(), 'San Diego adds 92.8 %');
    System.assertEquals(expected, tooFar.message);
    System.assertEquals(0, noPoint.options.size());
    System.assertEquals(expected, noPoint.message);
  }
}
