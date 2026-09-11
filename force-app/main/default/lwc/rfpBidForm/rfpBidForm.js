import { LightningElement, api } from "lwc";

const CURRENCIES = [
  { label: "CAD", value: "CAD" },
  { label: "USD", value: "USD" }
];
const DEFAULT_VALID_DAYS = 30;

/** Local-calendar ISO date: a UTC round trip would slide the day across zones. */
function isoDate(date) {
  const pad = (n) => String(n).padStart(2, "0");
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
}

function inDays(days) {
  const d = new Date();
  d.setDate(d.getDate() + days);
  return isoDate(d);
}

function num(value) {
  if (value === null || value === undefined || String(value).trim() === "") {
    return null;
  }
  const n = Number(value);
  return Number.isFinite(n) ? n : null;
}

function trimmed(value) {
  const s = value === null || value === undefined ? "" : String(value).trim();
  return s === "" ? null : s;
}

export default class RfpBidForm extends LightningElement {
  @api laneId;

  _currency = "CAD";
  _bid = null;

  @api
  get currency() {
    return this._currency;
  }
  set currency(val) {
    this._currency = val || "CAD";
    // Seeds the editable currency only while the form is still blank, so
    // reopening an existing bid keeps the currency it was saved with.
    if (!this._bid) {
      this.currencyIso = this._currency;
    }
  }

  @api
  get bid() {
    return this._bid;
  }
  set bid(value) {
    this._bid = value || null;
    if (!value) {
      return;
    }
    this.bidId = value.Id || null;
    this.carrierId = value.Carrier__c || null;
    this.carrierLabel = value.Carrier_Display__c || "";
    this.newCarrier = !value.Carrier__c && !!value.Carrier_Name__c;
    this.typedName = value.Carrier_Name__c || "";
    this.contactName = value.Contact_Name__c || "";
    this.contactEmail = value.Contact_Email__c || "";
    this.contactPhone = value.Contact_Phone__c || "";
    this.rate = value.Rate__c === undefined ? null : value.Rate__c;
    this.currencyIso = value.CurrencyIsoCode || this._currency;
    this.fsc =
      value.Fuel_Surcharge__c === undefined ? null : value.Fuel_Surcharge__c;
    this.fscIncluded = !!value.FSC_Included__c;
    this.transitDays =
      value.Transit_Days__c === undefined ? null : value.Transit_Days__c;
    this.validFrom = value.Valid_From__c || this.validFrom;
    this.expiresOn = value.Expires_On__c || this.expiresOn;
    this.notes = value.Notes__c || "";
  }

  bidId = null;
  carrierId = null;
  carrierLabel = "";
  newCarrier = false;
  typedName = "";
  contactName = "";
  contactEmail = "";
  contactPhone = "";
  rate = null;
  currencyIso = "CAD";
  fsc = null;
  fscIncluded = false;
  transitDays = null;
  validFrom = isoDate(new Date());
  expiresOn = inDays(DEFAULT_VALID_DAYS);
  notes = "";
  error = null;

  currencyOptions = CURRENCIES;

  get saveLabel() {
    return this.bidId ? "Update bid" : "Save bid";
  }

  handleCarrier(event) {
    this.carrierId = event.detail.id;
    this.carrierLabel = event.detail.name;
  }
  handleNewCarrier(event) {
    this.newCarrier = !!event.detail.checked;
  }
  handleCarrierName(event) {
    this.typedName = event.detail.value;
  }
  handleContactName(event) {
    this.contactName = event.detail.value;
  }
  handleContactEmail(event) {
    this.contactEmail = event.detail.value;
  }
  handleContactPhone(event) {
    this.contactPhone = event.detail.value;
  }
  handleRate(event) {
    this.rate = event.detail.value;
  }
  handleCurrency(event) {
    this.currencyIso = event.detail.value;
  }
  handleFsc(event) {
    this.fsc = event.detail.value;
  }
  handleFscIncluded(event) {
    this.fscIncluded = !!event.detail.checked;
  }
  handleTransit(event) {
    this.transitDays = event.detail.value;
  }
  handleValidFrom(event) {
    this.validFrom = event.detail.value;
  }
  handleExpiresOn(event) {
    this.expiresOn = event.detail.value;
  }
  handleNotes(event) {
    this.notes = event.detail.value;
  }

  handleCancel() {
    this.dispatchEvent(new CustomEvent("cancel"));
  }

  handleSave() {
    const rate = num(this.rate);
    if (!(rate > 0)) {
      this.error = "Enter a rate above zero.";
      return;
    }
    const typed = this.newCarrier ? trimmed(this.typedName) : null;
    if (!this.newCarrier && !this.carrierId) {
      this.error = "Pick a carrier, or switch on a carrier not in the system.";
      return;
    }
    if (this.newCarrier && !typed) {
      this.error = "Name the carrier that is not in the system.";
      return;
    }
    this.error = null;

    const bid = {
      RFP_Lane__c: this.laneId,
      Carrier__c: this.newCarrier ? null : this.carrierId,
      Contact_Name__c: trimmed(this.contactName),
      Contact_Email__c: trimmed(this.contactEmail),
      Contact_Phone__c: trimmed(this.contactPhone),
      Rate__c: rate,
      CurrencyIsoCode: this.currencyIso,
      Fuel_Surcharge__c: num(this.fsc),
      FSC_Included__c: !!this.fscIncluded,
      Transit_Days__c: num(this.transitDays),
      Valid_From__c: this.validFrom || null,
      Expires_On__c: this.expiresOn || null,
      Notes__c: trimmed(this.notes)
    };
    if (typed) {
      bid.Carrier_Name__c = typed;
    }
    if (this.bidId) {
      bid.Id = this.bidId;
    }
    this.dispatchEvent(new CustomEvent("save", { detail: { bid } }));
  }
}
