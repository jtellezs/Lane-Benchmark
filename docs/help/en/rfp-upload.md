---
title: Uploading a lane file and mapping
order: 70
hint: Upload the customer's .xlsx or .csv, match its columns to our fields (the mapping is remembered per customer), then import.
---

## The file

Accepted: `.xlsx`, `.xlsm`, `.xls`, `.csv` up to 3 MB and 2,000 rows per file; keep a project under 2,000 lanes in total, the table shows at most that many. The first row must be the headers. A second upload into the same project adds rows after the existing ones.

## Mapping the columns

The tool guesses which column is the origin city, destination postal code, mode, equipment, quantity and so on, and shows a sample of each. Fix any guess with the dropdowns. Map both city columns, or both postal-code columns. The mapping is remembered for this customer's next file.

## Import

**Import lanes** creates one lane per row and matches each end to a known place. The summary line reads "imported N, skipped N, unresolved ends N". Skipped rows had neither an origin nor a destination; a row missing one end is imported with that end Unresolved. Unresolved ends are lanes whose city could not be matched - see **Unresolved lane ends**.
