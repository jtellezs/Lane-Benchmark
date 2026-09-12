/** @AuraEnabled wrappers over RfpBulkService: user errors out, RfpBulkService.Result back. */
public with sharing class RfpBulkController {
  @AuraEnabled
  public static RfpBulkService.Result applyMedian(
    List<Id> laneIds,
    Boolean overwrite
  ) {
    try {
      return RfpBulkService.applyMedian(laneIds, overwrite);
    } catch (LaneSearchException e) {
      throw RfpUserError.of(e.getMessage());
    } catch (Exception e) {
      throw RfpUserError.of(
        'The medians could not be applied. ' + RfpUserError.safe(e)
      );
    }
  }

  @AuraEnabled
  public static RfpBulkService.Result applyPricing(
    List<Id> laneIds,
    Decimal cost,
    Decimal sell,
    Decimal margin
  ) {
    try {
      return RfpBulkService.applyPricing(laneIds, cost, sell, margin);
    } catch (LaneSearchException e) {
      throw RfpUserError.of(e.getMessage());
    } catch (Exception e) {
      throw RfpUserError.of(
        'The pricing could not be applied. ' + RfpUserError.safe(e)
      );
    }
  }

  @AuraEnabled
  public static RfpBulkService.Result applyBid(
    List<Id> laneIds,
    String bidJson
  ) {
    try {
      return RfpBulkService.applyBid(laneIds, bidJson);
    } catch (LaneSearchException e) {
      throw RfpUserError.of(e.getMessage());
    } catch (Exception e) {
      throw RfpUserError.of(
        'The carrier rate could not be added. ' + RfpUserError.safe(e)
      );
    }
  }

  @AuraEnabled
  public static RfpBulkService.Result copyPricing(
    Id sourceLaneId,
    List<Id> laneIds
  ) {
    try {
      return RfpBulkService.copyPricing(sourceLaneId, laneIds);
    } catch (LaneSearchException e) {
      throw RfpUserError.of(e.getMessage());
    } catch (Exception e) {
      throw RfpUserError.of(
        'The pricing could not be copied. ' + RfpUserError.safe(e)
      );
    }
  }

  @AuraEnabled
  public static RfpBulkService.Result deleteLanes(List<Id> laneIds) {
    try {
      return RfpBulkService.deleteLanes(laneIds);
    } catch (LaneSearchException e) {
      throw RfpUserError.of(e.getMessage());
    } catch (Exception e) {
      throw RfpUserError.of(
        'The lanes could not be deleted. ' + RfpUserError.safe(e)
      );
    }
  }
}
