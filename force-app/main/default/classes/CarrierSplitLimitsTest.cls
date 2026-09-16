/**
 * The caps and the query-row guard of Carriers to ask and Split-lane options (phase 8, spec §8), each
 * reached with a small fixture. CarrierLeadService.rowLimitOverride puts the query-row limit a few
 * rows above what a call has used, so the three quotes on one lane can trip the COUNT() pre-check
 * before a grouped count. The 500-plan and 1,000-plan caps take plans built in memory through
 * FreightPlanReader.rowsOverride: no plan is inserted and no plan query runs.
 *
 * Query budget (measured in PostProduc on 2026-09-15): the graph 33 queries and one load 35 to 37
 * before Test.startTest(); the quote insert 13 to 16 inside it, and find() at most 7.
 */
@IsTest
private class CarrierSplitLimitsTest {
  /** The graph carrier's quotes on the lane's load: the first accepted, the others declined. */
  private static final Integer LANE_QUOTES = 3;
  /** Query rows of the places read: the lane's two places. */
  private static final Integer PLACE_ROWS = 2;
  /** Query rows of one COUNT(). */
  private static final Integer COUNT_ROWS = 1;

  private class Fx {
    PricingTestDataFactory.Graph g;
    rtms__Load__c load;
  }

  /** Montreal and Toronto, the graph's lane ("Montreal, QC:Toronto, ON"), with no removal set. */
  private static void places() {
    RfpTestDataFactory.createPlace(
      'Montreal',
      'QC',
      'CA',
      45.5019,
      -73.5674,
      'H1A'
    );
    RfpTestDataFactory.createPlace(
      'Toronto',
      'ON',
      'CA',
      43.6532,
      -79.3832,
      'M5V'
    );
    LaneSearchExclusions.excludedContactIdsOverride = new Set<String>();
    IntercompanyCarriers.idsOverride = new Set<Id>();
  }

  private static LaneSearchRequest montrealToToronto() {
    LaneSearchRequest req = new LaneSearchRequest();
    req.originKey = 'montreal|qc|ca';
    req.destinationKey = 'toronto|on|ca';
    return req;
  }

  /** The graph, the lane's places and one load on the lane. */
  private static Fx laneLoad() {
    Fx f = new Fx();
    f.g = PricingTestDataFactory.createGraph();
    places();
    f.load = PricingTestDataFactory.createLoad(
      f.g,
      f.g.originLocation,
      f.g.destinationLocation
    );
    return f;
  }

  /** LANE_QUOTES quotes by the graph carrier on the load, in one insert: one accepted, the rest declined. */
  private static void insertLaneQuotes(Fx f) {
    List<rtms__CarrierQuote__c> quotes = new List<rtms__CarrierQuote__c>();
    for (Integer i = 0; i < LANE_QUOTES; i++) {
      rtms__CarrierQuote__c q = PricingTestDataFactory.buildQuote(
        f.g,
        f.load,
        1000
      );
      q.rtms__Accepted__c = i == 0;
      quotes.add(q);
    }
    insert quotes;
  }

