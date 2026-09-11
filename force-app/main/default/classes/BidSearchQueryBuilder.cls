/**
 * Dynamic SOQL for bids (Benchmark_Rate__c) with the same precision semantics as
 * LaneSearchQueryBuilder has for Loads: CITY matches City_Lane__c against the place's spelling
 * variants, PROVINCE matches State_Lane__c, ZIP3 matches Zip3_Lane__c, RADIUS uses DISTANCE() on
 * the copied geolocation. The per-end bookkeeping is a smaller copy of LaneSearchQueryBuilder's
 * LaneEnd (private there); the two builders address different objects and fields, so a shared
 * abstraction would have to be parameterised on six field names for two callers.
 * Returns null when the request can never match a bid (see canMatchBids).
 */
public with sharing class BidSearchQueryBuilder {
  private static final String SELECT_CLAUSE =
    'SELECT Id, Name, RFP_Lane__c, RFP_Project__c, Carrier__c, Carrier_Name__c, Carrier_Display__c, ' +
    'Contact_Name__c, Contact_Email__c, Contact_Phone__c, Rate__c, CurrencyIsoCode, Fuel_Surcharge__c, ' +
    'FSC_Included__c, Transit_Days__c, Valid_From__c, Expires_On__c, Status__c, Mode__c, ' +
    'Equipment_Category__c, Equipment_Type__c, Hazmat__c, Origin_City__c, Origin_Province__c, ' +
    'Destination_City__c, Destination_Province__c, Notes__c, CreatedDate FROM Benchmark_Rate__c';

  private class BidEnd {
    String key;
    LaneSearchRequest.Precision precision;
    String explicitZip3;
    Decimal radius;
    String bindPrefix; // 'bO' or 'bD'
    String geoField; // Origin_Geolocation__c / Destination_Geolocation__c
    String likePrefix;
    String likeSuffix;
  }

  public static String buildSoql(
    LaneSearchRequest req,
    Map<String, Object> binds,
    Map<String, Pricing_Place__c> places
  ) {
    if (!canMatchBids(req)) {
      return null;
    }
    List<String> conditions = new List<String>();
    conditions.add(
      'CreatedDate = LAST_N_DAYS:' + String.valueOf(req.lookbackDays)
    );
    if (req.sourceFilter != LaneSearchRequest.RowSource.BIDS) {
      conditions.add('Valid_From__c <= TODAY');
      conditions.add('Expires_On__c >= TODAY');
    }
    addEnd(conditions, binds, req, originEnd(req), places);
    addEnd(conditions, binds, req, destinationEnd(req), places);
    addFilters(req, conditions, binds);
    binds.put('bRowLimitPlusOne', req.rowLimit + 1);
    return SELECT_CLAUSE +
      ' WHERE ' +
      String.join(conditions, ' AND ') +
      ' ORDER BY CreatedDate DESC LIMIT :bRowLimitPlusOne';
  }

  /** Bids have no accepted/declined state and no customer, so those filters exclude every bid. */
  private static Boolean canMatchBids(LaneSearchRequest req) {
    return req.sourceFilter != LaneSearchRequest.RowSource.LOADS &&
      req.marketTestOnly != true &&
      req.acceptedFilter == LaneSearchRequest.Accepted.ANY_STATUS;
  }

  private static BidEnd originEnd(LaneSearchRequest req) {
    BidEnd e = new BidEnd();
    e.key = req.originKey;
    e.precision = req.originPrecision;
    e.explicitZip3 = req.originZip3;
    e.radius = req.originRadius;
    e.bindPrefix = 'bO';
    e.geoField = 'Origin_Geolocation__c';
    e.likePrefix = '';
    e.likeSuffix = ':%';
    return e;
  }

  private static BidEnd destinationEnd(LaneSearchRequest req) {
    BidEnd e = new BidEnd();
    e.key = req.destinationKey;
    e.precision = req.destinationPrecision;
    e.explicitZip3 = req.destinationZip3;
    e.radius = req.destinationRadius;
    e.bindPrefix = 'bD';
    e.geoField = 'Destination_Geolocation__c';
    e.likePrefix = '%:';
    e.likeSuffix = '';
    return e;
  }

  private static void addEnd(
    List<String> conditions,
    Map<String, Object> binds,
    LaneSearchRequest req,
    BidEnd e,
    Map<String, Pricing_Place__c> places
  ) {
    if (
      e.precision == LaneSearchRequest.Precision.ZIP3 &&
      String.isNotBlank(e.explicitZip3)
    ) {
      addLike(conditions, binds, e, 'Zip3_Lane__c', 'Zip3', e.explicitZip3);
      return;
    }
    Pricing_Place__c place = places.get(e.key);
    if (place == null) {
      return;
    }
    if (e.precision == LaneSearchRequest.Precision.CITY) {
      addCity(conditions, binds, e, place);
    } else if (e.precision == LaneSearchRequest.Precision.PROVINCE) {
      addLike(conditions, binds, e, 'State_Lane__c', 'Prov', place.Province__c);
    } else if (e.precision == LaneSearchRequest.Precision.ZIP3) {
      addLike(
        conditions,
        binds,
        e,
        'Zip3_Lane__c',
        'Zip3',
        place.Postal_Prefix__c
      );
    } else {
      addRadius(conditions, binds, req, e, place);
    }
  }

  private static String pattern(BidEnd e, String raw) {
    return e.likePrefix + LaneSearchQueryBuilder.escapeLike(raw) + e.likeSuffix;
  }

  private static void addCity(
    List<String> conditions,
    Map<String, Object> binds,
    BidEnd e,
    Pricing_Place__c place
  ) {
    List<String> patterns = new List<String>();
    for (String v : PlaceNormalizer.cityLaneVariants(place)) {
      patterns.add(pattern(e, v));
    }
    binds.put(e.bindPrefix + 'City', patterns);
    conditions.add('City_Lane__c LIKE :' + e.bindPrefix + 'City');
  }

  private static void addLike(
    List<String> conditions,
    Map<String, Object> binds,
    BidEnd e,
    String field,
    String bindSuffix,
    String raw
  ) {
    // A place with nothing to match at this precision (no province, no postal prefix) leaves this
    // end unconstrained rather than failing the whole search - same call as
    // LaneSearchQueryBuilder.addEnd falling through to "no constraint" when places.get(e.key) is
    // null.
    if (String.isBlank(raw)) {
      return;
    }
    binds.put(e.bindPrefix + bindSuffix, pattern(e, raw));
    conditions.add(field + ' LIKE :' + e.bindPrefix + bindSuffix);
  }

  private static void addRadius(
    List<String> conditions,
    Map<String, Object> binds,
    LaneSearchRequest req,
    BidEnd e,
    Pricing_Place__c place
  ) {
    if (
      place.Geolocation__Latitude__s == null ||
      place.Geolocation__Longitude__s == null
    ) {
      throw new LaneSearchException('Place ' + e.key + ' has no coordinates');
    }
    String unit = req.radiusUnit == LaneSearchRequest.Unit.KM ? 'km' : 'mi';
    binds.put(e.bindPrefix + 'Lat', place.Geolocation__Latitude__s);
    binds.put(e.bindPrefix + 'Lng', place.Geolocation__Longitude__s);
    binds.put(e.bindPrefix + 'Radius', e.radius);
    conditions.add(
      'DISTANCE(' +
        e.geoField +
        ', GEOLOCATION(:' +
        e.bindPrefix +
        'Lat, :' +
        e.bindPrefix +
        'Lng), \'' +
        unit +
        '\') < :' +
        e.bindPrefix +
        'Radius'
    );
  }

  private static void addFilters(
    LaneSearchRequest req,
    List<String> conditions,
    Map<String, Object> binds
  ) {
    if (String.isNotBlank(req.currencyIsoCode)) {
      binds.put('bCurrency', req.currencyIsoCode);
      conditions.add('CurrencyIsoCode = :bCurrency');
    }
    if (req.modes != null && !req.modes.isEmpty()) {
      binds.put('bModes', req.modes);
      conditions.add('Mode__c IN :bModes');
    }
    addEquipment(req, conditions, binds);
    if (req.hazmatOnly == true) {
      conditions.add('Hazmat__c = true');
    }
  }

  private static void addEquipment(
    LaneSearchRequest req,
    List<String> conditions,
    Map<String, Object> binds
  ) {
    Boolean hasCats =
      req.equipmentCategories != null && !req.equipmentCategories.isEmpty();
    Boolean hasTypes =
      req.equipmentTypes != null && !req.equipmentTypes.isEmpty();
    if (hasCats) {
      binds.put('bCats', req.equipmentCategories);
    }
    if (hasTypes) {
      binds.put('bTypes', req.equipmentTypes);
    }
    if (hasCats && hasTypes) {
      conditions.add(
        '(Equipment_Category__c IN :bCats OR Equipment_Type__c IN :bTypes)'
      );
    } else if (hasCats) {
      conditions.add('Equipment_Category__c IN :bCats');
    } else if (hasTypes) {
      conditions.add('Equipment_Type__c IN :bTypes');
    }
  }
}
