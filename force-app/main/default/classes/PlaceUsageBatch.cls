/**
 * Counts, per place key, the stops created in the last 365 days, and writes Load_Count_365d__c.
 * The changed rows are handed to PlaceWriteBatch (chainUsageBatch=false) rather than updated
 * directly here, for the same governor-limit reason PlaceBuilderBatch does: a single update of
 * every place in a large org can exceed the 10,000-DML-row-per-transaction limit.
 */
// Runs without sharing on purpose: pricing benchmarks every team's quotes. Access is gated by the Lane Benchmark permission sets.
public without sharing class PlaceUsageBatch implements Database.Batchable<SObject>, Database.Stateful {
  private Map<String, Integer> counts = new Map<String, Integer>();

  @SuppressWarnings(
    'PMD.ApexCRUDViolation'
  ) // system mode by design (see class comment)
  public Database.QueryLocator start(Database.BatchableContext bc) {
    return Database.getQueryLocator(
      [
        SELECT
          rtms__Location2__r.ShippingCity,
          rtms__Location2__r.ShippingState,
          rtms__Location2__r.ShippingCountry
        FROM rtms__Stop__c
        WHERE
          CreatedDate = LAST_N_DAYS:365
          AND rtms__Location2__c != NULL
          AND rtms__Location2__r.ShippingCity != NULL
      ]
    );
  }

  public void execute(Database.BatchableContext bc, List<rtms__Stop__c> scope) {
    for (rtms__Stop__c s : scope) {
      String key = PlaceNormalizer.key(
        s.rtms__Location2__r.ShippingCity,
        s.rtms__Location2__r.ShippingState,
        s.rtms__Location2__r.ShippingCountry
      );
      counts.put(key, (counts.containsKey(key) ? counts.get(key) : 0) + 1);
    }
  }

  public void finish(Database.BatchableContext bc) {
    // chainUsageBatch=false: nothing chains off this write, so there's no risk of re-entering
    // PlaceUsageBatch in a loop.
    Database.executeBatch(new PlaceWriteBatch(buildUpdates(), false), 2000);
  }

  @TestVisible
  private List<Pricing_Place__c> buildUpdatesForTest() {
    return buildUpdates();
  }

  @SuppressWarnings(
    'PMD.ApexCRUDViolation'
  ) // system mode by design (see class comment)
  private List<Pricing_Place__c> buildUpdates() {
    List<Pricing_Place__c> updates = new List<Pricing_Place__c>();
    for (Pricing_Place__c p : [
      SELECT Key__c, Load_Count_365d__c
      FROM Pricing_Place__c
    ]) {
      Integer n = counts.containsKey(p.Key__c) ? counts.get(p.Key__c) : 0;
      if (p.Load_Count_365d__c != n) {
        updates.add(
          new Pricing_Place__c(Key__c = p.Key__c, Load_Count_365d__c = n)
        );
      }
    }
    return updates;
  }
}
