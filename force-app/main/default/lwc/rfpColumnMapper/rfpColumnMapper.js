import { LightningElement, api } from "lwc";
import { TARGETS, missingRequired } from "c/rfpHeaderGuess";

export default class RfpColumnMapper extends LightningElement {
  @api headers = [];
  @api sampleRows = [];
  /** The container owns the chunked import; Import stays down until it is done. */
  @api busy = false;
  _mapping = {};
  @api
  get mapping() {
    return this._mapping;
  }
  set mapping(v) {
    this._mapping = { ...(v || {}) };
  }

  get options() {
    // A blank header names no column, so it is dropped here rather than
    // colliding with the "— none —" sentinel's empty value.
    return [
      { label: "— none —", value: "" },
      ...(this.headers || [])
        .filter((h) => h !== "")
        .map((h) => ({ label: h, value: h }))
    ];
  }
  get targets() {
    return TARGETS.map((t) => ({
      ...t,
      value: this._mapping[t.key] || "",
      sample: this.sampleFor(this._mapping[t.key])
    }));
  }
  sampleFor(header) {
    const i = (this.headers || []).indexOf(header);
    if (i < 0) return "";
    return (this.sampleRows || [])
      .map((r) => r[i])
      .filter((v) => v !== "" && v !== undefined)
      .slice(0, 3)
      .join(" · ");
  }
  get missing() {
    return missingRequired(this._mapping).map(
      (k) => TARGETS.find((t) => t.key === k).label
    );
  }
  get missingText() {
    return this.missing.length
      ? `Map ${this.missing.join(" and ")} (or both postal columns) to import.`
      : "";
  }
  get cannotImport() {
    return this.missing.length > 0 || !!this.busy;
  }

  handleChange(event) {
    const key = event.target.dataset.target;
    const next = { ...this._mapping };
    if (event.detail.value) next[key] = event.detail.value;
    else delete next[key];
    this._mapping = next;
    this.dispatchEvent(
      new CustomEvent("mappingchange", { detail: { mapping: { ...next } } })
    );
  }
  handleImport() {
    this.dispatchEvent(
      new CustomEvent("import", { detail: { mapping: { ...this._mapping } } })
    );
  }
}
