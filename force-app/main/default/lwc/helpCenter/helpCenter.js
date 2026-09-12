import { LightningElement, wire } from "lwc";
import { CurrentPageReference, NavigationMixin } from "lightning/navigation";
import LANG from "@salesforce/i18n/lang";
import {
  loadIndex,
  loadSection,
  findSection,
  defaultLang,
  readLang,
  writeLang,
  sectionUrl
} from "c/helpContent";

const DEFAULT_SLUG = "overview";
const COPY = {
  en: {
    card: "Help",
    filter: "Find a section",
    error: "The help content did not load. Reload the page or ask your admin."
  },
  fr: {
    card: "Aide",
    filter: "Trouver une section",
    error:
      "Le contenu de l'aide n'a pas pu être chargé. Rechargez la page ou demandez à votre administrateur."
  }
};

/**
 * The Help tab: a section list, an EN | FR toggle, a title filter and the
 * chosen section rendered from the helpCenter static resource. The URL
 * (c__section, c__lang) is the source of truth for what is shown, so hints
 * can deep-link and the browser back button works.
 */
export default class HelpCenter extends NavigationMixin(LightningElement) {
  lang = "en";
  slug = DEFAULT_SLUG;
  filter = "";
  sections = [];
  html = "";
  error = null;
  loading = true;
  indexReady = false;

  @wire(CurrentPageReference)
  handlePageReference(ref) {
    const state = (ref && ref.state) || {};
    const lang = ["en", "fr"].includes(state.c__lang)
      ? state.c__lang
      : readLang() || defaultLang(LANG);
    const slug = state.c__section || DEFAULT_SLUG;
    this.show(slug, lang);
  }

  get copy() {
    return COPY[this.lang];
  }
  get cardTitle() {
    return this.copy.card;
  }
  get filterLabel() {
    return this.copy.filter;
  }
  get enVariant() {
    return this.lang === "en" ? "brand" : "neutral";
  }
  get frVariant() {
    return this.lang === "fr" ? "brand" : "neutral";
  }
  get section() {
    return findSection({ sections: this.sections }, this.slug);
  }
  get title() {
    const s = this.section;
    return s ? s.title[this.lang] || s.title.en : "";
  }
  get visibleSections() {
    const needle = this.filter.trim().toLowerCase();
    return this.sections
      .filter(
        (s) =>
          !needle ||
          (s.title[this.lang] || s.title.en).toLowerCase().includes(needle)
      )
      .map((s) => ({
        slug: s.slug,
        label: s.title[this.lang] || s.title.en,
        current: s.slug === this.slug ? "page" : null,
        itemClass:
          s.slug === this.slug
            ? "slds-nav-vertical__item slds-is-active"
            : "slds-nav-vertical__item"
      }));
  }

  async show(slug, lang) {
    this.lang = lang;
    this.loading = true;
    this.error = null;
    try {
      if (!this.indexReady) {
        const index = await loadIndex();
        this.sections = index.sections;
        this.indexReady = true;
      }
      this.slug = findSection({ sections: this.sections }, slug)
        ? slug
        : DEFAULT_SLUG;
      this.html = await loadSection(this.slug, this.lang);
    } catch {
      this.error = this.copy.error;
    }
    this.loading = false;
  }

  go(slug, lang) {
    writeLang(lang);
    this[NavigationMixin.Navigate](sectionUrl(slug, lang), true);
    // The wire re-emits with the new state in the org; in tests it does not,
    // so render the choice directly as well.
    this.show(slug, lang);
  }
  handleEn() {
    this.go(this.slug, "en");
  }
  handleFr() {
    this.go(this.slug, "fr");
  }
  handlePick(event) {
    this.go(event.currentTarget.dataset.slug, this.lang);
  }
  handleFilter(event) {
    this.filter = event.detail.value || "";
  }
}
