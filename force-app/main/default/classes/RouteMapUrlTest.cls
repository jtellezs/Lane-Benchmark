@IsTest
private class RouteMapUrlTest {
  private static final String GOOGLE_EXAMPLE = '_p~iF~ps|U_ulLnnqC_mqNvxq`@';
  private static final String MAIN = 'path-5+0070d2-0.9';
  private static final String AMBER = 'path-3+f59e0b-0.8';
  private static final String GREY = 'path-3+706e6b-0.7';
  private static final TruckRoute.Point MONTREAL = new TruckRoute.Point(
    45.5019,
    -73.5674
  );
  private static final TruckRoute.Point TORONTO = new TruckRoute.Point(
    43.6532,
    -79.3832
  );

  private static List<Decimal> p(Decimal lat, Decimal lng) {
    return new List<Decimal>{ lat, lng };
  }

  private static TruckRoute.Line line(String polyline5) {
    TruckRoute.Line route = new TruckRoute.Line();
    route.polyline5 = polyline5;
    return route;
  }

  /** n points from Montréal to Toronto bowed north (bow above zero) or south by bow degrees: a smooth arc. */
  private static List<List<Decimal>> arc(Integer n, Decimal bow) {
    Double lat0 = MONTREAL.lat.doubleValue();
    Double lng0 = MONTREAL.lng.doubleValue();
    Double latSpan = TORONTO.lat.doubleValue() - lat0;
    Double lngSpan = TORONTO.lng.doubleValue() - lng0;
    Double bowDegrees = bow.doubleValue();
    Double steps = n - 1;
    List<List<Decimal>> points = new List<List<Decimal>>();
    for (Integer i = 0; i < n; i++) {
      Double t = i / steps;
      points.add(
        p(
          Decimal.valueOf(
              lat0 + latSpan * t + bowDegrees * Math.sin(Math.PI * t)
            )
            .setScale(5),
          Decimal.valueOf(lng0 + lngSpan * t).setScale(5)
        )
      );
    }
    return points;
  }

  /** n points scattered up to one degree around (44.5, -76.5) by a fixed pseudo-random sequence (MINSTD). */
  private static List<List<Decimal>> scatter(Integer n) {
    List<List<Decimal>> points = new List<List<Decimal>>();
    Long seed = 42;
    for (Integer i = 0; i < n; i++) {
      seed = Math.mod(seed * 48271, 2147483647);
      Decimal lat =
        44.5 +
        Decimal.valueOf(Math.mod(seed, 200001) - 100000).divide(100000, 5);
      seed = Math.mod(seed * 48271, 2147483647);
      Decimal lng =
        -76.5 +
        Decimal.valueOf(Math.mod(seed, 200001) - 100000).divide(100000, 5);
      points.add(p(lat, lng));
    }
    return points;
  }

  /** The URL-decoded polyline inside the overlay with this style, or null when the URL has none. */
  private static String overlay(String url, String style) {
    Integer start = url.indexOf(style + '(');
    if (start < 0) {
      return null;
    }
    start += style.length() + 1;
    return EncodingUtil.urlDecode(
      url.substring(start, url.indexOf(')', start)),
      'UTF-8'
    );
  }

  @IsTest
  static void decodeReadsGooglesExampleAndEncodeWritesItBack() {
    List<List<Decimal>> points = RouteMapUrl.decode(GOOGLE_EXAMPLE);
    System.assertEquals(3, points.size());
    System.assertEquals(p(38.50000, -120.20000), points[0]);
    System.assertEquals(p(40.70000, -120.95000), points[1]);
    System.assertEquals(p(43.25200, -126.45300), points[2]);
    System.assertEquals(GOOGLE_EXAMPLE, RouteMapUrl.encode(points));
    System.assertEquals(
      GOOGLE_EXAMPLE,
      RouteMapUrl.encode(
        new List<List<Decimal>>{
          p(38.5, -120.2),
          p(40.7, -120.95),
          p(43.252, -126.453)
        }
      ),
      'the scale of the input does not change the encoding'
    );
  }

  @IsTest
  static void negativeAndZeroCoordinatesRoundTrip() {
    List<List<Decimal>> points = new List<List<Decimal>>{
      p(-33.86882, 151.20929),
      p(0.00000, 0.00000),
      p(51.50735, -0.12776)
    };
    String encoded = RouteMapUrl.encode(points);
    System.assertEquals('b_vmEaa|y[c_vmE`a|y[}_kyHn}W', encoded);
    System.assertEquals(points, RouteMapUrl.decode(encoded));
    System.assertEquals(
      'A@',
      RouteMapUrl.encode(new List<List<Decimal>>{ p(0.000005, -0.000005) }),
      'a half at the sixth decimal rounds away from zero, as Mapbox does'
    );
    List<List<Decimal>> backslashU = new List<List<Decimal>>{
      p(-0.00015, 0.00027)
    };
    System.assertEquals('\\u@', RouteMapUrl.encode(backslashU));
    System.assertEquals(
      backslashU,
      RouteMapUrl.decode('\\u@'),
      'a backslash in a polyline is a character, not the start of an escape'
    );
  }

