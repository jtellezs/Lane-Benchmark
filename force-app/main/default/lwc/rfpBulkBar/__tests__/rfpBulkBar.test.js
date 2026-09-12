import { createElement } from "lwc";
import RfpBulkBar from "c/rfpBulkBar";

// c-rfp-bid-form pulls in c-rfp-account-picker, which imports Apex.
jest.mock(
  "@salesforce/apex/RfpProjectController.searchAccounts",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const flush = () => Promise.resolve().then(() => Promise.resolve());
const field = (el, id) => el.shadowRoot.querySelector(`[data-id="${id}"]`);

async function mount(props = {}) {
  const el = createElement("c-rfp-bulk-bar", { is: RfpBulkBar });
  Object.assign(
    el,
    { selectedCount: 0, totalCount: 10, currency: "CAD" },
    props
  );
  document.body.appendChild(el);
  await flush();
  return el;
}
const lastBulk = (spy) => spy.mock.calls[spy.mock.calls.length - 1][0].detail;

describe("c-rfp-bulk-bar", () => {
  afterEach(() => {
    while (document.body.firstChild)
      document.body.removeChild(document.body.firstChild);
  });

  it("starts on All lanes and disables Selected at zero", async () => {
    const el = await mount();
    expect(field(el, "scope-all").variant).toBe("brand");
    expect(field(el, "scope-selected").disabled).toBe(true);
    expect(field(el, "scope-selected").label).toBe("Selected (0)");
    expect(field(el, "delete")).toBeNull();
  });

  it("emits median for the chosen scope", async () => {
    const el = await mount({ selectedCount: 3 });
    const spy = jest.fn();
    el.addEventListener("bulk", spy);
    field(el, "use-median").click();
    expect(lastBulk(spy)).toEqual({ action: "median", scope: "all" });
    field(el, "scope-selected").click();
    await flush();
    field(el, "use-median").click();
    expect(lastBulk(spy)).toEqual({ action: "median", scope: "selected" });
  });

  it("validates and emits pricing values", async () => {
    const el = await mount({ selectedCount: 2 });
    const spy = jest.fn();
    el.addEventListener("bulk", spy);
    field(el, "margin").dispatchEvent(
      new CustomEvent("change", { detail: { value: "120" } })
    );
    field(el, "apply-margin").click();
    await flush();
    expect(spy).not.toHaveBeenCalled();
    expect(field(el, "bar-error").textContent).toContain("0 and 100");
    field(el, "margin").dispatchEvent(
      new CustomEvent("change", { detail: { value: "18" } })
    );
    field(el, "apply-margin").click();
    expect(lastBulk(spy)).toEqual({
      action: "pricing",
      scope: "all",
      margin: 18
    });
    field(el, "cost").dispatchEvent(
      new CustomEvent("change", { detail: { value: "1250.5" } })
    );
    field(el, "apply-cost").click();
    expect(lastBulk(spy)).toEqual({
      action: "pricing",
      scope: "all",
      cost: 1250.5
    });
    field(el, "sell").dispatchEvent(
      new CustomEvent("change", { detail: { value: "0" } })
    );
    field(el, "apply-sell").click();
    await flush();
    expect(field(el, "bar-error").textContent).toContain("above zero");
  });

  it("deletes only the selection and only on the second click", async () => {
    const el = await mount({ selectedCount: 4 });
    const spy = jest.fn();
    el.addEventListener("bulk", spy);
    field(el, "scope-selected").click();
    await flush();
    const del = field(el, "delete");
    expect(del.label).toBe("Delete selected");
    del.click();
    await flush();
    expect(spy).not.toHaveBeenCalled();
    expect(field(el, "delete").label).toBe(
      "Confirm: delete 4 lanes and their carrier rates"
    );
    field(el, "delete").click();
    expect(lastBulk(spy)).toEqual({ action: "delete", scope: "selected" });
    el.selectedCount = 0;
    await flush();
    expect(field(el, "delete")).toBeNull();
    expect(field(el, "scope-all").variant).toBe("brand");
  });

  it("adds the same carrier rate through the bid form", async () => {
    const el = await mount({ selectedCount: 2 });
    const spy = jest.fn();
    el.addEventListener("bulk", spy);
    field(el, "add-bid").click();
    await flush();
    const form = el.shadowRoot.querySelector("c-rfp-bid-form");
    expect(form).not.toBeNull();
    expect(form.currency).toBe("CAD");
    form.dispatchEvent(
      new CustomEvent("save", {
        detail: {
          bid: {
            RFP_Lane__c: null,
            Carrier_Name__c: "ACME",
            Rate__c: 900,
            CurrencyIsoCode: "CAD"
          }
        }
      })
    );
    await flush();
    expect(lastBulk(spy)).toEqual({
      action: "bid",
      scope: "all",
      bid: { Carrier_Name__c: "ACME", Rate__c: 900, CurrencyIsoCode: "CAD" }
    });
    expect(el.shadowRoot.querySelector("c-rfp-bid-form")).toBeNull();
  });

  it("offers to overwrite the lanes a median run skipped", async () => {
    const el = await mount({
      lastResult: {
        action: "median",
        updated: 5,
        skipped: 2,
        skippedIds: ["a", "b"],
        errors: [],
        failedIds: []
      }
    });
    const spy = jest.fn();
    el.addEventListener("bulk", spy);
    expect(field(el, "skipped-note").textContent).toContain(
      "2 lanes already costed"
    );
    field(el, "overwrite").click();
    expect(lastBulk(spy)).toEqual({
      action: "median",
      scope: "skipped",
      overwrite: true
    });
  });

  it("disables every action while busy", async () => {
    const el = await mount({ busy: true, selectedCount: 1 });
    [
      "use-median",
      "apply-margin",
      "apply-cost",
      "apply-sell",
      "add-bid"
    ].forEach((id) => expect(field(el, id).disabled).toBe(true));
  });
});
