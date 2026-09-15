@IsTest
private class CarrierWarningTest {
  @IsTest
  static void noFlagGivesNoWarning() {
    System.assertEquals(
      null,
      CarrierWarning.text(false, false),
      'a clean carrier has no warning'
    );
    System.assertEquals(
      null,
      CarrierWarning.text(null, null),
      'a flag the query did not reach (no vendor, no profile) counts as not set'
    );
  }

  @IsTest
  static void theBlacklistFlagAloneGivesTheBlacklistText() {
    System.assertEquals(
      'THE CARRIER IS BLACK-LISTED',
      CarrierWarning.text(true, false),
      'the formula text, trimmed'
    );
    System.assertEquals(
      'THE CARRIER IS BLACK-LISTED',
      CarrierWarning.text(true, null),
      'a bid row passes no claim flag'
    );
  }

  @IsTest
  static void theClaimFlagAloneGivesTheClaimText() {
    System.assertEquals(
      'UNDER A CLAIM',
      CarrierWarning.text(false, true),
      'the text a query of Carrier_Att__c returns today'
    );
  }

  @IsTest
  static void bothFlagsKeepTheFormulaOrderWithTwoSpacesBetween() {
    System.assertEquals(
      'THE CARRIER IS BLACK-LISTED  UNDER A CLAIM',
      CarrierWarning.text(true, true),
      'blacklist first, then claim; the inner spaces of both texts stay'
    );
  }
}
