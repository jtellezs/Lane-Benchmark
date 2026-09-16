/**
 * USD dated exchange rates for split-lane amounts (phase 8, spec D7 and R109). Revenova stores leg costs
 * in CAD, the corporate currency; a USD DatedConversionRate row gives the USD that one CAD buys from its
 * StartDate until the day before its NextStartDate, so a USD amount is the CAD amount times the rate of
 * the period holding the load's day (a NextStartDate belongs to the next period). A day on or after the
 * last period's start uses the last rate; a day before the first period uses the first. usd() reads the
 * periods in one query; tests set periodsOverride because dated rates cannot be inserted in tests.
 */
public with sharing class ExchangeRates {
  // Test hook: tests set the periods because DatedConversionRate rows cannot be inserted in tests.
  @TestVisible
  private static List<Period> periodsOverride;

  private final List<Period> periods;
  // One lookup per distinct load day: a split read converts up to thousands of legs over about 365 days.
  private final Map<Date, Period> periodByDay = new Map<Date, Period>();

  /** The start date of the latest period any conversion used; null before the first conversion. */
  public Date latestStartUsed { get; private set; }

  public class Period {
    public Date startDate;
    public Date nextStartDate;
    public Decimal rate;

    public Period(Date startDate, Date nextStartDate, Decimal rate) {
      this.startDate = startDate;
      this.nextStartDate = nextStartDate;
      this.rate = rate;
    }
  }

  private ExchangeRates(List<Period> periods) {
    this.periods = periods == null ? new List<Period>() : periods;
  }

  /**
   * The USD periods that end after fromDate, oldest first. One query, unless periodsOverride is set.
   * System mode on purpose: exchange rates are org-wide reference data every pricer's amounts depend
   * on, not a user's record, and a restricted pricer must convert like everyone else.
   */
  public static ExchangeRates usd(Date fromDate) {
    if (periodsOverride != null) {
      return new ExchangeRates(new List<Period>(periodsOverride));
    }
    List<Period> periods = new List<Period>();
    for (DatedConversionRate row : [
      SELECT IsoCode, ConversionRate, StartDate, NextStartDate
      FROM DatedConversionRate
      WHERE IsoCode = 'USD' AND NextStartDate > :fromDate
      WITH SYSTEM_MODE
      ORDER BY StartDate
    ]) {
      periods.add(
        new Period(row.StartDate, row.NextStartDate, row.ConversionRate)
      );
    }
    return new ExchangeRates(periods);
  }

  public Boolean hasRates() {
    return !periods.isEmpty();
  }

  /**
   * cadAmount in USD at the rate of the period holding loadCreated's day (in the running user's time
   * zone), unrounded; null when cadAmount or loadCreated is null or there is no period. Each conversion
   * moves latestStartUsed forward when it used a later period.
   */
  public Decimal fromCad(Decimal cadAmount, Datetime loadCreated) {
    if (cadAmount == null || loadCreated == null || periods.isEmpty()) {
      return null;
    }
    Period used = periodFor(loadCreated.date());
    if (latestStartUsed == null || used.startDate > latestStartUsed) {
      latestStartUsed = used.startDate;
    }
    return cadAmount * used.rate;
  }

  /** The period with the latest start on or before day, else the earliest period; the list order does not matter. */
  private Period periodFor(Date day) {
    Period cached = periodByDay.get(day);
    if (cached != null) {
      return cached;
    }
    Period earliest;
    Period latestStarted;
    for (Period candidate : periods) {
      if (earliest == null || candidate.startDate < earliest.startDate) {
        earliest = candidate;
      }
      if (
        candidate.startDate <= day &&
        (latestStarted == null ||
        candidate.startDate > latestStarted.startDate)
      ) {
        latestStarted = candidate;
      }
    }
    Period chosen = latestStarted == null ? earliest : latestStarted;
    periodByDay.put(day, chosen);
    return chosen;
  }
}
