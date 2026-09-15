import { LightningElement, track, wire } from "lwc";
import search from "@salesforce/apex/LaneBenchmarkController.search";
import getFilterOptions from "@salesforce/apex/LaneBenchmarkController.getFilterOptions";
import mapPreviewUrl from "@salesforce/apex/LaneBenchmarkController.mapPreviewUrl";
import truckRoute from "@salesforce/apex/LaneBenchmarkController.truckRoute";
import {
  subscribe,
  unsubscribe,
  MessageContext,
  APPLICATION_SCOPE
} from "lightning/messageService";
import DISTANCE_UNIT from "@salesforce/messageChannel/Distance_Unit__c";
import { load, save, clear } from "c/laneBenchmarkStorage";
import { DEFAULT_FILTERS, cloneDefaults } from "c/laneBenchmarkFilters";
import { readUnit } from "c/distanceUnit";
import { hasBothKeys, noRate } from "c/carrierLeadRules";

const LONG_RADIUS_DAYS = 365;

function emptyRequest() {
  return {
    originKey: null,
    originLabel: "",
    originPrecision: "CITY",
    originRadius: null,
    destinationKey: null,
    destinationLabel: "",
    destinationPrecision: "CITY",
    destinationRadius: null,
    radiusUnit: "MI",
    marginPct: 15,
    ...cloneDefaults()
  };
}

export default class LaneBenchmark extends LightningElement {
  @track request = emptyRequest();
  filterOptions = {
    modes: [],
    equipmentByCategory: {},
    currencies: ["CAD", "USD"]
  };
  result = null;
  error = null;
  isSearching = false;
  elapsedSeconds = 0;
  needsConfirmation = false;
  previewUrl = null;
  ticker = null;
  // the request as it was when the last successful search ran, so a margin-only
  // edit can be saved without persisting unapplied filter changes
  lastSearched = null;
  // Phase 8: the exact request JSON the last successful search sent and the currency filter it
  // ran with (null without one). Carriers to ask judges "no rate" in that currency (spec D2) and
  // asks about the lane that was searched, never about filter edits made since.
  lastRequestJson = null;
  lastCurrency = null;
  // Phase 7: the truck route for the searched place pair (TripRouteView). Fetched after the
  // search, not awaited by it: a Mapbox route can take several seconds and the results must not wait.
  routeView = null;
  isRouteLoading = false;
  // bumped by every route request and every reset; an answer carrying an older ticket belongs
  // to an earlier search and is dropped
  routeTicket = 0;
  // 'mi' | 'km' for the whole page: starts from this browser's choice and follows
  // Distance_Unit__c, which c-distance-unit-toggle (in the statistics card) publishes on
  unit = readUnit();
  unitSubscription = null;

  @wire(MessageContext)
  messageContext;

  get filters() {
    const f = {};
    Object.keys(DEFAULT_FILTERS).forEach((k) => {
      f[k] = this.request[k];
    });
    return f;
  }
  get rows() {
    return this.result ? this.result.rows : [];
  }
  get statsByCurrency() {
    return this.result ? this.result.statsByCurrency : {};
  }
  get hasResult() {
    return !!this.result;
  }
  get showEmptyState() {
    return !this.hasResult && !this.isSearching;
  }
  get isRadiusSearch() {
    return (
      this.request.originPrecision === "RADIUS" ||
      this.request.destinationPrecision === "RADIUS"
    );
  }
  get medianMiles() {
    return this.result ? this.result.medianMiles : null;
  }
  /**
   * The loads whose billed miles fed the median, each counted once however many of its quotes
   * matched, as LaneSearchResult.medianMiles counts them (bid rows carry no load).
   */
  get milesCount() {
    const loads = new Set();
    this.rows.forEach((r) => {
      if (r.load && r.load.loadId && Number(r.load.miles) > 0) {
        loads.add(r.load.loadId);
      }
    });
    return loads.size;
  }
  /** The route image shows whenever there is one to draw. */
  get hasRouteMap() {
    return !!(this.routeView && this.routeView.mapUrl);
  }
  /**
   * The preview keeps its place after a radius search, under the route image: its circles show
   * the matched area (spec §5). After any other search the route image takes its place (spec §6).
   */
  get showPreview() {
    const s = this.lastSearched;
    const radius =
      !!s &&
      (s.originPrecision === "RADIUS" || s.destinationPrecision === "RADIUS");
    return !this.hasRouteMap || radius;
  }
  /** Carriers to ask: after a search with both place keys and no priced rate in its currency. */
  get showCarrierLeads() {
    return (
      this.hasResult &&
      hasBothKeys(this.lastRequestJson) &&
      noRate(this.statsByCurrency, this.lastCurrency)
    );
  }

  /** Split-lane options need a place key on both ends of the search that ran (spec §4). */
  get showSplitOptions() {
    return this.hasResult && hasBothKeys(this.lastRequestJson);
  }
  /** The split card opens in the currency filter the search ran with, or in CAD without one. */
  get splitStartCurrency() {
    return this.lastCurrency === "USD" ? "USD" : "CAD";
  }

  async connectedCallback() {
    // subscribe before the first await, so a unit published while the options load is not missed
    this.unitSubscription = subscribe(
      this.messageContext,
      DISTANCE_UNIT,
      (message) => this.handleUnit(message),
      { scope: APPLICATION_SCOPE }
    );
    try {
      this.filterOptions = await getFilterOptions();
    } catch (e) {
      this.error = this.messageOf(e);
    }
    const saved = load();
    if (saved) {
      this.request = { ...emptyRequest(), ...saved };
      this.runSearch();
    }
  }

