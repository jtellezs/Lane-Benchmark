import { LightningElement, api, track } from "lwc";
import getTrend from "@salesforce/apex/LaneTrendController.getTrend";

// Nine windows, one week to three years (spec W2). The row cap that withdrew three years on
// 2026-09-19 was raised in Apex (W5) on the same measurement that withdrew it, so it is back; the
// bucket that made 37 months unreadable is no longer fixed at a month either (W1) - Apex buckets
// each window by day, week or month depending on its length and states the choice on
// `trend.bucketUnit`, which is what the summary getter below reads to name it.
const WINDOWS = [
  { key: "1w", label: "1 week", days: 7 },
  { key: "2w", label: "2 weeks", days: 14 },
  { key: "1m", label: "1 month", days: 30 },
  { key: "2m", label: "2 months", days: 60 },
  { key: "3m", label: "3 months", days: 90 },
  { key: "6m", label: "6 months", days: 182 },
  { key: "1y", label: "1 year", days: 365 },
  { key: "2y", label: "2 years", days: 730 },
  { key: "3y", label: "3 years", days: 1095 }
];

// W8: the caption counts buckets that carry rates (Ruling 22) and now says which kind they are.
// Apex is the only layer that decides which unit a window gets (W1); this map only spells out
// the noun for a unit Apex already chose, never re-derives it from lookbackDays or anything else.
const UNIT_NOUN = { day: "days", week: "weeks", month: "months" };

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

