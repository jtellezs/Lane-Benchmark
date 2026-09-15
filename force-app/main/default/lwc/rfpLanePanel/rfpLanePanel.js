import { LightningElement, api, track, wire } from "lwc";
import {
  APPLICATION_SCOPE,
  MessageContext,
  subscribe,
  unsubscribe
} from "lightning/messageService";
import DISTANCE_UNIT from "@salesforce/messageChannel/Distance_Unit__c";
import getBids from "@salesforce/apex/RfpBidController.getBids";
import saveBid from "@salesforce/apex/RfpBidController.saveBid";
import search from "@salesforce/apex/LaneBenchmarkController.search";
import laneRoute from "@salesforce/apex/RfpLaneController.laneRoute";
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
import { readUnit, formatDistance, perDistance } from "c/distanceUnit";

const laneIdOf = (lane) => (lane && lane.Id) || null;
const apexMessage = (e, fallback) =>
  (e && e.body && e.body.message) || fallback;
const placeText = (city, province) =>
  [city, province].filter(Boolean).join(", ");
/** Both place keys, or null while an end is unresolved: there is nothing to route between. */
const placePair = (lane) => {
  const origin = lane?.Origin_Place__r?.Key__c;
  const destination = lane?.Destination_Place__r?.Key__c;
  return origin && destination ? `${origin}~${destination}` : null;
};
/** The lane's three trip fields as one string, to notice newer miles arriving. */
const milesFingerprint = (lane) =>
  ["Miles__c", "Miles_Source__c", "Route_Hours__c"]
    .map((f) => lane?.[f] ?? "")
    .join("|");
/** How the line under the title names each source that comes with miles. */
const SOURCE_WORDS = {
  History: "from history",
  "Truck route": "truck route",
  "Regular route": "regular route",
  Approx: "approx."
};
/** The line under the title when the lane has no miles, by source. */
const NO_MILES_LINES = {
  "No route": "No route found between the two places",
  "No coordinates": "A place on this lane is missing or has no coordinates"
};
const ROUTE_UNAVAILABLE = "The truck route is not available right now.";

export default class RfpLanePanel extends LightningElement {
  @api project;

  _busy = false;
  _lane = null;

  /**
   * A chunked run is going in the container: the panel must not add a save to it.
   * laneRoute is one (it writes the lane's miles), so a route asked for during
   * the run waits for it to end; see loadRoute.
   */
  @api
  get busy() {
    return this._busy;
  }
  set busy(value) {
    this._busy = !!value;
    this.runDeferredRoute();
  }

