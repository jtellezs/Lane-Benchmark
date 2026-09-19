import { createElement } from "lwc";
import LaneTrendChart from "c/laneTrendChart";
import getTrend from "@salesforce/apex/LaneTrendController.getTrend";

jest.mock(
  "@salesforce/apex/LaneTrendController.getTrend",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const settle = () => Promise.resolve().then(() => Promise.resolve());

const point = (over = {}) => ({
  monthKey: "2026-01",
  label: "Jan",
  monthIndex: 0,
  count: 8,
  median: 2400,
  minimum: 2000,
  maximum: 2900,
  thin: false,
  ...over
});

const trend = (over = {}) => ({
  points: [
    point(),
    point({ monthKey: "2026-02", label: "Feb", monthIndex: 1, median: 2550 })
  ],
  currencyIsoCode: "CAD",
  lookbackDays: 365,
  monthSpan: 12,
  truncated: false,
  outsideWindow: 0,
  totalRates: 16,
  overallMedian: 2450,
  changePct: 6.2,
  firstLabel: "Jan",
  lastLabel: "Feb",
  ...over
});

// Carries a marketTestFilter so a test below can pin that the whole search request - not just
// the two lane keys - travels through to Apex (D7): a trend that dropped this would plot a
// different row set than the stats card directly above it.
const requestJson = JSON.stringify({
  originKey: "montreal|qc|ca",
  destinationKey: "toronto|on|ca",
  lookbackDays: 365,
  marketTestFilter: "EXCLUDE"
});

async function open(result, json = requestJson) {
  getTrend.mockResolvedValue(result);
  const el = createElement("c-lane-trend-chart", { is: LaneTrendChart });
  el.requestJson = json;
  document.body.appendChild(el);
  await settle();
  return el;
}

describe("c-lane-trend-chart", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("asks for the trend with the lookback the window control names, carrying the rest of the request", async () => {
    const el = await open(trend());
    expect(getTrend).toHaveBeenCalledTimes(1);
    const sent = JSON.parse(getTrend.mock.calls[0][0].requestJson);
    expect(sent.lookbackDays).toBe(365);
    expect(sent.originKey).toBe("montreal|qc|ca");
    expect(sent.marketTestFilter).toBe("EXCLUDE");
    expect(
      el.shadowRoot.querySelector('[data-id="trend-summary"]')
    ).not.toBeNull();
  });

  it("shows a loading state while the request is in flight, then clears it", async () => {
    let resolveTrend;
    getTrend.mockReturnValue(
      new Promise((resolve) => {
        resolveTrend = resolve;
      })
    );
    const el = createElement("c-lane-trend-chart", { is: LaneTrendChart });
    el.requestJson = requestJson;
    document.body.appendChild(el);
    expect(
      el.shadowRoot.querySelector('[data-id="trend-loading"]')
    ).not.toBeNull();
    expect(el.shadowRoot.querySelector('[data-id="trend-summary"]')).toBeNull();
    resolveTrend(trend());
    await settle();
    expect(el.shadowRoot.querySelector('[data-id="trend-loading"]')).toBeNull();
    expect(
      el.shadowRoot.querySelector('[data-id="trend-summary"]')
    ).not.toBeNull();
  });

  it("does not re-ask when the same request is set again", async () => {
    await open(trend());
    getTrend.mockClear();
    const el = document.body.querySelector("c-lane-trend-chart");
    el.requestJson = requestJson;
    await settle();
    expect(getTrend).not.toHaveBeenCalled();
  });

  it("re-asks with a new lookback when the window changes", async () => {
    const el = await open(trend());
    getTrend.mockClear();
    el.shadowRoot
      .querySelector('[data-id="window-3y"]')
      .dispatchEvent(new CustomEvent("click"));
    await settle();
    expect(getTrend).toHaveBeenCalledTimes(1);
    const sent = JSON.parse(getTrend.mock.calls[0][0].requestJson);
    expect(sent.lookbackDays).toBe(1095);
  });

  it("says so rather than drawing a frame when fewer than two months are usable", async () => {
    // Two points total, but one is thin: solidPoints must be filtered by `thin`, not just
    // counted by points.length, or this fixture would wrongly read as "enough".
    const el = await open(
      trend({
        points: [
          point(),
          point({
            monthKey: "2026-02",
            label: "Feb",
            monthIndex: 1,
            thin: true
          })
        ],
        changePct: null
      })
    );
    expect(el.shadowRoot.querySelector("svg")).toBeNull();
    expect(el.shadowRoot.querySelector('[data-id="trend-summary"]')).toBeNull();
    expect(
      el.shadowRoot.querySelector('[data-id="trend-empty"]').textContent
    ).toContain("not enough");
  });

  it("states the months that carry rates, not the window's calendar span", async () => {
    // monthSpan (13) is what a 365-day window touches on the calendar axis - correct for Task
    // 6's axis, wrong for this sentence. The sentence must count points.length (5) instead,
    // since that is what the reader can verify by counting dots on the chart.
    const el = await open(
      trend({
        monthSpan: 13,
        points: [
          point({ monthKey: "2025-09", label: "Sep", monthIndex: 0 }),
          point({ monthKey: "2025-10", label: "Oct", monthIndex: 1 }),
          point({ monthKey: "2025-11", label: "Nov", monthIndex: 2 }),
          point({ monthKey: "2025-12", label: "Dec", monthIndex: 3 }),
          point({ monthKey: "2026-01", label: "Jan", monthIndex: 4 })
        ]
      })
    );
    const summary = el.shadowRoot.querySelector(
      '[data-id="trend-summary"]'
    ).textContent;
    expect(summary).toContain("5 months");
    expect(summary).not.toContain("13 months");
  });

  it("warns when the window was truncated", async () => {
    const el = await open(trend({ truncated: true }));
    expect(
      el.shadowRoot.querySelector('[data-id="trend-truncated"]').textContent
    ).toContain("may be incomplete");
  });

  it("says when rows fall outside the window rather than hiding them", async () => {
    const el = await open(trend({ outsideWindow: 12 }));
    expect(
      el.shadowRoot.querySelector('[data-id="trend-outside-window"]')
        .textContent
    ).toContain("12");
  });

  it("does not mention rows outside the window when there are none", async () => {
    const el = await open(trend({ outsideWindow: 0 }));
    expect(
      el.shadowRoot.querySelector('[data-id="trend-outside-window"]')
    ).toBeNull();
  });

  it("shows the Apex error message rather than a stale trend when the call fails", async () => {
    getTrend.mockRejectedValue({
      body: { message: "The trend could not be read." }
    });
    const el = createElement("c-lane-trend-chart", { is: LaneTrendChart });
    el.requestJson = requestJson;
    document.body.appendChild(el);
    await settle();
    expect(
      el.shadowRoot.querySelector('[data-id="trend-error"]').textContent
    ).toContain("could not be read");
    expect(el.shadowRoot.querySelector('[data-id="trend-summary"]')).toBeNull();
  });

  it("stays closed when the request cannot be parsed", async () => {
    const el = await open(trend(), "{not json");
    expect(getTrend).not.toHaveBeenCalled();
    expect(
      el.shadowRoot.querySelector('[data-id="lane-trend-card"]')
    ).toBeNull();
  });

  it("stays closed when the request has no destination", async () => {
    const el = await open(
      trend(),
      JSON.stringify({ originKey: "montreal|qc|ca" })
    );
    expect(getTrend).not.toHaveBeenCalled();
    expect(
      el.shadowRoot.querySelector('[data-id="lane-trend-card"]')
    ).toBeNull();
  });
});
