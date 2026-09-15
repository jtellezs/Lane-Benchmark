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
      RFP_Lane__c lane = new RFP_Lane__c(
        Id = laneId,
        Hist_Status__c = nextHistStatus(laneId, side)
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
}
