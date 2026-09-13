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
    },
    {
      slug: "lb-filters",
      order: 200,
      title: { en: "Filters and lookback", fr: "Filtres et période" },
      hint: { en: "g", fr: "h" }
    }
  ]
};
const ALL_SLUGS = ["overview", "rfp-pricing", "faq", "lb-filters"];
const INDEX_URL = "/resource/helpCenter/index.json";
const PRICING_EN_URL = "/resource/helpCenter/en/rfp-pricing.html";
const pages = {
  [INDEX_URL]: JSON.stringify(index),
  "/resource/helpCenter/en/overview.html": "<h2>Overview EN</h2>",
  "/resource/helpCenter/fr/overview.html": "<h2>Aperçu FR</h2>",
  [PRICING_EN_URL]: "<h2>Pricing EN</h2>",
  "/resource/helpCenter/fr/rfp-pricing.html": "<h2>Tarifer FR</h2>",
  "/resource/helpCenter/en/faq.html": "<h2>FAQ EN</h2>",
  "/resource/helpCenter/fr/faq.html": "<h2>FAQ FR</h2>",
  "/resource/helpCenter/en/lb-filters.html": "<h2>Filters EN</h2>",
  "/resource/helpCenter/fr/lb-filters.html": "<h2>Filtres FR</h2>"
};

const respond = (map, url) => {
  const body = map[url];
  if (body === undefined) {
    return Promise.resolve({ ok: false, status: 404 });
  }
  return Promise.resolve({
    ok: true,
    json: () => Promise.resolve(JSON.parse(body)),
    text: () => Promise.resolve(body)
  });
};

/**
 * Point fetch at `pages`, but hold one URL's response open until the
 * returned function is called; it then answers from `pages` as usual.
 */
function holdOpen(heldUrl) {
  let release;
  const held = new Promise((resolve) => {
    release = resolve;
  });
  global.fetch = jest.fn((url) => {
    if (url === heldUrl) {
      return held;
    }
    return respond(pages, url);
  });
  return () => release(respond(pages, heldUrl));
}

