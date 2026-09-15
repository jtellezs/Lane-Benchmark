/**
 * Carriers to ask, stage 1 (phase 8, Task 5). Every freight plan goes through SplitTestData.plan,
 * so these tests hold whichever way Task 1 proved plans reach a test (inserted, or built in memory
 * for FreightPlanReader). PricingTestDataFactory's load automation is not bulkified (its class doc:
 * three createLoad() calls in one context passed 100 queries), so each test creates at most one load
 * before Test.startTest() - the one whose quotes or date Test.setCreatedDate moves, which works only
 * there - and at most two inside. Every test that expects a carrier to be left out keeps another
 * carrier on the same lane, so stage 1 is never empty and a later stage cannot change the answer.
 *
 * Query budget (measured in PostProduc on 2026-09-15): the graph 33 queries, a load 35 to 37, the yard
 * 10 to 12, a carrier account 21 to 23 when it is not blacklisted but 6 to 8 when it is (the org's
 * Account flows), a quoter 3, the first quote insert 13 to 16, a plan 4 and find() at most 5. So only
 * the tests that build legs make the yard, a carrier whose blacklist flag no assertion reads is made
 * blacklisted (it is still listed), and the graph's carrier is the one that both quotes and moves a leg.
 */
@IsTest
private class CarrierLeadServiceTest {
  private static final String LIVE = 'Delivered';
  private static final String CANCELLED = 'Cancelled';

  private class Fx {
    PricingTestDataFactory.Graph g;
    Account yard;
  }

  /** A carrier with its own profile, quote contact and carrier service: Revenova keeps a quote's vendor equal to its service's carrier. */
  private class Quoter {
    Account carrier;
    Contact contact;
    rtms__CarrierService__c service;
  }

  private static Fx fx() {
    Fx f = new Fx();
    f.g = PricingTestDataFactory.createGraph();
    places();
    return f;
  }

  /**
   * Legs end at a yard off the lane, as real legs do, so no quote the automation might give a leg
   * can reach the lane's quote counts (Task 1 asserts the automation gives legs none).
   */
  private static void addYard(Fx f) {
    f.yard = PricingTestDataFactory.createLocation(
      'Kingston Yard',
      'Kingston',
      'Ontario',
      'Canada',
      'K7K 1A1',
      44.2312,
      -76.486
    );
  }

  /** Montreal and Toronto, the graph's lane ("Montreal, QC:Toronto, ON"), with no removal set. */
  private static void places() {
    RfpTestDataFactory.createPlace(
      'Montreal',
      'QC',
      'CA',
      45.5019,
      -73.5674,
      'H1A'
    );
    RfpTestDataFactory.createPlace(
      'Toronto',
      'ON',
      'CA',
      43.6532,
      -79.3832,
      'A1A'
    );
    LaneSearchExclusions.excludedContactIdsOverride = new Set<String>();
    IntercompanyCarriers.idsOverride = new Set<Id>();
    SplitTestData.resetPlans();
  }

  private static LaneSearchRequest montrealToToronto() {
    LaneSearchRequest req = new LaneSearchRequest();
    req.originKey = 'montreal|qc|ca';
    req.destinationKey = 'toronto|on|ca';
    return req;
  }

  private static rtms__Load__c laneLoad(Fx f) {
    return PricingTestDataFactory.createLoad(
      f.g,
      f.g.originLocation,
      f.g.destinationLocation
    );
  }

  private static rtms__Load__c leg(Fx f, Account carrier, String status) {
    return SplitTestData.legLoad(
      f.g,
      f.g.originLocation,
      f.yard,
      carrier,
      1000,
      status
    );
  }

  private static Quoter quoter(Fx f, Account carrier) {
    Quoter q = new Quoter();
    q.carrier = carrier;
    rtms__TransportationProfile__c profile = new rtms__TransportationProfile__c(
      Name = carrier.Name + ' Profile',
      RecordTypeId = Schema.SObjectType.rtms__TransportationProfile__c
        .getRecordTypeInfosByDeveloperName()
        .get('Carrier')
        .getRecordTypeId(),
      rtms__Company_Risk__c = 'Acceptable',
      rtms__Carrier_Remit_To__c = carrier.Id
    );
    insert profile;
    q.contact = new Contact(
      FirstName = 'Quote',
      LastName = carrier.Name,
      AccountId = carrier.Id,
      Email = 'quotes@example.invalid'
    );
    insert q.contact;
    q.service = new rtms__CarrierService__c(
      Name = carrier.Name + ' Service',
      rtms__Carrier__c = carrier.Id,
      rtms__Mode__c = f.g.mode.Id,
      rtms__Transportation_Profile__c = profile.Id,
      rtms__Quote_Contact__c = q.contact.Id,
      rtms__Minimum_Weight__c = 0,
      rtms__Maximum_Weight__c = 100000
    );
    insert q.service;
    return q;
  }

