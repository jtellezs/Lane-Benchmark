/**
 * Turns a Mapbox geocoding JSON response into MapboxGeocoder.GeoResult rows. Split out of
 * MapboxGeocoder per the second final-review ruling ("split the class instead of suppressing",
 * same reasoning as LaneSearchService -> LaneSearchQueryBuilder and LaneBenchmarkController ->
 * LaneBenchmarkPlaceService): with parsing inline, MapboxGeocoder's class-wide PMD cyclomatic
 * complexity was 47 against the 40 threshold, and parse()/applyContext() were themselves each at
 * the 10-per-method limit.
 */
public with sharing class MapboxResponseParser {
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

  public static List<MapboxGeocoder.GeoResult> parse(String body) {
    Map<String, Object> root;
    try {
      root = (Map<String, Object>) JSON.deserializeUntyped(body);
    } catch (Exception e) {
      throw new MapboxException('Could not parse the Mapbox response');
    }
    List<MapboxGeocoder.GeoResult> out = new List<MapboxGeocoder.GeoResult>();
    List<Object> features = (List<Object>) root.get('features');
    if (features == null) {
      return out;
    }
    for (Object f : features) {
      MapboxGeocoder.GeoResult g = toGeoResult((Map<String, Object>) f);
      if (g != null) {
        out.add(g);
      }
    }
    return out;
  }

  /** Null when the feature has no usable center, or resolves to neither a city nor a country. */
  private static MapboxGeocoder.GeoResult toGeoResult(
    Map<String, Object> feat
  ) {
    List<Object> center = (List<Object>) feat.get('center');
    if (!hasValidCenter(center)) {
      return null;
    }
    MapboxGeocoder.GeoResult g = new MapboxGeocoder.GeoResult();
    g.name = (String) feat.get('place_name');
    g.lng = Decimal.valueOf(String.valueOf(center[0]));
    g.lat = Decimal.valueOf(String.valueOf(center[1]));
    applyCityOrPostal(g, feat);
    applyContext(g, (List<Object>) feat.get('context'));
    return g.city != null && g.country != null ? g : null;
  }

  private static Boolean hasValidCenter(List<Object> center) {
    return center != null && center.size() == 2;
  }

  private static void applyCityOrPostal(
    MapboxGeocoder.GeoResult g,
    Map<String, Object> feat
  ) {
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
  }

  private static void applyContext(
    MapboxGeocoder.GeoResult g,
    List<Object> ctx
  ) {
    if (ctx == null) {
      return;
    }
    for (Object c : ctx) {
      applyContextItem(g, (Map<String, Object>) c);
    }
  }

  private static void applyContextItem(
    MapboxGeocoder.GeoResult g,
    Map<String, Object> item
  ) {
    String id = (String) item.get('id');
    if (id == null) {
      return;
    }
    if (id.startsWith('place.') && g.city == null) {
      g.city = (String) item.get('text');
    } else if (id.startsWith('region.') && item.get('short_code') != null) {
      g.province = provinceFromShortCode((String) item.get('short_code'));
    } else if (id.startsWith('country.') && item.get('short_code') != null) {
      g.country = ((String) item.get('short_code')).toUpperCase();
    }
  }

  /** 'CA-QC' -> 'QC', 'US-TX' -> 'TX', 'MX-NLE' -> 'NL' (Revenova's code); unknown suffix kept. */
  public static String provinceFromShortCode(String shortCode) {
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
}
