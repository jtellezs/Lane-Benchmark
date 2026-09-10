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

// One combobox listbox id per component instance, so two pickers on the same page
// (origin/destination) don't collide on aria-controls/aria-activedescendant targets.
let nextPickerId = 0;

export default class LaneBenchmarkPlacePicker extends LightningElement {
  @api label = "Place";

  listboxId = `lane-benchmark-picker-listbox-${nextPickerId++}`;

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
      this.setOptions([]);
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
  highlightedIndex = -1;
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
  requestSeq = 0;

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
    return this.options.map((o, index) => ({
      ...o,
      isMapbox: o.source === "Mapbox",
      loadText: o.loadCount ? `${o.loadCount} loads` : "",
      optionId: `${this.listboxId}-option-${index}`,
      liClass:
        index === this.highlightedIndex
          ? "slds-listbox__item option slds-has-focus"
          : "slds-listbox__item option",
      ariaSelected: index === this.highlightedIndex ? "true" : "false"
    }));
  }
  get activeDescendant() {
    return this.highlightedIndex >= 0
      ? `${this.listboxId}-option-${this.highlightedIndex}`
      : null;
  }

  /** Every options list change (search results, clear, pick) resets the keyboard highlight. */
  setOptions(list) {
    this.options = list;
    this.highlightedIndex = -1;
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
      this.setOptions([]);
      this.isOpen = false;
      return;
    }
    const seq = ++this.requestSeq;
    this.isSearching = true;
    try {
      const results = await searchPlaces({ term, limitCount: 10 });
      if (seq !== this.requestSeq) {
        return; // a newer search already landed; drop this stale response
      }
      this.setOptions(results);
      this.isOpen = true;
      this.error = null;
    } catch (e) {
      if (seq !== this.requestSeq) {
        return;
      }
      this.error = e?.body?.message || "Place search failed";
      this.setOptions([]);
    } finally {
      if (seq === this.requestSeq) {
        this.isSearching = false;
      }
    }
  }

  async handleMapSearch() {
    if (this.isSearching) {
      return;
    }
    this.isSearching = true;
    try {
      const results = await geocode({
        query: this.term.trim(),
        countryHint: null
      });
      this.setOptions(results);
      this.isOpen = true;
      this.error = results.length ? null : "No place found on the map";
    } catch (e) {
      this.error = e?.body?.message || "Map search is unavailable right now";
    } finally {
      this.isSearching = false;
    }
  }

  handlePick(event) {
    const key = event.currentTarget.dataset.key;
    this.selectOption(this.options.find((o) => o.key === key));
  }

  selectOption(opt) {
    if (!opt) {
      return;
    }
    this._value = opt.key;
    this._valueLabel = opt.label;
    this.term = "";
    this.setOptions([]);
    this.isOpen = false;
    this.emit();
  }

  handleClear() {
    this._value = null;
    this._valueLabel = "";
    this.term = "";
    this.setOptions([]);
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
      return;
    }
    if (!this.isOpen) {
      return;
    }
    if (event.key === "ArrowDown") {
      event.preventDefault();
      this.moveHighlight(1);
    } else if (event.key === "ArrowUp") {
      event.preventDefault();
      this.moveHighlight(-1);
    } else if (event.key === "Enter") {
      event.preventDefault();
      this.handleEnter();
    }
  }

  moveHighlight(step) {
    if (!this.options.length) {
      return;
    }
    const next = this.highlightedIndex + step;
    this.highlightedIndex = Math.min(
      Math.max(next, 0),
      this.options.length - 1
    );
  }

  handleEnter() {
    const picked = this.options[this.highlightedIndex];
    if (picked) {
      this.selectOption(picked);
      return;
    }
    if (!this.options.length && this.showMapAction) {
      this.handleMapSearch();
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