  @api
  get lane() {
    return this._lane;
  }
  set lane(value) {
    const laneChanged = laneIdOf(value) !== laneIdOf(this._lane);
    const pricingChanged =
      pricingFingerprint(value) !== pricingFingerprint(this._lane);
    const milesChanged =
      milesFingerprint(value) !== milesFingerprint(this._lane);
    const previousHistoryKey = historyKey(this._lane);
    const previousPlaces = placePair(this._lane);
    this._lane = value || null;
    if (laneChanged) {
      this.syncFromLane();
      this.loadBids();
    } else if (pricingChanged) {
      // An inline edit or a bulk action touched the lane on screen: the editor
      // must show what is stored now, not what it showed before the change.
      this.syncPricing();
    }
    // Miles the container sends for the lane on screen (a history run, a price
    // save that re-read the lane) are newer than the copy the last route call
    // returned, so that copy stops standing in for them.
    if (milesChanged) {
      this.routeLane = null;
    }
    // A new lane always re-searches. Re-sending the same lane searches again
    // only once its place keys change — an end resolved through the table gives
    // it keys it did not have, while a pricing round trip changes nothing.
    if (laneChanged || historyKey(this._lane) !== previousHistoryKey) {
      this.loadHistory();
    }
    // The route belongs to the place pair alone: a history run changes the
    // lane's precision and lookback, never its places, so it asks nothing.
    if (laneChanged || placePair(this._lane) !== previousPlaces) {
      this.loadRoute(false);
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
  /** The TripRouteView c-route-map draws; null until laneRoute answers. */
  routeView = null;
  /** The lane as stored after laneRoute's write step; see milesLane. */
  routeLane = null;
  loadingRoute = false;
  routeSeq = 0;
  /** The refresh flag of a route loadRoute held back (see there), or null. */
  routeDeferred = null;
  /** Between connectedCallback and disconnectedCallback. */
  connected = false;
  /** "mi" or "km"; every distance on the page follows Distance_Unit__c. */
  unit = readUnit();
  @wire(MessageContext) messageContext;
  unitSubscription = null;

  sourceOptions = SOURCES;

  connectedCallback() {
    if (!this.unitSubscription) {
      this.unitSubscription = subscribe(
        this.messageContext,
        DISTANCE_UNIT,
        (message) => this.handleUnit(message),
        { scope: APPLICATION_SCOPE }
      );
    }
    this.connected = true;
    this.runDeferredRoute();
  }

  /** The workbench drops the panel when it leaves the lanes view. */
  disconnectedCallback() {
    if (this.unitSubscription) {
      unsubscribe(this.unitSubscription);
    }
    this.unitSubscription = null;
    this.connected = false;
  }

  handleUnit(message) {
    const unit = message && message.unit;
    if (unit === "mi" || unit === "km") {
      this.unit = unit;
    }
  }

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
  /**
   * The lane's trip fields. The lane laneRoute returned stands in until the
   * container sends the lane again. laneRoute re-reads the lane FOR UPDATE
   * after its callouts, keeps History miles, writes only changed values and
   * returns the stored lane whenever it reaches its write step, so this copy
   * matches the database. rfpTool is not told about a route, so its lanes
   * catch up on the next price save or history run.
   */
  get milesLane() {
    return this.routeLane || this._lane || {};
  }
  /** The lane's miles when its source comes with a distance, else null. */
  get milesNumber() {
    const l = this.milesLane;
    const known = Object.prototype.hasOwnProperty.call(
      SOURCE_WORDS,
      l.Miles_Source__c || ""
    );
    const miles = Number(l.Miles__c);
    return known && miles > 0 ? miles : null;
  }
  /** "1,234 mi · truck route · 21.5 h", why there are no miles, or "" before any run. */
  get milesLine() {
    const l = this.milesLane;
    const miles = this.milesNumber;
    if (miles === null) {
      return NO_MILES_LINES[l.Miles_Source__c] || "";
    }
    const hours =
      Number(l.Route_Hours__c) > 0
        ? ` · ${Number(l.Route_Hours__c).toFixed(1)} h`
        : "";
    return `${formatDistance(miles, this.unit)} · ${SOURCE_WORDS[l.Miles_Source__c]}${hours}`;
  }
  get hasRoutePlaces() {
    return !!placePair(this._lane);
  }
  /** c-route-map says under its legend that a hazmat lane gets the ordinary route. */
  get laneHazmat() {
    return !!(this._lane && this._lane.Hazmat__c);
  }

  syncFromLane() {
    const l = this._lane || {};
    this.syncPricing();
    this.notes = l.Notes__c || "";
    // Nothing from the lane we were showing may survive into the new one.
    this.bids = [];
    this.historyRows = [];
    this.routeView = null;
    this.routeLane = null;
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

  /**
   * The stored truck route on open (refresh false), a new Mapbox request on
   * Refresh route (refresh true). After its callouts laneRoute re-reads the
   * lane FOR UPDATE, keeps History miles (R75), writes the route's miles,
   * source and hours only when they change, and returns the stored lane as
   * view.lane whenever it reaches that write step (written, unchanged or kept
   * for History); view.lane is null only for an Unavailable route or a lane
   * without coordinates. A failure is shown in the route map, not in the
   * panel's error line, so it never hides a bid or history error.
   *
   * The server's re-read is what keeps History miles. While the container is
   * busy the request still waits, with the map loading, and runDeferredRoute
   * sends it when the run ends: no lane write lands inside a chunked run, and
   * the FOR UPDATE read never waits on a running chunk's lock. It also waits
   * until the panel is connected: rfpTool.html sets lane before busy, so a
   * panel rendered mid-run gets its lane while busy still reads false.
   */
  async loadRoute(refresh) {
    const seq = ++this.routeSeq;
    const laneId = this.laneId;
    this.routeDeferred = null;
    if (!laneId || !placePair(this._lane)) {
      this.routeView = null;
      this.loadingRoute = false;
      return;
    }
    this.loadingRoute = true;
    if (this._busy || !this.connected) {
      this.routeDeferred = !!refresh;
      return;
    }
    try {
      const view = await laneRoute({ laneId, refresh: !!refresh });
      if (seq !== this.routeSeq) {
        return; // the panel moved to another lane; this route is not its
      }
      this.routeView = view || null;
      if (view && view.lane) {
        this.routeLane = view.lane;
      }
    } catch (e) {
      if (seq === this.routeSeq) {
        this.routeView = {
          status: "Unavailable",
          routeType: null,
          routes: [],
          mapUrl: null,
          message: apexMessage(e, ROUTE_UNAVAILABLE)
        };
      }
    } finally {
      if (seq === this.routeSeq) {
        this.loadingRoute = false;
      }
    }
  }

  /** Sends the route loadRoute held back, once the panel is connected and the run is over. */
  runDeferredRoute() {
    if (this.routeDeferred === null || this._busy || !this.connected) {
      return;
    }
    this.loadRoute(this.routeDeferred);
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

  /** The sell the pricer sees: typed in Manual mode, derived from the margin otherwise. */
  get sellNumber() {
    return this.isManualSell ? parseMoney(this.sellText) : this.pricing.Sell__c;
  }
  get hasPerDistance() {
    return this.milesNumber !== null;
  }
  get costPerDistanceText() {
    return this.perDistanceText("Cost", this.costNumber);
  }
  get sellPerDistanceText() {
    return this.perDistanceText("Sell", this.sellNumber);
  }

  /** "Cost per mile: 1.22 CAD", or "—" while there is no amount to divide yet. */
  perDistanceText(label, amount) {
    const value =
      amount === null || amount === undefined
        ? null
        : perDistance(amount, this.milesNumber, this.unit);
    const word = this.unit === "km" ? "km" : "mile";
    const shown =
      value === null || value === undefined
        ? "—"
        : `${value.toFixed(2)} ${this.currency}`;
    return `${label} per ${word}: ${shown}`;
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
  handleRefreshRoute() {
    this.loadRoute(true);
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
