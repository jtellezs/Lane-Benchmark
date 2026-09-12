# Phase 5 — Help center: in-app hints and a bilingual user guide

Date: 2026-09-12. Roadmap: phase 5, after phase 4 retired the old page. Builds
on the Lane Benchmark page (phase 2) and the RFP workbench (phases 3a–3d);
nothing there changes except where this document adds a hint.

## 1. Decisions from the brainstorm (2026-09-12)

| #   | Decision                                                                                                                                                                       |
| --- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| D1  | Two layers: short in-app hints that link to a full guide.                                                                                                                      |
| D2  | The guide lives in the repo as Markdown and is rendered inside Salesforce on a Help tab. No external hosting. Changes ship by pull request and deploy like code.               |
| D3  | English and French, both written here; the pricer's Salesforce language picks the default and a toggle switches.                                                               |
| D4  | Users only. Setup, deploy and admin material stays in the README and in the admin's own documentation, outside Salesforce.                                                     |
| D5  | Hints are a small "?" button per area that opens a popover with one or two sentences and a "Read more" link into the matching guide section. No banners, no first-visit strip. |
| D6  | Production is not deployed yet (user, 2026-09-12); everything here is built and verified in PostProduc only.                                                                   |

## 2. What the pricer sees

- A **Help** tab (API name `Help_Center`) in the Lane Benchmark app and in the
  Trans-Pro app, after RFP Tool. It shows a left column of sections, the
  chosen section's text on the right, a language toggle (EN | FR) and a
  filter box that narrows the section list as you type.
- Opening the tab with `?c__section=rfp-pricing&c__lang=fr` lands on that
  section in French. Without parameters it opens the Overview in the
  language of the user's Salesforce locale (`fr*` → French, anything else →
  English), or the language they last picked on this browser.
- A **"?" button** next to the title of each area listed in §5. Clicking it
  opens a popover with the area's hint in the current language and a
  "Read more" link. The link opens the Help tab at that area's section, in
  the same language. Escape or a click outside closes the popover. Nothing
  else on the page changes.

## 3. Content

Source of truth: `docs/help/en/<slug>.md` and `docs/help/fr/<slug>.md`, one
file per section, same slugs in both languages. Each file starts with a
front-matter block:

```
---
title: Pricing a lane
order: 40
hint: Pick a cost source (a bid, the history median or a number you type), set a margin or a sell price, save.
---
```

`title` is the section heading and the entry in the left column, `order` sorts
the column, `hint` is the popover text (one or two sentences, at most 240
characters). Body: Markdown limited to headings (`##`, `###`), paragraphs,
bold, italics, inline code, links, ordered and unordered lists, and tables. No
images in this phase (ruling R51: screenshots go stale with every UI change;
text first, images when the UI settles).

Sections and slugs (the `order` values leave room between them):

| Slug                 | English title                      | Covers                                                                                                                    |
| -------------------- | ---------------------------------- | ------------------------------------------------------------------------------------------------------------------------- |
| `overview`           | What these tools do                | Lane Benchmark vs RFP Tool, where the data comes from (Revenova loads, carrier bids), who to ask                          |
| `lb-lane`            | Choosing a lane                    | Origin/destination picker, aliases, "Not found? Search on the map", precision (exact city, province, postal, radius)      |
| `lb-filters`         | Filters and lookback               | Lookback days, currency, modes, equipment, hazmat, market test, source (All / Loads / Bids), quote status, saved filters  |
| `lb-stats`           | Reading the statistics             | Per-currency min/median/average/max, priced vs unpriced, margin and suggested sell, 15 % / 20 % buttons                   |
| `lb-results`         | Results, carrier detail and export | Row expand, bid badge and expiry, duplicates removed, CSV export                                                          |
| `rfp-projects`       | RFP projects                       | Create a project (customer, due date, currency, default margin), open, counts                                             |
| `rfp-upload`         | Uploading a lane file and mapping  | Accepted files and limits, column mapping, remembered mapping per customer, import summary, uploading more rows           |
| `rfp-unresolved`     | Unresolved lane ends               | What "Unresolved" means, fixing an end inline, retry                                                                      |
| `rfp-history`        | Loading history                    | Precision, lookback, radius and unit, "Include RFP bids", what "N loads + M bids · median" means, Refresh vs Retry failed |
| `rfp-pricing`        | Pricing a lane                     | Cost source (bid / history median / manual), margin or sell, "Sell follows the margin" vs "Margin follows the sell", Save |
| `rfp-inline`         | Editing in the table               | Click a cell, Enter/Tab/Shift+Tab/Escape, red errors, the "manual" tag, the twin offer                                    |
| `rfp-bids`           | Recording carrier bids             | Existing carrier or free text, rate/currency/FSC/transit/validity, where bids show up afterwards                          |
| `rfp-bulk`           | Bulk actions                       | Selected vs All lanes, Use median and Overwrite, Apply margin/cost/sell, Add carrier rate, Delete (two clicks), Stop      |
| `rfp-filters-export` | Filters, selection and export      | Show filter, text search, select all shown, Export to Excel and its three sheets                                          |
| `faq`                | Questions and problems             | "No match", "Failed", history looks old, wrong currency, who can see what, how to ask for a change                        |

