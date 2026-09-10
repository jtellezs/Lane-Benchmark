/**
 * Pricing_Place__c reads/writes on behalf of LaneBenchmarkController's geocode() and
 * mapPreviewUrl(). Split out of LaneBenchmarkController per the Task 3 review ruling ("split the
 * class instead of suppressing", same as LaneSearchService -> LaneSearchQueryBuilder): with this
 * logic inline the controller's PMD CyclomaticComplexity total was 53 against the 40 threshold.
 * Extracting private helpers within the controller alone does not fix a class TOTAL (it only adds
 * a "+1 method entry" per split, which measured 46 -> 53 for the same branches) - only moving the
 * branches to another class reduces the original class's total, so upsertFromGeocode() (place
 * matching/insert) and previewUrl() (place lookup + Mapbox circle building) live here instead.
 */
// Runs without sharing on purpose: same reasoning as LaneBenchmarkController - pricing benchmarks
// every team's quotes, and place lookups here are not user/record-specific. Access is gated by the
// Lane Benchmark permission sets.
public without sharing class LaneBenchmarkPlaceService {
  /**
   * Upserts one Pricing_Place__c per distinct city/province/country in results (Source__c =
   * 'Mapbox' for a newly inserted place; an existing place, from any source, is returned
   * untouched) and returns every candidate's final record keyed by its place key.
   */
  public static Map<String, Pricing_Place__c> upsertFromGeocode(
    List<MapboxGeocoder.GeoResult> results
  ) {
    Map<String, Pricing_Place__c> candidates = new Map<String, Pricing_Place__c>();
    for (MapboxGeocoder.GeoResult g : results) {
      toPlaceRecord(g, candidates);
    }
    Map<String, Pricing_Place__c> existing = findExisting(candidates.keySet());
    insertNewPlaces(candidates, existing);
    Map<String, Pricing_Place__c> merged = new Map<String, Pricing_Place__c>();
    for (String key : candidates.keySet()) {
      merged.put(
        key,
        existing.containsKey(key) ? existing.get(key) : candidates.get(key)
      );
    }
    return merged;
  }

  /** Builds the candidate place for one geocoder result, keyed by its normalized place key. */
  private static void toPlaceRecord(
    MapboxGeocoder.GeoResult g,
    Map<String, Pricing_Place__c> candidates
  ) {
    String key = PlaceNormalizer.key(g.city, g.province, g.country).left(120);
    if (candidates.containsKey(key)) {
      return;
    }
    Pricing_Place__c p = new Pricing_Place__c(
      Key__c = key,
      City__c = g.city,
      Province__c = g.province,
      Country__c = g.country,
      Name = (g.city + ', ' + g.province + ', ' + g.country).left(80),
      Geolocation__Latitude__s = g.lat,
      Geolocation__Longitude__s = g.lng,
      Postal_Prefix__c = g.postalPrefix,
      Source__c = 'Mapbox',
      Location_Count__c = 0,
      Load_Count_365d__c = 0,
      Active__c = true
    );
    candidates.put(key, p);
  }

  @SuppressWarnings(
    'PMD.ApexCRUDViolation'
  ) // system mode by design (see class comment)
  private static Map<String, Pricing_Place__c> findExisting(Set<String> keys) {
    Map<String, Pricing_Place__c> existing = new Map<String, Pricing_Place__c>();
    for (Pricing_Place__c p : [
      SELECT
        Key__c,
        Name,
        Province__c,
        Country__c,
        Source__c,
        Load_Count_365d__c,
        Geolocation__Latitude__s,
        Geolocation__Longitude__s
      FROM Pricing_Place__c
      WHERE Key__c IN :keys
    ]) {
      existing.put(p.Key__c, p);
    }
    return existing;
  }

  @SuppressWarnings(
    'PMD.ApexCRUDViolation'
  ) // system mode by design (see class comment)
  private static void insertNewPlaces(
    Map<String, Pricing_Place__c> candidates,
    Map<String, Pricing_Place__c> existing
  ) {
    List<Pricing_Place__c> toInsert = new List<Pricing_Place__c>();
    for (String key : candidates.keySet()) {
      if (!existing.containsKey(key)) {
        toInsert.add(candidates.get(key));
      }
    }
    insert toInsert;
  }

  /** Static Images URL for the origin/destination radii, or null when neither end has both a place and a radius. */
  public static String previewUrl(
    String originKey,
    Decimal originRadius,
    String destinationKey,
    Decimal destinationRadius,
    String unit
  ) {
    Decimal factor = unit == 'KM' ? 1 : 1.609344;
    Set<String> keys = new Set<String>();
    if (String.isNotBlank(originKey) && originRadius != null) {
      keys.add(originKey);
    }
    if (String.isNotBlank(destinationKey) && destinationRadius != null) {
      keys.add(destinationKey);
    }
    if (keys.isEmpty()) {
      return null;
    }
    Map<String, Pricing_Place__c> places = placesByKey(keys);
    List<MapboxGeocoder.Circle> circles = new List<MapboxGeocoder.Circle>();
    addCircle(circles, places.get(originKey), originRadius, factor, '#0070D2');
    addCircle(
      circles,
      places.get(destinationKey),
      destinationRadius,
      factor,
      '#2E844A'
    );
    return MapboxGeocoder.staticMapUrl(circles);
  }

  @SuppressWarnings(
    'PMD.ApexCRUDViolation'
  ) // system mode by design (see class comment)
  private static Map<String, Pricing_Place__c> placesByKey(Set<String> keys) {
    Map<String, Pricing_Place__c> places = new Map<String, Pricing_Place__c>();
    for (Pricing_Place__c p : [
      SELECT Key__c, Geolocation__Latitude__s, Geolocation__Longitude__s
      FROM Pricing_Place__c
      WHERE Key__c IN :keys
    ]) {
      places.put(p.Key__c, p);
    }
    return places;
  }

  private static void addCircle(
    List<MapboxGeocoder.Circle> circles,
    Pricing_Place__c p,
    Decimal radius,
    Decimal factor,
    String color
  ) {
    if (p == null || radius == null || p.Geolocation__Latitude__s == null) {
      return;
    }
    MapboxGeocoder.Circle c = new MapboxGeocoder.Circle();
    c.lat = p.Geolocation__Latitude__s;
    c.lng = p.Geolocation__Longitude__s;
    c.radiusKm = radius * factor;
    c.color = color;
    circles.add(c);
  }
}
