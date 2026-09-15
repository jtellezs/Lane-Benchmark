@IsTest
private class MapboxTruckRouteTest {
  private static final TruckRoute.Point MONTREAL = new TruckRoute.Point(
    45.5019,
    -73.5674
  );
  private static final TruckRoute.Point TORONTO = new TruckRoute.Point(
    43.6532,
    -79.3832
  );
  private static final String MAIN_GEOMETRY = '_p~iF~ps|U_ulLnnqC_mqNvxq`@';
  private static final String NO_ROUTE = '{"code":"NoRoute","message":"No route found","routes":[]}';
  private static final String BORDER_ALERT = '{"type":"alert","subtype":"countryBorderCrossing","refresh_type":"static","geometry_index_start":0,"geometry_index_end":1,"details":{"actual_value":"CA,US","message":"Crossing the border of the countries of CA and US."}}';

  /** Answers the n-th callout with the n-th queued response (the last one repeats) and records every endpoint. */
  private class SequenceMock implements HttpCalloutMock {
    List<Integer> statuses = new List<Integer>();
    List<String> bodies = new List<String>();
    List<String> endpoints = new List<String>();

    SequenceMock reply(Integer status, String body) {
      statuses.add(status);
      bodies.add(body);
      return this;
    }

    public HttpResponse respond(HttpRequest req) {
      endpoints.add(req.getEndpoint());
      Integer i = Math.min(endpoints.size(), statuses.size()) - 1;
      HttpResponse res = new HttpResponse();
      res.setStatusCode(statuses[i]);
      res.setHeader('Content-Type', 'application/json');
      res.setBody(bodies[i]);
      return res;
    }
  }

  private class ThrowingMock implements HttpCalloutMock {
    Integer calls = 0;

    public HttpResponse respond(HttpRequest req) {
      calls++;
      throw new CalloutException(
        'Read timed out: https://api.mapbox.com/directions/v5?access_token=pk.test'
      );
    }
  }

  /** Sets the test token and installs a fresh recording mock. */
  private static SequenceMock mock() {
    MapboxHttp.tokenOverride = 'pk.test';
    SequenceMock m = new SequenceMock();
    Test.setMock(HttpCalloutMock.class, m);
    return m;
  }

  /** The default 53 ft dry van, built by hand so the tests do not depend on the org's setting record. */
  private static TruckRoute.Profile truck() {
    TruckRoute.Profile p = new TruckRoute.Profile();
    p.heightM = 4.11;
    p.widthM = 2.6;
    p.weightT = 36.29;
    p.alternatives = true;
    p.approxFactor = 1.2;
    p.timeoutMs = 8000;
    return p;
  }

  /** One route object with a single leg; notification is a notification object's JSON or null. */
  private static String routeJson(
    Decimal metres,
    Decimal seconds,
    String geometry,
    String notification
  ) {
    return '{"geometry":"' +
      geometry +
      '","distance":' +
      metres +
      ',"duration":' +
      seconds +
      ',"weight":' +
      seconds +
      ',"weight_name":"auto","legs":[{"summary":"A-20, ON-401","distance":' +
      metres +
      ',"duration":' +
      seconds +
      ',"steps":[],"notifications":[' +
      (notification == null ? '' : notification) +
      ']}]}';
  }

  private static String answer(List<String> routes) {
    return '{"code":"Ok","routes":[' +
      String.join(routes, ',') +
      '],"waypoints":[{"name":"","location":[-73.5674,45.5019]},{"name":"","location":[-79.3832,43.6532]}],"uuid":"test"}';
  }

  private static String violation(String subtype) {
    return '{"type":"violation","subtype":"' +
      subtype +
      '","refresh_type":"static","geometry_index_start":3,"geometry_index_end":5,"details":{"actual_value":"2.00","requested_value":"4.11","unit":"meters","message":"The vehicle is more than the permissible limit of the road."}}';
  }

