---
title: Bulk actions
order: 130
hint: Choose Selected or All lanes, then Use median, Apply margin, cost or sell, Add carrier rate, or Delete. Runs go 200 lanes at a time with a Stop button.
---

## Scope

**Selected (N)** acts on the lanes you ticked; **All lanes (N)** acts on every lane in the project.

## Actions

- **Use median**: costs each lane from its history median. Lanes already costed from a bid or by hand are left alone; the bar then says how many and offers **Overwrite them**. Lanes without a median are reported separately.
- **Apply margin**, **Apply cost**, **Apply sell**: set that value on every lane in scope and recompute the rest.
- **Add carrier rate**: record the same bid on every lane in scope and select it as the cost (lanes in another currency are skipped).
- **Delete selected**: removes the lanes and their bids. It asks for a second click to confirm.

## Progress and Stop

Long runs show a progress bar. **Stop** ends the run after the current batch; the summary line says how many lanes were updated, skipped or failed.
