/**
 * Estimated split-lane options for a lane whose split history has no group (phase 8, spec §4
 * Estimates, D8, R86). The active handoff points (HandoffPoints), minus a point equal to either
 * end, are read by Key__c; a point is kept when origin -> point -> destination is at most 10 %
 * longer than origin -> destination in TripMilesService.approxMiles (the Approx factor cancels out
 * of the ratio), at most 3, least extra distance first. Each kept point reads its two leg lanes
 * from Revenova loads (LaneQueries.legConditions and legLoadSoql): moved loads with a positive CAD
 * carrier total, not cancelled, without an intercompany carrier, the most recent 500 per leg over
 * 365 days. Leg 1 keeps the origin end at the first search's precision (a radius end uses its
 * place's city key) and matches the point by city; leg 2 matches the point by city and keeps the
 * destination end's precision. Each leg shows its carriers and its median in the card's currency;
 * the estimate total is leg 1 median + leg 2 median, and the screen adds the typed handoff cost.
 * No callout: distances come from the places' coordinates, never from Mapbox.
 */
// Runs without sharing on purpose, like LaneSearchService: loads are Private and an estimate reads every team's moved loads on the leg lanes. Access is gated by the Lane Benchmark and RFP Tool permission sets.
public without sharing class SplitEstimates {
  @TestVisible
  private static final Decimal MAX_EXTRA = 0.10;
  @TestVisible
  private static final Integer MAX_POINTS = 3;
  @TestVisible
  private static final Integer LEG_DAYS = 365;
  @TestVisible
  private static final Integer LEG_LIMIT = 500;
  private static final String POINT_SOQL = 'SELECT Id, Key__c, City__c, Province__c, Country__c, Postal_Prefix__c, Spellings__c, Geolocation__Latitude__s, Geolocation__Longitude__s FROM Pricing_Place__c WHERE Key__c IN :pointKeys';

  /** One Estimate option per kept handoff point, least extra distance first; empty when none qualifies. */
  public static List<SplitLaneResult.Option> estimate(
    LaneSearchRequest req,
    Pricing_Place__c origin,
    Pricing_Place__c destination,
    String currencyCode,
    ExchangeRates rates
  ) {
    List<SplitLaneResult.Option> options = new List<SplitLaneResult.Option>();
    for (Candidate c : candidates(origin, destination)) {
      options.add(toOption(req, origin, destination, c, currencyCode, rates));
    }
    return options;
  }

  /** The qualifying points, sorted and cut to MAX_POINTS; no query when an end has no coordinates. */
  private static List<Candidate> candidates(
    Pricing_Place__c origin,
    Pricing_Place__c destination
  ) {
    List<Candidate> kept = new List<Candidate>();
    TruckRoute.Profile profile = TruckRoute.defaultProfile();
    Decimal direct = TripMilesService.approxMiles(origin, destination, profile);
    if (direct == null || direct == 0) {
      return kept;
    }
    for (Pricing_Place__c point : pointPlaces(origin, destination)) {
      Decimal extra = extraShare(origin, point, destination, direct, profile);
      if (extra != null && extra <= MAX_EXTRA) {
        kept.add(new Candidate(point, extra));
      }
    }
    kept.sort();
    while (kept.size() > MAX_POINTS) {
      kept.remove(kept.size() - 1);
    }
    return kept;
  }

  /** (origin -> point + point -> destination - direct) / direct; null when the point has no coordinates. */
  private static Decimal extraShare(
    Pricing_Place__c origin,
    Pricing_Place__c point,
    Pricing_Place__c destination,
    Decimal direct,
    TruckRoute.Profile profile
  ) {
    Decimal toPoint = TripMilesService.approxMiles(origin, point, profile);
    Decimal fromPoint = TripMilesService.approxMiles(
      point,
      destination,
      profile
    );
    if (toPoint == null || fromPoint == null) {
      return null;
    }
    return (toPoint + fromPoint - direct) / direct;
  }

  /** The places of the active handoff keys other than the two lane ends; no query when no key is left. */
  @SuppressWarnings(
    'PMD.ApexCRUDViolation'
  ) // system mode by design (see class comment); Database.queryWithBinds also counts as CRUD for PMD
  private static List<Pricing_Place__c> pointPlaces(
    Pricing_Place__c origin,
    Pricing_Place__c destination
  ) {
    Set<String> pointKeys = new Set<String>(HandoffPoints.activeKeys());
    pointKeys.remove(origin.Key__c?.toLowerCase());
    pointKeys.remove(destination.Key__c?.toLowerCase());
    if (pointKeys.isEmpty()) {
      return new List<Pricing_Place__c>();
    }
    return Database.queryWithBinds(
      POINT_SOQL,
      new Map<String, Object>{ 'pointKeys' => pointKeys },
      AccessLevel.SYSTEM_MODE
    );
  }

  private static SplitLaneResult.Option toOption(
    LaneSearchRequest req,
    Pricing_Place__c origin,
    Pricing_Place__c destination,
    Candidate c,
    String currencyCode,
    ExchangeRates rates
  ) {
    SplitLaneResult.Option estimated = new SplitLaneResult.Option();
    estimated.kind = SplitLaneResult.ESTIMATE;
    estimated.handoffLabel = placeLabel(c.point);
    estimated.extraDistancePct = (c.extra * 100)
      .setScale(0, RoundingMode.HALF_UP)
      .intValue();
    Map<String, Object> oneBinds = new Map<String, Object>();
    List<String> oneLane = LaneQueries.legConditions(
      req,
      origin,
      LaneQueries.deepPrecision(req.originPrecision),
      req.originZip3,
      c.point,
      LaneSearchRequest.Precision.CITY,
      null,
      oneBinds
    );
    Map<String, Object> twoBinds = new Map<String, Object>();
    List<String> twoLane = LaneQueries.legConditions(
      req,
      c.point,
      LaneSearchRequest.Precision.CITY,
      null,
      destination,
      LaneQueries.deepPrecision(req.destinationPrecision),
      req.destinationZip3,
      twoBinds
    );
    SplitLaneResult.Leg legOne = toLeg(
      1,
      origin,
      c.point,
      readLeg(oneLane, oneBinds),
      currencyCode,
      rates
    );
    SplitLaneResult.Leg legTwo = toLeg(
      2,
      c.point,
      destination,
      readLeg(twoLane, twoBinds),
      currencyCode,
      rates
    );
    estimated.legs = new List<SplitLaneResult.Leg>{ legOne, legTwo };
    if (legOne.median != null && legTwo.median != null) {
      estimated.medianTotal = (legOne.median + legTwo.median).setScale(2);
    }
    return estimated;
  }

  /** The leg's moved loads; none (and no query) when LaneQueries could not match both ends. */
  @SuppressWarnings(
    'PMD.ApexCRUDViolation'
  ) // system mode by design (see class comment); Database.queryWithBinds also counts as CRUD for PMD
  private static List<rtms__Load__c> readLeg(
    List<String> conditions,
    Map<String, Object> binds
  ) {
    if (conditions == null) {
      return new List<rtms__Load__c>();
    }
    String soql = LaneQueries.legLoadSoql(
      conditions,
      LEG_DAYS,
      LEG_LIMIT,
      binds
    );
    return Database.queryWithBinds(soql, binds, AccessLevel.SYSTEM_MODE);
  }

  /** Carriers with their legs moved, and the median of the loads' totals in the card's currency. */
  private static SplitLaneResult.Leg toLeg(
    Integer position,
    Pricing_Place__c fromPlace,
    Pricing_Place__c toPlace,
    List<rtms__Load__c> loads,
    String currencyCode,
    ExchangeRates rates
  ) {
    SplitLaneResult.Leg out = new SplitLaneResult.Leg();
    out.position = position;
    out.laneLabel = placeLabel(fromPlace) + ' → ' + placeLabel(toPlace);
    SplitLaneService.CarrierTally tally = new SplitLaneService.CarrierTally();
    List<Decimal> amounts = new List<Decimal>();
    for (rtms__Load__c load : loads) {
      tally.add(
        load.rtms__Carrier__c,
        load.rtms__Carrier__r?.Name,
        load.rtms__Carrier__r?.Black_List__c
      );
      Decimal amount = SplitLaneService.amountIn(
        currencyCode,
        rates,
        load.rtms__Carrier_Quote_Total__c,
        load.CreatedDate
      );
      if (amount != null) {
        amounts.add(amount);
      }
    }
    out.carriers = tally.sorted();
    out.median = SplitLaneService.median(amounts);
    out.pricedCount = amounts.size();
    return out;
  }

  private static String placeLabel(Pricing_Place__c place) {
    return place.City__c + ', ' + place.Province__c;
  }

  /** A handoff point that qualified, with its extra distance as a share of the direct distance. */
  private class Candidate implements Comparable {
    private final Pricing_Place__c point;
    private final Decimal extra;

    private Candidate(Pricing_Place__c point, Decimal extra) {
      this.point = point;
      this.extra = extra;
    }

    /** Least extra distance first; an equal share goes by place key, so the order never depends on the query. */
    public Integer compareTo(Object other) {
      Candidate that = (Candidate) other;
      if (extra != that.extra) {
        return extra < that.extra ? -1 : 1;
      }
      return point.Key__c.compareTo(that.point.Key__c);
    }
  }
}
