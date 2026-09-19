/**
 * Phase 10. The bucketing is the part that can lie: a month whose median is wrong, or a month
 * invented where there were no rates, produces a chart a pricer will quote from.
 */
@IsTest
private class LaneTrendServiceTest {
  private static LaneTrendService.Sample s(String isoDate, Decimal amount) {
    return new LaneTrendService.Sample(Date.valueOf(isoDate), amount);
  }

  @IsTest
  static void bucketsByCalendarMonthAndComputesMedianMinMax() {
    List<LaneTrendService.Sample> samples = new List<LaneTrendService.Sample>{
      s('2026-01-05', 1000),
      s('2026-01-20', 2000),
      s('2026-01-28', 3000),
      s('2026-03-02', 500),
      s('2026-03-09', 700),
      s('2026-03-30', 900)
    };

    Test.startTest();
    List<LaneTrend.Point> points = LaneTrendService.bucket(
      samples,
      Date.newInstance(2026, 1, 1)
    );
    Test.stopTest();

    System.assertEquals(
      2,
      points.size(),
      'February had no rates, so it is a gap and not a zero'
    );
    LaneTrend.Point jan = points[0];
    System.assertEquals('2026-01', jan.monthKey);
    System.assertEquals(0, jan.monthIndex);
    System.assertEquals(3, jan.count);
    System.assert(jan.median == 2000, 'January median: ' + jan.median);
    System.assert(jan.minimum == 1000, 'January minimum: ' + jan.minimum);
    System.assert(jan.maximum == 3000, 'January maximum: ' + jan.maximum);
    System.assertEquals(false, jan.thin, 'three rates is not thin');

    LaneTrend.Point mar = points[1];
    System.assertEquals('2026-03', mar.monthKey);
    System.assertEquals(
      2,
      mar.monthIndex,
      'March sits two months after the window start, so the gap is visible on the axis'
    );
    System.assert(mar.median == 700, 'March median: ' + mar.median);
  }

  @IsTest
  static void marksAMonthThinBelowThreeRates() {
    List<LaneTrendService.Sample> samples = new List<LaneTrendService.Sample>{
      s('2026-01-05', 1000),
      s('2026-01-06', 1200),
      s('2026-02-05', 9999)
    };

    Test.startTest();
    List<LaneTrend.Point> points = LaneTrendService.bucket(
      samples,
      Date.newInstance(2026, 1, 1)
    );
    Test.stopTest();

    System.assertEquals(true, points[0].thin, 'two rates do not make a market');
    System.assertEquals(true, points[1].thin, 'nor does one');
  }

  @IsTest
  static void ignoresSamplesWithNoDateOrNoAmount() {
    List<LaneTrendService.Sample> samples = new List<LaneTrendService.Sample>{
      s('2026-01-05', 1000),
      new LaneTrendService.Sample(null, 5000),
      new LaneTrendService.Sample(Date.newInstance(2026, 1, 9), null)
    };

    Test.startTest();
    List<LaneTrend.Point> points = LaneTrendService.bucket(
      samples,
      Date.newInstance(2026, 1, 1)
    );
    Test.stopTest();

    System.assertEquals(1, points.size());
    System.assertEquals(
      1,
      points[0].count,
      'a rate with no date cannot be placed on a time axis, and one with no amount is not a rate'
    );
  }

  @IsTest
  static void anEmptyListProducesNoPointsRatherThanThrowing() {
    Test.startTest();
    List<LaneTrend.Point> points = LaneTrendService.bucket(
      new List<LaneTrendService.Sample>(),
      Date.newInstance(2026, 1, 1)
    );
    Test.stopTest();
    System.assertEquals(0, points.size());
  }

  @IsTest
  static void bucketsAcrossACalendarYearBoundary() {
    List<LaneTrendService.Sample> samples = new List<LaneTrendService.Sample>{
      s('2025-11-03', 1000),
      s('2025-11-10', 1100),
      s('2025-11-20', 1200),
      s('2025-12-01', 2000),
      s('2025-12-15', 2100),
      s('2025-12-28', 2200),
      s('2026-01-02', 3000),
      s('2026-01-15', 3100),
      s('2026-01-30', 3200)
    };

    Test.startTest();
    List<LaneTrend.Point> points = LaneTrendService.bucket(
      samples,
      Date.newInstance(2025, 11, 1)
    );
    Test.stopTest();

    System.assertEquals(
      3,
      points.size(),
      'three months, none thin, none skipped across the year boundary'
    );

    System.assertEquals(
      '2025-11',
      points[0].monthKey,
      'chronological order across the year boundary'
    );
    System.assertEquals(0, points[0].monthIndex, 'the window start month');
    System.assertEquals(
      '2025-12',
      points[1].monthKey,
      'chronological order across the year boundary'
    );
    System.assertEquals(
      1,
      points[1].monthIndex,
      'a lost *12 year term in monthsBetween would miscount once the window crosses a year'
    );
    System.assertEquals(
      '2026-01',
      points[2].monthKey,
      'chronological order across the year boundary'
    );
    System.assertEquals(
      2,
      points[2].monthIndex,
      'two months after the window start, crossing the year: a lost *12 year term would give -10'
    );
  }

  /**
   * monthKeyOf pads single-digit months so keys sort correctly as strings. Unpadded, '2026-10'
   * (October) would sort before '2026-2' (February) because the character comparison never
   * reaches the month digits: '1' < '2' at the position where they first differ. Crossing a year
   * boundary does not exercise this - the year digit differs first there - so this needs two
   * months in the same year, one single-digit and one double-digit.
   */
  @IsTest
  static void sortsASingleDigitMonthBeforeADoubleDigitOneInTheSameYear() {
    List<LaneTrendService.Sample> samples = new List<LaneTrendService.Sample>{
      s('2026-02-03', 1000),
      s('2026-02-10', 1100),
      s('2026-02-20', 1200),
      s('2026-10-01', 2000),
      s('2026-10-15', 2100),
      s('2026-10-28', 2200)
    };

    Test.startTest();
    List<LaneTrend.Point> points = LaneTrendService.bucket(
      samples,
      Date.newInstance(2026, 2, 1)
    );
    Test.stopTest();

    System.assertEquals(2, points.size());
    System.assertEquals(
      '2026-02',
      points[0].monthKey,
      'unpadded, "2026-10" would sort before "2026-2" and put October first'
    );
    System.assertEquals(0, points[0].monthIndex);
    System.assertEquals('2026-10', points[1].monthKey);
    System.assertEquals(8, points[1].monthIndex);
  }
}
