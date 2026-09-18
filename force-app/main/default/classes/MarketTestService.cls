/**
 * Phase 9: the carrier rates a pricer records on the Market Test page for one lane.
 *
 * A market-test rate is a Benchmark_Rate__c with no RFP project, no RFP lane and
 * Market_Test__c true. The marker identifies it, not the absence of the lookups: both are
 * SetNull, so deleting a customer account leaves its bids with no project and no lane, and a
 * read scoped on that absence would list a deleted customer's bids to everyone holding the
 * permission set (spec D4, O3).
 *
 * `without sharing` on purpose, as LaneSearchService is: a lane's market-test rates are shared
 * knowledge, the same rates Lane Benchmark already counts in its median. Writing is not shared -
 * updateRate and deleteRate take only a record the running user owns and only one that carries
 * the marker, so neither can reach an RFP bid or an orphan.
 */
public without sharing class MarketTestService {
  @TestVisible
  private static final String NOT_YOURS = 'That rate is not yours to change.';
  @TestVisible
  private static final String NO_PLACES = 'Pick both ends of the lane first.';
  private static final Integer RATE_LIMIT = 200;

  public static List<Benchmark_Rate__c> ratesOfLane(
    String originKey,
    String destinationKey
  ) {
    String lane = cityLaneOf(originKey, destinationKey);
    return [
      SELECT
        Id,
        Name,
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
        OwnerId,
        CreatedDate
      FROM Benchmark_Rate__c
      WHERE Market_Test__c = TRUE AND City_Lane__c = :lane
      ORDER BY CreatedDate DESC
      LIMIT :RATE_LIMIT
    ];
  }

  public static Benchmark_Rate__c save(
    Benchmark_Rate__c posted,
    String originKey,
    String destinationKey
  ) {
    if (!Schema.SObjectType.Benchmark_Rate__c.isCreateable()) {
      throw new LaneSearchException('You cannot record a rate.');
    }
    Map<String, Pricing_Place__c> places = placesByKey(
      originKey,
      destinationKey
    );
    Benchmark_Rate__c rate = new Benchmark_Rate__c();
    copySettable(posted, rate);
    rate.Market_Test__c = true;
    rate.RFP_Project__c = null;
    rate.RFP_Lane__c = null;
    applyPlaces(rate, places.get(originKey), places.get(destinationKey));
    insert rate;
    return rate;
  }

  public static Benchmark_Rate__c updateRate(Benchmark_Rate__c posted) {
    Benchmark_Rate__c stored = ownRate(posted.Id);
    copySettable(posted, stored);
    update stored;
    return stored;
  }

  public static void deleteRate(Id rateId) {
    delete ownRate(rateId);
  }

  /**
   * The one gate for every write: the record exists, carries the marker, has no RFP lane and
   * belongs to the running user. Anything else is refused with the same sentence, so a probe
   * cannot tell a colleague's rate from an RFP bid from a record that is not there.
   */
  private static Benchmark_Rate__c ownRate(Id rateId) {
    List<Benchmark_Rate__c> stored = [
      SELECT Id, OwnerId, Market_Test__c, RFP_Lane__c, RFP_Project__c
      FROM Benchmark_Rate__c
      WHERE Id = :rateId
      LIMIT 1
    ];
    Boolean mine =
      !stored.isEmpty() &&
      stored[0].Market_Test__c == true &&
      stored[0].RFP_Lane__c == null &&
      stored[0].OwnerId == UserInfo.getUserId();
    if (!mine) {
      throw new LaneSearchException(NOT_YOURS);
    }
    return stored[0];
  }

  /** Only the fields the form owns: never OwnerId, never the marker, never the lane keys. */
  private static void copySettable(
    Benchmark_Rate__c posted,
    Benchmark_Rate__c onto
  ) {
    onto.Carrier__c = posted.Carrier__c;
    onto.Carrier_Name__c = posted.Carrier_Name__c;
    onto.Contact_Name__c = posted.Contact_Name__c;
    onto.Contact_Email__c = posted.Contact_Email__c;
    onto.Contact_Phone__c = posted.Contact_Phone__c;
    onto.Rate__c = posted.Rate__c;
    onto.CurrencyIsoCode = posted.CurrencyIsoCode;
    onto.Fuel_Surcharge__c = posted.Fuel_Surcharge__c;
    onto.FSC_Included__c = posted.FSC_Included__c;
    onto.Transit_Days__c = posted.Transit_Days__c;
    onto.Valid_From__c = posted.Valid_From__c;
    onto.Expires_On__c = posted.Expires_On__c;
    onto.Notes__c = posted.Notes__c;
    onto.Mode__c = posted.Mode__c;
    onto.Equipment_Category__c = posted.Equipment_Category__c;
    onto.Equipment_Type__c = posted.Equipment_Type__c;
    onto.Hazmat__c = posted.Hazmat__c;
  }

  /**
   * The trigger copies lane keys from an RFP lane, and a market-test rate has none, so the keys
   * are stamped here from the two places instead - without them the rate carries no lane and no
   * lane search would ever match it, so it would never reach the median it exists to join (D5).
   */
  private static void applyPlaces(
    Benchmark_Rate__c rate,
    Pricing_Place__c origin,
    Pricing_Place__c destination
  ) {
    rate.Origin_Place__c = origin.Id;
    rate.Origin_City__c = origin.City__c;
    rate.Origin_Province__c = origin.Province__c;
    rate.Origin_Country__c = origin.Country__c;
    rate.Origin_Postal__c = origin.Postal_Prefix__c;
    rate.Origin_Geolocation__Latitude__s = origin.Geolocation__Latitude__s;
    rate.Origin_Geolocation__Longitude__s = origin.Geolocation__Longitude__s;
    rate.Destination_Place__c = destination.Id;
    rate.Destination_City__c = destination.City__c;
    rate.Destination_Province__c = destination.Province__c;
    rate.Destination_Country__c = destination.Country__c;
    rate.Destination_Postal__c = destination.Postal_Prefix__c;
    rate.Destination_Geolocation__Latitude__s = destination.Geolocation__Latitude__s;
    rate.Destination_Geolocation__Longitude__s = destination.Geolocation__Longitude__s;
    rate.City_Lane__c = BenchmarkRateService.cityLane(origin, destination);
    rate.State_Lane__c = BenchmarkRateService.stateLane(origin, destination);
    rate.Zip3_Lane__c = BenchmarkRateService.zip3Lane(origin, destination);
  }

  private static String cityLaneOf(String originKey, String destinationKey) {
    Map<String, Pricing_Place__c> places = placesByKey(
      originKey,
      destinationKey
    );
    return BenchmarkRateService.cityLane(
      places.get(originKey),
      places.get(destinationKey)
    );
  }

  /** Keyed by Key__c, the same place key the picker emits and every lane search speaks. */
  private static Map<String, Pricing_Place__c> placesByKey(
    String originKey,
    String destinationKey
  ) {
    if (String.isBlank(originKey) || String.isBlank(destinationKey)) {
      throw new LaneSearchException(NO_PLACES);
    }
    Map<String, Pricing_Place__c> places = new Map<String, Pricing_Place__c>();
    for (Pricing_Place__c place : [
      SELECT
        Id,
        Key__c,
        City__c,
        Province__c,
        Country__c,
        Postal_Prefix__c,
        Geolocation__Latitude__s,
        Geolocation__Longitude__s
      FROM Pricing_Place__c
      WHERE Key__c IN (:originKey, :destinationKey)
    ]) {
      places.put(place.Key__c, place);
    }
    if (places.get(originKey) == null || places.get(destinationKey) == null) {
      throw new LaneSearchException(NO_PLACES);
    }
    return places;
  }
}
