import { createElement } from "lwc";
import Filters from "c/laneBenchmarkFilters";

const flush = () => Promise.resolve().then(() => Promise.resolve());
const OPTIONS = {
  modes: ["Truckload", "LTL"],
  equipmentByCategory: { Van: ["Dry Van 53'"], Reefer: ["Reefer 53'"] },
  currencies: ["CAD", "USD"]
};
const DEFAULTS = {
  lookbackDays: 90,
  currencyIsoCode: null,
  modes: [],
  equipmentCategories: [],
  equipmentTypes: [],
  hazmatOnly: false,
  acceptedFilter: "ANY_STATUS",
  sourceFilter: "ALL"
};

async function mount(value = DEFAULTS) {
  const el = createElement("c-lane-benchmark-filters", { is: Filters });
  el.options = OPTIONS;
  el.value = value;
  document.body.appendChild(el);
  await flush();
  return el;
}
const change = (el, id, value) =>
  el.shadowRoot
    .querySelector(`[data-id="${id}"]`)
    .dispatchEvent(new CustomEvent("change", { detail: { value } }));

describe("c-lane-benchmark-filters", () => {
  afterEach(() => {
    while (document.body.firstChild)
      document.body.removeChild(document.body.firstChild);
  });

  it("renders defaults and options", async () => {
    const el = await mount();
    expect(el.shadowRoot.querySelector('[data-id="lookback"]').value).toBe(90);
    expect(
      el.shadowRoot.querySelector('[data-id="modes"]').options.length
    ).toBe(2);
    expect(
      el.shadowRoot
        .querySelector('[data-id="categories"]')
        .options.map((o) => o.value)
    ).toEqual(["Van", "Reefer"]);
    const a = createElement("c-lane-benchmark-filters", { is: Filters });
    const b = createElement("c-lane-benchmark-filters", { is: Filters });
    document.body.appendChild(a);
    document.body.appendChild(b);
    await flush();
    expect(a.value.modes).not.toBe(b.value.modes);
  });

  it("emits the full filters object on each change and narrows equipment types by category", async () => {
    const el = await mount({
      ...DEFAULTS,
      equipmentTypes: ["Dry Van 53'", "Reefer 53'"]
    });
    const handler = jest.fn();
    el.addEventListener("filterschange", handler);
    change(el, "lookback", "365");
    change(el, "currency", "USD");
    change(el, "categories", ["Reefer"]);
    await flush();
    const last = handler.mock.calls[handler.mock.calls.length - 1][0].detail;
    expect(last).toMatchObject({
      lookbackDays: 365,
      currencyIsoCode: "USD",
      equipmentCategories: ["Reefer"],
      equipmentTypes: ["Reefer 53'"]
    });
    expect(last.equipmentTypes).not.toContain("Dry Van 53'");
    expect(
      el.shadowRoot
        .querySelector('[data-id="types"]')
        .options.map((o) => o.value)
    ).toEqual(["Reefer 53'"]);
    change(el, "accepted", "ACCEPTED");
    change(el, "flags", ["hazmatOnly"]);
    await flush();
    const final = handler.mock.calls[handler.mock.calls.length - 1][0].detail;
    expect(final.acceptedFilter).toBe("ACCEPTED");
    expect(final.hazmatOnly).toBe(true);
    expect(final).not.toHaveProperty("marketTestOnly");
  });

  it("offers Hazmat only as the only flag: Market Test quotes are never searched", async () => {
    const el = await mount();
    expect(
      el.shadowRoot
        .querySelector('[data-id="flags"]')
        .options.map((o) => o.value)
    ).toEqual(["hazmatOnly"]);
    expect(el.value).not.toHaveProperty("marketTestOnly");
  });

  it("rejects a non-positive lookback and keeps the previous value", async () => {
    const el = await mount();
    const handler = jest.fn();
    el.addEventListener("filterschange", handler);
    const input = el.shadowRoot.querySelector('[data-id="lookback"]');
    input.value = "0";
    input.dispatchEvent(new CustomEvent("change", { detail: { value: "0" } }));
    await flush();
    expect(
      handler.mock.calls[handler.mock.calls.length - 1][0].detail.lookbackDays
    ).toBe(90);
    expect(input.value).toBe(90);
  });

  it("emits the source filter and defaults it to ALL", async () => {
    const el = await mount();
    expect(el.shadowRoot.querySelector('[data-id="source"]').value).toBe("ALL");
    const handler = jest.fn();
    el.addEventListener("filterschange", handler);
    change(el, "source", "BIDS");
    await flush();
    expect(handler.mock.calls[0][0].detail.sourceFilter).toBe("BIDS");
  });

  it("restores a saved value without sourceFilter as ALL", async () => {
    const { sourceFilter, ...legacy } = DEFAULTS;
    expect(sourceFilter).toBe("ALL");
    const el = await mount(legacy);
    expect(el.shadowRoot.querySelector('[data-id="source"]').value).toBe("ALL");
  });

  it("apply, reset and clear-saved raise their events; reset restores defaults", async () => {
    const el = await mount({ ...DEFAULTS, lookbackDays: 30, modes: ["LTL"] });
    const apply = jest.fn();
    const reset = jest.fn();
    const clear = jest.fn();
    const changed = jest.fn();
    el.addEventListener("apply", apply);
    el.addEventListener("reset", reset);
    el.addEventListener("clearsaved", clear);
    el.addEventListener("filterschange", changed);
    el.shadowRoot.querySelector('[data-id="apply"]').click();
    el.shadowRoot.querySelector('[data-id="reset"]').click();
    el.shadowRoot.querySelector('[data-id="clear-saved"]').click();
    await flush();
    expect(apply).toHaveBeenCalledTimes(1);
    expect(reset).toHaveBeenCalledTimes(1);
    expect(clear).toHaveBeenCalledTimes(1);
    expect(changed.mock.calls[changed.mock.calls.length - 1][0].detail).toEqual(
      DEFAULTS
    );
  });
});
