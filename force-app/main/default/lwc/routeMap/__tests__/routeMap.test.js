import { createElement } from "lwc";
import RouteMap from "c/routeMap";

const flush = () => Promise.resolve().then(() => Promise.resolve());
const field = (el, id) => el.shadowRoot.querySelector(`[data-id="${id}"]`);
const text = (el, id) => field(el, id).textContent.trim();
const legendLines = (el) =>
  [...el.shadowRoot.querySelectorAll('[data-id="legend-line"]')].map((n) =>
    n.textContent.trim()
  );

const MAP_URL =
  "https://api.mapbox.com/styles/v1/mapbox/streets-v12/static/pin-s-a+0070d2(-73.5674,45.5019),pin-s-b+2e844a(-79.3832,43.6532)/auto/600x300@2x?padding=40&access_token=pk.test";

const TRUCK = {
  status: "Found",
  routeType: "Truck",
  source: "Truck route",
  miles: 1234,
  hours: 21.5,
  routes: [
    { miles: 1234, hours: 21.5 },
    { miles: 1260.4, hours: 22 },
    { miles: 1301, hours: 23.2 }
  ],
  mapUrl: MAP_URL,
  message: null
};

const REGULAR = {
  ...TRUCK,
  routeType: "Regular",
  routes: [{ miles: 1234, hours: 21.5 }]
};

async function mount(props = {}) {
  const el = createElement("c-route-map", { is: RouteMap });
  Object.assign(el, props);
  document.body.appendChild(el);
  await flush();
  return el;
}

describe("c-route-map", () => {
  beforeEach(() => {
    window.localStorage.clear();
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("draws the map and a truck legend with every route in miles", async () => {
    const el = await mount({ view: TRUCK, unit: "mi" });
    expect(field(el, "image").src).toBe(MAP_URL);
    expect(field(el, "image").alt).toBe("Truck route from A to B on a map");
    expect(text(el, "legend-title")).toBe("Truck route");
    expect(legendLines(el)).toEqual([
      "Route 1: 1,234 mi · 21.5 h",
      "Route 2: 1,260 mi · 22.0 h",
      "Route 3: 1,301 mi · 23.2 h"
    ]);
    const swatches = [...el.shadowRoot.querySelectorAll(".swatch")].map(
      (n) => n.className
    );
    expect(swatches).toEqual([
      "swatch swatch-1",
      "swatch swatch-2",
      "swatch swatch-3"
    ]);
    expect(field(el, "message")).toBeNull();
    expect(field(el, "spinner")).toBeNull();
    expect(field(el, "hazmat")).toBeNull();
  });

  it("labels a regular route and follows the unit it is given", async () => {
    const el = await mount({ view: REGULAR, unit: "km" });
    expect(text(el, "legend-title")).toBe(
      "Regular route — truck limits could not be met"
    );
    expect(legendLines(el)).toEqual(["Route 1: 1,986 km · 21.5 h"]);
    el.unit = "mi";
    await flush();
    expect(legendLines(el)).toEqual(["Route 1: 1,234 mi · 21.5 h"]);
  });

  it("starts from the unit this browser remembered when the parent passes none", async () => {
    window.localStorage.setItem("tripMiles.unit.v1", "km");
    const el = await mount({ view: REGULAR });
    expect(el.unit).toBe("km");
    expect(legendLines(el)).toEqual(["Route 1: 1,986 km · 21.5 h"]);
  });

  it("shows no more than three routes and a dash for a route without miles", async () => {
    const el = await mount({
      view: {
        ...TRUCK,
        routes: [
          { miles: null, hours: null },
          { miles: 10, hours: 0.2 },
          { miles: 11, hours: 0.3 },
          { miles: 12, hours: 0.4 }
        ]
      },
      unit: "mi"
    });
    expect(legendLines(el)).toEqual([
      "Route 1: —",
      "Route 2: 10 mi · 0.2 h",
      "Route 3: 11 mi · 0.3 h"
    ]);
  });

  it("says the truck route is unavailable, with the server's message when there is one", async () => {
    const el = await mount({
      view: {
        status: "Unavailable",
        routeType: null,
        routes: [],
        mapUrl: null,
        message: null
      }
    });
    expect(text(el, "message")).toBe(
      "The truck route is not available right now."
    );
    expect(field(el, "image")).toBeNull();
    expect(field(el, "legend-title")).toBeNull();
    expect(field(el, "refresh")).not.toBeNull();
    el.view = {
      status: "Unavailable",
      routeType: null,
      routes: [],
      mapUrl: null,
      message: "This lane has no coordinates."
    };
    await flush();
    expect(text(el, "message")).toBe("This lane has no coordinates.");
  });

  it("says when no route exists between the places", async () => {
    const el = await mount({
      view: {
        status: "No route",
        routeType: null,
        routes: [],
        mapUrl: null,
        message: null
      }
    });
    expect(text(el, "message")).toBe(
      "No route was found between these places, even without truck limits."
    );
    expect(field(el, "legend-title")).toBeNull();
  });

  it("shows a spinner and blocks Refresh route while loading", async () => {
    const el = await mount({ view: TRUCK, loading: true });
    expect(field(el, "spinner")).not.toBeNull();
    expect(field(el, "refresh").disabled).toBe(true);
    const seen = [];
    el.addEventListener("refreshroute", (e) => seen.push(e));
    field(el, "refresh").click();
    expect(seen).toHaveLength(0);
    el.loading = false;
    await flush();
    expect(field(el, "spinner")).toBeNull();
    expect(field(el, "refresh").disabled).toBe(false);
  });

  it("shows a spinner before the first view arrives", async () => {
    const el = await mount({ view: null, loading: true });
    expect(field(el, "spinner")).not.toBeNull();
    expect(field(el, "refresh")).toBeNull();
    expect(field(el, "image")).toBeNull();
  });

  it("asks its parent to refresh the route", async () => {
    const el = await mount({ view: TRUCK });
    const seen = [];
    el.addEventListener("refreshroute", (e) => seen.push(e));
    const refresh = field(el, "refresh");
    expect(refresh.label).toBe("Refresh route");
    refresh.click();
    expect(seen).toHaveLength(1);
    expect(seen[0].bubbles).toBe(false);
    expect(seen[0].detail).toBeNull();
  });

  it("notes that a hazmat lane gets the same route", async () => {
    const el = await mount({ view: TRUCK, hazmat: true });
    expect(text(el, "hazmat")).toContain("Mapbox has no hazmat routing");
    el.hazmat = false;
    await flush();
    expect(field(el, "hazmat")).toBeNull();
  });

  it("renders nothing without a view", async () => {
    const el = await mount();
    expect(field(el, "image")).toBeNull();
    expect(field(el, "message")).toBeNull();
    expect(field(el, "legend-title")).toBeNull();
    expect(field(el, "refresh")).toBeNull();
    expect(field(el, "spinner")).toBeNull();
  });
});
