import { LightningElement, api, track } from "lwc";
import { toCsv, fileName } from "c/laneBenchmarkCsv";
import { formatDistance } from "c/distanceUnit";

const MODE_CLASS = {
  LTL: "ltl-cell",
  Truckload: "ftl-cell",
  "Freight Forwarding": "freight-cell"
};
export const CSV_COLUMNS = [
  { label: "Source", field: "source" },
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
  // phase 7: the load's billed miles as a raw number (blank for bids); the CSV never follows the
  // mi/km toggle, so a spreadsheet can always divide by it
  { label: "Miles", field: "load.miles" },
  { label: "Quote date", field: "quoteDate" },
  { label: "Load status", field: "loadStatus" },
  { label: "Hazmat", field: "hazmat" },
  { label: "Accepted", field: "accepted" },
  { label: "Quote", field: "quoteName" },
  { label: "Comments", field: "opsComments" },
  { label: "Expires on", field: "bid.expiresOn" }
];

export default class LaneBenchmarkResults extends LightningElement {
  @api originLabel = "";
  @api destinationLabel = "";
  // 'mi' | 'km', owned by c-lane-benchmark (which follows the Distance_Unit__c channel)
  @api unit = "mi";
  @track expanded = new Set();
  selected = null;
  _rows = [];

  @api
  get rows() {
    return this._rows;
  }
  set rows(value) {
    this._rows = value;
    // A fresh result set invalidates any indices the user had expanded before.
    this.expanded = new Set();
  }

  get hasRows() {
    return (this._rows || []).length > 0;
  }
  get distanceHeader() {
    return this.unit === "km" ? "Km" : "Miles";
  }
  get viewRows() {
    return (this._rows || []).map((r, i) => ({
      ...r,
      index: i,
      rowNumber: i + 1,
      modeClass: `slds-cell-wrap ${MODE_CLASS[r.mode] || ""}`.trim(),
      isExpanded: this.expanded.has(i),
      detailKey: `${r.quoteId}-detail`,
      total:
        r.carrierTotal === null || r.carrierTotal === undefined
          ? ""
          : Number(r.carrierTotal).toFixed(2),
      // bid rows carry no miles, and a load can have none (or 0) in Revenova: both show a dash
      milesText:
        r.load && Number(r.load.miles) > 0
          ? formatDistance(r.load.miles, this.unit)
          : "—",
      hazmatText: r.hazmat ? "Hazmat" : "",
      acceptedText: r.bid ? "" : r.accepted ? "Accepted" : "Declined",
      isBid: !!r.bid,
      bidExpiry: r.bid ? `Expires ${r.bid.expiresOn}` : "",
      bidClass:
        r.bid && r.bid.status === "Expired"
          ? "slds-text-color_weak bid-expired"
          : "",
      transitText:
        r.bid && r.bid.transitDays != null
          ? `${r.bid.transitDays} d transit`
          : "",
      fscText:
        r.bid && r.bid.fuelSurcharge != null
          ? `FSC ${Number(r.bid.fuelSurcharge).toFixed(2)}${r.bid.fscIncluded ? " (included)" : ""}`
          : ""
    }));
  }
  get selectedFlags() {
    return this.selected?.carrier?.attention
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
    this.selected = this._rows[i];
  }
  handleClose() {
    this.selected = null;
  }
  handleDialogClick(event) {
    event.stopPropagation();
  }

  handleExport() {
    const csv = toCsv(
      this._rows.map((r) => ({ ...r, source: r.bid ? "Bid" : "Load" })),
      CSV_COLUMNS
    );
    const blob = new Blob([csv], { type: "text/csv;charset=utf-8" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = fileName(this.originLabel, this.destinationLabel, new Date());
    // Safari can drop the download if the anchor isn't attached to the document,
    // or if the object URL is revoked before the download has actually started.
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    setTimeout(() => URL.revokeObjectURL(url), 0);
  }
}
