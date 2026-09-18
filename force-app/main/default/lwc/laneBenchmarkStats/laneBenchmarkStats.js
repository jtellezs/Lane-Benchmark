import { LightningElement, api } from "lwc";
import { formatDistance, perDistance } from "c/distanceUnit";

function fmt(n) {
  if (n === null || n === undefined) return "—";
  return Number(n).toLocaleString("en-CA", {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2
  });
}

function hoursText(hours) {
  return hours === null || hours === undefined
    ? ""
    : ` · ${Number(hours).toFixed(1)} h`;
}

export default class LaneBenchmarkStats extends LightningElement {
  @api statsByCurrency = {};
  @api dedupedCount = 0;
  @api truncated = false;
  @api elapsedMs = 0;
  @api rowCount = 0;
  // Phase 7: the median of the matched loads' billed miles (LaneSearchResult.medianMiles), how
  // many distinct loads had miles, the truck route view (TripRouteView from
  // LaneBenchmarkController.truckRoute) and the page's unit, all passed by c-lane-benchmark.
  @api medianMiles = null;
  @api milesCount = 0;
  @api routeView = null;
  @api routeLoading = false;
  @api unit = "mi";

  get hasStats() {
    return Object.keys(this.statsByCurrency || {}).length > 0;
  }
  get isEmpty() {
    return !this.hasStats && this.rowCount === 0;
  }
  /** Joins only the parts that apply, so a zero dedupe count doesn't leave a trailing " · ". */
  get summary() {
    const seconds = (Number(this.elapsedMs || 0) / 1000).toFixed(1);
    const parts = [
      `${this.rowCount} ${this.rowCount === 1 ? "row" : "rows"} in ${seconds} s`
    ];
    if (this.dedupedCount > 0) {
      parts.push(`${this.dedupedCount} duplicates removed`);
    }
    if (this.truncated) {
      parts.push("truncated to the first 2,000 rows");
    }
    return parts.join(" · ");
  }
  /** "Trip: 1,234 mi · median of 3 loads", or "" when no matched load has miles. */
  get tripLine() {
    if (!(Number(this.medianMiles) > 0)) {
      return "";
    }
    const n = Number(this.milesCount || 0);
    return `Trip: ${formatDistance(this.medianMiles, this.unit)} · median of ${n} ${n === 1 ? "load" : "loads"}`;
  }
  /**
   * "Truck route: 1,260 mi · 21.5 h" or "Regular route: …" (truck limits could not be met);
   * a dash when there is no route (spec §7), and a dash with the server's message when Mapbox is
   * unavailable.
   */
  get routeLine() {
    const v = this.routeView;
    if (!v) {
      return this.routeLoading ? "Truck route: finding the route…" : "";
    }
    const label = v.routeType === "Regular" ? "Regular route" : "Truck route";
    if (v.status === "Found") {
      return `${label}: ${formatDistance(v.miles, this.unit)}${hoursText(v.hours)}`;
    }
    return v.status === "Unavailable" && v.message
      ? `${label}: — · ${v.message}`
      : `${label}: —`;
  }
  get hasTripInfo() {
    return !!(this.tripLine || this.routeLine);
  }
  get rateLabel() {
    return this.unit === "km"
      ? "Rate per km (median)"
      : "Rate per mile (median)";
  }
  get cards() {
    return Object.keys(this.statsByCurrency || {})
      .sort()
      .map((currency) => {
        const s = this.statsByCurrency[currency];
        const rate = s.ratePerMileMedian;
        return {
          currency,
          count: s.count,
          countNonZero: s.countNonZero,
          min: fmt(s.min),
          max: fmt(s.max),
          avg: fmt(s.avg),
          median: fmt(s.median),
          // a rate per mile over a trip of one mile is the rate per unit of distance
          rate: fmt(
            rate === null || rate === undefined
              ? null
              : perDistance(rate, 1, this.unit)
          )
        };
      });
  }
}
