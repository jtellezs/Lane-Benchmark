/** Shared AuraHandledException helpers for the RFP controllers. */
public with sharing class RfpUserError {
  /** An AuraHandledException whose getMessage() is the given sentence (setMessage makes it visible to LWC). */
  public static AuraHandledException of(String message) {
    AuraHandledException e = new AuraHandledException(message);
    e.setMessage(message);
    return e;
  }
  /** Platform messages can carry field names but never SOQL; keep the first sentence only. */
  public static String safe(Exception e) {
    String m = e.getMessage();
    return m == null ? '' : m.substringBefore('.').left(160);
  }
}