  disconnectedCallback() {
    window.clearInterval(this.ticker);
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

  handleOrigin(event) {
    const d = event.detail;
    this.request = {
      ...this.request,
      originKey: d.key,
      originLabel: d.label,
      originPrecision: d.precision,
      originRadius: d.radius,
      radiusUnit: d.unit || this.request.radiusUnit
    };
  }
  handleDestination(event) {
    const d = event.detail;
    this.request = {
      ...this.request,
      destinationKey: d.key,
      destinationLabel: d.label,
      destinationPrecision: d.precision,
      destinationRadius: d.radius,
      radiusUnit: d.unit || this.request.radiusUnit
    };
  }
  handleFilters(event) {
    this.request = { ...this.request, ...event.detail };
  }
  handleMargin(event) {
    const marginPct = event.detail.marginPct;
    this.request = { ...this.request, marginPct };
    // only persist a margin tweak against the request that was actually searched;
    // unapplied filter edits in this.request must not leak into storage
    if (this.lastSearched) {
      save({ ...this.lastSearched, marginPct });
    }
  }
  handleReset() {
    // reset only the filter keys (lookback, currency, modes, equipment, flags,
    // accepted status); places, precisions, radii, unit and margin are untouched
    this.request = { ...this.request, ...cloneDefaults() };
  }
  handleClearSaved() {
    clear();
    this.request = emptyRequest();
    this.result = null;
    this.previewUrl = null;
    this.clearRoute();
    this.lastSearched = null;
    this.error = null;
    this.needsConfirmation = false;
  }

  handleApply() {
    if (this.isSearching) {
      return;
    }
    if (
      this.isRadiusSearch &&
      Number(this.request.lookbackDays) > LONG_RADIUS_DAYS
    ) {
      this.needsConfirmation = true;
      return;
    }
    this.runSearch();
  }
  handleContinue() {
    if (this.isSearching) {
      return;
    }
    this.needsConfirmation = false;
    this.runSearch();
  }
  handleCancel() {
    this.needsConfirmation = false;
  }

  toServiceRequest() {
    const r = this.request;
    return {
      originKey: r.originKey,
      destinationKey: r.destinationKey,
      originPrecision: r.originPrecision,
      destinationPrecision: r.destinationPrecision,
      originRadius: r.originPrecision === "RADIUS" ? r.originRadius : null,
      destinationRadius:
        r.destinationPrecision === "RADIUS" ? r.destinationRadius : null,
      radiusUnit: r.radiusUnit,
      lookbackDays: r.lookbackDays,
      currencyIsoCode: r.currencyIsoCode,
      modes: r.modes,
      equipmentCategories: r.equipmentCategories,
      equipmentTypes: r.equipmentTypes,
      hazmatOnly: r.hazmatOnly,
      acceptedFilter: r.acceptedFilter,
      sourceFilter: r.sourceFilter,
      rowLimit: 2000,
      includeStopGeolocation: true
    };
  }

  async runSearch() {
    this.needsConfirmation = false;
    this.error = null;
    this.isSearching = true;
    this.elapsedSeconds = 0;
    window.clearInterval(this.ticker);
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    this.ticker = window.setInterval(() => {
      this.elapsedSeconds += 1;
    }, 1000);
    const svc = this.toServiceRequest();
    const requestJson = JSON.stringify(svc);
    try {
      this.result = await search({ requestJson });
      // the search succeeded: keep it even if the map preview below fails
      this.lastSearched = { ...this.request };
      this.lastRequestJson = requestJson;
      this.lastCurrency = svc.currencyIsoCode || null;
      save(this.request);
      // not awaited: the route runs beside the preview and never holds the results back
      this.loadRoute(svc.originKey, svc.destinationKey, false);
      try {
        this.previewUrl = await mapPreviewUrl({
          originKey: svc.originKey,
          originRadius: svc.originRadius,
          destinationKey: svc.destinationKey,
          destinationRadius: svc.destinationRadius,
          unit: svc.radiusUnit
        });
      } catch {
        // map preview is a nice-to-have; a failure here (no token, a place with no
        // coordinates, Mapbox down) must not wipe the search result or show an error
        this.previewUrl = null;
      }
    } catch (e) {
      this.result = null;
      this.previewUrl = null;
      this.clearRoute();
      this.error = this.messageOf(e);
    } finally {
      window.clearInterval(this.ticker);
      this.isSearching = false;
    }
  }

  /**
   * Asks LaneBenchmarkController.truckRoute for the pair's route: the stored one, or Mapbox
   * when there is none or refresh is true. Needs both ends; never throws.
   */
  async loadRoute(originKey, destinationKey, refresh) {
    this.routeTicket += 1;
    const ticket = this.routeTicket;
    if (!refresh) {
      this.routeView = null;
    }
    if (!originKey || !destinationKey) {
      this.isRouteLoading = false;
      return;
    }
    this.isRouteLoading = true;
    try {
      const view = await truckRoute({ originKey, destinationKey, refresh });
      if (ticket === this.routeTicket) {
        this.routeView = view;
      }
    } catch {
      // the route is a nice-to-have like the preview: a failure keeps the results, and a
      // failed refresh keeps the route already shown
    } finally {
      if (ticket === this.routeTicket) {
        this.isRouteLoading = false;
      }
    }
  }
  handleRefreshRoute() {
    if (!this.lastSearched || this.isRouteLoading) {
      return;
    }
    this.loadRoute(
      this.lastSearched.originKey,
      this.lastSearched.destinationKey,
      true
    );
  }
  clearRoute() {
    this.routeTicket += 1;
    this.routeView = null;
    this.isRouteLoading = false;
  }

  messageOf(e) {
    return (
      (e && e.body && e.body.message) ||
      (e && e.message) ||
      "Something went wrong"
    );
  }
}
