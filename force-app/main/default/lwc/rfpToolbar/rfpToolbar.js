import { LightningElement, api } from "lwc";

const PRECISIONS = [
  { label: "City", value: "CITY" },
  { label: "Province / state", value: "PROVINCE" },
  { label: "Radius", value: "RADIUS" }
];
const UNITS = [
  { label: "km", value: "KM" },
  { label: "mi", value: "MI" }
];

/**
 * The workbench toolbar row: the two navigation buttons, the four history
 * settings, the "Include RFP bids" toggle, the three history buttons and the
 * Excel export. It holds no state of its own — every control reports back to
 * rfpTool, which owns the settings and runs the calls, the same split
 * c/rfpBulkBar already uses for the bulk actions.
 */
export default class RfpToolbar extends LightningElement {
  @api busy = false;
  @api project = null;
  @api lanes = [];
  @api precision = "CITY";
  @api lookbackDays = 90;
  @api radius = 50;
  @api radiusUnit = "KM";

  // LWC1099 refuses a public Boolean property that defaults to true, so the
  // "on unless the container says otherwise" default lives on the backing
  // field and only an explicit `false` clears it.
  _includeBids = true;
  @api
  get includeBids() {
    return this._includeBids;
  }
  set includeBids(value) {
    this._includeBids = value !== false;
  }

  get precisionOptions() {
    return PRECISIONS;
  }
  get unitOptions() {
    return UNITS;
  }

  /** One event for the five settings; the container normalises the raw value. */
  setting(name, value) {
    this.dispatchEvent(
      new CustomEvent("settingchange", { detail: { name, value } })
    );
  }

  handleBack() {
    this.dispatchEvent(new CustomEvent("back"));
  }
  handleUploadMore() {
    this.dispatchEvent(new CustomEvent("uploadmore"));
  }
  handlePrecision(event) {
    this.setting("precision", event.detail.value);
  }
  handleLookback(event) {
    this.setting("lookbackDays", event.detail.value);
  }
  handleRadius(event) {
    this.setting("radius", event.detail.value);
  }
  handleRadiusUnit(event) {
    this.setting("radiusUnit", event.detail.value);
  }
  handleIncludeBids(event) {
    this.setting("includeBids", !!event.detail.checked);
  }
  handleLoadHistory() {
    this.dispatchEvent(new CustomEvent("loadhistory"));
  }
  handleRefreshHistory() {
    this.dispatchEvent(new CustomEvent("refreshhistory"));
  }
  handleRetryFailed() {
    this.dispatchEvent(new CustomEvent("retryfailed"));
  }
}