  /** The timeoutMs profileFrom builds from a setting whose only field is Timeout_Ms__c. */
  private static Integer timeoutFrom(String ms) {
    return TruckRoute.profileFrom(
        (Truck_Routing_Setting__mdt) JSON.deserialize(
          '{"Timeout_Ms__c":' + ms + '}',
          Truck_Routing_Setting__mdt.class
        )
      )
      .timeoutMs;
  }

  private static String cleanTruckAnswer() {
    return answer(
      new List<String>{ routeJson(541234.5, 19845, MAIN_GEOMETRY, null) }
    );
  }

  @IsTest
  static void truckRequestCarriesTheTruckLimitsAndAlternatives() {
    SequenceMock m = mock().reply(200, cleanTruckAnswer());
    TruckRoute.Profile noAlternatives = truck();
    noAlternatives.alternatives = false;
    Test.startTest();
    MapboxTruckRoute.route(MONTREAL, TORONTO, truck());
    MapboxTruckRoute.route(MONTREAL, TORONTO, noAlternatives);
    Test.stopTest();
    System.assertEquals(
      2,
      m.endpoints.size(),
      'one request per clean truck route'
    );
    String url = m.endpoints[0];
    System.assert(
      url.startsWith(
        'https://api.mapbox.com/directions/v5/mapbox/driving/-73.567400,45.501900;-79.383200,43.653200?'
      ),
      url
    );
    for (
      String part : new List<String>{
        'alternatives=true',
        'overview=simplified',
        'geometries=polyline',
        'steps=false',
        'max_height=4.11',
        'max_width=2.60',
        'max_weight=36.29',
        'notifications=all',
        'access_token=pk.test'
      }
    ) {
      System.assert(url.contains(part), part + ' missing from ' + url);
    }
    System.assert(
      m.endpoints[1].contains('alternatives=false'),
      m.endpoints[1]
    );
  }

  @IsTest
  static void cleanTruckAnswerKeepsUpToThreeCompliantRoutesInMilesAndHours() {
    SequenceMock m = mock()
      .reply(
        200,
        answer(
          new List<String>{
            routeJson(541234.5, 19845, MAIN_GEOMETRY, null),
            routeJson(612345.6, 21912, 'alt1', null),
            routeJson(498765, 18000, 'breaksWeight', violation('maxWeight')),
            routeJson(700321, 23600, 'alt2', null),
            routeJson(530000, 19000, 'fourth', null)
          }
        )
      );
    Test.startTest();
    TruckRoute.Result r = MapboxTruckRoute.route(MONTREAL, TORONTO, truck());
    Test.stopTest();
    System.assertEquals('Found', r.status);
    System.assertEquals('Truck', r.routeType);
    System.assertEquals(null, r.message);
    System.assertEquals(1, m.endpoints.size(), 'no fallback request');
    System.assertEquals(
      3,
      r.routes.size(),
      'the main route and two compliant alternatives, never more than 3'
    );
    System.assertEquals(336.3, r.routes[0].miles, '541,234.5 m');
    System.assertEquals(5.5, r.routes[0].hours, '19,845 s');
    System.assertEquals(MAIN_GEOMETRY, r.routes[0].polyline5);
    System.assertEquals('alt1', r.routes[1].polyline5);
    System.assertEquals(380.5, r.routes[1].miles, '612,345.6 m');
    System.assertEquals(6.1, r.routes[1].hours, '21,912 s');
    System.assertEquals(
      'alt2',
      r.routes[2].polyline5,
      'the alternative that breaks the weight limit is left out'
    );
    System.assertEquals(435.2, r.routes[2].miles, '700,321 m');
    System.assertEquals(6.6, r.routes[2].hours, '23,600 s');
  }

  @IsTest
  static void anAlertIsNotATruckLimit() {
    SequenceMock m = mock()
      .reply(
        200,
        answer(
          new List<String>{
            routeJson(541234.5, 19845, MAIN_GEOMETRY, BORDER_ALERT)
          }
        )
      );
    Test.startTest();
    TruckRoute.Result r = MapboxTruckRoute.route(MONTREAL, TORONTO, truck());
    Test.stopTest();
    System.assertEquals('Truck', r.routeType, 'a border crossing is an alert');
    System.assertEquals(1, r.routes.size());
    System.assertEquals(1, m.endpoints.size());
  }

