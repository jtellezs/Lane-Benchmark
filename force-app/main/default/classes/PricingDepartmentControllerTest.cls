/**
 * There is no @TestSetup on purpose: each test builds its own graph so field values are explicit.
 */
@IsTest
private class PricingDepartmentControllerTest {
  private static final String ALL = '';
  private static final Integer DAYS = 30;

  private static List<rtms__CarrierQuote__c> search(
    String origin,
    String destination,
    String mode,
    String hazmat,
    String priceDep,
    String equipment,
    Integer days,
    String accepted,
    String declined
  ) {
    return PricingDepartmentController.getCarrierQuotes(
      origin,
      destination,
      mode,
      hazmat,
      priceDep,
      equipment,
      days,
      accepted,
      declined
    );
  }

  private static rtms__CarrierQuote__c insertQuote(
    PricingTestDataFactory.Graph g,
    rtms__Load__c load,
    Decimal total
  ) {
    rtms__CarrierQuote__c q = PricingTestDataFactory.buildQuote(g, load, total);
    insert q;
    return q;
  }

  @IsTest
  static void returnsQuotesMatchingOriginAndDestination() {
    // This org's Load automation (LoadTrigger plus the "UAT - Load Updated" flow) is not
    // bulkified: a second rtms__Load__c DML statement in one test method exceeds the 100
    // synchronous SOQL query limit. Test.startTest() gives the code after it a fresh limit
    // set, so the second createLoad() call is placed there.
    PricingDepartmentController.excludedContactIdsOverride = new Set<String>();
    PricingTestDataFactory.Graph g = PricingTestDataFactory.createGraph();
    rtms__Load__c mtlToTor = PricingTestDataFactory.createLoad(
      g,
      g.originLocation,
      g.destinationLocation
    );
    insertQuote(g, mtlToTor, 1000);

    Test.startTest();
    rtms__Load__c torToMtl = PricingTestDataFactory.createLoad(
      g,
      g.destinationLocation,
      g.originLocation
    );
    insertQuote(g, torToMtl, 2000);
    List<rtms__CarrierQuote__c> result = search(
      'Montreal',
      'Toronto',
      ALL,
      ALL,
      ALL,
      ALL,
      DAYS,
      ALL,
      ALL
    );
    Test.stopTest();

    System.assertEquals(
      1,
      result.size(),
      'Only the Montreal -> Toronto quote should match'
    );
    System.assertEquals(1000, result[0].CAD_Quote_Total__c);
    System.assertEquals('Montreal, Quebec', result[0].Origin__c);
  }

  @IsTest
  static void originFilterIsCaseInsensitiveSubstring() {
    PricingDepartmentController.excludedContactIdsOverride = new Set<String>();
    PricingTestDataFactory.Graph g = PricingTestDataFactory.createGraph();
    rtms__Load__c load = PricingTestDataFactory.createLoad(
      g,
      g.originLocation,
      g.destinationLocation
    );
    insertQuote(g, load, 1000);

    System.assertEquals(
      1,
      search('montr', ALL, ALL, ALL, ALL, ALL, DAYS, ALL, ALL).size()
    );
    System.assertEquals(
      0,
      search('Calgary', ALL, ALL, ALL, ALL, ALL, DAYS, ALL, ALL).size()
    );
  }

  @IsTest
  static void dateWindowExcludesOlderQuotes() {
    PricingDepartmentController.excludedContactIdsOverride = new Set<String>();
    PricingTestDataFactory.Graph g = PricingTestDataFactory.createGraph();
    rtms__Load__c load = PricingTestDataFactory.createLoad(
      g,
      g.originLocation,
      g.destinationLocation
    );
    rtms__CarrierQuote__c recent = insertQuote(g, load, 1000);
    rtms__CarrierQuote__c old = insertQuote(g, load, 2000);
    Test.setCreatedDate(recent.Id, Datetime.now().addDays(-2));
    Test.setCreatedDate(old.Id, Datetime.now().addDays(-10));

    Test.startTest();
    List<rtms__CarrierQuote__c> last5 = search(
      ALL,
      ALL,
      ALL,
      ALL,
      ALL,
      ALL,
      5,
      ALL,
      ALL
    );
    List<rtms__CarrierQuote__c> last30 = search(
      ALL,
      ALL,
      ALL,
      ALL,
      ALL,
      ALL,
      30,
      ALL,
      ALL
    );
    Test.stopTest();

    System.assertEquals(
      1,
      last5.size(),
      'A 10-day-old quote is outside a 5-day window'
    );
    System.assertEquals(2, last30.size());
  }

