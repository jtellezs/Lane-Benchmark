/**
 * What the split-lane card shows (phase 8, spec section 4): the currency of every amount, the start
 * date of the latest USD dated rate used (null in CAD), one Option per history group or estimate,
 * whether the plan read reached its limit, and a message when the card has
 * nothing to show. Plain data, no logic. Every amount is at scale 2; the handoff cost is added on
 * the screen.
 */
public class SplitLaneResult {
  public static final String HISTORY = 'History';
  public static final String ESTIMATE = 'Estimate';

  @AuraEnabled
  public String currencyCode;
  @AuraEnabled
  public Date rateStartDate;
  @AuraEnabled
  public List<Option> options = new List<Option>();
  @AuraEnabled
  public Boolean truncated = false;
  @AuraEnabled
  public String message;

  /** A carrier on one leg position, with the legs it moved there. */
  public class LegCarrier {
    @AuraEnabled
    public Id carrierId;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public Integer legsMoved = 0;
    @AuraEnabled
    public Boolean blacklisted = false;
  }

  /** One leg position (1-based): its most frequent lane, its carriers and the median of its priced totals. */
  public class Leg {
    @AuraEnabled
    public Integer position;
    @AuraEnabled
    public String laneLabel;
    @AuraEnabled
    public List<LegCarrier> carriers = new List<LegCarrier>();
    @AuraEnabled
    public Decimal median;
    @AuraEnabled
    public Integer pricedCount = 0;
  }

  /** A history group (kind History) or an estimate through a handoff point (kind Estimate). */
  public class Option {
    @AuraEnabled
    public String kind;
    @AuraEnabled
    public String handoffLabel;
    @AuraEnabled
    public Integer shipments = 0;
    @AuraEnabled
    public List<Leg> legs = new List<Leg>();
    @AuraEnabled
    public Decimal medianTotal;
    @AuraEnabled
    public Integer pricedShipments = 0;
    @AuraEnabled
    public Integer extraDistancePct;
  }
}
