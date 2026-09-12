/** Writes carrier-quote history snapshots onto RFP lanes, ten lanes per call (user-mode DML). */
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
    String radiusUnit
  ) {
    if (laneIds == null || laneIds.size() > MAX_LANES) {
      throw new LaneSearchException(
        'Load history for at most ' + MAX_LANES + ' lanes per call.'
      );
    }
    Integer days = lookbackDays == null || lookbackDays < 1 ? 90 : lookbackDays;
    Integer km = radiusOf(radius);
    String unit = radiusUnit == 'MI' ? 'MI' : 'KM';
    List<RFP_Lane__c> lanes = RfpLaneController.lanesByIds(laneIds);
    List<RFP_Lane__c> updates = new List<RFP_Lane__c>();
    for (RFP_Lane__c lane : lanes) {
      updates.add(snapshot(lane, precision, days, km, unit));
    }
    saveSnapshots(updates);
    return RfpLaneController.lanesByIds(laneIds);
  }

  /** Null or non-positive means the 50 km default; anything above 500 is refused, not clamped. */
  private static Integer radiusOf(Decimal radius) {
    if (radius == null || radius <= 0) {
      return DEFAULT_RADIUS;
    }
    if (radius > MAX_RADIUS) {
      throw new LaneSearchException(
        'Radius must be between 1 and ' + MAX_RADIUS + '.'
      );
    }
    return radius.round().intValue();
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
    String unit
  ) {
    RFP_Lane__c u = new RFP_Lane__c(
      Id = lane.Id,
      Hist_Lookback_Days__c = days,
      Hist_As_Of__c = Datetime.now(),
      Hist_Count__c = 0,
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
      return u;
    }
    try {
      String used = precision;
      LaneSearchResult r = LaneSearchService.search(
        request(lane, precision, days, radius, unit)
      );
      if (r.rows.isEmpty() && precision == 'CITY') {
        used = 'RADIUS';
        r = LaneSearchService.search(request(lane, used, days, radius, unit));
      }
      fill(u, r, lane.CurrencyIsoCode);
      u.Hist_Precision__c = used == 'RADIUS' ? 'RADIUS-' + radius + unit : used;
      u.Hist_Status__c = r.rows.isEmpty() ? 'No match' : 'Done';
    } catch (LaneSearchException e) {
      u.Hist_Status__c = 'No match';
    } catch (Exception e) {
      u.Hist_Status__c = 'Failed';
    }
    return u;
  }

  private static LaneSearchRequest request(
    RFP_Lane__c lane,
    String precision,
    Integer days,
    Integer radius,
    String unit
  ) {
    LaneSearchRequest req = new LaneSearchRequest();
    req.originKey = lane.Origin_Place__r.Key__c;
    req.destinationKey = lane.Destination_Place__r.Key__c;
    req.lookbackDays = days;
    req.rowLimit = ROW_LIMIT;
    req.sourceFilter = LaneSearchRequest.RowSource.LOADS;
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
    LaneSearchResult.Stats s = r.statsByCurrency.get(currencyCode);
    if (s == null) {
      return;
    }
    u.Hist_Min__c = s.min;
    u.Hist_Median__c = s.median;
    u.Hist_Average__c = s.avg;
    u.Hist_Max__c = s.max;
  }
}
