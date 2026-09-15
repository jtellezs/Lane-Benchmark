/**
 * Carriers to ask (phase 8, spec section 3): names the carriers that know a lane when the first
 * search found no carrier rate, never an amount (D4, R106). Stage 1, the same lane over the last
 * 3 years: two grouped carrier quote counts by rtms__Vendor__c - distinct loads quoted, and distinct
 * loads moved with rtms__Accepted__c = true, because SOQL has no conditional count (R107) - and the
 * carrier legs of freight plans whose customer load is on the lane (read through
 * FreightPlanReader), merged per carrier (sources Quote, Split leg) and ranked by loads moved, loads
 * quoted, last seen, then name (R82). Only the request's place keys, precisions, postal prefixes
 * and mode, equipment and hazmat filters apply (R101); LaneQueries builds every statement.
 * Intercompany carriers are left out by the quote counts and by the leg loop (D6); the excluded
 * contact applies to quotes only (R89). Before each read after the places, a query-row check stops
 * early and marks the list incomplete. One user-mode Account read decides each link.
 */
// Runs without sharing on purpose: carrier quotes and loads inherit Private load sharing, and pricing names every team's carriers, like LaneSearchService. Access is gated by the Lane Benchmark and RFP Tool permission sets; the Account link check is the one user-mode read.
public without sharing class CarrierLeadService {
  private static final String LOAD_PATH = 'rtms__Load__r.';
  private static final Integer SAME_LANE_DAYS = 1095;
  private static final Integer PLAN_LIMIT = 500;

  /** Query rows kept free before each read; a test raises it past the limit to force the early stop. */
  @TestVisible
  private static Integer rowReserve = 5000;

  public static CarrierLeadResult find(LaneSearchRequest req) {
    req.applyDefaults();
    CarrierLeadResult result = new CarrierLeadResult();
    Map<String, Pricing_Place__c> places = loadPlaces(req);
    Pricing_Place__c origin = places.get(req.originKey);
    Pricing_Place__c destination = places.get(req.destinationKey);
    if (origin == null || destination == null) {
      return result;
    }
    Tally sameLane = new Tally();
    Map<String, Object> binds = new Map<String, Object>();
    List<String> onLane = LaneQueries.laneConditions(
      req,
      origin,
      destination,
      LOAD_PATH,
      binds
    );
    // The plan read gets the lane binds only: quoteCountSoql adds 'excluded' and 'intercompany'.
    Map<String, Object> planBinds = binds.clone();
    countQuotes(onLane, SAME_LANE_DAYS, binds, sameLane, result);
    readLegs(onLane, SAME_LANE_DAYS, planBinds, sameLane, result);
    if (!sameLane.isEmpty()) {
      result.stage = CarrierLeadResult.SAME_LANE;
      result.leads = ranked(sameLane.leads(), true);
    }
    markReadable(result);
    return result;
  }

  /**
   * Stage 1 order (byQuoted true): loads moved, loads quoted, last seen (newest first, none last),
   * then the name ignoring case; with byQuoted false loads quoted is skipped (stage 2, R82). Returns
   * a new list.
   */
  @TestVisible
  private static List<CarrierLeadResult.Lead> ranked(
    List<CarrierLeadResult.Lead> leads,
    Boolean byQuoted
  ) {
    List<CarrierLeadResult.Lead> sorted = new List<CarrierLeadResult.Lead>(
      leads
    );
    sorted.sort(new LeadOrder(byQuoted));
    return sorted;
  }

  /** Both places by Key__c; empty, with no query, when either key is blank. */
  @SuppressWarnings(
    'PMD.ApexCRUDViolation'
  ) // system mode by design (see class comment)
  private static Map<String, Pricing_Place__c> loadPlaces(
    LaneSearchRequest req
  ) {
    Map<String, Pricing_Place__c> byKey = new Map<String, Pricing_Place__c>();
    if (String.isBlank(req.originKey) || String.isBlank(req.destinationKey)) {
      return byKey;
    }
    Set<String> keys = new Set<String>{ req.originKey, req.destinationKey };
    for (Pricing_Place__c p : [
      SELECT
        Key__c,
        City__c,
        Province__c,
        Country__c,
        Postal_Prefix__c,
        Spellings__c,
        Geolocation__Latitude__s,
        Geolocation__Longitude__s
      FROM Pricing_Place__c
      WHERE Key__c IN :keys
    ]) {
      byKey.put(p.Key__c, p);
    }
    return byKey;
  }

  /** The loads quoted count, then the loads moved count; each is skipped once the query-row check stops. */
  @SuppressWarnings(
    'PMD.ApexCRUDViolation'
  ) // system mode by design (see class comment); Database.queryWithBinds also counts as CRUD for PMD
  private static void countQuotes(
    List<String> onLane,
    Integer days,
    Map<String, Object> binds,
    Tally tally,
    CarrierLeadResult result
  ) {
    if (stopEarly(result)) {
      return;
    }
    String quotedSoql = LaneQueries.quoteCountSoql(onLane, days, false, binds);
    List<AggregateResult> quoted = Database.queryWithBinds(
      quotedSoql,
      binds,
      AccessLevel.SYSTEM_MODE
    );
    tally.addQuoteGroups(capped(quoted, result), false);
    if (stopEarly(result)) {
      return;
    }
    String movedSoql = LaneQueries.quoteCountSoql(onLane, days, true, binds);
    List<AggregateResult> moved = Database.queryWithBinds(
      movedSoql,
      binds,
      AccessLevel.SYSTEM_MODE
    );
    tally.addQuoteGroups(capped(moved, result), true);
  }

  /** The carrier legs of freight plans whose customer load matches onLane, as plain rows with no amount. */
  private static void readLegs(
    List<String> onLane,
    Integer days,
    Map<String, Object> binds,
    Tally tally,
    CarrierLeadResult result
  ) {
    if (stopEarly(result)) {
      return;
    }
    List<rtms__FreightPlan__c> plans = FreightPlanReader.read(
      LaneQueries.planSoql(onLane, days, PLAN_LIMIT, false),
      binds
    );
    if (plans.size() >= PLAN_LIMIT) {
      result.truncated = true;
    }
    tally.addPlans(plans, IntercompanyCarriers.ids());
  }

  /** A count that came back with GROUP_LIMIT + 1 groups was cut: the extra, smallest group is dropped. */
  private static List<AggregateResult> capped(
    List<AggregateResult> groups,
    CarrierLeadResult result
  ) {
    if (groups.size() > LaneQueries.GROUP_LIMIT) {
      groups.remove(groups.size() - 1);
      result.truncated = true;
    }
    return groups;
  }

  /** true, with the list marked incomplete, once no more than rowReserve query rows are left. */
  private static Boolean stopEarly(CarrierLeadResult result) {
    if (Limits.getQueryRows() > Limits.getLimitQueryRows() - rowReserve) {
      result.truncated = true;
      return true;
    }
    return false;
  }

  /** canOpen from one user-mode read: a carrier account the user cannot read shows its name without a link. */
  private static void markReadable(CarrierLeadResult result) {
    if (result.leads.isEmpty() || stopEarly(result)) {
      return;
    }
    Set<Id> carrierIds = new Set<Id>();
    for (CarrierLeadResult.Lead entry : result.leads) {
      carrierIds.add(entry.carrierId);
    }
    Map<Id, Account> readable;
    try {
      readable = new Map<Id, Account>(
        [SELECT Id FROM Account WHERE Id IN :carrierIds WITH USER_MODE]
      );
    } catch (Exception e) {
      // A caller with no read on Account at all gets an exception from the platform: no link.
      return;
    }
    for (CarrierLeadResult.Lead entry : result.leads) {
      entry.canOpen = readable.containsKey(entry.carrierId);
    }
  }

  /**
   * One stage's carriers while its reads come in. Quote groups set loads quoted and keep loads
   * moved apart; plan legs collect each carrier's distinct leg loads; leads() adds the two into
   * loads moved and lists the sources in the order Quote, Split leg. An inner class, so its branches
   * stay out of CarrierLeadService's PMD class complexity total.
   */
  private class Tally {
    private final Map<Id, CarrierLeadResult.Lead> byCarrier = new Map<Id, CarrierLeadResult.Lead>();
    private final Set<Id> quoteCarriers = new Set<Id>();
    private final Map<Id, Integer> movedQuoteLoads = new Map<Id, Integer>();
    private final Map<Id, Set<Id>> legLoads = new Map<Id, Set<Id>>();

    private Boolean isEmpty() {
      return byCarrier.isEmpty();
    }

    private void addQuoteGroups(List<AggregateResult> groups, Boolean moved) {
      for (AggregateResult row : groups) {
        CarrierLeadResult.Lead entry = entryFor(
          (Id) row.get('rtms__Vendor__c'),
          (String) row.get('vname'),
          (Boolean) row.get('bl')
        );
        quoteCarriers.add(entry.carrierId);
        Integer loads = (Integer) row.get('loads');
        if (moved) {
          movedQuoteLoads.put(entry.carrierId, loads);
        } else {
          entry.loadsQuoted = loads;
        }
        seen(entry, ((Datetime) row.get('lastSeen'))?.date());
      }
    }

    /**
     * Per plan, the customer row gives the date and each carrier leg whose load has a carrier off
     * the intercompany list and is not cancelled counts for that carrier. The child rows are read
     * with a for loop: reading a child list of more than 200 rows any other way throws.
     */
    private void addPlans(
      List<rtms__FreightPlan__c> plans,
      Set<Id> intercompany
    ) {
      for (rtms__FreightPlan__c plan : plans) {
        Date customerDate = null;
        List<rtms__FreightPlanLoad__c> legs = new List<rtms__FreightPlanLoad__c>();
        for (rtms__FreightPlanLoad__c row : plan.rtms__Freight_Plan_Loads__r) {
          if (row.rtms__Type__c == 'Customer') {
            customerDate = row.rtms__Load__r?.CreatedDate?.date();
          } else if (countsAsLeg(row, intercompany)) {
            legs.add(row);
          }
        }
        for (rtms__FreightPlanLoad__c leg : legs) {
          addLeg(leg, customerDate);
        }
      }
    }

    private Boolean countsAsLeg(
      rtms__FreightPlanLoad__c row,
      Set<Id> intercompany
    ) {
      rtms__Load__c legLoad = row.rtms__Load__r;
      return row.rtms__Type__c == 'Carrier' &&
        legLoad?.rtms__Carrier__c != null &&
        !intercompany.contains(legLoad.rtms__Carrier__c) &&
        legLoad.rtms__Load_Status__c != 'Cancelled';
    }

    private void addLeg(rtms__FreightPlanLoad__c leg, Date customerDate) {
      rtms__Load__c legLoad = leg.rtms__Load__r;
      CarrierLeadResult.Lead entry = entryFor(
        legLoad.rtms__Carrier__c,
        legLoad.rtms__Carrier__r?.Name,
        legLoad.rtms__Carrier__r?.Black_List__c
      );
      if (!legLoads.containsKey(entry.carrierId)) {
        legLoads.put(entry.carrierId, new Set<Id>());
      }
      legLoads.get(entry.carrierId).add(leg.rtms__Load__c);
      seen(entry, customerDate);
    }

    private CarrierLeadResult.Lead entryFor(
      Id carrierId,
      String name,
      Boolean blacklisted
    ) {
      CarrierLeadResult.Lead entry = byCarrier.get(carrierId);
      if (entry == null) {
        entry = new CarrierLeadResult.Lead();
        entry.carrierId = carrierId;
        entry.name = name;
        byCarrier.put(carrierId, entry);
      }
      entry.blacklisted = entry.blacklisted || blacklisted == true;
      return entry;
    }

    private void seen(CarrierLeadResult.Lead entry, Date seenOn) {
      if (
        seenOn != null && (entry.lastSeen == null || seenOn > entry.lastSeen)
      ) {
        entry.lastSeen = seenOn;
      }
    }

    private List<CarrierLeadResult.Lead> leads() {
      for (CarrierLeadResult.Lead entry : byCarrier.values()) {
        Set<Id> legs = legLoads.get(entry.carrierId) ?? new Set<Id>();
        entry.loadsMoved =
          (movedQuoteLoads.get(entry.carrierId) ?? 0) + legs.size();
        entry.sources = new List<String>();
        if (quoteCarriers.contains(entry.carrierId)) {
          entry.sources.add(CarrierLeadResult.SOURCE_QUOTE);
        }
        if (!legs.isEmpty()) {
          entry.sources.add(CarrierLeadResult.SOURCE_SPLIT_LEG);
        }
      }
      return byCarrier.values();
    }
  }

  /** The order ranked() sorts by; an inner class for the same complexity reason as Tally. */
  private class LeadOrder implements Comparator<CarrierLeadResult.Lead> {
    private final Boolean byQuoted;

    private LeadOrder(Boolean byQuoted) {
      this.byQuoted = byQuoted;
    }

    public Integer compare(CarrierLeadResult.Lead a, CarrierLeadResult.Lead b) {
      Integer diff = b.loadsMoved - a.loadsMoved;
      if (diff == 0 && byQuoted) {
        diff = b.loadsQuoted - a.loadsQuoted;
      }
      if (diff == 0) {
        diff = newestFirst(a.lastSeen, b.lastSeen);
      }
      if (diff == 0) {
        diff = nameKey(a).compareTo(nameKey(b));
      }
      return diff;
    }

    private Integer newestFirst(Date a, Date b) {
      if (a == b) {
        return 0;
      }
      if (a == null) {
        return 1;
      }
      if (b == null) {
        return -1;
      }
      return a > b ? -1 : 1;
    }

    private String nameKey(CarrierLeadResult.Lead entry) {
      return entry.name == null ? '' : entry.name.toLowerCase();
    }
  }
}
