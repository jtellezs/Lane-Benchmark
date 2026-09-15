import { LightningElement, api } from "lwc";
import splitOptions from "@salesforce/apex/SplitLaneController.splitOptions";
import { directMedian } from "c/carrierLeadRules";

const BUTTON_ON = "slds-button slds-button_brand";
const BUTTON_OFF = "slds-button slds-button_neutral";
/** SplitLaneResult.ESTIMATE; any other kind is a history group (SplitLaneResult.HISTORY). */
const ESTIMATE = "Estimate";
const LOAD_FAILED = "The split-lane options could not be loaded.";
const AMOUNT = new Intl.NumberFormat("en-CA", { maximumFractionDigits: 0 });

const isNumber = (value) => typeof value === "number" && Number.isFinite(value);
/** "1,248 CAD": the card shows whole amounts, in its own currency. */
const amountText = (value, code) => `${AMOUNT.format(value)} ${code}`;

/** The handoff cost as typed: a number of 0 or more, else null (blank, junk or negative). */
function handoffNumber(text) {
  if (text === null || text === undefined) {
    return null;
  }
  const trimmed = String(text).trim();
  if (trimmed === "") {
    return null;
  }
  const n = Number(trimmed);
  return Number.isFinite(n) && n >= 0 ? n : null;
}

/**
 * An option's total per shipment in the card's currency, or null: a history
 * group's median total (R85), or an estimate's two leg medians plus the typed
 * handoff cost (D8). An estimate with a leg that has no median has no total.
 */
function optionTotal(option, handoffText) {
  if (!isNumber(option.medianTotal)) {
    return null;
  }
  if (option.kind !== ESTIMATE) {
    return option.medianTotal;
  }
  const handoff = handoffNumber(handoffText);
  return handoff === null ? null : option.medianTotal + handoff;
}

/**
 * One leg line: "Leg 1 <lane> · " then each carrier with its legs moved (a
 * blacklisted one gets its badge in the template), then " · median <amount>"
 * when the leg has priced loads. Separators live in the strings, because the
 * template compiler drops whitespace between tags.
 */
function legView(leg, code) {
  const carriers = leg.carriers || [];
  return {
    key: `leg-${leg.position}`,
    head: `Leg ${leg.position} ${leg.laneLabel} · ${carriers.length ? "" : "no carrier found"}`,
    carriers: carriers.map((c, i) => ({
      key: c.carrierId || `carrier-${i}`,
      text: `${c.name} (${c.legsMoved})`,
      blacklisted: c.blacklisted === true,
      separator: i < carriers.length - 1 ? ", " : ""
    })),
    tail: isNumber(leg.median)
      ? ` · median ${amountText(leg.median, code)}`
      : ""
  };
}

/**
 * Split-lane options for one lane request (spec §4): nothing is asked until
 * the pricer clicks the button (D1); the card then shows one currency at a
 * time, CAD or USD, and keeps each currency's answer for this request.
 */
export default class SplitLaneOptions extends LightningElement {
  /** "CAD" or "USD": the currency the card opens in; anything else opens in CAD. */
  @api startCurrency;
  /** The currency Use as cost works in: the RFP lane's. Unset on Lane Benchmark. */
  @api laneCurrency;
  /** The first search's statistics by currency, for the direct median (R96). */
  @api statsByCurrency;
  /** Only the RFP lane panel lets an option fill its price editor (D9). */
  @api allowUseAsCost = false;

  _requestJson = null;
  opened = false;
  /** The card's currency once opened: "CAD" or "USD". */
  currencyCode = null;
  /** SplitLaneResult by currency code, for the request on screen. */
  answers = {};
  /** The typed handoff cost by estimate option key, in the card's currency. */
  handoffCosts = {};
  loading = false;
  error = null;
  /** 0 on the first call and one more per Retry, so a retry reaches the server past the cache. */
  attempt = 0;
  /** Bumped per call: only the latest call moves the spinner or shows an error. */
  seq = 0;
  /** Bumped per new request: an answer for an earlier request is dropped. */
  generation = 0;

