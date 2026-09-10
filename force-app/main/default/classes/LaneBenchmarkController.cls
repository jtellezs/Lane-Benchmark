/**
 * Aura/LWC entry points for the Lane Benchmark page. Thin: validation and error
 * translation here, all search logic in LaneSearchService. geocode()/mapPreviewUrl()'s
 * Pricing_Place__c read/write logic lives in LaneBenchmarkPlaceService (see that class's doc
 * comment for why: keeping it inline pushed this class's PMD CyclomaticComplexity total to 53
 * against the 40 threshold).
 */
// Runs without sharing on purpose: pricing benchmarks every team's quotes. Access is gated by the Lane Benchmark permission sets.
public without sharing class LaneBenchmarkController {
  public class PlaceOption {
    @AuraEnabled
    public String key;
    @AuraEnabled
    public String label;
    @AuraEnabled
    public String province;
    @AuraEnabled
    public String country;
    @AuraEnabled
    public String source;
    @AuraEnabled
    public Decimal loadCount;
    @AuraEnabled
    public Decimal lat;
    @AuraEnabled
    public Decimal lng;
  }

  public class FilterOptions {
    @AuraEnabled
    public List<String> modes = new List<String>();
    @AuraEnabled
    public Map<String, List<String>> equipmentByCategory = new Map<String, List<String>>();
    @AuraEnabled
    public List<String> currencies = new List<String>{ 'CAD', 'USD' };
  }

  @TestVisible
  private static List<MapboxGeocoder.GeoResult> geocoderOverride;

  @AuraEnabled(cacheable=true)
  public static LaneSearchResult search(String requestJson) {
    LaneSearchRequest req;
    try {
      req = (LaneSearchRequest) JSON.deserialize(
        requestJson,
        LaneSearchRequest.class
      );
    } catch (Exception e) {
      throw userError(
        'The search request could not be read. Please reset the filters and try again.'
      );
    }
    try {
      return LaneSearchService.search(req);
    } catch (LaneSearchException e) {
      throw userError(e.getMessage());
    } catch (QueryException e) {
      throw userError(
        'The search took too long or returned too much data. Narrow the lookback or the radius and try again. (' +
          e.getMessage() +
          ')'
      );
    }
  }

  @AuraEnabled(cacheable=true)
  @SuppressWarnings(
    'PMD.ApexCRUDViolation'
  ) // system mode by design (see class comment)
  public static List<PlaceOption> searchPlaces(
    String term,
    Integer limitCount
  ) {
    List<PlaceOption> out = new List<PlaceOption>();
    if (term == null || term.trim().length() < 2) {
      return out;
    }
    Integer lim = limitCount == null ||
      limitCount < 1
      ? 10
      : Math.min(limitCount, 10);
    String keyPattern =
      LaneSearchQueryBuilder.escapeLike(PlaceNormalizer.normalizeCity(term)) +
      '%';
    String aliasPattern =
      '%' +
      LaneSearchQueryBuilder.escapeLike(term.trim()) +
      '%';
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
      WHERE
        Active__c = TRUE
        AND (Key__c LIKE :keyPattern
        OR Aliases__c LIKE :aliasPattern)
      ORDER BY Load_Count_365d__c DESC NULLS LAST, Name
      LIMIT :lim
    ]) {
      out.add(toOption(p));
    }
    return out;
  }

  @AuraEnabled(cacheable=true)
  public static FilterOptions getFilterOptions() {
    FilterOptions o = new FilterOptions();
    addEnabledModes(o);
    addEnabledEquipment(o);
    return o;
  }

  @SuppressWarnings(
    'PMD.ApexCRUDViolation'
  ) // system mode by design (see class comment)
  private static void addEnabledModes(FilterOptions o) {
    for (rtms__Mode__c m : [
      SELECT Name
      FROM rtms__Mode__c
      WHERE rtms__Enabled__c = TRUE
      ORDER BY rtms__Order__c, Name
    ]) {
      o.modes.add(m.Name);
    }
  }

  @SuppressWarnings(
    'PMD.ApexCRUDViolation'
  ) // system mode by design (see class comment)
  private static void addEnabledEquipment(FilterOptions o) {
    for (rtms__EquipmentType__c e : [
      SELECT Name, rtms__Category__c
      FROM rtms__EquipmentType__c
      WHERE rtms__Enabled__c = TRUE
      ORDER BY rtms__Category__c NULLS LAST, Name
    ]) {
      String cat = String.isBlank(e.rtms__Category__c)
        ? 'Other'
        : e.rtms__Category__c;
      if (!o.equipmentByCategory.containsKey(cat)) {
        o.equipmentByCategory.put(cat, new List<String>());
      }
      o.equipmentByCategory.get(cat).add(e.Name);
    }
  }

  @AuraEnabled
  public static List<PlaceOption> geocode(String query, String countryHint) {
    if (query == null || query.trim().length() < 3) {
      throw userError('Type at least 3 characters to search the map.');
    }
    List<MapboxGeocoder.GeoResult> results = fetchGeoResults(
      query,
      countryHint
    );
    Map<String, Pricing_Place__c> places = LaneBenchmarkPlaceService.upsertFromGeocode(
      results
    );
    List<PlaceOption> out = new List<PlaceOption>();
    for (Pricing_Place__c p : places.values()) {
      out.add(toOption(p));
    }
    return out;
  }

  private static List<MapboxGeocoder.GeoResult> fetchGeoResults(
    String query,
    String countryHint
  ) {
    try {
      return geocoderOverride != null
        ? geocoderOverride
        : MapboxGeocoder.forward(query, countryHint);
    } catch (MapboxException e) {
      throw userError('Map search is unavailable right now. ' + e.getMessage());
    }
  }

  @AuraEnabled(cacheable=true)
  public static String mapPreviewUrl(
    String originKey,
    Decimal originRadius,
    String destinationKey,
    Decimal destinationRadius,
    String unit
  ) {
    return LaneBenchmarkPlaceService.previewUrl(
      originKey,
      originRadius,
      destinationKey,
      destinationRadius,
      unit
    );
  }

  private static PlaceOption toOption(Pricing_Place__c p) {
    PlaceOption o = new PlaceOption();
    o.key = p.Key__c;
    o.label = p.Name;
    o.province = p.Province__c;
    o.country = p.Country__c;
    o.source = p.Source__c;
    o.loadCount = p.Load_Count_365d__c;
    o.lat = p.Geolocation__Latitude__s;
    o.lng = p.Geolocation__Longitude__s;
    return o;
  }

  private static AuraHandledException userError(String message) {
    AuraHandledException e = new AuraHandledException(message);
    e.setMessage(message);
    return e;
  }
}