  @IsTest
  static void decodeStopsAtACutValueAndReadsNothingFromBlank() {
    System.assertEquals(
      new List<List<Decimal>>{ p(38.50000, -120.20000) },
      RouteMapUrl.decode('_p~iF~ps|U_ulL'),
      'a latitude without its longitude is not a point'
    );
    System.assertEquals(
      new List<List<Decimal>>{ p(38.50000, -120.20000) },
      RouteMapUrl.decode('_p~iF~ps|U_ul'),
      'a value cut inside its chunks is not read'
    );
    System.assertEquals(0, RouteMapUrl.decode('').size());
    System.assertEquals(0, RouteMapUrl.decode(null).size());
  }

  @IsTest
  static void simplifyKeepsTheEndsAndCornersAndDropsCollinearPoints() {
    List<List<Decimal>> straight = new List<List<Decimal>>{
      p(45, -73),
      p(45, -74),
      p(45, -75),
      p(45, -76)
    };
    System.assertEquals(
      new List<List<Decimal>>{ straight[0], straight[3] },
      RouteMapUrl.simplify(straight, 0.0001)
    );
    List<List<Decimal>> corner = new List<List<Decimal>>{
      p(0, 0),
      p(0, 1),
      p(0, 2),
      p(1, 2),
      p(2, 2)
    };
    System.assertEquals(
      new List<List<Decimal>>{ corner[0], corner[2], corner[4] },
      RouteMapUrl.simplify(corner, 0.01)
    );
    List<List<Decimal>> bump = new List<List<Decimal>>{
      p(45, -73),
      p(45.00005, -74),
      p(45, -75)
    };
    System.assertEquals(
      2,
      RouteMapUrl.simplify(bump, 0.0001).size(),
      'a bump under the tolerance goes'
    );
    System.assertEquals(
      3,
      RouteMapUrl.simplify(bump, 0.00001).size(),
      'a bump over the tolerance stays'
    );
    List<List<Decimal>> outAndBack = new List<List<Decimal>>{
      p(45, -73),
      p(46, -73.5),
      p(45, -73)
    };
    System.assertEquals(
      3,
      RouteMapUrl.simplify(outAndBack, 0.01).size(),
      'a route back to its start keeps its far point'
    );
    System.assertEquals(corner, RouteMapUrl.simplify(corner, 0));
    System.assertEquals(corner, RouteMapUrl.simplify(corner, null));
    System.assertEquals(
      2,
      RouteMapUrl.simplify(new List<List<Decimal>>{ p(1, 1), p(2, 2) }, 1)
        .size()
    );
    System.assertEquals(null, RouteMapUrl.simplify(null, 1));
  }

  @IsTest
  static void buildDrawsTwoPinsAndThreeColouredRoutes() {
    MapboxHttp.tokenOverride = 'pk.test';
    String url = RouteMapUrl.build(
      MONTREAL,
      TORONTO,
      new List<TruckRoute.Line>{
        line(GOOGLE_EXAMPLE),
        line(GOOGLE_EXAMPLE),
        line(GOOGLE_EXAMPLE),
        line(GOOGLE_EXAMPLE)
      }
    );
    String polyline = '(_p%7EiF%7Eps%7CU_ulLnnqC_mqNvxq%60%40)';
    System.assert(
      url.startsWith(
        'https://api.mapbox.com/styles/v1/mapbox/streets-v12/static/'
      ),
      url
    );
    System.assert(url.contains(MAIN + polyline), url);
    System.assert(url.contains(AMBER + polyline), url);
    System.assert(url.contains(GREY + polyline), url);
    System.assertEquals(
      3,
      url.countMatches('path-'),
      'a fourth route is not drawn'
    );
    System.assert(url.contains('pin-s-a+0070d2(-73.5674,45.5019)'), url);
    System.assert(url.contains('pin-s-b+2e844a(-79.3832,43.6532)'), url);
    System.assert(
      url.endsWith('/auto/600x300@2x?padding=40&access_token=pk.test'),
      url
    );
    System.assert(
      url.indexOf(GREY) < url.indexOf(AMBER) &&
        url.indexOf(AMBER) < url.indexOf(MAIN) &&
        url.indexOf(MAIN) < url.indexOf('pin-s-a'),
      'alternatives under the main route, pins on top: ' + url
    );
  }

