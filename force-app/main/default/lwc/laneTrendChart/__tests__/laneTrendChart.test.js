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
  bucketKey: "2026-01",
  label: "Jan",
  bucketIndex: 0,
  count: 8,
  median: 2400,
  minimum: 2000,
  maximum: 2900,
  thin: false,
  ...over
});

// bucketUnit defaults to "month" because every other default here is month-shaped: a 365-day
// lookback (which Apex's own mapping puts at month) and bucket keys/labels ("2026-01", "Jan")
// that only make sense as calendar months. A test that needs a different unit overrides it, and
// the fixture then has to override the shape that goes with it.
const trend = (over = {}) => ({
  points: [
    point(),
    point({ bucketKey: "2026-02", label: "Feb", bucketIndex: 1, median: 2550 })
  ],
  currencyIsoCode: "CAD",
  lookbackDays: 365,
  bucketSpan: 12,
  bucketUnit: "month",
  truncated: false,
  totalRates: 16,
  overallMedian: 2450,
  changePct: 6.2,
  firstLabel: "Jan",
  lastLabel: "Feb",
  ...over
});

const MONTH_NAMES = [
  "Jan",
  "Feb",
  "Mar",
  "Apr",
  "May",
  "Jun",
  "Jul",
  "Aug",
  "Sep",
  "Oct",
  "Nov",
  "Dec"
];

// W4 fixture: a real three-year, month-bucketed window. bucketKey must be unique across the
// whole range - a naive `(i % 12) + 1` generator repeats the same 12 keys three times over and
// for:each would collide on them - so this walks the calendar forward from Sep 2023 (36 months
// before this month, 2026-09) instead of wrapping a bare month number. label is derived from the
// same calendar math as bucketKey so the fixture is a label/bucketKey pair Apex could actually
// emit, not a bucketKey with an unrelated "Jan" stapled to every entry.
// The day-bucketed counterpart of manyPoints, for the two windows whose daily point counts are
// dense enough to thin: two weeks (14) and one month (30). Keys and labels come from the same walk
// so each point is a pair Apex's keyOf/labelOf would really emit - YYYY-MM-DD with a "D Mon" label
// - rather than a day key wearing a month's name.
const manyDayPoints = (n) =>
  Array.from({ length: n }, (_, i) => {
    const d = new Date(Date.UTC(2026, 0, 1 + i));
    const month = d.getUTCMonth();
    return point({
      bucketKey: `2026-${String(month + 1).padStart(2, "0")}-${String(
        d.getUTCDate()
      ).padStart(2, "0")}`,
      bucketIndex: i,
      label: `${d.getUTCDate()} ${MONTH_NAMES[month]}`
    });
  });

