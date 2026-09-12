import { LightningElement, wire } from "lwc";
import { CurrentPageReference } from "lightning/navigation";
import getProject from "@salesforce/apex/RfpProjectController.getProject";
import saveProject from "@salesforce/apex/RfpProjectController.saveProject";
import columnMappingFor from "@salesforce/apex/RfpProjectController.columnMappingFor";
import getLanes from "@salesforce/apex/RfpLaneController.getLanes";
import importLanes from "@salesforce/apex/RfpLaneController.importLanes";
import saveLanePricing from "@salesforce/apex/RfpLaneController.saveLanePricing";
import resolveLaneEnd from "@salesforce/apex/RfpLaneController.resolveLaneEnd";
import loadHistory from "@salesforce/apex/RfpHistoryController.loadHistory";
import { toImportRows } from "c/rfpSheet";
import { guess } from "c/rfpHeaderGuess";
import { chunk, mergeLanes, lanesForHistory, series } from "c/rfpBatch";
import { applyFilter, STATUS_FILTERS, siblings } from "c/rfpLaneFilter";
import { runBulk, applyBulkResult, summaryText } from "c/rfpBulk";

// Apex caps a single importLanes call at 200 rows and a loadHistory call at 10
// lane ids, so both run as a sequence of chunks with a progress bar and a Stop.
const IMPORT_CHUNK = 200;
const HISTORY_CHUNK = 10;
const DEFAULT_RADIUS = 50;
const MAX_RADIUS = 500;

const apexMessage = (e, fallback) =>
  (e && e.body && e.body.message) || fallback;

/** The customer's saved mapping wins for every header the new file still has. */
function startingMapping(headers, saved) {
  const mapping = guess(headers);
  Object.keys(saved || {}).forEach((key) => {
    if ((headers || []).includes(saved[key])) {
      mapping[key] = saved[key];
    }
  });
  return mapping;
}

export default class RfpTool extends LightningElement {
  view = "list";
  project = null;
  lanes = [];
  selectedId = null;
  selectedIds = [];
  filter = { status: "all", text: "" };
  pendingIds = [];
  rowErrors = {};
  twinOffer = null; // { sourceLaneId, laneIds }
  bulkResult = null;

  fileName = "";
  headers = [];
  rows = [];
  mapping = {};
  savedMapping = null;

  precision = "CITY";
  lookbackDays = 90;
  radius = DEFAULT_RADIUS;
  radiusUnit = "KM";
  includeBids = true;

  // `loading` is a single round trip (a spinner); `busy` is a chunked run that
  // owns the progress bar and the Stop button.
  loading = false;
  busy = false;
  stopRequested = false;
  progress = { done: 0, total: 0 };
  error = null;
  mappingNote = "";
  summary = "";
  openedProjectId = null;

  /** The Account component links here with ?c__projectId=…; open it once. */
  @wire(CurrentPageReference)
  handlePageReference(reference) {
    const projectId =
      reference && reference.state && reference.state.c__projectId;
    if (projectId && projectId !== this.openedProjectId) {
      this.openProject(projectId);
    }
  }

  get isList() {
    return this.view === "list";
  }
  get isUpload() {
    return this.view === "upload";
  }
  get isMap() {
    return this.view === "map";
  }
  get isWorkbench() {
    return this.view === "workbench";
  }
  get projectId() {
    return this.project ? this.project.Id : null;
  }
  get projectTitle() {
    if (!this.project) {
      return "";
    }
    const customer = this.project.Customer__r
      ? ` — ${this.project.Customer__r.Name}`
      : "";
    return `${this.project.Name}${customer}`;
  }
  get currency() {
    return (this.project && this.project.CurrencyIsoCode) || "CAD";
  }
  get selectedLane() {
    return this.lanes.find((l) => l.Id === this.selectedId) || null;
  }
  get sampleRows() {
    return this.rows.slice(0, 3);
  }
  get statusOptions() {
    return STATUS_FILTERS;
  }
  get visibleLanes() {
    return applyFilter(this.lanes, {
      ...this.filter,
      selectedIds: this.selectedIds
    });
  }
  get filterCount() {
    return `${this.visibleLanes.length} of ${this.lanes.length} lanes`;
  }
  get selectedCount() {
    return this.selectedIds.length;
  }
  get defaultMargin() {
    return this.project ? this.project.Default_Margin__c : null;
  }
  get twinText() {
    const n = this.twinOffer ? this.twinOffer.laneIds.length : 0;
    return `Apply the same cost and sell to ${n} identical lane${n === 1 ? "" : "s"}?`;
  }
  get hasLanes() {
    return this.lanes.length > 0;
  }
  get progressValue() {
    return this.progress.total
      ? Math.round((this.progress.done / this.progress.total) * 100)
      : 0;
  }
  get progressText() {
    return `${this.progress.done} of ${this.progress.total}`;
  }
  /**
   * A second upload into the same project continues the sheet's numbering
   * instead of restarting at 1 and colliding with the lanes already there
   * (ruling R20). The lanes on screen are the ones `loadLanes` last returned,
   * so they carry the highest `Row_Number__c` the project holds.
   */
  get nextRowNumber() {
    return (
      this.lanes.reduce(
        (max, lane) => Math.max(max, Number(lane.Row_Number__c) || 0),
        0
      ) + 1
    );
  }