  /** An uninserted CAD quote on the load, by the quoter or, when it is null, by the graph's carrier. */
  private static rtms__CarrierQuote__c quote(
    Fx f,
    rtms__Load__c load,
    Quoter quotedBy,
    Boolean accepted
  ) {
    rtms__CarrierQuote__c q = PricingTestDataFactory.buildQuote(
      f.g,
      load,
      1000
    );
    if (quotedBy != null) {
      q.rtms__Carrier_Service__c = quotedBy.service.Id;
      q.rtms__Vendor__c = quotedBy.carrier.Id;
      q.rtms__Quote_Contact__c = quotedBy.contact.Id;
    }
    q.rtms__Accepted__c = accepted;
    return q;
  }

  private static CarrierLeadResult.Lead leadOf(
    CarrierLeadResult r,
    Id carrierId
  ) {
    for (CarrierLeadResult.Lead entry : r.leads) {
      if (entry.carrierId == carrierId) {
        return entry;
      }
    }
    return null;
  }

  private static CarrierLeadResult.Lead newLead(
    String name,
    Integer moved,
    Integer quoted,
    Date lastSeen
  ) {
    CarrierLeadResult.Lead entry = new CarrierLeadResult.Lead();
    entry.name = name;
    entry.loadsMoved = moved;
    entry.loadsQuoted = quoted;
    entry.lastSeen = lastSeen;
    return entry;
  }

  private static List<String> names(List<CarrierLeadResult.Lead> leads) {
    List<String> out = new List<String>();
    for (CarrierLeadResult.Lead entry : leads) {
      out.add(entry.name);
    }
    return out;
  }

  @IsTest
  static void quotesCountDistinctLoadsQuotedAndMovedPerCarrier() {
    Fx f = fx();
    Quoter black = quoter(f, SplitTestData.carrier('Black Freight', true));
    rtms__Load__c firstLoad = laneLoad(f);
    rtms__CarrierQuote__c acceptedQuote = quote(f, firstLoad, null, true);
    rtms__CarrierQuote__c declinedSameLoad = quote(f, firstLoad, null, false);
    rtms__CarrierQuote__c blackQuote = quote(f, firstLoad, black, false);
    insert new List<rtms__CarrierQuote__c>{
      acceptedQuote,
      declinedSameLoad,
      blackQuote
    };
    Datetime fortyDaysAgo = Datetime.now().addDays(-40);
    Test.setCreatedDate(acceptedQuote.Id, Datetime.now().addDays(-20));
    Test.setCreatedDate(declinedSameLoad.Id, Datetime.now().addDays(-5));
    Test.setCreatedDate(blackQuote.Id, fortyDaysAgo);
    Test.startTest();
    rtms__Load__c secondLoad = laneLoad(f);
    insert quote(f, secondLoad, null, false);
    CarrierLeadResult r = CarrierLeadService.find(montrealToToronto());
    Test.stopTest();

    System.assertEquals(CarrierLeadResult.SAME_LANE, r.stage);
    System.assertEquals(false, r.truncated);
    System.assertEquals(
      2,
      r.leads.size(),
      'the graph carrier and Black Freight'
    );
    CarrierLeadResult.Lead graphCarrier = r.leads[0];
    System.assertEquals(
      f.g.vendor.Id,
      graphCarrier.carrierId,
      'a load moved ranks first'
    );
    System.assertEquals('Test Carrier', graphCarrier.name);
    System.assertEquals(1, graphCarrier.loadsMoved, 'its accepted quote');
    System.assertEquals(
      2,
      graphCarrier.loadsQuoted,
      'three quotes on two loads count two loads'
    );
    System.assertEquals(
      Date.today(),
      graphCarrier.lastSeen,
      'its newest quote, made today on the second load'
    );
    System.assertEquals(
      new List<String>{ CarrierLeadResult.SOURCE_QUOTE },
      graphCarrier.sources
    );
    System.assertEquals(false, graphCarrier.blacklisted);
    System.assertEquals(
      true,
      graphCarrier.canOpen,
      'the running user reads the carrier account'
    );
    CarrierLeadResult.Lead blackCarrier = r.leads[1];
    System.assertEquals(black.carrier.Id, blackCarrier.carrierId);
    System.assertEquals('Black Freight', blackCarrier.name);
    System.assertEquals(0, blackCarrier.loadsMoved, 'its quote was declined');
    System.assertEquals(1, blackCarrier.loadsQuoted);
    System.assertEquals(fortyDaysAgo.date(), blackCarrier.lastSeen);
    System.assertEquals(
      true,
      blackCarrier.blacklisted,
      'Account.Black_List__c through rtms__Vendor__r (D5)'
    );
    System.assertEquals(true, blackCarrier.canOpen);
  }