const manyPoints = (n) =>
  Array.from({ length: n }, (_, i) => {
    const monthIndex0 = 8 + i; // Sep 2023 is month index 8 of year 2023
    const year = 2023 + Math.floor(monthIndex0 / 12);
    const month = (monthIndex0 % 12) + 1;
    return point({
      bucketKey: `${year}-${String(month).padStart(2, "0")}`,
      bucketIndex: i,
      label: MONTH_NAMES[month - 1]
    });
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
      .querySelector('[data-id="window-6m"]')
      .dispatchEvent(new CustomEvent("click"));
    await settle();
    expect(getTrend).toHaveBeenCalledTimes(1);
    const sent = JSON.parse(getTrend.mock.calls[0][0].requestJson);
    expect(sent.lookbackDays).toBe(182);
  });

  it("offers all nine windows, shortest first", async () => {
    const el = await open(trend());
    const keys = [...el.shadowRoot.querySelectorAll("[data-window]")].map(
      (b) => b.dataset.window
    );
    expect(keys).toEqual([
      "1w",
      "2w",
      "1m",
      "2m",
      "3m",
      "6m",
      "1y",
      "2y",
      "3y"
    ]);
  });

  // Extended to all nine windows (previously only 1w, 3m and 3y were checked) so a typo in any
  // one window's `days` - 14, 30, 60 and 730 were previously untested - is caught. Mutation
  // (observed): change WINDOWS' "2y" entry from 730 to 720; the sent("2y") assertion fails.
  it("sends each window its own lookback", async () => {
    const el = await open(trend());
    const sent = async (key) => {
      getTrend.mockClear();
      el.shadowRoot
        .querySelector(`[data-id="window-${key}"]`)
        .dispatchEvent(new CustomEvent("click"));
      await settle();
      return JSON.parse(getTrend.mock.calls[0][0].requestJson).lookbackDays;
    };
    expect(await sent("1w")).toBe(7);
    expect(await sent("2w")).toBe(14);
    expect(await sent("1m")).toBe(30);
    expect(await sent("2m")).toBe(60);
    expect(await sent("3m")).toBe(90);
    expect(await sent("6m")).toBe(182);
    expect(await sent("1y")).toBe(365);
    expect(await sent("2y")).toBe(730);
    expect(await sent("3y")).toBe(1095);
  });

  // The last review proved by mutation that hard-coding every button's aria-pressed to "true"
  // still passes the whole suite - nothing asserted the "false" side. This checks both: the
  // selected button is "true" and every other button is "false", then clicks a different window
  // and checks the states swap rather than accumulate. Mutation (observed): hard-code
  // `ariaPressed: selected ? "true" : "false"` to `ariaPressed: "true"` in the `windows` getter -
  // the unselected-button assertions fail. A second mutation (observed): comment out
  // `this.windowKey = key;` in `handleWindow` so the selection never updates - the two
  // post-click assertions fail (6m stays "false", 1y stays "true").
  it("marks only the selected window button as pressed, not every button, and swaps which one on click", async () => {
    const el = await open(trend());
    const pressedOf = (key) =>
      el.shadowRoot
        .querySelector(`[data-id="window-${key}"]`)
        .getAttribute("aria-pressed");

    expect(pressedOf("1y")).toBe("true");
    ["1w", "2w", "1m", "2m", "3m", "6m", "2y", "3y"].forEach((key) => {
      expect(pressedOf(key)).toBe("false");
    });

    el.shadowRoot
      .querySelector('[data-id="window-6m"]')
      .dispatchEvent(new CustomEvent("click"));
    await settle();

    expect(pressedOf("6m")).toBe("true");
    expect(pressedOf("1y")).toBe("false");
  });

  it("names the unit in the caption, so a count of days is not read as months", async () => {
    const el = await open(
      trend({
        bucketUnit: "day",
        // Both points carry day-shaped keys and "D Mon" labels. The default point() is month-shaped
        // ("Jan" on a 2026-01 key), which Apex's labelOf could never emit for a day bucket.
        points: [
          point({ bucketKey: "2026-01-01", label: "1 Jan" }),
          point({ bucketKey: "2026-01-02", bucketIndex: 1, label: "2 Jan" })
        ]
      })
    );
    expect(
      el.shadowRoot.querySelector('[data-id="trend-summary"]').textContent
    ).toContain("2 days");
  });

  it("says so rather than drawing a frame when fewer than two months are usable", async () => {
    // Two points total, but one is thin: solidPoints must be filtered by `thin`, not just
    // counted by points.length, or this fixture would wrongly read as "enough".
    const el = await open(
      trend({
        points: [
          point(),
          point({
            bucketKey: "2026-02",
            label: "Feb",
            bucketIndex: 1,
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
    // bucketSpan (13) is what a 365-day window touches on the calendar axis - correct for Task
    // 6's axis, wrong for this sentence. The sentence must count points.length (5) instead,
    // since that is what the reader can verify by counting dots on the chart.
    const el = await open(
      trend({
        bucketSpan: 13,
        points: [
          point({ bucketKey: "2025-09", label: "Sep", bucketIndex: 0 }),
          point({ bucketKey: "2025-10", label: "Oct", bucketIndex: 1 }),
          point({ bucketKey: "2025-11", label: "Nov", bucketIndex: 2 }),
          point({ bucketKey: "2025-12", label: "Dec", bucketIndex: 3 }),
          point({ bucketKey: "2026-01", label: "Jan", bucketIndex: 4 })
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

  // The window control fires load() on every click and the answers come back on their own
  // schedule: getTrend is cacheable, so a window already in the cache resolves almost at once
  // while an uncached one waits for a round trip. Without a generation token the late answer wins
  // whatever the pricer last asked for, and the chart, the highlighted button and the caption stop
  // agreeing with each other. Mutation: drop the `ticket === this.loadTicket` guards in
  // laneTrendChart.load() and the assertions below read the six-month answer under the 1-year
  // button.
  it("keeps the answer to the window last clicked when a slower earlier request lands after it", async () => {
    const slowSixMonth = trend({ lookbackDays: 182, totalRates: 900 });
    const fastOneYear = trend({ lookbackDays: 365, totalRates: 16 });
    let resolveSixMonth;
    getTrend
      // the card's own first load, on the default 1-year window
      .mockReturnValueOnce(Promise.resolve(fastOneYear))
      // 6 months: uncached, held back until after the click that follows
      .mockReturnValueOnce(
        new Promise((resolve) => {
          resolveSixMonth = resolve;
        })
      )
      // 1 year again: already cached, so it answers at once
      .mockReturnValueOnce(Promise.resolve(fastOneYear));

    const el = createElement("c-lane-trend-chart", { is: LaneTrendChart });
    el.requestJson = requestJson;
    document.body.appendChild(el);
    await settle();

    // 6 months first (its answer is held back), then 1 year, whose answer lands immediately.
    el.shadowRoot
      .querySelector('[data-id="window-6m"]')
      .dispatchEvent(new CustomEvent("click"));
    await settle();
    el.shadowRoot
      .querySelector('[data-id="window-1y"]')
      .dispatchEvent(new CustomEvent("click"));
    await settle();
    resolveSixMonth(slowSixMonth);
    await settle();
    await settle();

    expect(
      el.shadowRoot
        .querySelector('[data-id="window-1y"]')
        .getAttribute("aria-pressed")
    ).toBe("true");
    expect(
      el.shadowRoot.querySelector('[data-id="trend-summary"]').textContent
    ).toContain("16 rates");
    expect(
      el.shadowRoot.querySelector('[data-id="trend-summary"]').textContent
    ).not.toContain("900 rates");
    expect(el.shadowRoot.querySelector('[data-id="trend-loading"]')).toBeNull();
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
          bucketKey: "2026-01",
          label: "Jan",
          bucketIndex: 0,
          count: 9,
          median: 2000,
          minimum: 1800,
          maximum: 2900
        }),
        point({
          bucketKey: "2026-02",
          label: "Feb",
          bucketIndex: 1,
          count: 1,
          median: 2600,
          minimum: 2600,
          maximum: 2600,
          thin: true
        }),
        point({
          bucketKey: "2026-03",
          label: "Mar",
          bucketIndex: 2,
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

  // The assistive table is the screen-reader equivalent of the SVG axis, so its column header is
  // the only name a non-sighted user gets for the bucket column - a hard-coded "Month" is simply
  // wrong for a day- or week-bucketed chart. Fixtures use real day/week shapes (Apex's
  // labelOf/keyOf: "D Mon" labels, ISO-Monday week keys) rather than reusing the month-shaped
  // point() defaults, per the brief's warning against a response Apex cannot produce. Mutation
  // (observed): hard-code the header getter to always return "Month" - the day and week
  // assertions below fail.
  it("names the actual bucket unit in the assistive table's header, not always 'Month'", async () => {
    const dayEl = await open(
      trend({
        bucketUnit: "day",
        lookbackDays: 14,
        bucketSpan: 14,
        points: [
          point({ bucketKey: "2026-01-05", label: "5 Jan", bucketIndex: 0 }),
          point({ bucketKey: "2026-01-06", label: "6 Jan", bucketIndex: 1 })
        ]
      })
    );
    expect(
      dayEl.shadowRoot.querySelectorAll('[data-id="trend-table"] th')[0]
        .textContent
    ).toBe("Day");

    const weekEl = await open(
      trend({
        bucketUnit: "week",
        lookbackDays: 90,
        bucketSpan: 13,
        points: [
          point({ bucketKey: "2026-01-05", label: "5 Jan", bucketIndex: 0 }),
          point({ bucketKey: "2026-01-12", label: "12 Jan", bucketIndex: 1 })
        ]
      })
    );
    expect(
      weekEl.shadowRoot.querySelectorAll('[data-id="trend-table"] th')[0]
        .textContent
    ).toBe("Week");

    const monthEl = await open(trend());
    expect(
      monthEl.shadowRoot.querySelectorAll('[data-id="trend-table"] th')[0]
        .textContent
    ).toBe("Month");
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
    // bucketIndex 0, 1 and 5 inside a 6-month span: the gap from index 1 to 5 must be four times
    // the gap from 0 to 1. A mutation that positioned dots by array index instead of bucketIndex
    // would space all three evenly (ratio 1), and a mutation that sized the axis by
    // points.length (3) instead of bucketSpan (6) would push month 5 off the right edge of the
    // viewBox - both are checked below.
    const el = await open(
      trend({
        bucketSpan: 6,
        points: [
          point({ bucketKey: "2026-01", label: "Jan", bucketIndex: 0 }),
          point({ bucketKey: "2026-02", label: "Feb", bucketIndex: 1 }),
          point({ bucketKey: "2026-06", label: "Jun", bucketIndex: 5 })
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

  // W4: 37 monthly labels at three years, or 30 daily ones at a month, collide at 11px in a
  // 572-unit plot. The axis must thin to about a dozen, evenly spaced, positioned labels.
  // Mutation (observed): remove the `i % step !== 0` guard - labels.length climbs to 37 and the
  // count assertion fails. Mutation (observed): drop `y: AXIS_LABEL_Y` from the pushed axis
  // object - the "not null" assertion below fails (a first attempt here checked only
  // Number.isFinite(Number(y)), which a missing attribute passes vacuously: getAttribute returns
  // null, and Number(null) is 0, a finite number - exactly the kind of test that cannot fail for
  // the reason it names).
  it("never draws more than about a dozen axis labels, however many buckets there are, and positions every one of them", async () => {
    const el = await open(
      trend({ points: manyPoints(37), bucketSpan: 37, bucketUnit: "month" })
    );
    const labels = el.shadowRoot.querySelectorAll('[data-id="axis-label"]');
    const points = manyPoints(37);
    expect(labels.length).toBeGreaterThan(0);
    expect(labels.length).toBeLessThanOrEqual(12);
    // Both ends, not just the count. An axis that drops an end reads as a window shorter than the
    // one the reader asked for, and nothing on the chart contradicts it.
    expect(labels[0].textContent).toContain(points[0].label);
    expect(labels[labels.length - 1].textContent).toContain(points[36].label);
    [...labels].forEach((l) => {
      // getAttribute returns null, not "0", for a missing attribute - and Number(null) is 0,
      // which Number.isFinite would wrongly accept, so the null case is checked explicitly.
      const y = l.getAttribute("y");
      expect(y).not.toBeNull();
      expect(Number.isFinite(Number(y))).toBe(true);
    });
  });

  // Mutation (observed): restore the old `i % step !== 0` selection - at both 14 and 30 points
  // `(n - 1) % step !== 0`, so the last point's label is never emitted and the final assertion
  // fails. These two counts are not arbitrary: they are the daily bucket counts of the two-week and
  // one-month windows, the only two of the nine where the old rule dropped an end.
  it.each([
    ["two weeks", 14],
    ["one month", 30]
  ])(
    "keeps the most recent bucket's label at %s, where an evenly-stepped axis would have dropped it",
    async (_name, n) => {
      const points = manyDayPoints(n);
      const el = await open(
        trend({ points, bucketSpan: n, bucketUnit: "day" })
      );
      const labels = el.shadowRoot.querySelectorAll('[data-id="axis-label"]');
      expect(labels.length).toBeLessThanOrEqual(12);
      expect(labels[0].textContent).toContain(points[0].label);
      expect(labels[labels.length - 1].textContent).toContain(
        points[n - 1].label
      );
    }
  );

  // Mutation (observed): drop the `year === lastYear` check (always prefix the year) - the
  // `not.toContain("Feb 2026")` assertion fails, since "Feb" would come back "Feb 2026" and the
  // crowding W4 exists to prevent (a year on every label) would be recreated.
  it("shows the year on the first label of each year, so three Januaries are distinguishable, but does not repeat it on every label after", async () => {
    const el = await open(
      trend({
        bucketUnit: "month",
        bucketSpan: 14,
        points: [
          point({ bucketKey: "2025-12", bucketIndex: 0, label: "Dec" }),
          point({ bucketKey: "2026-01", bucketIndex: 1, label: "Jan" }),
          point({ bucketKey: "2026-02", bucketIndex: 2, label: "Feb" })
        ]
      })
    );
    const texts = [
      ...el.shadowRoot.querySelectorAll('[data-id="axis-label"]')
    ].map((t) => t.textContent.trim());
    expect(texts.some((t) => t.includes("2026"))).toBe(true);
    expect(texts).toContain("Feb");
    expect(texts).not.toContain("Feb 2026");
  });

  // Ruling 24: every test above reads the x dimension only. These two read y.

  it("plots a higher median with a smaller cy, because SVG y grows downward", async () => {
    // Dropping the "1 -" in the y() formula would invert the chart: a rising market would draw
    // as a falling line, and nothing above this test would notice, since none of it reads cy.
    const el = await open(
      trend({
        points: [
          point({
            bucketKey: "2026-01",
            label: "Jan",
            bucketIndex: 0,
            median: 2000,
            minimum: 1800,
            maximum: 2200
          }),
          point({
            bucketKey: "2026-02",
            label: "Feb",
            bucketIndex: 1,
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
    // minima - the same x-coordinates the dots already sit at, since both use x(p.bucketIndex).
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

  // Ruling 25: bucketSpan is an Apex contract, not a value to paper over.

  it("falls through to the empty state rather than drawing a misleading chart when bucketSpan is missing or zero", async () => {
    // A `|| points.length` fallback would let this quietly draw a chart sized by array position
    // instead of the window - a chart that looks right but is not sized by bucketSpan, which is
    // the specific wrongness Ruling 11's bucketIndex contract exists to prevent. Two sequential
    // scenarios rather than a loop, so as not to await inside one.
    const withMissingSpan = await open(trend({ bucketSpan: null }));
    expect(withMissingSpan.shadowRoot.querySelector("svg")).toBeNull();
    expect(
      withMissingSpan.shadowRoot.querySelector('[data-id="trend-empty"]')
    ).not.toBeNull();

    const withZeroSpan = await open(trend({ bucketSpan: 0 }));
    expect(withZeroSpan.shadowRoot.querySelector("svg")).toBeNull();
    expect(
      withZeroSpan.shadowRoot.querySelector('[data-id="trend-empty"]')
    ).not.toBeNull();
  });

  it("still draws real coordinates when the window spans exactly one month", async () => {
    // bucketSpan === 1 is a legitimate one-month window, not a contract violation - the
    // Math.max(bucketSpan, 2) floor exists only so (span - 1) is never zero. Checking only that
    // an <svg> exists would not catch that floor being "simplified" away later: the element
    // would still render even with NaN coordinates, so this checks the coordinates themselves.
    const el = await open(
      trend({
        bucketSpan: 1,
        points: [
          point({ bucketKey: "2026-01", label: "Jan", bucketIndex: 0 }),
          point({
            bucketKey: "2026-01b",
            label: "Jan",
            bucketIndex: 0,
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
