/** Typed input for LaneSearchService. Null or empty means "no constraint". */
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

  // Brief-specified validation dispatch across four independent concerns (lookbackDays, rowLimit,
  // origin/destination radius, currency); a per-field refactor is a call for a later task, not a
  // faithful implementation of this one.
  @SuppressWarnings('PMD.CyclomaticComplexity')
  public void validate() {
    if (lookbackDays == null || lookbackDays < 1) {
      throw new LaneSearchException(
        'lookbackDays must be a positive integer (default 90)'
      );
    }
    if (rowLimit == null || rowLimit < 1 || rowLimit > 2000) {
      throw new LaneSearchException('rowLimit must be between 1 and 2000');
    }
    if (
      originPrecision == Precision.RADIUS &&
      String.isNotBlank(originKey) &&
      (originRadius == null ||
      originRadius <= 0)
    ) {
      throw new LaneSearchException(
        'originRadius is required and must be positive for RADIUS precision'
      );
    }
    if (
      destinationPrecision == Precision.RADIUS &&
      String.isNotBlank(destinationKey) &&
      (destinationRadius == null ||
      destinationRadius <= 0)
    ) {
      throw new LaneSearchException(
        'destinationRadius is required and must be positive for RADIUS precision'
      );
    }
    if (
      currencyIsoCode != null &&
      currencyIsoCode != 'CAD' &&
      currencyIsoCode != 'USD'
    ) {
      throw new LaneSearchException('currencyIsoCode must be CAD, USD or null');
    }
  }
}
