# Pricing Department: Roadmap

Approved 2026-09-07. Deliberately unhurried: each phase is independently
shippable, has its own spec and plan, and lands in the sandbox chain
dev -> postproduction (UAT) -> production.

## Goal

Turn the Pricing Department page from a text-filtered list of carrier
quotes into a lane benchmarking tool: pick an origin and destination at a
chosen precision (radius, exact city, province/state, postal prefix), a
mode and equipment (by category or specific type), see comparable carrier
costs with statistics, and get a suggested sell price from a default
15-20 % margin the user can override.

## Ground truth that shaped the design (measured in the postproduction sandbox)

- 66,188 carrier quotes in the last 365 days; 404,380 since 2018.
- 14,999 of 15,043 location accounts used by stops in the last year already
  have shipping latitude/longitude. Radius search needs no geocoding purchase
  for historical data.
- Origin/destination text has spelling variants (Montréal / Montreal /
  MONTREAL / Montreal, QC). Coordinates remove most of that problem.
- Equipment Type (managed) already has a Category picklist (Van, Flatbed,
  Reefer, Specialized, Ocean/Intermodal) and a mode multi-select. Mode is a
  managed object with 8 enabled values.
- Truckload 70 %, LTL 25 % of quotes; Dry Van 53' is 62 % of equipment.

## Architecture decision

Approach B: denormalize the lane onto the Load (origin/destination
geolocation, normalized city key, province, postal prefix, equipment
category), filled by automation at save time and backfilled for 24 months.
Carrier Quote is one lookup away, so every precision level becomes plain,
selective SOQL. A Place object built from the geocoded location accounts
feeds history autocomplete and typo tolerance. The page is rebuilt as small
components sharing one typed search request.

Rejected: extending the current formula-driven page in place (cannot be
indexed, grouped, or searched by geography), and a nightly lane analytics
object (delays the interactive features; possible later on top of B).

## Phases (revised 2026-09-09 evening: Mapbox key available, so geocoding and margin fold into phase 2)

