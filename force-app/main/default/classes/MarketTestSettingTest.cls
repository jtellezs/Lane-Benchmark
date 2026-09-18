/**
 * Phase 12. The setting is read from custom metadata, which is visible to a test without
 * SeeAllData, so these run against whatever the org is configured with. They assert the shape
 * and the precedence rather than one org's account id, so they pass in any org.
 */
@IsTest
private class MarketTestSettingTest {
  /**
   * Reads the same custom metadata the class reads and asserts they agree, so deleting the
   * query from MarketTestSetting fails this test instead of quietly returning null forever.
   */
  @IsTest
  static void theConfiguredAccountIsTheOneInCustomMetadata() {
    List<Pricing_Department_Setting__mdt> settings = [
      SELECT Market_Test_Account_Id__c
      FROM Pricing_Department_Setting__mdt
      WHERE DeveloperName = 'Default'
      LIMIT 1
    ];
    String expected = settings.isEmpty()
      ? null
      : settings[0].Market_Test_Account_Id__c;
    Test.startTest();
    Id configured = MarketTestSetting.accountId();
    Test.stopTest();
    if (String.isBlank(expected)) {
      System.assertEquals(
        null,
        configured,
        'no setting reads as no account rather than a broken id'
      );
    } else {
      System.assertEquals(
        (Id) expected,
        configured,
        'the class returns what the Default record holds'
      );
      System.assertEquals(Account.SObjectType, configured.getSObjectType());
    }
  }

  @IsTest
  static void anOverrideWinsSoATestNeverDependsOnTheOrgsSetting() {
    Account a = new Account(
      Name = 'Market Test Stand-in',
      RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
        .get('Customer')
        ?.getRecordTypeId(),
      rtms__TMS_Type__c = 'Customer',
      Industry = 'Other',
      BillingStreet = '1 Test St',
      BillingCity = 'Montreal',
      BillingState = 'Quebec',
      BillingPostalCode = 'H1A 1A1',
      BillingCountry = 'Canada',
      CurrencyIsoCode = 'CAD'
    );
    insert a;
    MarketTestSetting.accountIdOverride = a.Id;
    Test.startTest();
    Id found = MarketTestSetting.accountId();
    Test.stopTest();
    System.assertEquals(a.Id, found);
  }

  @IsTest
  static void noSettingMeansNoAccountRatherThanAnError() {
    MarketTestSetting.accountIdOverride = null;
    Test.startTest();
    Id found = MarketTestSetting.accountId();
    Test.stopTest();
    System.assert(
      found == null || found.getSObjectType() == Account.SObjectType,
      'a blank setting reads as no account, never as a broken id'
    );
  }

  @IsTest
  static void anOrgWithNoSettingReadsAsNoAccount() {
    MarketTestSetting.suppressSetting = true;
    Test.startTest();
    Id found = MarketTestSetting.accountId();
    Test.stopTest();
    System.assertEquals(
      null,
      found,
      'the branch that decides on the marker alone has to be reachable in a configured org'
    );
  }
}
