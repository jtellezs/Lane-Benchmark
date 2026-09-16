import { LightningElement, api, wire } from "lwc";
import {
  APPLICATION_SCOPE,
  MessageContext,
  subscribe,
  unsubscribe
} from "lightning/messageService";
import DISTANCE_UNIT from "@salesforce/messageChannel/Distance_Unit__c";
import { inlineEdit } from "c/rfpPricing";
import { readUnit, formatDistance } from "c/distanceUnit";

/** The three columns the pricer can type into, in column order. */
const EDITABLE = ["cost", "margin", "sell"];

/** Why a typed value was refused, shown under the cell it was typed in. */
const ERRORS = {
  cost: "Enter a cost above zero",
  sell: "Enter a sell above zero",
  margin: "Margin must be 0 to 100"
};

/** The stored value as text, so an untouched draft can be recognised. */
const rawText = (lane, field) => {
  const v = { cost: lane.Cost__c, margin: lane.Margin__c, sell: lane.Sell__c }[
    field
  ];
  return v === null || v === undefined ? "" : String(v);
};

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

/** "1 load" / "12 loads", "1 bid" / "3 bids". */
function plural(n, word) {
  return `${n} ${word}${n === 1 ? "" : "s"}`;
}

/** How many rows the snapshot counted, split by source when any were bids. */
function historyCount(lane) {
  const count = lane.Hist_Count__c || 0;
  const bids = lane.Hist_Bid_Count__c || 0;
  if (bids <= 0) {
    return `${count}`;
  }
  // A count below the bid count cannot come from the server; guard the
  // arithmetic anyway so a hand-edited lane never reads "-1 loads".
  return `${plural(Math.max(count - bids, 0), "load")} + ${plural(bids, "bid")}`;
}

/**
 * "2 · median 2000.00" once the snapshot is Done — or "12 loads + 3 bids ·
 * median 5800.00" when carrier bids from other RFPs were counted too.
 * Otherwise the status word (Pending / Unresolved / No match / Failed), so the
 * row says why it is empty.
 */
