/**
 * Spec W1 and W3. The keys are the part that can lie: they are sorted as strings to put the
 * chart in chronological order, so a key that sorts differently than it reads puts a month in
 * the wrong place with nothing red.
 */
@IsTest
private class LaneTrendBucketsTest {
  @IsTest
  static void mapsEachWindowToTheUnitThatKeepsItLegible() {
    System.assertEquals(LaneTrendBuckets.DAY, LaneTrendBuckets.unitFor(7));
    System.assertEquals(LaneTrendBuckets.DAY, LaneTrendBuckets.unitFor(14));
    System.assertEquals(LaneTrendBuckets.DAY, LaneTrendBuckets.unitFor(30));
    System.assertEquals(LaneTrendBuckets.WEEK, LaneTrendBuckets.unitFor(60));
    System.assertEquals(LaneTrendBuckets.WEEK, LaneTrendBuckets.unitFor(90));
    System.assertEquals(LaneTrendBuckets.MONTH, LaneTrendBuckets.unitFor(182));
    System.assertEquals(LaneTrendBuckets.MONTH, LaneTrendBuckets.unitFor(365));
    System.assertEquals(LaneTrendBuckets.MONTH, LaneTrendBuckets.unitFor(730));
    System.assertEquals(LaneTrendBuckets.MONTH, LaneTrendBuckets.unitFor(1095));
  }

  @IsTest
  static void everyUnitsKeySortsAsStringExactlyAsItSortsInTime() {
    // The chart's order comes from keys.sort() on strings, so a key whose lexical order differs
    // from its chronological order silently reorders the axis.
    List<String> dayKeys = new List<String>{
      LaneTrendBuckets.keyOf(
        Date.newInstance(2026, 1, 9),
        LaneTrendBuckets.DAY
      ),
      LaneTrendBuckets.keyOf(
        Date.newInstance(2025, 12, 31),
        LaneTrendBuckets.DAY
      ),
      LaneTrendBuckets.keyOf(
        Date.newInstance(2026, 1, 10),
        LaneTrendBuckets.DAY
      )
    };
    dayKeys.sort();
    System.assertEquals(
      new List<String>{ '2025-12-31', '2026-01-09', '2026-01-10' },
      dayKeys,
      'a day key must zero-pad both month and day, or the 9th sorts after the 10th'
    );

    List<String> monthKeys = new List<String>{
      LaneTrendBuckets.keyOf(
        Date.newInstance(2026, 10, 5),
        LaneTrendBuckets.MONTH
      ),
      LaneTrendBuckets.keyOf(
        Date.newInstance(2026, 2, 5),
        LaneTrendBuckets.MONTH
      )
    };
    monthKeys.sort();
    System.assertEquals(
      new List<String>{ '2026-02', '2026-10' },
      monthKeys,
      'unpadded, October would sort before February'
    );
  }

  @IsTest
  static void aWeekKeyIsItsMondayWhateverTheRunningUsersLocale() {
    // Apex Date.toStartOfWeek() follows the running user's locale, so Sunday-first users would
    // get a different bucket for the same rate. The anchor arithmetic here does not.
    Date wed = Date.newInstance(2026, 9, 16);
    Date sun = Date.newInstance(2026, 9, 20);
    Date mon = Date.newInstance(2026, 9, 14);
    System.assertEquals(mon, LaneTrendBuckets.startOfWeek(wed));
    System.assertEquals(
      mon,
      LaneTrendBuckets.startOfWeek(sun),
      'Sunday belongs to the week that started the Monday before it'
    );
    System.assertEquals(
      '2026-09-14',
      LaneTrendBuckets.keyOf(sun, LaneTrendBuckets.WEEK)
    );
  }

  @IsTest
  static void countsTheDistanceBetweenTwoDatesInEachUnit() {
    Date from0 = Date.newInstance(2025, 11, 1);
    System.assertEquals(
      2,
      LaneTrendBuckets.between(
        from0,
        Date.newInstance(2026, 1, 1),
        LaneTrendBuckets.MONTH
      ),
      'a lost *12 year term would give -10 here'
    );
    System.assertEquals(
      61,
      LaneTrendBuckets.between(
        from0,
        Date.newInstance(2026, 1, 1),
        LaneTrendBuckets.DAY
      )
    );
    System.assertEquals(
      2,
      LaneTrendBuckets.between(
        Date.newInstance(2026, 9, 14),
        Date.newInstance(2026, 9, 30),
        LaneTrendBuckets.WEEK
      ),
      'Mondays 14th, 21st, 28th: the 30th falls in the third week, index 2'
    );
  }

  @IsTest
  static void theThinThresholdScalesWithTheBucket() {
    System.assertEquals(
      3,
      LaneTrendBuckets.thinCountFor(LaneTrendBuckets.MONTH)
    );
    System.assertEquals(
      2,
      LaneTrendBuckets.thinCountFor(LaneTrendBuckets.WEEK)
    );
    System.assertEquals(
      1,
      LaneTrendBuckets.thinCountFor(LaneTrendBuckets.DAY),
      'W3: a day needs one rate, so no daily bucket is ever thin'
    );
  }
}
