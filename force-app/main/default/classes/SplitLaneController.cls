/**
 * Aura/LWC entry point for the Split-lane options card (phase 8, spec §4 and §6). Thin: it refuses a
 * currency other than CAD or USD, reads the request JSON and turns search errors into short user
 * messages the way LaneBenchmarkController.search does; SplitLaneService does the work. attempt is
 * 0 on the first call and grows with each Retry, so a retry reaches the server past the cacheable
 * answer; the server ignores it. No readable-project check: no bid is read.
 */
public with sharing class SplitLaneController {
  @TestVisible
  private static final String CURRENCY_REFUSED = 'Choose CAD or USD.';
  @TestVisible
  private static final String UNREADABLE = 'The search request could not be read. Please reset the filters and try again.';

  @AuraEnabled(cacheable=true)
  public static SplitLaneResult splitOptions(
    String requestJson,
    String currencyCode,
    Integer attempt
  ) {
    requireCurrency(currencyCode);
    LaneSearchRequest req = readRequest(requestJson);
    try {
      return SplitLaneService.options(req, currencyCode);
    } catch (LaneSearchException e) {
      throw userError(e.getMessage());
    } catch (QueryException e) {
      throw userError(
        'The search took too long or returned too much data. Narrow the lookback or the radius and try again. (' +
          e.getMessage() +
          ')'
      );
    }
  }

  /** equals, not ==: Apex compares strings without case, and the card sends exactly CAD or USD. */
  private static void requireCurrency(String currencyCode) {
    if (!'CAD'.equals(currencyCode) && !'USD'.equals(currencyCode)) {
      throw userError(CURRENCY_REFUSED);
    }
  }

  private static LaneSearchRequest readRequest(String requestJson) {
    LaneSearchRequest req;
    try {
      req = (LaneSearchRequest) JSON.deserialize(
        requestJson,
        LaneSearchRequest.class
      );
    } catch (Exception e) {
      throw userError(UNREADABLE);
    }
    if (req == null) {
      throw userError(UNREADABLE);
    }
    return req;
  }

  private static AuraHandledException userError(String message) {
    AuraHandledException e = new AuraHandledException(message);
    e.setMessage(message);
    return e;
  }
}
