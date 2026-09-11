import { createElement } from "lwc";
import RfpLaneTable from "c/rfpLaneTable";

// c-lane-benchmark-place-picker is rendered inline for unresolved ends and it
// imports Apex, so its modules have to resolve in jsdom.
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

const flush = () => Promise.resolve().then(() => Promise.resolve());

const RESOLVED_LANE = {
  Id: "a0L00000001",
  Name: "RL-0001",
  Row_Number__c: 1,
  Origin_City__c: "Montreal",
  Origin_Province__c: "QC",
  Origin_Resolved__c: true,
  Origin_Place__c: "a0P00000001",
  Origin_Place__r: { Key__c: "montreal|qc|ca" },
  Destination_City__c: "Toronto",
  Destination_Province__c: "ON",
  Destination_Resolved__c: true,
  Destination_Place__c: "a0P00000002",
  Destination_Place__r: { Key__c: "toronto|on|ca" },
  Mode__c: "Truckload",
  Equipment_Category__c: "Dry Van",
  Hist_Count__c: 2,
  Hist_Min__c: 1800,
  Hist_Median__c: 2000,
  Hist_Average__c: 1950,
  Hist_Max__c: 2100,
  Hist_Status__c: "Done",
  Cost__c: 1900,
  Cost_Source__c: "History median",
  Margin__c: 15,
  Sell__c: 2185,
  CurrencyIsoCode: "CAD"
};

const UNRESOLVED_LANE = {
  Id: "a0L00000002",
  Name: "RL-0002",
  Row_Number__c: 2,
  Origin_City__c: "Laval",
  Origin_Province__c: "QC",
  Origin_Resolved__c: false,
  Destination_City__c: "Calgary",
  Destination_Province__c: "AB",
  Destination_Resolved__c: true,
  Destination_Place__c: "a0P00000003",
  Destination_Place__r: { Key__c: "calgary|ab|ca" },
  Mode__c: "LTL",
  Equipment_Category__c: "",
  Hist_Count__c: 0,
  Hist_Status__c: "Unresolved",
  CurrencyIsoCode: "CAD"
};

async function mount(props = {}) {
  const el = createElement("c-rfp-lane-table", { is: RfpLaneTable });
  Object.assign(
    el,
    { lanes: [RESOLVED_LANE, UNRESOLVED_LANE], currency: "CAD" },
    props
  );
  document.body.appendChild(el);
  await flush();
  return el;
}

const rowsOf = (el) => el.shadowRoot.querySelectorAll('[data-id="lane-row"]');

