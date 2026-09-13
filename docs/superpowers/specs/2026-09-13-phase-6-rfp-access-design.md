# Phase 6 — RFP access follows the customer account

Date: 2026-09-13. Roadmap: phase 6, after phase 5 (help center) merged as
`5bb8ba2`. Changes the sharing model of the RFP objects built in phase 3 and
the Apex that reads and writes bids; nothing changes in Lane Benchmark.

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
- **Lane Benchmark:** unchanged for everyone (D2).
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
  create/read/edit/delete on the three objects; `Lane_Benchmark_User` keeps
  read on `Benchmark_Rate__c` (its queries run in system mode anyway).

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
