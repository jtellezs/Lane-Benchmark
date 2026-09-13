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
const escape = (target) =>
  target.dispatchEvent(
    new KeyboardEvent("keydown", { key: "Escape", bubbles: true })
  );

function mount(props = {}) {
  const el = createElement("c-help-hint", { is: HelpHint });
  Object.assign(el, { topic: "rfp-pricing" }, props);
  document.body.appendChild(el);
  return el;
}

async function opened(props) {
  const el = mount(props);
  await flush();
  field(el, "open").click();
  await flush();
  await flush();
  expect(field(el, "popover")).not.toBeNull();
  return el;
}

// The last listener a spy saw for one event type: [fn, capture].
function lastListener(spy, type) {
  const calls = spy.mock.calls.filter(([t]) => t === type);
  const last = calls[calls.length - 1] || [];
  return [last[1], last[2]];
}

// The Jest stub for lightning-button-icon renders nothing and cannot take
// focus, while the real component exposes focus() on its inner button. Let
// the stub hosts accept focus so the focus assertions can see where it went.
let nativeFocus;
function focusableStubs() {
  const descriptor = Object.getOwnPropertyDescriptor(
    HTMLElement.prototype,
    "focus"
  );
  nativeFocus = descriptor.value;
  Object.defineProperty(HTMLElement.prototype, "focus", {
    ...descriptor,
    value(...args) {
      if (
        this.tagName === "LIGHTNING-BUTTON-ICON" &&
        !this.hasAttribute("tabindex")
      ) {
        this.setAttribute("tabindex", "-1");
      }
      return nativeFocus.apply(this, args);
    }
  });
  return () =>
    Object.defineProperty(HTMLElement.prototype, "focus", descriptor);
}

