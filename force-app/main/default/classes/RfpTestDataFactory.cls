/**
 * Test builders for the phase 3 RFP objects. Places mirror LaneSearchServiceTest.place();
 * projects/lanes/bids carry the minimum the services and Lane Benchmark need.
 */
@IsTest
public class RfpTestDataFactory {
  public static Pricing_Place__c createPlace(
    String city,
    String prov,
    String country,
    Decimal lat,
    Decimal lng,
    String prefix
  ) {
    Pricing_Place__c p = new Pricing_Place__c(
      Name = city + ', ' + prov,
      Key__c = PlaceNormalizer.key(city, prov, country),
      City__c = city,
      Province__c = prov,
      Country__c = country,
      Geolocation__Latitude__s = lat,
      Geolocation__Longitude__s = lng,
      Postal_Prefix__c = prefix,
      Active__c = true,
      Source__c = 'Locations'
    );
    insert p;
    return p;
  }

  public static RFP_Project__c createProject(Account customer) {
    RFP_Project__c p = new RFP_Project__c(
      Name = 'Test RFP',
      Customer__c = customer.Id,
      Status__c = 'Draft',
      Default_Margin__c = 15,
      CurrencyIsoCode = 'CAD'
    );
    insert p;
    return p;
  }

  public static RFP_Lane__c createLane(
    RFP_Project__c project,
    Pricing_Place__c origin,
    Pricing_Place__c destination
  ) {
    RFP_Lane__c lane = new RFP_Lane__c(
      RFP_Project__c = project.Id,
      Row_Number__c = 1,
      Origin_City__c = origin.City__c,
      Origin_Province__c = origin.Province__c,
      Origin_Country__c = origin.Country__c,
      Origin_Postal__c = origin.Postal_Prefix__c,
      Origin_Place__c = origin.Id,
      Origin_Resolved__c = true,
      Destination_City__c = destination.City__c,
      Destination_Province__c = destination.Province__c,
      Destination_Country__c = destination.Country__c,
      Destination_Postal__c = destination.Postal_Prefix__c,
      Destination_Place__c = destination.Id,
      Destination_Resolved__c = true,
      Mode__c = 'Truckload',
      Equipment_Category__c = 'Van',
      Equipment_Type__c = 'Dry Van 53\'',
      Margin__c = 15,
      Hist_Status__c = 'Pending',
      CurrencyIsoCode = 'CAD'
    );
    insert lane;
    return lane;
  }

  public static Benchmark_Rate__c buildBid(RFP_Lane__c lane, Decimal rate) {
    return new Benchmark_Rate__c(
      RFP_Lane__c = lane.Id,
      Carrier_Name__c = 'Bid Carrier',
      Contact_Name__c = 'Bid Contact',
      Contact_Email__c = 'bid@example.invalid',
      Rate__c = rate,
      CurrencyIsoCode = 'CAD',
      Valid_From__c = Date.today(),
      Expires_On__c = Date.today().addDays(30)
    );
  }
}
