# Phase 6 — RFP access follows the customer account

Date: 2026-09-13. Roadmap: phase 6, after phase 5 (help center) merged as
`5bb8ba2`. Changes the sharing model of the RFP objects built in phase 3 and
the Apex that reads and writes bids. Lane Benchmark's results are unchanged,
except that an RFP exclusion is honoured only for a project the caller can
read (R65).

## 1. Decisions from the brainstorm (2026-09-13)

| #   | Decision                                                                                                                                                                                                                       |
| --- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| D1  | Who can open an RFP project is decided by Salesforce access to its **customer account**: if you can see the account, you can open its RFPs from the account page or the RFP Tool list; if not, the RFP does not appear at all. |
| D2  | The lanes and bids inside every RFP keep feeding **Lane Benchmark for everyone**, as today: carrier, rate and expiry, never the customer or the RFP.                                                                           |
| D3  | The driver is confidentiality of customer names: RFPs are opened and worked from the account page (`rfpProjectsForAccount`), and Account is Private in this org.                                                               |
| D4  | Read access on the account is enough to **work** an RFP (create it, upload lanes, price, record bids); no Edit on the account is required.                                                                                     |
| D5  | Owner-based sharing (creator, managers, manual shares) and "hide only the customer name" were considered and rejected: the first hides RFPs from the sales rep on the account, the second still lists every deal.              |
| D6  | Production is still untouched (nothing since phase 0), so the relationship change costs nothing there; PostProduc converts in place.                                                                                           |

## 2. Today (measured in PostProduc, 2026-09-13)

| Object              | Sharing today                  | Relationship                                                                            |
| ------------------- | ------------------------------ | --------------------------------------------------------------------------------------- |
| `Account`           | Private                        |                                                                                         |
| `RFP_Project__c`    | Public Read/Write              | `Customer__c` lookup to Account, filtered to the Customer and New Customer record types |
| `RFP_Lane__c`       | Controlled by Parent (project) | `RFP_Project__c` master-detail, "write requires master Read" off                        |
| `Benchmark_Rate__c` | Public Read/Write              | `RFP_Lane__c` and `RFP_Project__c` lookups (set-null on delete)                         |

Every workbench class is `with sharing` and queries `WITH USER_MODE`; Lane
Benchmark (`LaneSearchService`, `BidSearchService`, `LaneBenchmarkController`)
runs `without sharing` in system mode on purpose and exposes no project or
customer field on a bid row. Data: 4 projects (all with a customer, one owner),
9 bids (all on a lane), one user holding `RFP_Tool_User` (the admin). Nothing
in the app or its metadata reads `RFP_Project__c.OwnerId`.

So the Lane Benchmark half of D2 already holds; what changes is who can open
an RFP and who can read a bid outside Lane Benchmark.

## 3. Data model and sharing

1. **`RFP_Project__c.Customer__c` becomes a master-detail to Account.**
   `relationshipOrder` 0, `reparentableMasterDetail` false,
   `writeRequiresMasterRead` **true** (D4), the existing lookup filter kept.
   The object's `sharingModel` becomes `ControlledByParent`. A detail object
   has no owner: the Owner field disappears from the project, which nothing
   uses. Converting a populated lookup to master-detail is a normal metadata
   deploy when every record has a value; the New project form already
   requires a customer (`rfpProjectList`, `required`), and
   `RfpProjectController.create` keeps validating it server-side.
2. **`RFP_Lane__c.RFP_Project__c`** gets `writeRequiresMasterRead` **true**,
   so a user who can only read the project (because they can only read the
   account) can still create, edit and delete lanes. Without it, D4 would
   hold for the project and fail one level down.
3. **`Benchmark_Rate__c`** `sharingModel` becomes **Private**. It cannot be a
   fourth master-detail level (Account → project → lane is already the
   maximum depth), so record access is not inherited; §4 grants it in code.
   Both lookups stay set-null so a deleted lane never deletes history that
   Lane Benchmark still uses. Consequence of the master-detail: deleting a
   customer account deletes its RFP projects and lanes (their bids survive
   with the lookups cleared); merging two accounts moves the RFPs to the
   surviving one.

Access chain after the change, for a user U and an RFP on account A:

```
U can read A  ──►  U can read the project (Controlled by Parent)
              ──►  U can read its lanes (Controlled by Parent)
              ──►  U can write project, lanes (write requires master Read)
              ──►  U can read/write the lanes' bids (Apex rule, §4)
U cannot read A ─► project, lanes and bids are absent for U everywhere in the
                   RFP Tool; Lane Benchmark still shows the bids' carrier,
                   rate and expiry (system mode), no customer, no RFP.
```

