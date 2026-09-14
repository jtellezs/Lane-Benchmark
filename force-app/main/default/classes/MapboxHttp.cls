/**
 * The shared door to the company's Mapbox account for Apex callouts: the token read and a send with one retry.
 * Token: TPRO_KPI__c org default, Mapbox_Api_Key__c (public pk. token). Remote site: MapBox.
 * Used by MapboxGeocoder (geocoding, static maps) and MapboxTruckRoute (Directions API). The token travels
 * only in request URLs: it is never logged and never put in an exception message.
 */
public with sharing class MapboxHttp {
  public static final String BASE = 'https://api.mapbox.com';

  // Test hook: tests set 'pk.test' (or '' for a missing token) instead of writing TPRO_KPI__c.
  @TestVisible
  private static String tokenOverride;

  public static String token() {
    if (tokenOverride != null) {
      return tokenOverride;
    }
    return TPRO_KPI__c.getOrgDefaults().Mapbox_Api_Key__c;
  }

  /** Sends the request, retries once on a server error (5xx); a callout failure becomes a MapboxException without the URL. */
  public static HttpResponse send(HttpRequest req) {
    Http http = new Http();
    try {
      HttpResponse res = http.send(req);
      if (res.getStatusCode() >= 500) {
        res = http.send(req); // one retry
      }
      return res;
    } catch (System.CalloutException e) {
      throw new MapboxException('Mapbox is not reachable right now');
    }
  }
}
