/**
 * LaneKeyMatcher and LaneLoadFilters on their own, for the row shapes the lane search never builds:
 * rtms__Load__c rows (loadPath ''), a RADIUS end read as CITY, and a missing place. The lane search's
 * own shapes are pinned by LaneSearchQueryBuilderTest. Pure: no record is inserted.
 */
@IsTest
private class LaneKeyMatcherTest {
  private static Pricing_Place__c montreal() {
    return new Pricing_Place__c(
      Key__c = 'montreal|qc|ca',
      City__c = 'Montréal',
      Province__c = 'QC',
      Country__c = 'CA',
      Postal_Prefix__c = 'H1A'
    );
  }

  private static Pricing_Place__c toronto() {
    return new Pricing_Place__c(
      Key__c = 'toronto|on|ca',
      City__c = 'Toronto',
      Province__c = 'ON',
      Country__c = 'CA',
      Postal_Prefix__c = 'M5V'
    );
  }

  @IsTest
  static void cityOnALoadRowHasNoRelationshipPath() {
    Map<String, Object> binds = new Map<String, Object>();
    String origin = LaneKeyMatcher.condition(
      '',
      true,
      'o',
      LaneSearchRequest.Precision.CITY,
      montreal(),
      null,
      binds
    );
    String destination = LaneKeyMatcher.condition(
      '',
      false,
      'd',
      LaneSearchRequest.Precision.CITY,
      toronto(),
      null,
      binds
    );
    System.assertEquals('rtms__City_Lane__c LIKE :oCity', origin);
    System.assertEquals('rtms__City_Lane__c LIKE :dCity', destination);
    System.assertEquals(new Set<String>{ 'oCity', 'dCity' }, binds.keySet());
    System.assertEquals(
      new Set<String>{ 'Montréal, QC:%', 'Montreal, QC:%' },
      new Set<String>((List<String>) binds.get('oCity'))
    );
    System.assertEquals(
      new List<String>{ '%:Toronto, ON' },
      binds.get('dCity')
    );
  }

  @IsTest
  static void provinceAndZip3OnAQuoteRowGoThroughTheLoad() {
    Map<String, Object> binds = new Map<String, Object>();
    System.assertEquals(
      'rtms__Load__r.rtms__State_Lane__c LIKE :oProv',
      LaneKeyMatcher.condition(
        'rtms__Load__r.',
        true,
        'o',
        LaneSearchRequest.Precision.PROVINCE,
        montreal(),
        null,
        binds
      )
    );
    System.assertEquals(
      'rtms__Load__r.rtms__Zip3_Lane__c LIKE :dZip3',
      LaneKeyMatcher.condition(
        'rtms__Load__r.',
        false,
        'd',
        LaneSearchRequest.Precision.ZIP3,
        toronto(),
        null,
        binds
      )
    );
    System.assertEquals('QC:%', binds.get('oProv'));
    System.assertEquals('%:M5V', binds.get('dZip3'));
  }

  @IsTest
  static void anExplicitZip3WinsAndNeedsNoPlace() {
    Map<String, Object> binds = new Map<String, Object>();
    System.assertEquals(
      'rtms__Zip3_Lane__c LIKE :oZip3',
      LaneKeyMatcher.condition(
        '',
        true,
        'o',
        LaneSearchRequest.Precision.ZIP3,
        null,
        'H2X',
        binds
      )
    );
    LaneKeyMatcher.condition(
      '',
      false,
      'd',
      LaneSearchRequest.Precision.ZIP3,
      toronto(),
      'M4W',
      binds
    );
    System.assertEquals('H2X:%', binds.get('oZip3'));
    System.assertEquals(
      '%:M4W',
      binds.get('dZip3'),
      'the explicit prefix, not the place prefix M5V'
    );
  }

  @IsTest
  static void radiusReadsAsCity() {
    Map<String, Object> cityBinds = new Map<String, Object>();
    String city = LaneKeyMatcher.condition(
      '',
      true,
      'o',
      LaneSearchRequest.Precision.CITY,
      montreal(),
      null,
      cityBinds
    );
    Map<String, Object> radiusBinds = new Map<String, Object>();
    String radius = LaneKeyMatcher.condition(
      '',
      true,
      'o',
      LaneSearchRequest.Precision.RADIUS,
      montreal(),
      null,
      radiusBinds
    );
    System.assertEquals(city, radius);
    System.assertEquals(
      cityBinds,
      radiusBinds,
      'the same city patterns, and no latitude, longitude or radius bind'
    );
  }

  @IsTest
  static void noPlaceMeansNoConstraint() {
    Map<String, Object> binds = new Map<String, Object>();
    for (LaneSearchRequest.Precision p : LaneSearchRequest.Precision.values()) {
      System.assertEquals(
        null,
        LaneKeyMatcher.condition('', true, 'o', p, null, null, binds),
        String.valueOf(p)
      );
    }
    System.assertEquals(
      null,
      LaneKeyMatcher.condition(
        '',
        true,
        'o',
        LaneSearchRequest.Precision.CITY,
        null,
        'H2X',
        binds
      ),
      'an explicit prefix counts only on a ZIP3 end'
    );
    System.assert(binds.isEmpty(), 'nothing is bound: ' + binds);
  }

