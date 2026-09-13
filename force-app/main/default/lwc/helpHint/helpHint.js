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

// Gap between the trigger and the popover, and how far the popover's edge
// overhangs the trigger so the nubbin (1.5rem in from that edge) points at it.
const GAP = 6;
const OVERHANG = 8;

/**
 * The "?" next to an area's title: a popover with that area's one-line hint
 * and a "Read more" link into the Help tab. Markup-only for the host: no
 * events, no props beyond the topic slug and an accessible label.
 *
 * The popover is position: fixed and placed from the trigger's viewport
 * rectangle when it opens, so it is never clipped by the page edge or by a
 * scrolling container. Any scroll closes it, so it cannot drift away from
 * its trigger.
 */
export default class HelpHint extends NavigationMixin(LightningElement) {
  @api topic;
  @api label = "Help";

  open = false;
  lang = "en";
  section = null;
  // Placement, computed at open time: which viewport edge the popover is
  // anchored to and how far from it, plus its top.
  side = "left";
  offset = 0;
  top = 0;

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
  get expanded() {
    return this.open ? "true" : "false";
  }
  get nubbinClass() {
    return `slds-nubbin_top-${this.side}`;
  }
  get popoverClass() {
    return `slds-popover popover ${this.nubbinClass}`;
  }
  get popoverStyle() {
    return `top: ${this.top}px; ${this.side}: ${this.offset}px;`;
  }

  connectedCallback() {
    // Warm the shared index so the first click shows the hint, not the
    // "no help" line while it loads. A failure here is reported on click.
    loadIndex().catch(() => {});
  }
  disconnectedCallback() {
    this.detach();
  }
  renderedCallback() {
    // The popover is a dialog: once it has rendered, focus goes to its
    // close button. The flag is not read by the template, so clearing it
    // here does not schedule another render.
    if (this.focusPending) {
      this.focusPending = false;
      const close = this.template.querySelector('[data-id="close"]');
      if (close) {
        close.focus();
      }
    }
  }

  async handleToggle(event) {
    event.stopPropagation();
    if (this.open) {
      // A second click on the "?" also puts focus back on it: browsers that
      // do not focus a clicked button would otherwise drop focus to body
      // when the focused close button leaves the DOM.
      this.close({ restoreFocus: true });
      return;
    }
    this.lang = readLang() || defaultLang(LANG);
    this.place();
    this.open = true;
    this.focusPending = true;
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
    this.close({ restoreFocus: true });
  }
  handleMore(event) {
    event.preventDefault();
    event.stopPropagation();
    const url = sectionUrl(this.topic, this.lang);
    this.close({ restoreFocus: true });
    this[NavigationMixin.Navigate](url);
  }

  get trigger() {
    return this.template.querySelector('[data-id="open"]');
  }

  // Anchor the popover to the trigger's viewport rectangle: below it, and
  // opening towards the side of the screen with more room. The layout
  // viewport width (clientWidth) is the one a fixed element's "right" is
  // measured from; window.innerWidth also counts a classic scrollbar, which
  // would push a right-anchored popover one scrollbar width off the trigger.
  // jsdom reports a clientWidth of 0, hence the fallback.
  place() {
    const button = this.trigger;
    const rect = button
      ? button.getBoundingClientRect()
      : { left: 0, right: 0, bottom: 0 };
    const viewportWidth =
      document.documentElement.clientWidth || window.innerWidth;
    this.top = Math.round(rect.bottom + GAP);
    if (rect.left <= viewportWidth / 2) {
      this.side = "left";
      this.offset = Math.round(rect.left - OVERHANG);
    } else {
      this.side = "right";
      this.offset = Math.round(viewportWidth - rect.right - OVERHANG);
    }
  }

  // The document listeners live only while the popover is open, all in the
  // capture phase: a click that another component stops still closes the
  // popover, Escape closes it wherever focus is, and a scroll anywhere
  // (scroll events do not bubble) closes it before it can float away from
  // the trigger. detach() removes the same function references.
  attach() {
    if (!this.outside) {
      this.outside = (event) => {
        if (!event.composedPath().includes(this.template.host)) {
          this.close();
        }
      };
      // Escape gives focus back to the "?" only when focus was inside the
      // popover; a user who Tabbed on and presses Escape for another control
      // keeps their place, as with an outside click.
      this.onKey = (event) => {
        if (event.key === "Escape" && this.open) {
          this.close({ restoreFocus: this.template.activeElement !== null });
        }
      };
      this.onScroll = () => {
        this.close();
      };
      document.addEventListener("click", this.outside, true);
      document.addEventListener("keydown", this.onKey, true);
      document.addEventListener("scroll", this.onScroll, true);
    }
  }
  detach() {
    if (this.outside) {
      document.removeEventListener("click", this.outside, true);
      document.removeEventListener("keydown", this.onKey, true);
      document.removeEventListener("scroll", this.onScroll, true);
      this.outside = null;
      this.onKey = null;
      this.onScroll = null;
    }
  }
  // Focus goes back to the "?" (before the popover leaves the DOM) when the
  // user dismissed the dialog from inside it or with Escape; an outside
  // click or a scroll leaves focus where it is.
  close({ restoreFocus = false } = {}) {
    if (restoreFocus) {
      const button = this.trigger;
      if (button) {
        button.focus();
      }
    }
    this.open = false;
    this.detach();
  }
}
