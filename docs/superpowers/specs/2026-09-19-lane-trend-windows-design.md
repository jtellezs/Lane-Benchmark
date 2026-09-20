# Lane trend windows — nine ranges, and a bucket that fits each one

Date: 2026-09-19. Extends phase 10 (the lane trend), which shipped with two windows
and a fixed monthly bucket. Requested by the owner on 2026-09-19: "i want one week,
2 weeks, one month, 2 month, 3 month, 6 month, 1 year, 2 years, 3 years".

No phase number is claimed here. Phases 10, 11 and 12 are taken and the roadmap
document stops at 8; the owner can slot this where it belongs.

## 0. Why the bucket has to change with the window

A window shorter than a couple of months cannot use a monthly bucket: one week is
one bucket, and a chart of one point is not a trend. So nine windows is not a
longer list of the same thing — it changes what a point means, which is why this
has its own design rather than a line in phase 10's.

Measured on PostProduc before deciding, because the answer turns on real density
rather than on argument:

| Search                                    | Rates      |
| ----------------------------------------- | ---------- |
| The lane the owner ran (radius 50/75)     | ~203 / yr  |
| Widest possible (Ontario→Quebec province) | 3,839 / yr |
| — the same, over 3 years                  | 11,499     |
| — the same, over 5 years                  | 16,006     |

So a typical lane runs about **16 rates a month, 3.9 a week, 0.56 a day**. That
number is what every decision below answers to.

## 1. Decisions

| #   | Decision                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         |
| --- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| W1  | **The bucket follows the window, and Apex decides it.** Day for one week, two weeks and one month; week for two and three months; month for six months and longer. Three ways to decide this were weighed: the component asks for a unit, Apex derives it, or Apex returns days and the component aggregates. The last breaks phase 10's D1, which is that the component formats and never calculates. The first splits one decision across two layers that can disagree — the drift that made the market-test filter mean two different things on one control, and that phase 10's own D2 exists to prevent. So Apex derives the unit and **states it on the response**; the component renders whatever it is told.                                             |
| W2  | **Nine windows: 1 week, 2 weeks, 1 month, 2 months, 3 months, 6 months, 1 year, 2 years, 3 years.** The mapping in W1 lands every one of them between roughly 7 and 37 points, which is the range a 640-unit viewBox can draw legibly once W4 thins the labels.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  |
| W3  | **The thin threshold scales with the bucket**: 3 rates for a month, 2 for a week, 1 for a day. Phase 10's D5 fixed it at 3 because every bucket was a month. Left fixed, a lane at 0.56 rates a day would have essentially every daily bucket thin — and thin buckets are skipped by the trend line, so the chart would show hollow dots with no line at all. That reads as broken rather than as honest, which is the same visual the three-year window was withdrawn for. **A consequence to state plainly: with a threshold of 1, no daily bucket is ever thin**, because a bucket only exists when it holds at least one rate. At that zoom the reader is looking at individual activity rather than a market median, and the hollow warning stops applying. |
| W4  | **At most about twelve axis labels, evenly spaced, with the year shown wherever it changes.** Both ends now need this: 37 monthly labels at three years and 30 daily labels at one month both collide at 11px in a 572-unit plot. The alternative the owner raised — numbering buckets so that a smaller number is nearer today — was weighed and rejected: it fixes the repeated-"Jan" ambiguity but turns "what happened in November" into arithmetic, gives a screen reader "17" instead of "Feb 2025", and does not actually solve crowding, since 37 two-character labels still collide.                                                                                                                                                                    |
| W5  | **`ROW_CAP` rises from 10,000 to 25,000 per side**, on a measurement rather than a guess. A three-year read of the widest search in the org was run in anonymous Apex: 11,499 rows cost **1,554,051 bytes of the 6,000,000 heap (26%)** and 11,499 of 50,000 query rows (23%). The old cap, not the platform, is what stopped a three-year window. 25,000 covers five years of the widest search with roughly two times the margin on both limits.                                                                                                                                                                                                                                                                                                               |
| W6  | **Truncation on a long window loses the oldest buckets, and that is worse than it sounds.** The reads order newest first, so a truncated three-year window silently drops exactly the early history the window was chosen to show. W5 is what keeps this out of reach for real searches; if a future window ever exceeds the cap, the note must say which end was lost rather than only that the trend may be incomplete.                                                                                                                                                                                                                                                                                                                                        |
| W7  | **`monthSpan` and `monthKey`/`monthIndex` are renamed.** They become `bucketSpan`, `bucketKey` and `bucketIndex`, and `LaneTrend` gains `bucketUnit` (`day`, `week` or `month`). A field named for months that holds days is the class of false statement this feature has already corrected eight times in comments, test names and help pages.                                                                                                                                                                                                                                                                                                                                                                                                                 |
| W8  | **The caption names the unit.** "30 days, 17 rates, median 2,450 CAD, up 6% since 21 Aug" rather than a count that silently means something different per window. Phase 10's Ruling 22 already made this sentence count buckets that carry rates rather than the axis span; W8 only adds which kind of bucket they are.                                                                                                                                                                                                                                                                                                                                                                                                                                          |

