import HELP from "@salesforce/resourceUrl/helpCenter";

const LANGS = ["en", "fr"];
const KEY = "helpCenter.lang.v1";
let indexPromise = null;
const sectionPromises = new Map();

async function fetchOk(url) {
  const res = await fetch(url);
  if (!res || !res.ok) {
    throw new Error(
      `Help content request failed (${res ? res.status : "no response"}): ${url}`
    );
  }
  return res;
}

/** The section list, fetched once per page load. */
export function loadIndex() {
  if (!indexPromise) {
    indexPromise = fetchOk(`${HELP}/index.json`)
      .then((r) => r.json())
      .catch((e) => {
        indexPromise = null;
        throw e;
      });
  }
  return indexPromise;
}

/** One section's HTML in one language, fetched once per page load. */
export function loadSection(slug, lang) {
  const key = `${lang}/${slug}`;
  if (!sectionPromises.has(key)) {
    const p = fetchOk(`${HELP}/${lang}/${slug}.html`)
      .then((r) => r.text())
      .catch((e) => {
        sectionPromises.delete(key);
        throw e;
      });
    sectionPromises.set(key, p);
  }
  return sectionPromises.get(key);
}

export function findSection(index, slug) {
  const list = (index && index.sections) || [];
  return list.find((s) => s.slug === slug) || null;
}

/** French for any fr* locale, English otherwise. */
export function defaultLang(locale) {
  return String(locale || "")
    .toLowerCase()
    .startsWith("fr")
    ? "fr"
    : "en";
}

export function readLang() {
  try {
    const v = window.localStorage.getItem(KEY);
    return LANGS.includes(v) ? v : null;
  } catch {
    return null;
  }
}

export function writeLang(lang) {
  if (!LANGS.includes(lang)) {
    return;
  }
  try {
    window.localStorage.setItem(KEY, lang);
  } catch {
    // private window or blocked storage: the choice just is not remembered
  }
}

/** Page reference for the Help tab, opened at one section in one language. */
export function sectionUrl(slug, lang) {
  return {
    type: "standard__navItemPage",
    attributes: { apiName: "Help_Center" },
    state: { c__section: slug, c__lang: lang }
  };
}

/** Tests only. */
export function resetCache() {
  indexPromise = null;
  sectionPromises.clear();
}
