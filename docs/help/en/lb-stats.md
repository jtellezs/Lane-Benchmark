---
title: Reading the statistics
order: 40
hint: One box per currency: min, median, average, max over the priced quotes, and a suggested sell from the margin you type.
---

## One box per currency

Statistics are never mixed across currencies. Each box shows how many quotes matched and how many had a price, then the minimum, median, average and maximum of the priced ones.

## Margin and suggested sell

Type a margin percentage (15 is the default) or click **15%** / **20%**. The box shows **Sell (median)** and **Sell (average)**: the median or average cost plus that margin. These are suggestions, not prices; nothing is saved here.

## Trip miles and truck routes

The **Statistics** card also shows how long the trip is:

- **Trip: 1,234 mi · median of 12 loads**: the median of the billed miles on the matched loads. Bids have no miles and do not count.
- **Truck route: 1,260 mi · 21.5 h**: the Mapbox truck route between the two places, with its drive hours. **Regular route** instead means the truck limits could not be met, so a regular driving route is shown.

Each currency box adds **Rate per mile (median)**: the median of each priced quote's total divided by its load's miles, in that box's currency.

After a search with both an origin and a destination, the map draws the truck route (pins A and B, the main route and up to two alternatives, a legend line per route) in place of the plain preview; a radius search keeps its radius preview under the route, and when no route is available the preview stays. The route is asked from Mapbox once per pair of places and stored, so the next search on the same lane reuses it; **Refresh route** asks again. The results table has a **Miles** column (bids show "—"), and the CSV export carries it.

The **mi** and **km** buttons in the card header switch every distance on the page, per-mile rates included. The choice is remembered in this browser, and the RFP Tool uses it too.

## Duplicates

The same quote can appear on several loads. Identical rows (same carrier, lane, mode, equipment and total) are counted once; the header says how many duplicates were removed.
