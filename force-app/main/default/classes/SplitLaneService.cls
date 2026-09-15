/**
 * Split-lane options, history part (phase 8, spec section 4). The lane's Revenova freight plans over
 * the last 12 months, found through their customer load (LaneQueries.planSoql, read only through
 * FreightPlanReader), become shipments of carrier legs. A shipment is left out when it has fewer
 * than two carrier legs, a cancelled leg, or an intercompany carrier on a leg (R87). The rest are
 * grouped by their handoff sequence: after every leg but the last, the city after the last ':' of
 * the leg's rtms__City_Lane__c, then the leg's last stop account name (R105). Each group gives every
 * leg position its carriers (CarrierTally), its most frequent leg lane and the median of its priced
 * leg totals, and gives the group the median of the sums of the shipments whose legs are all priced,
 * not a sum of leg medians (R85). Leg totals are stored in CAD; in USD each one is converted at the
 * dated rate of its own load's CreatedDate before any median or sum (R109). Task 9 adds estimates
 * when history finds no group.
 *
 * The grouping lives in the inner classes HistoryGroups, ShipmentGroup and PositionTally, so their
 * branches stay out of this class's PMD complexity total (the phase 7 TripMilesService ruling).
 */
// Runs without sharing on purpose, like LaneSearchService: freight plans, loads and carrier quotes
// inherit Private load sharing, and a split benchmark reads every team's shipments. Access is gated
// by the Lane Benchmark and RFP Tool permission sets through SplitLaneController (Task 9).
public without sharing class SplitLaneService {
  public static final String NO_OPTION_MESSAGE = 'No split shipment on this lane in the last 12 months, and no handoff point is close enough for an estimate.';
  private static final String USD = 'USD';
  private static final String CARRIER_ROW = 'Carrier';
  private static final String CANCELLED = 'Cancelled';
  private static final String LOAD_PATH = 'rtms__Load__r.';
  private static final String ARROW = ' → ';
  private static final String DOT = ' · ';
  private static final String NO_PLACE = 'Both ends of the lane need a place.';
  private static final String NO_USD_RATE = 'No USD exchange rate is available.';
  private static final Integer HISTORY_DAYS = 365;
  private static final Integer PLAN_LIMIT = 1000;
  private static final Integer RATE_LOOKBACK_DAYS = 400;

  /** One carrier leg of a shipment, as the history reads it from the leg load. Public so tests can group shipments built in memory. */
  public class LegRow {
    public Datetime created;
    public Id carrierId;
    public String carrierName;
    public Boolean blacklisted = false;
    public String cityLane;
    public String status;
    public Decimal cadTotal;
    public String stopName;
  }

  /** Distinct carriers of one leg position with the legs each moved; SplitEstimates (Task 9) uses it too. */
  public class CarrierTally {
    private final Map<Id, SplitLaneResult.LegCarrier> byCarrier = new Map<Id, SplitLaneResult.LegCarrier>();

    /** Counts one leg. A leg without a carrier is ignored; a carrier is blacklisted when any of its legs says so. */
    public void add(Id carrierId, String name, Boolean blacklisted) {
      if (carrierId == null) {
        return;
      }
      SplitLaneResult.LegCarrier carrier = byCarrier.get(carrierId);
      if (carrier == null) {
        carrier = new SplitLaneResult.LegCarrier();
        carrier.carrierId = carrierId;
        byCarrier.put(carrierId, carrier);
      }
      carrier.name = carrier.name ?? name;
      carrier.legsMoved++;
      carrier.blacklisted = carrier.blacklisted || blacklisted == true;
    }

    /** Most legs first, then by name ignoring case. */
    public List<SplitLaneResult.LegCarrier> sorted() {
      List<CarrierOrder> entries = new List<CarrierOrder>();
      for (SplitLaneResult.LegCarrier carrier : byCarrier.values()) {
        entries.add(new CarrierOrder(carrier));
      }
      entries.sort();
      List<SplitLaneResult.LegCarrier> ranked = new List<SplitLaneResult.LegCarrier>();
      for (CarrierOrder entry : entries) {
        ranked.add(entry.carrier);
      }
      return ranked;
    }
  }

  /**
   * The split-lane card's history for a lane, in CAD or USD (SplitLaneController refuses other
   * codes, Task 9). The request's place keys, precisions, postal prefixes and mode, equipment and
   * hazmat filters decide the lane (LaneQueries.laneConditions; a radius end uses its place's city
   * key); its lookback, currency, accepted and source filters are ignored (R101). A
   * blank key reads nothing; an unknown place reads only the places; USD without a dated rate reads
   * no plan.
   */
  public static SplitLaneResult options(
    LaneSearchRequest req,
    String currencyCode
  ) {
    req.applyDefaults();
    SplitLaneResult result = new SplitLaneResult();
    result.currencyCode = currencyCode;
    Map<String, Pricing_Place__c> places = loadPlaces(req);
    Pricing_Place__c origin = places.get(req.originKey);
    Pricing_Place__c destination = places.get(req.destinationKey);
    if (origin == null || destination == null) {
      result.message = NO_PLACE;
      return result;
    }
    ExchangeRates rates = currencyCode == USD
      ? ExchangeRates.usd(Date.today().addDays(-RATE_LOOKBACK_DAYS))
      : null;
    if (rates != null && !rates.hasRates()) {
      result.message = NO_USD_RATE;
      return result;
    }
    Map<String, Object> binds = new Map<String, Object>();
    List<rtms__FreightPlan__c> plans = FreightPlanReader.read(
      historySoql(req, origin, destination, binds),
      binds
    );
    result.truncated = plans.size() >= PLAN_LIMIT;
    List<List<LegRow>> shipments = new List<List<LegRow>>();
    for (rtms__FreightPlan__c plan : plans) {
      shipments.add(legRows(plan));
    }
    result.options = groupHistory(shipments, currencyCode, rates);
    // Estimates only when history found no group (spec §4); they use the same places and rates.
    if (result.options.isEmpty()) {
      result.options = SplitEstimates.estimate(
        req,
        origin,
        destination,
        currencyCode,
        rates
      );
      if (result.options.isEmpty()) {
        result.message = NO_OPTION_MESSAGE;
      }
    }
    result.rateStartDate = rates?.latestStartUsed;
    return result;
  }

  /** Null for null or empty; odd count the middle value, even count the mean of the two middle values; scale 2. The list is not changed. */
  public static Decimal median(List<Decimal> values) {
    if (values == null || values.isEmpty()) {
      return null;
    }
    List<Decimal> ordered = values.clone();
    ordered.sort();
    Integer n = ordered.size();
    Decimal middle = Math.mod(n, 2) == 1
      ? ordered[n / 2]
      : (ordered[n / 2 - 1] + ordered[n / 2]) / 2;
    return middle.setScale(2);
  }

  /** A stored CAD amount in the card currency: USD at the dated rate of the load's CreatedDate (null without rates), otherwise the CAD amount. Unrounded. */
  public static Decimal amountIn(
    String currencyCode,
    ExchangeRates rates,
    Decimal cadAmount,
    Datetime loadCreated
  ) {
    return currencyCode == USD
      ? rates?.fromCad(cadAmount, loadCreated)
      : cadAmount;
  }

  /** The plan read: a year of customer loads on the lane, at most PLAN_LIMIT plans, with the leg amounts, lanes and last stop accounts. */
  @TestVisible
  private static String historySoql(
    LaneSearchRequest req,
    Pricing_Place__c origin,
    Pricing_Place__c destination,
    Map<String, Object> binds
  ) {
    return LaneQueries.planSoql(
      LaneQueries.laneConditions(req, origin, destination, LOAD_PATH, binds),
      HISTORY_DAYS,
      PLAN_LIMIT,
      true
    );
  }

  /**
   * Groups shipments (each a list of carrier legs in plan order) into history options, most
   * shipments first. @TestVisible so tests group shipments built in memory: a split shipment is three
   * loads, and the load automation leaves room for one per test (PricingTestDataFactory's class doc).
   */
  @TestVisible
  private static List<SplitLaneResult.Option> groupHistory(
    List<List<LegRow>> shipments,
    String currencyCode,
    ExchangeRates rates
  ) {
    return new HistoryGroups(currencyCode, rates, IntercompanyCarriers.ids())
      .build(shipments);
  }

  // System mode by design (see the class comment): places are reference data every pricer reads.
  @SuppressWarnings('PMD.ApexCRUDViolation')
  private static Map<String, Pricing_Place__c> loadPlaces(
    LaneSearchRequest req
  ) {
    Map<String, Pricing_Place__c> byKey = new Map<String, Pricing_Place__c>();
    if (String.isBlank(req.originKey) || String.isBlank(req.destinationKey)) {
      return byKey;
    }
    Set<String> keys = new Set<String>{ req.originKey, req.destinationKey };
    for (Pricing_Place__c p : [
      SELECT
        Id,
        Key__c,
        City__c,
        Province__c,
        Country__c,
        Postal_Prefix__c,
        Spellings__c,
        Geolocation__Latitude__s,
        Geolocation__Longitude__s
      FROM Pricing_Place__c
      WHERE Key__c IN :keys
    ]) {
      byKey.put(p.Key__c, p);
    }
    return byKey;
  }

  /** The plan's Carrier rows as legs, in the reader's rtms__Number__c order; the Customer row is skipped. A for loop, because a child list over 200 rows read directly throws. */
  private static List<LegRow> legRows(rtms__FreightPlan__c plan) {
    List<LegRow> legs = new List<LegRow>();
    for (rtms__FreightPlanLoad__c row : plan.rtms__Freight_Plan_Loads__r) {
      if (row.rtms__Type__c == CARRIER_ROW) {
        legs.add(toLegRow(row.rtms__Load__r));
      }
    }
    return legs;
  }

  /** A leg load as a LegRow; the carrier and last stop relationships may be absent (no carrier, or a row built by JSON.deserialize). */
  private static LegRow toLegRow(rtms__Load__c load) {
    LegRow leg = new LegRow();
    leg.created = load.CreatedDate;
    leg.carrierId = load.rtms__Carrier__c;
    leg.carrierName = load.rtms__Carrier__r?.Name;
    leg.blacklisted = load.rtms__Carrier__r?.Black_List__c == true;
    leg.cityLane = load.rtms__City_Lane__c;
    leg.status = load.rtms__Load_Status__c;
    leg.cadTotal = load.rtms__Carrier_Quote_Total__c;
    leg.stopName = load.rtms__Last_Stop__r?.rtms__Location2__r?.Name;
    return leg;
  }

  private static String sortName(String name) {
    return name == null ? '' : name.toLowerCase();
  }

  /** Builds the history options from shipments for one card currency and one intercompany list. */
  private class HistoryGroups {
    private final String currencyCode;
    private final ExchangeRates rates;
    private final Set<Id> intercompany;

    private HistoryGroups(
      String currencyCode,
      ExchangeRates rates,
      Set<Id> intercompany
    ) {
      this.currencyCode = currencyCode;
      this.rates = rates;
      this.intercompany = intercompany;
    }

    private List<SplitLaneResult.Option> build(List<List<LegRow>> shipments) {
      Map<String, ShipmentGroup> byKey = new Map<String, ShipmentGroup>();
      for (List<LegRow> legs : shipments) {
        if (!usable(legs)) {
          continue;
        }
        String label = handoffLabel(legs);
        String key = legs.size() + '|' + label.toLowerCase();
        if (!byKey.containsKey(key)) {
          byKey.put(key, new ShipmentGroup(label, legs.size()));
        }
        byKey.get(key).add(legs, amounts(legs));
      }
      List<ShipmentGroup> ordered = byKey.values();
      ordered.sort();
      List<SplitLaneResult.Option> built = new List<SplitLaneResult.Option>();
      for (ShipmentGroup shipmentGroup : ordered) {
        built.add(shipmentGroup.toOption());
      }
      return built;
    }

    /** Two carrier legs or more, none cancelled and none moved by an intercompany carrier (R87). */
    private Boolean usable(List<LegRow> legs) {
      if (legs.size() < 2) {
        return false;
      }
      for (LegRow leg : legs) {
        if (leg.status == CANCELLED || intercompany.contains(leg.carrierId)) {
          return false;
        }
      }
      return true;
    }

    /** The handoffs after every leg but the last, joined with an arrow. */
    private String handoffLabel(List<LegRow> legs) {
      List<String> handoffs = new List<String>();
      for (Integer i = 0; i < legs.size() - 1; i++) {
        handoffs.add(handoff(legs[i]));
      }
      return String.join(handoffs, ARROW);
    }

    /** "Laredo, TX · SFMN Park ITC Laredo yard": the city after the last ':' of the leg lane, then the leg's last stop account name when it has one. */
    private String handoff(LegRow leg) {
      List<String> parts = new List<String>();
      String city = leg.cityLane == null
        ? ''
        : leg.cityLane.substringAfterLast(':').trim();
      if (String.isNotBlank(city)) {
        parts.add(city);
      }
      if (String.isNotBlank(leg.stopName)) {
        parts.add(leg.stopName.trim());
      }
      return String.join(parts, DOT);
    }

    /** Each leg's amount in the card currency; null when the leg has no CAD total above zero. */
    private List<Decimal> amounts(List<LegRow> legs) {
      List<Decimal> converted = new List<Decimal>();
      for (LegRow leg : legs) {
        converted.add(
          leg.cadTotal != null &&
            leg.cadTotal > 0
            ? SplitLaneService.amountIn(
                currencyCode,
                rates,
                leg.cadTotal,
                leg.created
              )
            : null
        );
      }
      return converted;
    }
  }

  /** One handoff sequence: its shipment count, a tally per leg position and the sums of its fully priced shipments. */
  private class ShipmentGroup implements Comparable {
    private final String label;
    private final List<PositionTally> positions = new List<PositionTally>();
    private final List<Decimal> sums = new List<Decimal>();
    private Integer shipments = 0;

    private ShipmentGroup(String label, Integer legCount) {
      this.label = label;
      for (Integer i = 1; i <= legCount; i++) {
        positions.add(new PositionTally(i));
      }
    }

    private void add(List<LegRow> legs, List<Decimal> amounts) {
      shipments++;
      Decimal shipmentSum = 0;
      for (Integer i = 0; i < legs.size(); i++) {
        positions[i].add(legs[i], amounts[i]);
        shipmentSum = shipmentSum == null ||
          amounts[i] == null
          ? null
          : shipmentSum + amounts[i];
      }
      if (shipmentSum != null) {
        sums.add(shipmentSum);
      }
    }

    private SplitLaneResult.Option toOption() {
      SplitLaneResult.Option built = new SplitLaneResult.Option();
      built.kind = SplitLaneResult.HISTORY;
      built.handoffLabel = label;
      built.shipments = shipments;
      for (PositionTally tally : positions) {
        built.legs.add(tally.toLeg());
      }
      built.medianTotal = SplitLaneService.median(sums);
      built.pricedShipments = sums.size();
      return built;
    }

    /** Most shipments first, then by handoff label ignoring case. */
    public Integer compareTo(Object other) {
      ShipmentGroup that = (ShipmentGroup) other;
      if (shipments != that.shipments) {
        return shipments > that.shipments ? -1 : 1;
      }
      return SplitLaneService.sortName(label)
        .compareTo(SplitLaneService.sortName(that.label));
    }
  }

  /** One leg position of a group: its carriers, its leg lanes by frequency and its priced amounts. */
  private class PositionTally {
    private final Integer position;
    private final CarrierTally carriers = new CarrierTally();
    private final List<Decimal> priced = new List<Decimal>();
    private final Map<String, Integer> laneCounts = new Map<String, Integer>();
    private final List<String> lanesInOrder = new List<String>();

    private PositionTally(Integer position) {
      this.position = position;
    }

    private void add(LegRow leg, Decimal amount) {
      carriers.add(leg.carrierId, leg.carrierName, leg.blacklisted);
      if (amount != null) {
        priced.add(amount);
      }
      if (String.isBlank(leg.cityLane)) {
        return;
      }
      if (!laneCounts.containsKey(leg.cityLane)) {
        laneCounts.put(leg.cityLane, 0);
        lanesInOrder.add(leg.cityLane);
      }
      laneCounts.put(leg.cityLane, laneCounts.get(leg.cityLane) + 1);
    }

    private SplitLaneResult.Leg toLeg() {
      SplitLaneResult.Leg built = new SplitLaneResult.Leg();
      built.position = position;
      built.laneLabel = mostFrequentLane();
      built.carriers = carriers.sorted();
      built.median = SplitLaneService.median(priced);
      built.pricedCount = priced.size();
      return built;
    }

    /** The leg lane seen most often at this position (ties: the first seen), with an arrow for its ':'. */
    private String mostFrequentLane() {
      String best;
      for (String lane : lanesInOrder) {
        if (best == null || laneCounts.get(lane) > laneCounts.get(best)) {
          best = lane;
        }
      }
      return best == null ? null : best.replace(':', ARROW);
    }
  }

  /** Sort wrapper for CarrierTally.sorted(): most legs first, then by name ignoring case. */
  private class CarrierOrder implements Comparable {
    private final SplitLaneResult.LegCarrier carrier;

    private CarrierOrder(SplitLaneResult.LegCarrier carrier) {
      this.carrier = carrier;
    }

    public Integer compareTo(Object other) {
      SplitLaneResult.LegCarrier that = ((CarrierOrder) other).carrier;
      if (carrier.legsMoved != that.legsMoved) {
        return carrier.legsMoved > that.legsMoved ? -1 : 1;
      }
      return SplitLaneService.sortName(carrier.name)
        .compareTo(SplitLaneService.sortName(that.name));
    }
  }
}