  @IsTest
  static void mainRouteBreakingATruckLimitFallsBackToARegularRoute() {
    String regular = answer(
      new List<String>{
        routeJson(530000, 19000, 'regular', null),
        routeJson(980000.4, 36000, 'regularAlt', null)
      }
    );
    Test.startTest();
    for (
      String subtype : new List<String>{ 'maxHeight', 'maxWidth', 'maxWeight' }
    ) {
      SequenceMock m = mock()
        .reply(
          200,
          answer(
            new List<String>{
              routeJson(541234.5, 19845, MAIN_GEOMETRY, violation(subtype)),
              routeJson(612345.6, 21912, 'alt1', null)
            }
          )
        )
        .reply(200, regular);
      TruckRoute.Result r = MapboxTruckRoute.route(MONTREAL, TORONTO, truck());
      System.assertEquals(
        2,
        m.endpoints.size(),
        subtype + ': the truck request, then the regular one'
      );
      System.assert(m.endpoints[0].contains('max_height=4.11'), m.endpoints[0]);
      String second = m.endpoints[1];
      System.assert(
        !second.contains('max_height') &&
          !second.contains('max_width') &&
          !second.contains('max_weight') &&
          !second.contains('notifications'),
        second
      );
      System.assert(
        second.contains('alternatives=true') &&
        second.contains('access_token=pk.test'),
        second
      );
      System.assertEquals('Found', r.status, subtype);
      System.assertEquals('Regular', r.routeType, subtype);
      System.assertEquals(
        2,
        r.routes.size(),
        subtype + ': the regular routes, not the truck alternative'
      );
      System.assertEquals('regular', r.routes[0].polyline5, subtype);
      System.assertEquals(329.3, r.routes[0].miles, subtype);
      System.assertEquals(5.3, r.routes[0].hours, subtype);
      System.assertEquals(608.9, r.routes[1].miles, subtype);
      System.assertEquals(10.0, r.routes[1].hours, subtype);
    }
    Test.stopTest();
  }

  @IsTest
  static void noTruckRouteAlsoFallsBackToARegularRoute() {
    String regular = answer(
      new List<String>{ routeJson(530000, 19000, 'regular', null) }
    );
    Test.startTest();
    SequenceMock noRoute = mock().reply(200, NO_ROUTE).reply(200, regular);
    TruckRoute.Result afterNoRoute = MapboxTruckRoute.route(
      MONTREAL,
      TORONTO,
      truck()
    );
    SequenceMock empty = mock()
      .reply(200, '{"code":"Ok","routes":[]}')
      .reply(200, regular);
    TruckRoute.Result afterEmpty = MapboxTruckRoute.route(
      MONTREAL,
      TORONTO,
      truck()
    );
    Test.stopTest();
    for (
      TruckRoute.Result r : new List<TruckRoute.Result>{
        afterNoRoute,
        afterEmpty
      }
    ) {
      System.assertEquals('Found', r.status);
      System.assertEquals('Regular', r.routeType);
      System.assertEquals(1, r.routes.size());
      System.assertEquals(329.3, r.routes[0].miles);
    }
    System.assertEquals(2, noRoute.endpoints.size());
    System.assert(
      !noRoute.endpoints[1].contains('max_weight'),
      noRoute.endpoints[1]
    );
    System.assertEquals(2, empty.endpoints.size());
  }

  @IsTest
  static void noRouteEvenWithoutTruckLimitsIsNoRoute() {
    SequenceMock m = mock().reply(200, NO_ROUTE);
    Test.startTest();
    TruckRoute.Result r = MapboxTruckRoute.route(MONTREAL, TORONTO, truck());
    Test.stopTest();
    System.assertEquals('No route', r.status);
    System.assertEquals(null, r.routeType);
    System.assert(r.routes.isEmpty());
    System.assertEquals(null, r.message);
    System.assertEquals(2, m.endpoints.size(), 'two requests at most');
  }