  /** The graph's carrier quotes and moves a leg: a second unblacklisted carrier does not fit before Test.startTest(). */
  @IsTest
  static void splitLegCarriersCountFromTheirPlanAndMergeWithTheirQuotes() {
    Fx f = fx();
    addYard(f);
    rtms__Load__c customer = laneLoad(f);
    rtms__CarrierQuote__c graphQuote = quote(f, customer, null, false);
    insert graphQuote;
    Datetime tenDaysAgo = Datetime.now().addDays(-10);
    Test.setCreatedDate(customer.Id, tenDaysAgo);
    Test.setCreatedDate(graphQuote.Id, Datetime.now().addDays(-60));
    Test.startTest();
    Account bravo = SplitTestData.carrier('Bravo Freight', true);
    SplitTestData.plan(
      customer,
      new List<rtms__Load__c>{ leg(f, f.g.vendor, LIVE), leg(f, bravo, LIVE) }
    );
    CarrierLeadResult r = CarrierLeadService.find(montrealToToronto());
    Test.stopTest();

    System.assertEquals(CarrierLeadResult.SAME_LANE, r.stage);
    System.assertEquals(2, r.leads.size(), 'the two leg carriers');
    CarrierLeadResult.Lead merged = r.leads[0];
    System.assertEquals(
      f.g.vendor.Id,
      merged.carrierId,
      'a leg and a quote rank above a leg alone'
    );
    System.assertEquals('Test Carrier', merged.name);
    System.assertEquals(
      1,
      merged.loadsMoved,
      'its leg; its own quote was declined'
    );
    System.assertEquals(1, merged.loadsQuoted);
    System.assertEquals(
      tenDaysAgo.date(),
      merged.lastSeen,
      'the customer load date is later than its quote'
    );
    System.assertEquals(
      new List<String>{
        CarrierLeadResult.SOURCE_QUOTE,
        CarrierLeadResult.SOURCE_SPLIT_LEG
      },
      merged.sources
    );
    System.assertEquals(false, merged.blacklisted);
    CarrierLeadResult.Lead legOnly = r.leads[1];
    System.assertEquals(bravo.Id, legOnly.carrierId);
    System.assertEquals('Bravo Freight', legOnly.name);
    System.assertEquals(1, legOnly.loadsMoved);
    System.assertEquals(0, legOnly.loadsQuoted);
    System.assertEquals(
      tenDaysAgo.date(),
      legOnly.lastSeen,
      'a leg is dated by its customer load (R84)'
    );
    System.assertEquals(
      new List<String>{ CarrierLeadResult.SOURCE_SPLIT_LEG },
      legOnly.sources
    );
    System.assertEquals(
      true,
      legOnly.blacklisted,
      'Account.Black_List__c through the leg load carrier'
    );
    System.assertEquals(true, legOnly.canOpen);
  }

