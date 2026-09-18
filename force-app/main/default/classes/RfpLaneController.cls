/** Lane-side @AuraEnabled entry points of the RFP workbench (user mode). */
public with sharing class RfpLaneController {
  private static final String LANE_FIELDS =
    'Id, Name, RFP_Project__c, Row_Number__c, Origin_City__c, Origin_Province__c, Origin_Country__c, Origin_Postal__c, ' +
    'Origin_Place__c, Origin_Place__r.Key__c, Origin_Resolved__c, Destination_City__c, Destination_Province__c, ' +
    'Destination_Country__c, Destination_Postal__c, Destination_Place__c, Destination_Place__r.Key__c, Destination_Resolved__c, ' +
    'Mode__c, Equipment_Category__c, Equipment_Type__c, Commodity__c, Quantity__c, Quantity_Unit__c, Shipments_Per_Year__c, ' +
    'Hazmat__c, Customer_Fuel_Surcharge__c, Customer_FSC_Included__c, Hist_Count__c, Hist_Bid_Count__c, Hist_Min__c, Hist_Median__c, ' +
    'Hist_Average__c, Hist_Max__c, Hist_Precision__c, Hist_Lookback_Days__c, Hist_As_Of__c, Hist_Status__c, Cost__c, ' +
    'Cost_Source__c, Selected_Bid__c, Selected_Bid__r.Carrier_Display__c, Margin__c, Sell__c, Sell_Source__c, Notes__c, CurrencyIsoCode, ' +
    'Miles__c, Miles_Source__c, Route_Hours__c, Origin_Place__r.Geolocation__Latitude__s, Origin_Place__r.Geolocation__Longitude__s, ' +
    'Destination_Place__r.Geolocation__Latitude__s, Destination_Place__r.Geolocation__Longitude__s';

  @AuraEnabled
  public static RfpImportService.Summary importLanes(
    Id projectId,
    String rowsJson
  ) {
    try {
      List<RfpImportService.ImportRow> rows = (List<RfpImportService.ImportRow>) JSON.deserialize(
        rowsJson,
        List<RfpImportService.ImportRow>.class
      );
      return RfpImportService.importRows(projectId, rows);
    } catch (LaneSearchException e) {
      throw RfpUserError.of(e.getMessage());
    } catch (Exception e) {
      throw RfpUserError.of(
        'The lanes could not be imported. ' + RfpUserError.safe(e)
      );
    }
  }

  @AuraEnabled
  public static List<RFP_Lane__c> getLanes(Id projectId) {
    try {
      return RfpBidAccess.attachSelectedBids(
        (List<RFP_Lane__c>) Database.queryWithBinds(
          'SELECT ' +
            LANE_FIELDS +
            ' FROM RFP_Lane__c WHERE RFP_Project__c = :projectId ORDER BY Row_Number__c LIMIT 2000',
          new Map<String, Object>{ 'projectId' => projectId },
          AccessLevel.USER_MODE
        )
      );
    } catch (Exception e) {
      throw RfpUserError.of(
        'The lanes could not be loaded. ' + RfpUserError.safe(e)
      );
    }
  }

  @AuraEnabled
  public static List<RFP_Lane__c> getRawRows(Id projectId, Integer offset) {
    try {
      Integer off = offset == null ? 0 : offset;
      return [
        SELECT Id, Row_Number__c, Raw_Row__c
        FROM RFP_Lane__c
        WHERE RFP_Project__c = :projectId
        WITH USER_MODE
        ORDER BY Row_Number__c
        LIMIT 500
        OFFSET :off
      ];
    } catch (Exception e) {
      throw RfpUserError.of(
        'The original rows could not be loaded. ' + RfpUserError.safe(e)
      );
    }
  }

  @AuraEnabled
  public static RFP_Lane__c saveLanePricing(String laneJson) {
    try {
      RFP_Lane__c posted = (RFP_Lane__c) JSON.deserialize(
        laneJson,
        RFP_Lane__c.class
      );
      RFP_Lane__c lane = new RFP_Lane__c(
        Id = posted.Id,
        Cost__c = posted.Cost__c,
        Cost_Source__c = posted.Cost_Source__c,
        Selected_Bid__c = posted.Selected_Bid__c,
        Margin__c = posted.Margin__c,
        Sell__c = posted.Sell__c,
        Sell_Source__c = posted.Sell_Source__c,
        Notes__c = posted.Notes__c
      );
      List<RFP_Lane__c> deferred = RfpBidAccess.detachSelectedBids(
        new List<RFP_Lane__c>{ lane }
      );
      Database.update(
        Security.stripInaccessible(
            AccessType.UPDATABLE,
            new List<RFP_Lane__c>{ lane }
          )
          .getRecords()[0],
        AccessLevel.USER_MODE
      );
      RfpBidAccess.applySelectedBids(deferred);
      return one(posted.Id);
    } catch (LaneSearchException e) {
      // The bid rule's own sentences ("That bid is not available.") read whole, as importLanes does.
      throw RfpUserError.of(e.getMessage());
    } catch (Exception e) {
      throw RfpUserError.of(
        'The lane price could not be saved. ' + RfpUserError.safe(e)
      );
    }
  }

  @AuraEnabled
  public static RFP_Lane__c resolveLaneEnd(
    Id laneId,
    String side,
    String placeKey
  ) {
    if (side != 'origin' && side != 'destination') {
      throw RfpUserError.of('side must be origin or destination');
    }
    try {
      Pricing_Place__c place = [
        SELECT Id, City__c, Province__c, Country__c, Postal_Prefix__c
        FROM Pricing_Place__c
        WHERE Key__c = :placeKey
        WITH USER_MODE
        LIMIT 1
      ];
      // The trip fields belong to the old place pair, or to none: a history run writes 'No
      // coordinates' on a lane with an unresolved end. They are cleared, and the lane panel's route
      // or the next history run fills them for the resolved lane (controller ruling).
      RFP_Lane__c lane = new RFP_Lane__c(
        Id = laneId,
        Hist_Status__c = nextHistStatus(laneId, side),
        Miles__c = null,
        Miles_Source__c = null,
        Route_Hours__c = null
      );
      if (side == 'origin') {
        lane.Origin_City__c = place.City__c;
        lane.Origin_Province__c = place.Province__c;
        lane.Origin_Country__c = place.Country__c;
        lane.Origin_Postal__c = place.Postal_Prefix__c;
        lane.Origin_Place__c = place.Id;
        lane.Origin_Resolved__c = true;
      } else {
        lane.Destination_City__c = place.City__c;
        lane.Destination_Province__c = place.Province__c;
        lane.Destination_Country__c = place.Country__c;
        lane.Destination_Postal__c = place.Postal_Prefix__c;
        lane.Destination_Place__c = place.Id;
        lane.Destination_Resolved__c = true;
      }
      Database.update(
        Security.stripInaccessible(
            AccessType.UPDATABLE,
            new List<RFP_Lane__c>{ lane }
          )
          .getRecords()[0],
        AccessLevel.USER_MODE
      );
      return one(laneId);
    } catch (AuraHandledException e) {
      throw e;
    } catch (Exception e) {
      throw RfpUserError.of(
        'The place could not be applied. ' + RfpUserError.safe(e)
      );
    }
  }

  /**
   * The truck route of one lane (phase 7), for the lane panel; not cacheable, it calls out and
   * saves. The lane is read in user mode, so a lane the caller cannot read is "This lane is not
   * available." TripRouteView.routeBetween makes the callouts and then saves the store row; the
   * lane's miles are written last, by writeLaneMiles, which decides on the lane as it is at that
   * moment; the read before the Mapbox call gives only the places. view.lane is the lane as stored
   * after that write step (written, already holding the route, or kept for its History miles), so
   * the panel's miles line always matches the database; it stays null only for an Unavailable
   * route (no coordinates included), which never reaches the write step (controller ruling). The
   * lane read and its refusal sit before the try so that no AuraHandledException needs
   * re-throwing: each catch and throw counts toward PMD's class complexity budget, which this
   * class is close to.
   */
  @AuraEnabled
  public static TripRouteView laneRoute(Id laneId, Boolean refresh) {
    List<RFP_Lane__c> lanes = lanesByIds(new List<Id>{ laneId });
    if (lanes.isEmpty()) {
      throw RfpUserError.of(RfpBidAccess.LANE_UNAVAILABLE);
    }
    try {
      RFP_Lane__c stored = lanes[0];
      TripRouteView view = TripRouteView.routeBetween(
        TripRouteView.laneEnd(stored.Origin_Place__c, stored.Origin_Place__r),
        TripRouteView.laneEnd(
          stored.Destination_Place__c,
          stored.Destination_Place__r
        ),
        refresh
      );
      view.lane = writeLaneMiles(laneId, view);
      return view;
    } catch (Exception e) {
      throw RfpUserError.of(
        'The truck route could not be loaded. ' + RfpUserError.safe(e)
      );
    }
  }

  /**
   * laneRoute's write step, after every callout. An Unavailable route (no source, no coordinates
   * included) changes nothing and never reaches the step: null. The lane's miles fields are read
   * again FOR UPDATE right before the update, not taken from laneRoute's read before the Mapbox
   * call: History miles that a history run saved while the route was on its way stay (R75), and
   * the lock keeps a run from saving between this read and the update (controller ruling).
   * TripRouteView.laneUpdate decides on that fresh copy, so a lane that already holds the route's
   * miles, source and hours is not rewritten either: the lane panel opens the route on every row
   * click (controller ruling). Written in user mode after the FLS strip like every lane save here.
   * Returns the lane as stored after the step, re-read with LANE_FIELDS, whether it was written,
   * already held the route or kept its History miles: the panel shows these miles beside the
   * route, so they must match the database (controller ruling). @TestVisible: a history run cannot
   * overlap a route call inside one test transaction, so the test replays that order on this step.
   */
  @TestVisible
  private static RFP_Lane__c writeLaneMiles(Id laneId, TripRouteView view) {
    if (view.source == null) {
      return null;
    }
    RFP_Lane__c miles = TripRouteView.laneUpdate(
      [
        SELECT Id, Miles__c, Miles_Source__c, Route_Hours__c
        FROM RFP_Lane__c
        WHERE Id = :laneId
        WITH USER_MODE
        FOR UPDATE
      ],
      view
    );
    if (miles != null) {
      Database.update(
        Security.stripInaccessible(
            AccessType.UPDATABLE,
            new List<RFP_Lane__c>{ miles }
          )
          .getRecords()[0],
        AccessLevel.USER_MODE
      );
    }
    return one(laneId);
  }

  /**
   * 'Pending' only once BOTH ends are resolved (the side being fixed now, plus whatever the
   * other side already is on the stored lane); otherwise the lane stays 'Unresolved', same rule
   * RfpImportService applies on import.
   */
  private static String nextHistStatus(Id laneId, String side) {
    RFP_Lane__c current = [
      SELECT Origin_Resolved__c, Destination_Resolved__c
      FROM RFP_Lane__c
      WHERE Id = :laneId
      WITH USER_MODE
    ];
    Boolean otherSideResolved = side == 'origin'
      ? current.Destination_Resolved__c
      : current.Origin_Resolved__c;
    return otherSideResolved ? 'Pending' : 'Unresolved';
  }

  private static RFP_Lane__c one(Id laneId) {
    return RfpBidAccess.attachSelectedBids(
      (List<RFP_Lane__c>) Database.queryWithBinds(
        'SELECT ' + LANE_FIELDS + ' FROM RFP_Lane__c WHERE Id = :laneId',
        new Map<String, Object>{ 'laneId' => laneId },
        AccessLevel.USER_MODE
      )
    )[0];
  }

  /** Shared by RfpHistoryService: the same field list as getLanes, for a set of Ids. */
  public static List<RFP_Lane__c> lanesByIds(List<Id> laneIds) {
    return RfpBidAccess.attachSelectedBids(
      (List<RFP_Lane__c>) Database.queryWithBinds(
        'SELECT ' +
          LANE_FIELDS +
          ' FROM RFP_Lane__c WHERE Id IN :laneIds ORDER BY Row_Number__c',
        new Map<String, Object>{ 'laneIds' => laneIds },
        AccessLevel.USER_MODE
      )
    );
  }

  /**
   * Phase 12: the other lanes of this lane's project that the same carrier rate plausibly covers,
   * for the pricer to confirm before anything is applied.
   */
  @AuraEnabled
  public static List<Id> similarLanes(Id laneId, Decimal radiusMiles) {
    try {
      return RfpLaneSimilarity.similarTo(laneId, radiusMiles);
    } catch (Exception e) {
      throw RfpUserError.of('The similar lanes could not be read.');
    }
  }
}
