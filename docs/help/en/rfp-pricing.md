---
title: Pricing a lane
order: 100
hint: Pick a cost source (a bid, the history median or a number you type), set a margin or a sell price, then Save price.
---

## The panel

Click a lane to open its panel on the right. It stays in view while you scroll the table.

## Cost source

- **Bid**: pick one of the carrier rates recorded for this lane. The cost is the bid's rate.
- **History median**: the median from the last history run.
- **Manual**: type the cost yourself.

## Margin or sell

Type a **Margin %** and the sell follows ("Sell follows the margin"), or type a **Sell** and the margin follows ("Margin follows the sell"). A sell you typed is kept when the cost changes later; the table shows a **manual** tag on it. Type a **Margin %** to go back to margin mode; the sell is recomputed from it.

## Save

**Save price** writes the cost, margin and sell to the lane and marks it **Priced**. **Add carrier rate** records a new bid for this lane; it then appears in the panel's bid list and in the **Bid** choice. To use it, switch **Cost source** to **Bid**, pick it in the **Bid** list, then click **Save price**.

## Trip miles and truck routes

Under the lane title, the panel shows the lane's miles and where they come from (see **Loading history**). Beside the prices, **Cost per mile** and **Sell per mile** divide the cost and the sell by those miles and follow what you type.

The **mi** and **km** buttons in the toolbar, next to **Include RFP bids**, switch the table, the panel and the map legend between miles and kilometres; per-mile values become per-km values. The choice is remembered in this browser, and Lane Benchmark opens with the same unit.

When the panel opens, it draws the route on the map: pin A at the origin, pin B at the destination, the main route as a thick blue line and up to two alternatives in orange and grey. The legend gives each route's distance and drive hours. A **Truck route** keeps to the truck limits of the Truck Routing Setting (by default 4.11 m high, 2.6 m wide, 36.29 t); when Mapbox cannot keep to them, the panel shows a regular driving route instead, headed "Regular route — truck limits could not be met". Mapbox has no hazmat option, so a hazmat lane gets the same route as any other lane.

The route is asked from Mapbox once per pair of places and stored; reopening the lane reuses it. **Refresh route** asks Mapbox again and replaces the stored route. When the lane's miles do not come from History, the route's miles and hours are written to the lane (Truck route or Regular route); History miles are never replaced. If Mapbox cannot be reached, the panel says "The truck route is not available right now." and the lane keeps its miles. When Mapbox finds no road even without truck limits (across water without a ferry, for example), the lane shows **No route**.

While **Load history** or a bulk action is running, the panel holds its route request: the map shows its spinner, **Refresh route** waits, and the route is asked for when the run ends.

The Excel export carries Miles, Km, Miles source, Route hours, Cost per mile and Sell per mile for every lane.

## Results

Below the form, the lane's history rows are listed exactly as Lane Benchmark shows them, so you can see which quotes made the median.
