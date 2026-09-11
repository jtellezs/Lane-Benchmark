/**
 * Turns mapped spreadsheet rows into RFP_Lane__c records (user mode). Each end is resolved to a
 * Pricing_Place__c by city|province|country key first (trying CA, US, MX when the row has no
 * country), then by postal prefix (busiest place wins). Ends that resolve nowhere are flagged so
 * the workbench can ask for a manual pick.
 */
public with sharing class RfpImportService {
  public class RowEnd {
    public String city;
    public String province;
    public String country;
    public String postal;
  }
  public class ImportRow {
    public Integer rowNumber;
    public RowEnd origin;
    public RowEnd destination;
    public String mode;
    public String equipmentCategory;
    public String equipmentType;
    public String commodity;
    public Decimal quantity;
    public String quantityUnit;
    public Integer shipmentsPerYear;
    public Decimal fuelSurcharge;
    public Boolean fscIncluded;
    public Boolean hazmat;
    public String raw;
  }
  public class Summary {
    @AuraEnabled
    public Integer imported = 0;
    @AuraEnabled
    public Integer skipped = 0;
    @AuraEnabled
    public Integer unresolvedEnds = 0;
    /** Rows the insert refused one by one (allOrNone = false); the rest still land. */
    @AuraEnabled
    public Integer failed = 0;
  }
  private static final List<String> COUNTRY_ORDER = new List<String>{
    'CA',
    'US',
    'MX'
  };
  private static final Integer MAX_ROWS = 200;
  // Spreadsheet cells are arbitrarily long; every free-text field is cut to its own schema
  // length before the insert, so one 60-character "mode" cannot STRING_TOO_LONG the whole chunk.
  private static final Integer MODE_MAX = 40;
  private static final Integer EQUIPMENT_CATEGORY_MAX = 40;
  private static final Integer EQUIPMENT_TYPE_MAX = 80;
  private static final Integer COMMODITY_MAX = 255;
  private static final Integer QUANTITY_UNIT_MAX = 20;
  private static final Integer RAW_ROW_MAX = 32768;
  private static final Integer POSTAL_MAX = 12;
  private static final Integer CITY_MAX = 80;

  public static Summary importRows(Id projectId, List<ImportRow> rows) {
    if (rows.size() > MAX_ROWS) {
      throw new LaneSearchException(
        'Import at most ' + MAX_ROWS + ' rows per call.'
      );
    }
    RFP_Project__c project = [
      SELECT Id, Default_Margin__c, CurrencyIsoCode
      FROM RFP_Project__c
      WHERE Id = :projectId
      WITH USER_MODE
    ];
    Summary s = new Summary();
    Resolver resolver = new Resolver(rows);
    List<RFP_Lane__c> lanes = new List<RFP_Lane__c>();
    for (ImportRow r : rows) {
      if (isEmpty(r.origin) && isEmpty(r.destination)) {
        s.skipped++;
        continue;
      }
      RFP_Lane__c lane = toLane(project, r);
      s.unresolvedEnds += applyEnd(lane, r.origin, resolver, true);
      s.unresolvedEnds += applyEnd(lane, r.destination, resolver, false);
      lane.Hist_Status__c = lane.Origin_Resolved__c &&
        lane.Destination_Resolved__c
        ? 'Pending'
        : 'Unresolved';
      lanes.add(lane);
    }
    save(s, lanes);
    return s;
  }

  /**
   * allOrNone = false: a row the platform still refuses (a number outside its field's range, a
   * validation rule, ...) lands in its own SaveResult and is counted into Summary.failed, instead
   * of a single bad cell aborting the statement and discarding all 200 rows of the chunk. The
   * caller shows "failed N" next to "imported N"; the rows that saved keep their lanes.
   */
  private static void save(Summary s, List<RFP_Lane__c> lanes) {
    List<SObject> clean = Security.stripInaccessible(
        AccessType.CREATABLE,
        lanes
      )
      .getRecords();
    for (
      Database.SaveResult sr : Database.insert(
        clean,
        false,
        AccessLevel.USER_MODE
      )
    ) {
      if (sr.isSuccess()) {
        s.imported++;
      } else {
        s.failed++;
      }
    }
  }

  private static Boolean isEmpty(RowEnd e) {
    return e == null || (String.isBlank(e.city) && String.isBlank(e.postal));
  }

  private static RFP_Lane__c toLane(RFP_Project__c project, ImportRow r) {
    return new RFP_Lane__c(
      RFP_Project__c = project.Id,
      Row_Number__c = r.rowNumber,
      Raw_Row__c = trimmed(r.raw, RAW_ROW_MAX),
      Mode__c = trimmed(r.mode, MODE_MAX),
      Equipment_Category__c = trimmed(
        r.equipmentCategory,
        EQUIPMENT_CATEGORY_MAX
      ),
      Equipment_Type__c = trimmed(r.equipmentType, EQUIPMENT_TYPE_MAX),
      Commodity__c = trimmed(r.commodity, COMMODITY_MAX),
      Quantity__c = r.quantity,
      Quantity_Unit__c = trimmed(r.quantityUnit, QUANTITY_UNIT_MAX),
      Shipments_Per_Year__c = r.shipmentsPerYear,
      Customer_Fuel_Surcharge__c = r.fuelSurcharge,
      Customer_FSC_Included__c = r.fscIncluded == true,
      Hazmat__c = r.hazmat == true,
      Margin__c = project.Default_Margin__c,
      CurrencyIsoCode = project.CurrencyIsoCode
    );
  }

  /** Returns 1 when the end stays unresolved, else 0. */
  private static Integer applyEnd(
    RFP_Lane__c lane,
    RowEnd e,
    Resolver resolver,
    Boolean isOrigin
  ) {
    Pricing_Place__c place = resolver.resolve(e);
    String city = place != null ? place.City__c : trimmed(e?.city, CITY_MAX);
    String province = place != null
      ? place.Province__c
      : PlaceNormalizer.provinceCode(trimmed(e?.province, CITY_MAX));
    String country = place != null
      ? place.Country__c
      : PlaceNormalizer.countryCode(trimmed(e?.country, CITY_MAX));
    String postal = place != null && String.isBlank(e?.postal)
      ? place.Postal_Prefix__c
      : trimmed(e?.postal, POSTAL_MAX);
    if (isOrigin) {
      lane.Origin_City__c = city;
      lane.Origin_Province__c = province;
      lane.Origin_Country__c = country;
      lane.Origin_Postal__c = postal;
      lane.Origin_Place__c = place?.Id;
      lane.Origin_Resolved__c = place != null;
    } else {
      lane.Destination_City__c = city;
      lane.Destination_Province__c = province;
      lane.Destination_Country__c = country;
      lane.Destination_Postal__c = postal;
      lane.Destination_Place__c = place?.Id;
      lane.Destination_Resolved__c = place != null;
    }
    return place == null ? 1 : 0;
  }

  /** Trimmed and cut to `cap`, the field's own schema length. */
  private static String trimmed(String s, Integer cap) {
    return s == null ? null : s.trim().left(cap);
  }

  /** Two bulk queries per import call: all candidate city keys, then all postal prefixes. */
  private with sharing class Resolver {
    private Map<String, Pricing_Place__c> byKey = new Map<String, Pricing_Place__c>();
    private Map<String, Pricing_Place__c> byPrefix = new Map<String, Pricing_Place__c>();

    Resolver(List<ImportRow> rows) {
      Set<String> keys = new Set<String>();
      Set<String> prefixes = new Set<String>();
      for (ImportRow r : rows) {
        collect(r.origin, keys, prefixes);
        collect(r.destination, keys, prefixes);
      }
      loadByKey(keys);
      loadByPrefix(prefixes);
    }

    private void loadByKey(Set<String> keys) {
      if (keys.isEmpty()) {
        return;
      }
      for (Pricing_Place__c p : [
        SELECT
          Id,
          Key__c,
          City__c,
          Province__c,
          Country__c,
          Postal_Prefix__c,
          Load_Count_365d__c
        FROM Pricing_Place__c
        WHERE Key__c IN :keys AND Active__c = TRUE
        WITH USER_MODE
      ]) {
        byKey.put(p.Key__c, p);
      }
    }

    private void loadByPrefix(Set<String> prefixes) {
      if (prefixes.isEmpty()) {
        return;
      }
      for (Pricing_Place__c p : [
        SELECT
          Id,
          Key__c,
          City__c,
          Province__c,
          Country__c,
          Postal_Prefix__c,
          Load_Count_365d__c
        FROM Pricing_Place__c
        WHERE Postal_Prefix__c IN :prefixes AND Active__c = TRUE
        WITH USER_MODE
        ORDER BY Load_Count_365d__c DESC NULLS LAST
      ]) {
        String k = p.Country__c + '|' + p.Postal_Prefix__c;
        if (!byPrefix.containsKey(k)) {
          byPrefix.put(k, p); // first = busiest, thanks to ORDER BY
        }
      }
    }

    private void collect(RowEnd e, Set<String> keys, Set<String> prefixes) {
      if (e == null) {
        return;
      }
      for (String k : candidateKeys(e)) {
        keys.add(k);
      }
      String prefix = prefixOf(e.postal);
      if (prefix != null) {
        prefixes.add(prefix);
      }
    }

    Pricing_Place__c resolve(RowEnd e) {
      if (e == null) {
        return null;
      }
      for (String k : candidateKeys(e)) {
        if (byKey.containsKey(k)) {
          return byKey.get(k);
        }
      }
      String prefix = prefixOf(e.postal);
      if (prefix == null) {
        return null;
      }
      String country = PlaceNormalizer.countryCode(e.country);
      List<String> countries = String.isBlank(country)
        ? COUNTRY_ORDER
        : new List<String>{ country };
      for (String c : countries) {
        if (byPrefix.containsKey(c + '|' + prefix)) {
          return byPrefix.get(c + '|' + prefix);
        }
      }
      return null;
    }
  }

  private static List<String> candidateKeys(RowEnd e) {
    List<String> out = new List<String>();
    if (e == null || String.isBlank(e.city)) {
      return out;
    }
    String country = PlaceNormalizer.countryCode(e.country);
    if (String.isNotBlank(country)) {
      out.add(PlaceNormalizer.key(e.city, e.province, country));
      return out;
    }
    for (String c : COUNTRY_ORDER) {
      out.add(PlaceNormalizer.key(e.city, e.province, c));
    }
    return out;
  }

  private static String prefixOf(String postal) {
    if (String.isBlank(postal)) {
      return null;
    }
    String p = postal.replace(' ', '').toUpperCase();
    return p.length() < 3 ? null : p.left(3);
  }
}
