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
    // Revenova writes 2-letter codes for Mexican states as well ("General Escobedo, NL:Laredo,
    // TX", "NL:TX"), measured over 730 days of loads in PostProduc, so a Mexican state name maps
    // like any other. It used to fall through unmapped and reach Pricing_Place__c as "Nue".
    System.assertEquals('NL', PlaceNormalizer.provinceCode('Nuevo León'));
    System.assertEquals('NL', PlaceNormalizer.provinceCode('Nuevo Leon'));
    System.assertEquals('NL', PlaceNormalizer.provinceCode('NUEVO LEON'));
    System.assertEquals('ME', PlaceNormalizer.provinceCode('Mexico State'));
    System.assertEquals('QE', PlaceNormalizer.provinceCode('Querétaro'));
    // Ciudad de México and Federal District are one entity under two Salesforce labels, and
    // Revenova writes a different code for each; both are kept so a place matches its own loads.
    System.assertEquals('MX', PlaceNormalizer.provinceCode('Ciudad de México'));
    System.assertEquals('DF', PlaceNormalizer.provinceCode('Federal District'));
    // Unknown province: returned as typed, in full, never truncated.
    System.assertEquals(
      'Baden-Württemberg',
      PlaceNormalizer.provinceCode('Baden-Württemberg')
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
  static void keyCollapsesEverySpellingOfAProvince() {
    String expected = 'general escobedo|nl|mx';
    System.assertEquals(
      expected,
      PlaceNormalizer.key('General Escobedo', 'Nuevo León', 'Mexico')
    );
    System.assertEquals(
      expected,
      PlaceNormalizer.key('GENERAL ESCOBEDO', 'Nuevo Leon', 'México')
    );
    System.assertEquals(
      expected,
      PlaceNormalizer.key('General  Escobedo', 'NUEVO LEON', 'MX')
    );
    // An unmapped province goes through the same accent/punctuation normalization as the city, so
    // two spellings of it cannot split one place in two.
    System.assertEquals(
      'stuttgart|baden wurttemberg|ge',
      PlaceNormalizer.key('Stuttgart', 'Baden-Württemberg', 'Germany')
    );
    System.assertEquals(
      'stuttgart|baden wurttemberg|ge',
      PlaceNormalizer.key('STUTTGART', 'Baden-Wurttemberg', 'Germany')
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
