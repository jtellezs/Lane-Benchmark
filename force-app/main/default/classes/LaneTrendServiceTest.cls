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
      Date.newInstance(2026, 1, 1),
      3
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
      Date.newInstance(2026, 1, 1),
      2
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
      Date.newInstance(2026, 1, 1),
      1
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
      Date.newInstance(2026, 1, 1),
      6
    );
    Test.stopTest();
    System.assertEquals(0, points.size());
  }
}
