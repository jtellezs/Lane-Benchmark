/**
 * Rates come from ExchangeRates.periodsOverride, because DatedConversionRate rows cannot be inserted in
 * tests. One test reads the org's own rates without the override and checks the answer against its own
 * query, so it holds whether or not the org's dated rates are visible to tests. Amounts are compared at
 * scale 6 on both sides, so no assertion depends on a Decimal's scale. No DML here.
 */
@IsTest(IsParallel=true)
private class ExchangeRatesTest {
  private static final Date JAN_05 = Date.newInstance(2026, 1, 5);
  private static final Date JAN_12 = Date.newInstance(2026, 1, 12);
  private static final Date JAN_19 = Date.newInstance(2026, 1, 19);
  private static final Date OPEN_END = Date.newInstance(9999, 12, 31);

  /** Three weekly periods, the last one open-ended like Salesforce's latest dated rate. */
  private static List<ExchangeRates.Period> threeWeeks() {
    return new List<ExchangeRates.Period>{
      new ExchangeRates.Period(JAN_05, JAN_12, 0.70),
      new ExchangeRates.Period(JAN_12, JAN_19, 0.72),
      new ExchangeRates.Period(JAN_19, OPEN_END, 0.74)
    };
  }

  /** Noon in the running user's time zone, so Datetime.date() is the given day. */
  private static Datetime noonOn(
    Integer year,
    Integer month,
    Integer dayOfMonth
  ) {
    return Datetime.newInstance(year, month, dayOfMonth, 12, 0, 0);
  }

  private static void assertAmount(
    Decimal expected,
    Decimal actual,
    String message
  ) {
    System.assertNotEquals(null, actual, message + ': no amount');
    System.assertEquals(expected.setScale(6), actual.setScale(6), message);
  }

  @IsTest
  static void aLoadDayInsideAPeriodUsesThatPeriodsRateUnrounded() {
    ExchangeRates.periodsOverride = threeWeeks();

    Test.startTest();
    ExchangeRates rates = ExchangeRates.usd(Date.newInstance(2025, 12, 1));
    Integer queries = Limits.getQueries();
    Decimal usdAmount = rates.fromCad(1234.56, noonOn(2026, 1, 14));
    Test.stopTest();

    System.assertEquals(0, queries, 'the override is used without a query');
    System.assert(rates.hasRates(), 'three periods are rates');
    assertAmount(
      888.8832,
      usdAmount,
      '1,234.56 CAD on January 14 at 0.72, not rounded to cents'
    );
    System.assertEquals(
      JAN_12,
      rates.latestStartUsed,
      'the period used starts on January 12'
    );
  }

  @IsTest
  static void aNextStartDateBelongsToTheNextPeriod() {
    ExchangeRates.periodsOverride = threeWeeks();

    Test.startTest();
    ExchangeRates rates = ExchangeRates.usd(Date.newInstance(2025, 12, 1));
    Decimal dayBefore = rates.fromCad(1000, noonOn(2026, 1, 11));
    Decimal onTheBoundary = rates.fromCad(1000, noonOn(2026, 1, 12));
    Test.stopTest();

    assertAmount(700, dayBefore, 'January 11 is still in the first period');
    assertAmount(
      720,
      onTheBoundary,
      'January 12, the first period NextStartDate, is in the second period'
    );
    System.assertEquals(
      JAN_12,
      rates.latestStartUsed,
      'the boundary day used the second period'
    );
  }

  @IsTest
  static void aDayOnOrAfterTheLastStartUsesTheLastRate() {
    ExchangeRates.periodsOverride = threeWeeks();

    Test.startTest();
    ExchangeRates rates = ExchangeRates.usd(Date.newInstance(2025, 12, 1));
    Decimal onTheLastStart = rates.fromCad(1000, noonOn(2026, 1, 19));
    Decimal longAfter = rates.fromCad(1000, noonOn(2027, 6, 30));
    Test.stopTest();

    assertAmount(740, onTheLastStart, 'January 19 starts the last period');
    assertAmount(740, longAfter, 'a later day keeps the last rate');
    System.assertEquals(JAN_19, rates.latestStartUsed, 'the last period');
  }