  handleBack() {
    this.view = "list";
  }
  handleUploadMore() {
    this.view = "upload";
  }
  handleShowWorkbench() {
    this.view = "workbench";
  }
  handleStop() {
    this.stopRequested = true;
  }
  handleSelect(event) {
    this.selectedId = event.detail.laneId;
  }
  handleFilterStatus(event) {
    this.filter = { ...this.filter, status: event.detail.value };
  }
  handleFilterText(event) {
    this.filter = { ...this.filter, text: event.detail.value };
  }
  /**
   * Assigned straight from the event, with nothing awaited first: the table's
   * header checkbox reads this back as its own state, and a later assignment
   * would leave it a tick behind the rows.
   */
  handleSelectionChange(event) {
    this.selectedIds = event.detail.laneIds || [];
  }
  handleTwinDismiss() {
    this.twinOffer = null;
  }
  handleTwinApply() {
    const { sourceLaneId, laneIds } = this.twinOffer;
    this.twinOffer = null;
    this.bulk({
      action: "copy",
      scope: "ids",
      ids: laneIds,
      params: { sourceLaneId }
    });
  }
  handleMappingChange(event) {
    this.mapping = event.detail.mapping;
  }
  /**
   * One handler for every toolbar setting, keeping the normalisation the four
   * separate handlers did: an unusable lookback or radius falls back to its
   * default rather than reaching Apex, and the unit is only ever KM or MI.
   */
  handleSetting(event) {
    const { name, value } = event.detail;
    if (name === "precision") {
      this.precision = value;
    } else if (name === "lookbackDays") {
      const days = Number(value);
      this.lookbackDays = Number.isFinite(days) && days > 0 ? days : 90;
    } else if (name === "radius") {
      const n = Number(value);
      this.radius =
        Number.isFinite(n) && n >= 1 && n <= MAX_RADIUS
          ? Math.round(n)
          : DEFAULT_RADIUS;
    } else if (name === "radiusUnit") {
      this.radiusUnit = value === "MI" ? "MI" : "KM";
    }
  }
  handleOpenProject(event) {
    this.openProject(event.detail.projectId);
  }

  async openProject(projectId) {
    this.openedProjectId = projectId;
    this.loading = true;
    this.error = null;
    this.mappingNote = "";
    this.summary = "";
    this.selectedId = null;
    this.progress = { done: 0, total: 0 };
    try {
      this.project = await getProject({ projectId });
      this.savedMapping = await this.loadSavedMapping();
      await this.loadLanes();
      this.view = this.hasLanes ? "workbench" : "upload";
    } catch (e) {
      this.error = apexMessage(e, "The RFP project could not be opened.");
    } finally {
      this.loading = false;
    }
  }

  /** The project's own mapping first, then whatever this customer used last. */
  async loadSavedMapping() {
    try {
      const json =
        this.project.Column_Mapping__c ||
        (this.project.Customer__c
          ? await columnMappingFor({ accountId: this.project.Customer__c })
          : null);
      return json ? JSON.parse(json) : null;
    } catch {
      return null;
    }
  }

  /** A reload is a fresh sheet: the selection, the row errors and any offer go. */
  async loadLanes() {
    this.lanes = (await getLanes({ projectId: this.projectId })) || [];
    this.selectedIds = [];
    this.pendingIds = [];
    this.rowErrors = {};
    this.twinOffer = null;
    this.bulkResult = null;
  }

