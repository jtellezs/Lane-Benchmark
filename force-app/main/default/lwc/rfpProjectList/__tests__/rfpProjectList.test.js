import { createElement } from "lwc";
import RfpProjectList from "c/rfpProjectList";
import listProjects from "@salesforce/apex/RfpProjectController.listProjects";
import saveProject from "@salesforce/apex/RfpProjectController.saveProject";

jest.mock(
  "@salesforce/apex/RfpProjectController.listProjects",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/RfpProjectController.saveProject",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
// c-rfp-account-picker is rendered by the new-project form.
jest.mock(
  "@salesforce/apex/RfpProjectController.searchAccounts",
  () => ({ default: jest.fn(() => Promise.resolve([])) }),
  { virtual: true }
);

const flush = () => Promise.resolve().then(() => Promise.resolve());

const PROJECTS = [
  {
    Id: "a0P1",
    Name: "Costco Q4",
    Customer__r: { Name: "Costco" },
    Status__c: "Pricing",
    Due_Date__c: "2026-10-01",
    Lane_Count__c: 12,
    Costed_Count__c: 4,
    Sold_Count__c: 3,
    CurrencyIsoCode: "CAD"
  },
  {
    Id: "a0P2",
    Name: "Walmart lanes",
    Customer__r: { Name: "Walmart" },
    Status__c: "Draft",
    Lane_Count__c: 0
  }
];

async function mount() {
  const el = createElement("c-rfp-project-list", { is: RfpProjectList });
  document.body.appendChild(el);
  await flush();
  await flush();
  return el;
}

const field = (el, id) => el.shadowRoot.querySelector(`[data-id="${id}"]`);
function change(el, id, value) {
  const node = field(el, id);
  node.value = value;
  node.dispatchEvent(new CustomEvent("change", { detail: { value } }));
}

describe("c-rfp-project-list", () => {
  beforeEach(() => {
    listProjects.mockResolvedValue(PROJECTS);
    saveProject.mockResolvedValue({ Id: "a0P9", Name: "New one" });
  });

  afterEach(() => {
    jest.clearAllMocks();
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("renders one row per project and opens the clicked one", async () => {
    const el = await mount();
    const rows = el.shadowRoot.querySelectorAll('[data-id="project-row"]');
    expect(rows.length).toBe(2);
    expect(rows[0].textContent).toContain("Costco Q4");
    expect(rows[0].textContent).toContain("Costco");

    const opened = jest.fn();
    el.addEventListener("open", opened);
    rows[1].querySelector("button").click();
    await flush();
    expect(opened.mock.calls[0][0].detail).toEqual({ projectId: "a0P2" });
  });

  it("shows the empty state and the Apex error text", async () => {
    listProjects.mockResolvedValue([]);
    const el = await mount();
    expect(el.shadowRoot.textContent).toContain("No RFP projects yet.");

    listProjects.mockRejectedValue({ body: { message: "no access" } });
    const el2 = await mount();
    expect(field(el2, "error").textContent).toContain("no access");
  });

  it("keeps the help hint out of the list heading's name", async () => {
    const el = await mount();
    const heading = [...el.shadowRoot.querySelectorAll("h2")].find((h) =>
      h.textContent.includes("RFP projects")
    );
    expect(heading.textContent.trim()).toBe("RFP projects");
    // The hint's button carries assistive text, so a hint inside the h2 is
    // read out as part of the heading's name.
    expect(heading.querySelector("c-help-hint")).toBeNull();
    const hints = [...el.shadowRoot.querySelectorAll("c-help-hint")].filter(
      (h) => h.topic === "rfp-projects"
    );
    expect(hints.length).toBe(1);
  });

  it("creates a project from the form and emits open", async () => {
    const el = await mount();
    const opened = jest.fn();
    el.addEventListener("open", opened);

    expect(field(el, "create").disabled).toBe(true);

    change(el, "name", "Costco Q1");
    el.shadowRoot.querySelector("c-rfp-account-picker").dispatchEvent(
      new CustomEvent("accountchange", {
        detail: { id: "001x", name: "Costco" }
      })
    );
    await flush();
    change(el, "due-date", "2026-12-01");
    change(el, "currency", "USD");
    change(el, "default-margin", "20");
    await flush();

    expect(field(el, "create").disabled).toBe(false);
    field(el, "create").click();
    await flush();
    await flush();

    expect(saveProject).toHaveBeenCalledTimes(1);
    const posted = JSON.parse(saveProject.mock.calls[0][0].projectJson);
    expect(posted).toEqual({
      Name: "Costco Q1",
      Customer__c: "001x",
      Due_Date__c: "2026-12-01",
      CurrencyIsoCode: "USD",
      Default_Margin__c: 20,
      Status__c: "Draft"
    });
    expect(opened.mock.calls[0][0].detail).toEqual({ projectId: "a0P9" });
  });

  it("defaults the currency to CAD and the margin to 15", async () => {
    const el = await mount();
    change(el, "name", "Plain project");
    el.shadowRoot.querySelector("c-rfp-account-picker").dispatchEvent(
      new CustomEvent("accountchange", {
        detail: { id: "001y", name: "Metro" }
      })
    );
    await flush();
    field(el, "create").click();
    await flush();
    await flush();
    const posted = JSON.parse(saveProject.mock.calls[0][0].projectJson);
    expect(posted.CurrencyIsoCode).toBe("CAD");
    expect(posted.Default_Margin__c).toBe(15);
    expect(posted.Due_Date__c).toBeNull();
  });

  it("keeps the form open and shows the error when the save fails", async () => {
    saveProject.mockRejectedValue({ body: { message: "name is required" } });
    const el = await mount();
    const opened = jest.fn();
    el.addEventListener("open", opened);
    change(el, "name", "Bad");
    el.shadowRoot.querySelector("c-rfp-account-picker").dispatchEvent(
      new CustomEvent("accountchange", {
        detail: { id: "001z", name: "Metro" }
      })
    );
    await flush();
    field(el, "create").click();
    await flush();
    await flush();
    expect(field(el, "error").textContent).toContain("name is required");
    expect(opened).not.toHaveBeenCalled();
  });
});