## 4. The bid access rule in the workbench

One rule: **if you can see a lane, you can see and change its bids**, whoever
recorded them. Implementation in a new `with sharing` helper
`RfpBidAccess`:

- `Set<Id> visibleLanes(Set<Id> laneIds)` — `SELECT Id FROM RFP_Lane__c WHERE
Id IN :laneIds WITH USER_MODE`; sharing decides which come back.
- `List<Benchmark_Rate__c> bidsOfLanes(Set<Id> laneIds, String fieldList)` —
  system-mode query restricted to the lanes that `visibleLanes` returned.
- `List<Benchmark_Rate__c> bidsByIds(Set<Id> bidIds)` — system-mode query,
  then drops every bid whose `RFP_Lane__c` is not in `visibleLanes`.
- `void assertLaneVisible(Id laneId)` — throws `RfpUserError` "This lane is not
  available." when the lane is not visible (the same wording family the
  workbench already uses for a missing record).

Field-level security stays enforced: every read strips through
`Security.stripInaccessible(AccessType.READABLE)` and every write through
`CREATABLE`/`UPDATABLE` before a system-mode `Database.insert/update/delete`
(`AccessLevel.SYSTEM_MODE`). Object permissions (`RFP_Tool_User` has create,
read, edit, delete on `Benchmark_Rate__c`) are checked once per call with
`Schema.SObjectType.Benchmark_Rate__c.isCreateable()` and friends. Lane
Benchmark's `BidSearchService` and the `BenchmarkRateTrigger` are untouched.

Sites that change (all currently `WITH USER_MODE` / `AccessLevel.USER_MODE`):

| Site                                        | Today                          | After                                                                                                              |
| ------------------------------------------- | ------------------------------ | ------------------------------------------------------------------------------------------------------------------ |
| `RfpBidController.getBids(laneId)`          | user-mode query by lane        | `assertLaneVisible(laneId)` then `bidsOfLanes`                                                                     |
| `BenchmarkRateService.save` / `saveAll`     | user-mode insert/update        | insert: the bid's lane must be visible; update: the stored bid's lane must be visible; system-mode DML after strip |
| `BenchmarkRateService.reload` / `reloadAll` | user-mode query by Id          | `bidsByIds`                                                                                                        |
| `RfpBulkService.deleteLanes`                | user-mode bid query + delete   | lanes already loaded in user mode (`load`), then `bidsOfLanes` + system-mode delete                                |
| `RfpBulkService` add carrier rate           | `saveAll`                      | unchanged call; `saveAll` applies the rule per lane                                                                |
| `RfpController.addBidCounts`                | user-mode aggregate by project | projects come from a user-mode query, so a system-mode aggregate over those project Ids                            |
| `RfpLaneController` / lane panel bid list   | via `RfpBidController.getBids` | unchanged                                                                                                          |

A bid recorded by user A on a lane of an RFP that user C can read (C has Read
on the account) is visible and editable by C. A bid on a lane the user cannot
see is refused with the user error above; the LWC already shows
`RfpUserError` messages as toasts.

## 5. What people see

- **RFP Tool list, account page component, deep links (`c__project`):** only
  RFPs whose account the user can read; the others are absent, no error. The
  project query is already user mode, so this needs no code.
- **Working an RFP with Read on the account:** create the project, upload,
  fix ends, load history, price, bulk actions, record bids, export, delete —
  everything, as today.
- **No access to the account:** the RFP does not exist for that user. If a
  colleague sends a link, the workbench behaves as for a deleted project
  (its existing not-found handling).
- **Admins** with View All Data see everything.
- **Lane Benchmark:** results unchanged for everyone (D2), except that an RFP
  exclusion (`excludeProjectId`) is honoured only for a project the caller can
  read (R65).
