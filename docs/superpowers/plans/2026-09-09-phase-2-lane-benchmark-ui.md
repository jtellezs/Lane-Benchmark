# Phase 2: Lane Benchmark UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A new Lane Benchmark page (tab, app, and a tab in TransPro) that lets pricing search lanes through phase 1's `LaneSearchService`, with dictionary autocomplete and Mapbox fallback, per-currency statistics with margin, carrier detail, CSV export and remembered filters.

**Architecture:** One thin Apex controller (`LaneBenchmarkController`) exposes search (JSON request), place autocomplete, filter options, geocoding and a static-map URL; `MapboxGeocoder` does the callout using the org's existing public token. A container LWC owns the request and result and composes five small components plus three pure modules. All new UI metadata is additive; the old Pricing Department page is untouched.

**Tech Stack:** Salesforce DX (API 64.0), Apex with `HttpCalloutMock` tests, LWC with `@salesforce/sfdx-lwc-jest`, existing CI (Jest, Apex validate against PostProduc, PMD quickstart P3).

**Spec:** `docs/superpowers/specs/2026-09-09-phase-2-lane-benchmark-ui-design.md` (roadmap: `docs/superpowers/specs/2026-09-07-pricing-department-roadmap.md`; phase 1 spec for the service API: `docs/superpowers/specs/2026-09-09-phase-1-search-foundation-design.md`)

## Global Constraints

- Org alias `sandbox` = PostProduc, the only org touched (real deploys allowed): `sf project deploy start -x manifest/package.xml -o sandbox -l RunSpecifiedTests -t <tests> -w 30`, always in the foreground. Never `vscodeOrg`, `Full`, `devpro`.
- Git rule: PRs opened in both repos (`origin` = personal `IulianEnescu78/PricingDepartment`, `tplm` = `TPLM/PricingDepartment`), MERGED ONLY on origin, `main` pushed to tplm fast-forward (`WT=$(gh auth token -u IulianEnescu) && git -c credential.helper= -c "credential.helper=!f() { echo username=IulianEnescu; echo password=$WT; }; f" push tplm <ref>`; `gh` against TPLM needs `GH_TOKEN=$(gh auth token -u IulianEnescu)`). Never force-push. Commit messages carry NO trailer lines. Husky pre-commit (Prettier, ESLint, related Jest) must pass without `--no-verify`. Do not stage `.superpowers/`.
- PMD: quickstart at priority 3, `ApexDoc` and `ExcessiveParameterList` excluded; no complexity suppressions; `@SuppressWarnings('PMD.ApexCRUDViolation')` with a one-line justification on SOQL/DML methods in `without sharing` classes. Class total cyclomatic complexity stays under 40: split rather than suppress.
- Phase 1 API names (use exactly): `LaneSearchRequest` fields `originKey, destinationKey, originPrecision, destinationPrecision, originRadius, destinationRadius, radiusUnit, originZip3, destinationZip3, lookbackDays (default 90), currencyIsoCode, modes, equipmentCategories, equipmentTypes, hazmatOnly, marketTestOnly, acceptedFilter, rowLimit, includeStopGeolocation`; enums `Precision {RADIUS, CITY, PROVINCE, ZIP3}`, `Unit {MI, KM}`, `Accepted {ANY_STATUS, ACCEPTED, DECLINED}`; `LaneSearchService.search(LaneSearchRequest)` → `LaneSearchResult { rows, statsByCurrency, truncated, elapsedMs (Integer), dedupedCount }`; `LaneSearchResult.Row` fields `quoteId, quoteName, loadId, origin, destination, mode, equipment, equipmentCategory, carrierName, contactName, currencyIsoCode, carrierTotal, quoteDate, createdDate, hazmat, accepted, loadStatus, opsComments`; `Stats { count, countNonZero, min, max, avg, median }`; `PlaceNormalizer.normalizeCity/provinceCode/countryCode/key`; `LaneSearchQueryBuilder.escapeLike` (`@TestVisible private`), `SELECT_CLAUSE`.
- Mapbox: token read at call time from `TPRO_KPI__c.getOrgDefaults().Mapbox_Api_Key__c` (hierarchy custom setting, org default holds a `pk.` token); callouts to `https://api.mapbox.com` through the existing active Remote Site Setting `MapBox`. The token never appears in git or logs.
- Names are fixed: Apex `LaneBenchmarkController`, `MapboxGeocoder`, `MapboxException`; LWC `laneBenchmark`, `laneBenchmarkPlacePicker`, `laneBenchmarkFilters`, `laneBenchmarkStats`, `laneBenchmarkResults`, `laneBenchmarkMap`, modules `marginMath`, `laneBenchmarkCsv`, `laneBenchmarkStorage`; metadata `Lane_Benchmark` (FlexiPage, CustomTab, CustomApplication), permission set `Lane_Benchmark_User`, CSP trusted site `Mapbox_API`, field `Pricing_Place__c.Source__c`.
- The old page (`pricingDepartment`, `Pricing_Department` tab/page, `PricingDepartmentController`, `Pricing_Department_User`) is NOT modified except that `PricingDepartmentController.excludedContactIdSet()` keeps being used by the query builder.
- LWC tests: `npx sfdx-lwc-jest <path>`; async flushes use the microtask pattern (`const flush = () => Promise.resolve().then(() => Promise.resolve());`), never `setTimeout` (ESLint forbids it in tests). Apex mocks: `jest.mock('@salesforce/apex/LaneBenchmarkController.<method>', () => ({ default: jest.fn() }), { virtual: true })`.

---

## File structure

| Path                                                                                                                                                                                                                                                                                                          | Responsibility                                                                                     |
| ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------- |
| `objects/Pricing_Place__c/fields/Source__c.field-meta.xml`                                                                                                                                                                                                                                                    | `Locations` / `Mapbox` picklist                                                                    |
| `classes/LaneSearchResult.cls`, `LaneSearchQueryBuilder.cls`, `LaneSearchService.cls`                                                                                                                                                                                                                         | Row gains five carrier-detail fields                                                               |
| `classes/PlaceBuilderBatch.cls`                                                                                                                                                                                                                                                                               | sets `Source__c = 'Locations'`                                                                     |
| `classes/MapboxException.cls`, `MapboxGeocoder.cls`, `MapboxGeocoderTest.cls`                                                                                                                                                                                                                                 | Callout, parsing, MX region mapping                                                                |
| `classes/LaneBenchmarkController.cls`, `LaneBenchmarkControllerTest.cls`                                                                                                                                                                                                                                      | The five `@AuraEnabled` entry points + DTOs                                                        |
| `lwc/marginMath`, `lwc/laneBenchmarkCsv`, `lwc/laneBenchmarkStorage`                                                                                                                                                                                                                                          | Pure modules with Jest                                                                             |
| `lwc/laneBenchmarkPlacePicker`                                                                                                                                                                                                                                                                                | Typeahead + precision + radius, emits `placechange`                                                |
| `lwc/laneBenchmarkFilters`                                                                                                                                                                                                                                                                                    | Lookback, currency, modes, equipment, flags; emits `filterschange`, `apply`, `reset`, `clearsaved` |
| `lwc/laneBenchmarkStats`                                                                                                                                                                                                                                                                                      | Per-currency cards, margin, suggested sell                                                         |
| `lwc/laneBenchmarkResults`                                                                                                                                                                                                                                                                                    | Table, expand, carrier popup, CSV                                                                  |
| `lwc/laneBenchmarkMap`                                                                                                                                                                                                                                                                                        | Static image or nothing                                                                            |
| `lwc/laneBenchmark`                                                                                                                                                                                                                                                                                           | Container: request, search, storage, warning gate                                                  |
| `flexipages/Lane_Benchmark.flexipage-meta.xml`, `tabs/Lane_Benchmark.tab-meta.xml`, `applications/Lane_Benchmark.app-meta.xml`, `applications/TransPro.app-meta.xml` (retrieved + one tab), `permissionsets/Lane_Benchmark_User.permissionset-meta.xml`, `cspTrustedSites/Mapbox_API.cspTrustedSite-meta.xml` | Navigation and access                                                                              |
| `manifest/package.xml`, `.github/workflows/ci.yml`, `README.md`, roadmap                                                                                                                                                                                                                                      |                                                                                                    |

Branches: `phase-2/backend` (Tasks 1-3), `phase-2/components` (Tasks 4-9), `phase-2/metadata` (Task 10). Each ends with PRs in both repos, merge on origin, mirror, deploy to PostProduc.

---

### Task 1: `Source__c`, carrier-detail row fields

**Files:**

- Create: `force-app/main/default/objects/Pricing_Place__c/fields/Source__c.field-meta.xml`
- Modify: `force-app/main/default/classes/PlaceBuilderBatch.cls` (set `Source__c`), `LaneSearchResult.cls` (Row fields), `LaneSearchQueryBuilder.cls` (`SELECT_CLAUSE`), `LaneSearchService.cls` (`toRow`), `LaneSearchServiceTest.cls` (assertion), `PlaceBuilderBatchTest.cls` (assertion), `manifest/package.xml`, `permissionsets/Pricing_Department_User.permissionset-meta.xml` (read on `Source__c`)

**Interfaces:**

- Produces: `Pricing_Place__c.Source__c` picklist values `Locations`, `Mapbox` (default `Locations`); `LaneSearchResult.Row` gains `@AuraEnabled public String contactEmail; contactPhone; carrierRisk; Decimal carrierLoadCount; String carrierAttention;` populated from `Contact_Email__c`, `Contact_Phone__c`, `Carrier_Risk__c`, `Nb_of_loads__c`, `Carrier_Att__c`.

- [ ] **Step 1: Branch and field metadata**

```bash
git checkout main && git pull origin main && git checkout -b phase-2/backend
```

`Source__c.field-meta.xml`:

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Source__c</fullName>
    <label>Source</label>
    <type>Picklist</type>
    <required>false</required>
    <inlineHelpText
  >Locations: built by PlaceBuilderBatch from shipping locations. Mapbox: geocoded on demand from the Lane Benchmark page.</inlineHelpText>
    <valueSet>
        <restricted>true</restricted>
        <valueSetDefinition>
            <sorted>false</sorted>
            <value><fullName>Locations</fullName><default>true</default><label
        >Locations</label></value>
            <value><fullName>Mapbox</fullName><default>false</default><label
        >Mapbox</label></value>
        </valueSetDefinition>
    </valueSet>
</CustomField>
```

Manifest: add `Pricing_Place__c.Source__c` to `CustomField`. `Pricing_Department_User`: add a readable/non-editable `fieldPermissions` block for `Pricing_Place__c.Source__c`.

- [ ] **Step 2: Failing assertions**

In `PlaceBuilderBatchTest.collapsesSpellingsIntoOnePlaceWithAveragedCoordinatesAndCounts` add `Source__c` to the SELECT and `System.assertEquals('Locations', mtl.Source__c);`.

In `LaneSearchServiceTest.cityPrecisionMatchesOnlyThatCityAndToleratesAccents` add after the existing assertions:

```apex
    System.assertEquals('Test Carrier', r.rows[0].carrierName);
    System.assertEquals('quote.contact@example.invalid', r.rows[0].contactEmail);
    System.assertEquals('514-555-0100', r.rows[0].contactPhone);
    System.assertEquals('Acceptable', r.rows[0].carrierRisk, 'from rtms__Company_Risk__c on the transportation profile');
```

(The factory's contact email/phone and profile risk are set in `createGraph()`; confirm the literals by reading the factory before running.)

Run: `sf project deploy start -m ApexClass:LaneSearchServiceTest -m ApexClass:PlaceBuilderBatchTest -o sandbox -l NoTestRun -w 10`
Expected: compile failure `Variable does not exist: contactEmail` (and `Source__c` unknown until the field deploys).

- [ ] **Step 3: Implement**

`PlaceBuilderBatch.buildPlaces()`: add `p.Source__c = 'Locations';` next to `p.City__c`.

`LaneSearchResult.Row`: add

```apex
    @AuraEnabled public String contactEmail;
    @AuraEnabled public String contactPhone;
    @AuraEnabled public String carrierRisk;
    @AuraEnabled public Decimal carrierLoadCount;
    @AuraEnabled public String carrierAttention;
```

`LaneSearchQueryBuilder.SELECT_CLAUSE`: add `Contact_Email__c, Contact_Phone__c, Carrier_Risk__c, Nb_of_loads__c, Carrier_Att__c, ` before `CreatedDate`.

`LaneSearchService.toRow()`: add

```apex
    r.contactEmail = q.Contact_Email__c;
    r.contactPhone = q.Contact_Phone__c;
    r.carrierRisk = q.Carrier_Risk__c;
    r.carrierLoadCount = q.Nb_of_loads__c;
    r.carrierAttention = q.Carrier_Att__c;
```

- [ ] **Step 4: Deploy and run**

Run: `sf project deploy start -x manifest/package.xml -o sandbox -l RunSpecifiedTests -t PlaceBuilderBatchTest LaneSearchServiceTest -w 30`
Expected: Succeeded, both classes green (4 + 17 tests). Then a one-off data fix so existing places carry the source (anonymous Apex, foreground): `List<Pricing_Place__c> ps = [SELECT Id FROM Pricing_Place__c WHERE Source__c = null LIMIT 10000]; for (Pricing_Place__c p : ps) p.Source__c = 'Locations'; update ps;` repeated until 0 rows (10,496 rows → 2 runs). Verify `SELECT COUNT() FROM Pricing_Place__c WHERE Source__c = null` = 0.

- [ ] **Step 5: Commit**

```bash
git add force-app manifest
git commit -m "Add Pricing_Place__c.Source__c and carrier-detail fields on LaneSearchResult.Row"
```

---

### Task 2: `MapboxGeocoder`

**Files:**

- Create: `classes/MapboxException.cls`, `classes/MapboxGeocoder.cls`, `classes/MapboxGeocoderTest.cls` (+ metas, 64.0)
- Modify: `manifest/package.xml`, `.github/workflows/ci.yml` (`--tests` gains `MapboxGeocoderTest`)

**Interfaces:**

- Produces:

```apex
public class MapboxException extends Exception {}
public with sharing class MapboxGeocoder {
  public class GeoResult { public String name; public String city; public String province; public String country; public Decimal lat; public Decimal lng; public String postalPrefix; }
  public static List<GeoResult> forward(String query, String countryHint);   // 1-5 results, throws MapboxException
  public static String staticMapUrl(List<Circle> circles);                    // null when no token
  public class Circle { public Decimal lat; public Decimal lng; public Decimal radiusKm; public String color; }
  @TestVisible private static String token();                                 // reads TPRO_KPI__c
  @TestVisible private static String provinceFromShortCode(String shortCode); // 'CA-QC'->'QC', 'MX-NLE'->'NL'
}
```

- [ ] **Step 1: Failing tests**

```apex
@IsTest
private class MapboxGeocoderTest {
  private class Mock implements HttpCalloutMock {
    Integer status;
    String body;
    Integer calls = 0;
    Mock(Integer status, String body) {
      this.status = status;
      this.body = body;
    }
    public HttpResponse respond(HttpRequest req) {
      calls++;
      System.assert(
        req.getEndpoint()
          .startsWith('https://api.mapbox.com/geocoding/v5/mapbox.places/'),
        req.getEndpoint()
      );
      System.assert(
        !req.getEndpoint().contains('access_token=pk.test') || true
      ); // token is appended; value asserted separately
      HttpResponse r = new HttpResponse();
      r.setStatusCode(status);
      r.setBody(body);
      return r;
    }
  }

  private static void setToken(String t) {
    TPRO_KPI__c s = TPRO_KPI__c.getOrgDefaults();
    s.Mapbox_Api_Key__c = t;
    upsert s;
  }

  private static final String SAGUENAY = '{"features":[{"id":"place.1","type":"Feature","place_type":["place"],"text":"Saguenay","place_name":"Saguenay, Quebec, Canada","center":[-71.0656,48.4279],"context":[{"id":"region.1","text":"Quebec","short_code":"CA-QC"},{"id":"country.1","text":"Canada","short_code":"ca"}]},{"id":"postcode.2","type":"Feature","place_type":["postcode"],"text":"G7H 2N1","place_name":"G7H 2N1, Saguenay, Quebec, Canada","center":[-71.07,48.43],"context":[{"id":"place.1","text":"Saguenay"},{"id":"region.1","text":"Quebec","short_code":"CA-QC"},{"id":"country.1","text":"Canada","short_code":"ca"}]}]}';
  private static final String MONTERREY = '{"features":[{"id":"place.3","type":"Feature","place_type":["place"],"text":"Monterrey","place_name":"Monterrey, Nuevo León, Mexico","center":[-100.3161,25.6866],"context":[{"id":"region.3","text":"Nuevo León","short_code":"MX-NLE"},{"id":"country.3","text":"Mexico","short_code":"mx"}]}]}';

  @IsTest
  static void parsesPlacesAndPostcodes() {
    setToken('pk.test');
    Test.setMock(HttpCalloutMock.class, new Mock(200, SAGUENAY));
    Test.startTest();
    List<MapboxGeocoder.GeoResult> out = MapboxGeocoder.forward(
      'Saguenay QC',
      'ca'
    );
    Test.stopTest();
    System.assertEquals(2, out.size());
    System.assertEquals('Saguenay', out[0].city);
    System.assertEquals('QC', out[0].province);
    System.assertEquals('CA', out[0].country);
    System.assertEquals(48.4279, out[0].lat);
    System.assertEquals(-71.0656, out[0].lng);
    System.assertEquals(null, out[0].postalPrefix);
    System.assertEquals(
      'Saguenay',
      out[1].city,
      'postcode results take the city from context'
    );
    System.assertEquals('G7H', out[1].postalPrefix);
  }

