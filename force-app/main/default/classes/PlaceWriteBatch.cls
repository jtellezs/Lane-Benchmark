/**
 * Writes Pricing_Place__c rows in governor-safe chunks. Chunking a big upsert inside a single
 * method (even split across several Database.upsert calls) still counts every row against the
 * same transaction's 10,000-DML-row limit, because it is all one transaction. An iterable batch
 * avoids that: Salesforce runs each execute() scope as its own transaction, so upserting 2,000
 * rows per scope stays under the limit no matter how many Pricing_Place__c rows there are in
 * total (iterable batches accept up to 50,000 items in the source list).
 * Optionally chains PlaceUsageBatch once every scope has been written.
 *
 * Not Database.Stateful: nothing accumulates across scopes here. The records and the chain flag
 * are constructor state, which every transaction of a non-stateful batch gets back from the job's
 * original serialized copy anyway, so finish() still sees the flag it was built with.
 */
// Runs without sharing on purpose: pricing benchmarks every team's quotes. Access is gated by the Lane Benchmark permission sets.
public without sharing class PlaceWriteBatch implements Database.Batchable<Pricing_Place__c> {
  private List<Pricing_Place__c> records;
  private Boolean chainUsageBatch;

  public PlaceWriteBatch(
    List<Pricing_Place__c> records,
    Boolean chainUsageBatch
  ) {
    this.records = records;
    this.chainUsageBatch = chainUsageBatch;
  }

  public Iterable<Pricing_Place__c> start(Database.BatchableContext bc) {
    return records;
  }

  @SuppressWarnings(
    'PMD.ApexCRUDViolation'
  ) // system mode by design (see class comment)
  public void execute(
    Database.BatchableContext bc,
    List<Pricing_Place__c> scope
  ) {
    Database.upsert(scope, Pricing_Place__c.Key__c, true);
  }

  public void finish(Database.BatchableContext bc) {
    if (chainUsageBatch) {
      Database.executeBatch(new PlaceUsageBatch(), 2000);
    }
  }
}
