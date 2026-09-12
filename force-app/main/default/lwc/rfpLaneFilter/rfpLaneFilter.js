/**
 * Pure helpers for the lane table's filter bar and the "same lane" copy offer.
 * Nothing here touches Apex or the DOM.
 */
export const STATUS_FILTERS = [
  { label: "All lanes", value: "all" },
  { label: "Unpriced", value: "unpriced" },
  { label: "No history match", value: "nomatch" },
  { label: "Unresolved ends", value: "unresolved" },
  { label: "Manual cost or sell", value: "manual" },
  { label: "Selected", value: "selected" }
];

const unpriced = (l) => l.Cost__c === null || l.Cost__c === undefined;

const MATCHERS = {
  all: () => true,
  unpriced,
  nomatch: (l) => l.Hist_Status__c === "No match",
  unresolved: (l) => !l.Origin_Resolved__c || !l.Destination_Resolved__c,
  manual: (l) => l.Cost_Source__c === "Manual" || l.Sell_Source__c === "Manual",
  selected: (l, selected) => selected.has(l.Id)
};

const TEXT_FIELDS = [
  "Origin_City__c",
  "Origin_Province__c",
  "Origin_Postal__c",
  "Destination_City__c",
  "Destination_Province__c",
  "Destination_Postal__c",
  "Equipment_Type__c"
];

export function applyFilter(
  lanes,
  { status = "all", text = "", selectedIds = [] } = {}
) {
  const match = MATCHERS[status] || MATCHERS.all;
  const selected = new Set(selectedIds || []);
  const needle = (text || "").trim().toLowerCase();
  return (lanes || []).filter(
    (l) =>
      match(l, selected) &&
      (!needle ||
        TEXT_FIELDS.some((f) =>
          String(l[f] || "")
            .toLowerCase()
            .includes(needle)
        ))
  );
}

const equipmentOf = (l) => l.Equipment_Type__c || l.Equipment_Category__c || "";

/**
 * The unpriced lanes that are the same lane again: same two places, same mode,
 * same equipment. An unresolved end has no place, so it never pairs, and a lane
 * with no cost of its own has nothing to offer — a notes-only save must not
 * offer to copy a null price onto its twins.
 */
export function siblings(lanes, lane) {
  if (!lane || !lane.Origin_Place__c || !lane.Destination_Place__c) {
    return [];
  }
  if (unpriced(lane)) {
    return [];
  }
  return (lanes || []).filter(
    (l) =>
      l.Id !== lane.Id &&
      unpriced(l) &&
      l.Origin_Place__c === lane.Origin_Place__c &&
      l.Destination_Place__c === lane.Destination_Place__c &&
      (l.Mode__c || "") === (lane.Mode__c || "") &&
      equipmentOf(l) === equipmentOf(lane)
  );
}