// W4: 37 monthly labels at three years, or 30 daily ones at a month, collide in a 572-unit plot.
// Show at most a dozen, evenly spaced - and then drop any that would still overlap (below).
const MAX_AXIS_LABELS = 12;
// Matches font-size="9" on the axis <text> in the template. 0.6em is a fair average advance width
// for digits and short month names in the SLDS stack; it only has to be close, since the gap below
// absorbs the error. Two characters of slack cover the year suffix a label may pick up later.
const AXIS_CHAR_W = 9 * 0.6;
const AXIS_LABEL_GAP = 6;
const axisLabelWidth = (label) => (label.length + 2) * AXIS_CHAR_W;

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
  // 1 year then 6 months and, unticketed, the 6-month answer lands first and the slow 1-year answer
  // overwrites it - leaving a year of data on screen with the 6-month button highlighted and
  // aria-pressed, captioned with the one-year counts.
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

  /** Two or more buckets not thinned by D5 - fewer than that draws no line worth trusting. */
  get hasEnough() {
    return this.solidPoints.length >= 2;
  }

  /**
   * Ruling 25: every point's bucketIndex is only meaningful against a positive bucketSpan - a
   * falsy or non-positive bucketSpan is an Apex contract violation, not a case to paper over by
   * falling back to points.length. A points.length fallback would silently downgrade the axis
   * to array-index spacing: a chart that looks right but is not sized by the window - quietly
   * wrong, which is the one failure mode a chart must not have, since a reader has nothing to
   * check it against.
   */
  get hasValidSpan() {
    return this.trend?.bucketSpan > 0;
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
   * Ruling 22: counts points.length, not bucketSpan. bucketSpan is the window's calendar span (a
   * 365-day window can touch 13 distinct calendar months) - right for Task 6's axis, wrong here,
   * because the window is already named by the highlighted button and restating it as a
   * different, larger number reads as a contradiction. points.length is the number of buckets
   * that carry rates - thin buckets included, since D5 only excludes a thin bucket from the
   * trend line, not from the evidence - and it is the number the reader can verify by counting
   * dots.
   *
   * W8: which noun that count gets is read off `trend.bucketUnit`, not decided here - Apex is the
   * only layer that picks the unit (W1), and this getter only spells out the plural Apex already
   * chose. `UNIT_NOUN[...] || "buckets"` is defensive against a fourth unit Apex's own contract
   * (`'day' | 'week' | 'month'`) does not currently allow, so that branch has no reachable test.
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
    const unit = UNIT_NOUN[t.bucketUnit] || "buckets";
    return `${t.points.length} ${unit}, ${t.totalRates} rates, median ${median} ${t.currencyIsoCode}${direction}.`;
  }

  /**
   * The assistive table's column header (spec 5) - the screen-reader equivalent of the axis, so
   * a hard-coded "Month" is simply wrong for a day- or week-bucketed chart. Reuses `UNIT_NOUN`
   * (the same noun the caption above already spells out for `bucketUnit`, W8) rather than adding
   * a second unit-to-word mapping - the exact drift W1 warns about, one layer down. A header
   * names what each row is, so it wants the singular ("Day", not "Days") where the caption wants
   * the plural ("30 days"); stripping the trailing "s" and capitalizing is a derivation of that
   * one mapping, not a second one.
   */
  get bucketUnitHeader() {
    const noun = UNIT_NOUN[this.trend?.bucketUnit] || "buckets";
    const singular = noun.endsWith("s") ? noun.slice(0, -1) : noun;
    return singular.charAt(0).toUpperCase() + singular.slice(1);
  }

  /**
   * Positions only. Every statistic was computed in Apex; this turns numbers into coordinates
   * for the hand-drawn SVG (D4) - no charting library.
   *
   * The x axis spans `bucketSpan`, not `points.length`: bucketSpan is the whole window the pricer
   * chose, and points are only the buckets that happened to carry a rate. Sizing the axis by the
   * window rather than by what showed up is what lets a quiet stretch read as the gap it is,
   * instead of being squeezed out next to its neighbours. `bucketIndex` is used exactly as Apex
   * sends it - it is already guaranteed to fall in [0, bucketSpan) there, so clamping it here
   * would only hide a future regression rather than surface it.
   *
   * `fill` is computed per point here, not read off a single component getter, because an LWC
   * template cannot evaluate an expression: one getter cannot vary per iteration of a for:each,
   * so each dot carries its own colour.
   *
   * No `|| points.length` fallback on bucketSpan (Ruling 25): `canDraw` has already ruled out a
   * falsy or non-positive bucketSpan, so by the time this runs bucketSpan is trustworthy. The
   * `Math.max(bucketSpan, 2)` floor is not that fallback - it exists only so a legitimate
   * one-bucket window (bucketSpan === 1) does not divide by zero on (span - 1) below.
   */
  get geometry() {
    const points = this.trend?.points || [];
    if (!this.canDraw) {
      return null;
    }
    const span = Math.max(this.trend.bucketSpan, 2);
    const low = Math.min(...points.map((p) => p.minimum));
    const high = Math.max(...points.map((p) => p.maximum));
    const range = high - low || 1;

    const plotW = VIEW_W - PAD_L - PAD_R;
    const plotH = VIEW_H - PAD_T - PAD_B;
    const x = (i) => PAD_L + (plotW * i) / (span - 1);
    const y = (v) => PAD_T + plotH * (1 - (v - low) / range);

    const dots = points.map((p) => ({
      key: p.bucketKey,
      cx: x(p.bucketIndex),
      cy: y(p.median),
      thin: p.thin === true ? "true" : "false",
      fill: p.thin === true ? COLOR_DOT_HOLLOW : COLOR_LINE,
      title: `${p.label}: median ${p.median} ${this.trend.currencyIsoCode}, ${p.count} rates`
    }));

    const line = points
      .filter((p) => !p.thin)
      .map((p) => `${x(p.bucketIndex)},${y(p.median)}`)
      .join(" ");

    // The band shows spread, not trend, so - unlike the line above - it keeps every bucket,
    // thin ones included: D5 withholds a thin bucket's authority over the trend line, not its
    // evidence of that bucket's spread.
    const top = points.map((p) => `${x(p.bucketIndex)},${y(p.maximum)}`);
    const bottom = points
      .slice()
      .reverse()
      .map((p) => `${x(p.bucketIndex)},${y(p.minimum)}`);
    const band = top.concat(bottom).join(" ");

    // W4: show at most a dozen axis labels, evenly spaced, and carry the year on the first label
    // of each year so three Januaries (or three "5 Jan" weeks) are not indistinguishable.
    // bucketKey's first four characters are the year for every unit (day, week and month all key
    // as YYYY-... - see the header comment on bucketKey in the spec), which is what lets this
    // work without a second field.
    // Positions are spaced across the whole range and anchored at both ends, rather than taken as
    // every step-th point. Stepping by `Math.ceil(n / 12)` keeps index 0 for free but keeps the last
    // index only when `(n - 1) % step === 0`, which is false at 14 and 30 points - the daily counts
    // for the two-week and one-month windows - so the most recent bucket, the one a reader looks at
    // first, went unlabelled on two of the nine windows. Forcing the last index into a stepped
    // selection is not the fix: at 14 points it puts labels on indices 12 and 13, recreating the very
    // collision W4 thins to avoid. The selection rule itself has to change.
    //
    // With `labelCount <= points.length` the spacing is at least one, so the rounded indices are
    // distinct - which matters beyond tidiness, since bucketKey is the for:each key.
    const labelCount = Math.min(points.length, MAX_AXIS_LABELS);
    const spaced = [];
    for (let k = 0; k < labelCount; k++) {
      spaced.push(
        labelCount === 1
          ? 0
          : Math.round((k * (points.length - 1)) / (labelCount - 1))
      );
    }

    // A dozen labels is few enough only when the buckets they sit on are spread out. They are
    // positioned by date, not by rank, so a lane quiet for three weeks and then busy for five
    // consecutive days puts five labels ~20 units apart where each needs ~35 - which is how
    // "9 Sep 10 Sep 11 Sep" ends up printed over itself. Walk left to right and keep a label only
    // when it clears the last one kept.
    const kept = [];
    spaced.forEach((i) => {
      if (!kept.length) {
        kept.push(i);
        return;
      }
      const prev = kept[kept.length - 1];
      const need =
        (axisLabelWidth(points[prev].label) + axisLabelWidth(points[i].label)) /
          2 +
        AXIS_LABEL_GAP;
      if (x(points[i].bucketIndex) - x(points[prev].bucketIndex) >= need) {
        kept.push(i);
      }
    });

    // The newest bucket keeps its label whatever the spacing says, so the axis never reads as
    // ending before the data does. If it crowds its neighbours, they give way rather than it.
    const lastIndex = points.length - 1;
    if (kept[kept.length - 1] !== lastIndex) {
      while (kept.length > 1) {
        const prev = kept[kept.length - 1];
        const need =
          (axisLabelWidth(points[prev].label) +
            axisLabelWidth(points[lastIndex].label)) /
            2 +
          AXIS_LABEL_GAP;
        if (
          x(points[lastIndex].bucketIndex) - x(points[prev].bucketIndex) >=
          need
        ) {
          break;
        }
        kept.pop();
      }
      kept.push(lastIndex);
    }

    let lastYear = null;
    const axis = [];
    kept.forEach((i) => {
      const p = points[i];
      const year = p.bucketKey.slice(0, 4);
      axis.push({
        key: p.bucketKey,
        x: x(p.bucketIndex),
        y: AXIS_LABEL_Y,
        label: year === lastYear ? p.label : `${p.label} ${year}`
      });
      lastYear = year;
    });

    return {
      viewBox: `0 0 ${VIEW_W} ${VIEW_H}`,
      line,
      band,
      dots,
      axis,
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
      key: p.bucketKey,
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
