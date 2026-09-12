import { createElement } from "lwc";
import HelpCenter from "c/helpCenter";
import { CurrentPageReference } from "lightning/navigation";
import { resetCache } from "c/helpContent";

const mockNavigateCalls = [];
jest.mock("lightning/navigation", () => {
  const { createTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
  const Navigate = Symbol("Navigate");
  const NavigationMixin = (Base) =>
    class extends Base {
      [Navigate](pageReference, replace) {
        mockNavigateCalls.push({ pageReference, replace });
      }
    };
  NavigationMixin.Navigate = Navigate;
  return {
    NavigationMixin,
    CurrentPageReference: createTestWireAdapter(jest.fn())
  };
});
jest.mock(
  "@salesforce/resourceUrl/helpCenter",
  () => ({ __esModule: true, default: "/resource/helpCenter" }),
  {
    virtual: true
  }
);
jest.mock(
  "@salesforce/i18n/lang",
  () => ({ __esModule: true, default: "fr" }),
  {
    virtual: true
  }
);

const index = {
  sections: [
    {
      slug: "overview",
      order: 10,
      title: { en: "What these tools do", fr: "À quoi servent ces outils" },
      hint: { en: "a", fr: "b" }
    },
    {
      slug: "rfp-pricing",
      order: 100,
      title: { en: "Pricing a lane", fr: "Tarifer une voie" },
      hint: { en: "c", fr: "d" }
    },
    {
      slug: "faq",
      order: 150,
      title: { en: "Questions and problems", fr: "Questions et problèmes" },
      hint: { en: "e", fr: "f" }
    }
  ]
};
const pages = {
  "/resource/helpCenter/index.json": JSON.stringify(index),
  "/resource/helpCenter/en/overview.html": "<h2>Overview EN</h2>",
  "/resource/helpCenter/fr/overview.html": "<h2>Aperçu FR</h2>",
  "/resource/helpCenter/en/rfp-pricing.html": "<h2>Pricing EN</h2>",
  "/resource/helpCenter/fr/rfp-pricing.html": "<h2>Tarifer FR</h2>"
};

const flush = () => Promise.resolve().then(() => Promise.resolve());
// Four sequential microtask flushes, written without a loop because the repo's
// ESLint config forbids `await` inside a loop.
const settle = () => flush().then(flush).then(flush).then(flush);
const field = (el, id) => el.shadowRoot.querySelector(`[data-id="${id}"]`);
const items = (el) => [
  ...el.shadowRoot.querySelectorAll('[data-id="nav-item"]')
];

async function mount(state = {}) {
  const el = createElement("c-help-center", { is: HelpCenter });
  document.body.appendChild(el);
  CurrentPageReference.emit({ type: "standard__navItemPage", state });
  await settle();
  return el;
}

describe("c-help-center", () => {
  beforeEach(() => {
    resetCache();
    mockNavigateCalls.length = 0;
    try {
      window.localStorage.clear();
    } catch {
      // ignore
    }
    global.fetch = jest.fn((url) => {
      const body = pages[url];
      if (body === undefined) {
        return Promise.resolve({ ok: false, status: 404 });
      }
      return Promise.resolve({
        ok: true,
        json: () => Promise.resolve(JSON.parse(body)),
        text: () => Promise.resolve(body)
      });
    });
  });
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("opens the overview in the user's language when the URL says nothing", async () => {
    const el = await mount();
    expect(items(el).map((i) => i.dataset.slug)).toEqual([
      "overview",
      "rfp-pricing",
      "faq"
    ]);
    expect(items(el)[0].textContent).toContain("À quoi servent ces outils");
    expect(field(el, "title").textContent).toBe("À quoi servent ces outils");
    expect(field(el, "body").value).toBe("<h2>Aperçu FR</h2>");
    expect(field(el, "lang-fr").variant).toBe("brand");
  });

  it("lands on the section and language from the URL", async () => {
    const el = await mount({ c__section: "rfp-pricing", c__lang: "en" });
    expect(field(el, "title").textContent).toBe("Pricing a lane");
    expect(field(el, "body").value).toBe("<h2>Pricing EN</h2>");
    expect(field(el, "lang-en").variant).toBe("brand");
  });

  it("falls back to the overview for an unknown slug", async () => {
    const el = await mount({ c__section: "nope", c__lang: "en" });
    expect(field(el, "title").textContent).toBe("What these tools do");
  });

  it("switches language, remembers it and rewrites the URL", async () => {
    const el = await mount({ c__section: "rfp-pricing", c__lang: "fr" });
    field(el, "lang-en").click();
    await settle();
    expect(field(el, "body").value).toBe("<h2>Pricing EN</h2>");
    expect(window.localStorage.getItem("helpCenter.lang.v1")).toBe("en");
    expect(mockNavigateCalls.pop()).toEqual({
      pageReference: {
        type: "standard__navItemPage",
        attributes: { apiName: "Help_Center" },
        state: { c__section: "rfp-pricing", c__lang: "en" }
      },
      replace: true
    });
  });

  it("prefers the remembered language over the user's language", async () => {
    window.localStorage.setItem("helpCenter.lang.v1", "en");
    const el = await mount();
    expect(field(el, "title").textContent).toBe("What these tools do");
  });

  it("navigates between sections from the left column", async () => {
    const el = await mount({ c__lang: "en" });
    items(el)[1].click();
    await settle();
    expect(field(el, "title").textContent).toBe("Pricing a lane");
    expect(mockNavigateCalls.pop().pageReference.state.c__section).toBe(
      "rfp-pricing"
    );
  });

  it("filters the column by title", async () => {
    const el = await mount({ c__lang: "en" });
    field(el, "filter").value = "pric";
    field(el, "filter").dispatchEvent(
      new CustomEvent("change", { detail: { value: "pric" } })
    );
    await settle();
    expect(items(el).map((i) => i.dataset.slug)).toEqual(["rfp-pricing"]);
  });

  it("shows an error when the content does not load", async () => {
    global.fetch = jest.fn(() => Promise.resolve({ ok: false, status: 500 }));
    const el = await mount({ c__lang: "en" });
    expect(field(el, "error").textContent).toContain("did not load");
    expect(field(el, "body")).toBeNull();
  });
});
