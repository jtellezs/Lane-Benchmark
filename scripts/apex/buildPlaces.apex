// Build or refresh the Pricing_Place__c dictionary - see "Place dictionary" in README.md.
// PlaceBuilderBatch.finish() chains PlaceWriteBatch, which upserts the built rows in
// governor-safe per-scope transactions, then chains PlaceUsageBatch to fill
// Load_Count_365d__c. Safe to rerun at any time: it never deletes a place and never
// overwrites Aliases__c or Active__c.
//
//     sf apex run -o sandbox -f scripts/apex/buildPlaces.apex
//
// The batches run asynchronously - watch them in Setup > Apex Jobs. A full build took
// about an hour in PostProduc and produced 10,496 places.
Database.executeBatch(new PlaceBuilderBatch(), 2000);
