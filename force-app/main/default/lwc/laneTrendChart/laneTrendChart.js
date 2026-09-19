import { LightningElement, api, track } from "lwc";
import getTrend from "@salesforce/apex/LaneTrendController.getTrend";

const WINDOWS = [
  { key: "6m", label: "6 months", days: 182 },
  { key: "1y", label: "1 year", days: 365 },
  { key: "3y", label: "3 years", days: 1095 }
];

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

  async load() {
    this.error = null;
    if (!this.hasLane) {
      this.trend = null;
      return;
    }
    const days = WINDOWS.find((w) => w.key === this.windowKey).days;
    this.loading = true;
    try {
      this.trend = await getTrend({
        requestJson: JSON.stringify({ ...this.request, lookbackDays: days })
      });
    } catch (e) {
      this.trend = null;
      this.error =
        e?.body?.message || e?.message || "The trend could not be read.";
    } finally {
      this.loading = false;
    }
  }

  get solidPoints() {
    return (this.trend?.points || []).filter((p) => !p.thin);
  }

  /** Two or more months not thinned by D5 - fewer than that draws no line worth trusting. */
  get hasEnough() {
    return this.solidPoints.length >= 2;
  }

  get isTruncated() {
    return this.trend?.truncated === true;
  }

  get outsideWindowCount() {
    return this.trend?.outsideWindow || 0;
  }

  /** Ruling 11: a rate the search matched but the trend dropped is never left unmentioned. */
  get hasOutsideWindow() {
    return this.outsideWindowCount > 0;
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
}
