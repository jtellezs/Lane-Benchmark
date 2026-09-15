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

  // ---- Task 6: stage 2, the state or province lane ----

  /** A carrier the way Revenova quotes it: account, quote contact, transportation profile, service. */
  private class StateLaneCarrier {
    Account carrierAccount;
    Contact quoteContact;
    rtms__TransportationProfile__c carrierProfile;
    rtms__CarrierService__c carrierService;
  }

  /**
   * The stage 2 helpers. An inner class used through an instance, so its loops stay out of this
   * class's PMD complexity total (Task 5's tests already use 28 of 40); no name here can clash with
   * Task 5's helpers.
   */
  private class StateLaneFixtures {
    /** No excluded contact; the intercompany list is the test's (custom metadata cannot be inserted). */
    void settings(Set<Id> intercompany) {
      IntercompanyCarriers.idsOverride = intercompany;
      LaneSearchExclusions.excludedContactIdsOverride = new Set<String>();
    }

    /**
     * Carriers keyed by name, one insert per object, each built like createGraph builds the graph's
     * vendor. A quote's rtms__Vendor__c is its carrier service's carrier on every recent PostProduc
     * quote, so each carrier quotes through its own service and contact (as in Task 5's tests). One
     * list per object keeps the Account and Revenova automation to one pass before Test.startTest().
     * Measured 2026-09-15: that pass costs 17 to 23 queries for carriers that are not blacklisted and
     * 6 to 8 for blacklisted ones, whether the list holds 2 or 51. So the carriers are blacklisted: no
     * stage 2 assertion reads the flag, and a blacklisted carrier is still listed.
     */
    Map<String, StateLaneCarrier> carriers(
      PricingTestDataFactory.Graph g,
      List<String> carrierNames
    ) {
      Map<String, StateLaneCarrier> byName = new Map<String, StateLaneCarrier>();
      List<Account> accounts = new List<Account>();
      for (String carrierName : carrierNames) {
        StateLaneCarrier c = new StateLaneCarrier();
        c.carrierAccount = new Account(
          Name = carrierName,
          RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
            .get('Carrier')
            .getRecordTypeId(),
          rtms__TMS_Type__c = 'Carrier (Ground)',
          Black_List__c = true,
          CurrencyIsoCode = 'CAD'
        );
        byName.put(carrierName, c);
        accounts.add(c.carrierAccount);
      }
      insert accounts;
      List<Contact> contacts = new List<Contact>();
      List<rtms__TransportationProfile__c> profiles = new List<rtms__TransportationProfile__c>();
      for (StateLaneCarrier c : byName.values()) {
        c.quoteContact = new Contact(
          FirstName = 'Quote',
          LastName = c.carrierAccount.Name,
          AccountId = c.carrierAccount.Id,
          Email = 'quote' + contacts.size() + '@example.invalid',
          Phone = '514-555-0100'
        );
        c.carrierProfile = new rtms__TransportationProfile__c(
          Name = c.carrierAccount.Name + ' Profile',
          RecordTypeId = Schema.SObjectType.rtms__TransportationProfile__c.getRecordTypeInfosByDeveloperName()
            .get('Carrier')
            .getRecordTypeId(),
          rtms__Company_Risk__c = 'Acceptable',
          rtms__Carrier_Remit_To__c = c.carrierAccount.Id
        );
        contacts.add(c.quoteContact);
        profiles.add(c.carrierProfile);
      }
      insert contacts;
      insert profiles;
      List<rtms__CarrierService__c> services = new List<rtms__CarrierService__c>();
      for (StateLaneCarrier c : byName.values()) {
        c.carrierService = new rtms__CarrierService__c(
          Name = c.carrierAccount.Name + ' Service',
          rtms__Carrier__c = c.carrierAccount.Id,
          rtms__Mode__c = g.mode.Id,
          rtms__Transportation_Profile__c = c.carrierProfile.Id,
          rtms__Quote_Contact__c = c.quoteContact.Id,
          rtms__Minimum_Weight__c = 0,
          rtms__Maximum_Weight__c = 100000
        );
        services.add(c.carrierService);
      }
      insert services;
      return byName;
    }

    /** A quote by the given carrier, through its own service and contact; uninserted. */
    rtms__CarrierQuote__c quote(
      PricingTestDataFactory.Graph g,
      rtms__Load__c load,
      StateLaneCarrier carrier,
      Boolean accepted
    ) {
      rtms__CarrierQuote__c q = PricingTestDataFactory.buildQuote(
        g,
        load,
        1000
      );
      q.rtms__Carrier_Service__c = carrier.carrierService.Id;
      q.rtms__Vendor__c = carrier.carrierAccount.Id;
      q.rtms__Quote_Contact__c = carrier.quoteContact.Id;
      q.rtms__Accepted__c = accepted;
      return q;
    }

    /** City precision on both ends (the LaneSearchRequest defaults). */
    LaneSearchRequest request(String originKey, String destinationKey) {
      LaneSearchRequest r = new LaneSearchRequest();
      r.originKey = originKey;
      r.destinationKey = destinationKey;
      return r;
    }

    /** 'Carrier 01', 'Carrier 02', ... up to count. */
    List<String> numberedNames(Integer count) {
      List<String> out = new List<String>();
      for (Integer i = 1; i <= count; i++) {
        out.add('Carrier ' + String.valueOf(i).leftPad(2, '0'));
      }
      return out;
    }

    List<String> leadNames(CarrierLeadResult r) {
      List<String> out = new List<String>();
      for (CarrierLeadResult.Lead entry : r.leads) {
        out.add(entry.name);
      }
      return out;
    }
  }

  /**
   * R81: stage 2 runs only when stage 1 has no carrier left after the removals. Laval to Toronto has
   * one quote (Alpha); Montréal to Toronto is on the same state lane QC:ON but not on that city
   * lane (Beta). Once Alpha is intercompany, stage 1 is empty and stage 2 names Beta.
   */
  @IsTest
  static void stateLaneRunsOnlyWhenTheSameLaneHasNoCarrierLeft() {
    StateLaneFixtures fixtures = new StateLaneFixtures();
    fixtures.settings(new Set<Id>());
    PricingTestDataFactory.Graph g = PricingTestDataFactory.createGraph();
    RfpTestDataFactory.createPlace(
      'Laval',
      'QC',
      'CA',
      45.6066,
      -73.7124,
      'H7P'
    );
    RfpTestDataFactory.createPlace(
      'Toronto',
      'ON',
      'CA',
      43.6532,
      -79.3832,
      'M5V'
    );
    Map<String, StateLaneCarrier> carriers = fixtures.carriers(
      g,
      new List<String>{ 'Alpha Lane Carrier', 'Beta State Carrier' }
    );
    rtms__Load__c montrealToronto = PricingTestDataFactory.createLoad(
      g,
      g.originLocation,
      g.destinationLocation
    );
    insert fixtures.quote(
      g,
      montrealToronto,
      carriers.get('Beta State Carrier'),
      true
    );
    Test.startTest();
    // Inside Test.startTest(): graph 33, carriers 6-8, contacts 3, a load 35 and a quote 12 fill the
    // context before it, and the Laval location (12) would pass 100 (measured 2026-09-15).
    Account lavalCo = PricingTestDataFactory.createLocation(
      'Laval Co',
      'Laval',
      'Quebec',
      'Canada',
      'H7P 1T2',
      45.6066,
      -73.7124
    );
    rtms__Load__c lavalToronto = PricingTestDataFactory.createLoad(
      g,
      lavalCo,
      g.destinationLocation
    );
    insert fixtures.quote(
      g,
      lavalToronto,
      carriers.get('Alpha Lane Carrier'),
      false
    );
    CarrierLeadResult sameLane = CarrierLeadService.find(
      fixtures.request('laval|qc|ca', 'toronto|on|ca')
    );
    IntercompanyCarriers.idsOverride = new Set<Id>{
      carriers.get('Alpha Lane Carrier').carrierAccount.Id
    };
    CarrierLeadResult afterRemoval = CarrierLeadService.find(
      fixtures.request('laval|qc|ca', 'toronto|on|ca')
    );
    Test.stopTest();
    System.assertEquals(
      CarrierLeadResult.SAME_LANE,
      sameLane.stage,
      JSON.serialize(sameLane)
    );
    System.assertEquals(
      new List<String>{ 'Alpha Lane Carrier' },
      fixtures.leadNames(sameLane),
      'stage 2 never mixes with stage 1'
    );
    System.assertEquals(
      null,
      sameLane.stateLaneLabel,
      'no state lane label on stage 1'
    );
    System.assertEquals(
      CarrierLeadResult.STATE_LANE,
      afterRemoval.stage,
      'an intercompany carrier leaves stage 1 empty: ' +
      JSON.serialize(afterRemoval)
    );
    System.assertEquals(
      new List<String>{ 'Beta State Carrier' },
      fixtures.leadNames(afterRemoval),
      'the intercompany carrier is left out of stage 2 as well'
    );
    System.assertEquals(
      'QC to ON',
      afterRemoval.stateLaneLabel,
      'the stage 2 wording names the state lane'
    );
    System.assertEquals(1, afterRemoval.leads[0].loadsMoved, 'accepted');
    System.assertEquals(1, afterRemoval.leads[0].loadsQuoted, 'quoted');
    System.assertEquals(
      new List<String>{ CarrierLeadResult.SOURCE_QUOTE },
      afterRemoval.leads[0].sources,
      'a quote source only'
    );
  }

  /**
   * R82 and R97: stage 2 ranks by loads moved, then last seen, and shows its top 10. Carrier 12
   * moved the load 12 days ago; Carrier 01 to 11 only quoted it, 1 to 11 days ago.
   */
  @IsTest
  static void stateLaneKeepsTheTopTenByLoadsMovedThenLastSeen() {
    StateLaneFixtures fixtures = new StateLaneFixtures();
    PricingTestDataFactory.Graph g = PricingTestDataFactory.createGraph();
    RfpTestDataFactory.createPlace(
      'Laval',
      'QC',
      'CA',
      45.6066,
      -73.7124,
      'H7P'
    );
    RfpTestDataFactory.createPlace(
      'Toronto',
      'ON',
      'CA',
      43.6532,
      -79.3832,
      'M5V'
    );
    fixtures.settings(new Set<Id>());
    List<String> names = new List<String>();
    for (Integer i = 1; i <= 12; i++) {
      names.add('Carrier ' + String.valueOf(i).leftPad(2, '0'));
    }
    Map<String, StateLaneCarrier> carriers = fixtures.carriers(g, names);
    rtms__Load__c montrealToronto = PricingTestDataFactory.createLoad(
      g,
      g.originLocation,
      g.destinationLocation
    );
    List<rtms__CarrierQuote__c> quotes = new List<rtms__CarrierQuote__c>();
    for (Integer i = 1; i <= 12; i++) {
      quotes.add(
        fixtures.quote(g, montrealToronto, carriers.get(names[i - 1]), i == 12)
      );
    }
    insert quotes;
    for (Integer i = 1; i <= 12; i++) {
      Test.setCreatedDate(quotes[i - 1].Id, Datetime.now().addDays(-i));
    }
    Test.startTest();
    CarrierLeadResult r = CarrierLeadService.find(
      fixtures.request('laval|qc|ca', 'toronto|on|ca')
    );
    Test.stopTest();
    System.assertEquals(
      CarrierLeadResult.STATE_LANE,
      r.stage,
      JSON.serialize(r)
    );
    System.assertEquals('QC to ON', r.stateLaneLabel, 'the label');
    System.assertEquals(
      new List<String>{
        'Carrier 12',
        'Carrier 01',
        'Carrier 02',
        'Carrier 03',
        'Carrier 04',
        'Carrier 05',
        'Carrier 06',
        'Carrier 07',
        'Carrier 08',
        'Carrier 09'
      },
      fixtures.leadNames(r),
      'loads moved first, then the latest quote; Carrier 10 and 11 fall past the top 10'
    );
    System.assertEquals(
      false,
      r.truncated,
      'the top 10 cut does not mark the list incomplete'
    );
    System.assertEquals(1, r.leads[0].loadsMoved, 'Carrier 12 moved it');
    System.assertEquals(
      Datetime.now().addDays(-1).date(),
      r.leads[1].lastSeen,
      'Carrier 01 was last seen a day ago'
    );
  }

  /**
   * R102: NL is both Newfoundland and Labrador and Nuevo León, so both loads below carry the state
   * lane NL:QC. Only the load whose first stop account is in Canada counts for Corner Brook, NL, CA.
   * A stop account with a blank ShippingCountry fails the same equality, so its load never counts
   * (spec §3); no extra load is built for it, to keep the fixture budget.
   */
  @IsTest
  static void stateLaneCountsOnlyLoadsWhoseStopsAreInEachPlacesCountry() {
    StateLaneFixtures fixtures = new StateLaneFixtures();
    fixtures.settings(new Set<Id>());
    PricingTestDataFactory.Graph g = PricingTestDataFactory.createGraph();
    Account newfoundland = PricingTestDataFactory.createLocation(
      'Newfoundland Co',
      'St. John\'s',
      'Newfoundland and Labrador',
      'Canada',
      'A1B 3T2',
      47.5615,
      -52.7126
    );
    RfpTestDataFactory.createPlace(
      'Corner Brook',
      'NL',
      'CA',
      48.949,
      -57.9503,
      'A2H'
    );
    RfpTestDataFactory.createPlace(
      'Montréal',
      'QC',
      'CA',
      45.5019,
      -73.5674,
      'H1A'
    );
    Map<String, StateLaneCarrier> carriers = fixtures.carriers(
      g,
      new List<String>{ 'Canada Carrier', 'Mexico Carrier' }
    );
    rtms__Load__c fromCanada = PricingTestDataFactory.createLoad(
      g,
      newfoundland,
      g.originLocation
    );
    Test.startTest();
    // Inside Test.startTest(): graph 33, the Newfoundland location 12, carriers 6-8, contacts 3 and a
    // load 35 fill the context before it; the Canadian quote (12) and the Mexican location (10) would
    // pass 100 there (measured 2026-09-15). Neither needs Test.setCreatedDate.
    insert fixtures.quote(g, fromCanada, carriers.get('Canada Carrier'), true);
    Account nuevoLeon = PricingTestDataFactory.createLocation(
      'Nuevo Leon Co',
      'Monterrey',
      'Nuevo León',
      'Mexico',
      '64000',
      25.6866,
      -100.3161
    );
    rtms__Load__c fromMexico = PricingTestDataFactory.createLoad(
      g,
      nuevoLeon,
      g.originLocation
    );
    insert fixtures.quote(g, fromMexico, carriers.get('Mexico Carrier'), true);
    CarrierLeadResult r = CarrierLeadService.find(
      fixtures.request('corner brook|nl|ca', 'montreal|qc|ca')
    );
    String mexicanStateLane = [
      SELECT rtms__State_Lane__c
      FROM rtms__Load__c
      WHERE Id = :fromMexico.Id
    ]
    .rtms__State_Lane__c;
    Test.stopTest();
    System.assertEquals(
      'NL:QC',
      mexicanStateLane,
      'precondition: the Mexican load carries the same state lane key'
    );
    System.assertEquals(
      CarrierLeadResult.STATE_LANE,
      r.stage,
      JSON.serialize(r)
    );
    System.assertEquals('NL to QC', r.stateLaneLabel, 'the label');
    System.assertEquals(
      new List<String>{ 'Canada Carrier' },
      fixtures.leadNames(r),
      'a load whose first stop is in Mexico is not on a Canadian NL lane'
    );
  }

  /**
   * Stage 2 counts the carrier legs of split shipments whose customer load is on the state lane,
   * dated by the customer load (R84). Called through stateLaneLeads, because a plan built by
   * SplitTestData in memory (Task 1, branch B) would also answer stage 1's plan read.
   */
  @IsTest
  static void stateLaneCountsTheLegsOfSplitShipments() {
    StateLaneFixtures fixtures = new StateLaneFixtures();
    fixtures.settings(new Set<Id>());
    PricingTestDataFactory.Graph g = PricingTestDataFactory.createGraph();
    Pricing_Place__c laval = RfpTestDataFactory.createPlace(
      'Laval',
      'QC',
      'CA',
      45.6066,
      -73.7124,
      'H7P'
    );
    Pricing_Place__c toronto = RfpTestDataFactory.createPlace(
      'Toronto',
      'ON',
      'CA',
      43.6532,
      -79.3832,
      'M5V'
    );
    Account legCarrier = SplitTestData.carrier('Leg Carrier', true);
    // The leg ends at a Quebec yard (state lane QC:QC), off QC:ON, so no quote the automation might
    // give a leg can reach the stage 2 quote counts (Task 1 asserts it gives legs none).
    Account yard = PricingTestDataFactory.createLocation(
      'Drummondville Yard',
      'Drummondville',
      'Quebec',
      'Canada',
      'J2C 1A1',
      45.8833,
      -72.4833
    );
    rtms__Load__c customerLoad = PricingTestDataFactory.createLoad(
      g,
      g.originLocation,
      g.destinationLocation
    );
    Test.startTest();
    rtms__Load__c leg = SplitTestData.legLoad(
      g,
      g.originLocation,
      yard,
      legCarrier,
      900,
      'Delivered'
    );
    SplitTestData.plan(customerLoad, new List<rtms__Load__c>{ leg });
    CarrierLeadResult r = CarrierLeadService.stateLaneLeads(
      fixtures.request(laval.Key__c, toronto.Key__c),
      laval,
      toronto,
      new CarrierLeadResult()
    );
    Date customerDay = [
        SELECT CreatedDate
        FROM rtms__Load__c
        WHERE Id = :customerLoad.Id
      ]
      .CreatedDate.date();
    Test.stopTest();
    SplitTestData.resetPlans();
    System.assertEquals(
      CarrierLeadResult.STATE_LANE,
      r.stage,
      JSON.serialize(r)
    );
    System.assertEquals(1, r.leads.size(), 'the leg carrier');
    CarrierLeadResult.Lead entry = r.leads[0];
    System.assertEquals('Leg Carrier', entry.name, 'by name');
    System.assertEquals(1, entry.loadsMoved, 'one leg load moved');
    System.assertEquals(0, entry.loadsQuoted, 'no quote');
    System.assertEquals(
      new List<String>{ CarrierLeadResult.SOURCE_SPLIT_LEG },
      entry.sources,
      'a split leg source only'
    );
    System.assertEquals(
      customerDay,
      entry.lastSeen,
      'dated by the customer load'
    );
    System.assertEquals(true, entry.blacklisted, 'the badge stays');
    System.assertEquals('QC to ON', r.stateLaneLabel, 'the label');
  }

  /**
   * Stage 2 is skipped when both ends used province keys (R95), when a place has a blank province,
   * and when a place's country has no stop country name (LaneQueries.COUNTRY_NAMES); a French place
   * then names nobody, without an error.
   */
  @IsTest
  static void stateLaneIsSkippedForProvinceEndsBlankProvincesAndOtherCountries() {
    StateLaneFixtures fixtures = new StateLaneFixtures();
    fixtures.settings(new Set<Id>());
    Pricing_Place__c quebec = new Pricing_Place__c(
      Key__c = 'laval|qc|ca',
      City__c = 'Laval',
      Province__c = 'QC',
      Country__c = 'CA'
    );
    Pricing_Place__c ontario = new Pricing_Place__c(
      Key__c = 'toronto|on|ca',
      City__c = 'Toronto',
      Province__c = 'ON',
      Country__c = 'CA'
    );
    Pricing_Place__c noProvince = new Pricing_Place__c(
      Key__c = 'nowhere||ca',
      City__c = 'Nowhere',
      Country__c = 'CA'
    );
    Pricing_Place__c paris = RfpTestDataFactory.createPlace(
      'Paris',
      'IDF',
      'FR',
      48.8566,
      2.3522,
      '750'
    );
    Pricing_Place__c toronto = RfpTestDataFactory.createPlace(
      'Toronto',
      'ON',
      'CA',
      43.6532,
      -79.3832,
      'M5V'
    );
    LaneSearchRequest cityEnds = fixtures.request(
      'laval|qc|ca',
      'toronto|on|ca'
    );
    LaneSearchRequest provinceEnds = fixtures.request(
      'laval|qc|ca',
      'toronto|on|ca'
    );
    provinceEnds.originPrecision = LaneSearchRequest.Precision.PROVINCE;
    provinceEnds.destinationPrecision = LaneSearchRequest.Precision.PROVINCE;
    LaneSearchRequest oneProvinceEnd = fixtures.request(
      'laval|qc|ca',
      'toronto|on|ca'
    );
    oneProvinceEnd.originPrecision = LaneSearchRequest.Precision.PROVINCE;
    Map<String, Object> binds = new Map<String, Object>();
    Test.startTest();
    List<String> conditions = CarrierLeadService.stateLane(
      cityEnds,
      quebec,
      ontario,
      binds
    );
    CarrierLeadResult french = CarrierLeadService.find(
      fixtures.request(paris.Key__c, toronto.Key__c)
    );
    Test.stopTest();
    System.assertNotEquals(null, conditions, 'city ends read the state lane');
    System.assert(
      conditions.contains('rtms__Load__r.rtms__State_Lane__c = :stateLane'),
      String.join(conditions, ' AND ')
    );
    System.assertEquals('QC:ON', binds.get('stateLane'), 'the state lane key');
    System.assertEquals('Canada', binds.get('oCountry'), 'origin country');
    System.assertEquals('Canada', binds.get('dCountry'), 'destination country');
    System.assertEquals(
      null,
      CarrierLeadService.stateLane(
        provinceEnds,
        quebec,
        ontario,
        new Map<String, Object>()
      ),
      'both ends on province keys: stage 1 already read that lane'
    );
    System.assertNotEquals(
      null,
      CarrierLeadService.stateLane(
        oneProvinceEnd,
        quebec,
        ontario,
        new Map<String, Object>()
      ),
      'one province end does not skip stage 2'
    );
    System.assertEquals(
      null,
      CarrierLeadService.stateLane(
        cityEnds,
        quebec,
        noProvince,
        new Map<String, Object>()
      ),
      'a blank destination province'
    );
    System.assertEquals(
      null,
      CarrierLeadService.stateLane(
        cityEnds,
        noProvince,
        ontario,
        new Map<String, Object>()
      ),
      'a blank origin province'
    );
    System.assertEquals(
      null,
      CarrierLeadService.stateLane(
        cityEnds,
        paris,
        ontario,
        new Map<String, Object>()
      ),
      'FR has no stop country name'
    );
    System.assertEquals(
      CarrierLeadResult.NONE,
      french.stage,
      JSON.serialize(french)
    );
    System.assertEquals(0, french.leads.size(), 'nobody');
    System.assertEquals(null, french.stateLaneLabel, 'no label');
  }

  /**
   * Controller ruling 2026-09-15: a 51st carrier group marks only stage 1 incomplete, because stage
   * 2's groups come back ordered by loads, so its top 10 is exact. 51 carriers each move the Montréal
   * to Toronto load. Searched as Montréal to Toronto, stage 1 reaches the group cap and says so;
   * searched as Laval to Toronto, stage 1 is empty and stage 2 keeps 10 without the note.
   */
  @IsTest
  static void stateLaneIgnoresTheGroupCap() {
    StateLaneFixtures fixtures = new StateLaneFixtures();
    fixtures.settings(new Set<Id>());
    PricingTestDataFactory.Graph g = PricingTestDataFactory.createGraph();
    RfpTestDataFactory.createPlace(
      'Montreal',
      'QC',
      'CA',
      45.5019,
      -73.5674,
      'H1A'
    );
    RfpTestDataFactory.createPlace(
      'Laval',
      'QC',
      'CA',
      45.6066,
      -73.7124,
      'H7P'
    );
    RfpTestDataFactory.createPlace(
      'Toronto',
      'ON',
      'CA',
      43.6532,
      -79.3832,
      'M5V'
    );
    Map<String, StateLaneCarrier> carriers = fixtures.carriers(
      g,
      fixtures.numberedNames(LaneQueries.GROUP_LIMIT + 1)
    );
    Test.startTest();
    // The 51 carriers take 44 queries before Test.startTest(). The load (35) and the 51 quotes (20)
    // need no Test.setCreatedDate, so they are made here (measured 2026-09-15).
    rtms__Load__c montrealToronto = PricingTestDataFactory.createLoad(
      g,
      g.originLocation,
      g.destinationLocation
    );
    List<rtms__CarrierQuote__c> quotes = new List<rtms__CarrierQuote__c>();
    for (StateLaneCarrier carrier : carriers.values()) {
      quotes.add(fixtures.quote(g, montrealToronto, carrier, true));
    }
    insert quotes;
    CarrierLeadResult sameLane = CarrierLeadService.find(
      fixtures.request('montreal|qc|ca', 'toronto|on|ca')
    );
    CarrierLeadResult r = CarrierLeadService.find(
      fixtures.request('laval|qc|ca', 'toronto|on|ca')
    );
    Test.stopTest();
    System.assertEquals(
      CarrierLeadResult.SAME_LANE,
      sameLane.stage,
      'precondition: the city lane search stops at stage 1'
    );
    System.assertEquals(
      true,
      sameLane.truncated,
      'precondition: the 51 carrier groups reach the cap, which marks stage 1 incomplete'
    );
    System.assertEquals(
      CarrierLeadResult.STATE_LANE,
      r.stage,
      JSON.serialize(r)
    );
    System.assertEquals(10, r.leads.size(), 'the top 10');
    System.assertEquals(
      false,
      r.truncated,
      'a 51st carrier group does not mark stage 2 incomplete'
    );
    System.assertEquals('QC to ON', r.stateLaneLabel, 'the label');
  }
}
