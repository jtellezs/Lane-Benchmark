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
    this.request = { ...this.request, marginPct: event.detail.marginPct };
    save(this.request);
  }
  handleReset() {
    this.request = {
      ...emptyRequest(),
      originKey: this.request.originKey,
      originLabel: this.request.originLabel,
      destinationKey: this.request.destinationKey,
      destinationLabel: this.request.destinationLabel
    };
  }
  handleClearSaved() {
    clear();
    this.request = emptyRequest();
    this.result = null;
    this.previewUrl = null;
  }

  handleApply() {
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
      rowLimit: 2000,
      includeStopGeolocation: true
    };
  }

  async runSearch() {
    this.error = null;
    this.isSearching = true;
    this.elapsedSeconds = 0;
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    this.ticker = window.setInterval(() => {
      this.elapsedSeconds += 1;
    }, 1000);
    const svc = this.toServiceRequest();
    try {
      this.result = await search({ requestJson: JSON.stringify(svc) });
      save(this.request);
      this.previewUrl = await mapPreviewUrl({
        originKey: svc.originKey,
        originRadius: svc.originRadius,
        destinationKey: svc.destinationKey,
        destinationRadius: svc.destinationRadius,
        unit: svc.radiusUnit
      });
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
