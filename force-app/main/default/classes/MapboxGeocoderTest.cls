@IsTest
private class MapboxGeocoderTest {
  private class Mock implements HttpCalloutMock {
    Integer status;
    String body;
    Integer calls = 0;
    Mock(Integer status, String body) {
      this.status = status;
      this.body = body;
    }
    public HttpResponse respond(HttpRequest req) {
      calls++;
      System.assert(
        req.getEndpoint()
          .startsWith('https://api.mapbox.com/geocoding/v5/mapbox.places/'),
        req.getEndpoint()
      );
      System.assert(
        req.getEndpoint().contains('access_token=pk.test'),
        req.getEndpoint()
      );
      HttpResponse r = new HttpResponse();
      r.setStatusCode(status);
      r.setBody(body);
      return r;
    }
  }

  private static void setToken(String t) {
    TPRO_KPI__c s = TPRO_KPI__c.getOrgDefaults();
    s.Mapbox_Api_Key__c = t;
    upsert s;
  }

  private static final String SAGUENAY = '{"features":[{"id":"place.1","type":"Feature","place_type":["place"],"text":"Saguenay","place_name":"Saguenay, Quebec, Canada","center":[-71.0656,48.4279],"context":[{"id":"region.1","text":"Quebec","short_code":"CA-QC"},{"id":"country.1","text":"Canada","short_code":"ca"}]},{"id":"postcode.2","type":"Feature","place_type":["postcode"],"text":"G7H 2N1","place_name":"G7H 2N1, Saguenay, Quebec, Canada","center":[-71.07,48.43],"context":[{"id":"place.1","text":"Saguenay"},{"id":"region.1","text":"Quebec","short_code":"CA-QC"},{"id":"country.1","text":"Canada","short_code":"ca"}]}]}';
  private static final String MONTERREY = '{"features":[{"id":"place.3","type":"Feature","place_type":["place"],"text":"Monterrey","place_name":"Monterrey, Nuevo León, Mexico","center":[-100.3161,25.6866],"context":[{"id":"region.3","text":"Nuevo León","short_code":"MX-NLE"},{"id":"country.3","text":"Mexico","short_code":"mx"}]}]}';

  @IsTest
  static void parsesPlacesAndPostcodes() {
    setToken('pk.test');
    Test.setMock(HttpCalloutMock.class, new Mock(200, SAGUENAY));
    Test.startTest();
    List<MapboxGeocoder.GeoResult> out = MapboxGeocoder.forward(
      'Saguenay QC',
      'ca'
    );
    Test.stopTest();
    System.assertEquals(2, out.size());
    System.assertEquals('Saguenay', out[0].city);
    System.assertEquals('QC', out[0].province);
    System.assertEquals('CA', out[0].country);
    System.assertEquals(48.4279, out[0].lat);
    System.assertEquals(-71.0656, out[0].lng);
    System.assertEquals(null, out[0].postalPrefix);
    System.assertEquals(
      'Saguenay',
      out[1].city,
      'postcode results take the city from context'
    );
    System.assertEquals('G7H', out[1].postalPrefix);
  }

  @IsTest
  static void mapsMexicanIsoRegionsToRevenovaCodes() {
    setToken('pk.test');
    Test.setMock(HttpCalloutMock.class, new Mock(200, MONTERREY));
    Test.startTest();
    List<MapboxGeocoder.GeoResult> out = MapboxGeocoder.forward(
      'Monterrey',
      null
    );
    Test.stopTest();
    System.assertEquals('NL', out[0].province);
    System.assertEquals('MX', out[0].country);
    System.assertEquals('QC', MapboxGeocoder.provinceFromShortCode('CA-QC'));
    System.assertEquals('TX', MapboxGeocoder.provinceFromShortCode('US-TX'));
    System.assertEquals('ME', MapboxGeocoder.provinceFromShortCode('MX-MEX'));
    System.assertEquals('PB', MapboxGeocoder.provinceFromShortCode('MX-PUE'));
    System.assertEquals('MX', MapboxGeocoder.provinceFromShortCode('MX-CMX'));
    System.assertEquals(
      'ZZZ',
      MapboxGeocoder.provinceFromShortCode('XX-ZZZ'),
      'unknown kept'
    );
  }

  @IsTest
  static void retriesOnceOnServerErrorThenThrows() {
    setToken('pk.test');
    Mock m = new Mock(503, 'down');
    Test.setMock(HttpCalloutMock.class, m);
    Test.startTest();
    try {
      MapboxGeocoder.forward('Saguenay', null);
      System.assert(false, 'expected MapboxException');
    } catch (MapboxException e) {
      System.assert(e.getMessage().contains('503'), e.getMessage());
    }
    Test.stopTest();
    System.assertEquals(2, m.calls, 'one retry');
  }

  @IsTest
  static void clientErrorAndMalformedJsonThrow() {
    setToken('pk.test');
    Test.setMock(
      HttpCalloutMock.class,
      new Mock(401, '{"message":"Not Authorized"}')
    );
    Test.startTest();
    try {
      MapboxGeocoder.forward('x', null);
      System.assert(false);
    } catch (MapboxException e) {
      System.assert(e.getMessage().contains('401'), e.getMessage());
    }
    Test.setMock(HttpCalloutMock.class, new Mock(200, 'not json'));
    try {
      MapboxGeocoder.forward('x', null);
      System.assert(false);
    } catch (MapboxException e) {
      System.assert(
        e.getMessage().toLowerCase().contains('parse'),
        e.getMessage()
      );
    }
    Test.stopTest();
  }

  @IsTest
  static void missingTokenThrowsBeforeCallout() {
    setToken(null);
    try {
      MapboxGeocoder.forward('Saguenay', null);
      System.assert(false);
    } catch (MapboxException e) {
      System.assert(e.getMessage().contains('not configured'), e.getMessage());
    }
    System.assertEquals(
      null,
      MapboxGeocoder.staticMapUrl(new List<MapboxGeocoder.Circle>())
    );
  }

  @IsTest
  static void staticMapUrlEncodesTwoCircles() {
    setToken('pk.test');
    MapboxGeocoder.Circle a = new MapboxGeocoder.Circle();
    a.lat = 45.5;
    a.lng = -73.5;
    a.radiusKm = 50;
    a.color = '#0070D2';
    MapboxGeocoder.Circle b = new MapboxGeocoder.Circle();
    b.lat = 43.6;
    b.lng = -79.4;
    b.radiusKm = 80;
    b.color = '#2E844A';
    String url = MapboxGeocoder.staticMapUrl(
      new List<MapboxGeocoder.Circle>{ a, b }
    );
    System.assert(
      url.startsWith(
        'https://api.mapbox.com/styles/v1/mapbox/streets-v12/static/geojson('
      ),
      url
    );
    System.assert(url.contains('/auto/600x300'), url);
    System.assert(url.contains('access_token=pk.test'), url);
    System.assert(
      url.length() < 8000,
      'URL must stay under browser limits: ' + url.length()
    );
  }
}
