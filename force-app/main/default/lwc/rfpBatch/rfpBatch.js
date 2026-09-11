/**
 * Pure helpers for the RFP workbench's chunked round trips: splitting a work
 * list into Apex-sized calls, folding returned lanes back into the list on
 * screen, and picking which lanes a history run covers.
 */

/**
 * Runs `step(item, index)` over the items one at a time, waiting for each before
 * starting the next. A chained reduce rather than a for/await loop, which the
 * project's ESLint config rules out; `step` itself decides whether a Stop has
 * ended the run, since every queued step still gets its turn.
 */
export const series = (items, step) =>
  (items || []).reduce(
    (chain, item, index) => chain.then(() => step(item, index)),
    Promise.resolve()
  );

/** Splits `list` into groups of at most `size`, in order; the last group is short. */
export function chunk(list, size) {
  const items = list || [];
  const step = Math.max(1, Math.trunc(size) || 1);
  const groups = [];
  for (let i = 0; i < items.length; i += step) {
    groups.push(items.slice(i, i + step));
  }
  return groups;
}

/**
 * Replaces lanes by Id, keeping the order the table already shows. `updated` is
 * a returned lane or a list of them; ids the list does not hold are ignored.
 * Lanes are replaced rather than spread over, so a field Apex cleared to null
 * (and therefore left out of its JSON) cannot survive as a stale value.
 */
export function mergeLanes(lanes, updated) {
  const list = Array.isArray(updated) ? updated : updated ? [updated] : [];
  if (!list.length) {
    return lanes || [];
  }
  const byId = {};
  list.forEach((lane) => {
    if (lane && lane.Id) {
      byId[lane.Id] = lane;
    }
  });
  return (lanes || []).map((lane) => byId[lane.Id] || lane);
}

const bothEndsResolved = (lane) =>
  !!(lane.Origin_Resolved__c && lane.Destination_Resolved__c);

/**
 * The lanes a history run covers. Only a lane with both ends resolved has the
 * place keys a snapshot matches on, so every mode starts from those:
 * - "all" (Refresh history) re-runs every resolved lane,
 * - "failed" (Retry failed) re-runs the ones a failed chunk left behind,
 * - "pending" (Load history) runs the ones that have no snapshot yet.
 */
export function lanesForHistory(lanes, mode) {
  const resolved = (lanes || []).filter(bothEndsResolved);
  if (mode === "all") {
    return resolved;
  }
  const wanted = mode === "failed" ? "Failed" : "Pending";
  return resolved.filter((lane) => lane.Hist_Status__c === wanted);
}