  @IsTest
  static void aZip3EndWithoutAPostalPrefixNamesTheFieldToPass() {
    Pricing_Place__c noPrefix = montreal();
    noPrefix.Postal_Prefix__c = null;
    List<String> messages = new List<String>();
    for (Boolean isOrigin : new List<Boolean>{ true, false }) {
      try {
        LaneKeyMatcher.condition(
          '',
          isOrigin,
          isOrigin ? 'o' : 'd',
          LaneSearchRequest.Precision.ZIP3,
          noPrefix,
          null,
          new Map<String, Object>()
        );
      } catch (LaneSearchException e) {
        messages.add(e.getMessage());
      }
    }
    System.assertEquals(
      new List<String>{
        'Place montreal|qc|ca has no postal prefix; pass originZip3',
        'Place montreal|qc|ca has no postal prefix; pass destinationZip3'
      },
      messages
    );
  }

  @IsTest
  static void likeWildcardsInASpellingAreEscaped() {
    Pricing_Place__c odd = new Pricing_Place__c(
      Key__c = 'st jean 100|qc|ca',
      City__c = 'St_Jean 100%',
      Province__c = 'QC'
    );
    Map<String, Object> binds = new Map<String, Object>();
    LaneKeyMatcher.condition(
      '',
      false,
      'd',
      LaneSearchRequest.Precision.CITY,
      odd,
      null,
      binds
    );
    System.assertEquals(
      new List<String>{ '%:St\\_Jean 100\\%, QC' },
      binds.get('dCity')
    );
  }

  @IsTest
  static void loadFiltersOnALoadRowHaveNoRelationshipPath() {
    LaneSearchRequest r = new LaneSearchRequest();
    r.modes = new List<String>{ 'Truckload' };
    r.equipmentCategories = new List<String>{ 'Van' };
    r.equipmentTypes = new List<String>{ 'Dry Van 53\'' };
    r.hazmatOnly = true;
    r.currencyIsoCode = 'CAD';
    r.acceptedFilter = LaneSearchRequest.Accepted.ACCEPTED;
    List<String> conditions = new List<String>();
    Map<String, Object> binds = new Map<String, Object>();
    LaneLoadFilters.add(r, '', conditions, binds);
    System.assertEquals(
      new List<String>{
        'rtms__Mode__r.Name IN :modes',
        '(rtms__Equipment_Type__r.rtms__Category__c IN :cats OR rtms__Equipment_Type__r.Name IN :types)',
        'rtms__Hazardous_Materials__c = true'
      },
      conditions,
      'currency and accepted are quote filters: never load filters'
    );
    System.assertEquals(
      new Set<String>{ 'modes', 'cats', 'types' },
      binds.keySet()
    );
    System.assertEquals(r.modes, binds.get('modes'));
    System.assertEquals(r.equipmentCategories, binds.get('cats'));
    System.assertEquals(r.equipmentTypes, binds.get('types'));
  }

  @IsTest
  static void loadFiltersTakeCategoriesOrTypesAloneAndNothingWhenUnset() {
    LaneSearchRequest cats = new LaneSearchRequest();
    cats.equipmentCategories = new List<String>{ 'Van' };
    List<String> conditions = new List<String>();
    Map<String, Object> binds = new Map<String, Object>();
    LaneLoadFilters.add(cats, 'rtms__Load__r.', conditions, binds);
    System.assertEquals(
      new List<String>{
        'rtms__Load__r.rtms__Equipment_Type__r.rtms__Category__c IN :cats'
      },
      conditions
    );
    System.assertEquals(new Set<String>{ 'cats' }, binds.keySet());

    LaneSearchRequest types = new LaneSearchRequest();
    types.equipmentTypes = new List<String>{ 'Dry Van 53\'' };
    conditions = new List<String>();
    binds = new Map<String, Object>();
    LaneLoadFilters.add(types, '', conditions, binds);
    System.assertEquals(
      new List<String>{ 'rtms__Equipment_Type__r.Name IN :types' },
      conditions
    );
    System.assertEquals(new Set<String>{ 'types' }, binds.keySet());

    // Field initializers (empty lists, hazmat false), then a JSON request that left them out (null).
    LaneSearchRequest unset = new LaneSearchRequest();
    LaneSearchRequest fromJson = (LaneSearchRequest) JSON.deserialize(
      '{"originKey":"montreal|qc|ca"}',
      LaneSearchRequest.class
    );
    conditions = new List<String>();
    binds = new Map<String, Object>();
    LaneLoadFilters.add(unset, '', conditions, binds);
    LaneLoadFilters.add(fromJson, '', conditions, binds);
    System.assert(conditions.isEmpty(), 'no condition: ' + conditions);
    System.assert(binds.isEmpty(), 'no bind: ' + binds);
  }
}