const flush = () => Promise.resolve().then(() => Promise.resolve());
// Four sequential microtask flushes, written without a loop because the repo's
// ESLint config forbids `await` inside a loop.
const settle = () => flush().then(flush).then(flush).then(flush);
const field = (el, id) => el.shadowRoot.querySelector(`[data-id="${id}"]`);
const items = (el) => [
  ...el.shadowRoot.querySelectorAll('[data-id="nav-item"]')
];
const pressed = (el, id) => field(el, id).getAttribute("aria-pressed");
const typeFilter = (el, value) => {
  field(el, "filter").value = value;
  field(el, "filter").dispatchEvent(
    new CustomEvent("change", { detail: { value } })
  );
};

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
    global.fetch = jest.fn((url) => respond(pages, url));
  });
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("opens the overview in the user's language when the URL says nothing", async () => {
    const el = await mount();
    expect(items(el).map((i) => i.dataset.slug)).toEqual(ALL_SLUGS);
    expect(items(el)[0].textContent).toContain("À quoi servent ces outils");
    expect(field(el, "title").textContent).toBe("À quoi servent ces outils");
    expect(field(el, "body").value).toBe("<h2>Aperçu FR</h2>");
    expect(field(el, "lang-fr").className).toBe(
      "slds-button slds-button_brand"
    );
    expect(pressed(el, "lang-fr")).toBe("true");
    expect(field(el, "lang-en").className).toBe(
      "slds-button slds-button_neutral"
    );
    expect(pressed(el, "lang-en")).toBe("false");
  });

  it("lands on the section and language from the URL", async () => {
    const el = await mount({ c__section: "rfp-pricing", c__lang: "en" });
    expect(field(el, "title").textContent).toBe("Pricing a lane");
    expect(field(el, "body").value).toBe("<h2>Pricing EN</h2>");
    expect(field(el, "lang-en").className).toBe(
      "slds-button slds-button_brand"
    );
    expect(pressed(el, "lang-en")).toBe("true");
    expect(field(el, "lang-fr").className).toBe(
      "slds-button slds-button_neutral"
    );
    expect(pressed(el, "lang-fr")).toBe("false");
  });

  it("lets a valid URL language beat the remembered one", async () => {
    window.localStorage.setItem("helpCenter.lang.v1", "fr");
    const el = await mount({ c__section: "rfp-pricing", c__lang: "en" });
    expect(field(el, "title").textContent).toBe("Pricing a lane");
    expect(field(el, "body").value).toBe("<h2>Pricing EN</h2>");
    expect(pressed(el, "lang-en")).toBe("true");
    expect(pressed(el, "lang-fr")).toBe("false");
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

  it("keeps the deep-linked section when the language changes during the index load", async () => {
    window.localStorage.setItem("helpCenter.lang.v1", "en");
    const releaseIndex = holdOpen(INDEX_URL);
    const el = await mount({ c__section: "rfp-pricing" });
    expect(field(el, "loading")).not.toBeNull();
    expect(field(el, "title")).toBeNull();

    field(el, "lang-fr").click();
    await flush();
    releaseIndex();
    await settle();

    expect(mockNavigateCalls).toHaveLength(1);
    expect(mockNavigateCalls[0].pageReference.state).toEqual({
      c__section: "rfp-pricing",
      c__lang: "fr"
    });
    expect(field(el, "title").textContent).toBe("Tarifer une voie");
    expect(field(el, "body").value).toBe("<h2>Tarifer FR</h2>");
    expect(pressed(el, "lang-fr")).toBe("true");
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

  it("adds a history entry for a section click and rewrites it for a language switch", async () => {
    const el = await mount({ c__lang: "en" });
    items(el)[1].click();
    await settle();
    expect(mockNavigateCalls).toHaveLength(1);
    expect(mockNavigateCalls[0].replace).toBe(false);

    field(el, "lang-fr").click();
    await settle();
    expect(mockNavigateCalls).toHaveLength(2);
    expect(mockNavigateCalls[1].replace).toBe(true);
  });

  it("clears the previous body before the next section's title appears", async () => {
    const el = await mount({ c__lang: "en" });
    expect(field(el, "body").value).toBe("<h2>Overview EN</h2>");
    const releasePricing = holdOpen(PRICING_EN_URL);

    items(el)[1].click();
    await settle();
    expect(field(el, "title").textContent).toBe("Pricing a lane");
    expect(field(el, "body").value).toBe("");

    releasePricing();
    await settle();
    expect(field(el, "title").textContent).toBe("Pricing a lane");
    expect(field(el, "body").value).toBe("<h2>Pricing EN</h2>");
  });

  it("shows the spinner only while a section is loading", async () => {
    const el = await mount({ c__lang: "en" });
    expect(field(el, "loading")).toBeNull();
    const releasePricing = holdOpen(PRICING_EN_URL);

    items(el)[1].click();
    await settle();
    expect(field(el, "loading")).not.toBeNull();

    releasePricing();
    await settle();
    expect(field(el, "loading")).toBeNull();
    expect(field(el, "body").value).toBe("<h2>Pricing EN</h2>");
  });

  it("marks exactly the clicked section current, even when the URL echoes the click", async () => {
    const el = await mount({ c__lang: "en" });
    items(el)[1].click();
    await settle();
    CurrentPageReference.emit({
      type: "standard__navItemPage",
      state: { c__section: "rfp-pricing", c__lang: "en" }
    });
    await settle();

    const current = items(el).filter(
      (i) => i.getAttribute("aria-current") === "page"
    );
    expect(current.map((i) => i.dataset.slug)).toEqual(["rfp-pricing"]);
    expect(el.shadowRoot.querySelectorAll(".slds-is-active")).toHaveLength(1);
    expect(field(el, "title").textContent).toBe("Pricing a lane");
    expect(field(el, "body").value).toBe("<h2>Pricing EN</h2>");
    expect(field(el, "loading")).toBeNull();
    const pricingLoads = global.fetch.mock.calls.filter(
      ([url]) => url === PRICING_EN_URL
    );
    expect(pricingLoads).toHaveLength(1);
  });

  it("filters the column by title", async () => {
    const el = await mount({ c__lang: "en" });
    typeFilter(el, "pric");
    await settle();
    expect(items(el).map((i) => i.dataset.slug)).toEqual(["rfp-pricing"]);
  });

  it("finds an accented title from unaccented text", async () => {
    const el = await mount({ c__lang: "fr" });
    typeFilter(el, "periode");
    await settle();
    expect(items(el).map((i) => i.dataset.slug)).toEqual(["lb-filters"]);
    expect(items(el)[0].textContent).toContain("Filtres et période");

    typeFilter(el, "a quoi");
    await settle();
    expect(items(el).map((i) => i.dataset.slug)).toEqual(["overview"]);
  });

  it("ignores a slow response that a later click has superseded", async () => {
    const el = await mount({ c__lang: "en" });
    const releaseSlow = holdOpen(PRICING_EN_URL);

    items(el)[1].click(); // rfp-pricing: its response is held open
    await flush();
    items(el)[2].click(); // faq: answers straight away and must win
    await settle();
    expect(field(el, "title").textContent).toBe("Questions and problems");
    expect(field(el, "body").value).toBe("<h2>FAQ EN</h2>");

    releaseSlow();
    await settle();
    expect(field(el, "title").textContent).toBe("Questions and problems");
    expect(field(el, "body").value).toBe("<h2>FAQ EN</h2>");
  });

  it("falls back to the first section when the index has no overview", async () => {
    const noOverview = {
      sections: [
        {
          slug: "faq",
          order: 10,
          title: { en: "Questions and problems", fr: "Questions et problèmes" },
          hint: { en: "e", fr: "f" }
        },
        {
          slug: "rfp-pricing",
          order: 100,
          title: { en: "Pricing a lane", fr: "Tarifer une voie" },
          hint: { en: "c", fr: "d" }
        }
      ]
    };
    const otherPages = {
      [INDEX_URL]: JSON.stringify(noOverview),
      "/resource/helpCenter/en/faq.html": "<h2>FAQ EN</h2>"
    };
    global.fetch = jest.fn((url) => respond(otherPages, url));
    const el = await mount({ c__lang: "en" });
    expect(field(el, "title").textContent).toBe("Questions and problems");
    expect(field(el, "body").value).toBe("<h2>FAQ EN</h2>");
  });

  it("says when nothing matches and clears the filter on a language switch", async () => {
    const el = await mount({ c__lang: "en" });
    typeFilter(el, "zzz");
    await settle();
    expect(items(el)).toHaveLength(0);
    expect(field(el, "nav-empty").textContent).toContain("No section matches.");

    field(el, "lang-fr").click();
    await settle();
    expect(field(el, "filter").value).toBe("");
    expect(field(el, "nav-empty")).toBeNull();
    expect(items(el).map((i) => i.dataset.slug)).toEqual(ALL_SLUGS);
  });

  it("says in French when nothing matches", async () => {
    const el = await mount({ c__lang: "fr" });
    typeFilter(el, "zzz");
    await settle();
    expect(items(el)).toHaveLength(0);
    expect(field(el, "nav-empty").textContent).toContain(
      "Aucune section ne correspond."
    );
  });

  it("shows an error when the content does not load", async () => {
    global.fetch = jest.fn(() => Promise.resolve({ ok: false, status: 500 }));
    const el = await mount({ c__lang: "en" });
    expect(field(el, "error").textContent).toContain("did not load");
    expect(field(el, "body")).toBeNull();
  });
});
