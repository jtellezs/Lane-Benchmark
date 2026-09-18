import { LightningElement, track } from "lwc";
import listProjects from "@salesforce/apex/RfpProjectController.listProjects";
import saveProject from "@salesforce/apex/RfpProjectController.saveProject";

const CURRENCIES = [
  { label: "CAD", value: "CAD" },
  { label: "USD", value: "USD" }
];
const DEFAULT_MARGIN = "15";
const apexMessage = (e, fallback) =>
  (e && e.body && e.body.message) || fallback;
const count = (v) => (v === null || v === undefined ? 0 : v);

export default class RfpProjectList extends LightningElement {
  @track projects = [];
  error = null;
  loading = false;
  saving = false;

  name = "";
  customerId = null;
  customerName = "";
  dueDate = "";
  currency = "CAD";
  defaultMargin = DEFAULT_MARGIN;

  connectedCallback() {
    this.load();
  }

  async load() {
    this.loading = true;
    try {
      this.projects = (await listProjects()) || [];
      this.error = null;
    } catch (e) {
      this.projects = [];
      this.error = apexMessage(e, "RFP projects could not be loaded.");
    } finally {
      this.loading = false;
    }
  }

  get currencyOptions() {
    return CURRENCIES;
  }
  get hasProjects() {
    return this.projects.length > 0;
  }
  get isEmpty() {
    return !this.loading && !this.hasProjects;
  }
  get cannotCreate() {
    // A project with no customer is a market test: the server attaches it to the Market Test
    // account, where the whole pricing team can work it (owner, 2026-09-18).
    return !this.name.trim() || this.saving;
  }

  get rows() {
    return this.projects.map((p) => ({
      id: p.Id,
      name: p.Name,
      customer: p.Customer__r ? p.Customer__r.Name : "",
      status: p.Status__c || "",
      due: p.Due_Date__c || "",
      lanes: count(p.Lane_Count__c),
      costed: count(p.Costed_Count__c),
      sold: count(p.Sold_Count__c),
      file: p.Source_File_Name__c || ""
    }));
  }

  handleOpen(event) {
    this.dispatchEvent(
      new CustomEvent("open", {
        detail: { projectId: event.currentTarget.dataset.projectId }
      })
    );
  }

  handleName(event) {
    this.name = event.detail.value || "";
  }
  handleDueDate(event) {
    this.dueDate = event.detail.value || "";
  }
  handleCurrency(event) {
    this.currency = event.detail.value;
  }
  handleMargin(event) {
    this.defaultMargin = event.detail.value;
  }
  handleAccount(event) {
    this.customerId = event.detail.id;
    this.customerName = event.detail.name;
  }

  async handleCreate() {
    if (this.cannotCreate) {
      return;
    }
    this.saving = true;
    this.error = null;
    const margin = Number(this.defaultMargin);
    try {
      const saved = await saveProject({
        projectJson: JSON.stringify({
          Name: this.name.trim(),
          Customer__c: this.customerId,
          Due_Date__c: this.dueDate || null,
          CurrencyIsoCode: this.currency,
          Default_Margin__c: Number.isFinite(margin) ? margin : null,
          Status__c: "Draft"
        })
      });
      this.dispatchEvent(
        new CustomEvent("open", { detail: { projectId: saved.Id } })
      );
    } catch (e) {
      this.error = apexMessage(e, "The project could not be created.");
    } finally {
      this.saving = false;
    }
  }
}
