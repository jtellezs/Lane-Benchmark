import { parseMargin, suggestedSell } from "c/marginMath";
import { bestBid, otherCurrencyCount } from "c/rfpMath";

/** The three values RFP_Lane__c.Cost_Source__c accepts. */
export const SOURCES = [
  { label: "Bid", value: "Bid" },
  { label: "History median", value: "History median" },
  { label: "Manual", value: "Manual" }
];

/** Two decimals, no grouping, so the numbers line up column by column. */
export function money(value) {
  if (value === null || value === undefined || value === "") {
    return "";
  }
  const n = Number(value);
  return Number.isFinite(n) ? n.toFixed(2) : "";
}

/** The cost the editor is currently showing, or null when it has none yet. */
export function costFor(source, { lane, bids, selectedBidId, manualCost }) {
  if (source === "Bid") {
    const picked = (bids || []).find((b) => b.Id === selectedBidId);
    return picked ? Number(picked.Rate__c) : null;
  }
  if (source === "History median") {
    const median = lane && lane.Hist_Median__c;
    return median === null || median === undefined ? null : Number(median);
  }
  const n = Number(manualCost);
  return manualCost !== "" && manualCost !== null && Number.isFinite(n)
    ? n
    : null;
}

export function bidOptions(bids) {
  return (bids || []).map((b) => ({
    label: `${b.Carrier_Display__c || "Carrier"} — ${money(b.Rate__c)} ${b.CurrencyIsoCode}${b.Status__c === "Expired" ? " (expired)" : ""}`,
    value: b.Id
  }));
}

export function bidRows(bids) {
  return (bids || []).map((b) => ({
    ...b,
    rateText: `${money(b.Rate__c)} ${b.CurrencyIsoCode}`,
    rowClass: b.Status__c === "Expired" ? "slds-text-color_weak" : "",
    buttonClass:
      b.Status__c === "Expired"
        ? "slds-button slds-button_reset bid-row slds-text-color_weak"
        : "slds-button slds-button_reset bid-row"
  }));
}

/**
 * Offered only against a real cost: with nothing costed yet there is nothing
 * for the cheapest bid to beat, and every bid would look like a saving.
 */
export function bestBidHint(bids, currency, cost) {
  const best = bestBid(bids, currency);
  if (!best || typeof cost !== "number" || !(cost > 0)) {
    return null;
  }
  if (!(Number(best.Rate__c) < cost)) {
    return null;
  }
  return `Use as cost: ${best.Carrier_Display__c || "a carrier"} at ${money(best.Rate__c)} ${currency}`;
}

export function otherCurrencyNote(bids, currency) {
  const n = otherCurrencyCount(bids, currency);
  if (!n) {
    return null;
  }
  return `${n} bid${n === 1 ? "" : "s"} in another currency ${n === 1 ? "is" : "are"} not compared`;
}

/** Exactly the fields RfpLaneController.saveLanePricing whitelists. */
export function pricingDetail({
  laneId,
  source,
  selectedBidId,
  cost,
  marginText,
  notes
}) {
  const margin = parseMargin(marginText);
  return {
    laneId,
    Cost__c: cost === undefined ? null : cost,
    Cost_Source__c: source,
    Selected_Bid__c: source === "Bid" ? selectedBidId || null : null,
    Margin__c: margin,
    Sell__c: suggestedSell(cost, margin),
    Notes__c: notes || null
  };
}

/**
 * Null until both ends are resolved to a place. Two lanes sharing a key share
 * their history, so the key — not the lane Id — decides when to search again.
 */
export function historyKey(lane) {
  const origin = lane?.Origin_Place__r?.Key__c;
  const destination = lane?.Destination_Place__r?.Key__c;
  if (!origin || !destination) {
    return null;
  }
  return [
    origin,
    destination,
    lane.Hist_Precision__c || "CITY",
    lane.Hist_Lookback_Days__c || 90
  ].join("~");
}

/** `RADIUS-<n><KM|MI>` as written by RfpHistoryService, else null. */
export function parseRadius(text) {
  const m = /^RADIUS-(\d+)(KM|MI)$/.exec(text || "");
  return m ? { radius: Number(m[1]), unit: m[2] } : null;
}

export function historyRequest(lane) {
  const r = parseRadius(lane.Hist_Precision__c);
  const precision = r ? "RADIUS" : lane.Hist_Precision__c || "CITY";
  return JSON.stringify({
    originKey: lane.Origin_Place__r?.Key__c,
    destinationKey: lane.Destination_Place__r?.Key__c,
    originPrecision: precision,
    destinationPrecision: precision,
    originRadius: r ? r.radius : null,
    destinationRadius: r ? r.radius : null,
    radiusUnit: r ? r.unit : "KM",
    lookbackDays: lane.Hist_Lookback_Days__c || 90,
    sourceFilter: "LOADS",
    rowLimit: 500,
    includeStopGeolocation: true
  });
}
