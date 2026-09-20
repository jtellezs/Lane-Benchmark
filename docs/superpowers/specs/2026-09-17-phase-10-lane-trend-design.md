# Phase 10 — Lane trend (how a lane's market moved)

Date: 2026-09-17. Roadmap: phase 10, built after phase 9 (market test). A chart
of a lane's rates over time, so a pricer can see whether the market is rising,
falling or flat instead of reading a single median.

Requested by the owner on 2026-09-16: "a visual way to see the market evolution
for a lane."

This phase does not depend on phase 9. The quote history it plots already
exists; phase 9 only adds more points to it. Phase 9 is built first because it
is smaller and because it gives the chart somewhere to live.

**Amended 2026-09-18, after phases 9 and 12 shipped.** Two things this spec
assumed have changed, and the decisions taken at the amendment are D7 and the
revised section 3. First, "the phase 9 page" no longer exists: PR #38 moved the
market test onto the Lane Benchmark page, so there is one page to site the chart
on, and it now carries a statistics card, a selling card and a market test card
before the results table. Second, phase 12 added `marketTestFilter`
(Include / Exclude / Only) to `LaneSearchRequest`, which did not exist when D2
was written - so "reuse the lane match" now has a concrete extra obligation.

**Amended again 2026-09-19, during the whole-branch fix wave.** Two things this spec
specified are now wrong on purpose, both decided by the owner after the review measured
them.

First, **both sources are bucketed on `CreatedDate`** - when the rate was recorded - and
not on `Quote_Date__c` for quotes or `Valid_From__c` for bids. `Quote_Date__c` is the
formula `IF(!ISBLANK(Shipping_Date__c), Shipping_Date__c, DATEVALUE(CreatedDate))` over
`rtms__Load__r.rtms__Expected_Ship_Date2__c`, so a quote on freight that has not shipped
yet is dated in the future: 363 of 69,215 PostProduc quotes over 365 days (0.5%), but
**341 of 4,892 over 30 days (7.0%)**, because a quote is future-dated precisely while its
freight is still ahead of it. The chart dropped every one of them, so the current month -
the month a pricer reads, and the month that sets `changePct` and `lastLabel` - was the
month most damaged. The axis means _when the evidence arrived_: a quote solicited today for
freight moving next month is evidence about today's market, and the ship date describes the
freight, not the market. It is also the field the borrowed WHERE (D2) already filters on, so
what the query admits and what the axis can hold are now one field, and `CreatedDate` cannot
be set into the future at all. Sections 2 and 4 are amended in place below, for the trend only:
the search's results table still reports a bid's `Valid_From__c` as its quote date, and the bid
WHERE still uses `Valid_From__c` to decide whether a bid is currently valid.

That decision also retires the window partition the earlier fix rounds built (the
`outsideWindow` count, and the page line that reported it). With the bucketing field equal to
the filtered field, no row read can fall outside the axis, so the partition was provably dead,
and it was never a guard: what it actually did was delete the 7%. A test that asserts the axis
position of a row whose `Valid_From__c` is 400 days old replaces it, so a future change of
bucketing field fails loudly instead of hiding quietly.

Second, **zero-amount rows are excluded**, matching the statistics card the chart sits
under: `LaneSearchService.stats()` has always computed its median, min, max and avg from
non-zero totals only. 1,986 of 69,215 PostProduc quotes over 365 days (2.9%) carry a zero
carrier total, and each one pinned its month's `minimum` to 0, which anchored the y axis at
zero, squashed the median line into the top of the frame, and printed a median the card
directly above contradicted. `totalRates` is therefore the card's `countNonZero` for the same
rows. A consequence taken deliberately: **D5's thin-month denominator is now the non-zero
count**, so a month of five rows of which three are zero is a month of two rates and is drawn
hollow. That is what D5 says - two priced quotes do not make a market (owner, 2026-09-19).

## 1. Decisions

