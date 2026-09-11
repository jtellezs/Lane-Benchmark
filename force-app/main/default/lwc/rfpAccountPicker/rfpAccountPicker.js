import { LightningElement, api, track } from "lwc";
import searchAccounts from "@salesforce/apex/RfpProjectController.searchAccounts";

const DEBOUNCE_MS = 250;

// One listbox id per instance, so a customer picker and a carrier picker on the
// same screen don't collide on aria-controls / aria-activedescendant targets.
let nextPickerId = 0;

export default class RfpAccountPicker extends LightningElement {
  @api label = "Account";
  @api kind = "customer";

  listboxId = `rfp-account-listbox-${nextPickerId++}`;

  _value = null;
  _valueLabel = "";

  @api
  get value() {
    return this._value;
  }
  set value(val) {
    // invalidates a still-pending searchAccounts response so it can't reopen the list
    this.requestSeq++;
    this._value = val || null;
    if (val) {
      this.term = "";
      this.setOptions([]);
      this.isOpen = false;
      window.clearTimeout(this.timer);
    }
  }

  @api
  get valueLabel() {
    return this._valueLabel;
  }
  set valueLabel(val) {
    this._valueLabel = val || "";
  }

  @track options = [];
  highlightedIndex = -1;
  term = "";
  isOpen = false;
  isSearching = false;
  error = null;
  timer = null;
  requestSeq = 0;

  get hasValue() {
    return !!this._value;
  }
  get displayValue() {
    return this.hasValue ? this._valueLabel : this.term;
  }
  get listItems() {
    return this.options.map((o, index) => ({
      ...o,
      optionId: `${this.listboxId}-option-${index}`,
      liClass:
        index === this.highlightedIndex
          ? "slds-listbox__item option slds-has-focus"
          : "slds-listbox__item option",
      ariaSelected: index === this.highlightedIndex ? "true" : "false"
    }));
  }
  get activeDescendant() {
    return this.highlightedIndex >= 0
      ? `${this.listboxId}-option-${this.highlightedIndex}`
      : null;
  }

  /** Every options list change (results, pick, clear) resets the keyboard highlight. */
  setOptions(list) {
    this.options = list;
    this.highlightedIndex = -1;
  }

  handleTerm(event) {
    this.term = event.detail.value || "";
    if (this.hasValue) {
      // typing over a chosen account drops it, so the form never keeps an id
      // that no longer matches what is on screen
      this._value = null;
      this._valueLabel = "";
      this.emit();
    }
    window.clearTimeout(this.timer);
    // eslint-disable-next-line @lwc/lwc/no-async-operation -- debounce the typeahead
    this.timer = window.setTimeout(() => this.search(), DEBOUNCE_MS);
  }

  async search() {
    const term = this.term.trim();
    if (term.length < 2) {
      this.setOptions([]);
      this.isOpen = false;
      return;
    }
    const seq = ++this.requestSeq;
    this.isSearching = true;
    try {
      const results = await searchAccounts({ term, kind: this.kind });
      if (seq !== this.requestSeq) {
        return; // a newer search already landed; drop this stale response
      }
      this.setOptions(results || []);
      this.isOpen = true;
      this.error = null;
    } catch (e) {
      if (seq !== this.requestSeq) {
        return;
      }
      this.error = e?.body?.message || "The account search failed";
      this.setOptions([]);
    } finally {
      if (seq === this.requestSeq) {
        this.isSearching = false;
      }
    }
  }

  handlePick(event) {
    const id = event.currentTarget.dataset.accountId;
    this.selectOption(this.options.find((o) => o.id === id));
  }

  selectOption(opt) {
    if (!opt) {
      return;
    }
    // invalidates a still-pending searchAccounts response so it can't reopen the list
    this.requestSeq++;
    this._value = opt.id;
    this._valueLabel = opt.name;
    this.term = "";
    this.setOptions([]);
    this.isOpen = false;
    this.emit();
  }

  handleClear() {
    this.requestSeq++;
    this._value = null;
    this._valueLabel = "";
    this.term = "";
    this.setOptions([]);
    this.isOpen = false;
    window.clearTimeout(this.timer);
    this.emit();
  }

  handleKey(event) {
    if (event.key === "Escape") {
      this.isOpen = false;
      return;
    }
    if (!this.isOpen) {
      return;
    }
    if (event.key === "ArrowDown") {
      event.preventDefault();
      this.moveHighlight(1);
    } else if (event.key === "ArrowUp") {
      event.preventDefault();
      this.moveHighlight(-1);
    } else if (event.key === "Enter") {
      event.preventDefault();
      this.selectOption(this.options[this.highlightedIndex]);
    }
  }

  moveHighlight(step) {
    if (!this.options.length) {
      return;
    }
    const next = this.highlightedIndex + step;
    this.highlightedIndex = Math.min(
      Math.max(next, 0),
      this.options.length - 1
    );
  }

  disconnectedCallback() {
    window.clearTimeout(this.timer);
  }

  emit() {
    this.dispatchEvent(
      new CustomEvent("accountchange", {
        detail: { id: this._value, name: this._valueLabel }
      })
    );
  }
}
