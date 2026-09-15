import { LightningElement, api } from "lwc";
import findCarrierLeads from "@salesforce/apex/CarrierLeadController.findCarrierLeads";

const STATE_LANE = "State lane";
const LOAD_FAILED = "The carriers to ask could not be loaded.";
const EMPTY_TEXT =
  "No carrier found on this lane or on its state or province lane.";

/**
 * Carriers to ask (spec §3 and §7): carrier names, never amounts, for a lane whose first search
 * found no carrier rate. The parent decides when the card shows (c/carrierLeadRules) and passes
 * the request JSON its first search sent; the card asks CarrierLeadController once per request.
 * The Apex method is cacheable, so the same request (a lane opened again) is served from the
 * browser cache; Retry sends attempt + 1 so it reaches the server.
 */
export default class CarrierLeads extends LightningElement {
  /** The code the heading names: the lane's currency, or Lane Benchmark's currency filter (null without one). */
  @api currencyCode;

  _requestJson = null;
  /** The CarrierLeadResult for the current request, null until it answers. */
  result = null;
  error = null;
  loading = false;
  /** 0 for a new request; each Retry adds 1. */
  attempt = 0;
  /** Bumped by every call; an answer carrying an older number is dropped. */
  seq = 0;

  @api
  get requestJson() {
    return this._requestJson;
  }
  set requestJson(value) {
    const next =
      typeof value === "string" && value.trim() !== "" ? value : null;
    if (next === this._requestJson) {
      return;
    }
    this._requestJson = next;
    this.attempt = 0;
    this.load();
  }

  async load() {
    const seq = ++this.seq;
    const requestJson = this._requestJson;
    this.result = null;
    this.error = null;
    if (!requestJson) {
      this.loading = false;
      return;
    }
    this.loading = true;
    try {
      const result = await findCarrierLeads({
        requestJson,
        attempt: this.attempt
      });
      if (seq === this.seq) {
        this.result = result || null;
      }
    } catch (e) {
      if (seq === this.seq) {
        this.error = (e && e.body && e.body.message) || LOAD_FAILED;
      }
    } finally {
      if (seq === this.seq) {
        this.loading = false;
      }
    }
  }

  handleRetry() {
    this.attempt += 1;
    this.load();
  }

  get leads() {
    return (this.result && this.result.leads) || [];
  }
  get hasLeads() {
    return this.leads.length > 0;
  }
  get isStateLane() {
    return !!this.result && this.result.stage === STATE_LANE;
  }
  get showHeading() {
    return this.hasLeads && !this.isStateLane;
  }
  get showStateLane() {
    return this.hasLeads && this.isStateLane;
  }
  get showEmpty() {
    return !!this.result && !this.hasLeads;
  }
  get truncated() {
    return !!(this.result && this.result.truncated);
  }
  get heading() {
    const code = this.currencyCode ? ` in ${this.currencyCode}` : "";
    return `No carrier rate on this lane${code}. These carriers quoted or moved it before; amounts are not shown.`;
  }
  get stateLaneText() {
    return `No carrier on this exact lane. Top carriers on ${this.result?.stateLaneLabel} over the last year.`;
  }
  get emptyText() {
    return EMPTY_TEXT;
  }
  /** One line per carrier: the link only when the user can read the account (lead.canOpen). */
  get leadRows() {
    return this.leads.map((lead, index) => ({
      key: lead.carrierId || `lead-${index}`,
      name: lead.name,
      canOpen: !!(lead.canOpen && lead.carrierId),
      url: `/lightning/r/Account/${lead.carrierId}/view`,
      blacklisted: !!lead.blacklisted,
      counts: `${lead.loadsMoved} moved · ${lead.loadsQuoted} quoted · last seen ${lead.lastSeen || "—"}`,
      sources: (lead.sources || []).join(", ")
    }));
  }
}
