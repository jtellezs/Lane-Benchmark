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
  }
  private static final List<String> COUNTRY_ORDER = new List<String>{
    'CA',
    'US',
    'MX'
  };
  private static final Integer MAX_ROWS = 200;

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
    List<SObject> clean = Security.stripInaccessible(
        AccessType.CREATABLE,
        lanes
      )
      .getRecords();
    Database.insert(clean, AccessLevel.USER_MODE);
    s.imported = clean.size();
    return s;
  }

  private static Boolean isEmpty(RowEnd e) {
    return e == null || (String.isBlank(e.city) && String.isBlank(e.postal));
  }

  private static RFP_Lane__c toLane(RFP_Project__c project, ImportRow r) {
    return new RFP_Lane__c(
      RFP_Project__c = project.Id,
      Row_Number__c = r.rowNumber,
      Raw_Row__c = r.raw,
      Mode__c = r.mode,
      Equipment_Category__c = r.equipmentCategory,
      Equipment_Type__c = r.equipmentType,
      Commodity__c = r.commodity,
      Quantity__c = r.quantity,
      Quantity_Unit__c = r.quantityUnit,
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
    String city = place != null ? place.City__c : trimmed(e?.city);
    String province = place != null
      ? place.Province__c
      : PlaceNormalizer.provinceCode(trimmed(e?.province));
    String country = place != null
      ? place.Country__c
      : PlaceNormalizer.countryCode(trimmed(e?.country));
    String postal = place != null && String.isBlank(e?.postal)
      ? place.Postal_Prefix__c
      : trimmed(e?.postal);
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

  private static String trimmed(String s) {
    return s == null ? null : s.trim().left(80);
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
