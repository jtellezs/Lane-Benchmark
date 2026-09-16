/**
 * Carriers to ask (phase 8, spec §6): the Lane Benchmark page and the RFP lane panel call this when
 * their first search found no carrier rate in the pricing currency. Thin, like
 * LaneBenchmarkController.search: it reads the request JSON and translates errors;
 * CarrierLeadService reads the place keys, precisions, postal prefixes and the mode, equipment and
 * hazmat filters, and does the work in system mode. No readable-project check, because no bid is
 * read. attempt is 0 on the first call and grows with each Retry, so a Retry is not answered from
 * the browser's cache of this cacheable method; the server ignores it (R91).
 */
public with sharing class CarrierLeadController {
  @TestVisible
  private static final String UNREADABLE_REQUEST = 'The search request could not be read. Please reset the filters and try again.';

  @AuraEnabled(cacheable=true)
  public static CarrierLeadResult findCarrierLeads(
    String requestJson,
    Integer attempt
  ) {
    LaneSearchRequest req;
    try {
      req = (LaneSearchRequest) JSON.deserialize(
        requestJson,
        LaneSearchRequest.class
      );
    } catch (Exception e) {
      throw userError(UNREADABLE_REQUEST);
    }
    if (req == null) {
      throw userError(UNREADABLE_REQUEST);
    }
    try {
      return CarrierLeadService.find(req);
    } catch (LaneSearchException e) {
      throw userError(e.getMessage());
    } catch (QueryException e) {
      throw userError('Carriers to ask could not be read in time. Try again.');
    }
  }

  private static AuraHandledException userError(String message) {
    AuraHandledException e = new AuraHandledException(message);
    e.setMessage(message);
    return e;
  }
}
