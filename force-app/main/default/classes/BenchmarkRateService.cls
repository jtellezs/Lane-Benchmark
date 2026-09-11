/**
 * Saves carrier bids (Benchmark_Rate__c) in user mode and stamps the lane keys Lane Benchmark
 * searches on. The keys come from the lane's resolved Pricing_Place__c records (canonical City__c,
 * Province__c, Postal_Prefix__c and coordinates), never from spreadsheet text, so a CITY-precision
 * search matches a bid through PlaceNormalizer.cityLaneVariants exactly as it matches a Load.
 */
public with sharing class BenchmarkRateService {
  public static Benchmark_Rate__c save(Benchmark_Rate__c bid) {
    if (bid.Rate__c == null) {
      throw new LaneSearchException('A bid needs a rate.');
    }
    if (bid.RFP_Lane__c != null) {
      applyLane(bid, loadLane(bid.RFP_Lane__c));
    }
    bid.Valid_From__c = bid.Valid_From__c ?? Date.today();
    bid.Expires_On__c = bid.Expires_On__c ?? Date.today().addDays(30);
    if (bid.Id == null) {
      Database.insert(bid, AccessLevel.USER_MODE);
    } else {
      Database.update(bid, AccessLevel.USER_MODE);
    }
    return reload(bid.Id);
  }

  private static RFP_Lane__c loadLane(Id laneId) {
    List<RFP_Lane__c> lanes = [
      SELECT
        Id,
        RFP_Project__c,
        Mode__c,
        Equipment_Category__c,
        Equipment_Type__c,
        Hazmat__c,
        Origin_City__c,
        Origin_Province__c,
        Origin_Country__c,
        Origin_Postal__c,
        Origin_Place__c,
        Origin_Place__r.City__c,
        Origin_Place__r.Province__c,
        Origin_Place__r.Postal_Prefix__c,
        Origin_Place__r.Geolocation__Latitude__s,
        Origin_Place__r.Geolocation__Longitude__s,
        Destination_City__c,
        Destination_Province__c,
        Destination_Country__c,
        Destination_Postal__c,
        Destination_Place__c,
        Destination_Place__r.City__c,
        Destination_Place__r.Province__c,
        Destination_Place__r.Postal_Prefix__c,
        Destination_Place__r.Geolocation__Latitude__s,
        Destination_Place__r.Geolocation__Longitude__s
      FROM RFP_Lane__c
      WHERE Id = :laneId
      WITH USER_MODE
    ];
    if (lanes.isEmpty()) {
      throw new LaneSearchException(
        'The RFP lane for this bid no longer exists.'
      );
    }
    return lanes[0];
  }

  private static void applyLane(Benchmark_Rate__c bid, RFP_Lane__c lane) {
    bid.RFP_Project__c = lane.RFP_Project__c;
    bid.Mode__c = lane.Mode__c;
    bid.Equipment_Category__c = lane.Equipment_Category__c;
    bid.Equipment_Type__c = lane.Equipment_Type__c;
    bid.Hazmat__c = lane.Hazmat__c;
    applyOrigin(bid, lane);
    applyDestination(bid, lane);
    Pricing_Place__c o = lane.Origin_Place__r;
    Pricing_Place__c d = lane.Destination_Place__r;
    if (o != null && d != null) {
      bid.City_Lane__c = cityLane(o, d);
      bid.State_Lane__c = stateLane(o, d);
      bid.Zip3_Lane__c = zip3Lane(o, d);
    }
  }

  private static void applyOrigin(Benchmark_Rate__c bid, RFP_Lane__c lane) {
    bid.Origin_City__c = lane.Origin_City__c;
    bid.Origin_Province__c = lane.Origin_Province__c;
    bid.Origin_Country__c = lane.Origin_Country__c;
    bid.Origin_Postal__c = lane.Origin_Postal__c;
    bid.Origin_Place__c = lane.Origin_Place__c;
    bid.Origin_Geolocation__Latitude__s = lane.Origin_Place__r
      ?.Geolocation__Latitude__s;
    bid.Origin_Geolocation__Longitude__s = lane.Origin_Place__r
      ?.Geolocation__Longitude__s;
  }

  private static void applyDestination(
    Benchmark_Rate__c bid,
    RFP_Lane__c lane
  ) {
    bid.Destination_City__c = lane.Destination_City__c;
    bid.Destination_Province__c = lane.Destination_Province__c;
    bid.Destination_Country__c = lane.Destination_Country__c;
    bid.Destination_Postal__c = lane.Destination_Postal__c;
    bid.Destination_Place__c = lane.Destination_Place__c;
    bid.Destination_Geolocation__Latitude__s = lane.Destination_Place__r
      ?.Geolocation__Latitude__s;
    bid.Destination_Geolocation__Longitude__s = lane.Destination_Place__r
      ?.Geolocation__Longitude__s;
  }

  /** "City, ST:City, ST" from the canonical place spellings, the way Revenova writes rtms__City_Lane__c. */
  public static String cityLane(Pricing_Place__c o, Pricing_Place__c d) {
    return PlaceNormalizer.cityLaneSide(
        o.City__c,
        PlaceNormalizer.provinceCode(o.Province__c)
      ) +
      ':' +
      PlaceNormalizer.cityLaneSide(
        d.City__c,
        PlaceNormalizer.provinceCode(d.Province__c)
      );
  }

  public static String stateLane(Pricing_Place__c o, Pricing_Place__c d) {
    return PlaceNormalizer.provinceCode(o.Province__c) +
      ':' +
      PlaceNormalizer.provinceCode(d.Province__c);
  }

  public static String zip3Lane(Pricing_Place__c o, Pricing_Place__c d) {
    return prefix(o.Postal_Prefix__c) + ':' + prefix(d.Postal_Prefix__c);
  }

  private static String prefix(String p) {
    return p == null ? '' : p.replace(' ', '').left(3).toUpperCase();
  }

  private static Benchmark_Rate__c reload(Id bidId) {
    return [
      SELECT
        Id,
        Name,
        RFP_Lane__c,
        RFP_Project__c,
        Carrier__c,
        Carrier_Name__c,
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
        Notes__c,
        City_Lane__c,
        State_Lane__c,
        Zip3_Lane__c
      FROM Benchmark_Rate__c
      WHERE Id = :bidId
      WITH USER_MODE
    ];
  }
}
