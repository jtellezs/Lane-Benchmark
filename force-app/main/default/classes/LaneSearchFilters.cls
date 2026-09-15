/**
 * Task 7's currency/mode/equipment/hazmat/accepted filters, plus the Market Test exclusion. Pure: no SOQL, no DML -
 * just condition/bind assembly from a LaneSearchRequest, appended to the conditions/binds
 * LaneSearchQueryBuilder.buildSoql() is assembling. Split out of LaneSearchQueryBuilder per the
 * Task 7 review ruling ("split the filters out"): LaneSearchQueryBuilder alone (lane-precision
 * logic plus these filters in one class) totaled cyclomatic complexity 44 against PMD's 40
 * threshold even though no individual method was over its own per-method threshold; moving this
 * filter family into its own class-wide total resolves it without any suppression.
 */
public with sharing class LaneSearchFilters {
  // addFilters itself stays a small dispatcher; one helper per filter so no single method carries
  // every branch.
  public static void addFilters(
    LaneSearchRequest req,
    List<String> conditions,
    Map<String, Object> binds
  ) {
    addCurrencyFilter(req, conditions, binds);
    addModeFilter(req, conditions, binds);
    addEquipmentFilter(req, conditions, binds);
    addHazmatFilter(req, conditions);
    addMarketTestExclusion(conditions, binds);
    addAcceptedFilter(req, conditions);
  }

  private static void addCurrencyFilter(
    LaneSearchRequest req,
    List<String> conditions,
    Map<String, Object> binds
  ) {
    if (String.isNotBlank(req.currencyIsoCode)) {
      binds.put('currencyCode', req.currencyIsoCode);
      conditions.add('CurrencyIsoCode = :currencyCode');
    }
  }

  private static void addModeFilter(
    LaneSearchRequest req,
    List<String> conditions,
    Map<String, Object> binds
  ) {
    if (req.modes != null && !req.modes.isEmpty()) {
      binds.put('modes', req.modes);
      conditions.add('rtms__Load__r.rtms__Mode__r.Name IN :modes');
    }
  }

  private static void addEquipmentFilter(
    LaneSearchRequest req,
    List<String> conditions,
    Map<String, Object> binds
  ) {
    Boolean hasCats =
      req.equipmentCategories != null && !req.equipmentCategories.isEmpty();
    Boolean hasTypes =
      req.equipmentTypes != null && !req.equipmentTypes.isEmpty();
    if (hasCats && hasTypes) {
      binds.put('cats', req.equipmentCategories);
      binds.put('types', req.equipmentTypes);
      conditions.add(
        '(rtms__Load__r.rtms__Equipment_Type__r.rtms__Category__c IN :cats OR rtms__Load__r.rtms__Equipment_Type__r.Name IN :types)'
      );
    } else if (hasCats) {
      binds.put('cats', req.equipmentCategories);
      conditions.add(
        'rtms__Load__r.rtms__Equipment_Type__r.rtms__Category__c IN :cats'
      );
    } else if (hasTypes) {
      binds.put('types', req.equipmentTypes);
      conditions.add('rtms__Load__r.rtms__Equipment_Type__r.Name IN :types');
    }
  }

  private static void addHazmatFilter(
    LaneSearchRequest req,
    List<String> conditions
  ) {
    if (req.hazmatOnly == true) {
      conditions.add('rtms__Load__r.rtms__Hazardous_Materials__c = true');
    }
  }

  /**
   * Quotes whose customer is a Market Test account are left out of every lane search (owner,
   * 2026-09-15): pricing reads carrier bids instead. A customer name is always set on quotes, so
   * NOT LIKE drops only the Market Test quotes (PostProduc, 90 days: 10,642 = 218 + 10,424).
   */
  private static void addMarketTestExclusion(
    List<String> conditions,
    Map<String, Object> binds
  ) {
    binds.put('marketTest', '%Market Test%');
    conditions.add('(NOT Customer_Name__c LIKE :marketTest)');
  }

  private static void addAcceptedFilter(
    LaneSearchRequest req,
    List<String> conditions
  ) {
    if (req.acceptedFilter == LaneSearchRequest.Accepted.ACCEPTED) {
      conditions.add('rtms__Accepted__c = true');
    } else if (req.acceptedFilter == LaneSearchRequest.Accepted.DECLINED) {
      conditions.add('rtms__Accepted__c = false');
    }
  }
}
