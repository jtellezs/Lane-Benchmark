/**
 * Forward geocoding and static-map URLs through the company's Mapbox account.
 * Token: TPRO_KPI__c org default, Mapbox_Api_Key__c (public pk. token). Remote site: MapBox.
 * Only the search CENTER is geocoded; historical data is never sent to Mapbox.
 * Response parsing lives in MapboxResponseParser (see that class's doc comment for why): this
 * class keeps the callout itself (build the request, send with one retry, callout-error mapping).
 */
public with sharing class MapboxGeocoder {
  private static final String BASE = 'https://api.mapbox.com';
  private static final Integer TIMEOUT_MS = 10000;

  public class GeoResult {
    public String name;
    public String city;
    public String province;
    public String country;
    public Decimal lat;
    public Decimal lng;
    public String postalPrefix;
  }

  public class Circle {
    public Decimal lat;
    public Decimal lng;
    public Decimal radiusKm;
    public String color;
  }

  @TestVisible
  private static String token() {
    return TPRO_KPI__c.getOrgDefaults().Mapbox_Api_Key__c;
  }

  public static List<GeoResult> forward(String query, String countryHint) {
    if (String.isBlank(query)) {
      throw new MapboxException('Query is required');
    }
    String t = token();
    if (String.isBlank(t)) {
      throw new MapboxException(
        'Mapbox token is not configured (TPRO_KPI__c.Mapbox_Api_Key__c)'
      );
    }
    HttpRequest req = buildRequest(query, countryHint, t);
    HttpResponse res = sendWithRetry(req);
    if (res.getStatusCode() != 200) {
      throw new MapboxException(
        'Mapbox geocoding failed: HTTP ' + res.getStatusCode()
      );
    }
    return MapboxResponseParser.parse(res.getBody());
  }

  private static HttpRequest buildRequest(
    String query,
    String countryHint,
    String token
  ) {
    String countries = sanitizeCountryHint(countryHint);
    String url =
      BASE +
      '/geocoding/v5/mapbox.places/' +
      EncodingUtil.urlEncode(query.trim(), 'UTF-8') +
      '.json' +
      '?limit=5&language=en&types=place,locality,postcode' +
      (countries != null ? '&country=' + countries : '') +
      '&access_token=' +
      token;
    HttpRequest req = new HttpRequest();
    req.setEndpoint(url);
    req.setMethod('GET');
    req.setTimeout(TIMEOUT_MS);
    return req;
  }

  private static HttpResponse sendWithRetry(HttpRequest req) {
    Http http = new Http();
    try {
      HttpResponse res = http.send(req);
      if (res.getStatusCode() >= 500) {
        res = http.send(req); // one retry
      }
      return res;
    } catch (System.CalloutException e) {
      throw new MapboxException('Mapbox is not reachable right now');
    }
  }

  /** Only 'xx' or 'xx,yy,...' (ISO-3166 alpha-2, lowercase) is forwarded to Mapbox; anything else is dropped. */
  @TestVisible
  private static String sanitizeCountryHint(String countryHint) {
    if (String.isBlank(countryHint)) {
      return 'ca,us,mx';
    }
    String normalized = countryHint.toLowerCase();
    return Pattern.matches('^[a-z]{2}(,[a-z]{2})*$', normalized)
      ? normalized
      : null;
  }

  /** 'CA-QC' -> 'QC', 'US-TX' -> 'TX', 'MX-NLE' -> 'NL' (Revenova's code); unknown suffix kept. */
  @TestVisible
  private static String provinceFromShortCode(String shortCode) {
    return MapboxResponseParser.provinceFromShortCode(shortCode);
  }

  /** Static Images API URL with one polygon per circle (24 points each), or null without a token / circles. */
  public static String staticMapUrl(List<Circle> circles) {
    String t = token();
    if (String.isBlank(t) || circles == null || circles.isEmpty()) {
      return null;
    }
    List<String> features = new List<String>();
    for (Circle c : circles) {
      List<String> pts = new List<String>();
      Decimal latKm = 111.32;
      Decimal lngKm = 111.32 * Math.cos(c.lat.doubleValue() * Math.PI / 180);
      for (Integer i = 0; i <= 24; i++) {
        Double a = i * 2 * Math.PI / 24;
        Decimal lat = (c.lat + c.radiusKm / latKm * Math.cos(a)).setScale(4);
        Decimal lng = (c.lng + c.radiusKm / lngKm * Math.sin(a)).setScale(4);
        pts.add('[' + lng + ',' + lat + ']');
      }
      features.add(
        '{"type":"Feature","properties":{"stroke":"' +
          c.color +
          '","stroke-width":2,"fill":"' +
          c.color +
          '","fill-opacity":0.15},' +
          '"geometry":{"type":"Polygon","coordinates":[[' +
          String.join(pts, ',') +
          ']]}}'
      );
    }
    String geojson =
      '{"type":"FeatureCollection","features":[' +
      String.join(features, ',') +
      ']}';
    return BASE +
      '/styles/v1/mapbox/streets-v12/static/geojson(' +
      EncodingUtil.urlEncode(geojson, 'UTF-8') +
      ')/auto/600x300?padding=40&access_token=' +
      t;
  }
}
