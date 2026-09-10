/**
 * Counts, per place key, the LOADS created in the last 365 days that touch that place, and writes
 * Load_Count_365d__c. One count per load END: a load whose first stop is in the place counts once,
 * a load whose last stop is in the place counts once, so a load that both picks up and delivers in
 * the same place counts 2 there. Ends whose stop has no location account, or whose location
 * account has no city, are skipped - they have no place to count against.
 *
 * Was "stops in the last 365 days", which counted a load's intermediate stops (a place could
 * score on a load that neither started nor ended there) and made the number impossible to state
 * plainly. Load_Count_365d__c means "loads touching this place (last 365 days)".
 *
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
          rtms__First_Stop__r.rtms__Location2__r.ShippingCity,
          rtms__First_Stop__r.rtms__Location2__r.ShippingState,
          rtms__First_Stop__r.rtms__Location2__r.ShippingCountry,
          rtms__Last_Stop__r.rtms__Location2__r.ShippingCity,
          rtms__Last_Stop__r.rtms__Location2__r.ShippingState,
          rtms__Last_Stop__r.rtms__Location2__r.ShippingCountry
        FROM rtms__Load__c
        WHERE CreatedDate = LAST_N_DAYS:365
      ]
    );
  }

  public void execute(Database.BatchableContext bc, List<rtms__Load__c> scope) {
    for (rtms__Load__c l : scope) {
      countEnd(l.rtms__First_Stop__r?.rtms__Location2__r);
      countEnd(l.rtms__Last_Stop__r?.rtms__Location2__r);
    }
  }

  /** One load end. Null location account, or one with no city, has no place to count against. */
  private void countEnd(Account location) {
    if (location == null || String.isBlank(location.ShippingCity)) {
      return;
    }
    String key = PlaceNormalizer.key(
      location.ShippingCity,
      location.ShippingState,
      location.ShippingCountry
    );
    counts.put(key, (counts.containsKey(key) ? counts.get(key) : 0) + 1);
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