| #   | Decision                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         |
| --- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| D1  | **Server-side buckets, not raw rows.** The controller returns one point per month — count, median, min, max, per currency — rather than shipping rows to the browser to bucket there. A three-year window on a busy lane exceeds the 2,000-row `rowLimit`, and a truncated chart is a chart that lies without saying so.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         |
| D2  | **Reuse the lane match.** Bucketing runs over the same conditions `LaneQueries` builds for a search, so a trend and a search of the same lane agree about which quotes belong to it.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             |
| D3  | **A row guard before reading.** The window is longer than a search's, so the phase 8 lesson applies: count the rows with `SELECT COUNT()` before reading them, and stop with a "the trend may be incomplete" note rather than risk an uncatchable `System.LimitException`.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| D4  | **Hand-drawn SVG, no charting library.** Salesforce will not load a script from a CDN, so a library means vendoring a static resource the app carries forever. A monthly series is a few hundred lines of SVG. `sheetJs` stays the only vendored library.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        |
| D5  | **Show n, and say when n is thin.** Every point carries its count. A month with fewer than three rates is drawn hollow and excluded from the trend line, because three quotes do not make a market.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              |
| D6  | **One currency at a time.** The chart plots the currency the pricer selected, as the stats card already does. Mixing CAD and USD on one axis would be meaningless.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               |
| D7  | **The trend honors the market-test filter** (owner, 2026-09-18). Whatever Include / Exclude / Only the pricer set on Lane Benchmark, the trend plots the same rows the stats card counted. This is D2 carried to its conclusion: a chart that describes a different row set than the median printed directly above it is the chart D1 refuses to draw - one that lies without saying so. It costs nothing, because the request the page already holds carries the filter, so routing the trend through the same condition assembly inherits it; and because the request JSON is the cacheable key, flipping the filter redraws rather than serving the previous answer. Deliberately **not** extended: a month leaning mostly on market-test rates is not marked differently, because D5's hollow point already means "do not trust this month" and giving one visual two meanings muddies both. |

## 2. Today (read in the repo, 2026-09-17)

- `LaneSearchResult.Stats` is computed server-side: `count`, `countNonZero`,
  `min`, `max`, `avg`, `median`, `ratePerMileMedian`, keyed by currency. The
  LWC formats them and does no maths of its own.
- Every `LaneSearchResult.Row` carries `quoteDate` and `carrierTotal`. For bid
  rows `quoteDate` is `Valid_From__c` (`BidSearchService.cls:60`) and
  `createdDate` is the record's `CreatedDate`. (Still true of the search's own
  results table. The trend does **not** inherit either date: it buckets both
  sources on `CreatedDate` - see the 2026-09-19 amendment.)
- `LaneSearchRequest.lookbackDays` is a free integer with a 90-day default and
  no cap; `rowLimit` defaults to 2,000.
- `LaneSearchService.search(LaneSearchRequest)` is the single public entry, and
  `LaneQueries` exposes `laneConditions` and `stateLaneConditions`.
- Phase 8 established that aggregates other than `COUNT()` charge every
  aggregated row against the 50,000 query-row limit, and that
  `System.LimitException` cannot be caught — hence D3.
- There is no charting library in the repo; the static resources are
  `helpCenter` and `sheetJs`.

Read again at the amendment (2026-09-18):

- `LaneSearchRequest.marketTestFilter` exists, and `MarketTestFilter.forQuotes`
  and `.forBids` build the two halves of its condition - the quote half on the
  house account's current name, the bid half on the phase 9 marker or the
  account id.
- Bid rows are `Benchmark_Rate__c`, which `BidSearchService` reports dated on
  `Valid_From__c`; quote rows are `rtms__CarrierQuote__c`, whose only customer
  field is the text `Customer_Name__c`. (The trend buckets both on
  `CreatedDate` instead - 2026-09-19 amendment.)
- The Lane Benchmark page composes eight cards today, in this order: statistics,
  selling, market test rates, carriers to ask, route map, map preview, results,
  split-lane options.

## 3. What people see

Its own card directly under the statistics card on the Lane Benchmark page,
showing the same lane the pricer already chose - so the page reads in the order a
pricer thinks: what is the median, then how did it move. The card pushes selling,
market test and carriers down one slot each, which is the cost of the placement
and was accepted for it (owner, 2026-09-18). The second home this spec named,
"the phase 9 page", is gone; PR #38 retired it.

The chart reads the searched lane out of `lastRequestJson`, as `marketTestRates`
and `carrierLeads` already do, so it follows the lane with no new plumbing.

- A horizontal axis of months, a vertical axis of rate, and a line through the
  monthly medians.
- A shaded band between each month's min and max, so the spread is visible
  rather than implied.
- A point per month labelled with its count on hover; thin months (D5) drawn
  hollow and skipped by the line.
