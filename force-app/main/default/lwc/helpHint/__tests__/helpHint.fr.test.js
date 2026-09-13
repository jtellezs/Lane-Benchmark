import { createElement } from "lwc";
import HelpHint from "c/helpHint";
import { resetCache } from "c/helpContent";

// A French user with no stored language choice: the hint follows the user's
// Salesforce language.
jest.mock(
  "@salesforce/i18n/lang",
  () => ({ __esModule: true, default: "fr" }),
  {
    virtual: true
  }
);
jest.mock(
  "@salesforce/resourceUrl/helpCenter",
  () => ({ __esModule: true, default: "/resource/helpCenter" }),
  {
    virtual: true
  }
);

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

async function opened(topic) {
  const el = createElement("c-help-hint", { is: HelpHint });
  el.topic = topic;
  document.body.appendChild(el);
  await flush();
  field(el, "open").click();
  await flush();
  await flush();
  expect(field(el, "popover")).not.toBeNull();
  return el;
}

describe("c-help-hint in French", () => {
  beforeEach(() => {
    resetCache();
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

  it("shows the French hint and link when the user's language is French", async () => {
    const el = await opened("rfp-pricing");
    expect(field(el, "text").textContent).toBe("Choisissez une source.");
    expect(field(el, "more").textContent).toContain("En savoir plus");
    expect(field(el, "close").alternativeText).toBe("Fermer");
  });

  it("says in French when a topic has no help yet", async () => {
    const el = await opened("unknown");
    expect(field(el, "text").textContent).toBe(
      "Pas encore d'aide pour cette zone."
    );
    expect(field(el, "more")).toBeNull();
  });
});
