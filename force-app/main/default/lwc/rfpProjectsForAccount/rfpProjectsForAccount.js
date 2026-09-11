import { LightningElement, api, wire } from "lwc";
import { getRecord } from "lightning/uiRecordApi";
import { NavigationMixin } from "lightning/navigation";
import hasRfpTool from "@salesforce/customPermission/RFP_Tool";
import projectsForAccount from "@salesforce/apex/RfpController.projectsForAccount";

const RT_FIELD = "Account.RecordType.DeveloperName";
const CUSTOMER_TYPES = new Set(["Customer", "New_Customer"]);

export default class RfpProjectsForAccount extends NavigationMixin(
  LightningElement
) {
  @api recordId;
  recordTypeName = null;
  projects = [];
  error = null;

  @wire(getRecord, { recordId: "$recordId", fields: [RT_FIELD] })
  wiredAccount({ data, error }) {
    if (data) {
      this.recordTypeName =
        data.fields?.RecordType?.value?.fields?.DeveloperName?.value ?? null;
    } else if (error) {
      this.recordTypeName = null;
    }
  }

  get wiredAccountId() {
    return hasRfpTool ? this.recordId : undefined;
  }

  @wire(projectsForAccount, { accountId: "$wiredAccountId" })
  wiredProjects({ data, error }) {
    if (data) {
      this.projects = data.map((p) => ({
        ...p,
        files: (p.fileNames || []).join(", ")
      }));
      this.error = null;
    } else if (error) {
      this.projects = [];
      this.error = error?.body?.message || "RFP projects could not be loaded.";
    }
  }

  get isCustomer() {
    return CUSTOMER_TYPES.has(this.recordTypeName);
  }
  get isVisible() {
    return this.isCustomer && hasRfpTool === true;
  }
  get hasProjects() {
    return this.projects.length > 0;
  }

  /**
   * The workbench, not the project's record page: c-rfp-tool reads
   * c__projectId off the page reference and opens that project.
   */
  handleOpen(event) {
    const id = event.currentTarget.dataset.id;
    this[NavigationMixin.Navigate]({
      type: "standard__navItemPage",
      attributes: { apiName: "RFP_Tool" },
      state: { c__projectId: id }
    });
  }
}
