public with sharing class RfpBidController {
  @AuraEnabled
  public static Benchmark_Rate__c saveBid(String bidJson) {
    try {
      return BenchmarkRateService.save(
        (Benchmark_Rate__c) JSON.deserialize(bidJson, Benchmark_Rate__c.class)
      );
    } catch (LaneSearchException e) {
      throw RfpUserError.of(e.getMessage());
    } catch (DmlException e) {
      throw RfpUserError.of(dmlMessage(e));
    } catch (Exception e) {
      throw RfpUserError.of('The bid could not be saved.');
    }
  }

  /**
   * A DmlException with no per-row entry (getNumDml() == 0) makes getDmlMessage(0) throw, so the
   * exception's own message is used there; either way the text is cut to 160 characters, the
   * same width RfpUserError.safe keeps, rather than pushing a full platform dump at the user.
   */
  private static String dmlMessage(DmlException e) {
    String message = e.getNumDml() > 0 ? e.getDmlMessage(0) : e.getMessage();
    return String.isBlank(message)
      ? 'The bid could not be saved.'
      : message.left(160);
  }

  @AuraEnabled
  public static List<Benchmark_Rate__c> getBids(Id laneId) {
    try {
      RfpBidAccess.assertLaneVisible(laneId);
      return RfpBidAccess.bidsOfLanes(new Set<Id>{ laneId });
    } catch (LaneSearchException e) {
      throw RfpUserError.of(e.getMessage());
    } catch (Exception e) {
      throw RfpUserError.of('The bids could not be loaded.');
    }
  }
}
