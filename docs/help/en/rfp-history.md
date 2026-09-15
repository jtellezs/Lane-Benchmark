---
title: Loading history
order: 90
hint: Load history runs a Lane Benchmark search per lane. Choose precision, lookback, radius and whether to count other RFPs' bids, then read "N loads + M bids · median".
---

## Running it

Set **History precision** (City, Province or Radius), **Lookback (days)**, **Radius** and its **Unit**, and whether to **Include RFP bids**, then click **Load history**. Lanes are processed in batches with a progress bar; **Stop** ends the run after the current batch. **Refresh history** reruns every lane; **Retry failed** reruns only the lanes marked Failed.

## Radius fallback

With City precision, a lane whose city has no history is searched again within the radius. On a lane with a median, the History cell's tooltip shows which precision was used, for example `RADIUS-50KM`.

## Include RFP bids

When on (the default), carrier bids recorded on **other** RFP projects count alongside the loads, even after their validity date, as long as they are inside the lookback. Bids on the project you are pricing are never counted - they are your own inputs. The History cell then reads "5 loads + 1 bid · median 5500.00". When off, only loads count.

## Reading the cell

- `12 · median 5800.00`: twelve quotes matched, the median of the priced ones is 5,800.
- `3 · no median`: three matched but none had a price.
- **No match**: nothing within the lookback at that precision.
- **Failed**: the search hit an error.
- **Unresolved**: one end is not a known place.
- **Pending**: not run yet.

Statistics use only quotes in the lane's own currency.

## Trip miles and truck routes

Load history also fills the **Miles** of every lane it runs, without asking Mapbox. It takes the first of these that exists:

1. **History**: the median of the billed miles (Revenova's Distance (Miles), filled by PC\*Miler) on the loads the search matched, at the precision the history used. Bids have no miles and do not count.
2. **Truck route** or **Regular route**: the miles and drive hours of a route already stored for the lane's two places, from an earlier lane opening or Lane Benchmark search.
3. **Approx**: the straight-line distance between the two places × 1.2, the ratio measured on a year of billed loads.

A lane gets **No coordinates** when an end is not resolved to a place or has no position on the map, and **No route** when Mapbox found no road between the two places. Billed miles always win: opening a lane never replaces History miles with route miles. Direction matters: Montréal → Toronto and Toronto → Montréal are separate routes.
