import { createElement } from "lwc";
import LaneBenchmark from "c/laneBenchmark";
import search from "@salesforce/apex/LaneBenchmarkController.search";
import getFilterOptions from "@salesforce/apex/LaneBenchmarkController.getFilterOptions";
import mapPreviewUrl from "@salesforce/apex/LaneBenchmarkController.mapPreviewUrl";
import { save, load, STORAGE_KEY } from "c/laneBenchmarkStorage";

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
  "@salesforce/apex/LaneBenchmarkController.searchPlaces",
  () => ({ default: jest.fn().mockResolvedValue([]) }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/LaneBenchmarkController.geocode",
  () => ({ default: jest.fn().mockResolvedValue([]) }),
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
      median: 1000
    }
  },
  truncated: false,
  elapsedMs: 300,
  dedupedCount: 0
};

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
          marketTestOnly: false,
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
});