  @IsTest
  static void intercompanyCarriersAndTheExcludedContactAreLeftOut() {
    Fx f = fx();
    addYard(f);
    rtms__Load__c customer = laneLoad(f);
    Test.startTest();
    Quoter intercompanyQuotes = quoter(
      f,
      SplitTestData.carrier('Intercompany Quotes', false)
    );
    insert new List<rtms__CarrierQuote__c>{
      quote(f, customer, intercompanyQuotes, false),
      quote(f, customer, null, true)
    };
    SplitTestData.plan(
      customer,
      new List<rtms__Load__c>{ leg(f, f.g.vendor, LIVE) }
    );
    IntercompanyCarriers.idsOverride = new Set<Id>{
      intercompanyQuotes.carrier.Id
    };
    LaneSearchExclusions.excludedContactIdsOverride = new Set<String>{
      String.valueOf(f.g.quoteContact.Id).left(15)
    };
    CarrierLeadResult r = CarrierLeadService.find(montrealToToronto());
    Test.stopTest();

    System.assertEquals(
      null,
      leadOf(r, intercompanyQuotes.carrier.Id),
      'an intercompany vendor is left out of the quote counts (D6)'
    );
    System.assertEquals(1, r.leads.size(), 'only the graph carrier is left');
    CarrierLeadResult.Lead kept = r.leads[0];
    System.assertEquals(f.g.vendor.Id, kept.carrierId);
    System.assertEquals(
      0,
      kept.loadsQuoted,
      'its accepted quote came from the excluded contact'
    );
    System.assertEquals(
      1,
      kept.loadsMoved,
      'its leg still counts: the contact setting applies to quotes only (R89)'
    );
    System.assertEquals(
      new List<String>{ CarrierLeadResult.SOURCE_SPLIT_LEG },
      kept.sources
    );
  }

  @IsTest
  static void anIntercompanyLegCarrierIsLeftOut() {
    Fx f = fx();
    addYard(f);
    Account intercompanyLegs = SplitTestData.carrier('Intercompany Legs', true);
    rtms__Load__c customer = laneLoad(f);
    Test.startTest();
    SplitTestData.plan(
      customer,
      new List<rtms__Load__c>{
        leg(f, f.g.vendor, LIVE),
        leg(f, intercompanyLegs, LIVE)
      }
    );
    IntercompanyCarriers.idsOverride = new Set<Id>{ intercompanyLegs.Id };
    CarrierLeadResult r = CarrierLeadService.find(montrealToToronto());
    Test.stopTest();

    System.assertEquals(
      null,
      leadOf(r, intercompanyLegs.Id),
      'an intercompany leg carrier is left out (D6)'
    );
    System.assertEquals(1, r.leads.size(), 'the other leg carrier is kept');
    System.assertEquals(f.g.vendor.Id, r.leads[0].carrierId);
    System.assertEquals(1, r.leads[0].loadsMoved);
  }

  @IsTest
  static void cancelledLoadsAreLeftOutOfQuotes() {
    Fx f = fx();
    // On the lane, so its quote meets every quote-count condition but the status.
    rtms__Load__c cancelledLoad = SplitTestData.legLoad(
      f.g,
      f.g.originLocation,
      f.g.destinationLocation,
      f.g.vendor,
      1000,
      CANCELLED
    );
    Test.startTest();
    Quoter onCancelled = quoter(
      f,
      SplitTestData.carrier('Cancelled Quotes', false)
    );
    rtms__Load__c liveLoad = laneLoad(f);
    insert new List<rtms__CarrierQuote__c>{
      quote(f, cancelledLoad, onCancelled, false),
      quote(f, liveLoad, null, false)
    };
    CarrierLeadResult r = CarrierLeadService.find(montrealToToronto());
    Test.stopTest();

    System.assertEquals(
      null,
      leadOf(r, onCancelled.carrier.Id),
      'a quote on a cancelled load does not count'
    );
    System.assertEquals(1, r.leads.size(), 'the quote on the live load');
    System.assertEquals(f.g.vendor.Id, r.leads[0].carrierId);
  }

  @IsTest
  static void cancelledLoadsAreLeftOutOfLegs() {
    Fx f = fx();
    addYard(f);
    Account cancelledLegCarrier = SplitTestData.carrier('Cancelled Legs', true);
    rtms__Load__c cancelledLeg = leg(f, cancelledLegCarrier, CANCELLED);
    Test.startTest();
    rtms__Load__c customer = laneLoad(f);
    SplitTestData.plan(
      customer,
      new List<rtms__Load__c>{ cancelledLeg, leg(f, f.g.vendor, LIVE) }
    );
    CarrierLeadResult r = CarrierLeadService.find(montrealToToronto());
    Test.stopTest();

    System.assertEquals(
      null,
      leadOf(r, cancelledLegCarrier.Id),
      'a cancelled leg does not count'
    );
    System.assertEquals(1, r.leads.size(), 'the live leg carrier');
    System.assertEquals(f.g.vendor.Id, r.leads[0].carrierId);
  }

