import { LightningElement, wire } from "lwc";
import {
  APPLICATION_SCOPE,
  MessageContext,
  publish,
  subscribe,
  unsubscribe
} from "lightning/messageService";
import DISTANCE_UNIT from "@salesforce/messageChannel/Distance_Unit__c";
import { readUnit, writeUnit } from "c/distanceUnit";

const BUTTON_ON = "slds-button slds-button_brand";
const BUTTON_OFF = "slds-button slds-button_neutral";

export default class DistanceUnitToggle extends LightningElement {
  @wire(MessageContext) messageContext;
  unit = readUnit();
  unitSubscription = null;

  connectedCallback() {
    if (!this.unitSubscription) {
      this.unitSubscription = subscribe(
        this.messageContext,
        DISTANCE_UNIT,
        (message) => this.handleMessage(message),
        { scope: APPLICATION_SCOPE }
      );
    }
  }

  disconnectedCallback() {
    if (this.unitSubscription) {
      unsubscribe(this.unitSubscription);
    }
    this.unitSubscription = null;
  }

  get miClass() {
    return this.unit === "mi" ? BUTTON_ON : BUTTON_OFF;
  }
  get kmClass() {
    return this.unit === "km" ? BUTTON_ON : BUTTON_OFF;
  }
  get miPressed() {
    return this.unit === "mi" ? "true" : "false";
  }
  get kmPressed() {
    return this.unit === "km" ? "true" : "false";
  }

  /** Another toggle on the page changed the unit: follow it, without publishing back. */
  handleMessage(message) {
    const unit = message && message.unit;
    if (unit === "mi" || unit === "km") {
      this.unit = unit;
    }
  }

  handleMi() {
    this.pick("mi");
  }
  handleKm() {
    this.pick("km");
  }

  pick(unit) {
    if (unit === this.unit) {
      return;
    }
    this.unit = unit;
    writeUnit(unit);
    publish(this.messageContext, DISTANCE_UNIT, { unit });
  }
}
