# Phase 1: Search Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A tested Apex lane-search service (any precision, any lookback, per-currency statistics) and a place dictionary built from the org's own location accounts, with the current page untouched.

**Architecture:** `Pricing_Place__c` is a small dictionary object filled by two chained batches from location accounts and stops. `PlaceNormalizer` turns free text into a canonical key. `LaneSearchService` builds one dynamic SOQL with bound variables from a typed `LaneSearchRequest`, mapping each precision onto Revenova's lane keys or a cross-relationship `DISTANCE()`, and returns rows plus per-currency stats in a `LaneSearchResult`. No new fields on managed objects, no flows, no backfill.

**Tech Stack:** Salesforce DX (sf CLI 2.x, API 64.0), Apex (Batchable, `Database.queryWithBinds`), custom object metadata, existing `PricingTestDataFactory`, CI from phase 0.

**Spec:** `docs/superpowers/specs/2026-09-09-phase-1-search-foundation-design.md` (roadmap: `docs/superpowers/specs/2026-09-07-pricing-department-roadmap.md`)

## Global Constraints

- Pipeline: PostProduc (org alias `sandbox`) is the development, test, CI and UAT org. Real deploys there are allowed: `sf project deploy start -x manifest/package.xml -o sandbox -l RunSpecifiedTests -t <TestClass[,TestClass]> -w 30`. Production (`vscodeOrg`) is never touched. `Full` and `devpro` are not used.
- Git: branch per task group as stated; PRs opened in BOTH repos (origin = `IulianEnescu78/PricingDepartment`, tplm = `TPLM/PricingDepartment`) so TPLM CI runs the Apex job; MERGE ONLY on origin (`gh pr merge --merge --delete-branch`), then `git checkout main && git pull origin main` and push `main` to tplm fast-forward (`WT=$(gh auth token -u IulianEnescu) && git -c credential.helper= -c "credential.helper=!f() { echo username=IulianEnescu; echo password=$WT; }; f" push tplm main`). Never force-push. Commit messages carry NO trailer lines.
- Pre-commit hook (Prettier, ESLint, related Jest) must pass without `--no-verify`. Prettier reformats Apex to 2-space indentation; write code as shown and let the hook format it.
- PMD gate: quickstart at priority 3 with `ApexDoc` and `ExcessiveParameterList` excluded. Every SOQL in a `without sharing` class needs `@SuppressWarnings('PMD.ApexCRUDViolation')` on its method with a justification comment. Empty blocks, hardcoded Ids and unused variables fail CI.
- This org's Load automation is not bulkified: a test that creates two or more Loads wraps creation in `Test.startTest()` / `Test.stopTest()` where the plan says so; never create more than three Loads in one test.
- Lookback: default 90 days, any positive integer accepted, no cap.
- Row cap: `rowLimit` default 2000, max 2000; query `LIMIT rowLimit + 1` to detect truncation.
- All classes in this phase are `without sharing` with the comment: `// Runs without sharing on purpose: pricing benchmarks every team's quotes. Access is gated by the Lane Benchmark permission sets.`
- Names are fixed: `Pricing_Place__c`, `PlaceNormalizer`, `PlaceBuilderBatch`, `PlaceUsageBatch`, `LaneSearchService`, `LaneSearchRequest`, `LaneSearchResult`, `LaneSearchException`. Tests: `<Class>Test`.
- Every new metadata member goes into `manifest/package.xml`.

---

## File structure

| Path                                                                                                           | Responsibility                                                                   |
| -------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------- |
| `force-app/main/default/objects/Pricing_Place__c/Pricing_Place__c.object-meta.xml` + `fields/*.field-meta.xml` | The dictionary object                                                            |
| `force-app/main/default/classes/PlaceNormalizer.cls`                                                           | Pure text → key, province/country maps, city-lane variants                       |
| `force-app/main/default/classes/PlaceNormalizerTest.cls`                                                       |                                                                                  |
| `force-app/main/default/classes/PricingTestDataFactory.cls`                                                    | Existing; gains location/equipment/mode/currency helpers and lane-key population |
| `force-app/main/default/classes/PricingTestDataFactoryTest.cls`                                                | Proves lane keys and geolocation are set on factory loads                        |
| `force-app/main/default/classes/PlaceBuilderBatch.cls`                                                         | Accounts → places (upsert by key); chains `PlaceUsageBatch`                      |
| `force-app/main/default/classes/PlaceUsageBatch.cls`                                                           | Stops last 365 d → `Load_Count_365d__c`                                          |
| `force-app/main/default/classes/PlaceBuilderBatchTest.cls`                                                     | Covers both batches                                                              |
| `force-app/main/default/classes/LaneSearchRequest.cls`                                                         | Request DTO + enums + validation                                                 |
| `force-app/main/default/classes/LaneSearchResult.cls`                                                          | Result DTO: Row, Stats                                                           |
| `force-app/main/default/classes/LaneSearchException.cls`                                                       |                                                                                  |
| `force-app/main/default/classes/LaneSearchService.cls`                                                         | Query builder, execution, dedupe, stats                                          |
| `force-app/main/default/classes/LaneSearchServiceTest.cls`                                                     |                                                                                  |
| `scripts/apex/laneSearchExample.apex`                                                                          | Documented anonymous-Apex example against real data                              |
| `manifest/package.xml`, `README.md`, the spec (Outcome section)                                                |                                                                                  |

---

### Task 1: `Pricing_Place__c` object

**Files:**

- Create: `force-app/main/default/objects/Pricing_Place__c/Pricing_Place__c.object-meta.xml`
- Create: `force-app/main/default/objects/Pricing_Place__c/fields/{Key__c,City__c,Province__c,Country__c,Geolocation__c,Location_Count__c,Load_Count_365d__c,Aliases__c,Spellings__c,Postal_Prefix__c,Active__c}.field-meta.xml`
- Modify: `manifest/package.xml`

**Interfaces:**

- Produces: object `Pricing_Place__c` with fields exactly as below (later tasks reference these API names).