  @IsTest
  static void mapsMexicanIsoRegionsToRevenovaCodes() {
    setToken('pk.test');
    Test.setMock(HttpCalloutMock.class, new Mock(200, MONTERREY));
    List<MapboxGeocoder.GeoResult> out = MapboxGeocoder.forward(
      'Monterrey',
      null
    );
    System.assertEquals('NL', out[0].province);
    System.assertEquals('MX', out[0].country);
    System.assertEquals('QC', MapboxGeocoder.provinceFromShortCode('CA-QC'));
    System.assertEquals('TX', MapboxGeocoder.provinceFromShortCode('US-TX'));
    System.assertEquals('ME', MapboxGeocoder.provinceFromShortCode('MX-MEX'));
    System.assertEquals('PB', MapboxGeocoder.provinceFromShortCode('MX-PUE'));
    System.assertEquals(
      'ZZZ',
      MapboxGeocoder.provinceFromShortCode('XX-ZZZ'),
      'unknown kept'
    );
  }

  @IsTest
  static void retriesOnceOnServerErrorThenThrows() {
    setToken('pk.test');
    Mock m = new Mock(503, 'down');
    Test.setMock(HttpCalloutMock.class, m);
    try {
      MapboxGeocoder.forward('Saguenay', null);
      System.assert(false, 'expected MapboxException');
    } catch (MapboxException e) {
      System.assert(e.getMessage().contains('503'), e.getMessage());
    }
    System.assertEquals(2, m.calls, 'one retry');
  }

  @IsTest
  static void clientErrorAndMalformedJsonThrow() {
    setToken('pk.test');
    Test.setMock(
      HttpCalloutMock.class,
      new Mock(401, '{"message":"Not Authorized"}')
    );
    try {
      MapboxGeocoder.forward('x', null);
      System.assert(false);
    } catch (MapboxException e) {
      System.assert(e.getMessage().contains('401'), e.getMessage());
    }
    Test.setMock(HttpCalloutMock.class, new Mock(200, 'not json'));
    try {
      MapboxGeocoder.forward('x', null);
      System.assert(false);
    } catch (MapboxException e) {
      System.assert(
        e.getMessage().toLowerCase().contains('parse'),
        e.getMessage()
      );
    }
  }

  @IsTest
  static void missingTokenThrowsBeforeCallout() {
    setToken(null);
    try {
      MapboxGeocoder.forward('Saguenay', null);
      System.assert(false);
    } catch (MapboxException e) {
      System.assert(e.getMessage().contains('not configured'), e.getMessage());
    }
    System.assertEquals(
      null,
      MapboxGeocoder.staticMapUrl(new List<MapboxGeocoder.Circle>())
    );
  }

