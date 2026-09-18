import { createElement } from "lwc";
import LaneBenchmarkSelling from "c/laneBenchmarkSelling";

const STATS = {
  CAD: { median: 2000, avg: 2000, ratePerMileMedian: 1.62 },
  USD: { median: 1000, avg: 1000, ratePerMileMedian: null }
};

async function flush() {
  await Promise.resolve();
  await Promise.resolve();
}

function mount(stats = STATS) {
  const el = createElement("c-lane-benchmark-selling", {
    is: LaneBenchmarkSelling
  });
  el.statsByCurrency = stats;
  el.unit = "mi";
  document.body.appendChild(el);
  return el;
}

const text = (el) => el.shadowRoot.textContent;

describe("c-lane-benchmark-selling", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("is only a button until it is asked for", () => {
    const el = mount();
    expect(
      el.shadowRoot.querySelector('[data-id="selling-toggle"]')
    ).not.toBeNull();
    expect(el.shadowRoot.querySelector("lightning-card")).toBeNull();
    expect(el.shadowRoot.querySelector('[data-id="margin"]')).toBeNull();
    expect(text(el)).not.toContain("Sell (median)");
  });

  it("shows nothing at all when the search found no statistics", () => {
    const el = mount({});
    expect(
      el.shadowRoot.querySelector('[data-id="selling-toggle"]')
    ).toBeNull();
  });

  it("opens into a card of sell figures at the default 15%", async () => {
    const el = mount();
    el.shadowRoot.querySelector('[data-id="selling-toggle"]').click();
    await flush();
    expect(el.shadowRoot.querySelector("lightning-card")).not.toBeNull();
    expect(text(el)).toContain("2,300.00"); // CAD median 2000 * 1.15
    expect(text(el)).toContain("1,150.00"); // USD median 1000 * 1.15
    expect(text(el)).toContain("Sell per mile (median)");
  });

  it("sells per mile from the lane's rate per mile, and a dash when there is none", async () => {
    const el = mount();
    el.shadowRoot.querySelector('[data-id="selling-toggle"]').click();
    await flush();
    const rates = el.shadowRoot.querySelectorAll('[data-id="sell-rate"]');
    expect(rates[0].textContent.trim()).toBe("1.86"); // 1.62 * 1.15
    expect(rates[1].textContent.trim()).toBe("—");
  });

  it("20% and free entry change the suggestion and emit marginchange", async () => {
    const el = mount();
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
    expect(text(el)).toContain("2,250.00"); // an invalid margin keeps the last one
    expect(text(el)).toMatch(/0 and 100/);
  });

  it("closes again", async () => {
    const el = mount();
    const toggle = () =>
      el.shadowRoot.querySelector('[data-id="selling-toggle"]');
    toggle().click();
    await flush();
    toggle().click();
    await flush();
    expect(el.shadowRoot.querySelector("lightning-card")).toBeNull();
  });
});
