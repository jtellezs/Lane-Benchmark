/**
 * Task 7's currency/mode/equipment/hazmat/accepted filters. Pure: no SOQL, no DML -
 * just condition/bind assembly from a LaneSearchRequest, appended to the conditions/binds
 * LaneSearchQueryBuilder.buildSoql() is assembling. Split out of LaneSearchQueryBuilder per the
 * Task 7 review ruling ("split the filters out"): LaneSearchQueryBuilder alone (lane-precision
 * logic plus these filters in one class) totaled cyclomatic complexity 44 against PMD's 40
 * threshold even though no individual method was over its own per-method threshold; moving this
 * filter family into its own class-wide total resolves it without any suppression. Phase 8 moved
 * the mode, equipment and hazmat conditions (load fields) into LaneLoadFilters, which the Carriers
 * to ask and Split-lane services share; this class keeps the quote filters and the order.
 */
public with sharing class LaneSearchFilters {
  // addFilters itself stays a small dispatcher; one helper per filter so no single method carries
  // every branch. The order (currency, mode, equipment, hazmat, accepted) is pinned
  // by LaneSearchQueryBuilderTest.
  public static void addFilters(
    LaneSearchRequest req,
    List<String> conditions,
    Map<String, Object> binds
  ) {
    addCurrencyFilter(req, conditions, binds);
    LaneLoadFilters.add(req, 'rtms__Load__r.', conditions, binds);
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
