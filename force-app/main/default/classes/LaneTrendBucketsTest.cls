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
  static void pinsTheDayWeekAndWeekMonthBoundariesToTheLongestRealCalendarSpan() {
    // 31 is the longest possible calendar month, so it is the only day/week cutoff under which
    // every real one-month window classifies as DAY. 92 is the longest possible span of three
    // consecutive calendar months, so it is the only week/month cutoff under which every real
    // three-month window classifies as WEEK. See LaneTrendBuckets.unitFor's doc comment.
    System.assertEquals(LaneTrendBuckets.DAY, LaneTrendBuckets.unitFor(31));
    System.assertEquals(LaneTrendBuckets.WEEK, LaneTrendBuckets.unitFor(32));
    System.assertEquals(LaneTrendBuckets.WEEK, LaneTrendBuckets.unitFor(92));
    System.assertEquals(LaneTrendBuckets.MONTH, LaneTrendBuckets.unitFor(93));
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

    List<String> monthKeysAcrossYear = new List<String>{
      LaneTrendBuckets.keyOf(
        Date.newInstance(2026, 1, 5),
        LaneTrendBuckets.MONTH
      ),
      LaneTrendBuckets.keyOf(
        Date.newInstance(2025, 12, 5),
        LaneTrendBuckets.MONTH
      )
    };
    monthKeysAcrossYear.sort();
    System.assertEquals(
      new List<String>{ '2025-12', '2026-01' },
      monthKeysAcrossYear,
      'a year boundary must sort 2025-12 before 2026-01'
    );

    // 2026-01-01 is a Thursday, so its Monday falls in both the previous year and the previous
    // month - one assertion closes the WEEK key's year-boundary and month-boundary gaps at once.
    System.assertEquals(
      '2025-12-29',
      LaneTrendBuckets.keyOf(
        Date.newInstance(2026, 1, 1),
        LaneTrendBuckets.WEEK
      ),
      'a week spanning a year and month boundary must key on its Monday, not the date handed in'
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
      mon,
      LaneTrendBuckets.startOfWeek(mon),
      'a Monday input is already the start of its own week'
    );
    System.assertEquals(
      '2026-09-14',
      LaneTrendBuckets.keyOf(sun, LaneTrendBuckets.WEEK)
    );
  }

  @IsTest
  static void labelOfFormatsShortForEachUnitAndAnchorsTheWeekToMonday() {
    System.assertEquals(
      '16 Sep',
      LaneTrendBuckets.labelOf(
        Date.newInstance(2026, 9, 16),
        LaneTrendBuckets.DAY
      )
    );
    System.assertEquals(
      '14 Sep',
      LaneTrendBuckets.labelOf(
        Date.newInstance(2026, 9, 20),
        LaneTrendBuckets.WEEK
      ),
      'a Sunday passed in must label its Monday, not the date it was handed'
    );
    System.assertEquals(
      'Oct',
      LaneTrendBuckets.labelOf(
        Date.newInstance(2026, 10, 5),
        LaneTrendBuckets.MONTH
      )
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
      1,
      LaneTrendBuckets.between(
        Date.newInstance(2026, 9, 15),
        Date.newInstance(2026, 9, 21),
        LaneTrendBuckets.WEEK
      ),
      'without anchoring both ends to Monday, Tue 15th to Mon 21st gives 6/7 = 0 instead of 1'
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
