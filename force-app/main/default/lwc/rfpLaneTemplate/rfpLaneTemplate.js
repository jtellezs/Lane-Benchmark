import { LightningElement, api } from "lwc";
import { ensureSheetJs } from "c/rfpSheetLoader";
import { TARGETS } from "c/rfpHeaderGuess";

const XLSX_MIME = "application/octet-stream";

/** One filled row so the shape is obvious; it names places that resolve to nothing, so an upload skips it. */
const EXAMPLE = {
  originCity: "Toronto",
  originProvince: "ON",
  originCountry: "CA",
  destinationCity: "Montreal",
  destinationProvince: "QC",
  destinationCountry: "CA",
  mode: "Truckload",
  equipmentCategory: "Van",
  equipmentType: "Dry Van 53'",
  shipmentsPerYear: 12
};

/**
 * The lane template, wherever a pricer needs it: beside the upload, and on the project list,
 * because the template is most useful before a project exists - you fill it in first and create
 * the project to upload it into.
 *
 * Its headers are TARGETS' own labels, the strings the column guesser matches, so a file filled
 * in from it maps with nothing left to match by hand.
 */
export default class RfpLaneTemplate extends LightningElement {
  @api variant = "base";
  @api label = "Download template";

  error = null;
  busy = false;

  async handleDownload() {
    this.error = null;
    this.busy = true;
    try {
      await ensureSheetJs(this);
      const XLSX = window.XLSX;
      const headers = TARGETS.map((t) => t.label);
      const example = TARGETS.map((t) => EXAMPLE[t.key] ?? "");
      const book = XLSX.utils.book_new();
      XLSX.utils.book_append_sheet(
        book,
        XLSX.utils.aoa_to_sheet([headers, example]),
        "Lanes"
      );
      const out = XLSX.write(book, { bookType: "xlsx", type: "array" });
      this.download(new Blob([out], { type: XLSX_MIME }), "lane-template.xlsx");
    } catch (e) {
      this.error =
        e?.body?.message || e?.message || "The template could not be built.";
    } finally {
      this.busy = false;
    }
  }

  download(blob, name) {
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = name;
    // Safari drops the download if the anchor is not in the document, or if the
    // object URL is revoked before the download has started.
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    setTimeout(() => URL.revokeObjectURL(url), 0);
  }
}
