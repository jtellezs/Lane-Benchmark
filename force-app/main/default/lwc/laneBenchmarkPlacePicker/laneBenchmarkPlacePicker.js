import { LightningElement, api, track } from "lwc";
import searchPlaces from "@salesforce/apex/LaneBenchmarkController.searchPlaces";
import geocode from "@salesforce/apex/LaneBenchmarkController.geocode";

const DEBOUNCE_MS = 250;
const PRECISIONS = [
  { label: "Exact city", value: "CITY" },
  { label: "Province / state", value: "PROVINCE" },
  { label: "Postal prefix (FSA / ZIP3)", value: "ZIP3" },
  { label: "Radius", value: "RADIUS" }
];

export default class LaneBenchmarkPlacePicker extends LightningElement {
  @api label = "Place";

  _value = null;
  _valueLabel = "";
  _precision = "CITY";
  _radius = null;
  _unit = "MI";

  @api
  get value() {
    return this._value;
  }
  set value(val) {
    this._value = val;
    if (val) {
      this.term = "";
      this.options = [];
      this.isOpen = false;
      window.clearTimeout(this.timer);
    }
  }

  @api
  get valueLabel() {
    return this._valueLabel;
  }
  set valueLabel(val) {
    this._valueLabel = val;
  }

  @api
  get precision() {
    return this._precision;
  }
  set precision(val) {
    this._precision = val;
  }

  @api
  get radius() {
    return this._radius;
  }
  set radius(val) {
    this._radius = val;
  }

  @api
  get unit() {
    return this._unit;
  }
  set unit(val) {
    this._unit = val;
  }

  @track options = [];
  term = "";
  isOpen = false;
  isSearching = false;
  error = null;
  precisionOptions = PRECISIONS;
  unitOptions = [
    { label: "mi", value: "MI" },
    { label: "km", value: "KM" }
  ];
  timer = null;

  get isRadius() {
    return this.precision === "RADIUS";
  }
  get hasValue() {
    return !!this.value;
  }
  get displayValue() {
    return this.hasValue ? this.valueLabel : this.term;
  }
  get showMapAction() {
    return this.isOpen && this.term.trim().length >= 3;
  }
  get listItems() {
    return this.options.map((o) => ({
      ...o,
      isMapbox: o.source === "Mapbox",
      loadText: o.loadCount ? `${o.loadCount} loads` : ""
    }));
  }

  handleTerm(event) {
    this.term = event.detail.value || "";
    if (this.hasValue) {
      this._value = null;
      this._valueLabel = "";
      this.emit();
    }
    window.clearTimeout(this.timer);
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    this.timer = window.setTimeout(() => this.search(), DEBOUNCE_MS);
  }

  async search() {
    const term = this.term.trim();
    if (term.length < 2) {
      this.options = [];
      this.isOpen = false;
      return;
    }
    this.isSearching = true;
    try {
      this.options = await searchPlaces({ term, limitCount: 10 });
      this.isOpen = true;
      this.error = null;
    } catch (e) {
      this.error = e?.body?.message || "Place search failed";
      this.options = [];
    } finally {
      this.isSearching = false;
    }
  }

  async handleMapSearch() {
    this.isSearching = true;
    try {
      this.options = await geocode({
        query: this.term.trim(),
        countryHint: null
      });
      this.isOpen = true;
      this.error = this.options.length ? null : "No place found on the map";
    } catch (e) {
      this.error = e?.body?.message || "Map search is unavailable right now";
    } finally {
      this.isSearching = false;
    }
  }

  handlePick(event) {
    const key = event.currentTarget.dataset.key;
    const opt = this.options.find((o) => o.key === key);
    this._value = opt.key;
    this._valueLabel = opt.label;
    this.term = "";
    this.options = [];
    this.isOpen = false;
    this.emit();
  }

  handleClear() {
    this._value = null;
    this._valueLabel = "";
    this.term = "";
    this.options = [];
    this.isOpen = false;
    this.emit();
  }

  handlePrecision(event) {
    this._precision = event.detail.value;
    if (!this.isRadius) {
      this._radius = null;
    }
    this.emit();
  }

  handleRadius(event) {
    const n = Number(event.detail.value);
    this._radius = Number.isFinite(n) && n > 0 ? n : null;
    this.emit();
  }

  handleUnit(event) {
    this._unit = event.detail.value;
    this.emit();
  }

  handleKey(event) {
    if (event.key === "Escape") {
      this.isOpen = false;
    }
  }

  disconnectedCallback() {
    window.clearTimeout(this.timer);
  }

  emit() {
    this.dispatchEvent(
      new CustomEvent("placechange", {
        detail: {
          key: this.value,
          label: this.valueLabel,
          precision: this.precision,
          radius: this.isRadius ? this.radius : null,
          unit: this.unit
        }
      })
    );
  }
}
