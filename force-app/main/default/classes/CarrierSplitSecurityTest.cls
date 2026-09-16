/**
 * Phase 8 security (spec §8). Carriers to ask reads quotes, loads and freight plans in system mode,
 * so a restricted pricer still gets carriers from records they cannot read, while the link to a
 * carrier account shows only when the caller can read that account in user mode. Class access is
 * read out of the permission set metadata, because Apex calling Apex does not enforce it. The
 * Split-lane options tests are here too.
 */
@IsTest
private class CarrierSplitSecurityTest {
  private static final String LANE_JSON = '{"originKey":"montreal|qc|ca","destinationKey":"toronto|on|ca"}';

  private class Fx {
    PricingTestDataFactory.Graph g;
    rtms__Load__c load;
  }

  /** The graph, the Montréal and Toronto places and one Montréal to Toronto load, owned by the admin. */
  private static Fx fx() {
    IntercompanyCarriers.idsOverride = new Set<Id>();
    LaneSearchExclusions.excludedContactIdsOverride = new Set<String>();
    Fx f = new Fx();
    f.g = PricingTestDataFactory.createGraph();
    RfpTestDataFactory.createPlace(
      'Montréal',
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
      'M5V'
    );
    f.load = PricingTestDataFactory.createLoad(
      f.g,
      f.g.originLocation,
      f.g.destinationLocation
    );
    return f;
  }

  /**
   * A carrier's own quote contact, transportation profile and carrier service, built like
   * PricingTestDataFactory.createGraph builds the graph's vendor: a quote's rtms__Vendor__c is its
   * service's carrier on every recent PostProduc quote.
   */
  private static rtms__CarrierService__c serviceFor(Fx f, Account carrier) {
    Contact quoteContact = new Contact(
      FirstName = 'Quote',
      LastName = carrier.Name,
      AccountId = carrier.Id,
      Email = 'hidden.quote@example.invalid',
      Phone = '514-555-0101'
    );
    insert quoteContact;
    rtms__TransportationProfile__c carrierProfile = new rtms__TransportationProfile__c(
      Name = carrier.Name + ' Profile',
      RecordTypeId = Schema.SObjectType.rtms__TransportationProfile__c.getRecordTypeInfosByDeveloperName()
        .get('Carrier')
        .getRecordTypeId(),
      rtms__Company_Risk__c = 'Acceptable',
      rtms__Carrier_Remit_To__c = carrier.Id
    );
    insert carrierProfile;
    rtms__CarrierService__c service = new rtms__CarrierService__c(
      Name = carrier.Name + ' Service',
      rtms__Carrier__c = carrier.Id,
      rtms__Mode__c = f.g.mode.Id,
      rtms__Transportation_Profile__c = carrierProfile.Id,
      rtms__Quote_Contact__c = quoteContact.Id,
      rtms__Minimum_Weight__c = 0,
      rtms__Maximum_Weight__c = 100000
    );
    insert service;
    return service;
  }

  /** A quote on the fixture load through the given carrier service; uninserted. */
  private static rtms__CarrierQuote__c quote(
    Fx f,
    rtms__CarrierService__c service,
    Boolean accepted
  ) {
    rtms__CarrierQuote__c q = PricingTestDataFactory.buildQuote(
      f.g,
      f.load,
      1000
    );
    q.rtms__Carrier_Service__c = service.Id;
    q.rtms__Vendor__c = service.rtms__Carrier__c;
    q.rtms__Quote_Contact__c = service.rtms__Quote_Contact__c;
    q.rtms__Accepted__c = accepted;
    return q;
  }

  private static CarrierLeadResult.Lead named(
    CarrierLeadResult r,
    String carrierName
  ) {
    for (CarrierLeadResult.Lead entry : r.leads) {
      if (entry.name == carrierName) {
        return entry;
      }
    }
    return null;
  }

