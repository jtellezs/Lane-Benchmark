---
title: Reading the lane trend
order: 45
hint: A monthly line of the lane's median rate, with a min-to-max band and a 6-month/1-year/3-year window. Hollow points are months with fewer than three rates.
---

## Under the statistics

The **Lane trend** card sits directly under **Statistics**, for the lane you already searched: a horizontal axis of months, a line through each month's median rate, and a shaded band between that month's lowest and highest rate. Point at a dot to see its month, median and rate count.

## Hollow points

A month with fewer than three rates is drawn as a hollow point and left off the median line — three rates are not enough to call a market. Its lowest and highest still shade the band, and it still counts in the "X months" total under the chart: a thin month is evidence, just not evidence the line should lean on.

## The window

**6 months**, **1 year** and **3 years** choose how far back the chart looks; **1 year** is the default. Switching windows asks the server again and redraws the chart.

## It follows the market-test filter

The chart reads the same lane and the same **Market test** filter (**Include**, **Exclude** or **Only**) that produced the statistics above it. Change the filter and both redraw together, so the trend never describes a different set of rates than the median it sits under.

## When there is not enough history

Fewer than two months with enough rates to trust, and the card says there is not enough history to show a trend, rather than draw an empty frame.

## "The trend may be incomplete."

A busy lane over a long window can hold more rows than the chart safely reads in one call. When that happens the chart is still drawn from what it read, with this note under it — narrow the window to see the rest.

## Rates counted outside the window

The chart picks up rates by the day they were created, over the window you chose, then places each one on the axis by the day it was quoted or the day it is valid from — a different date. A rate created inside the window can still be dated, by that second date, into a month outside it. Rather than drop it without saying so, the card counts how many rates this happened to and shows that count under the chart.