describe("c-help-hint", () => {
  const innerWidth = window.innerWidth;
  const cleanups = [];

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
    while (cleanups.length) {
      cleanups.pop()();
    }
    Object.defineProperty(window, "innerWidth", {
      configurable: true,
      writable: true,
      value: innerWidth
    });
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

  it("closes on Escape while focus is on an unrelated input", async () => {
    const input = document.createElement("input");
    document.body.appendChild(input);
    const el = await opened();
    input.focus();
    expect(document.activeElement).toBe(input);
    escape(document.body);
    await flush();
    expect(field(el, "popover")).toBeNull();
    // Focus was outside the hint, so Escape leaves it there.
    expect(document.activeElement).toBe(input);
    expect(el.shadowRoot.activeElement).toBeNull();
  });

  it("uses the layout viewport width, not window.innerWidth, to place the popover", async () => {
    const clientWidth = Object.getOwnPropertyDescriptor(
      HTMLElement.prototype,
      "clientWidth"
    );
    Object.defineProperty(document.documentElement, "clientWidth", {
      configurable: true,
      value: 1183
    });
    Object.defineProperty(window, "innerWidth", {
      configurable: true,
      value: 1200
    });
    const el = await mount();
    const button = field(el, "open");
    button.getBoundingClientRect = () => ({
      left: 1150,
      right: 1170,
      bottom: 40
    });
    button.click();
    await flush();
    await flush();
    const popover = field(el, "popover");
    expect(popover.className).toContain("slds-nubbin_top-right");
    // 1183 - 1170 - 8 = 5, measured from the layout viewport's right edge.
    expect(popover.getAttribute("style")).toContain("right: 5px");
    delete document.documentElement.clientWidth;
    if (clientWidth) {
      Object.defineProperty(HTMLElement.prototype, "clientWidth", clientWidth);
    }
  });

  it("focuses the close button on open and returns focus to the ? when dismissed from inside", async () => {
    cleanups.push(focusableStubs());
    const el = await opened();
    expect(el.shadowRoot.activeElement).toBe(field(el, "close"));
    escape(document.body);
    await flush();
    expect(field(el, "popover")).toBeNull();
    expect(el.shadowRoot.activeElement).toBe(field(el, "open"));

    field(el, "open").click();
    await flush();
    expect(el.shadowRoot.activeElement).toBe(field(el, "close"));
    field(el, "close").click();
    await flush();
    expect(field(el, "popover")).toBeNull();
    expect(el.shadowRoot.activeElement).toBe(field(el, "open"));

    field(el, "open").click();
    await flush();
    field(el, "more").click();
    await flush();
    expect(field(el, "popover")).toBeNull();
    expect(el.shadowRoot.activeElement).toBe(field(el, "open"));
    expect(mockNavigateCalls).toHaveLength(1);
  });

  it("leaves focus where it is when an outside click closes the popover", async () => {
    cleanups.push(focusableStubs());
    const input = document.createElement("input");
    document.body.appendChild(input);
    const el = await opened();
    expect(el.shadowRoot.activeElement).toBe(field(el, "close"));
    input.focus();
    document.body.click();
    await flush();
    expect(field(el, "popover")).toBeNull();
    expect(document.activeElement).toBe(input);
    expect(el.shadowRoot.activeElement).toBeNull();
  });

  it("tells assistive technology whether the dialog is open", async () => {
    const el = mount();
    await flush();
    expect(field(el, "open").ariaExpanded).toBe("false");
    expect(field(el, "open").ariaHasPopup).toBe("dialog");
    field(el, "open").click();
    await flush();
    expect(field(el, "open").ariaExpanded).toBe("true");
    field(el, "close").click();
    await flush();
    expect(field(el, "open").ariaExpanded).toBe("false");
  });

  it("opens towards the side of the screen with room, anchored to the viewport", async () => {
    Object.defineProperty(window, "innerWidth", {
      configurable: true,
      writable: true,
      value: 1200
    });
    const el = mount();
    await flush();
    const button = field(el, "open");

    button.getBoundingClientRect = () => ({
      left: 1000,
      right: 1020,
      bottom: 40
    });
    button.click();
    await flush();
    let popover = field(el, "popover");
    expect(popover.classList.contains("slds-nubbin_top-right")).toBe(true);
    expect(popover.classList.contains("slds-nubbin_top-left")).toBe(false);
    let style = popover.getAttribute("style");
    expect(style).toContain("top: 46px");
    expect(style).toContain("right: 172px");
    expect(style).not.toContain("left:");
    button.click();
    await flush();
    expect(field(el, "popover")).toBeNull();

    button.getBoundingClientRect = () => ({
      left: 100,
      right: 120,
      bottom: 40
    });
    button.click();
    await flush();
    popover = field(el, "popover");
    expect(popover.classList.contains("slds-nubbin_top-left")).toBe(true);
    expect(popover.classList.contains("slds-nubbin_top-right")).toBe(false);
    style = popover.getAttribute("style");
    expect(style).toContain("left: 92px");
    expect(style).not.toContain("right:");
  });

  it("removes the same click, keydown and scroll listeners it added, on close and on removal", async () => {
    const add = jest.spyOn(document, "addEventListener");
    const remove = jest.spyOn(document, "removeEventListener");
    cleanups.push(() => {
      add.mockRestore();
      remove.mockRestore();
    });
    const types = ["click", "keydown", "scroll"];
    const el = await opened();

    field(el, "close").click();
    await flush();
    types.forEach((type) => {
      const [addedFn, addedCapture] = lastListener(add, type);
      const [removedFn, removedCapture] = lastListener(remove, type);
      expect({ type, added: typeof addedFn, capture: addedCapture }).toEqual({
        type,
        added: "function",
        capture: true
      });
      expect(removedFn).toBe(addedFn);
      expect(removedCapture).toBe(true);
    });

    const addCount = add.mock.calls.length;
    field(el, "open").click();
    await flush();
    expect(add.mock.calls.length).toBe(addCount + 3);
    document.body.removeChild(el);
    types.forEach((type) => {
      const [addedFn] = lastListener(add, type);
      const [removedFn, removedCapture] = lastListener(remove, type);
      expect(typeof addedFn).toBe("function");
      expect(removedFn).toBe(addedFn);
      expect(removedCapture).toBe(true);
    });
  });

  it("closes when anything scrolls, including a container whose scroll does not bubble", async () => {
    const pane = document.createElement("div");
    document.body.appendChild(pane);
    const el = await opened();
    pane.dispatchEvent(new CustomEvent("scroll"));
    await flush();
    expect(field(el, "popover")).toBeNull();

    field(el, "open").click();
    await flush();
    expect(field(el, "popover")).not.toBeNull();
    document.dispatchEvent(new CustomEvent("scroll"));
    await flush();
    expect(field(el, "popover")).toBeNull();
  });
});
