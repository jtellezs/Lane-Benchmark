/**
 * Forward geocoding and static-map URLs through the company's Mapbox account.
 * Token: TPRO_KPI__c org default, Mapbox_Api_Key__c (public pk. token). Remote site: MapBox.
 * Only the search CENTER is geocoded; historical data is never sent to Mapbox.
 */
public with sharing class MapboxGeocoder {
  private static final String BASE = 'https://api.mapbox.com';
  private static final Integer TIMEOUT_MS = 10000;
  private static final Map<String, String> MX_ISO_TO_REVENOVA = new Map<String, String>{
    'AGU' => 'AG',
    'BCN' => 'BC',
    'BCS' => 'BS',
    'CAM' => 'CP',
    'CHP' => 'CS',
    'CHH' => 'CH',
    'CMX' => 'MX',
    'COA' => 'CO',
    'COL' => 'CL',
    'DUR' => 'DG',
    'GUA' => 'GT',
    'GRO' => 'GR',
    'HID' => 'HG',
    'JAL' => 'JA',
    'MEX' => 'ME',
    'MIC' => 'MI',
    'MOR' => 'MO',
    'NAY' => 'NA',
    'NLE' => 'NL',
    'OAX' => 'OA',
    'PUE' => 'PB',
    'QUE' => 'QE',
    'ROO' => 'QR',
    'SLP' => 'SL',
    'SIN' => 'SI',
    'SON' => 'SO',
    'TAB' => 'TB',
    'TAM' => 'TM',
    'TLA' => 'TL',
    'VER' => 'VE',
    'YUC' => 'YU',
    'ZAC' => 'ZA'
  };

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
    String countries = sanitizeCountryHint(countryHint);
    String url =
      BASE +
      '/geocoding/v5/mapbox.places/' +
      EncodingUtil.urlEncode(query.trim(), 'UTF-8') +
      '.json' +
      '?limit=5&language=en&types=place,locality,postcode' +
      (countries != null ? '&country=' + countries : '') +
      '&access_token=' +
      t;
    HttpRequest req = new HttpRequest();
    req.setEndpoint(url);
    req.setMethod('GET');
    req.setTimeout(TIMEOUT_MS);
    Http http = new Http();
    HttpResponse res;
    try {
      res = http.send(req);
      if (res.getStatusCode() >= 500) {
        res = http.send(req); // one retry
      }
    } catch (System.CalloutException e) {
      throw new MapboxException('Mapbox is not reachable right now');
    }
    if (res.getStatusCode() != 200) {
      throw new MapboxException(
        'Mapbox geocoding failed: HTTP ' + res.getStatusCode()
      );
    }
    return parse(res.getBody());
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

  @TestVisible
  private static List<GeoResult> parse(String body) {
    Map<String, Object> root;
    try {
      root = (Map<String, Object>) JSON.deserializeUntyped(body);
    } catch (Exception e) {
      throw new MapboxException('Could not parse the Mapbox response');
    }
    List<GeoResult> out = new List<GeoResult>();
    List<Object> features = (List<Object>) root.get('features');
    if (features == null) {
      return out;
    }
    for (Object f : features) {
      Map<String, Object> feat = (Map<String, Object>) f;
      List<Object> center = (List<Object>) feat.get('center');
      if (!hasValidCenter(center)) {
        continue;
      }
      GeoResult g = new GeoResult();
      g.name = (String) feat.get('place_name');
      g.lng = Decimal.valueOf(String.valueOf(center[0]));
      g.lat = Decimal.valueOf(String.valueOf(center[1]));
      List<Object> types = (List<Object>) feat.get('place_type');
      Boolean isPostcode = types != null && types.contains('postcode');
      String text = (String) feat.get('text');
      if (isPostcode) {
        g.postalPrefix = text == null
          ? null
          : text.replace(' ', '').left(3).toUpperCase();
      } else {
        g.city = text;
      }
      applyContext(g, (List<Object>) feat.get('context'));
      if (g.city != null && g.country != null) {
        out.add(g);
      }
    }
    return out;
  }

  private static Boolean hasValidCenter(List<Object> center) {
    return center != null && center.size() == 2;
  }

  private static void applyContext(GeoResult g, List<Object> ctx) {
    if (ctx == null) {
      return;
    }
    for (Object c : ctx) {
      Map<String, Object> item = (Map<String, Object>) c;
      String id = (String) item.get('id');
      if (id == null) {
        continue;
      }
      if (id.startsWith('place.') && g.city == null) {
        g.city = (String) item.get('text');
      } else if (id.startsWith('region.') && item.get('short_code') != null) {
        g.province = provinceFromShortCode((String) item.get('short_code'));
      } else if (id.startsWith('country.') && item.get('short_code') != null) {
        g.country = ((String) item.get('short_code')).toUpperCase();
      }
    }
  }

  /** 'CA-QC' -> 'QC', 'US-TX' -> 'TX', 'MX-NLE' -> 'NL' (Revenova's code); unknown suffix kept. */
  @TestVisible
  private static String provinceFromShortCode(String shortCode) {
    if (String.isBlank(shortCode) || !shortCode.contains('-')) {
      return shortCode;
    }
    String prefix = shortCode.substringBefore('-').toUpperCase();
    String suffix = shortCode.substringAfter('-').toUpperCase();
    if (prefix == 'MX' && MX_ISO_TO_REVENOVA.containsKey(suffix)) {
      return MX_ISO_TO_REVENOVA.get(suffix);
    }
    return suffix;
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
