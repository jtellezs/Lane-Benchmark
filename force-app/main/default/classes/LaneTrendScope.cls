/**
 * Phase 10 (Ruling 14, revised by the spec's 2026-09-19 amendment): which of the merged samples the
 * chart actually plots.
 *
 * Today that means one thing - one currency, chosen rather than blended - and it says so on the
 * trend, because a median over CAD and USD together describes no market at all (D6).
 *
 * This class also used to partition the samples by window and count what fell outside, and that
 * machinery was removed when the trend moved to bucketing both sources on CreatedDate. The partition
 * existed because the WHERE filtered CreatedDate while the chart bucketed on Quote_Date__c /
 * Valid_From__c, so a row could match the search and still land off the axis. With one field doing
 * both jobs, no read row can: LAST_N_DAYS admits CreatedDate from the window start onward, the axis
 * starts on the first of that month, and CreatedDate cannot be in the future. The partition was
 * therefore provably unreachable - and it was not a safety net, it was the defect. What it did in
 * production was silently delete every quote on freight that had not shipped yet, 7.0% of PostProduc
 * over 30 days and concentrated in the current month, and report the deletion through a counter no
 * one reads as a warning. Keeping it "in case the bucketing field changes again" would have kept
 * exactly that behaviour armed for the next change, and kept a page telling pricers "0 rates fall
 * outside this window" on a sentence that could never say anything else.
 *
 * What replaces it is a test that fails loudly instead of a guard that hides quietly:
 * LaneTrendServiceTest.aRowTheSearchMatchedIsAlwaysPlacedOnTheAxis asserts the axis position of a
 * row whose Valid_From__c is 400 days old, so bucketing on anything other than the filtered field
 * puts that point off the frame and goes red.
 *
 * Kept as its own class rather than folded back into LaneTrendService, which sits at 39 of PMD's
 * 40-point cyclomatic-complexity cap - the project's standing ruling is that a class at the ceiling
 * is split, not suppressed (the ruling behind LaneSearchFilters, MarketTestFilter, LaneTrendQueries
 * and LaneTrendSummary). No SOQL, no DML, no sharing declaration needed.
 */
public class LaneTrendScope {
  /**
   * The samples the chart plots: the ones in the currency it plots.
   *
   * Records the choice on trend.currencyIsoCode - the currency the component already displays - so
   * the caption and the chart can never describe two different populations.
   */
  public static List<LaneTrendService.Sample> narrow(
    LaneTrend trend,
    List<LaneTrendService.Sample> samples
  ) {
    // D6/Ruling 14: req.currencyIsoCode already narrows both queries' own WHERE when it is set, so
    // samplesInCurrency is a no-op filter in that case; when it is blank (both currencies allowed
    // through) the chart picks the one with the most usable samples and says so, rather than
    // merging CAD and USD into one meaningless median.
    if (String.isBlank(trend.currencyIsoCode)) {
      trend.currencyIsoCode = majorityCurrency(samples);
    }
    return samplesInCurrency(samples, trend.currencyIsoCode);
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
   * usable, where there is no chart to keep to one currency: every sample left is unusable by
   * definition, so bucket() and summarise() drop all of them anyway.
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
