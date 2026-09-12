import { LightningElement, api, track } from "lwc";
import getBids from "@salesforce/apex/RfpBidController.getBids";
import saveBid from "@salesforce/apex/RfpBidController.saveBid";
import search from "@salesforce/apex/LaneBenchmarkController.search";
import { bestBid } from "c/rfpMath";
import {
  SOURCES,
  costFor,
  bidOptions,
  bidRows,
  bestBidHint,
  otherCurrencyNote,
  pricingDetail,
  pricingFingerprint,
  parseMoney,
  historyKey,
  historyRequest
} from "c/rfpPricing";
import { marginFor } from "c/marginMath";

const laneIdOf = (lane) => (lane && lane.Id) || null;
const apexMessage = (e, fallback) =>
  (e && e.body && e.body.message) || fallback;
const placeText = (city, province) =>
  [city, province].filter(Boolean).join(", ");

export default class RfpLanePanel extends LightningElement {
  @api project;
  /** A chunked run is going in the container: the panel must not add a save to it. */
  @api busy = false;

  _lane = null;

  @api
  get lane() {
    return this._lane;
  }
  set lane(value) {
    const laneChanged = laneIdOf(value) !== laneIdOf(this._lane);
    const pricingChanged =
      pricingFingerprint(value) !== pricingFingerprint(this._lane);
    const previousHistoryKey = historyKey(this._lane);
    this._lane = value || null;
    if (laneChanged) {
      this.syncFromLane();
      this.loadBids();
    } else if (pricingChanged) {
      // An inline edit or a bulk action touched the lane on screen: the editor
      // must show what is stored now, not what it showed before the change.
      this.syncPricing();
    }
    // A new lane always re-searches. Re-sending the same lane searches again
    // only once its place keys change — an end resolved through the table gives
    // it keys it did not have, while a pricing round trip changes nothing.
    if (laneChanged || historyKey(this._lane) !== previousHistoryKey) {
      this.loadHistory();
    }
  }

  @track bids = [];
  @track historyRows = [];
  costSource = "Manual";
  selectedBidId = null;
  manualCost = "";
  marginText = "";
  sellSource = "Margin";
  sellText = "";
  notes = "";
  showForm = false;
  editingBid = null;
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
    this.syncPricing();
    this.notes = l.Notes__c || "";
    // Nothing from the lane we were showing may survive into the new one.
    this.bids = [];
    this.historyRows = [];
    this.truncated = false;
    this.showForm = false;
    this.editingBid = null;
    this.error = null;
  }

  syncPricing() {
    const l = this._lane || {};
    this.costSource = l.Cost_Source__c || "Manual";
    this.selectedBidId = l.Selected_Bid__c || null;
    this.manualCost =
      l.Cost__c === null || l.Cost__c === undefined ? "" : String(l.Cost__c);
    this.marginText =
      l.Margin__c === null || l.Margin__c === undefined
        ? ""
        : String(l.Margin__c);
    this.sellSource = l.Sell_Source__c === "Manual" ? "Manual" : "Margin";
    this.sellText =
      l.Sell__c === null || l.Sell__c === undefined ? "" : String(l.Sell__c);
  }

  /** Resolves true only when the panel is showing this lane's current bids. */
  async loadBids() {
    // Bumped before the early return too, so a request still in flight for the
    // lane we just left cannot land on top of the lane now on screen.
    const seq = ++this.bidSeq;
    const laneId = this.laneId;
    if (!laneId) {
      this.bids = [];
      return false;
    }
    try {
      const rows = await getBids({ laneId });
      if (seq === this.bidSeq) {
        this.bids = rows || [];
      }
      return true;
    } catch (e) {
      if (seq === this.bidSeq) {
        this.bids = [];
        this.error = apexMessage(e, "The bids could not be loaded.");
      }
      return false;
    }
  }

  /**
   * Only a lane whose two ends are already resolved to places can be searched;
   * an unresolved end has no key to match loads on.
   */
  async loadHistory() {
    const seq = ++this.historySeq;
    if (!historyKey(this._lane)) {
      this.historyRows = [];
      this.truncated = false;
      this.loadingHistory = false;
      return;
    }
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
  /**
   * With no cost to send, saveLanePricing would write nulls over whatever cost
   * and sell the lane already had. That includes a "Bid" source whose bid is not
   * loaded — bids still in flight, or a getBids that failed. A manual sell that
   * cannot be parsed is the same problem on the sell side: pricingDetail would
   * write a null Sell__c over whatever the lane already had.
   */
  get cannotSavePrice() {
    return (
      this.costNumber === null ||
      (this.isManualSell && parseMoney(this.sellText) === null)
    );
  }
  /** Save is off while the container is mid-run, as well as when there is nothing to save. */
  get saveDisabled() {
    return this.busy || this.cannotSavePrice;
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
  get isManualSell() {
    return this.sellSource === "Manual";
  }
  get sellMode() {
    return this.isManualSell
      ? "Margin follows the sell"
      : "Sell follows the margin";
  }
  get sellValue() {
    return this.isManualSell ? this.sellText : this.pricing.Sell__c;
  }
  get sellLabel() {
    return `Sell (${this.currency})`;
  }
  get marginValue() {
    if (!this.isManualSell) {
      return this.marginText;
    }
    const m = marginFor(this.costNumber, parseMoney(this.sellText));
    return m === null ? "" : String(m);
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
      notes: this.notes,
      sellSource: this.sellSource,
      sellText: this.sellText
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
    this.sellSource = "Margin";
  }
  handleSell(event) {
    this.sellText = event.detail.value;
    this.sellSource = "Manual";
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
    if (this.cannotSavePrice) {
      return;
    }
    this.dispatchEvent(
      new CustomEvent("pricingchange", { detail: this.pricing })
    );
  }

  handleAddBid() {
    this.error = null;
    this.editingBid = null;
    this.showForm = true;
  }
  handleEditBid(event) {
    const bidId = event.currentTarget.dataset.bidId;
    this.error = null;
    this.editingBid = this.bids.find((b) => b.Id === bidId) || null;
    this.showForm = true;
  }
  handleCancelBid() {
    this.showForm = false;
    this.editingBid = null;
  }

  async handleSaveBid(event) {
    this.error = null;
    try {
      await saveBid({ bidJson: JSON.stringify(event.detail.bid) });
      this.showForm = false;
      this.editingBid = null;
    } catch (e) {
      this.error = apexMessage(e, "The bid could not be saved.");
      return;
    }
    // Only once the panel is showing the saved bid is the container told to
    // refresh the lane; a failed refresh leaves the error on screen instead.
    if (await this.loadBids()) {
      this.dispatchEvent(
        new CustomEvent("bidsaved", { detail: { laneId: this.laneId } })
      );
    }
  }
}
