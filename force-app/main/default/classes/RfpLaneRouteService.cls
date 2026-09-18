/**
 * Phase 7's truck route for one lane, and the miles write that follows it.
 *
 * Split out of RfpLaneController per the Task 7 ruling that a class over PMD's 40 total
 * cyclomatic complexity is split rather than suppressed: the controller reached 42 when phase 12
 * added similarLanes, with no single method over its own threshold. The route pair is the most
 * self-contained group there - it is glue over TripRouteView, TripMilesService and the Mapbox
 * callout - and moving it leaves the FLS-sensitive lane-end resolution untouched.
 *
 * RfpLaneController keeps the @AuraEnabled laneRoute entry point as a thin delegate, so the page's
 * Apex contract and every existing test call are unchanged. Reading lanes still goes through the
 * controller's shared LANE_FIELDS readers, the same way RfpHistoryService does.
 */
public with sharing class RfpLaneRouteService {
  public static TripRouteView route(Id laneId, Boolean refresh) {
    List<RFP_Lane__c> lanes = RfpLaneController.lanesByIds(
      new List<Id>{ laneId }
    );
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
   * route's write step, after every callout. An Unavailable route (no source, no coordinates
   * included) changes nothing and never reaches the step: null. The lane's miles fields are read
   * again FOR UPDATE right before the update, not taken from route's read before the Mapbox
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
  public static RFP_Lane__c writeLaneMiles(Id laneId, TripRouteView view) {
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
    return RfpLaneController.one(laneId);
  }
}
