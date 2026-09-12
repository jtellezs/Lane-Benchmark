import { LightningElement, api } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import LANG from "@salesforce/i18n/lang";
import {
  loadIndex,
  findSection,
  defaultLang,
  readLang,
  sectionUrl
} from "c/helpContent";

const COPY = {
  en: { more: "Read more", close: "Close", none: "No help for this area yet." },
  fr: {
    more: "En savoir plus",
    close: "Fermer",
    none: "Pas encore d'aide pour cette zone."
  }
};

/**
 * The "?" next to an area's title: a popover with that area's one-line hint
 * and a "Read more" link into the Help tab. Markup-only for the host: no
 * events, no props beyond the topic slug and an accessible label.
 */
export default class HelpHint extends NavigationMixin(LightningElement) {
  @api topic;
  @api label = "Help";

  open = false;
  lang = "en";
  section = null;

  get text() {
    if (this.section) {
      return this.section.hint[this.lang] || this.section.hint.en;
    }
    return COPY[this.lang].none;
  }
  get hasSection() {
    return this.section !== null;
  }
  get moreLabel() {
    return COPY[this.lang].more;
  }
  get closeLabel() {
    return COPY[this.lang].close;
  }

  connectedCallback() {
    // Warm the shared index so the first click shows the hint, not the
    // "no help" line while it loads. A failure here is reported on click.
    loadIndex().catch(() => {});
  }
  disconnectedCallback() {
    this.detach();
  }

  async handleToggle(event) {
    event.stopPropagation();
    if (this.open) {
      this.close();
      return;
    }
    this.lang = readLang() || defaultLang(LANG);
    this.open = true;
    this.attach();
    try {
      const index = await loadIndex();
      this.section = findSection(index, this.topic);
    } catch {
      this.section = null;
    }
  }
  handleClose(event) {
    event.stopPropagation();
    this.close();
  }
  handleKeydown(event) {
    if (event.key === "Escape" && this.open) {
      this.close();
    }
  }
  handleMore(event) {
    event.preventDefault();
    event.stopPropagation();
    const url = sectionUrl(this.topic, this.lang);
    this.close();
    this[NavigationMixin.Navigate](url);
  }

  // The outside-click listener lives on the document only while open, in
  // the capture phase so a click that another component stops still closes
  // the popover.
  attach() {
    if (!this.outside) {
      this.outside = (event) => {
        if (!event.composedPath().includes(this.template.host)) {
          this.close();
        }
      };
      document.addEventListener("click", this.outside, true);
    }
  }
  detach() {
    if (this.outside) {
      document.removeEventListener("click", this.outside, true);
      this.outside = null;
    }
  }
  close() {
    this.open = false;
    this.detach();
  }
}