  /** The request the first search ran. A new one closes the card and forgets what it kept. */
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
    this.generation += 1;
    this.seq += 1;
    this.opened = false;
    this.currencyCode = null;
    this.answers = {};
    this.handoffCosts = {};
    this.loading = false;
    this.error = null;
    this.attempt = 0;
  }

  get cadClass() {
    return this.currencyCode === "CAD" ? BUTTON_ON : BUTTON_OFF;
  }
  get usdClass() {
    return this.currencyCode === "USD" ? BUTTON_ON : BUTTON_OFF;
  }
  get cadPressed() {
    return this.currencyCode === "CAD" ? "true" : "false";
  }
  get usdPressed() {
    return this.currencyCode === "USD" ? "true" : "false";
  }
  get result() {
    return (this.currencyCode && this.answers[this.currencyCode]) || null;
  }
  get hasOptions() {
    const r = this.result;
    return !!(r && r.options && r.options.length);
  }
  get message() {
    return (this.result && this.result.message) || null;
  }
  get truncated() {
    return !!(this.result && this.result.truncated);
  }
  get rateNote() {
    const r = this.result;
    return this.currencyCode === "USD" && r && r.rateStartDate
      ? `Converted at the USD rate of ${r.rateStartDate}.`
      : null;
  }
  get handoffLabel() {
    return `Handoff cost (${this.currencyCode})`;
  }
  /** Use as cost fills the lane's price editor, so only in the lane's own currency (R88). */
  get canUseAsCost() {
    return !!this.allowUseAsCost && this.currencyCode === this.laneCurrency;
  }
  get useAsCostOff() {
    return this.allowUseAsCost &&
      this.laneCurrency &&
      this.hasOptions &&
      !this.canUseAsCost
      ? `Switch to ${this.laneCurrency} to use a split cost.`
      : null;
  }
  get directMedianText() {
    const median = directMedian(this.statsByCurrency || {}, this.currencyCode);
    return isNumber(median)
      ? `Direct median ${amountText(median, this.currencyCode)}`
      : null;
  }
  get options() {
    const r = this.result;
    if (!r || !r.options) {
      return [];
    }
    const code = this.currencyCode;
    return r.options.map((option, index) => {
      const key = `${option.kind}-${index}`;
      const isEstimate = option.kind === ESTIMATE;
      const handoffText = this.handoffCosts[key] ?? "";
      const total = optionTotal(option, handoffText);
      let totalText = null;
      if (total !== null) {
        totalText = isEstimate
          ? `Estimate total ${amountText(total, code)}`
          : `Total per shipment, median ${amountText(total, code)} (${option.pricedShipments} shipments)`;
      }
      return {
        key,
        index,
        isEstimate,
        title: isEstimate
          ? `Estimate via ${option.handoffLabel} · +${option.extraDistancePct} % distance`
          : `Via ${option.handoffLabel} · ${option.shipments} shipments`,
        legs: (option.legs || []).map((leg) => legView(leg, code)),
        handoffText,
        totalText,
        canUse: this.canUseAsCost && total !== null
      };
    });
  }

  handleOpen() {
    this.opened = true;
    this.currencyCode = this.startCurrency === "USD" ? "USD" : "CAD";
    this.load();
  }
  handleCad() {
    this.pick("CAD");
  }
  handleUsd() {
    this.pick("USD");
  }

  /** Another currency: typed handoff costs are cleared, and a kept answer shows without a call. */
  pick(code) {
    if (code === this.currencyCode) {
      return;
    }
    this.currencyCode = code;
    this.handoffCosts = {};
    this.error = null;
    if (this.answers[code]) {
      this.seq += 1;
      this.loading = false;
      return;
    }
    this.load();
  }

  handleRetry() {
    this.attempt += 1;
    this.load();
  }

  handleHandoff(event) {
    this.handoffCosts = {
      ...this.handoffCosts,
      [event.currentTarget.dataset.option]: event.detail.value
    };
  }

  handleUseAsCost(event) {
    const r = this.result;
    const index = Number(event.currentTarget.dataset.index);
    const option = r && r.options ? r.options[index] : null;
    if (!option || !this.canUseAsCost) {
      return;
    }
    const total = optionTotal(
      option,
      this.handoffCosts[`${option.kind}-${index}`]
    );
    if (total === null) {
      return;
    }
    this.dispatchEvent(
      new CustomEvent("useascost", {
        detail: {
          cost: Math.round(total * 100) / 100,
          currencyCode: this.currencyCode
        }
      })
    );
  }

  async load() {
    const seq = ++this.seq;
    const generation = this.generation;
    const code = this.currencyCode;
    this.loading = true;
    this.error = null;
    try {
      const result = await splitOptions({
        requestJson: this._requestJson,
        currencyCode: code,
        attempt: this.attempt
      });
      if (generation === this.generation) {
        this.answers = { ...this.answers, [code]: result || { options: [] } };
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
}
