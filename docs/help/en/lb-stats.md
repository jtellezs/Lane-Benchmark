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

The truck route always runs between the two places you picked, even after a **Province / state** or **Postal prefix** search: **Truck route** then measures city to city, while **Trip** covers every load the wider search matched.

Each currency box adds **Rate per mile (median)**: the median of each priced quote's total divided by its load's miles, in that box's currency.

After a search with both an origin and a destination, the map draws the truck route (pins A and B, the main route and up to two alternatives, a legend line per route) in place of the plain preview; a radius search keeps its radius preview under the route, and when no route is available the preview stays. The route is asked from Mapbox once per pair of places and stored, so the next search on the same lane reuses it; **Refresh route** asks again. The results table has a **Miles** column (bids show "—"), and the CSV export carries it.

The **mi** and **km** buttons in the card header switch every distance on the page, per-mile rates included. The choice is remembered in this browser, and the RFP Tool uses it too.

## Carriers to ask

When a search finds no priced carrier rate in the currency you filtered on (in any currency when **Currency** is All), and both ends are places from the list, a **Carriers to ask** card appears under **Statistics**, above the map. It names carriers that know the lane, so you know whom to ask for a price. It never shows an amount.

The heading reads "No carrier rate on this lane in CAD. These carriers quoted or moved it before; amounts are not shown." (without "in CAD" when no currency is filtered). Each carrier shows:

- its name, as a link to the carrier's account when you can open that account;
- **3 moved · 5 quoted · last seen 2026-07-08**: the loads it moved (accepted quotes and legs of split shipments) and the loads it quoted;
- where it was found: **Quote**, **Split leg** or both;
- a **Blacklisted** badge when the carrier's account is blacklisted. Blacklisted carriers stay in the list so you recognise them; do not ask them for a price.

The card first looks at the same lane over the last 3 years, with your search's precision on each end (a radius end uses its city) and its mode, equipment and hazmat filters; the lookback, currency, quote status and source filters do not apply, and Market Test quotes never count. When that finds nobody, it shows the top 10 carriers on the state or province lane over the last year, ranked by loads moved: "No carrier on this exact lane. Top carriers on QC to ON over the last year." That second step is skipped when both ends were searched by province or state. When neither step finds anyone, the card says "No carrier found on this lane or on its state or province lane." Trans-Pro's own intercompany carrier accounts are never listed.

"The list may be incomplete." means the card stopped early to stay within Salesforce limits. If the card cannot load, click **Retry**.

## Split-lane options

At the bottom of the page, under the results, **Split-lane options** shows how the lane has been moved in two or more legs by different carriers. Nothing is looked up until you click the button, so the direct results always come first. The button is hidden when an end is not a place from the list.

- **History**: split shipments on the lane over the last 12 months (by the customer load's date), grouped by handoff point, most shipments first: "Via Laredo, TX · SFMN Park ITC Laredo yard · 34 shipments". Each leg line gives the leg's lane, its carriers with the number of legs each one moved, and the leg's median cost: "Leg 1 General Escobedo, NL → Laredo, TX · Q Transportes (18), Fletes Mex (9) · median 1,248 CAD". "Total per shipment, median 6,453 CAD (31 shipments)" is the median of each shipment's own leg total, over the shipments whose legs all have a cost. A leg without a cost shows carrier names only. Shipments with a cancelled leg, or with an intercompany carrier on a leg, are left out.
- **Estimate**: when the lane has no split history, the card tries the active handoff points on the admin list (today Laredo TX, San Diego CA and Calexico CA) that add at most about 10 % distance, up to 3, closest first: "Estimate via Laredo, TX · +6 % distance". Each leg shows its carriers and the median cost of the loads moved on that leg over the last year. Type the yard, transload or cross-dock cost in **Handoff cost**: **Estimate total** is leg 1's median + leg 2's median + that cost. A leg without a cost gives no total. With neither history nor a close handoff point, the card says "No split shipment on this lane in the last 12 months, and no handoff point is close enough for an estimate."

The **CAD** and **USD** buttons in the card header switch every amount on the card. The card starts in the currency you filtered on, or in CAD. Leg costs are stored in CAD; in USD each load's cost is converted at Salesforce's USD exchange rate for that load's date, and the note "Converted at the USD rate of 2026-08-11." gives the start date of the latest rate used ("No USD exchange rate is available." when Salesforce has none). **Direct median 5,800 CAD** repeats your search's median from **Statistics** in the card's currency, for comparison; it is hidden when the search has no median in that currency. A blacklisted leg carrier carries the **Blacklisted** badge. "The list may be incomplete." and **Retry** work as in **Carriers to ask**. On Lane Benchmark the card is for information; to use a split cost, price the lane in the RFP Tool.

## Duplicates

The same quote can appear on several loads. Identical rows (same carrier, lane, mode, equipment and total) are counted once; the header says how many duplicates were removed.
