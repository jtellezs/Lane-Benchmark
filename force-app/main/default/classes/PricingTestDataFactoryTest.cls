@IsTest
private class PricingTestDataFactoryTest {
  /**
   * The brief's original version of this test asserted rtms__First_Stop__r.rtms__City__c,
   * rtms__Postal_Code__c and both geolocation fields directly. Those assertions were replaced with
   * equivalent ones sourced through rtms__Location2__r: PostProduc's managed rtms__StopUpsert
   * trigger unconditionally blanks those four raw Stop fields on every save (see
   * PricingTestDataFactory.buildStop()'s doc comment for the full discovery), so the values are
   * only reliably readable off the stop's linked location account.
   */
  @IsTest
  static void loadCarriesLaneKeysAndStopsCarryGeolocation() {
    PricingTestDataFactory.Graph g = PricingTestDataFactory.createGraph();
    Account laval = PricingTestDataFactory.createLocation(
      'Laval Co',
      'Laval',
      'Quebec',
      'Canada',
      'H7P 1T2',
      45.6066,
      -73.7124
    );
    Test.startTest();
    rtms__Load__c load = PricingTestDataFactory.createLoad(
      g,
      laval,
      g.destinationLocation
    );
    Test.stopTest();
    load = [
      SELECT
        rtms__City_Lane__c,
        rtms__State_Lane__c,
        rtms__Zip3_Lane__c,
        rtms__First_Stop__r.rtms__Location2__c,
        rtms__First_Stop__r.rtms__Location2__r.ShippingCity,
        rtms__First_Stop__r.rtms__Location2__r.ShippingPostalCode,
        rtms__First_Stop__r.rtms__Location2__r.ShippingLatitude,
        rtms__Last_Stop__r.rtms__Location2__r.ShippingLongitude
      FROM rtms__Load__c
      WHERE Id = :load.Id
    ];
    System.assertEquals('Laval, QC:Toronto, ON', load.rtms__City_Lane__c);
    System.assertEquals('QC:ON', load.rtms__State_Lane__c);
    System.assertEquals('H7P:A1A', load.rtms__Zip3_Lane__c);
    System.assertEquals(laval.Id, load.rtms__First_Stop__r.rtms__Location2__c);
    System.assertEquals(
      'Laval',
      load.rtms__First_Stop__r.rtms__Location2__r.ShippingCity
    );
    System.assertEquals(
      'H7P 1T2',
      load.rtms__First_Stop__r.rtms__Location2__r.ShippingPostalCode
    );
    System.assertEquals(
      45.6066,
      load.rtms__First_Stop__r.rtms__Location2__r.ShippingLatitude
    );
    System.assertEquals(
      -79.3832,
      load.rtms__Last_Stop__r.rtms__Location2__r.ShippingLongitude
    );
  }

  @IsTest
  static void quoteCanBeBuiltInUsd() {
    PricingTestDataFactory.Graph g = PricingTestDataFactory.createGraph();
    rtms__Load__c load = PricingTestDataFactory.createLoad(
      g,
      g.originLocation,
      g.destinationLocation
    );
    rtms__CarrierQuote__c q = PricingTestDataFactory.buildQuote(
      g,
      load,
      1200,
      'USD'
    );
    insert q;
    q = [
      SELECT CurrencyIsoCode, rtms__Carrier_Total__c, CAD_Quote_Total__c
      FROM rtms__CarrierQuote__c
      WHERE Id = :q.Id
    ];
    System.assertEquals('USD', q.CurrencyIsoCode);
    System.assertEquals(1200, q.rtms__Carrier_Total__c);
    System.assertEquals(
      0,
      q.CAD_Quote_Total__c,
      'the CAD formula is zero for USD quotes; the service must use rtms__Carrier_Total__c per currency'
    );
  }

  @IsTest
  static void equipmentAndModeHelpersInsert() {
    rtms__EquipmentType__c reefer = PricingTestDataFactory.createEquipment(
      'Reefer 53\'',
      'Reefer'
    );
    rtms__Mode__c ltl = PricingTestDataFactory.createMode('LTL');
    System.assertNotEquals(null, reefer.Id);
    System.assertEquals(
      'Reefer',
      [
        SELECT rtms__Category__c
        FROM rtms__EquipmentType__c
        WHERE Id = :reefer.Id
      ]
      .rtms__Category__c
    );
    System.assertNotEquals(null, ltl.Id);
  }
}
