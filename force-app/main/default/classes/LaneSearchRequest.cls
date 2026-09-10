/**
 * Typed input for LaneSearchService. Null or empty means "no constraint".
 *
 * Phase 2's controller takes the search as a JSON String and
 * `JSON.deserialize(payload, LaneSearchRequest.class)` into this class rather than declaring an
 * @AuraEnabled parameter of this type, because it accepts the enum fields as their string names,
 * which an @AuraEnabled parameter of an enum type does not. JSON.deserialize does not run
 * initializers, though, so a field the UI leaves out of the JSON arrives null, not at its declared
 * default; validate() applies defaults first, so a JSON request may omit any field. The field
 * initializers below still cover direct Apex callers that build a LaneSearchRequest without going
 * through JSON.
 */
public class LaneSearchRequest {
  public enum Precision {
    RADIUS,
    CITY,
    PROVINCE,
    ZIP3
  }
  public enum Unit {
    MI,
    KM
  }
  // Brief specified ANY, but ANY is a reserved Apex identifier (compiler: "Identifier name is
  // reserved: ANY"); renamed to ANY_STATUS. Tasks 6-7/phase 2 must reference Accepted.ANY_STATUS.
  public enum Accepted {
    ANY_STATUS,
    ACCEPTED,
    DECLINED
  }

  public String originKey;
  public String destinationKey;
  public Precision originPrecision = Precision.CITY;
  public Precision destinationPrecision = Precision.CITY;
  public Decimal originRadius;
  public Decimal destinationRadius;
  public Unit radiusUnit = Unit.MI;
  public String originZip3;
  public String destinationZip3;
  public Integer lookbackDays = 90;
  public String currencyIsoCode;
  public List<String> modes = new List<String>();
  public List<String> equipmentCategories = new List<String>();
  public List<String> equipmentTypes = new List<String>();
  public Boolean hazmatOnly = false;
  public Boolean marketTestOnly = false;
  // Brief named this field "accepted", but Apex is case-insensitive and that collides with the
  // enum type "Accepted" declared above (compiler: "Illegal forward reference: accepted");
  // renamed the field to acceptedFilter, matching the originPrecision/radiusUnit naming pattern.
  // Tasks 6-7/phase 2 must reference req.acceptedFilter, not req.accepted.
  public Accepted acceptedFilter = Accepted.ANY_STATUS;
  public Integer rowLimit = 2000;
  public Boolean includeStopGeolocation = true;

  /**
   * Validates and normalizes in place: a blank currency becomes null, and a ZIP3 prefix is
   * uppercased. One helper per concern, so no method (and not this class) needs a complexity
   * suppression - the same ruling that split LaneSearchQueryBuilder.
   */
  public void validate() {
    applyDefaults();
    validateLookback();
    validateRowLimit();
    validateRadius(originPrecision, originKey, originRadius, 'originRadius');
    validateRadius(
      destinationPrecision,
      destinationKey,
      destinationRadius,
      'destinationRadius'
    );
    validateCurrency();
    originZip3 = validatedZip3(originZip3, 'originZip3');
    destinationZip3 = validatedZip3(destinationZip3, 'destinationZip3');
  }

  /**
   * JSON.deserialize does not run field initializers, so a field the UI leaves out of the JSON
   * arrives null here, not at its declared default; this fills each one in before validation.
   * Direct Apex callers never see this do anything (their fields are never null to begin with).
   * Uses `??` (null coalescing), not a dozen `if (x == null) x = ...` statements: PMD's
   * CyclomaticComplexity rule doesn't count `??` as a decision point, so this stays one simple
   * method instead of needing a same-class split that (measured) pushes the class-wide total over
   * PMD's 40 threshold no matter how the twelve fields are grouped into helpers - the split-not-
   * suppress ruling only works when there's somewhere cheaper to put the branches.
   */
  public void applyDefaults() {
    lookbackDays = lookbackDays ?? 90;
    originPrecision = originPrecision ?? Precision.CITY;
    destinationPrecision = destinationPrecision ?? Precision.CITY;
    radiusUnit = radiusUnit ?? Unit.MI;
    acceptedFilter = acceptedFilter ?? Accepted.ANY_STATUS;
    rowLimit = rowLimit ?? 2000;
    includeStopGeolocation = includeStopGeolocation ?? true;
    hazmatOnly = hazmatOnly ?? false;
    marketTestOnly = marketTestOnly ?? false;
    modes = modes ?? new List<String>();
    equipmentCategories = equipmentCategories ?? new List<String>();
    equipmentTypes = equipmentTypes ?? new List<String>();
  }

  private void validateLookback() {
    if (lookbackDays == null || lookbackDays < 1) {
      throw new LaneSearchException(
        'lookbackDays must be a positive integer (default 90)'
      );
    }
  }

  private void validateRowLimit() {
    if (rowLimit == null || rowLimit < 1 || rowLimit > 2000) {
      throw new LaneSearchException('rowLimit must be between 1 and 2000');
    }
  }

  // The parameter is endPrecision, not precision: Apex is case-insensitive, so a local named
  // "precision" hides the "Precision" enum type and Precision.RADIUS stops compiling.
  private static void validateRadius(
    Precision endPrecision,
    String key,
    Decimal radius,
    String fieldName
  ) {
    if (
      endPrecision == Precision.RADIUS &&
      String.isNotBlank(key) &&
      (radius == null ||
      radius <= 0)
    ) {
      throw new LaneSearchException(
        fieldName + ' is required and must be positive for RADIUS precision'
      );
    }
  }

  /** Blank means "both currencies", the same as null - a UI that sends "" is not an error. */
  private void validateCurrency() {
    if (String.isBlank(currencyIsoCode)) {
      currencyIsoCode = null;
      return;
    }
    if (currencyIsoCode != 'CAD' && currencyIsoCode != 'USD') {
      throw new LaneSearchException('currencyIsoCode must be CAD, USD or null');
    }
  }

  /**
   * A postal prefix is exactly three letters or digits ("H1A", "660"), uppercased so it matches
   * Revenova's rtms__Zip3_Lane__c. Blank means "use the place's own prefix" and stays blank.
   */
  private static String validatedZip3(String value, String fieldName) {
    if (String.isBlank(value)) {
      return value;
    }
    String trimmed = value.trim();
    if (!Pattern.matches('[A-Za-z0-9]{3}', trimmed)) {
      throw new LaneSearchException(
        fieldName + ' must be exactly 3 letters or digits'
      );
    }
    return trimmed.toUpperCase();
  }
}
