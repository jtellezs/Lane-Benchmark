import { LightningElement, api } from "lwc";
import { parseMargin } from "c/marginMath";
import { parseMoney } from "c/rfpPricing";

/**
 * The bulk actions above the lane table: pick a scope (the selection or every
 * lane), then push a median, a margin, a cost, a sell or a carrier rate onto it,
 * or delete the selection. The bar only emits `bulk`; rfpTool runs the calls.
 */
export default class RfpBulkBar extends LightningElement {
  @api totalCount = 0;
  @api currency = "CAD";
  @api busy = false;
  @api lastResult = null;

  _selectedCount = 0;
  scope = "all";
  marginText = "";
  costText = "";
  sellText = "";
  similarRadius = "50";
  showBidForm = false;
  confirmingDelete = false;
  error = null;

  @api
  get selectedCount() {
    return this._selectedCount;
  }
  set selectedCount(value) {
    this._selectedCount = value || 0;
    // A changed selection is a new decision: the delete confirm starts over,
    // and an empty selection can only mean every lane.
    this.confirmingDelete = false;
    if (!this._selectedCount) {
      this.scope = "all";
    }
  }

  /**
   * Phase 12: one carrier's rate often covers more than the lane it was quoted on, so with a
   * single lane selected the bar offers to find the others. It only ever grows the selection -
   * the pricer still confirms, and the apply is the same bulk action as before.
   */
  get canFindSimilar() {
    return this._selectedCount === 1;
  }

  handleSimilarRadius(event) {
    this.similarRadius = event.detail.value;
  }

  handleFindSimilar() {
    this.dispatchEvent(
      new CustomEvent("selectsimilar", {
        detail: { radiusMiles: Number(this.similarRadius) || 50 }
      })
    );
  }

  get isSelectedScope() {
    return this.scope === "selected";
  }
  get selectedLabel() {
    return `Selected (${this._selectedCount})`;
  }
  get allLabel() {
    return `All lanes (${this.totalCount || 0})`;
  }
  get selectedVariant() {
    return this.isSelectedScope ? "brand" : "neutral";
  }
  get allVariant() {
    return this.isSelectedScope ? "neutral" : "brand";
  }
  get noSelection() {
    return !this._selectedCount;
  }
  get deleteLabel() {
    const n = this._selectedCount;
    return this.confirmingDelete
      ? `Confirm: delete ${n} lane${n === 1 ? "" : "s"} and ${n === 1 ? "its" : "their"} carrier rates`
      : "Delete selected";
  }
  get costLabel() {
    return `Cost (${this.currency})`;
  }
  get sellLabel() {
    return `Sell (${this.currency})`;
  }
  get skippedCount() {
    const r = this.lastResult;
    return r && r.action === "median" && r.skippedIds ? r.skippedIds.length : 0;
  }
  get skippedNote() {
    const n = this.skippedCount;
    return `${n} lane${n === 1 ? "" : "s"} already costed from a bid or manually ${n === 1 ? "was" : "were"} left as ${n === 1 ? "it is" : "they are"}`;
  }

  handleScopeSelected() {
    this.scope = "selected";
    this.confirmingDelete = false;
  }
  handleScopeAll() {
    this.scope = "all";
    this.confirmingDelete = false;
  }
  handleMargin(event) {
    this.marginText = event.detail.value;
  }
  handleCost(event) {
    this.costText = event.detail.value;
  }
  handleSell(event) {
    this.sellText = event.detail.value;
  }

  emit(detail) {
    this.error = null;
    this.dispatchEvent(
      new CustomEvent("bulk", { detail: { scope: this.scope, ...detail } })
    );
  }

  handleUseMedian() {
    this.emit({ action: "median" });
  }
  handleApplyMargin() {
    const margin = parseMargin(this.marginText);
    if (margin === null) {
      this.error = "The margin must be between 0 and 100.";
      return;
    }
    this.emit({ action: "pricing", margin });
  }
  handleApplyCost() {
    const cost = parseMoney(this.costText);
    if (cost === null) {
      this.error = "The cost must be above zero.";
      return;
    }
    this.emit({ action: "pricing", cost });
  }
  handleApplySell() {
    const sell = parseMoney(this.sellText);
    if (sell === null) {
      this.error = "The sell must be above zero.";
      return;
    }
    this.emit({ action: "pricing", sell });
  }
  handleOverwrite() {
    this.error = null;
    this.dispatchEvent(
      new CustomEvent("bulk", {
        detail: { action: "median", scope: "skipped", overwrite: true }
      })
    );
  }
  handleDelete() {
    if (!this.confirmingDelete) {
      this.confirmingDelete = true;
      return;
    }
    this.confirmingDelete = false;
    this.dispatchEvent(
      new CustomEvent("bulk", {
        detail: { action: "delete", scope: "selected" }
      })
    );
  }
  handleAddBid() {
    this.error = null;
    this.showBidForm = true;
  }
  handleCancelBid() {
    this.showBidForm = false;
  }
  handleSaveBid(event) {
    const bid = { ...event.detail.bid };
    delete bid.RFP_Lane__c;
    this.showBidForm = false;
    this.emit({ action: "bid", bid });
  }
}