## 2. Today (read in the repo, 2026-09-19)

- `laneTrendChart.js` holds `WINDOWS` as `[6m, 1y]`; three years was withdrawn on
  2026-09-19 because it exceeded the row cap on a real province pair and its axis
  was unreadable. W4 and W5 remove both obstacles.
- `LaneTrendService.bucket(List<Sample>, Date windowStart)` buckets by calendar
  month only, via `monthKeyOf` and `monthsBetween`.
- `LaneTrendSummary.isUsable` drops a sample with no date, no amount, or a zero
  amount; `THIN_COUNT` is 3.
- Both sources bucket on `CreatedDate`, which is also the field the borrowed WHERE
  filters, so no sample can fall outside the window.
- `LaneTrendScope.narrow` chooses one currency and returns the plotted samples.

## 3. What people see

The window control offers nine ranges. It no longer fits on one line of the card
header at narrow widths, so it wraps; if wrapping proves ugly in the org it becomes
a picklist, which is a change to markup only.

Everything else is phase 10's card unchanged: a line through the bucket medians, a
band from each bucket's low to high, hollow dots where W3 says the evidence is thin,
the summary sentence, and the assistive-text table.

Two honest consequences the owner has been told and accepted:

- On a lane at 0.56 rates a day, the three shortest windows will often show very
  little. Adaptive bucketing makes them **legible**, not **populated**.
- At day buckets nothing is thin (W3), so the hollow signal — the one at-a-glance
  warning that a point is weak — is absent exactly where single rates dominate.

## 4. Apex behaviour

`LaneTrendService.trendFor` is unchanged in shape. Two additions:

- A unit is derived from `req.lookbackDays` per W1 and set on `trend.bucketUnit`.
- `bucket()` takes the unit. `bucketKeyOf` and `bucketsBetween` dispatch on it:
  day keys as `YYYY-MM-DD`, week keys as the ISO week's Monday, month keys as
  `YYYY-MM` — all three lexically sortable, which is what lets the existing
  `keys.sort()` stay chronological. `bucketSpan` counts buckets from the window
  start to today in the same unit.

`LaneTrendService.THIN_COUNT` becomes a function of the unit (W3) — it lives on the service,
beside `bucket()`, which is the only thing that reads it, not on `LaneTrendSummary`. Everything else
about the summary — the zero-amount rule, the median, the change between the first
and last non-thin buckets — is untouched.

`ROW_CAP` becomes 25,000 (W5). No other limit changes; both counts still run before
both reads.

## 5. The component

`WINDOWS` gains seven entries. The axis label thinning of W4 is a pure geometry
concern and belongs in the existing `geometry` getter, which already owns
positioning: it selects which buckets get a label and formats them with the year
when it changes. The caption reads `bucketUnit` to name its count (W8).

Nothing else in the component changes. The band, the line's thin filter, the hollow
fill, the hidden table and the race guard all work off whatever points arrive.

## 6. Limits, errors, security

No new access path: the same borrowed WHERE, the same `AccessLevel.SYSTEM_MODE`,
the same permission-set grant on `LaneTrendController`. The only limit that moves is
`ROW_CAP`, measured in W5.

A longer window costs proportionally more query rows and heap, both of which W5's
measurement bounds for the widest search the tool allows.

## 7. Testing

- Apex: each window maps to the unit W1 names; day, week and month keys all sort
  chronologically, including across a year boundary and across a week that spans two
  months; the thin threshold differs by unit and no daily bucket is ever thin;
  `bucketSpan` counts correctly in each unit; a read at the new cap still bounds.
- Jest: nine buttons render and each sends its own lookback; the axis never draws
  more than about twelve labels at any window; a year appears where it changes; the
  caption names the unit; the existing race, geometry and empty-state tests still
  hold under a non-month unit.
- Each test names the mutation it catches, and the ones that matter are watched
  failing — this feature has shipped four tests that could not fail for the reason
  they claimed, and the discipline is what caught them.
- In the org: run the shortest and longest windows on a real lane and confirm the
  axis is legible and the caption agrees with the chart.

## 8. Out of scope

A custom date range. Quarter buckets. A per-lane suggestion of which window to use.
Changing what the search itself does — this is the trend's control only.