  handleParsed(event) {
    const { fileName, headers, rows } = event.detail;
    this.fileName = fileName;
    this.headers = headers;
    this.rows = rows;
    this.mapping = startingMapping(headers, this.savedMapping);
    this.summary = "";
    this.view = "map";
  }

  async handleImport(event) {
    // The mapper's Import button is disabled while `busy`, so this is the
    // belt-and-braces half: a second event can never import every row twice.
    if (this.busy) {
      return;
    }
    const mapping = event.detail.mapping;
    this.mapping = mapping;
    this.stopRequested = false;
    this.busy = true;
    this.error = null;
    this.mappingNote = "";
    const total = this.rows.length;
    this.progress = { done: 0, total };
    const totals = { imported: 0, skipped: 0, unresolvedEnds: 0, failed: 0 };
    // Fixed before the first call: `loadLanes` below moves it on, and every
    // chunk of this file must number from where the project already ended.
    const startRow = this.nextRowNumber;
    try {
      await series(chunk(this.rows, IMPORT_CHUNK), (rows, index) =>
        this.importChunk(totals, rows, index * IMPORT_CHUNK, startRow, total)
      );
      // A failed chunk still leaves the earlier chunks' lanes in the project,
      // so the workbench opens either way rather than hiding rows that exist.
      if (this.error) {
        this.error = `${this.error} — imported ${totals.imported} of ${total} rows before failing.`;
      } else {
        this.summary = this.importSummary(totals);
        await this.rememberMapping(mapping);
      }
      await this.loadLanes();
      this.view = "workbench";
    } catch (e) {
      this.error = apexMessage(e, "The lanes could not be loaded.");
    } finally {
      this.busy = false;
    }
  }

  /**
   * A Stop leaves the rows it never reached out of the counts, so the summary
   * says how far the import actually got; `failed` (rows the insert refused
   * one at a time) only appears when there were any.
   */
  importSummary(totals) {
    const stopped = this.stopRequested
      ? `stopped after ${this.progress.done} rows; `
      : "";
    const failed = totals.failed ? `, failed ${totals.failed}` : "";
    return `${stopped}imported ${totals.imported}, skipped ${totals.skipped}, unresolved ends ${totals.unresolvedEnds}${failed}`;
  }

  /** One importLanes call; a chunk that fails stops the rest of the import. */
  async importChunk(totals, rows, offset, startRow, total) {
    if (this.stopRequested) {
      return;
    }
    try {
      const summary = await importLanes({
        projectId: this.projectId,
        rowsJson: JSON.stringify(
          toImportRows(this.headers, rows, this.mapping, startRow + offset)
        )
      });
      Object.keys(totals).forEach((key) => {
        totals[key] += (summary && summary[key]) || 0;
      });
    } catch (e) {
      this.error = apexMessage(e, "The lanes could not be imported.");
      this.stopRequested = true;
      return;
    }
    this.progress = { done: Math.min(offset + IMPORT_CHUNK, total), total };
  }

  /** A mapping that imported once is the starting point for the next file. */
  async rememberMapping(mapping) {
    try {
      this.savedMapping = mapping;
      this.project = await saveProject({
        projectJson: JSON.stringify({
          Id: this.projectId,
          Column_Mapping__c: JSON.stringify(mapping)
        })
      });
    } catch (e) {
      this.mappingNote = apexMessage(
        e,
        "The column mapping was not remembered."
      );
    }
  }

  handleLoadHistory() {
    this.runHistory(lanesForHistory(this.lanes, "pending"));
  }
  handleRefreshHistory() {
    this.runHistory(lanesForHistory(this.lanes, "all"));
  }
  handleRetryFailed() {
    this.runHistory(lanesForHistory(this.lanes, "failed"));
  }

  /**
   * Runs the snapshot 10 lanes at a time. A chunk that fails marks just those
   * lanes Failed on screen and the run carries on, so one bad chunk does not
   * cost the whole sheet; "Retry failed" picks them up afterwards.
   */
  async runHistory(lanes) {
    // The three history buttons are disabled while `busy`; this also stops a
    // click that slipped through (a keyboard repeat, a stale render) from
    // starting a second run on top of the one already going.
    if (this.busy) {
      return;
    }
    const laneIds = lanes.map((l) => l.Id);
    this.stopRequested = false;
    this.busy = true;
    // A fresh run owns the banner: a successful retry clears the chunk failure
    // the previous run left behind.
    this.error = null;
    this.progress = { done: 0, total: laneIds.length };
    try {
      await series(chunk(laneIds, HISTORY_CHUNK), (ids) =>
        this.historyChunk(ids, laneIds.length)
      );
    } finally {
      this.busy = false;
    }
  }

