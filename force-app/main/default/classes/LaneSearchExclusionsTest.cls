/**
 * No DML and no setup-object writes here, so the class runs in parallel with the rest of the suite.
 */
@IsTest(IsParallel=true)
private class LaneSearchExclusionsTest {
  @IsTest
  static void excludedContactIdsComeFromCustomMetadataInBothIdLengths() {
    // Asserts the wiring (custom metadata -> parseExcludedContactIds), not the org's data:
    // re-parsing the deployed ids here would only restate parseExcludedContactIds' own logic,
    // and would break whenever an admin adds an entry this test did not anticipate.
    LaneSearchExclusions.excludedContactIdsOverride = null;
    Set<String> ids = LaneSearchExclusions.excludedContactIds();
    List<Pricing_Department_Setting__mdt> settings = [
      SELECT Excluded_Contact_Ids__c
      FROM Pricing_Department_Setting__mdt
      WHERE DeveloperName = 'Default'
    ];

    System.assertEquals(
      1,
      settings.size(),
      'The Default setting record must be deployed'
    );
    System.assert(
      ids.equals(
        LaneSearchExclusions.parseExcludedContactIds(
          settings[0].Excluded_Contact_Ids__c
        )
      ),
      'excludedContactIds() must return exactly what the Default record parses to'
    );
    System.assert(
      !ids.isEmpty(),
      'The Default record must exclude at least one contact'
    );
  }

  @IsTest
  @SuppressWarnings('PMD.AvoidHardcodingId')
  static void parseExcludedContactIdsSkipsInvalidEntries() {
    String validContactId = '0033l00002px9ja';
    Id validId = Id.valueOf(validContactId);

    Test.startTest();
    Set<String> ids = LaneSearchExclusions.parseExcludedContactIds(
      validContactId + ', not-an-id, 0033l00002px9j, 001000000000001AAA ,'
    );
    Set<String> fromNull = LaneSearchExclusions.parseExcludedContactIds(null);
    Set<String> fromBlank = LaneSearchExclusions.parseExcludedContactIds('  ');
    Test.stopTest();

    System.assertEquals(
      2,
      ids.size(),
      'Only the valid Contact id (both forms) should survive: ' +
      String.join(new List<String>(ids), ', ')
    );
    System.assert(
      ids.contains(String.valueOf(validId)),
      '18-char form present'
    );
    System.assert(
      ids.contains(String.valueOf(validId).left(15)),
      '15-char form present'
    );
    System.assertEquals(0, fromNull.size(), 'null input yields an empty set');
    System.assertEquals(0, fromBlank.size(), 'blank input yields an empty set');
  }

  @IsTest
  static void overrideWinsOverCustomMetadata() {
    // A sentinel rather than a Contact Id: the override is returned verbatim, never parsed,
    // and no real id could prove the Default record was skipped rather than merged.
    LaneSearchExclusions.excludedContactIdsOverride = new Set<String>{
      'OVERRIDE-ONLY'
    };

    Test.startTest();
    Set<String> ids = LaneSearchExclusions.excludedContactIdSet();
    Test.stopTest();

    System.assertEquals(
      1,
      ids.size(),
      'the Default record must not be consulted when the override is set'
    );
    System.assert(ids.contains('OVERRIDE-ONLY'), 'the override is returned');
  }

  @IsTest
  static void excludedContactIdSetIsNeverNullForAnEmptyField() {
    // Custom metadata cannot be inserted in a test, so a Default record with a blank
    // Excluded_Contact_Ids__c is simulated by parsing that blank value and feeding the
    // result back through the same public entry point the lane search calls.
    LaneSearchExclusions.excludedContactIdsOverride = LaneSearchExclusions.parseExcludedContactIds(
      ''
    );

    Test.startTest();
    Set<String> ids = LaneSearchExclusions.excludedContactIdSet();
    Test.stopTest();

    System.assertNotEquals(
      null,
      ids,
      'an empty Excluded_Contact_Ids__c must yield an empty set, never null'
    );
    System.assertEquals(0, ids.size(), 'and that set must be empty');
  }
}
