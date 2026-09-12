/**
 * Runs one RfpBulkController action over any number of lane ids, 200 per call
 * (the server refuses more), folding the per-call results into one. A chunk
 * that throws counts its ids as failed; the run carries on with the next one.
 */
import applyMedian from "@salesforce/apex/RfpBulkController.applyMedian";
import applyPricing from "@salesforce/apex/RfpBulkController.applyPricing";
import applyBid from "@salesforce/apex/RfpBulkController.applyBid";
import copyPricing from "@salesforce/apex/RfpBulkController.copyPricing";
import deleteLanes from "@salesforce/apex/RfpBulkController.deleteLanes";
import { chunk, series, mergeLanes } from "c/rfpBatch";

export const BULK_CHUNK = 200;

const CALLS = {
  median: (laneIds, p) => applyMedian({ laneIds, overwrite: !!p.overwrite }),
  pricing: (laneIds, p) =>
    applyPricing({
      laneIds,
      cost: p.cost ?? null,
      sell: p.sell ?? null,
      margin: p.margin ?? null
    }),
  bid: (laneIds, p) => applyBid({ laneIds, bidJson: JSON.stringify(p.bid) }),
  copy: (laneIds, p) => copyPricing({ sourceLaneId: p.sourceLaneId, laneIds }),
  delete: (laneIds) => deleteLanes({ laneIds })
};

const VERBS = {
  median: "Median applied to",
  pricing: "Pricing applied to",
  bid: "Carrier rate added to",
  copy: "Pricing copied to",
  delete: "Deleted"
};

export async function runBulk({
  action,
  ids,
  params = {},
  onProgress,
  isStopped
}) {
  const call = CALLS[action];
  if (!call) {
    throw new Error(`Unknown bulk action: ${action}`);
  }
  const total = {
    action,
    ids: ids || [],
    // The ids of the chunks that actually came back. A chunk that threw and a
    // chunk a Stop skipped are not in here, so the caller can tell the lanes
    // the server dealt with from the ones it never heard about.
    doneIds: [],
    lanes: [],
    updated: 0,
    skipped: 0,
    skippedIds: [],
    errors: [],
    failedIds: []
  };
  await series(chunk(ids, BULK_CHUNK), async (part) => {
    if (isStopped && isStopped()) {
      return;
    }
    try {
      const r = await call(part, params);
      total.doneIds.push(...part);
      total.lanes.push(...(r.lanes || []));
      total.updated += r.updated || 0;
      total.skipped += r.skipped || 0;
      total.skippedIds.push(...(r.skippedIds || []));
      total.errors.push(...(r.errors || []));
    } catch (e) {
      total.failedIds.push(...part);
      total.errors.push((e && e.body && e.body.message) || "A chunk failed.");
    }
    if (onProgress) {
      onProgress(part.length);
    }
  });
  return total;
}

/**
 * Folds a run's outcome into the lanes on screen. Deleted lanes are the ids of
 * the chunks that came back minus the lanes those calls returned; they leave
 * the list and the selection. A chunk that failed and a chunk a Stop skipped
 * are not in `doneIds`, so their lanes stay on screen — the server still has
 * them. (`ids` is the fallback for a result recorded before `doneIds` existed.)
 */
export function applyBulkResult(lanes, selectedIds, result) {
  if (result.action !== "delete") {
    return { lanes: mergeLanes(lanes, result.lanes), selectedIds };
  }
  const survivors = new Set((result.lanes || []).map((l) => l.Id));
  const attempted = result.doneIds || result.ids || [];
  const gone = new Set(attempted.filter((id) => !survivors.has(id)));
  return {
    lanes: (lanes || []).filter((l) => !gone.has(l.Id)),
    selectedIds: (selectedIds || []).filter((id) => !gone.has(id))
  };
}

export function summaryText(r) {
  const n = r.updated || 0;
  const parts = [
    `${VERBS[r.action] || "Applied to"} ${n} lane${n === 1 ? "" : "s"}`
  ];
  if (r.skipped) {
    parts.push(`${r.skipped} skipped`);
  }
  const failed = (r.failedIds || []).length;
  if (failed) {
    parts.push(`${failed} failed`);
  }
  if (r.errors && r.errors.length) {
    parts.push(r.errors[0]);
  }
  return parts.join("; ");
}
