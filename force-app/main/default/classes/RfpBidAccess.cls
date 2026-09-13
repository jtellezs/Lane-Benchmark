/**
 * The one place the RFP workbench crosses from user mode into system mode for bids. Since
 * phase 6 Benchmark_Rate__c is Private and an RFP follows its customer account, so a bid
 * recorded by a colleague on a lane you can read must still be yours to see and change. Rule:
 * a user who can read a lane can read, create, edit and delete every bid on that lane. The
 * class runs without sharing on purpose: the lane and project checks are `WITH USER_MODE`
 * queries, and user mode enforces the running user's sharing whatever the class keyword says,
 * so sharing still decides which lanes count; the bid reads and writes then run in system mode
 * past sharing, restricted to those lanes, because a Private bid recorded by a colleague must be
 * visible and editable to anyone who can read its lane. Lane Benchmark (BidSearchService) does
 * not use this class: it reads every bid in system mode on purpose and shows no customer.
 */
public without sharing class RfpBidAccess {
  public static final String BID_FIELDS =
    'Id, Name, RFP_Lane__c, RFP_Project__c, Carrier__c, Carrier_Name__c, Carrier_Display__c, ' +
    'Contact_Name__c, Contact_Email__c, Contact_Phone__c, Rate__c, CurrencyIsoCode, ' +
    'Fuel_Surcharge__c, FSC_Included__c, Transit_Days__c, Valid_From__c, Expires_On__c, ' +
    'Status__c, Notes__c, City_Lane__c, State_Lane__c, Zip3_Lane__c';
  public static final String LANE_UNAVAILABLE = 'This lane is not available.';

  /** The subset of laneIds the running user can read; empty when they cannot read lanes at all. */
  public static Set<Id> visibleLanes(Set<Id> laneIds) {
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

  /** The bids among bidIds whose lane the user can read, in the order of bidIds. */
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
   * Takes the Selected_Bid__c values off lane updates about to run in user mode and returns them
   * as bare (Id, Selected_Bid__c) records to apply afterwards: a user-mode update that names a
   * colleague's Private bid fails the cross-reference check even though the lane rule grants the
   * bid. Throws LaneSearchException("That bid is not available.") when any named bid is not
   * readable through the rule, before any DML.
   */
  public static List<RFP_Lane__c> detachSelectedBids(
    List<RFP_Lane__c> updates
  ) {
    return SELECTED.detach(updates);
  }

  /** Writes the detached Selected_Bid__c values back in system mode, each lane first proved
   * readable in user mode (Gate.lanes, the gate assertLaneVisible uses, asked once for all of
   * them); FLS on RFP_Lane__c.Selected_Bid__c checked once. */
  public static void applySelectedBids(List<RFP_Lane__c> deferred) {
    SELECTED.apply(deferred);
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

  /** Inserts bids on visible lanes only (a bid without a lane is refused) and returns them reloaded in input order. */
  public static List<Benchmark_Rate__c> insertBids(
    List<Benchmark_Rate__c> bids
  ) {
    GATE.create();
    Set<Id> laneIds = new Set<Id>();
    for (Benchmark_Rate__c bid : bids) {
      if (bid.RFP_Lane__c == null) {
        throw new LaneSearchException('A bid needs a lane.');
      }
      laneIds.add(bid.RFP_Lane__c);
    }
    if (!visibleLanes(laneIds).containsAll(laneIds)) {
      throw new LaneSearchException(LANE_UNAVAILABLE);
    }
    List<Benchmark_Rate__c> clean = Security.stripInaccessible(
        AccessType.CREATABLE,
        bids
      )
      .getRecords();
    systemInsert(clean);
    List<Id> ids = new List<Id>();
    for (Benchmark_Rate__c bid : clean) {
      ids.add(bid.Id);
    }
    return bidsByIds(ids);
  }

  /** Updates one bid whose stored lane the user can read; a lane change is refused only when the caller sets a different lane. */
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
      bid.isSet('RFP_Lane__c') &&
      bid.RFP_Lane__c != null &&
      bid.RFP_Lane__c != stored[0].RFP_Lane__c;
    if (moves) {
      throw new LaneSearchException('A bid cannot move to another lane.');
    }
    Benchmark_Rate__c clean = (Benchmark_Rate__c) Security.stripInaccessible(
        AccessType.UPDATABLE,
        new List<Benchmark_Rate__c>{ bid }
      )
      .getRecords()[0];
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
   * does not count toward RfpBidAccess's cyclomatic complexity budget. */
  private class Gate {
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
  }

  /** Row-filtering helpers, kept out of the outer class for the same complexity-budget reason
   * as Gate above. */
  private class Rows {
    /** The bids among byId whose lane the user can read, in the order of ids. */
    private List<Benchmark_Rate__c> keepVisible(
      List<Id> ids,
      Map<Id, Benchmark_Rate__c> byId
    ) {
      Set<Id> laneIds = new Set<Id>();
      for (Benchmark_Rate__c bid : byId.values()) {
        if (bid.RFP_Lane__c != null) {
          laneIds.add(bid.RFP_Lane__c);
        }
      }
      Set<Id> lanes = RfpBidAccess.visibleLanes(laneIds);
      List<Benchmark_Rate__c> kept = new List<Benchmark_Rate__c>();
      for (Id id : ids) {
        Benchmark_Rate__c bid = byId.get(id);
        if (bid != null && lanes.contains(bid.RFP_Lane__c)) {
          kept.add(bid);
        }
      }
      return kept;
    }

    /** Field-level security on the way out: only the fields the caller may read. */
    private List<Benchmark_Rate__c> readable(List<Benchmark_Rate__c> bids) {
      return Security.stripInaccessible(AccessType.READABLE, bids).getRecords();
    }
  }

  /** The selected-bid stitching of attachSelectedBids, kept out of the outer class for the same
   * complexity-budget reason as Gate above. */
  private class Selected {
    private List<RFP_Lane__c> attach(List<RFP_Lane__c> lanes) {
      // A Set: two lanes can share one selected bid, and bidsByIds answers per input Id.
      Set<Id> bidIds = selectedIds(lanes);
      // Nothing selected: no bid is read at all, so a user who can read lanes but no bid keeps
      // their lanes instead of meeting Gate.read()'s refusal. An empty list lands here too.
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

    /** The Selected_Bid__c values of updates, lifted out and nulled on the update records. */
    private List<RFP_Lane__c> detach(List<RFP_Lane__c> updates) {
      List<RFP_Lane__c> deferred = new List<RFP_Lane__c>();
      Set<Id> bidIds = selectedIds(updates);
      for (RFP_Lane__c u : updates) {
        if (u.Selected_Bid__c != null) {
          deferred.add(
            new RFP_Lane__c(Id = u.Id, Selected_Bid__c = u.Selected_Bid__c)
          );
          // Left isSet as null on purpose: a user switching back to a manual cost must still
          // clear the field in the user-mode update that follows. A caller who means null
          // defers nothing, so nothing is written back either.
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

    /** The bidIds the lane rule grants the caller. */
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