  @IsTest
  static void anHttpErrorIsUnavailableWithoutTheToken() {
    Test.startTest();
    SequenceMock unauthorized = mock()
      .reply(401, '{"message":"Not Authorized - Invalid Token"}');
    TruckRoute.Result first = MapboxTruckRoute.route(
      MONTREAL,
      TORONTO,
      truck()
    );
    SequenceMock regularFails = mock()
      .reply(
        200,
        answer(
          new List<String>{
            routeJson(541234.5, 19845, MAIN_GEOMETRY, violation('maxHeight'))
          }
        )
      )
      .reply(403, '{"message":"Forbidden"}');
    TruckRoute.Result second = MapboxTruckRoute.route(
      MONTREAL,
      TORONTO,
      truck()
    );
    Test.stopTest();
    System.assertEquals('Unavailable', first.status);
    System.assertEquals(TruckRoute.UNAVAILABLE, first.message);
    System.assertEquals(null, first.routeType);
    System.assert(first.routes.isEmpty());
    System.assert(!first.message.contains('pk.'), first.message);
    System.assertEquals(
      1,
      unauthorized.endpoints.size(),
      'a 4xx is not retried and does not fall back'
    );
    System.assertEquals('Unavailable', second.status);
    System.assertEquals(TruckRoute.UNAVAILABLE, second.message);
    System.assertEquals(2, regularFails.endpoints.size());
  }

  @IsTest
  static void aCalloutFailureIsUnavailableWithoutTheToken() {
    MapboxHttp.tokenOverride = 'pk.test';
    ThrowingMock m = new ThrowingMock();
    Test.setMock(HttpCalloutMock.class, m);
    Test.startTest();
    TruckRoute.Result r = MapboxTruckRoute.route(MONTREAL, TORONTO, truck());
    Test.stopTest();
    System.assertEquals('Unavailable', r.status);
    System.assertEquals(TruckRoute.UNAVAILABLE, r.message);
    System.assert(!r.message.contains('pk.test'), r.message);
    System.assert(!r.message.contains('access_token'), r.message);
    System.assertEquals(1, m.calls, 'a callout failure is not retried');
  }

  @IsTest
  static void aServerErrorIsRetriedOnce() {
    Test.startTest();
    SequenceMock recovers = mock()
      .reply(503, 'Service Unavailable')
      .reply(200, cleanTruckAnswer());
    TruckRoute.Result recovered = MapboxTruckRoute.route(
      MONTREAL,
      TORONTO,
      truck()
    );
    SequenceMock down = mock().reply(503, 'Service Unavailable');
    TruckRoute.Result stillDown = MapboxTruckRoute.route(
      MONTREAL,
      TORONTO,
      truck()
    );
    Test.stopTest();
    System.assertEquals('Truck', recovered.routeType);
    System.assertEquals(1, recovered.routes.size());
    System.assertEquals(2, recovers.endpoints.size(), 'one retry');
    System.assert(
      recovers.endpoints[1].contains('max_height=4.11'),
      'the same truck request is resent'
    );
    System.assertEquals('Unavailable', stillDown.status);
    System.assertEquals(
      2,
      down.endpoints.size(),
      'one retry, then Unavailable'
    );
  }

  @IsTest
  static void aBlankTokenOrAMissingCoordinateMakesNoCallout() {
    SequenceMock m = mock().reply(200, cleanTruckAnswer());
    MapboxHttp.tokenOverride = '';
    Test.startTest();
    TruckRoute.Result noToken = MapboxTruckRoute.route(
      MONTREAL,
      TORONTO,
      truck()
    );
    MapboxHttp.tokenOverride = 'pk.test';
    TruckRoute.Result noLatitude = MapboxTruckRoute.route(
      new TruckRoute.Point(null, -73.5674),
      TORONTO,
      truck()
    );
    TruckRoute.Result noDestination = MapboxTruckRoute.route(
      MONTREAL,
      null,
      truck()
    );
    Integer callouts = Limits.getCallouts();
    Test.stopTest();
    System.assertEquals(0, callouts);
    System.assert(m.endpoints.isEmpty(), String.valueOf(m.endpoints));
    for (
      TruckRoute.Result r : new List<TruckRoute.Result>{
        noToken,
        noLatitude,
        noDestination
      }
    ) {
      System.assertEquals('Unavailable', r.status);
      System.assertEquals(TruckRoute.UNAVAILABLE, r.message);
    }
  }

