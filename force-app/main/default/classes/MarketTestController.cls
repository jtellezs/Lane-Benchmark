/**
 * Phase 9: the Market Test page's only Apex surface. Thin, like RfpBidController: it reads the
 * posted JSON, delegates to MarketTestService and turns an exception into one sentence a pricer
 * can act on. Nothing here is cacheable - the page mutates this list, so it reads it imperatively
 * after every save, update and delete rather than working around a stale client cache.
 */
public with sharing class MarketTestController {
  @AuraEnabled
  public static List<Benchmark_Rate__c> getRates(
    Id originPlaceId,
    Id destinationPlaceId
  ) {
    try {
      return MarketTestService.ratesOfLane(originPlaceId, destinationPlaceId);
    } catch (LaneSearchException e) {
      throw RfpUserError.of(e.getMessage());
    } catch (Exception e) {
      throw RfpUserError.of('The rates for this lane could not be loaded.');
    }
  }

  @AuraEnabled
  public static Benchmark_Rate__c saveRate(
    String rateJson,
    Id originPlaceId,
    Id destinationPlaceId
  ) {
    try {
      return MarketTestService.save(
        (Benchmark_Rate__c) JSON.deserialize(rateJson, Benchmark_Rate__c.class),
        originPlaceId,
        destinationPlaceId
      );
    } catch (LaneSearchException e) {
      throw RfpUserError.of(e.getMessage());
    } catch (JSONException e) {
      throw RfpUserError.of('The rate could not be read. Please try again.');
    } catch (Exception e) {
      throw RfpUserError.of('The rate could not be saved.');
    }
  }

  @AuraEnabled
  public static Benchmark_Rate__c updateRate(String rateJson) {
    try {
      return MarketTestService.updateRate(
        (Benchmark_Rate__c) JSON.deserialize(rateJson, Benchmark_Rate__c.class)
      );
    } catch (LaneSearchException e) {
      throw RfpUserError.of(e.getMessage());
    } catch (JSONException e) {
      throw RfpUserError.of('The rate could not be read. Please try again.');
    } catch (Exception e) {
      throw RfpUserError.of('The rate could not be saved.');
    }
  }

  @AuraEnabled
  public static void deleteRate(Id rateId) {
    try {
      MarketTestService.deleteRate(rateId);
    } catch (LaneSearchException e) {
      throw RfpUserError.of(e.getMessage());
    } catch (Exception e) {
      throw RfpUserError.of('The rate could not be deleted.');
    }
  }
}