  @IsTest
  static void hazmatFilterMatchesOnlyHazardousLoads() {
    // Same governor-limit reasoning as returnsQuotesMatchingOriginAndDestination: the second
    // Load is created inside Test.startTest()'s fresh limit set. Hazmat is set at creation
    // (factory overload) rather than via a post-insert `update`, which also avoided a Load
    // validation rule failure/limit trip on `update`.
    PricingDepartmentController.excludedContactIdsOverride = new Set<String>();
    PricingTestDataFactory.Graph g = PricingTestDataFactory.createGraph();
    rtms__Load__c plain = PricingTestDataFactory.createLoad(
      g,
      g.originLocation,
      g.destinationLocation
    );
    insertQuote(g, plain, 1000);

    Test.startTest();
    rtms__Load__c hazardous = PricingTestDataFactory.createLoad(
      g,
      g.originLocation,
      g.destinationLocation,
      true
    );
    insertQuote(g, hazardous, 2000);
    List<rtms__CarrierQuote__c> result = search(
      ALL,
      ALL,
      ALL,
      'Hazmat',
      ALL,
      ALL,
      DAYS,
      ALL,
      ALL
    );
    List<rtms__CarrierQuote__c> unfiltered = search(
      ALL,
      ALL,
      ALL,
      ALL,
      ALL,
      ALL,
      DAYS,
      ALL,
      ALL
    );
    Test.stopTest();

    List<String> hazmatValuesSeen = new List<String>();
    for (rtms__CarrierQuote__c q : unfiltered) {
      hazmatValuesSeen.add(String.valueOf(q.Hazmat__c));
    }
    System.assertEquals(
      1,
      result.size(),
      'Expected exactly 1 hazardous quote. Hazmat__c values seen on all quotes: ' +
      String.join(hazmatValuesSeen, ', ')
    );
    System.assertEquals(2000, result[0].CAD_Quote_Total__c);
  }

  @IsTest
  static void marketTestFilterMatchesCustomerName() {
    // Same governor-limit reasoning as the two tests above. The customer is set at creation
    // (factory overload) rather than via `mt.rtms__Customer__c = marketTest.Id; update mt;`,
    // and the second Load is created inside Test.startTest()'s fresh limit set.
    PricingDepartmentController.excludedContactIdsOverride = new Set<String>();
    PricingTestDataFactory.Graph g = PricingTestDataFactory.createGraph();
    Account marketTest = g.customer.clone(false, true, false, false);
    marketTest.Name = 'Market Test';
    insert marketTest;
    rtms__Load__c normal = PricingTestDataFactory.createLoad(
      g,
      g.originLocation,
      g.destinationLocation
    );
    insertQuote(g, normal, 1000);

    Test.startTest();
    rtms__Load__c mt = PricingTestDataFactory.createLoad(
      g,
      g.originLocation,
      g.destinationLocation,
      marketTest
    );
    insertQuote(g, mt, 3000);
    List<rtms__CarrierQuote__c> result = search(
      ALL,
      ALL,
      ALL,
      ALL,
      'Market Test',
      ALL,
      DAYS,
      ALL,
      ALL
    );
    List<rtms__CarrierQuote__c> unfiltered = search(
      ALL,
      ALL,
      ALL,
      ALL,
      ALL,
      ALL,
      DAYS,
      ALL,
      ALL
    );
    Test.stopTest();

    List<String> customerNamesSeen = new List<String>();
    for (rtms__CarrierQuote__c q : unfiltered) {
      customerNamesSeen.add(String.valueOf(q.Customer_Name__c));
    }
    System.assertEquals(
      1,
      result.size(),
      'Expected exactly 1 quote for Market Test customer. Customer_Name__c values seen: ' +
      String.join(customerNamesSeen, ', ')
    );
    System.assertEquals(3000, result[0].CAD_Quote_Total__c);
  }

  @IsTest
  static void acceptedAndDeclinedFlagsFilterOnAcceptedCheckbox() {
    PricingDepartmentController.excludedContactIdsOverride = new Set<String>();
    PricingTestDataFactory.Graph g = PricingTestDataFactory.createGraph();
    rtms__Load__c load = PricingTestDataFactory.createLoad(
      g,
      g.originLocation,
      g.destinationLocation
    );
    rtms__CarrierQuote__c accepted = PricingTestDataFactory.buildQuote(
      g,
      load,
      1000
    );
    accepted.rtms__Accepted__c = true;
    rtms__CarrierQuote__c declined = PricingTestDataFactory.buildQuote(
      g,
      load,
      2000
    );
    insert new List<rtms__CarrierQuote__c>{ accepted, declined };

    List<rtms__CarrierQuote__c> onlyAccepted = search(
      ALL,
      ALL,
      ALL,
      ALL,
      ALL,
      ALL,
      DAYS,
      'true',
      ALL
    );
    List<rtms__CarrierQuote__c> onlyDeclined = search(
      ALL,
      ALL,
      ALL,
      ALL,
      ALL,
      ALL,
      DAYS,
      ALL,
      'true'
    );

    System.assertEquals(1, onlyAccepted.size());
    System.assertEquals(1000, onlyAccepted[0].CAD_Quote_Total__c);
    System.assertEquals(1, onlyDeclined.size());
    System.assertEquals(2000, onlyDeclined[0].CAD_Quote_Total__c);
  }

