/**
 * Builds Pricing_Place__c from every location account referenced by a stop:
 * one place per normalized key, averaged coordinates, spellings, counts.
 * Upserts by Key__c; never deletes; never touches Aliases__c or Active__c.
 * finish() chains PlaceUsageBatch to fill Load_Count_365d__c.
 */
// Runs without sharing on purpose: pricing benchmarks every team's quotes. Access is gated by the Lane Benchmark permission sets.
public without sharing class PlaceBuilderBatch implements Database.Batchable<SObject>, Database.Stateful {
  private class Agg {
    String city;
    String province;
    String country;
    Decimal latSum = 0;
    Decimal lngSum = 0;
    Integer geoCount = 0;
    Integer locationCount = 0;
    Set<String> spellings = new Set<String>();
    Map<String, Integer> prefixCounts = new Map<String, Integer>();
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
      g.spellings.add(spelling);
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
    upsertPlaces();
    Database.executeBatch(new PlaceUsageBatch(), 2000);
  }

  @TestVisible
  private void finishForTest() {
    upsertPlaces();
  }

  @SuppressWarnings(
    'PMD.ApexCRUDViolation'
  ) // system mode by design (see class comment)
  private void upsertPlaces() {
    List<Pricing_Place__c> places = new List<Pricing_Place__c>();
    for (String key : aggs.keySet()) {
      Agg g = aggs.get(key);
      Pricing_Place__c p = new Pricing_Place__c(Key__c = key);
      p.City__c = mostCommon(g.spellingCounts);
      p.Province__c = g.province.left(3);
      p.Country__c = g.country.left(2);
      p.Name = (p.City__c +
        ', ' +
        p.Province__c +
        ', ' +
        p.Country__c)
        .left(80);
      p.Location_Count__c = g.locationCount;
      p.Spellings__c = String.join(new List<String>(g.spellings), '\n')
        .left(4000);
      p.Postal_Prefix__c = g.prefixCounts.isEmpty()
        ? null
        : mostCommon(g.prefixCounts);
      if (g.geoCount > 0) {
        p.Geolocation__Latitude__s = (g.latSum / g.geoCount).setScale(6);
        p.Geolocation__Longitude__s = (g.lngSum / g.geoCount).setScale(6);
      }
      places.add(p);
    }
    // Upsert by external id updates only the fields set above; Aliases__c and Active__c are untouched.
    for (Integer i = 0; i < places.size(); i += 2000) {
      List<Pricing_Place__c> chunk = new List<Pricing_Place__c>();
      for (Integer j = i; j < Math.min(i + 2000, places.size()); j++) {
        chunk.add(places[j]);
      }
      Database.upsert(chunk, Pricing_Place__c.Key__c, true); // NOPMD - chunked to 2000 rows, within governor limits
    }
  }

  private static String mostCommon(Map<String, Integer> counts) {
    String best;
    Integer bestN = -1;
    for (String k : counts.keySet()) {
      if (counts.get(k) > bestN) {
        best = k;
        bestN = counts.get(k);
      }
    }
    return best;
  }
}
