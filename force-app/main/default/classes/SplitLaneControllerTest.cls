@IsTest
private class SplitLaneControllerTest {
  /** The AuraHandledException message the call throws, or null when it returns. */
  private static String refusal(String requestJson, String currencyCode) {
    try {
      SplitLaneController.splitOptions(requestJson, currencyCode, 0);
      return null;
    } catch (AuraHandledException e) {
      return e.getMessage();
    }
  }

  @IsTest
  static void aCurrencyOtherThanCadOrUsdIsRefusedBeforeAnyQuery() {
    String lane = '{"originKey":"general escobedo|nl|mx","destinationKey":"toronto|on|ca"}';
    Test.startTest();
    String euro = refusal(lane, 'EUR');
    String none = refusal(lane, null);
    String blank = refusal(lane, '');
    String lower = refusal(lane, 'usd');
    Integer queries = Limits.getQueries();
    Test.stopTest();
    System.assertEquals('Choose CAD or USD.', euro);
    System.assertEquals('Choose CAD or USD.', none);
    System.assertEquals('Choose CAD or USD.', blank);
    System.assertEquals(
      'Choose CAD or USD.',
      lower,
      'the code is exact: the card sends CAD or USD'
    );
    System.assertEquals(0, queries, 'refused before any query');
  }

  @IsTest
  static void anUnreadableRequestIsAShortUserError() {
    String expected = 'The search request could not be read. Please reset the filters and try again.';
    System.assertEquals(expected, refusal('not json', 'CAD'));
    System.assertEquals(expected, refusal(null, 'USD'));
    System.assertEquals(expected, refusal('null', 'CAD'));
  }

  @IsTest
  static void theAttemptNumberIsIgnored() {
    String oneEnd = '{"originKey":"general escobedo|nl|mx","destinationKey":""}';
    Test.startTest();
    SplitLaneResult first = SplitLaneController.splitOptions(oneEnd, 'CAD', 0);
    SplitLaneResult retry = SplitLaneController.splitOptions(oneEnd, 'CAD', 3);
    Test.stopTest();
    System.assertEquals('Both ends of the lane need a place.', first.message);
    System.assertEquals(
      JSON.serialize(first),
      JSON.serialize(retry),
      'a Retry number changes only the cache key'
    );
  }

  @IsTest
  static void aLaneSearchErrorBecomesAUserError() {
    RfpTestDataFactory.createPlace(
      'General Escobedo',
      'NL',
      'MX',
      25.8000,
      -100.3167,
      null
    );
    RfpTestDataFactory.createPlace(
      'Toronto',
      'ON',
      'CA',
      43.6532,
      -79.3832,
      null
    );
    String zip3 = '{"originKey":"general escobedo|nl|mx","destinationKey":"toronto|on|ca","originPrecision":"ZIP3"}';
    Test.startTest();
    String message = refusal(zip3, 'CAD');
    Test.stopTest();
    System.assert(
      message != null && message.contains('has no postal prefix'),
      'the matcher\'s LaneSearchException reaches the card as its message: ' +
      message
    );
  }

  @IsTest
  static void usdReachesTheServiceAndComesBackOnTheResult() {
    RfpTestDataFactory.createPlace(
      'General Escobedo',
      'NL',
      'MX',
      25.8000,
      -100.3167,
      '660'
    );
    RfpTestDataFactory.createPlace(
      'Toronto',
      'ON',
      'CA',
      43.6532,
      -79.3832,
      'M5V'
    );
    HandoffPoints.keysOverride = new List<String>();
    IntercompanyCarriers.idsOverride = new Set<Id>();
    ExchangeRates.periodsOverride = new List<ExchangeRates.Period>{
      new ExchangeRates.Period(
        Date.today().addDays(-30),
        Date.newInstance(9999, 12, 31),
        0.72
      )
    };
    Test.startTest();
    SplitLaneResult result = SplitLaneController.splitOptions(
      '{"originKey":"general escobedo|nl|mx","destinationKey":"toronto|on|ca"}',
      'USD',
      0
    );
    Test.stopTest();
    System.assertEquals('USD', result.currencyCode);
    System.assertEquals(0, result.options.size());
    System.assertEquals(SplitLaneService.NO_OPTION_MESSAGE, result.message);
  }
}
