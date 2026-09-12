/**
 * Many-lane pricing actions of the RFP workbench (spec §5.4): one call prices, copies or deletes
 * up to 200 lanes in user mode. Validation failures are LaneSearchExceptions (the controller turns
 * them into user errors); per-record DML failures land in Result.errors and never abort the rest.
 */
public with sharing class RfpBulkService {
  public static final Integer MAX_LANES = 200;
  private static final Integer MAX_ERRORS = 5;

  public class Result {
    @AuraEnabled
    public List<RFP_Lane__c> lanes = new List<RFP_Lane__c>();
    @AuraEnabled
    public Integer updated = 0;
    @AuraEnabled
    public Integer skipped = 0;
    @AuraEnabled
    public List<Id> skippedIds = new List<Id>();
    @AuraEnabled
    public List<String> errors = new List<String>();
  }

  /** Everything one action needs: the lanes as read, their projects' default margins, and what to write. */
  @TestVisible
  private class Context {
    List<Id> ids;
    List<RFP_Lane__c> lanes;
    Map<Id, Decimal> defaultMarginByProject = new Map<Id, Decimal>();
    List<RFP_Lane__c> updates = new List<RFP_Lane__c>();
    @TestVisible
    Result result = new Result();
    /** Failures of every DML pass of this action, listed or not. */
    @TestVisible
    Integer failedTotal = 0;
    Boolean finished = false;

    Decimal defaultMarginFor(RFP_Lane__c lane) {
      return defaultMarginByProject.get(lane.RFP_Project__c);
    }

    /** Counts the rows that saved and notes the failures; count=false for the cascade delete of bids. */
    void collect(List<Database.SaveResult> results, Boolean count) {
      for (Database.SaveResult r : results) {
        if (r.isSuccess()) {
          if (count) {
            result.updated++;
          }
          continue;
        }
        noteFailure(r.getId(), r.getErrors()[0].getMessage());
      }
    }

    void collect(List<Database.DeleteResult> results, Boolean count) {
      for (Database.DeleteResult r : results) {
        if (r.isSuccess()) {
          if (count) {
            result.updated++;
          }
          continue;
        }
        noteFailure(r.getId(), r.getErrors()[0].getMessage());
      }
    }

    /** Lists the first few failures verbatim; the rest are only counted, so finish() can tally them. */
    @TestVisible
    void noteFailure(Id recordId, String message) {
      failedTotal++;
      if (result.errors.size() < MAX_ERRORS) {
        result.errors.add(recordId + ': ' + message.left(160));
      }
    }

    /** One tail for the whole action, once every DML pass has been collected. */
    @TestVisible
    void finish() {
      if (finished) {
        return;
      }
      finished = true;
      Integer unlisted = failedTotal - result.errors.size();
      if (unlisted > 0) {
        result.errors.add('… and ' + unlisted + ' more');
      }
    }
  }

  public static Result applyMedian(List<Id> laneIds, Boolean overwrite) {
    Context c = load(laneIds);
    for (RFP_Lane__c lane : c.lanes) {
      Boolean costedElsewhere =
        lane.Cost__c != null &&
        lane.Cost_Source__c != 'History median';
      Boolean leaveAlone =
        lane.Hist_Median__c == null || (costedElsewhere && overwrite != true);
      if (leaveAlone) {
        skip(c, lane);
        continue;
      }
      RFP_Lane__c u = pricingCopy(lane);
      u.Cost__c = lane.Hist_Median__c;
      u.Cost_Source__c = 'History median';
      u.Selected_Bid__c = null;
      RfpPricingMath.recompute(u, c.defaultMarginFor(lane));
      c.updates.add(u);
    }
    return save(c, false);
  }

  public static Result applyPricing(
    List<Id> laneIds,
    Decimal cost,
    Decimal sell,
    Decimal margin
  ) {
    validatePricing(cost, sell, margin);
    Context c = load(laneIds);
    for (RFP_Lane__c lane : c.lanes) {
      RFP_Lane__c u = pricingCopy(lane);
      if (cost != null) {
        u.Cost__c = cost;
        u.Cost_Source__c = 'Manual';
        u.Selected_Bid__c = null;
        RfpPricingMath.recompute(u, c.defaultMarginFor(lane));
      }
      if (sell != null) {
        u.Sell__c = sell;
        u.Sell_Source__c = 'Manual';
        u.Margin__c = RfpPricingMath.marginFor(u.Cost__c, sell);
      }
      if (margin != null) {
        u.Margin__c = margin;
        u.Sell_Source__c = 'Margin';
        u.Sell__c = RfpPricingMath.sellFor(u.Cost__c, margin);
      }
      c.updates.add(u);
    }
    return save(c, false);
  }

  private static void validatePricing(
    Decimal cost,
    Decimal sell,
    Decimal margin
  ) {
    String problem = RfpPricingInput.problem(cost, sell, margin);
    if (problem != null) {
      throw new LaneSearchException(problem);
    }
  }

  /**
   * One bid per lane from the same template, then the lanes pick it as their cost. Two DMLs in one
   * Savepoint: if the lane update fails the bids are rolled back too, so no bid is left behind
   * without a lane pointing at it (allOrNone on the lane update for the same reason).
   */
  public static Result applyBid(List<Id> laneIds, String bidJson) {
    Benchmark_Rate__c template = bidTemplate(bidJson);
    Context c = load(laneIds);
    BidPlan plan = planBids(c, template);
    if (plan.bids.isEmpty()) {
      return save(c, false);
    }
    Savepoint sp = Database.setSavepoint();
    try {
      costFromBids(c, plan, BenchmarkRateService.saveAll(plan.bids));
      return save(c, true);
    } catch (Exception e) {
      Database.rollback(sp);
      throw new LaneSearchException(
        'No lane was updated: ' + RfpUserError.safe(e)
      );
    }
  }

  /** The bids to insert and the lanes they will cost, in the same order. */
  private class BidPlan {
    List<Benchmark_Rate__c> bids = new List<Benchmark_Rate__c>();
    List<RFP_Lane__c> targets = new List<RFP_Lane__c>();
  }

  /** The typed carrier rate, refused before any DML when it carries no usable rate. */
  private static Benchmark_Rate__c bidTemplate(String bidJson) {
    Benchmark_Rate__c template = (Benchmark_Rate__c) JSON.deserialize(
      bidJson,
      Benchmark_Rate__c.class
    );
    Boolean unusable = template.Rate__c == null || template.Rate__c <= 0;
    if (unusable) {
      throw new LaneSearchException('A bid needs a rate above zero.');
    }
    return template;
  }

  /** One clone of the template per lane it can price; a lane in another currency is skipped. */
  private static BidPlan planBids(Context c, Benchmark_Rate__c template) {
    BidPlan plan = new BidPlan();
    for (RFP_Lane__c lane : c.lanes) {
      Boolean otherCurrency =
        template.CurrencyIsoCode != null &&
        lane.CurrencyIsoCode != template.CurrencyIsoCode;
      if (otherCurrency) {
        skip(c, lane);
        continue;
      }
      Benchmark_Rate__c bid = template.clone(false, true);
      bid.RFP_Lane__c = lane.Id;
      plan.bids.add(bid);
      plan.targets.add(lane);
    }
    return plan;
  }

  /** Every planned lane takes its saved bid as the cost, recomputed against the project margin. */
  private static void costFromBids(
    Context c,
    BidPlan plan,
    List<Benchmark_Rate__c> saved
  ) {
    for (Integer i = 0; i < saved.size(); i++) {
      RFP_Lane__c u = pricingCopy(plan.targets[i]);
      u.Cost__c = saved[i].Rate__c;
      u.Cost_Source__c = 'Bid';
      u.Selected_Bid__c = saved[i].Id;
      RfpPricingMath.recompute(u, c.defaultMarginFor(plan.targets[i]));
      c.updates.add(u);
    }
  }

  public static Result copyPricing(Id sourceLaneId, List<Id> laneIds) {
    List<RFP_Lane__c> sources = RfpLaneController.lanesByIds(
      new List<Id>{ sourceLaneId }
    );
    Boolean nothingToCopy = sources.isEmpty() || sources[0].Cost__c == null;
    if (nothingToCopy) {
      throw new LaneSearchException('The source lane has no cost to copy.');
    }
    RFP_Lane__c source = sources[0];
    Context c = load(laneIds);
    for (RFP_Lane__c lane : c.lanes) {
      if (lane.Id == source.Id) {
        continue;
      }
      RFP_Lane__c u = pricingCopy(source);
      u.Id = lane.Id;
      c.updates.add(u);
    }
    return save(c, false);
  }

  public static Result deleteLanes(List<Id> laneIds) {
    Context c = load(laneIds);
    List<Benchmark_Rate__c> bids = [
      SELECT Id
      FROM Benchmark_Rate__c
      WHERE RFP_Lane__c IN :c.ids
      WITH USER_MODE
    ];
    if (!bids.isEmpty()) {
      c.collect(Database.delete(bids, false, AccessLevel.USER_MODE), false);
    }
    c.collect(Database.delete(c.lanes, false, AccessLevel.USER_MODE), true);
    c.finish();
    c.result.lanes = RfpLaneController.lanesByIds(c.ids);
    return c.result;
  }

  // ---- shared helpers (Task 6 reuses them for applyBid) ----

  private static Context load(List<Id> laneIds) {
    Boolean unusable =
      laneIds == null ||
      laneIds.isEmpty() ||
      laneIds.size() > MAX_LANES;
    if (unusable) {
      throw new LaneSearchException(
        'Apply to at most ' + MAX_LANES + ' lanes per call.'
      );
    }
    Context c = new Context();
    c.ids = new List<Id>(new Set<Id>(laneIds));
    c.lanes = RfpLaneController.lanesByIds(c.ids);
    Set<Id> projectIds = new Set<Id>();
    for (RFP_Lane__c lane : c.lanes) {
      projectIds.add(lane.RFP_Project__c);
    }
    for (RFP_Project__c p : [
      SELECT Id, Default_Margin__c
      FROM RFP_Project__c
      WHERE Id IN :projectIds
      WITH USER_MODE
    ]) {
      c.defaultMarginByProject.put(p.Id, p.Default_Margin__c);
    }
    return c;
  }

  private static void skip(Context c, RFP_Lane__c lane) {
    c.result.skipped++;
    c.result.skippedIds.add(lane.Id);
  }

  /** The six pricing fields as currently stored, so recompute() sees the lane's real state. */
  private static RFP_Lane__c pricingCopy(RFP_Lane__c lane) {
    return new RFP_Lane__c(
      Id = lane.Id,
      Cost__c = lane.Cost__c,
      Cost_Source__c = lane.Cost_Source__c,
      Selected_Bid__c = lane.Selected_Bid__c,
      Margin__c = lane.Margin__c,
      Sell__c = lane.Sell__c,
      Sell_Source__c = lane.Sell_Source__c
    );
  }

  /** Writes c.updates; allOrNone=true is for callers holding a Savepoint (applyBid). */
  private static Result save(Context c, Boolean allOrNone) {
    if (!c.updates.isEmpty()) {
      List<RFP_Lane__c> clean = Security.stripInaccessible(
          AccessType.UPDATABLE,
          c.updates
        )
        .getRecords();
      c.collect(Database.update(clean, allOrNone, AccessLevel.USER_MODE), true);
    }
    c.finish();
    c.result.lanes = RfpLaneController.lanesByIds(c.ids);
    return c.result;
  }
}
