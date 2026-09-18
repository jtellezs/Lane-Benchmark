import { createElement } from "lwc";
import { CurrentPageReference } from "lightning/navigation";
import RfpTool from "c/rfpTool";
import getProject from "@salesforce/apex/RfpProjectController.getProject";
import saveProject from "@salesforce/apex/RfpProjectController.saveProject";
import columnMappingFor from "@salesforce/apex/RfpProjectController.columnMappingFor";
import getLanes from "@salesforce/apex/RfpLaneController.getLanes";
import importLanes from "@salesforce/apex/RfpLaneController.importLanes";
import saveLanePricing from "@salesforce/apex/RfpLaneController.saveLanePricing";
import resolveLaneEnd from "@salesforce/apex/RfpLaneController.resolveLaneEnd";
import similarLanes from "@salesforce/apex/RfpLaneController.similarLanes";
import loadHistory from "@salesforce/apex/RfpHistoryController.loadHistory";
import getBids from "@salesforce/apex/RfpBidController.getBids";
import applyMedian from "@salesforce/apex/RfpBulkController.applyMedian";
import copyPricing from "@salesforce/apex/RfpBulkController.copyPricing";
import deleteLanes from "@salesforce/apex/RfpBulkController.deleteLanes";

// babel-plugin-jest-hoist only hoists literal jest.mock() calls, so each Apex
// module the workbench tree imports is listed out here.
jest.mock(
  "@salesforce/apex/RfpProjectController.getProject",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/RfpProjectController.saveProject",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/RfpProjectController.columnMappingFor",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/RfpProjectController.listProjects",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/RfpProjectController.searchAccounts",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/RfpProjectController.attachFile",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/RfpLaneController.getLanes",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/RfpLaneController.similarLanes",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/RfpLaneController.getRawRows",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/RfpLaneController.importLanes",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/RfpLaneController.saveLanePricing",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/RfpLaneController.resolveLaneEnd",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/RfpLaneController.laneRoute",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/RfpHistoryController.loadHistory",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/RfpBidController.getBids",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/RfpBidController.saveBid",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/RfpBulkController.applyMedian",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/RfpBulkController.applyPricing",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/RfpBulkController.applyBid",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/RfpBulkController.copyPricing",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/RfpBulkController.deleteLanes",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/LaneBenchmarkController.search",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/LaneBenchmarkController.searchPlaces",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/LaneBenchmarkController.geocode",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/CarrierLeadController.findCarrierLeads",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/SplitLaneController.splitOptions",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

jest.mock("@salesforce/resourceUrl/sheetJs", () => "/sheetjs", {
  virtual: true
});

const flush = () => Promise.resolve().then(() => Promise.resolve());
// Chained rather than looped: the ESLint config forbids `await` inside a loop.
const settle = (times = 6) =>
  Array.from({ length: times }).reduce((p) => p.then(flush), Promise.resolve());

const PROJECT = {
  Id: "a0P1",
  Name: "Costco Q4",
  Customer__c: "001x",
  Customer__r: { Name: "Costco" },
  CurrencyIsoCode: "CAD",
  Default_Margin__c: 15
};

const pendingLane = (n) => ({
  Id: `a0L${n}`,
  Row_Number__c: n,
  Origin_City__c: "Montreal",
  Origin_Province__c: "QC",
  Origin_Resolved__c: true,
  Destination_City__c: "Toronto",
  Destination_Province__c: "ON",
  Destination_Resolved__c: true,
  Hist_Status__c: "Pending",
  CurrencyIsoCode: "CAD"
});

const lanes = (count) =>
  Array.from({ length: count }, (_, i) => pendingLane(i + 1));

const field = (el, id) => el.shadowRoot.querySelector(`[data-id="${id}"]`);
const child = (el, tag) => el.shadowRoot.querySelector(tag);
const toolbar = (el) => el.shadowRoot.querySelector("c-rfp-toolbar");
// The toolbar row is c/rfpToolbar now, so the flows it used to own arrive
// here as its events instead of as clicks on buttons in this shadow root.
const fire = (el, name, detail) =>
  toolbar(el).dispatchEvent(
    detail ? new CustomEvent(name, { detail }) : new CustomEvent(name)
  );
const setting = (el, name, value) => fire(el, "settingchange", { name, value });

function mount() {
  const el = createElement("c-rfp-tool", { is: RfpTool });
  document.body.appendChild(el);
  return el;
}

/** Mounts and opens a project through the page reference, as the Account tab does. */
async function openFromUrl(laneList = lanes(2)) {
  getLanes.mockResolvedValue(laneList);
  const el = mount();
  CurrentPageReference.emit({ state: { c__projectId: "a0P1" } });
  await settle();
  return el;
}

describe("c-rfp-tool", () => {
  beforeEach(() => {
    getProject.mockResolvedValue(PROJECT);
    getLanes.mockResolvedValue([]);
    columnMappingFor.mockResolvedValue(null);
    getBids.mockResolvedValue([]);
    saveProject.mockResolvedValue(PROJECT);
  });

  afterEach(() => {
    jest.clearAllMocks();
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("shows the project list until a project is opened", async () => {
    const el = mount();
    await settle();
    expect(child(el, "c-rfp-project-list")).not.toBeNull();
    expect(child(el, "c-rfp-lane-table")).toBeNull();
    expect(getProject).not.toHaveBeenCalled();
  });

  it("opens the project named by c__projectId and shows the workbench once", async () => {
    const el = await openFromUrl(lanes(3));
    expect(getProject).toHaveBeenCalledWith({ projectId: "a0P1" });
    expect(getLanes).toHaveBeenCalledWith({ projectId: "a0P1" });
    const table = child(el, "c-rfp-lane-table");
    expect(table).not.toBeNull();
    expect(table.lanes.length).toBe(3);

    // A second page-reference emission must not re-open the same project.
    CurrentPageReference.emit({ state: { c__projectId: "a0P1" } });
    await settle();
    expect(getProject).toHaveBeenCalledTimes(1);
  });

  it("spins while opening and shows the progress bar only for a chunked run", async () => {
    let release;
    getProject.mockImplementation(
      () => new Promise((resolve) => (release = resolve))
    );
    getLanes.mockResolvedValue(lanes(2));
    const el = mount();
    CurrentPageReference.emit({ state: { c__projectId: "a0P1" } });
    await settle(2);
    expect(field(el, "loading")).not.toBeNull();
    expect(field(el, "progress")).toBeNull();
    expect(field(el, "stop")).toBeNull();

    release(PROJECT);
    await settle(8);
    expect(field(el, "loading")).toBeNull();

    loadHistory.mockImplementation(async ({ laneIds }) => {
      await flush();
      expect(field(el, "progress")).not.toBeNull();
      expect(field(el, "loading")).toBeNull();
      return laneIds.map((id) => ({
        ...pendingLane(Number(id.replace("a0L", ""))),
        Hist_Status__c: "Done"
      }));
    });
    fire(el, "loadhistory");
    await settle(10);
    expect(loadHistory).toHaveBeenCalledTimes(1);
    expect(field(el, "progress")).toBeNull();
  });

  it("opens an empty project on the upload step", async () => {
    const el = await openFromUrl([]);
    expect(child(el, "c-rfp-upload")).not.toBeNull();
    expect(child(el, "c-rfp-lane-table")).toBeNull();
  });

  it("shows the Apex message when the project cannot be opened", async () => {
    getProject.mockRejectedValue({ body: { message: "no access" } });
    const el = mount();
    CurrentPageReference.emit({ state: { c__projectId: "a0P1" } });
    await settle();
    expect(field(el, "error").textContent).toContain("no access");
  });

  it("opens the project the list asks for", async () => {
    getLanes.mockResolvedValue(lanes(1));
    const el = mount();
    await settle();
    child(el, "c-rfp-project-list").dispatchEvent(
      new CustomEvent("open", { detail: { projectId: "a0P7" } })
    );
    await settle();
    expect(getProject).toHaveBeenCalledWith({ projectId: "a0P7" });
    expect(child(el, "c-rfp-lane-table")).not.toBeNull();
  });

  describe("import", () => {
    async function toMapStep(rowCount) {
      const el = await openFromUrl([]);
      child(el, "c-rfp-upload").dispatchEvent(
        new CustomEvent("parsed", {
          detail: {
            fileName: "lanes.xlsx",
            headers: ["From", "To"],
            rows: Array.from({ length: rowCount }, (_, i) => [
              `City ${i + 1}`,
              "Toronto"
            ])
          }
        })
      );
      await settle();
      return el;
    }

    it("imports 450 rows in chunks of 200 and lands on the workbench", async () => {
      const el = await toMapStep(450);
      const mapper = child(el, "c-rfp-column-mapper");
      expect(mapper).not.toBeNull();

      importLanes.mockResolvedValue({
        imported: 200,
        skipped: 0,
        unresolvedEnds: 5
      });
      getLanes.mockResolvedValue(lanes(4));
      mapper.dispatchEvent(
        new CustomEvent("import", {
          detail: {
            mapping: { originCity: "From", destinationCity: "To" }
          }
        })
      );
      await settle(14);

      expect(importLanes).toHaveBeenCalledTimes(3);
      const sizes = importLanes.mock.calls.map(
        (c) => JSON.parse(c[0].rowsJson).length
      );
      expect(sizes).toEqual([200, 200, 50]);
      const starts = importLanes.mock.calls.map(
        (c) => JSON.parse(c[0].rowsJson)[0].rowNumber
      );
      expect(starts).toEqual([1, 201, 401]);
      expect(importLanes.mock.calls[0][0].projectId).toBe("a0P1");

      // The mapping is remembered on the project once the import finishes.
      const posted = JSON.parse(saveProject.mock.calls[0][0].projectJson);
      expect(posted.Id).toBe("a0P1");
      expect(JSON.parse(posted.Column_Mapping__c)).toEqual({
        originCity: "From",
        destinationCity: "To"
      });

      expect(field(el, "summary").textContent).toContain(
        "imported 600, skipped 0, unresolved ends 15"
      );
      expect(child(el, "c-rfp-lane-table")).not.toBeNull();
    });

    it("stops on a failed chunk but still shows the lanes it did import", async () => {
      const el = await toMapStep(450);
      importLanes
        .mockResolvedValueOnce({ imported: 200, skipped: 0, unresolvedEnds: 0 })
        .mockRejectedValueOnce({ body: { message: "row 240 is bad" } });
      getLanes.mockResolvedValue(lanes(200));
      child(el, "c-rfp-column-mapper").dispatchEvent(
        new CustomEvent("import", {
          detail: { mapping: { originCity: "From" } }
        })
      );
      await settle(14);
      expect(importLanes).toHaveBeenCalledTimes(2);
      expect(field(el, "error").textContent).toContain("row 240 is bad");
      expect(field(el, "error").textContent).toContain(
        "imported 200 of 450 rows before failing"
      );
      // The 200 lanes the first chunk landed exist in the project, so the
      // workbench opens on them instead of leaving the user on the mapper.
      expect(child(el, "c-rfp-lane-table")).not.toBeNull();
      expect(child(el, "c-rfp-lane-table").lanes.length).toBe(200);
      // A half-finished import is no endorsement of the mapping.
      expect(saveProject).not.toHaveBeenCalled();
    });

    it("counts the rows Apex refused into the summary line", async () => {
      const el = await toMapStep(3);
      importLanes.mockResolvedValue({
        imported: 2,
        skipped: 0,
        unresolvedEnds: 0,
        failed: 1
      });
      getLanes.mockResolvedValue(lanes(2));
      child(el, "c-rfp-column-mapper").dispatchEvent(
        new CustomEvent("import", {
          detail: { mapping: { originCity: "From" } }
        })
      );
      await settle(14);
      expect(field(el, "summary").textContent).toContain(
        "imported 2, skipped 0, unresolved ends 0, failed 1"
      );
    });

    it("continues the row numbering into a second upload", async () => {
      const el = await openFromUrl(lanes(22));
      fire(el, "uploadmore");
      await settle();
      child(el, "c-rfp-upload").dispatchEvent(
        new CustomEvent("parsed", {
          detail: {
            fileName: "more-lanes.xlsx",
            headers: ["From", "To"],
            rows: Array.from({ length: 250 }, (_, i) => [
              `City ${i + 1}`,
              "Toronto"
            ])
          }
        })
      );
      await settle();
      importLanes.mockResolvedValue({
        imported: 200,
        skipped: 0,
        unresolvedEnds: 0
      });
      child(el, "c-rfp-column-mapper").dispatchEvent(
        new CustomEvent("import", {
          detail: { mapping: { originCity: "From", destinationCity: "To" } }
        })
      );
      await settle(14);

      const starts = importLanes.mock.calls.map(
        (c) => JSON.parse(c[0].rowsJson)[0].rowNumber
      );
      // 22 lanes are already in the project, so the new sheet starts at 23.
      expect(starts).toEqual([23, 223]);
    });

    it("keeps the mapping-failure note visible after the lanes load", async () => {
      const el = await toMapStep(2);
      importLanes.mockResolvedValue({
        imported: 2,
        skipped: 0,
        unresolvedEnds: 0
      });
      saveProject.mockRejectedValue({ body: { message: "mapping too long" } });
      getLanes.mockResolvedValue(lanes(2));
      child(el, "c-rfp-column-mapper").dispatchEvent(
        new CustomEvent("import", {
          detail: { mapping: { originCity: "From" } }
        })
      );
      await settle(14);
      // loadLanes runs after rememberMapping, and must not clear the notice.
      expect(child(el, "c-rfp-lane-table")).not.toBeNull();
      expect(field(el, "mapping-note").textContent).toContain(
        "mapping too long"
      );
      expect(field(el, "error")).toBeNull();
    });

    it("says how far a stopped import got", async () => {
      const el = await toMapStep(450);
      getLanes.mockResolvedValue(lanes(2));
      importLanes.mockImplementation(async () => {
        await flush();
        field(el, "stop").click();
        return { imported: 200, skipped: 0, unresolvedEnds: 0 };
      });
      child(el, "c-rfp-column-mapper").dispatchEvent(
        new CustomEvent("import", {
          detail: { mapping: { originCity: "From" } }
        })
      );
      await settle(16);
      expect(importLanes).toHaveBeenCalledTimes(1);
      expect(field(el, "summary").textContent).toContain(
        "stopped after 200 rows; imported 200, skipped 0, unresolved ends 0"
      );
    });

    it("starts the mapper from the customer's saved mapping", async () => {
      columnMappingFor.mockResolvedValue(
        JSON.stringify({ destinationCity: "To", mode: "Gone" })
      );
      const el = await toMapStep(2);
      expect(columnMappingFor).toHaveBeenCalledWith({ accountId: "001x" });
      // The saved mapping wins for headers that still exist; "Gone" is dropped
      // and the guess fills the rest.
      expect(child(el, "c-rfp-column-mapper").mapping).toEqual({
        originCity: "From",
        destinationCity: "To"
      });
    });
  });

  describe("history", () => {
    const done = (ids) =>
      ids.map((id) => ({
        ...pendingLane(Number(id.replace("a0L", ""))),
        Hist_Status__c: "Done",
        Hist_Count__c: 4,
        Hist_Median__c: 2000
      }));

    it("runs 23 pending lanes as 10 / 10 / 3 in order and merges the result", async () => {
      const el = await openFromUrl(lanes(23));
      loadHistory.mockImplementation(({ laneIds }) =>
        Promise.resolve(done(laneIds))
      );
      fire(el, "loadhistory");
      await settle(14);

      expect(loadHistory).toHaveBeenCalledTimes(3);
      const sizes = loadHistory.mock.calls.map((c) => c[0].laneIds.length);
      expect(sizes).toEqual([10, 10, 3]);
      expect(loadHistory.mock.calls[0][0].laneIds[0]).toBe("a0L1");
      expect(loadHistory.mock.calls[1][0].laneIds[0]).toBe("a0L11");
      expect(loadHistory.mock.calls[2][0].laneIds).toEqual([
        "a0L21",
        "a0L22",
        "a0L23"
      ]);
      expect(loadHistory.mock.calls[0][0].precision).toBe("CITY");
      expect(loadHistory.mock.calls[0][0].lookbackDays).toBe(90);

      const table = child(el, "c-rfp-lane-table");
      expect(table.lanes.length).toBe(23);
      expect(table.lanes.every((l) => l.Hist_Status__c === "Done")).toBe(true);
      expect(table.lanes.map((l) => l.Id)).toEqual(lanes(23).map((l) => l.Id));
    });

    it("sends the chosen precision and lookback", async () => {
      const el = await openFromUrl(lanes(1));
      loadHistory.mockImplementation(({ laneIds }) =>
        Promise.resolve(done(laneIds))
      );
      setting(el, "precision", "RADIUS");
      setting(el, "lookbackDays", "30");
      await flush();
      fire(el, "loadhistory");
      await settle(8);
      expect(loadHistory.mock.calls[0][0].precision).toBe("RADIUS");
      expect(loadHistory.mock.calls[0][0].lookbackDays).toBe(30);
    });

    it("marks a failed chunk Failed locally and keeps going", async () => {
      const el = await openFromUrl(lanes(23));
      loadHistory
        .mockImplementationOnce(({ laneIds }) => Promise.resolve(done(laneIds)))
        .mockRejectedValueOnce({ body: { message: "callout limit" } })
        .mockImplementationOnce(({ laneIds }) =>
          Promise.resolve(done(laneIds))
        );
      fire(el, "loadhistory");
      await settle(16);

      expect(loadHistory).toHaveBeenCalledTimes(3);
      const table = child(el, "c-rfp-lane-table");
      expect(table.lanes[0].Hist_Status__c).toBe("Done");
      expect(table.lanes[10].Hist_Status__c).toBe("Failed");
      expect(table.lanes[22].Hist_Status__c).toBe("Done");
      expect(field(el, "error").textContent).toContain("callout limit");

      // "Retry failed" runs only over the lanes the failed chunk left behind.
      loadHistory.mockClear();
      loadHistory.mockImplementation(({ laneIds }) =>
        Promise.resolve(done(laneIds))
      );
      fire(el, "retryfailed");
      await settle(10);
      expect(loadHistory).toHaveBeenCalledTimes(1);
      expect(loadHistory.mock.calls[0][0].laneIds.length).toBe(10);
      expect(loadHistory.mock.calls[0][0].laneIds[0]).toBe("a0L11");
      // The run that succeeded owns the banner, so the stale failure is gone.
      expect(field(el, "error")).toBeNull();
      expect(child(el, "c-rfp-lane-table").lanes[10].Hist_Status__c).toBe(
        "Done"
      );
    });

    it("refreshes every resolved lane and skips the unresolved ones", async () => {
      const list = lanes(3);
      list[2].Origin_Resolved__c = false;
      list[2].Hist_Status__c = "Unresolved";
      list[1].Hist_Status__c = "Done";
      const el = await openFromUrl(list);
      loadHistory.mockImplementation(({ laneIds }) =>
        Promise.resolve(done(laneIds))
      );

      fire(el, "loadhistory");
      await settle(8);
      expect(loadHistory.mock.calls[0][0].laneIds).toEqual(["a0L1"]);

      loadHistory.mockClear();
      fire(el, "refreshhistory");
      await settle(8);
      expect(loadHistory.mock.calls[0][0].laneIds).toEqual(["a0L1", "a0L2"]);
    });

    it("ignores a Load history click while a run already owns the page", async () => {
      const el = await openFromUrl(lanes(23));
      loadHistory.mockImplementation(async ({ laneIds }) => {
        await flush();
        // The toolbar takes its disabled states and the export's from this
        // flag, and its own suite covers them; an event that gets through
        // anyway (a keyboard repeat, a stale render) must not start a second
        // pass over the same 23 lanes.
        expect(toolbar(el).busy).toBe(true);
        fire(el, "loadhistory");
        return done(laneIds);
      });
      fire(el, "loadhistory");
      await settle(16);
      expect(loadHistory).toHaveBeenCalledTimes(3);
      expect(toolbar(el).busy).toBe(false);
    });

    it("stops between chunks when Stop is pressed", async () => {
      const el = await openFromUrl(lanes(23));
      // Stop only appears once the run has started, so the first chunk waits a
      // render before pressing it — the loop then breaks before the second.
      loadHistory.mockImplementation(async ({ laneIds }) => {
        await flush();
        const stop = field(el, "stop");
        expect(stop).not.toBeNull();
        stop.click();
        return done(laneIds);
      });
      fire(el, "loadhistory");
      await settle(12);
      expect(loadHistory).toHaveBeenCalledTimes(1);
      expect(child(el, "c-rfp-lane-table").lanes[0].Hist_Status__c).toBe(
        "Done"
      );
      expect(child(el, "c-rfp-lane-table").lanes[10].Hist_Status__c).toBe(
        "Pending"
      );
    });

    it("passes the radius and unit to every history chunk", async () => {
      loadHistory.mockImplementation(async ({ laneIds }) =>
        laneIds.map((Id) => ({ ...pendingLane(1), Id, Hist_Status__c: "Done" }))
      );
      const el = await openFromUrl(lanes(2));
      setting(el, "radius", "150");
      setting(el, "radiusUnit", "MI");
      fire(el, "loadhistory");
      await settle();
      expect(loadHistory).toHaveBeenCalledTimes(1);
      expect(loadHistory.mock.calls[0][0]).toMatchObject({
        precision: "CITY",
        lookbackDays: 90,
        radius: 150,
        radiusUnit: "MI",
        includeBids: true
      });
    });
    it("hands the toolbar the project and lanes its export needs", async () => {
      const el = await openFromUrl(lanes(2));
      expect(toolbar(el).project).toEqual(
        expect.objectContaining({ Id: expect.any(String) })
      );
      expect(toolbar(el).lanes.map((l) => l.Id)).toEqual(["a0L1", "a0L2"]);
    });
    it("sends the bids toggle, on by default, with every history run", async () => {
      loadHistory.mockResolvedValue([]);
      const el = await openFromUrl(lanes(1));
      expect(toolbar(el).includeBids).toBe(true);
      fire(el, "loadhistory");
      await settle();
      expect(loadHistory.mock.calls[0][0].includeBids).toBe(true);

      setting(el, "includeBids", false);
      await flush();
      expect(toolbar(el).includeBids).toBe(false);
      fire(el, "refreshhistory");
      await settle();
      expect(loadHistory.mock.calls[1][0].includeBids).toBe(false);

      // Every history flow goes through the one loadHistory call site, so the
      // toggle applies to Load history, Refresh history and Retry failed alike.
      setting(el, "includeBids", true);
      await flush();
      fire(el, "loadhistory");
      await settle();
      expect(loadHistory.mock.calls[2][0].includeBids).toBe(true);
    });

    it("falls back to 50 km when the radius box is emptied", async () => {
      loadHistory.mockResolvedValue([]);
      const el = await openFromUrl(lanes(1));
      setting(el, "radius", "");
      fire(el, "loadhistory");
      await settle();
      expect(loadHistory.mock.calls[0][0].radius).toBe(50);
      expect(loadHistory.mock.calls[0][0].radiusUnit).toBe("KM");
    });
  });

  describe("workbench edits", () => {
    it("saves a price change and merges the returned lane", async () => {
      const el = await openFromUrl(lanes(2));
      saveLanePricing.mockResolvedValue({
        ...pendingLane(2),
        Cost__c: 1200,
        Margin__c: 15,
        Sell__c: 1411.76
      });
      child(el, "c-rfp-lane-table").dispatchEvent(
        new CustomEvent("select", { detail: { laneId: "a0L2" } })
      );
      await flush();
      child(el, "c-rfp-lane-panel").dispatchEvent(
        new CustomEvent("pricingchange", {
          detail: {
            laneId: "a0L2",
            Cost__c: 1200,
            Cost_Source__c: "Manual",
            Selected_Bid__c: null,
            Margin__c: 15,
            Sell__c: 1411.76,
            Notes__c: "ok"
          }
        })
      );
      await settle(8);
      expect(JSON.parse(saveLanePricing.mock.calls[0][0].laneJson)).toEqual({
        Id: "a0L2",
        Cost__c: 1200,
        Cost_Source__c: "Manual",
        Selected_Bid__c: null,
        Margin__c: 15,
        Sell__c: 1411.76,
        Notes__c: "ok"
      });
      const table = child(el, "c-rfp-lane-table");
      expect(table.lanes[1].Cost__c).toBe(1200);
      expect(table.lanes[0].Cost__c).toBeUndefined();
    });

    it("resolves an end and runs history for that lane alone", async () => {
      const list = lanes(2);
      list[0].Origin_Resolved__c = false;
      list[0].Hist_Status__c = "Unresolved";
      const el = await openFromUrl(list);
      resolveLaneEnd.mockResolvedValue({
        ...pendingLane(1),
        Hist_Status__c: "Pending"
      });
      loadHistory.mockResolvedValue([
        { ...pendingLane(1), Hist_Status__c: "Done" }
      ]);
      child(el, "c-rfp-lane-table").dispatchEvent(
        new CustomEvent("resolveend", {
          detail: { laneId: "a0L1", side: "origin", key: "CA|QC|MONTREAL" }
        })
      );
      await settle(10);
      expect(resolveLaneEnd).toHaveBeenCalledWith({
        laneId: "a0L1",
        side: "origin",
        placeKey: "CA|QC|MONTREAL"
      });
      expect(loadHistory).toHaveBeenCalledTimes(1);
      expect(loadHistory.mock.calls[0][0].laneIds).toEqual(["a0L1"]);
      expect(child(el, "c-rfp-lane-table").lanes[0].Hist_Status__c).toBe(
        "Done"
      );
    });

    it("does not run history while the other end is still unresolved", async () => {
      const list = lanes(1);
      list[0].Origin_Resolved__c = false;
      list[0].Destination_Resolved__c = false;
      const el = await openFromUrl(list);
      resolveLaneEnd.mockResolvedValue({
        ...pendingLane(1),
        Destination_Resolved__c: false,
        Hist_Status__c: "Unresolved"
      });
      child(el, "c-rfp-lane-table").dispatchEvent(
        new CustomEvent("resolveend", {
          detail: { laneId: "a0L1", side: "origin", key: "CA|QC|MONTREAL" }
        })
      );
      await settle(8);
      expect(loadHistory).not.toHaveBeenCalled();
    });
  });

  describe("workbench wiring", () => {
    it("filters the table and selects only the rows shown", async () => {
      const el = await openFromUrl([
        { ...pendingLane(1), Cost__c: 100 },
        { ...pendingLane(2), Destination_City__c: "Calgary" },
        pendingLane(3)
      ]);
      field(el, "filter-status").dispatchEvent(
        new CustomEvent("change", { detail: { value: "unpriced" } })
      );
      await settle();
      let table = child(el, "c-rfp-lane-table");
      expect(table.lanes.map((l) => l.Id)).toEqual(["a0L2", "a0L3"]);
      expect(field(el, "filter-count").textContent).toContain("2 of 3");
      field(el, "filter-text").dispatchEvent(
        new CustomEvent("change", { detail: { value: "calg" } })
      );
      await settle();
      table = child(el, "c-rfp-lane-table");
      expect(table.lanes.map((l) => l.Id)).toEqual(["a0L2"]);
      table.dispatchEvent(
        new CustomEvent("selectionchange", { detail: { laneIds: ["a0L2"] } })
      );
      await settle();
      expect(child(el, "c-rfp-bulk-bar").selectedCount).toBe(1);
      expect(child(el, "c-rfp-bulk-bar").totalCount).toBe(3);
    });

    it("runs a bulk action over the chosen scope and merges the lanes back", async () => {
      applyMedian.mockResolvedValue({
        lanes: [{ ...pendingLane(1), Cost__c: 2000 }],
        updated: 1,
        skipped: 2,
        skippedIds: ["a0L2", "a0L3"],
        errors: []
      });
      const el = await openFromUrl(lanes(3));
      child(el, "c-rfp-bulk-bar").dispatchEvent(
        new CustomEvent("bulk", { detail: { action: "median", scope: "all" } })
      );
      await settle();
      expect(applyMedian).toHaveBeenCalledWith({
        laneIds: ["a0L1", "a0L2", "a0L3"],
        overwrite: false
      });
      expect(child(el, "c-rfp-lane-table").lanes[0].Cost__c).toBe(2000);
      expect(field(el, "summary").textContent).toContain(
        "Median applied to 1 lane; 2 skipped"
      );
      expect(child(el, "c-rfp-bulk-bar").lastResult.skippedIds).toEqual([
        "a0L2",
        "a0L3"
      ]);
      child(el, "c-rfp-bulk-bar").dispatchEvent(
        new CustomEvent("bulk", {
          detail: { action: "median", scope: "skipped", overwrite: true }
        })
      );
      await settle();
      expect(applyMedian).toHaveBeenLastCalledWith({
        laneIds: ["a0L2", "a0L3"],
        overwrite: true
      });
    });

    it("deletes the selection and drops the rows", async () => {
      deleteLanes.mockResolvedValue({
        lanes: [],
        updated: 2,
        skipped: 0,
        skippedIds: [],
        errors: []
      });
      const el = await openFromUrl(lanes(3));
      child(el, "c-rfp-lane-table").dispatchEvent(
        new CustomEvent("selectionchange", {
          detail: { laneIds: ["a0L1", "a0L3"] }
        })
      );
      await settle();
      child(el, "c-rfp-bulk-bar").dispatchEvent(
        new CustomEvent("bulk", {
          detail: { action: "delete", scope: "selected" }
        })
      );
      await settle();
      expect(deleteLanes).toHaveBeenCalledWith({ laneIds: ["a0L1", "a0L3"] });
      expect(child(el, "c-rfp-lane-table").lanes.map((l) => l.Id)).toEqual([
        "a0L2"
      ]);
      expect(child(el, "c-rfp-bulk-bar").selectedCount).toBe(0);
    });

    it("marks a row pending while an inline save runs and offers the twins afterwards", async () => {
      const twin = {
        ...pendingLane(2),
        Origin_Place__c: "p1",
        Destination_Place__c: "p2",
        Mode__c: "TL"
      };
      let release;
      saveLanePricing.mockImplementation(
        () =>
          new Promise((r) => {
            release = r;
          })
      );
      copyPricing.mockResolvedValue({
        lanes: [{ ...twin, Cost__c: 900 }],
        updated: 1,
        skipped: 0,
        skippedIds: [],
        errors: []
      });
      const el = await openFromUrl([
        {
          ...pendingLane(1),
          Origin_Place__c: "p1",
          Destination_Place__c: "p2",
          Mode__c: "TL"
        },
        twin
      ]);
      child(el, "c-rfp-lane-table").dispatchEvent(
        new CustomEvent("pricingchange", {
          detail: {
            laneId: "a0L1",
            Cost__c: 900,
            Cost_Source__c: "Manual",
            Selected_Bid__c: null,
            Margin__c: 15,
            Sell__c: 1035,
            Sell_Source__c: "Margin",
            Notes__c: null
          }
        })
      );
      await settle();
      expect(child(el, "c-rfp-lane-table").pendingIds).toEqual(["a0L1"]);
      release({
        ...pendingLane(1),
        Origin_Place__c: "p1",
        Destination_Place__c: "p2",
        Mode__c: "TL",
        Cost__c: 900,
        Sell__c: 1035
      });
      await settle();
      expect(child(el, "c-rfp-lane-table").pendingIds).toEqual([]);
      expect(field(el, "twin-offer").textContent).toContain("1 identical lane");
      field(el, "twin-apply").click();
      await settle();
      expect(copyPricing).toHaveBeenCalledWith({
        sourceLaneId: "a0L1",
        laneIds: ["a0L2"]
      });
      expect(field(el, "twin-offer")).toBeNull();
      expect(child(el, "c-rfp-lane-table").lanes[1].Cost__c).toBe(900);
    });

    it("will not start a bulk run while an inline save is still in flight", async () => {
      saveLanePricing.mockImplementation(() => new Promise(() => {}));
      const el = await openFromUrl(lanes(2));
      child(el, "c-rfp-lane-table").dispatchEvent(
        new CustomEvent("pricingchange", {
          detail: {
            laneId: "a0L1",
            Cost__c: 900,
            Cost_Source__c: "Manual",
            Selected_Bid__c: null,
            Margin__c: 15,
            Sell__c: 1035,
            Sell_Source__c: "Margin",
            Notes__c: null
          }
        })
      );
      await settle();
      child(el, "c-rfp-bulk-bar").dispatchEvent(
        new CustomEvent("bulk", { detail: { action: "median", scope: "all" } })
      );
      await settle();
      expect(applyMedian).not.toHaveBeenCalled();
      expect(field(el, "error").textContent).toContain(
        "Wait for the current save to finish."
      );
    });

    it("turns a panel save away while a bulk run is going and says so", async () => {
      applyMedian.mockImplementation(() => new Promise(() => {}));
      const el = await openFromUrl(lanes(2));
      child(el, "c-rfp-lane-table").dispatchEvent(
        new CustomEvent("select", { detail: { laneId: "a0L2" } })
      );
      await flush();
      child(el, "c-rfp-bulk-bar").dispatchEvent(
        new CustomEvent("bulk", { detail: { action: "median", scope: "all" } })
      );
      await settle();
      const panel = child(el, "c-rfp-lane-panel");
      expect(panel.busy).toBe(true);
      panel.dispatchEvent(
        new CustomEvent("pricingchange", {
          detail: {
            laneId: "a0L2",
            Cost__c: 900,
            Cost_Source__c: "Manual",
            Selected_Bid__c: null,
            Margin__c: 15,
            Sell__c: 1035,
            Sell_Source__c: "Margin",
            Notes__c: null
          }
        })
      );
      await settle();
      expect(saveLanePricing).not.toHaveBeenCalled();
      expect(field(el, "error").textContent).toContain(
        "Wait for the current run to finish."
      );
    });

    it("shows a bulk run that threw outside a chunk on the banner", async () => {
      const el = await openFromUrl(lanes(2));
      child(el, "c-rfp-bulk-bar").dispatchEvent(
        new CustomEvent("bulk", { detail: { action: "nope", scope: "all" } })
      );
      await settle();
      expect(field(el, "error").textContent).toContain(
        "The bulk action failed."
      );
      // The page is usable again: the run released the progress bar and Stop.
      expect(field(el, "progress")).toBeNull();
    });

    it("records a failed inline save on the row instead of the banner", async () => {
      saveLanePricing.mockRejectedValue({
        body: { message: "The lane price could not be saved. Boom" }
      });
      const el = await openFromUrl(lanes(1));
      child(el, "c-rfp-lane-table").dispatchEvent(
        new CustomEvent("pricingchange", {
          detail: {
            laneId: "a0L1",
            Cost__c: 1,
            Cost_Source__c: "Manual",
            Selected_Bid__c: null,
            Margin__c: 15,
            Sell__c: 1.15,
            Sell_Source__c: "Margin",
            Notes__c: null
          }
        })
      );
      await settle();
      expect(child(el, "c-rfp-lane-table").rowErrors.a0L1).toContain("Boom");
    });
  });

  it("adds the similar lanes to the selection without applying anything", async () => {
    similarLanes.mockResolvedValue(["a0L2", "a0L3"]);
    const el = await openFromUrl(lanes(3));
    const table = el.shadowRoot.querySelector("c-rfp-lane-table");
    table.dispatchEvent(
      new CustomEvent("selectionchange", { detail: { laneIds: ["a0L1"] } })
    );
    await settle();
    el.shadowRoot
      .querySelector("c-rfp-bulk-bar")
      .dispatchEvent(
        new CustomEvent("selectsimilar", { detail: { radiusMiles: 50 } })
      );
    await settle();
    expect(similarLanes).toHaveBeenCalledWith({
      laneId: "a0L1",
      radiusMiles: 50
    });
    const ids = el.shadowRoot.querySelector("c-rfp-lane-table").selectedIds;
    expect(ids).toEqual(expect.arrayContaining(["a0L1", "a0L2", "a0L3"]));
  });

  it("refuses to find similar lanes while another run holds the page", async () => {
    similarLanes.mockResolvedValue(["a0L2"]);
    let release;
    // A chunked bulk run in flight: busy is the page's only mutex, and clearing it under the
    // run would take the progress bar and Stop with it.
    applyMedian.mockImplementation(
      () => new Promise((resolve) => (release = resolve))
    );
    const el = await openFromUrl(lanes(3));
    el.shadowRoot
      .querySelector("c-rfp-lane-table")
      .dispatchEvent(
        new CustomEvent("selectionchange", { detail: { laneIds: ["a0L1"] } })
      );
    await settle();
    el.shadowRoot
      .querySelector("c-rfp-bulk-bar")
      .dispatchEvent(
        new CustomEvent("bulk", { detail: { scope: "all", action: "median" } })
      );
    await flush();
    el.shadowRoot
      .querySelector("c-rfp-bulk-bar")
      .dispatchEvent(
        new CustomEvent("selectsimilar", { detail: { radiusMiles: 50 } })
      );
    await settle();
    expect(similarLanes).not.toHaveBeenCalled();
    if (release) {
      release({
        lanes: [],
        updated: 0,
        skipped: 0,
        skippedIds: [],
        errors: []
      });
    }
  });

  it("reports what the similar search found in its own note", async () => {
    similarLanes.mockResolvedValue([]);
    const el = await openFromUrl(lanes(3));
    el.shadowRoot
      .querySelector("c-rfp-lane-table")
      .dispatchEvent(
        new CustomEvent("selectionchange", { detail: { laneIds: ["a0L1"] } })
      );
    await settle();
    el.shadowRoot
      .querySelector("c-rfp-bulk-bar")
      .dispatchEvent(
        new CustomEvent("selectsimilar", { detail: { radiusMiles: 50 } })
      );
    await settle();
    // a button that silently does nothing reads as broken
    expect(
      el.shadowRoot.querySelector('[data-id="similar-note"]').textContent
    ).toContain("No other lane");
    // and the note is its own, not the bulk result the Overwrite affordance reads
    expect(
      el.shadowRoot.querySelector("c-rfp-bulk-bar").lastResult
    ).not.toEqual(expect.objectContaining({ message: expect.any(String) }));
  });

  it("drops the similar note once the selection it describes has changed", async () => {
    similarLanes.mockResolvedValue(["a0L2", "a0L3"]);
    const el = await openFromUrl(lanes(3));
    const table = el.shadowRoot.querySelector("c-rfp-lane-table");
    table.dispatchEvent(
      new CustomEvent("selectionchange", { detail: { laneIds: ["a0L1"] } })
    );
    await settle();
    el.shadowRoot
      .querySelector("c-rfp-bulk-bar")
      .dispatchEvent(
        new CustomEvent("selectsimilar", { detail: { radiusMiles: 50 } })
      );
    await settle();
    expect(
      el.shadowRoot.querySelector('[data-id="similar-note"]')
    ).not.toBeNull();

    // The pricer unticks everything. The note still claims lanes are selected, and it sits
    // directly above the bulk bar's Apply - a sentence asserting a selection that is gone.
    table.dispatchEvent(
      new CustomEvent("selectionchange", { detail: { laneIds: [] } })
    );
    await settle();
    expect(el.shadowRoot.querySelector('[data-id="similar-note"]')).toBeNull();
  });

  it("announces the similar note, which grows a selection the reader cannot see", async () => {
    similarLanes.mockResolvedValue(["a0L2"]);
    const el = await openFromUrl(lanes(3));
    el.shadowRoot
      .querySelector("c-rfp-lane-table")
      .dispatchEvent(
        new CustomEvent("selectionchange", { detail: { laneIds: ["a0L1"] } })
      );
    await settle();
    el.shadowRoot
      .querySelector("c-rfp-bulk-bar")
      .dispatchEvent(
        new CustomEvent("selectsimilar", { detail: { radiusMiles: 50 } })
      );
    await settle();
    // the twin-offer banner in this same file carries role="status" for the same reason
    expect(
      el.shadowRoot
        .querySelector('[data-id="similar-note"]')
        .getAttribute("role")
    ).toBe("status");
  });
});
