import { createElement } from "lwc";
import PlacePicker from "c/laneBenchmarkPlacePicker";
import searchPlaces from "@salesforce/apex/LaneBenchmarkController.searchPlaces";
import geocode from "@salesforce/apex/LaneBenchmarkController.geocode";

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
const OPTIONS = [
  {
    key: "montreal|qc|ca",
    label: "Montréal, QC, CA",
    loadCount: 900,
    source: "Locations"
  },
  {
    key: "montmagny|qc|ca",
    label: "Montmagny, QC, CA",
    loadCount: 12,
    source: "Locations"
  }
];

async function mount(props = {}) {
  const el = createElement("c-lane-benchmark-place-picker", {
    is: PlacePicker
  });
  Object.assign(el, { label: "Origin", precision: "CITY", unit: "MI" }, props);
  document.body.appendChild(el);
  await flush();
  return el;
}

function type(el, text) {
  const input = el.shadowRoot.querySelector('lightning-input[data-id="term"]');
  input.value = text;
  input.dispatchEvent(new CustomEvent("change", { detail: { value: text } }));
}

function pressKey(el, key) {
  const picker = el.shadowRoot.querySelector(".picker");
  picker.dispatchEvent(new KeyboardEvent("keydown", { key, cancelable: true }));
}

describe("c-lane-benchmark-place-picker", () => {
  beforeEach(() => {
    jest.useFakeTimers();
    searchPlaces.mockResolvedValue(OPTIONS);
    geocode.mockResolvedValue([]);
  });
  afterEach(() => {
    jest.useRealTimers();
    while (document.body.firstChild)
      document.body.removeChild(document.body.firstChild);
    jest.clearAllMocks();
  });

  it("debounces typing and lists options with load counts", async () => {
    const el = await mount();
    type(el, "mo");
    type(el, "mon");
    jest.advanceTimersByTime(250);
    await flush();
    await flush();
    expect(searchPlaces).toHaveBeenCalledTimes(1);
    expect(searchPlaces).toHaveBeenCalledWith({ term: "mon", limitCount: 10 });
    const items = el.shadowRoot.querySelectorAll("li[data-key]");
    expect(items.length).toBe(2);
    expect(items[0].textContent).toContain("Montréal, QC, CA");
    expect(items[0].textContent).toContain("900");
  });

  it("emits placechange with the picked key and closes the list", async () => {
    const el = await mount();
    const handler = jest.fn();
    el.addEventListener("placechange", handler);
    type(el, "mon");
    jest.advanceTimersByTime(250);
    await flush();
    await flush();
    el.shadowRoot.querySelector('li[data-key="montreal|qc|ca"]').click();
    await flush();
    expect(handler).toHaveBeenCalledTimes(1);
    expect(handler.mock.calls[0][0].detail).toEqual({
      key: "montreal|qc|ca",
      label: "Montréal, QC, CA",
      precision: "CITY",
      radius: null,
      unit: "MI"
    });
    expect(el.shadowRoot.querySelectorAll("li[data-key]").length).toBe(0);
  });

  it("shows radius controls only for RADIUS and emits radius changes", async () => {
    const el = await mount({
      value: "montreal|qc|ca",
      valueLabel: "Montréal, QC, CA"
    });
    expect(
      el.shadowRoot.querySelector('lightning-input[data-id="radius"]')
    ).toBeNull();
    const handler = jest.fn();
    el.addEventListener("placechange", handler);
    const precision = el.shadowRoot.querySelector(
      'lightning-combobox[data-id="precision"]'
    );
    precision.dispatchEvent(
      new CustomEvent("change", { detail: { value: "RADIUS" } })
    );
    await flush();
    const radius = el.shadowRoot.querySelector(
      'lightning-input[data-id="radius"]'
    );
    expect(radius).not.toBeNull();
    radius.dispatchEvent(
      new CustomEvent("change", { detail: { value: "75" } })
    );
    await flush();
    const last = handler.mock.calls[handler.mock.calls.length - 1][0].detail;
    expect(last).toMatchObject({
      key: "montreal|qc|ca",
      precision: "RADIUS",
      radius: 75,
      unit: "MI"
    });
  });

  it("falls back to the map search on the footer action", async () => {
    geocode.mockResolvedValue([
      {
        key: "saguenay|qc|ca",
        label: "Saguenay, QC, CA",
        loadCount: 0,
        source: "Mapbox"
      }
    ]);
    const el = await mount();
    type(el, "sague");
    jest.advanceTimersByTime(250);
    await flush();
    await flush();
    el.shadowRoot.querySelector('button[data-id="map-search"]').click();
    await flush();
    await flush();
    expect(geocode).toHaveBeenCalledWith({ query: "sague", countryHint: null });
    const item = el.shadowRoot.querySelector('li[data-key="saguenay|qc|ca"]');
    expect(item).not.toBeNull();
    expect(item.textContent).toContain("Mapbox");
  });

  it("clear button empties the value and emits", async () => {
    const el = await mount({
      value: "montreal|qc|ca",
      valueLabel: "Montréal, QC, CA"
    });
    const handler = jest.fn();
    el.addEventListener("placechange", handler);
    el.shadowRoot.querySelector('button[data-id="clear"]').click();
    await flush();
    expect(handler.mock.calls[0][0].detail.key).toBeNull();
  });

  it("ignores a pending debounce when the parent sets a value mid-type", async () => {
    const el = await mount();
    type(el, "mon");
    el.value = "toronto|on|ca";
    el.valueLabel = "Toronto, ON, CA";
    jest.runOnlyPendingTimers();
    await flush();
    await flush();
    expect(searchPlaces).not.toHaveBeenCalled();
    expect(el.shadowRoot.querySelectorAll("li[data-key]").length).toBe(0);
  });

  it("clears the pending debounce timer on disconnect", async () => {
    const el = await mount();
    type(el, "mon");
    document.body.removeChild(el);
    jest.runOnlyPendingTimers();
    await flush();
    await flush();
    expect(searchPlaces).not.toHaveBeenCalled();
  });

  it("keyboard: ArrowDown twice then Enter picks the second option", async () => {
    const el = await mount();
    const handler = jest.fn();
    el.addEventListener("placechange", handler);
    type(el, "mon");
    jest.advanceTimersByTime(250);
    await flush();
    await flush();
    pressKey(el, "ArrowDown");
    pressKey(el, "ArrowDown");
    pressKey(el, "Enter");
    await flush();
    expect(handler).toHaveBeenCalledTimes(1);
    expect(handler.mock.calls[0][0].detail.key).toBe("montmagny|qc|ca");
  });

  it("keyboard: Escape closes the list", async () => {
    const el = await mount();
    type(el, "mon");
    jest.advanceTimersByTime(250);
    await flush();
    await flush();
    expect(el.shadowRoot.querySelectorAll("li[data-key]").length).toBe(2);
    pressKey(el, "Escape");
    await flush();
    expect(el.shadowRoot.querySelectorAll("li[data-key]").length).toBe(0);
  });

  it("keyboard: ArrowUp at the first option stays at index 0", async () => {
    const el = await mount();
    const handler = jest.fn();
    el.addEventListener("placechange", handler);
    type(el, "mon");
    jest.advanceTimersByTime(250);
    await flush();
    await flush();
    pressKey(el, "ArrowDown"); // -1 -> 0
    pressKey(el, "ArrowUp"); // stays at 0
    pressKey(el, "ArrowUp"); // stays at 0
    pressKey(el, "Enter");
    await flush();
    expect(handler.mock.calls[0][0].detail.key).toBe("montreal|qc|ca");
  });

  it("ignores a second rapid click on the map search button while one is pending", async () => {
    let resolveGeocode;
    geocode.mockImplementationOnce(
      () =>
        new Promise((resolve) => {
          resolveGeocode = resolve;
        })
    );
    const el = await mount();
    type(el, "sague");
    jest.advanceTimersByTime(250);
    await flush();
    await flush();
    const btn = el.shadowRoot.querySelector('button[data-id="map-search"]');
    btn.click();
    btn.click();
    expect(geocode).toHaveBeenCalledTimes(1);
    resolveGeocode([]);
    await flush();
    await flush();
  });

  it("ignores a stale search response that resolves after a newer one", async () => {
    let resolveFirst;
    let resolveSecond;
    searchPlaces
      .mockImplementationOnce(
        () =>
          new Promise((resolve) => {
            resolveFirst = resolve;
          })
      )
      .mockImplementationOnce(
        () =>
          new Promise((resolve) => {
            resolveSecond = resolve;
          })
      );
    const el = await mount();
    type(el, "mo");
    jest.advanceTimersByTime(250);
    await flush();
    type(el, "mon");
    jest.advanceTimersByTime(250);
    await flush();
    expect(searchPlaces).toHaveBeenCalledTimes(2);
    resolveSecond([OPTIONS[1]]);
    await flush();
    await flush();
    resolveFirst([OPTIONS[0]]);
    await flush();
    await flush();
    const items = el.shadowRoot.querySelectorAll("li[data-key]");
    expect(items.length).toBe(1);
    expect(items[0].dataset.key).toBe("montmagny|qc|ca");
  });
});
