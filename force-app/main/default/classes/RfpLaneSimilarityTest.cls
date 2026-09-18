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

  /**
   * A place that was never geocoded has no coordinates, so distance cannot decide. The class
   * falls back to the province, which is what keeps a half-geocoded project usable.
   */
  @IsTest
  static void aLaneEndWithNoCoordinatesFallsBackToItsProvince() {
    fixture();
    Pricing_Place__c blindOrigin = RfpTestDataFactory.createPlace(
      'Nowhere',
      'QC',
      'CA',
      null,
      null,
      'H1A'
    );
    RFP_Lane__c anchor = RfpTestDataFactory.createLane(
      project,
      blindOrigin,
      place('Toronto', 'ON', 43.65, -79.38)
    );
    Pricing_Place__c blindTwin = RfpTestDataFactory.createPlace(
      'Elsewhere',
      'QC',
      'CA',
      null,
      null,
      'H2B'
    );
    RFP_Lane__c sameProvince = RfpTestDataFactory.createLane(
      project,
      blindTwin,
      place('Mississauga', 'ON', 43.59, -79.64)
    );
    Pricing_Place__c otherProvince = RfpTestDataFactory.createPlace(
      'Moncton',
      'NB',
      'CA',
      null,
      null,
      'E1C'
    );
    RFP_Lane__c elsewhere = RfpTestDataFactory.createLane(
      project,
      otherProvince,
      place('Windsor', 'ON', 42.31, -83.03)
    );
    Test.startTest();
    List<Id> found = RfpLaneSimilarity.similarTo(anchor.Id, 50);
    Test.stopTest();
    System.assert(
      found.contains(sameProvince.Id),
      'with no coordinates the province decides, so a half-geocoded project still works'
    );
    System.assert(
      !found.contains(elsewhere.Id),
      'and a different province is still a different lane'
    );
  }

  /** A lane id that is not there answers with nothing rather than throwing at the page. */
  @IsTest
  static void aLaneThatIsNotThereOffersNothing() {
    Id missing =
      RFP_Lane__c.SObjectType.getDescribe().getKeyPrefix() + '000000000001';
    Test.startTest();
    List<Id> found = RfpLaneSimilarity.similarTo(missing, 50);
    Test.stopTest();
    System.assertEquals(0, found.size());
  }

  /**
   * Review findings #4/#9: the project scan takes a 2,000-lane window, and the workbench takes
   * its own window ordered by Row_Number__c. Unordered, the two windows are different sets on a
   * project past the cap, so a lane the pricer never saw could be handed to a bulk apply and
   * priced. The lanes below are inserted out of row order on purpose: unordered, the window
   * would take them in Id order and pick up the wrong two.
   */
  @IsTest
  static void scansTheProjectInTheSameOrderTheWorkbenchLoadsIt() {
    fixture();
    // One pair of places for every lane: the places are unique per city, and here only the row
    // number and the insert order are meant to differ.
    Pricing_Place__c origin = place('Montreal', 'QC', 45.5, -73.57);
    Pricing_Place__c destination = place('Toronto', 'ON', 43.65, -79.38);
    RFP_Lane__c anchor = similarLane(origin, destination, 1);
    RFP_Lane__c fourth = similarLane(origin, destination, 4);
    RFP_Lane__c second = similarLane(origin, destination, 2);
    RFP_Lane__c third = similarLane(origin, destination, 3);
    RfpLaneSimilarity.laneLimit = 2;

    Test.startTest();
    List<Id> found = RfpLaneSimilarity.similarTo(anchor.Id, 50);
    Test.stopTest();

    System.assert(
      found.contains(second.Id) && found.contains(third.Id),
      'the window is the first rows by Row_Number__c, as the workbench loads them'
    );
    System.assert(
      !found.contains(fourth.Id),
      'a row past the window is never offered: the pricer cannot see it to uncheck it'
    );
  }

  /** Same lane every time, so only Row_Number__c and the insert order distinguish them. */
  private static RFP_Lane__c similarLane(
    Pricing_Place__c origin,
    Pricing_Place__c destination,
    Integer rowNumber
  ) {
    RFP_Lane__c lane = RfpTestDataFactory.createLane(
      project,
      origin,
      destination
    );
    lane.Row_Number__c = rowNumber;
    update lane;
    return lane;
  }
}
