import { LightningElement, api, track } from "lwc";
import { toCsv, fileName } from "c/laneBenchmarkCsv";

const MODE_CLASS = {
  LTL: "ltl-cell",
  Truckload: "ftl-cell",
  "Freight Forwarding": "freight-cell"
};
export const CSV_COLUMNS = [
  { label: "Origin", field: "origin" },
  { label: "Destination", field: "destination" },
  { label: "Carrier", field: "carrierName" },
  { label: "Contact", field: "contactName" },
  { label: "Email", field: "carrier.contactEmail" },
  { label: "Phone", field: "carrier.contactPhone" },
  { label: "Mode", field: "mode" },
  { label: "Equipment", field: "equipment" },
  { label: "Currency", field: "currencyIsoCode" },
  { label: "Carrier total", field: "carrierTotal" },
  { label: "Quote date", field: "quoteDate" },
  { label: "Load status", field: "loadStatus" },
  { label: "Hazmat", field: "hazmat" },
  { label: "Accepted", field: "accepted" },
  { label: "Quote", field: "quoteName" },
  { label: "Comments", field: "opsComments" }
];

export default class LaneBenchmarkResults extends LightningElement {
  @api rows = [];
  @api originLabel = "";
  @api destinationLabel = "";
  @track expanded = new Set();
  selected = null;

  get hasRows() {
    return (this.rows || []).length > 0;
  }
  get viewRows() {
    return (this.rows || []).map((r, i) => ({
      ...r,
      index: i,
      rowNumber: i + 1,
      modeClass: `slds-cell-wrap ${MODE_CLASS[r.mode] || ""}`.trim(),
      isExpanded: this.expanded.has(i),
      total:
        r.carrierTotal === null || r.carrierTotal === undefined
          ? ""
          : Number(r.carrierTotal).toFixed(2),
      hazmatText: r.hazmat ? "Hazmat" : "",
      acceptedText: r.accepted ? "Accepted" : "Declined"
    }));
  }
  get selectedFlags() {
    return this.selected && this.selected.carrier.attention
      ? this.selected.carrier.attention.trim()
      : "";
  }

  handleExpand(event) {
    const i = Number(event.currentTarget.closest("tr").dataset.index);
    const next = new Set(this.expanded);
    if (next.has(i)) next.delete(i);
    else next.add(i);
    this.expanded = next;
  }
  handleCarrier(event) {
    const i = Number(event.currentTarget.closest("tr").dataset.index);
    this.selected = this.rows[i];
  }
  handleClose() {
    this.selected = null;
  }
  handleDialogClick(event) {
    event.stopPropagation();
  }

  handleExport() {
    const csv = toCsv(this.rows, CSV_COLUMNS);
    const blob = new Blob([csv], { type: "text/csv;charset=utf-8" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = fileName(this.originLabel, this.destinationLabel, new Date());
    a.click();
    URL.revokeObjectURL(url);
  }
}
