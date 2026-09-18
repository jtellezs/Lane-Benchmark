import { LightningElement, track } from "lwc";
import getRates from "@salesforce/apex/MarketTestController.getRates";
import saveRate from "@salesforce/apex/MarketTestController.saveRate";
import deleteRate from "@salesforce/apex/MarketTestController.deleteRate";
import search from "@salesforce/apex/LaneBenchmarkController.search";
import USER_ID from "@salesforce/user/Id";

const CURRENCIES = [
  { label: "CAD", value: "CAD" },
  { label: "USD", value: "USD" }
];

/**
 * Phase 9: record what carriers quote for one lane now, and read it against what the lane has
 * done historically. The rates are ordinary lane bids, so they join every median the app shows.
 */
export default class MarketTest extends LightningElement {
  originKey = null;
  originLabel = "";
  destinationKey = null;
  destinationLabel = "";
  currency = "CAD";

  @track rates = [];
  history = null;
  error = null;
  loading = false;
  adding = false;

  currencyOptions = CURRENCIES;

  get hasLane() {
    return !!(this.originKey && this.destinationKey);
  }

  get laneLabel() {
    return this.hasLane
      ? `${this.originLabel} → ${this.destinationLabel}`
      : "Pick both ends of the lane";
  }

  get hasRates() {
    return this.rates.length > 0;
  }

  /** The rates on screen, with edit and delete offered only on the ones you recorded. */
  get rows() {
    return this.rates.map((r) => ({
      ...r,
      mine: r.OwnerId === USER_ID,
      rateText: `${Number(r.Rate__c).toLocaleString()} ${r.CurrencyIsoCode}`,
      carrier: r.Carrier_Display__c || r.Carrier_Name__c || "Carrier"
    }));
  }

  /** Count, median and spread of what has been gathered, so the pricer reads it at a glance. */
  get summary() {
    const amounts = this.rates
      .map((r) => Number(r.Rate__c))
      .filter((n) => !Number.isNaN(n))
      .sort((a, b) => a - b);
    if (!amounts.length) {
      return null;
    }
    const middle = Math.floor(amounts.length / 2);
    const median =
      amounts.length % 2
        ? amounts[middle]
        : (amounts[middle - 1] + amounts[middle]) / 2;
    return {
      count: amounts.length,
      median: median.toLocaleString(),
      min: amounts[0].toLocaleString(),
      max: amounts[amounts.length - 1].toLocaleString(),
      currency: this.currency
    };
  }

  get historyLine() {
    if (!this.history) {
      return "";
    }
    const stats = this.history.statsByCurrency?.[this.currency];
    if (!stats || !stats.count) {
      return "No history for this lane in the last 90 days.";
    }
    return `${stats.count} in the last 90 days · median ${Number(
      stats.median
    ).toLocaleString()} ${this.currency} · ${Number(
      stats.min
    ).toLocaleString()}–${Number(stats.max).toLocaleString()}`;
  }

  handleOrigin(event) {
    this.originKey = event.detail.key;
    this.originLabel = event.detail.label;
    this.refresh();
  }

  handleDestination(event) {
    this.destinationKey = event.detail.key;
    this.destinationLabel = event.detail.label;
    this.refresh();
  }

  handleCurrency(event) {
    this.currency = event.detail.value;
    this.refresh();
  }

  handleAdd() {
    this.adding = true;
  }

  handleCancel() {
    this.adding = false;
  }

  async handleSave(event) {
    this.error = null;
    try {
      await saveRate({
        rateJson: JSON.stringify({
          ...event.detail.bid,
          CurrencyIsoCode: this.currency
        }),
        originKey: this.originKey,
        destinationKey: this.destinationKey
      });
      this.adding = false;
      await this.loadRates();
    } catch (e) {
      this.error = this.messageOf(e);
    }
  }

  async handleDelete(event) {
    this.error = null;
    try {
      await deleteRate({ rateId: event.target.dataset.id });
      await this.loadRates();
    } catch (e) {
      this.error = this.messageOf(e);
    }
  }

  refresh() {
    if (!this.hasLane) {
      this.rates = [];
      this.history = null;
      return;
    }
    this.loadRates();
    this.loadHistory();
  }

  async loadRates() {
    this.loading = true;
    try {
      this.rates = await getRates({
        originKey: this.originKey,
        destinationKey: this.destinationKey
      });
    } catch (e) {
      this.error = this.messageOf(e);
      this.rates = [];
    } finally {
      this.loading = false;
    }
  }

  async loadHistory() {
    try {
      this.history = await search({
        requestJson: JSON.stringify({
          originKey: this.originKey,
          destinationKey: this.destinationKey,
          originPrecision: "CITY",
          destinationPrecision: "CITY",
          lookbackDays: 90,
          currencyIsoCode: this.currency
        })
      });
    } catch {
      // a lane with no history is normal here: the page still records rates
      this.history = null;
    }
  }

  messageOf(e) {
    return (
      e?.body?.message || e?.message || "Something went wrong. Please retry."
    );
  }
}
