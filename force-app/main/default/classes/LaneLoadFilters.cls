/**
 * The mode, equipment and hazmat conditions a lane request puts on a load. Pure: no SOQL, no DML.
 * Phase 8 moved them out of LaneSearchFilters (its addModeFilter, addEquipmentFilter and
 * addHazmatFilter) so the Carriers to ask and Split-lane services filter a quote's load, a split's
 * customer load and an estimate's leg load exactly as the lane search filters a quote's load (spec
 * R101); LaneSearchQueryBuilderTest proves the search's SOQL did not change.
 *
 * loadPath is the relationship path from the queried row to its load: 'rtms__Load__r.' on
 * rtms__CarrierQuote__c and rtms__FreightPlanLoad__c rows, '' on rtms__Load__c rows. The bind names
 * (modes, cats, types) are the same whatever the path. Currency and accepted
 * exclusion stay in LaneSearchFilters: they read quote fields, not load fields.
 */
public with sharing class LaneLoadFilters {
  public static void add(
    LaneSearchRequest req,
    String loadPath,
    List<String> conditions,
    Map<String, Object> binds
  ) {
    addMode(req, loadPath, conditions, binds);
    addEquipment(req, loadPath, conditions, binds);
    addHazmat(req, loadPath, conditions);
  }

  private static void addMode(
    LaneSearchRequest req,
    String loadPath,
    List<String> conditions,
    Map<String, Object> binds
  ) {
    if (req.modes != null && !req.modes.isEmpty()) {
      binds.put('modes', req.modes);
      conditions.add(loadPath + 'rtms__Mode__r.Name IN :modes');
    }
  }

  private static void addEquipment(
    LaneSearchRequest req,
    String loadPath,
    List<String> conditions,
    Map<String, Object> binds
  ) {
    Boolean hasCats =
      req.equipmentCategories != null && !req.equipmentCategories.isEmpty();
    Boolean hasTypes =
      req.equipmentTypes != null && !req.equipmentTypes.isEmpty();
    String byCategory =
      loadPath + 'rtms__Equipment_Type__r.rtms__Category__c IN :cats';
    String byType = loadPath + 'rtms__Equipment_Type__r.Name IN :types';
    if (hasCats && hasTypes) {
      binds.put('cats', req.equipmentCategories);
      binds.put('types', req.equipmentTypes);
      conditions.add('(' + byCategory + ' OR ' + byType + ')');
    } else if (hasCats) {
      binds.put('cats', req.equipmentCategories);
      conditions.add(byCategory);
    } else if (hasTypes) {
      binds.put('types', req.equipmentTypes);
      conditions.add(byType);
    }
  }

  private static void addHazmat(
    LaneSearchRequest req,
    String loadPath,
    List<String> conditions
  ) {
    if (req.hazmatOnly == true) {
      conditions.add(loadPath + 'rtms__Hazardous_Materials__c = true');
    }
  }
}
