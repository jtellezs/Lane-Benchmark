/**
 * Turns free-text place parts into a canonical key and produces the spellings
 * Revenova may have written into rtms__City_Lane__c. Pure: no SOQL, no DML.
 */
public with sharing class PlaceNormalizer {
  private static final Map<String, String> PROVINCES = new Map<String, String>{
    'alberta' => 'AB',
    'british columbia' => 'BC',
    'manitoba' => 'MB',
    'new brunswick' => 'NB',
    'newfoundland and labrador' => 'NL',
    'newfoundland' => 'NL',
    'nova scotia' => 'NS',
    'northwest territories' => 'NT',
    'nunavut' => 'NU',
    'ontario' => 'ON',
    'prince edward island' => 'PE',
    'quebec' => 'QC',
    'saskatchewan' => 'SK',
    'yukon' => 'YT',
    'alabama' => 'AL',
    'alaska' => 'AK',
    'arizona' => 'AZ',
    'arkansas' => 'AR',
    'california' => 'CA',
    'colorado' => 'CO',
    'connecticut' => 'CT',
    'delaware' => 'DE',
    'florida' => 'FL',
    'georgia' => 'GA',
    'hawaii' => 'HI',
    'idaho' => 'ID',
    'illinois' => 'IL',
    'indiana' => 'IN',
    'iowa' => 'IA',
    'kansas' => 'KS',
    'kentucky' => 'KY',
    'louisiana' => 'LA',
    'maine' => 'ME',
    'maryland' => 'MD',
    'massachusetts' => 'MA',
    'michigan' => 'MI',
    'minnesota' => 'MN',
    'mississippi' => 'MS',
    'missouri' => 'MO',
    'montana' => 'MT',
    'nebraska' => 'NE',
    'nevada' => 'NV',
    'new hampshire' => 'NH',
    'new jersey' => 'NJ',
    'new mexico' => 'NM',
    'new york' => 'NY',
    'north carolina' => 'NC',
    'north dakota' => 'ND',
    'ohio' => 'OH',
    'oklahoma' => 'OK',
    'oregon' => 'OR',
    'pennsylvania' => 'PA',
    'rhode island' => 'RI',
    'south carolina' => 'SC',
    'south dakota' => 'SD',
    'tennessee' => 'TN',
    'texas' => 'TX',
    'utah' => 'UT',
    'vermont' => 'VT',
    'virginia' => 'VA',
    'washington' => 'WA',
    'west virginia' => 'WV',
    'wisconsin' => 'WI',
    'wyoming' => 'WY',
    'district of columbia' => 'DC'
  };
  /**
   * Mexican states, mapped to the codes Revenova actually writes into rtms__State_Lane__c and the
   * province half of rtms__City_Lane__c. Measured in PostProduc on 2026-09-09 by grouping
   * rtms__Load__c.rtms__State_Lane__c against the first/last stop location account's
   * ShippingState over 730 days: Revenova writes a 2-letter code ("General Escobedo, NL:Laredo,
   * TX", "NL:TX"), NOT the full name and not the 3-letter ISO 3166-2:MX code, so Province__c has
   * to hold that same 2-letter code for the PROVINCE and CITY precisions to match anything.
   * Twenty-five states plus Distrito Federal were confirmed against real loads; seven states have
   * no load in this org at all, so their codes come from the same 2-letter series rather than from
   * measurement and are marked "unverified" below.
   *
   * Ciudad de México and Federal District are Salesforce's two picklist labels for one entity and
   * Revenova writes a DIFFERENT code for each (MX vs DF, both measured), so both are kept: a place
   * must carry whatever code the loads for that place carry, not a tidier merged one.
   *
   * Keys are accent-stripped and lowercased because provinceCode() looks them up that way, which
   * is what makes "Nuevo León", "Nuevo Leon" and "NUEVO LEON" one place.
   */
  private static final Map<String, String> MX_STATES = new Map<String, String>{
    'aguascalientes' => 'AG',
    'baja california' => 'BC',
    'baja california norte' => 'BC',
    'baja california sur' => 'BS',
    'campeche' => 'CP', // unverified: no load in this org
    'chiapas' => 'CS', // unverified: no load in this org
    'chihuahua' => 'CH',
    'ciudad de mexico' => 'MX',
    'cdmx' => 'MX',
    'mexico city' => 'MX',
    'distrito federal' => 'DF',
    'federal district' => 'DF',
    'coahuila' => 'CO',
    'coahuila de zaragoza' => 'CO',
    'colima' => 'CL',
    'durango' => 'DG',
    'guanajuato' => 'GT',
    'guerrero' => 'GR',
    'hidalgo' => 'HG',
    'jalisco' => 'JA',
    'mexico state' => 'ME',
    'estado de mexico' => 'ME',
    'state of mexico' => 'ME',
    'mexico' => 'ME', // the STATE named México; no US or Canadian state shares the name
    'michoacan' => 'MI',
    'michoacan de ocampo' => 'MI',
    'morelos' => 'MO',
    'nayarit' => 'NA', // unverified: no load in this org
    'nuevo leon' => 'NL',
    'oaxaca' => 'OA', // unverified: no load in this org
    'puebla' => 'PB',
    'queretaro' => 'QE',
    'quintana roo' => 'QR', // unverified: no load in this org
    'san luis potosi' => 'SL',
    'sinaloa' => 'SI', // unverified: no load in this org
    'sonora' => 'SO',
    'tabasco' => 'TB', // unverified: no load in this org
    'tamaulipas' => 'TM',
    'tlaxcala' => 'TL',
    'veracruz' => 'VE',
    'veracruz de ignacio de la llave' => 'VE',
    'yucatan' => 'YU',
    'zacatecas' => 'ZA'
  };
  // Declared after both maps on purpose: Apex initializes static finals in declaration order.
  private static final Set<String> PROVINCE_CODES = allProvinceCodes();

  private static Set<String> allProvinceCodes() {
    Set<String> codes = new Set<String>(PROVINCES.values());
    codes.addAll(MX_STATES.values());
    return codes;
  }

  private static final Map<String, String> COUNTRIES = new Map<String, String>{
    'canada' => 'CA',
    'ca' => 'CA',
    'can' => 'CA',
    'united states' => 'US',
    'united states of america' => 'US',
    'usa' => 'US',
    'us' => 'US',
    'u.s.' => 'US',
    'u.s.a.' => 'US',
    'mexico' => 'MX',
    'méxico' => 'MX',
    'mx' => 'MX',
    'mex' => 'MX'
  };

  public static String stripAccents(String s) {
    if (s == null) {
      return '';
    }
    String out = s.normalizeSpace();
    // Common Latin-1 accented letters seen in Canadian/US/Mexican place names.
    Map<String, String> repl = new Map<String, String>{
      'à' => 'a',
      'á' => 'a',
      'â' => 'a',
      'ä' => 'a',
      'ã' => 'a',
      'å' => 'a',
      'è' => 'e',
      'é' => 'e',
      'ê' => 'e',
      'ë' => 'e',
      'ì' => 'i',
      'í' => 'i',
      'î' => 'i',
      'ï' => 'i',
      'ò' => 'o',
      'ó' => 'o',
      'ô' => 'o',
      'ö' => 'o',
      'õ' => 'o',
      'ù' => 'u',
      'ú' => 'u',
      'û' => 'u',
      'ü' => 'u',
      'ç' => 'c',
      'ñ' => 'n',
      'ý' => 'y',
      'ÿ' => 'y',
      'À' => 'A',
      'Á' => 'A',
      'Â' => 'A',
      'Ä' => 'A',
      'Ã' => 'A',
      'Å' => 'A',
      'È' => 'E',
      'É' => 'E',
      'Ê' => 'E',
      'Ë' => 'E',
      'Ì' => 'I',
      'Í' => 'I',
      'Î' => 'I',
      'Ï' => 'I',
      'Ò' => 'O',
      'Ó' => 'O',
      'Ô' => 'O',
      'Ö' => 'O',
      'Õ' => 'O',
      'Ù' => 'U',
      'Ú' => 'U',
      'Û' => 'U',
      'Ü' => 'U',
      'Ç' => 'C',
      'Ñ' => 'N',
      'Ý' => 'Y'
    };
    for (String k : repl.keySet()) {
      out = out.replace(k, repl.get(k));
    }
    return out;
  }

  public static String normalizeCity(String city) {
    return normalizeSegment(city);
  }

  /**
   * The one normalization every key segment goes through: accents stripped, lowercased,
   * punctuation collapsed to single spaces. Applied to the province segment as well as the city
   * segment so an unmapped province ("Baden-Württemberg", "Baden-Wurttemberg") cannot split one
   * place in two.
   */
  private static String normalizeSegment(String value) {
    if (String.isBlank(value)) {
      return '';
    }
    String s = stripAccents(value).toLowerCase();
    s = s.replaceAll('[^a-z0-9 ]', ' ');
    return s.normalizeSpace();
  }

  public static String provinceCode(String province) {
    if (String.isBlank(province)) {
      return '';
    }
    String t = province.trim();
    String upper = t.toUpperCase();
    if (upper.length() == 2 && PROVINCE_CODES.contains(upper)) {
      return upper;
    }
    String lookup = stripAccents(t).toLowerCase();
    String mapped = PROVINCES.get(lookup);
    if (mapped == null) {
      mapped = MX_STATES.get(lookup);
    }
    // Still unknown: return the value as typed, in full. Truncating here is what produced the
    // "GENERAL ESCOBEDO, Nue, MX" places; Province__c is Text(80), as wide as ShippingState.
    return mapped != null ? mapped : t;
  }

  public static String countryCode(String country) {
    if (String.isBlank(country)) {
      return '';
    }
    String t = country.trim();
    String mapped = COUNTRIES.get(t.toLowerCase());
    if (mapped != null) {
      return mapped;
    }
    return t.toUpperCase().left(2);
  }

  /**
   * city|province|country, every segment normalized the same way (see normalizeSegment): the
   * province goes through provinceCode() first, so "Nuevo León", "Nuevo Leon", "NUEVO LEON" and
   * "NL" all land on "nl" and share one place.
   */
  public static String key(String city, String province, String country) {
    return normalizeSegment(city) +
      '|' +
      normalizeSegment(provinceCode(province)) +
      '|' +
      countryCode(country).toLowerCase();
  }

  public static String cityLaneSide(
    String citySpelling,
    String provinceCodeValue
  ) {
    return (citySpelling == null ? '' : citySpelling.trim()) +
      ', ' +
      (provinceCodeValue == null ? '' : provinceCodeValue.trim());
  }

  public static Set<String> cityLaneVariants(Pricing_Place__c place) {
    Set<String> spellings = new Set<String>();
    if (String.isNotBlank(place.City__c)) {
      spellings.add(place.City__c.trim());
    }
    if (String.isNotBlank(place.Spellings__c)) {
      for (String line : place.Spellings__c.split('\n')) {
        if (String.isNotBlank(line)) {
          spellings.add(line.trim());
        }
      }
    }
    Set<String> variants = new Set<String>();
    for (String s : spellings) {
      variants.add(cityLaneSide(s, place.Province__c));
      variants.add(cityLaneSide(stripAccents(s), place.Province__c));
    }
    return variants;
  }
}
