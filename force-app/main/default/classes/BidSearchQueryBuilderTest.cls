@IsTest
private class BidSearchQueryBuilderTest {
  private static Map<String, Pricing_Place__c> places() {
    return new Map<String, Pricing_Place__c>{
      'montreal|qc|ca' => new Pricing_Place__c(
        Key__c = 'montreal|qc|ca',
        City__c = 'Montréal',
        Province__c = 'QC',
        Country__c = 'CA',
        Postal_Prefix__c = 'H1A',
        Geolocation__Latitude__s = 45.5,
        Geolocation__Longitude__s = -73.5
      ),
      'toronto|on|ca' => new Pricing_Place__c(
        Key__c = 'toronto|on|ca',
        City__c = 'Toronto',
        Province__c = 'ON',
        Country__c = 'CA',
        Postal_Prefix__c = 'M5V',
        Geolocation__Latitude__s = 43.6,
        Geolocation__Longitude__s = -79.3
      )
    };
  }
  private static LaneSearchRequest req() {
    LaneSearchRequest r = new LaneSearchRequest();
    r.originKey = 'montreal|qc|ca';
    r.destinationKey = 'toronto|on|ca';
    r.validate();
    return r;
  }

  @IsTest
  static void cityPrecisionUsesLaneVariantsAndActiveWindow() {
    LaneSearchRequest r = req();
    Map<String, Object> binds = new Map<String, Object>();
    String soql = BidSearchQueryBuilder.buildSoql(r, binds, places());
    System.assert(soql.startsWith('SELECT Id, Name, '), soql);
    System.assert(soql.contains('FROM Benchmark_Rate__c'), soql);
    System.assert(soql.contains('CreatedDate = LAST_N_DAYS:90'), soql);
    System.assert(soql.contains('City_Lane__c LIKE :bOCity'), soql);
    System.assert(soql.contains('City_Lane__c LIKE :bDCity'), soql);
    System.assert(soql.contains('Valid_From__c <= TODAY'), soql);
    System.assert(soql.contains('Expires_On__c >= TODAY'), soql);
    System.assert(
      soql.endsWith('ORDER BY CreatedDate DESC LIMIT :bRowLimitPlusOne'),
      soql
    );
    List<String> oPatterns = (List<String>) binds.get('bOCity');
    System.assert(oPatterns.contains('Montréal, QC:%'), oPatterns);
    System.assert(oPatterns.contains('Montreal, QC:%'), oPatterns);
    System.assert(
      ((List<String>) binds.get('bDCity')).contains('%:Toronto, ON')
    );
    System.assertEquals(2001, binds.get('bRowLimitPlusOne'));
  }

  @IsTest
  static void provinceZip3AndRadiusMapToTheirColumns() {
    LaneSearchRequest r = req();
    r.originPrecision = LaneSearchRequest.Precision.PROVINCE;
    r.destinationPrecision = LaneSearchRequest.Precision.ZIP3;
    Map<String, Object> binds = new Map<String, Object>();
    String soql = BidSearchQueryBuilder.buildSoql(r, binds, places());
    System.assert(soql.contains('State_Lane__c LIKE :bOProv'), soql);
    System.assert(soql.contains('Zip3_Lane__c LIKE :bDZip3'), soql);
    System.assertEquals('QC:%', binds.get('bOProv'));
    System.assertEquals('%:M5V', binds.get('bDZip3'));

    r = req();
    r.originPrecision = LaneSearchRequest.Precision.RADIUS;
    r.originRadius = 50;
    r.radiusUnit = LaneSearchRequest.Unit.KM;
    binds = new Map<String, Object>();
    soql = BidSearchQueryBuilder.buildSoql(r, binds, places());
    System.assert(
      soql.contains(
        'DISTANCE(Origin_Geolocation__c, GEOLOCATION(:bOLat, :bOLng), \'km\') < :bORadius'
      ),
      soql
    );
    System.assertEquals(50, binds.get('bORadius'));
  }

