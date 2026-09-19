import { LightningElement, api, track } from "lwc";
import getTrend from "@salesforce/apex/LaneTrendController.getTrend";

const WINDOWS = [
  { key: "6m", label: "6 months", days: 182 },
  { key: "1y", label: "1 year", days: 365 },
  { key: "3y", label: "3 years", days: 1095 }
];

// Geometry constants for the hand-drawn SVG (D4). A fixed viewBox, scaled by CSS, is what lets
// the chart resize without a resize listener.
const VIEW_W = 640;
const VIEW_H = 220;
const PAD_L = 56;
const PAD_R = 12;
const PAD_T = 12;
const PAD_B = 28;
const AXIS_LABEL_Y = VIEW_H - 8;
const GRID_LABEL_X = 8;

// SLDS design tokens with hex fallbacks (spec 5), so the chart reads correctly in both themes.
// Only the dot fill varies per point (below); the rest are static and set directly in the
// template.
const COLOR_LINE = "var(--slds-g-color-accent-base-50, #0176d3)";
const COLOR_DOT_HOLLOW = "var(--slds-g-color-neutral-base-100, #ffffff)";

/**
 * Phase 10: how this lane's market moved. Imperative rather than @wire because the window
 * control asks the same question over a different span, and because the card must stay closed
 * when there is no lane yet rather than firing a call with nothing in it.
 *
 * The requestJson setter mirrors marketTestRates: parsing happens synchronously in a method the
 * setter calls directly (readRequest), not inside the async load(). A JSON.parse thrown from
 * inside an async function's body becomes a rejected promise on a call nobody awaits, not a
 * failure the caller (or a test) can see - so the try/catch that keeps a bad request from
 * breaking the page has to sit where a caller can actually observe it going missing.
 */
export default class LaneTrendChart extends LightningElement {
  _requestJson = null;
  request = null;

  @track trend = null;
  windowKey = "1y";
  loading = false;
  error = null;
  // Bumped by every trend request; an answer carrying an older ticket belongs to an earlier window
  // or an earlier lane and is dropped. The same pattern as laneBenchmark.js's routeTicket, and
  // needed for the same reason plus one more: getTrend is cacheable, so a window whose answer is
  // already cached resolves almost immediately while an uncached one takes a round trip. Click
  // 3 years then 1 year and, unticketed, the 1-year answer lands first and the slow 3-year answer
  // overwrites it - leaving three years of data on screen with the 1-year button highlighted and
  // aria-pressed, captioned with the three-year counts.
  loadTicket = 0;

  @api
  get requestJson() {
    return this._requestJson;
  }
  set requestJson(value) {
    const next = value || null;
    if (next === this._requestJson) {
      return;
    }
    this._requestJson = next;
    this.readRequest();
    this.load();
  }

  readRequest() {
    this.request = null;
    if (!this._requestJson) {
      return;
    }
    try {
      const parsed = JSON.parse(this._requestJson);
      this.request =
        parsed && parsed.originKey && parsed.destinationKey ? parsed : null;
    } catch {
      // a request we cannot read leaves the card closed rather than breaking the page
      this.request = null;
    }
  }

  get hasLane() {
    return !!this.request;
  }

  get windows() {
    return WINDOWS.map((w) => {
      const selected = w.key === this.windowKey;
      return {
        key: w.key,
        label: w.label,
        dataId: `window-${w.key}`,
        buttonClass: selected
          ? "slds-button slds-button_brand slds-m-left_xx-small"
          : "slds-button slds-button_neutral slds-m-left_xx-small",
        ariaPressed: selected ? "true" : "false"
      };
    });
  }

  handleWindow(event) {
    const key = event.currentTarget.dataset.window;
    if (!key || key === this.windowKey) {
      return;
    }
    this.windowKey = key;
    this.load();
  }

  /**
   * The ticket is taken before the early return, as laneBenchmark.loadRoute does, so clearing the
   * card also invalidates a request already in flight. Every write that describes the answer -
   * trend, error and the loading flag - is guarded by it: a stale rejection would otherwise blank a
   * chart that had already arrived, and a stale `loading = false` would unspin a request still
   * running.
   */
  async load() {
    this.loadTicket += 1;
    const ticket = this.loadTicket;
    this.error = null;
    if (!this.hasLane) {
      this.trend = null;
      return;
    }
    const days = WINDOWS.find((w) => w.key === this.windowKey).days;
    this.loading = true;
    try {
      const result = await getTrend({
        requestJson: JSON.stringify({ ...this.request, lookbackDays: days })
      });
      if (ticket === this.loadTicket) {
        this.trend = result;
      }
    } catch (e) {
      if (ticket === this.loadTicket) {
        this.trend = null;
        this.error =
          e?.body?.message || e?.message || "The trend could not be read.";
      }
    } finally {
      if (ticket === this.loadTicket) {
        this.loading = false;
      }
    }
  }

  get solidPoints() {
    return (this.trend?.points || []).filter((p) => !p.thin);
  }

  /** Two or more months not thinned by D5 - fewer than that draws no line worth trusting. */
  get hasEnough() {
    return this.solidPoints.length >= 2;
  }

  /**
   * Ruling 25: every point's monthIndex is only meaningful against a positive monthSpan - a
   * falsy or non-positive monthSpan is an Apex contract violation, not a case to paper over by
   * falling back to points.length. A points.length fallback would silently downgrade the axis
   * to array-index spacing: a chart that looks right but is not sized by the window - quietly
   * wrong, which is the one failure mode a chart must not have, since a reader has nothing to
   * check it against.
   */
  get hasValidSpan() {
    return this.trend?.monthSpan > 0;
  }