  @IsTest
  static void theAccountLinkShowsOnlyForACarrierTheCallerCanRead() {
    User viewer = RfpTestDataFactory.restrictedUser('Lane_Benchmark_User');
    if (viewer == null) {
      System.assert(
        true,
        'no usable profile in this org; runAs coverage skipped (ledgered)'
      );
      return;
    }
    Fx f = fx();
    Account hidden = RfpTestDataFactory.hiddenCarrier();
    rtms__CarrierService__c hiddenService = serviceFor(f, hidden);
    Id hiddenId = hidden.Id;
    if (!RfpTestDataFactory.hiddenFrom(viewer, hiddenId)) {
      System.assert(
        true,
        'this org shares the hidden carrier ' +
          RfpTestDataFactory.sharingInputs(hiddenId) +
          '; account link coverage skipped (ledgered, R68)'
      );
      return;
    }
    Test.startTest();
    RfpTestDataFactory.shareAccount(f.g.vendor, viewer, 'Read');
    insert new List<rtms__CarrierQuote__c>{
      quote(f, f.g.carrierService, true),
      quote(f, hiddenService, false)
    };
    CarrierLeadResult seen;
    System.runAs(viewer) {
      seen = CarrierLeadController.findCarrierLeads(LANE_JSON, 0);
    }
    CarrierLeadResult admin = CarrierLeadController.findCarrierLeads(
      LANE_JSON,
      0
    );
    Test.stopTest();
    System.assertEquals(
      2,
      seen.leads.size(),
      'system mode names both carriers: ' + JSON.serialize(seen)
    );
    System.assertEquals(
      'Test Carrier',
      seen.leads[0].name,
      'the carrier that moved the load ranks first'
    );
    System.assertEquals(
      true,
      named(seen, 'Test Carrier').canOpen,
      'a carrier account the viewer can read opens'
    );
    CarrierLeadResult.Lead hiddenLead = named(seen, 'Hidden Carrier');
    System.assertEquals(
      false,
      hiddenLead.canOpen,
      'no link to an account the viewer cannot read'
    );
    System.assertEquals(
      true,
      hiddenLead.blacklisted,
      'the name still shows, with its badge'
    );
    System.assertEquals(
      true,
      named(admin, 'Hidden Carrier').canOpen,
      'the admin reads every account'
    );
  }

  @IsTest
  static void restrictedPricersStillGetCarriersFromPrivateQuotes() {
    User benchmark = RfpTestDataFactory.restrictedUser('Lane_Benchmark_User');
    User pricing = RfpTestDataFactory.restrictedUser('RFP_Tool_User');
    if (benchmark == null || pricing == null) {
      System.assert(
        true,
        'no usable profile in this org; runAs coverage skipped (ledgered)'
      );
      return;
    }
    Fx f = fx();
    Test.startTest();
    rtms__CarrierQuote__c moved = quote(f, f.g.carrierService, true);
    insert moved;
    Id quoteId = moved.Id;
    Integer visible;
    CarrierLeadResult benchmarkResult;
    CarrierLeadResult pricingResult;
    System.runAs(benchmark) {
      visible = [
        SELECT COUNT()
        FROM rtms__CarrierQuote__c
        WHERE Id = :quoteId
        WITH USER_MODE
      ];
      benchmarkResult = CarrierLeadController.findCarrierLeads(LANE_JSON, 0);
    }
    System.runAs(pricing) {
      pricingResult = CarrierLeadController.findCarrierLeads(LANE_JSON, 0);
    }
    Test.stopTest();
    System.assertEquals(
      0,
      visible,
      'precondition: the admin\'s quote is private to the Lane Benchmark user'
    );
    for (
      CarrierLeadResult r : new List<CarrierLeadResult>{
        benchmarkResult,
        pricingResult
      }
    ) {
      System.assertEquals(
        CarrierLeadResult.SAME_LANE,
        r.stage,
        JSON.serialize(r)
      );
      System.assertEquals(1, r.leads.size(), 'the graph carrier');
      System.assertEquals('Test Carrier', r.leads[0].name, 'by name');
      System.assertEquals(1, r.leads[0].loadsMoved, 'one accepted quote');
    }
  }

