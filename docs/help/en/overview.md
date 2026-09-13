---
title: What these tools do
order: 10
hint: Lane Benchmark shows what a lane cost recently; the RFP Tool prices a customer's lane list from that history and from carrier bids.
---

## Two tools, one source of truth

**Lane Benchmark** answers "what did this lane cost recently?". You pick an origin and a destination, how precisely to match them, and how far back to look. It returns every matching carrier quote from Revenova loads plus the carrier bids recorded in the RFP Tool, with per-currency statistics and a suggested sell.

**RFP Tool** prices a whole customer request. You upload the customer's lane file, the tool matches each lane's ends to known places, loads the same history per lane, and lets you set a cost, a margin and a sell for every lane - one at a time, straight in the table, or in bulk - then export the priced list to Excel.

## Where the numbers come from

- **Loads**: carrier quotes on Revenova loads, matched by the lane's origin and destination.
- **Bids**: carrier rates recorded in the RFP Tool without a load (a quote a carrier gave you for an RFP). They show with a **Bid** badge and an expiry date.

Both sources are filtered by the lookback window (days since the quote or bid was created).

## Who to ask

Access is granted by the `Lane_Benchmark_User` and `RFP_Tool_User` permission sets. If a tab is missing or a button is greyed out with a permission message, ask your Salesforce admin.
