@IsTest
private class LaneBenchmarkPlaceServiceTest {
  private static Pricing_Place__c place(
    String city,
    String prov,
    String country,
    Decimal lat,
    Decimal lng,
    String source
  ) {
    return new Pricing_Place__c(
      Name = city + ', ' + prov + ', ' + country,
      Key__c = PlaceNormalizer.key(city, prov, country),
      City__c = city,
      Province__c = prov,
      Country__c = country,
      Geolocation__Latitude__s = lat,
      Geolocation__Longitude__s = lng,
      Active__c = true,
      Source__c = source
    );
  }

  private static MapboxGeocoder.GeoResult saguenay() {
    MapboxGeocoder.GeoResult g = new MapboxGeocoder.GeoResult();
    g.name = 'Saguenay, Quebec, Canada';
    g.city = 'Saguenay';
    g.province = 'QC';
    g.country = 'CA';
    g.lat = 48.4279;
    g.lng = -71.0656;
    return g;
  }

  @IsTest
  static void upsertFromGeocodeCalledTwiceInSameTransactionIsIdempotent() {
    List<MapboxGeocoder.GeoResult> results = new List<MapboxGeocoder.GeoResult>{
      saguenay()
    };
    Test.startTest();
    Map<String, Pricing_Place__c> first = LaneBenchmarkPlaceService.upsertFromGeocode(
      results
    );
    Map<String, Pricing_Place__c> second = LaneBenchmarkPlaceService.upsertFromGeocode(
      results
    );
    Test.stopTest();
    Id firstId = first.get('saguenay|qc|ca').Id;
    Id secondId = second.get('saguenay|qc|ca').Id;
    System.assertNotEquals(null, firstId);
    System.assertEquals(
      firstId,
      secondId,
      'second call must resolve to the same record without throwing'
    );
    System.assertEquals(
      1,
      [SELECT COUNT() FROM Pricing_Place__c WHERE Key__c = 'saguenay|qc|ca']
    );
  }

  @IsTest
  static void preInsertedDuplicateKeyResolvesToTheExistingRecord() {
    Pricing_Place__c existing = place(
      'Saguenay',
      'QC',
      'CA',
      48.4279,
      -71.0656,
      'Locations'
    );
    insert existing;
    Map<String, Pricing_Place__c> out = LaneBenchmarkPlaceService.upsertFromGeocode(
      new List<MapboxGeocoder.GeoResult>{ saguenay() }
    );
    Pricing_Place__c resolved = out.get('saguenay|qc|ca');
    System.assertEquals(existing.Id, resolved.Id);
    System.assertEquals(
      'Locations',
      resolved.Source__c,
      'the pre-existing record is returned untouched, not overwritten by the geocode candidate'
    );
    System.assertEquals(
      1,
      [SELECT COUNT() FROM Pricing_Place__c WHERE Key__c = 'saguenay|qc|ca']
    );
  }
}