French files carry the same slugs with French `title` and `hint`. The first
draft of both languages is written in this phase; the user reviews the French.

## 4. Build: Markdown to a static resource

`scripts/help/build.mjs` (Node, run as `npm run help:build`) reads both
language folders and writes the static resource
`force-app/main/default/staticresources/helpCenter/` (a folder resource,
`contentType` `application/zip` after the CLI packs it) containing:

- `index.json`: `{ "sections": [ { "slug", "order", "title": { "en", "fr" }, "hint": { "en", "fr" } } ] }` sorted by `order`.
- `en/<slug>.html` and `fr/<slug>.html`: the rendered body of each section.

Rendering uses `marked` (devDependency, pinned) with `headerIds` off and
`mangle` off; output goes through a whitelist that keeps only
`h2 h3 p strong em code a ul ol li table thead tbody tr th td br` and the
`href` attribute on `a` (links must start with `#`, `/`, or `https://`). The
built files are committed (like the vendored `sheetJs`), so a deploy never
depends on a build step. `npm run help:check` rebuilds into a temp folder and
fails if it differs from the committed resource, or if any slug exists in one
language only, or if a `hint` exceeds 240 characters, or if a section's
`order` repeats. CI runs `help:check` in the `lwc` job.

Ruling R52: a folder static resource, not one JSON blob, so the Help tab
fetches one section at a time and hints need only `index.json`.

## 5. Components

### 5.1 `c/helpContent` (pure module)

- `loadIndex()` → cached promise of `index.json` parsed (fetched from the
  static resource URL imported with `@salesforce/resourceUrl/helpCenter`).
- `loadSection(slug, lang)` → cached promise of the HTML string.
- `defaultLang(locale)` → `"fr"` when the locale starts with `fr`, else `"en"`.
- `readLang()` / `writeLang(lang)` → localStorage key `helpCenter.lang.v1`,
  guarded with try/catch (private windows).
- `sectionUrl(slug, lang)` → the page reference for the Help tab:
  `{ type: "standard__navItemPage", attributes: { apiName: "Help_Center" }, state: { c__section: slug, c__lang: lang } }`.

### 5.2 `c/helpCenter` (the tab)

Props: none; reads `CurrentPageReference` for `c__section` and `c__lang`.
State: `lang`, `slug`, `filter`, `sections`, `html`, `error`. Renders the
left column (`lightning-vertical-navigation` items from the filtered index,
titles in `lang`), a `lightning-button-group` EN | FR, a `lightning-input
type="search"` filter, and the section HTML in a `lightning-formatted-rich-text`
(it sanitises again on the client; the tag list in §4 is what it keeps). The
heading above the text is the section title. Changing language keeps the slug
and rewrites the URL state through `NavigationMixin.Navigate` with `replace`.
A failed fetch shows "The help content did not load. Reload the page or ask
your admin." with `data-id="error"`. Every element that a test touches has a
`data-id`: `nav`, `lang-en`, `lang-fr`, `filter`, `title`, `body`, `error`.

### 5.3 `c/helpHint` (the "?" button)

