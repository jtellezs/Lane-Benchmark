# Phase 9 — Market test (rate check on a lane)

Date: 2026-09-17. Roadmap: phase 9, the first phase after phase 8 merged. A new
tab where a pricer picks a lane, records what carriers quote for it now, and
reads those rates against what the lane has done historically. The rates are
ordinary lane bids, so they join every median the app already shows.

Requested by the owner on 2026-09-16: "a way to evaluate the market for a
particular lane — enter a lane then use a tool like the bid where we can choose
from the existing carriers or new one and enter the rate."

Build order and rollout: phase 9 is built before phase 10 (lane trend chart).
Work happens on a branch off main, deployed to PostProduc (alias `sandbox`)
only; production is not deployed from this branch. PostProduc was refreshed on
2026-09-16, so the app must be redeployed there before this phase starts.

## 1. Decisions (brainstorm with the owner, 2026-09-16)

| #   | Decision                                                                                                                                                                                                                                                                                                                                                      |
| --- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| D1  | **A dedicated tab.** The owner chose a Market Test tab of its own over a card inside Lane Benchmark or a hidden one-lane RFP project. It is the larger build, and it is the home phase 10's chart will share.                                                                                                                                                 |
| D2  | **Rates only, no ask tracking.** The page records what carriers answered. It does not track who was asked, who declined, or response rates. Phase 8's Carriers to ask already names who to contact; pairing the two is a later phase if the team wants it.                                                                                                    |
| D3  | **Counted like any other bid.** A market-test rate is not flagged and not separated. It joins the lane's count, median and min/avg/max wherever the app shows them, exactly as an RFP bid does.                                                                                                                                                               |
| D4  | **No project, no RFP lane.** A market-test rate is a `Benchmark_Rate__c` with `RFP_Project__c` and `RFP_Lane__c` both null. That absence is what distinguishes it from an RFP bid, so no new field is needed, and a later phase can still separate the two without a schema change or a backfill.                                                             |
| D5  | **The controller stamps the lane keys.** `BenchmarkRateService.applyLanes` copies lane keys from an RFP lane, so a rate with no lane gets none — and a rate with no keys never matches a lane search, so it would never reach the median D3 requires. The new controller sets the places and calls the already-public `cityLane`, `stateLane` and `zip3Lane`. |
| D6  | **Read shared, write owned.** The page reads a lane's market-test rates in system mode, gated on the permission set, so the team sees the same rates it already sees in the median. Editing and deleting are restricted to whoever recorded the rate.                                                                                                         |
| D7  | **Reuse the existing parts.** `laneBenchmarkPlacePicker` for both ends, `rfpBidForm` for the carrier-and-rate entry, `LaneBenchmarkController.search` unchanged for the history half.                                                                                                                                                                         |

## 2. Today (read in the repo, 2026-09-17)

- `Benchmark_Rate__c` is "a carrier bid for a lane, captured without a Load",
  with `RFP_Project__c` / `RFP_Lane__c` as optional lookups. `sharingModel` is
  `Private`.
- `rfpBidForm` already offers an existing carrier or a typed name for one that
  is not in the system: "Pick a carrier, or switch on a carrier not in the
  system." It is used today only by `rfpLanePanel`, which calls
  `RfpBidController.saveBid`.
- `BenchmarkRateTrigger` (before insert, before update) calls
  `BenchmarkRateService.applyLanes`, which guards a null lane
  (`if (lane != null)`), and defaults `Valid_From__c` to today and
  `Expires_On__c` to today + 30 days for every bid. Lane keys are copied only
  when an RFP lane is present.
- `BenchmarkRateService.cityLane`, `stateLane` and `zip3Lane` are public and
  take two `Pricing_Place__c` records.
- `RfpBidAccess` is lane-scoped end to end: `assertLaneVisible(Id laneId)`,
  `bidsOfLanes(Set<Id>)`, and `updateBid` throwing `LANE_UNAVAILABLE`. It cannot
  serve a rate that has no lane.
- Object permissions on `Benchmark_Rate__c`: `Lane_Benchmark_User` read only;
  `RFP_Tool_User` create, read, edit and delete.
- Lane Benchmark history already counts bids with no project, so D3 needs no
  change to the search.
- `laneBenchmarkPlacePicker` exposes `label`, `value`, `valueLabel`,
  `precision`, `radius` and `unit`, and generates its own listbox id, so several
  instances coexist outside Lane Benchmark's state.
- `RFP_Lane__c.Selected_Bid__c` is a Lookup with `deleteConstraint` `SetNull`.
- Every page in this app is a tab, a FlexiPage, an LWC bundle, three manifest
  entries, `tabSettings` in both permission sets, nav entries in
  `TransPro.app-meta.xml` and `Lane_Benchmark.app-meta.xml`, and a help page in
  EN and FR with the help resource rebuilt.

## 3. The page

One tab, one LWC (`marketTest`), two halves on one screen.

**The lane.** Origin and destination through `laneBenchmarkPlacePicker`, plus
mode, equipment category and equipment type, and hazmat — the same controls
Lane Benchmark uses, so a pricer moving between the two pages meets no new
vocabulary. A lane must have both ends before anything else appears.