  async historyChunk(ids, total) {
    if (this.stopRequested) {
      return;
    }
    try {
      const updated = await loadHistory({
        laneIds: ids,
        precision: this.precision,
        lookbackDays: this.lookbackDays,
        radius: this.radius,
        radiusUnit: this.radiusUnit,
        includeBids: this.includeBids
      });
      this.lanes = mergeLanes(this.lanes, updated);
    } catch (e) {
      this.lanes = mergeLanes(
        this.lanes,
        ids.map((id) => ({ ...this.laneById(id), Hist_Status__c: "Failed" }))
      );
      this.error = apexMessage(
        e,
        "History failed for a chunk; use Retry failed."
      );
    }
    this.progress = { done: this.progress.done + ids.length, total };
  }

  laneById(laneId) {
    return this.lanes.find((l) => l.Id === laneId) || { Id: laneId };
  }

  /**
   * One lane's save, from the panel or from a table cell. Several lanes may be
   * saving at once (a quick Enter-Enter-Enter down a column); a lane already
   * saving ignores a second request. A failure lands on the row, not the banner.
   */
  async handlePricingChange(event) {
    const { laneId, ...fields } = event.detail;
    if (this.busy) {
      this.error = "Wait for the current run to finish.";
      return;
    }
    if (this.pendingIds.includes(laneId)) {
      return;
    }
    this.pendingIds = [...this.pendingIds, laneId];
    // A new object rather than a delete in place: LWC reacts to the assignment.
    this.rowErrors = { ...this.rowErrors, [laneId]: undefined };
    try {
      const lane = await saveLanePricing({
        laneJson: JSON.stringify({ Id: laneId, ...fields })
      });
      this.lanes = mergeLanes(this.lanes, lane);
      const twins = siblings(this.lanes, lane);
      this.twinOffer = twins.length
        ? { sourceLaneId: laneId, laneIds: twins.map((l) => l.Id) }
        : null;
    } catch (e) {
      this.rowErrors = {
        ...this.rowErrors,
        [laneId]: apexMessage(e, "The price could not be saved.")
      };
    } finally {
      this.pendingIds = this.pendingIds.filter((id) => id !== laneId);
    }
  }

  handleBulk(event) {
    const { action, scope, ...params } = event.detail;
    const ids =
      scope === "selected"
        ? this.selectedIds
        : scope === "skipped"
          ? (this.bulkResult && this.bulkResult.skippedIds) || []
          : this.lanes.map((l) => l.Id);
    this.bulk({ action, scope, ids, params });
  }

  /** Every many-lane call goes through here: progress bar, Stop, merge, summary. */
  async bulk({ action, ids, params }) {
    if (this.busy || !ids.length) {
      return;
    }
    // An inline save is a lane's own round trip already in flight; a bulk run
    // started on top of it would merge its own copy of that lane back over the
    // save. Say so rather than swallowing the click.
    if (this.pendingIds.length) {
      this.error = "Wait for the current save to finish.";
      return;
    }
    this.stopRequested = false;
    this.busy = true;
    this.error = null;
    this.twinOffer = null;
    this.progress = { done: 0, total: ids.length };
    try {
      const result = await runBulk({
        action,
        ids,
        params,
        onProgress: (n) => {
          this.progress = { done: this.progress.done + n, total: ids.length };
        },
        isStopped: () => this.stopRequested
      });
      const next = applyBulkResult(this.lanes, this.selectedIds, result);
      this.lanes = next.lanes;
      this.selectedIds = next.selectedIds;
      this.bulkResult = result;
      this.summary = summaryText(result);
    } catch (e) {
      // runBulk keeps a failed chunk to itself; anything landing here failed
      // outside one, so the whole run is off and the banner says so.
      this.error = apexMessage(e, "The bulk action failed.");
    } finally {
      this.busy = false;
    }
  }

  async handleResolveEnd(event) {
    const { laneId, side, key } = event.detail;
    this.error = null;
    try {
      const lane = await resolveLaneEnd({ laneId, side, placeKey: key });
      this.lanes = mergeLanes(this.lanes, lane);
      if (lane.Origin_Resolved__c && lane.Destination_Resolved__c) {
        await this.runHistory([lane]);
      }
    } catch (e) {
      this.error = apexMessage(e, "The place could not be applied.");
    }
  }
}
