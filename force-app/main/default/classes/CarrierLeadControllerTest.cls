@IsTest
private class CarrierLeadControllerTest {
  private static final String LANE_JSON = '{"originKey":"montreal|qc|ca","destinationKey":"toronto|on|ca"}';

  /** No intercompany carrier and no excluded contact: tests never read the org's custom metadata. */
  private static void settings() {
    IntercompanyCarriers.idsOverride = new Set<Id>();
    LaneSearchExclusions.excludedContactIdsOverride = new Set<String>();
  }

  @IsTest
  static void anUnreadableRequestIsRefusedWithAShortMessage() {
    settings();
    Test.startTest();
    List<String> messages = new List<String>();
    for (String bad : new List<String>{ 'not json', '', 'null', null }) {
      try {
        CarrierLeadController.findCarrierLeads(bad, 0);
        messages.add('no exception for ' + bad);
      } catch (AuraHandledException e) {
        messages.add(e.getMessage());
      }
    }
    Test.stopTest();
    for (String message : messages) {
      System.assertEquals(
        CarrierLeadController.UNREADABLE_REQUEST,
        message,
        'every unreadable request gets the same message'
      );
    }
    System.assertEquals(4, messages.size(), 'four requests were tried');
  }

  @IsTest
  static void aLaneSearchExceptionReachesTheScreenAsItsMessage() {
    settings();
    // ZIP3 on an end whose place has no postal prefix and no typed prefix: LaneKeyMatcher refuses it.
    RfpTestDataFactory.createPlace(
      'Montréal',
      'QC',
      'CA',
      45.5019,
      -73.5674,
      null
    );
    RfpTestDataFactory.createPlace(
      'Toronto',
      'ON',
      'CA',
      43.6532,
      -79.3832,
      'M5V'
    );
    String message;
    Test.startTest();
    try {
      CarrierLeadController.findCarrierLeads(
        '{"originKey":"montreal|qc|ca","destinationKey":"toronto|on|ca","originPrecision":"ZIP3"}',
        0
      );
      message = 'no exception';
    } catch (AuraHandledException e) {
      message = e.getMessage();
    }
    Test.stopTest();
    System.assert(
      message.contains('has no postal prefix'),
      'the LaneSearchException text reaches the screen: ' + message
    );
  }

  @IsTest
  static void attemptIsIgnoredAndAnUnknownPlaceNamesNobody() {
    settings();
    PricingTestDataFactory.Graph g = PricingTestDataFactory.createGraph();
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
    rtms__Load__c load = PricingTestDataFactory.createLoad(
      g,
      g.originLocation,
      g.destinationLocation
    );
    rtms__CarrierQuote__c moved = PricingTestDataFactory.buildQuote(
      g,
      load,
      1000
    );
    moved.rtms__Accepted__c = true;
    insert moved;
    Test.startTest();
    CarrierLeadResult first = CarrierLeadController.findCarrierLeads(
      LANE_JSON,
      0
    );
    CarrierLeadResult retry = CarrierLeadController.findCarrierLeads(
      LANE_JSON,
      1
    );
    CarrierLeadResult noAttempt = CarrierLeadController.findCarrierLeads(
      LANE_JSON,
      null
    );
    CarrierLeadResult unknown = CarrierLeadController.findCarrierLeads(
      '{"originKey":"nowhere|zz|zz","destinationKey":"toronto|on|ca"}',
      0
    );
    Test.stopTest();
    System.assertEquals(
      CarrierLeadResult.SAME_LANE,
      first.stage,
      JSON.serialize(first)
    );
    System.assertEquals(1, first.leads.size(), 'the graph carrier');
    System.assertEquals('Test Carrier', first.leads[0].name, 'by name');
    System.assertEquals(1, first.leads[0].loadsMoved, 'one accepted quote');
    System.assertEquals(
      JSON.serialize(first),
      JSON.serialize(retry),
      'a Retry (attempt 1) gets the same answer'
    );
    System.assertEquals(
      JSON.serialize(first),
      JSON.serialize(noAttempt),
      'so does a call without attempt'
    );
    System.assertEquals(
      CarrierLeadResult.NONE,
      unknown.stage,
      'an unknown place key names nobody and is not an error'
    );
    System.assertEquals(0, unknown.leads.size(), 'no lead');
  }
}
