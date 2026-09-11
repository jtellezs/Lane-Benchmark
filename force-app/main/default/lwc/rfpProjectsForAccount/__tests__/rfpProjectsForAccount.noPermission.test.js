import { createElement } from "lwc";
import RfpProjectsForAccount from "c/rfpProjectsForAccount";
import { getRecord } from "lightning/uiRecordApi";
import projectsForAccount from "@salesforce/apex/RfpController.projectsForAccount";

jest.mock("@salesforce/customPermission/RFP_Tool", () => ({ default: false }), {
  virtual: true
});

jest.mock(
  "@salesforce/apex/RfpController.projectsForAccount",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);

const flush = () => Promise.resolve().then(() => Promise.resolve());

describe("c-rfp-projects-for-account without the RFP_Tool custom permission", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("renders nothing for a Customer account and never wires the Apex adapter with an accountId", async () => {
    const el = createElement("c-rfp-projects-for-account", {
      is: RfpProjectsForAccount
    });
    el.recordId = "001x";
    document.body.appendChild(el);
    await flush();
    getRecord.emit({
      fields: {
        RecordType: {
          value: { fields: { DeveloperName: { value: "Customer" } } }
        }
      }
    });
    await flush();
    expect(el.shadowRoot.querySelector("lightning-card")).toBeNull();
    const lastConfig = projectsForAccount.getLastConfig();
    expect(lastConfig ? lastConfig.accountId : undefined).toBeUndefined();
  });
});