  @IsTest
  static void excludedContactIsNeverReturned() {
    PricingTestDataFactory.Graph g = PricingTestDataFactory.createGraph();
    rtms__Load__c load = PricingTestDataFactory.createLoad(
      g,
      g.originLocation,
      g.destinationLocation
    );
    insertQuote(g, load, 1000);
    String fifteen = String.valueOf(g.quoteContact.Id).left(15);

    PricingDepartmentController.excludedContactIdsOverride = new Set<String>{
      fifteen
    };
    System.assertEquals(
      0,
      search(ALL, ALL, ALL, ALL, ALL, ALL, DAYS, ALL, ALL).size(),
      'Quotes whose contact is excluded must not be returned'
    );
    PricingDepartmentController.excludedContactIdsOverride = new Set<String>();
    System.assertEquals(
      1,
      search(ALL, ALL, ALL, ALL, ALL, ALL, DAYS, ALL, ALL).size()
    );
  }

  @IsTest
  static void identicalQuotesAreDeduplicated() {
    PricingDepartmentController.excludedContactIdsOverride = new Set<String>();
    PricingTestDataFactory.Graph g = PricingTestDataFactory.createGraph();
    rtms__Load__c load = PricingTestDataFactory.createLoad(
      g,
      g.originLocation,
      g.destinationLocation
    );
    insertQuote(g, load, 1000);
    insertQuote(g, load, 1000);
    insertQuote(g, load, 1250);

    List<rtms__CarrierQuote__c> result = search(
      ALL,
      ALL,
      ALL,
      ALL,
      ALL,
      ALL,
      DAYS,
      ALL,
      ALL
    );

    System.assertEquals(
      2,
      result.size(),
      'Same total, carrier, lane, mode and equipment collapse to one row'
    );
  }

  @IsTest
  static void resultIsCappedAtFiveHundredRows() {
    PricingDepartmentController.excludedContactIdsOverride = new Set<String>();
    PricingTestDataFactory.Graph g = PricingTestDataFactory.createGraph();
    rtms__Load__c load = PricingTestDataFactory.createLoad(
      g,
      g.originLocation,
      g.destinationLocation
    );
    List<rtms__CarrierQuote__c> quotes = new List<rtms__CarrierQuote__c>();
    for (Integer i = 0; i < 520; i++) {
      quotes.add(PricingTestDataFactory.buildQuote(g, load, 1000 + i)); // distinct totals so dedupe keeps all
    }
    insert quotes;

    Test.startTest();
    List<rtms__CarrierQuote__c> result = search(
      ALL,
      ALL,
      ALL,
      ALL,
      ALL,
      ALL,
      DAYS,
      ALL,
      ALL
    );
    Test.stopTest();

    System.assertEquals(500, result.size());
  }

  @IsTest
  static void excludedContactIdsComeFromCustomMetadataInBothIdLengths() {
    PricingDepartmentController.excludedContactIdsOverride = null;
    Set<String> ids = PricingDepartmentController.excludedContactIds();
    List<Pricing_Department_Setting__mdt> settings = [
      SELECT Excluded_Contact_Ids__c
      FROM Pricing_Department_Setting__mdt
      WHERE DeveloperName = 'Default'
    ];
    System.assertEquals(
      1,
      settings.size(),
      'The Default setting record must be deployed'
    );
    for (String raw : settings[0].Excluded_Contact_Ids__c.split(',')) {
      Id contactId = Id.valueOf(raw.trim());
      System.assert(
        ids.contains(String.valueOf(contactId)),
        '18-char form present'
      );
      System.assert(
        ids.contains(String.valueOf(contactId).left(15)),
        '15-char form present'
      );
    }
  }

  @IsTest
  @SuppressWarnings('PMD.AvoidHardcodingId')
  static void parseExcludedContactIdsSkipsInvalidEntries() {
    String validContactId = '0033l00002px9ja';
    Id validId = Id.valueOf(validContactId);

    Test.startTest();
    Set<String> ids = PricingDepartmentController.parseExcludedContactIds(
      validContactId + ', not-an-id, 0033l00002px9j, 001000000000001AAA ,'
    );
    Set<String> fromNull = PricingDepartmentController.parseExcludedContactIds(
      null
    );
    Set<String> fromBlank = PricingDepartmentController.parseExcludedContactIds(
      '  '
    );
    Test.stopTest();

    System.assertEquals(
      2,
      ids.size(),
      'Only the valid Contact id (both forms) should survive: ' +
      String.join(new List<String>(ids), ', ')
    );
    System.assert(
      ids.contains(String.valueOf(validId)),
      '18-char form present'
    );
    System.assert(
      ids.contains(String.valueOf(validId).left(15)),
      '15-char form present'
    );
    System.assertEquals(0, fromNull.size(), 'null input yields an empty set');
    System.assertEquals(0, fromBlank.size(), 'blank input yields an empty set');
  }
}
