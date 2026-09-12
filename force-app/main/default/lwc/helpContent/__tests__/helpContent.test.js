import {
  loadIndex,
  loadSection,
  findSection,
  defaultLang,
  readLang,
  writeLang,
  sectionUrl,
  resetCache
} from "c/helpContent";

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
      slug: "overview",
      order: 10,
      title: { en: "What", fr: "Quoi" },
      hint: { en: "h", fr: "i" }
    },
    {
      slug: "faq",
      order: 150,
      title: { en: "FAQ", fr: "FAQ" },
      hint: { en: "q", fr: "q" }
    }
  ]
};

function mockFetch(map) {
  global.fetch = jest.fn((url) => {
    const body = map[url];
    if (body === undefined) {
      return Promise.resolve({ ok: false, status: 404 });
    }
    return Promise.resolve({
      ok: true,
      json: () => Promise.resolve(JSON.parse(body)),
      text: () => Promise.resolve(body)
    });
  });
}

describe("helpContent", () => {
  beforeEach(() => {
    resetCache();
    try {
      window.localStorage.clear();
    } catch {
      // ignore
    }
  });

  it("loads the index once and finds sections", async () => {
    mockFetch({ "/resource/helpCenter/index.json": JSON.stringify(index) });
    const a = await loadIndex();
    const b = await loadIndex();
    expect(fetch).toHaveBeenCalledTimes(1);
    expect(a).toBe(b);
    expect(findSection(a, "faq").title.fr).toBe("FAQ");
    expect(findSection(a, "nope")).toBeNull();
  });

  it("loads a section's html per language and caches it", async () => {
    mockFetch({
      "/resource/helpCenter/en/faq.html": "<h2>FAQ</h2>",
      "/resource/helpCenter/fr/faq.html": "<h2>Questions</h2>"
    });
    expect(await loadSection("faq", "en")).toBe("<h2>FAQ</h2>");
    expect(await loadSection("faq", "fr")).toBe("<h2>Questions</h2>");
    await loadSection("faq", "en");
    expect(fetch).toHaveBeenCalledTimes(2);
  });

  it("rejects when a file is missing", async () => {
    mockFetch({});
    await expect(loadSection("faq", "en")).rejects.toThrow("404");
    await expect(loadIndex()).rejects.toThrow("404");
  });

  it("picks French for fr locales only", () => {
    expect(defaultLang("fr")).toBe("fr");
    expect(defaultLang("fr-CA")).toBe("fr");
    expect(defaultLang("en-US")).toBe("en");
    expect(defaultLang(undefined)).toBe("en");
  });

  it("stores the chosen language and survives a broken localStorage", () => {
    expect(readLang()).toBeNull();
    writeLang("fr");
    expect(readLang()).toBe("fr");
    writeLang("xx");
    expect(readLang()).toBe("fr");
    const spy = jest
      .spyOn(Storage.prototype, "getItem")
      .mockImplementation(() => {
        throw new Error("blocked");
      });
    expect(readLang()).toBeNull();
    spy.mockRestore();
  });

  it("builds the Help tab page reference", () => {
    expect(sectionUrl("rfp-pricing", "fr")).toEqual({
      type: "standard__navItemPage",
      attributes: { apiName: "Help_Center" },
      state: { c__section: "rfp-pricing", c__lang: "fr" }
    });
  });
});