  @IsTest
  static void quotesOlderThanThreeYearsAreLeftOut() {
    Fx f = fx();
    Quoter stale = quoter(f, SplitTestData.carrier('Stale Freight', true));
    rtms__Load__c load = laneLoad(f);
    rtms__CarrierQuote__c tooOld = quote(f, load, stale, true);
    rtms__CarrierQuote__c inWindow = quote(f, load, null, false);
    insert new List<rtms__CarrierQuote__c>{ tooOld, inWindow };
    Datetime thousandDaysAgo = Datetime.now().addDays(-1000);
    Test.setCreatedDate(tooOld.Id, Datetime.now().addDays(-1100));
    Test.setCreatedDate(inWindow.Id, thousandDaysAgo);
    Test.startTest();
    CarrierLeadResult r = CarrierLeadService.find(montrealToToronto());
    Test.stopTest();

    System.assertEquals(
      null,
      leadOf(r, stale.carrier.Id),
      'a quote from 1,100 days ago is outside the 3 years'
    );
    System.assertEquals(1, r.leads.size());
    System.assertEquals(f.g.vendor.Id, r.leads[0].carrierId);
    System.assertEquals(thousandDaysAgo.date(), r.leads[0].lastSeen);
  }

  @IsTest
  static void modeEquipmentAndHazmatApplyButCurrencyLookbackAcceptedAndSourceDoNot() {
    Fx f = fx();
    rtms__Load__c load = laneLoad(f); // Truckload, Dry Van 53' (Van), not hazmat
    rtms__CarrierQuote__c acceptedQuote = quote(f, load, null, true); // CAD
    insert acceptedQuote;
    Test.setCreatedDate(acceptedQuote.Id, Datetime.now().addDays(-30));
    LaneSearchRequest ignored = montrealToToronto();
    ignored.currencyIsoCode = 'USD';
    ignored.lookbackDays = 1;
    ignored.acceptedFilter = LaneSearchRequest.Accepted.DECLINED;
    ignored.sourceFilter = LaneSearchRequest.RowSource.BIDS;
    LaneSearchRequest matching = montrealToToronto();
    matching.modes = new List<String>{ 'Truckload' };
    matching.equipmentCategories = new List<String>{ 'Van' };
    LaneSearchRequest otherMode = montrealToToronto();
    otherMode.modes = new List<String>{ 'LTL' };
    LaneSearchRequest otherEquipment = montrealToToronto();
    otherEquipment.equipmentTypes = new List<String>{ 'Reefer 53\'' };
    LaneSearchRequest hazmatOnly = montrealToToronto();
    hazmatOnly.hazmatOnly = true;
    Test.startTest();
    CarrierLeadResult rIgnored = CarrierLeadService.find(ignored);
    CarrierLeadResult rMatching = CarrierLeadService.find(matching);
    CarrierLeadResult rOtherMode = CarrierLeadService.find(otherMode);
    CarrierLeadResult rOtherEquipment = CarrierLeadService.find(otherEquipment);
    CarrierLeadResult rHazmat = CarrierLeadService.find(hazmatOnly);
    Test.stopTest();

    System.assertEquals(
      1,
      rIgnored.leads.size(),
      'a CAD accepted quote from 30 days ago still counts for a USD, 1-day, declined-only, bids-only request (R101)'
    );
    System.assertEquals(1, rIgnored.leads[0].loadsMoved);
    System.assertEquals(1, rIgnored.leads[0].loadsQuoted);
    System.assertEquals(
      1,
      rMatching.leads.size(),
      'the load matches the mode and equipment'
    );
    System.assertEquals(0, rOtherMode.leads.size(), 'mode filter applies');
    System.assertEquals(CarrierLeadResult.NONE, rOtherMode.stage);
    System.assertEquals(
      0,
      rOtherEquipment.leads.size(),
      'equipment filter applies'
    );
    System.assertEquals(0, rHazmat.leads.size(), 'hazmat filter applies');
  }