  /**
   * count freight plans built in memory, as FreightPlanReader.read returns them: each has a Customer
   * row and one Carrier row whose delivered leg load, a different one per plan, the same carrier moved.
   */
  private static List<rtms__FreightPlan__c> plans(Integer count) {
    String planPrefix = rtms__FreightPlan__c.SObjectType.getDescribe()
      .getKeyPrefix();
    String loadPrefix = rtms__Load__c.SObjectType.getDescribe().getKeyPrefix();
    String carrierId =
      Account.SObjectType.getDescribe().getKeyPrefix() + '000000000001';
    List<Object> rows = new List<Object>();
    for (Integer i = 1; i <= count; i++) {
      String legLoadId = loadPrefix + String.valueOf(i).leftPad(12, '0');
      rows.add(
        new Map<String, Object>{
          'attributes' => new Map<String, Object>{
            'type' => 'rtms__FreightPlan__c'
          },
          'Id' => planPrefix + String.valueOf(i).leftPad(12, '0'),
          'rtms__Freight_Plan_Loads__r' => new Map<String, Object>{
            'totalSize' => 2,
            'done' => true,
            'records' => new List<Object>{
              new Map<String, Object>{
                'attributes' => new Map<String, Object>{
                  'type' => 'rtms__FreightPlanLoad__c'
                },
                'rtms__Type__c' => 'Customer'
              },
              new Map<String, Object>{
                'attributes' => new Map<String, Object>{
                  'type' => 'rtms__FreightPlanLoad__c'
                },
                'rtms__Type__c' => 'Carrier',
                'rtms__Load__c' => legLoadId,
                'rtms__Load__r' => new Map<String, Object>{
                  'attributes' => new Map<String, Object>{
                    'type' => 'rtms__Load__c'
                  },
                  'Id' => legLoadId,
                  'rtms__Carrier__c' => carrierId,
                  'rtms__Load_Status__c' => 'Delivered',
                  'rtms__Carrier__r' => new Map<String, Object>{
                    'attributes' => new Map<String, Object>{
                      'type' => 'Account'
                    },
                    'Id' => carrierId,
                    'Name' => 'Plan Carrier'
                  }
                }
              }
            }
          }
        }
      );
    }
    return (List<rtms__FreightPlan__c>) JSON.deserialize(
      JSON.serialize(rows),
      List<rtms__FreightPlan__c>.class
    );
  }

  /**
   * The quoted count's COUNT() finds the lane's 3 quotes, and the limit leaves room for only 2 of them
   * after the places read and that COUNT(). The stage stops before either grouped count runs: no
   * carrier is counted, and the list says it may be incomplete.
   */
  @IsTest
  static void theGuardStopsBeforeTheQuotedCountWhenItsRowsWouldPassTheLimit() {
    Fx f = laneLoad();
    Test.startTest();
    insertLaneQuotes(f);
    CarrierLeadService.rowReserve = 0;
    CarrierLeadService.rowLimitOverride =
      Limits.getQueryRows() +
      PLACE_ROWS +
      COUNT_ROWS +
      LANE_QUOTES -
      1;
    Integer queriesBefore = Limits.getQueries();
    CarrierLeadResult r = CarrierLeadService.find(montrealToToronto());
    Integer queriesUsed = Limits.getQueries() - queriesBefore;
    Test.stopTest();

    System.assertEquals(
      LANE_QUOTES,
      [
        SELECT COUNT()
        FROM rtms__CarrierQuote__c
        WHERE rtms__Load__c = :f.load.Id
      ],
      'precondition: the lane holds the fixture quotes only'
    );
    System.assertEquals(
      2,
      queriesUsed,
      'the places read and the quoted COUNT() only: neither grouped count ran'
    );
    System.assertEquals(true, r.truncated, 'The list may be incomplete.');
    System.assertEquals(CarrierLeadResult.NONE, r.stage, JSON.serialize(r));
    System.assertEquals(0, r.leads.size(), 'no quote-sourced lead');
  }

  /**
   * The quoted count fits and runs; the moved count's COUNT() finds the one accepted quote, and the
   * limit leaves no row for it. The stage stops before the moved count: the carrier the quoted count
   * found is kept with no load moved, and the list says it may be incomplete.
   */
  @IsTest
  static void theGuardStopsBeforeTheMovedCountAndKeepsTheQuotedCarrier() {
    Fx f = laneLoad();
    Test.startTest();
    insertLaneQuotes(f);
    CarrierLeadService.rowReserve = 0;
    // The places read, the quoted COUNT(), the quote rows the quoted count reads and the moved COUNT()
    // fit; the accepted quote row the moved count would read does not.
    CarrierLeadService.rowLimitOverride =
      Limits.getQueryRows() +
      PLACE_ROWS +
      COUNT_ROWS +
      LANE_QUOTES +
      COUNT_ROWS;
    Integer queriesBefore = Limits.getQueries();
    CarrierLeadResult r = CarrierLeadService.find(montrealToToronto());
    Integer queriesUsed = Limits.getQueries() - queriesBefore;
    Test.stopTest();

    System.assertEquals(
      LANE_QUOTES,
      [
        SELECT COUNT()
        FROM rtms__CarrierQuote__c
        WHERE rtms__Load__c = :f.load.Id
      ],
      'precondition: the lane holds the fixture quotes only'
    );
    System.assertEquals(
      1,
      [
        SELECT COUNT()
        FROM rtms__CarrierQuote__c
        WHERE rtms__Load__c = :f.load.Id AND rtms__Accepted__c = TRUE
      ],
      'precondition: one of them is accepted'
    );
    System.assertEquals(
      4,
      queriesUsed,
      'the places read, the quoted COUNT() and count, and the moved COUNT(): no moved count, plan read or account read'
    );
    System.assertEquals(
      CarrierLeadResult.SAME_LANE,
      r.stage,
      JSON.serialize(r)
    );
    System.assertEquals(true, r.truncated, 'The list may be incomplete.');
    System.assertEquals(1, r.leads.size(), 'the graph carrier');
    CarrierLeadResult.Lead kept = r.leads[0];
    System.assertEquals(
      f.g.vendor.Id,
      kept.carrierId,
      'found by the quoted count'
    );
    System.assertEquals(1, kept.loadsQuoted, 'three quotes on one load');
    System.assertEquals(
      0,
      kept.loadsMoved,
      'the moved count did not run, though one quote is accepted'
    );
    System.assertEquals(
      new List<String>{ CarrierLeadResult.SOURCE_QUOTE },
      kept.sources,
      'a quote source only'
    );
    System.assertEquals(
      false,
      kept.canOpen,
      'a stopped stage skips the account read'
    );
  }

