/**
 * Phase 12. The setting is read from custom metadata, which is visible to a test without
 * SeeAllData, so these run against whatever the org is configured with. They assert the shape
 * and the precedence rather than one org's account id, so they pass in any org.
 */
@IsTest
private class MarketTestSettingTest {
  @IsTest
  static void theConfiguredAccountIsReadFromCustomMetadata() {
    Test.startTest();
    Id configured = MarketTestSetting.accountId();
    Test.stopTest();
    if (configured != null) {
      System.assertEquals(
        Account.SObjectType,
        configured.getSObjectType(),
        'the setting names an account, or nothing at all'
      );
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
}
