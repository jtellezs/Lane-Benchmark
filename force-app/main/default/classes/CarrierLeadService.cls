/**
 * Carriers to ask (phase 8, spec §3): the carriers that know a lane when the first search found no
 * carrier rate, by name and counts only. Stage 1 reads the same lane over 3 years: carrier quotes in
 * two grouped counts (loads quoted, loads moved; SOQL has no conditional count, R107) and the carrier
 * legs of freight plans whose customer load is on the lane, read through FreightPlanReader. Stage 2
 * runs only when stage 1 has no carrier left after the removals (R81): the same state or province
 * lane over the last 365 days, each end also in its place's country (R102), top 10 by loads moved
 * then last seen. Intercompany carriers are left out by the quote queries and while reading plan
 * legs; the excluded contacts apply to quotes only. No query here selects an amount (R106), and
 * CarrierLeadResult has no amount field. A query-row guard (spec §8) stops a stage and marks the list
 * incomplete once fewer than rowReserve query rows would be left: before each query, and before each
 * grouped quote count after a COUNT() of the quote rows that count would read, because COUNT_DISTINCT
 * and MAX charge every row they aggregate and one count cannot be stopped once it runs. The
 * per-carrier merge (Tally) and the ranking (LeadOrder) are inner classes, so their branches stay out
 * of this class's PMD complexity total.
 */
