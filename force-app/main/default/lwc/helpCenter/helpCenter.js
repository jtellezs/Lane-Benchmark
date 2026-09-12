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
    empty: "No section matches.",
    error: "The help content did not load. Reload the page or ask your admin."
  },
  fr: {
    card: "Aide",
    filter: "Trouver une section",
    empty: "Aucune section ne correspond.",
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
  // Bumped by every show(); a request whose token is stale by the time it
  // settles has been superseded by a later click and must not paint.
  requestSeq = 0;

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
  get emptyLabel() {
    return this.copy.empty;
  }
  get noMatches() {
    return this.indexReady && this.visibleSections.length === 0;
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

  /**
   * The asked-for slug when the index has it, otherwise the overview, otherwise
   * the first section there is. An index without an "overview" is still usable.
   */
  resolveSlug(slug) {
    const index = { sections: this.sections };
    if (findSection(index, slug)) {
      return slug;
    }
    if (findSection(index, DEFAULT_SLUG)) {
      return DEFAULT_SLUG;
    }
    if (this.sections.length) {
      return this.sections[0].slug;
    }
    return DEFAULT_SLUG;
  }

  async show(slug, lang) {
    const token = ++this.requestSeq;
    this.lang = lang;
    this.loading = true;
    this.error = null;
    try {
      if (!this.indexReady) {
        const index = await loadIndex();
        this.sections = index.sections;
        this.indexReady = true;
      }
      if (token !== this.requestSeq) {
        return;
      }
      this.slug = this.resolveSlug(slug);
      const html = await loadSection(this.slug, this.lang);
      if (token !== this.requestSeq) {
        return;
      }
      this.html = html;
    } catch {
      if (token !== this.requestSeq) {
        return;
      }
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
  /** A filter typed against one language's titles cannot survive the switch. */
  pickLang(lang) {
    this.filter = "";
    this.go(this.slug, lang);
  }
  handleEn() {
    this.pickLang("en");
  }
  handleFr() {
    this.pickLang("fr");
  }
  handlePick(event) {
    this.go(event.currentTarget.dataset.slug, this.lang);
  }
  handleFilter(event) {
    this.filter = event.detail.value || "";
  }
}