  /**
   * The Carriers to ask plan read takes 500 plans: 500 plans read mark the list incomplete, 499 do not.
   * Every plan's leg names the same carrier, so stage 1 counts its leg loads and stage 2 never runs.
   */
  @IsTest
  static void fiveHundredPlansMarkCarriersToAskIncomplete() {
    places();
    List<rtms__FreightPlan__c> underCap = plans(
      CarrierLeadService.PLAN_LIMIT - 1
    );
    List<rtms__FreightPlan__c> atCap = plans(CarrierLeadService.PLAN_LIMIT);
    Test.startTest();
    FreightPlanReader.rowsOverride = underCap;
    CarrierLeadResult under = CarrierLeadService.find(montrealToToronto());
    FreightPlanReader.rowsOverride = atCap;
    CarrierLeadResult atLimit = CarrierLeadService.find(montrealToToronto());
    Test.stopTest();

    System.assertEquals(500, CarrierLeadService.PLAN_LIMIT, 'the plan LIMIT');
    System.assertEquals(CarrierLeadResult.SAME_LANE, under.stage);
    System.assertEquals(
      499,
      under.leads[0].loadsMoved,
      'every in-memory plan was read'
    );
    System.assertEquals(false, under.truncated, '499 plans are under the cap');
    System.assertEquals(CarrierLeadResult.SAME_LANE, atLimit.stage);
    System.assertEquals(500, atLimit.leads[0].loadsMoved);
    System.assertEquals(
      true,
      atLimit.truncated,
      '500 plans reach the cap: The list may be incomplete.'
    );
  }

  /**
   * Split history reads 1,000 plans: 1,000 plans mark the card incomplete, 999 do not. A plan with a
   * single carrier leg makes no split shipment and no handoff point is set, so the card shows the
   * no-option message either way.
   */
  @IsTest
  static void aThousandPlansMarkSplitHistoryIncomplete() {
    places();
    HandoffPoints.keysOverride = new List<String>();
    List<rtms__FreightPlan__c> underCap = plans(999);
    List<rtms__FreightPlan__c> atCap = plans(1000);
    Test.startTest();
    FreightPlanReader.rowsOverride = underCap;
    SplitLaneResult under = SplitLaneService.options(
      montrealToToronto(),
      'CAD'
    );
    FreightPlanReader.rowsOverride = atCap;
    SplitLaneResult atLimit = SplitLaneService.options(
      montrealToToronto(),
      'CAD'
    );
    Test.stopTest();

    System.assertEquals(false, under.truncated, '999 plans are under the cap');
    System.assertEquals(
      true,
      atLimit.truncated,
      '1,000 plans reach the cap: The list may be incomplete.'
    );
    System.assertEquals(
      SplitLaneService.NO_OPTION_MESSAGE,
      atLimit.message,
      'single-leg plans make no split shipment'
    );
  }
}