describe("c-rfp-lane-table", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("renders one row per lane with places, history and pricing text", async () => {
    const el = await mount();
    const rows = rowsOf(el);
    expect(rows.length).toBe(2);
    expect(rows[0].dataset.laneId).toBe("a0L00000001");

    const first = rows[0].textContent;
    expect(first).toContain("Montreal");
    expect(first).toContain("Toronto");
    expect(first).toContain("Truckload");

    const hist = rows[0].querySelector('[data-id="hist"]');
    expect(hist.textContent.trim()).toBe("2 · median 2000.00");
    expect(hist.title).toContain("1800.00");
    expect(hist.title).toContain("1950.00");
    expect(hist.title).toContain("2100.00");

    expect(rows[0].querySelector('[data-id="cost"]').textContent.trim()).toBe(
      "1900.00"
    );
    expect(rows[0].querySelector('[data-id="margin"]').textContent.trim()).toBe(
      "15"
    );
    expect(rows[0].querySelector('[data-id="sell"]').textContent.trim()).toBe(
      "2185.00"
    );
    expect(rows[0].querySelector('[data-id="status"]').textContent.trim()).toBe(
      "Priced"
    );

    const secondHist = rows[1].querySelector('[data-id="hist"]');
    expect(secondHist.textContent.trim()).toBe("Unresolved");
    expect(rows[1].querySelector('[data-id="status"]').textContent.trim()).toBe(
      ""
    );
  });

  it("shows a place picker only for unresolved ends", async () => {
    const el = await mount();
    const rows = rowsOf(el);
    expect(
      rows[0].querySelectorAll("c-lane-benchmark-place-picker").length
    ).toBe(0);
    const pickers = rows[1].querySelectorAll("c-lane-benchmark-place-picker");
    expect(pickers.length).toBe(1);
    expect(pickers[0].dataset.side).toBe("origin");
    expect(pickers[0].dataset.laneId).toBe("a0L00000002");
  });

  it("keeps the unresolved city on screen next to its picker", async () => {
    const el = await mount();
    const row = rowsOf(el)[1];
    expect(row.querySelector('[data-id="origin"]').textContent).toContain(
      "Laval"
    );
    expect(row.querySelector("c-lane-benchmark-place-picker")).not.toBeNull();
    // the resolved destination keeps its text and gets no picker
    expect(row.querySelector('[data-id="destination"]').textContent).toContain(
      "Calgary"
    );
  });

  it("says so when a Done snapshot found loads but no median", async () => {
    const el = await mount({
      lanes: [
        {
          ...RESOLVED_LANE,
          Hist_Count__c: 3,
          Hist_Median__c: null
        }
      ]
    });
    expect(
      rowsOf(el)[0].querySelector('[data-id="hist"]').textContent.trim()
    ).toBe("3 · no median");
  });

  it("selects a row from the keyboard without stealing the picker's keys", async () => {
    const el = await mount();
    const handler = jest.fn();
    el.addEventListener("select", handler);
    const row = rowsOf(el)[1];
    expect(row.getAttribute("tabindex")).toBe("0");

    row.dispatchEvent(
      new KeyboardEvent("keydown", { key: "Enter", cancelable: true })
    );
    expect(handler).toHaveBeenCalledTimes(1);
    expect(handler.mock.calls[0][0].detail).toEqual({
      laneId: "a0L00000002"
    });

    row.dispatchEvent(
      new KeyboardEvent("keydown", { key: " ", cancelable: true })
    );
    expect(handler).toHaveBeenCalledTimes(2);

    row.dispatchEvent(
      new KeyboardEvent("keydown", { key: "a", cancelable: true })
    );
    expect(handler).toHaveBeenCalledTimes(2);

    // a key pressed inside the inline picker must not select the row
    row
      .querySelector("c-lane-benchmark-place-picker")
      .dispatchEvent(
        new KeyboardEvent("keydown", { key: "Enter", bubbles: true })
      );
    expect(handler).toHaveBeenCalledTimes(2);
  });

  it("marks the selected row for assistive technology", async () => {
    const el = await mount({ selectedId: "a0L00000002" });
    const rows = rowsOf(el);
    expect(rows[0].getAttribute("aria-selected")).toBe("false");
    expect(rows[1].getAttribute("aria-selected")).toBe("true");
  });

  it("emits select with the lane id when a row is clicked", async () => {
    const el = await mount();
    const handler = jest.fn();
    el.addEventListener("select", handler);
    rowsOf(el)[1].click();
    expect(handler).toHaveBeenCalledTimes(1);
    expect(handler.mock.calls[0][0].detail).toEqual({
      laneId: "a0L00000002"
    });
  });

  it("emits resolveend when the picker reports a key and stays quiet without one", async () => {
    const el = await mount();
    const handler = jest.fn();
    el.addEventListener("resolveend", handler);
    const picker = rowsOf(el)[1].querySelector("c-lane-benchmark-place-picker");

    picker.dispatchEvent(
      new CustomEvent("placechange", {
        detail: { key: null, label: "", precision: "CITY" }
      })
    );
    expect(handler).not.toHaveBeenCalled();

    picker.dispatchEvent(
      new CustomEvent("placechange", {
        detail: { key: "laval|qc|ca", label: "Laval, QC, CA" }
      })
    );
    expect(handler).toHaveBeenCalledTimes(1);
    expect(handler.mock.calls[0][0].detail).toEqual({
      laneId: "a0L00000002",
      side: "origin",
      key: "laval|qc|ca"
    });
  });
});
