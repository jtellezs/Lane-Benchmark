/**
 * Phase 10: the lane trend's only Apex surface.
 *
 * cacheable=true (spec §4) because a trend over closed months does not change minute to minute,
 * and because the request JSON is the cache key: flipping the market-test filter produces a
 * different key and therefore a redraw rather than the previous answer (D7).
 */
// without sharing, like LaneBenchmarkController and LaneTrendService: this is the same page's
// second entry point, gated by the same Lane Benchmark permission sets, not by record sharing.
public without sharing class LaneTrendController {
  @AuraEnabled(cacheable=true)
  public static LaneTrend getTrend(String requestJson) {
    LaneSearchRequest req;
    try {
      req = (LaneSearchRequest) JSON.deserialize(
        requestJson,
        LaneSearchRequest.class
      );
    } catch (Exception e) {
      throw userError(
        'The trend could not be read. Please reset the filters and try again.'
      );
    }
    try {
      req.excludeProjectId = LaneBenchmarkController.readableProject(
        req.excludeProjectId
      );
      return LaneTrendService.trendFor(req);
    } catch (LaneSearchException e) {
      throw userError(e.getMessage());
    } catch (QueryException e) {
      // The same arm LaneBenchmarkController.search carries, and needed more here than there: this
      // runs the search's own WHERE - RADIUS DISTANCE() predicates included - over as much as 1095
      // days where a search runs 90, so the platform is strictly likelier to refuse it. D3's row
      // guard is no substitute, because the guard is a COUNT() and the count is the first query
      // trendFor runs: the throw comes out of the guard itself. Without this the component renders
      // e.body.message straight into its error line, so a pricer reads a raw platform string on a
      // page whose search has just worked. "Window" rather than "lookback" because the window is
      // what the chart's own control is called.
      throw userError(
        'The trend took too long or returned too much data. Narrow the window or the radius and try again. (' +
          e.getMessage() +
          ')'
      );
    }
  }

  private static AuraHandledException userError(String message) {
    AuraHandledException e = new AuraHandledException(message);
    e.setMessage(message);
    return e;
  }
}
