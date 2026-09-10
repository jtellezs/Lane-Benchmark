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
    median: 2000
  },
  USD: {
    count: 2,
    countNonZero: 2,
    min: 800,
    max: 1200,
    avg: 1000,
    median: 1000
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

describe("c-lane-benchmark-stats", () => {
  afterEach(() => {
    while (document.body.firstChild)
      document.body.removeChild(document.body.firstChild);
  });

  it("renders one card per currency with suggested sell at the default 15%", async () => {
    const el = await mount();
    const cards = el.shadowRoot.querySelectorAll("[data-currency]");
    expect(Array.from(cards).map((c) => c.dataset.currency)).toEqual([
      "CAD",
      "USD"
    ]);
    expect(text(el)).toContain("2,300.00"); // CAD median 2000 * 1.15
    expect(text(el)).toContain("1,150.00"); // USD median 1000 * 1.15
    expect(text(el)).toContain("4 duplicates removed");
    expect(text(el)).toContain("0.4 s");
  });

  it("20% button and free entry change the suggestion and emit marginchange", async () => {
    const el = await mount();
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
});
