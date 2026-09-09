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
  private static final Set<String> PROVINCE_CODES = new Set<String>(
    PROVINCES.values()
  );
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
    if (String.isBlank(city)) {
      return '';
    }
    String s = stripAccents(city).toLowerCase();
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
    String mapped = PROVINCES.get(stripAccents(t).toLowerCase());
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

  public static String key(String city, String province, String country) {
    return normalizeCity(city) +
      '|' +
      provinceCode(province).toLowerCase() +
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