- **Guide:** a new FAQ entry "Who can see an RFP?" in English and French
  ("An RFP is visible to the people who can see its customer account. Ask
  the account owner or your admin for access to the account; Lane Benchmark
  shows every bid's carrier and rate to everyone, without the customer.") and
  one sentence in `rfp-projects` about the customer being required.

## 6. Deploy, migration, admin

- **PostProduc:** the routine full-manifest deploy converts the field and the
  sharing models; Salesforce recalculates sharing for the 4 projects, their
  lanes and the 9 bids. No data migration. Bids already carry
  `RFP_Project__c` and `RFP_Lane__c`.
- **Production:** none of these objects exist yet, so the go-live deploy
  creates them in their final shape; nothing to convert.
- **Admin task, documented in the README (not code):** pricers need at least
  Read on the customer accounts they price for — through the role hierarchy or
  an Account sharing rule to the pricing group. This is now the switch that
  governs RFP access. In PostProduc the admin user sees everything, so a
  manual check of the restriction needs a second login.
- **Permission sets:** unchanged object permissions. `RFP_Tool_User` keeps
  create/read/edit on the three RFP objects (`RFP_Project__c`, `RFP_Lane__c`,
  `Benchmark_Rate__c`) and delete on `RFP_Lane__c` and `Benchmark_Rate__c` only
  (no delete on `RFP_Project__c`), plus read on `Account` and read with View
  All on `Pricing_Place__c`; `Lane_Benchmark_User` keeps read on
  `Benchmark_Rate__c` (its queries run in system mode anyway).

## 7. Testing

- **Apex** (`RfpSecurityTest` extended, plus `RfpBidAccessTest`): three
  users created in the test, each with `RFP_Tool_User` and
  `Lane_Benchmark_User`; account X owned by user A.
  - A: creates the RFP on X, a lane, a bid — full path succeeds.
  - B (no share on X): project list empty, `projectsForAccount(X)` empty,
    `getBids(lane)` and `saveBid(lane)` throw the user error, bulk delete of
    A's lane refused; `LaneBenchmarkController` search on the lane still
    returns A's bid with its rate and no customer field.
  - C (`AccountShare` Read on X): sees the project and the lane, edits the
    lane, records a bid, reads A's bid, deletes their own bid.
  - Regression: every existing test (124) still passes; the PMD class-size and
    complexity budgets hold (the new helper keeps `BenchmarkRateService` under
    its ceiling).
- **Jest:** no LWC change is expected; the suite must stay green.
- **Browser (PostProduc):** the admin's full workflow is unchanged (create,
  upload, price, bid, export); the restriction is proven by the Apex tests
  because the sandbox has one RFP user. If a colleague's login is available,
  one check: a project on an account they cannot see is absent from their
  list.

## 8. Out of scope

Hiding the RFP or lane names from anyone who can already see the account;
Account sharing rules themselves (admin configuration); external or
community sharing; a bid recorded outside an RFP (none exists); an audit of
who viewed what.

## 9. Rulings

- R58 — the bid rule lives in one helper (`RfpBidAccess`) rather than in each
  controller, so the system-mode boundary is visible in one place.
- R59 — no new permission or custom permission gates bids; the lane's
  visibility is the only key.
- R60 — one `BID_FIELDS` list for every bid read; `bidsOfLanes` takes no field
  list (the LWC ignores extra fields, and one list keeps `stripInaccessible`
  uniform).
- R61 — `RfpBidAccess` runs `without sharing`; its `WITH USER_MODE` lane and
  project checks are the gate, because `AccessLevel.SYSTEM_MODE` alone lifts
  object and field checks but not record sharing, which follows the class
  keyword.
- R62 — bids stay Private. Public Read Only was rejected: a bid's record page
  would show its project's name, which may carry the customer, to anyone
  holding a bid Id.
- R63 — a `Selected_Bid__c` value the caller carries forward unchanged is not
  re-validated; only a changed value must pass the lane rule.
- R64 — bid saves copy an allow-list of caller-settable fields; the owner, the
  project and the lane keys come only from the platform and
  `BenchmarkRateTrigger`.
- R65 — Lane Benchmark honours `excludeProjectId` only when the caller can read
  that project in user mode.
- R66 — a bid save may name a `Carrier__c` account only if the caller can read
  it in user mode; an unchanged carrier is not re-checked.
- R67 — a bid whose lane is gone (its `RFP_Lane__c` cleared by the set-null
  lookup, `RFP_Project__c` kept) is granted through its project, read in user
  mode. This adds no access because a bid's project is service-maintained:
  `BenchmarkRateTrigger` stamps it from the lane in system context, and
  `RFP_Tool_User` can read it but not edit it (`Lane_Benchmark_User` cannot
  edit it either). A lane-less bid's project is therefore the project of the
  last lane it had, and lanes are Controlled by Parent, so that project's
  readers could already read the bid through its lane. Such a bid stays
  uneditable (`updateBid` needs a lane), and a bid with neither lookup is
  granted to nobody. Moving a bid to another project is an admin data fix.
- R68 — the carrier tests skip, like the no-usable-profile branch, when the org
  shares the hidden carrier with the restricted user, so carrier-sharing
  configuration cannot block a deploy; PostProduc does not share it, so they run
  there.