  @IsTest
  static void anUnreadableAnswerIsUnavailable() {
    Test.startTest();
    mock().reply(200, 'not json');
    TruckRoute.Result notJson = MapboxTruckRoute.route(
      MONTREAL,
      TORONTO,
      truck()
    );
    mock()
      .reply(
        200,
        '{"code":"Ok","routes":[{"geometry":"x","duration":10,"legs":[]}]}'
      );
    TruckRoute.Result noDistance = MapboxTruckRoute.route(
      MONTREAL,
      TORONTO,
      truck()
    );
    Test.stopTest();
    System.assertEquals('Unavailable', notJson.status);
    System.assertEquals(TruckRoute.UNAVAILABLE, notJson.message);
    System.assertEquals('Unavailable', noDistance.status);
    System.assertEquals(TruckRoute.UNAVAILABLE, noDistance.message);
  }

  @IsTest
  static void defaultProfileDescribesTheTruckAndKeysItsLimits() {
    TruckRoute.Profile fallback = TruckRoute.profileFrom(null);
    System.assertEquals('h4.11w2.60t36.29', fallback.key());
    System.assertEquals(true, fallback.alternatives);
    System.assertEquals('1.2', fallback.approxFactor.toPlainString());
    System.assertEquals(8000, fallback.timeoutMs);

    TruckRoute.Profile custom = TruckRoute.profileFrom(
      (Truck_Routing_Setting__mdt) JSON.deserialize(
        '{"Height_M__c":4.5,"Width_M__c":2.5,"Weight_T__c":30,"Alternatives__c":false,"Approx_Factor__c":1.25,"Timeout_Ms__c":6000}',
        Truck_Routing_Setting__mdt.class
      )
    );
    System.assertEquals(
      'h4.50w2.50t30.00',
      custom.key(),
      'another truck gets another key'
    );
    System.assertEquals(false, custom.alternatives);
    System.assertEquals('1.25', custom.approxFactor.toPlainString());
    System.assertEquals(6000, custom.timeoutMs);

    TruckRoute.Profile partial = TruckRoute.profileFrom(
      (Truck_Routing_Setting__mdt) JSON.deserialize(
        '{"Height_M__c":4.2}',
        Truck_Routing_Setting__mdt.class
      )
    );
    System.assertEquals(
      'h4.20w2.60t36.29',
      partial.key(),
      'blank fields keep the default truck'
    );
    System.assertEquals(8000, partial.timeoutMs);

    System.assertEquals(1, timeoutFrom('0'), 'setTimeout refuses 0 ms');
    System.assertEquals(1, timeoutFrom('-250'), 'a negative timeout');
    System.assertEquals(1, timeoutFrom('1'), 'the shortest timeout kept');
    System.assertEquals(120000, timeoutFrom('120000'), 'the longest kept');
    System.assertEquals(
      120000,
      timeoutFrom('120001'),
      'setTimeout refuses more than 120,000 ms'
    );
    System.assertEquals(120000, timeoutFrom('999999'), 'the field maximum');

    TruckRoute.Profile fromOrg = TruckRoute.defaultProfile();
    System.assert(
      Pattern.matches(
        'h\\d+\\.\\d{2}w\\d+\\.\\d{2}t\\d+\\.\\d{2}',
        fromOrg.key()
      ),
      fromOrg.key()
    );
    System.assertNotEquals(null, fromOrg.alternatives);
    System.assertNotEquals(null, fromOrg.approxFactor);
    System.assertNotEquals(null, fromOrg.timeoutMs);
  }
}
