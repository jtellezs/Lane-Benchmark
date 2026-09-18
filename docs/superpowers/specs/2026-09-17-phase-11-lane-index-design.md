# Phase 11 — Lane index: how hard a lane is to cover, and building one from segments

Date: 2026-09-17. Roadmap: phase 11, after phase 9 (market test) and phase 10
(lane trend). Two features the owner asked for on 2026-09-17, specified together
because they need the same expensive thing: an index of what the company knows
about every lane it has priced.

- **How hard is this lane to cover?** A band, with the numbers behind it, so a
  pricer knows before quoting whether a lane is routine or a scramble.
- **Build a lane from segments.** When A to B has no usable history, compose it
  from A to C and C to B (and at most one hop further), using the segments the
  company has actually priced.

## 1. Decisions

| #   | Decision                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| --- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| D1  | **One materialised index, two features.** A `Lane_Edge__c` record per priced lane, built by a batch like `PlaceBuilderBatch` builds the place dictionary. Both features read it; neither scans quotes at search time. 203,023 quotes over three years cannot be aggregated per request, and phase 8 already read 13,624 rows for one province pair's counts.                                                                                |
| D2  | **Edges come from what the org actually has.** Quotes through their loads' stops (the volume), `Benchmark_Rate__c` bids and market-test rates (already carry `City_Lane__c`, `State_Lane__c`, `Zip3_Lane__c`, so they are free), and freight plan legs (phase 8's source, proven multi-leg moves). **Not** `rtms__Lane__c` (10 records) or `rtms__LanePreference__c` (0): the objects exist with the right shape but are empty in this org. |
| D3  | **Always a range, never a single number** (owner, 2026-09-17). Every composed cost and every difficulty figure shows its spread and the sample size behind it. A single number gets anchored on and quoted back.                                                                                                                                                                                                                            |
| D4  | **Two hops maximum.** A composed lane may cross at most two intermediate places (three legs). Each hop adds a handoff cost the data does not contain, so a guess compounds with every hop; capping at two keeps the estimate arguable.                                                                                                                                                                                                      |
| D5  | **Carriers, not quotes, measure difficulty.** 15,810 quotes against 13,567 loads in 90 days is about 1.17 quotes per load, 74 % accepted: most loads take the first quote. Quote count therefore measures the company's process, not the market. Difficulty reads distinct carriers that _moved_ the lane, how often it runs, how wide the spread is, and how recent the last move was.                                                     |
| D6  | **A band, not a score.** "Routine / Workable / Hard / Too thin to say", each with the counts that produced it. A 0-100 score invites false precision over data this sparse.                                                                                                                                                                                                                                                                 |
| D7  | **Composed options never outrank direct history.** As in phase 8's D1, direct results stay first; a composed lane is offered only when the direct lane is thin or absent, and is always labelled as built from segments.                                                                                                                                                                                                                    |
| D8  | **The index is derived and disposable.** It is rebuilt from source data and holds no curation, so it can be dropped and rebuilt at any time - the same property that made the place dictionary safe to lose in the 2026-09-16 refresh.                                                                                                                                                                                                      |

## 2. Today (measured in PostProduc, 2026-09-17)

- Quotes: 203,023 over three years; loads: 164,845. Over 90 days, 15,810 quotes
  on 13,567 loads, 11,722 accepted.
- Places by yearly load count: 314 above 50, 674 between 10 and 50, 3,536
  between 1 and 10. The lane graph has a small head and a long, thin tail.
- `Benchmark_Rate__c` stores its own lane keys; quotes do not, which is why
  phase 8's province counts were expensive.
- Freight plans gave phase 8 3,883 split shipments; three handoff points are
  curated in `Handoff_Point__mdt` (Laredo, San Diego, Calexico).
- `rtms__Lane__c`: 10 records. `rtms__LanePreference__c` and
  `rtms__LanePreferenceCarrierService__c`: 0.

## 3. The index

One `Lane_Edge__c` per (origin place, destination place) the company has priced,
keyed by `City_Lane__c` so it joins everything else in the app.

