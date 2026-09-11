import { createElement } from "lwc";
import RfpBidForm from "c/rfpBidForm";

// c-rfp-account-picker is rendered for the carrier lookup and it imports Apex.
jest.mock(
  "@salesforce/apex/RfpProjectController.searchAccounts",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const flush = () => Promise.resolve().then(() => Promise.resolve());

function isoDate(date) {
  const pad = (n) => String(n).padStart(2, "0");
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
}

const TODAY = isoDate(new Date());
const IN_30_DAYS = (() => {
  const d = new Date();
  d.setDate(d.getDate() + 30);
  return isoDate(d);
})();

async function mount(props = {}) {
  const el = createElement("c-rfp-bid-form", { is: RfpBidForm });
  Object.assign(el, { laneId: "a0L00000001", currency: "CAD" }, props);
  document.body.appendChild(el);
  await flush();
  return el;
}

const field = (el, id) => el.shadowRoot.querySelector(`[data-id="${id}"]`);

function change(el, id, detail) {
  const node = field(el, id);
  Object.assign(node, detail);
  node.dispatchEvent(new CustomEvent("change", { detail }));
}

const save = (el) => field(el, "save").click();

describe("c-rfp-bid-form", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("defaults the dates to today and today + 30 days", async () => {
    const el = await mount();
    expect(field(el, "valid-from").value).toBe(TODAY);
    expect(field(el, "expires-on").value).toBe(IN_30_DAYS);
    expect(field(el, "currency").value).toBe("CAD");
  });

  it("blocks Save with an error when the rate is empty", async () => {
    const el = await mount();
    const handler = jest.fn();
    el.addEventListener("save", handler);
    save(el);
    await flush();
    expect(handler).not.toHaveBeenCalled();
    expect(field(el, "form-error").textContent).toContain("rate");
  });

  it("blocks Save with an error when no carrier is chosen", async () => {
    const el = await mount();
    const handler = jest.fn();
    el.addEventListener("save", handler);
    change(el, "rate", { value: "1500" });
    save(el);
    await flush();
    expect(handler).not.toHaveBeenCalled();
    expect(field(el, "form-error").textContent).toContain("carrier");
  });

  it("emits save with a typed carrier name and a null Carrier__c", async () => {
    const el = await mount();
    const handler = jest.fn();
    el.addEventListener("save", handler);

    expect(el.shadowRoot.querySelector("c-rfp-account-picker")).not.toBeNull();
    change(el, "new-carrier", { checked: true });
    await flush();
    expect(el.shadowRoot.querySelector("c-rfp-account-picker")).toBeNull();

    change(el, "carrier-name", { value: "Speedy Lines" });
    change(el, "contact-name", { value: "Dana Roy" });
    change(el, "contact-email", { value: "dana@speedy.example" });
    change(el, "rate", { value: "1500" });
    change(el, "fsc", { value: "0.32" });
    change(el, "fsc-included", { checked: true });
    change(el, "transit", { value: "3" });
    change(el, "notes", { value: "Spot rate" });
    await flush();
    save(el);
    await flush();

    expect(handler).toHaveBeenCalledTimes(1);
    expect(handler.mock.calls[0][0].detail.bid).toEqual({
      RFP_Lane__c: "a0L00000001",
      Carrier__c: null,
      Carrier_Name__c: "Speedy Lines",
      Contact_Name__c: "Dana Roy",
      Contact_Email__c: "dana@speedy.example",
      Contact_Phone__c: null,
      Rate__c: 1500,
      CurrencyIsoCode: "CAD",
      Fuel_Surcharge__c: 0.32,
      FSC_Included__c: true,
      Transit_Days__c: 3,
      Valid_From__c: TODAY,
      Expires_On__c: IN_30_DAYS,
      Notes__c: "Spot rate"
    });
  });

  it("emits save with the picked carrier id and no Carrier_Name__c", async () => {
    const el = await mount();
    const handler = jest.fn();
    el.addEventListener("save", handler);
    el.shadowRoot.querySelector("c-rfp-account-picker").dispatchEvent(
      new CustomEvent("accountchange", {
        detail: { id: "001Acme", name: "Acme Transport" }
      })
    );
    change(el, "rate", { value: "2100.5" });
    await flush();
    save(el);
    await flush();

    expect(handler).toHaveBeenCalledTimes(1);
    const { bid } = handler.mock.calls[0][0].detail;
    expect(bid.Carrier__c).toBe("001Acme");
    expect(bid.Carrier_Name__c).toBeUndefined();
    expect(bid.Rate__c).toBe(2100.5);
  });

  it("loads an existing bid for editing and emits cancel", async () => {
    const el = await mount({
      bid: {
        Id: "a0B00000001",
        Carrier__c: "001Acme",
        Carrier_Display__c: "Acme Transport",
        Rate__c: 1750,
        CurrencyIsoCode: "USD",
        Transit_Days__c: 2,
        Valid_From__c: "2026-01-01",
        Expires_On__c: "2026-02-01",
        Notes__c: "Renewal"
      }
    });
    expect(field(el, "rate").value).toBe(1750);
    expect(field(el, "currency").value).toBe("USD");
    expect(field(el, "valid-from").value).toBe("2026-01-01");

    const handler = jest.fn();
    el.addEventListener("cancel", handler);
    field(el, "cancel").click();
    expect(handler).toHaveBeenCalledTimes(1);
  });
});
