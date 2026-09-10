import { LightningElement, api } from "lwc";

export const DEFAULT_FILTERS = Object.freeze({
  lookbackDays: 90,
  currencyIsoCode: null,
  modes: [],
  equipmentCategories: [],
  equipmentTypes: [],
  hazmatOnly: false,
  marketTestOnly: false,
  acceptedFilter: "ANY_STATUS"
});

export function cloneDefaults() {
  return {
    ...DEFAULT_FILTERS,
    modes: [],
    equipmentCategories: [],
    equipmentTypes: []
  };
}

export default class LaneBenchmarkFilters extends LightningElement {
  @api options = {
    modes: [],
    equipmentByCategory: {},
    currencies: ["CAD", "USD"]
  };
  _value = cloneDefaults();
  @api get value() {
    return this._value;
  }
  set value(v) {
    this._value = { ...cloneDefaults(), ...(v || {}) };
  }

  acceptedOptions = [
    { label: "All", value: "ANY_STATUS" },
    { label: "Accepted", value: "ACCEPTED" },
    { label: "Declined", value: "DECLINED" }
  ];
  flagOptions = [
    { label: "Hazmat only", value: "hazmatOnly" },
    { label: "Market test only", value: "marketTestOnly" }
  ];

  get lookbackDays() {
    return this._value.lookbackDays;
  }
  get currencyValue() {
    return this._value.currencyIsoCode || "";
  }
  get currencyOptions() {
    return [
      { label: "All", value: "" },
      ...(this.options.currencies || []).map((c) => ({ label: c, value: c }))
    ];
  }
  get modeOptions() {
    return (this.options.modes || []).map((m) => ({ label: m, value: m }));
  }
  get categoryOptions() {
    return Object.keys(this.options.equipmentByCategory || {}).map((c) => ({
      label: c,
      value: c
    }));
  }
  get typeOptions() {
    const byCat = this.options.equipmentByCategory || {};
    const cats = this._value.equipmentCategories.length
      ? this._value.equipmentCategories
      : Object.keys(byCat);
    return cats
      .flatMap((c) => byCat[c] || [])
      .map((t) => ({ label: t, value: t }));
  }
  get flagValues() {
    return this.flagOptions.map((f) => f.value).filter((f) => this._value[f]);
  }

  update(patch) {
    this._value = { ...this._value, ...patch };
    this.dispatchEvent(
      new CustomEvent("filterschange", { detail: { ...this._value } })
    );
  }

  handleLookback(event) {
    const n = parseInt(event.detail.value, 10);
    if (!Number.isFinite(n) || n < 1) {
      event.target.value = this._value.lookbackDays;
      this.update({});
      return; // keep previous value, re-emit
    }
    this.update({ lookbackDays: n });
  }
  handleCurrency(event) {
    this.update({ currencyIsoCode: event.detail.value || null });
  }
  handleModes(event) {
    this.update({ modes: [...event.detail.value] });
  }
  handleCategories(event) {
    const cats = [...event.detail.value];
    const allowed = new Set(
      cats.flatMap((c) => (this.options.equipmentByCategory || {})[c] || [])
    );
    const types = cats.length
      ? this._value.equipmentTypes.filter((t) => allowed.has(t))
      : this._value.equipmentTypes;
    this.update({ equipmentCategories: cats, equipmentTypes: types });
  }
  handleTypes(event) {
    this.update({ equipmentTypes: [...event.detail.value] });
  }
  handleAccepted(event) {
    this.update({ acceptedFilter: event.detail.value });
  }
  handleFlags(event) {
    const set = new Set(event.detail.value);
    this.update({
      hazmatOnly: set.has("hazmatOnly"),
      marketTestOnly: set.has("marketTestOnly")
    });
  }
  handleApply() {
    this.dispatchEvent(new CustomEvent("apply"));
  }
  handleReset() {
    this._value = cloneDefaults();
    this.dispatchEvent(
      new CustomEvent("filterschange", { detail: { ...this._value } })
    );
    this.dispatchEvent(new CustomEvent("reset"));
  }
  handleClearSaved() {
    this.dispatchEvent(new CustomEvent("clearsaved"));
  }
}