  /** What the template gates the chart on: D5's count rule and Ruling 25's span contract. */
  get canDraw() {
    return this.hasEnough && this.hasValidSpan;
  }

  get isTruncated() {
    return this.trend?.truncated === true;
  }

  /**
   * The sentence most pricers will read. Formats numbers Apex already computed; does no maths.
   *
   * Ruling 22: counts points.length, not monthSpan. monthSpan is the window's calendar span (a
   * 365-day window can touch 13 distinct calendar months) - right for Task 6's axis, wrong here,
   * because the window is already named by the highlighted button and restating it as a
   * different, larger number reads as a contradiction. points.length is the number of months
   * that carry rates - thin months included, since D5 only excludes a thin month from the trend
   * line, not from the evidence - and it is the number the reader can verify by counting dots.
   */
  get summary() {
    if (!this.trend) {
      return "";
    }
    const t = this.trend;
    const median =
      t.overallMedian === null || t.overallMedian === undefined
        ? ""
        : Number(t.overallMedian).toLocaleString();
    const direction =
      t.changePct === null || t.changePct === undefined
        ? ""
        : `, ${t.changePct >= 0 ? "up" : "down"} ${Math.abs(t.changePct)}% since ${t.firstLabel}`;
    return `${t.points.length} months, ${t.totalRates} rates, median ${median} ${t.currencyIsoCode}${direction}.`;
  }

  /**
   * Positions only. Every statistic was computed in Apex; this turns numbers into coordinates
   * for the hand-drawn SVG (D4) - no charting library.
   *
   * The x axis spans `monthSpan`, not `points.length`: monthSpan is the whole window the pricer
   * chose, and points are only the months that happened to carry a rate. Sizing the axis by the
   * window rather than by what showed up is what lets a quiet stretch read as the gap it is,
   * instead of being squeezed out next to its neighbours. `monthIndex` is used exactly as Apex
   * sends it - it is already guaranteed to fall in [0, monthSpan) there, so clamping it here
   * would only hide a future regression rather than surface it.
   *
   * `fill` is computed per point here, not read off a single component getter, because an LWC
   * template cannot evaluate an expression: one getter cannot vary per iteration of a for:each,
   * so each dot carries its own colour.
   *
   * No `|| points.length` fallback on monthSpan (Ruling 25): `canDraw` has already ruled out a
   * falsy or non-positive monthSpan, so by the time this runs monthSpan is trustworthy. The
   * `Math.max(monthSpan, 2)` floor is not that fallback - it exists only so a legitimate
   * one-month window (monthSpan === 1) does not divide by zero on (span - 1) below.
   */
  get geometry() {
    const points = this.trend?.points || [];
    if (!this.canDraw) {
      return null;
    }
    const span = Math.max(this.trend.monthSpan, 2);
    const low = Math.min(...points.map((p) => p.minimum));
    const high = Math.max(...points.map((p) => p.maximum));
    const range = high - low || 1;

    const plotW = VIEW_W - PAD_L - PAD_R;
    const plotH = VIEW_H - PAD_T - PAD_B;
    const x = (i) => PAD_L + (plotW * i) / (span - 1);
    const y = (v) => PAD_T + plotH * (1 - (v - low) / range);

    const dots = points.map((p) => ({
      key: p.monthKey,
      cx: x(p.monthIndex),
      cy: y(p.median),
      thin: p.thin === true ? "true" : "false",
      fill: p.thin === true ? COLOR_DOT_HOLLOW : COLOR_LINE,
      title: `${p.label}: median ${p.median} ${this.trend.currencyIsoCode}, ${p.count} rates`
    }));

    const line = points
      .filter((p) => !p.thin)
      .map((p) => `${x(p.monthIndex)},${y(p.median)}`)
      .join(" ");

    // The band shows spread, not trend, so - unlike the line above - it keeps every month,
    // thin ones included: D5 withholds a thin month's authority over the trend line, not its
    // evidence of that month's spread.
    const top = points.map((p) => `${x(p.monthIndex)},${y(p.maximum)}`);
    const bottom = points
      .slice()
      .reverse()
      .map((p) => `${x(p.monthIndex)},${y(p.minimum)}`);
    const band = top.concat(bottom).join(" ");

    return {
      viewBox: `0 0 ${VIEW_W} ${VIEW_H}`,
      line,
      band,
      dots,
      axis: points.map((p) => ({
        key: p.monthKey,
        x: x(p.monthIndex),
        y: AXIS_LABEL_Y,
        label: p.label
      })),
      gridY: [
        {
          key: "hi",
          x: GRID_LABEL_X,
          y: y(high),
          label: String(Math.round(high))
        },
        {
          key: "lo",
          x: GRID_LABEL_X,
          y: y(low),
          label: String(Math.round(low))
        }
      ]
    };
  }

  /** The same numbers as the chart, laid out for the visually-hidden table (spec 5). */
  get tableRows() {
    return (this.trend?.points || []).map((p) => ({
      key: p.monthKey,
      label: p.label,
      count: p.count,
      median: p.median,
      minimum: p.minimum,
      maximum: p.maximum
    }));
  }

  get figureTitle() {
    return `Lane trend, ${this.trend?.currencyIsoCode || ""}`;
  }
}
