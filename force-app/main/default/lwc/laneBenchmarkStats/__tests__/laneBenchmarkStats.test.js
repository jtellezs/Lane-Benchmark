import { createElement } from "lwc";
import Stats from "c/laneBenchmarkStats";

const flush = () => Promise.resolve().then(() => Promise.resolve());
const STATS = {
  CAD: {
    count: 4,
    countNonZero: 3,
    min: 1000,
    max: 3000,
    avg: 2000,
    median: 2000,
    ratePerMileMedian: 1.62
  },
  USD: {
    count: 2,
    countNonZero: 2,
    min: 800,
    max: 1200,
    avg: 1000,
    median: 1000,
    ratePerMileMedian: null
  }
};

async function mount(props = {}) {
  const el = createElement("c-lane-benchmark-stats", { is: Stats });
  Object.assign(
    el,
    {
      statsByCurrency: STATS,
      dedupedCount: 4,
      truncated: false,
      elapsedMs: 412,
      rowCount: 6
    },
    props
  );
  document.body.appendChild(el);
  await flush();
  return el;
}
const text = (el) => el.shadowRoot.textContent;
const line = (el, id) => {
  const node = el.shadowRoot.querySelector(`[data-id="${id}"]`);
  return node ? node.textContent.trim() : null;
};
const TRUCK_VIEW = {
  status: "Found",
  routeType: "Truck",
  source: "Truck route",
  miles: 1260,
  hours: 21.5,
  routes: [{ miles: 1260, hours: 21.5 }],
  mapUrl:
    "https://api.mapbox.com/styles/v1/mapbox/streets-v12/static/pin-s-a+0070d2(-73.56,45.5)/auto/600x300@2x?padding=40&access_token=pk.test",
  message: null
};

