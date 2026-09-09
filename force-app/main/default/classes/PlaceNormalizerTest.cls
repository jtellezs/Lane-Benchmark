@IsTest
private class PlaceNormalizerTest {
  @IsTest
  static void normalizeCityStripsAccentsCaseAndPunctuation() {
    System.assertEquals('montreal', PlaceNormalizer.normalizeCity('Montréal'));
    System.assertEquals('montreal', PlaceNormalizer.normalizeCity('MONTREAL'));
    System.assertEquals(
      'st jerome',
      PlaceNormalizer.normalizeCity('St-Jérôme')
    );
    System.assertEquals(
      'city of industry',
      PlaceNormalizer.normalizeCity('  City  Of Industry ')
    );
    System.assertEquals('', PlaceNormalizer.normalizeCity(null));
  }

  @IsTest
  static void provinceCodeAcceptsNamesAndCodes() {
    System.assertEquals('QC', PlaceNormalizer.provinceCode('Quebec'));
    System.assertEquals('QC', PlaceNormalizer.provinceCode('Québec'));
    System.assertEquals('QC', PlaceNormalizer.provinceCode('qc'));
    System.assertEquals('ON', PlaceNormalizer.provinceCode('Ontario'));
    System.assertEquals('TX', PlaceNormalizer.provinceCode('Texas'));
    System.assertEquals(
      'Nuevo León',
      PlaceNormalizer.provinceCode('Nuevo León')
    );
    System.assertEquals('', PlaceNormalizer.provinceCode(null));
  }

  @IsTest
  static void countryCodeAcceptsNamesAndCodes() {
    System.assertEquals('CA', PlaceNormalizer.countryCode('Canada'));
    System.assertEquals('US', PlaceNormalizer.countryCode('United States'));
    System.assertEquals('US', PlaceNormalizer.countryCode('USA'));
    System.assertEquals('US', PlaceNormalizer.countryCode('us'));
    System.assertEquals('MX', PlaceNormalizer.countryCode('Mexico'));
    System.assertEquals('', PlaceNormalizer.countryCode(null));
  }

  @IsTest
  static void keyCombinesAllThreeParts() {
    System.assertEquals(
      'montreal|qc|ca',
      PlaceNormalizer.key('Montréal', 'Quebec', 'Canada')
    );
    System.assertEquals(
      'montreal|qc|ca',
      PlaceNormalizer.key('MONTREAL', 'QC', 'CA')
    );
    System.assertEquals(
      'laredo|tx|us',
      PlaceNormalizer.key('Laredo', 'Texas', 'United States')
    );
  }

  @IsTest
  static void cityLaneVariantsCoverEverySpellingWithAndWithoutAccents() {
    Pricing_Place__c p = new Pricing_Place__c(
      City__c = 'Montréal',
      Province__c = 'QC',
      Spellings__c = 'MONTREAL\nMontreal-Nord'
    );
    Set<String> v = PlaceNormalizer.cityLaneVariants(p);
    System.assert(v.contains('Montréal, QC'), v);
    System.assert(v.contains('Montreal, QC'), v);
    System.assert(v.contains('MONTREAL, QC'), v);
    System.assert(v.contains('Montreal-Nord, QC'), v);
  }
}
