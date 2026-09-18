/**
 * Phase 12: the lanes a carrier's rate also covers.
 *
 * The owner's rule (2026-09-18): similar means the pick-ups are close to each other and the
 * deliveries are close to each other, with the mode and the equipment matching - not the same
 * province pair, which lumps Montreal-Toronto in with Gaspe-Windsor.
 *
 * Distance comes from the places' own coordinates through Location.getDistance rather than a
 * SOQL DISTANCE() across the lane's lookup, so the rule is testable without an org that has
 * geocoded data. A lane end with no coordinates falls back to matching its province.
 *
 * Nothing here applies a rate. It answers which lanes to offer, and the pricer confirms the
 * selection - a rate spread across lanes nobody looked at is a rate nobody can defend.
 *
 * The project scan is ordered by Row_Number__c because the workbench loads its own 2,000-lane
 * window that way. Unordered, the two windows are different sets on a project past the cap, and
 * an offered lane the table never rendered cannot be unticked - only submitted.
 *
 * Both queries bind through Database.queryWithBinds rather than Database.query: only the field
 * list and the row cap are ever concatenated, but the bound form is what the rest of the app uses
 * (RfpLaneController.one, .lanesByIds) and it is what keeps the SOQL-injection rule satisfied
 * without a suppression.
 */
public with sharing class RfpLaneSimilarity {
  /**
   * The row cap, camelCase and not final because it is overridable: a test shrinks the window to
   * prove the scan is ordered without inserting 2,001 lanes. Same shape as
   * MarketTestSetting.accountIdOverride.
   */
  @TestVisible
  private static Integer laneLimit = 2000;

  private static final String LANE_FIELDS =
    'Id, RFP_Project__c, Mode__c, Equipment_Category__c, Equipment_Type__c, ' +
    'Origin_Province__c, Destination_Province__c, ' +
    'Origin_Place__r.Geolocation__Latitude__s, Origin_Place__r.Geolocation__Longitude__s, ' +
    'Destination_Place__r.Geolocation__Latitude__s, Destination_Place__r.Geolocation__Longitude__s';

  /** The other lanes of this lane's project that the same rate plausibly covers. */
  public static List<Id> similarTo(Id laneId, Decimal radiusMiles) {
    List<Id> found = new List<Id>();
    if (laneId == null) {
      return found;
    }
    Decimal radius = radiusMiles == null || radiusMiles <= 0 ? 50 : radiusMiles;
    List<RFP_Lane__c> anchors = (List<RFP_Lane__c>) Database.queryWithBinds(
      'SELECT ' + LANE_FIELDS + ' FROM RFP_Lane__c WHERE Id = :laneId LIMIT 1',
      new Map<String, Object>{ 'laneId' => laneId },
      AccessLevel.USER_MODE
    );
    if (anchors.isEmpty()) {
      return found;
    }
    RFP_Lane__c anchor = anchors[0];
    Id projectId = anchor.RFP_Project__c;
    for (
      RFP_Lane__c lane : (List<RFP_Lane__c>) Database.queryWithBinds(
        'SELECT ' +
          LANE_FIELDS +
          ' FROM RFP_Lane__c' +
          ' WHERE RFP_Project__c = :projectId AND Id != :laneId' +
          ' ORDER BY Row_Number__c' +
          ' LIMIT ' +
          String.valueOf(laneLimit),
        new Map<String, Object>{ 'projectId' => projectId, 'laneId' => laneId },
        AccessLevel.USER_MODE
      )
    ) {
      if (covers(anchor, lane, radius)) {
        found.add(lane.Id);
      }
    }
    return found;
  }

  private static Boolean covers(
    RFP_Lane__c anchor,
    RFP_Lane__c lane,
    Decimal radius
  ) {
    return sameKind(anchor, lane) &&
      near(
        anchor.Origin_Place__r,
        lane.Origin_Place__r,
        anchor.Origin_Province__c,
        lane.Origin_Province__c,
        radius
      ) &&
      near(
        anchor.Destination_Place__r,
        lane.Destination_Place__r,
        anchor.Destination_Province__c,
        lane.Destination_Province__c,
        radius
      );
  }

  /** A blank on either side matches: an unfilled equipment type must not hide a real match. */
  private static Boolean sameKind(RFP_Lane__c anchor, RFP_Lane__c lane) {
    return agrees(anchor.Mode__c, lane.Mode__c) &&
      agrees(anchor.Equipment_Category__c, lane.Equipment_Category__c) &&
      agrees(anchor.Equipment_Type__c, lane.Equipment_Type__c);
  }

  private static Boolean agrees(String a, String b) {
    return String.isBlank(a) || String.isBlank(b) || a == b;
  }

  /** Coordinates when both ends have them; the province otherwise, so a place never geocoded still matches. */
  private static Boolean near(
    Pricing_Place__c a,
    Pricing_Place__c b,
    String provinceA,
    String provinceB,
    Decimal radius
  ) {
    Location here = pointOf(a);
    Location there = pointOf(b);
    if (here == null || there == null) {
      return String.isNotBlank(provinceA) && provinceA == provinceB;
    }
    return Location.getDistance(here, there, 'mi') <= radius;
  }

  private static Location pointOf(Pricing_Place__c place) {
    if (
      place == null ||
      place.Geolocation__Latitude__s == null ||
      place.Geolocation__Longitude__s == null
    ) {
      return null;
    }
    return Location.newInstance(
      place.Geolocation__Latitude__s,
      place.Geolocation__Longitude__s
    );
  }
}
