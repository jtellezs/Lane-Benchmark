/**
 * The Mapbox Static Images URL of a lane's truck route: a pin on each place, the main route as a
 * thick blue line and up to two alternatives (amber, then grey) under it. It sits next to
 * MapboxGeocoder.staticMapUrl and uses the same style, framing and token. Mapbox refuses URLs
 * longer than 8,192 characters, so this class keeps the URL under 8,000: every drawn route climbs
 * a Douglas-Peucker tolerance ladder until the URL fits; when three or two routes still do not fit
 * at 0.03 degrees, the last alternative is dropped; the main route alone keeps climbing until it
 * fits, so it is never missing. Polylines are Google's precision-5 format, which the Directions
 * API returns with geometries=polyline. The URL carries the public token: it is built for each
 * view, never stored and never logged.
 */
public with sharing class RouteMapUrl {
  private static final Integer MAX_URL_LENGTH = 8000;
  private static final Decimal E5 = 100000;
  private static final String STYLE_PATH = '/styles/v1/mapbox/streets-v12/static/';
  private static final String FRAME = '/auto/600x300@2x?padding=40&access_token=';
  private static final List<String> PATH_STYLES = new List<String>{
    'path-5+0070d2-0.9',
    'path-3+f59e0b-0.8',
    'path-3+706e6b-0.7'
  };
  // Degrees (0.0001 is about 11 m). Rungs 1 to SHARED_RUNGS (up to 0.03, about 3.3 km) are tried
  // while alternatives are drawn; the main route alone climbs on to 1,000, where only its two
  // endpoints are left, so the ladder always ends with a URL that fits.
  private static final List<Decimal> TOLERANCES = new List<Decimal>{
    0.0001,
    0.0003,
    0.001,
    0.003,
    0.01,
    0.03,
    0.1,
    0.3,
    1,
    3,
    10,
    30,
    100,
    1000
  };
  private static final Integer SHARED_RUNGS = 6;

  /** The static map URL, or null without a token or without coordinates for both places. */
  public static String build(
    TruckRoute.Point origin,
    TruckRoute.Point destination,
    List<TruckRoute.Line> routes
  ) {
    String token = MapboxHttp.token();
    if (
      String.isBlank(token) ||
      !hasCoordinates(origin) ||
      !hasCoordinates(destination)
    ) {
      return null;
    }
    String pins =
      'pin-s-a+0070d2(' +
      lngLat(origin) +
      '),pin-s-b+2e844a(' +
      lngLat(destination) +
      ')';
    List<Ladder> ladders = laddersOf(routes);
    for (
      Integer keep = Math.min(ladders.size(), PATH_STYLES.size());
      keep > 0;
      keep--
    ) {
      String url = fitting(token, pins, ladders, keep);
      if (url != null) {
        return url;
      }
    }
    return compose(token, pins, new List<String>());
  }

  private static Boolean hasCoordinates(TruckRoute.Point point) {
    return point != null && point.lat != null && point.lng != null;
  }

  /** 'lng,lat' with at most five decimals and no trailing zeros. */
  private static String lngLat(TruckRoute.Point point) {
    return point.lng.setScale(5, System.RoundingMode.HALF_UP)
        .stripTrailingZeros()
        .toPlainString() +
      ',' +
      point.lat.setScale(5, System.RoundingMode.HALF_UP)
        .stripTrailingZeros()
        .toPlainString();
  }

  private static List<Ladder> laddersOf(List<TruckRoute.Line> routes) {
    List<Ladder> ladders = new List<Ladder>();
    if (routes == null) {
      return ladders;
    }
    for (TruckRoute.Line line : routes) {
      if (line != null && String.isNotBlank(line.polyline5)) {
        ladders.add(new Ladder(line.polyline5));
      }
    }
    return ladders;
  }

  /** The URL with the first `keep` routes at the lowest rung that fits, or null when no rung does. */
  private static String fitting(
    String token,
    String pins,
    List<Ladder> ladders,
    Integer keep
  ) {
    Integer topRung = keep == 1 ? TOLERANCES.size() : SHARED_RUNGS;
    for (Integer rung = 0; rung <= topRung; rung++) {
      List<String> lines = new List<String>();
      for (Integer i = 0; i < keep; i++) {
        lines.add(ladders[i].at(rung));
      }
      String url = compose(token, pins, lines);
      if (url.length() < MAX_URL_LENGTH) {
        return url;
      }
    }
    return null;
  }

  /** Alternatives first, then the main route, then the pins: Mapbox draws later overlays on top. */
  private static String compose(
    String token,
    String pins,
    List<String> urlEncodedLines
  ) {
    List<String> overlays = new List<String>();
    for (Integer i = urlEncodedLines.size() - 1; i >= 0; i--) {
      overlays.add(PATH_STYLES[i] + '(' + urlEncodedLines[i] + ')');
    }
    overlays.add(pins);
    return MapboxHttp.BASE +
      STYLE_PATH +
      String.join(overlays, ',') +
      FRAME +
      token;
  }

  /** [lat, lng] pairs at scale 5; stops before a value the string cuts off; empty for null or blank. */
  @TestVisible
  static List<List<Decimal>> decode(String polyline5) {
    List<List<Decimal>> points = new List<List<Decimal>>();
    PolylineReader reader = new PolylineReader(polyline5);
    Long lat = 0;
    Long lng = 0;
    while (reader.hasMore()) {
      Long latDelta = reader.nextValue();
      Long lngDelta = reader.nextValue();
      if (latDelta == null || lngDelta == null) {
        break;
      }
      lat += latDelta;
      lng += lngDelta;
      points.add(
        new List<Decimal>{
          Decimal.valueOf(lat).divide(E5, 5),
          Decimal.valueOf(lng).divide(E5, 5)
        }
      );
    }
    return points;
  }

  /** Google's encoded polyline, precision 5, of [lat, lng] pairs. */
  @TestVisible
  static String encode(List<List<Decimal>> latLngPoints) {
    List<Integer> chars = new List<Integer>();
    Long lastLat = 0;
    Long lastLng = 0;
    for (List<Decimal> point : latLngPoints) {
      // HALF_UP rounds half away from zero, as Mapbox's polyline library does; Apex's default
      // Decimal rounding is HALF_EVEN, which would move some sixth-decimal halves the other way.
      Long lat = (point[0] * E5).round(System.RoundingMode.HALF_UP);
      Long lng = (point[1] * E5).round(System.RoundingMode.HALF_UP);
      appendValue(chars, lat - lastLat);
      appendValue(chars, lng - lastLng);
      lastLat = lat;
      lastLng = lng;
    }
    return String.fromCharArray(chars);
  }

  /** One signed value: zig-zag (a negative value becomes odd), then 5-bit chunks, low bits first, each plus 63. */
  private static void appendValue(List<Integer> chars, Long value) {
    Long rest = value < 0 ? -(value << 1) - 1 : value << 1;
    while (rest >= 32) {
      chars.add((32 + Math.mod(rest, 32)).intValue() + 63);
      rest = rest >> 5;
    }
    chars.add(rest.intValue() + 63);
  }

  /** Douglas-Peucker over lat/lng degrees; the input comes back unchanged when there is nothing to drop. */
  @TestVisible
  static List<List<Decimal>> simplify(
    List<List<Decimal>> points,
    Decimal toleranceDegrees
  ) {
    Boolean nothingToDrop =
      points == null ||
      points.size() < 3 ||
      toleranceDegrees == null ||
      toleranceDegrees <= 0;
    if (nothingToDrop) {
      return points;
    }
    return new Simplifier(points, toleranceDegrees).run(points);
  }

  /** One route's URL-encoded polyline at each rung of the tolerance ladder, computed once and cached. */
  private class Ladder {
    private String original;
    private List<List<Decimal>> points;
    private List<String> rungs = new List<String>();

    Ladder(String polyline5) {
      original = polyline5;
      rungs.add(EncodingUtil.urlEncode(polyline5, 'UTF-8'));
    }

    String at(Integer rung) {
      while (rungs.size() <= rung) {
        if (points == null) {
          points = decode(original);
        }
        points = simplify(points, TOLERANCES[rungs.size() - 1]);
        rungs.add(EncodingUtil.urlEncode(encode(points), 'UTF-8'));
      }
      return rungs[rung];
    }
  }

  /**
   * Reads the signed values of a precision-5 polyline one at a time, with charAt: String.getChars
   * turns a backslash and the letters after it into an escaped character (a Salesforce System Error
   * when they are not a valid escape), and a polyline can hold a backslash (a final chunk of 29).
   */
  private class PolylineReader {
    private String text;
    private Integer index = 0;

    PolylineReader(String polyline5) {
      text = String.isBlank(polyline5) ? '' : polyline5;
    }

    Boolean hasMore() {
      return index < text.length();
    }

    /** The next value, or null when the string ends inside it. */
    Long nextValue() {
      Long result = 0;
      Integer shift = 0;
      Integer chunk = 32;
      while (chunk >= 32) {
        if (index >= text.length()) {
          return null;
        }
        chunk = text.charAt(index) - 63;
        index++;
        Long bits = chunk & 31;
        result += bits << shift;
        shift += 5;
      }
      return Math.mod(result, 2) == 1 ? -(result >> 1) - 1 : result >> 1;
    }
  }

  /**
   * Douglas-Peucker with an explicit stack (Apex caps recursion depth at 1,000 calls). Distances are
   * squared, in degrees, on Doubles: Decimal arithmetic is far slower and a route has thousands of
   * points. A point's distance is to the infinite line through the segment's ends, or to the first
   * end when both ends are the same place.
   */
  private class Simplifier {
    private List<Double> lats = new List<Double>();
    private List<Double> lngs = new List<Double>();
    private Double tolerance2;

    Simplifier(List<List<Decimal>> points, Decimal toleranceDegrees) {
      for (List<Decimal> point : points) {
        lats.add(point[0].doubleValue());
        lngs.add(point[1].doubleValue());
      }
      tolerance2 =
        toleranceDegrees.doubleValue() * toleranceDegrees.doubleValue();
    }

    List<List<Decimal>> run(List<List<Decimal>> points) {
      Integer lastIndex = points.size() - 1;
      Set<Integer> kept = new Set<Integer>{ 0, lastIndex };
      List<Integer> stack = new List<Integer>{ 0, lastIndex };
      while (!stack.isEmpty()) {
        Integer endIndex = stack.remove(stack.size() - 1);
        Integer startIndex = stack.remove(stack.size() - 1);
        Integer farIndex = farthest(startIndex, endIndex);
        if (farIndex != null) {
          kept.add(farIndex);
          stack.addAll(
            new List<Integer>{ startIndex, farIndex, farIndex, endIndex }
          );
        }
      }
      List<List<Decimal>> result = new List<List<Decimal>>();
      for (Integer i = 0; i <= lastIndex; i++) {
        if (kept.contains(i)) {
          result.add(points[i]);
        }
      }
      return result;
    }

    /** The index strictly between the two ends farthest from their line, or null when all are within the tolerance. */
    private Integer farthest(Integer startIndex, Integer endIndex) {
      Double lat0 = lats[startIndex];
      Double lng0 = lngs[startIndex];
      Double dLat = lats[endIndex] - lat0;
      Double dLng = lngs[endIndex] - lng0;
      Double length2 = dLat * dLat + dLng * dLng;
      Double best = tolerance2;
      Integer bestIndex;
      for (Integer i = startIndex + 1; i < endIndex; i++) {
        Double pLat = lats[i] - lat0;
        Double pLng = lngs[i] - lng0;
        Double cross = pLng * dLat - pLat * dLng;
        Double distance2 = length2 > 0
          ? cross * cross / length2
          : pLat * pLat + pLng * pLng;
        if (distance2 > best) {
          best = distance2;
          bestIndex = i;
        }
      }
      return bestIndex;
    }
  }
}