  /**
   * Class security is not enforced Apex to Apex, so the grant is read out of the metadata: a
   * controller missing here is the "You do not have access to the Apex class named ..." error a
   * pricer would hit in the browser. bothPermissionSetsOpenTheSplitController checks SplitLaneController.
   */
  @IsTest
  static void bothPermissionSetsGrantThePhaseEightControllers() {
    List<String> permissionSets = new List<String>{
      'Lane_Benchmark_User',
      'RFP_Tool_User'
    };
    List<String> controllers = new List<String>{ 'CarrierLeadController' };
    List<SetupEntityAccess> grants = [
      SELECT Parent.Name, SetupEntityId
      FROM SetupEntityAccess
      WHERE Parent.Name IN :permissionSets AND SetupEntityType = 'ApexClass'
    ];
    Set<Id> classIds = new Set<Id>();
    for (SetupEntityAccess grant : grants) {
      classIds.add(grant.SetupEntityId);
    }
    Map<Id, ApexClass> classes = new Map<Id, ApexClass>(
      [SELECT Id, Name FROM ApexClass WHERE Id IN :classIds]
    );
    Set<String> granted = new Set<String>();
    for (SetupEntityAccess grant : grants) {
      granted.add(
        grant.Parent.Name + ':' + classes.get(grant.SetupEntityId).Name
      );
    }
    for (String permissionSet : permissionSets) {
      for (String controller : controllers) {
        System.assert(
          granted.contains(permissionSet + ':' + controller),
          permissionSet + ' grants no class access to ' + controller
        );
      }
    }
  }

  @IsTest
  static void restrictedUsersGetSplitEstimatesFromLoadsTheyCannotOpen() {
    User viewer = RfpTestDataFactory.restrictedUser('Lane_Benchmark_User');
    User pricer = RfpTestDataFactory.restrictedUser('RFP_Tool_User');
    if (viewer == null || pricer == null) {
      System.assert(
        true,
        'no usable profile in this org; runAs coverage skipped (ledgered)'
      );
      return;
    }
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
    ExchangeRates.periodsOverride = new List<ExchangeRates.Period>{
      new ExchangeRates.Period(
        Date.today().addDays(-30),
        Date.newInstance(9999, 12, 31),
        0.72
      )
    };
    Test.startTest();
    SplitTestData.legLoad(
      g,
      escobedoDock,
      laredoYard,
      g.vendor,
      1000,
      'Delivered'
    );
    SplitTestData.legLoad(
      g,
      laredoYard,
      g.destinationLocation,
      g.vendor,
      3000,
      'Delivered'
    );
    String lane = JSON.serialize(
      new Map<String, Object>{
        'originKey' => escobedo.Key__c,
        'destinationKey' => toronto.Key__c
      }
    );
    SplitLaneResult seenByViewer;
    SplitLaneResult seenByPricer;
    System.runAs(viewer) {
      seenByViewer = SplitLaneController.splitOptions(lane, 'CAD', 0);
    }
    System.runAs(pricer) {
      seenByPricer = SplitLaneController.splitOptions(lane, 'USD', 0);
    }
    Test.stopTest();
    System.assertEquals(1, seenByViewer.options.size());
    SplitLaneResult.Option cad = seenByViewer.options[0];
    System.assertEquals('Laredo, TX', cad.handoffLabel);
    System.assertEquals('Test Carrier', cad.legs[0].carriers[0].name);
    System.assertEquals(
      4000.00,
      cad.medianTotal,
      'the admin\'s Private loads are read in system mode for a Lane Benchmark user'
    );
    System.assertEquals('USD', seenByPricer.currencyCode);
    System.assertEquals(
      2880.00,
      seenByPricer.options[0].medianTotal,
      'and for an RFP Tool user, in USD: 720 + 2160'
    );
    System.assertEquals(Date.today().addDays(-30), seenByPricer.rateStartDate);
  }

  @IsTest
  static void bothPermissionSetsOpenTheSplitController() {
    List<String> grantedTo = new List<String>();
    for (SetupEntityAccess access : [
      SELECT Parent.Name
      FROM SetupEntityAccess
      WHERE
        SetupEntityId IN (
          SELECT Id
          FROM ApexClass
          WHERE Name = 'SplitLaneController'
        )
        AND Parent.Name IN ('Lane_Benchmark_User', 'RFP_Tool_User')
      ORDER BY Parent.Name
    ]) {
      grantedTo.add(access.Parent.Name);
    }
    System.assertEquals(
      new List<String>{ 'Lane_Benchmark_User', 'RFP_Tool_User' },
      grantedTo
    );
  }
}
