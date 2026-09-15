import { createElement } from "lwc";
import { subscribe, unsubscribe } from "lightning/messageService";
import DISTANCE_UNIT from "@salesforce/messageChannel/Distance_Unit__c";
import RfpLanePanel from "c/rfpLanePanel";
import getBids from "@salesforce/apex/RfpBidController.getBids";
import saveBid from "@salesforce/apex/RfpBidController.saveBid";
import search from "@salesforce/apex/LaneBenchmarkController.search";
import laneRoute from "@salesforce/apex/RfpLaneController.laneRoute";
import splitOptions from "@salesforce/apex/SplitLaneController.splitOptions";
import findCarrierLeads from "@salesforce/apex/CarrierLeadController.findCarrierLeads";
import { writeUnit } from "c/distanceUnit";

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
  "@salesforce/apex/RfpLaneController.laneRoute",
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
  RFP_Project__c: "a0R00000001",
  Hist_Count__c: 4,
  Hist_Bid_Count__c: 1,
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

/** LANE as laneRoute re-reads it after writing the truck route's miles. */
const ROUTED_LANE = {
  ...LANE,
  Miles__c: 1234,
  Miles_Source__c: "Truck route",
  Route_Hours__c: 21.5
};

/** A TripRouteView as RfpLaneController.laneRoute returns it (polyline5 is not @AuraEnabled). */
const ROUTE_VIEW = {
  status: "Found",
  routeType: "Truck",
  miles: 1234,
  hours: 21.5,
  routes: [
    { miles: 1234, hours: 21.5 },
    { miles: 1260.2, hours: 22.1 }
  ],
  mapUrl:
    "https://api.mapbox.com/styles/v1/mapbox/streets-v12/static/pin-s-a+0070d2(-73.5674,45.5019)/auto/600x300@2x?padding=40&access_token=pk.test",
  message: null,
  lane: ROUTED_LANE
};

/** What Lightning Message Service does on a publish: every subscriber hears it. */
const publishUnit = (unit) =>
  subscribe.mock.calls
    .filter((call) => call[1] === DISTANCE_UNIT)
    .forEach((call) => call[2]({ unit }));

