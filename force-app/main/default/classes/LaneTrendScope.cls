/**
 * Phase 10 fix round 4 (Ruling 19): which of the merged samples the chart actually plots, and what
 * that leaves out.
 *
 * Rulings 11 and 14 compose, and getting the order wrong breaks something in either direction -
 * which is why they live together here rather than as two steps trendFor sequences by hand:
 * - drop the out-of-window rows first (what trendFor did) and they are counted across every
 *   currency, so trend.outsideWindow can report rows of a currency the chart never drew. On a mixed
 *   lane whose losing currency happens to be the old one, the caption under the chart described a
 *   different population than the chart - the exact defect Ruling 11 exists to prevent, one field
 *   over;
 * - choose the currency first and a currency can win the majority contest on the strength of rows
 *   that are about to be discarded, leaving the "winning" currency a sparse or empty chart.
 *
 * So: partition by window, choose the currency from the in-window rows - the plottable ones - then
 * count only that currency's out-of-window rows. Both numbers then describe one population: the
 * chart's.
 *
 * Split out of LaneTrendService per this project's standing ruling that a class at PMD's
 * cyclomatic-complexity ceiling is split, not suppressed (the ruling behind LaneSearchFilters,
 * MarketTestFilter, LaneTrendQueries and LaneTrendSummary). No SOQL, no DML, no sharing declaration
 * needed - this class only sorts samples into the ones the chart draws and the ones it does not.
 */
public class LaneTrendScope {
  /**
   * The samples the chart plots: inside the window, in one currency.
   *
   * Records both of the trend's own accounts of what it left out, so they cannot drift apart:
   * trend.currencyIsoCode (the currency it chose, which the component already displays) and
   * trend.outsideWindow (how many rows of that same currency fell outside the window).
   */
  public static List<LaneTrendService.Sample> narrow(
    LaneTrend trend,
    List<LaneTrendService.Sample> samples,
    Date windowStartMonth
  ) {
    List<LaneTrendService.Sample> outOfWindow = new List<LaneTrendService.Sample>();
    List<LaneTrendService.Sample> inWindow = partitionByWindow(
      samples,
      windowStartMonth,
      outOfWindow
    );
    // D6/Ruling 14: req.currencyIsoCode already narrows both queries' own WHERE when it is set, so
    // samplesInCurrency is a no-op filter in that case; when it is blank (both currencies allowed
    // through) the chart picks the one with the most usable in-window samples and says so, rather
    // than merging CAD and USD into one meaningless median.
    if (String.isBlank(trend.currencyIsoCode)) {
      trend.currencyIsoCode = majorityCurrency(inWindow);
    }
    // Ruling 19: scoped to the chosen currency, so the caption and the chart describe one
    // population. When no currency could be chosen there is nothing plottable and therefore no
    // chart, samplesInCurrency then matches everything, and this reports every out-of-window row:
    // a lane whose only rows all fall outside the window must still say so, which is what
    // aSampleOutsideTheWindowIsDroppedAndCounted pins, and with no charted currency there is
    // nothing to scope the count to anyway.
    trend.outsideWindow = samplesInCurrency(outOfWindow, trend.currencyIsoCode)
      .size();
    return samplesInCurrency(inWindow, trend.currencyIsoCode);
  }

  /**
   * Ruling 11: the WHERE clause borrowed from the search (D2) filters on CreatedDate, but each
   * sample is bucketed on a different date - Quote_Date__c or Valid_From__c - so a row can match the
   * search and still fall outside the chart's own window. Separated here rather than clamped onto the
   * axis, so monthSpan keeps meaning exactly the window the pricer picked.
   *
   * Returns the in-window samples and appends the rest to outOfWindow, because Ruling 19 needs both
   * halves: one to plot, the other to count once the currency is known.
   */
  private static List<LaneTrendService.Sample> partitionByWindow(
    List<LaneTrendService.Sample> samples,
    Date windowStartMonth,
    List<LaneTrendService.Sample> outOfWindow
  ) {
    Date today = Date.today();
    List<LaneTrendService.Sample> inWindow = new List<LaneTrendService.Sample>();
    for (LaneTrendService.Sample s : samples) {
      Boolean isOutsideWindow =
        s?.sampleDate != null &&
        (s.sampleDate < windowStartMonth ||
        s.sampleDate > today);
      if (isOutsideWindow) {
        outOfWindow.add(s);
      } else {
        inWindow.add(s);
      }
    }
    return inWindow;
  }

  /**
   * The currency with the most usable samples - the one there is most of to plot. Null when nothing
   * here is usable, which means there is no chart to choose a currency for.
   *
   * Ruling 20: the codes are sorted before the scan, so the strict > below resolves an exact tie to
   * the alphabetically first currency. Without the sort the winner is simply the first key the count
   * map happens to yield: Apex's Map<String, Integer> was observed on this org to iterate in
   * insertion order, which here is the order the rows came back from SOQL, and rows tied on the
   * ORDER BY key have no guaranteed order of their own. So the same lane could render as CAD on one
   * run and USD on the next, off nothing the pricer can see. Which of two equally-sized currencies
   * wins is arbitrary; that the same one wins every time is not, and the chart states the currency
   * it plotted (trend.currencyIsoCode), so a stable arbitrary pick misleads nobody. The sort IS the
   * tie-break - dropping it as redundant puts the instability straight back.
   */
  private static String majorityCurrency(
    List<LaneTrendService.Sample> samples
  ) {
    Map<String, Integer> counts = new Map<String, Integer>();
    for (LaneTrendService.Sample s : samples) {
      if (!LaneTrendSummary.isUsable(s)) {
        continue;
      }
      counts.put(s.currencyIsoCode, (counts.get(s.currencyIsoCode) ?? 0) + 1);
    }
    List<String> codes = new List<String>(counts.keySet());
    codes.sort();
    String best = null;
    Integer bestCount = 0;
    for (String code : codes) {
      Integer count = counts.get(code);
      if (count > bestCount) {
        best = code;
        bestCount = count;
      }
    }
    return best;
  }

  /**
   * "currency" is a reserved Apex identifier (compiler: "Identifier name is reserved: currency"), so
   * the parameter is currencyCode, matching req.currencyIsoCode's own naming.
   *
   * A blank currencyCode matches every sample. That happens only when majorityCurrency found nothing
   * usable in the window, where there is no chart to keep to one currency: every in-window sample
   * left is unusable by definition, so bucket() and summarise() drop all of them anyway, and the
   * out-of-window rows are counted in full deliberately (see narrow()).
   */
  private static List<LaneTrendService.Sample> samplesInCurrency(
    List<LaneTrendService.Sample> samples,
    String currencyCode
  ) {
    List<LaneTrendService.Sample> matching = new List<LaneTrendService.Sample>();
    for (LaneTrendService.Sample s : samples) {
      if (String.isBlank(currencyCode) || currencyCode == s.currencyIsoCode) {
        matching.add(s);
      }
    }
    return matching;
  }
}
