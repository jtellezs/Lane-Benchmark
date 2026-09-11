import { LightningElement, api } from "lwc";

/** Money is shown with two decimals and no grouping, so the columns line up. */
function money(value) {
  if (value === null || value === undefined || value === "") {
    return "";
  }
  const n = Number(value);
  return Number.isFinite(n) ? n.toFixed(2) : "";
}

function placeText(city, province) {
  return [city, province].filter(Boolean).join(", ");
}

/**
 * "2 · median 2000.00" once the snapshot is Done, otherwise the status word
 * (Pending / Unresolved / No match / Failed) so the row says why it is empty.
 */
function historyText(lane) {
  if (lane.Hist_Status__c !== "Done") {
    return lane.Hist_Status__c || "";
  }
  const count = lane.Hist_Count__c || 0;
  const median = money(lane.Hist_Median__c);
  return median ? `${count} · median ${median}` : `${count}`;
}

function historyTitle(lane) {
  if (lane.Hist_Status__c !== "Done") {
    return "";
  }
  const parts = [
    ["min", money(lane.Hist_Min__c)],
    ["avg", money(lane.Hist_Average__c)],
    ["max", money(lane.Hist_Max__c)]
  ].filter(([, v]) => v !== "");
  const precision = lane.Hist_Precision__c
    ? ` (${lane.Hist_Precision__c})`
    : "";
  return parts.length
    ? `${parts.map(([k, v]) => `${k} ${v}`).join(" · ")}${precision}`
    : "";
}

export default class RfpLaneTable extends LightningElement {
  @api selectedId;
  @api currency = "CAD";

  _lanes = [];

  @api
  get lanes() {
    return this._lanes;
  }
  set lanes(value) {
    this._lanes = value || [];
  }

  get costHeader() {
    return this.currency ? `Cost (${this.currency})` : "Cost";
  }
  get sellHeader() {
    return this.currency ? `Sell (${this.currency})` : "Sell";
  }
  get hasLanes() {
    return this._lanes.length > 0;
  }

  get viewRows() {
    return this._lanes.map((l) => ({
      id: l.Id,
      rowNumber: l.Row_Number__c,
      rowClass:
        l.Id === this.selectedId ? "lane-row lane-row_selected" : "lane-row",
      originResolved: !!l.Origin_Resolved__c,
      originText: placeText(l.Origin_City__c, l.Origin_Province__c),
      originKey: l.Origin_Place__r ? l.Origin_Place__r.Key__c : null,
      destinationResolved: !!l.Destination_Resolved__c,
      destinationText: placeText(
        l.Destination_City__c,
        l.Destination_Province__c
      ),
      destinationKey: l.Destination_Place__r
        ? l.Destination_Place__r.Key__c
        : null,
      mode: l.Mode__c || "",
      equipment: l.Equipment_Type__c || l.Equipment_Category__c || "",
      histText: historyText(l),
      histTitle: historyTitle(l),
      costText: money(l.Cost__c),
      marginText:
        l.Margin__c === null || l.Margin__c === undefined
          ? ""
          : String(l.Margin__c),
      sellText: money(l.Sell__c),
      statusText: l.Cost__c ? "Priced" : ""
    }));
  }

  handleRowClick(event) {
    this.dispatchEvent(
      new CustomEvent("select", {
        detail: { laneId: event.currentTarget.dataset.laneId }
      })
    );
  }

  /**
   * The inline picker also fires on a precision or radius change, so only a
   * placechange that carries a key is worth a round trip to resolve the end.
   */
  handlePlaceChange(event) {
    const key = event.detail && event.detail.key;
    if (!key) {
      return;
    }
    const { laneId, side } = event.currentTarget.dataset;
    this.dispatchEvent(
      new CustomEvent("resolveend", { detail: { laneId, side, key } })
    );
  }
}