  @IsTest
  static void filtersAndSourceRules() {
    LaneSearchRequest r = req();
    r.modes = new List<String>{ 'Truckload' };
    r.equipmentCategories = new List<String>{ 'Van' };
    r.equipmentTypes = new List<String>{ 'Dry Van 53\'' };
    r.hazmatOnly = true;
    r.currencyIsoCode = 'CAD';
    Map<String, Object> binds = new Map<String, Object>();
    String soql = BidSearchQueryBuilder.buildSoql(r, binds, places());
    System.assert(soql.contains('Mode__c IN :bModes'), soql);
    System.assert(
      soql.contains(
        '(Equipment_Category__c IN :bCats OR Equipment_Type__c IN :bTypes)'
      ),
      soql
    );
    System.assert(soql.contains('Hazmat__c = true'), soql);
    System.assert(soql.contains('CurrencyIsoCode = :bCurrency'), soql);

    r = req();
    r.sourceFilter = LaneSearchRequest.RowSource.BIDS;
    soql = BidSearchQueryBuilder.buildSoql(
      r,
      new Map<String, Object>(),
      places()
    );
    // Not !soql.contains('Expires_On__c'): that field is always a SELECT column (see
    // cityPrecisionUsesLaneVariantsAndActiveWindow's positive assertion on the same string), so a
    // bare-field check can never pass. This checks the WHERE-clause condition specifically.
    System.assert(
      !soql.contains('Expires_On__c >= TODAY'),
      'BIDS also returns expired bids: ' + soql
    );

    r = req();
    r.sourceFilter = LaneSearchRequest.RowSource.LOADS;
    System.assertEquals(
      null,
      BidSearchQueryBuilder.buildSoql(r, new Map<String, Object>(), places())
    );
    r = req();
    r.acceptedFilter = LaneSearchRequest.Accepted.DECLINED;
    System.assertEquals(
      null,
      BidSearchQueryBuilder.buildSoql(r, new Map<String, Object>(), places())
    );
  }

  // Phase 3d: an RFP history run asks for every other project's bids, expired ones included.
  // The active-window pair drops out for includeExpiredBids, exactly as it already does for
  // sourceFilter BIDS, and the excluded project becomes a bound inequality.
  @IsTest
  static void expiredBidsAndTheProjectExclusionChangeTheWhereClause() {
    LaneSearchRequest r = req();
    r.includeExpiredBids = true;
    Map<String, Object> binds = new Map<String, Object>();
    String soql = BidSearchQueryBuilder.buildSoql(r, binds, places());
    System.assert(
      !soql.contains('Expires_On__c >= TODAY'),
      'an expired bid inside the lookback still counts: ' + soql
    );
    System.assert(!soql.contains('Valid_From__c <= TODAY'), soql);
    System.assert(
      !soql.contains('RFP_Project__c !='),
      'no exclusion was asked for: ' + soql
    );
    System.assertEquals(null, binds.get('bExcludeProject'));

    r = req();
    r.excludeProjectId = fakeProjectId();
    binds = new Map<String, Object>();
    soql = BidSearchQueryBuilder.buildSoql(r, binds, places());
    System.assert(soql.contains('RFP_Project__c != :bExcludeProject'), soql);
    System.assertEquals(r.excludeProjectId, binds.get('bExcludeProject'));
    System.assert(
      soql.contains('Expires_On__c >= TODAY'),
      'the window is untouched by the exclusion: ' + soql
    );
  }

