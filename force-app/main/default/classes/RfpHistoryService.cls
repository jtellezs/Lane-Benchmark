/**
 * Writes carrier-quote history snapshots and trip miles onto RFP lanes, ten lanes per call
 * (user-mode DML). Trip miles never call Mapbox here (spec D4, ruling R73): see TripMiles.
 */
public with sharing class RfpHistoryService {
  private static final Integer MAX_LANES = 10;
  private static final Integer ROW_LIMIT = 500;
  private static final Integer DEFAULT_RADIUS = 50;
  private static final Integer MAX_RADIUS = 500;

  public static List<RFP_Lane__c> run(
    List<Id> laneIds,
    String precision,
    Integer lookbackDays,
    Decimal radius,
    String radiusUnit,
    Boolean includeBids
  ) {
    if (laneIds == null || laneIds.size() > MAX_LANES) {
      throw new LaneSearchException(
        'Load history for at most ' + MAX_LANES + ' lanes per call.'
      );
    }
    Integer days = lookbackDays == null || lookbackDays < 1 ? 90 : lookbackDays;
    Integer km = radiusOf(radius);
    String unit = radiusUnit == 'MI' ? 'MI' : 'KM';
    // Null reads as true: a caller that never mentions bids gets the whole market, which is
    // what the workbench's toggle shows by default.
    Boolean bids = includeBids != false;
    List<RFP_Lane__c> lanes = RfpLaneController.lanesByIds(laneIds);
    // Built once per call: one read of the stored truck routes for the whole chunk.
    TripMiles trip = new TripMiles(lanes);
    List<RFP_Lane__c> updates = new List<RFP_Lane__c>();
    for (RFP_Lane__c lane : lanes) {
      updates.add(snapshot(lane, precision, days, km, unit, bids, trip));
    }
    saveSnapshots(updates);
    return RfpLaneController.lanesByIds(laneIds);
  }

  /**
   * Null or non-positive means the 50 km default; anything above 500 is refused, not
   * clamped. A value that rounds to 0 (e.g. 0.4) is not a usable radius either, so it
   * also falls back to the default instead of stamping a zero-radius search.
   */
  private static Integer radiusOf(Decimal radius) {
    if (radius == null || radius <= 0) {
      return DEFAULT_RADIUS;
    }
    if (radius > MAX_RADIUS) {
      throw new LaneSearchException(
        'Radius must be between 1 and ' + MAX_RADIUS + '.'
      );
    }
    Integer whole = radius.round().intValue();
    return whole < 1 ? DEFAULT_RADIUS : whole;
  }

  /**
   * allOrNone=false: one lane's DML failure (an out-of-range Hist_Lookback_Days__c, a validation
   * rule, ...) never discards every other lane's snapshot in the same chunk - a per-record
   * failure lands in that record's SaveResult instead of aborting the whole statement. Each
   * failed record then gets a best-effort second, minimal update (also allOrNone=false, user
   * mode) that flips only Hist_Status__c to 'Failed', so the UI still sees it; a lane that saved
   * keeps its full snapshot untouched. If that minimal update itself fails, it is ignored - best
   * effort only, per review ruling.
   */
  private static void saveSnapshots(List<RFP_Lane__c> updates) {
    List<RFP_Lane__c> toUpdate = Security.stripInaccessible(
        AccessType.UPDATABLE,
        updates
      )
      .getRecords();
    List<Database.SaveResult> results = Database.update(
      toUpdate,
      false,
      AccessLevel.USER_MODE
    );
    List<RFP_Lane__c> failed = new List<RFP_Lane__c>();
    for (Integer i = 0; i < results.size(); i++) {
      if (!results[i].isSuccess()) {
        failed.add(
          new RFP_Lane__c(Id = toUpdate[i].Id, Hist_Status__c = 'Failed')
        );
      }
    }
    if (failed.isEmpty()) {
      return;
    }
    try {
      Database.update(failed, false, AccessLevel.USER_MODE);
    } catch (Exception e) {
      // Best effort only: a lane that failed the real snapshot update just keeps whatever
      // Hist_Status__c it already had.
      System.debug(
        LoggingLevel.WARN,
        'RfpHistoryService: could not flag failed lanes as Failed: ' +
        e.getMessage()
      );
    }
  }

  private static RFP_Lane__c snapshot(
    RFP_Lane__c lane,
    String precision,
    Integer days,
    Integer radius,
    String unit,
    Boolean includeBids,
    TripMiles trip
  ) {
    RFP_Lane__c u = new RFP_Lane__c(
      Id = lane.Id,
      Hist_Lookback_Days__c = days,
      Hist_As_Of__c = Datetime.now(),
      Hist_Count__c = 0,
      Hist_Bid_Count__c = 0,
      Hist_Min__c = null,
      Hist_Median__c = null,
      Hist_Average__c = null,
      Hist_Max__c = null,
      // Reset here (not left unset) so a LaneSearchException/generic-exception catch below never
      // leaves a stale precision from an earlier run sitting next to a No match/Failed status;
      // the success path below sets the real value after this.
      Hist_Precision__c = null
    );
    if (
      lane.Origin_Place__r?.Key__c == null ||
      lane.Destination_Place__r?.Key__c == null
    ) {
      u.Hist_Status__c = 'Unresolved';
      trip.apply(u, lane, null);
      return u;
    }
    // Declared outside the try so the miles below read the search actually used: the RADIUS
    // fallback's result when it ran, the CITY result when the fallback threw.
    LaneSearchResult r = null;
    try {
      String used = precision;
      r = LaneSearchService.search(
        request(lane, precision, days, radius, unit, includeBids)
      );
      if (r.rows.isEmpty() && precision == 'CITY') {
        used = 'RADIUS';
        r = LaneSearchService.search(
          request(lane, used, days, radius, unit, includeBids)
        );
      }
      fill(u, r, lane.CurrencyIsoCode);
      u.Hist_Precision__c = used == 'RADIUS' ? 'RADIUS-' + radius + unit : used;
      u.Hist_Status__c = r.rows.isEmpty() ? 'No match' : 'Done';
    } catch (LaneSearchException e) {
      u.Hist_Status__c = 'No match';
    } catch (Exception e) {
      u.Hist_Status__c = 'Failed';
    }
    trip.apply(u, lane, r);
    return u;
  }

  private static LaneSearchRequest request(
    RFP_Lane__c lane,
    String precision,
    Integer days,
    Integer radius,
    String unit,
    Boolean includeBids
  ) {
    LaneSearchRequest req = new LaneSearchRequest();
    req.originKey = lane.Origin_Place__r.Key__c;
    req.destinationKey = lane.Destination_Place__r.Key__c;
    req.lookbackDays = days;
    req.rowLimit = ROW_LIMIT;
    // With bids in, the run counts every other RFP's carrier quotes for this lane match,
    // expired ones included (ruling R45), but never this project's own - those are the pricer's
    // inputs on the sheet in front of them, not market evidence (ruling R46).
    req.sourceFilter = includeBids
      ? LaneSearchRequest.RowSource.ALL
      : LaneSearchRequest.RowSource.LOADS;
    req.includeExpiredBids = includeBids;
    req.excludeProjectId = lane.RFP_Project__c;
    if (precision == 'RADIUS') {
      req.originPrecision = LaneSearchRequest.Precision.RADIUS;
      req.destinationPrecision = LaneSearchRequest.Precision.RADIUS;
      req.originRadius = radius;
      req.destinationRadius = radius;
      req.radiusUnit = unit == 'MI'
        ? LaneSearchRequest.Unit.MI
        : LaneSearchRequest.Unit.KM;
    } else if (precision == 'PROVINCE') {
      req.originPrecision = LaneSearchRequest.Precision.PROVINCE;
      req.destinationPrecision = LaneSearchRequest.Precision.PROVINCE;
    } else {
      req.originPrecision = LaneSearchRequest.Precision.CITY;
      req.destinationPrecision = LaneSearchRequest.Precision.CITY;
    }
    return req;
  }

  /**
   * Only the lane's own currency bucket is ever written (ruling R19). Falling back to the first
   * bucket used to stamp, say, a USD median onto a CAD lane - a number the pricer would then
   * mark up as if it were CAD. With no bucket for the lane's currency the count still records
   * that rows were found and the status is still 'Done'; min/median/average/max stay null, which
   * rfpLaneTable already renders as "N · no median".
   */
  private static void fill(
    RFP_Lane__c u,
    LaneSearchResult r,
    String currencyCode
  ) {
    u.Hist_Count__c = r.rows.size();
    // Counted before the stats lookup, so a Done lane with no bucket in its own currency still
    // records how much of its history came from bids.
    Integer bids = 0;
    for (LaneSearchResult.Row row : r.rows) {
      if (row.bid != null) {
        bids++;
      }
    }
    u.Hist_Bid_Count__c = bids;
    LaneSearchResult.Stats s = r.statsByCurrency.get(currencyCode);
    if (s == null) {
      return;
    }
    u.Hist_Min__c = s.min;
    u.Hist_Median__c = s.median;
    u.Hist_Average__c = s.avg;
    u.Hist_Max__c = s.max;
  }

  /**
   * Phase 7 trip miles for a history run (spec D4; rulings R73, R75): History, else the stored
   * truck route for the lane's ordered place pair and the current truck, else Approx, else
   * No coordinates. Every branch rewrites all three fields, so a stale route's hours never sit
   * next to History or Approx miles. Kept out of the outer class for the same complexity-budget
   * reason as RfpBidAccess.Gate.
   */
  private class TripMiles {
    private final TruckRoute.Profile profile = TruckRoute.defaultProfile();
    private final Map<String, Truck_Route__c> stored;

    TripMiles(List<RFP_Lane__c> lanes) {
      Set<String> keys = new Set<String>();
      for (RFP_Lane__c lane : lanes) {
        String key = routeKeyOf(lane);
        if (key != null) {
          keys.add(key);
        }
      }
      stored = TripMilesService.storedRoutes(keys);
    }

    private void apply(RFP_Lane__c u, RFP_Lane__c lane, LaneSearchResult r) {
      u.Miles__c = r?.medianMiles;
      u.Route_Hours__c = null;
      if (u.Miles__c != null) {
        u.Miles_Source__c = 'History';
        return;
      }
      Truck_Route__c route = stored.get(routeKeyOf(lane));
      if (route?.Status__c == 'Found') {
        u.Miles__c = route.Miles__c;
        u.Route_Hours__c = route.Hours__c;
        u.Miles_Source__c = route.Route_Type__c == 'Regular'
          ? 'Regular route'
          : 'Truck route';
      } else if (route?.Status__c == 'No route') {
        u.Miles_Source__c = 'No route';
      } else {
        u.Miles__c = approx(lane);
        u.Miles_Source__c = u.Miles__c == null ? 'No coordinates' : 'Approx';
      }
    }

    private String routeKeyOf(RFP_Lane__c lane) {
      return lane.Origin_Place__c == null ||
        lane.Destination_Place__c == null
        ? null
        : TripMilesService.routeKey(
            lane.Origin_Place__c,
            lane.Destination_Place__c,
            profile
          );
    }

    private Decimal approx(RFP_Lane__c lane) {
      return lane.Origin_Place__r == null ||
        lane.Destination_Place__r == null
        ? null
        : TripMilesService.approxMiles(
            lane.Origin_Place__r,
            lane.Destination_Place__r,
            profile
          );
    }
  }
}
