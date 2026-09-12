import { LightningElement, api } from "lwc";
import getRawRows from "@salesforce/apex/RfpLaneController.getRawRows";
import getBids from "@salesforce/apex/RfpBidController.getBids";
import { buildSheets, exportFileName } from "c/rfpWorkbook";
import { ensureSheetJs } from "c/rfpSheetLoader";
import { series } from "c/rfpBatch";

/** getRawRows returns one page of this size; a short page is the last one. */
const PAGE = 500;
/** One getBids round trip per lane, so past this many the Bids sheet is capped. */
const MAX_BID_LANES = 200;
// Lightning Web Security rejects a Blob whose type it does not allow ("Unsupported
// MIME type"), the spreadsheetml type among them; the .xlsx download name is what
// tells Excel what the bytes are.
const XLSX_MIME = "application/octet-stream";

const hasCost = (lane) => Number(lane.Cost__c) > 0;

export default class RfpExport extends LightningElement {
  @api project;
  /**
   * True while the container runs a chunked import or history pass. The lane
   * set is still moving then, so the button is down for that too — not only
   * for an export of our own already under way.
   */
  @api parentBusy = false;

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
  status = "";
  note = "";
  error = null;

  get priced() {
    return this._lanes.some(hasCost);
  }
  get disabled() {
    return this.busy || !!this.parentBusy;
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
    this.note = "";
    try {
      this.status = "Reading the rows…";
      const rawRows = await this.allRawRows();
      this.status = "Collecting the bids…";
      const bidsByLaneId = await this.collectBids();
      this.status = "Building the workbook…";
      await ensureSheetJs(this);
      const sheets = buildSheets(this._lanes, rawRows, bidsByLaneId);
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
      XLSX.utils.book_append_sheet(
        book,
        XLSX.utils.aoa_to_sheet(sheets.summary),
        "Summary"
      );
      const out = XLSX.write(book, { bookType: "xlsx", type: "array" });
      this.download(new Blob([out], { type: XLSX_MIME }));
    } catch (e) {
      this.error =
        e?.body?.message || e?.message || "The export could not be built.";
    } finally {
      this.busy = false;
      this.status = "";
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

  /**
   * The Bids sheet needs one getBids call per lane that has a selected bid, so
   * they are fetched here — at export time, for this click only — rather than
   * kept warm for an export that may never happen. A lane whose bids fail is
   * left out of the sheet and counted into the note.
   */
  async collectBids() {
    const withBid = this._lanes.filter((l) => l.Selected_Bid__c);
    const wanted = withBid.slice(0, MAX_BID_LANES);
    const bids = {};
    let failed = 0;
    await series(wanted, async (lane) => {
      try {
        bids[lane.Id] = (await getBids({ laneId: lane.Id })) || [];
      } catch {
        failed += 1;
      }
    });
    const notes = [];
    if (withBid.length > wanted.length) {
      notes.push(
        `Only the first ${MAX_BID_LANES} lanes with a selected bid carry their bids into the workbook.`
      );
    }
    if (failed) {
      notes.push(`Bids for ${failed} lanes could not be loaded.`);
    }
    this.note = notes.join(" ");
    return bids;
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