**Left half — what the lane has done.** The page calls
`LaneBenchmarkController.search` with the chosen lane and the default 90-day
lookback, and shows the same stats card Lane Benchmark shows: count, median,
min/avg/max, rate per mile. No new Apex, no new maths, and the numbers agree
with Lane Benchmark by construction because they come from it.

**Right half — what you are collecting.** A list of the market-test rates
already recorded for this lane, and an **Add rate** button that opens
`rfpBidForm`. Each saved rate appears in the list with carrier, rate, currency,
transit days, fuel surcharge and validity. A running count, median and spread of
the rates in this list sits above it, so the pricer can read today's market
against the history on the left without doing arithmetic.

## 4. Data

No new object and no new field. A market-test rate is a `Benchmark_Rate__c`
with:

- `RFP_Project__c` = null, `RFP_Lane__c` = null (D4)
- `Origin_Place__c` / `Destination_Place__c` = the chosen places
- `Origin_City__c` … `Destination_Country__c` copied from those places
- `City_Lane__c`, `State_Lane__c`, `Zip3_Lane__c` from
  `BenchmarkRateService.cityLane` / `stateLane` / `zip3Lane` (D5)
- `Mode__c`, `Equipment_Category__c`, `Equipment_Type__c`, `Hazmat__c` from the
  page's filters
- `Carrier__c` or `Carrier_Name__c`, `Rate__c`, `CurrencyIsoCode`,
  `Transit_Days__c`, `Fuel_Surcharge__c`, `FSC_Included__c`, `Notes__c` from the
  form
- `Valid_From__c` / `Expires_On__c` defaulted by the trigger when left blank

## 5. Apex behaviour

A new `MarketTestController` and a `MarketTestService`. The controller is the
only new Apex surface the LWC calls.

- `getRates(String laneJson)` — the lane's market-test rates: bids matching the
  lane keys with both lookups null. Runs in system mode (D6) so the team sees
  the same rates the median already counts, after asserting
  `Benchmark_Rate__c.isAccessible()` for the running user.
- `saveRate(String rateJson)` — builds the record per §4, asserts
  `isCreateable()`, inserts through `Security.stripInaccessible`, returns the
  saved rate.
- `updateRate(String rateJson)` / `deleteRate(Id rateId)` — assert the running
  user owns the record (`OwnerId == UserInfo.getUserId()`), and that the record
  has no RFP lane, so this path can never edit or delete an RFP bid. Anything
  else throws the page's "That rate is not yours to change."

The lane match reuses `LaneQueries`' condition builders rather than a second
copy of the matching rules.

## 6. What people see

- No lane chosen: the two halves are empty with a one-line prompt.
- A lane with history and no rates yet: the left half fills, the right half says
  "No rates recorded for this lane yet."
- A lane with no history: the left half says so plainly, which is itself the
  answer a pricer wants — this lane has nothing to go on, which is why they are
  running a market test.
- A rate someone else recorded: visible, with edit and delete hidden.
- Without create permission: the list still shows, **Add rate** does not.

## 7. Limits, errors, security

- `Benchmark_Rate__c` stays `Private`. The page reads in system mode by
  deliberate decision (D6); every read is gated on the object being accessible
  to the running user, and writes are gated on ownership.
- The write path refuses any record carrying an `RFP_Lane__c`, so `RfpBidAccess`
  remains the only way an RFP bid is edited.
- `Selected_Bid__c` is `SetNull`: if an RFP lane has selected a market-test rate
  and its owner deletes it, that lane's selected cost silently becomes blank.
  The delete confirmation says so when the rate is referenced.
- Rates recorded here move the medians every other screen shows (D3). That is
  the intent, and the help page says it in plain words.

## 8. Open decisions for the owner's review

| #   | Question                                                                                                                                                                                                                                                                                                                                                                      |
| --- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| O1  | **The name.** Lane Benchmark's help says, in EN and FR, "Market Test quotes are never included" — those are Revenova quotes under a customer named Market Test, excluded since phase 7. A tab called Market Test whose rates _are_ counted contradicts that sentence in four help files. Recommendation: call the feature **Rate check** and leave the phase 7 wording alone. |
| O2  | **Who may record a rate.** `Lane_Benchmark_User` has read-only on bids today, so only `RFP_Tool_User` holders could add one. The go-live assigns both sets to the pricing team, so nothing changes in practice, and no permission set is widened. Recommendation: leave the permissions alone and hide **Add rate** when the user cannot create.                              |

## 9. Testing

- Apex: lane keys stamped for a lane-less rate; a rate with no keys never
  matches (the regression D5 exists to prevent); `getRates` returns another
  user's rate; `updateRate` and `deleteRate` refuse a rate the user does not own
  and refuse any rate with an RFP lane; create without permission throws.
- Jest: the page renders both halves; **Add rate** hidden without create; the
  right-half summary recomputes as rates are added; edit and delete hidden on
  another user's rate.
- Browser check in PostProduc: record three rates on a real lane, confirm they
  appear in Lane Benchmark's median for the same lane, and confirm a colleague's
  rate is visible but not editable.

## 10. Out of scope

Ask tracking (D2), a source flag (D3), emailing carriers, and the trend chart
(phase 10, its own spec).