Props: `@api topic` (a slug from §3), `@api label` (accessible name, defaults
to "Help"). Renders a `lightning-button-icon` (`utility:info`, size
`x-small`, `variant="bare"`, `alternative-text={label}`, `data-id="open"`),
and when open a `section.slds-popover slds-nubbin_top-left` with
`role="dialog"`, the hint text (`data-id="text"`) and a "Read more" link
(`data-id="more"`) that navigates through `sectionUrl(topic, lang)`. `lang`
comes from `readLang()` or `defaultLang(LOCALE)` at open time, so a toggle on
the Help tab is honoured by the next hint opened. Escape and an outside click
close it (document `click` listener added on open, removed on close and in
`disconnectedCallback`). If the topic is missing from the index the button
still renders and the popover says "No help for this area yet."

Hint placement (`<c-help-hint topic="…">` right after the area's heading or
label, markup only, no JS in the host component):

| Host component                         | Topic          |
| -------------------------------------- | -------------- |
| `laneBenchmarkPlacePicker` (Lane card) | `lb-lane`      |
| `laneBenchmarkFilters`                 | `lb-filters`   |
| `laneBenchmarkStats`                   | `lb-stats`     |
| `laneBenchmarkResults`                 | `lb-results`   |
| `rfpProjectList`                       | `rfp-projects` |
| `rfpUpload`                            | `rfp-upload`   |
| `rfpColumnMapper`                      | `rfp-upload`   |
| `rfpToolbar`                           | `rfp-history`  |
| `rfpBulkBar`                           | `rfp-bulk`     |
| `rfpLaneTable` (header row)            | `rfp-inline`   |
| `rfpLanePanel`                         | `rfp-pricing`  |
| `rfpBidForm`                           | `rfp-bids`     |

`rfpTool.js` is at 554 of its 560-line ceiling; this phase adds no line to it
(the hints sit in child components; the filter bar's hint goes on the
`rfp-filters-export` topic through `rfpLaneTable`'s header instead of the
container).

## 6. Metadata

- FlexiPage `Help_Center` (app page, one region, `c:helpCenter`), CustomTab
  `Help_Center` (label "Help", icon `Custom54: Ribbon` or the closest help
  icon available), added to `applications/Lane_Benchmark.app-meta.xml` and
  `applications/TransPro.app-meta.xml` after `RFP_Tool`.
- Tab visibility `Visible` in `Lane_Benchmark_User` and `RFP_Tool_User`. No
  Apex, so no class access.
- Static resource `helpCenter` (`cacheControl` `Public`).
- Manifest: the three bundles (`helpContent`, `helpCenter`, `helpHint`), the
  FlexiPage, the CustomTab, the StaticResource, the two app files already
  listed.

## 7. Testing

- Jest: `helpContent` (defaultLang, lang storage with a throwing localStorage,
  sectionUrl shape, index/section caching with a mocked `fetch`),
  `helpCenter` (opens the section from the URL, falls back to overview,
  toggle rewrites state and reloads the HTML, filter narrows the nav,
  error state), `helpHint` (opens/closes, text in the right language, "Read
  more" navigates with the topic, unknown topic message, listener removed on
  disconnect), and one placement test per host component asserting the
  `c-help-hint` with the expected `topic` is in its template.
- `npm run help:check` as described in §4, plus a Jest test that every
  `topic="…"` used in `force-app/main/default/lwc/**/*.html` exists in
  `index.json`.
- Browser (PostProduc): Help tab opens in English for an English user; FR
  toggle switches and is remembered; deep link from the RFP panel's "?" lands
  on "Pricing a lane" in the current language; the popover closes on Escape;
  the French section reads well (the user reviews the French text).

## 8. Out of scope

Screenshots and videos; per-field help text; Salesforce Knowledge; search
across the guide's body text (the filter matches titles only); analytics on
which hints are opened; production deploy (D6).

## 9. Rulings

- R51 — no images in the first version.
- R52 — folder static resource with one HTML file per section and language.
- R53 — the Help tab is a separate FlexiPage rather than a component embedded
  in each tool's page, so the guide has a stable URL for deep links and the
  two tools' pages do not grow.
