/** History-side @AuraEnabled entry point of the RFP workbench: runs a history snapshot chunk. */
public with sharing class RfpHistoryController {
  @AuraEnabled
  public static List<RFP_Lane__c> loadHistory(
    List<Id> laneIds,
    String precision,
    Integer lookbackDays,
    Decimal radius,
    String radiusUnit,
    Boolean includeBids
  ) {
    try {
      return RfpHistoryService.run(
        laneIds,
        precision,
        lookbackDays,
        radius,
        radiusUnit,
        includeBids
      );
    } catch (LaneSearchException e) {
      throw RfpUserError.of(e.getMessage());
    } catch (Exception e) {
      throw RfpUserError.of('History could not be loaded for this chunk.');
    }
  }
}
