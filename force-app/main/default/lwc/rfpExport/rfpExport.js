import { LightningElement, api } from "lwc";
import getRawRows from "@salesforce/apex/RfpLaneController.getRawRows";
import { buildSheets, exportFileName } from "c/rfpWorkbook";
import { ensureSheetJs } from "c/rfpSheetLoader";

/** getRawRows returns one page of this size; a short page is the last one. */
const PAGE = 500;
const XLSX_MIME =
  "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet";

const hasCost = (lane) =>
  lane.Cost__c !== null && lane.Cost__c !== undefined && lane.Cost__c !== "";

export default class RfpExport extends LightningElement {
  @api project;
  @api bidsByLaneId;

  _lanes = [];
  @api
  get lanes() {
    return this._lanes;
  }
  set lanes(value) {
    this._lanes = value || [];
    // A new lane set re-answers the "nothing is priced" question from scratch.
    this.confirming = false;
  }

  busy = false;
  confirming = false;
  error = null;

  get priced() {
    return this._lanes.some(hasCost);
  }
  get disabled() {
    return this.busy;
  }

  handleExport() {
    this.error = null;
    if (!this.priced) {
      this.confirming = true;
      return;
    }
    this.run();
  }

  handleExportAnyway() {
    this.confirming = false;
    this.error = null;
    this.run();
  }

  async run() {
    this.busy = true;
    try {
      const rawRows = await this.allRawRows();
      await ensureSheetJs(this);
      const sheets = buildSheets(this._lanes, rawRows, this.bidsByLaneId);
      const XLSX = window.XLSX;
      const book = XLSX.utils.book_new();
      XLSX.utils.book_append_sheet(
        book,
        XLSX.utils.aoa_to_sheet(sheets.lanes),
        "Lanes"
      );
      XLSX.utils.book_append_sheet(
        book,
        XLSX.utils.aoa_to_sheet(sheets.bids),
        "Bids"
      );
      const out = XLSX.write(book, { bookType: "xlsx", type: "array" });
      this.download(new Blob([out], { type: XLSX_MIME }));
    } catch (e) {
      this.error =
        e?.body?.message || e?.message || "The export could not be built.";
    } finally {
      this.busy = false;
    }
  }

  /**
   * Pages the spreadsheet rows 500 at a time until a short page comes back.
   * Recursive rather than a loop, so the pages stay sequential without an
   * `await` inside a loop (which the project's ESLint config rules out).
   */
  async allRawRows(offset = 0, all = []) {
    const page =
      (await getRawRows({ projectId: this.project?.Id, offset })) || [];
    all.push(...page);
    return page.length === PAGE ? this.allRawRows(offset + PAGE, all) : all;
  }

  download(blob) {
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = exportFileName(
      this.project?.Customer__r?.Name,
      this.project?.Name,
      new Date()
    );
    // Safari can drop the download if the anchor isn't attached to the document,
    // or if the object URL is revoked before the download has actually started.
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    setTimeout(() => URL.revokeObjectURL(url), 0);
  }
}
