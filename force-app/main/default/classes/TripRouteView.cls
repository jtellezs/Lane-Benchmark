/**
 * The truck route the lane panel or a Lane Benchmark search shows (phase 7), and the flow both
 * controllers share: the stored Truck_Route__c for the ordered place pair unless refresh,
 * otherwise Mapbox; the store row saved after the callouts; the static map URL built on each view
 * and never stored. The branching lives here rather than in the controllers for the reason
 * LaneBenchmarkPlaceService gives: RfpLaneController (39) and LaneBenchmarkController (37) sit
 * close to PMD's class complexity budget of 40, and only moving branches to another class lowers
 * a class total.
 */
public with sharing class TripRouteView {
  public static final String NO_COORDINATES = 'This lane has no coordinates.';
  public static final String NO_ROUTE = 'No route was found between these places, even without truck limits.';
  private static final String FOUND = 'Found';
  private static final String NONE_FOUND = 'No route';

  @AuraEnabled
  public String status;
  @AuraEnabled
  public String routeType;
  /** The Miles_Source__c value this route stands for: Truck route, Regular route, No route; null when Unavailable. */
  @AuraEnabled
  public String source;
  @AuraEnabled
  public Decimal miles;
  @AuraEnabled
  public Decimal hours;
  @AuraEnabled
  public List<TruckRoute.Line> routes = new List<TruckRoute.Line>();
  @AuraEnabled
  public String mapUrl;
  @AuraEnabled
  public String message;
  /**
   * Set by RfpLaneController.laneRoute only: the lane as stored after its write step, whether the
   * route was written, was already on the lane or gave way to History miles, so the panel's miles
   * match the database. Null for an Unavailable route (no coordinates included) and for truckRoute.
   */
  @AuraEnabled
  public RFP_Lane__c lane;

  /** A view with no route: status Unavailable and the sentence to show. */
  public static TripRouteView unavailable(String message) {
    TripRouteView view = new TripRouteView();
    view.status = 'Unavailable';
    view.message = message;
    return view;
  }

  /**
   * The route from origin to destination for the default truck profile. A place without an Id or
   * a coordinate makes no callout. storedOrRoute makes the callouts (none when a stored row
   * answers); the store row is saved after them, so the transaction's first DML follows its last
   * callout. A row read from the store is not saved again: nothing about it changed. A save that
   * throws a DmlException (DUPLICATE_VALUE when two pricers store the same new route at the same
   * moment) does not stop the view: the route is still shown, and still written to the lane by
   * laneRoute; it is stored on a later open. Only the save sits in the try.
   */
  public static TripRouteView routeBetween(
    Pricing_Place__c origin,
    Pricing_Place__c destination,
    Boolean refresh
  ) {
    if (!located(origin) || !located(destination)) {
      return unavailable(NO_COORDINATES);
    }
    TripMilesService.RouteOutcome outcome = TripMilesService.storedOrRoute(
      origin,
      destination,
      TruckRoute.defaultProfile(),
      refresh == true
    );
    if (outcome.toSave != null && outcome.fromStore != true) {
      try {
        TripMilesService.save(new List<Truck_Route__c>{ outcome.toSave });
      } catch (DmlException e) {
        // Best effort: the route stays on screen. The status code only, never the row's values.
        System.debug(
          LoggingLevel.WARN,
          'TripRouteView: the truck route was not stored: ' + e.getDmlType(0)
        );
      }
    }
    TripRouteView view = fromResult(outcome.result);
    if (view.status == FOUND) {
      view.mapUrl = RouteMapUrl.build(
        point(origin),
        point(destination),
        view.routes
      );
    }
    return view;
  }

  /** The place a lane end routes from - its Id and coordinates - or null when the end has no place. */
  public static Pricing_Place__c laneEnd(Id placeId, Pricing_Place__c related) {
    if (placeId == null || related == null) {
      return null;
    }
    return new Pricing_Place__c(
      Id = placeId,
      Geolocation__Latitude__s = related.Geolocation__Latitude__s,
      Geolocation__Longitude__s = related.Geolocation__Longitude__s
    );
  }

  /**
   * The lane write a route makes, or null. History miles are billed PC*Miler miles and outrank a
   * route (R75); an unavailable route changes nothing (spec section 7); No route clears the miles
   * and the hours. A lane that already holds the route's miles, source and hours needs no write
   * (controller ruling). RfpLaneRouteService.writeLaneMiles passes the lane as read, FOR UPDATE,
   * right before its update.
   */
  public static RFP_Lane__c laneUpdate(RFP_Lane__c lane, TripRouteView view) {
    if (
      lane.Miles_Source__c == 'History' ||
      view.source == null ||
      holdsRoute(lane, view)
    ) {
      return null;
    }
    return new RFP_Lane__c(
      Id = lane.Id,
      Miles__c = view.miles,
      Miles_Source__c = view.source,
      Route_Hours__c = view.hours
    );
  }

  /** True when the lane already carries the view's miles, source and hours; null matches null. */
  private static Boolean holdsRoute(RFP_Lane__c lane, TripRouteView view) {
    return lane.Miles__c == view.miles &&
      view.source.equals(lane.Miles_Source__c) &&
      lane.Route_Hours__c == view.hours;
  }

  /** Found needs at least one line; anything that is neither Found nor No route reads as Unavailable. */
  private static TripRouteView fromResult(TruckRoute.Result result) {
    TripRouteView view = new TripRouteView();
    view.status = result.status;
    view.routeType = result.routeType;
    view.routes = result.routes == null
      ? new List<TruckRoute.Line>()
      : result.routes;
    if (result.status == FOUND && !view.routes.isEmpty()) {
      view.source = result.routeType == 'Regular'
        ? 'Regular route'
        : 'Truck route';
      view.miles = view.routes[0].miles;
      view.hours = view.routes[0].hours;
    } else if (result.status == NONE_FOUND) {
      view.source = NONE_FOUND;
      view.message = String.isBlank(result.message) ? NO_ROUTE : result.message;
    } else {
      view.status = 'Unavailable';
      view.routeType = null;
      view.message = TruckRoute.UNAVAILABLE;
    }
    return view;
  }

  private static Boolean located(Pricing_Place__c place) {
    return place != null &&
      place.Id != null &&
      place.Geolocation__Latitude__s != null &&
      place.Geolocation__Longitude__s != null;
  }

  private static TruckRoute.Point point(Pricing_Place__c place) {
    return new TruckRoute.Point(
      place.Geolocation__Latitude__s,
      place.Geolocation__Longitude__s
    );
  }
}
