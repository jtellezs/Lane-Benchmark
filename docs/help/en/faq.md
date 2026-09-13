---
title: Questions and problems
order: 150
hint: No match, Failed, old history, wrong currency, missing tab: the usual causes and what to do.
---

## "No match" on a lane

The ends resolved but no quote or bid matched within the lookback and precision. Raise the radius (City precision already falls back to it), extend the lookback, or turn **Include RFP bids** on, then **Refresh history**. Mode and equipment filters exist only in Lane Benchmark.

## "Failed" on a lane

The search itself failed (usually a timeout on a very wide radius). Click **Retry failed**; if it keeps failing, narrow the radius or the lookback.

## The history looks old

History is a snapshot taken when you clicked Load or Refresh. **Refresh history** takes a new snapshot.

## The median is in the wrong currency

Statistics use only quotes in the lane's own currency (the project's currency). A lane with USD quotes only shows no CAD median; record a bid or type the cost.

## Who can see an RFP?

An RFP is visible to the people who can see its customer account, from the account page and in the RFP Tool list; Read access on the account is enough to work on it. If a project you expect is missing, ask the account owner or your admin for access to that account. Lane Benchmark shows every bid's carrier, rate and expiry to everyone, without the customer or the RFP.

## I cannot see the tab or a button says I lack permission

Ask your admin for the `Lane_Benchmark_User` and `RFP_Tool_User` permission sets.

## Something looks wrong

Send your admin the project name, the lane number and what you expected. Changes to these tools go through a pull request, so the fix will be tracked.
