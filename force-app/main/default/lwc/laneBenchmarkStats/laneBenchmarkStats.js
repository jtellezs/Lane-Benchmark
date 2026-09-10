import { LightningElement, api } from "lwc";
import { parseMargin, suggestedSell } from "c/marginMath";

function fmt(n) {
  if (n === null || n === undefined) return "—";
  return Number(n).toLocaleString("en-CA", {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2
  });
}

export default class LaneBenchmarkStats extends LightningElement {
  @api statsByCurrency = {};
  @api dedupedCount = 0;
  @api truncated = false;
  @api elapsedMs = 0;
  @api rowCount = 0;
  _marginPct = 15;
  @api get marginPct() {
    return this._marginPct;
  }
  set marginPct(v) {
    this._marginPct = v;
  }
  marginError = null;

  get hasStats() {
    return Object.keys(this.statsByCurrency || {}).length > 0;
  }
  get isEmpty() {
    return !this.hasStats && this.rowCount === 0;
  }
  get elapsedText() {
    return `${(Number(this.elapsedMs || 0) / 1000).toFixed(1)} s`;
  }
  get dedupeText() {
    return this.dedupedCount ? `${this.dedupedCount} duplicates removed` : "";
  }
  get cards() {
    return Object.keys(this.statsByCurrency || {})
      .sort()
      .map((currency) => {
        const s = this.statsByCurrency[currency];
        return {
          currency,
          count: s.count,
          countNonZero: s.countNonZero,
          min: fmt(s.min),
          max: fmt(s.max),
          avg: fmt(s.avg),
          median: fmt(s.median),
          sellMedian: fmt(suggestedSell(s.median, this._marginPct)),
          sellAvg: fmt(suggestedSell(s.avg, this._marginPct))
        };
      });
  }

  setMargin(n) {
    this._marginPct = n;
    this.marginError = null;
    this.dispatchEvent(
      new CustomEvent("marginchange", { detail: { marginPct: n } })
    );
  }
  handleMargin15() {
    this.setMargin(15);
  }
  handleMargin20() {
    this.setMargin(20);
  }
  handleMarginInput(event) {
    const n = parseMargin(event.detail.value);
    if (n === null) {
      this.marginError = "Enter a margin between 0 and 100";
      return;
    }
    this.setMargin(n);
  }
}
