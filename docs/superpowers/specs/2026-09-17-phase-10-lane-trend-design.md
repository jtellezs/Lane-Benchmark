# Phase 10 — Lane trend (how a lane's market moved)

Date: 2026-09-17. Roadmap: phase 10, built after phase 9 (market test). A chart
of a lane's rates over time, so a pricer can see whether the market is rising,
falling or flat instead of reading a single median.

Requested by the owner on 2026-09-16: "a visual way to see the market evolution
for a lane."

This phase does not depend on phase 9. The quote history it plots already
exists; phase 9 only adds more points to it. Phase 9 is built first because it
is smaller and because it gives the chart somewhere to live.

## 1. Decisions

| #   | Decision                                                                                                                                                                                                                                                                                                                 |
| --- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| D1  | **Server-side buckets, not raw rows.** The controller returns one point per month — count, median, min, max, per currency — rather than shipping rows to the browser to bucket there. A three-year window on a busy lane exceeds the 2,000-row `rowLimit`, and a truncated chart is a chart that lies without saying so. |
| D2  | **Reuse the lane match.** Bucketing runs over the same conditions `LaneQueries` builds for a search, so a trend and a search of the same lane agree about which quotes belong to it.                                                                                                                                     |
| D3  | **A row guard before reading.** The window is longer than a search's, so the phase 8 lesson applies: count the rows with `SELECT COUNT()` before reading them, and stop with a "the trend may be incomplete" note rather than risk an uncatchable `System.LimitException`.                                               |
| D4  | **Hand-drawn SVG, no charting library.** Salesforce will not load a script from a CDN, so a library means vendoring a static resource the app carries forever. A monthly series is a few hundred lines of SVG. `sheetJs` stays the only vendored library.                                                                |
| D5  | **Show n, and say when n is thin.** Every point carries its count. A month with fewer than three rates is drawn hollow and excluded from the trend line, because three quotes do not make a market.                                                                                                                      |
| D6  | **One currency at a time.** The chart plots the currency the pricer selected, as the stats card already does. Mixing CAD and USD on one axis would be meaningless.                                                                                                                                                       |

## 2. Today (read in the repo, 2026-09-17)

- `LaneSearchResult.Stats` is computed server-side: `count`, `countNonZero`,
  `min`, `max`, `avg`, `median`, `ratePerMileMedian`, keyed by currency. The
  LWC formats them and does no maths of its own.
- Every `LaneSearchResult.Row` carries `quoteDate` and `carrierTotal`. For bid
  rows `quoteDate` is `Valid_From__c` (`BidSearchService.cls:60`) and
  `createdDate` is the record's `CreatedDate`.
- `LaneSearchRequest.lookbackDays` is a free integer with a 90-day default and
  no cap; `rowLimit` defaults to 2,000.
- `LaneSearchService.search(LaneSearchRequest)` is the single public entry, and
  `LaneQueries` exposes `laneConditions` and `stateLaneConditions`.
- Phase 8 established that aggregates other than `COUNT()` charge every
  aggregated row against the 50,000 query-row limit, and that
  `System.LimitException` cannot be caught — hence D3.
- There is no charting library in the repo; the static resources are
  `helpCenter` and `sheetJs`.

## 3. What people see

A card under the lane's stats, on the Lane Benchmark results page and on the
phase 9 page, showing the same lane the pricer already chose.

- A horizontal axis of months, a vertical axis of rate, and a line through the
  monthly medians.
- A shaded band between each month's min and max, so the spread is visible
  rather than implied.
- A point per month labelled with its count on hover; thin months (D5) drawn
  hollow and skipped by the line.
- A window control: 6 months, 1 year, 3 years. Default 1 year.
- Under the chart, one plain sentence: "12 months, 148 rates, median 2,450 CAD,
  up 6% since October." The sentence is the part most pricers will read.

When the lane has fewer than two usable months, the card says so and draws
nothing. An empty chart frame invites a reader to see a trend that is not there.

## 4. Apex behaviour

A new `LaneTrendController.getTrend(String requestJson)` over a
`LaneTrendService`.

- Takes the same `LaneSearchRequest` the page already holds, with
  `lookbackDays` set from the window control.
- Builds conditions through `LaneQueries` (D2), runs `SELECT COUNT()` first
  (D3), and stops with `truncated = true` when the count exceeds the rows left.
- Reads the matching quote and bid rows with only the fields the buckets need —
  the date, the amount, the currency — not the full search projection.
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
  window; a single-currency filter never mixes currencies.
- Jest: the chart renders a point per month; thin months are hollow and skipped
  by the line; the hidden table matches the points; fewer than two usable months
  renders the empty message and no frame.
- Browser check in PostProduc: a busy lane over three years, with the query-row
  cost measured from a debug log, and the summary sentence checked against the
  stats card for the same window.

## 8. Out of scope

Forecasting, seasonality modelling, comparing two lanes on one chart, and
exporting the chart as an image.
