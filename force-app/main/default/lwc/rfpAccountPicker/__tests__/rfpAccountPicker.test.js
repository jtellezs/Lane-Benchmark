import { createElement } from "lwc";
import RfpAccountPicker from "c/rfpAccountPicker";
import searchAccounts from "@salesforce/apex/RfpProjectController.searchAccounts";

jest.mock(
  "@salesforce/apex/RfpProjectController.searchAccounts",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const flush = () => Promise.resolve().then(() => Promise.resolve());

const ACCOUNTS = [
  { id: "001Acme", name: "Acme Transport", city: "Laval" },
  { id: "001Acm2", name: "Acme Freight", city: "Toronto" }
];

async function mount(props = {}) {
  const el = createElement("c-rfp-account-picker", { is: RfpAccountPicker });
  Object.assign(el, { label: "Carrier", kind: "carrier" }, props);
  document.body.appendChild(el);
  await flush();
  return el;
}

function type(el, text) {
  const input = el.shadowRoot.querySelector('lightning-input[data-id="term"]');
  input.value = text;
  input.dispatchEvent(new CustomEvent("change", { detail: { value: text } }));
}

describe("c-rfp-account-picker", () => {
  beforeEach(() => {
    jest.useFakeTimers();
    searchAccounts.mockResolvedValue(ACCOUNTS);
  });
  afterEach(() => {
    jest.useRealTimers();
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("debounces typing by 250 ms and searches with the term and kind", async () => {
    const el = await mount();
    type(el, "Ac");
    type(el, "Acm");
    jest.advanceTimersByTime(240);
    expect(searchAccounts).not.toHaveBeenCalled();
    jest.advanceTimersByTime(10);
    await flush();
    await flush();
    expect(searchAccounts).toHaveBeenCalledTimes(1);
    expect(searchAccounts).toHaveBeenCalledWith({
      term: "Acm",
      kind: "carrier"
    });
    const options = el.shadowRoot.querySelectorAll('[data-id="option"]');
    expect(options.length).toBe(2);
    expect(options[0].textContent).toContain("Acme Transport");
    expect(options[0].textContent).toContain("Laval");
  });

  it("does not search for fewer than two characters", async () => {
    const el = await mount();
    type(el, "A");
    jest.advanceTimersByTime(250);
    await flush();
    expect(searchAccounts).not.toHaveBeenCalled();
    expect(el.shadowRoot.querySelectorAll('[data-id="option"]').length).toBe(0);
  });

  it("emits accountchange with the id and name when an option is picked", async () => {
    const el = await mount();
    const handler = jest.fn();
    el.addEventListener("accountchange", handler);
    type(el, "Acm");
    jest.advanceTimersByTime(250);
    await flush();
    await flush();
    el.shadowRoot.querySelectorAll('[data-id="option"]')[1].click();
    await flush();
    expect(handler).toHaveBeenCalledTimes(1);
    expect(handler.mock.calls[0][0].detail).toEqual({
      id: "001Acm2",
      name: "Acme Freight"
    });
    expect(el.value).toBe("001Acm2");
    expect(el.shadowRoot.querySelectorAll('[data-id="option"]').length).toBe(0);
  });

  it("clears the selection and emits an empty accountchange", async () => {
    const el = await mount({ value: "001Acme", valueLabel: "Acme Transport" });
    const handler = jest.fn();
    el.addEventListener("accountchange", handler);
    el.shadowRoot.querySelector('[data-id="clear"]').click();
    await flush();
    expect(handler).toHaveBeenCalledTimes(1);
    expect(handler.mock.calls[0][0].detail).toEqual({ id: null, name: "" });
    expect(el.value).toBeNull();
  });
});
