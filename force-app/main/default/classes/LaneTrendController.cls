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
    }
  }

  private static AuraHandledException userError(String message) {
    AuraHandledException e = new AuraHandledException(message);
    e.setMessage(message);
    return e;
  }
}
