---
title: Reading the lane trend
order: 45
hint: Nine windows from one week to three years, each grouped by day, week or month depending on length. Pick a window to draw the chart; hollow points mark buckets with too few rates for their size.
---

## Under the statistics

The **Lane trend** card sits directly under **Statistics**, for the lane you already searched: a horizontal axis of buckets, a line through each bucket's median rate, and a shaded band between that bucket's lowest and highest rate. Point at a dot to see its bucket, median and rate count.

## The window

**1 week**, **2 weeks**, **1 month**, **2 months**, **3 months**, **6 months**, **1 year**, **2 years** and **3 years** choose how far back the chart looks. **Nothing is drawn until you pick one** — the card waits, showing its buttons, because reading a trend over a busy lane is a real query and most searches never need it. Picking a window fetches that window and draws it; switching asks the server again and redraws. Searching a new lane clears the chart and waits to be asked again.

## How the chart groups rates

The size of a bucket follows the window you picked, not something you choose separately: **1 week**, **2 weeks** and **1 month** group rates by day; **2 months** and **3 months** group by week; **6 months** and longer group by month. Apex decides which from the window, so the axis, the hollow-point rule below and the summary sentence always agree on what kind of bucket they are describing.

## Hollow points

A hollow point marks a bucket with too few rates to trust for its size — three for a month, two for a week — and is left off the median line. Its lowest and highest still shade the band, and it still counts in the total under the chart: a thin bucket is evidence, just not evidence the line should lean on. At day buckets nothing is ever marked thin: a bucket only exists once it holds at least one rate, and one rate is all a day needs.

## On a quiet lane

A bucket only appears once it has a rate in it, so on a lane with little recent activity the shortest windows — **1 week** and **2 weeks** especially — can show very few points, sometimes none. That is the window doing exactly what it should: showing what is actually there. A longer window will usually fill back in.

## It follows the market-test filter

The chart reads the same lane and the same **Market test** filter (**Include**, **Exclude** or **Only**) that produced the statistics above it. Change the filter and both redraw together, so the trend never describes a different set of rates than the median it sits under.

## When there is not enough history

Fewer than two buckets with enough rates to trust, and the card says there is not enough history to show a trend, rather than draw an empty frame.

## "The trend may be incomplete."

A busy lane over a long window can hold more rows than the chart safely reads in one call. When that happens the chart is still drawn from what it read, with this note under it — narrow the window to see the rest.

## Which bucket a rate lands in

Each rate is placed on the axis by the day it was recorded, not by the day the freight is due to move. A quote you asked for today tells you about today's market whether the truck rolls next week or next month. The window you choose counts that same day, so every rate the chart finds is a rate it can place — nothing is quietly left off the axis, and the newest bucket is as complete as the older ones.

## Rates the chart leaves out

A row with no rate on it, and a row whose carrier total is zero, are not prices a market set, so the chart leaves them out — exactly as the median, lowest and highest in **Statistics** above already do. A bucket's rate count here is therefore the non-zero count, which can be smaller than the number of rows the results table shows for the same bucket.
