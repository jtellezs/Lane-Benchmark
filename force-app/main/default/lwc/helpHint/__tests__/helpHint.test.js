import { createElement } from "lwc";
import HelpHint from "c/helpHint";
import { resetCache } from "c/helpContent";

const mockNavigateCalls = [];
jest.mock("lightning/navigation", () => {
  const Navigate = Symbol("Navigate");
  const NavigationMixin = (Base) =>
    class extends Base {
      [Navigate](pageReference) {
        mockNavigateCalls.push(pageReference);
      }
    };
  NavigationMixin.Navigate = Navigate;
  return { NavigationMixin, CurrentPageReference: { emit: () => {} } };
});
jest.mock(
  "@salesforce/resourceUrl/helpCenter",
  () => ({ __esModule: true, default: "/resource/helpCenter" }),
  {
    virtual: true
  }
);
jest.mock("@salesforce/i18n/lang", () => ({ default: "en-US" }), {
  virtual: true
});

const index = {
  sections: [
    {
      slug: "rfp-pricing",
      order: 100,
      title: { en: "Pricing a lane", fr: "Tarifer une voie" },
      hint: { en: "Pick a cost source.", fr: "Choisissez une source." }
    }
  ]
};

const flush = () => Promise.resolve().then(() => Promise.resolve());
const field = (el, id) => el.shadowRoot.querySelector(`[data-id="${id}"]`);

function mount(props = {}) {
  const el = createElement("c-help-hint", { is: HelpHint });
  Object.assign(el, { topic: "rfp-pricing" }, props);
  document.body.appendChild(el);
  return el;
}

describe("c-help-hint", () => {
  beforeEach(() => {
    resetCache();
    mockNavigateCalls.length = 0;
    try {
      window.localStorage.clear();
    } catch {
      // ignore
    }
    global.fetch = jest.fn(() =>
      Promise.resolve({ ok: true, json: () => Promise.resolve(index) })
    );
  });
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("renders only the button until opened, then the hint in the default language", async () => {
    const el = mount();
    await flush();
    expect(field(el, "popover")).toBeNull();
    expect(field(el, "open").alternativeText).toBe("Help");
    field(el, "open").click();
    await flush();
    await flush();
    expect(field(el, "text").textContent).toBe("Pick a cost source.");
    expect(field(el, "more").textContent).toContain("Read more");
  });

  it("uses the stored language and navigates to the section on Read more", async () => {
    window.localStorage.setItem("helpCenter.lang.v1", "fr");
    const el = mount({ label: "Aide" });
    await flush();
    field(el, "open").click();
    await flush();
    await flush();
    expect(field(el, "text").textContent).toBe("Choisissez une source.");
    expect(field(el, "more").textContent).toContain("En savoir plus");
    field(el, "more").click();
    expect(mockNavigateCalls[0]).toEqual({
      type: "standard__navItemPage",
      attributes: { apiName: "Help_Center" },
      state: { c__section: "rfp-pricing", c__lang: "fr" }
    });
    await flush();
    expect(field(el, "popover")).toBeNull();
  });

  it("closes on Escape, on the close button and on an outside click", async () => {
    const el = mount();
    await flush();
    field(el, "open").click();
    await flush();
    await flush();
    expect(field(el, "popover")).not.toBeNull();
    field(el, "popover").dispatchEvent(
      new KeyboardEvent("keydown", {
        key: "Escape",
        bubbles: true,
        composed: true
      })
    );
    await flush();
    expect(field(el, "popover")).toBeNull();

    field(el, "open").click();
    await flush();
    field(el, "close").click();
    await flush();
    expect(field(el, "popover")).toBeNull();

    field(el, "open").click();
    await flush();
    document.body.click();
    await flush();
    expect(field(el, "popover")).toBeNull();
  });

  it("says when a topic has no help yet, and when the index cannot load", async () => {
    const el = mount({ topic: "unknown" });
    await flush();
    field(el, "open").click();
    await flush();
    await flush();
    expect(field(el, "text").textContent).toBe("No help for this area yet.");
    expect(field(el, "more")).toBeNull();

    resetCache();
    global.fetch = jest.fn(() => Promise.resolve({ ok: false, status: 500 }));
    const broken = mount();
    await flush();
    field(broken, "open").click();
    await flush();
    await flush();
    await flush();
    expect(field(broken, "text").textContent).toBe(
      "No help for this area yet."
    );
  });

  it("removes its document listener when removed from the page", async () => {
    const add = jest.spyOn(document, "addEventListener");
    const remove = jest.spyOn(document, "removeEventListener");
    const el = mount();
    await flush();
    field(el, "open").click();
    await flush();
    expect(add).toHaveBeenCalledWith("click", expect.any(Function), true);
    document.body.removeChild(el);
    expect(remove).toHaveBeenCalledWith("click", expect.any(Function), true);
    add.mockRestore();
    remove.mockRestore();
  });
});
