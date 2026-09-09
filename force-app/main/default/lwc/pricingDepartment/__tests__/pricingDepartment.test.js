import { createElement } from "lwc";
import PricingDepartment from "c/pricingDepartment";
import getCarrierQuotes from "@salesforce/apex/PricingDepartmentController.getCarrierQuotes";

jest.mock(
  "@salesforce/apex/PricingDepartmentController.getCarrierQuotes",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const QUOTES = [
  {
    Id: "a",
    CAD_Quote_Total__c: 100,
    Mode__c: "LTL",
    Origin__c: "Montreal, Quebec"
  },
  {
    Id: "b",
    CAD_Quote_Total__c: 300,
    Mode__c: "Truckload",
    Origin__c: "Toronto, Ontario"
  },
  {
    Id: "c",
    CAD_Quote_Total__c: 0,
    Mode__c: "Truckload",
    Origin__c: "Laval, Quebec"
  }
];

const flush = () => Promise.resolve().then(() => Promise.resolve());

async function mount() {
  const element = createElement("c-pricing-department", {
    is: PricingDepartment
  });
  document.body.appendChild(element);
  await flush();
  return element;
}

async function openCarrierModal(element) {
  element.shadowRoot.querySelector("div[data-id]").click();
  await flush();
  return element.shadowRoot.querySelector('section[role="dialog"]');
}

function checkbox(element, name) {
  return element.shadowRoot.querySelector(
    `input[type="checkbox"][data-filter="${name}"]`
  );
}

function statValueFor(element, label) {
  const rows = element.shadowRoot.querySelectorAll(
    "table tbody tr.slds-hint-parent"
  );
  for (const row of rows) {
    const th = row.querySelector("th");
    if (th && th.textContent.trim() === label) {
      return row.querySelector("td").textContent.trim();
    }
  }
  return null;
}

describe("c-pricing-department", () => {
  beforeEach(() => {
    getCarrierQuotes.mockResolvedValue(QUOTES);
  });
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("loads quotes on connect with the default 5-day window", async () => {
    await mount();
    expect(getCarrierQuotes).toHaveBeenCalledTimes(1);
    expect(getCarrierQuotes.mock.calls[0][0]).toMatchObject({
      dateRangeFilter: "5",
      originFilter: ""
    });
  });

  it("renders one row per quote and the computed statistics", async () => {
    const element = await mount();
    const rows = element.shadowRoot.querySelectorAll("tbody tr[data-index]");
    expect(rows.length).toBe(3);
    expect(statValueFor(element, "Total quotes")).toBe("3");
    expect(statValueFor(element, "Quotes with no zero")).toBe("2");
  });

  it("toggling the accepted-quotes checkbox sets the filter without throwing", async () => {
    const element = await mount();
    const box = checkbox(element, "accepted");
    box.checked = true;
    // Guards the historical ReferenceError; the toHaveBeenLastCalledWith below is the
    // load-bearing assertion that the handler actually set the filter.
    expect(() => box.dispatchEvent(new CustomEvent("change"))).not.toThrow();
    await flush();
    element.shadowRoot.querySelector("button.slds-button_brand").click();
    await flush();
    expect(getCarrierQuotes).toHaveBeenLastCalledWith(
      expect.objectContaining({ acceptedQuotesFilter: "true" })
    );
  });

  it("each checkbox maps to its filter value", async () => {
    const element = await mount();
    const expectations = [
      ["hazmat", "hazmatFilter", "Hazmat"],
      ["marketTest", "priceDepFilter", "Market Test"],
      ["declined", "declinedQuotesFilter", "true"]
    ];
    for (const [name] of expectations) {
      const box = checkbox(element, name);
      box.checked = true;
      box.dispatchEvent(new CustomEvent("change"));
    }
    await flush();
    element.shadowRoot.querySelector("button.slds-button_brand").click();
    await flush();
    const args = getCarrierQuotes.mock.calls.at(-1)[0];
    for (const [, param, value] of expectations) {
      expect(args[param]).toBe(value);
    }
  });

  it("reset restores defaults and reloads", async () => {
    const element = await mount();
    checkbox(element, "hazmat").checked = true;
    checkbox(element, "hazmat").dispatchEvent(new CustomEvent("change"));
    element.shadowRoot.querySelector("button.slds-button_destructive").click();
    await flush();
    const args = getCarrierQuotes.mock.calls.at(-1)[0];
    expect(args).toMatchObject({
      hazmatFilter: "",
      dateRangeFilter: "5",
      acceptedQuotesFilter: ""
    });
  });

  it("clicking inside the carrier modal keeps it open", async () => {
    const element = await mount();
    const dialog = await openCarrierModal(element);
    expect(dialog).not.toBeNull();

    dialog.dispatchEvent(new CustomEvent("click", { bubbles: true }));
    await flush();

    expect(
      element.shadowRoot.querySelector('section[role="dialog"]')
    ).not.toBeNull();
  });

  it("clicking the backdrop closes the carrier modal", async () => {
    const element = await mount();
    expect(await openCarrierModal(element)).not.toBeNull();

    element.shadowRoot
      .querySelector(".modal-wrapper")
      .dispatchEvent(new CustomEvent("click", { bubbles: true }));
    await flush();

    expect(
      element.shadowRoot.querySelector('section[role="dialog"]')
    ).toBeNull();
  });

  it("shows the error block when Apex rejects", async () => {
    getCarrierQuotes.mockRejectedValue(new Error("boom"));
    const element = await mount();
    expect(
      element.shadowRoot.querySelectorAll("tbody tr[data-index]").length
    ).toBe(0);
    expect(element.shadowRoot.textContent).toMatch(/error/i);
  });
});