const field = (el, id) => el.shadowRoot.querySelector(`[data-id="${id}"]`);
const textOf = (el, id) => field(el, id).textContent.trim();

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
    // No stored route unless a test says so: the earlier tests are about pricing.
    laneRoute.mockResolvedValue(null);
    findCarrierLeads.mockResolvedValue({
      leads: [],
      stage: "None",
      stateLaneLabel: null,
      truncated: false
    });
  });
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    // readUnit() reads the real jsdom localStorage: a km test must not leak.
    window.localStorage.clear();
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
      // The lane's own run counted bids (Hist_Bid_Count__c 1), so the panel's
      // second search repeats it: every project but this one, expired kept.
      sourceFilter: "ALL",
      includeExpiredBids: true,
      excludeProjectId: "a0R00000001",
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

  it("keeps the help hint out of the lane heading's name", async () => {
    const el = await mount();
    const heading = el.shadowRoot.querySelector("h2");
    expect(heading.textContent.trim()).toBe("Montreal, QC → Toronto, ON");
    // The hint's button carries assistive text, so a hint inside the h2 is
    // read out as part of the heading's name.
    expect(heading.querySelector("c-help-hint")).toBeNull();
    const hints = [...el.shadowRoot.querySelectorAll("c-help-hint")].filter(
      (h) => h.topic === "rfp-pricing"
    );
    expect(hints.length).toBe(1);
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

  describe("trip miles and route", () => {
    const map = (el) => el.shadowRoot.querySelector("c-route-map");

    it("asks for the stored route on open and hands it to the route map", async () => {
      laneRoute.mockResolvedValue(ROUTE_VIEW);
      const el = await mount();
      await flush();
      expect(laneRoute).toHaveBeenCalledTimes(1);
      expect(laneRoute).toHaveBeenCalledWith({
        laneId: "a0L00000001",
        refresh: false
      });
      expect(map(el).view).toEqual(ROUTE_VIEW);
      expect(map(el).loading).toBe(false);
      expect(map(el).unit).toBe("mi");
      // The lane on screen had no miles; the copy laneRoute wrote and re-read has.
      expect(textOf(el, "lane-miles")).toBe("1,234 mi · truck route · 21.5 h");
      // The miles line sits under the heading, never inside its name.
      expect(el.shadowRoot.querySelector("h2").textContent.trim()).toBe(
        "Montreal, QC → Toronto, ON"
      );
    });

    it("shows the route map loading until the route arrives", async () => {
      let release;
      laneRoute.mockReturnValue(
        new Promise((resolve) => {
          release = resolve;
        })
      );
      const el = await mount();
      expect(map(el).loading).toBe(true);
      expect(map(el).view).toBeNull();
      release(ROUTE_VIEW);
      await flush();
      await flush();
      expect(map(el).loading).toBe(false);
      expect(map(el).view.routes.length).toBe(2);
    });

    it("asks Mapbox again when the route map asks for a refresh", async () => {
      laneRoute.mockResolvedValue(ROUTE_VIEW);
      const el = await mount();
      await flush();
      const regular = {
        ...ROUTE_VIEW,
        routeType: "Regular",
        miles: 1302,
        hours: 22,
        routes: [{ miles: 1302, hours: 22 }],
        lane: {
          ...ROUTED_LANE,
          Miles__c: 1302,
          Miles_Source__c: "Regular route",
          Route_Hours__c: 22
        }
      };
      laneRoute.mockResolvedValue(regular);
      map(el).dispatchEvent(new CustomEvent("refreshroute"));
      await flush();
      await flush();
      expect(laneRoute).toHaveBeenCalledTimes(2);
      expect(laneRoute.mock.calls[1][0]).toEqual({
        laneId: "a0L00000001",
        refresh: true
      });
      expect(map(el).view.routeType).toBe("Regular");
      expect(textOf(el, "lane-miles")).toBe(
        "1,302 mi · regular route · 22.0 h"
      );
    });

    it("asks for no route while an end is unresolved", async () => {
      const el = await mount({
        lane: { ...LANE, Destination_Place__r: undefined }
      });
      expect(laneRoute).not.toHaveBeenCalled();
      expect(map(el)).toBeNull();
      expect(field(el, "lane-miles")).toBeNull();
      expect(field(el, "cost-per-distance")).toBeNull();
    });

    it("drops a route that lands after the panel moved to another lane", async () => {
      let release;
      laneRoute.mockReturnValueOnce(
        new Promise((resolve) => {
          release = resolve;
        })
      );
      const el = await mount();
      laneRoute.mockResolvedValue({
        status: "No route",
        routeType: null,
        miles: null,
        hours: null,
        routes: [],
        mapUrl: null,
        message: null,
        lane: {
          ...LANE,
          Id: "a0L00000002",
          Miles__c: null,
          Miles_Source__c: "No route",
          Route_Hours__c: null
        }
      });
      el.lane = { ...LANE, Id: "a0L00000002" };
      await flush();
      await flush();
      release(ROUTE_VIEW);
      await flush();
      await flush();
      expect(laneRoute.mock.calls.map((c) => c[0])).toEqual([
        { laneId: "a0L00000001", refresh: false },
        { laneId: "a0L00000002", refresh: false }
      ]);
      expect(map(el).view.status).toBe("No route");
      expect(textOf(el, "lane-miles")).toBe(
        "No route found between the two places"
      );
    });

    it("shows an Apex failure as an unavailable route, not as a panel error", async () => {
      laneRoute.mockRejectedValue({
        body: { message: "This lane is not available." }
      });
      const el = await mount();
      await flush();
      expect(map(el).view).toMatchObject({
        status: "Unavailable",
        routes: [],
        message: "This lane is not available."
      });
      expect(map(el).loading).toBe(false);
      expect(field(el, "panel-error")).toBeNull();
    });

    it("tells the route map when the lane is hazmat", async () => {
      laneRoute.mockResolvedValue(ROUTE_VIEW);
      const plain = await mount();
      expect(map(plain).hazmat).toBe(false);
      const hazmat = await mount({
        lane: { ...LANE, Id: "a0L00000003", Hazmat__c: true }
      });
      expect(map(hazmat).hazmat).toBe(true);
    });

    it("prices per mile as the pricer types, and per km once the unit changes", async () => {
      const el = await mount({
        lane: { ...LANE, Miles__c: 1234, Miles_Source__c: "History" }
      });
      expect(textOf(el, "lane-miles")).toBe("1,234 mi · from history");
      // 1500 / 1234; the lane has no margin yet, so there is no sell to divide
      expect(textOf(el, "cost-per-distance")).toBe("Cost per mile: 1.22 CAD");
      expect(textOf(el, "sell-per-distance")).toBe("Sell per mile: —");

      change(el, "margin", { value: "20" });
      await flush();
      // sell 1800 / 1234
      expect(textOf(el, "sell-per-distance")).toBe("Sell per mile: 1.46 CAD");

      change(el, "sell", { value: "2250" });
      await flush();
      expect(textOf(el, "sell-per-distance")).toBe("Sell per mile: 1.82 CAD");

      publishUnit("km");
      await flush();
      // 1234 mi = 1,985.93 km
      expect(textOf(el, "lane-miles")).toBe("1,986 km · from history");
      expect(textOf(el, "cost-per-distance")).toBe("Cost per km: 0.76 CAD");
      expect(textOf(el, "sell-per-distance")).toBe("Sell per km: 1.13 CAD");
      expect(map(el).unit).toBe("km");
    });

    it("starts from the stored unit and lets go of the channel when removed", async () => {
      writeUnit("km");
      subscribe.mockReturnValueOnce({ id: "unit-sub" });
      const el = await mount({
        lane: { ...LANE, Miles__c: 1234, Miles_Source__c: "Approx" }
      });
      expect(textOf(el, "lane-miles")).toBe("1,986 km · approx.");
      expect(textOf(el, "cost-per-distance")).toBe("Cost per km: 0.76 CAD");
      expect(subscribe.mock.calls.some((c) => c[1] === DISTANCE_UNIT)).toBe(
        true
      );
      document.body.removeChild(el);
      expect(unsubscribe).toHaveBeenCalledWith({ id: "unit-sub" });
    });

    it("lets newer miles from the container replace the route's copy", async () => {
      laneRoute.mockResolvedValue(ROUTE_VIEW);
      const el = await mount();
      await flush();
      expect(textOf(el, "lane-miles")).toBe("1,234 mi · truck route · 21.5 h");
      // a history run found billed miles for the same lane and the same places
      el.lane = {
        ...LANE,
        Miles__c: 1198,
        Miles_Source__c: "History",
        Route_Hours__c: null
      };
      await flush();
      expect(textOf(el, "lane-miles")).toBe("1,198 mi · from history");
      // same place pair: no second route request
      expect(laneRoute).toHaveBeenCalledTimes(1);
    });

    it("asks for no route while the container is mid-run, and asks for the lane on screen once it ends", async () => {
      laneRoute.mockResolvedValue(ROUTE_VIEW);
      // rfpTool.html sets lane before busy, so a panel rendered mid-run gets its
      // lane while busy still reads false.
      const el = await mount({ busy: true });
      expect(laneRoute).not.toHaveBeenCalled();
      expect(map(el).loading).toBe(true);
      // laneRoute writes the lane's miles: during a history run it could land
      // on top of the History miles the lane's chunk just wrote (R75).
      el.lane = { ...LANE, Id: "a0L00000002" };
      await flush();
      await flush();
      expect(laneRoute).not.toHaveBeenCalled();
      el.busy = false;
      await flush();
      await flush();
      expect(laneRoute.mock.calls.map((c) => c[0])).toEqual([
        { laneId: "a0L00000002", refresh: false }
      ]);
      expect(map(el).loading).toBe(false);
      expect(textOf(el, "lane-miles")).toBe("1,234 mi · truck route · 21.5 h");
    });

    it("holds a Refresh route clicked mid-run until the run ends", async () => {
      laneRoute.mockResolvedValue(ROUTE_VIEW);
      const el = await mount();
      await flush();
      expect(laneRoute).toHaveBeenCalledTimes(1);
      el.busy = true;
      await flush();
      map(el).dispatchEvent(new CustomEvent("refreshroute"));
      await flush();
      await flush();
      expect(laneRoute).toHaveBeenCalledTimes(1);
      expect(map(el).loading).toBe(true);
      // The run wrote History miles for this lane and the container merged them
      // (same places) in the render that ends the run; laneRoute then reads
      // History and writes nothing, so its view comes back without a lane.
      laneRoute.mockResolvedValue({ ...ROUTE_VIEW, lane: null });
      el.lane = {
        ...LANE,
        Miles__c: 1198,
        Miles_Source__c: "History",
        Route_Hours__c: null
      };
      el.busy = false;
      await flush();
      await flush();
      expect(laneRoute).toHaveBeenCalledTimes(2);
      expect(laneRoute.mock.calls[1][0]).toEqual({
        laneId: "a0L00000001",
        refresh: true
      });
      expect(map(el).loading).toBe(false);
      expect(textOf(el, "lane-miles")).toBe("1,198 mi · from history");
    });
  });

  describe("carriers to ask", () => {
    it("shows Carriers to ask under the history once it loads with no rate in the lane's currency", async () => {
      // HISTORY has no statistics bucket at all
      const el = await mount();
      const leads = field(el, "carrier-leads");
      expect(leads).not.toBeNull();
      const sent = search.mock.calls[0][0].requestJson;
      expect(leads.requestJson).toBe(sent);
      expect(leads.currencyCode).toBe("CAD");
      expect(findCarrierLeads).toHaveBeenCalledWith({
        requestJson: sent,
        attempt: 0
      });
      expect(
        field(el, "history-scroll").nextElementSibling.contains(leads)
      ).toBe(true);
    });

    it("judges the rate in the lane's own currency", async () => {
      search.mockResolvedValue({
        ...HISTORY,
        statsByCurrency: { CAD: { count: 1, countNonZero: 1, median: 1950 } }
      });
      const el = await mount();
      expect(field(el, "carrier-leads")).toBeNull();
      expect(findCarrierLeads).not.toHaveBeenCalled();

      el.lane = { ...LANE, Id: "a0L00000002", CurrencyIsoCode: "USD" };
      await flush();
      await flush();
      const leads = field(el, "carrier-leads");
      expect(leads).not.toBeNull();
      expect(leads.currencyCode).toBe("USD");
    });

    it("hides Carriers to ask while the history loads, after it fails and without both place keys", async () => {
      let releaseSearch;
      search.mockReturnValueOnce(
        new Promise((resolve) => {
          releaseSearch = resolve;
        })
      );
      const el = await mount();
      expect(field(el, "carrier-leads")).toBeNull();
      releaseSearch(HISTORY);
      await flush();
      await flush();
      expect(field(el, "carrier-leads")).not.toBeNull();

      // the previous lane's answer does not count for a lane still loading
      search.mockReturnValueOnce(new Promise(() => {}));
      el.lane = { ...LANE, Id: "a0L00000002" };
      await flush();
      expect(field(el, "carrier-leads")).toBeNull();

      search.mockRejectedValueOnce({ body: { message: "Search failed" } });
      el.lane = { ...LANE, Id: "a0L00000003" };
      await flush();
      await flush();
      expect(textOf(el, "panel-error")).toBe("Search failed");
      expect(field(el, "carrier-leads")).toBeNull();

      el.lane = { ...LANE, Id: "a0L00000004", Destination_Place__r: undefined };
      await flush();
      await flush();
      expect(field(el, "carrier-leads")).toBeNull();
      expect(findCarrierLeads).toHaveBeenCalledTimes(1);
    });
  });

  describe("split-lane options and the Split cost", () => {
    const split = (el) => field(el, "split-options");
    const useAsCost = (el, cost) =>
      split(el).dispatchEvent(
        new CustomEvent("useascost", { detail: { cost, currencyCode: "CAD" } })
      );
    const sourceValues = (el) =>
      field(el, "cost-source").options.map((o) => o.value);

    it("hands the lane's history request, currency and statistics to the split card", async () => {
      const stats = {
        CAD: { count: 1, countNonZero: 1, median: 1950 },
        USD: { count: 1, countNonZero: 1, median: 1420 }
      };
      search.mockResolvedValue({ ...HISTORY, statsByCurrency: stats });
      const el = await mount({ lane: { ...LANE, CurrencyIsoCode: "USD" } });
      expect(split(el)).not.toBeNull();
      expect(split(el).requestJson).toBe(search.mock.calls[0][0].requestJson);
      expect(split(el).startCurrency).toBe("USD");
      expect(split(el).laneCurrency).toBe("USD");
      expect(split(el).statsByCurrency).toEqual(stats);
      expect(split(el).allowUseAsCost).toBe(true);
      // The card asks nothing until the pricer clicks it (D1).
      expect(splitOptions).not.toHaveBeenCalled();

      el.lane = { ...LANE, Id: "a0L00000002", Destination_Place__r: undefined };
      await flush();
      expect(split(el)).toBeNull();
    });

    it("fills the editor from a split option: source Split, bid cleared, cost locked, saved as a Split cost", async () => {
      getBids.mockResolvedValue([CHEAP_BID]);
      const el = await mount({
        lane: {
          ...LANE,
          Cost_Source__c: "Bid",
          Selected_Bid__c: "a0B00000001",
          Cost__c: 1800
        }
      });
      expect(field(el, "bid-select")).not.toBeNull();
      const handler = jest.fn();
      el.addEventListener("pricingchange", handler);

      useAsCost(el, 6450);
      await flush();
      expect(field(el, "cost-source").value).toBe("Split");
      expect(field(el, "bid-select")).toBeNull();
      expect(field(el, "cost").value).toBe(6450);
      expect(field(el, "cost").disabled).toBe(true);

      change(el, "margin", { value: "10" });
      await flush();
      field(el, "save-price").click();
      expect(handler).toHaveBeenCalledTimes(1);
      expect(handler.mock.calls[0][0].detail).toEqual({
        laneId: "a0L00000001",
        Cost__c: 6450,
        Cost_Source__c: "Split",
        Selected_Bid__c: null,
        Margin__c: 10,
        Sell__c: 7095,
        Sell_Source__c: "Margin",
        Notes__c: "Watch the ferry surcharge"
      });
    });

    it("offers Split as a cost source only while Split is the source", async () => {
      const el = await mount();
      expect(sourceValues(el)).toEqual(["Bid", "History median", "Manual"]);
      useAsCost(el, 2400);
      await flush();
      expect(sourceValues(el)).toEqual([
        "Bid",
        "History median",
        "Manual",
        "Split"
      ]);
      change(el, "cost-source", { value: "Manual" });
      await flush();
      expect(sourceValues(el)).toEqual(["Bid", "History median", "Manual"]);
      expect(field(el, "cost").disabled).toBe(false);
      expect(field(el, "cost").value).toBe("1500");
    });

    it("shows a lane saved with Split at its stored cost, and lets stored pricing replace a filled amount", async () => {
      const el = await mount({
        lane: { ...LANE, Cost_Source__c: "Split", Cost__c: 6400 }
      });
      expect(field(el, "cost-source").value).toBe("Split");
      expect(sourceValues(el)).toContain("Split");
      expect(field(el, "cost").value).toBe(6400);

      useAsCost(el, 6510.4);
      await flush();
      expect(field(el, "cost").value).toBe(6510.4);

      // A bulk action stored another Split cost on the lane on screen.
      el.lane = { ...LANE, Cost_Source__c: "Split", Cost__c: 6300 };
      await flush();
      expect(field(el, "cost").value).toBe(6300);

      useAsCost(el, 6999);
      await flush();
      // Another lane: nothing is filled for it yet.
      el.lane = {
        ...LANE,
        Id: "a0L00000002",
        Cost_Source__c: "Split",
        Cost__c: 5900
      };
      await flush();
      expect(field(el, "cost").value).toBe(5900);
    });
  });
});
