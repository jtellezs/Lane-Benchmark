import { LightningElement, api, track } from "lwc";
import getRates from "@salesforce/apex/MarketTestController.getRates";
import saveRate from "@salesforce/apex/MarketTestController.saveRate";
import deleteRate from "@salesforce/apex/MarketTestController.deleteRate";
import USER_ID from "@salesforce/user/Id";

/**
 * Phase 9: the market test, on the lane the pricer has already searched. It carries only the
 * capture half - what carriers quote for this lane now - because the statistics card above
 * already shows what the lane has done. Each rate is an ordinary lane bid, so it joins the
 * median that card reports.
 */
export default class MarketTestRates extends LightningElement {
  @api currencyCode;

  _requestJson = null;
  originKey = null;
  destinationKey = null;

  @track rates = [];
  error = null;
  adding = false;

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
    this.readLane();
    this.load();
  }

  readLane() {
    this.originKey = null;
    this.destinationKey = null;
    if (!this._requestJson) {
      return;
    }
    try {
      const request = JSON.parse(this._requestJson);
      this.originKey = request.originKey || null;
      this.destinationKey = request.destinationKey || null;
    } catch {
      // a request we cannot read leaves the card closed rather than breaking the page
      this.originKey = null;
    }
  }

  get hasLane() {
    return !!(this.originKey && this.destinationKey);
  }

  get hasRates() {
    return (this.rates || []).length > 0;
  }

  get rows() {
    return (this.rates || []).map((r) => ({
      ...r,
      mine: r.OwnerId === USER_ID,
      rateText: `${Number(r.Rate__c).toLocaleString()} ${r.CurrencyIsoCode}`,
      carrier: r.Carrier_Display__c || r.Carrier_Name__c || "Carrier"
    }));
  }

  /** Count, median and spread of what has been gathered, beside the lane's own history above. */
  get summary() {
    const amounts = (this.rates || [])
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
      max: amounts[amounts.length - 1].toLocaleString()
    };
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
          CurrencyIsoCode: this.currencyCode || "CAD"
        }),
        originKey: this.originKey,
        destinationKey: this.destinationKey
      });
      this.adding = false;
      await this.load();
    } catch (e) {
      this.error = this.messageOf(e);
    }
  }

  async handleDelete(event) {
    this.error = null;
    try {
      await deleteRate({ rateId: event.target.dataset.id });
      await this.load();
    } catch (e) {
      this.error = this.messageOf(e);
    }
  }

  async load() {
    if (!this.hasLane) {
      this.rates = [];
      return;
    }
    try {
      // Always an array: an Apex call that resolves to nothing must not break the whole
      // Lane Benchmark page this card sits on.
      const found = await getRates({
        originKey: this.originKey,
        destinationKey: this.destinationKey
      });
      this.rates = found || [];
    } catch (e) {
      this.error = this.messageOf(e);
      this.rates = [];
    }
  }

  messageOf(e) {
    return (
      e?.body?.message || e?.message || "Something went wrong. Please retry."
    );
  }
}
