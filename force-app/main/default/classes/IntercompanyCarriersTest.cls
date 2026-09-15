/**
 * No DML and no setup-object writes here, so the class runs in parallel with the rest of the suite.
 * Account Ids are built from the key prefix rather than written out: PMD's AvoidHardcodingId matches
 * Id-shaped literals, and the real intercompany Ids belong only in the custom metadata records.
 */
@IsTest(IsParallel=true)
private class IntercompanyCarriersTest {
  /** A syntactically valid 15-character Id of the given object: its key prefix and twelve characters. */
  private static String fakeId(Schema.SObjectType objectType, String twelve) {
    return objectType.getDescribe().getKeyPrefix() + twelve;
  }

  /** An in-memory record: custom metadata cannot be inserted in tests (the MapboxTruckRouteTest pattern). */
  private static Intercompany_Carrier__mdt mdtRow(String accountId) {
    return (Intercompany_Carrier__mdt) JSON.deserialize(
      JSON.serialize(
        new Map<String, Object>{ 'Carrier_Account_Id__c' => accountId }
      ),
      Intercompany_Carrier__mdt.class
    );
  }

  @IsTest
  static void idsComeFromTheDeployedRecords() {
    // Asserts the wiring (custom metadata -> parseIds), not the org's data, like LaneSearchExclusionsTest.
    IntercompanyCarriers.idsOverride = null;
    List<Intercompany_Carrier__mdt> records = [
      SELECT Carrier_Account_Id__c
      FROM Intercompany_Carrier__mdt
      LIMIT 1000
    ];

    Test.startTest();
    Set<Id> accountIds = IntercompanyCarriers.ids();
    Test.stopTest();

    System.assert(
      !records.isEmpty(),
      'The intercompany carrier records must be deployed'
    );
    System.assert(
      accountIds.equals(IntercompanyCarriers.parseIds(records)),
      'ids() must return exactly what the deployed records parse to'
    );
    System.assert(
      !accountIds.isEmpty(),
      'The deployed records must name at least one carrier account'
    );
    for (Id accountId : accountIds) {
      System.assertEquals(
        Account.SObjectType,
        accountId.getSObjectType(),
        'every intercompany carrier is an Account'
      );
    }
  }

  @IsTest
  static void parseKeepsAccountIdsOfBothLengthsAndSkipsTheRest() {
    String account15 = fakeId(Account.SObjectType, '00000000000A');
    String account18 = String.valueOf(Id.valueOf(account15));
    String otherAccount15 = fakeId(Account.SObjectType, '00000000000B');
    String contact15 = fakeId(Contact.SObjectType, '00000000000A');

    Test.startTest();
    Set<Id> parsed = IntercompanyCarriers.parseIds(
      new List<Intercompany_Carrier__mdt>{
        mdtRow(account15),
        mdtRow(account18),
        mdtRow('  ' + otherAccount15 + '  '),
        mdtRow(contact15),
        mdtRow('not-an-id'),
        mdtRow('001-not-an-id!!'),
        mdtRow(account15.left(14)),
        mdtRow(''),
        mdtRow(null),
        null
      }
    );
    Test.stopTest();

    System.assertEquals(
      2,
      parsed.size(),
      'Only the two accounts survive, the 15- and 18-character forms of one being one entry: ' +
      String.valueOf(parsed)
    );
    System.assert(
      parsed.contains(Id.valueOf(account18)),
      'the account given in both lengths is kept'
    );
    System.assert(
      parsed.contains(Id.valueOf(otherAccount15)),
      'a padded entry is trimmed and kept'
    );
    System.assert(
      !parsed.contains(Id.valueOf(contact15)),
      'a Contact Id is not a carrier account'
    );
  }

  @IsTest
  static void overrideWinsOverTheRecordsAndIsReturnedAsACopy() {
    // A fake Account Id that no deployed record holds, so a merge with the records would show.
    Id sentinel = Id.valueOf(fakeId(Account.SObjectType, '00000000000Z'));
    IntercompanyCarriers.idsOverride = new Set<Id>{ sentinel };

    Test.startTest();
    IntercompanyCarriers.ids().clear();
    Set<Id> accountIds = IntercompanyCarriers.ids();
    Test.stopTest();

    System.assertEquals(
      1,
      accountIds.size(),
      'the deployed records are not consulted when the override is set, and a caller cannot empty it'
    );
    System.assert(accountIds.contains(sentinel), 'the override is returned');
  }

  @IsTest
  static void idsIsNeverNullWithoutAValidRecord() {
    // Custom metadata cannot be inserted in a test, so a list with no valid entry is simulated by
    // parsing one and feeding the result back through the public entry point the services call.
    IntercompanyCarriers.idsOverride = IntercompanyCarriers.parseIds(
      new List<Intercompany_Carrier__mdt>{ mdtRow(''), mdtRow('not-an-id') }
    );

    Test.startTest();
    Set<Id> accountIds = IntercompanyCarriers.ids();
    Set<Id> fromNull = IntercompanyCarriers.parseIds(null);
    Test.stopTest();

    System.assertNotEquals(null, accountIds, 'never null');
    System.assertEquals(0, accountIds.size(), 'and empty');
    System.assertNotEquals(null, fromNull, 'no record list gives a set');
    System.assertEquals(0, fromNull.size(), 'an empty one');
  }
}
