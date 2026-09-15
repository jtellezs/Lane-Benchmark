/**
 * No DML and no setup-object writes here, so the class runs in parallel with the rest of the suite.
 */
@IsTest(IsParallel=true)
private class HandoffPointsTest {
  /** An in-memory record: custom metadata cannot be inserted in tests (the MapboxTruckRouteTest pattern). */
  private static Handoff_Point__mdt mdtRow(String placeKey, Boolean active) {
    Map<String, Object> fields = new Map<String, Object>{
      'Place_Key__c' => placeKey
    };
    if (active != null) {
      fields.put('Active__c', active);
    }
    return (Handoff_Point__mdt) JSON.deserialize(
      JSON.serialize(fields),
      Handoff_Point__mdt.class
    );
  }

  @IsTest
  static void activeKeysComeFromTheDeployedRecords() {
    // Asserts the wiring (custom metadata -> parseKeys), not which points an admin keeps active.
    HandoffPoints.keysOverride = null;
    List<Handoff_Point__mdt> records = [
      SELECT Place_Key__c, Active__c
      FROM Handoff_Point__mdt
      LIMIT 1000
    ];

    Test.startTest();
    List<String> placeKeys = HandoffPoints.activeKeys();
    Test.stopTest();

    System.assert(
      !records.isEmpty(),
      'The handoff point records must be deployed'
    );
    System.assertEquals(
      HandoffPoints.parseKeys(records),
      placeKeys,
      'activeKeys() must return exactly what the deployed records parse to'
    );
  }

  @IsTest
  static void parseKeepsActiveKeysTrimmedLowercasedDistinctAndSorted() {
    Test.startTest();
    List<String> placeKeys = HandoffPoints.parseKeys(
      new List<Handoff_Point__mdt>{
        mdtRow('  San Diego|CA|US ', true),
        mdtRow('laredo|tx|us', true),
        mdtRow('LAREDO|TX|US', true),
        mdtRow('calexico|ca|us', false),
        mdtRow('mexicali|bc|mx', null),
        mdtRow('   ', true),
        mdtRow(null, true),
        null
      }
    );
    Test.stopTest();

    System.assertEquals(
      new List<String>{ 'laredo|tx|us', 'san diego|ca|us' },
      placeKeys,
      'inactive, unset and blank records are dropped; keys are trimmed, lowercased, distinct and sorted'
    );
  }

  @IsTest
  static void overrideWinsOverTheRecordsAndIsReturnedAsACopy() {
    HandoffPoints.keysOverride = new List<String>{ 'override-only' };

    Test.startTest();
    HandoffPoints.activeKeys().clear();
    List<String> placeKeys = HandoffPoints.activeKeys();
    Test.stopTest();

    System.assertEquals(
      new List<String>{ 'override-only' },
      placeKeys,
      'the deployed records are not consulted when the override is set, and a caller cannot empty it'
    );
  }

  @IsTest
  static void activeKeysIsNeverNullWithoutAnActiveRecord() {
    HandoffPoints.keysOverride = HandoffPoints.parseKeys(
      new List<Handoff_Point__mdt>{ mdtRow('laredo|tx|us', false) }
    );

    Test.startTest();
    List<String> placeKeys = HandoffPoints.activeKeys();
    List<String> fromNull = HandoffPoints.parseKeys(null);
    Test.stopTest();

    System.assertNotEquals(null, placeKeys, 'never null');
    System.assertEquals(0, placeKeys.size(), 'and empty');
    System.assertNotEquals(null, fromNull, 'no record list gives a list');
    System.assertEquals(0, fromNull.size(), 'an empty one');
  }
}
