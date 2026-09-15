/**
 * Truck routes from the Mapbox Directions API (phase 7, spec §3, R79): profile mapbox/driving with the truck's
 * height and width (metres) and weight (metric tons), alternatives from the profile, simplified polyline5 geometry.
 * When the main truck route breaks a truck limit (a violation notification with subtype maxHeight, maxWidth or
 * maxWeight on one of its legs) or Mapbox finds no truck route, one more request without the truck limits asks for
 * a regular driving route, returned as routeType 'Regular'; when that finds nothing either, the status is 'No route'.
 * A truck alternative that breaks a limit is left out: no partially compliant truck route is ever returned.
 * A blank token, a point without coordinates, an HTTP error, a callout failure or an unreadable answer is
 * 'Unavailable' with TruckRoute.UNAVAILABLE; a failure inside the requests is logged at WARN with its exception type
 * only. The token only ever appears in the request URL. No DML.
 */
public with sharing class MapboxTruckRoute {
  private static final Decimal METRES_PER_MILE = 1609.344;
  private static final Decimal SECONDS_PER_HOUR = 3600;
  private static final Integer MAX_ROUTES = 3;
  private static final Set<String> TRUCK_LIMITS = new Set<String>{
    'maxHeight',
    'maxWidth',
    'maxWeight'
  };

  public static TruckRoute.Result route(
    TruckRoute.Point origin,
    TruckRoute.Point destination,
    TruckRoute.Profile profile
  ) {
    String token = MapboxHttp.token();
    if (
      String.isBlank(token) ||
      !located(origin) ||
      !located(destination) ||
      profile == null
    ) {
      return unavailable();
    }
    try {
      List<Object> truckRoutes = ask(origin, destination, profile, true, token);
      if (!truckRoutes.isEmpty() && !breaksTruckLimit(truckRoutes[0])) {
        return found('Truck', truckRoutes);
      }
      List<Object> regularRoutes = ask(
        origin,
        destination,
        profile,
        false,
        token
      );
      return regularRoutes.isEmpty()
        ? noRoute()
        : found('Regular', regularRoutes);
    } catch (Exception e) {
      // MapboxException (HTTP error or callout failure), JSONException or a cast on an unexpected answer.
      // The type name only: a callout failure's message can carry the request URL, token included.
      System.debug(
        LoggingLevel.WARN,
        'Mapbox truck route failed: ' + e.getTypeName()
      );
      return unavailable();
    }
  }

  /** The routes of one Directions answer, main first; empty when the answer's code is not Ok (NoRoute, NoSegment). */
  private static List<Object> ask(
    TruckRoute.Point origin,
    TruckRoute.Point destination,
    TruckRoute.Profile profile,
    Boolean truck,
    String token
  ) {
    HttpRequest req = new HttpRequest();
    req.setEndpoint(endpoint(origin, destination, profile, truck, token));
    req.setMethod('GET');
    if (profile.timeoutMs != null) {
      req.setTimeout(profile.timeoutMs);
    }
    HttpResponse res = MapboxHttp.send(req);
    if (res.getStatusCode() != 200) {
      throw new MapboxException(
        'Mapbox routing failed: HTTP ' + res.getStatusCode()
      );
    }
    Map<String, Object> answer = (Map<String, Object>) JSON.deserializeUntyped(
      res.getBody()
    );
    if (String.valueOf(answer.get('code')) != 'Ok') {
      return new List<Object>();
    }
    return listOf(answer.get('routes'));
  }

  /** The truck request adds max_height, max_width, max_weight and notifications=all; the regular request has none of them. */
  private static String endpoint(
    TruckRoute.Point origin,
    TruckRoute.Point destination,
    TruckRoute.Profile profile,
    Boolean truck,
    String token
  ) {
    String url =
      MapboxHttp.BASE +
      '/directions/v5/mapbox/driving/' +
      coordinates(origin) +
      ';' +
      coordinates(destination) +
      '?alternatives=' +
      (profile.alternatives == true) +
      '&overview=simplified&geometries=polyline&steps=false';
    if (truck) {
      url +=
        '&max_height=' +
        twoDecimals(profile.heightM) +
        '&max_width=' +
        twoDecimals(profile.widthM) +
        '&max_weight=' +
        twoDecimals(profile.weightT) +
        '&notifications=all';
    }
    return url + '&access_token=' + token;
  }

  /** True when a leg of the route carries a violation of the truck's height, width or weight. */
  private static Boolean breaksTruckLimit(Object route) {
    for (Object leg : listOf(((Map<String, Object>) route).get('legs'))) {
      for (
        Object item : listOf(((Map<String, Object>) leg).get('notifications'))
      ) {
        Map<String, Object> notification = (Map<String, Object>) item;
        if (
          String.valueOf(notification.get('type')) == 'violation' &&
          TRUCK_LIMITS.contains(String.valueOf(notification.get('subtype')))
        ) {
          return true;
        }
      }
    }
    return false;
  }

  /** Up to MAX_ROUTES routes, main first; a truck alternative that breaks a limit is left out. */
  private static TruckRoute.Result found(
    String routeType,
    List<Object> routes
  ) {
    TruckRoute.Result result = new TruckRoute.Result();
    result.status = 'Found';
    result.routeType = routeType;
    for (Object route : routes) {
      Boolean keep =
        result.routes.size() < MAX_ROUTES &&
        !(routeType == 'Truck' && breaksTruckLimit(route));
      if (keep) {
        result.routes.add(line((Map<String, Object>) route));
      }
    }
    return result;
  }

  /** Metres to miles and seconds to hours, one decimal; a route without either makes the answer unreadable. */
  private static TruckRoute.Line line(Map<String, Object> route) {
    Object distance = route.get('distance');
    Object duration = route.get('duration');
    if (distance == null || duration == null) {
      throw new MapboxException(
        'Mapbox answered a route without distance or duration'
      );
    }
    TruckRoute.Line out = new TruckRoute.Line();
    out.miles = (decimalOf(distance) / METRES_PER_MILE).setScale(1);
    out.hours = (decimalOf(duration) / SECONDS_PER_HOUR).setScale(1);
    Object geometry = route.get('geometry');
    out.polyline5 = geometry instanceof String ? (String) geometry : null;
    return out;
  }

  private static TruckRoute.Result noRoute() {
    TruckRoute.Result result = new TruckRoute.Result();
    result.status = 'No route';
    return result;
  }

  private static TruckRoute.Result unavailable() {
    TruckRoute.Result result = new TruckRoute.Result();
    result.status = 'Unavailable';
    result.message = TruckRoute.UNAVAILABLE;
    return result;
  }

  private static Boolean located(TruckRoute.Point p) {
    return p != null && p.lat != null && p.lng != null;
  }

  /** 'lng,lat' with 6 decimals (about 0.1 m), the order the Directions API expects. */
  private static String coordinates(TruckRoute.Point p) {
    return p.lng.setScale(6).toPlainString() +
      ',' +
      p.lat.setScale(6).toPlainString();
  }

  private static String twoDecimals(Decimal value) {
    return value.setScale(2).toPlainString();
  }

  private static Decimal decimalOf(Object value) {
    return Decimal.valueOf(String.valueOf(value));
  }

  private static List<Object> listOf(Object value) {
    return value instanceof List<Object>
      ? (List<Object>) value
      : new List<Object>();
  }
}
