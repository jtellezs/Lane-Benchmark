import { createElement } from "lwc";
import RfpProjectsForAccount from "c/rfpProjectsForAccount";
import { getRecord } from "lightning/uiRecordApi";
import projectsForAccount from "@salesforce/apex/RfpController.projectsForAccount";

jest.mock(
  "@salesforce/apex/RfpController.projectsForAccount",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);

const flush = () => Promise.resolve().then(() => Promise.resolve());

async function mount(recordId) {
  const el = createElement("c-rfp-projects-for-account", {
    is: RfpProjectsForAccount
  });
  el.recordId = recordId;
  document.body.appendChild(el);
  await flush();
  return el;
}

describe("c-rfp-projects-for-account", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("renders projects for a Customer account and nothing for a Carrier", async () => {
    const el = await mount("001x");
    getRecord.emit({
      fields: {
        RecordType: {
          value: { fields: { DeveloperName: { value: "Customer" } } }
        }
      }
    });
    await flush();
    projectsForAccount.emit([
      {
        id: "a1",
        name: "Costco Q4",
        status: "Pricing",
        dueDate: "2026-10-01",
        laneCount: 12,
        costedCount: 4,
        soldCount: 3,
        bidCount: 5,
        fileNames: ["lanes.xlsx"]
      }
    ]);
    await flush();
    const rows = el.shadowRoot.querySelectorAll('[data-id="project-row"]');
    expect(rows.length).toBe(1);
    expect(rows[0].textContent).toContain("Costco Q4");
    expect(rows[0].textContent).toContain("lanes.xlsx");

    getRecord.emit({
      fields: {
        RecordType: {
          value: { fields: { DeveloperName: { value: "Carrier" } } }
        }
      }
    });
    await flush();
    expect(el.shadowRoot.querySelector("lightning-card")).toBeNull();
  });

  it("shows the empty state and the error text", async () => {
    const el = await mount("001y");
    getRecord.emit({
      fields: {
        RecordType: {
          value: { fields: { DeveloperName: { value: "New_Customer" } } }
        }
      }
    });
    await flush();
    projectsForAccount.emit([]);
    await flush();
    expect(el.shadowRoot.textContent).toContain("No RFP projects yet.");
    projectsForAccount.emitError({ body: { message: "boom" } });
    await flush();
    expect(el.shadowRoot.querySelector('[data-id="error"]').textContent).toBe(
      "boom"
    );
  });
});
