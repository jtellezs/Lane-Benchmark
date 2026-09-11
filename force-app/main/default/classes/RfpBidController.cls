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
      throw RfpUserError.of(e.getDmlMessage(0));
    } catch (Exception e) {
      throw RfpUserError.of('The bid could not be saved.');
    }
  }

  @AuraEnabled
  public static List<Benchmark_Rate__c> getBids(Id laneId) {
    try {
      return [
        SELECT
          Id,
          Name,
          Carrier__c,
          Carrier_Display__c,
          Contact_Name__c,
          Contact_Email__c,
          Contact_Phone__c,
          Rate__c,
          CurrencyIsoCode,
          Fuel_Surcharge__c,
          FSC_Included__c,
          Transit_Days__c,
          Valid_From__c,
          Expires_On__c,
          Status__c,
          Notes__c
        FROM Benchmark_Rate__c
        WHERE RFP_Lane__c = :laneId
        WITH USER_MODE
        ORDER BY Rate__c
      ];
    } catch (Exception e) {
      throw RfpUserError.of('The bids could not be loaded.');
    }
  }
}