  @IsTest
  static void aDayBeforeTheFirstPeriodUsesTheFirstRateInAnyListOrder() {
    List<ExchangeRates.Period> newestFirst = new List<ExchangeRates.Period>();
    List<ExchangeRates.Period> weeks = threeWeeks();
    for (Integer i = weeks.size() - 1; i >= 0; i--) {
      newestFirst.add(weeks[i]);
    }
    ExchangeRates.periodsOverride = newestFirst;

    Test.startTest();
    ExchangeRates rates = ExchangeRates.usd(Date.newInstance(2025, 12, 1));
    Decimal before = rates.fromCad(1000, noonOn(2025, 12, 20));
    Decimal inside = rates.fromCad(1000, noonOn(2026, 1, 13));
    Test.stopTest();

    assertAmount(700, before, 'December 20 is before the first period');
    assertAmount(720, inside, 'the list order does not change the period');
    System.assertEquals(
      JAN_12,
      rates.latestStartUsed,
      'the latest period used, whatever the list order'
    );
  }

  @IsTest
  static void aMissingAmountOrDateGivesNoAmountAndRecordsNothing() {
    ExchangeRates.periodsOverride = threeWeeks();

    Test.startTest();
    ExchangeRates rates = ExchangeRates.usd(Date.newInstance(2025, 12, 1));
    Decimal noAmount = rates.fromCad(null, noonOn(2026, 1, 14));
    Decimal noDate = rates.fromCad(1000, null);
    Test.stopTest();

    System.assertEquals(null, noAmount, 'a null CAD amount has no USD amount');
    System.assertEquals(null, noDate, 'a missing load date has no USD amount');
    System.assertEquals(
      null,
      rates.latestStartUsed,
      'no conversion happened, so no period was used'
    );
  }

  @IsTest
  static void noPeriodsMeansNoRates() {
    ExchangeRates.periodsOverride = new List<ExchangeRates.Period>();

    Test.startTest();
    ExchangeRates rates = ExchangeRates.usd(Date.newInstance(2025, 12, 1));
    Decimal usdAmount = rates.fromCad(1000, noonOn(2026, 1, 14));
    Test.stopTest();

    System.assert(!rates.hasRates(), 'no period is no rate');
    System.assertEquals(null, usdAmount, 'nothing to convert with');
    System.assertEquals(null, rates.latestStartUsed, 'no period used');
  }

  @IsTest
  static void latestStartUsedIsTheLatestPeriodActuallyUsed() {
    ExchangeRates.periodsOverride = threeWeeks();

    Test.startTest();
    ExchangeRates allThree = ExchangeRates.usd(Date.newInstance(2025, 12, 1));
    allThree.fromCad(100, noonOn(2026, 1, 20));
    allThree.fromCad(100, noonOn(2026, 1, 6));
    allThree.fromCad(100, noonOn(2026, 1, 13));
    ExchangeRates firstTwo = ExchangeRates.usd(Date.newInstance(2025, 12, 1));
    firstTwo.fromCad(100, noonOn(2026, 1, 6));
    firstTwo.fromCad(100, noonOn(2026, 1, 13));
    firstTwo.fromCad(null, noonOn(2026, 1, 25));
    Test.stopTest();

    System.assertEquals(
      JAN_19,
      allThree.latestStartUsed,
      'an earlier period used later does not move it back'
    );
    System.assertEquals(
      JAN_12,
      firstTwo.latestStartUsed,
      'a later period that no amount used does not count'
    );
  }

  @IsTest
  static void theOrgReadIsOneQueryAndAgreesWithTheOrgsRates() {
    ExchangeRates.periodsOverride = null;
    Date fromDate = Date.today().addDays(-400);
    Date todayDate = Date.today();
    Integer periodCount = [
      SELECT COUNT()
      FROM DatedConversionRate
      WHERE IsoCode = 'USD' AND NextStartDate > :fromDate
    ];
    List<DatedConversionRate> current = [
      SELECT ConversionRate, StartDate
      FROM DatedConversionRate
      WHERE
        IsoCode = 'USD'
        AND StartDate <= :todayDate
        AND NextStartDate > :todayDate
      LIMIT 1
    ];

    Test.startTest();
    ExchangeRates rates = ExchangeRates.usd(fromDate);
    Integer queries = Limits.getQueries();
    Decimal usdAmount = rates.fromCad(1000, System.now());
    Test.stopTest();

    System.assertEquals(1, queries, 'usd() reads the periods in one query');
    System.assertEquals(
      periodCount > 0,
      rates.hasRates(),
      'hasRates() says whether USD periods end after the read date'
    );
    if (current.isEmpty()) {
      System.assertEquals(
        null,
        usdAmount,
        'no USD period is visible, so there is no USD amount'
      );
    } else {
      assertAmount(
        1000 * current[0].ConversionRate,
        usdAmount,
        'today converts at the rate of the period holding today'
      );
      System.assertEquals(
        current[0].StartDate,
        rates.latestStartUsed,
        'and records that period start'
      );
    }
  }
}