describe("c-lane-benchmark-stats", () => {
  afterEach(() => {
    while (document.body.firstChild)
      document.body.removeChild(document.body.firstChild);
  });

  it("renders one card per currency showing the lane's own cost, not selling", async () => {
    const el = await mount();
    const cards = el.shadowRoot.querySelectorAll("[data-currency]");
    expect(Array.from(cards).map((c) => c.dataset.currency)).toEqual([
      "CAD",
      "USD"
    ]);
    expect(text(el)).toContain("2,000.00"); // the CAD median itself
    expect(text(el)).toContain("4 duplicates removed");
    expect(text(el)).toContain("0.4 s");
    // selling is a separate act: no margin control and no sell figures until asked for
    expect(text(el)).not.toContain("2,300.00");
    expect(text(el)).not.toContain("Sell (median)");
    expect(el.shadowRoot.querySelector('[data-id="margin"]')).toBeNull();
    expect(el.shadowRoot.querySelector('[data-id="sell-rate"]')).toBeNull();
  });

  it("the selling button reveals the margin, the sell figures and the sell per mile", async () => {
    const el = await mount();
    el.shadowRoot.querySelector('[data-id="selling-toggle"]').click();
    await flush();
    expect(el.shadowRoot.querySelector('[data-id="margin"]')).not.toBeNull();
    expect(text(el)).toContain("2,300.00"); // CAD median 2000 * 1.15
    expect(text(el)).toContain("1,150.00"); // USD median 1000 * 1.15
    expect(text(el)).toContain("Sell per mile (median)");
    expect(el.shadowRoot.querySelector('[data-id="sell-rate"]')).not.toBeNull();
    el.shadowRoot.querySelector('[data-id="selling-toggle"]').click();
    await flush();
    expect(text(el)).not.toContain("Sell (median)");
  });

  it("20% button and free entry change the suggestion and emit marginchange", async () => {
    const el = await mount();
    el.shadowRoot.querySelector('[data-id="selling-toggle"]').click();
    await flush();
    const handler = jest.fn();
    el.addEventListener("marginchange", handler);
    el.shadowRoot.querySelector('[data-id="margin-20"]').click();
    await flush();
    expect(text(el)).toContain("2,400.00");
    expect(handler.mock.calls[0][0].detail).toEqual({ marginPct: 20 });
    const input = el.shadowRoot.querySelector('[data-id="margin"]');
    input.dispatchEvent(
      new CustomEvent("change", { detail: { value: "12.5" } })
    );
    await flush();
    expect(text(el)).toContain("2,250.00");
    input.dispatchEvent(
      new CustomEvent("change", { detail: { value: "250" } })
    );
    await flush();
    expect(text(el)).toContain("2,250.00"); // invalid input keeps the last margin
    expect(text(el)).toMatch(/0 and 100/);
  });

  it("shows the truncation notice and an empty state", async () => {
    const el = await mount({ truncated: true });
    expect(text(el)).toMatch(/first 2,?000/i);
    const empty = await mount({ statsByCurrency: {}, rowCount: 0 });
    expect(text(empty)).toContain("No quotes");
  });

  it("summary omits the dedupe segment and its separator when there are none, and singularizes one row", async () => {
    const el = await mount({ dedupedCount: 0, rowCount: 1 });
    const summary = el.shadowRoot
      .querySelector('[data-id="summary"]')
      .textContent.trim();
    expect(summary).toBe("1 row in 0.4 s");
    expect(summary.endsWith(" s")).toBe(true);
    expect(summary).not.toContain("duplicates removed");
  });

  it("shows the trip miles, the truck route, the rate per mile and the unit toggle, in miles by default", async () => {
    const el = await mount({
      medianMiles: 1234.4,
      milesCount: 3,
      routeView: TRUCK_VIEW
    });
    expect(line(el, "trip-line")).toBe("Trip: 1,234 mi · median of 3 loads");
    expect(line(el, "route-line")).toBe("Truck route: 1,260 mi · 21.5 h");
    const cad = el.shadowRoot.querySelector('[data-currency="CAD"]');
    expect(cad.textContent).toContain("Rate per mile (median)");
    expect(cad.querySelector('[data-id="rate"]').textContent.trim()).toBe(
      "1.62"
    );
    expect(
      el.shadowRoot
        .querySelector('[data-currency="USD"] [data-id="rate"]')
        .textContent.trim()
    ).toBe("—");
    expect(
      el.shadowRoot.querySelector("c-distance-unit-toggle")
    ).not.toBeNull();
  });

  it("switches the trip, the route and the rate to km", async () => {
    const el = await mount({
      medianMiles: 1234.4,
      milesCount: 1,
      routeView: TRUCK_VIEW,
      unit: "km"
    });
    expect(line(el, "trip-line")).toBe("Trip: 1,987 km · median of 1 load");
    expect(line(el, "route-line")).toBe("Truck route: 2,028 km · 21.5 h");
    const cad = el.shadowRoot.querySelector('[data-currency="CAD"]');
    expect(cad.textContent).toContain("Rate per km (median)");
    expect(cad.querySelector('[data-id="rate"]').textContent.trim()).toBe(
      "1.01"
    ); // 1.62 per mile / 1.609344
  });

  it("labels a regular route, a missing or unavailable route and a route still loading, even with no quotes", async () => {
    const regular = await mount({
      routeView: { ...TRUCK_VIEW, routeType: "Regular" }
    });
    expect(line(regular, "route-line")).toBe(
      "Regular route: 1,260 mi · 21.5 h"
    );
    expect(line(regular, "trip-line")).toBeNull();
    const unavailable = await mount({
      routeView: {
        status: "Unavailable",
        routeType: null,
        routes: [],
        mapUrl: null,
        message: "The truck route is not available right now."
      }
    });
    expect(line(unavailable, "route-line")).toBe(
      "Truck route: — · The truck route is not available right now."
    );
    const noRoute = await mount({
      routeView: {
        status: "No route",
        routeType: null,
        routes: [],
        mapUrl: null,
        message:
          "No route was found between these places, even without truck limits."
      }
    });
    expect(line(noRoute, "route-line")).toBe("Truck route: —");
    const loading = await mount({ routeView: null, routeLoading: true });
    expect(line(loading, "route-line")).toBe("Truck route: finding the route…");
    const empty = await mount({
      statsByCurrency: {},
      rowCount: 0,
      routeView: TRUCK_VIEW
    });
    expect(text(empty)).toContain("No quotes");
    expect(line(empty, "route-line")).toBe("Truck route: 1,260 mi · 21.5 h");
  });
});
