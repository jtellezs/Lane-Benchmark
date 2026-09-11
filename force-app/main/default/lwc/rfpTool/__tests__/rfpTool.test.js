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
import loadHistory from "@salesforce/apex/RfpHistoryController.loadHistory";
import getBids from "@salesforce/apex/RfpBidController.getBids";

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

    it("stops the import on a failed chunk and keeps the message", async () => {
      const el = await toMapStep(450);
      importLanes
        .mockResolvedValueOnce({ imported: 200, skipped: 0, unresolvedEnds: 0 })
        .mockRejectedValueOnce({ body: { message: "row 240 is bad" } });
      child(el, "c-rfp-column-mapper").dispatchEvent(
        new CustomEvent("import", {
          detail: { mapping: { originCity: "From" } }
        })
      );
      await settle(14);
      expect(importLanes).toHaveBeenCalledTimes(2);
      expect(field(el, "error").textContent).toContain("row 240 is bad");
      expect(child(el, "c-rfp-lane-table")).toBeNull();
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
      field(el, "load-history").click();
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
      const precision = field(el, "precision");
      precision.dispatchEvent(
        new CustomEvent("change", { detail: { value: "RADIUS" } })
      );
      const lookback = field(el, "lookback");
      lookback.dispatchEvent(
        new CustomEvent("change", { detail: { value: "30" } })
      );
      await flush();
      field(el, "load-history").click();
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
      field(el, "load-history").click();
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
      field(el, "retry-failed").click();
      await settle(10);
      expect(loadHistory).toHaveBeenCalledTimes(1);
      expect(loadHistory.mock.calls[0][0].laneIds.length).toBe(10);
      expect(loadHistory.mock.calls[0][0].laneIds[0]).toBe("a0L11");
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

      field(el, "load-history").click();
      await settle(8);
      expect(loadHistory.mock.calls[0][0].laneIds).toEqual(["a0L1"]);

      loadHistory.mockClear();
      field(el, "refresh-history").click();
      await settle(8);
      expect(loadHistory.mock.calls[0][0].laneIds).toEqual(["a0L1", "a0L2"]);
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
      field(el, "load-history").click();
      await settle(12);
      expect(loadHistory).toHaveBeenCalledTimes(1);
      expect(child(el, "c-rfp-lane-table").lanes[0].Hist_Status__c).toBe(
        "Done"
      );
      expect(child(el, "c-rfp-lane-table").lanes[10].Hist_Status__c).toBe(
        "Pending"
      );
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

  it("collects the bids of lanes with a selected bid for the export", async () => {
    const list = lanes(3);
    list[0].Selected_Bid__c = "a0B1";
    list[2].Selected_Bid__c = "a0B3";
    getBids.mockResolvedValue([{ Id: "a0B1", Rate__c: 1000 }]);
    const el = await openFromUrl(list);
    await settle(8);
    expect(getBids).toHaveBeenCalledTimes(2);
    expect(getBids.mock.calls.map((c) => c[0].laneId)).toEqual([
      "a0L1",
      "a0L3"
    ]);
    expect(Object.keys(child(el, "c-rfp-export").bidsByLaneId)).toEqual([
      "a0L1",
      "a0L3"
    ]);
  });
});
