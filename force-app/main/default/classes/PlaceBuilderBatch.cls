/**
 * Builds Pricing_Place__c from every location account referenced by a stop:
 * one place per normalized key, averaged coordinates, spellings, counts.
 * Upserts by Key__c (via PlaceWriteBatch); never deletes; never touches Aliases__c or Active__c.
 * finish() hands the built rows to PlaceWriteBatch, which chains PlaceUsageBatch once every row
 * is written, to fill Load_Count_365d__c. The rows are built here but never upserted directly:
 * a single upsert (even chunked across several Database.upsert calls) still counts every row
 * against this transaction's 10,000-DML-row limit, which a large org's distinct place count can
 * exceed; PlaceWriteBatch spreads the upsert across its own per-scope transactions instead.
 */
// Runs without sharing on purpose: pricing benchmarks every team's quotes. Access is gated by the Lane Benchmark permission sets.
public without sharing class PlaceBuilderBatch implements Database.Batchable<SObject>, Database.Stateful {
  private class Agg {
    String province;
    String country;
    Decimal latSum = 0;
    Decimal lngSum = 0;
    Integer geoCount = 0;
    Integer locationCount = 0;
    Map<String, Integer> prefixCounts = new Map<String, Integer>();
    // Every spelling seen for this key, with how often; the keys alone are the spelling set.
    Map<String, Integer> spellingCounts = new Map<String, Integer>();
  }

  private Map<String, Agg> aggs = new Map<String, Agg>();

  @SuppressWarnings(
    'PMD.ApexCRUDViolation'
  ) // system mode by design (see class comment)
  public Database.QueryLocator start(Database.BatchableContext bc) {
    return Database.getQueryLocator(
      [
        SELECT
          Id,
          ShippingCity,
          ShippingState,
          ShippingCountry,
          ShippingPostalCode,
          ShippingLatitude,
          ShippingLongitude
        FROM Account
        WHERE
          ShippingCity != NULL
          AND Id IN (SELECT rtms__Location2__c FROM rtms__Stop__c)
      ]
    );
  }

  public void execute(Database.BatchableContext bc, List<Account> scope) {
    for (Account a : scope) {
      String key = PlaceNormalizer.key(
        a.ShippingCity,
        a.ShippingState,
        a.ShippingCountry
      );
      if (key.startsWith('|')) {
        continue; // no usable city
      }
      Agg g = aggs.get(key);
      if (g == null) {
        g = new Agg();
        g.province = PlaceNormalizer.provinceCode(a.ShippingState);
        g.country = PlaceNormalizer.countryCode(a.ShippingCountry);
        aggs.put(key, g);
      }
      g.locationCount++;
      String spelling = a.ShippingCity.trim();
      g.spellingCounts.put(
        spelling,
        (g.spellingCounts.containsKey(spelling)
          ? g.spellingCounts.get(spelling)
          : 0) + 1
      );
      if (a.ShippingLatitude != null && a.ShippingLongitude != null) {
        g.latSum += a.ShippingLatitude;
        g.lngSum += a.ShippingLongitude;
        g.geoCount++;
      }
      if (String.isNotBlank(a.ShippingPostalCode)) {
        String p = a.ShippingPostalCode.replace(' ', '').left(3).toUpperCase();
        g.prefixCounts.put(
          p,
          (g.prefixCounts.containsKey(p) ? g.prefixCounts.get(p) : 0) + 1
        );
      }
    }
  }

  public void finish(Database.BatchableContext bc) {
    // Deliberate: every built row is held in this instance's heap until PlaceWriteBatch takes
    // them, so a growing org's headroom against the 12 MB async cap is worth having in the log.
    System.debug(
      LoggingLevel.WARN,
      'PlaceBuilderBatch heap ' + Limits.getHeapSize()
    );
    Database.executeBatch(new PlaceWriteBatch(buildPlaces(), true), 2000);
  }

  @TestVisible
  private List<Pricing_Place__c> buildPlacesForTest() {
    return buildPlaces();
  }

  // Builds the Pricing_Place__c rows in memory only - no DML here. PlaceWriteBatch does the
  // upsert, in its own governor-safe, per-scope transactions; Aliases__c and Active__c are never
  // set on these rows, so an upsert by external id updates only the fields set below.
  private List<Pricing_Place__c> buildPlaces() {
    List<Pricing_Place__c> places = new List<Pricing_Place__c>();
    for (String key : aggs.keySet()) {
      Agg g = aggs.get(key);
      // Key__c is Text(120); PlaceUsageBatch caps its own keys the same way so the two match.
      Pricing_Place__c p = new Pricing_Place__c(Key__c = key.left(120));
      p.City__c = mostCommon(g.spellingCounts);
      // No truncation: provinceCode() returns either a 2-letter code or the value as typed, and
      // Province__c is Text(80) - as wide as Account.ShippingState - so every value fits whole.
      p.Province__c = g.province;
      p.Country__c = g.country.left(2);
      p.Name = displayName(p.City__c, p.Province__c, p.Country__c);
      p.Location_Count__c = g.locationCount;
      p.Spellings__c = joinSpellings(g.spellingCounts.keySet());
      p.Postal_Prefix__c = g.prefixCounts.isEmpty()
        ? null
        : mostCommon(g.prefixCounts);
      if (g.geoCount > 0) {
        p.Geolocation__Latitude__s = (g.latSum / g.geoCount).setScale(6);
        p.Geolocation__Longitude__s = (g.lngSum / g.geoCount).setScale(6);
      }
      places.add(p);
    }
    return places;
  }

  /**
   * "City, PROV, CC" within Name's 80 characters, shortening the CITY when it does not fit and
   * never the province: a truncated province ("GENERAL ESCOBEDO, Nue, MX") reads as a different
   * place entirely, which is the defect this replaced.
   */
  private static String displayName(
    String city,
    String province,
    String country
  ) {
    String suffix = ', ' + province + ', ' + country;
    Integer room = 80 - suffix.length();
    String shownCity = room >= city.length()
      ? city
      : city.left(Math.max(room, 0));
    return (shownCity + suffix).left(80);
  }

  /**
   * Every spelling, sorted, one per line, cut at a line boundary so Spellings__c (LongTextArea,
   * 4000) never ends mid-word: a partial city name reads as a real spelling that nothing produced.
   */
  private static String joinSpellings(Set<String> spellings) {
    List<String> sorted = new List<String>(spellings);
    sorted.sort();
    List<String> kept = new List<String>();
    Integer length = 0;
    for (String spelling : sorted) {
      Integer added = (kept.isEmpty() ? 0 : 1) + spelling.length();
      if (length + added > 4000) {
        break;
      }
      kept.add(spelling);
      length += added;
    }
    return String.join(kept, '\n');
  }

  /**
   * The most frequent value, ties broken by the lowest value: iterating a Map's keySet is not
   * ordered, so without the sort a rerun over identical data could pick a different display
   * spelling (or postal prefix) and rewrite every affected place for no reason.
   */
  private static String mostCommon(Map<String, Integer> counts) {
    List<String> keys = new List<String>(counts.keySet());
    keys.sort();
    String best;
    Integer bestN = -1;
    for (String k : keys) {
      if (counts.get(k) > bestN) {
        best = k;
        bestN = counts.get(k);
      }
    }
    return best;
  }
}
