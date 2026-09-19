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

  // Fixture for the drawing tests below: three real months, the middle one thin (one quote).
  // min <= median <= max on every point, including the thin one, so a coordinate mistake shows
  // up as a wrong position rather than an off-canvas point that would fail for the wrong reason.
  const threeMonthsOneThin = () =>
    trend({
      points: [
        point({
          monthKey: "2026-01",
          label: "Jan",
          monthIndex: 0,
          count: 9,
          median: 2000,
          minimum: 1800,
          maximum: 2900
        }),
        point({
          monthKey: "2026-02",
          label: "Feb",
          monthIndex: 1,
          count: 1,
          median: 2600,
          minimum: 2600,
          maximum: 2600,
          thin: true
        }),
        point({
          monthKey: "2026-03",
          label: "Mar",
          monthIndex: 2,
          count: 7,
          median: 2200,
          minimum: 1900,
          maximum: 2600
        })
      ]
    });

  it("draws one dot per month, skips the thin month on the line, and gives it a distinct hollow fill", async () => {
    const el = await open(threeMonthsOneThin());
    const dots = [...el.shadowRoot.querySelectorAll('[data-id="trend-dot"]')];
    expect(dots).toHaveLength(3);

    const hollow = dots.filter((d) => d.getAttribute("data-thin") === "true");
    const solid = dots.filter((d) => d.getAttribute("data-thin") === "false");
    expect(hollow).toHaveLength(1);
    expect(solid).toHaveLength(2);
    expect(hollow[0].querySelector("title").textContent).toContain("Feb");

    // Hollow must actually be a different, white-ish fill from a getter computed per point -
    // not the same fill on every dot, which is the mistake an earlier draft made by binding a
    // single component getter instead of a per-point value from the geometry getter.
    const hollowFill = hollow[0].getAttribute("fill");
    const solidFill = solid[0].getAttribute("fill");
    expect(hollowFill).not.toBe(solidFill);
    expect(hollowFill.toLowerCase()).toContain("fff");
    expect(solid[1].getAttribute("fill")).toBe(solidFill);

    // The line joins Jan to Mar directly: the month standing on one quote must not bend it.
    const line = el.shadowRoot.querySelector('[data-id="trend-line"]');
    expect(line.getAttribute("points").trim().split(/\s+/)).toHaveLength(2);
  });

  it("shades a min-max band that still includes the thin month's spread", async () => {
    // D5 excludes a thin month from the trend line, not from the evidence, so the band - which
    // shows spread, not trend - keeps all three months: a mistake that reused the line's filter
    // would quietly shrink the band to two vertices per side instead of three.
    const el = await open(threeMonthsOneThin());
    const band = el.shadowRoot
      .querySelector('[data-id="trend-band"]')
      .getAttribute("points")
      .trim()
      .split(/\s+/);
    expect(band).toHaveLength(6);
  });

  it("shows one table row per month with the same numbers as the chart", async () => {
    const el = await open(trend());
    const rows = el.shadowRoot.querySelectorAll('[data-id="trend-row"]');
    expect(rows).toHaveLength(2);
    const cells = (row) => [...row.children].map((td) => td.textContent);
    expect(cells(rows[0])).toEqual(["Jan", "8", "2400", "2000", "2900"]);
    expect(cells(rows[1])).toEqual(["Feb", "8", "2550", "2000", "2900"]);
    expect(
      el.shadowRoot.querySelector('[data-id="trend-table"]').className
    ).toContain("slds-assistive-text");
  });

  it("keeps a thin month's row in the table even though its dot is hollow and off the line", async () => {
    const el = await open(threeMonthsOneThin());
    const rows = el.shadowRoot.querySelectorAll('[data-id="trend-row"]');
    expect(rows).toHaveLength(3);
    const cells = (row) => [...row.children].map((td) => td.textContent);
    expect(cells(rows[1])).toEqual(["Feb", "1", "2600", "2600", "2600"]);
  });

  it("titles and describes the figure so it is not an unlabelled picture", async () => {
    const el = await open(trend());
    const svg = el.shadowRoot.querySelector("svg");
    expect(svg.getAttribute("role")).toBe("img");

    const title = el.shadowRoot.querySelector("svg title");
    expect(title.textContent).toContain("Lane trend");
    expect(title.id).toBeTruthy();
    expect(svg.getAttribute("aria-labelledby")).toBe(title.id);

    const desc = el.shadowRoot.querySelector("svg desc");
    expect(desc).not.toBeNull();
    expect(desc.textContent.trim().length).toBeGreaterThan(0);
    expect(desc.id).toBeTruthy();
    expect(svg.getAttribute("aria-describedby")).toBe(desc.id);
    // The accessible description is the same sentence printed under the chart, not a second,
    // independently-worded string that could drift from it.
    expect(desc.textContent).toBe(
      el.shadowRoot.querySelector('[data-id="trend-summary"]').textContent
    );
  });

  it("gives the svg a viewBox so it scales without a resize listener", async () => {
    const el = await open(trend());
    const viewBox = el.shadowRoot.querySelector("svg").getAttribute("viewBox");
    expect(viewBox).toMatch(/^0 0 \d+ \d+$/);
    const [, , w, h] = viewBox.split(" ").map(Number);
    expect(w).toBeGreaterThan(0);
    expect(h).toBeGreaterThan(0);
  });

  it("spaces months across the window's whole span, not just the plotted months", async () => {
    // monthIndex 0, 1 and 5 inside a 6-month span: the gap from index 1 to 5 must be four times
    // the gap from 0 to 1. A mutation that positioned dots by array index instead of monthIndex
    // would space all three evenly (ratio 1), and a mutation that sized the axis by
    // points.length (3) instead of monthSpan (6) would push month 5 off the right edge of the
    // viewBox - both are checked below.
    const el = await open(
      trend({
        monthSpan: 6,
        points: [
          point({ monthKey: "2026-01", label: "Jan", monthIndex: 0 }),
          point({ monthKey: "2026-02", label: "Feb", monthIndex: 1 }),
          point({ monthKey: "2026-06", label: "Jun", monthIndex: 5 })
        ]
      })
    );
    const dots = [...el.shadowRoot.querySelectorAll('[data-id="trend-dot"]')];
    const [cx0, cx1, cx5] = dots.map((d) => Number(d.getAttribute("cx")));
    const smallGap = cx1 - cx0;
    const bigGap = cx5 - cx1;
    expect(Math.abs(bigGap - smallGap * 4)).toBeLessThan(0.01);

    const viewBoxWidth = Number(
      el.shadowRoot.querySelector("svg").getAttribute("viewBox").split(" ")[2]
    );
    expect(cx5).toBeLessThanOrEqual(viewBoxWidth);
    expect(cx5).toBeGreaterThan(viewBoxWidth * 0.9);
  });

  // Ruling 24: every test above reads the x dimension only. These two read y.

  it("plots a higher median with a smaller cy, because SVG y grows downward", async () => {
    // Dropping the "1 -" in the y() formula would invert the chart: a rising market would draw
    // as a falling line, and nothing above this test would notice, since none of it reads cy.
    const el = await open(
      trend({
        points: [
          point({
            monthKey: "2026-01",
            label: "Jan",
            monthIndex: 0,
            median: 2000,
            minimum: 1800,
            maximum: 2200
          }),
          point({
            monthKey: "2026-02",
            label: "Feb",
            monthIndex: 1,
            median: 2800,
            minimum: 2600,
            maximum: 3000
          })
        ]
      })
    );
    const dots = [...el.shadowRoot.querySelectorAll('[data-id="trend-dot"]')];
    const cyJan = Number(dots[0].getAttribute("cy"));
    const cyFeb = Number(dots[1].getAttribute("cy"));
    expect(cyFeb).toBeLessThan(cyJan);
  });

  it("orders the band as each month's maximum going forward then each month's minimum coming back, not a bowtie", async () => {
    // The earlier band-vertex-count test only counts vertices (six), which a self-intersecting
    // polygon still has if .reverse() is dropped from `bottom`. This checks their order instead:
    // the vertex x-coordinates must trace right across the maxima, then back left across the
    // minima - the same x-coordinates the dots already sit at, since both use x(p.monthIndex).
    const el = await open(threeMonthsOneThin());
    const dotX = [
      ...el.shadowRoot.querySelectorAll('[data-id="trend-dot"]')
    ].map((d) => Number(d.getAttribute("cx")));
    const bandX = el.shadowRoot
      .querySelector('[data-id="trend-band"]')
      .getAttribute("points")
      .trim()
      .split(/\s+/)
      .map((pair) => Number(pair.split(",")[0]));
    expect(bandX).toEqual([
      dotX[0],
      dotX[1],
      dotX[2],
      dotX[2],
      dotX[1],
      dotX[0]
    ]);
  });

  // Ruling 25: monthSpan is an Apex contract, not a value to paper over.

  it("falls through to the empty state rather than drawing a misleading chart when monthSpan is missing or zero", async () => {
    // A `|| points.length` fallback would let this quietly draw a chart sized by array position
    // instead of the window - a chart that looks right but is not sized by monthSpan, which is
    // the specific wrongness Ruling 11's monthIndex contract exists to prevent. Two sequential
    // scenarios rather than a loop, so as not to await inside one.
    const withMissingSpan = await open(trend({ monthSpan: null }));
    expect(withMissingSpan.shadowRoot.querySelector("svg")).toBeNull();
    expect(
      withMissingSpan.shadowRoot.querySelector('[data-id="trend-empty"]')
    ).not.toBeNull();

    const withZeroSpan = await open(trend({ monthSpan: 0 }));
    expect(withZeroSpan.shadowRoot.querySelector("svg")).toBeNull();
    expect(
      withZeroSpan.shadowRoot.querySelector('[data-id="trend-empty"]')
    ).not.toBeNull();
  });

  it("still draws real coordinates when the window spans exactly one month", async () => {
    // monthSpan === 1 is a legitimate one-month window, not a contract violation - the
    // Math.max(monthSpan, 2) floor exists only so (span - 1) is never zero. Checking only that
    // an <svg> exists would not catch that floor being "simplified" away later: the element
    // would still render even with NaN coordinates, so this checks the coordinates themselves.
    const el = await open(
      trend({
        monthSpan: 1,
        points: [
          point({ monthKey: "2026-01", label: "Jan", monthIndex: 0 }),
          point({
            monthKey: "2026-01b",
            label: "Jan",
            monthIndex: 0,
            median: 2600
          })
        ]
      })
    );
    expect(el.shadowRoot.querySelector("svg")).not.toBeNull();
    const dots = [...el.shadowRoot.querySelectorAll('[data-id="trend-dot"]')];
    expect(dots).toHaveLength(2);
    dots.forEach((d) => {
      expect(Number.isFinite(Number(d.getAttribute("cx")))).toBe(true);
      expect(Number.isFinite(Number(d.getAttribute("cy")))).toBe(true);
    });
  });
});