- A window control: 6 months, 1 year. Default 1 year. **Three years was withdrawn on
  2026-09-19** (owner decision, on a measurement): the busiest province pair in the org runs
  about 3,839 quotes a year, so three years lands near 11,500 against the 10,000-per-side cap
  named in section 4 - a real lane would have truncated routinely. The 37-month axis was also
  unreadable, since labels are month-only and repeat. It can return once the axis thins its
  labels and the cap is revisited.
- Under the chart, one plain sentence: "12 months, 148 rates, median 2,450 CAD,
  up 6% since October." The sentence is the part most pricers will read.

When the lane has fewer than two usable months, the card says so and draws
nothing. An empty chart frame invites a reader to see a trend that is not there.

## 4. Apex behaviour

A new `LaneTrendController.getTrend(String requestJson)` over a
`LaneTrendService`.

- Takes the same `LaneSearchRequest` the page already holds, with
  `lookbackDays` set from the window control.
- Builds conditions through `LaneQueries` **and** the same `MarketTestFilter`
  halves the search uses (D2, D7), runs `SELECT COUNT()` first (D3), and stops
  with `truncated = true` above a cap of **10,000 rows**.
- Why 10,000 against the search's 2,000: a three-year window legitimately holds
  more than a 90-day search, `getTrend` is its own transaction with its own
  50,000 query-row budget, and 10,000 rows of three small fields sits far inside
  the 6 MB synchronous heap. Over the cap the chart is still drawn from what was
  read, with the note - a drawn-and-flagged chart beats a refused one.
- Two sources, one series: quotes from `rtms__CarrierQuote__c` and bids from
  `Benchmark_Rate__c`, **both dated on `CreatedDate`** - when the rate was
  recorded, which is the field the borrowed WHERE already filters on
  (2026-09-19 amendment; `Quote_Date__c` and `Valid_From__c` are not used for
  the axis) - each narrowed to the selected currency (D6), merged before
  bucketing.
- Bucketing is Apex, not `GROUP BY CALENDAR_MONTH`, for two reasons: a median
  cannot be expressed in SOQL at all, and phase 8 established that any aggregate
  other than `COUNT()` charges every aggregated row against the 50,000-row
  limit - so the guard would cost the very rows it is meant to protect.
- Reads the matching quote and bid rows with only the fields the buckets need —
  `CreatedDate`, the amount, the currency — not the full search projection. A
  row with no amount, or an amount of zero, is dropped rather than bucketed, so
  the chart and the statistics card above it exclude the same rows
  (2026-09-19 amendment).
- Groups by calendar month in Apex, computing count, median, min and max per
  month per currency, and returns a compact `LaneTrend` result: a list of
  points, the currency, the window, and `truncated`.
- Cacheable (`@AuraEnabled(cacheable=true)`), like the search, since a trend
  over closed months does not change minute to minute.

## 5. The component

A `laneTrendChart` LWC that takes the points and draws them.

- An inline `<svg>` with a `viewBox`, so it scales without a resize listener.
- Colours from SLDS design tokens, so it reads correctly in both themes rather
  than hard-coded hex.
- Accessible: the SVG carries a title and description, and the same numbers are
  rendered as a visually hidden table, so the trend is reachable by screen
  reader and copyable.
- No animation and no tooltips library: hover shows a native `<title>`.

## 6. Limits, errors, security

- The trend reads through the same system-mode services the search uses; it adds
  no new access path and exposes no row a search of the same lane would not.
- `truncated` surfaces as "The trend may be incomplete" under the chart, with
  the advice to narrow the window — the same wording pattern phase 8 used.
- A window of three years on a busy province pair is the expensive case; the
  guard (D3) is what keeps it from throwing, and the browser check must measure
  it on the busiest pair in PostProduc before the phase is called done.

## 7. Testing

- Apex: months with no rates leave gaps rather than zeros; medians match a
  hand-computed fixture; the row guard trips before the read on an oversized
  window; a single-currency filter never mixes currencies; and **Exclude moves
  the chart** - a lane whose only rates are market-test plots nothing under
  Exclude and plots them under Include, which is the test that D7 is real rather
  than asserted.
- Jest: the chart renders a point per month; thin months are hollow and skipped
  by the line; the hidden table matches the points; fewer than two usable months
  renders the empty message and no frame.
- Browser check in PostProduc: a busy lane over three years, with the query-row
  cost measured from a debug log, and the summary sentence checked against the
  stats card for the same window.

## 8. Out of scope

Forecasting, seasonality modelling, comparing two lanes on one chart, and
exporting the chart as an image.
