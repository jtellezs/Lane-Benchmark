---
title: Uploading a lane file and mapping
order: 70
hint: Upload the customer's .xlsx or .csv, match its columns to our fields (the mapping is remembered per customer), then import.
---

## The file

Accepted: `.xlsx`, `.xlsm`, `.xls`, `.csv` up to 3 MB and 2,000 lanes per project. The first row must be the headers. A second upload into the same project adds rows after the existing ones.

## Mapping the columns

The tool guesses which column is the origin city, destination postal code, mode, equipment, quantity and so on, and shows a sample of each. Fix any guess with the dropdowns. Origin and destination need at least a city or a postal code each. The mapping is remembered for this customer's next file.

## Import

**Import lanes** creates one lane per row and matches each end to a known place. The summary line reads "imported N, skipped N, unresolved ends N". Skipped rows had no usable origin or destination; unresolved ends are lanes whose city could not be matched - see **Unresolved lane ends**.