  // The two phase 3d members are auto-properties (see LaneSearchRequest's comment on the PMD
  // field cap), and c/rfpPricing sends them as ordinary JSON keys, so this pins that
  // JSON.deserialize fills a property exactly as it fills the fields beside it.
  @IsTest
  static void jsonFillsTheBidScopeMembers() {
    LaneSearchRequest r = (LaneSearchRequest) JSON.deserialize(
      '{"originKey":"montreal|qc|ca","sourceFilter":"ALL","includeExpiredBids":true,' +
        '"excludeProjectId":"' +
        fakeProjectId() +
        '"}',
      LaneSearchRequest.class
    );
    r.validate();
    System.assertEquals(true, r.includeExpiredBids);
    System.assertEquals(fakeProjectId(), r.excludeProjectId);
    LaneSearchRequest plain = (LaneSearchRequest) JSON.deserialize(
      '{"originKey":"montreal|qc|ca"}',
      LaneSearchRequest.class
    );
    plain.validate();
    System.assertEquals(
      null,
      plain.includeExpiredBids,
      'a request that never mentions them reads as no exclusion, active bids only'
    );
    System.assertEquals(null, plain.excludeProjectId);
  }

  /** A syntactically valid, never-inserted RFP_Project__c Id: the object's own key prefix plus
   * twelve digits. Built rather than written out, so PMD's AvoidHardcodingId (which matches on
   * 15- and 18-character literals) has nothing to flag and no record has to be inserted. */
  private static Id fakeProjectId() {
    return RFP_Project__c.SObjectType.getDescribe().getKeyPrefix() +
      '000000000001';
  }

  @IsTest
  static void blankProvinceOrPostalPrefixLeavesTheEndUnconstrained() {
    Map<String, Pricing_Place__c> withBlankProvince = places();
    withBlankProvince.get('montreal|qc|ca').Province__c = null;
    LaneSearchRequest r = req();
    r.originPrecision = LaneSearchRequest.Precision.PROVINCE;
    Map<String, Object> binds = new Map<String, Object>();
    String soql = BidSearchQueryBuilder.buildSoql(r, binds, withBlankProvince);
    System.assert(!soql.contains('State_Lane__c'), soql);

    Map<String, Pricing_Place__c> withBlankPrefix = places();
    withBlankPrefix.get('toronto|on|ca').Postal_Prefix__c = null;
    r = req();
    r.destinationPrecision = LaneSearchRequest.Precision.ZIP3;
    binds = new Map<String, Object>();
    soql = BidSearchQueryBuilder.buildSoql(r, binds, withBlankPrefix);
    System.assert(!soql.contains('Zip3_Lane__c'), soql);
  }

  @IsTest
  static void defaultsApplySourceAll() {
    LaneSearchRequest r = (LaneSearchRequest) JSON.deserialize(
      '{"originKey":"montreal|qc|ca"}',
      LaneSearchRequest.class
    );
    r.validate();
    System.assertEquals(LaneSearchRequest.RowSource.ALL, r.sourceFilter);
    LaneSearchResult.Row row = new LaneSearchResult.Row();
    System.assertEquals(null, row.bid, 'loads carry no bid detail');
  }

  /** A bid is market test by the phase 9 marker or by sitting on the Market Test account. */
  @IsTest
  static void marketTestFiltersBidsByTheMarkerOrTheAccount() {
    LaneSearchRequest include = req();
    Map<String, Object> binds = new Map<String, Object>();
    String soql = BidSearchQueryBuilder.buildSoql(include, binds, places());
    System.assert(!soql.contains('Market_Test__c'), soql);

    LaneSearchRequest only = req();
    only.marketTestFilter = LaneSearchRequest.MarketTest.ONLY;
    Map<String, Object> onlyBinds = new Map<String, Object>();
    String onlySoql = BidSearchQueryBuilder.buildSoql(
      only,
      onlyBinds,
      places()
    );
    System.assert(onlySoql.contains('Market_Test__c = true'), onlySoql);

    LaneSearchRequest without = req();
    without.marketTestFilter = LaneSearchRequest.MarketTest.EXCLUDE;
    Map<String, Object> withoutBinds = new Map<String, Object>();
    String withoutSoql = BidSearchQueryBuilder.buildSoql(
      without,
      withoutBinds,
      places()
    );
    System.assert(withoutSoql.contains('NOT'), withoutSoql);
    System.assert(withoutSoql.contains('Market_Test__c = true'), withoutSoql);
  }
}
