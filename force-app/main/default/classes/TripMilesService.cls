/**
 * Trip miles for a lane (phase 7): the median of the billed miles a history search matched, an
 * approximate distance from the two places' coordinates, and the Mapbox truck route stored per
 * ordered place pair and truck profile in Truck_Route__c. Nothing here writes a lane: the callers
 * (RfpHistoryService, RfpLaneController.laneRoute, LaneBenchmarkController.truckRoute) decide what
 * a lane shows, and they save the route after their callouts, because storedOrRoute makes no DML.
 * Truck_Route__c is a shared cache of Mapbox results, not anyone's data: it is read in system mode
 * and only this class writes it, through Store, which runs without sharing (see its comment).
 */
public with sharing class TripMilesService {
  public static final Decimal EARTH_RADIUS_MI = 3958.7613;
  private static final String FOUND = 'Found';
  private static final String NO_ROUTE = 'No route';
  private static final Geo GEO = new Geo();
  private static final Store STORE = new Store();

  public class RouteOutcome {
    public TruckRoute.Result result;
    public Truck_Route__c toSave;
    public Boolean fromStore = false;
  }

  /**
   * Median of the billed miles of the loads behind the rows, one decimal. Each load counts once
   * (spec D1: the loads the search matched), however many quote rows it has, so a load quoted by
   * several carriers weighs no more than a load quoted once. A row counts when row.load has a
   * loadId and miles above zero: bid rows (no load Id), a row without a load group
   * (JSON.deserialize skips field initializers) and blank, zero or negative miles are skipped. Odd
   * count the middle value, even count the mean of the two middle values (LaneSearchService's
   * rule). Null when no load has miles.
   */
  public static Decimal medianMiles(List<LaneSearchResult.Row> rows) {
    if (rows == null) {
      return null;
    }
    Set<Id> seen = new Set<Id>();
    List<Decimal> miles = new List<Decimal>();
    for (LaneSearchResult.Row row : rows) {
      Id loadId = row?.load?.loadId;
      Decimal m = row?.load?.miles;
      if (loadId != null && m != null && m > 0 && seen.add(loadId)) {
        miles.add(m);
      }
    }
    if (miles.isEmpty()) {
      return null;
    }
    miles.sort();
    Integer n = miles.size();
    Decimal median = Math.mod(n, 2) == 1
      ? miles[n / 2]
      : (miles[n / 2 - 1] + miles[n / 2]) / 2;
    return median.setScale(1);
  }

  /**
   * Great-circle (haversine) miles between the two places times the profile's Approx factor, one
   * decimal. Null when a place or one of its coordinates is missing, or the profile has no factor.
   */
  public static Decimal approxMiles(
    Pricing_Place__c o,
    Pricing_Place__c d,
    TruckRoute.Profile p
  ) {
    if (
      !GEO.hasCoordinates(o) ||
      !GEO.hasCoordinates(d) ||
      p?.approxFactor == null
    ) {
      return null;
    }
    return (GEO.greatCircleMiles(o, d) * p.approxFactor).setScale(1);
  }

  /** '<origin place Id>:<destination place Id>:<profile key>'; direction matters. Null without both places. */
  public static String routeKey(
    Id originPlaceId,
    Id destinationPlaceId,
    TruckRoute.Profile p
  ) {
    if (originPlaceId == null || destinationPlaceId == null) {
      return null;
    }
    return String.valueOf(originPlaceId) +
      ':' +
      String.valueOf(destinationPlaceId) +
      ':' +
      p.key();
  }

  /**
   * The stored rows for routeKeys, by Route_Key__c. A row whose place was deleted (the lookups
   * clear on delete) no longer describes a place pair and is ignored. One query; none for an
   * empty set.
   */
  // System mode on purpose: Truck_Route__c is Public Read Only and both permission sets read it;
  // a stored route is a Mapbox result shared by everyone who prices, not a user's record.
  @SuppressWarnings('PMD.ApexCRUDViolation')
  public static Map<String, Truck_Route__c> storedRoutes(
    Set<String> routeKeys
  ) {
    Map<String, Truck_Route__c> byKey = new Map<String, Truck_Route__c>();
    if (routeKeys == null || routeKeys.isEmpty()) {
      return byKey;
    }
    for (Truck_Route__c row : [
      SELECT
        Id,
        Route_Key__c,
        Profile_Key__c,
        Origin_Place__c,
        Destination_Place__c,
        Miles__c,
        Hours__c,
        Route_Type__c,
        Status__c,
        Routes_Json__c,
        Checked_On__c
      FROM Truck_Route__c
      WHERE
        Route_Key__c IN :routeKeys
        AND Origin_Place__c != NULL
        AND Destination_Place__c != NULL
    ]) {
      byKey.put(row.Route_Key__c, row);
    }
    return byKey;
  }

  /** A stored row as a route result: its status, route type and the routes saved with it, main route first. */
  public static TruckRoute.Result fromStored(Truck_Route__c row) {
    TruckRoute.Result r = new TruckRoute.Result();
    r.status = row.Status__c;
    r.routeType = row.Route_Type__c;
    if (String.isNotBlank(row.Routes_Json__c)) {
      try {
        r.routes = (List<TruckRoute.Line>) JSON.deserialize(
          row.Routes_Json__c,
          List<TruckRoute.Line>.class
        );
      } catch (JSONException e) {
        r.routes = null;
      }
    }
    if (r.routes == null) {
      r.routes = new List<TruckRoute.Line>();
    }
    return r;
  }

  /**
   * The stored route for the ordered place pair and truck profile wins unless refresh; otherwise
   * one Mapbox route call (two with the regular fallback). toSave is the row to upsert for Found
   * and No route, never for Unavailable; the caller saves it after its callouts (no DML here). A
   * missing place, or a place without coordinates and no stored route, is Unavailable without a
   * callout.
   */
  public static RouteOutcome storedOrRoute(
    Pricing_Place__c o,
    Pricing_Place__c d,
    TruckRoute.Profile p,
    Boolean refresh
  ) {
    RouteOutcome out = new RouteOutcome();
    String key = routeKey(o?.Id, d?.Id, p);
    if (key == null) {
      out.result = unavailable();
      return out;
    }
    if (refresh != true) {
      Truck_Route__c stored = storedRoutes(new Set<String>{ key }).get(key);
      if (stored != null) {
        out.result = fromStored(stored);
        out.fromStore = true;
        return out;
      }
    }
    if (!GEO.hasCoordinates(o) || !GEO.hasCoordinates(d)) {
      out.result = unavailable();
      return out;
    }
    out.result = MapboxTruckRoute.route(GEO.point(o), GEO.point(d), p);
    if (out.result.status == FOUND || out.result.status == NO_ROUTE) {
      out.toSave = STORE.row(o.Id, d.Id, key, p, out.result);
    }
    return out;
  }

  /** Upserts route rows on Route_Key__c, so a refresh replaces the row; an empty list does nothing. */
  public static void save(List<Truck_Route__c> rows) {
    if (rows == null || rows.isEmpty()) {
      return;
    }
    STORE.upsertRows(rows);
  }

  private static TruckRoute.Result unavailable() {
    TruckRoute.Result r = new TruckRoute.Result();
    r.status = 'Unavailable';
    r.message = TruckRoute.UNAVAILABLE;
    return r;
  }

  /** Coordinates of a place, and the great-circle distance between two. */
  private class Geo {
    private Boolean hasCoordinates(Pricing_Place__c place) {
      return place != null &&
        place.Geolocation__Latitude__s != null &&
        place.Geolocation__Longitude__s != null;
    }

    private TruckRoute.Point point(Pricing_Place__c place) {
      return new TruckRoute.Point(
        place.Geolocation__Latitude__s,
        place.Geolocation__Longitude__s
      );
    }

    /** Haversine miles on a sphere of EARTH_RADIUS_MI; both places must have coordinates. */
    private Decimal greatCircleMiles(Pricing_Place__c o, Pricing_Place__c d) {
      Double lat1 = radians(o.Geolocation__Latitude__s);
      Double lat2 = radians(d.Geolocation__Latitude__s);
      Double dLng = radians(
        d.Geolocation__Longitude__s - o.Geolocation__Longitude__s
      );
      Double h =
        Math.pow(Math.sin((lat2 - lat1) / 2), 2) +
        Math.cos(lat1) * Math.cos(lat2) * Math.pow(Math.sin(dLng / 2), 2);
      return Decimal.valueOf(
        2 * EARTH_RADIUS_MI.doubleValue() * Math.asin(Math.sqrt(h))
      );
    }

    private Double radians(Decimal degrees) {
      return degrees.doubleValue() * Math.PI / 180;
    }
  }

  /**
   * Without sharing on purpose, and only for writing Truck_Route__c. The object is Public Read
   * Only, so under the outer class's sharing a pricer refreshing a route a colleague saved would
   * fail on the update (the row belongs to whoever opened the lane first). The permission sets
   * grant read only, so the write also runs in system mode past object permissions; every row
   * comes from row() below, built from a Mapbox answer for two places the caller has already read.
   */
  private without sharing class Store {
    /** The row for a Found or No route result; a Found result without routes is stored as No route. */
    private Truck_Route__c row(
      Id originId,
      Id destinationId,
      String key,
      TruckRoute.Profile p,
      TruckRoute.Result r
    ) {
      Boolean isFound = r.status == FOUND && !r.routes.isEmpty();
      TruckRoute.Line main = isFound ? r.routes[0] : new TruckRoute.Line();
      return new Truck_Route__c(
        Origin_Place__c = originId,
        Destination_Place__c = destinationId,
        Profile_Key__c = p.key(),
        Route_Key__c = key,
        Status__c = isFound ? FOUND : NO_ROUTE,
        Route_Type__c = isFound ? r.routeType : null,
        Miles__c = main.miles,
        Hours__c = main.hours,
        Routes_Json__c = JSON.serialize(
          isFound ? r.routes : new List<TruckRoute.Line>()
        ),
        Checked_On__c = System.now()
      );
    }

    @SuppressWarnings('PMD.ApexCRUDViolation')
    private void upsertRows(List<Truck_Route__c> rows) {
      Database.upsert(
        rows,
        Truck_Route__c.Route_Key__c,
        true,
        AccessLevel.SYSTEM_MODE
      );
    }
  }
}
