import { LightningElement, api } from "lwc";
import { ensureSheetJs } from "c/rfpSheetLoader";
import { TARGETS } from "c/rfpHeaderGuess";

const XLSX_MIME = "application/octet-stream";

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
      // Headers only. An example row is not skipped on upload: RfpImportService drops a row
      // only when both ends are blank, so a sample Toronto to Montreal line would import as a
      // real lane, get costed and go out in the export.
      const headers = TARGETS.map((t) => t.label);
      const book = XLSX.utils.book_new();
      XLSX.utils.book_append_sheet(
        book,
        XLSX.utils.aoa_to_sheet([headers]),
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
