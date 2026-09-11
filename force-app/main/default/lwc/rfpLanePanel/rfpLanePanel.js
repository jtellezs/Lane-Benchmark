import { LightningElement, api, track } from "lwc";
import getBids from "@salesforce/apex/RfpBidController.getBids";
import saveBid from "@salesforce/apex/RfpBidController.saveBid";
import search from "@salesforce/apex/LaneBenchmarkController.search";
import { bestBid } from "c/rfpMath";
import {
  SOURCES,
  money,
  costFor,
  bidOptions,
  bidRows,
  bestBidHint,
  otherCurrencyNote,
  pricingDetail,
  historyKey,
  historyRequest
} from "c/rfpPricing";

const laneIdOf = (lane) => (lane && lane.Id) || null;
const apexMessage = (e, fallback) =>
  (e && e.body && e.body.message) || fallback;
const placeText = (city, province) =>
  [city, province].filter(Boolean).join(", ");

export default class RfpLanePanel extends LightningElement {
  @api project;

  _lane = null;

  @api
  get lane() {
    return this._lane;
  }
  set lane(value) {
    const laneChanged = laneIdOf(value) !== laneIdOf(this._lane);
    const previousHistoryKey = historyKey(this._lane);
    this._lane = value || null;
    if (laneChanged) {
      this.syncFromLane();
      this.loadBids();
    }
    // Re-sending the same lane after an end was resolved gives it place keys it
    // did not have, so the history search keys off those and not off the Id.
    if (historyKey(this._lane) !== previousHistoryKey) {
      this.loadHistory();
    }
  }

  @track bids = [];
  @track historyRows = [];
  costSource = "Manual";
  selectedBidId = null;
  manualCost = "";
  marginText = "";
  notes = "";
  showForm = false;
  truncated = false;
  error = null;
  loadingHistory = false;
  bidSeq = 0;
  historySeq = 0;

  sourceOptions = SOURCES;

  get laneId() {
    return laneIdOf(this._lane);
  }
  get hasLane() {
    return !!this._lane;
  }
  get currency() {
    return (
      (this._lane && this._lane.CurrencyIsoCode) ||
      (this.project && this.project.CurrencyIsoCode) ||
      "CAD"
    );
  }
  get originLabel() {
    const l = this._lane || {};
    return placeText(l.Origin_City__c, l.Origin_Province__c);
  }
  get destinationLabel() {
    const l = this._lane || {};
    return placeText(l.Destination_City__c, l.Destination_Province__c);
  }
  get laneTitle() {
    return `${this.originLabel} → ${this.destinationLabel}`;
  }

  syncFromLane() {
    const l = this._lane || {};
    this.costSource = l.Cost_Source__c || "Manual";
    this.selectedBidId = l.Selected_Bid__c || null;
    this.manualCost =
      l.Cost__c === null || l.Cost__c === undefined ? "" : String(l.Cost__c);
    this.marginText =
      l.Margin__c === null || l.Margin__c === undefined
        ? ""
        : String(l.Margin__c);
    this.notes = l.Notes__c || "";
    this.showForm = false;
    this.error = null;
  }

  async loadBids() {
    const laneId = this.laneId;
    if (!laneId) {
      this.bids = [];
      return;
    }
    const seq = ++this.bidSeq;
    try {
      const rows = await getBids({ laneId });
      if (seq === this.bidSeq) {
        this.bids = rows || [];
      }
    } catch (e) {
      if (seq === this.bidSeq) {
        this.bids = [];
        this.error = apexMessage(e, "The bids could not be loaded.");
      }
    }
  }

  /**
   * Only a lane whose two ends are already resolved to places can be searched;
   * an unresolved end has no key to match loads on.
   */
  async loadHistory() {
    if (!historyKey(this._lane)) {
      this.historyRows = [];
      this.truncated = false;
      return;
    }
    const seq = ++this.historySeq;
    this.loadingHistory = true;
    try {
      const result = await search({
        requestJson: historyRequest(this._lane)
      });
      if (seq !== this.historySeq) {
        return; // a newer lane already landed; drop this stale response
      }
      this.historyRows = (result && result.rows) || [];
      this.truncated = !!(result && result.truncated);
    } catch (e) {
      if (seq === this.historySeq) {
        this.historyRows = [];
        this.error = apexMessage(e, "The lane history could not be loaded.");
      }
    } finally {
      if (seq === this.historySeq) {
        this.loadingHistory = false;
      }
    }
  }

  get isBidSource() {
    return this.costSource === "Bid";
  }
  get costLocked() {
    return this.costSource !== "Manual";
  }
  /** A "Bid" cost with no bid behind it would save an inconsistent lane. */
  get cannotSavePrice() {
    return this.isBidSource && !this.selectedBidId;
  }
  get hasBids() {
    return this.bids.length > 0;
  }
  get bidOptions() {
    return bidOptions(this.bids);
  }
  get bidRows() {
    return bidRows(this.bids);
  }
  get costNumber() {
    return costFor(this.costSource, {
      lane: this._lane,
      bids: this.bids,
      selectedBidId: this.selectedBidId,
      manualCost: this.manualCost
    });
  }
  get costInputValue() {
    return this.costSource === "Manual" ? this.manualCost : this.costNumber;
  }
  get sellText() {
    return money(this.pricing.Sell__c);
  }
  get bestBidHint() {
    return bestBidHint(this.bids, this.currency, this.costNumber);
  }
  get otherCurrencyNote() {
    return otherCurrencyNote(this.bids, this.currency);
  }
  get pricing() {
    return pricingDetail({
      laneId: this.laneId,
      source: this.costSource,
      selectedBidId: this.selectedBidId,
      cost: this.costNumber,
      marginText: this.marginText,
      notes: this.notes
    });
  }

  handleSource(event) {
    this.costSource = event.detail.value;
    if (this.isBidSource && !this.selectedBidId) {
      const best = bestBid(this.bids, this.currency);
      this.selectedBidId = best ? best.Id : null;
    }
  }
  handleBidSelect(event) {
    this.selectedBidId = event.detail.value;
  }
  handleCost(event) {
    this.manualCost = event.detail.value;
  }
  handleMargin(event) {
    this.marginText = event.detail.value;
  }
  handleNotes(event) {
    this.notes = event.detail.value;
  }
  handleUseBest() {
    const best = bestBid(this.bids, this.currency);
    if (!best) {
      return;
    }
    this.costSource = "Bid";
    this.selectedBidId = best.Id;
  }

  handleSavePrice() {
    this.dispatchEvent(
      new CustomEvent("pricingchange", { detail: this.pricing })
    );
  }

  handleAddBid() {
    this.error = null;
    this.showForm = true;
  }
  handleCancelBid() {
    this.showForm = false;
  }

  async handleSaveBid(event) {
    this.error = null;
    try {
      await saveBid({ bidJson: JSON.stringify(event.detail.bid) });
      this.showForm = false;
      await this.loadBids();
      this.dispatchEvent(
        new CustomEvent("bidsaved", { detail: { laneId: this.laneId } })
      );
    } catch (e) {
      this.error = apexMessage(e, "The bid could not be saved.");
    }
  }
}
