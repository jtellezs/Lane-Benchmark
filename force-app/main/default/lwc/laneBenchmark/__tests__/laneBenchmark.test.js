import { createElement } from "lwc";
import LaneBenchmark from "c/laneBenchmark";
import search from "@salesforce/apex/LaneBenchmarkController.search";
import getFilterOptions from "@salesforce/apex/LaneBenchmarkController.getFilterOptions";
import mapPreviewUrl from "@salesforce/apex/LaneBenchmarkController.mapPreviewUrl";
import truckRoute from "@salesforce/apex/LaneBenchmarkController.truckRoute";
import findCarrierLeads from "@salesforce/apex/CarrierLeadController.findCarrierLeads";
import {
  subscribe,
  unsubscribe,
  APPLICATION_SCOPE
} from "lightning/messageService";
import DISTANCE_UNIT from "@salesforce/messageChannel/Distance_Unit__c";
import { save, load, STORAGE_KEY } from "c/laneBenchmarkStorage";
import { writeUnit } from "c/distanceUnit";

jest.mock(
  "@salesforce/apex/LaneBenchmarkController.search",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/LaneBenchmarkController.getFilterOptions",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/LaneBenchmarkController.mapPreviewUrl",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/LaneBenchmarkController.truckRoute",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/LaneBenchmarkController.searchPlaces",
  () => ({ default: jest.fn().mockResolvedValue([]) }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/LaneBenchmarkController.geocode",
  () => ({ default: jest.fn().mockResolvedValue([]) }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/CarrierLeadController.findCarrierLeads",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const flush = () => Promise.resolve().then(() => Promise.resolve());
const RESULT = {
  rows: [
    {
      quoteId: "q1",
      quoteName: "CQ-1",
      origin: "A",
      destination: "B",
      mode: "LTL",
      carrierName: "Acme",
      currencyIsoCode: "CAD",
      carrierTotal: 1000,
      load: { loadId: "a0L000000000001", miles: 337.2 },
      quoteDate: "2026-09-01",
      accepted: true
    }
  ],
  statsByCurrency: {
    CAD: {
      count: 1,
      countNonZero: 1,
      min: 1000,
      max: 1000,
      avg: 1000,
      median: 1000,
      ratePerMileMedian: 2.97
    }
  },
  truncated: false,
  elapsedMs: 300,
  dedupedCount: 0,
  medianMiles: 337.2
};
const ROUTE_VIEW = {
  status: "Found",
  routeType: "Truck",
  source: "Truck route",
  miles: 336.9,
  hours: 5.4,
  routes: [{ miles: 336.9, hours: 5.4 }],
  mapUrl:
    "https://api.mapbox.com/styles/v1/mapbox/streets-v12/static/pin-s-a+0070d2(-73.5674,45.5019)/auto/600x300@2x?padding=40&access_token=pk.test",
  message: null
};
// a route answer comes after the search, the preview and a re-render: give it room to land
const settle = () => flush().then(flush).then(flush).then(flush);

async function mount() {
  const el = createElement("c-lane-benchmark", { is: LaneBenchmark });
  document.body.appendChild(el);
  await flush();
  await flush();
  return el;
}
const pick = (el, label, detail) =>
  el.shadowRoot
    .querySelector(`c-lane-benchmark-place-picker[data-id="${label}"]`)
    .dispatchEvent(new CustomEvent("placechange", { detail }));
const pickLane = (el) => {
  pick(el, "origin", {
    key: "montreal|qc|ca",
    label: "Montréal, QC, CA",
    precision: "CITY",
    radius: null,
    unit: "MI"
  });
  pick(el, "destination", {
    key: "toronto|on|ca",
    label: "Toronto, ON, CA",
    precision: "CITY",
    radius: null,
    unit: "MI"
  });
};
const applySearch = (el) =>
  el.shadowRoot
    .querySelector("c-lane-benchmark-filters")
    .dispatchEvent(new CustomEvent("apply"));

describe("c-lane-benchmark", () => {
  beforeEach(() => {
    window.localStorage.clear();
    getFilterOptions.mockResolvedValue({
      modes: ["LTL"],
      equipmentByCategory: { Van: ["Dry Van"] },
      currencies: ["CAD", "USD"]
    });
    search.mockResolvedValue(RESULT);
    mapPreviewUrl.mockResolvedValue(null);
    truckRoute.mockResolvedValue(ROUTE_VIEW);
    findCarrierLeads.mockResolvedValue({
      leads: [],
      stage: "None",
      stateLaneLabel: null,
      truncated: false
    });
  });
  afterEach(() => {
    while (document.body.firstChild)
      document.body.removeChild(document.body.firstChild);
    jest.clearAllMocks();
  });

  it("does not search on load without a saved request, then searches on apply with the assembled request", async () => {
    const el = await mount();
    expect(search).not.toHaveBeenCalled();
    pick(el, "origin", {
      key: "montreal|qc|ca",
      label: "Montréal, QC, CA",
      precision: "CITY",
      radius: null,
      unit: "MI"
    });
    pick(el, "destination", {
      key: "toronto|on|ca",
      label: "Toronto, ON, CA",
      precision: "RADIUS",
      radius: 100,
      unit: "KM"
    });
    el.shadowRoot.querySelector("c-lane-benchmark-filters").dispatchEvent(
      new CustomEvent("filterschange", {
        detail: {
          lookbackDays: 120,
          currencyIsoCode: "CAD",
          modes: ["LTL"],
          equipmentCategories: [],
          equipmentTypes: [],
          hazmatOnly: false,
          acceptedFilter: "ANY_STATUS"
        }
      })
    );
    el.shadowRoot
      .querySelector("c-lane-benchmark-filters")
      .dispatchEvent(new CustomEvent("apply"));
    await flush();
    await flush();
    expect(search).toHaveBeenCalledTimes(1);
    const sent = JSON.parse(search.mock.calls[0][0].requestJson);
    expect(sent).not.toHaveProperty("marketTestOnly");
    expect(sent).toMatchObject({
      originKey: "montreal|qc|ca",
      originPrecision: "CITY",
      destinationKey: "toronto|on|ca",
      destinationPrecision: "RADIUS",
      destinationRadius: 100,
      radiusUnit: "KM",
      lookbackDays: 120,
      currencyIsoCode: "CAD",
      modes: ["LTL"]
    });
    expect(sent.sourceFilter).toBe("ALL");
    expect(
      el.shadowRoot.querySelector("c-lane-benchmark-results").rows.length
    ).toBe(1);
    expect(load()).toMatchObject({
      originKey: "montreal|qc|ca",
      lookbackDays: 120,
      marginPct: 15
    });
    expect(mapPreviewUrl).toHaveBeenCalledWith({
      originKey: "montreal|qc|ca",
      originRadius: null,
      destinationKey: "toronto|on|ca",
      destinationRadius: 100,
      unit: "KM"
    });
  });

  it("restores a saved request and searches immediately", async () => {
    save({
      originKey: "laval|qc|ca",
      originLabel: "Laval, QC, CA",
      originPrecision: "CITY",
      destinationKey: null,
      lookbackDays: 45,
      marginPct: 20,
      modes: [],
      equipmentCategories: [],
      equipmentTypes: [],
      acceptedFilter: "ANY_STATUS"
    });
    await mount();
    await flush();
    expect(search).toHaveBeenCalledTimes(1);
    expect(JSON.parse(search.mock.calls[0][0].requestJson)).toMatchObject({
      originKey: "laval|qc|ca",
      lookbackDays: 45
    });
  });

  it("gates a long radius search behind a confirmation", async () => {
    const el = await mount();
    pick(el, "origin", {
      key: "montreal|qc|ca",
      label: "Montréal, QC, CA",
      precision: "RADIUS",
      radius: 100,
      unit: "MI"
    });
    el.shadowRoot.querySelector("c-lane-benchmark-filters").dispatchEvent(
      new CustomEvent("filterschange", {
        detail: {
          lookbackDays: 730,
          modes: [],
          equipmentCategories: [],
          equipmentTypes: [],
          acceptedFilter: "ANY_STATUS"
        }
      })
    );
    el.shadowRoot
      .querySelector("c-lane-benchmark-filters")
      .dispatchEvent(new CustomEvent("apply"));
    await flush();
    expect(search).not.toHaveBeenCalled();
    expect(el.shadowRoot.textContent).toMatch(/10-20 seconds/);
    el.shadowRoot.querySelector('[data-id="continue"]').click();
    await flush();
    await flush();
    expect(search).toHaveBeenCalledTimes(1);
  });

  it("lowering the lookback and applying again clears the long-radius confirmation banner", async () => {
    const el = await mount();
    pick(el, "origin", {
      key: "montreal|qc|ca",
      label: "Montréal, QC, CA",
      precision: "RADIUS",
      radius: 100,
      unit: "MI"
    });
    const filters = () =>
      el.shadowRoot.querySelector("c-lane-benchmark-filters");
    filters().dispatchEvent(
      new CustomEvent("filterschange", {
        detail: {
          lookbackDays: 730,
          modes: [],
          equipmentCategories: [],
          equipmentTypes: [],
          acceptedFilter: "ANY_STATUS"
        }
      })
    );
    filters().dispatchEvent(new CustomEvent("apply"));
    await flush();
    expect(search).not.toHaveBeenCalled();
    expect(el.shadowRoot.textContent).toMatch(/10-20 seconds/);
    filters().dispatchEvent(
      new CustomEvent("filterschange", {
        detail: {
          lookbackDays: 90,
          modes: [],
          equipmentCategories: [],
          equipmentTypes: [],
          acceptedFilter: "ANY_STATUS"
        }
      })
    );
    filters().dispatchEvent(new CustomEvent("apply"));
    await flush();
    await flush();
    expect(search).toHaveBeenCalledTimes(1);
    expect(el.shadowRoot.textContent).not.toMatch(/10-20 seconds/);
  });

  it("shows the controller error message and clears results", async () => {
    search.mockRejectedValue({
      body: { message: "Unknown place key: nowhere|zz|zz" }
    });
    const el = await mount();
    el.shadowRoot
      .querySelector("c-lane-benchmark-filters")
      .dispatchEvent(new CustomEvent("apply"));
    await flush();
    await flush();
    expect(
      el.shadowRoot.querySelector('[data-id="error"]').textContent
    ).toContain("nowhere|zz|zz");
  });

  it("clear saved filters empties storage and resets the request", async () => {
    save({
      originKey: "laval|qc|ca",
      lookbackDays: 45,
      modes: [],
      equipmentCategories: [],
      equipmentTypes: [],
      acceptedFilter: "ANY_STATUS"
    });
    const el = await mount();
    el.shadowRoot
      .querySelector("c-lane-benchmark-filters")
      .dispatchEvent(new CustomEvent("clearsaved"));
    await flush();
    expect(window.localStorage.getItem(STORAGE_KEY)).toBeNull();
    expect(
      el.shadowRoot.querySelector("c-lane-benchmark-filters").value.lookbackDays
    ).toBe(90);
  });

  it("keeps the search result when the map preview call fails", async () => {
    mapPreviewUrl.mockRejectedValue(new Error("no token"));
    const el = await mount();
    el.shadowRoot
      .querySelector("c-lane-benchmark-filters")
      .dispatchEvent(new CustomEvent("apply"));
    await flush();
    await flush();
    await flush();
    expect(
      el.shadowRoot.querySelector("c-lane-benchmark-results").rows.length
    ).toBe(1);
    expect(el.shadowRoot.querySelector('[data-id="error"]')).toBeNull();
  });

  it("ignores a second apply while a search is already in flight", async () => {
    let resolveSearch;
    search.mockImplementation(
      () =>
        new Promise((resolve) => {
          resolveSearch = resolve;
        })
    );
    const el = await mount();
    const filters = el.shadowRoot.querySelector("c-lane-benchmark-filters");
    filters.dispatchEvent(new CustomEvent("apply"));
    await flush();
    filters.dispatchEvent(new CustomEvent("apply"));
    await flush();
    expect(search).toHaveBeenCalledTimes(1);
    resolveSearch(RESULT);
    await flush();
    await flush();
    expect(search).toHaveBeenCalledTimes(1);
  });

  it("reset clears only the filter keys, keeping places, precisions, radii and margin", async () => {
    const el = await mount();
    pick(el, "origin", {
      key: "montreal|qc|ca",
      label: "Montréal, QC, CA",
      precision: "RADIUS",
      radius: 100,
      unit: "MI"
    });
    el.shadowRoot
      .querySelector("c-lane-benchmark-filters")
      .dispatchEvent(new CustomEvent("apply"));
    await flush();
    await flush();
    el.shadowRoot
      .querySelector("c-lane-benchmark-stats")
      .dispatchEvent(
        new CustomEvent("marginchange", { detail: { marginPct: 20 } })
      );
    el.shadowRoot.querySelector("c-lane-benchmark-filters").dispatchEvent(
      new CustomEvent("filterschange", {
        detail: {
          lookbackDays: 120,
          modes: ["LTL"],
          equipmentCategories: [],
          equipmentTypes: [],
          acceptedFilter: "ACCEPTED"
        }
      })
    );
    el.shadowRoot
      .querySelector("c-lane-benchmark-filters")
      .dispatchEvent(new CustomEvent("reset"));
    await flush();
    const origin = el.shadowRoot.querySelector(
      'c-lane-benchmark-place-picker[data-id="origin"]'
    );
    expect(origin.precision).toBe("RADIUS");
    expect(origin.radius).toBe(100);
    expect(
      el.shadowRoot.querySelector("c-lane-benchmark-stats").marginPct
    ).toBe(20);
    expect(
      el.shadowRoot.querySelector("c-lane-benchmark-filters").value
    ).toMatchObject({
      lookbackDays: 90,
      modes: [],
      acceptedFilter: "ANY_STATUS"
    });
  });

  it("asks for the truck route after a successful search and shows it in place of the preview", async () => {
    // two quotes on one load and a load without miles: "median of N loads" counts each load once,
    // like LaneSearchResult.medianMiles (TripMilesService.medianMiles counts distinct load Ids)
    search.mockResolvedValueOnce({
      ...RESULT,
      rows: [
        RESULT.rows[0],
        { ...RESULT.rows[0], quoteId: "q2", quoteName: "CQ-2" },
        {
          ...RESULT.rows[0],
          quoteId: "q3",
          quoteName: "CQ-3",
          load: { loadId: "a0L000000000002", miles: 0 }
        }
      ]
    });
    const el = await mount();
    pickLane(el);
    applySearch(el);
    await settle();
    expect(truckRoute).toHaveBeenCalledTimes(1);
    expect(truckRoute).toHaveBeenCalledWith({
      originKey: "montreal|qc|ca",
      destinationKey: "toronto|on|ca",
      refresh: false
    });
    const routeMap = el.shadowRoot.querySelector("c-route-map");
    expect(routeMap).not.toBeNull();
    expect(routeMap.view.mapUrl).toBe(ROUTE_VIEW.mapUrl);
    expect(routeMap.unit).toBe("mi");
    expect(el.shadowRoot.querySelector("c-lane-benchmark-map")).toBeNull();
    const stats = el.shadowRoot.querySelector("c-lane-benchmark-stats");
    expect(stats.routeView.status).toBe("Found");
    expect(stats.medianMiles).toBe(337.2);
    expect(stats.milesCount).toBe(1);
  });

  it("does not ask for a route when only one end is chosen, and keeps the preview", async () => {
    mapPreviewUrl.mockResolvedValue(
      "https://api.mapbox.com/styles/v1/x/static/auto/600x300?access_token=pk.test"
    );
    const el = await mount();
    pick(el, "origin", {
      key: "montreal|qc|ca",
      label: "Montréal, QC, CA",
      precision: "RADIUS",
      radius: 100,
      unit: "MI"
    });
    applySearch(el);
    await settle();
    expect(search).toHaveBeenCalledTimes(1);
    expect(truckRoute).not.toHaveBeenCalled();
    expect(el.shadowRoot.querySelector("c-route-map")).toBeNull();
    expect(
      el.shadowRoot.querySelector("c-lane-benchmark-map").previewUrl
    ).toContain("api.mapbox.com");
  });

  it("keeps the radius preview under the route map after a radius search", async () => {
    mapPreviewUrl.mockResolvedValue(
      "https://api.mapbox.com/styles/v1/x/static/auto/600x300?access_token=pk.test"
    );
    const el = await mount();
    pick(el, "origin", {
      key: "montreal|qc|ca",
      label: "Montréal, QC, CA",
      precision: "RADIUS",
      radius: 100,
      unit: "MI"
    });
    pick(el, "destination", {
      key: "toronto|on|ca",
      label: "Toronto, ON, CA",
      precision: "CITY",
      radius: null,
      unit: "MI"
    });
    applySearch(el);
    await settle();
    expect(truckRoute).toHaveBeenCalledTimes(1);
    expect(el.shadowRoot.querySelector("c-route-map").view.mapUrl).toBe(
      ROUTE_VIEW.mapUrl
    );
    expect(
      el.shadowRoot.querySelector("c-lane-benchmark-map").previewUrl
    ).toContain("api.mapbox.com");
  });

  it("keeps the preview and the results when the route has no map or the route call fails", async () => {
    truckRoute.mockResolvedValueOnce({
      status: "Unavailable",
      routeType: null,
      routes: [],
      mapUrl: null,
      message: "The truck route is not available right now."
    });
    const el = await mount();
    pickLane(el);
    applySearch(el);
    await settle();
    expect(el.shadowRoot.querySelector("c-route-map")).toBeNull();
    expect(el.shadowRoot.querySelector("c-lane-benchmark-map")).not.toBeNull();
    expect(
      el.shadowRoot.querySelector("c-lane-benchmark-stats").routeView.message
    ).toBe("The truck route is not available right now.");
    truckRoute.mockRejectedValueOnce({
      body: { message: "Unknown place key: toronto|on|ca" }
    });
    applySearch(el);
    await settle();
    expect(truckRoute).toHaveBeenCalledTimes(2);
    expect(
      el.shadowRoot.querySelector("c-lane-benchmark-results").rows.length
    ).toBe(1);
    expect(el.shadowRoot.querySelector('[data-id="error"]')).toBeNull();
    expect(
      el.shadowRoot.querySelector("c-lane-benchmark-stats").routeView
    ).toBeNull();
    expect(el.shadowRoot.querySelector("c-lane-benchmark-map")).not.toBeNull();
  });

  it("refresh route asks again for the same pair without searching again", async () => {
    const el = await mount();
    pickLane(el);
    applySearch(el);
    await settle();
    truckRoute.mockResolvedValueOnce({
      ...ROUTE_VIEW,
      routeType: "Regular",
      miles: 351
    });
    el.shadowRoot
      .querySelector("c-route-map")
      .dispatchEvent(new CustomEvent("refreshroute"));
    await settle();
    expect(truckRoute).toHaveBeenCalledTimes(2);
    expect(truckRoute.mock.calls[1][0]).toEqual({
      originKey: "montreal|qc|ca",
      destinationKey: "toronto|on|ca",
      refresh: true
    });
    expect(el.shadowRoot.querySelector("c-route-map").view.routeType).toBe(
      "Regular"
    );
    expect(search).toHaveBeenCalledTimes(1);
  });

  it("drops a route answer that belongs to an earlier search", async () => {
    let resolveFirst;
    truckRoute.mockImplementationOnce(
      () =>
        new Promise((resolve) => {
          resolveFirst = resolve;
        })
    );
    const el = await mount();
    pickLane(el);
    applySearch(el);
    await settle();
    pick(el, "destination", {
      key: "ottawa|on|ca",
      label: "Ottawa, ON, CA",
      precision: "CITY",
      radius: null,
      unit: "MI"
    });
    truckRoute.mockResolvedValueOnce({ ...ROUTE_VIEW, miles: 124.8 });
    applySearch(el);
    await settle();
    resolveFirst({ ...ROUTE_VIEW, miles: 336.9 });
    await settle();
    expect(truckRoute).toHaveBeenCalledTimes(2);
    expect(truckRoute.mock.calls[1][0].destinationKey).toBe("ottawa|on|ca");
    expect(el.shadowRoot.querySelector("c-route-map").view.miles).toBe(124.8);
  });

  it("shows Carriers to ask under the statistics when the search has no rate in the currency filter", async () => {
    const el = await mount();
    pickLane(el);
    el.shadowRoot
      .querySelector("c-lane-benchmark-filters")
      .dispatchEvent(
        new CustomEvent("filterschange", { detail: { currencyIsoCode: "USD" } })
      );
    applySearch(el);
    await settle();
    // RESULT is priced in CAD only, so the USD filter has no rate
    const leads = el.shadowRoot.querySelector('[data-id="carrier-leads"]');
    expect(leads).not.toBeNull();
    const sent = search.mock.calls[0][0].requestJson;
    expect(leads.requestJson).toBe(sent);
    expect(leads.currencyCode).toBe("USD");
    expect(findCarrierLeads).toHaveBeenCalledWith({
      requestJson: sent,
      attempt: 0
    });
    const order = [
      ...el.shadowRoot.querySelectorAll(
        "c-lane-benchmark-stats, c-carrier-leads, c-route-map, c-lane-benchmark-results"
      )
    ].map((node) => node.tagName.toLowerCase());
    expect(order).toEqual([
      "c-lane-benchmark-stats",
      "c-carrier-leads",
      "c-route-map",
      "c-lane-benchmark-results"
    ]);
  });

  it("shows Carriers to ask without a filter only when no currency has a rate, and never without both place keys", async () => {
    const el = await mount();
    pickLane(el);
    applySearch(el);
    await settle();
    // no currency filter: the CAD rate counts
    expect(
      el.shadowRoot.querySelector("c-lane-benchmark-stats")
    ).not.toBeNull();
    expect(el.shadowRoot.querySelector('[data-id="carrier-leads"]')).toBeNull();

    search.mockResolvedValue({ ...RESULT, rows: [], statsByCurrency: {} });
    pick(el, "destination", {
      key: null,
      label: "",
      precision: "CITY",
      radius: null,
      unit: "MI"
    });
    applySearch(el);
    await settle();
    expect(search).toHaveBeenCalledTimes(2);
    expect(
      el.shadowRoot.querySelector("c-lane-benchmark-stats")
    ).not.toBeNull();
    expect(el.shadowRoot.querySelector('[data-id="carrier-leads"]')).toBeNull();
    expect(findCarrierLeads).not.toHaveBeenCalled();

    pickLane(el);
    applySearch(el);
    await settle();
    const leads = el.shadowRoot.querySelector('[data-id="carrier-leads"]');
    expect(leads).not.toBeNull();
    expect(leads.currencyCode).toBeNull();
    expect(findCarrierLeads).toHaveBeenCalledTimes(1);
    expect(findCarrierLeads.mock.calls[0][0].requestJson).toBe(
      search.mock.calls[2][0].requestJson
    );
  });

  it("keeps the statistics and results when Carriers to ask fails", async () => {
    findCarrierLeads.mockRejectedValue({
      body: { message: "Carriers failed" }
    });
    const el = await mount();
    pickLane(el);
    el.shadowRoot
      .querySelector("c-lane-benchmark-filters")
      .dispatchEvent(
        new CustomEvent("filterschange", { detail: { currencyIsoCode: "USD" } })
      );
    applySearch(el);
    await settle();
    await settle();
    const leads = el.shadowRoot.querySelector('[data-id="carrier-leads"]');
    expect(leads).not.toBeNull();
    expect(
      leads.shadowRoot.querySelector('[data-id="leads-error"]')
    ).not.toBeNull();
    expect(
      el.shadowRoot.querySelector("c-lane-benchmark-stats")
    ).not.toBeNull();
    expect(
      el.shadowRoot.querySelector("c-lane-benchmark-results")
    ).not.toBeNull();
  });

  it("starts from the saved unit, follows the distance unit channel and unsubscribes when removed", async () => {
    writeUnit("km");
    subscribe.mockReturnValueOnce({ channel: "unit" });
    const el = await mount();
    expect(subscribe).toHaveBeenCalledTimes(1);
    expect(subscribe.mock.calls[0][1]).toBe(DISTANCE_UNIT);
    expect(subscribe.mock.calls[0][3]).toEqual({ scope: APPLICATION_SCOPE });
    const onUnit = subscribe.mock.calls[0][2];
    pickLane(el);
    applySearch(el);
    await settle();
    const results = () =>
      el.shadowRoot.querySelector("c-lane-benchmark-results");
    expect(results().unit).toBe("km");
    onUnit({ unit: "mi" });
    await flush();
    expect(results().unit).toBe("mi");
    expect(el.shadowRoot.querySelector("c-lane-benchmark-stats").unit).toBe(
      "mi"
    );
    expect(el.shadowRoot.querySelector("c-route-map").unit).toBe("mi");
    onUnit({ unit: "furlongs" });
    await flush();
    expect(results().unit).toBe("mi");
    document.body.removeChild(el);
    expect(unsubscribe).toHaveBeenCalledWith({ channel: "unit" });
  });
});
