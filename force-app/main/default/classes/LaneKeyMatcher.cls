/**
 * One end of a lane as a Revenova lane-key condition: the city, province or postal-prefix LIKE
 * pattern for that end, bound under the end's bind prefix. Pure: no SOQL, no DML. Phase 8 moved
 * this out of LaneSearchQueryBuilder (its addCity, addProvince, addZip3, requirePostalPrefix and
 * laneLikePattern) so the lane search, CarrierLeadService and SplitLaneService match a lane the same
 * way (spec R103); LaneSearchQueryBuilderTest proves the search's SOQL did not change.
 *
 * loadPath is the relationship path from the queried row to its load: 'rtms__Load__r.' on
 * rtms__CarrierQuote__c and rtms__FreightPlanLoad__c rows, '' on rtms__Load__c rows. Only the lane
 * search draws a radius (LaneSearchQueryBuilder.addRadius, through the stops); here RADIUS reads as
 * CITY, because the deeper steps use a radius end's place city key (spec R83).
 */
public with sharing class LaneKeyMatcher {
  /**
   * The condition for one end, after putting its pattern into binds under bindPrefix + 'City',
   * 'Prov' or 'Zip3'; null when the end has no constraint (no place, and no explicit ZIP3 prefix on
   * a ZIP3 end). The parameter is endPrecision, not precision: Apex is case-insensitive, and the
   * same collision with the Precision enum is documented in LaneSearchRequest.validateRadius.
   */
  public static String condition(
    String loadPath,
    Boolean isOrigin,
    String bindPrefix,
    LaneSearchRequest.Precision endPrecision,
    Pricing_Place__c place,
    String explicitZip3,
    Map<String, Object> binds
  ) {
    if (endPrecision == LaneSearchRequest.Precision.ZIP3) {
      return zip3Condition(
        loadPath,
        isOrigin,
        bindPrefix,
        place,
        explicitZip3,
        binds
      );
    }
    if (place == null) {
      return null;
    }
    if (endPrecision == LaneSearchRequest.Precision.PROVINCE) {
      binds.put(bindPrefix + 'Prov', likePattern(isOrigin, place.Province__c));
      return loadPath + 'rtms__State_Lane__c LIKE :' + bindPrefix + 'Prov';
    }
    List<String> patterns = new List<String>();
    for (String v : PlaceNormalizer.cityLaneVariants(place)) {
      patterns.add(likePattern(isOrigin, v));
    }
    binds.put(bindPrefix + 'City', patterns);
    return loadPath + 'rtms__City_Lane__c LIKE :' + bindPrefix + 'City';
  }

  /** An explicit prefix needs no place; without one, the place's own prefix is required. */
  private static String zip3Condition(
    String loadPath,
    Boolean isOrigin,
    String bindPrefix,
    Pricing_Place__c place,
    String explicitZip3,
    Map<String, Object> binds
  ) {
    String prefix = explicitZip3;
    if (String.isBlank(prefix)) {
      if (place == null) {
        return null;
      }
      if (String.isBlank(place.Postal_Prefix__c)) {
        throw new LaneSearchException(
          'Place ' +
            place.Key__c +
            ' has no postal prefix; pass ' +
            (isOrigin == true ? 'originZip3' : 'destinationZip3')
        );
      }
      prefix = place.Postal_Prefix__c;
    }
    binds.put(bindPrefix + 'Zip3', likePattern(isOrigin, prefix));
    return loadPath + 'rtms__Zip3_Lane__c LIKE :' + bindPrefix + 'Zip3';
  }

  /** "value:%" for an origin, "%:value" for a destination - the shared shape of every lane LIKE pattern. */
  private static String likePattern(Boolean isOrigin, String rawValue) {
    String escaped = LaneSearchQueryBuilder.escapeLike(rawValue);
    return isOrigin == true ? escaped + ':%' : '%:' + escaped;
  }
}