  @IsTest
  static void buildSkipsEmptyRoutesAndDrawsPinsOnlyWithoutRoutes() {
    MapboxHttp.tokenOverride = 'pk.test';
    String url = RouteMapUrl.build(
      MONTREAL,
      TORONTO,
      new List<TruckRoute.Line>{
        line(GOOGLE_EXAMPLE),
        null,
        line(''),
        line(GOOGLE_EXAMPLE)
      }
    );
    System.assertEquals(2, url.countMatches('path-'), url);
    System.assert(url.contains(MAIN + '('), url);
    System.assert(url.contains(AMBER + '('), url);
    String pinsOnly =
      'https://api.mapbox.com/styles/v1/mapbox/streets-v12/static/' +
      'pin-s-a+0070d2(-73.5674,45.5019),pin-s-b+2e844a(-79.3832,43.6532)' +
      '/auto/600x300@2x?padding=40&access_token=pk.test';
    System.assertEquals(pinsOnly, RouteMapUrl.build(MONTREAL, TORONTO, null));
    System.assertEquals(
      pinsOnly,
      RouteMapUrl.build(MONTREAL, TORONTO, new List<TruckRoute.Line>())
    );
  }

  @IsTest
  static void buildReturnsNullWithoutATokenOrCoordinates() {
    MapboxHttp.tokenOverride = null;
    TPRO_KPI__c settings = TPRO_KPI__c.getOrgDefaults();
    settings.Mapbox_Api_Key__c = null;
    upsert settings;
    List<TruckRoute.Line> routes = new List<TruckRoute.Line>{
      line(GOOGLE_EXAMPLE)
    };
    System.assertEquals(null, RouteMapUrl.build(MONTREAL, TORONTO, routes));
    MapboxHttp.tokenOverride = 'pk.test';
    System.assertEquals(null, RouteMapUrl.build(null, TORONTO, routes));
    System.assertEquals(
      null,
      RouteMapUrl.build(MONTREAL, new TruckRoute.Point(43.6532, null), routes)
    );
  }

  @IsTest
  static void longRoutesAreSimplifiedUnderTheLimitAndAllThreeStay() {
    MapboxHttp.tokenOverride = 'pk.test';
    List<List<Decimal>> north = arc(3000, 0.4);
    String mainRoute = RouteMapUrl.encode(north);
    String farNorth = RouteMapUrl.encode(arc(3000, 0.8));
    String south = RouteMapUrl.encode(arc(3000, -0.4));
    System.assert(
      mainRoute.length() > 8000,
      'each route alone is over the limit before simplification: ' +
      mainRoute.length()
    );
    Test.startTest();
    String url = RouteMapUrl.build(
      MONTREAL,
      TORONTO,
      new List<TruckRoute.Line>{ line(mainRoute), line(farNorth), line(south) }
    );
    Test.stopTest();
    System.assert(url.length() < 8000, 'URL length ' + url.length());
    System.assertNotEquals(null, overlay(url, AMBER), url);
    System.assertNotEquals(null, overlay(url, GREY), url);
    List<List<Decimal>> drawn = RouteMapUrl.decode(overlay(url, MAIN));
    System.assert(
      drawn.size() > 2 && drawn.size() < 3000,
      'simplified, not flattened: ' + drawn.size()
    );
    System.assertEquals(north[0], drawn[0], 'starts at Montréal');
    System.assertEquals(
      north[2999],
      drawn[drawn.size() - 1],
      'ends at Toronto'
    );
  }

  @IsTest
  static void anAlternativeThatCannotFitIsDroppedBeforeTheOthers() {
    MapboxHttp.tokenOverride = 'pk.test';
    String mainRoute = RouteMapUrl.encode(arc(3000, 0.4));
    String farNorth = RouteMapUrl.encode(arc(3000, 0.8));
    String scattered = RouteMapUrl.encode(scatter(1000));
    System.assert(
      EncodingUtil.urlEncode(scattered, 'UTF-8').length() > 8000,
      'the scattered route cannot fit even alone at full precision'
    );
    Test.startTest();
    String url = RouteMapUrl.build(
      MONTREAL,
      TORONTO,
      new List<TruckRoute.Line>{
        line(mainRoute),
        line(farNorth),
        line(scattered)
      }
    );
    Test.stopTest();
    System.assert(url.length() < 8000, 'URL length ' + url.length());
    System.assertNotEquals(null, overlay(url, MAIN), url);
    System.assertNotEquals(null, overlay(url, AMBER), url);
    System.assertEquals(
      null,
      overlay(url, GREY),
      'the last alternative is dropped'
    );
  }

  @IsTest
  static void aMainRouteAloneIsSimplifiedUntilItFits() {
    MapboxHttp.tokenOverride = 'pk.test';
    List<List<Decimal>> points = scatter(1000);
    Test.startTest();
    String url = RouteMapUrl.build(
      MONTREAL,
      TORONTO,
      new List<TruckRoute.Line>{ line(RouteMapUrl.encode(points)) }
    );
    Test.stopTest();
    System.assert(url.length() < 8000, 'URL length ' + url.length());
    List<List<Decimal>> drawn = RouteMapUrl.decode(overlay(url, MAIN));
    System.assert(
      drawn.size() >= 2 && drawn.size() < 1000,
      'simplified: ' + drawn.size()
    );
    System.assertEquals(points[0], drawn[0], 'the route keeps its start');
    System.assertEquals(
      points[999],
      drawn[drawn.size() - 1],
      'the route keeps its end'
    );
  }
}
