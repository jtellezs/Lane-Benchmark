import { LightningElement, api } from "lwc";
import { formatDistance, readUnit } from "c/distanceUnit";

const TRUCK_TITLE = "Truck route";
const REGULAR_TITLE = "Regular route — truck limits could not be met";
const UNAVAILABLE = "The truck route is not available right now.";
const NO_ROUTE =
  "No route was found between these places, even without truck limits.";
const MAX_ROUTES = 3;
const HOURS = new Intl.NumberFormat("en-CA", {
  minimumFractionDigits: 1,
  maximumFractionDigits: 1
});

function hoursText(hours) {
  if (hours === null || hours === undefined || hours === "") {
    return "";
  }
  const n = Number(hours);
  return Number.isFinite(n) ? `${HOURS.format(n)} h` : "";
}

export default class RouteMap extends LightningElement {
  /** TripRouteView from RfpLaneController.laneRoute or LaneBenchmarkController.truckRoute. */
  @api view = null;
  @api loading = false;
  /** True on a hazmat RFP lane: the legend says the route ignores hazmat rules. */
  @api hazmat = false;
  _unit = readUnit();

  /** 'mi' or 'km'; anything else falls back to the unit this browser remembered. */
  @api
  get unit() {
    return this._unit;
  }
  set unit(value) {
    this._unit = value === "mi" || value === "km" ? value : readUnit();
  }

  get hasView() {
    return Boolean(this.view);
  }
  get status() {
    return this.view ? this.view.status : null;
  }
  get found() {
    return this.status === "Found";
  }
  get mapUrl() {
    return this.view ? this.view.mapUrl : null;
  }
  get hasImage() {
    return Boolean(this.mapUrl);
  }
  get imageAlt() {
    return this.found
      ? `${this.legendTitle} from A to B on a map`
      : "Origin A and destination B on a map";
  }
  get message() {
    if (this.status === "Unavailable") {
      return this.view.message || UNAVAILABLE;
    }
    if (this.status === "No route") {
      return this.view.message || NO_ROUTE;
    }
    return null;
  }
  get routes() {
    const routes = this.found && this.view.routes;
    return Array.isArray(routes) ? routes.slice(0, MAX_ROUTES) : [];
  }
  get hasLegend() {
    return this.routes.length > 0;
  }
  get legendTitle() {
    return this.view && this.view.routeType === "Regular"
      ? REGULAR_TITLE
      : TRUCK_TITLE;
  }
  get legend() {
    return this.routes.map((route, i) => {
      const distance = formatDistance(route && route.miles, this._unit) || "—";
      const hours = hoursText(route && route.hours);
      return {
        key: `route-${i + 1}`,
        swatchClass: `swatch swatch-${i + 1}`,
        text: `Route ${i + 1}: ${distance}${hours ? ` · ${hours}` : ""}`
      };
    });
  }
  get showHazmat() {
    return this.hasLegend && Boolean(this.hazmat);
  }

  handleRefresh() {
    if (this.loading) {
      return;
    }
    this.dispatchEvent(new CustomEvent("refreshroute"));
  }
}