// Runs without sharing on purpose: carrier quotes inherit Private load sharing, like LaneSearchService. Access is gated by the Lane Benchmark and RFP permission sets; the account link alone is decided in user mode.
public without sharing class CarrierLeadService {
  @TestVisible
  private static final Integer SAME_LANE_DAYS = 1095;
  @TestVisible
  private static final Integer STATE_LANE_DAYS = 365;
  @TestVisible
  private static final Integer PLAN_LIMIT = 500;
  @TestVisible
  private static final Integer STATE_LANE_TOP = 10;
  private static final String LOAD_PATH = 'rtms__Load__r.';
  /** Query rows kept in reserve: a stage stops once fewer remain, or would remain after a grouped count (spec §8). */
  @TestVisible
  private static Integer rowReserve = 5000;
  /** A smaller query-row limit for tests, so the guard trips without 50,000 rows of fixtures; null uses the platform's. */
  @TestVisible
  private static Integer rowLimitOverride;

  public static CarrierLeadResult find(LaneSearchRequest req) {
    CarrierLeadResult result = new CarrierLeadResult();
    req.applyDefaults();
    Map<String, Pricing_Place__c> places = placesByKey(req);
    Pricing_Place__c origin = places.get(req.originKey);
    Pricing_Place__c destination = places.get(req.destinationKey);
    if (origin == null || destination == null) {
      return result;
    }
    Map<String, Object> quoteBinds = new Map<String, Object>();
    Map<String, Object> planBinds = new Map<String, Object>();
    Tally sameLane = readStage(
      LaneQueries.laneConditions(
        req,
        origin,
        destination,
        LOAD_PATH,
        quoteBinds
      ),
      LaneQueries.laneConditions(
        req,
        origin,
        destination,
        LOAD_PATH,
        planBinds
      ),
      SAME_LANE_DAYS,
      quoteBinds,
      planBinds
    );
    if (sameLane.hasLeads() || sameLane.stopped) {
      return finish(result, sameLane, CarrierLeadResult.SAME_LANE, null);
    }
    result.truncated = sameLane.truncated;
    return stateLaneLeads(req, origin, destination, result);
  }

  /**
   * Stage 2 on its own: the state or province lane over 365 days, top 10, labelled "QC to ON". find
   * calls it only when stage 1 has no carrier; tests call it directly, so a freight plan fixture
   * (SplitTestData.plan) proves stage 2's leg count even when its rows would also answer stage 1's
   * plan read.
   */
  @TestVisible
  private static CarrierLeadResult stateLaneLeads(
    LaneSearchRequest req,
    Pricing_Place__c origin,
    Pricing_Place__c destination,
    CarrierLeadResult result
  ) {
    Map<String, Object> quoteBinds = new Map<String, Object>();
    List<String> quoteConditions = stateLane(
      req,
      origin,
      destination,
      quoteBinds
    );
    if (quoteConditions == null) {
      return result;
    }
    Map<String, Object> planBinds = new Map<String, Object>();
    Tally stateLaneTally = readStage(
      quoteConditions,
      stateLane(req, origin, destination, planBinds),
      STATE_LANE_DAYS,
      quoteBinds,
      planBinds
    );
    finish(
      result,
      stateLaneTally,
      CarrierLeadResult.STATE_LANE,
      STATE_LANE_TOP
    );
    if (result.stage == CarrierLeadResult.STATE_LANE) {
      result.stateLaneLabel =
        origin.Province__c +
        ' to ' +
        destination.Province__c;
    }
    return result;
  }

  /**
   * Stage 2's conditions, or null when stage 2 does not apply: both ends of the first search used
   * province keys (stage 1 already read that lane, R95), a place has a blank Province__c, or
   * LaneQueries cannot map a place's Country__c to the country name a stop account holds.
   */
  @TestVisible
  private static List<String> stateLane(
    LaneSearchRequest req,
    Pricing_Place__c origin,
    Pricing_Place__c destination,
    Map<String, Object> binds
  ) {
    Boolean bothProvince =
      req.originPrecision == LaneSearchRequest.Precision.PROVINCE &&
      req.destinationPrecision == LaneSearchRequest.Precision.PROVINCE;
    if (
      bothProvince ||
      String.isBlank(origin.Province__c) ||
      String.isBlank(destination.Province__c)
    ) {
      return null;
    }
    return LaneQueries.stateLaneConditions(
      req,
      origin,
      destination,
      LOAD_PATH,
      binds
    );
  }

  /**
   * Stage 1 order (byQuoted true): loads moved, loads quoted, last seen (a missing date last),
   * name ignoring case; byQuoted false skips loads quoted (stage 2, R82). Returns a new list.
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

  /**
   * The two grouped quote counts (loads quoted, then loads moved), then the plans with their legs.
   * The stage stops, marked incomplete, once fewer than rowReserve query rows are left before a query
   * or would be left after a grouped count (countQuotes).
   */
  private static Tally readStage(
    List<String> quoteConditions,
    List<String> planConditions,
    Integer days,
    Map<String, Object> quoteBinds,
    Map<String, Object> planBinds
  ) {
    Tally tally = new Tally();
    if (tally.outOfRows()) {
      return tally;
    }
    if (!countQuotes(tally, quoteConditions, days, false, quoteBinds)) {
      return tally;
    }
    if (!countQuotes(tally, quoteConditions, days, true, quoteBinds)) {
      return tally;
    }
    tally.addPlans(
      FreightPlanReader.read(
        LaneQueries.planSoql(planConditions, days, PLAN_LIMIT, false),
        planBinds
      ),
      IntercompanyCarriers.ids()
    );
    return tally;
  }

  /**
   * One grouped quote count: loads moved when moved is true, loads quoted otherwise. A COUNT() of the
   * quote rows it would aggregate runs first (LaneQueries.quoteTotalSoql, one query row); when those
   * rows would leave fewer than rowReserve query rows, the stage stops without running the count.
   * Returns false once the stage has stopped.
   */
  @SuppressWarnings(
    'PMD.ApexCRUDViolation'
  ) // system mode by design (see class comment); Database.countQueryWithBinds and queryWithBinds also count as CRUD for PMD
  private static Boolean countQuotes(
    Tally tally,
    List<String> quoteConditions,
    Integer days,
    Boolean moved,
    Map<String, Object> quoteBinds
  ) {
    Integer quoteRows = Database.countQueryWithBinds(
      LaneQueries.quoteTotalSoql(quoteConditions, days, moved, quoteBinds),
      quoteBinds,
      AccessLevel.SYSTEM_MODE
    );
    if (tally.outOfRows(quoteRows)) {
      return false;
    }
    tally.addGroups(
      (List<AggregateResult>) Database.queryWithBinds(
        LaneQueries.quoteCountSoql(quoteConditions, days, moved, quoteBinds),
        quoteBinds,
        AccessLevel.SYSTEM_MODE
      ),
      moved
    );
    return !tally.outOfRows();
  }

  /** The query-row limit the guard measures against: a test's rowLimitOverride, else the platform's. */
  private static Integer rowLimit() {
    return rowLimitOverride != null
      ? rowLimitOverride
      : Limits.getLimitQueryRows();
  }

  /** Ranks, cuts stage 2 to its top 10, and decides each account link with one user-mode read. */
  private static CarrierLeadResult finish(
    CarrierLeadResult result,
    Tally tally,
    String stage,
    Integer top
  ) {
    List<CarrierLeadResult.Lead> leads = ranked(tally.leads(), top == null);
    while (top != null && leads.size() > top) {
      leads.remove(leads.size() - 1);
    }
    result.truncated =
      result.truncated ||
      tally.truncated ||
      (top == null && tally.groupCapped);
    if (leads.isEmpty()) {
      return result;
    }
    result.stage = stage;
    result.leads = leads;
    if (tally.outOfRows()) {
      // The guard stopped before the account read: the list is marked incomplete, as a stopped stage is.
      result.truncated = true;
      return result;
    }
    Set<Id> carrierIds = new Set<Id>();
    for (CarrierLeadResult.Lead entry : leads) {
      carrierIds.add(entry.carrierId);
    }
    Set<Id> readable = readableAccounts(carrierIds);
    for (CarrierLeadResult.Lead entry : leads) {
      entry.canOpen = readable.contains(entry.carrierId);
    }
    return result;
  }

  /**
   * The carrier accounts the caller can read in user mode (sharing and object access). A caller
   * with no read on Account at all gets an exception from the platform, and opens no link.
   */
  private static Set<Id> readableAccounts(Set<Id> accountIds) {
    Set<Id> readable = new Set<Id>();
    try {
      for (Account a : [
        SELECT Id
        FROM Account
        WHERE Id IN :accountIds
        WITH USER_MODE
      ]) {
        readable.add(a.Id);
      }
    } catch (Exception e) {
      return new Set<Id>();
    }
    return readable;
  }

  @SuppressWarnings(
    'PMD.ApexCRUDViolation'
  ) // system mode by design (see class comment)
  private static Map<String, Pricing_Place__c> placesByKey(
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

  /**
   * One stage's carriers. Quote groups set loadsQuoted or loadsMoved and the latest quote date; plan
   * legs add distinct leg loads per carrier (a leg is a Carrier row whose load is not Cancelled and
   * whose carrier is set and not intercompany), dated by the plan's customer load (R84). leads()
   * adds the leg loads to loadsMoved and lists the sources in the order Quote, Split leg.
   */
  private class Tally {
    Map<Id, CarrierLeadResult.Lead> byCarrier = new Map<Id, CarrierLeadResult.Lead>();
    Set<Id> quoteCarriers = new Set<Id>();
    Map<Id, Set<Id>> legLoads = new Map<Id, Set<Id>>();
    Boolean truncated = false;
    // A 51st carrier group marks stage 1 incomplete (it shows every carrier), never stage 2, which
    // shows its top 10 without the note although that top 10 can be wrong: the moved count keeps the
    // 50 carriers with the most accepted-quote loads, so a carrier cut from it counts only its split
    // legs as loads moved and can fall out of the top 10; and on a lane with fewer than 10 movers the
    // rest of the top 10 comes from the 50 carriers with the most loads quoted.
    Boolean groupCapped = false;
    Boolean stopped = false;

    Boolean hasLeads() {
      return !byCarrier.isEmpty();
    }

    Boolean outOfRows() {
      return outOfRows(0);
    }

    /** Stops the stage, marked incomplete, when rowsAhead more query rows would leave fewer than rowReserve. */
    Boolean outOfRows(Integer rowsAhead) {
      if (Limits.getQueryRows() + rowsAhead > rowLimit() - rowReserve) {
        stopped = true;
        truncated = true;
      }
      return stopped;
    }

    void addGroups(List<AggregateResult> groups, Boolean moved) {
      if (groups.size() > LaneQueries.GROUP_LIMIT) {
        groupCapped = true;
        groups.remove(groups.size() - 1);
      }
      for (AggregateResult g : groups) {
        CarrierLeadResult.Lead entry = leadFor(
          (Id) g.get('rtms__Vendor__c'),
          (String) g.get('vname'),
          (Boolean) g.get('bl')
        );
        Integer loads = (Integer) g.get('loads');
        // Every moved load is also a quoted load. The two counts are cut at 50 groups separately,
        // so a carrier the moved count found but the quoted count cut still shows at least as many
        // loads quoted as quote loads moved.
        if (moved) {
          entry.loadsMoved = loads;
        }
        entry.loadsQuoted = Math.max(entry.loadsQuoted, loads);
        quoteCarriers.add(entry.carrierId);
        Datetime seen = (Datetime) g.get('lastSeen');
        see(entry, seen?.date());
      }
    }

    void addPlans(List<rtms__FreightPlan__c> plans, Set<Id> intercompany) {
      if (plans.size() >= PLAN_LIMIT) {
        truncated = true;
      }
      for (rtms__FreightPlan__c plan : plans) {
        addPlan(plan, intercompany);
      }
    }

    // A for loop over the child rows: reading a child list of more than 200 rows directly throws.
    void addPlan(rtms__FreightPlan__c plan, Set<Id> intercompany) {
      Date customerDate;
      List<rtms__FreightPlanLoad__c> legs = new List<rtms__FreightPlanLoad__c>();
      for (rtms__FreightPlanLoad__c row : plan.rtms__Freight_Plan_Loads__r) {
        if (row.rtms__Type__c == 'Customer') {
          customerDate = row.rtms__Load__r?.CreatedDate?.date();
        } else if (isLeg(row, intercompany)) {
          legs.add(row);
        }
      }
      for (rtms__FreightPlanLoad__c row : legs) {
        CarrierLeadResult.Lead entry = leadFor(
          row.rtms__Load__r.rtms__Carrier__c,
          row.rtms__Load__r.rtms__Carrier__r?.Name,
          row.rtms__Load__r.rtms__Carrier__r?.Black_List__c
        );
        if (!legLoads.containsKey(entry.carrierId)) {
          legLoads.put(entry.carrierId, new Set<Id>());
        }
        legLoads.get(entry.carrierId).add(row.rtms__Load__c);
        see(entry, customerDate);
      }
    }

    Boolean isLeg(rtms__FreightPlanLoad__c row, Set<Id> intercompany) {
      Id carrierId = row.rtms__Load__r?.rtms__Carrier__c;
      return row.rtms__Type__c == 'Carrier' &&
        carrierId != null &&
        !intercompany.contains(carrierId) &&
        row.rtms__Load__r.rtms__Load_Status__c != 'Cancelled';
    }

    CarrierLeadResult.Lead leadFor(
      Id carrierId,
      String carrierName,
      Boolean blacklisted
    ) {
      CarrierLeadResult.Lead existing = byCarrier.get(carrierId);
      if (existing == null) {
        existing = new CarrierLeadResult.Lead();
        existing.carrierId = carrierId;
        existing.name = carrierName;
        byCarrier.put(carrierId, existing);
      }
      existing.blacklisted = existing.blacklisted || blacklisted == true;
      return existing;
    }

    void see(CarrierLeadResult.Lead entry, Date day) {
      if (day != null && (entry.lastSeen == null || day > entry.lastSeen)) {
        entry.lastSeen = day;
      }
    }

    List<CarrierLeadResult.Lead> leads() {
      List<CarrierLeadResult.Lead> out = new List<CarrierLeadResult.Lead>();
      for (CarrierLeadResult.Lead entry : byCarrier.values()) {
        entry.sources = new List<String>();
        if (quoteCarriers.contains(entry.carrierId)) {
          entry.sources.add(CarrierLeadResult.SOURCE_QUOTE);
        }
        Set<Id> legs = legLoads.get(entry.carrierId);
        if (legs != null) {
          entry.loadsMoved += legs.size();
          entry.sources.add(CarrierLeadResult.SOURCE_SPLIT_LEG);
        }
        out.add(entry);
      }
      return out;
    }
  }

  /**
   * Stage 1 (thenQuoted true): loads moved, loads quoted, last seen (a missing date last), name.
   * Stage 2 (thenQuoted false): loads moved, last seen, name (R82).
   */
  private class LeadOrder implements Comparator<CarrierLeadResult.Lead> {
    private Boolean thenQuoted;

    LeadOrder(Boolean thenQuoted) {
      this.thenQuoted = thenQuoted;
    }

    public Integer compare(CarrierLeadResult.Lead a, CarrierLeadResult.Lead b) {
      if (a.loadsMoved != b.loadsMoved) {
        return b.loadsMoved - a.loadsMoved;
      }
      if (thenQuoted && a.loadsQuoted != b.loadsQuoted) {
        return b.loadsQuoted - a.loadsQuoted;
      }
      if (a.lastSeen != b.lastSeen) {
        return byDateDescending(a.lastSeen, b.lastSeen);
      }
      return (a.name == null ? '' : a.name.toLowerCase())
        .compareTo(b.name == null ? '' : b.name.toLowerCase());
    }

    private Integer byDateDescending(Date a, Date b) {
      if (a == null) {
        return 1;
      }
      if (b == null) {
        return -1;
      }
      return a > b ? -1 : 1;
    }
  }
}
