/**
 * Phase 12. The test that matters is the one that refuses: a lane whose ends are next door but
 * whose equipment differs is not covered by the same rate, and offering it would spread a price
 * across freight it was never quoted for.
 */
@IsTest
private class RfpLaneSimilarityTest {
  private static Account customer;
  private static RFP_Project__c project;

  private static Pricing_Place__c place(
    String city,
    String prov,
    Decimal lat,
    Decimal lng
  ) {
    return RfpTestDataFactory.createPlace(city, prov, 'CA', lat, lng, 'H1A');
  }

  private static void fixture() {
    customer = new Account(
      Name = 'Market Test',
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
    insert customer;
    project = RfpTestDataFactory.createProject(customer);
  }

  @IsTest
  static void offersLanesWhoseEndsAreCloseAndWhoseEquipmentAgrees() {
    fixture();
    // Montreal and Laval are about 10 mi apart; Toronto and Mississauga about 15.
    RFP_Lane__c anchor = RfpTestDataFactory.createLane(
      project,
      place('Montreal', 'QC', 45.5, -73.57),
      place('Toronto', 'ON', 43.65, -79.38)
    );
    RFP_Lane__c near = RfpTestDataFactory.createLane(
      project,
      place('Laval', 'QC', 45.61, -73.71),
      place('Mississauga', 'ON', 43.59, -79.64)
    );
    RFP_Lane__c far = RfpTestDataFactory.createLane(
      project,
      place('Quebec City', 'QC', 46.81, -71.21),
      place('Windsor', 'ON', 42.31, -83.03)
    );
    Test.startTest();
    List<Id> found = RfpLaneSimilarity.similarTo(anchor.Id, 50);
    Test.stopTest();
    System.assert(found.contains(near.Id), 'a lane next door is covered');
    System.assert(
      !found.contains(far.Id),
      'three hundred miles away is a different lane, whatever the province'
    );
    System.assert(!found.contains(anchor.Id), 'never the lane itself');
  }

  @IsTest
  static void refusesANearbyLaneWhoseEquipmentDiffers() {
    fixture();
    RFP_Lane__c anchor = RfpTestDataFactory.createLane(
      project,
      place('Montreal', 'QC', 45.5, -73.57),
      place('Toronto', 'ON', 43.65, -79.38)
    );
    RFP_Lane__c reefer = RfpTestDataFactory.createLane(
      project,
      place('Laval', 'QC', 45.61, -73.71),
      place('Mississauga', 'ON', 43.59, -79.64)
    );
    reefer.Equipment_Category__c = 'Reefer';
    reefer.Equipment_Type__c = 'Reefer 53\'';
    update reefer;
    Test.startTest();
    List<Id> found = RfpLaneSimilarity.similarTo(anchor.Id, 50);
    Test.stopTest();
    System.assert(
      !found.contains(reefer.Id),
      'a dry van rate does not cover a reefer lane, however close the cities are'
    );
  }

  @IsTest
  static void aTighterRadiusOffersLess() {
    fixture();
    RFP_Lane__c anchor = RfpTestDataFactory.createLane(
      project,
      place('Montreal', 'QC', 45.5, -73.57),
      place('Toronto', 'ON', 43.65, -79.38)
    );
    RFP_Lane__c near = RfpTestDataFactory.createLane(
      project,
      place('Laval', 'QC', 45.61, -73.71),
      place('Mississauga', 'ON', 43.59, -79.64)
    );
    Test.startTest();
    List<Id> wide = RfpLaneSimilarity.similarTo(anchor.Id, 50);
    List<Id> tight = RfpLaneSimilarity.similarTo(anchor.Id, 2);
    Test.stopTest();
    System.assert(wide.contains(near.Id));
    System.assert(
      !tight.contains(near.Id),
      'the radius is a judgement call, and it has to bite'
    );
  }

  @IsTest
  static void aLaneThatIsGoneOrUnreadableOffersNothingRatherThanThrowing() {
    Test.startTest();
    List<Id> none = RfpLaneSimilarity.similarTo(null, 50);
    Test.stopTest();
    System.assertEquals(0, none.size());
  }
}