function historyText(lane) {
  if (lane.Hist_Status__c !== "Done") {
    return lane.Hist_Status__c || "";
  }
  const count = historyCount(lane);
  const median = money(lane.Hist_Median__c);
  // A Done snapshot with no median means matches were found but none priced.
  return median ? `${count} · median ${median}` : `${count} · no median`;
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

/**
 * The no rate tag (spec §7): the stored snapshot matched nothing (No match), or it matched rows
 * but none priced in the lane's currency (Done with a blank median).
 */
function hasNoRate(lane) {
  const median = lane.Hist_Median__c;
  return (
    lane.Hist_Status__c === "No match" ||
    (lane.Hist_Status__c === "Done" &&
      (median === null || median === undefined || median === ""))
  );
}

/** The small tag after a lane's miles; billed History miles need none. */
const MILES_TAGS = {
  History: "",
  "Truck route": "truck",
  "Regular route": "route",
  Approx: "approx."
};

/** The tooltip on a lane's miles: where they came from. */
const MILES_TITLES = {
  History: "Median billed miles of the loads the history matched",
  "Truck route": "Mapbox truck route",
  "Regular route": "Mapbox regular route: the truck limits could not be met",
  Approx: "Straight-line distance between the two places, adjusted for roads"
};

/** The tooltip on "—": why the lane has no miles. */
const NO_MILES_TITLES = {
  "No route": "Mapbox found no route between the two places",
  "No coordinates": "A place on this lane is missing or has no coordinates"
};
const NO_MILES_YET = "No miles yet: load history or open the lane";

/**
 * The Miles cell in the chosen unit: the distance and its tag, or "—" with the
 * reason when the lane has no miles (No route, No coordinates, never run).
 */
function milesCell(lane, unit) {
  const source = lane.Miles_Source__c || "";
  const known = Object.prototype.hasOwnProperty.call(MILES_TAGS, source);
  if (!known || !(Number(lane.Miles__c) > 0)) {
    return {
      milesText: "—",
      milesTag: "",
      milesTitle: NO_MILES_TITLES[source] || NO_MILES_YET
    };
  }
  const hours =
    Number(lane.Route_Hours__c) > 0
      ? ` · ${Number(lane.Route_Hours__c).toFixed(1)} h`
      : "";
  return {
    milesText: formatDistance(lane.Miles__c, unit),
    milesTag: MILES_TAGS[source],
    milesTitle: `${MILES_TITLES[source]}${hours}`
  };
}

export default class RfpLaneTable extends LightningElement {
  @api selectedId;
  @api currency = "CAD";
  @api pendingIds = [];
  @api rowErrors = {};
  @api defaultMargin;
  @api locked = false;

  _lanes = [];
  _selectedIds = [];

  @api
  get lanes() {
    return this._lanes;
  }
  set lanes(value) {
    this._lanes = value || [];
  }

  @api
  get selectedIds() {
    return this._selectedIds;
  }
  set selectedIds(value) {
    this._selectedIds = value || [];
  }

  editing = null; // { laneId, field }
  draft = "";
  cellError = null;
  focusPending = false;
  refocus = null; // the { laneId, field } cell to hand focus back to

  /** "mi" or "km"; every distance on the page follows Distance_Unit__c. */
  unit = readUnit();
  @wire(MessageContext) messageContext;
  unitSubscription = null;

  connectedCallback() {
    if (!this.unitSubscription) {
      this.unitSubscription = subscribe(
        this.messageContext,
        DISTANCE_UNIT,
        (message) => this.handleUnit(message),
        { scope: APPLICATION_SCOPE }
      );
    }
  }

  /** The workbench drops the table when it leaves the lanes view. */
  disconnectedCallback() {
    if (this.unitSubscription) {
      unsubscribe(this.unitSubscription);
    }
    this.unitSubscription = null;
  }

  handleUnit(message) {
    const unit = message && message.unit;
    if (unit === "mi" || unit === "km") {
      this.unit = unit;
    }
  }

  renderedCallback() {
    if (this.focusPending) {
      this.focusPending = false;
      const input = this.template.querySelector('[data-id="cell-input"]');
      if (input && typeof input.focus === "function") {
        input.focus();
      }
      return;
    }
    if (!this.refocus) {
      return;
    }
    const { laneId, field } = this.refocus;
    this.refocus = null;
    const cell = this.template.querySelector(
      `td[data-field="${field}"][data-lane-id="${laneId}"]`
    );
    if (cell && typeof cell.focus === "function") {
      cell.focus();
    }
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
  /** The column reads in the unit its cells are shown in. */
  get distanceHeader() {
    return this.unit === "km" ? "Km" : "Miles";
  }

  get allChecked() {
    const selected = new Set(this._selectedIds);
    return (
      this._lanes.length > 0 && this._lanes.every((l) => selected.has(l.Id))
    );
  }

  get viewRows() {
    const selected = new Set(this._selectedIds);
    const pending = new Set(this.pendingIds || []);
    return this._lanes.map((l) => ({
      id: l.Id,
      rowNumber: l.Row_Number__c,
      rowClass:
        l.Id === this.selectedId ? "lane-row lane-row_selected" : "lane-row",
      ariaSelected: l.Id === this.selectedId ? "true" : "false",
      // The spreadsheet text stays on screen next to the picker, so the user can
      // see which city failed to resolve while they fix it.
      originUnresolved: !l.Origin_Resolved__c,
      originText: placeText(l.Origin_City__c, l.Origin_Province__c),
      originKey: l.Origin_Place__r ? l.Origin_Place__r.Key__c : null,
      destinationUnresolved: !l.Destination_Resolved__c,
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
      noRate: hasNoRate(l),
      ...milesCell(l, this.unit),
      costText: money(l.Cost__c),
      marginText:
        l.Margin__c === null || l.Margin__c === undefined
          ? ""
          : String(l.Margin__c),
      sellText: money(l.Sell__c),
      statusText: l.Cost__c ? "Priced" : "",
      checked: selected.has(l.Id),
      pending: pending.has(l.Id),
      error: (this.rowErrors || {})[l.Id] || null,
      marginClass:
        "slds-text-align_right cell" +
        (l.Margin__c !== null && l.Margin__c !== undefined && l.Margin__c < 0
          ? " slds-text-color_error"
          : ""),
      manualSell: l.Sell_Source__c === "Manual",
      editingCost: this.isEditing(l.Id, "cost"),
      editingMargin: this.isEditing(l.Id, "margin"),
      editingSell: this.isEditing(l.Id, "sell")
    }));
  }

  isEditing(laneId, field) {
    return (
      !!this.editing &&
      this.editing.laneId === laneId &&
      this.editing.field === field
    );
  }

  handleRowClick(event) {
    this.emitSelect(event.currentTarget.dataset.laneId);
  }

  /**
   * Only when the row itself has focus: the inline place picker lives inside the
   * row, and its own Enter / Space (pick an option, type a space) must not be
   * swallowed into a row selection.
   */
  handleRowKey(event) {
    if (event.target !== event.currentTarget) {
      return;
    }
    if (
      event.key !== "Enter" &&
      event.key !== " " &&
      event.key !== "Spacebar"
    ) {
      return;
    }
    event.preventDefault();
    this.emitSelect(event.currentTarget.dataset.laneId);
  }

  /**
   * Everything the inline place picker does stays inside the picker. Selecting
   * the row would re-render the panel, change the page height and scroll the
   * browser away underneath the option list the user is still clicking in.
   */
  stopRowSelect(event) {
    event.stopPropagation();
  }

  emitSelect(laneId) {
    this.dispatchEvent(new CustomEvent("select", { detail: { laneId } }));
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

  handleRowCheck(event) {
    const laneId = event.currentTarget.dataset.laneId;
    const next = event.currentTarget.checked
      ? [...this._selectedIds.filter((id) => id !== laneId), laneId]
      : this._selectedIds.filter((id) => id !== laneId);
    this.emitSelection(next);
  }

  /** Toggles the rows currently shown; ids the table does not show are left as they are. */
  handleCheckAll() {
    const shown = this._lanes.map((l) => l.Id);
    const next = this.allChecked
      ? this._selectedIds.filter((id) => !shown.includes(id))
      : [
          ...this._selectedIds,
          ...shown.filter((id) => !this._selectedIds.includes(id))
        ];
    this.emitSelection(next);
  }

  emitSelection(laneIds) {
    this.dispatchEvent(
      new CustomEvent("selectionchange", { detail: { laneIds } })
    );
  }

  handleCellClick(event) {
    // open() does the selecting, so the row handler must not select again.
    event.stopPropagation();
    this.open(event.currentTarget.dataset);
  }

  handleCellKey(event) {
    if (event.target !== event.currentTarget || event.key !== "Enter") {
      return;
    }
    event.preventDefault();
    event.stopPropagation();
    this.open(event.currentTarget.dataset);
  }

  open({ laneId, field }) {
    if (!EDITABLE.includes(field)) {
      return;
    }
    const lane = this._lanes.find((l) => l.Id === laneId);
    if (!lane) {
      return;
    }
    // The panel follows the cell that was pointed at however it was reached —
    // a click, Enter on a focused cell, or stepping down the column — so a
    // keyboard pricer never types into one lane while reading another.
    if (laneId !== this.selectedId) {
      this.emitSelect(laneId);
    }
    // A locked table still navigates; it just refuses the typing.
    if (this.locked || this.isEditing(laneId, field)) {
      return;
    }
    this.editing = { laneId, field };
    this.draft = rawText(lane, field);
    this.cellError = null;
    this.focusPending = true;
    this.refocus = null;
  }

  handleDraft(event) {
    this.draft = event.detail.value;
  }

  handleInputKey(event) {
    event.stopPropagation();
    if (event.key === "Escape") {
      event.preventDefault();
      this.close(true);
    } else if (event.key === "Enter" || event.key === "Tab") {
      event.preventDefault();
      this.commit(event.shiftKey ? -1 : 1);
    }
  }

  handleInputBlur(event) {
    const { laneId, field } = event.currentTarget.dataset;
    // A commit that already moved on leaves a blur behind on the old input.
    if (!this.isEditing(laneId, field)) {
      return;
    }
    if (!this.commit(0)) {
      this.close(); // an unusable value is dropped on blur rather than trapping focus
    }
  }

  /**
   * `keepFocus` hands focus back to the cell itself, so Escape and the end of a
   * column leave the keyboard inside the table. A blur must not: the user has
   * already moved focus somewhere else and pulling it back would trap them.
   */
  close(keepFocus = false) {
    if (keepFocus && this.editing) {
      this.refocus = this.editing;
    }
    this.editing = null;
    this.draft = "";
    this.cellError = null;
  }

  /**
   * Saves the draft and moves `step` rows down the same column (0 = just
   * close). Returns false when the draft is unusable; the cell stays open
   * with the reason under it.
   */
  commit(step) {
    const { laneId, field } = this.editing;
    const index = this._lanes.findIndex((l) => l.Id === laneId);
    if (index < 0) {
      // the lane left the table while its cell was open; there is nothing to save
      this.close();
      return true;
    }
    const lane = this._lanes[index];
    const text = String(this.draft ?? "").trim();
    if (text !== rawText(lane, field)) {
      const detail = inlineEdit(lane, field, text, this.defaultMargin);
      if (!detail) {
        this.cellError = ERRORS[field];
        return false;
      }
      this.dispatchEvent(new CustomEvent("pricingchange", { detail }));
    }
    const next = this._lanes[index + step];
    this.close(step !== 0);
    if (step !== 0 && next) {
      this.open({ laneId: next.Id, field });
    }
    return true;
  }
}
