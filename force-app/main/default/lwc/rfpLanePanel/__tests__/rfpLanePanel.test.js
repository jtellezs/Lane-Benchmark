import { createElement } from "lwc";
import RfpLanePanel from "c/rfpLanePanel";
import getBids from "@salesforce/apex/RfpBidController.getBids";
import saveBid from "@salesforce/apex/RfpBidController.saveBid";
import search from "@salesforce/apex/LaneBenchmarkController.search";

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
// c-rfp-bid-form pulls in c-rfp-account-picker, which imports Apex.
jest.mock(
  "@salesforce/apex/RfpProjectController.searchAccounts",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const flush = () => Promise.resolve().then(() => Promise.resolve());

const LANE = {
  Id: "a0L00000001",
  Name: "RL-0001",
  Row_Number__c: 1,
  Origin_City__c: "Montreal",
  Origin_Province__c: "QC",
  Origin_Resolved__c: true,
  Origin_Place__r: { Key__c: "montreal|qc|ca" },
  Destination_City__c: "Toronto",
  Destination_Province__c: "ON",
  Destination_Resolved__c: true,
  Destination_Place__r: { Key__c: "toronto|on|ca" },
  Mode__c: "Truckload",
  Hist_Count__c: 4,
  Hist_Median__c: 2000,
  Hist_Precision__c: "CITY",
  Hist_Status__c: "Done",
  Cost__c: 1500,
  Cost_Source__c: "Manual",
  Notes__c: "Watch the ferry surcharge",
  CurrencyIsoCode: "CAD"
};

const HISTORY = {
  rows: [
    {
      quoteId: "0Q1",
      quoteName: "Q-1",
      origin: "Montreal, QC",
      destination: "Toronto, ON",
      carrierName: "Acme Transport",
      currencyIsoCode: "CAD",
      carrierTotal: 1950,
      quoteDate: "2026-08-01"
    }
  ],
  statsByCurrency: {},
  truncated: false
};

const CHEAP_BID = {
  Id: "a0B00000001",
  Name: "BR-1",
  Carrier__c: "001Acme",
  Carrier_Display__c: "Acme Transport",
  Rate__c: 1800,
  CurrencyIsoCode: "CAD",
  Status__c: "Active",
  Expires_On__c: "2026-12-31"
};

const field = (el, id) => el.shadowRoot.querySelector(`[data-id="${id}"]`);

function change(el, id, detail) {
  const node = field(el, id);
  Object.assign(node, detail);
  node.dispatchEvent(new CustomEvent("change", { detail }));
}

async function mount(props = {}) {
  const el = createElement("c-rfp-lane-panel", { is: RfpLanePanel });
  // Spread, not a second Object.assign source: the lane setter only reacts to a
  // new Id, so assigning `lane` twice would drop the override.
  Object.assign(el, { lane: LANE, project: { Id: "a0R1" }, ...props });
  document.body.appendChild(el);
  await flush();
  await flush();
  return el;
}

describe("c-rfp-lane-panel", () => {
  beforeEach(() => {
    getBids.mockResolvedValue([]);
    saveBid.mockResolvedValue({ Id: "a0B00000009" });
    search.mockResolvedValue(HISTORY);
  });
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("loads the bids and the history rows for a resolved lane", async () => {
    const el = await mount();
    expect(getBids).toHaveBeenCalledWith({ laneId: "a0L00000001" });
    expect(search).toHaveBeenCalledTimes(1);
    const request = JSON.parse(search.mock.calls[0][0].requestJson);
    expect(request).toMatchObject({
      originKey: "montreal|qc|ca",
      destinationKey: "toronto|on|ca",
      originPrecision: "CITY",
      destinationPrecision: "CITY",
      originRadius: null,
      destinationRadius: null,
      radiusUnit: "KM",
      lookbackDays: 90,
      sourceFilter: "LOADS",
      rowLimit: 500,
      includeStopGeolocation: true
    });
    const results = el.shadowRoot.querySelector("c-lane-benchmark-results");
    expect(results.rows.length).toBe(1);
    expect(results.rows[0].quoteId).toBe("0Q1");
  });

  it("wraps the history results in a horizontal scroller", async () => {
    const el = await mount();
    // The panel column is narrower than the results table; without the wrapper
    // the table renders one character per line.
    const scroller = field(el, "history-scroll");
    expect(scroller).not.toBeNull();
    expect(scroller.querySelector("c-lane-benchmark-results")).not.toBeNull();
  });

  it("asks for a 50 km radius on both ends when the lane fell back to RADIUS-50KM", async () => {
    await mount({
      lane: {
        ...LANE,
        Hist_Precision__c: "RADIUS-50KM",
        Hist_Lookback_Days__c: 180
      }
    });
    const request = JSON.parse(search.mock.calls[0][0].requestJson);
    expect(request.originPrecision).toBe("RADIUS");
    expect(request.destinationPrecision).toBe("RADIUS");
    expect(request.originRadius).toBe(50);
    expect(request.destinationRadius).toBe(50);
    expect(request.lookbackDays).toBe(180);
  });

  it("skips the history search when an end is not resolved to a place", async () => {
    await mount({ lane: { ...LANE, Destination_Place__r: undefined } });
    expect(getBids).toHaveBeenCalledTimes(1);
    expect(search).not.toHaveBeenCalled();
  });

  it("takes the cost from the history median and emits the priced lane", async () => {
    const el = await mount();
    const handler = jest.fn();
    el.addEventListener("pricingchange", handler);

    change(el, "cost-source", { value: "History median" });
    await flush();
    expect(field(el, "cost").value).toBe(2000);

    change(el, "margin", { value: "15" });
    await flush();
    expect(field(el, "sell").value).toBe(2300);

    field(el, "save-price").click();
    expect(handler).toHaveBeenCalledTimes(1);
    expect(handler.mock.calls[0][0].detail).toEqual({
      laneId: "a0L00000001",
      Cost__c: 2000,
      Cost_Source__c: "History median",
      Selected_Bid__c: null,
      Margin__c: 15,
      Sell__c: 2300,
      Sell_Source__c: "Margin",
      Notes__c: "Watch the ferry surcharge"
    });
  });

  it("selects a bid as the cost and carries its id on the payload", async () => {
    getBids.mockResolvedValue([CHEAP_BID]);
    const el = await mount();
    const handler = jest.fn();
    el.addEventListener("pricingchange", handler);

    change(el, "cost-source", { value: "Bid" });
    await flush();
    change(el, "bid-select", { value: "a0B00000001" });
    await flush();
    expect(field(el, "cost").value).toBe(1800);

    field(el, "save-price").click();
    expect(handler.mock.calls[0][0].detail).toMatchObject({
      Cost__c: 1800,
      Cost_Source__c: "Bid",
      Selected_Bid__c: "a0B00000001"
    });
  });

  it("will not save while the container reports a run in flight", async () => {
    // The lane carries a manual cost, so `busy` is the only reason Save is off.
    const el = await mount({ busy: true });
    expect(field(el, "save-price").disabled).toBe(true);
    el.busy = false;
    await flush();
    expect(field(el, "save-price").disabled).toBe(false);
  });

  it("will not save a Bid cost while no bid is picked", async () => {
    const el = await mount();
    change(el, "cost-source", { value: "Bid" });
    await flush();
    expect(field(el, "save-price").disabled).toBe(true);
    change(el, "cost-source", { value: "Manual" });
    await flush();
    expect(field(el, "save-price").disabled).toBe(false);
  });

  it("will not save a cost the bids have not produced yet", async () => {
    // the lane already points at a bid, but getBids came back empty (or failed),
    // so there is no rate behind "Bid" and saving would null out the stored cost
    getBids.mockResolvedValue([]);
    const el = await mount({
      lane: {
        ...LANE,
        Cost_Source__c: "Bid",
        Selected_Bid__c: "a0B00000001",
        Cost__c: 1800
      }
    });
    const handler = jest.fn();
    el.addEventListener("pricingchange", handler);

    expect(field(el, "cost").value).toBeNull();
    expect(field(el, "save-price").disabled).toBe(true);
    field(el, "save-price").click();
    expect(handler).not.toHaveBeenCalled();
  });

  it("will not save an empty manual cost either", async () => {
    const el = await mount({ lane: { ...LANE, Cost__c: null } });
    const handler = jest.fn();
    el.addEventListener("pricingchange", handler);
    expect(field(el, "save-price").disabled).toBe(true);
    field(el, "save-price").click();
    expect(handler).not.toHaveBeenCalled();
  });

  it("drops the previous lane's bids and history when the lane changes", async () => {
    getBids.mockResolvedValue([CHEAP_BID]);
    const el = await mount();
    expect(el.shadowRoot.querySelectorAll('[data-id="bid-row"]').length).toBe(
      1
    );
    expect(
      el.shadowRoot.querySelector("c-lane-benchmark-results").rows.length
    ).toBe(1);

    // the next lane's loads never resolve during this tick, so anything on
    // screen right after the switch would be the old lane's
    let releaseBids;
    getBids.mockReturnValue(
      new Promise((resolve) => {
        releaseBids = resolve;
      })
    );
    search.mockReturnValue(new Promise(() => {}));
    el.lane = { ...LANE, Id: "a0L00000002", Name: "RL-0002" };
    await flush();

    expect(el.shadowRoot.querySelectorAll('[data-id="bid-row"]').length).toBe(
      0
    );
    expect(
      el.shadowRoot.querySelector("c-lane-benchmark-results").rows.length
    ).toBe(0);
    releaseBids([]);
  });

  it("drops a response that lands after the panel moved to another lane", async () => {
    let releaseSearch;
    search.mockReturnValueOnce(
      new Promise((resolve) => {
        releaseSearch = resolve;
      })
    );
    const el = await mount();

    // the next lane has an unresolved end, so it runs no search of its own
    el.lane = { ...LANE, Id: "a0L00000002", Destination_Place__r: undefined };
    await flush();

    releaseSearch(HISTORY);
    await flush();
    await flush();
    expect(
      el.shadowRoot.querySelector("c-lane-benchmark-results").rows.length
    ).toBe(0);
  });

  it("hints at a cheaper active bid only when it beats the current cost", async () => {
    getBids.mockResolvedValue([CHEAP_BID]);
    const el = await mount();
    expect(field(el, "best-bid-hint")).toBeNull();

    change(el, "cost-source", { value: "History median" });
    await flush();
    const hint = field(el, "best-bid-hint");
    expect(hint).not.toBeNull();
    expect(hint.textContent).toContain("1800.00");
    expect(hint.textContent).toContain("Acme Transport");
  });

  it("warns about bids that are in another currency", async () => {
    getBids.mockResolvedValue([
      CHEAP_BID,
      { ...CHEAP_BID, Id: "a0B00000002", CurrencyIsoCode: "USD" }
    ]);
    const el = await mount();
    expect(field(el, "other-currency").textContent).toContain("1 bid");
  });

  it("saves a bid from the form, refreshes and reports it", async () => {
    const el = await mount();
    const handler = jest.fn();
    el.addEventListener("bidsaved", handler);

    field(el, "add-bid").click();
    await flush();
    const form = el.shadowRoot.querySelector("c-rfp-bid-form");
    expect(form).not.toBeNull();
    expect(form.laneId).toBe("a0L00000001");

    const bid = {
      RFP_Lane__c: "a0L00000001",
      Carrier__c: null,
      Carrier_Name__c: "Speedy Lines",
      Rate__c: 1700,
      CurrencyIsoCode: "CAD"
    };
    getBids.mockResolvedValue([CHEAP_BID]);
    form.dispatchEvent(new CustomEvent("save", { detail: { bid } }));
    await flush();
    await flush();

    expect(saveBid).toHaveBeenCalledWith({ bidJson: JSON.stringify(bid) });
    expect(getBids).toHaveBeenCalledTimes(2);
    expect(handler).toHaveBeenCalledTimes(1);
    expect(handler.mock.calls[0][0].detail).toEqual({
      laneId: "a0L00000001"
    });
    expect(el.shadowRoot.querySelector("c-rfp-bid-form")).toBeNull();
  });

  it("opens the form on an existing bid when its row is clicked", async () => {
    getBids.mockResolvedValue([CHEAP_BID]);
    const el = await mount();
    field(el, "bid-row").click();
    await flush();
    const form = el.shadowRoot.querySelector("c-rfp-bid-form");
    expect(form).not.toBeNull();
    expect(form.bid).toEqual(CHEAP_BID);
    expect(form.laneId).toBe("a0L00000001");

    // switching to Add clears the edited bid out of the same form
    field(el, "add-bid").click();
    await flush();
    expect(el.shadowRoot.querySelector("c-rfp-bid-form").bid).toBeNull();
  });

  it("does not report a saved bid when the refresh fails", async () => {
    const el = await mount();
    const handler = jest.fn();
    el.addEventListener("bidsaved", handler);
    field(el, "add-bid").click();
    await flush();

    getBids.mockRejectedValue({
      body: { message: "The bids could not be loaded." }
    });
    el.shadowRoot
      .querySelector("c-rfp-bid-form")
      .dispatchEvent(new CustomEvent("save", { detail: { bid: {} } }));
    await flush();
    await flush();

    expect(saveBid).toHaveBeenCalledTimes(1);
    expect(handler).not.toHaveBeenCalled();
    expect(field(el, "panel-error").textContent).toContain(
      "could not be loaded"
    );
  });

  it("shows the Apex message when a bid cannot be saved", async () => {
    saveBid.mockRejectedValue({ body: { message: "A bid needs a rate." } });
    const el = await mount();
    field(el, "add-bid").click();
    await flush();
    el.shadowRoot
      .querySelector("c-rfp-bid-form")
      .dispatchEvent(new CustomEvent("save", { detail: { bid: {} } }));
    await flush();
    await flush();
    expect(field(el, "panel-error").textContent).toContain(
      "A bid needs a rate."
    );
  });

  describe("linked sell and margin", () => {
    it("typing a sell flips the lane to Manual and shows the derived margin", async () => {
      const el = await mount();
      field(el, "margin").dispatchEvent(
        new CustomEvent("change", { detail: { value: "20" } })
      );
      await flush();
      expect(field(el, "sell").value).toBe(1800);
      expect(field(el, "sell-mode").textContent).toContain(
        "Sell follows the margin"
      );
      field(el, "sell").dispatchEvent(
        new CustomEvent("change", { detail: { value: "2250" } })
      );
      await flush();
      expect(field(el, "margin").value).toBe("50");
      expect(field(el, "sell-mode").textContent).toContain(
        "Margin follows the sell"
      );
      const spy = jest.fn();
      el.addEventListener("pricingchange", spy);
      field(el, "save-price").click();
      expect(spy.mock.calls[0][0].detail).toMatchObject({
        Cost__c: 1500,
        Sell__c: 2250,
        Margin__c: 50,
        Sell_Source__c: "Manual"
      });
    });

    it("a cost change keeps a manual sell and re-derives the margin", async () => {
      const el = await mount();
      field(el, "sell").dispatchEvent(
        new CustomEvent("change", { detail: { value: "2000" } })
      );
      field(el, "cost").dispatchEvent(
        new CustomEvent("change", { detail: { value: "1000" } })
      );
      await flush();
      // sellValue in Manual mode returns the typed text as-is (the lightning-input
      // stub does not coerce it to a number), unlike Margin mode where it is
      // pricing.Sell__c, a computed number.
      expect(field(el, "sell").value).toBe("2000");
      expect(field(el, "margin").value).toBe("100");
    });

    it("cannot save a manual sell that is blank", async () => {
      const el = await mount();
      field(el, "sell").dispatchEvent(
        new CustomEvent("change", { detail: { value: "" } })
      );
      await flush();
      expect(field(el, "save-price").disabled).toBe(true);
    });

    it("re-syncs when the same lane comes back with different pricing", async () => {
      const el = await mount();
      el.lane = {
        ...LANE,
        Cost__c: 1700,
        Margin__c: 10,
        Sell__c: 1870,
        Sell_Source__c: "Margin"
      };
      await flush();
      expect(field(el, "cost").value).toBe("1700");
      expect(field(el, "margin").value).toBe("10");
      expect(field(el, "sell").value).toBe(1870);
    });
  });
});
