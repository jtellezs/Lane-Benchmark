/**
 * Value types for Mapbox truck routes (phase 7) and the truck profile from Truck_Routing_Setting__mdt.Default.
 * Profile.key() (height, width and weight rounded to 2 decimals) is part of every stored route's key, so a new
 * truck never reuses an old route; the key is the same for the truck request and its regular fallback.
 */
public with sharing class TruckRoute {
  public static final String UNAVAILABLE = 'The truck route is not available right now.';

  // The 53 ft dry-van tractor-trailer at 80,000 lb, 13 ft 6 in high, 102 in wide (spec §3).
  private static final Decimal DEFAULT_HEIGHT_M = 4.11;
  private static final Decimal DEFAULT_WIDTH_M = 2.6;
  private static final Decimal DEFAULT_WEIGHT_T = 36.29;
  private static final Decimal DEFAULT_APPROX_FACTOR = 1.2;
  private static final Integer DEFAULT_TIMEOUT_MS = 8000;
  // HttpRequest.setTimeout throws outside 1 to 120,000 ms, which would make every route Unavailable.
  private static final Integer MAX_TIMEOUT_MS = 120000;

  public class Point {
    public Decimal lat;
    public Decimal lng;

    public Point(Decimal lat, Decimal lng) {
      this.lat = lat;
      this.lng = lng;
    }
  }

  public class Profile {
    public Decimal heightM;
    public Decimal widthM;
    public Decimal weightT;
    public Boolean alternatives;
    public Decimal approxFactor;
    public Integer timeoutMs;

    /** 'h4.11w2.60t36.29' */
    public String key() {
      return 'h' +
        heightM.setScale(2) +
        'w' +
        widthM.setScale(2) +
        't' +
        weightT.setScale(2);
    }
  }

  public class Line {
    @AuraEnabled
    public Decimal miles;
    @AuraEnabled
    public Decimal hours;
    public String polyline5;
  }

  public class Result {
    public String status; // 'Found' | 'No route' | 'Unavailable'
    public String routeType; // 'Truck' | 'Regular' | null
    public List<Line> routes = new List<Line>();
    public String message;
  }

  public static Profile defaultProfile() {
    return profileFrom(Truck_Routing_Setting__mdt.getInstance('Default'));
  }

  /**
   * A missing record or a blank field falls back to the default truck, so a half-filled setting never breaks routing.
   * A timeout outside the 1 to 120,000 ms a callout accepts is brought to the nearest end.
   */
  @TestVisible
  private static Profile profileFrom(Truck_Routing_Setting__mdt setting) {
    Profile p = new Profile();
    p.heightM = setting?.Height_M__c ?? DEFAULT_HEIGHT_M;
    p.widthM = setting?.Width_M__c ?? DEFAULT_WIDTH_M;
    p.weightT = setting?.Weight_T__c ?? DEFAULT_WEIGHT_T;
    p.alternatives = setting?.Alternatives__c ?? true;
    p.approxFactor = setting?.Approx_Factor__c ?? DEFAULT_APPROX_FACTOR;
    p.timeoutMs = setting?.Timeout_Ms__c == null
      ? DEFAULT_TIMEOUT_MS
      : Math.max(1, Math.min(MAX_TIMEOUT_MS, setting.Timeout_Ms__c.intValue()));
    return p;
  }
}
