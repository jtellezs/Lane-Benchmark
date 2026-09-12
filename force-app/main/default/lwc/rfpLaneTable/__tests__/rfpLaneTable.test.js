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
const cellOf = (row, field) => row.querySelector(`[data-id="${field}"]`);
const inputIn = (el) => el.shadowRoot.querySelector('[data-id="cell-input"]');
const key = (target, k, extra = {}) =>
  target.dispatchEvent(
    new KeyboardEvent("keydown", {
      key: k,
      bubbles: true,
      cancelable: true,
      ...extra
    })
  );

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

  it("splits the history count into loads and bids once bids were counted", async () => {
    const el = await mount({
      lanes: [
        { ...RESOLVED_LANE, Hist_Count__c: 15, Hist_Bid_Count__c: 3 },
        {
          ...RESOLVED_LANE,
          Id: "a0L00000009",
          Hist_Count__c: 2,
          Hist_Bid_Count__c: 1,
          Hist_Median__c: null
        }
      ]
    });
    const rows = rowsOf(el);
    expect(rows[0].querySelector('[data-id="hist"]').textContent.trim()).toBe(
      "12 loads + 3 bids · median 2000.00"
    );
    // One of each reads in the singular, and a Done lane with no median in its
    // own currency still says where the rows came from.
    expect(rows[1].querySelector('[data-id="hist"]').textContent.trim()).toBe(
      "1 load + 1 bid · no median"
    );
  });

  it("keeps the bare count when the run found no bids", async () => {
    const el = await mount({
      lanes: [
        { ...RESOLVED_LANE, Hist_Count__c: 2, Hist_Bid_Count__c: 0 },
        { ...RESOLVED_LANE, Id: "a0L00000008", Hist_Count__c: 2 }
      ]
    });
    const rows = rowsOf(el);
    expect(rows[0].querySelector('[data-id="hist"]').textContent.trim()).toBe(
      "2 · median 2000.00"
    );
    expect(rows[1].querySelector('[data-id="hist"]').textContent.trim()).toBe(
      "2 · median 2000.00"
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

  it("does not select the row when the click lands in the inline picker", async () => {
    const el = await mount();
    const handler = jest.fn();
    el.addEventListener("select", handler);
    const row = rowsOf(el)[1];

    // Selecting the row here would re-render the panel, shrink the page and
    // scroll the option list the user is still clicking in off the screen.
    row
      .querySelector("c-lane-benchmark-place-picker")
      .dispatchEvent(new MouseEvent("click", { bubbles: true }));
    expect(handler).not.toHaveBeenCalled();

    // the rest of the row still selects it
    row.click();
    expect(handler).toHaveBeenCalledTimes(1);
    expect(handler.mock.calls[0][0].detail).toEqual({
      laneId: "a0L00000002"
    });
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

  describe("selection", () => {
    it("emits the whole selection on a row checkbox and on the header checkbox", async () => {
      const el = await mount({ selectedIds: ["a0L00000002"] });
      const spy = jest.fn();
      el.addEventListener("selectionchange", spy);
      const select = jest.fn();
      el.addEventListener("select", select);
      const checks = el.shadowRoot.querySelectorAll('[data-id="row-check"]');
      expect(checks[1].checked).toBe(true);
      checks[0].click();
      expect(spy.mock.calls[0][0].detail.laneIds).toEqual([
        "a0L00000002",
        "a0L00000001"
      ]);
      expect(select).not.toHaveBeenCalled();
      el.shadowRoot.querySelector('[data-id="check-all"]').click();
      expect(spy.mock.calls[1][0].detail.laneIds).toEqual([
        "a0L00000002",
        "a0L00000001"
      ]);
      el.selectedIds = ["a0L00000001", "a0L00000002"];
      await flush();
      expect(el.shadowRoot.querySelector('[data-id="check-all"]').checked).toBe(
        true
      );
      el.shadowRoot.querySelector('[data-id="check-all"]').click();
      expect(spy.mock.calls[2][0].detail.laneIds).toEqual([]);
    });
  });

  describe("inline editing", () => {
    it("opens one cell on click, saves on Enter and moves down the column", async () => {
      const el = await mount({ defaultMargin: 15 });
      const spy = jest.fn();
      el.addEventListener("pricingchange", spy);
      const select = jest.fn();
      el.addEventListener("select", select);
      cellOf(rowsOf(el)[0], "margin").click();
      await flush();
      // one select, from the cell itself — the row handler must not add a second
      expect(select).toHaveBeenCalledTimes(1);
      expect(select.mock.calls[0][0].detail).toEqual({ laneId: "a0L00000001" });
      const input = inputIn(el);
      expect(input).not.toBeNull();
      expect(input.value).toBe("15");
      expect(
        el.shadowRoot.querySelectorAll('[data-id="cell-input"]').length
      ).toBe(1);
      input.dispatchEvent(
        new CustomEvent("change", { detail: { value: "20" } })
      );
      key(input, "Enter");
      await flush();
      expect(spy).toHaveBeenCalledTimes(1);
      expect(spy.mock.calls[0][0].detail).toMatchObject({
        laneId: "a0L00000001",
        Margin__c: 20,
        Sell__c: 2280,
        Sell_Source__c: "Margin"
      });
      const next = inputIn(el);
      expect(next).not.toBeNull();
      expect(rowsOf(el)[1].contains(next)).toBe(true);
      // the panel follows the cell down the column
      expect(select).toHaveBeenCalledTimes(2);
      expect(select.mock.calls[1][0].detail).toEqual({ laneId: "a0L00000002" });
    });

    it("does not re-select the lane when its own cell is opened again", async () => {
      const el = await mount({ defaultMargin: 15, selectedId: "a0L00000001" });
      const select = jest.fn();
      el.addEventListener("select", select);
      cellOf(rowsOf(el)[0], "margin").click();
      await flush();
      expect(inputIn(el)).not.toBeNull();
      expect(select).not.toHaveBeenCalled();
    });

    it("Tab saves and moves down; Escape cancels without saving", async () => {
      const el = await mount({ defaultMargin: 15 });
      const spy = jest.fn();
      el.addEventListener("pricingchange", spy);
      cellOf(rowsOf(el)[0], "sell").click();
      await flush();
      inputIn(el).dispatchEvent(
        new CustomEvent("change", { detail: { value: "2500" } })
      );
      key(inputIn(el), "Tab");
      await flush();
      expect(spy.mock.calls[0][0].detail).toMatchObject({
        Sell__c: 2500,
        Sell_Source__c: "Manual",
        Margin__c: 31.58
      });
      key(inputIn(el), "Escape");
      await flush();
      expect(inputIn(el)).toBeNull();
      expect(spy).toHaveBeenCalledTimes(1);
    });

    it("keeps an invalid value open with an error, and an unchanged value just closes", async () => {
      const el = await mount({ defaultMargin: 15 });
      const spy = jest.fn();
      el.addEventListener("pricingchange", spy);
      cellOf(rowsOf(el)[0], "cost").click();
      await flush();
      inputIn(el).dispatchEvent(
        new CustomEvent("change", { detail: { value: "-5" } })
      );
      key(inputIn(el), "Enter");
      await flush();
      expect(inputIn(el)).not.toBeNull();
      expect(
        el.shadowRoot.querySelector('[data-id="cell-error"]').textContent
      ).toContain("above zero");
      expect(spy).not.toHaveBeenCalled();
      inputIn(el).dispatchEvent(
        new CustomEvent("change", { detail: { value: "1900" } })
      );
      key(inputIn(el), "Enter");
      await flush();
      expect(spy).not.toHaveBeenCalled();
    });

    it("Enter on a focused cell opens it, blur commits, and a locked table ignores clicks", async () => {
      const el = await mount({ defaultMargin: 15 });
      const spy = jest.fn();
      el.addEventListener("pricingchange", spy);
      const select = jest.fn();
      el.addEventListener("select", select);
      const cell = cellOf(rowsOf(el)[1], "cost");
      key(cell, "Enter");
      await flush();
      expect(inputIn(el)).not.toBeNull();
      // the keyboard path selects the lane too, so the panel follows it
      expect(select).toHaveBeenCalledTimes(1);
      expect(select.mock.calls[0][0].detail).toEqual({ laneId: "a0L00000002" });
      inputIn(el).dispatchEvent(
        new CustomEvent("change", { detail: { value: "800" } })
      );
      inputIn(el).dispatchEvent(new CustomEvent("blur"));
      await flush();
      expect(spy.mock.calls[0][0].detail).toMatchObject({
        laneId: "a0L00000002",
        Cost__c: 800,
        Cost_Source__c: "Manual",
        Margin__c: 15,
        Sell__c: 920
      });
      expect(inputIn(el)).toBeNull();
      el.locked = true;
      await flush();
      cellOf(rowsOf(el)[0], "cost").click();
      await flush();
      expect(inputIn(el)).toBeNull();
      // locking stops the typing, not the navigating
      expect(select).toHaveBeenCalledTimes(2);
      expect(select.mock.calls[1][0].detail).toEqual({ laneId: "a0L00000001" });
    });

    it("sends focus back to the cell when Escape closes it", async () => {
      const el = await mount({ defaultMargin: 15 });
      const cell = cellOf(rowsOf(el)[0], "margin");
      const focus = jest.spyOn(cell, "focus");
      cell.click();
      await flush();
      key(inputIn(el), "Escape");
      await flush();
      expect(inputIn(el)).toBeNull();
      expect(focus).toHaveBeenCalled();
      expect(el.shadowRoot.activeElement).toBe(cell);
    });

    it("ignores the blur left behind by a cell that already moved on", async () => {
      const el = await mount({ defaultMargin: 15 });
      const spy = jest.fn();
      el.addEventListener("pricingchange", spy);
      cellOf(rowsOf(el)[0], "margin").click();
      await flush();
      const first = inputIn(el);
      first.dispatchEvent(
        new CustomEvent("change", { detail: { value: "20" } })
      );
      key(first, "Enter");
      await flush();
      expect(spy).toHaveBeenCalledTimes(1);
      // the input that moved on still gets a blur; it must not save twice
      first.dispatchEvent(new CustomEvent("blur"));
      await flush();
      expect(spy).toHaveBeenCalledTimes(1);
    });

    it("drops an unusable value on blur instead of trapping the cursor", async () => {
      const el = await mount({ defaultMargin: 15 });
      const spy = jest.fn();
      el.addEventListener("pricingchange", spy);
      cellOf(rowsOf(el)[0], "cost").click();
      await flush();
      inputIn(el).dispatchEvent(
        new CustomEvent("change", { detail: { value: "abc" } })
      );
      inputIn(el).dispatchEvent(new CustomEvent("blur"));
      await flush();
      expect(spy).not.toHaveBeenCalled();
      expect(inputIn(el)).toBeNull();
    });

    it("survives a lane that leaves the table while its cell is open", async () => {
      const el = await mount({ defaultMargin: 15 });
      const spy = jest.fn();
      el.addEventListener("pricingchange", spy);
      cellOf(rowsOf(el)[0], "margin").click();
      await flush();
      const input = inputIn(el);
      input.dispatchEvent(
        new CustomEvent("change", { detail: { value: "20" } })
      );
      // a filter change drops the lane the open cell belongs to
      el.lanes = [UNRESOLVED_LANE];
      await flush();
      key(input, "Enter");
      await flush();
      expect(spy).not.toHaveBeenCalled();
      expect(inputIn(el)).toBeNull();
    });

    it("marks pending rows, errors, negative margins and manual sells", async () => {
      const el = await mount({
        lanes: [
          { ...RESOLVED_LANE, Margin__c: -5, Sell_Source__c: "Manual" },
          UNRESOLVED_LANE
        ],
        pendingIds: ["a0L00000001"],
        rowErrors: { a0L00000002: "The lane price could not be saved." }
      });
      const rows = rowsOf(el);
      expect(rows[0].querySelector('[data-id="row-pending"]')).not.toBeNull();
      expect(rows[1].querySelector('[data-id="row-error"]').title).toContain(
        "could not be saved"
      );
      expect(
        cellOf(rows[0], "margin").classList.contains("slds-text-color_error")
      ).toBe(true);
      expect(
        rows[0].querySelector('[data-id="manual-tag"]').textContent.trim()
      ).toBe("manual");
    });
  });
});
