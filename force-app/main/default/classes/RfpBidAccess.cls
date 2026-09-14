/**
 * The one place the RFP workbench crosses from user mode into system mode for bids. Since
 * phase 6 Benchmark_Rate__c is Private and an RFP follows its customer account, so a bid
 * recorded by a colleague on a lane you can read must still be yours to see and change. Rule:
 * a user who can read a lane can read, create, edit and delete every bid on that lane. The
 * class runs without sharing on purpose: the lane and project checks are `WITH USER_MODE`
 * queries, and user mode enforces the running user's sharing whatever the class keyword says,
 * so sharing still decides which lanes count; the bid reads and writes then run in system mode
 * past sharing, restricted to those lanes, because a Private bid recorded by a colleague must be
 * visible and editable to anyone who can read its lane. A bid whose lane is gone (RFP_Lane__c is a
 * set-null lookup; RFP_Project__c stays) is granted through its project, read in user mode, which
 * adds no access because lanes are Controlled by Parent. A bid save that names a Carrier__c
 * account is checked in user mode too (Gate.carriers), because the system-mode DML skips the
 * sharing check a lookup target gets. Lane Benchmark (BidSearchService) does not use this class:
 * it reads every bid in system mode on purpose and shows no customer.
 */
public without sharing class RfpBidAccess {
  public static final String BID_FIELDS =
    'Id, Name, RFP_Lane__c, RFP_Project__c, Carrier__c, Carrier_Name__c, Carrier_Display__c, ' +
    'Contact_Name__c, Contact_Email__c, Contact_Phone__c, Rate__c, CurrencyIsoCode, ' +
    'Fuel_Surcharge__c, FSC_Included__c, Transit_Days__c, Valid_From__c, Expires_On__c, ' +
    'Status__c, Notes__c, City_Lane__c, State_Lane__c, Zip3_Lane__c';
  public static final String LANE_UNAVAILABLE = 'This lane is not available.';
  public static final String CARRIER_UNAVAILABLE = 'That carrier is not available.';
  /**
   * The bid fields a caller may set. Everything else - OwnerId, RFP_Project__c, the lane keys, the
   * geolocations - is set only by BenchmarkRateTrigger or the platform and never reaches the
   * system-mode DML below, whatever FLS the caller happens to hold. RFP_Lane__c travels on insert
   * only (an update keeps the stored lane); Status__c is a formula, so it is not listed.
   */
  @TestVisible
  private static final List<String> SETTABLE_FIELDS = new List<String>{
    'Carrier__c',
    'Carrier_Name__c',
    'Contact_Name__c',
    'Contact_Email__c',
    'Contact_Phone__c',
    'Rate__c',
    'CurrencyIsoCode',
    'Fuel_Surcharge__c',
    'FSC_Included__c',
    'Transit_Days__c',
    'Valid_From__c',
    'Expires_On__c',
    'Notes__c',
    'Mode__c',
    'Equipment_Category__c',
    'Equipment_Type__c',
    'Hazmat__c'
  };

  /** The subset of laneIds the running user can read; empty when they cannot read lanes at all. */
  public static Set<Id> visibleLanes(Set<Id> laneIds) {
    return ROWS.visibleLanes(laneIds);
  }

  public static void assertLaneVisible(Id laneId) {
    GATE.lanes(new Set<Id>{ laneId });
  }

  /** Every bid on the visible lanes among laneIds, cheapest first, readable fields only. */
  public static List<Benchmark_Rate__c> bidsOfLanes(Set<Id> laneIds) {
    GATE.read();
    Set<Id> lanes = visibleLanes(laneIds);
    if (lanes.isEmpty()) {
      return new List<Benchmark_Rate__c>();
    }
    return ROWS.readable(
      systemQuery(
        'RFP_Lane__c IN :lanes ORDER BY Rate__c, Id',
        new Map<String, Object>{ 'lanes' => lanes }
      )
    );
  }

  /**
   * The bids among bidIds the rule grants the user - through their lane, or through their project
   * once their lane is gone - in the order of bidIds.
   */
  public static List<Benchmark_Rate__c> bidsByIds(List<Id> bidIds) {
    GATE.read();
    if (bidIds == null || bidIds.isEmpty()) {
      return new List<Benchmark_Rate__c>();
    }
    Map<Id, Benchmark_Rate__c> byId = new Map<Id, Benchmark_Rate__c>(
      systemQuery(
        'Id IN :bidIds',
        new Map<String, Object>{ 'bidIds' => bidIds }
      )
    );
    return ROWS.readable(ROWS.keepVisible(bidIds, byId));
  }

  /**
   * Fills lane.Selected_Bid__r on lanes the caller has just read in user mode. A user-mode
   * parent traversal to a Private bid recorded by someone else comes back null; the lane panel,
   * the table and the export need the selected bid's carrier, and the lane rule grants it.
   */
  public static List<RFP_Lane__c> attachSelectedBids(List<RFP_Lane__c> lanes) {
    return SELECTED.attach(lanes);
  }

  /**
   * Takes the CHANGED Selected_Bid__c values off lane updates about to run in user mode and returns
   * them as bare (Id, Selected_Bid__c) records to apply afterwards: a user-mode update that names a
   * colleague's Private bid fails the cross-reference check even though the lane rule grants the
   * bid. A value equal to the one the lane already stores (read once, in user mode) stays on the
   * update untouched and is neither checked nor deferred: rewriting an unchanged lookup runs no
   * cross-reference check, and a bid carried forward (an inline edit, pricingCopy) may have lost
   * both its lane and its project outside the workbench, which the rule no longer grants. Throws
   * LaneSearchException("That bid is not available.") when any changed bid is not readable through
   * the rule, before any DML.
   */
  public static List<RFP_Lane__c> detachSelectedBids(
    List<RFP_Lane__c> updates
  ) {
    return SELECTED.detach(updates);
  }

  /**
   * Writes the detached Selected_Bid__c values back in system mode, each lane first proved
   * readable in user mode (Gate.lanes, the gate assertLaneVisible uses, asked once for all of
   * them); FLS on RFP_Lane__c.Selected_Bid__c checked once.
   *
   * Only for records returned by detachSelectedBids, which has already proved every bid readable
   * through the rule: this method checks the lanes, not the bids, and re-checking them here would
   * cost two more queries on top of the one the lane gate already spends.
   */
  public static void applySelectedBids(List<RFP_Lane__c> deferred) {
    SELECTED.apply(deferred);
  }

  /**
   * The same write, for a caller whose user-mode update collected per-row results: only the
   * deferred lanes whose own update succeeded are applied. A lane the pricing write refused
   * (a validation, a concurrent edit) keeps the bid it had, instead of showing the new bid's
   * carrier against its old cost.
   */
  public static void applySelectedBids(
    List<RFP_Lane__c> deferred,
    List<Database.SaveResult> results
  ) {
    applySelectedBids(SELECTED.written(deferred, results));
  }

  /** Bid counts per project, for the projects among projectIds the user can read. */
  public static Map<Id, Integer> bidCountsByProject(Set<Id> projectIds) {
    GATE.read();
    Map<Id, Integer> counts = new Map<Id, Integer>();
    if (projectIds == null || projectIds.isEmpty()) {
      return counts;
    }
    Set<Id> projects = new Map<Id, RFP_Project__c>(
        [
          SELECT Id
          FROM RFP_Project__c
          WHERE Id IN :projectIds
          WITH USER_MODE
        ]
      )
      .keySet();
    if (projects.isEmpty()) {
      return counts;
    }
    for (AggregateResult ar : countQuery(projects)) {
      counts.put((Id) ar.get('pid'), (Integer) ar.get('n'));
    }
    return counts;
  }

  /**
   * Inserts bids on visible lanes only (a bid without a lane is refused) and returns them reloaded
   * in input order. Only SETTABLE_FIELDS and RFP_Lane__c travel, and the lane checks run on the
   * records actually inserted - after the CREATABLE strip, so a stripped lane is refused too. Every
   * Carrier__c account named must be readable in user mode (Gate.carriers).
   */
  public static List<Benchmark_Rate__c> insertBids(
    List<Benchmark_Rate__c> bids
  ) {
    GATE.create();
    List<Benchmark_Rate__c> clean = Security.stripInaccessible(
        AccessType.CREATABLE,
        ROWS.settable(bids, true)
      )
      .getRecords();
    GATE.lanesOf(clean);
    GATE.carriers(clean, null);
    systemInsert(clean);
    List<Id> ids = new List<Id>();
    for (Benchmark_Rate__c bid : clean) {
      ids.add(bid.Id);
    }
    return bidsByIds(ids);
  }

  /**
   * Updates one bid whose stored lane the user can read. The lane is never written: a caller who
   * sets RFP_Lane__c to anything but the stored lane (null included) is refused. Only
   * SETTABLE_FIELDS travel. A Carrier__c other than the stored one must be readable in user mode;
   * the stored carrier is not re-checked, so a colleague can edit a bid whose carrier they cannot read.
   */
  public static Benchmark_Rate__c updateBid(Benchmark_Rate__c bid) {
    GATE.edit();
    List<Benchmark_Rate__c> stored = bid.Id == null
      ? new List<Benchmark_Rate__c>()
      : systemQuery(
          'Id = :bidId',
          new Map<String, Object>{ 'bidId' => bid.Id }
        );
    if (stored.isEmpty() || stored[0].RFP_Lane__c == null) {
      throw new LaneSearchException(LANE_UNAVAILABLE);
    }
    assertLaneVisible(stored[0].RFP_Lane__c);
    Boolean moves =
      ROWS.posted(bid).contains('rfp_lane__c') &&
      bid.RFP_Lane__c != stored[0].RFP_Lane__c;
    if (moves) {
      throw new LaneSearchException('A bid cannot move to another lane.');
    }
    Benchmark_Rate__c clean = (Benchmark_Rate__c) Security.stripInaccessible(
        AccessType.UPDATABLE,
        ROWS.settable(new List<Benchmark_Rate__c>{ bid }, false)
      )
      .getRecords()[0];
    GATE.carriers(new List<Benchmark_Rate__c>{ clean }, stored[0].Carrier__c);
    systemUpdate(clean);
    return bidsByIds(new List<Id>{ bid.Id })[0];
  }

  /** Deletes every bid on the visible lanes among laneIds; partial success, results returned. */
  public static List<Database.DeleteResult> deleteBidsOfLanes(Set<Id> laneIds) {
    GATE.remove();
    List<Benchmark_Rate__c> bids = bidsOfLanes(laneIds);
    if (bids.isEmpty()) {
      return new List<Database.DeleteResult>();
    }
    return systemDelete(bids);
  }

  // Single instances: Apex inner classes cannot hold static members, so the helper methods
  // below are instance methods called through one shared instance per class.
  private static final Gate GATE = new Gate();
  private static final Rows ROWS = new Rows();
  private static final Selected SELECTED = new Selected();

  /** Object-permission gates for Benchmark_Rate__c, kept in their own class so their branching
   * does not count toward RfpBidAccess's cyclomatic complexity budget. Declared like Rows: its one
   * query (the carrier accounts) is `WITH USER_MODE`, so the running user's sharing decides. */
  private without sharing class Gate {
    private void read() {
      if (!Schema.SObjectType.Benchmark_Rate__c.isAccessible()) {
        throw new LaneSearchException('You cannot read bids.');
      }
    }
    private void create() {
      if (!Schema.SObjectType.Benchmark_Rate__c.isCreateable()) {
        throw new LaneSearchException('You cannot create bids.');
      }
    }
    private void edit() {
      if (!Schema.SObjectType.Benchmark_Rate__c.isUpdateable()) {
        throw new LaneSearchException('You cannot edit bids.');
      }
    }
    // Named remove(), not delete(): delete is an Apex reserved word and cannot name a method.
    private void remove() {
      if (!Schema.SObjectType.Benchmark_Rate__c.isDeletable()) {
        throw new LaneSearchException('You cannot delete bids.');
      }
    }
    /** The record gate: every lane in laneIds must be readable, sharing deciding, in one query
     * however many there are (applySelectedBids passes up to 200). A null Id is never visible. */
    private void lanes(Set<Id> laneIds) {
      if (!RfpBidAccess.visibleLanes(laneIds).containsAll(laneIds)) {
        throw new LaneSearchException(RfpBidAccess.LANE_UNAVAILABLE);
      }
    }
    /** The insert gate, on the records about to be inserted: each names a lane (one the CREATABLE
     * strip removed reads as none), and every lane is readable. */
    private void lanesOf(List<Benchmark_Rate__c> bids) {
      Set<Id> laneIds = new Set<Id>();
      for (Benchmark_Rate__c bid : bids) {
        Id laneId = RfpBidAccess.ROWS.posted(bid).contains('rfp_lane__c')
          ? bid.RFP_Lane__c
          : null;
        if (laneId == null) {
          throw new LaneSearchException('A bid needs a lane.');
        }
        laneIds.add(laneId);
      }
      lanes(laneIds);
    }
    /** The carrier gate, on the records about to be written: every Carrier__c account they name
     * must come back from a user-mode query. The system-mode DML skips the sharing check the
     * platform makes on a lookup target, and the reload's Carrier_Display__c would show the
     * account's name. storedCarrier is the carrier an update already holds (null on insert); it is
     * not re-checked. One query, none when no record names a new carrier. */
    private void carriers(List<Benchmark_Rate__c> bids, Id storedCarrier) {
      Set<Id> carrierIds = newCarriers(bids, storedCarrier);
      Boolean refused =
        !carrierIds.isEmpty() &&
        !readableAccounts(carrierIds).containsAll(carrierIds);
      if (refused) {
        throw new LaneSearchException(RfpBidAccess.CARRIER_UNAVAILABLE);
      }
    }
    /** The non-null Carrier__c values populated on bids, other than storedCarrier. */
    private Set<Id> newCarriers(
      List<Benchmark_Rate__c> bids,
      Id storedCarrier
    ) {
      Set<Id> carrierIds = new Set<Id>();
      for (Benchmark_Rate__c bid : bids) {
        Id carrierId = RfpBidAccess.ROWS.posted(bid).contains('carrier__c')
          ? bid.Carrier__c
          : null;
        if (carrierId != null && carrierId != storedCarrier) {
          carrierIds.add(carrierId);
        }
      }
      return carrierIds;
    }
    /** The accounts among accountIds the caller can read in user mode, sharing deciding; none for
     * a caller with no read on Account at all (the query throws), so the carrier is refused. */
    private Set<Id> readableAccounts(Set<Id> accountIds) {
      try {
        return new Map<Id, Account>(
            [SELECT Id FROM Account WHERE Id IN :accountIds WITH USER_MODE]
          )
          .keySet();
      } catch (QueryException e) {
        return new Set<Id>();
      }
    }
  }

  /** Row-filtering helpers, kept out of the outer class for the same complexity-budget reason
   * as Gate above. Declared like the outer class: the lane and project queries below are
   * `WITH USER_MODE`, so the running user's sharing decides what comes back whatever the keyword
   * says. */
  private without sharing class Rows {
    /** The subset of laneIds the running user can read; sharing decides, in one query. */
    private Set<Id> visibleLanes(Set<Id> laneIds) {
      Set<Id> visible = new Set<Id>();
      Boolean nothingToAsk =
        laneIds == null ||
        laneIds.isEmpty() ||
        !Schema.SObjectType.RFP_Lane__c.isAccessible();
      if (nothingToAsk) {
        return visible;
      }
      for (RFP_Lane__c lane : [
        SELECT Id
        FROM RFP_Lane__c
        WHERE Id IN :laneIds
        WITH USER_MODE
      ]) {
        visible.add(lane.Id);
      }
      return visible;
    }

    /**
     * The bids among byId the user is granted, in the order of ids: a bid on a lane through that
     * lane; a bid whose lane is gone through its project; a bid with neither, to nobody. The project
     * query runs only when such a bid is present.
     */
    private List<Benchmark_Rate__c> keepVisible(
      List<Id> ids,
      Map<Id, Benchmark_Rate__c> byId
    ) {
      Set<Id> laneIds = new Set<Id>();
      Set<Id> projectIds = new Set<Id>();
      for (Benchmark_Rate__c bid : byId.values()) {
        if (bid.RFP_Lane__c != null) {
          laneIds.add(bid.RFP_Lane__c);
        } else if (bid.RFP_Project__c != null) {
          projectIds.add(bid.RFP_Project__c);
        }
      }
      // Lane and project Ids never collide, so one set holds both grants; each bid is looked up by
      // its lane, or by its project only when it has no lane, so a readable project never grants a
      // bid whose lane is still there but hidden. A bid with neither looks up null, never held.
      Set<Id> granted = RfpBidAccess.visibleLanes(laneIds);
      granted.addAll(readableProjects(projectIds));
      List<Benchmark_Rate__c> kept = new List<Benchmark_Rate__c>();
      for (Id id : ids) {
        Benchmark_Rate__c bid = byId.get(id);
        if (
          bid != null && granted.contains(bid.RFP_Lane__c ?? bid.RFP_Project__c)
        ) {
          kept.add(bid);
        }
      }
      return kept;
    }

    /** The projects among projectIds the caller can read in user mode, sharing deciding: no query
     * for an empty set, and none readable for a caller with no read on RFP_Project__c (the query
     * throws). */
    private Set<Id> readableProjects(Set<Id> projectIds) {
      if (projectIds.isEmpty()) {
        return new Set<Id>();
      }
      try {
        return new Map<Id, RFP_Project__c>(
            [
              SELECT Id
              FROM RFP_Project__c
              WHERE Id IN :projectIds
              WITH USER_MODE
            ]
          )
          .keySet();
      } catch (QueryException e) {
        return new Set<Id>();
      }
    }

    /** Field-level security on the way out: only the fields the caller may read. */
    private List<Benchmark_Rate__c> readable(List<Benchmark_Rate__c> bids) {
      return Security.stripInaccessible(AccessType.READABLE, bids).getRecords();
    }

    /** Fresh bids carrying only the SETTABLE_FIELDS populated on bids, plus RFP_Lane__c on insert or
     * the Id on update; an update never writes null over a field the caller left out. */
    private List<Benchmark_Rate__c> settable(
      List<Benchmark_Rate__c> bids,
      Boolean inserting
    ) {
      List<String> fields = new List<String>(RfpBidAccess.SETTABLE_FIELDS);
      if (inserting) {
        fields.add('RFP_Lane__c');
      }
      List<Benchmark_Rate__c> copies = new List<Benchmark_Rate__c>();
      for (Benchmark_Rate__c bid : bids) {
        Benchmark_Rate__c copy = new Benchmark_Rate__c();
        if (!inserting) {
          copy.Id = bid.Id;
        }
        Set<String> posted = posted(bid);
        for (String field : fields) {
          if (posted.contains(field.toLowerCase())) {
            copy.put(field, bid.get(field));
          }
        }
        copies.add(copy);
      }
      return copies;
    }

    /**
     * The lower-cased names of the fields populated on bid: set in memory (null included) or
     * queried. Not isSet: on a record JSON.deserialize built, isSet reports fields the JSON never
     * named, which would copy a null checkbox into the insert and read an absent lane as a move.
     */
    private Set<String> posted(SObject bid) {
      Set<String> names = new Set<String>();
      for (String name : bid.getPopulatedFieldsAsMap().keySet()) {
        names.add(name.toLowerCase());
      }
      return names;
    }
  }

  /** The selected-bid stitching of attachSelectedBids, kept out of the outer class for the same
   * complexity-budget reason as Gate above. Declared like Rows: its one query (the stored
   * selections) is `WITH USER_MODE`, so the running user's sharing decides what comes back. */
  private without sharing class Selected {
    private List<RFP_Lane__c> attach(List<RFP_Lane__c> lanes) {
      // A Set: two lanes can share one selected bid, and bidsByIds answers per input Id.
      Set<Id> bidIds = selectedIds(lanes);
      // Nothing selected (an empty list included): return before bidsByIds, so lanes that name no
      // bid cost no query. Read on Benchmark_Rate__c is still required the moment one lane does
      // name a bid - bidsByIds opens with Gate.read() and refuses a caller who has none.
      if (bidIds.isEmpty()) {
        return lanes;
      }
      Map<Id, Benchmark_Rate__c> byId = new Map<Id, Benchmark_Rate__c>(
        RfpBidAccess.bidsByIds(new List<Id>(bidIds))
      );
      for (RFP_Lane__c lane : lanes) {
        Benchmark_Rate__c bid = byId.get(lane.Selected_Bid__c);
        if (bid != null) {
          lane.Selected_Bid__r = bid;
        }
      }
      return lanes;
    }

    /** The changed Selected_Bid__c values of updates, lifted out and nulled on the update records;
     * a null or a value equal to the stored one stays on the update as posted. */
    private List<RFP_Lane__c> detach(List<RFP_Lane__c> updates) {
      Map<Id, Id> stored = storedSelections(updates);
      List<RFP_Lane__c> deferred = new List<RFP_Lane__c>();
      Set<Id> bidIds = new Set<Id>();
      for (RFP_Lane__c u : updates) {
        Boolean changed =
          u.Selected_Bid__c != null &&
          u.Selected_Bid__c != stored.get(u.Id);
        if (changed) {
          bidIds.add(u.Selected_Bid__c);
          deferred.add(
            new RFP_Lane__c(Id = u.Id, Selected_Bid__c = u.Selected_Bid__c)
          );
          // Left isSet as null on purpose, as a caller who means null leaves it: a user switching
          // back to a manual cost must still clear the field in the user-mode update that follows.
          u.Selected_Bid__c = null;
        }
      }
      Boolean refused =
        !bidIds.isEmpty() && !grantedBids(bidIds).containsAll(bidIds);
      if (refused) {
        throw new LaneSearchException('That bid is not available.');
      }
      return deferred;
    }

    /** Selected_Bid__c as stored, for the updates that name a bid, in one user-mode query (none
     * when no update names one). A lane the user cannot read comes back absent, so its value
     * counts as changed and goes through the rule. */
    private Map<Id, Id> storedSelections(List<RFP_Lane__c> updates) {
      Map<Id, Id> stored = new Map<Id, Id>();
      Set<Id> laneIds = new Set<Id>();
      for (RFP_Lane__c u : updates) {
        if (u.Selected_Bid__c != null && u.Id != null) {
          laneIds.add(u.Id);
        }
      }
      if (laneIds.isEmpty()) {
        return stored;
      }
      for (RFP_Lane__c lane : [
        SELECT Id, Selected_Bid__c
        FROM RFP_Lane__c
        WHERE Id IN :laneIds
        WITH USER_MODE
      ]) {
        stored.put(lane.Id, lane.Selected_Bid__c);
      }
      return stored;
    }

    /** Writes the detached values back past sharing, once their lanes are proved readable. */
    private void apply(List<RFP_Lane__c> deferred) {
      if (deferred.isEmpty()) {
        return;
      }
      RfpBidAccess.GATE.lanes(new Map<Id, RFP_Lane__c>(deferred).keySet());
      if (
        !Schema.SObjectType.RFP_Lane__c.fields.Selected_Bid__c.isUpdateable()
      ) {
        throw new LaneSearchException('You cannot change the selected bid.');
      }
      RfpBidAccess.systemUpdateLanes(deferred);
    }

    /** The deferred lanes whose Id came back on a successful SaveResult. */
    private List<RFP_Lane__c> written(
      List<RFP_Lane__c> deferred,
      List<Database.SaveResult> results
    ) {
      Set<Id> saved = new Set<Id>();
      for (Database.SaveResult r : results) {
        if (r.isSuccess()) {
          saved.add(r.getId());
        }
      }
      List<RFP_Lane__c> kept = new List<RFP_Lane__c>();
      for (RFP_Lane__c lane : deferred) {
        if (saved.contains(lane.Id)) {
          kept.add(lane);
        }
      }
      return kept;
    }

    /** The distinct non-null Selected_Bid__c values of lanes. */
    private Set<Id> selectedIds(List<RFP_Lane__c> lanes) {
      Set<Id> bidIds = new Set<Id>();
      for (RFP_Lane__c lane : lanes) {
        if (lane.Selected_Bid__c != null) {
          bidIds.add(lane.Selected_Bid__c);
        }
      }
      return bidIds;
    }

    /** The bidIds the rule grants the caller (bidsByIds). */
    private Set<Id> grantedBids(Set<Id> bidIds) {
      return new Map<Id, Benchmark_Rate__c>(
          RfpBidAccess.bidsByIds(new List<Id>(bidIds))
        )
        .keySet();
    }
  }

  // System-mode SOQL and DML on purpose, and only here: every caller has just proved the lane
  // (or project) readable in user mode, object permissions are checked by Gate above, and the
  // rows pass through Security.stripInaccessible before they leave this class.
  @SuppressWarnings('PMD.ApexCRUDViolation')
  private static List<Benchmark_Rate__c> systemQuery(
    String whereClause,
    Map<String, Object> binds
  ) {
    return Database.queryWithBinds(
      'SELECT ' + BID_FIELDS + ' FROM Benchmark_Rate__c WHERE ' + whereClause,
      binds,
      AccessLevel.SYSTEM_MODE
    );
  }
  @SuppressWarnings('PMD.ApexCRUDViolation')
  private static List<AggregateResult> countQuery(Set<Id> projects) {
    return Database.queryWithBinds(
      'SELECT RFP_Project__c pid, COUNT(Id) n FROM Benchmark_Rate__c ' +
      'WHERE RFP_Project__c IN :projects GROUP BY RFP_Project__c',
      new Map<String, Object>{ 'projects' => projects },
      AccessLevel.SYSTEM_MODE
    );
  }
  @SuppressWarnings('PMD.ApexCRUDViolation')
  private static void systemInsert(List<Benchmark_Rate__c> bids) {
    Database.insert(bids, AccessLevel.SYSTEM_MODE);
  }
  @SuppressWarnings('PMD.ApexCRUDViolation')
  private static void systemUpdate(Benchmark_Rate__c bid) {
    Database.update(bid, AccessLevel.SYSTEM_MODE);
  }
  // System-mode lane DML on purpose, and only here: applySelectedBids has just proved every one
  // of these lanes readable in user mode and every named bid readable through the lane rule, and
  // it checks FLS on Selected_Bid__c itself; the records carry that one field and nothing else.
  @SuppressWarnings('PMD.ApexCRUDViolation')
  private static void systemUpdateLanes(List<RFP_Lane__c> lanes) {
    Database.update(lanes, AccessLevel.SYSTEM_MODE);
  }
  @SuppressWarnings('PMD.ApexCRUDViolation')
  private static List<Database.DeleteResult> systemDelete(
    List<Benchmark_Rate__c> bids
  ) {
    return Database.delete(bids, false, AccessLevel.SYSTEM_MODE);
  }
}