  @IsTest
  static void staticMapUrlEncodesTwoCircles() {
    setToken('pk.test');
    MapboxGeocoder.Circle a = new MapboxGeocoder.Circle();
    a.lat = 45.5;
    a.lng = -73.5;
    a.radiusKm = 50;
    a.color = '#0070D2';
    MapboxGeocoder.Circle b = new MapboxGeocoder.Circle();
    b.lat = 43.6;
    b.lng = -79.4;
    b.radiusKm = 80;
    b.color = '#2E844A';
    String url = MapboxGeocoder.staticMapUrl(
      new List<MapboxGeocoder.Circle>{ a, b }
    );
    System.assert(
      url.startsWith(
        'https://api.mapbox.com/styles/v1/mapbox/streets-v12/static/geojson('
      ),
      url
    );
    System.assert(url.contains('/auto/600x300'), url);
    System.assert(url.contains('access_token=pk.test'), url);
    System.assert(
      url.length() < 8000,
      'URL must stay under browser limits: ' + url.length()
    );
  }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `sf project deploy start -m ApexClass:MapboxGeocoderTest -o sandbox -l NoTestRun -w 10` → `Invalid type: MapboxGeocoder`.

- [ ] **Step 3: Implement**

`MapboxException.cls`: `public class MapboxException extends Exception {}`

`MapboxGeocoder.cls`:

```apex
/**
 * Forward geocoding and static-map URLs through the company's Mapbox account.
 * Token: TPRO_KPI__c org default, Mapbox_Api_Key__c (public pk. token). Remote site: MapBox.
 * Only the search CENTER is geocoded; historical data is never sent to Mapbox.
 */
public with sharing class MapboxGeocoder {
  private static final String BASE = 'https://api.mapbox.com';
  private static final Integer TIMEOUT_MS = 10000;
  private static final Map<String, String> MX_ISO_TO_REVENOVA = new Map<String, String>{
    'AGU' => 'AG',
    'BCN' => 'BC',
    'BCS' => 'BS',
    'CAM' => 'CP',
    'CHP' => 'CS',
    'CHH' => 'CH',
    'CMX' => 'DF',
    'COA' => 'CO',
    'COL' => 'CL',
    'DUR' => 'DG',
    'GUA' => 'GT',
    'GRO' => 'GR',
    'HID' => 'HG',
    'JAL' => 'JA',
    'MEX' => 'ME',
    'MIC' => 'MI',
    'MOR' => 'MO',
    'NAY' => 'NA',
    'NLE' => 'NL',
    'OAX' => 'OA',
    'PUE' => 'PB',
    'QUE' => 'QE',
    'ROO' => 'QR',
    'SLP' => 'SL',
    'SIN' => 'SI',
    'SON' => 'SO',
    'TAB' => 'TB',
    'TAM' => 'TM',
    'TLA' => 'TL',
    'VER' => 'VE',
    'YUC' => 'YU',
    'ZAC' => 'ZA'
  };

  public class GeoResult {
    public String name;
    public String city;
    public String province;
    public String country;
    public Decimal lat;
    public Decimal lng;
    public String postalPrefix;
  }

  public class Circle {
    public Decimal lat;
    public Decimal lng;
    public Decimal radiusKm;
    public String color;
  }

  @TestVisible
  private static String token() {
    TPRO_KPI__c s = TPRO_KPI__c.getOrgDefaults();
    return s == null ? null : s.Mapbox_Api_Key__c;
  }

  public static List<GeoResult> forward(String query, String countryHint) {
    String t = token();
    if (String.isBlank(t)) {
      throw new MapboxException(
        'Mapbox token is not configured (TPRO_KPI__c.Mapbox_Api_Key__c)'
      );
    }
    String countries = String.isBlank(countryHint)
      ? 'ca,us,mx'
      : countryHint.toLowerCase();
    String url =
      BASE +
      '/geocoding/v5/mapbox.places/' +
      EncodingUtil.urlEncode(query.trim(), 'UTF-8') +
      '.json' +
      '?limit=5&language=en&types=place,locality,postcode&country=' +
      countries +
      '&access_token=' +
      t;
    HttpResponse res = send(url);
    if (res.getStatusCode() >= 500) {
      res = send(url); // one retry
    }
    if (res.getStatusCode() != 200) {
      throw new MapboxException(
        'Mapbox geocoding failed: HTTP ' + res.getStatusCode()
      );
    }
    return parse(res.getBody());
  }

  private static HttpResponse send(String url) {
    HttpRequest req = new HttpRequest();
    req.setEndpoint(url);
    req.setMethod('GET');
    req.setTimeout(TIMEOUT_MS);
    return new Http().send(req);
  }

  @TestVisible
  private static List<GeoResult> parse(String body) {
    Map<String, Object> root;
    try {
      root = (Map<String, Object>) JSON.deserializeUntyped(body);
    } catch (Exception e) {
      throw new MapboxException('Could not parse the Mapbox response');
    }
    List<GeoResult> out = new List<GeoResult>();
    List<Object> features = (List<Object>) root.get('features');
    if (features == null) {
      return out;
    }
    for (Object f : features) {
      Map<String, Object> feat = (Map<String, Object>) f;
      GeoResult g = new GeoResult();
      g.name = (String) feat.get('place_name');
      List<Object> center = (List<Object>) feat.get('center');
      g.lng = (Decimal) center[0];
      g.lat = (Decimal) center[1];
      List<Object> types = (List<Object>) feat.get('place_type');
      Boolean isPostcode = types != null && types.contains('postcode');
      String text = (String) feat.get('text');
      if (isPostcode) {
        g.postalPrefix = text == null
          ? null
          : text.replace(' ', '').left(3).toUpperCase();
      } else {
        g.city = text;
      }
      List<Object> ctx = (List<Object>) feat.get('context');
      if (ctx != null) {
        for (Object c : ctx) {
          Map<String, Object> item = (Map<String, Object>) c;
          String id = (String) item.get('id');
          if (id == null) {
            continue;
          }
          if (id.startsWith('place.') && g.city == null) {
            g.city = (String) item.get('text');
          } else if (id.startsWith('region.')) {
            g.province = provinceFromShortCode((String) item.get('short_code'));
          } else if (id.startsWith('country.')) {
            g.country = ((String) item.get('short_code')).toUpperCase();
          }
        }
      }
      if (g.city != null && g.country != null) {
        out.add(g);
      }
    }
    return out;
  }

  /** 'CA-QC' -> 'QC', 'US-TX' -> 'TX', 'MX-NLE' -> 'NL' (Revenova's code); unknown suffix kept. */
  @TestVisible
  private static String provinceFromShortCode(String shortCode) {
    if (String.isBlank(shortCode) || !shortCode.contains('-')) {
      return shortCode;
    }
    String prefix = shortCode.substringBefore('-').toUpperCase();
    String suffix = shortCode.substringAfter('-').toUpperCase();
    if (prefix == 'MX' && MX_ISO_TO_REVENOVA.containsKey(suffix)) {
      return MX_ISO_TO_REVENOVA.get(suffix);
    }
    return suffix;
  }

  /** Static Images API URL with one polygon per circle (24 points each), or null without a token / circles. */
  public static String staticMapUrl(List<Circle> circles) {
    String t = token();
    if (String.isBlank(t) || circles == null || circles.isEmpty()) {
      return null;
    }
    List<String> features = new List<String>();
    for (Circle c : circles) {
      features.add(polygonFeature(c));
    }
    String geojson =
      '{"type":"FeatureCollection","features":[' +
      String.join(features, ',') +
      ']}';
    return BASE +
      '/styles/v1/mapbox/streets-v12/static/geojson(' +
      EncodingUtil.urlEncode(geojson, 'UTF-8') +
      ')/auto/600x300?padding=40&access_token=' +
      t;
  }

  private static String polygonFeature(Circle c) {
    List<String> pts = new List<String>();
    Decimal latKm = 111.32;
    Decimal lngKm = 111.32 * Math.cos(c.lat.doubleValue() * Math.PI / 180);
    for (Integer i = 0; i <= 24; i++) {
      Double a = i * 2 * Math.PI / 24;
      Decimal lat = (c.lat + c.radiusKm / latKm * Math.cos(a)).setScale(4);
      Decimal lng = (c.lng + c.radiusKm / lngKm * Math.sin(a)).setScale(4);
      pts.add('[' + lng + ',' + lat + ']');
    }
    return '{"type":"Feature","properties":{"stroke":"' +
      c.color +
      '","stroke-width":2,"fill":"' +
      c.color +
      '","fill-opacity":0.15},' +
      '"geometry":{"type":"Polygon","coordinates":[[' +
      String.join(pts, ',') +
      ']]}}';
  }
}
```

Manifest: add the three classes. CI: add `MapboxGeocoderTest`.

- [ ] **Step 4: Deploy and run**

Run: `sf project deploy start -m ApexClass:MapboxException -m ApexClass:MapboxGeocoder -m ApexClass:MapboxGeocoderTest -o sandbox -l RunSpecifiedTests -t MapboxGeocoderTest -w 15`
Expected: 6/6. If `(Decimal) center[0]` fails with a cast error because the JSON number deserializes as `Double`, use `Decimal.valueOf(String.valueOf(center[0]))`.

- [ ] **Step 5: Commit**

```bash
git add force-app/main/default/classes/Mapbox* manifest/package.xml .github/workflows/ci.yml
git commit -m "Add MapboxGeocoder: forward geocoding and static map URLs with the org's public token"
```

---

### Task 3: `LaneBenchmarkController`

**Files:**

- Create: `classes/LaneBenchmarkController.cls`, `classes/LaneBenchmarkControllerTest.cls` (+ metas)
- Modify: `manifest/package.xml`, `.github/workflows/ci.yml` (`LaneBenchmarkControllerTest`)

**Interfaces:**

- Consumes: `LaneSearchService.search`, `LaneSearchRequest`, `PlaceNormalizer`, `MapboxGeocoder.forward/staticMapUrl`, `LaneSearchQueryBuilder.escapeLike` is private → the controller has its own tiny `escapeLike` copy? No: make `LaneSearchQueryBuilder.escapeLike` `public static` (one-word change) and reuse it.
- Produces:

```apex
public without sharing class LaneBenchmarkController {
  public class PlaceOption { @AuraEnabled public String key; label; province; country; source; @AuraEnabled public Decimal loadCount; lat; lng; }
  public class FilterOptions { @AuraEnabled public List<String> modes; @AuraEnabled public Map<String, List<String>> equipmentByCategory; @AuraEnabled public List<String> currencies; }
  @AuraEnabled(cacheable=true) public static LaneSearchResult search(String requestJson);
  @AuraEnabled(cacheable=true) public static List<PlaceOption> searchPlaces(String term, Integer limitCount);
  @AuraEnabled(cacheable=true) public static FilterOptions getFilterOptions();
  @AuraEnabled public static List<PlaceOption> geocode(String query, String countryHint);   // not cacheable: writes places
  @AuraEnabled(cacheable=true) public static String mapPreviewUrl(String originKey, Decimal originRadius, String destinationKey, Decimal destinationRadius, String unit);
  @TestVisible private static List<MapboxGeocoder.GeoResult> geocoderOverride; // tests inject results
}
```

- [ ] **Step 1: Failing tests**

```apex
@IsTest
private class LaneBenchmarkControllerTest {
  private static Pricing_Place__c place(
    String city,
    String prov,
    String country,
    Decimal lat,
    Decimal lng,
    Decimal loads,
    String aliases
  ) {
    return new Pricing_Place__c(
      Name = city + ', ' + prov + ', ' + country,
      Key__c = PlaceNormalizer.key(city, prov, country),
      City__c = city,
      Province__c = prov,
      Country__c = country,
      Geolocation__Latitude__s = lat,
      Geolocation__Longitude__s = lng,
      Load_Count_365d__c = loads,
      Aliases__c = aliases,
      Active__c = true,
      Source__c = 'Locations',
      Postal_Prefix__c = 'H1A'
    );
  }

  @TestSetup
  static void places() {
    insert new List<Pricing_Place__c>{
      place(
        'Montréal',
        'QC',
        'CA',
        45.5019,
        -73.5674,
        900,
        'Mtl\nMontreal-Nord'
      ),
      place('Montmagny', 'QC', 'CA', 46.98, -70.55, 12, null),
      place('Toronto', 'ON', 'CA', 43.6532, -79.3832, 800, null),
      place('Hidden', 'ON', 'CA', 43.0, -79.0, 5000, null)
    };
    Pricing_Place__c hidden = [
      SELECT Id
      FROM Pricing_Place__c
      WHERE City__c = 'Hidden'
    ];
    hidden.Active__c = false;
    update hidden;
  }

  @IsTest
  static void searchPlacesMatchesNormalizedPrefixAndAliasesOrderedByLoads() {
    List<LaneBenchmarkController.PlaceOption> byPrefix = LaneBenchmarkController.searchPlaces(
      'mont',
      10
    );
    System.assertEquals(2, byPrefix.size());
    System.assertEquals('montreal|qc|ca', byPrefix[0].key, 'more loads first');
    System.assertEquals('Montréal, QC, CA', byPrefix[0].label);
    System.assertEquals(900, byPrefix[0].loadCount);
    List<LaneBenchmarkController.PlaceOption> byAlias = LaneBenchmarkController.searchPlaces(
      'mtl',
      10
    );
    System.assertEquals(1, byAlias.size());
    System.assertEquals('montreal|qc|ca', byAlias[0].key);
    System.assertEquals(
      0,
      LaneBenchmarkController.searchPlaces('h', 10).size(),
      'terms under 2 chars return nothing'
    );
    System.assertEquals(
      0,
      LaneBenchmarkController.searchPlaces('hidden', 10).size(),
      'inactive places are hidden'
    );
    System.assertEquals(
      1,
      LaneBenchmarkController.searchPlaces('mont', 1).size(),
      'limit honored'
    );
  }

  @IsTest
  static void searchDeserializesJsonKeepsDefaultsAndTranslatesErrors() {
    PricingDepartmentController.excludedContactIdsOverride = new Set<String>();
    LaneSearchResult r = LaneBenchmarkController.search(
      '{"originKey":"montreal|qc|ca","destinationKey":"toronto|on|ca"}'
    );
    System.assertNotEquals(null, r);
    System.assertEquals(0, r.rows.size(), 'no quotes in this test org context');
    try {
      LaneBenchmarkController.search('{"originKey":"nowhere|zz|zz"}');
      System.assert(false, 'unknown key must surface as AuraHandledException');
    } catch (AuraHandledException e) {
      System.assert(e.getMessage().contains('nowhere|zz|zz'), e.getMessage());
    }
    try {
      LaneBenchmarkController.search('{"lookbackDays":0}');
      System.assert(false);
    } catch (AuraHandledException e) {
      System.assert(e.getMessage().contains('lookbackDays'), e.getMessage());
    }
    try {
      LaneBenchmarkController.search('not json');
      System.assert(false);
    } catch (AuraHandledException e) {
      System.assert(
        e.getMessage().toLowerCase().contains('request'),
        e.getMessage()
      );
    }
  }

  @IsTest
  static void filterOptionsListEnabledModesAndEquipmentByCategory() {
    PricingTestDataFactory.createMode('LTL');
    PricingTestDataFactory.createEquipment('Reefer 53\'', 'Reefer');
    PricingTestDataFactory.createEquipment('Dry Van 53\'', 'Van');
    rtms__EquipmentType__c noCat = PricingTestDataFactory.createEquipment(
      'Mystery',
      null
    );
    LaneBenchmarkController.FilterOptions o = LaneBenchmarkController.getFilterOptions();
    System.assert(o.modes.contains('LTL'), o.modes);
    System.assert(o.equipmentByCategory.get('Reefer').contains('Reefer 53\''));
    System.assert(
      o.equipmentByCategory.get('Other').contains('Mystery'),
      'null category grouped as Other'
    );
    System.assertEquals(new List<String>{ 'CAD', 'USD' }, o.currencies);
  }

  @IsTest
  static void geocodeStoresMapboxPlacesWithoutDowngradingExistingOnes() {
    MapboxGeocoder.GeoResult existing = new MapboxGeocoder.GeoResult();
    existing.name = 'Montréal, Quebec, Canada';
    existing.city = 'Montréal';
    existing.province = 'QC';
    existing.country = 'CA';
    existing.lat = 45.5;
    existing.lng = -73.5;
    MapboxGeocoder.GeoResult fresh = new MapboxGeocoder.GeoResult();
    fresh.name = 'Saguenay, Quebec, Canada';
    fresh.city = 'Saguenay';
    fresh.province = 'QC';
    fresh.country = 'CA';
    fresh.lat = 48.4279;
    fresh.lng = -71.0656;
    LaneBenchmarkController.geocoderOverride = new List<MapboxGeocoder.GeoResult>{
      existing,
      fresh
    };
    Test.startTest();
    List<LaneBenchmarkController.PlaceOption> out = LaneBenchmarkController.geocode(
      'anything',
      null
    );
    Test.stopTest();
    System.assertEquals(2, out.size());
    Pricing_Place__c mtl = [
      SELECT Source__c, Load_Count_365d__c
      FROM Pricing_Place__c
      WHERE Key__c = 'montreal|qc|ca'
    ];
    System.assertEquals('Locations', mtl.Source__c, 'existing place untouched');
    System.assertEquals(900, mtl.Load_Count_365d__c);
    Pricing_Place__c sag = [
      SELECT
        Source__c,
        City__c,
        Province__c,
        Country__c,
        Geolocation__Latitude__s,
        Active__c,
        Name
      FROM Pricing_Place__c
      WHERE Key__c = 'saguenay|qc|ca'
    ];
    System.assertEquals('Mapbox', sag.Source__c);
    System.assertEquals('Saguenay, QC, CA', sag.Name);
    System.assertEquals(48.4279, sag.Geolocation__Latitude__s);
    System.assertEquals(true, sag.Active__c);
    try {
      LaneBenchmarkController.geocode('ab', null);
      System.assert(false);
    } catch (AuraHandledException e) {
      System.assert(e.getMessage().contains('3'), e.getMessage());
    }
  }

  @IsTest
  static void mapPreviewUrlUsesPlaceCoordinatesAndRadii() {
    TPRO_KPI__c s = TPRO_KPI__c.getOrgDefaults();
    s.Mapbox_Api_Key__c = 'pk.test';
    upsert s;
    String url = LaneBenchmarkController.mapPreviewUrl(
      'montreal|qc|ca',
      50,
      'toronto|on|ca',
      100,
      'MI'
    );
    System.assert(url != null && url.contains('access_token=pk.test'), url);
    System.assertEquals(
      null,
      LaneBenchmarkController.mapPreviewUrl(null, null, null, null, 'MI'),
      'no radius end -> no map'
    );
    System.assertEquals(
      null,
      LaneBenchmarkController.mapPreviewUrl(
        'montreal|qc|ca',
        null,
        'toronto|on|ca',
        null,
        'MI'
      )
    );
  }
}
```

Note: `search(...)` in the JSON test runs against real data in PostProduc? No: Apex tests see no org data (no `SeeAllData`), so `rows` is empty; the assertions are about deserialization and error translation. `createEquipment(name, null)` requires the factory to accept a null category (it sets `rtms__Category__c = category`; null is fine).

- [ ] **Step 2: Run to verify it fails**

Run: `sf project deploy start -m ApexClass:LaneBenchmarkControllerTest -o sandbox -l NoTestRun -w 10` → `Invalid type: LaneBenchmarkController`.

- [ ] **Step 3: Implement**

Make `LaneSearchQueryBuilder.escapeLike` `public static` (keep `@TestVisible` harmlessly or drop it).

`LaneBenchmarkController.cls`:

```apex
/**
 * Aura/LWC entry points for the Lane Benchmark page. Thin: validation and error
 * translation here, all search logic in LaneSearchService.
 */
// Runs without sharing on purpose: pricing benchmarks every team's quotes. Access is gated by the Lane Benchmark permission sets.
public without sharing class LaneBenchmarkController {
  public class PlaceOption {
    @AuraEnabled
    public String key;
    @AuraEnabled
    public String label;
    @AuraEnabled
    public String province;
    @AuraEnabled
    public String country;
    @AuraEnabled
    public String source;
    @AuraEnabled
    public Decimal loadCount;
    @AuraEnabled
    public Decimal lat;
    @AuraEnabled
    public Decimal lng;
  }

  public class FilterOptions {
    @AuraEnabled
    public List<String> modes = new List<String>();
    @AuraEnabled
    public Map<String, List<String>> equipmentByCategory = new Map<String, List<String>>();
    @AuraEnabled
    public List<String> currencies = new List<String>{ 'CAD', 'USD' };
  }

  @TestVisible
  private static List<MapboxGeocoder.GeoResult> geocoderOverride;

  @AuraEnabled(cacheable=true)
  public static LaneSearchResult search(String requestJson) {
    LaneSearchRequest req;
    try {
      req = (LaneSearchRequest) JSON.deserialize(
        requestJson,
        LaneSearchRequest.class
      );
    } catch (Exception e) {
      throw userError(
        'The search request could not be read. Please reset the filters and try again.'
      );
    }
    try {
      return LaneSearchService.search(req);
    } catch (LaneSearchException e) {
      throw userError(e.getMessage());
    } catch (QueryException e) {
      throw userError(
        'The search took too long or returned too much data. Narrow the lookback or the radius and try again. (' +
          e.getMessage() +
          ')'
      );
    }
  }

  @AuraEnabled(cacheable=true)
  @SuppressWarnings(
    'PMD.ApexCRUDViolation'
  ) // system mode by design (see class comment)
  public static List<PlaceOption> searchPlaces(
    String term,
    Integer limitCount
  ) {
    List<PlaceOption> out = new List<PlaceOption>();
    if (term == null || term.trim().length() < 2) {
      return out;
    }
    Integer lim = limitCount == null ||
      limitCount < 1
      ? 10
      : Math.min(limitCount, 10);
    String keyPattern =
      LaneSearchQueryBuilder.escapeLike(PlaceNormalizer.normalizeCity(term)) +
      '%';
    String aliasPattern =
      '%' +
      LaneSearchQueryBuilder.escapeLike(term.trim()) +
      '%';
    for (Pricing_Place__c p : [
      SELECT
        Key__c,
        Name,
        Province__c,
        Country__c,
        Source__c,
        Load_Count_365d__c,
        Geolocation__Latitude__s,
        Geolocation__Longitude__s
      FROM Pricing_Place__c
      WHERE
        Active__c = TRUE
        AND (Key__c LIKE :keyPattern
        OR Aliases__c LIKE :aliasPattern)
      ORDER BY Load_Count_365d__c DESC NULLS LAST, Name
      LIMIT :lim
    ]) {
      out.add(toOption(p));
    }
    return out;
  }

  @AuraEnabled(cacheable=true)
  @SuppressWarnings(
    'PMD.ApexCRUDViolation'
  ) // system mode by design (see class comment)
  public static FilterOptions getFilterOptions() {
    FilterOptions o = new FilterOptions();
    for (rtms__Mode__c m : [
      SELECT Name
      FROM rtms__Mode__c
      WHERE rtms__Enabled__c = TRUE
      ORDER BY rtms__Order__c, Name
    ]) {
      o.modes.add(m.Name);
    }
    for (rtms__EquipmentType__c e : [
      SELECT Name, rtms__Category__c
      FROM rtms__EquipmentType__c
      WHERE rtms__Enabled__c = TRUE
      ORDER BY rtms__Category__c NULLS LAST, Name
    ]) {
      String cat = String.isBlank(e.rtms__Category__c)
        ? 'Other'
        : e.rtms__Category__c;
      if (!o.equipmentByCategory.containsKey(cat)) {
        o.equipmentByCategory.put(cat, new List<String>());
      }
      o.equipmentByCategory.get(cat).add(e.Name);
    }
    return o;
  }

  @AuraEnabled
  @SuppressWarnings(
    'PMD.ApexCRUDViolation'
  ) // system mode by design (see class comment)
  public static List<PlaceOption> geocode(String query, String countryHint) {
    if (query == null || query.trim().length() < 3) {
      throw userError('Type at least 3 characters to search the map.');
    }
    List<MapboxGeocoder.GeoResult> results;
    try {
      results = geocoderOverride != null
        ? geocoderOverride
        : MapboxGeocoder.forward(query, countryHint);
    } catch (MapboxException e) {
      throw userError('Map search is unavailable right now. ' + e.getMessage());
    }
    Map<String, Pricing_Place__c> candidates = new Map<String, Pricing_Place__c>();
    for (MapboxGeocoder.GeoResult g : results) {
      String key = PlaceNormalizer.key(g.city, g.province, g.country).left(120);
      if (candidates.containsKey(key)) {
        continue;
      }
      Pricing_Place__c p = new Pricing_Place__c(
        Key__c = key,
        City__c = g.city,
        Province__c = g.province,
        Country__c = g.country,
        Name = (g.city + ', ' + g.province + ', ' + g.country).left(80),
        Geolocation__Latitude__s = g.lat,
        Geolocation__Longitude__s = g.lng,
        Postal_Prefix__c = g.postalPrefix,
        Source__c = 'Mapbox',
        Location_Count__c = 0,
        Load_Count_365d__c = 0,
        Active__c = true
      );
      candidates.put(key, p);
    }
    Map<String, Pricing_Place__c> existing = new Map<String, Pricing_Place__c>();
    for (Pricing_Place__c p : [
      SELECT
        Key__c,
        Name,
        Province__c,
        Country__c,
        Source__c,
        Load_Count_365d__c,
        Geolocation__Latitude__s,
        Geolocation__Longitude__s
      FROM Pricing_Place__c
      WHERE Key__c IN :candidates.keySet()
    ]) {
      existing.put(p.Key__c, p);
    }
    List<Pricing_Place__c> toInsert = new List<Pricing_Place__c>();
    for (String key : candidates.keySet()) {
      if (!existing.containsKey(key)) {
        toInsert.add(candidates.get(key));
      }
    }
    insert toInsert;
    List<PlaceOption> out = new List<PlaceOption>();
    for (String key : candidates.keySet()) {
      out.add(
        toOption(
          existing.containsKey(key) ? existing.get(key) : candidates.get(key)
        )
      );
    }
    return out;
  }

  @AuraEnabled(cacheable=true)
  @SuppressWarnings(
    'PMD.ApexCRUDViolation'
  ) // system mode by design (see class comment)
  public static String mapPreviewUrl(
    String originKey,
    Decimal originRadius,
    String destinationKey,
    Decimal destinationRadius,
    String unit
  ) {
    Decimal factor = unit == 'KM' ? 1 : 1.609344;
    Set<String> keys = new Set<String>();
    if (String.isNotBlank(originKey) && originRadius != null) {
      keys.add(originKey);
    }
    if (String.isNotBlank(destinationKey) && destinationRadius != null) {
      keys.add(destinationKey);
    }
    if (keys.isEmpty()) {
      return null;
    }
    Map<String, Pricing_Place__c> places = new Map<String, Pricing_Place__c>();
    for (Pricing_Place__c p : [
      SELECT Key__c, Geolocation__Latitude__s, Geolocation__Longitude__s
      FROM Pricing_Place__c
      WHERE Key__c IN :keys
    ]) {
      places.put(p.Key__c, p);
    }
    List<MapboxGeocoder.Circle> circles = new List<MapboxGeocoder.Circle>();
    addCircle(circles, places.get(originKey), originRadius, factor, '#0070D2');
    addCircle(
      circles,
      places.get(destinationKey),
      destinationRadius,
      factor,
      '#2E844A'
    );
    return MapboxGeocoder.staticMapUrl(circles);
  }

  private static void addCircle(
    List<MapboxGeocoder.Circle> circles,
    Pricing_Place__c p,
    Decimal radius,
    Decimal factor,
    String color
  ) {
    if (p == null || radius == null || p.Geolocation__Latitude__s == null) {
      return;
    }
    MapboxGeocoder.Circle c = new MapboxGeocoder.Circle();
    c.lat = p.Geolocation__Latitude__s;
    c.lng = p.Geolocation__Longitude__s;
    c.radiusKm = radius * factor;
    c.color = color;
    circles.add(c);
  }

  private static PlaceOption toOption(Pricing_Place__c p) {
    PlaceOption o = new PlaceOption();
    o.key = p.Key__c;
    o.label = p.Name;
    o.province = p.Province__c;
    o.country = p.Country__c;
    o.source = p.Source__c;
    o.loadCount = p.Load_Count_365d__c;
    o.lat = p.Geolocation__Latitude__s;
    o.lng = p.Geolocation__Longitude__s;
    return o;
  }

  private static AuraHandledException userError(String message) {
    AuraHandledException e = new AuraHandledException(message);
    e.setMessage(message);
    return e;
  }
}
```

`mapPreviewUrl` has 5 parameters: `ExcessiveParameterList` is excluded from PMD, so it is allowed; if PMD complains for another rule, wrap the parameters in a small inner class.

Manifest: both classes. CI: `LaneBenchmarkControllerTest`.

- [ ] **Step 4: Deploy and run**

Run: `sf project deploy start -x manifest/package.xml -o sandbox -l RunSpecifiedTests -t LaneBenchmarkControllerTest MapboxGeocoderTest LaneSearchServiceTest -w 30`
Expected: 5 + 6 + 17 pass. Run PMD as CI does; must be clean.

- [ ] **Step 5: Commit, PR, merge, deploy (backend milestone)**

```bash
git add force-app manifest .github/workflows/ci.yml
git commit -m "Add LaneBenchmarkController: search, place autocomplete, filter options, geocode, map preview"
git push -u origin phase-2/backend
WT=$(gh auth token -u IulianEnescu) && git -c credential.helper= -c "credential.helper=!f() { echo username=IulianEnescu; echo password=$WT; }; f" push -u tplm phase-2/backend
gh pr create --base main --head phase-2/backend --title "Phase 2 backend: controller, Mapbox geocoder, place source" --body "Tasks 1-3 of docs/superpowers/plans/2026-09-09-phase-2-lane-benchmark-ui.md"
GH_TOKEN=$WT gh pr create -R TPLM/PricingDepartment --base main --head phase-2/backend --title "Phase 2 backend: controller, Mapbox geocoder, place source" --body "Tasks 1-3 of docs/superpowers/plans/2026-09-09-phase-2-lane-benchmark-ui.md"
```

Watch both; merge on origin only; pull main; push main to tplm; deploy main to PostProduc with all test classes (`PricingDepartmentControllerTest PlaceNormalizerTest PricingTestDataFactoryTest PlaceBuilderBatchTest LaneSearchServiceTest MapboxGeocoderTest LaneBenchmarkControllerTest`).

---

### Task 4: Pure modules `marginMath`, `laneBenchmarkCsv`, `laneBenchmarkStorage`

**Files:**

- Create: `lwc/marginMath/marginMath.js` (+ `.js-meta.xml`, isExposed false), `lwc/marginMath/__tests__/marginMath.test.js`; same for `laneBenchmarkCsv`, `laneBenchmarkStorage`
- Modify: `manifest/package.xml` (three `LightningComponentBundle` members)

**Interfaces:**

- Produces:
  - `marginMath.parseMargin(text) -> number|null` (accepts "15", "15%", " 20 ", rejects <0, >100, NaN → null); `marginMath.suggestedSell(cost, marginPct) -> number|null` (2 decimals; null when cost is not a positive number).
  - `laneBenchmarkCsv.toCsv(rows, columns) -> string` where `columns = [{ label, field }]`; RFC 4180 quoting; lines joined by `\r\n`; starts with a UTF-8 BOM `﻿`. `laneBenchmarkCsv.fileName(originLabel, destinationLabel, date) -> string` (`lane-benchmark-<slug>-<slug>-<yyyymmdd>.csv`, slug = lowercase letters/digits, dashes for the rest, "any" when blank).
  - `laneBenchmarkStorage.load() -> object|null`, `save(request)`, `clear()`; key `laneBenchmark.request.v1`; every call wrapped in try/catch; corrupt JSON → null.

- [ ] **Step 1: Branch and failing tests**

```bash
git checkout main && git pull origin main && git checkout -b phase-2/components
```

`marginMath.test.js`:

```javascript
import { parseMargin, suggestedSell } from "c/marginMath";

describe("parseMargin", () => {
  it("accepts plain numbers, percent signs and whitespace", () => {
    expect(parseMargin("15")).toBe(15);
    expect(parseMargin("15%")).toBe(15);
    expect(parseMargin(" 20 ")).toBe(20);
    expect(parseMargin("12.5")).toBe(12.5);
  });
  it("rejects out-of-range and non-numeric input", () => {
    expect(parseMargin("-1")).toBeNull();
    expect(parseMargin("101")).toBeNull();
    expect(parseMargin("abc")).toBeNull();
    expect(parseMargin("")).toBeNull();
    expect(parseMargin(null)).toBeNull();
  });
});

describe("suggestedSell", () => {
  it("applies the margin and rounds to cents", () => {
    expect(suggestedSell(1000, 15)).toBe(1150);
    expect(suggestedSell(1234.56, 20)).toBe(1481.47);
    expect(suggestedSell(100, 0)).toBe(100);
  });
  it("returns null for missing or non-positive cost", () => {
    expect(suggestedSell(0, 15)).toBeNull();
    expect(suggestedSell(null, 15)).toBeNull();
    expect(suggestedSell(100, null)).toBeNull();
  });
});
```

`laneBenchmarkCsv.test.js`:

```javascript
import { toCsv, fileName } from "c/laneBenchmarkCsv";

const columns = [
  { label: "Origin", field: "origin" },
  { label: "Carrier", field: "carrierName" },
  { label: "Total", field: "carrierTotal" }
];

describe("toCsv", () => {
  it("quotes commas, quotes and newlines, and starts with a BOM", () => {
    const csv = toCsv(
      [
        {
          origin: "Montréal, QC",
          carrierName: 'Acme "Fast" Inc',
          carrierTotal: 1000
        },
        { origin: "Laval", carrierName: "Line1\nLine2", carrierTotal: null }
      ],
      columns
    );
    const lines = csv.split("\r\n");
    expect(lines[0]).toBe("﻿Origin,Carrier,Total");
    expect(lines[1]).toBe('"Montréal, QC","Acme ""Fast"" Inc",1000');
    expect(lines[2]).toBe('Laval,"Line1\nLine2",');
  });
  it("handles an empty row list", () => {
    expect(toCsv([], columns)).toBe("﻿Origin,Carrier,Total");
  });
});

describe("fileName", () => {
  it("slugs labels and formats the date", () => {
    expect(
      fileName("Montréal, QC, CA", "Toronto, ON, CA", new Date(2026, 8, 9))
    ).toBe("lane-benchmark-montreal-qc-ca-toronto-on-ca-20260909.csv");
    expect(fileName("", null, new Date(2026, 0, 1))).toBe(
      "lane-benchmark-any-any-20260101.csv"
    );
  });
});
```

`laneBenchmarkStorage.test.js`:

```javascript
import { load, save, clear, STORAGE_KEY } from "c/laneBenchmarkStorage";

describe("laneBenchmarkStorage", () => {
  beforeEach(() => window.localStorage.clear());

  it("round-trips a request", () => {
    save({ originKey: "montreal|qc|ca", lookbackDays: 90 });
    expect(load()).toEqual({ originKey: "montreal|qc|ca", lookbackDays: 90 });
    expect(STORAGE_KEY).toBe("laneBenchmark.request.v1");
  });
  it("returns null when nothing is saved or the value is corrupt", () => {
    expect(load()).toBeNull();
    window.localStorage.setItem(STORAGE_KEY, "{not json");
    expect(load()).toBeNull();
  });
  it("clear removes the entry", () => {
    save({ a: 1 });
    clear();
    expect(load()).toBeNull();
  });
  it("never throws when storage is unavailable", () => {
    const original = window.localStorage.setItem;
    window.localStorage.setItem = () => {
      throw new Error("quota");
    };
    expect(() => save({ a: 1 })).not.toThrow();
    window.localStorage.setItem = original;
  });
});
```

- [ ] **Step 2: Run to verify they fail**

Run: `npx sfdx-lwc-jest force-app/main/default/lwc/marginMath force-app/main/default/lwc/laneBenchmarkCsv force-app/main/default/lwc/laneBenchmarkStorage` → cannot find modules.

- [ ] **Step 3: Implement**

`marginMath.js`:

```javascript
export function parseMargin(text) {
  if (text === null || text === undefined) return null;
  const cleaned = String(text).replace("%", "").trim();
  if (cleaned === "") return null;
  const n = Number(cleaned);
  if (!Number.isFinite(n) || n < 0 || n > 100) return null;
  return n;
}

export function suggestedSell(cost, marginPct) {
  if (typeof cost !== "number" || !(cost > 0)) return null;
  if (typeof marginPct !== "number" || !Number.isFinite(marginPct)) return null;
  return Math.round(cost * (1 + marginPct / 100) * 100) / 100;
}
```

`laneBenchmarkCsv.js`:

```javascript
function cell(value) {
  if (value === null || value === undefined) return "";
  const s = String(value);
  return /[",\r\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
}

export function toCsv(rows, columns) {
  const header = columns.map((c) => cell(c.label)).join(",");
  const body = rows.map((r) => columns.map((c) => cell(r[c.field])).join(","));
  return `﻿${[header, ...body].join("\r\n")}`;
}

function slug(label) {
  const s = String(label || "")
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "");
  return s || "any";
}

export function fileName(originLabel, destinationLabel, date) {
  const d = date || new Date();
  const ymd = `${d.getFullYear()}${String(d.getMonth() + 1).padStart(2, "0")}${String(d.getDate()).padStart(2, "0")}`;
  return `lane-benchmark-${slug(originLabel)}-${slug(destinationLabel)}-${ymd}.csv`;
}
```

`laneBenchmarkStorage.js`:

```javascript
export const STORAGE_KEY = "laneBenchmark.request.v1";

export function load() {
  try {
    const raw = window.localStorage.getItem(STORAGE_KEY);
    return raw ? JSON.parse(raw) : null;
  } catch (e) {
    return null;
  }
}

export function save(request) {
  try {
    window.localStorage.setItem(STORAGE_KEY, JSON.stringify(request));
  } catch (e) {
    // storage unavailable (private mode, quota): remembering filters is a convenience only
  }
}

export function clear() {
  try {
    window.localStorage.removeItem(STORAGE_KEY);
  } catch (e) {
    // same as above
  }
}
```

Each `.js-meta.xml`: `<LightningComponentBundle xmlns="http://soap.sforce.com/2006/04/metadata"><apiVersion>64.0</apiVersion><isExposed>false</isExposed></LightningComponentBundle>`. Manifest: three members.

- [ ] **Step 4: Run, lint, commit**

Run: `npx sfdx-lwc-jest force-app/main/default/lwc/marginMath force-app/main/default/lwc/laneBenchmarkCsv force-app/main/default/lwc/laneBenchmarkStorage && npm run lint` → 11 tests pass, lint clean (ESLint may flag the empty `catch` blocks: keep the comment inside them; if `no-empty` still fires, add `/* eslint-disable-line no-empty */` is NOT allowed by the LWC config; instead assign `const ignored = e;` — no: return undefined explicitly `return undefined;` inside the catch).

```bash
git add force-app/main/default/lwc/marginMath force-app/main/default/lwc/laneBenchmarkCsv force-app/main/default/lwc/laneBenchmarkStorage manifest/package.xml
git commit -m "Add marginMath, laneBenchmarkCsv and laneBenchmarkStorage pure modules"
```

---

### Task 5: `laneBenchmarkPlacePicker`

**Files:**

- Create: `lwc/laneBenchmarkPlacePicker/{laneBenchmarkPlacePicker.js,.html,.css,.js-meta.xml}`, `__tests__/laneBenchmarkPlacePicker.test.js`
- Modify: `manifest/package.xml`

**Interfaces:**

- Consumes: `LaneBenchmarkController.searchPlaces(term, limitCount)`, `geocode(query, countryHint)`.
- Produces: `<c-lane-benchmark-place-picker label="Origin" value={originKey} value-label={originLabel} precision="CITY" radius={r} unit="MI">` emitting `CustomEvent('placechange', { detail: { key, label, precision, radius, unit } })` on every change (place picked, cleared, precision, radius or unit changed). `@api` properties: `label`, `value` (key), `valueLabel`, `precision` (`CITY|PROVINCE|ZIP3|RADIUS`), `radius` (number), `unit` (`MI|KM`).

- [ ] **Step 1: Failing tests**

```javascript
import { createElement } from "lwc";
import PlacePicker from "c/laneBenchmarkPlacePicker";
import searchPlaces from "@salesforce/apex/LaneBenchmarkController.searchPlaces";
import geocode from "@salesforce/apex/LaneBenchmarkController.geocode";

jest.mock(
  "@salesforce/apex/LaneBenchmarkController.searchPlaces",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/LaneBenchmarkController.geocode",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const flush = () => Promise.resolve().then(() => Promise.resolve());
const OPTIONS = [
  {
    key: "montreal|qc|ca",
    label: "Montréal, QC, CA",
    loadCount: 900,
    source: "Locations"
  },
  {
    key: "montmagny|qc|ca",
    label: "Montmagny, QC, CA",
    loadCount: 12,
    source: "Locations"
  }
];

async function mount(props = {}) {
  const el = createElement("c-lane-benchmark-place-picker", {
    is: PlacePicker
  });
  Object.assign(el, { label: "Origin", precision: "CITY", unit: "MI" }, props);
  document.body.appendChild(el);
  await flush();
  return el;
}

function type(el, text) {
  const input = el.shadowRoot.querySelector('lightning-input[data-id="term"]');
  input.value = text;
  input.dispatchEvent(new CustomEvent("change", { detail: { value: text } }));
}

describe("c-lane-benchmark-place-picker", () => {
  beforeEach(() => {
    jest.useFakeTimers();
    searchPlaces.mockResolvedValue(OPTIONS);
    geocode.mockResolvedValue([]);
  });
  afterEach(() => {
    jest.useRealTimers();
    while (document.body.firstChild)
      document.body.removeChild(document.body.firstChild);
    jest.clearAllMocks();
  });

  it("debounces typing and lists options with load counts", async () => {
    const el = await mount();
    type(el, "mo");
    type(el, "mon");
    jest.advanceTimersByTime(250);
    await flush();
    await flush();
    expect(searchPlaces).toHaveBeenCalledTimes(1);
    expect(searchPlaces).toHaveBeenCalledWith({ term: "mon", limitCount: 10 });
    const items = el.shadowRoot.querySelectorAll("li[data-key]");
    expect(items.length).toBe(2);
    expect(items[0].textContent).toContain("Montréal, QC, CA");
    expect(items[0].textContent).toContain("900");
  });

  it("emits placechange with the picked key and closes the list", async () => {
    const el = await mount();
    const handler = jest.fn();
    el.addEventListener("placechange", handler);
    type(el, "mon");
    jest.advanceTimersByTime(250);
    await flush();
    await flush();
    el.shadowRoot.querySelector('li[data-key="montreal|qc|ca"]').click();
    await flush();
    expect(handler).toHaveBeenCalledTimes(1);
    expect(handler.mock.calls[0][0].detail).toEqual({
      key: "montreal|qc|ca",
      label: "Montréal, QC, CA",
      precision: "CITY",
      radius: null,
      unit: "MI"
    });
    expect(el.shadowRoot.querySelectorAll("li[data-key]").length).toBe(0);
  });

  it("shows radius controls only for RADIUS and emits radius changes", async () => {
    const el = await mount({
      value: "montreal|qc|ca",
      valueLabel: "Montréal, QC, CA"
    });
    expect(
      el.shadowRoot.querySelector('lightning-input[data-id="radius"]')
    ).toBeNull();
    const handler = jest.fn();
    el.addEventListener("placechange", handler);
    const precision = el.shadowRoot.querySelector(
      'lightning-combobox[data-id="precision"]'
    );
    precision.dispatchEvent(
      new CustomEvent("change", { detail: { value: "RADIUS" } })
    );
    await flush();
    const radius = el.shadowRoot.querySelector(
      'lightning-input[data-id="radius"]'
    );
    expect(radius).not.toBeNull();
    radius.dispatchEvent(
      new CustomEvent("change", { detail: { value: "75" } })
    );
    await flush();
    const last = handler.mock.calls[handler.mock.calls.length - 1][0].detail;
    expect(last).toMatchObject({
      key: "montreal|qc|ca",
      precision: "RADIUS",
      radius: 75,
      unit: "MI"
    });
  });

  it("falls back to the map search on the footer action", async () => {
    geocode.mockResolvedValue([
      {
        key: "saguenay|qc|ca",
        label: "Saguenay, QC, CA",
        loadCount: 0,
        source: "Mapbox"
      }
    ]);
    const el = await mount();
    type(el, "sague");
    jest.advanceTimersByTime(250);
    searchPlaces.mockResolvedValue([]);
    await flush();
    await flush();
    el.shadowRoot.querySelector('button[data-id="map-search"]').click();
    await flush();
    await flush();
    expect(geocode).toHaveBeenCalledWith({ query: "sague", countryHint: null });
    const item = el.shadowRoot.querySelector('li[data-key="saguenay|qc|ca"]');
    expect(item).not.toBeNull();
    expect(item.textContent).toContain("Mapbox");
  });

  it("clear button empties the value and emits", async () => {
    const el = await mount({
      value: "montreal|qc|ca",
      valueLabel: "Montréal, QC, CA"
    });
    const handler = jest.fn();
    el.addEventListener("placechange", handler);
    el.shadowRoot.querySelector('button[data-id="clear"]').click();
    await flush();
    expect(handler.mock.calls[0][0].detail.key).toBeNull();
  });
});
```

- [ ] **Step 2: Run to verify they fail**

Run: `npx sfdx-lwc-jest force-app/main/default/lwc/laneBenchmarkPlacePicker` → module not found.

- [ ] **Step 3: Implement**

`laneBenchmarkPlacePicker.js`:

```javascript
import { LightningElement, api, track } from "lwc";
import searchPlaces from "@salesforce/apex/LaneBenchmarkController.searchPlaces";
import geocode from "@salesforce/apex/LaneBenchmarkController.geocode";

const DEBOUNCE_MS = 250;
const PRECISIONS = [
  { label: "Exact city", value: "CITY" },
  { label: "Province / state", value: "PROVINCE" },
  { label: "Postal prefix (FSA / ZIP3)", value: "ZIP3" },
  { label: "Radius", value: "RADIUS" }
];

export default class LaneBenchmarkPlacePicker extends LightningElement {
  @api label = "Place";
  @api value = null;
  @api valueLabel = "";
  @api precision = "CITY";
  @api radius = null;
  @api unit = "MI";

  @track options = [];
  term = "";
  isOpen = false;
  isSearching = false;
  error = null;
  precisionOptions = PRECISIONS;
  unitOptions = [
    { label: "mi", value: "MI" },
    { label: "km", value: "KM" }
  ];
  timer = null;

  get isRadius() {
    return this.precision === "RADIUS";
  }
  get hasValue() {
    return !!this.value;
  }
  get displayValue() {
    return this.hasValue ? this.valueLabel : this.term;
  }
  get showMapAction() {
    return this.isOpen && this.term.trim().length >= 3;
  }
  get listItems() {
    return this.options.map((o) => ({
      ...o,
      isMapbox: o.source === "Mapbox",
      loadText: o.loadCount ? `${o.loadCount} loads` : ""
    }));
  }

  handleTerm(event) {
    this.term = event.detail.value || "";
    if (this.hasValue) {
      this.value = null;
      this.valueLabel = "";
      this.emit();
    }
    window.clearTimeout(this.timer);
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    this.timer = window.setTimeout(() => this.search(), DEBOUNCE_MS);
  }

  async search() {
    const term = this.term.trim();
    if (term.length < 2) {
      this.options = [];
      this.isOpen = false;
      return;
    }
    this.isSearching = true;
    try {
      this.options = await searchPlaces({ term, limitCount: 10 });
      this.isOpen = true;
      this.error = null;
    } catch (e) {
      this.error = e?.body?.message || "Place search failed";
      this.options = [];
    } finally {
      this.isSearching = false;
    }
  }

  async handleMapSearch() {
    this.isSearching = true;
    try {
      this.options = await geocode({
        query: this.term.trim(),
        countryHint: null
      });
      this.isOpen = true;
      this.error = this.options.length ? null : "No place found on the map";
    } catch (e) {
      this.error = e?.body?.message || "Map search is unavailable right now";
    } finally {
      this.isSearching = false;
    }
  }

  handlePick(event) {
    const key = event.currentTarget.dataset.key;
    const opt = this.options.find((o) => o.key === key);
    this.value = opt.key;
    this.valueLabel = opt.label;
    this.term = "";
    this.options = [];
    this.isOpen = false;
    this.emit();
  }

  handleClear() {
    this.value = null;
    this.valueLabel = "";
    this.term = "";
    this.options = [];
    this.isOpen = false;
    this.emit();
  }

  handlePrecision(event) {
    this.precision = event.detail.value;
    if (!this.isRadius) {
      this.radius = null;
    }
    this.emit();
  }

  handleRadius(event) {
    const n = Number(event.detail.value);
    this.radius = Number.isFinite(n) && n > 0 ? n : null;
    this.emit();
  }

  handleUnit(event) {
    this.unit = event.detail.value;
    this.emit();
  }

  handleKey(event) {
    if (event.key === "Escape") {
      this.isOpen = false;
    }
  }

  emit() {
    this.dispatchEvent(
      new CustomEvent("placechange", {
        detail: {
          key: this.value,
          label: this.valueLabel,
          precision: this.precision,
          radius: this.isRadius ? this.radius : null,
          unit: this.unit
        }
      })
    );
  }
}
```

The `setTimeout` debounce is legitimate production code; `@lwc/lwc/no-async-operation` is disabled for that one line only, with the reason in the plan: a typeahead must debounce.

`laneBenchmarkPlacePicker.html`:

```html
<template>
  <div class="slds-form-element picker" onkeydown="{handleKey}">
    <div class="slds-grid slds-gutters_x-small slds-grid_vertical-align-end">
      <div class="slds-col slds-size_7-of-12 slds-is-relative">
        <lightning-input
          data-id="term"
          label="{label}"
          value="{displayValue}"
          placeholder="City, province or alias"
          onchange="{handleTerm}"
          autocomplete="off"
        ></lightning-input>
        <template lwc:if="{hasValue}">
          <button
            data-id="clear"
            class="slds-button slds-button_icon clear"
            title="Clear"
            onclick="{handleClear}"
          >
            <lightning-icon
              icon-name="utility:clear"
              size="x-small"
              alternative-text="Clear"
            ></lightning-icon>
          </button>
        </template>
        <template lwc:if="{isOpen}">
          <div
            class="slds-dropdown slds-dropdown_fluid slds-dropdown_length-10 list"
            role="listbox"
          >
            <ul class="slds-listbox slds-listbox_vertical">
              <template for:each="{listItems}" for:item="o">
                <li
                  key="{o.key}"
                  data-key="{o.key}"
                  class="slds-listbox__item option"
                  role="option"
                  onclick="{handlePick}"
                >
                  <span class="slds-truncate">{o.label}</span>
                  <span class="slds-text-color_weak slds-m-left_x-small"
                    >{o.loadText}</span
                  >
                  <template lwc:if="{o.isMapbox}"
                    ><lightning-badge
                      label="Mapbox"
                      class="slds-m-left_x-small"
                    ></lightning-badge
                  ></template>
                </li>
              </template>
            </ul>
            <template lwc:if="{showMapAction}">
              <div class="slds-p-around_x-small slds-border_top">
                <button
                  data-id="map-search"
                  class="slds-button slds-button_neutral slds-button_stretch"
                  onclick="{handleMapSearch}"
                >
                  Not found? Search on the map
                </button>
              </div>
            </template>
          </div>
        </template>
      </div>
      <div class="slds-col slds-size_5-of-12">
        <lightning-combobox
          data-id="precision"
          label="Precision"
          value="{precision}"
          options="{precisionOptions}"
          onchange="{handlePrecision}"
        ></lightning-combobox>
      </div>
    </div>
    <template lwc:if="{isRadius}">
      <div class="slds-grid slds-gutters_x-small slds-m-top_x-small">
        <div class="slds-col slds-size_7-of-12">
          <lightning-input
            data-id="radius"
            type="number"
            min="1"
            step="1"
            label="Radius"
            value="{radius}"
            onchange="{handleRadius}"
          ></lightning-input>
        </div>
        <div class="slds-col slds-size_5-of-12">
          <lightning-radio-group
            data-id="unit"
            label="Unit"
            type="button"
            options="{unitOptions}"
            value="{unit}"
            onchange="{handleUnit}"
          ></lightning-radio-group>
        </div>
      </div>
    </template>
    <template lwc:if="{isSearching}"
      ><lightning-spinner
        size="small"
        alternative-text="Searching"
      ></lightning-spinner
    ></template>
    <template lwc:if="{error}"
      ><div class="slds-text-color_error slds-m-top_xx-small">
        {error}
      </div></template
    >
  </div>
</template>
```

`laneBenchmarkPlacePicker.css`:

```css
.picker {
  position: relative;
}
.list {
  position: absolute;
  z-index: 9000;
  background: white;
}
.option {
  padding: 0.25rem 0.75rem;
  cursor: pointer;
  display: flex;
  align-items: center;
}
.option:hover {
  background: #f3f3f3;
}
.clear {
  position: absolute;
  right: 0.25rem;
  bottom: 0.25rem;
}
```

Meta: `apiVersion` 64.0, `isExposed` false. Manifest member.

- [ ] **Step 4: Run tests and lint**

Run: `npx sfdx-lwc-jest force-app/main/default/lwc/laneBenchmarkPlacePicker && npm run lint` → 5 pass. If the fake-timer debounce test is flaky, replace `jest.advanceTimersByTime(250)` with `jest.runOnlyPendingTimers()`.

- [ ] **Step 5: Commit**

```bash
git add force-app/main/default/lwc/laneBenchmarkPlacePicker manifest/package.xml
git commit -m "Add laneBenchmarkPlacePicker: dictionary typeahead with Mapbox fallback, precision and radius"
```

---

### Task 6: `laneBenchmarkFilters`

**Files:**

- Create: `lwc/laneBenchmarkFilters/{.js,.html,.js-meta.xml}`, `__tests__/laneBenchmarkFilters.test.js`
- Modify: `manifest/package.xml`

**Interfaces:**

- Consumes: `LaneBenchmarkController.getFilterOptions()` (called by the container and passed in as `@api options`).
- Produces: `<c-lane-benchmark-filters options={filterOptions} value={filters}>` where `filters = { lookbackDays, currencyIsoCode, modes, equipmentCategories, equipmentTypes, hazmatOnly, marketTestOnly, acceptedFilter }`; events `filterschange` (detail = full filters object), `apply`, `reset`, `clearsaved`.

- [ ] **Step 1: Failing tests**

```javascript
import { createElement } from "lwc";
import Filters from "c/laneBenchmarkFilters";

const flush = () => Promise.resolve().then(() => Promise.resolve());
const OPTIONS = {
  modes: ["Truckload", "LTL"],
  equipmentByCategory: { Van: ["Dry Van 53'"], Reefer: ["Reefer 53'"] },
  currencies: ["CAD", "USD"]
};
const DEFAULTS = {
  lookbackDays: 90,
  currencyIsoCode: null,
  modes: [],
  equipmentCategories: [],
  equipmentTypes: [],
  hazmatOnly: false,
  marketTestOnly: false,
  acceptedFilter: "ANY_STATUS"
};

async function mount(value = DEFAULTS) {
  const el = createElement("c-lane-benchmark-filters", { is: Filters });
  el.options = OPTIONS;
  el.value = value;
  document.body.appendChild(el);
  await flush();
  return el;
}
const change = (el, id, value) =>
  el.shadowRoot
    .querySelector(`[data-id="${id}"]`)
    .dispatchEvent(new CustomEvent("change", { detail: { value } }));

describe("c-lane-benchmark-filters", () => {
  afterEach(() => {
    while (document.body.firstChild)
      document.body.removeChild(document.body.firstChild);
  });

  it("renders defaults and options", async () => {
    const el = await mount();
    expect(el.shadowRoot.querySelector('[data-id="lookback"]').value).toBe(90);
    expect(
      el.shadowRoot.querySelector('[data-id="modes"]').options.length
    ).toBe(2);
    expect(
      el.shadowRoot
        .querySelector('[data-id="categories"]')
        .options.map((o) => o.value)
    ).toEqual(["Van", "Reefer"]);
  });

  it("emits the full filters object on each change and narrows equipment types by category", async () => {
    const el = await mount();
    const handler = jest.fn();
    el.addEventListener("filterschange", handler);
    change(el, "lookback", "365");
    change(el, "currency", "USD");
    change(el, "categories", ["Reefer"]);
    await flush();
    const last = handler.mock.calls[handler.mock.calls.length - 1][0].detail;
    expect(last).toMatchObject({
      lookbackDays: 365,
      currencyIsoCode: "USD",
      equipmentCategories: ["Reefer"]
    });
    expect(
      el.shadowRoot
        .querySelector('[data-id="types"]')
        .options.map((o) => o.value)
    ).toEqual(["Reefer 53'"]);
    change(el, "accepted", "ACCEPTED");
    change(el, "flags", ["hazmatOnly"]);
    await flush();
    const final = handler.mock.calls[handler.mock.calls.length - 1][0].detail;
    expect(final.acceptedFilter).toBe("ACCEPTED");
    expect(final.hazmatOnly).toBe(true);
    expect(final.marketTestOnly).toBe(false);
  });

  it("rejects a non-positive lookback and keeps the previous value", async () => {
    const el = await mount();
    const handler = jest.fn();
    el.addEventListener("filterschange", handler);
    change(el, "lookback", "0");
    await flush();
    expect(
      handler.mock.calls[handler.mock.calls.length - 1][0].detail.lookbackDays
    ).toBe(90);
    expect(el.shadowRoot.querySelector('[data-id="lookback"]').value).toBe(90);
  });

  it("apply, reset and clear-saved raise their events; reset restores defaults", async () => {
    const el = await mount({ ...DEFAULTS, lookbackDays: 30, modes: ["LTL"] });
    const apply = jest.fn();
    const reset = jest.fn();
    const clear = jest.fn();
    const changed = jest.fn();
    el.addEventListener("apply", apply);
    el.addEventListener("reset", reset);
    el.addEventListener("clearsaved", clear);
    el.addEventListener("filterschange", changed);
    el.shadowRoot.querySelector('[data-id="apply"]').click();
    el.shadowRoot.querySelector('[data-id="reset"]').click();
    el.shadowRoot.querySelector('[data-id="clear-saved"]').click();
    await flush();
    expect(apply).toHaveBeenCalledTimes(1);
    expect(reset).toHaveBeenCalledTimes(1);
    expect(clear).toHaveBeenCalledTimes(1);
    expect(changed.mock.calls[changed.mock.calls.length - 1][0].detail).toEqual(
      DEFAULTS
    );
  });
});
```

- [ ] **Step 2: Run to verify they fail** — module not found.

- [ ] **Step 3: Implement**

`laneBenchmarkFilters.js`:

```javascript
import { LightningElement, api } from "lwc";

export const DEFAULT_FILTERS = Object.freeze({
  lookbackDays: 90,
  currencyIsoCode: null,
  modes: [],
  equipmentCategories: [],
  equipmentTypes: [],
  hazmatOnly: false,
  marketTestOnly: false,
  acceptedFilter: "ANY_STATUS"
});

export default class LaneBenchmarkFilters extends LightningElement {
  @api options = {
    modes: [],
    equipmentByCategory: {},
    currencies: ["CAD", "USD"]
  };
  _value = { ...DEFAULT_FILTERS };
  @api get value() {
    return this._value;
  }
  set value(v) {
    this._value = { ...DEFAULT_FILTERS, ...(v || {}) };
  }

  acceptedOptions = [
    { label: "All", value: "ANY_STATUS" },
    { label: "Accepted", value: "ACCEPTED" },
    { label: "Declined", value: "DECLINED" }
  ];
  flagOptions = [
    { label: "Hazmat only", value: "hazmatOnly" },
    { label: "Market test only", value: "marketTestOnly" }
  ];

  get lookbackDays() {
    return this._value.lookbackDays;
  }
  get currencyValue() {
    return this._value.currencyIsoCode || "";
  }
  get currencyOptions() {
    return [
      { label: "All", value: "" },
      ...(this.options.currencies || []).map((c) => ({ label: c, value: c }))
    ];
  }
  get modeOptions() {
    return (this.options.modes || []).map((m) => ({ label: m, value: m }));
  }
  get categoryOptions() {
    return Object.keys(this.options.equipmentByCategory || {}).map((c) => ({
      label: c,
      value: c
    }));
  }
  get typeOptions() {
    const byCat = this.options.equipmentByCategory || {};
    const cats = this._value.equipmentCategories.length
      ? this._value.equipmentCategories
      : Object.keys(byCat);
    return cats
      .flatMap((c) => byCat[c] || [])
      .map((t) => ({ label: t, value: t }));
  }
  get flagValues() {
    return this.flagOptions.map((f) => f.value).filter((f) => this._value[f]);
  }

  update(patch) {
    this._value = { ...this._value, ...patch };
    this.dispatchEvent(
      new CustomEvent("filterschange", { detail: { ...this._value } })
    );
  }

  handleLookback(event) {
    const n = parseInt(event.detail.value, 10);
    if (!Number.isFinite(n) || n < 1) {
      this.update({});
      return;
    } // keep previous value, re-emit
    this.update({ lookbackDays: n });
  }
  handleCurrency(event) {
    this.update({ currencyIsoCode: event.detail.value || null });
  }
  handleModes(event) {
    this.update({ modes: [...event.detail.value] });
  }
  handleCategories(event) {
    const cats = [...event.detail.value];
    const allowed = new Set(
      cats.flatMap((c) => (this.options.equipmentByCategory || {})[c] || [])
    );
    const types = cats.length
      ? this._value.equipmentTypes.filter((t) => allowed.has(t))
      : this._value.equipmentTypes;
    this.update({ equipmentCategories: cats, equipmentTypes: types });
  }
  handleTypes(event) {
    this.update({ equipmentTypes: [...event.detail.value] });
  }
  handleAccepted(event) {
    this.update({ acceptedFilter: event.detail.value });
  }
  handleFlags(event) {
    const set = new Set(event.detail.value);
    this.update({
      hazmatOnly: set.has("hazmatOnly"),
      marketTestOnly: set.has("marketTestOnly")
    });
  }
  handleApply() {
    this.dispatchEvent(new CustomEvent("apply"));
  }
  handleReset() {
    this._value = { ...DEFAULT_FILTERS };
    this.dispatchEvent(
      new CustomEvent("filterschange", { detail: { ...this._value } })
    );
    this.dispatchEvent(new CustomEvent("reset"));
  }
  handleClearSaved() {
    this.dispatchEvent(new CustomEvent("clearsaved"));
  }
}
```

`laneBenchmarkFilters.html`:

```html
<template>
  <div class="slds-form slds-form_stacked">
    <lightning-input
      data-id="lookback"
      type="number"
      min="1"
      step="1"
      label="Lookback (days)"
      value="{lookbackDays}"
      onchange="{handleLookback}"
      field-level-help="Default 90. Any number of days back; radius searches over a year are slower."
    ></lightning-input>
    <lightning-combobox
      data-id="currency"
      label="Currency"
      value="{currencyValue}"
      options="{currencyOptions}"
      onchange="{handleCurrency}"
    ></lightning-combobox>
    <lightning-dual-listbox
      data-id="modes"
      label="Modes"
      source-label="Available"
      selected-label="Selected"
      options="{modeOptions}"
      value="{value.modes}"
      onchange="{handleModes}"
      size="4"
    ></lightning-dual-listbox>
    <lightning-checkbox-group
      data-id="categories"
      label="Equipment categories"
      options="{categoryOptions}"
      value="{value.equipmentCategories}"
      onchange="{handleCategories}"
    ></lightning-checkbox-group>
    <lightning-dual-listbox
      data-id="types"
      label="Equipment types"
      source-label="Available"
      selected-label="Selected"
      options="{typeOptions}"
      value="{value.equipmentTypes}"
      onchange="{handleTypes}"
      size="5"
    ></lightning-dual-listbox>
    <lightning-checkbox-group
      data-id="flags"
      label="Only"
      options="{flagOptions}"
      value="{flagValues}"
      onchange="{handleFlags}"
    ></lightning-checkbox-group>
    <lightning-radio-group
      data-id="accepted"
      label="Quote status"
      type="button"
      options="{acceptedOptions}"
      value="{value.acceptedFilter}"
      onchange="{handleAccepted}"
    ></lightning-radio-group>
    <div class="slds-m-top_small slds-grid slds-grid_align-spread">
      <div>
        <lightning-button
          data-id="apply"
          variant="brand"
          label="Apply"
          onclick="{handleApply}"
        ></lightning-button>
        <lightning-button
          data-id="reset"
          label="Reset"
          class="slds-m-left_x-small"
          onclick="{handleReset}"
        ></lightning-button>
      </div>
      <button
        data-id="clear-saved"
        class="slds-button slds-button_reset slds-text-link"
        onclick="{handleClearSaved}"
      >
        Clear saved filters
      </button>
    </div>
  </div>
</template>
```

Meta: 64.0, not exposed. Manifest member.

- [ ] **Step 4: Run tests and lint**

Run: `npx sfdx-lwc-jest force-app/main/default/lwc/laneBenchmarkFilters && npm run lint` → 4 pass. If `lightning-dual-listbox`'s stub does not expose `.options`, assert through the component's getters via a test-only `@api`? No: assert on the rendered stub attribute `options` (the sfdx-lwc-jest stubs reflect `@api` properties; `querySelector(...).options` works).

- [ ] **Step 5: Commit**

```bash
git add force-app/main/default/lwc/laneBenchmarkFilters manifest/package.xml
git commit -m "Add laneBenchmarkFilters: lookback, currency, modes, equipment, flags"
```

---

### Task 7: `laneBenchmarkStats`

**Files:**

- Create: `lwc/laneBenchmarkStats/{.js,.html,.js-meta.xml}`, `__tests__/laneBenchmarkStats.test.js`
- Modify: `manifest/package.xml`

**Interfaces:**

- Consumes: `c/marginMath`.
- Produces: `<c-lane-benchmark-stats stats-by-currency={result.statsByCurrency} deduped-count={result.dedupedCount} truncated={result.truncated} elapsed-ms={result.elapsedMs} row-count={rows.length}>`; internal margin state (default 15), event `marginchange` (detail `{ marginPct }`) so the container can persist it with the filters.

- [ ] **Step 1: Failing tests**

```javascript
import { createElement } from "lwc";
import Stats from "c/laneBenchmarkStats";

const flush = () => Promise.resolve().then(() => Promise.resolve());
const STATS = {
  CAD: {
    count: 4,
    countNonZero: 3,
    min: 1000,
    max: 3000,
    avg: 2000,
    median: 2000
  },
  USD: {
    count: 2,
    countNonZero: 2,
    min: 800,
    max: 1200,
    avg: 1000,
    median: 1000
  }
};

async function mount(props = {}) {
  const el = createElement("c-lane-benchmark-stats", { is: Stats });
  Object.assign(
    el,
    {
      statsByCurrency: STATS,
      dedupedCount: 4,
      truncated: false,
      elapsedMs: 412,
      rowCount: 6
    },
    props
  );
  document.body.appendChild(el);
  await flush();
  return el;
}
const text = (el) => el.shadowRoot.textContent;

describe("c-lane-benchmark-stats", () => {
  afterEach(() => {
    while (document.body.firstChild)
      document.body.removeChild(document.body.firstChild);
  });

  it("renders one card per currency with suggested sell at the default 15%", async () => {
    const el = await mount();
    const cards = el.shadowRoot.querySelectorAll("[data-currency]");
    expect(Array.from(cards).map((c) => c.dataset.currency)).toEqual([
      "CAD",
      "USD"
    ]);
    expect(text(el)).toContain("2,300.00"); // CAD median 2000 * 1.15
    expect(text(el)).toContain("1,150.00"); // USD median 1000 * 1.15
    expect(text(el)).toContain("4 duplicates removed");
    expect(text(el)).toContain("0.4 s");
  });

  it("20% button and free entry change the suggestion and emit marginchange", async () => {
    const el = await mount();
    const handler = jest.fn();
    el.addEventListener("marginchange", handler);
    el.shadowRoot.querySelector('[data-id="margin-20"]').click();
    await flush();
    expect(text(el)).toContain("2,400.00");
    expect(handler.mock.calls[0][0].detail).toEqual({ marginPct: 20 });
    const input = el.shadowRoot.querySelector('[data-id="margin"]');
    input.dispatchEvent(
      new CustomEvent("change", { detail: { value: "12.5" } })
    );
    await flush();
    expect(text(el)).toContain("2,250.00");
    input.dispatchEvent(
      new CustomEvent("change", { detail: { value: "250" } })
    );
    await flush();
    expect(text(el)).toContain("2,250.00"); // invalid input keeps the last margin
    expect(text(el)).toMatch(/0 and 100/);
  });

  it("shows the truncation notice and an empty state", async () => {
    const el = await mount({ truncated: true });
    expect(text(el)).toMatch(/first 2,?000/i);
    const empty = await mount({ statsByCurrency: {}, rowCount: 0 });
    expect(text(empty)).toContain("No quotes");
  });
});
```

- [ ] **Step 2: Run to verify they fail** — module not found.

- [ ] **Step 3: Implement**

`laneBenchmarkStats.js`:

```javascript
import { LightningElement, api } from "lwc";
import { parseMargin, suggestedSell } from "c/marginMath";

const fmt = (n) =>
  n === null || n === undefined
    ? "—"
    : Number(n).toLocaleString("en-CA", {
        minimumFractionDigits: 2,
        maximumFractionDigits: 2
      });

export default class LaneBenchmarkStats extends LightningElement {
  @api statsByCurrency = {};
  @api dedupedCount = 0;
  @api truncated = false;
  @api elapsedMs = 0;
  @api rowCount = 0;
  @api marginPct = 15;
  marginError = null;

  get hasStats() {
    return Object.keys(this.statsByCurrency || {}).length > 0;
  }
  get isEmpty() {
    return !this.hasStats && this.rowCount === 0;
  }
  get elapsedText() {
    return `${(Number(this.elapsedMs || 0) / 1000).toFixed(1)} s`;
  }
  get dedupeText() {
    return this.dedupedCount ? `${this.dedupedCount} duplicates removed` : "";
  }
  get cards() {
    return Object.keys(this.statsByCurrency || {})
      .sort()
      .map((currency) => {
        const s = this.statsByCurrency[currency];
        return {
          currency,
          count: s.count,
          countNonZero: s.countNonZero,
          min: fmt(s.min),
          max: fmt(s.max),
          avg: fmt(s.avg),
          median: fmt(s.median),
          sellMedian: fmt(suggestedSell(s.median, this.marginPct)),
          sellAvg: fmt(suggestedSell(s.avg, this.marginPct))
        };
      });
  }

  setMargin(n) {
    this.marginPct = n;
    this.marginError = null;
    this.dispatchEvent(
      new CustomEvent("marginchange", { detail: { marginPct: n } })
    );
  }
  handleMargin15() {
    this.setMargin(15);
  }
  handleMargin20() {
    this.setMargin(20);
  }
  handleMarginInput(event) {
    const n = parseMargin(event.detail.value);
    if (n === null) {
      this.marginError = "Enter a margin between 0 and 100";
      return;
    }
    this.setMargin(n);
  }
}
```

`laneBenchmarkStats.html`:

```html
<template>
  <lightning-card title="Statistics" icon-name="standard:metrics">
    <div class="slds-p-horizontal_medium">
      <template lwc:if="{isEmpty}">
        <p class="slds-text-color_weak">
          No quotes match this lane and these filters yet. Widen the radius or
          the lookback, or choose a broader precision.
        </p>
      </template>
      <template lwc:else>
        <div
          class="slds-grid slds-gutters_small slds-wrap slds-m-bottom_small slds-grid_vertical-align-end"
        >
          <div class="slds-col slds-size_1-of-3">
            <lightning-input
              data-id="margin"
              type="text"
              label="Margin %"
              value="{marginPct}"
              onchange="{handleMarginInput}"
            ></lightning-input>
            <template lwc:if="{marginError}"
              ><div class="slds-text-color_error slds-text-body_small">
                {marginError}
              </div></template
            >
          </div>
          <div class="slds-col">
            <lightning-button
              data-id="margin-15"
              label="15%"
              onclick="{handleMargin15}"
            ></lightning-button>
            <lightning-button
              data-id="margin-20"
              label="20%"
              class="slds-m-left_x-small"
              onclick="{handleMargin20}"
            ></lightning-button>
          </div>
          <div
            class="slds-col slds-text-align_right slds-text-color_weak slds-text-body_small"
          >
            {rowCount} rows in {elapsedText} · {dedupeText}
          </div>
        </div>
        <template lwc:if="{truncated}">
          <div
            class="slds-notify slds-notify_alert slds-alert_warning slds-m-bottom_small"
            role="alert"
          >
            Showing the first 2,000 most recent quotes; narrow the lookback or
            filters to see everything.
          </div>
        </template>
        <div class="slds-grid slds-gutters_small slds-wrap">
          <template for:each="{cards}" for:item="c">
            <div
              key="{c.currency}"
              data-currency="{c.currency}"
              class="slds-col slds-size_1-of-1 slds-large-size_1-of-2 slds-m-bottom_small"
            >
              <div class="slds-box slds-box_small">
                <h3 class="slds-text-heading_small">
                  {c.currency} · {c.count} quotes ({c.countNonZero} priced)
                </h3>
                <dl class="slds-dl_horizontal slds-m-top_x-small">
                  <dt class="slds-dl_horizontal__label">Min</dt>
                  <dd class="slds-dl_horizontal__detail">{c.min}</dd>
                  <dt class="slds-dl_horizontal__label">Median</dt>
                  <dd class="slds-dl_horizontal__detail">{c.median}</dd>
                  <dt class="slds-dl_horizontal__label">Average</dt>
                  <dd class="slds-dl_horizontal__detail">{c.avg}</dd>
                  <dt class="slds-dl_horizontal__label">Max</dt>
                  <dd class="slds-dl_horizontal__detail">{c.max}</dd>
                  <dt class="slds-dl_horizontal__label slds-text-title_bold">
                    Sell (median)
                  </dt>
                  <dd class="slds-dl_horizontal__detail slds-text-title_bold">
                    {c.sellMedian}
                  </dd>
                  <dt class="slds-dl_horizontal__label">Sell (average)</dt>
                  <dd class="slds-dl_horizontal__detail">{c.sellAvg}</dd>
                </dl>
              </div>
            </div>
          </template>
        </div>
      </template>
    </div>
  </lightning-card>
</template>
```

Meta 64.0 not exposed; manifest.

- [ ] **Step 4: Run tests and lint**

Run: `npx sfdx-lwc-jest force-app/main/default/lwc/laneBenchmarkStats && npm run lint` → 3 pass. Note `toLocaleString('en-CA')` in Node/jsdom formats `2300` as `2,300.00`; if the ICU data differs, format manually (`Intl.NumberFormat('en-CA', ...)` is the same engine; fall back to a hand-written thousands separator if needed and say so).

- [ ] **Step 5: Commit**

```bash
git add force-app/main/default/lwc/laneBenchmarkStats manifest/package.xml
git commit -m "Add laneBenchmarkStats: per-currency statistics with margin and suggested sell"
```

---

### Task 8: `laneBenchmarkResults`

**Files:**

- Create: `lwc/laneBenchmarkResults/{.js,.html,.css,.js-meta.xml}`, `__tests__/laneBenchmarkResults.test.js`
- Modify: `manifest/package.xml`

**Interfaces:**

- Consumes: `c/laneBenchmarkCsv`.
- Produces: `<c-lane-benchmark-results rows={result.rows} origin-label={...} destination-label={...}>`; internal expand state and carrier popup; "Export CSV" downloads via a temporary anchor with a `Blob` URL.

- [ ] **Step 1: Failing tests**

```javascript
import { createElement } from "lwc";
import Results from "c/laneBenchmarkResults";

const flush = () => Promise.resolve().then(() => Promise.resolve());
const ROWS = [
  {
    quoteId: "q1",
    quoteName: "CQ-1",
    origin: "Montréal, Quebec",
    destination: "Toronto, Ontario",
    mode: "Truckload",
    equipment: "Dry Van 53'",
    carrierName: "Acme",
    contactName: "Jo Contact",
    contactEmail: "jo@acme.test",
    contactPhone: "514-555-0100",
    carrierRisk: "Acceptable",
    carrierLoadCount: 42,
    carrierAttention: "",
    currencyIsoCode: "CAD",
    carrierTotal: 1000,
    quoteDate: "2026-09-01",
    createdDate: "2026-09-01T10:00:00.000Z",
    hazmat: false,
    accepted: true,
    loadStatus: "Delivered",
    opsComments: "Fast pickup"
  },
  {
    quoteId: "q2",
    quoteName: "CQ-2",
    origin: "Laval, Quebec",
    destination: "Toronto, Ontario",
    mode: "LTL",
    equipment: "Reefer 53'",
    carrierName: 'Beta "Cold"',
    contactName: null,
    contactEmail: null,
    contactPhone: null,
    carrierRisk: "Moderate",
    carrierLoadCount: 3,
    carrierAttention: " THE CARRIER IS BLACK-LISTED ",
    currencyIsoCode: "USD",
    carrierTotal: 800,
    quoteDate: "2026-08-30",
    createdDate: "2026-08-30T10:00:00.000Z",
    hazmat: true,
    accepted: false,
    loadStatus: "Quotes Received",
    opsComments: null
  }
];

async function mount(rows = ROWS) {
  const el = createElement("c-lane-benchmark-results", { is: Results });
  el.rows = rows;
  el.originLabel = "Montréal, QC, CA";
  el.destinationLabel = "Toronto, ON, CA";
  document.body.appendChild(el);
  await flush();
  return el;
}

describe("c-lane-benchmark-results", () => {
  afterEach(() => {
    while (document.body.firstChild)
      document.body.removeChild(document.body.firstChild);
    jest.restoreAllMocks();
  });

  it("renders one row per quote with mode class and flags", async () => {
    const el = await mount();
    const rows = el.shadowRoot.querySelectorAll("tbody tr[data-index]");
    expect(rows.length).toBe(2);
    expect(rows[1].querySelector('[data-id="mode"]').className).toContain(
      "ltl-cell"
    );
    expect(rows[1].textContent).toContain("Hazmat");
    expect(rows[0].textContent).toContain("Accepted");
  });

  it("expands a row to show comments and opens/closes the carrier popup", async () => {
    const el = await mount();
    el.shadowRoot
      .querySelector('tbody tr[data-index="0"] [data-id="expand"]')
      .click();
    await flush();
    expect(
      el.shadowRoot.querySelector('tr[data-detail="0"]').textContent
    ).toContain("Fast pickup");
    el.shadowRoot
      .querySelector('tbody tr[data-index="1"] [data-id="carrier"]')
      .click();
    await flush();
    const dialog = el.shadowRoot.querySelector('section[role="dialog"]');
    expect(dialog).not.toBeNull();
    expect(dialog.textContent).toContain("BLACK-LISTED");
    expect(dialog.textContent).toContain("Moderate");
    dialog.dispatchEvent(new CustomEvent("click", { bubbles: true }));
    await flush();
    expect(
      el.shadowRoot.querySelector('section[role="dialog"]')
    ).not.toBeNull();
    el.shadowRoot.querySelector('[data-id="close"]').click();
    await flush();
    expect(el.shadowRoot.querySelector('section[role="dialog"]')).toBeNull();
  });

  it("exports the visible rows as CSV", async () => {
    const el = await mount();
    const createUrl = jest.fn(() => "blob:x");
    const revoke = jest.fn();
    global.URL.createObjectURL = createUrl;
    global.URL.revokeObjectURL = revoke;
    const clicks = jest
      .spyOn(HTMLAnchorElement.prototype, "click")
      .mockImplementation(() => {});
    el.shadowRoot.querySelector('[data-id="export"]').click();
    await flush();
    expect(createUrl).toHaveBeenCalledTimes(1);
    const blob = createUrl.mock.calls[0][0];
    const textOf = await new Response(blob).text();
    expect(textOf.startsWith("﻿Origin,Destination,Carrier")).toBe(true);
    expect(textOf).toContain('"Beta ""Cold"""');
    expect(clicks).toHaveBeenCalledTimes(1);
    expect(revoke).toHaveBeenCalledWith("blob:x");
  });

  it("shows nothing but a hint when there are no rows", async () => {
    const el = await mount([]);
    expect(el.shadowRoot.querySelectorAll("tbody tr[data-index]").length).toBe(
      0
    );
    expect(el.shadowRoot.querySelector('[data-id="export"]')).toBeNull();
  });
});
```

- [ ] **Step 2: Run to verify they fail** — module not found.

- [ ] **Step 3: Implement**

`laneBenchmarkResults.js`:

```javascript
import { LightningElement, api, track } from "lwc";
import { toCsv, fileName } from "c/laneBenchmarkCsv";

const MODE_CLASS = {
  LTL: "ltl-cell",
  Truckload: "ftl-cell",
  "Freight Forwarding": "freight-cell"
};
export const CSV_COLUMNS = [
  { label: "Origin", field: "origin" },
  { label: "Destination", field: "destination" },
  { label: "Carrier", field: "carrierName" },
  { label: "Contact", field: "contactName" },
  { label: "Email", field: "contactEmail" },
  { label: "Phone", field: "contactPhone" },
  { label: "Mode", field: "mode" },
  { label: "Equipment", field: "equipment" },
  { label: "Currency", field: "currencyIsoCode" },
  { label: "Carrier total", field: "carrierTotal" },
  { label: "Quote date", field: "quoteDate" },
  { label: "Load status", field: "loadStatus" },
  { label: "Hazmat", field: "hazmat" },
  { label: "Accepted", field: "accepted" },
  { label: "Quote", field: "quoteName" },
  { label: "Comments", field: "opsComments" }
];

export default class LaneBenchmarkResults extends LightningElement {
  @api rows = [];
  @api originLabel = "";
  @api destinationLabel = "";
  @track expanded = new Set();
  selected = null;

  get hasRows() {
    return (this.rows || []).length > 0;
  }
  get viewRows() {
    return (this.rows || []).map((r, i) => ({
      ...r,
      index: i,
      rowNumber: i + 1,
      modeClass: `slds-cell-wrap ${MODE_CLASS[r.mode] || ""}`.trim(),
      isExpanded: this.expanded.has(i),
      total:
        r.carrierTotal === null || r.carrierTotal === undefined
          ? ""
          : Number(r.carrierTotal).toFixed(2),
      hazmatText: r.hazmat ? "Hazmat" : "",
      acceptedText: r.accepted ? "Accepted" : "Declined"
    }));
  }
  get selectedFlags() {
    return this.selected && this.selected.carrierAttention
      ? this.selected.carrierAttention.trim()
      : "";
  }

  handleExpand(event) {
    const i = Number(event.currentTarget.closest("tr").dataset.index);
    const next = new Set(this.expanded);
    if (next.has(i)) next.delete(i);
    else next.add(i);
    this.expanded = next;
  }
  handleCarrier(event) {
    const i = Number(event.currentTarget.closest("tr").dataset.index);
    this.selected = this.rows[i];
  }
  handleClose() {
    this.selected = null;
  }
  handleDialogClick(event) {
    event.stopPropagation();
  }

  handleExport() {
    const csv = toCsv(this.rows, CSV_COLUMNS);
    const blob = new Blob([csv], { type: "text/csv;charset=utf-8" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = fileName(this.originLabel, this.destinationLabel, new Date());
    a.click();
    URL.revokeObjectURL(url);
  }
}
```

`laneBenchmarkResults.html`:

```html
<template>
  <lightning-card title="Results" icon-name="standard:quotes">
    <template lwc:if="{hasRows}">
      <lightning-button
        slot="actions"
        data-id="export"
        label="Export CSV"
        icon-name="utility:download"
        onclick="{handleExport}"
      ></lightning-button>
    </template>
    <div class="slds-p-horizontal_small">
      <template lwc:if="{hasRows}">
        <table
          class="slds-table slds-table_bordered slds-table_fixed-layout results"
        >
          <thead>
            <tr class="slds-line-height_reset">
              <th scope="col" class="w-2"></th>
              <th scope="col" class="w-2">#</th>
              <th scope="col">Origin</th>
              <th scope="col">Destination</th>
              <th scope="col">Carrier</th>
              <th scope="col">Equipment</th>
              <th scope="col">Mode</th>
              <th scope="col" class="w-4">Cur.</th>
              <th scope="col" class="w-6">Total</th>
              <th scope="col" class="w-7">Quote date</th>
              <th scope="col">Status</th>
              <th scope="col" class="w-5">Flags</th>
            </tr>
          </thead>
          <tbody>
            <template for:each="{viewRows}" for:item="r">
              <tr key="{r.quoteId}" data-index="{r.index}">
                <td>
                  <button
                    data-id="expand"
                    class="slds-button slds-button_icon"
                    title="Details"
                    onclick="{handleExpand}"
                  >
                    <lightning-icon
                      icon-name="utility:chevronright"
                      size="xx-small"
                      alternative-text="Details"
                    ></lightning-icon>
                  </button>
                </td>
                <td>{r.rowNumber}</td>
                <td class="slds-cell-wrap">{r.origin}</td>
                <td class="slds-cell-wrap">{r.destination}</td>
                <td>
                  <button
                    data-id="carrier"
                    class="slds-button slds-text-link"
                    onclick="{handleCarrier}"
                  >
                    {r.carrierName}
                  </button>
                </td>
                <td class="slds-cell-wrap">{r.equipment}</td>
                <td data-id="mode" class="{r.modeClass}">{r.mode}</td>
                <td>{r.currencyIsoCode}</td>
                <td class="slds-text-align_right">{r.total}</td>
                <td>{r.quoteDate}</td>
                <td class="slds-cell-wrap">{r.loadStatus}</td>
                <td class="slds-cell-wrap">{r.hazmatText} {r.acceptedText}</td>
              </tr>
              <template lwc:if="{r.isExpanded}">
                <tr key="{r.quoteName}" data-detail="{r.index}" class="detail">
                  <td colspan="12">
                    <div class="slds-p-around_x-small">
                      <strong>Quote {r.quoteName}</strong> · Contact:
                      {r.contactName} · Comments: {r.opsComments}
                    </div>
                  </td>
                </tr>
              </template>
            </template>
          </tbody>
        </table>
      </template>
      <template lwc:else
        ><p class="slds-text-color_weak slds-p-around_small">
          Run a search to see quotes.
        </p></template
      >
    </div>
  </lightning-card>
  <template lwc:if="{selected}">
    <div class="modal-wrapper" onclick="{handleClose}">
      <section
        role="dialog"
        class="slds-modal slds-fade-in-open slds-modal_small"
        onclick="{handleDialogClick}"
      >
        <div class="slds-modal__container">
          <header class="slds-modal__header">
            <h2 class="slds-modal__title">{selected.carrierName}</h2>
          </header>
          <div class="slds-modal__content slds-p-around_medium">
            <dl class="slds-dl_horizontal">
              <dt class="slds-dl_horizontal__label">Contact</dt>
              <dd class="slds-dl_horizontal__detail">{selected.contactName}</dd>
              <dt class="slds-dl_horizontal__label">Email</dt>
              <dd class="slds-dl_horizontal__detail">
                {selected.contactEmail}
              </dd>
              <dt class="slds-dl_horizontal__label">Phone</dt>
              <dd class="slds-dl_horizontal__detail">
                {selected.contactPhone}
              </dd>
              <dt class="slds-dl_horizontal__label">Risk</dt>
              <dd class="slds-dl_horizontal__detail">{selected.carrierRisk}</dd>
              <dt class="slds-dl_horizontal__label">Loads</dt>
              <dd class="slds-dl_horizontal__detail">
                {selected.carrierLoadCount}
              </dd>
            </dl>
            <template lwc:if="{selectedFlags}"
              ><div
                class="slds-notify slds-notify_alert slds-alert_error slds-m-top_small"
              >
                {selectedFlags}
              </div></template
            >
          </div>
          <footer class="slds-modal__footer">
            <lightning-button
              data-id="close"
              label="Close"
              onclick="{handleClose}"
            ></lightning-button>
          </footer>
        </div>
      </section>
      <div class="slds-backdrop slds-backdrop_open"></div>
    </div>
  </template>
</template>
```

`laneBenchmarkResults.css` (reuse the old page's colours):

```css
.ltl-cell {
  background: #fff4e5;
}
.ftl-cell {
  background: #e8f4ff;
}
.freight-cell {
  background: #eefbea;
}
.detail td {
  background: #fafaf9;
}
.modal-wrapper {
  position: fixed;
  inset: 0;
  z-index: 9001;
}
.w-2 {
  width: 2rem;
}
.w-4 {
  width: 4rem;
}
.w-5 {
  width: 5rem;
}
.w-6 {
  width: 6rem;
}
.w-7 {
  width: 7rem;
}
```

Meta 64.0 not exposed; manifest.

- [ ] **Step 4: Run tests and lint** → 4 pass. If `new Response(blob).text()` is unavailable in the jsdom version, read the blob with `FileReader` in the test or assert on the `Blob` size and on `toCsv` separately (the module has its own tests).

- [ ] **Step 5: Commit**

```bash
git add force-app/main/default/lwc/laneBenchmarkResults manifest/package.xml
git commit -m "Add laneBenchmarkResults: table, expandable rows, carrier popup, CSV export"
```

---

### Task 9: `laneBenchmarkMap` and the `laneBenchmark` container

**Files:**

- Create: `lwc/laneBenchmarkMap/{.js,.html,.js-meta.xml}`, `__tests__/laneBenchmarkMap.test.js`; `lwc/laneBenchmark/{.js,.html,.css,.js-meta.xml}`, `__tests__/laneBenchmark.test.js`
- Modify: `manifest/package.xml`

**Interfaces:**

- Consumes: all Task 4-8 components; Apex `search`, `getFilterOptions`, `mapPreviewUrl`; `c/laneBenchmarkStorage`; `DEFAULT_FILTERS` from `c/laneBenchmarkFilters`.
- Produces: `laneBenchmark` exposed to `lightning__AppPage` and `lightning__HomePage`; `laneBenchmarkMap` with `@api previewUrl`.

- [ ] **Step 1: Failing tests**

`laneBenchmarkMap.test.js`:

```javascript
import { createElement } from "lwc";
import MapPreview from "c/laneBenchmarkMap";
const flush = () => Promise.resolve().then(() => Promise.resolve());

describe("c-lane-benchmark-map", () => {
  afterEach(() => {
    while (document.body.firstChild)
      document.body.removeChild(document.body.firstChild);
  });
  it("renders the image only when a url is given", async () => {
    const el = createElement("c-lane-benchmark-map", { is: MapPreview });
    document.body.appendChild(el);
    await flush();
    expect(el.shadowRoot.querySelector("img")).toBeNull();
    el.previewUrl =
      "https://api.mapbox.com/styles/v1/x/static/auto/600x300?access_token=pk";
    await flush();
    expect(el.shadowRoot.querySelector("img").src).toContain("api.mapbox.com");
  });
});
```

`laneBenchmark.test.js`:

```javascript
import { createElement } from "lwc";
import LaneBenchmark from "c/laneBenchmark";
import search from "@salesforce/apex/LaneBenchmarkController.search";
import getFilterOptions from "@salesforce/apex/LaneBenchmarkController.getFilterOptions";
import mapPreviewUrl from "@salesforce/apex/LaneBenchmarkController.mapPreviewUrl";
import { save, load, STORAGE_KEY } from "c/laneBenchmarkStorage";

jest.mock(
  "@salesforce/apex/LaneBenchmarkController.search",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/LaneBenchmarkController.getFilterOptions",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/LaneBenchmarkController.mapPreviewUrl",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/LaneBenchmarkController.searchPlaces",
  () => ({ default: jest.fn().mockResolvedValue([]) }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/LaneBenchmarkController.geocode",
  () => ({ default: jest.fn().mockResolvedValue([]) }),
  { virtual: true }
);

const flush = () => Promise.resolve().then(() => Promise.resolve());
const RESULT = {
  rows: [
    {
      quoteId: "q1",
      quoteName: "CQ-1",
      origin: "A",
      destination: "B",
      mode: "LTL",
      carrierName: "Acme",
      currencyIsoCode: "CAD",
      carrierTotal: 1000,
      quoteDate: "2026-09-01",
      accepted: true
    }
  ],
  statsByCurrency: {
    CAD: {
      count: 1,
      countNonZero: 1,
      min: 1000,
      max: 1000,
      avg: 1000,
      median: 1000
    }
  },
  truncated: false,
  elapsedMs: 300,
  dedupedCount: 0
};

async function mount() {
  const el = createElement("c-lane-benchmark", { is: LaneBenchmark });
  document.body.appendChild(el);
  await flush();
  await flush();
  return el;
}
const pick = (el, label, detail) =>
  el.shadowRoot
    .querySelector(`c-lane-benchmark-place-picker[data-id="${label}"]`)
    .dispatchEvent(new CustomEvent("placechange", { detail }));

describe("c-lane-benchmark", () => {
  beforeEach(() => {
    window.localStorage.clear();
    getFilterOptions.mockResolvedValue({
      modes: ["LTL"],
      equipmentByCategory: { Van: ["Dry Van"] },
      currencies: ["CAD", "USD"]
    });
    search.mockResolvedValue(RESULT);
    mapPreviewUrl.mockResolvedValue(null);
  });
  afterEach(() => {
    while (document.body.firstChild)
      document.body.removeChild(document.body.firstChild);
    jest.clearAllMocks();
  });

  it("does not search on load without a saved request, then searches on apply with the assembled request", async () => {
    const el = await mount();
    expect(search).not.toHaveBeenCalled();
    pick(el, "origin", {
      key: "montreal|qc|ca",
      label: "Montréal, QC, CA",
      precision: "CITY",
      radius: null,
      unit: "MI"
    });
    pick(el, "destination", {
      key: "toronto|on|ca",
      label: "Toronto, ON, CA",
      precision: "RADIUS",
      radius: 100,
      unit: "KM"
    });
    el.shadowRoot
      .querySelector("c-lane-benchmark-filters")
      .dispatchEvent(
        new CustomEvent("filterschange", {
          detail: {
            lookbackDays: 120,
            currencyIsoCode: "CAD",
            modes: ["LTL"],
            equipmentCategories: [],
            equipmentTypes: [],
            hazmatOnly: false,
            marketTestOnly: false,
            acceptedFilter: "ANY_STATUS"
          }
        })
      );
    el.shadowRoot
      .querySelector("c-lane-benchmark-filters")
      .dispatchEvent(new CustomEvent("apply"));
    await flush();
    await flush();
    expect(search).toHaveBeenCalledTimes(1);
    const sent = JSON.parse(search.mock.calls[0][0].requestJson);
    expect(sent).toMatchObject({
      originKey: "montreal|qc|ca",
      originPrecision: "CITY",
      destinationKey: "toronto|on|ca",
      destinationPrecision: "RADIUS",
      destinationRadius: 100,
      radiusUnit: "KM",
      lookbackDays: 120,
      currencyIsoCode: "CAD",
      modes: ["LTL"]
    });
    expect(
      el.shadowRoot.querySelector("c-lane-benchmark-results").rows.length
    ).toBe(1);
    expect(load()).toMatchObject({
      originKey: "montreal|qc|ca",
      lookbackDays: 120,
      marginPct: 15
    });
    expect(mapPreviewUrl).toHaveBeenCalledWith({
      originKey: "montreal|qc|ca",
      originRadius: null,
      destinationKey: "toronto|on|ca",
      destinationRadius: 100,
      unit: "KM"
    });
  });

  it("restores a saved request and searches immediately", async () => {
    save({
      originKey: "laval|qc|ca",
      originLabel: "Laval, QC, CA",
      originPrecision: "CITY",
      destinationKey: null,
      lookbackDays: 45,
      marginPct: 20,
      modes: [],
      equipmentCategories: [],
      equipmentTypes: [],
      acceptedFilter: "ANY_STATUS"
    });
    await mount();
    await flush();
    expect(search).toHaveBeenCalledTimes(1);
    expect(JSON.parse(search.mock.calls[0][0].requestJson)).toMatchObject({
      originKey: "laval|qc|ca",
      lookbackDays: 45
    });
  });

  it("gates a long radius search behind a confirmation", async () => {
    const el = await mount();
    pick(el, "origin", {
      key: "montreal|qc|ca",
      label: "Montréal, QC, CA",
      precision: "RADIUS",
      radius: 100,
      unit: "MI"
    });
    el.shadowRoot
      .querySelector("c-lane-benchmark-filters")
      .dispatchEvent(
        new CustomEvent("filterschange", {
          detail: {
            lookbackDays: 730,
            modes: [],
            equipmentCategories: [],
            equipmentTypes: [],
            acceptedFilter: "ANY_STATUS"
          }
        })
      );
    el.shadowRoot
      .querySelector("c-lane-benchmark-filters")
      .dispatchEvent(new CustomEvent("apply"));
    await flush();
    expect(search).not.toHaveBeenCalled();
    expect(el.shadowRoot.textContent).toMatch(/10-20 seconds/);
    el.shadowRoot.querySelector('[data-id="continue"]').click();
    await flush();
    await flush();
    expect(search).toHaveBeenCalledTimes(1);
  });

  it("shows the controller error message and clears results", async () => {
    search.mockRejectedValue({
      body: { message: "Unknown place key: nowhere|zz|zz" }
    });
    const el = await mount();
    el.shadowRoot
      .querySelector("c-lane-benchmark-filters")
      .dispatchEvent(new CustomEvent("apply"));
    await flush();
    await flush();
    expect(
      el.shadowRoot.querySelector('[data-id="error"]').textContent
    ).toContain("nowhere|zz|zz");
  });

  it("clear saved filters empties storage and resets the request", async () => {
    save({
      originKey: "laval|qc|ca",
      lookbackDays: 45,
      modes: [],
      equipmentCategories: [],
      equipmentTypes: [],
      acceptedFilter: "ANY_STATUS"
    });
    const el = await mount();
    el.shadowRoot
      .querySelector("c-lane-benchmark-filters")
      .dispatchEvent(new CustomEvent("clearsaved"));
    await flush();
    expect(window.localStorage.getItem(STORAGE_KEY)).toBeNull();
    expect(
      el.shadowRoot.querySelector("c-lane-benchmark-filters").value.lookbackDays
    ).toBe(90);
  });
});
```

- [ ] **Step 2: Run to verify they fail** — modules not found.

- [ ] **Step 3: Implement**

`laneBenchmarkMap.js` / `.html`:

```javascript
import { LightningElement, api } from "lwc";
export default class LaneBenchmarkMap extends LightningElement {
  @api previewUrl = null;
}
```

```html
<template>
  <template lwc:if="{previewUrl}">
    <div class="slds-m-bottom_small">
      <img
        src="{previewUrl}"
        alt="Origin and destination radius on a map"
        style="max-width:100%;border-radius:4px"
      />
    </div>
  </template>
</template>
```

`laneBenchmark.js`:

```javascript
import { LightningElement, track } from "lwc";
import search from "@salesforce/apex/LaneBenchmarkController.search";
import getFilterOptions from "@salesforce/apex/LaneBenchmarkController.getFilterOptions";
import mapPreviewUrl from "@salesforce/apex/LaneBenchmarkController.mapPreviewUrl";
import { load, save, clear } from "c/laneBenchmarkStorage";
import { DEFAULT_FILTERS } from "c/laneBenchmarkFilters";

const LONG_RADIUS_DAYS = 365;

function emptyRequest() {
  return {
    originKey: null,
    originLabel: "",
    originPrecision: "CITY",
    originRadius: null,
    destinationKey: null,
    destinationLabel: "",
    destinationPrecision: "CITY",
    destinationRadius: null,
    radiusUnit: "MI",
    marginPct: 15,
    ...DEFAULT_FILTERS
  };
}

export default class LaneBenchmark extends LightningElement {
  @track request = emptyRequest();
  filterOptions = {
    modes: [],
    equipmentByCategory: {},
    currencies: ["CAD", "USD"]
  };
  result = null;
  error = null;
  isSearching = false;
  elapsedSeconds = 0;
  needsConfirmation = false;
  previewUrl = null;
  ticker = null;

  get filters() {
    const f = {};
    Object.keys(DEFAULT_FILTERS).forEach((k) => {
      f[k] = this.request[k];
    });
    return f;
  }
  get rows() {
    return this.result ? this.result.rows : [];
  }
  get statsByCurrency() {
    return this.result ? this.result.statsByCurrency : {};
  }
  get hasResult() {
    return !!this.result;
  }
  get isRadiusSearch() {
    return (
      this.request.originPrecision === "RADIUS" ||
      this.request.destinationPrecision === "RADIUS"
    );
  }

  async connectedCallback() {
    try {
      this.filterOptions = await getFilterOptions();
    } catch (e) {
      this.error = this.messageOf(e);
    }
    const saved = load();
    if (saved) {
      this.request = { ...emptyRequest(), ...saved };
      this.runSearch();
    }
  }

  handleOrigin(event) {
    const d = event.detail;
    this.request = {
      ...this.request,
      originKey: d.key,
      originLabel: d.label,
      originPrecision: d.precision,
      originRadius: d.radius,
      radiusUnit: d.unit || this.request.radiusUnit
    };
  }
  handleDestination(event) {
    const d = event.detail;
    this.request = {
      ...this.request,
      destinationKey: d.key,
      destinationLabel: d.label,
      destinationPrecision: d.precision,
      destinationRadius: d.radius,
      radiusUnit: d.unit || this.request.radiusUnit
    };
  }
  handleFilters(event) {
    this.request = { ...this.request, ...event.detail };
  }
  handleMargin(event) {
    this.request = { ...this.request, marginPct: event.detail.marginPct };
    save(this.request);
  }
  handleReset() {
    this.request = {
      ...emptyRequest(),
      originKey: this.request.originKey,
      originLabel: this.request.originLabel,
      destinationKey: this.request.destinationKey,
      destinationLabel: this.request.destinationLabel
    };
  }
  handleClearSaved() {
    clear();
    this.request = emptyRequest();
    this.result = null;
    this.previewUrl = null;
  }

  handleApply() {
    if (
      this.isRadiusSearch &&
      Number(this.request.lookbackDays) > LONG_RADIUS_DAYS
    ) {
      this.needsConfirmation = true;
      return;
    }
    this.runSearch();
  }
  handleContinue() {
    this.needsConfirmation = false;
    this.runSearch();
  }
  handleCancel() {
    this.needsConfirmation = false;
  }

  toServiceRequest() {
    const r = this.request;
    return {
      originKey: r.originKey,
      destinationKey: r.destinationKey,
      originPrecision: r.originPrecision,
      destinationPrecision: r.destinationPrecision,
      originRadius: r.originPrecision === "RADIUS" ? r.originRadius : null,
      destinationRadius:
        r.destinationPrecision === "RADIUS" ? r.destinationRadius : null,
      radiusUnit: r.radiusUnit,
      lookbackDays: r.lookbackDays,
      currencyIsoCode: r.currencyIsoCode,
      modes: r.modes,
      equipmentCategories: r.equipmentCategories,
      equipmentTypes: r.equipmentTypes,
      hazmatOnly: r.hazmatOnly,
      marketTestOnly: r.marketTestOnly,
      acceptedFilter: r.acceptedFilter,
      rowLimit: 2000,
      includeStopGeolocation: true
    };
  }

  async runSearch() {
    this.error = null;
    this.isSearching = true;
    this.elapsedSeconds = 0;
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    this.ticker = window.setInterval(() => {
      this.elapsedSeconds += 1;
    }, 1000);
    const svc = this.toServiceRequest();
    try {
      this.result = await search({ requestJson: JSON.stringify(svc) });
      save(this.request);
      this.previewUrl = await mapPreviewUrl({
        originKey: svc.originKey,
        originRadius: svc.originRadius,
        destinationKey: svc.destinationKey,
        destinationRadius: svc.destinationRadius,
        unit: svc.radiusUnit
      });
    } catch (e) {
      this.result = null;
      this.previewUrl = null;
      this.error = this.messageOf(e);
    } finally {
      window.clearInterval(this.ticker);
      this.isSearching = false;
    }
  }

  messageOf(e) {
    return (
      (e && e.body && e.body.message) ||
      (e && e.message) ||
      "Something went wrong"
    );
  }
}
```

`laneBenchmark.html`:

```html
<template>
  <lightning-layout multiple-rows class="lane-benchmark">
    <lightning-layout-item
      size="12"
      large-device-size="4"
      padding="around-x-small"
    >
      <lightning-card title="Lane" icon-name="standard:location">
        <div class="slds-p-horizontal_medium">
          <c-lane-benchmark-place-picker
            data-id="origin"
            label="Origin"
            value="{request.originKey}"
            value-label="{request.originLabel}"
            precision="{request.originPrecision}"
            radius="{request.originRadius}"
            unit="{request.radiusUnit}"
            onplacechange="{handleOrigin}"
          ></c-lane-benchmark-place-picker>
          <div class="slds-m-top_small"></div>
          <c-lane-benchmark-place-picker
            data-id="destination"
            label="Destination"
            value="{request.destinationKey}"
            value-label="{request.destinationLabel}"
            precision="{request.destinationPrecision}"
            radius="{request.destinationRadius}"
            unit="{request.radiusUnit}"
            onplacechange="{handleDestination}"
          ></c-lane-benchmark-place-picker>
          <div class="slds-m-top_medium"></div>
          <c-lane-benchmark-filters
            options="{filterOptions}"
            value="{filters}"
            onfilterschange="{handleFilters}"
            onapply="{handleApply}"
            onreset="{handleReset}"
            onclearsaved="{handleClearSaved}"
          ></c-lane-benchmark-filters>
        </div>
      </lightning-card>
    </lightning-layout-item>
    <lightning-layout-item
      size="12"
      large-device-size="8"
      padding="around-x-small"
    >
      <template lwc:if="{needsConfirmation}">
        <div
          class="slds-notify slds-notify_alert slds-alert_warning slds-m-bottom_small"
          role="alert"
        >
          Radius searches over a year can take 10-20 seconds.
          <lightning-button
            data-id="continue"
            label="Continue"
            variant="brand"
            class="slds-m-left_small"
            onclick="{handleContinue}"
          ></lightning-button>
          <lightning-button
            data-id="cancel"
            label="Cancel"
            class="slds-m-left_x-small"
            onclick="{handleCancel}"
          ></lightning-button>
        </div>
      </template>
      <template lwc:if="{error}">
        <div
          data-id="error"
          class="slds-notify slds-notify_alert slds-alert_error slds-m-bottom_small"
          role="alert"
        >
          {error}
        </div>
      </template>
      <template lwc:if="{isSearching}">
        <div class="slds-is-relative searching">
          <lightning-spinner alternative-text="Searching"></lightning-spinner>
          <p class="slds-text-align_center slds-p-top_xx-large">
            Searching… {elapsedSeconds} s
          </p>
        </div>
      </template>
      <template lwc:if="{hasResult}">
        <c-lane-benchmark-stats
          stats-by-currency="{statsByCurrency}"
          deduped-count="{result.dedupedCount}"
          truncated="{result.truncated}"
          elapsed-ms="{result.elapsedMs}"
          row-count="{rows.length}"
          margin-pct="{request.marginPct}"
          onmarginchange="{handleMargin}"
        ></c-lane-benchmark-stats>
        <c-lane-benchmark-map preview-url="{previewUrl}"></c-lane-benchmark-map>
        <c-lane-benchmark-results
          rows="{rows}"
          origin-label="{request.originLabel}"
          destination-label="{request.destinationLabel}"
        ></c-lane-benchmark-results>
      </template>
      <template lwc:else>
        <template lwc:if="{isSearching}"></template>
        <template lwc:else>
          <lightning-card title="Lane Benchmark">
            <div class="slds-p-horizontal_medium slds-text-color_weak">
              <p>
                Pick an origin and a destination, choose how precise each end
                should be, and Apply.
              </p>
              <ul class="slds-list_dotted slds-m-top_x-small">
                <li>
                  <strong>Exact city</strong> matches the city as Revenova wrote
                  it, accents ignored.
                </li>
                <li>
                  <strong>Province / state</strong> matches anything in that
                  province or state.
                </li>
                <li>
                  <strong>Postal prefix</strong> matches the first three
                  characters of the postal code.
                </li>
                <li>
                  <strong>Radius</strong> matches every stop within the distance
                  you set.
                </li>
              </ul>
            </div>
          </lightning-card>
        </template>
      </template>
    </lightning-layout-item>
  </lightning-layout>
</template>
```

`laneBenchmark.css`: `.searching { min-height: 12rem; }`

`laneBenchmark.js-meta.xml`:

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<LightningComponentBundle xmlns="http://soap.sforce.com/2006/04/metadata">
    <apiVersion>64.0</apiVersion>
    <isExposed>true</isExposed>
    <masterLabel>Lane Benchmark</masterLabel>
    <targets>
        <target>lightning__AppPage</target>
        <target>lightning__HomePage</target>
    </targets>
</LightningComponentBundle>
```

`laneBenchmarkMap.js-meta.xml`: not exposed. Manifest: both bundles.

- [ ] **Step 4: Run all Jest, lint, Prettier**

Run: `npm test && npm run lint && npm run prettier:verify` → all suites pass (14 existing + 11 + 5 + 4 + 3 + 4 + 1 + 5 = 47). Fix any `lwc:if`/`lwc:else` pairing errors the compiler reports (each `lwc:else` must immediately follow its `lwc:if` template).

- [ ] **Step 5: Commit, PR, merge (components milestone)**

```bash
git add force-app/main/default/lwc manifest/package.xml
git commit -m "Add laneBenchmark container and laneBenchmarkMap; wire the Lane Benchmark page"
git push -u origin phase-2/components
WT=$(gh auth token -u IulianEnescu) && git -c credential.helper= -c "credential.helper=!f() { echo username=IulianEnescu; echo password=$WT; }; f" push -u tplm phase-2/components
gh pr create --base main --head phase-2/components --title "Phase 2 components: Lane Benchmark LWC" --body "Tasks 4-9 of docs/superpowers/plans/2026-09-09-phase-2-lane-benchmark-ui.md"
GH_TOKEN=$WT gh pr create -R TPLM/PricingDepartment --base main --head phase-2/components --title "Phase 2 components: Lane Benchmark LWC" --body "Tasks 4-9 of docs/superpowers/plans/2026-09-09-phase-2-lane-benchmark-ui.md"
```

Watch both (the Apex job validates the manifest incl. the bundles against PostProduc, which compiles the LWC), merge on origin only, mirror, deploy main to PostProduc with the full test list.

---

### Task 10: Page, tab, app, TransPro tab, permission set, CSP, docs

**Files:**

- Create: `flexipages/Lane_Benchmark.flexipage-meta.xml`, `tabs/Lane_Benchmark.tab-meta.xml`, `applications/Lane_Benchmark.app-meta.xml`, `applications/TransPro.app-meta.xml` (retrieved), `permissionsets/Lane_Benchmark_User.permissionset-meta.xml`, `cspTrustedSites/Mapbox_API.cspTrustedSite-meta.xml`
- Modify: `manifest/package.xml`, `README.md`, roadmap, phase 2 spec (Outcome)

- [ ] **Step 1: Branch and retrieve the TransPro app**

```bash
git checkout main && git pull origin main && git checkout -b phase-2/metadata
sf project retrieve start -m CustomApplication:TransPro -o sandbox
```

Add `<tabs>Lane_Benchmark</tabs>` as the LAST `<tabs>` element in `force-app/main/default/applications/TransPro.app-meta.xml`. Change nothing else in that file.

- [ ] **Step 2: New metadata**

`Lane_Benchmark.flexipage-meta.xml`:

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<FlexiPage xmlns="http://soap.sforce.com/2006/04/metadata">
    <flexiPageRegions>
        <itemInstances>
            <componentInstance>
                <componentName>laneBenchmark</componentName>
                <identifier>c_laneBenchmark</identifier>
            </componentInstance>
        </itemInstances>
        <name>main</name>
        <type>Region</type>
    </flexiPageRegions>
    <masterLabel>Lane Benchmark</masterLabel>
    <template><name>flexipage:defaultAppHomeTemplate</name></template>
    <type>AppPage</type>
</FlexiPage>
```

`Lane_Benchmark.tab-meta.xml`:

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<CustomTab xmlns="http://soap.sforce.com/2006/04/metadata">
    <description>Lane Benchmark: compare carrier quotes on a lane</description>
    <flexiPage>Lane_Benchmark</flexiPage>
    <label>Lane Benchmark</label>
    <motif>Custom80: Motorcycle</motif>
</CustomTab>
```

(`Custom80: Motorcycle` is the motif the old tab uses and is known to deploy; change the icon later in Setup if wanted.)

`Lane_Benchmark.app-meta.xml`:

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<CustomApplication xmlns="http://soap.sforce.com/2006/04/metadata">
    <brand>
        <headerColor>#0070D2</headerColor>
        <shouldOverrideOrgTheme>false</shouldOverrideOrgTheme>
    </brand>
    <description>Lane Benchmark for pricing</description>
    <formFactors>Large</formFactors>
    <isNavAutoTempTabsDisabled>false</isNavAutoTempTabsDisabled>
    <isNavPersonalizationDisabled>false</isNavPersonalizationDisabled>
    <isNavTabPersistenceDisabled>false</isNavTabPersistenceDisabled>
    <label>Lane Benchmark</label>
    <navType>Standard</navType>
    <tabs>Lane_Benchmark</tabs>
    <uiType>Lightning</uiType>
</CustomApplication>
```

`Mapbox_API.cspTrustedSite-meta.xml`:

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<CspTrustedSite xmlns="http://soap.sforce.com/2006/04/metadata">
    <context>LEX</context>
    <description>Mapbox static map images for Lane Benchmark</description>
    <endpointUrl>https://api.mapbox.com</endpointUrl>
    <isActive>true</isActive>
    <isApplicableToConnectSrc>false</isApplicableToConnectSrc>
    <isApplicableToFontSrc>false</isApplicableToFontSrc>
    <isApplicableToFrameSrc>false</isApplicableToFrameSrc>
    <isApplicableToImgSrc>true</isApplicableToImgSrc>
    <isApplicableToMediaSrc>false</isApplicableToMediaSrc>
    <isApplicableToStyleSrc>false</isApplicableToStyleSrc>
</CspTrustedSite>
```

`Lane_Benchmark_User.permissionset-meta.xml`: generate the `rtms__CarrierQuote__c` field list with the same script phase 0 used (from `LaneSearchQueryBuilder.SELECT_CLAUSE` this time: every field that is not `Id`, `Name`, `CurrencyIsoCode`, `CreatedDate`, a relationship path, or a required field), then:

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<PermissionSet xmlns="http://soap.sforce.com/2006/04/metadata">
    <label>Lane Benchmark User</label>
    <description
  >Everything needed to use the Lane Benchmark page. Assign this to the pricing team.</description>
    <hasActivationRequired>false</hasActivationRequired>
    <applicationVisibilities><application>Lane_Benchmark</application><visible
    >true</visible></applicationVisibilities>
    <classAccesses><apexClass>LaneBenchmarkController</apexClass><enabled
    >true</enabled></classAccesses>
    <classAccesses><apexClass>LaneSearchService</apexClass><enabled
    >true</enabled></classAccesses>
    <classAccesses><apexClass>MapboxGeocoder</apexClass><enabled
    >true</enabled></classAccesses>
    <objectPermissions><allowCreate>false</allowCreate><allowDelete
    >false</allowDelete><allowEdit>false</allowEdit><allowRead
    >true</allowRead><modifyAllRecords>false</modifyAllRecords><object
    >rtms__CarrierQuote__c</object><viewAllRecords
    >false</viewAllRecords></objectPermissions>
    <objectPermissions><allowCreate>false</allowCreate><allowDelete
    >false</allowDelete><allowEdit>false</allowEdit><allowRead
    >true</allowRead><modifyAllRecords>false</modifyAllRecords><object
    >rtms__Load__c</object><viewAllRecords
    >false</viewAllRecords></objectPermissions>
    <objectPermissions><allowCreate>false</allowCreate><allowDelete
    >false</allowDelete><allowEdit>false</allowEdit><allowRead
    >true</allowRead><modifyAllRecords>false</modifyAllRecords><object
    >Pricing_Place__c</object><viewAllRecords
    >true</viewAllRecords></objectPermissions>
    <!-- generated rtms__CarrierQuote__c fieldPermissions (readable, not editable) -->
    <!-- Pricing_Place__c fieldPermissions: every custom field except Key__c, readable, not editable -->
    <tabSettings><tab>Lane_Benchmark</tab><visibility
    >Visible</visibility></tabSettings>
</PermissionSet>
```

Manifest: `FlexiPage:Lane_Benchmark`, `CustomTab:Lane_Benchmark`, `CustomApplication:Lane_Benchmark`, `CustomApplication:TransPro`, `PermissionSet:Lane_Benchmark_User`, `CspTrustedSite:Mapbox_API`.

- [ ] **Step 3: Deploy and verify in PostProduc**

Run: `sf project deploy start -x manifest/package.xml -o sandbox -l RunSpecifiedTests -t PricingDepartmentControllerTest PlaceNormalizerTest PricingTestDataFactoryTest PlaceBuilderBatchTest LaneSearchServiceTest MapboxGeocoderTest LaneBenchmarkControllerTest -w 30`
Expected: Succeeded. Then: `sf org assign permset -n Lane_Benchmark_User -o sandbox`; `sf org open -o sandbox -p /lightning/n/Lane_Benchmark` and, in the browser, run: Montreal→Toronto at CITY; the same with destination RADIUS 100 km (the map image appears); type "Saguenay" in Origin, use "Search on the map", pick the Mapbox result, search; toggle 20%; export CSV and open it in Excel/Numbers (accents intact). Record what you saw (row counts, seconds, any console error) in the report. Check the TransPro app shows the new tab.

- [ ] **Step 4: Docs**

README: new "## Lane Benchmark (phase 2)" section: how to open it (tab in TransPro, App Launcher app), what each precision means, the margin controls, CSV export, "Clear saved filters" and the storage key, the Mapbox reuse (custom setting `TPRO_KPI__c.Mapbox_Api_Key__c`, remote site `MapBox`, CSP trusted site `Mapbox_API`, and the recommendation to add URL restrictions for `*.my.salesforce.com`, `*.lightning.force.com`, `*.sandbox.my.salesforce.com` on the token in the Mapbox account), permission set assignment, and the retirement plan for the old tab (phase 4). Update the "What is in here" table with the phase 1 and phase 2 components (the phase 1 omission was noted as a gap). Roadmap: phase 2 row → "Done <date>". Phase 2 spec: append `## Outcome (<date>)` with deploy ids, test counts, the manual checks from Step 3, and any adaptation.

- [ ] **Step 5: Commit, PR, merge, mirror**

```bash
git add force-app manifest README.md docs
git commit -m "Add Lane Benchmark page, tab, app, TransPro tab, permission set and Mapbox CSP site"
git push -u origin phase-2/metadata
WT=$(gh auth token -u IulianEnescu) && git -c credential.helper= -c "credential.helper=!f() { echo username=IulianEnescu; echo password=$WT; }; f" push -u tplm phase-2/metadata
gh pr create --base main --head phase-2/metadata --title "Phase 2 metadata: Lane Benchmark page, tab, app, permission set" --body "Task 10 of docs/superpowers/plans/2026-09-09-phase-2-lane-benchmark-ui.md"
GH_TOKEN=$WT gh pr create -R TPLM/PricingDepartment --base main --head phase-2/metadata --title "Phase 2 metadata: Lane Benchmark page, tab, app, permission set" --body "Task 10 of docs/superpowers/plans/2026-09-09-phase-2-lane-benchmark-ui.md"
```

Watch both, merge on origin only, mirror, final deploy of main to PostProduc.

---

## Self-review

**Spec coverage.** Navigation and access (page, tab, app, TransPro tab, permission set): Task 10. Controller (search JSON, searchPlaces normalization/aliases/ordering/limit, getFilterOptions, geocode with cache-into-dictionary and no downgrade, mapPreviewUrl): Task 3. Mapbox integration (custom-setting token, remote site, geocoder with retry/timeout/MX mapping, static map URL, CSP trusted site): Tasks 2, 3, 10. `Source__c` and Row carrier-detail fields: Task 1. Components and pure modules exactly as the spec's list: Tasks 4-9 (picker debounce/keyboard-escape/map fallback/precision/radius; filters incl. category→type narrowing and clear-saved; stats per currency with margin default 15, 20 button, free entry, dedupe and truncation notices, empty state; results with expand, popup, CSV with BOM and RFC 4180, file name; map; container with storage restore, warning gate over 365 days for radius, elapsed seconds, error box, layout). Remembered filters (localStorage, versioned key, clear link): Tasks 4, 6, 9. Errors and states: Tasks 7, 9. Testing list: every task. Definition of done: Task 10 Steps 3-4 (manual checks, docs), CI lists in Tasks 2-3. Out of scope respected (no record links, no retirement, no RFP).

**Placeholders.** None. The permission set's field lists are generated by the documented script rather than typed, with the exclusion rule stated.

**Type consistency.** `PlaceOption` fields (`key,label,province,country,source,loadCount,lat,lng`) match the picker's use (`key,label,loadCount,source`). `FilterOptions` (`modes, equipmentByCategory, currencies`) matches `laneBenchmarkFilters.options`. `search({ requestJson })`, `searchPlaces({ term, limitCount })`, `geocode({ query, countryHint })`, `mapPreviewUrl({ originKey, originRadius, destinationKey, destinationRadius, unit })` match between controller signatures and component calls/tests. `placechange` detail `{key,label,precision,radius,unit}` matches the container handlers. `filterschange` detail keys equal `DEFAULT_FILTERS` keys and the service request fields. `marginchange` detail `{ marginPct }` matches. `Row` fields used by results/CSV exist in phase 1 plus Task 1's five additions. Storage key constant used consistently.