| Field                                                      | Meaning                                                           |
| ---------------------------------------------------------- | ----------------------------------------------------------------- |
| `Origin_Place__c`, `Destination_Place__c`                  | The two ends, as `Pricing_Place__c`.                              |
| `City_Lane__c`, `State_Lane__c`, `Zip3_Lane__c`            | The same keys every lane search speaks.                           |
| `Loads_Moved_365d__c`, `Loads_Moved_3y__c`                 | How often the lane actually runs.                                 |
| `Carriers_Moved_3y__c`                                     | Distinct carriers that moved it - D5's main signal.               |
| `Median_Cost_CAD__c`, `P25_Cost_CAD__c`, `P75_Cost_CAD__c` | The range, not a point (D3).                                      |
| `Median_Rate_Per_Mile__c`                                  | Generalises across lanes, which is what the long tail needs.      |
| `Last_Moved_On__c`                                         | Recency; a lane last run in 2023 is not a live lane.              |
| `Sources__c`                                               | Which of quotes / bids / market tests / freight legs produced it. |

Built by `LaneEdgeBatch`, chained like the place batch: read loads and their
stops, group by place pair, then fold in `Benchmark_Rate__c` rows by their
stored keys, then freight plan legs. Rerunnable, never curated (D8).

## 4. How hard is this lane to cover

On the Lane Benchmark results card, beside the existing statistics.

- **Routine**: moved by several carriers, recently, with a narrow spread.
- **Workable**: fewer carriers or a wider spread.
- **Hard**: one or two carriers, or nothing in months.
- **Too thin to say**: below the evidence floor - the honest answer for most of
  the 3,536 thin places.

The band always shows its evidence: "4 carriers moved this lane in the last
year, 23 loads, 2,100-2,650 CAD." A pricer can argue with numbers; they cannot
argue with a score.

Where the exact lane is too thin, the province lane answers instead, labelled as
such - the same fallback phase 8 uses for Carriers to ask.

## 5. Building a lane from segments

Offered when the direct lane is thin or absent (D7), on a click, never
pre-computed.

1. **Candidates**: places that appear as a destination of a priced edge from the
   origin _and_ as an origin of a priced edge toward the destination. The
   curated handoff points stay in the candidate set, but are no longer the only
   way through.
2. **Envelope**: a path whose legs sum to more than about 10 % over the direct
   distance is dropped, as phase 8's estimates already do.
3. **Depth**: one hop first; two only when one finds nothing (D4).
4. **Cost**: the sum of each leg's median, shown as a range built from each leg's
   P25-P75, plus a handoff cost per hop that the pricer types - phase 8 made
   that a typed input because the data does not contain it, and that stays true.
5. **Evidence**: every leg shows its carrier count and last moved date, so a
   path resting on one carrier's single move two years ago is visibly that.

Paths are ranked by the middle of their range, and at most three are shown.

## 6. Limits, errors, security

- Reads are of `Lane_Edge__c` by indexed key, so a search costs a handful of
  rows rather than the thousands phase 8 measured.
- The batch is the expensive part and runs out of hours, like the place batch.
- The index is derived from data the running user may not be able to see
  directly, so it is read in system mode exactly as the lane search already is,
  and it stores no customer, no carrier rate attributable to one customer's RFP,
  and no bid identity - only counts, medians and ranges.
- A stale index is a correctness risk, not just a freshness one: every card
  shows the index's build date, and a lane whose last build predates its newest
  load says so.

## 7. Testing

- Apex: the batch folds all four sources into one edge; a lane with one carrier
  bands as Hard; a lane below the floor bands as Too thin; the path search
  respects the distance envelope, the depth cap and the top-three limit; a path
  whose legs are thin still reports its counts rather than hiding them.
- Browser check in PostProduc on the busiest province pair, with the query-row
  cost measured from a debug log, and on a lane known to have no direct history.

## 8. Out of scope

Rate prediction and seasonality (their own phase; the index is what they will
read). Automatic handoff-cost estimation. Paths deeper than two hops. Anything
that writes back to a carrier or a customer record.
