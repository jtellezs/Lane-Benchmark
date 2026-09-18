import { LightningElement, api } from "lwc";
import { parseMargin, suggestedSell } from "c/marginMath";
import { perDistance } from "c/distanceUnit";

function fmt(n) {
  if (n === null || n === undefined) return "—";
  return Number(n).toLocaleString("en-CA", {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2
  });
}

/**
 * Phase 9: selling, beside the statistics rather than inside them. Reading a lane and pricing it
 * are two acts: the statistics card answers what the lane costs, and this one answers what to
 * quote once a margin is chosen. It stays a button until asked for, so a card of figures nobody
 * has set a margin for never appears.
 */
export default class LaneBenchmarkSelling extends LightningElement {
  @api statsByCurrency = {};
  @api unit = "mi";

  _marginPct = 15;
  @api get marginPct() {
    return this._marginPct;
  }
  set marginPct(v) {
    this._marginPct = v;
  }

  open = false;
  marginError = null;

  get hasStats() {
    return Object.keys(this.statsByCurrency || {}).length > 0;
  }

  get toggleLabel() {
    return this.open ? "Hide selling" : "Selling";
  }

  get rateLabel() {
    return this.unit === "km"
      ? "Sell per km (median)"
      : "Sell per mile (median)";
  }

  get cards() {
    return Object.keys(this.statsByCurrency || {})
      .sort()
      .map((currency) => {
        const s = this.statsByCurrency[currency];
        const rate = s.ratePerMileMedian;
        const perUnit =
          rate === null || rate === undefined
            ? null
            : perDistance(rate, 1, this.unit);
        return {
          currency,
          median: fmt(s.median),
          avg: fmt(s.avg),
          sellMedian: fmt(suggestedSell(s.median, this._marginPct)),
          sellAvg: fmt(suggestedSell(s.avg, this._marginPct)),
          sellRate: fmt(
            perUnit === null ? null : suggestedSell(perUnit, this._marginPct)
          )
        };
      });
  }

  handleToggle() {
    this.open = !this.open;
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

  setMargin(n) {
    this._marginPct = n;
    this.marginError = null;
    this.dispatchEvent(
      new CustomEvent("marginchange", { detail: { marginPct: n } })
    );
  }
}