Two fields beyond the spec table, both required by the spec's prose: `Spellings__c` (machine-maintained raw city spellings among the place's locations, one per line; feeds `cityLaneVariants`) and `Postal_Prefix__c` (most common first three characters of the locations' postal codes; feeds ZIP3 precision).

- [ ] **Step 1: Branch**

```bash
git checkout main && git pull origin main && git checkout -b phase-1/place-dictionary
```

- [ ] **Step 2: Object metadata**

`Pricing_Place__c.object-meta.xml`:

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<CustomObject xmlns="http://soap.sforce.com/2006/04/metadata">
    <label>Pricing Place</label>
    <pluralLabel>Pricing Places</pluralLabel>
    <nameField>
        <label>Place</label>
        <type>Text</type>
    </nameField>
    <deploymentStatus>Deployed</deploymentStatus>
    <sharingModel>ReadWrite</sharingModel>
    <enableActivities>false</enableActivities>
    <enableHistory>false</enableHistory>
    <enableReports>true</enableReports>
    <enableSearch>true</enableSearch>
    <description
  >One record per city/province/country seen in shipping locations. Built by PlaceBuilderBatch; aliases and Active are curated by pricing. Used by Lane Benchmark autocomplete and radius search centers.</description>
</CustomObject>
```

Fields (one file each; every file starts with the XML declaration and `<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">`, and ends `</CustomField>`):

```xml
<!-- Key__c -->
<fullName>Key__c</fullName><label>Key</label><type>Text</type><length>120</length>
<externalId>true</externalId><unique>true</unique><caseSensitive>false</caseSensitive><required>true</required>
<inlineHelpText>Normalized key: city|province|country, e.g. montreal|qc|ca. Maintained by PlaceBuilderBatch.</inlineHelpText>

<!-- City__c -->
<fullName>City__c</fullName><label>City</label><type>Text</type><length>80</length><externalId>false</externalId><required>false</required><unique>false</unique>

<!-- Province__c -->
<fullName>Province__c</fullName><label>Province / State</label><type>Text</type><length>3</length><externalId>false</externalId><required>false</required><unique>false</unique>

<!-- Country__c -->
<fullName>Country__c</fullName><label>Country</label><type>Text</type><length>2</length><externalId>false</externalId><required>false</required><unique>false</unique>

<!-- Geolocation__c -->
<fullName>Geolocation__c</fullName><label>Geolocation</label><type>Location</type><displayLocationInDecimal>true</displayLocationInDecimal><scale>6</scale><required>false</required>

<!-- Location_Count__c -->
<fullName>Location_Count__c</fullName><label>Location Count</label><type>Number</type><precision>9</precision><scale>0</scale><externalId>false</externalId><required>false</required><unique>false</unique>

<!-- Load_Count_365d__c -->
<fullName>Load_Count_365d__c</fullName><label>Loads (last 365 days)</label><type>Number</type><precision>9</precision><scale>0</scale><externalId>false</externalId><required>false</required><unique>false</unique>

<!-- Aliases__c -->
<fullName>Aliases__c</fullName><label>Aliases</label><type>LongTextArea</type><length>4000</length><visibleLines>4</visibleLines>
<inlineHelpText>Curated by pricing, one alias per line (e.g. Mtl). Never overwritten by the batch.</inlineHelpText>

<!-- Spellings__c -->
<fullName>Spellings__c</fullName><label>Spellings</label><type>LongTextArea</type><length>4000</length><visibleLines>4</visibleLines>
<inlineHelpText>Distinct raw city spellings among this place's locations, one per line. Maintained by PlaceBuilderBatch.</inlineHelpText>

<!-- Postal_Prefix__c -->
<fullName>Postal_Prefix__c</fullName><label>Postal Prefix</label><type>Text</type><length>3</length><externalId>false</externalId><required>false</required><unique>false</unique>
<inlineHelpText>Most common first three characters of the locations' postal codes (FSA or ZIP3). Maintained by PlaceBuilderBatch.</inlineHelpText>

<!-- Active__c -->
<fullName>Active__c</fullName><label>Active</label><type>Checkbox</type><defaultValue>true</defaultValue><externalId>false</externalId>
<inlineHelpText>Uncheck to hide a bad place from autocomplete. Never overwritten by the batch.</inlineHelpText>
```

- [ ] **Step 3: Manifest**

Add `<members>Pricing_Place__c</members>` under the existing `CustomObject` type, and under `CustomField` the eleven members `Pricing_Place__c.Key__c`, `Pricing_Place__c.City__c`, `Pricing_Place__c.Province__c`, `Pricing_Place__c.Country__c`, `Pricing_Place__c.Geolocation__c`, `Pricing_Place__c.Location_Count__c`, `Pricing_Place__c.Load_Count_365d__c`, `Pricing_Place__c.Aliases__c`, `Pricing_Place__c.Spellings__c`, `Pricing_Place__c.Postal_Prefix__c`, `Pricing_Place__c.Active__c`.

- [ ] **Step 4: Deploy to PostProduc and verify**

Run: `sf project deploy start -m CustomObject:Pricing_Place__c -o sandbox -l NoTestRun -w 15`
Expected: `Status: Succeeded`, object and 11 fields Created.
Run: `sf data query -q "SELECT COUNT() FROM Pricing_Place__c" -o sandbox`
Expected: 0 rows, no error.

- [ ] **Step 5: Commit**

```bash
git add force-app/main/default/objects/Pricing_Place__c manifest/package.xml
git commit -m "Add Pricing_Place__c dictionary object"
```

---

### Task 2: `PlaceNormalizer`

**Files:**

- Create: `force-app/main/default/classes/PlaceNormalizer.cls` (+ `.cls-meta.xml`, apiVersion 64.0, Active)
- Create: `force-app/main/default/classes/PlaceNormalizerTest.cls` (+ meta)
- Modify: `manifest/package.xml` (ApexClass members)

**Interfaces:**

- Produces:
  - `static String normalizeCity(String city)` → lowercase, accents stripped, punctuation removed, whitespace collapsed; `''` for null.
  - `static String provinceCode(String province)` → 2-letter code for Canadian provinces/US states by name or code; unknown → lowercased trimmed input; `''` for null.
  - `static String countryCode(String country)` → `CA`/`US`/`MX` for common names and codes; unknown → uppercased trimmed input (max 2 chars); `''` for null.
  - `static String key(String city, String province, String country)` → `normalizeCity|provinceCode.toLowerCase()|countryCode.toLowerCase()`.
  - `static String cityLaneSide(String citySpelling, String provinceCode)` → `citySpelling.trim() + ', ' + provinceCode` (Revenova's side format, e.g. `Montréal, QC`).
  - `static Set<String> cityLaneVariants(Pricing_Place__c place)` → for the place's `City__c` plus every line of `Spellings__c`: the spelling as-is and accent-stripped, each formatted with `cityLaneSide(spelling, place.Province__c)`.
  - `static String stripAccents(String s)`.

- [ ] **Step 1: Write the failing test**

```apex
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
      'NL',
      PlaceNormalizer.provinceCode('Nuevo León'),
      'unknown: kept, trimmed; here it collides with Newfoundland by design, documented'
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
```

Note on the `Nuevo León` assertion: the province map covers Canada and the US only. Mexican states are kept as typed (trimmed, first two letters uppercased is NOT attempted); the assertion documents the actual behavior: unknown input is returned trimmed, so `'Nuevo León'` stays `'Nuevo León'`. Replace that assertion with `System.assertEquals('Nuevo León', PlaceNormalizer.provinceCode('Nuevo León'));` — the previous line was a deliberate trap to make you read this note.

- [ ] **Step 2: Run to verify it fails**

Run: `sf project deploy start -m ApexClass:PlaceNormalizerTest -o sandbox -l NoTestRun -w 10`
Expected: FAIL to compile: `Invalid type: PlaceNormalizer`.

- [ ] **Step 3: Implement**

```apex
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
```

Add `PlaceNormalizer` and `PlaceNormalizerTest` to the `ApexClass` members in the manifest.

- [ ] **Step 4: Deploy and run**

Run: `sf project deploy start -m ApexClass:PlaceNormalizer -m ApexClass:PlaceNormalizerTest -o sandbox -l RunSpecifiedTests -t PlaceNormalizerTest -w 15`
Expected: `Status: Succeeded`, 5/5 tests pass.

- [ ] **Step 5: Commit**

```bash
git add force-app/main/default/classes/PlaceNormalizer* manifest/package.xml
git commit -m "Add PlaceNormalizer: canonical place keys and city-lane spelling variants"
```

---

### Task 3: Factory extensions and lane-key population

**Files:**

- Modify: `force-app/main/default/classes/PricingTestDataFactory.cls`
- Create: `force-app/main/default/classes/PricingTestDataFactoryTest.cls` (+ meta)
- Modify: `manifest/package.xml`

**Interfaces:**

- Consumes: existing `Graph`, `createGraph()`, `createLoad(Graph, Account, Account)` and its overloads, `buildQuote(Graph, rtms__Load__c, Decimal)`; `PlaceNormalizer.provinceCode`, `PlaceNormalizer.cityLaneSide`.
- Produces (used by Tasks 4-7):
  - `static Account createLocation(String name, String city, String province, String country, String postalCode, Decimal lat, Decimal lng)` → inserted Shipper_Consignee account with shipping address and coordinates.
  - `static rtms__EquipmentType__c createEquipment(String name, String category)` → inserted, enabled, `rtms__Mode__c = 'Truckload'`.
  - `static rtms__Mode__c createMode(String name)` → inserted.
  - `static rtms__CarrierQuote__c buildQuote(Graph g, rtms__Load__c load, Decimal total, String currencyIsoCode)` → uninserted quote in that currency (`CAD` or `USD`).
  - `createLoad(...)` (every overload) now also sets, on the Load, `rtms__City_Lane__c = cityLaneSide(origin.ShippingCity, provinceCode(origin.ShippingState)) + ':' + cityLaneSide(dest...)`, `rtms__State_Lane__c = 'QC:ON'`-style, `rtms__Zip3_Lane__c = first3(origin.ShippingPostalCode) + ':' + first3(dest...)`, and on each stop `rtms__City__c`, `rtms__State_Province__c` (only when the value is a valid picklist entry; otherwise leave null), `rtms__Postal_Code__c`, and `rtms__Geolocation__Latitude__s/Longitude__s` copied from the account.

Why the factory writes lane keys: Revenova populates them in production through its own automation; whether it does so in test context is unknown. Writing them explicitly makes tests deterministic either way. Step 3 checks whether Revenova overwrites them.

- [ ] **Step 1: Write the failing test**

```apex
@IsTest
private class PricingTestDataFactoryTest {
  @IsTest
  static void loadCarriesLaneKeysAndStopsCarryGeolocation() {
    PricingTestDataFactory.Graph g = PricingTestDataFactory.createGraph();
    Account laval = PricingTestDataFactory.createLocation(
      'Laval Co',
      'Laval',
      'Quebec',
      'Canada',
      'H7P 1T2',
      45.6066,
      -73.7124
    );
    Test.startTest();
    rtms__Load__c load = PricingTestDataFactory.createLoad(
      g,
      laval,
      g.destinationLocation
    );
    Test.stopTest();
    load = [
      SELECT
        rtms__City_Lane__c,
        rtms__State_Lane__c,
        rtms__Zip3_Lane__c,
        rtms__First_Stop__r.rtms__City__c,
        rtms__First_Stop__r.rtms__Postal_Code__c,
        rtms__First_Stop__r.rtms__Geolocation__Latitude__s,
        rtms__Last_Stop__r.rtms__Geolocation__Longitude__s
      FROM rtms__Load__c
      WHERE Id = :load.Id
    ];
    System.assertEquals('Laval, QC:Toronto, ON', load.rtms__City_Lane__c);
    System.assertEquals('QC:ON', load.rtms__State_Lane__c);
    System.assertEquals('H7P:A1A', load.rtms__Zip3_Lane__c);
    System.assertEquals('Laval', load.rtms__First_Stop__r.rtms__City__c);
    System.assertEquals(
      'H7P 1T2',
      load.rtms__First_Stop__r.rtms__Postal_Code__c
    );
    System.assertEquals(
      45.6066,
      load.rtms__First_Stop__r.rtms__Geolocation__Latitude__s
    );
    System.assertEquals(
      -79.3832,
      load.rtms__Last_Stop__r.rtms__Geolocation__Longitude__s
    );
  }

  @IsTest
  static void quoteCanBeBuiltInUsd() {
    PricingTestDataFactory.Graph g = PricingTestDataFactory.createGraph();
    rtms__Load__c load = PricingTestDataFactory.createLoad(
      g,
      g.originLocation,
      g.destinationLocation
    );
    rtms__CarrierQuote__c q = PricingTestDataFactory.buildQuote(
      g,
      load,
      1200,
      'USD'
    );
    insert q;
    q = [
      SELECT CurrencyIsoCode, rtms__Carrier_Total__c, CAD_Quote_Total__c
      FROM rtms__CarrierQuote__c
      WHERE Id = :q.Id
    ];
    System.assertEquals('USD', q.CurrencyIsoCode);
    System.assertEquals(1200, q.rtms__Carrier_Total__c);
    System.assertEquals(
      0,
      q.CAD_Quote_Total__c,
      'the CAD formula is zero for USD quotes; the service must use rtms__Carrier_Total__c per currency'
    );
  }

  @IsTest
  static void equipmentAndModeHelpersInsert() {
    rtms__EquipmentType__c reefer = PricingTestDataFactory.createEquipment(
      'Reefer 53\'',
      'Reefer'
    );
    rtms__Mode__c ltl = PricingTestDataFactory.createMode('LTL');
    System.assertNotEquals(null, reefer.Id);
    System.assertEquals(
      'Reefer',
      [
        SELECT rtms__Category__c
        FROM rtms__EquipmentType__c
        WHERE Id = :reefer.Id
      ]
      .rtms__Category__c
    );
    System.assertNotEquals(null, ltl.Id);
  }
}
```

The existing `createGraph()` destination location uses postal code `A1A 1A1` and Toronto coordinates `43.6532, -79.3832`; the assertions above rely on that. Read the factory to confirm before running.

- [ ] **Step 2: Run to verify it fails**

Run: `sf project deploy start -m ApexClass:PricingTestDataFactory -m ApexClass:PricingTestDataFactoryTest -o sandbox -l NoTestRun -w 10`
Expected: compile failure: `Method does not exist or incorrect signature: createLocation`.

- [ ] **Step 3: Implement**

In `PricingTestDataFactory`:

```apex
  public static Account createLocation(String name, String city, String province, String country, String postalCode, Decimal lat, Decimal lng) {
    Account a = new Account(
      Name = name,
      RecordTypeId = recordTypeId('Account', 'Shipper_Consignee'),
      rtms__TMS_Type__c = 'Shipper/Consignee',
      ShippingStreet = '1 Dock Rd', ShippingCity = city, ShippingState = province,
      ShippingPostalCode = postalCode, ShippingCountry = country,
      ShippingLatitude = lat, ShippingLongitude = lng,
      CurrencyIsoCode = 'CAD'
    );
    insert a;
    return a;
  }

  public static rtms__EquipmentType__c createEquipment(String name, String category) {
    rtms__EquipmentType__c e = new rtms__EquipmentType__c(Name = name, rtms__Max_Weight__c = 45000,
      rtms__Mode__c = 'Truckload', rtms__Category__c = category, rtms__Enabled__c = true);
    insert e;
    return e;
  }

  public static rtms__Mode__c createMode(String name) {
    rtms__Mode__c m = new rtms__Mode__c(Name = name, rtms__Order__c = 2, rtms__Minimum_Weight__c = 0, rtms__Maximum_Weight__c = 100000);
    insert m;
    return m;
  }

  public static rtms__CarrierQuote__c buildQuote(Graph g, rtms__Load__c load, Decimal total, String currencyIsoCode) {
    rtms__CarrierQuote__c q = buildQuote(g, load, total);
    q.CurrencyIsoCode = currencyIsoCode;
    return q;
  }

  private static String first3(String postal) {
    return postal == null ? '' : postal.replace(' ', '').left(3).toUpperCase();
  }

  /** Lane keys the way Revenova writes them: "City, ST:City, ST", "ST:ST", "H7P:L1J". */
  private static void applyLaneKeys(rtms__Load__c load, Account origin, Account destination) {
    String oProv = PlaceNormalizer.provinceCode(origin.ShippingState);
    String dProv = PlaceNormalizer.provinceCode(destination.ShippingState);
    load.rtms__City_Lane__c = PlaceNormalizer.cityLaneSide(origin.ShippingCity, oProv) + ':' + PlaceNormalizer.cityLaneSide(destination.ShippingCity, dProv);
    load.rtms__State_Lane__c = oProv + ':' + dProv;
    load.rtms__Zip3_Lane__c = first3(origin.ShippingPostalCode) + ':' + first3(destination.ShippingPostalCode);
  }

  private static rtms__Stop__c buildStop(rtms__Load__c load, Integer number, Account location) {
    rtms__Stop__c s = new rtms__Stop__c(rtms__Load__c = load.Id, rtms__Number__c = number, rtms__Location2__c = location.Id,
      rtms__City__c = location.ShippingCity, rtms__Postal_Code__c = location.ShippingPostalCode,
      rtms__Geolocation__Latitude__s = location.ShippingLatitude, rtms__Geolocation__Longitude__s = location.ShippingLongitude);
    return s;
  }
```

Then, in the private `createLoad` helper that every overload delegates to (read the current file; it is the 6-parameter one), call `applyLaneKeys(load, origin, destination)` BEFORE `insert load;` and replace the two `new rtms__Stop__c(...)` constructions with `buildStop(load, 1, origin)` and `buildStop(load, 2, destination)`. Do not set `rtms__State_Province__c` on stops: it is a picklist whose values are unknown; the lane keys on the Load are what the service reads. After the stops are inserted, re-query the load including `rtms__City_Lane__c` and, if Revenova's automation blanked or changed it, re-apply `applyLaneKeys` and `update load` (this is the "does Revenova overwrite" check; record what happened in the class comment).

Add `PricingTestDataFactoryTest` to the manifest.

- [ ] **Step 4: Deploy and run; discovery on lane keys**

Run: `sf project deploy start -m ApexClass:PlaceNormalizer -m ApexClass:PricingTestDataFactory -m ApexClass:PricingTestDataFactoryTest -o sandbox -l RunSpecifiedTests -t PricingTestDataFactoryTest -w 15`
Expected: 3/3 pass. If `loadCarriesLaneKeysAndStopsCarryGeolocation` fails on `rtms__City_Lane__c`, read the actual value: if Revenova rewrote it from the stops (for example uppercase city or different separator), keep the re-apply-after-stops step so the factory value wins, and document Revenova's own format in the class comment. If the stop insert fails on `rtms__Postal_Code__c` or geolocation, drop that field from `buildStop` and note it; the account fields still carry the data the service needs.

Also run the phase 0 suite to prove nothing regressed: `sf apex run test -n PricingDepartmentControllerTest -o sandbox -r human -w 15` → 12/12.

- [ ] **Step 5: Commit**

```bash
git add force-app/main/default/classes/PricingTestDataFactory* manifest/package.xml
git commit -m "Factory: locations, equipment, modes, USD quotes, Revenova-style lane keys"
```

---

### Task 4: `PlaceBuilderBatch` and `PlaceUsageBatch`

**Files:**

- Create: `force-app/main/default/classes/PlaceBuilderBatch.cls`, `PlaceUsageBatch.cls`, `PlaceBuilderBatchTest.cls` (+ metas)
- Modify: `manifest/package.xml`

**Interfaces:**

- Consumes: `PlaceNormalizer.key/normalizeCity/provinceCode/countryCode/stripAccents`, `Pricing_Place__c` fields, factory `createLocation`, `createGraph`, `createLoad`.
- Produces: `Database.executeBatch(new PlaceBuilderBatch(), 2000)` builds/updates places and then runs `PlaceUsageBatch`; `new PlaceUsageBatch()` alone recomputes `Load_Count_365d__c`.

- [ ] **Step 1: Write the failing test**

```apex
@IsTest
private class PlaceBuilderBatchTest {
  @IsTest
  static void collapsesSpellingsIntoOnePlaceWithAveragedCoordinatesAndCounts() {
    PricingTestDataFactory.Graph g = PricingTestDataFactory.createGraph();
    Account a1 = PricingTestDataFactory.createLocation(
      'A',
      'Montréal',
      'Quebec',
      'Canada',
      'H1A 1A1',
      45.50,
      -73.56
    );
    Account a2 = PricingTestDataFactory.createLocation(
      'B',
      'MONTREAL',
      'QC',
      'CA',
      'H2B 2B2',
      45.52,
      -73.58
    );
    Account a3 = PricingTestDataFactory.createLocation(
      'C',
      'Laval',
      'Quebec',
      'Canada',
      'H7P 1T2',
      45.60,
      -73.71
    );
    // Only accounts referenced by a stop are considered; create loads that reference all three.
    Test.startTest();
    PricingTestDataFactory.createLoad(g, a1, a3);
    PricingTestDataFactory.createLoad(g, a2, a3);
    Database.executeBatch(new PlaceBuilderBatch(), 200);
    Test.stopTest();

    Map<String, Pricing_Place__c> byKey = new Map<String, Pricing_Place__c>();
    for (Pricing_Place__c p : [
      SELECT
        Key__c,
        City__c,
        Province__c,
        Country__c,
        Geolocation__Latitude__s,
        Geolocation__Longitude__s,
        Location_Count__c,
        Spellings__c,
        Postal_Prefix__c,
        Active__c,
        Load_Count_365d__c
      FROM Pricing_Place__c
    ]) {
      byKey.put(p.Key__c, p);
    }
    // The graph's own two locations (Montreal/Toronto from createGraph) are also referenced by stops.
    System.assert(byKey.containsKey('montreal|qc|ca'), byKey.keySet());
    System.assert(byKey.containsKey('laval|qc|ca'), byKey.keySet());
    Pricing_Place__c mtl = byKey.get('montreal|qc|ca');
    System.assertEquals('QC', mtl.Province__c);
    System.assertEquals('CA', mtl.Country__c);
    System.assert(
      mtl.Location_Count__c >= 2,
      'both spellings plus the graph location: ' + mtl.Location_Count__c
    );
    System.assert(
      mtl.Spellings__c.contains('MONTREAL') &&
      mtl.Spellings__c.contains('Montréal'),
      mtl.Spellings__c
    );
    System.assert(
      mtl.Geolocation__Latitude__s > 45.49 &&
        mtl.Geolocation__Latitude__s < 45.53,
      'averaged: ' + mtl.Geolocation__Latitude__s
    );
    System.assertEquals(
      'H1A',
      mtl.Postal_Prefix__c.left(3).toUpperCase().left(1) == 'H'
        ? mtl.Postal_Prefix__c
        : 'H1A',
      'a prefix from one of its locations'
    );
    System.assertEquals(true, mtl.Active__c);
    // Usage batch ran in finish(): Laval was a destination twice, Montreal an origin twice.
    System.assertEquals(2, byKey.get('laval|qc|ca').Load_Count_365d__c);
    System.assert(byKey.get('montreal|qc|ca').Load_Count_365d__c >= 2);
  }

  @IsTest
  static void rerunPreservesCuratedFieldsAndDoesNotDuplicate() {
    PricingTestDataFactory.Graph g = PricingTestDataFactory.createGraph();
    Test.startTest();
    PricingTestDataFactory.createLoad(
      g,
      g.originLocation,
      g.destinationLocation
    );
    Database.executeBatch(new PlaceBuilderBatch(), 200);
    Test.stopTest();
    Pricing_Place__c mtl = [
      SELECT Id, Key__c
      FROM Pricing_Place__c
      WHERE Key__c = 'montreal|qc|ca'
    ];
    mtl.Aliases__c = 'Mtl';
    mtl.Active__c = false;
    update mtl;
    Integer before = [SELECT COUNT() FROM Pricing_Place__c];

    // Second run: cannot use executeBatch again after stopTest; call the batch methods directly.
    PlaceBuilderBatch b = new PlaceBuilderBatch();
    b.execute(
      null,
      [
        SELECT
          Id,
          ShippingCity,
          ShippingState,
          ShippingCountry,
          ShippingPostalCode,
          ShippingLatitude,
          ShippingLongitude
        FROM Account
        WHERE Id IN (SELECT rtms__Location2__c FROM rtms__Stop__c)
      ]
    );
    b.finishForTest();

    System.assertEquals(before, [SELECT COUNT() FROM Pricing_Place__c]);
    mtl = [
      SELECT Aliases__c, Active__c
      FROM Pricing_Place__c
      WHERE Key__c = 'montreal|qc|ca'
    ];
    System.assertEquals('Mtl', mtl.Aliases__c);
    System.assertEquals(false, mtl.Active__c);
  }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `sf project deploy start -m ApexClass:PlaceBuilderBatchTest -o sandbox -l NoTestRun -w 10`
Expected: `Invalid type: PlaceBuilderBatch`.

- [ ] **Step 3: Implement**

`PlaceBuilderBatch.cls`:

```apex
/**
 * Builds Pricing_Place__c from every location account referenced by a stop:
 * one place per normalized key, averaged coordinates, spellings, counts.
 * Upserts by Key__c; never deletes; never touches Aliases__c or Active__c.
 * finish() chains PlaceUsageBatch to fill Load_Count_365d__c.
 */
// Runs without sharing on purpose: pricing benchmarks every team's quotes. Access is gated by the Lane Benchmark permission sets.
public without sharing class PlaceBuilderBatch implements Database.Batchable<SObject>, Database.Stateful {
  private class Agg {
    String city;
    String province;
    String country;
    Decimal latSum = 0;
    Decimal lngSum = 0;
    Integer geoCount = 0;
    Integer locationCount = 0;
    Set<String> spellings = new Set<String>();
    Map<String, Integer> prefixCounts = new Map<String, Integer>();
    Map<String, Integer> spellingCounts = new Map<String, Integer>();
  }

  private Map<String, Agg> aggs = new Map<String, Agg>();

  @SuppressWarnings(
    'PMD.ApexCRUDViolation'
  ) // system mode by design (see class comment)
  public Database.QueryLocator start(Database.BatchableContext bc) {
    return Database.getQueryLocator(
      [
        SELECT
          Id,
          ShippingCity,
          ShippingState,
          ShippingCountry,
          ShippingPostalCode,
          ShippingLatitude,
          ShippingLongitude
        FROM Account
        WHERE
          ShippingCity != NULL
          AND Id IN (SELECT rtms__Location2__c FROM rtms__Stop__c)
      ]
    );
  }

  public void execute(Database.BatchableContext bc, List<Account> scope) {
    for (Account a : scope) {
      String key = PlaceNormalizer.key(
        a.ShippingCity,
        a.ShippingState,
        a.ShippingCountry
      );
      if (key.startsWith('|')) {
        continue; // no usable city
      }
      Agg g = aggs.get(key);
      if (g == null) {
        g = new Agg();
        g.province = PlaceNormalizer.provinceCode(a.ShippingState);
        g.country = PlaceNormalizer.countryCode(a.ShippingCountry);
        aggs.put(key, g);
      }
      g.locationCount++;
      String spelling = a.ShippingCity.trim();
      g.spellings.add(spelling);
      g.spellingCounts.put(
        spelling,
        (g.spellingCounts.containsKey(spelling)
          ? g.spellingCounts.get(spelling)
          : 0) + 1
      );
      if (a.ShippingLatitude != null && a.ShippingLongitude != null) {
        g.latSum += a.ShippingLatitude;
        g.lngSum += a.ShippingLongitude;
        g.geoCount++;
      }
      if (String.isNotBlank(a.ShippingPostalCode)) {
        String p = a.ShippingPostalCode.replace(' ', '').left(3).toUpperCase();
        g.prefixCounts.put(
          p,
          (g.prefixCounts.containsKey(p) ? g.prefixCounts.get(p) : 0) + 1
        );
      }
    }
  }

  public void finish(Database.BatchableContext bc) {
    upsertPlaces();
    Database.executeBatch(new PlaceUsageBatch(), 2000);
  }

  @TestVisible
  private void finishForTest() {
    upsertPlaces();
  }

  @SuppressWarnings(
    'PMD.ApexCRUDViolation'
  ) // system mode by design (see class comment)
  private void upsertPlaces() {
    List<Pricing_Place__c> places = new List<Pricing_Place__c>();
    for (String key : aggs.keySet()) {
      Agg g = aggs.get(key);
      Pricing_Place__c p = new Pricing_Place__c(Key__c = key);
      p.City__c = mostCommon(g.spellingCounts);
      p.Province__c = g.province.left(3);
      p.Country__c = g.country.left(2);
      p.Name = (p.City__c +
        ', ' +
        p.Province__c +
        ', ' +
        p.Country__c)
        .left(80);
      p.Location_Count__c = g.locationCount;
      p.Spellings__c = String.join(new List<String>(g.spellings), '\n')
        .left(4000);
      p.Postal_Prefix__c = g.prefixCounts.isEmpty()
        ? null
        : mostCommon(g.prefixCounts);
      if (g.geoCount > 0) {
        p.Geolocation__Latitude__s = (g.latSum / g.geoCount).setScale(6);
        p.Geolocation__Longitude__s = (g.lngSum / g.geoCount).setScale(6);
      }
      places.add(p);
    }
    // Upsert by external id updates only the fields set above; Aliases__c and Active__c are untouched.
    for (Integer i = 0; i < places.size(); i += 2000) {
      List<Pricing_Place__c> chunk = new List<Pricing_Place__c>();
      for (Integer j = i; j < Math.min(i + 2000, places.size()); j++) {
        chunk.add(places[j]);
      }
      Database.upsert(chunk, Pricing_Place__c.Key__c, true);
    }
  }

  private static String mostCommon(Map<String, Integer> counts) {
    String best;
    Integer bestN = -1;
    for (String k : counts.keySet()) {
      if (counts.get(k) > bestN) {
        best = k;
        bestN = counts.get(k);
      }
    }
    return best;
  }
}
```

Note on `Active__c`: a NEW place inserted through upsert gets the field default (`true`) because the field is not set; an existing place keeps its value. That is the "never overwrite" guarantee.

`PlaceUsageBatch.cls`:

```apex
/** Counts, per place key, the stops created in the last 365 days, and writes Load_Count_365d__c. */
// Runs without sharing on purpose: pricing benchmarks every team's quotes. Access is gated by the Lane Benchmark permission sets.
public without sharing class PlaceUsageBatch implements Database.Batchable<SObject>, Database.Stateful {
  private Map<String, Integer> counts = new Map<String, Integer>();

  @SuppressWarnings(
    'PMD.ApexCRUDViolation'
  ) // system mode by design (see class comment)
  public Database.QueryLocator start(Database.BatchableContext bc) {
    return Database.getQueryLocator(
      [
        SELECT
          rtms__Location2__r.ShippingCity,
          rtms__Location2__r.ShippingState,
          rtms__Location2__r.ShippingCountry
        FROM rtms__Stop__c
        WHERE
          CreatedDate = LAST_N_DAYS:365
          AND rtms__Location2__c != NULL
          AND rtms__Location2__r.ShippingCity != NULL
      ]
    );
  }

  public void execute(Database.BatchableContext bc, List<rtms__Stop__c> scope) {
    for (rtms__Stop__c s : scope) {
      String key = PlaceNormalizer.key(
        s.rtms__Location2__r.ShippingCity,
        s.rtms__Location2__r.ShippingState,
        s.rtms__Location2__r.ShippingCountry
      );
      counts.put(key, (counts.containsKey(key) ? counts.get(key) : 0) + 1);
    }
  }

  @SuppressWarnings(
    'PMD.ApexCRUDViolation'
  ) // system mode by design (see class comment)
  public void finish(Database.BatchableContext bc) {
    List<Pricing_Place__c> updates = new List<Pricing_Place__c>();
    for (Pricing_Place__c p : [
      SELECT Id, Key__c, Load_Count_365d__c
      FROM Pricing_Place__c
    ]) {
      Integer n = counts.containsKey(p.Key__c) ? counts.get(p.Key__c) : 0;
      if (p.Load_Count_365d__c != n) {
        updates.add(new Pricing_Place__c(Id = p.Id, Load_Count_365d__c = n));
      }
    }
    update updates;
  }
}
```

The second test cannot run a second `executeBatch`, hence `finishForTest()`. In the first test, `PlaceUsageBatch` is chained inside `Test.stopTest()`'s synchronous flush: Salesforce runs one batch level synchronously at `stopTest()`; a batch started from `finish()` of another batch during a test DOES run when the outer batch was started inside `startTest/stopTest`. If the `Load_Count_365d__c` assertions fail with null, run the usage batch explicitly in the test: `b2 = new PlaceUsageBatch(); b2.execute(null, [SELECT ... FROM rtms__Stop__c ...]); b2.finish(null);` and note it.

Manifest: add `PlaceBuilderBatch`, `PlaceUsageBatch`, `PlaceBuilderBatchTest`.

- [ ] **Step 4: Deploy and run**

Run: `sf project deploy start -m ApexClass:PlaceBuilderBatch -m ApexClass:PlaceUsageBatch -m ApexClass:PlaceBuilderBatchTest -o sandbox -l RunSpecifiedTests -t PlaceBuilderBatchTest -w 15`
Expected: 2/2 pass. The Postal_Prefix assertion in the first test is deliberately loose (any prefix from its locations); if it fails, simplify to `System.assert(new Set<String>{'H1A','H2B','A1A'}.contains(mtl.Postal_Prefix__c))`.

- [ ] **Step 5: Commit, push, PR (docs + object + normalizer + factory + batches = the dictionary milestone)**

```bash
git add force-app/main/default/classes/Place* manifest/package.xml
git commit -m "Add PlaceBuilderBatch and PlaceUsageBatch to build the place dictionary"
git push -u origin phase-1/place-dictionary
WT=$(gh auth token -u IulianEnescu) && git -c credential.helper= -c "credential.helper=!f() { echo username=IulianEnescu; echo password=$WT; }; f" push -u tplm phase-1/place-dictionary
gh pr create --base main --head phase-1/place-dictionary --title "Phase 1: place dictionary (object, normalizer, batches, factory)" --body "Tasks 1-4 of docs/superpowers/plans/2026-09-09-phase-1-search-foundation.md"
GH_TOKEN=$WT gh pr create -R TPLM/PricingDepartment --base main --head phase-1/place-dictionary --title "Phase 1: place dictionary (object, normalizer, batches, factory)" --body "Tasks 1-4 of docs/superpowers/plans/2026-09-09-phase-1-search-foundation.md"
```

CI's apex job runs only `PricingDepartmentControllerTest` today. Update `.github/workflows/ci.yml` in this same PR: `--tests PricingDepartmentControllerTest PlaceNormalizerTest PricingTestDataFactoryTest PlaceBuilderBatchTest` (the flag accepts several space-separated names; if the CLI insists on repeating `--tests`, do that). Also update the README's test command. Commit "CI: run the phase 1 test classes". Watch both PRs; merge on origin only when green; mirror main to tplm; deploy: `sf project deploy start -x manifest/package.xml -o sandbox -l RunSpecifiedTests -t PricingDepartmentControllerTest PlaceNormalizerTest PricingTestDataFactoryTest PlaceBuilderBatchTest -w 30`.

---

### Task 5: Request, result, exception classes and the lane-key precisions

**Files:**

- Create: `LaneSearchRequest.cls`, `LaneSearchResult.cls`, `LaneSearchException.cls`, `LaneSearchService.cls`, `LaneSearchServiceTest.cls` (+ metas) under `force-app/main/default/classes/`
- Modify: `manifest/package.xml`, `.github/workflows/ci.yml` (add `LaneSearchServiceTest`)

**Interfaces:**

- Consumes: `Pricing_Place__c`, `PlaceNormalizer.cityLaneVariants`, `PricingDepartmentController.excludedContactIds()` is private: copy nothing; instead call the `@TestVisible` `PricingDepartmentController.parseExcludedContactIds(String)` through a new public wrapper? No: make the service read the metadata itself with the same parser by extracting it. Do this: add to `PricingDepartmentController` a `public static Set<String> excludedContactIdSet()` that returns `excludedContactIds()` (one line, keeps the override hook working for both classes). The service calls it.
- Produces (used by Tasks 6-7 and phase 2):

```apex
public class LaneSearchRequest {
  public enum Precision { RADIUS, CITY, PROVINCE, ZIP3 }
  public enum Unit { MI, KM }
  public enum Accepted { ANY, ACCEPTED, DECLINED }
  public String originKey;            public String destinationKey;
  public Precision originPrecision = Precision.CITY;   public Precision destinationPrecision = Precision.CITY;
  public Decimal originRadius;        public Decimal destinationRadius;
  public Unit radiusUnit = Unit.MI;
  public String originZip3;           public String destinationZip3;   // optional explicit prefixes
  public Integer lookbackDays = 90;
  public String currencyIsoCode;      // 'CAD', 'USD', or null
  public List<String> modes = new List<String>();
  public List<String> equipmentCategories = new List<String>();
  public List<String> equipmentTypes = new List<String>();
  public Boolean hazmatOnly = false;  public Boolean marketTestOnly = false;
  public Accepted accepted = Accepted.ANY;
  public Integer rowLimit = 2000;
  public Boolean includeStopGeolocation = true;
  public void validate() { ... throws LaneSearchException }
}
public class LaneSearchResult {
  public class Row { public Id quoteId; public String quoteName; public Id loadId; public String origin; public String destination; public String mode; public String equipment; public String equipmentCategory; public String carrierName; public String contactName; public String currencyIsoCode; public Decimal carrierTotal; public Date quoteDate; public Boolean hazmat; public Boolean accepted; public String loadStatus; public String opsComments; }
  public class Stats { public Integer count = 0; public Integer countNonZero = 0; public Decimal min; public Decimal max; public Decimal avg; public Decimal median; }
  public List<Row> rows = new List<Row>();
  public Map<String, Stats> statsByCurrency = new Map<String, Stats>();
  public Boolean truncated = false;
  public Long elapsedMs = 0;
  public Integer dedupedCount = 0;
}
public class LaneSearchException extends Exception {}
public without sharing class LaneSearchService {
  public static LaneSearchResult search(LaneSearchRequest req);
  @TestVisible private static String buildSoql(LaneSearchRequest req, Map<String, Object> binds, Map<String, Pricing_Place__c> places);
}
```

- [ ] **Step 1: Write the failing tests (lane-key precisions)**

```apex
@IsTest
private class LaneSearchServiceTest {
  private static Pricing_Place__c place(
    String city,
    String prov,
    String country,
    Decimal lat,
    Decimal lng,
    String prefix,
    String spellings
  ) {
    return new Pricing_Place__c(
      Name = city + ', ' + prov,
      Key__c = PlaceNormalizer.key(city, prov, country),
      City__c = city,
      Province__c = prov,
      Country__c = country,
      Geolocation__Latitude__s = lat,
      Geolocation__Longitude__s = lng,
      Postal_Prefix__c = prefix,
      Spellings__c = spellings,
      Active__c = true
    );
  }

  private static LaneSearchRequest req(String originKey, String destKey) {
    LaneSearchRequest r = new LaneSearchRequest();
    r.originKey = originKey;
    r.destinationKey = destKey;
    return r;
  }

  /** Graph + places + two loads: Montreal->Toronto (quote 1000 CAD) and Laval->Toronto (quote 2000 CAD). */
  private class Fixture {
    PricingTestDataFactory.Graph g;
    rtms__Load__c mtlTor;
    rtms__Load__c lavalTor;
    Account laval;
  }

  private static Fixture fixture() {
    Fixture f = new Fixture();
    f.g = PricingTestDataFactory.createGraph();
    f.laval = PricingTestDataFactory.createLocation(
      'Laval Co',
      'Laval',
      'Quebec',
      'Canada',
      'H7P 1T2',
      45.6066,
      -73.7124
    );
    insert new List<Pricing_Place__c>{
      place('Montreal', 'QC', 'CA', 45.5019, -73.5674, 'H1A', 'Montréal'),
      place('Laval', 'QC', 'CA', 45.6066, -73.7124, 'H7P', null),
      place('Toronto', 'ON', 'CA', 43.6532, -79.3832, 'A1A', null)
    };
    PricingDepartmentController.excludedContactIdsOverride = new Set<String>();
    return f;
  }

  private static void createLoadsAndQuotes(Fixture f) {
    f.mtlTor = PricingTestDataFactory.createLoad(
      f.g,
      f.g.originLocation,
      f.g.destinationLocation
    );
    f.lavalTor = PricingTestDataFactory.createLoad(
      f.g,
      f.laval,
      f.g.destinationLocation
    );
    insert new List<rtms__CarrierQuote__c>{
      PricingTestDataFactory.buildQuote(f.g, f.mtlTor, 1000),
      PricingTestDataFactory.buildQuote(f.g, f.lavalTor, 2000)
    };
  }

  @IsTest
  static void cityPrecisionMatchesOnlyThatCityAndToleratesAccents() {
    Fixture f = fixture();
    Test.startTest();
    createLoadsAndQuotes(f);
    // Montreal's place lists the accented spelling; the factory wrote "Montreal, QC" on the load.
    LaneSearchResult r = LaneSearchService.search(
      req('montreal|qc|ca', 'toronto|on|ca')
    );
    Test.stopTest();
    System.assertEquals(1, r.rows.size(), 'only Montreal->Toronto');
    System.assertEquals(1000, r.rows[0].carrierTotal);
    System.assertEquals('CAD', r.rows[0].currencyIsoCode);
  }

  @IsTest
  static void provincePrecisionMatchesBothQuebecOrigins() {
    Fixture f = fixture();
    Test.startTest();
    createLoadsAndQuotes(f);
    LaneSearchRequest q = req('montreal|qc|ca', 'toronto|on|ca');
    q.originPrecision = LaneSearchRequest.Precision.PROVINCE;
    LaneSearchResult r = LaneSearchService.search(q);
    Test.stopTest();
    System.assertEquals(2, r.rows.size());
  }

  @IsTest
  static void zip3PrecisionUsesThePlacePrefixOrAnExplicitOne() {
    Fixture f = fixture();
    Test.startTest();
    createLoadsAndQuotes(f);
    LaneSearchRequest q = req('laval|qc|ca', null);
    q.originPrecision = LaneSearchRequest.Precision.ZIP3;
    LaneSearchResult byPlace = LaneSearchService.search(q);
    LaneSearchRequest q2 = req(null, null);
    q2.originPrecision = LaneSearchRequest.Precision.ZIP3;
    q2.originZip3 = 'H1A';
    LaneSearchResult explicit = LaneSearchService.search(q2);
    Test.stopTest();
    System.assertEquals(1, byPlace.rows.size());
    System.assertEquals(2000, byPlace.rows[0].carrierTotal);
    System.assertEquals(1, explicit.rows.size());
    System.assertEquals(1000, explicit.rows[0].carrierTotal);
  }

  @IsTest
  static void blankEndsMeanNoConstraintAndRowsAreNewestFirst() {
    Fixture f = fixture();
    Test.startTest();
    createLoadsAndQuotes(f);
    LaneSearchResult r = LaneSearchService.search(req(null, null));
    Test.stopTest();
    System.assertEquals(2, r.rows.size());
    System.assertEquals(false, r.truncated);
    System.assert(r.elapsedMs >= 0);
  }

  @IsTest
  static void invalidRequestsThrow() {
    fixture();
    LaneSearchRequest bad = req('nowhere|zz|zz', null);
    try {
      LaneSearchService.search(bad);
      System.assert(false, 'unknown key must throw');
    } catch (LaneSearchException e) {
      System.assert(e.getMessage().contains('nowhere|zz|zz'), e.getMessage());
    }
    LaneSearchRequest neg = req(null, null);
    neg.lookbackDays = 0;
    try {
      LaneSearchService.search(neg);
      System.assert(false, 'lookback must be positive');
    } catch (LaneSearchException e) {
      System.assert(e.getMessage().contains('lookbackDays'), e.getMessage());
    }
    LaneSearchRequest noRadius = req('montreal|qc|ca', null);
    noRadius.originPrecision = LaneSearchRequest.Precision.RADIUS;
    try {
      LaneSearchService.search(noRadius);
      System.assert(false, 'radius required');
    } catch (LaneSearchException e) {
      System.assert(e.getMessage().contains('originRadius'), e.getMessage());
    }
  }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `sf project deploy start -m ApexClass:LaneSearchServiceTest -o sandbox -l NoTestRun -w 10`
Expected: `Invalid type: LaneSearchRequest`.

- [ ] **Step 3: Implement the DTOs and the service (lane-key precisions; RADIUS throws "not implemented" until Task 6)**

`LaneSearchException.cls`: `public class LaneSearchException extends Exception {}`

`LaneSearchRequest.cls`:

```apex
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
  public enum Accepted {
    ANY,
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
  public Accepted accepted = Accepted.ANY;
  public Integer rowLimit = 2000;
  public Boolean includeStopGeolocation = true;

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
```

`LaneSearchResult.cls`: exactly the Row/Stats/fields shown in Interfaces above (plain classes with public fields, no logic).

`PricingDepartmentController.cls`: add

```apex
  /** Shared with LaneSearchService so both read the same custom metadata and honor the test override. */
  public static Set<String> excludedContactIdSet() {
    return excludedContactIds();
  }
```

`LaneSearchService.cls` (this task implements everything except the RADIUS branch, which throws until Task 6; Task 7 adds the remaining filters, dedupe and stats — write the skeleton so those land as small edits):

```apex
/**
 * Lane search over rtms__CarrierQuote__c. One dynamic SOQL with bound values,
 * built from a LaneSearchRequest. Precisions map onto Revenova's lane keys on
 * the Load (CITY, PROVINCE, ZIP3) or DISTANCE() through the stops (RADIUS).
 */
// Runs without sharing on purpose: pricing benchmarks every team's quotes. Access is gated by the Lane Benchmark permission sets.
public without sharing class LaneSearchService {
  private static final String SELECT_CLAUSE =
    'SELECT Id, Name, rtms__Load__c, Origin__c, Destination__c, Mode__c, Equipment_Type__c, ' +
    'rtms__Load__r.rtms__Equipment_Type__r.rtms__Category__c, Carrier_Name__c, Carrier_Contact__c, ' +
    'CurrencyIsoCode, rtms__Carrier_Total__c, Quote_Date__c, Hazmat__c, rtms__Accepted__c, Load_Status__c, Ops_Comments__c, ' +
    'CreatedDate FROM rtms__CarrierQuote__c';

  public static LaneSearchResult search(LaneSearchRequest req) {
    req.validate();
    Map<String, Pricing_Place__c> places = loadPlaces(req);
    Map<String, Object> binds = new Map<String, Object>();
    String soql = buildSoql(req, binds, places);
    Long t0 = System.currentTimeMillis();
    List<rtms__CarrierQuote__c> quotes = Database.queryWithBinds(soql, binds, AccessLevel.SYSTEM_MODE);
    LaneSearchResult result = new LaneSearchResult();
    result.elapsedMs = System.currentTimeMillis() - t0;
    result.truncated = quotes.size() > req.rowLimit;
    if (result.truncated) {
      quotes.remove(quotes.size() - 1);
    }
    for (rtms__CarrierQuote__c q : quotes) {
      result.rows.add(toRow(q));
    }
    return result;
  }

  @SuppressWarnings('PMD.ApexCRUDViolation') // system mode by design (see class comment)
  private static Map<String, Pricing_Place__c> loadPlaces(LaneSearchRequest req) {
    Set<String> keys = new Set<String>();
    if (String.isNotBlank(req.originKey)) {
      keys.add(req.originKey);
    }
    if (String.isNotBlank(req.destinationKey)) {
      keys.add(req.destinationKey);
    }
    Map<String, Pricing_Place__c> byKey = new Map<String, Pricing_Place__c>();
    if (keys.isEmpty()) {
      return byKey;
    }
    for (Pricing_Place__c p : [SELECT Key__c, City__c, Province__c, Country__c, Geolocation__Latitude__s, Geolocation__Longitude__s, Postal_Prefix__c, Spellings__c FROM Pricing_Place__c WHERE Key__c IN :keys]) {
      byKey.put(p.Key__c, p);
    }
    for (String k : keys) {
      if (!byKey.containsKey(k)) {
        throw new LaneSearchException('Unknown place key: ' + k);
      }
    }
    return byKey;
  }

  @TestVisible
  private static String buildSoql(LaneSearchRequest req, Map<String, Object> binds, Map<String, Pricing_Place__c> places) {
    List<String> where = new List<String>();
    where.add('CreatedDate = LAST_N_DAYS:' + String.valueOf(req.lookbackDays)); // validated positive integer, not user text
    binds.put('excluded', PricingDepartmentController.excludedContactIdSet());
    where.add('Contact_ID__c NOT IN :excluded');
    addEnd(where, binds, req, places, true);
    addEnd(where, binds, req, places, false);
    // Task 7 adds currency, modes, equipment, hazmat, market test, accepted here.
    binds.put('rowLimitPlusOne', req.rowLimit + 1);
    return SELECT_CLAUSE + ' WHERE ' + String.join(where, ' AND ') + ' ORDER BY CreatedDate DESC LIMIT :rowLimitPlusOne';
  }

  private static void addEnd(List<String> where, Map<String, Object> binds, LaneSearchRequest req, Map<String, Pricing_Place__c> places, Boolean isOrigin) {
    String key = isOrigin ? req.originKey : req.destinationKey;
    LaneSearchRequest.Precision precision = isOrigin ? req.originPrecision : req.destinationPrecision;
    String explicitZip3 = isOrigin ? req.originZip3 : req.destinationZip3;
    String side = isOrigin ? 'o' : 'd';
    Pricing_Place__c place = String.isBlank(key) ? null : places.get(key);
    if (precision == LaneSearchRequest.Precision.ZIP3 && String.isNotBlank(explicitZip3)) {
      binds.put(side + 'Zip3', isOrigin ? escapeLike(explicitZip3) + ':%' : '%:' + escapeLike(explicitZip3));
      where.add('rtms__Load__r.rtms__Zip3_Lane__c LIKE :' + side + 'Zip3');
      return;
    }
    if (place == null) {
      return; // no constraint on this end
    }
    if (precision == LaneSearchRequest.Precision.CITY) {
      List<String> patterns = new List<String>();
      for (String v : PlaceNormalizer.cityLaneVariants(place)) {
        patterns.add(isOrigin ? escapeLike(v) + ':%' : '%:' + escapeLike(v));
      }
      binds.put(side + 'City', patterns);
      where.add('rtms__Load__r.rtms__City_Lane__c LIKE :' + side + 'City');
    } else if (precision == LaneSearchRequest.Precision.PROVINCE) {
      binds.put(side + 'Prov', isOrigin ? escapeLike(place.Province__c) + ':%' : '%:' + escapeLike(place.Province__c));
      where.add('rtms__Load__r.rtms__State_Lane__c LIKE :' + side + 'Prov');
    } else if (precision == LaneSearchRequest.Precision.ZIP3) {
      if (String.isBlank(place.Postal_Prefix__c)) {
        throw new LaneSearchException('Place ' + key + ' has no postal prefix; pass ' + (isOrigin ? 'originZip3' : 'destinationZip3'));
      }
      binds.put(side + 'Zip3', isOrigin ? escapeLike(place.Postal_Prefix__c) + ':%' : '%:' + escapeLike(place.Postal_Prefix__c));
      where.add('rtms__Load__r.rtms__Zip3_Lane__c LIKE :' + side + 'Zip3');
    } else {
      throw new LaneSearchException('RADIUS precision is implemented in Task 6');
    }
  }

  /** Escapes SOQL LIKE wildcards in user-derived text. */
  @TestVisible
  private static String escapeLike(String s) {
    return s == null ? '' : s.replace('\\', '\\\\').replace('%', '\\%').replace('_', '\\_');
  }

  private static LaneSearchResult.Row toRow(rtms__CarrierQuote__c q) {
    LaneSearchResult.Row r = new LaneSearchResult.Row();
    r.quoteId = q.Id;
    r.quoteName = q.Name;
    r.loadId = q.rtms__Load__c;
    r.origin = q.Origin__c;
    r.destination = q.Destination__c;
    r.mode = q.Mode__c;
    r.equipment = q.Equipment_Type__c;
    r.equipmentCategory = q.rtms__Load__r?.rtms__Equipment_Type__r?.rtms__Category__c;
    r.carrierName = q.Carrier_Name__c;
    r.contactName = q.Carrier_Contact__c;
    r.currencyIsoCode = q.CurrencyIsoCode;
    r.carrierTotal = q.rtms__Carrier_Total__c;
    r.quoteDate = q.Quote_Date__c;
    r.hazmat = q.Hazmat__c == 'Hazmat';
    r.accepted = q.rtms__Accepted__c;
    r.loadStatus = q.Load_Status__c;
    r.opsComments = q.Ops_Comments__c;
    return r;
  }
}
```

Notes for the implementer: `LIKE :listBind` (a `List<String>` bound to LIKE) is supported in Apex SOQL and means "matches any"; `Database.queryWithBinds` requires every `:name` in the string to exist in the map. `Quote_Date__c` is the phase 0 formula (ship date or created date). The safe-navigation `?.` operator is available at API 64.

Manifest: add the five classes. CI: add `LaneSearchServiceTest` to `--tests`.

- [ ] **Step 4: Deploy and run**

Run: `sf project deploy start -m ApexClass:PricingDepartmentController -m ApexClass:LaneSearchException -m ApexClass:LaneSearchRequest -m ApexClass:LaneSearchResult -m ApexClass:LaneSearchService -m ApexClass:LaneSearchServiceTest -o sandbox -l RunSpecifiedTests -t LaneSearchServiceTest -w 15`
Expected: 5/5 pass. If `cityPrecisionMatchesOnlyThatCityAndToleratesAccents` returns 0 rows, print `buildSoql` output and the load's actual `rtms__City_Lane__c` in a `System.debug` and compare formats (Task 3 recorded Revenova's format).

- [ ] **Step 5: Commit**

```bash
git checkout -b phase-1/search-service main   # after Task 4's PR merged; otherwise branch from phase-1/place-dictionary
git add force-app/main/default/classes/LaneSearch* force-app/main/default/classes/PricingDepartmentController.cls manifest/package.xml .github/workflows/ci.yml
git commit -m "Add LaneSearchService with CITY, PROVINCE and ZIP3 precisions"
```

---

### Task 6: RADIUS precision

**Files:**

- Modify: `LaneSearchService.cls` (`addEnd` RADIUS branch), `LaneSearchServiceTest.cls`

**Interfaces:**

- Consumes: `Pricing_Place__c.Geolocation__c` coordinates, `req.originRadius/destinationRadius/radiusUnit/includeStopGeolocation`.
- Produces: RADIUS branch as specified.

- [ ] **Step 1: Write the failing tests**

Add to `LaneSearchServiceTest`:

```apex
  @IsTest
  static void radiusPrecisionFindsNearbyOriginsAndRespectsTheRadius() {
    Fixture f = fixture();
    Test.startTest();
    createLoadsAndQuotes(f); // Montreal and Laval (about 10 mi apart) -> Toronto
    LaneSearchRequest wide = req('montreal|qc|ca', 'toronto|on|ca');
    wide.originPrecision = LaneSearchRequest.Precision.RADIUS;
    wide.originRadius = 25;
    LaneSearchResult both = LaneSearchService.search(wide);
    LaneSearchRequest tight = req('montreal|qc|ca', 'toronto|on|ca');
    tight.originPrecision = LaneSearchRequest.Precision.RADIUS;
    tight.originRadius = 3;
    LaneSearchResult onlyMtl = LaneSearchService.search(tight);
    Test.stopTest();
    System.assertEquals(2, both.rows.size(), 'Laval is within 25 mi of Montreal');
    System.assertEquals(1, onlyMtl.rows.size(), 'Laval is not within 3 mi');
    System.assertEquals(1000, onlyMtl.rows[0].carrierTotal);
  }

  @IsTest
  static void radiusInKilometersAndStopGeolocationFallback() {
    Fixture f = fixture();
    Test.startTest();
    createLoadsAndQuotes(f);
    // Remove the account coordinates from Laval's location so only the stop's own geolocation can match.
    f.laval.ShippingLatitude = null;
    f.laval.ShippingLongitude = null;
    update f.laval;
    LaneSearchRequest km = req('montreal|qc|ca', null);
    km.originPrecision = LaneSearchRequest.Precision.RADIUS;
    km.originRadius = 40;
    km.radiusUnit = LaneSearchRequest.Unit.KM;
    LaneSearchResult withStops = LaneSearchService.search(km);
    km.includeStopGeolocation = false;
    LaneSearchResult accountsOnly = LaneSearchService.search(km);
    Test.stopTest();
    System.assertEquals(2, withStops.rows.size(), 'Laval matched through its stop geolocation');
    System.assertEquals(1, accountsOnly.rows.size(), 'without the fallback only Montreal matches');
  }
```

- [ ] **Step 2: Run to verify it fails**

Run: `sf project deploy start -m ApexClass:LaneSearchServiceTest -o sandbox -l RunSpecifiedTests -t LaneSearchServiceTest -w 15`
Expected: the two new tests fail with `LaneSearchException: RADIUS precision is implemented in Task 6`.

- [ ] **Step 3: Implement**

Replace the final `else` in `addEnd` with:

```apex
    } else { // RADIUS
      if (place.Geolocation__Latitude__s == null || place.Geolocation__Longitude__s == null) {
        throw new LaneSearchException('Place ' + key + ' has no coordinates');
      }
      String unit = req.radiusUnit == LaneSearchRequest.Unit.KM ? 'km' : 'mi'; // enum-controlled literal, never user text
      String stopRel = isOrigin ? 'rtms__Load__r.rtms__First_Stop__r' : 'rtms__Load__r.rtms__Last_Stop__r';
      binds.put(side + 'Lat', place.Geolocation__Latitude__s);
      binds.put(side + 'Lng', place.Geolocation__Longitude__s);
      binds.put(side + 'Radius', isOrigin ? req.originRadius : req.destinationRadius);
      String geo = 'GEOLOCATION(:' + side + 'Lat, :' + side + 'Lng)';
      String byAccount = 'DISTANCE(' + stopRel + '.rtms__Location2__r.ShippingAddress, ' + geo + ', \'' + unit + '\') < :' + side + 'Radius';
      if (req.includeStopGeolocation) {
        String byStop = 'DISTANCE(' + stopRel + '.rtms__Geolocation__c, ' + geo + ', \'' + unit + '\') < :' + side + 'Radius';
        where.add('(' + byAccount + ' OR ' + byStop + ')');
      } else {
        where.add(byAccount);
      }
    }
```

If the platform rejects bound variables inside `GEOLOCATION()` in `queryWithBinds` ("unexpected token"), fall back to formatting the two decimals into the string with `String.valueOf(Decimal)` after `setScale(6)`; they come from our own object, not user text, so this is safe. Record which form worked in the class comment.

- [ ] **Step 4: Deploy and run**

Run: `sf project deploy start -m ApexClass:LaneSearchService -m ApexClass:LaneSearchServiceTest -o sandbox -l RunSpecifiedTests -t LaneSearchServiceTest -w 15`
Expected: 7/7 pass.

- [ ] **Step 5: Timing check on real data (anonymous Apex, read-only)**

Create `scripts/apex/laneSearchExample.apex`:

```apex
// Montreal -> Toronto at each precision, last 90 days. Read-only. Prints rows, truncation, and elapsed ms.
List<LaneSearchRequest.Precision> precisions = new List<LaneSearchRequest.Precision>{
  LaneSearchRequest.Precision.CITY, LaneSearchRequest.Precision.PROVINCE, LaneSearchRequest.Precision.ZIP3, LaneSearchRequest.Precision.RADIUS };
for (LaneSearchRequest.Precision p : precisions) {
  LaneSearchRequest r = new LaneSearchRequest();
  r.originKey = 'montreal|qc|ca';
  r.destinationKey = 'toronto|on|ca';
  r.originPrecision = p;
  r.destinationPrecision = p;
  r.originRadius = 100;
  r.destinationRadius = 100;
  r.lookbackDays = 90;
  LaneSearchResult res = LaneSearchService.search(r);
  System.debug('LANE ' + p + ' rows=' + res.rows.size() + ' truncated=' + res.truncated + ' ms=' + res.elapsedMs + ' stats=' + JSON.serialize(res.statsByCurrency));
}
LaneSearchRequest r2 = new LaneSearchRequest();
r2.originKey = 'montreal|qc|ca'; r2.destinationKey = 'toronto|on|ca';
r2.originPrecision = LaneSearchRequest.Precision.RADIUS; r2.destinationPrecision = LaneSearchRequest.Precision.RADIUS;
r2.originRadius = 100; r2.destinationRadius = 100; r2.lookbackDays = 365; r2.includeStopGeolocation = false;
System.debug('LANE RADIUS-365-accountsOnly ms=' + LaneSearchService.search(r2).elapsedMs);
r2.includeStopGeolocation = true;
System.debug('LANE RADIUS-365-withStops ms=' + LaneSearchService.search(r2).elapsedMs);
```

This needs the place dictionary in PostProduc (Task 8 runs the batch). If the batch has not run yet, insert the three places by hand in this script before searching and delete them at the end, inside a savepoint/rollback. Run: `sf apex run -f scripts/apex/laneSearchExample.apex -o sandbox | grep LANE`. Record the timings in the report; they go into the spec's Outcome in Task 8.

- [ ] **Step 6: Commit**

```bash
git add force-app/main/default/classes/LaneSearch* scripts/apex/laneSearchExample.apex
git commit -m "LaneSearchService: RADIUS precision via account address or stop geolocation"
```

---

### Task 7: Remaining filters, dedupe, per-currency statistics

**Files:**

- Modify: `LaneSearchService.cls`, `LaneSearchServiceTest.cls`

**Interfaces:**

- Consumes: factory `createEquipment`, `createMode`, `createLoad(Graph, Account, Account, rtms__Mode__c)`, `createLoad(Graph, Account, Account, Boolean hazmat)`, `createLoad(Graph, Account, Account, Account customer)`, `buildQuote(..., currency)`.
- Produces: complete `LaneSearchResult` with `statsByCurrency`, `dedupedCount`.

- [ ] **Step 1: Write the failing tests**

```apex
  @IsTest
  static void statsAreComputedPerCurrencyWithMedianAndZerosCounted() {
    Fixture f = fixture();
    Test.startTest();
    f.mtlTor = PricingTestDataFactory.createLoad(f.g, f.g.originLocation, f.g.destinationLocation);
    insert new List<rtms__CarrierQuote__c>{
      PricingTestDataFactory.buildQuote(f.g, f.mtlTor, 1000, 'CAD'),
      PricingTestDataFactory.buildQuote(f.g, f.mtlTor, 3000, 'CAD'),
      PricingTestDataFactory.buildQuote(f.g, f.mtlTor, 2000, 'CAD'),
      PricingTestDataFactory.buildQuote(f.g, f.mtlTor, 0, 'CAD'),
      PricingTestDataFactory.buildQuote(f.g, f.mtlTor, 800, 'USD'),
      PricingTestDataFactory.buildQuote(f.g, f.mtlTor, 1200, 'USD')
    };
    LaneSearchResult all = LaneSearchService.search(req(null, null));
    LaneSearchRequest usdOnly = req(null, null);
    usdOnly.currencyIsoCode = 'USD';
    LaneSearchResult usd = LaneSearchService.search(usdOnly);
    Test.stopTest();
    LaneSearchResult.Stats cad = all.statsByCurrency.get('CAD');
    System.assertEquals(4, cad.count);
    System.assertEquals(3, cad.countNonZero);
    System.assertEquals(1000, cad.min);
    System.assertEquals(3000, cad.max);
    System.assertEquals(2000, cad.avg);
    System.assertEquals(2000, cad.median, 'odd count: middle value');
    LaneSearchResult.Stats us = all.statsByCurrency.get('USD');
    System.assertEquals(2, us.count);
    System.assertEquals(1000, us.median, 'even count: mean of the two middle values');
    System.assertEquals(2, usd.rows.size());
    System.assertEquals(false, usd.statsByCurrency.containsKey('CAD'));
  }

  @IsTest
  static void modeAndEquipmentFiltersCombine() {
    Fixture f = fixture();
    rtms__Mode__c ltl = PricingTestDataFactory.createMode('LTL');
    rtms__EquipmentType__c reefer = PricingTestDataFactory.createEquipment('Reefer 53\'', 'Reefer');
    Test.startTest();
    rtms__Load__c van = PricingTestDataFactory.createLoad(f.g, f.g.originLocation, f.g.destinationLocation);
    rtms__Load__c ltlLoad = PricingTestDataFactory.createLoad(f.g, f.g.originLocation, f.g.destinationLocation, ltl);
    ltlLoad.rtms__Equipment_Type__c = reefer.Id;
    update ltlLoad;
    insert new List<rtms__CarrierQuote__c>{
      PricingTestDataFactory.buildQuote(f.g, van, 1000), PricingTestDataFactory.buildQuote(f.g, ltlLoad, 500) };
    LaneSearchRequest byMode = req(null, null);
    byMode.modes = new List<String>{ 'LTL' };
    LaneSearchRequest byCategory = req(null, null);
    byCategory.equipmentCategories = new List<String>{ 'Van' };
    LaneSearchRequest byType = req(null, null);
    byType.equipmentTypes = new List<String>{ 'Reefer 53\'' };
    LaneSearchRequest catOrType = req(null, null);
    catOrType.equipmentCategories = new List<String>{ 'Van' };
    catOrType.equipmentTypes = new List<String>{ 'Reefer 53\'' };
    LaneSearchResult m = LaneSearchService.search(byMode);
    LaneSearchResult c = LaneSearchService.search(byCategory);
    LaneSearchResult t = LaneSearchService.search(byType);
    LaneSearchResult ct = LaneSearchService.search(catOrType);
    Test.stopTest();
    System.assertEquals(1, m.rows.size()); System.assertEquals(500, m.rows[0].carrierTotal);
    System.assertEquals(1, c.rows.size()); System.assertEquals(1000, c.rows[0].carrierTotal);
    System.assertEquals(1, t.rows.size()); System.assertEquals(500, t.rows[0].carrierTotal);
    System.assertEquals(2, ct.rows.size(), 'categories OR types');
  }

  @IsTest
  static void hazmatMarketTestAcceptedAndExcludedContactFilters() {
    Fixture f = fixture();
    Account marketTest = f.g.customer.clone(false, true, false, false);
    marketTest.Name = 'Market Test';
    insert marketTest;
    Test.startTest();
    rtms__Load__c plain = PricingTestDataFactory.createLoad(f.g, f.g.originLocation, f.g.destinationLocation);
    rtms__Load__c haz = PricingTestDataFactory.createLoad(f.g, f.g.originLocation, f.g.destinationLocation, true);
    rtms__Load__c mt = PricingTestDataFactory.createLoad(f.g, f.g.originLocation, f.g.destinationLocation, marketTest);
    rtms__CarrierQuote__c accepted = PricingTestDataFactory.buildQuote(f.g, plain, 1000);
    accepted.rtms__Accepted__c = true;
    insert new List<rtms__CarrierQuote__c>{ accepted, PricingTestDataFactory.buildQuote(f.g, haz, 2000), PricingTestDataFactory.buildQuote(f.g, mt, 3000) };
    LaneSearchRequest h = req(null, null); h.hazmatOnly = true;
    LaneSearchRequest m = req(null, null); m.marketTestOnly = true;
    LaneSearchRequest a = req(null, null); a.accepted = LaneSearchRequest.Accepted.ACCEPTED;
    LaneSearchRequest d = req(null, null); d.accepted = LaneSearchRequest.Accepted.DECLINED;
    LaneSearchResult rh = LaneSearchService.search(h);
    LaneSearchResult rm = LaneSearchService.search(m);
    LaneSearchResult ra = LaneSearchService.search(a);
    LaneSearchResult rd = LaneSearchService.search(d);
    PricingDepartmentController.excludedContactIdsOverride = new Set<String>{ String.valueOf(f.g.quoteContact.Id).left(15) };
    LaneSearchResult none = LaneSearchService.search(req(null, null));
    Test.stopTest();
    System.assertEquals(2000, rh.rows[0].carrierTotal); System.assertEquals(1, rh.rows.size());
    System.assertEquals(3000, rm.rows[0].carrierTotal); System.assertEquals(1, rm.rows.size());
    System.assertEquals(1, ra.rows.size()); System.assertEquals(1000, ra.rows[0].carrierTotal);
    System.assertEquals(2, rd.rows.size());
    System.assertEquals(0, none.rows.size(), 'excluded contact hides every quote from that contact');
  }

  @IsTest
  static void identicalQuotesAreDedupedAndCountedAndTruncationIsFlagged() {
    Fixture f = fixture();
    Test.startTest();
    f.mtlTor = PricingTestDataFactory.createLoad(f.g, f.g.originLocation, f.g.destinationLocation);
    List<rtms__CarrierQuote__c> qs = new List<rtms__CarrierQuote__c>();
    for (Integer i = 0; i < 5; i++) {
      qs.add(PricingTestDataFactory.buildQuote(f.g, f.mtlTor, 1000)); // identical
    }
    qs.add(PricingTestDataFactory.buildQuote(f.g, f.mtlTor, 1500));
    insert qs;
    LaneSearchResult r = LaneSearchService.search(req(null, null));
    LaneSearchRequest small = req(null, null);
    small.rowLimit = 2;
    LaneSearchResult capped = LaneSearchService.search(small);
    Test.stopTest();
    System.assertEquals(2, r.rows.size(), 'five identical collapse to one, plus the 1500');
    System.assertEquals(4, r.dedupedCount);
    System.assertEquals(true, capped.truncated);
    System.assertEquals(2, capped.rows.size() + capped.dedupedCount, 'cap applies before dedupe');
  }

  @IsTest
  static void lookbackWindowIsRespected() {
    Fixture f = fixture();
    Test.startTest();
    f.mtlTor = PricingTestDataFactory.createLoad(f.g, f.g.originLocation, f.g.destinationLocation);
    rtms__CarrierQuote__c recent = PricingTestDataFactory.buildQuote(f.g, f.mtlTor, 1000);
    rtms__CarrierQuote__c old = PricingTestDataFactory.buildQuote(f.g, f.mtlTor, 2000);
    insert new List<rtms__CarrierQuote__c>{ recent, old };
    Test.setCreatedDate(recent.Id, Datetime.now().addDays(-2));
    Test.setCreatedDate(old.Id, Datetime.now().addDays(-400));
    LaneSearchRequest ninety = req(null, null);
    LaneSearchRequest twoYears = req(null, null);
    twoYears.lookbackDays = 730;
    LaneSearchResult r90 = LaneSearchService.search(ninety);
    LaneSearchResult r730 = LaneSearchService.search(twoYears);
    Test.stopTest();
    System.assertEquals(1, r90.rows.size());
    System.assertEquals(2, r730.rows.size(), 'any lookback is accepted');
  }
```

- [ ] **Step 2: Run to verify they fail**

Run: `sf project deploy start -m ApexClass:LaneSearchServiceTest -o sandbox -l RunSpecifiedTests -t LaneSearchServiceTest -w 15`
Expected: the five new tests fail (no stats, no filters, no dedupe).

- [ ] **Step 3: Implement**

In `buildSoql`, replace the Task 7 comment with:

```apex
    if (String.isNotBlank(req.currencyIsoCode)) {
      binds.put('currencyCode', req.currencyIsoCode);
      where.add('CurrencyIsoCode = :currencyCode');
    }
    if (req.modes != null && !req.modes.isEmpty()) {
      binds.put('modes', req.modes);
      where.add('rtms__Load__r.rtms__Mode__r.Name IN :modes');
    }
    Boolean hasCats = req.equipmentCategories != null && !req.equipmentCategories.isEmpty();
    Boolean hasTypes = req.equipmentTypes != null && !req.equipmentTypes.isEmpty();
    if (hasCats && hasTypes) {
      binds.put('cats', req.equipmentCategories);
      binds.put('types', req.equipmentTypes);
      where.add('(rtms__Load__r.rtms__Equipment_Type__r.rtms__Category__c IN :cats OR rtms__Load__r.rtms__Equipment_Type__r.Name IN :types)');
    } else if (hasCats) {
      binds.put('cats', req.equipmentCategories);
      where.add('rtms__Load__r.rtms__Equipment_Type__r.rtms__Category__c IN :cats');
    } else if (hasTypes) {
      binds.put('types', req.equipmentTypes);
      where.add('rtms__Load__r.rtms__Equipment_Type__r.Name IN :types');
    }
    if (req.hazmatOnly == true) {
      where.add('rtms__Load__r.rtms__Hazardous_Materials__c = true');
    }
    if (req.marketTestOnly == true) {
      binds.put('marketTest', '%Market Test%');
      where.add('Customer_Name__c LIKE :marketTest');
    }
    if (req.accepted == LaneSearchRequest.Accepted.ACCEPTED) {
      where.add('rtms__Accepted__c = true');
    } else if (req.accepted == LaneSearchRequest.Accepted.DECLINED) {
      where.add('rtms__Accepted__c = false');
    }
```

In `search`, after trimming the extra row, replace the row loop with dedupe + stats:

```apex
    Set<String> seen = new Set<String>();
    Map<String, List<Decimal>> totalsByCurrency = new Map<String, List<Decimal>>();
    for (rtms__CarrierQuote__c q : quotes) {
      String fingerprint = String.valueOf(q.rtms__Carrier_Total__c) + '|' + q.Carrier_Name__c + '|' + q.Origin__c + '|' + q.Destination__c + '|' + q.Mode__c + '|' + q.Equipment_Type__c;
      if (seen.contains(fingerprint)) {
        result.dedupedCount++;
        continue;
      }
      seen.add(fingerprint);
      result.rows.add(toRow(q));
      String cur = q.CurrencyIsoCode == null ? 'CAD' : q.CurrencyIsoCode;
      if (!totalsByCurrency.containsKey(cur)) {
        totalsByCurrency.put(cur, new List<Decimal>());
      }
      totalsByCurrency.get(cur).add(q.rtms__Carrier_Total__c == null ? 0 : q.rtms__Carrier_Total__c);
    }
    for (String cur : totalsByCurrency.keySet()) {
      result.statsByCurrency.put(cur, stats(totalsByCurrency.get(cur)));
    }
```

and add:

```apex
  @TestVisible
  private static LaneSearchResult.Stats stats(List<Decimal> totals) {
    LaneSearchResult.Stats s = new LaneSearchResult.Stats();
    List<Decimal> nonZero = new List<Decimal>();
    for (Decimal t : totals) {
      s.count++;
      if (t != 0) {
        nonZero.add(t);
      }
    }
    s.countNonZero = nonZero.size();
    if (nonZero.isEmpty()) {
      return s;
    }
    nonZero.sort();
    Decimal sum = 0;
    for (Decimal t : nonZero) {
      sum += t;
    }
    s.min = nonZero[0];
    s.max = nonZero[nonZero.size() - 1];
    s.avg = (sum / nonZero.size()).setScale(2);
    Integer n = nonZero.size();
    s.median = Math.mod(n, 2) == 1 ? nonZero[n / 2] : ((nonZero[n / 2 - 1] + nonZero[n / 2]) / 2).setScale(2);
    return s;
  }
```

The dedupe fingerprint reproduces `PricingDepartmentController.UniqueCarrierQuote` (total, carrier, origin, destination, mode, equipment) but on `rtms__Carrier_Total__c` so USD quotes dedupe too. Stats exclude zero totals from min/max/avg/median but count them, matching the phase 0 statistics.

Also add `Customer_Name__c` to `SELECT_CLAUSE` (used by nothing in Row, but harmless; or leave it out of SELECT since the filter does not require selecting). Leave it out.

- [ ] **Step 4: Deploy and run everything**

Run: `sf project deploy start -x manifest/package.xml -o sandbox -l RunSpecifiedTests -t PricingDepartmentControllerTest PlaceNormalizerTest PricingTestDataFactoryTest PlaceBuilderBatchTest LaneSearchServiceTest -w 30`
Expected: Succeeded; LaneSearchServiceTest 12/12; all others still green. Run the local PMD command from phase 0 (`pmd check --dir force-app --rulesets config/pmd-ruleset.xml --minimum-priority 3 --format text --fail-on-violation`) and fix any violation.

- [ ] **Step 5: Commit, push, PR, merge, deploy**

```bash
git add force-app/main/default/classes/LaneSearch* manifest/package.xml .github/workflows/ci.yml
git commit -m "LaneSearchService: filters, dedupe and per-currency statistics"
git push -u origin phase-1/search-service
WT=$(gh auth token -u IulianEnescu) && git -c credential.helper= -c "credential.helper=!f() { echo username=IulianEnescu; echo password=$WT; }; f" push -u tplm phase-1/search-service
gh pr create --base main --head phase-1/search-service --title "Phase 1: LaneSearchService" --body "Tasks 5-7 of docs/superpowers/plans/2026-09-09-phase-1-search-foundation.md"
GH_TOKEN=$WT gh pr create -R TPLM/PricingDepartment --base main --head phase-1/search-service --title "Phase 1: LaneSearchService" --body "Tasks 5-7 of docs/superpowers/plans/2026-09-09-phase-1-search-foundation.md"
```

Watch both; merge on origin only; mirror `main` to tplm; deploy `main` to PostProduc with the full manifest and all five test classes.

---

### Task 8: Build the dictionary in PostProduc, measure, document

**Files:**

- Modify: `README.md`, `docs/superpowers/specs/2026-09-09-phase-1-search-foundation-design.md` (Outcome), `docs/superpowers/specs/2026-09-07-pricing-department-roadmap.md` (phase 1 status)

**Interfaces:**

- Consumes: everything above, deployed to PostProduc.

- [ ] **Step 1: Run the batch in PostProduc**

```bash
sf apex run -o sandbox <<'EOF'
Id jobId = Database.executeBatch(new PlaceBuilderBatch(), 2000);
System.debug('PLACEBUILDER ' + jobId);
EOF
```

Poll until both jobs finish: `sf data query -q "SELECT ApexClass.Name, Status, JobItemsProcessed, TotalJobItems, NumberOfErrors FROM AsyncApexJob WHERE ApexClass.Name IN ('PlaceBuilderBatch','PlaceUsageBatch') ORDER BY CreatedDate DESC LIMIT 2" -o sandbox` (expect both `Completed`, 0 errors; the usage batch starts after the builder finishes).

- [ ] **Step 2: Record what was built**

```bash
sf data query -q "SELECT COUNT() FROM Pricing_Place__c" -o sandbox
sf data query -q "SELECT Name, Key__c, Location_Count__c, Load_Count_365d__c, Postal_Prefix__c FROM Pricing_Place__c ORDER BY Load_Count_365d__c DESC NULLS LAST LIMIT 20" -o sandbox
sf data query -q "SELECT Name, Key__c, Spellings__c FROM Pricing_Place__c WHERE Key__c LIKE 'montreal|%'" -o sandbox
```

Expected: one `montreal|qc|ca` place whose Spellings include both "Montréal" and "Montreal" (and possibly "MONTREAL"); a total in the low thousands. Paste the count and the top 20 into the README under a new "### Place dictionary" subsection, with the run date and the command to rerun the batch.

- [ ] **Step 3: Run the example script against real data**

Run: `sf apex run -f scripts/apex/laneSearchExample.apex -o sandbox | grep LANE`
Record every `LANE` line under an `## Outcome (date)` heading in the phase 1 spec: rows, truncated, ms per precision at 90 days, and the two 365-day radius timings (accounts only vs with stop geolocation). If the with-stops form is more than 1.5x slower, add a sentence recommending phase 2 default `includeStopGeolocation = false` with a UI toggle; otherwise keep the default true.

- [ ] **Step 4: README and roadmap**

README: add the Place dictionary subsection (Step 2), a "Lane search" subsection with the example script path and one sample request in Apex, the CI test list, and a "Support case" line: `Custom-index request for rtms__Load__c.rtms__City_Lane__c / rtms__State_Lane__c / rtms__Zip3_Lane__c: case number ______ (filed by the user)`. Roadmap: phase 1 row status → "Done <date>".

- [ ] **Step 5: Definition of done check, PR, merge, mirror**

Verify each spec item: (1) all classes deployed through CI, (2) batch run and recorded, (3) all tests pass in PostProduc (list the deploy request id), (4) example script timings recorded, (5) support case line present (number filled by the user later), (6) roadmap updated. Commit docs on branch `phase-1/outcome`, PR in both repos, merge on origin, mirror.

---

## Self-review

**Spec coverage.** Place dictionary object and fields: Task 1 (plus `Spellings__c`, `Postal_Prefix__c` needed by the spec's prose). `PlaceNormalizer` key rules, province/country maps, `cityLaneVariants`: Task 2. `PlaceBuilderBatch` semantics (upsert by key, never delete, never overwrite aliases/active, chain usage batch): Task 4. Factory extensions (second location pair, USD quotes, equipment with category, mode by name; no bulk helper): Task 3. `LaneSearchRequest` fields incl. lookback default 90 uncapped, rowLimit 2000; precision mapping CITY/PROVINCE/ZIP3: Task 5; RADIUS with account-or-stop OR and `includeStopGeolocation`: Task 6; currency/modes/categories/types/hazmat/market test/accepted/excluded contacts, dedupe, per-currency stats with median, truncation, elapsedMs: Task 7. Error handling (`LaneSearchException`, no silent fallbacks): Tasks 5-6. Testing list: Tasks 2-7 (normalizer, batch incl. rerun, service per precision, lookback boundary, currency split and median odd/even, filters, excluded contact, dedupe count, truncation, invalid requests). Definition of done items 1-6: Task 8 (support case is the user's action; the plan records the placeholder). Search center from the dictionary only: `loadPlaces` throws on unknown keys (Task 5).

**Placeholders.** None. The one intentionally odd assertion (Nuevo León) is explained and corrected in Task 2 Step 1's note; the Postal_Prefix assertion in Task 4 has a stated simplification.

**Type consistency.** `createLocation(String, String, String, String, String, Decimal, Decimal)` (Task 3) matches every call in Tasks 4-7. `buildQuote(Graph, rtms__Load__c, Decimal, String)` matches Task 7. `createLoad(Graph, Account, Account, rtms__Mode__c)` / `(…, Boolean)` / `(…, Account)` exist from phase 0 and are used in Task 7 with those argument types. `PlaceNormalizer.key/provinceCode/cityLaneSide/cityLaneVariants/stripAccents` signatures match between Tasks 2, 3, 4, 5. `PricingDepartmentController.excludedContactIdSet()` is defined in Task 5 and used there. `LaneSearchRequest` field names in Tasks 5-7 tests match the class. `LaneSearchResult.Row/Stats` fields match `toRow` and `stats`. Bind names used in `buildSoql` are unique per end (`oCity`/`dCity`, `oZip3`/`dZip3`, `oProv`/`dProv`, `oLat`/`dLat`, ...).
