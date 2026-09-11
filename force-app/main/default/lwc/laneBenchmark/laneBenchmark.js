import { LightningElement, track } from "lwc";
import search from "@salesforce/apex/LaneBenchmarkController.search";
import getFilterOptions from "@salesforce/apex/LaneBenchmarkController.getFilterOptions";
import mapPreviewUrl from "@salesforce/apex/LaneBenchmarkController.mapPreviewUrl";
import { load, save, clear } from "c/laneBenchmarkStorage";
import { DEFAULT_FILTERS, cloneDefaults } from "c/laneBenchmarkFilters";

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

  async connectedCallback() {
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
      marketTestOnly: r.marketTestOnly,
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
    try {
      this.result = await search({ requestJson: JSON.stringify(svc) });
      // the search succeeded: keep it even if the map preview below fails
      this.lastSearched = { ...this.request };
      save(this.request);
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
      this.error = this.messageOf(e);
    } finally {
      window.clearInterval(this.ticker);
      this.isSearching = false;
    }
  }

  messageOf(e) {
    return (
      (e && e.body && e.body.message) ||
      (e && e.message) ||
      "Something went wrong"
    );
  }
}
