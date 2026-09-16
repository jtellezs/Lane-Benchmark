---
title: Editing in the table
order: 110
hint: Click a Cost, Margin or Sell cell and type. Enter saves and moves down, Tab moves down, Shift+Tab moves up, Escape cancels.
---

## Cells you can type in

**Cost**, **Margin** and **Sell** are editable in the table, like a spreadsheet. Click a cell (the row is selected at the same time), type a value and press:

- **Enter** or **Tab**: save and open the same cell on the next row.
- **Shift+Tab**: save and open the same cell on the previous row.
- **Escape**: close without saving.

Clicking elsewhere also saves. A cost typed here sets the cost source to Manual; a sell typed here is a manual sell (the **manual** tag) and the margin follows it.

## Errors

A value that cannot be saved (zero, negative, a margin over 100) shows a red message under the cell and the cell stays open until you fix it or press Escape.

## Identical lanes

When you price a lane that has twins in the same project (same ends, mode and equipment), a bar offers to copy the cost and sell to them. **Apply** copies; **Not now** dismisses.

## The Miles column

**Miles**, after **History**, is read-only: it shows the lane's trip length in miles, or in kilometres when **km** is selected in the toolbar. A small tag says where the value comes from:

- No tag: **History**, the median of the billed miles on the matched loads.
- `truck`: a Mapbox truck route.
- `route`: a regular driving route, used when the truck limits could not be met.
- `approx.`: the straight-line distance between the two places × 1.2.

"—" means the lane has no distance: hover it for the reason (history not loaded yet, no route found, or no coordinates). Load history fills the column. Opening a lane stores its route and replaces an `approx.` value with the route's miles when Mapbox finds one; the column shows the new value after your next price save, history run or page reload.

## The no rate tag

After **Load history**, the **History** cell shows a **no rate** tag when the lane has no priced carrier rate in its currency: the cell reads **No match**, or quotes matched but none had a price in the lane's currency (no median). Open the lane to see **Carriers to ask** and **Split-lane options** in the panel. Load history itself never looks for carriers.
