/**
 * Saves carrier bids (Benchmark_Rate__c) in user mode. Validates the rate, inserts/updates and
 * reloads - nothing else. The lane keys Lane Benchmark searches on (city lane, state lane, zip3
 * lane, geolocations, project, mode/equipment/hazmat) are stamped by BenchmarkRateTrigger's
 * before-insert/before-update call into applyLanes below, not by save(): RFP_Tool_User marks those
 * fields editable=false (they are service-maintained, never user-entered), so the user-mode
 * insert/update here must not set them - only a system-context trigger can. This also means a bid
 * created directly on the record page (bypassing save() entirely) still gets stamped, which a
 * save()-only implementation could never do.
 */
public with sharing class BenchmarkRateService {
  public static Benchmark_Rate__c save(Benchmark_Rate__c bid) {
    if (bid.Rate__c == null) {
      throw new LaneSearchException('A bid needs a rate.');
    }
    if (bid.Id == null) {
      Database.insert(bid, AccessLevel.USER_MODE);
    } else {
      Database.update(bid, AccessLevel.USER_MODE);
    }
    return reload(bid.Id);
  }

  /** Called by BenchmarkRateTrigger (before insert/update) for every bid in the trigger batch. */
  public static void applyLanes(List<Benchmark_Rate__c> bids) {
    Map<Id, RFP_Lane__c> lanesById = loadLanes(bids);
    for (Benchmark_Rate__c bid : bids) {
      RFP_Lane__c lane = bid.RFP_Lane__c == null
        ? null
        : lanesById.get(bid.RFP_Lane__c);
      if (lane != null) {
        applyLane(bid, lane);
      }
      bid.Valid_From__c = bid.Valid_From__c ?? Date.today();
      bid.Expires_On__c = bid.Expires_On__c ?? Date.today().addDays(30);
    }
  }

  // System-mode SOQL: this only ever runs from BenchmarkRateTrigger, which is already a
  // system-context call (before insert/update), so there is no running user's FLS/CRUD to check -
  // the trigger reads every referenced lane once per batch to copy its keys onto the bids.
  @SuppressWarnings('PMD.ApexCRUDViolation')
  private static Map<Id, RFP_Lane__c> loadLanes(List<Benchmark_Rate__c> bids) {
    Set<Id> laneIds = new Set<Id>();
    for (Benchmark_Rate__c bid : bids) {
      if (bid.RFP_Lane__c != null) {
        laneIds.add(bid.RFP_Lane__c);
      }
    }
    Map<Id, RFP_Lane__c> lanesById = new Map<Id, RFP_Lane__c>();
    if (laneIds.isEmpty()) {
      return lanesById;
    }
    for (RFP_Lane__c lane : [
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
      WHERE Id IN :laneIds
    ]) {
      lanesById.put(lane.Id, lane);
    }
    return lanesById;
  }

  private static void applyLane(Benchmark_Rate__c bid, RFP_Lane__c lane) {
    bid.RFP_Project__c = lane.RFP_Project__c;
    bid.Mode__c = bid.Mode__c ?? lane.Mode__c;
    bid.Equipment_Category__c = bid.Equipment_Category__c ??
      lane.Equipment_Category__c;
    bid.Equipment_Type__c = bid.Equipment_Type__c ?? lane.Equipment_Type__c;
    bid.Hazmat__c = bid.Hazmat__c ?? lane.Hazmat__c;
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