| #   | Phase               | Lands                                                                                                                                                                                                                                                                                                                                                                                                 | Status                                                                                      |
| --- | ------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------- |
| 0   | Engineering hygiene | Toolchain, CI, real tests, bug-fix PR                                                                                                                                                                                                                                                                                                                                                                 | Done 2026-09-09                                                                             |
| 1   | Search foundation   | Place dictionary + batches, PlaceNormalizer, LaneSearchService with typed request/result and per-currency stats, any lookback (default 90 days)                                                                                                                                                                                                                                                       | Done 2026-09-09 (index support case outstanding)                                            |
| 2   | Lane Benchmark UI   | New page, tab and app (also in TransPro): place picker with dictionary autocomplete and Mapbox fallback, precision and radius, lookback, currency/mode/equipment filters, per-currency stats with margin and suggested sell (default 15 %, 20 % one click), results with carrier detail, CSV export, remembered filters, static map preview                                                           | Done 2026-09-10                                                                             |
| 3   | RFP tool            | Upload an Excel/CSV of requested lanes; per row, show existing prices via LaneSearchService; add or update carrier prices WITHOUT creating loads as load-less Benchmark Rate records (carrier = existing Account lookup OR free-text carrier + contact name/email/phone; expiry date; parent RFP Project with name, file, customer); Benchmark Rates appear in lane search as a flagged second source | Done 2026-09-12 (3a objects and bids; 3b workbench; 3c pricing; 3d bids in history)         |
| 4   | Retire the old page | Remove the Pricing Department tab/page/LWC once pricing has switched                                                                                                                                                                                                                                                                                                                                  | Done 2026-09-12 (PostProduc; production deploy is the admin's step, README has the command) |
| 5   | Help center         | Help tab with the bilingual guide built from `docs/help`, "?" hints in twelve areas                                                                                                                                                                                                                                                                                                                   | Done 2026-09-12 (PostProduc; French text awaits the user's read-through)                    |
| 6   | RFP access model    | An RFP follows its customer account (master-detail, Read is enough to work it); bids Private with the lane rule in `RfpBidAccess`; Lane Benchmark unchanged                                                                                                                                                                                                                                           | Done 2026-09-13 (PostProduc; production untouched)                                          |

Former phases 4 (margin) and 5 (external autocomplete) are inside phase 2.

## Product name (decided 2026-09-09)

The tool is rebranded **Lane Benchmark**. Phase 2 creates the new page under
that name and retires the "Pricing Department" tab once users have switched
(a Lightning component cannot be renamed in place). API names from phase 2
onward: LWC `laneBenchmark*`, FlexiPage and CustomTab `Lane_Benchmark`,
Apex `LaneBenchmark*` for UI-facing classes, permission set
`Lane_Benchmark_User` replacing `Pricing_Department_User`. Phase 1's
`LaneSearchService` and `Pricing_Place__c` keep their names.

## Backlog

- RFP tool (see phase 6 above): requested by the user on 2026-09-09, after
  phase 1 wrapped, as a load-less way to capture and compare bid pricing.

## Standing constraints

- Develop and test in PostProduc; production is the only org after it. Nothing
  is developed directly in production.
- (Retired with phase 4.) `PricingDepartmentController` stayed `without
sharing` on purpose while it existed; the excluded Contact Ids moved to
  custom metadata in phase 0 and are read by `LaneSearchExclusions` now.
- Lookback is a free number of days (default 90, no cap). Radius searches over long windows are slower (about 13 s for a year); the fix is custom indexes requested from Salesforce, not new fields.
- No backfill: lane data is read through relationships from Revenova's lane keys and the location accounts.
- Alias rules for places are a business asset curated by the pricing team.
- No AI attribution trailers in commits.

## Known issues to fix in phase 0

- LWC: `handleAcceptedQuotesFilterChange` references an undeclared
  identifier (ReferenceError on toggle).
- Apex: `PricingDepartmentControllerTest3` calls `getCarrierQuotes` with 8
  arguments (method has 9); both tests assert nothing.
- LWC: dead `fetchModeOptions`; API version 57.0 vs project 64.0.
- Sandbox admin profile lacks field-level read on `Quote_Date__c`
  (SOQL from the API reports "No such column").

## Outcome — phase 4 (2026-09-12)

Branch `phase-4/retire-pricing-department`, three commits:

1. `e4bd684` Move the carrier-quote exclusions into LaneSearchExclusions and drop the
   old controller — `excludedContactIdSet()`, `excludedContactIds()`,
   `parseExcludedContactIds()` and the `@TestVisible excludedContactIdsOverride` hook
   move verbatim into `LaneSearchExclusions` (`with sharing`, it only reads custom
   metadata), with a new `LaneSearchExclusionsTest`. Every consumer, the 22-class test
   list and both surviving permission sets are repointed.
2. `870e6cc` Remove the Pricing Department page, tab, component and permission set.
3. `6f7b0db` Document the retired Pricing Department page and the production steps.
4. Review fix wave (this commit): remove the orphaned `lwc/quoteStats` (its only importer
   was `pricingDepartment.js`), add the production pre-check for the two legacy test
   classes and the unassign commands to the README runbook, note that `e4bd684` is not
   deployable on its own, and fix the data-flow diagram.

**PostProduc deploys:** `0AfbZ00000CpbZhSAJ` (the new class and the repointed consumers,
124/124 Apex tests) and `0AfbZ00000CpaH4SAJ` (the destructive run, 124/124). An earlier
attempt, `0AfbZ00000Cpb53SAB`, failed: Salesforce will not delete
`PricingDepartmentController` while `lwc/pricingDepartment` imports `getCarrierQuotes`,
so the two Apex classes are deleted together with the component rather than a step
earlier. The single `Pricing_Department_User` assignment was removed by Id first.

**Removed** from repo and org: the `Pricing_Department` tab and FlexiPage, the
`pricingDepartment` LWC and its Jest suite, the orphaned `quoteStats` LWC (deploy
`0AfbZ00000CpbwHSAR`), `PricingDepartmentController` and its test, the `Pricing_Department_User`
permission set, and the reference-only `Pricing` profile.

**Kept:** `Pricing_Department_Setting__mdt`, its `Excluded_Contact_Ids__c` field and its
`Default` record (the lane search still reads the exclusions), and every
`rtms__CarrierQuote__c` formula field - including the eight only the old page used, which
the README lists as an admin follow-up because dropping a field cannot be undone. The
standing constraint about `PricingDepartmentController` staying `without sharing` retires
with the class; `LaneSearchExclusions` is `with sharing`.

**Production** is not done: the admin assigns `Lane_Benchmark_User` and `RFP_Tool_User` to
the pricing team, then runs the one-time
`manifest/destructiveChanges-phase4.xml` deploy written out in full in the README section
"Retired: Pricing Department page (phase 4)".