- R69 — a stored carrier's name shown on reads is not a defect:
  `Carrier_Display__c` is a cross-object formula, which Salesforce evaluates
  regardless of the reader's access to the related account; it behaved the same
  before phase 6, and Lane Benchmark shows carrier names to everyone.

## Outcome — phase 6 (2026-09-13)

Branch `phase-6/rfp-access` from `main` at `5bb8ba2`; spec `7cf4160`.

Commits: `7cf4160` Write the phase 6 design: RFP access follows the customer
account; `3cf15ae` Plan phase 6: RFP access follows the customer account;
`83e8435` Add RfpBidAccess: a lane you can see grants its bids (Task 1);
`e543c1a` Read and write bids through the lane rule (Task 2; also fixed
`RfpBidAccess.updateBid` to read the caller's `RFP_Lane__c` only when `isSet`,
with a regression test); `6dcfa98` Let an RFP follow its customer account and
make bids private (Task 3: metadata + `RfpSecurityTest` rewrite; also removed
the stale fieldPermissions entry for `RFP_Project__c.Customer__c` from
`RFP_Tool_User`, since a master-detail field is required); `d1d7842` Let a
colleague's private bid show and serve as cost source through the lane rule
(Task 3 fix round: `RfpBidAccess` is `without sharing` because
`AccessLevel.SYSTEM_MODE` lifts only object/field checks while record sharing
follows the class keyword — the `WITH USER_MODE` lane/project checks stay the
gate; `attachSelectedBids` fills `Selected_Bid__r` after every
`RfpLaneController` lane read because a user-mode traversal to a colleague's
Private bid returns null; `detachSelectedBids`/`applySelectedBids` move the
`Selected_Bid__c` write into a gated system-mode update in `saveLanePricing`
and `RfpBulkService.save` because a changed lookup to a colleague's Private
bid fails the cross-reference check, proved by `copyPricing` in the test;
`assertLaneVisible` delegates to a batched `Gate.lanes`); `9936d44` Apply a
deferred bid only to lanes whose pricing update succeeded (Task 3 fix round:
`applySelectedBids(deferred, results)` keeps only lanes with a successful
`SaveResult` and `RfpBulkService.save` uses it; the contract of
`applySelectedBids` documented; `visibleLanes`'s body moved into the inner
class `Rows`, now `private without sharing`, for PMD headroom — outer class
38/40); `53f1adc` Keep the bid source test's setup outside its governor window
(`LaneSearchServiceTest.bidsMergeIntoRowsAndObeyTheSourceFilter` did its place
lookups, project, lane and two bid saves inside `Test.startTest()`; a save now
costs four SOQL through the lane rule and the three searches already spend
about ninety, so the full run hit 101; the setup moved above `startTest`,
assertions unchanged); `7d94685` Document the RFP access model (phase 6) and
record the outcome (Task 4: README access model, the guide's FAQ entry in
English and French, the roadmap row, this Outcome); `ba2ffaf` Record the phase
6 browser check; `e16a64a` Harden the bid rule and prove it under sharing (the
final review's code and test fixes, see "Final review" below); `878bf6d`
Document the final review of phase 6 (the CI and README test rosters, the
README object table and access model, R60–R65, the Outcome); `be73fd9` Check
the carrier account on bid saves and prove the remaining gaps (the residual
round's code and tests, see "Residual round" below); and this documentation
commit, Record the residual round of phase 6 (R66, the README access model and
permission set, the spec's Lane Benchmark and permission statements, this
Outcome).

**Differences from the §4 sketch.** `RfpBidAccess` runs `without sharing`, not
`with sharing` (R61); `bidsOfLanes` takes no `fieldList` parameter (R60);
`bidsByIds` takes a `List<Id>` rather than a `Set<Id>`, to keep the caller's
order; the helper throws `LaneSearchException`, which the controllers
convert to `RfpUserError`; and, where the table says "unchanged",
`RfpLaneController` (`getLanes`, the single-lane read, `lanesByIds`,
`saveLanePricing`) and `RfpBulkService.save` also route through
`attachSelectedBids`/`detachSelectedBids`/`applySelectedBids` (R63), including
a system-mode `Selected_Bid__c` update after a user-mode lane gate.

**PostProduc deploys**, all Succeeded except the failed attempts noted
below: `0AfbZ00000CpjiXSAR` (Task 1: helper + test, 10/10),
`0AfbZ00000CpkmfSAB` (Task 2: seven classes, 55/55), `0AfbZ00000CpkwLSAR`
(Task 3: full manifest NoTestRun, 246 components — the lookup→master-detail
conversion went through the metadata deploy, no Setup fallback needed),
`0AfbZ00000CplafSAB` (Task 3 fix round after `d1d7842`: five classes, 55/55),
`0AfbZ00000CplpBSAR` (Task 3 fix round after `9936d44`: five classes, 44/44),
`0AfbZ00000CplyrSAB` (governor-window fix `53f1adc`: 19/19). Two full-manifest
RunSpecifiedTests deploys FAILED, both only on
`LaneSearchServiceTest.bidsMergeIntoRowsAndObeyTheSourceFilter`
("Too many SOQL queries: 101"), the condition `53f1adc` fixed:
`0AfbZ00000CplnZSAR` (141/142) and `0AfbZ00000CpllySAB` (143/144). Task 4 pair:
`0AfbZ00000CpmA9SAJ` (NoTestRun, 246 components, 0 errors), `0AfbZ00000CpmEzSAJ`
(RunSpecifiedTests, 144/144, 0 failures). Final review fix wave (`e16a64a`):
`0AfbZ00000CpoIPSAZ` (the new tests against the classes before the fix, Failed
as expected, 27/32), `0AfbZ00000CpnpOSAR` (seven classes, Failed 63/68: `isSet`
on a `JSON.deserialize`d bid reports fields the JSON never named, so the fix
reads `getPopulatedFieldsAsMap()` instead), `0AfbZ00000CpoThSAJ` (seven classes,
nine test classes, 68/68). Fix wave pair: `0AfbZ00000CpoezSAB` (NoTestRun, 246
components, 0 errors), `0AfbZ00000CpoTiSAJ` (RunSpecifiedTests, the 23 test
classes, 148/148, 0 failures). The residual round's deploys and the final pair
are listed under "Residual round" below.

**Model verified in the org** (Task 3 Step 6): `RFP_Project__c` ControlledByParent,
`RFP_Lane__c` ControlledByParent, `Benchmark_Rate__c` Private, `Customer__c`
Master-Detail(Account) not nillable; 4 projects kept.

**Tests:** Apex 152 / 152 in the final RunSpecifiedTests deploy (144 at Task 4,
plus four methods from the fix wave: three in `RfpBidAccessTest`, one in
`LaneBenchmarkControllerTest`; plus four from the residual round: two in
`RfpSecurityTest`, one in `RfpBidAccessTest`, one in `RfpBidControllerTest`). 21
methods in `RfpBidAccessTest`; 8 methods in `RfpSecurityTest`, 6 of them
restricted-user scenarios. Unlike §7's three fixed users, each scenario creates
its own restricted users (holding `RFP_Tool_User`, `Lane_Benchmark_User` or
both), and the admin running the test owns the customer account. The scenarios:
a Read-shared pricer records and edits a bid and a Lane Benchmark user sees it;
a Read-shared pricer deletes lanes and a bid the admin recorded; a stranger sees
no project and no lane, gets no bid from `bidsByIds`, deletes nothing through
`deleteLanes`, is refused a colleague's hidden bid named as cost source on a
readable lane ("That bid is not available."), and Lane Benchmark still counts
the bid; a Read-shared user creates a project, a lane and a bid, reads and edits
the admin's bid, sees its carrier through `getLanes`, picks it as cost source,
copies that pricing and deletes the lane with the admin's bid; a Read-shared
pricer is refused a carrier account they cannot read ("That carrier is not
available.") and, once the account is shared, saves the same bid; a Read-shared
pricer edits the rate of the admin's bid whose carrier account they cannot read.
`LaneBenchmarkControllerTest` gains
`searchExcludesAProjectOnlyWhenTheCallerCanReadIt`, whose stranger branch came
in the residual round. Jest unchanged (36 suites / 309 tests). PMD clean.

**Known limits.** `Selected_Bid__r.Carrier_Display__c` is read through the lane
in user mode (`RfpLaneController.LANE_FIELDS`, `rfpWorkbook`); it did not pass
as written and needed the fill — `lanesByIds`/every lane read routes through
`RfpBidAccess.attachSelectedBids`, which refills `Selected_Bid__r` because a
user-mode traversal to a colleague's Private bid returns null. Deferred
minors, unresolved by design: `Selected_Bid__r` now carries the full stripped
bid (`BID_FIELDS`) instead of one formula field — a larger payload for a
2000-lane project, no new exposure; `detachSelectedBids` nulls the update
records before validating (callers abandon them on the exception); the
one-argument `applySelectedBids` stays public for `saveLanePricing`. The
restriction itself cannot be shown in PostProduc with one RFP user; a
colleague's login would show a project on an unshared account absent from
their list.

**Open follow-ups.** None. Each one recorded here, and the copy-pricing limit
from the fix wave, is closed under "Follow-ups closed (2026-09-13)" at the end
of this Outcome.

**Review record.** Task 1 review clean; Task 2 one fix round (`updateBid`
`isSet`); Task 3 three fix rounds (`without sharing`; attach/detach/apply;
apply-only-successful), reviewed by opus, re-review clean.

**Browser check** (PostProduc, 2026-09-13, the admin user, fresh tab after the
final deploy): the RFP Tool list shows all four projects (View All Data); the
"Phase 3c browser check" workbench opens with its 68 lanes and lane 1 still reads
"5 loads + 1 bid · median 5500.00"; the lane panel lists the existing bid and a
new free-text bid ("Phase 6 check carrier", 5100 CAD) saved through the lane
rule and appears at once; the Help tab's FAQ shows "Who can see an RFP?" in
English and "Qui peut voir un RFP?" in French; the ALIMENTS MULTIBAR INC.
account page lists both RFP projects with lane and bid counts through
`bidCountsByProject`. Not shown here: the restriction itself (one RFP user in
the sandbox); `RfpSecurityTest` is the proof.

**Final review (2026-09-13).** The whole-branch review ran as a workflow
(`wf_c5df5c30-498`): seven review dimensions, two verifiers per finding and a
completeness critic, 60 agents in all. It confirmed 16 findings and left 4
contested. Twelve verifier agents failed on a usage limit and the critic did
not run, so the controller read the six findings whose verifiers failed
itself. Fixed in `e16a64a`:

1. `RfpBidAccess.detachSelectedBids` checks only a changed `Selected_Bid__c`.
   A value equal to the stored one stays on the user-mode update untouched, so
   a lane whose selected bid has lost its lane still saves its margin, sell and
   notes (R63).
2. `insertBids` strips first and runs its lane checks on the records it will
   insert, so a stripped `RFP_Lane__c` is refused with "A bid needs a lane."
3. Bid saves copy onto fresh records only the populated caller-settable fields
   (`SETTABLE_FIELDS`, plus `RFP_Lane__c` on insert or the Id on update) before
   `stripInaccessible`, so `OwnerId`, `RFP_Project__c`, the lane keys and the
   geolocations never reach the system-mode DML (R64).
4. `updateBid` refuses a posted `RFP_Lane__c` other than the stored lane, null
   included, with "A bid cannot move to another lane."
5. `RfpController.projectsForAccount` and `RfpLaneController.saveLanePricing`
   also catch `LaneSearchException` and pass its sentence on as the user error,
   so a lane price save refused by the rule now shows "That bid is not
   available." without the generic prefix.
6. `LaneBenchmarkController.search` keeps `excludeProjectId` only when a
   `WITH USER_MODE` query returns that project; otherwise it excludes nothing
   (R65). `RfpHistoryService` calls `LaneSearchService.search` directly and
   keeps its exclusion.
7. The sharing tests: the stranger's `deleteLanes` leaves the lane and bid in
   place, and the stranger is refused a colleague's hidden bid on a readable
   lane; the Read-shared user edits and deletes the admin's bid and sees its
   carrier through `getLanes`; the restricted `deleteLanes` scenario removes a
   bid the admin recorded; a stale field-level-security comment was reworded.
8. `878bf6d`, the documentation fix: `RfpBidAccessTest` added to the CI roster
   and the README production deploy command; the README object table, bid-save
   sentences and access model corrected; R60–R65 added; this Outcome's SHAs,
   counts and deploys corrected.

Known limits, parked. `RfpProjectController.saveProject` still copies
`Customer__c` on update; no caller sends it, and the platform treats a
master-detail that is not reparentable as not updateable, so the value is
stripped. No end-to-end test fails one row of `RfpBulkService.save` to prove
the two-argument `applySelectedBids`: `RFP_Lane__c` has no validation rule that
could fail a single row, and the filter itself is unit-tested. The fix wave's
report adds two more, both since closed: that no test posted a JSON null in a
bid update (the residual round below), and that copying pricing from a lane
whose selected bid had lost its lane was refused ("Follow-ups closed" below).

**Residual round (2026-09-13).** The re-review of the fix wave left four
findings, closed in `be73fd9`:

1. R1, a security regression (R66). `Carrier__c` is a lookup to Account, which
   is Private. The bid save's system-mode DML skips the sharing check that the
   earlier user-mode save made on the lookup target, and the reload's
   `Carrier_Display__c` hands back the account's name. `RfpBidAccess` now
   requires every `Carrier__c` about to be written to come back from a
   `WITH USER_MODE` Account query: on insert every one, on update only one that
   differs from the stored bid's. Otherwise the save is refused with "That
   carrier is not available.", and a caller with no Account read gets the same
   sentence. `RfpBulkService.applyBid` (bulk "Add carrier rate") reaches the
   same check through `saveAll` and `insertBids`. The factory's carrier could
   not serve as the hidden account: in this org the flow
   `Ownership_update_Carrier_and` gives every carrier that is not blacklisted
   to the Public Accounts user, whose owner-based sharing rules reach All
   Internal Users, and the rule `Carrier_Sharing_Setting` shares every carrier
   of Trans-Pro Logistics Inc. The tests use a blacklisted Trans-Pro Logistica
   carrier, so in this org the check matters for such carriers. Before the fix
   the refused save succeeded ("expected AuraHandledException"); the edit that
   keeps an unreadable carrier passed.
2. R2. `RfpBidControllerTest.switchingABidToATypedCarrierClearsTheAccount`
   posts what `rfpBidForm` sends when a bid switches from a carrier account to
   a typed name, `"Carrier__c": null` included. It passed before any change, so
   `getPopulatedFieldsAsMap()` counts an explicit JSON null and
   `RfpBidController` is unchanged.
3. R3. The exclusion test gains a stranger holding `RFP_Tool_User` and
   `Lane_Benchmark_User` with no share on the customer: the bid row still comes
   back. It passed before the change, so this was a coverage gap, not a defect.
4. R4. The trigger-stamp test's comment now says what it proves, and
   `settableFieldsLeaveOutEveryServiceMaintainedField` asserts that
   `SETTABLE_FIELDS` leaves out the owner, the project, the lane keys and the
   geolocations and holds the carrier and the rate. `RFP_Lane__c` is not on the
   list (the insert appends it), so the test asserts that an insert carries it.

Deploys: `0AfbZ00000CppCrSAJ` (the new tests against the classes before the
fix, Failed 17/19: the factory's carrier was readable), `0AfbZ00000CppETSAZ`
(Failed 6/8, the same), `0AfbZ00000CppG5SAJ` (the blacklisted carrier, Failed
7/8: the refused save succeeded), `0AfbZ00000CppJJSAZ` (five classes, seven
test classes, 62/62). Final pair: `0AfbZ00000CppXpSAJ` (NoTestRun, 246
components, 0 errors), `0AfbZ00000CpoWwSAJ` (RunSpecifiedTests, the 23 test classes,
152/152, 0 failures). PMD clean; `RfpBidAccess` stays at 33 of 40.

**Follow-ups closed (2026-09-13).** Branch `phase-6/follow-ups` from `main` at
`009e9a0`; commits `ca84425` Grant a bid whose lane is gone through its project
and harden the carrier tests, and this documentation commit, Record the phase 6
follow-ups as closed. Closed, from "Open follow-ups" and the fix wave's known
limits:

1. Copying pricing from a lane whose selected bid has lost its lane (R67).
   `RfpBidAccess.Rows.keepVisible` keeps the lane check for a bid on a lane and
   grants a bid whose `RFP_Lane__c` is null through its `RFP_Project__c`, read
   `WITH USER_MODE` (a `QueryException` counts as none), in one extra query that
   runs only when such a bid is present; a bid with neither lookup stays hidden.
   `updateBid` and `deleteBidsOfLanes` are unchanged, so such a bid still cannot
   be edited. `RfpBidAccessTest.aBidWhoseLaneIsGoneIsGrantedThroughItsProject`
   (the admin: `bidsByIds` returns the bid, `copyPricing` carries it to another
   lane, `attachSelectedBids` fills its carrier, and with the project cleared
   too the bid is hidden) and
   `RfpSecurityTest.aReadSharedUserCopiesPricingWhoseSelectedBidLostItsLane`
   failed before the change with "That bid is not available.";
   `RfpSecurityTest.aStrangerCannotNameABidWhoseLaneIsGone` (a stranger with
   Read on a second customer names that bid on their own lane) passed before and
   after, the guard that the grant adds no access.
2. The update path of the carrier check.
   `RfpSecurityTest.aColleagueCannotSwitchABidToACarrierTheyCannotRead`: a
   Read-shared pricer who posts the admin's bid, stored with the graph's vendor,
   with the hidden carrier and a new rate is refused with "That carrier is not
   available.", and the stored carrier and rate stay. It passed before the
   change, as expected: the check already existed.
3. The bulk "Add carrier rate" refusal.
   `RfpBulkControllerTest.addCarrierRateRefusesACarrierTheCallerCannotRead`:
   `applyBid` naming the hidden carrier is refused ("No lane was updated: That
   carrier is not available"), no bid is inserted, and the lane keeps its cost
   and selected bid. It passed before the change too.
4. The carrier tests' portability (R68). The four tests built on
   `hiddenCarrier()` skip, like the no-usable-profile branch, when the
   restricted user can read that carrier; their real assertions are unchanged,
   and they still need the Account fields `Company_Org__c` and `Black_List__c`
   and the Carrier record type, which predate the sandbox. In PostProduc they
   run rather than skip: in a per-test coverage run (`707bZ00000rFQhq`, 4/4)
   the three refusal tests each cover the `CARRIER_UNAVAILABLE` throw in
   `RfpBidAccess`, and the rate-edit test covers 164 of its lines, where a
   skipped test covers none.
5. A stored carrier's name on reads (R69): a ruling, no code.

`RfpSecurityTest` would have reached a cyclomatic complexity of 51 against
PMD's class budget of 40, so its restricted-user helpers (`restrictedUser`,
`shareAccount`, `hiddenCarrier`, `sharingInputs`, and the new `hiddenFrom` and
`secondCustomer`) moved to `RfpTestDataFactory`, and the bulk test went to
`RfpBulkControllerTest`, which shares them; `RfpSecurityTest` is at 38.
Deploys: `0AfbZ00000CprWPSAZ` (the new tests against the classes before the
change, Failed 35/37 on the two copy tests, as expected), `0AfbZ00000CprZdSAJ`
(`RfpBidAccess` and four test classes, seven test classes run, 69/69). Final
pair on `ca84425`: `0AfbZ00000CprjKSAR` (NoTestRun, 246 components, 0 errors),
`0AfbZ00000CprctSAB` (RunSpecifiedTests, the 23 test classes, 157/157, 0
failures). Apex 157 (152 plus one method in `RfpBidAccessTest`, three in
`RfpSecurityTest` and one in `RfpBulkControllerTest`). PMD clean;
`RfpBidAccess` stays at 33 of 40 (`Rows` 22).

Review of the follow-ups (2026-09-14), closed in `c361024`. Three minor
findings, each confirmed at `88f4f43`:

1. R67's "adds no access" rested on a field users could edit. `RFP_Tool_User`
   could edit `Benchmark_Rate__c.RFP_Project__c`, and the trigger stamps the
   project only when a bid has a lane. So a pricer who could edit a bid could
   clear its lane and point it at any project they could read, and that
   project's readers were then granted the bid. The field is now readable but
   not editable in `RFP_Tool_User`; the trigger still stamps it in system
   context. `BenchmarkRateServiceTest.aPricerCannotPointABidAtAnotherProject`:
   a restricted pricer who owns a bid and can read a second project edits
   the bid's rate in user mode, but a user-mode update that clears the lane
   and names the second project, and a user-mode lane-less insert naming it,
   leave no bid on that project. It failed against the old permission set
   (the bid moved to the second project).
2. R67, the README and the `RfpBidAccess` header now name the invariant: a
   bid's project is service-maintained, so a lane-less bid's project is the
   project of the last lane it had.
3. `RfpBidAccessTest.anUnchangedSelectedBidWhoseLaneIsGoneStillSaves` clears
   the bid's project as well as its lane. With the project kept, R67 granted
   the bid, and a `detachSelectedBids` that validated an unchanged selection
   passed the test. A dry run with that mutation now fails it ("That bid is not
   available.").

Deploys: `0AfbZ00000Cq475SAB` (dry run of the new tests against the old
permission set, with the mutation, Failed 30/32 on exactly those two tests),
`0AfbZ00000Cq5O5SAJ` (the permission set, `RfpBidAccess` and two test classes;
five test classes run, 53/53). Final pair on `c361024`: `0AfbZ00000Cq5zBSAR`
(NoTestRun, 246 components, 0 errors), `0AfbZ00000Cq3CcSAJ`
(RunSpecifiedTests, the 23 test classes, 158/158, 0 failures). Apex 158 (157
plus one method in `BenchmarkRateServiceTest`). PMD clean. Still open: only
the known limits recorded above.