  @IsTest
  static void aBlankKeyOrAMissingPlaceGivesNoneAfterOnlyThePlacesRead() {
    places();
    LaneSearchRequest blank = montrealToToronto();
    blank.destinationKey = '  ';
    LaneSearchRequest missing = montrealToToronto();
    missing.destinationKey = 'nowhere|zz|ca';
    Test.startTest();
    Integer atStart = Limits.getQueries();
    CarrierLeadResult rBlank = CarrierLeadService.find(blank);
    Integer afterBlank = Limits.getQueries();
    CarrierLeadResult rMissing = CarrierLeadService.find(missing);
    Integer afterMissing = Limits.getQueries();
    Test.stopTest();

    System.assertEquals(0, afterBlank - atStart, 'a blank key reads nothing');
    System.assertEquals(
      1,
      afterMissing - afterBlank,
      'a missing place stops after the places read'
    );
    for (
      CarrierLeadResult r : new List<CarrierLeadResult>{ rBlank, rMissing }
    ) {
      System.assertEquals(CarrierLeadResult.NONE, r.stage);
      System.assertEquals(0, r.leads.size());
      System.assertEquals(false, r.truncated);
    }
  }

  @IsTest
  static void theQueryRowCheckStopsBeforeTheFirstCountAndMarksTheListIncomplete() {
    places();
    CarrierLeadService.rowReserve = Limits.getLimitQueryRows() + 1;
    Test.startTest();
    Integer atStart = Limits.getQueries();
    CarrierLeadResult r = CarrierLeadService.find(montrealToToronto());
    Integer used = Limits.getQueries() - atStart;
    Test.stopTest();

    System.assertEquals(1, used, 'only the places read ran');
    System.assertEquals(true, r.truncated, 'The list may be incomplete');
    System.assertEquals(CarrierLeadResult.NONE, r.stage);
    System.assertEquals(0, r.leads.size());
  }

  @IsTest
  static void leadsRankByLoadsMovedThenLoadsQuotedThenLastSeenThenName() {
    Date yesterday = Date.today().addDays(-1);
    List<CarrierLeadResult.Lead> leads = new List<CarrierLeadResult.Lead>{
      newLead('Aaron', 1, 3, null),
      newLead('Bravo', 1, 3, yesterday),
      newLead('able', 1, 3, yesterday),
      newLead('Alpha', 1, 5, Date.today().addDays(-200)),
      newLead('Zulu', 2, 0, Date.today().addDays(-400))
    };
    System.assertEquals(
      new List<String>{ 'Zulu', 'Alpha', 'able', 'Bravo', 'Aaron' },
      names(CarrierLeadService.ranked(leads, true)),
      'loads moved, then loads quoted, then the newest last seen with none last, then the name ignoring case'
    );
    System.assertEquals(
      new List<String>{ 'Zulu', 'able', 'Bravo', 'Alpha', 'Aaron' },
      names(CarrierLeadService.ranked(leads, false)),
      'without loads quoted (stage 2): loads moved, then last seen, then the name'
    );
    System.assertEquals(
      'Aaron',
      leads[0].name,
      'ranked returns a new list and leaves its input alone'
    );
  }

  @IsTest
  static void aResultSerializesNamesAndCountsButNeverAnAmount() {
    CarrierLeadResult.Lead entry = new CarrierLeadResult.Lead();
    entry.carrierId = UserInfo.getUserId();
    entry.name = 'Alpha Freight';
    entry.loadsMoved = 3;
    entry.loadsQuoted = 4;
    entry.lastSeen = Date.today();
    entry.sources.add(CarrierLeadResult.SOURCE_QUOTE);
    entry.blacklisted = true;
    entry.canOpen = true;
    CarrierLeadResult result = new CarrierLeadResult();
    result.leads.add(entry);
    result.stage = CarrierLeadResult.STATE_LANE;
    result.stateLaneLabel = 'QC to ON';
    result.truncated = true;

    Map<String, Object> top = (Map<String, Object>) JSON.deserializeUntyped(
      JSON.serialize(result)
    );
    System.assertEquals(
      new Set<String>{ 'leads', 'stage', 'stateLaneLabel', 'truncated' },
      top.keySet(),
      'the result has no amount field (R106)'
    );
    Map<String, Object> firstLead = (Map<String, Object>) ((List<Object>) top.get(
      'leads'
    ))[0];
    System.assertEquals(
      new Set<String>{
        'carrierId',
        'name',
        'loadsMoved',
        'loadsQuoted',
        'lastSeen',
        'sources',
        'blacklisted',
        'canOpen'
      },
      firstLead.keySet(),
      'a lead has no amount field (R106)'
    );
    System.assertEquals(CarrierLeadResult.NONE, new CarrierLeadResult().stage);
  }
}
