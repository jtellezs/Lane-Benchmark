/** Writes carrier-quote history snapshots onto RFP lanes, ten lanes per call (user-mode DML). */
public with sharing class RfpHistoryService {
  private static final Integer MAX_LANES = 10;
  private static final Integer ROW_LIMIT = 500;
  private static final Decimal FALLBACK_RADIUS_KM = 50;

  public static List<RFP_Lane__c> run(
    List<Id> laneIds,
    String precision,
    Integer lookbackDays
  ) {
    if (laneIds == null || laneIds.size() > MAX_LANES) {
      throw new LaneSearchException(
        'Load history for at most ' + MAX_LANES + ' lanes per call.'
      );
    }
    Integer days = lookbackDays == null || lookbackDays < 1 ? 90 : lookbackDays;
    List<RFP_Lane__c> lanes = RfpLaneController.lanesByIds(laneIds);
    List<RFP_Lane__c> updates = new List<RFP_Lane__c>();
    for (RFP_Lane__c lane : lanes) {
      updates.add(snapshot(lane, precision, days));
    }
    Database.update(
      Security.stripInaccessible(AccessType.UPDATABLE, updates).getRecords(),
      AccessLevel.USER_MODE
    );
    return RfpLaneController.lanesByIds(laneIds);
  }

  private static RFP_Lane__c snapshot(
    RFP_Lane__c lane,
    String precision,
    Integer days
  ) {
    RFP_Lane__c u = new RFP_Lane__c(
      Id = lane.Id,
      Hist_Lookback_Days__c = days,
      Hist_As_Of__c = Datetime.now(),
      Hist_Count__c = 0,
      Hist_Min__c = null,
      Hist_Median__c = null,
      Hist_Average__c = null,
      Hist_Max__c = null
    );
    if (
      lane.Origin_Place__r?.Key__c == null ||
      lane.Destination_Place__r?.Key__c == null
    ) {
      u.Hist_Status__c = 'Unresolved';
      u.Hist_Precision__c = null;
      return u;
    }
    try {
      String used = precision;
      LaneSearchResult r = LaneSearchService.search(
        request(lane, precision, days)
      );
      if (r.rows.isEmpty() && precision == 'CITY') {
        used = 'RADIUS';
        r = LaneSearchService.search(request(lane, used, days));
      }
      fill(u, r, lane.CurrencyIsoCode);
      u.Hist_Precision__c = used == 'RADIUS' ? 'RADIUS-50KM' : used;
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
    Integer days
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
      req.originRadius = FALLBACK_RADIUS_KM;
      req.destinationRadius = FALLBACK_RADIUS_KM;
      req.radiusUnit = LaneSearchRequest.Unit.KM;
    } else if (precision == 'PROVINCE') {
      req.originPrecision = LaneSearchRequest.Precision.PROVINCE;
      req.destinationPrecision = LaneSearchRequest.Precision.PROVINCE;
    } else {
      req.originPrecision = LaneSearchRequest.Precision.CITY;
      req.destinationPrecision = LaneSearchRequest.Precision.CITY;
    }
    return req;
  }

  private static void fill(
    RFP_Lane__c u,
    LaneSearchResult r,
    String currencyCode
  ) {
    u.Hist_Count__c = r.rows.size();
    if (r.statsByCurrency.isEmpty()) {
      return;
    }
    LaneSearchResult.Stats s = r.statsByCurrency.get(currencyCode);
    if (s == null) {
      s = r.statsByCurrency.values()[0];
    }
    u.Hist_Min__c = s.min;
    u.Hist_Median__c = s.median;
    u.Hist_Average__c = s.avg;
    u.Hist_Max__c = s.max;
  }
}
