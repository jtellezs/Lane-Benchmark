# Phase 5 — Help Center Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give pricers a bilingual (EN/FR) user guide on a Help tab inside Salesforce, plus small "?" hints in each tool area that link to the matching guide section.

**Architecture:** Markdown in `docs/help/{en,fr}` is rendered by a Node script into a committed folder static resource (`helpCenter`: `index.json` + one HTML file per section and language). Three LWC bundles consume it: `c/helpContent` (fetch + language helpers), `c/helpCenter` (the Help tab: nav, toggle, filter, body) and `c/helpHint` (the "?" popover with a "Read more" deep link). Twelve existing components get a `<c-help-hint topic="…">` in their markup only. No Apex.

**Tech Stack:** Salesforce DX (API 64.0), LWC, Jest (`@salesforce/sfdx-lwc-jest`), Node 20 build script with `marked`, ESLint 9, Prettier, GitHub Actions CI. Sandbox: `sf` alias `sandbox` (PostProduc). Production is NOT deployed in this phase.

**Spec:** `docs/superpowers/specs/2026-09-12-phase-5-help-center-design.md`

## Global Constraints

- Deploy only to the org alias `sandbox`. Never to `vscodeOrg`, `Full`, `devpro` or any other alias. Production stays untouched (spec D6).
- NO "Co-Authored-By", NO "Generated with", NO AI ATTRIBUTION TRAILER OF ANY KIND IN ANY COMMIT MESSAGE. Before pushing or reporting, `git log --format=%B main..HEAD | grep -ci "co-authored\|generated with"` must print 0.
- Never commit `.vscode/settings.json` (it is dirty in the tree; stage files by name).
- ESLint 9 config as-is: no `eslint-disable`, no `await` inside loops (use `Promise.all` or `series` from `c/rfpBatch`), no arrow functions whose body is a ternary (write a function declaration). Prettier runs on commit and may reformat staged files.
- `rfpTool.js` is at 554 of its 560-line ceiling: this phase adds no line to `rfpTool.js` or `rfpTool.html` (spec §5.3).
- Content rules (spec §3): one file per section per language, identical slugs, front matter `title`, `order`, `hint`; `hint` at most 240 characters; Markdown limited to `##`/`###` headings, paragraphs, bold, italics, inline code, links, ordered/unordered lists, tables; no images.
- Rendered HTML keeps only `h2 h3 p strong em code a ul ol li table thead tbody tr th td br` and the `href` attribute on `a` whose value starts with `#`, `/` or `https://` (spec §4).
- Every new LWC bundle, the FlexiPage, the CustomTab and the StaticResource go into `manifest/package.xml`. The Help tab is `Visible` in `Lane_Benchmark_User` and `RFP_Tool_User`. No Apex, so no class access.
- Every element a test touches has a `data-id`. Tests never assert on styling.
- Deploys run in the foreground with a Bash timeout of 600000 ms; if the CLI times out, poll with `sf project deploy report -o sandbox --use-most-recent -w 10`. Full-manifest deploys: `-l NoTestRun` first when metadata is new, then `-l RunSpecifiedTests` with the 22 classes listed in README (`grep -n RunSpecifiedTests README.md`).
- Do not call the `advisor` tool. Do not spawn subagents. Do not push. Do not merge.

---

## File structure

| Path                                                                                                | Responsibility                                                                               |
| --------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------- |
| `docs/help/en/*.md`, `docs/help/fr/*.md`                                                            | Guide source, 15 sections per language (Tasks 1–2)                                           |
| `scripts/help/build.mjs`                                                                            | Markdown → `staticresources/helpCenter/` (`index.json`, `en/*.html`, `fr/*.html`); `--check` |
| `force-app/main/default/staticresources/helpCenter/` + `.resource-meta.xml`                         | Committed build output (folder resource, `application/zip`)                                  |
| `force-app/main/default/lwc/helpContent/`                                                           | Pure module: index/section loading with cache, language default/storage, deep-link page ref  |
| `force-app/main/default/lwc/helpHint/`                                                              | "?" button + popover + "Read more"                                                           |
| `force-app/main/default/lwc/helpCenter/`                                                            | The Help tab component                                                                       |
| `force-app/main/default/flexipages/Help_Center.flexipage-meta.xml`, `tabs/Help_Center.tab-meta.xml` | App page and tab                                                                             |
| `applications/Lane_Benchmark.app-meta.xml`, `applications/TransPro.app-meta.xml`                    | Tab added after `RFP_Tool`                                                                   |
| `permissionsets/Lane_Benchmark_User…`, `permissionsets/RFP_Tool_User…`                              | `tabSettings` for `Help_Center`                                                              |
| twelve host templates (spec §5.3)                                                                   | one `<c-help-hint>` each, markup only                                                        |
| `.github/workflows/ci.yml`, `package.json`, `README.md`, roadmap spec                               | `help:check` in CI, scripts, docs                                                            |

---

### Task 1: English guide content

**Files:**

- Create: `docs/help/en/overview.md`, `lb-lane.md`, `lb-filters.md`, `lb-stats.md`, `lb-results.md`, `rfp-projects.md`, `rfp-upload.md`, `rfp-unresolved.md`, `rfp-history.md`, `rfp-pricing.md`, `rfp-inline.md`, `rfp-bids.md`, `rfp-bulk.md`, `rfp-filters-export.md`, `faq.md`

**Interfaces:**

- Produces: the 15 slugs above with `order` 10, 20, 30, 40, 50, 60, 70, 80, 90, 100, 110, 120, 130, 140, 150 (in the order listed). Task 3's build reads `title`, `order`, `hint` from the front matter.

- [ ] **Step 1: Write the fifteen files with exactly this content**

`docs/help/en/overview.md`

```markdown
---
title: What these tools do
order: 10
hint: Lane Benchmark shows what a lane cost recently; the RFP Tool prices a customer's lane list from that history and from carrier bids.
---

## Two tools, one source of truth

**Lane Benchmark** answers "what did this lane cost recently?". You pick an origin and a destination, how precisely to match them, and how far back to look. It returns every matching carrier quote from Revenova loads plus the carrier bids recorded in the RFP Tool, with per-currency statistics and a suggested sell.

**RFP Tool** prices a whole customer request. You upload the customer's lane file, the tool matches each lane's ends to known places, loads the same history per lane, and lets you set a cost, a margin and a sell for every lane - one at a time, straight in the table, or in bulk - then export the priced list to Excel.

## Where the numbers come from

- **Loads**: carrier quotes on Revenova loads, matched by the lane's origin and destination.
- **Bids**: carrier rates recorded in the RFP Tool without a load (a quote a carrier gave you for an RFP). They show with a **Bid** badge and an expiry date.

Both sources are filtered by the lookback window (days since the quote or bid was created).

## Who to ask

Access is granted by the `Lane_Benchmark_User` and `RFP_Tool_User` permission sets. If a tab is missing or a button is greyed out with a permission message, ask your Salesforce admin.
```

`docs/help/en/lb-lane.md`

```markdown
---
title: Choosing a lane
order: 20
hint: Type a city, province or alias for each end, then pick how precisely to match: exact city, province, postal prefix or a radius.
---

## Origin and destination

Start typing a city name, a province or an alias the team uses (for example a plant name). The list shows known places with how many loads touched them. Pick one. If the place is not in the list, click **Not found? Search on the map** to look it up by address; the tool adds it to the place dictionary for next time.

## Precision

Each end has its own precision:

| Precision        | Matches                                                |
| ---------------- | ------------------------------------------------------ |
| Exact city       | the city exactly as Revenova wrote it, accents ignored |
| Province / state | anything in that province or state                     |
| Postal prefix    | the first three characters of the postal code          |
| Radius           | every stop within the distance you set (km or mi)      |

Radius is the widest net: use it when an exact city has no history of its own. The RFP Tool falls back to a radius search automatically when a city has no match.

## Tips

- Aliases save typing: ask your admin to add the names the team uses.
- A saved lane and its filters come back when you reopen the page.
```

`docs/help/en/lb-filters.md`

```markdown
---
title: Filters and lookback
order: 30
hint: Lookback is how many days back to search. Currency, mode, equipment, hazmat, market test, source and quote status narrow the results.
---

## Lookback

The number of days back to search, counted from when the quote or bid was created. 90 days is the default. Longer windows return more rows and take longer on radius searches.

## Filters

- **Currency**: All, or one currency. Statistics are always per currency.
- **Modes** and **Equipment categories / types**: move the ones you want into the Selected list; nothing selected means no filter.
- **Hazmat only**, **Market test only**: keep only quotes with that flag.
- **Source**: **All** (loads and bids), **Loads only**, or **Bids only**. Under All, expired bids are left out; under Bids only they are listed with their expiry so you can see what was quoted.
- **Quote status**: All, Accepted or Declined quotes on loads.

## Apply, Reset and saved filters

**Apply** runs the search. **Reset** clears the lane and filters. Your last lane and filters are remembered on this computer; **Clear saved filters** forgets them.
```

`docs/help/en/lb-stats.md`

```markdown
---
title: Reading the statistics
order: 40
hint: One box per currency: min, median, average, max over the priced quotes, and a suggested sell from the margin you type.
---

## One box per currency

Statistics are never mixed across currencies. Each box shows how many quotes matched and how many had a price, then the minimum, median, average and maximum of the priced ones.

## Margin and suggested sell

Type a margin percentage (15 is the default) or click **15%** / **20%**. The box shows **Sell (median)** and **Sell (average)**: the median or average cost plus that margin. These are suggestions, not prices; nothing is saved here.

## Duplicates

The same quote can appear on several loads. Identical rows (same carrier, lane, mode, equipment and total) are counted once; the header says how many duplicates were removed.
```

`docs/help/en/lb-results.md`

```markdown
---
title: Results, carrier detail and export
order: 50
hint: Each row is one quote. Expand it for the load and contact detail; bids carry a badge and an expiry. Export CSV downloads what you see.
---

## The rows

Each row is one carrier quote: origin, destination, carrier, equipment, mode, currency, total, quote date, status and flags. Click the arrow at the left to expand the load and contact details, and the carrier name to open the carrier record.

## Bids

A row with the **Bid** badge is a rate recorded in the RFP Tool, not a load. Its flags show **Expires** with the date. Under Source = All, only bids still valid today are included.

## Export CSV

**Export CSV** downloads the rows on screen, with a Source column (Load or Bid), named after the lane and the date. It opens in Excel or Numbers.
```

`docs/help/en/rfp-projects.md`

```markdown
---
title: RFP projects
order: 60
hint: A project is one customer request: name, customer, due date, currency and default margin. Open it to upload lanes and price them.
---

## Create a project

On the RFP Tool tab, fill in **Name** (required), **Customer** (type two letters and pick the account), **Due date**, **Currency** (the currency you will quote in) and **Default margin %** (applied to every lane until you change it). Click **Create**; the project opens on the upload step.

## The project list

Each row shows the customer, status, due date, how many lanes the project has, how many have a cost and how many have a sell price, and the file that was uploaded. Click the project name to open it. **All projects** brings you back.
```

`docs/help/en/rfp-upload.md`

```markdown
---
title: Uploading a lane file and mapping
order: 70
hint: Upload the customer's .xlsx or .csv, match its columns to our fields (the mapping is remembered per customer), then import.
---

## The file

Accepted: `.xlsx`, `.xlsm`, `.xls`, `.csv` up to 3 MB and 2,000 lanes per project. The first row must be the headers. A second upload into the same project adds rows after the existing ones.

## Mapping the columns

The tool guesses which column is the origin city, destination postal code, mode, equipment, quantity and so on, and shows a sample of each. Fix any guess with the dropdowns. Origin and destination need at least a city or a postal code each. The mapping is remembered for this customer's next file.

## Import

**Import lanes** creates one lane per row and matches each end to a known place. The summary line reads "imported N, skipped N, unresolved ends N". Skipped rows had no usable origin or destination; unresolved ends are lanes whose city could not be matched - see **Unresolved lane ends**.
```

`docs/help/en/rfp-unresolved.md`

```markdown
---
title: Unresolved lane ends
order: 80
hint: An "Unresolved" lane has an end the tool could not match to a known place. Fix the place inline, then reload its history.
---

## What it means

A lane shows **Unresolved** when its origin or destination city (or postal prefix) is not in the place dictionary, often because of a typo, an unusual spelling or a very small town. The lane is imported but cannot be searched.

## Fixing it

In the lane row, the unresolved end shows an **Origin** or **Destination** field with a **Precision** picker. Type the place, pick it from the list (or search the map), and save. Then click **Retry failed** in the toolbar to load history for the lanes you fixed.

## Prevention

Ask your admin to add an alias for the spelling the customer uses, so the next file resolves on its own.
```

`docs/help/en/rfp-history.md`

```markdown
---
title: Loading history
order: 90
hint: Load history runs a Lane Benchmark search per lane. Choose precision, lookback, radius and whether to count other RFPs' bids, then read "N loads + M bids · median".
---

## Running it

Set **History precision** (City, Province or Radius), **Lookback (days)**, **Radius** and its **Unit**, and whether to **Include RFP bids**, then click **Load history**. Lanes are processed in batches with a progress bar; **Stop** ends the run after the current batch. **Refresh history** reruns every lane; **Retry failed** reruns only the lanes marked Failed or Unresolved.

## Radius fallback

With City precision, a lane whose city has no history is searched again within the radius. The History cell's tooltip shows which precision was used, for example `RADIUS-50KM`.

## Include RFP bids

When on (the default), carrier bids recorded on **other** RFP projects count alongside the loads, even after their validity date, as long as they are inside the lookback. Bids on the project you are pricing are never counted - they are your own inputs. The History cell then reads "5 loads + 1 bid · median 5,500.00". When off, only loads count.

## Reading the cell

- `12 · median 5,800.00`: twelve quotes matched, the median of the priced ones is 5,800.
- `3 · no median`: three matched but none had a price.
- **No match**, **Failed**, **Unresolved**, **Pending**: no history yet; hover for the reason.

Statistics use only quotes in the lane's own currency.
```

`docs/help/en/rfp-pricing.md`

```markdown
---
title: Pricing a lane
order: 100
hint: Pick a cost source (a bid, the history median or a number you type), set a margin or a sell price, then Save price.
---

## The panel

Click a lane to open its panel on the right. It stays in view while you scroll the table.

## Cost source

- **Bid**: pick one of the carrier rates recorded for this lane. The cost is the bid's rate.
- **History median**: the median from the last history run.
- **Manual**: type the cost yourself.

## Margin or sell

Type a **Margin %** and the sell follows ("Sell follows the margin"), or type a **Sell** and the margin follows ("Margin follows the sell"). A sell you typed is kept when the cost changes later; the table shows a **manual** tag on it. Clear the sell to go back to margin mode.

## Save

**Save price** writes the cost, margin and sell to the lane and marks it **Priced**. **Add carrier rate** records a new bid for this lane and selects it as the cost.

## Results

Below the form, the lane's history rows are listed exactly as Lane Benchmark shows them, so you can see which quotes made the median.
```

`docs/help/en/rfp-inline.md`

```markdown
---
title: Editing in the table
order: 110
hint: Click a Cost, Margin or Sell cell and type. Enter saves and moves down, Tab moves down, Shift+Tab moves up, Escape cancels.
---

## Cells you can type in

**Cost**, **Margin** and **Sell** are editable in the table, like a spreadsheet. Click a cell (the row is selected at the same time), type a value and press:

- **Enter** or **Tab**: save and open the same cell on the next row.
- **Shift+Tab**: save and open the same cell on the previous row.
- **Escape**: close without saving.

Clicking elsewhere also saves. A cost typed here sets the cost source to Manual; a sell typed here is a manual sell (the **manual** tag) and the margin follows it.

## Errors

A value that cannot be saved (zero, negative, a margin over 100) shows a red message under the cell and the cell stays open until you fix it or press Escape.

## Identical lanes

When you price a lane that has twins in the same project (same ends, mode and equipment), a bar offers to copy the cost and sell to them. **Apply** copies; **Not now** dismisses.
```

`docs/help/en/rfp-bids.md`

```markdown
---
title: Recording carrier bids
order: 120
hint: Add carrier rate stores a carrier's quote for a lane without creating a load: existing carrier or free text, rate, currency, validity dates.
---

## When to record a bid

A carrier answered your RFP with a rate. Record it so it counts as history for this lane, for other RFPs, and in Lane Benchmark.

## The form

- **Carrier**: type two letters and pick the account, or switch **Carrier not in the system** on and type the name and a contact (name, email, phone).
- **Rate** and **Currency**; **Fuel surcharge** and **FSC included** when relevant; **Transit days**.
- **Valid from** and **Expires on**: default today and today + 30 days.
- **Notes**: anything the carrier said that matters.

**Save bid** stores it and, from the lane panel, selects it as the lane's cost source.

## Where bids show up

In the lane panel (with Active or Expired), in Lane Benchmark with the **Bid** badge, and in other projects' history under "Include RFP bids". Bids belong to the project they were recorded on and never count in that project's own history.
```

`docs/help/en/rfp-bulk.md`

```markdown
---
title: Bulk actions
order: 130
hint: Choose Selected or All lanes, then Use median, Apply margin, cost or sell, Add carrier rate, or Delete. Runs go 200 lanes at a time with a Stop button.
---

## Scope

**Selected (N)** acts on the lanes you ticked; **All lanes (N)** acts on every lane in the project.

## Actions

- **Use median**: costs each lane from its history median. Lanes already costed from a bid or by hand are left alone; the bar then says how many and offers **Overwrite them**. Lanes without a median are reported separately.
- **Apply margin**, **Apply cost**, **Apply sell**: set that value on every lane in scope and recompute the rest.
- **Add carrier rate**: record the same bid on every lane in scope and select it as the cost (lanes in another currency are skipped).
- **Delete selected**: removes the lanes and their bids. It asks for a second click to confirm.

## Progress and Stop

Long runs show a progress bar. **Stop** ends the run after the current batch; the summary line says how many lanes were updated, skipped or failed.
```

`docs/help/en/rfp-filters-export.md`

```markdown
---
title: Filters, selection and export
order: 140
hint: Show narrows the table (Unpriced, No history match, Manual…), the search box filters by text, the header checkbox selects the rows shown, Export to Excel builds the workbook.
---

## Show and search

**Show** keeps only one kind of lane: All, Unpriced, No history match, Unresolved ends, Manual cost or sell, or Selected. The search box matches origin, destination and equipment. The counter reads "N of M lanes".

## Selecting

Tick rows one by one, or tick the header checkbox to select every row currently shown (a filter plus select-all is the quickest way to bulk-price a subset).

## Export to Excel

**Export to Excel** downloads a workbook with three sheets: **Lanes** (every lane with its history, cost, margin, sell, annual sell and sell source), **Bids**, and **Summary** (counts, total annual sell per currency, average margin, by mode). Open it in Excel or Numbers.
```

`docs/help/en/faq.md`

```markdown
---
title: Questions and problems
order: 150
hint: No match, Failed, old history, wrong currency, missing tab: the usual causes and what to do.
---

## "No match" on a lane

The ends resolved but no quote or bid matched within the lookback and precision. Widen the radius, extend the lookback, or check the mode and equipment filters.

## "Failed" on a lane

The search itself failed (usually a timeout on a very wide radius). Click **Retry failed**; if it keeps failing, narrow the radius or the lookback.

## The history looks old

History is a snapshot taken when you clicked Load or Refresh. The tooltip shows when. Click **Refresh history** to take a new one.

## The median is in the wrong currency

Statistics use only quotes in the lane's own currency (the project's currency). A lane with USD quotes only shows no CAD median; record a bid or type the cost.

## I cannot see the tab or a button says I lack permission

Ask your admin for the `Lane_Benchmark_User` and `RFP_Tool_User` permission sets.

## Something looks wrong

Send your admin the project name, the lane number and what you expected. Changes to these tools go through a pull request, so the fix will be tracked.
```

- [ ] **Step 2: Check the content rules**

Run:

```bash
for f in docs/help/en/*.md; do h=$(awk '/^hint:/{sub(/^hint: /,""); print length($0)}' "$f"); echo "$f hint=$h"; done | awk '$2 ~ /hint=/ {split($2,a,"="); if (a[2] > 240) print "TOO LONG", $0}'
grep -L "^title:" docs/help/en/*.md; grep -L "^order:" docs/help/en/*.md; grep -c "" docs/help/en/*.md | wc -l
```

Expected: no "TOO LONG" line, both `grep -L` print nothing, the count line prints `15`.

- [ ] **Step 3: Commit**

```bash
git add docs/help/en
git commit -m "Write the English help guide"
```

---

### Task 2: French guide content

**Files:**

- Create: `docs/help/fr/` — the same fifteen slugs as Task 1.

**Interfaces:**

- Consumes: the slugs and `order` values from Task 1 (identical here).
- Produces: French `title` and `hint` per slug; Task 3's build refuses a slug present in one language only.

- [ ] **Step 1: Write the fifteen files with exactly this content**

`docs/help/fr/overview.md`

```markdown
---
title: À quoi servent ces outils
order: 10
hint: Lane Benchmark montre ce qu'une voie a coûté récemment; l'outil RFP tarifie la liste de voies d'un client à partir de cet historique et des soumissions des transporteurs.
---

## Deux outils, une seule source

**Lane Benchmark** répond à « combien cette voie a-t-elle coûté récemment? ». Vous choisissez une origine, une destination, la précision de la correspondance et la période. L'outil renvoie toutes les cotations de transporteurs correspondantes tirées des chargements Revenova, plus les soumissions enregistrées dans l'outil RFP, avec des statistiques par devise et un prix de vente suggéré.

**L'outil RFP** tarifie une demande complète d'un client. Vous téléversez le fichier de voies du client, l'outil associe les extrémités de chaque voie à des lieux connus, charge le même historique voie par voie, et vous laisse fixer un coût, une marge et un prix de vente pour chaque voie - une à la fois, directement dans le tableau, ou en lot - puis exporter la liste tarifée vers Excel.

## D'où viennent les chiffres

- **Chargements** : cotations de transporteurs sur des chargements Revenova, appariées par origine et destination.
- **Soumissions** : tarifs de transporteurs enregistrés dans l'outil RFP sans chargement (une cotation reçue pour un appel d'offres). Elles portent l'étiquette **Bid** et une date d'expiration.

Les deux sources sont limitées par la fenêtre de recherche (jours depuis la création de la cotation ou de la soumission).

## À qui s'adresser

L'accès est donné par les ensembles d'autorisations `Lane_Benchmark_User` et `RFP_Tool_User`. Si un onglet manque ou qu'un bouton est grisé avec un message d'autorisation, demandez à votre administrateur Salesforce.
```

`docs/help/fr/lb-lane.md`

```markdown
---
title: Choisir une voie
order: 20
hint: Tapez une ville, une province ou un alias pour chaque extrémité, puis choisissez la précision : ville exacte, province, préfixe postal ou rayon.
---

## Origine et destination

Commencez à taper un nom de ville, une province ou un alias utilisé par l'équipe (par exemple le nom d'une usine). La liste montre les lieux connus et le nombre de chargements qui les ont touchés. Choisissez-en un. Si le lieu n'est pas dans la liste, cliquez sur **Not found? Search on the map** pour le chercher par adresse; l'outil l'ajoute au dictionnaire des lieux pour la prochaine fois.

## Précision

Chaque extrémité a sa propre précision :

| Précision       | Correspond à                                            |
| --------------- | ------------------------------------------------------- |
| Ville exacte    | la ville telle que Revenova l'a écrite, accents ignorés |
| Province / état | tout ce qui se trouve dans cette province ou cet état   |
| Préfixe postal  | les trois premiers caractères du code postal            |
| Rayon           | tous les arrêts dans la distance choisie (km ou mi)     |

Le rayon ratisse le plus large : utilisez-le quand une ville exacte n'a pas d'historique. L'outil RFP passe automatiquement au rayon quand une ville n'a aucune correspondance.

## Conseils

- Les alias évitent de retaper : demandez à votre administrateur d'ajouter les noms que l'équipe utilise.
- La voie et les filtres enregistrés reviennent quand vous rouvrez la page.
```

`docs/help/fr/lb-filters.md`

```markdown
---
title: Filtres et période
order: 30
hint: La période est le nombre de jours à remonter. Devise, mode, équipement, matières dangereuses, test de marché, source et statut de cotation resserrent les résultats.
---

## Période (lookback)

Le nombre de jours à remonter, compté depuis la création de la cotation ou de la soumission. 90 jours par défaut. Une fenêtre plus longue renvoie plus de lignes et prend plus de temps sur une recherche par rayon.

## Filtres

- **Devise** : toutes, ou une seule. Les statistiques sont toujours par devise.
- **Modes** et **catégories / types d'équipement** : déplacez ceux voulus dans la liste Selected; rien de sélectionné veut dire aucun filtre.
- **Hazmat only**, **Market test only** : ne garder que les cotations portant ce drapeau.
- **Source** : **All** (chargements et soumissions), **Loads only**, ou **Bids only**. Sous All, les soumissions expirées sont exclues; sous Bids only elles sont listées avec leur expiration.
- **Quote status** : toutes, acceptées ou refusées.

## Apply, Reset et filtres enregistrés

**Apply** lance la recherche. **Reset** efface la voie et les filtres. Votre dernière voie et vos filtres sont mémorisés sur cet ordinateur; **Clear saved filters** les oublie.
```

`docs/help/fr/lb-stats.md`

```markdown
---
title: Lire les statistiques
order: 40
hint: Une boîte par devise : min, médiane, moyenne, max sur les cotations tarifées, et un prix de vente suggéré à partir de la marge saisie.
---

## Une boîte par devise

Les statistiques ne sont jamais mélangées entre devises. Chaque boîte indique combien de cotations correspondent et combien avaient un prix, puis le minimum, la médiane, la moyenne et le maximum des cotations tarifées.

## Marge et prix de vente suggéré

Saisissez un pourcentage de marge (15 par défaut) ou cliquez sur **15%** / **20%**. La boîte affiche **Sell (median)** et **Sell (average)** : le coût médian ou moyen plus cette marge. Ce sont des suggestions, pas des prix; rien n'est enregistré ici.

## Doublons

La même cotation peut apparaître sur plusieurs chargements. Les lignes identiques (même transporteur, voie, mode, équipement et total) sont comptées une fois; l'en-tête indique combien de doublons ont été retirés.
```

`docs/help/fr/lb-results.md`

```markdown
---
title: Résultats, détail du transporteur et export
order: 50
hint: Chaque ligne est une cotation. Dépliez-la pour le détail du chargement et du contact; les soumissions portent une étiquette et une expiration. Export CSV télécharge ce qui est affiché.
---

## Les lignes

Chaque ligne est une cotation de transporteur : origine, destination, transporteur, équipement, mode, devise, total, date, statut et drapeaux. Cliquez sur la flèche à gauche pour déplier le détail du chargement et du contact, et sur le nom du transporteur pour ouvrir sa fiche.

## Soumissions

Une ligne avec l'étiquette **Bid** est un tarif enregistré dans l'outil RFP, pas un chargement. Ses drapeaux indiquent **Expires** et la date. Sous Source = All, seules les soumissions encore valides aujourd'hui sont incluses.

## Export CSV

**Export CSV** télécharge les lignes à l'écran, avec une colonne Source (Load ou Bid), nommé d'après la voie et la date. Il s'ouvre dans Excel ou Numbers.
```

`docs/help/fr/rfp-projects.md`

```markdown
---
title: Projets RFP
order: 60
hint: Un projet est une demande client : nom, client, échéance, devise et marge par défaut. Ouvrez-le pour téléverser les voies et les tarifer.
---

## Créer un projet

Dans l'onglet RFP Tool, remplissez **Name** (obligatoire), **Customer** (tapez deux lettres et choisissez le compte), **Due date**, **Currency** (la devise dans laquelle vous coterez) et **Default margin %** (appliquée à chaque voie jusqu'à ce que vous la changiez). Cliquez sur **Create**; le projet s'ouvre à l'étape de téléversement.

## La liste des projets

Chaque ligne montre le client, le statut, l'échéance, le nombre de voies, combien ont un coût, combien ont un prix de vente, et le fichier téléversé. Cliquez sur le nom du projet pour l'ouvrir. **All projects** ramène à la liste.
```

`docs/help/fr/rfp-upload.md`

```markdown
---
title: Téléverser un fichier de voies et faire la correspondance
order: 70
hint: Téléversez le .xlsx ou .csv du client, associez ses colonnes à nos champs (la correspondance est mémorisée par client), puis importez.
---

## Le fichier

Formats acceptés : `.xlsx`, `.xlsm`, `.xls`, `.csv`, jusqu'à 3 Mo et 2 000 voies par projet. La première ligne doit contenir les en-têtes. Un second téléversement dans le même projet ajoute les lignes à la suite.

## Correspondance des colonnes

L'outil devine quelle colonne est la ville d'origine, le code postal de destination, le mode, l'équipement, la quantité, etc., et montre un échantillon de chacune. Corrigez avec les listes déroulantes. L'origine et la destination ont besoin d'au moins une ville ou un code postal chacune. La correspondance est mémorisée pour le prochain fichier de ce client.

## Import

**Import lanes** crée une voie par ligne et associe chaque extrémité à un lieu connu. La ligne de résumé dit « imported N, skipped N, unresolved ends N ». Les lignes ignorées n'avaient pas d'origine ou de destination utilisable; les extrémités non résolues sont des voies dont la ville n'a pas pu être appariée - voir **Extrémités non résolues**.
```

`docs/help/fr/rfp-unresolved.md`

```markdown
---
title: Extrémités non résolues
order: 80
hint: Une voie « Unresolved » a une extrémité que l'outil n'a pas pu associer à un lieu connu. Corrigez le lieu dans la ligne, puis rechargez son historique.
---

## Ce que ça veut dire

Une voie affiche **Unresolved** quand sa ville d'origine ou de destination (ou son préfixe postal) n'est pas dans le dictionnaire des lieux, souvent à cause d'une faute de frappe, d'une graphie inhabituelle ou d'un très petit village. La voie est importée mais ne peut pas être recherchée.

## Corriger

Dans la ligne de la voie, l'extrémité non résolue montre un champ **Origin** ou **Destination** avec un sélecteur **Precision**. Tapez le lieu, choisissez-le dans la liste (ou cherchez sur la carte) et enregistrez. Cliquez ensuite sur **Retry failed** dans la barre d'outils pour charger l'historique des voies corrigées.

## Prévention

Demandez à votre administrateur d'ajouter un alias pour la graphie utilisée par le client, pour que le prochain fichier se résolve tout seul.
```

`docs/help/fr/rfp-history.md`

```markdown
---
title: Charger l'historique
order: 90
hint: Load history lance une recherche Lane Benchmark par voie. Choisissez précision, période, rayon et si les soumissions des autres RFP comptent, puis lisez « N loads + M bids · median ».
---

## Lancer

Réglez **History precision** (City, Province ou Radius), **Lookback (days)**, **Radius** et son **Unit**, et **Include RFP bids**, puis cliquez sur **Load history**. Les voies sont traitées par lots avec une barre de progression; **Stop** arrête après le lot en cours. **Refresh history** relance toutes les voies; **Retry failed** ne relance que celles marquées Failed ou Unresolved.

## Repli sur le rayon

Avec la précision City, une voie dont la ville n'a pas d'historique est recherchée à nouveau dans le rayon. L'infobulle de la cellule History indique la précision utilisée, par exemple `RADIUS-50KM`.

## Include RFP bids

Activé (par défaut), les soumissions enregistrées sur **d'autres** projets RFP comptent avec les chargements, même après leur date de validité, tant qu'elles sont dans la période. Les soumissions du projet que vous tarifez ne sont jamais comptées - ce sont vos propres données. La cellule History se lit alors « 5 loads + 1 bid · median 5,500.00 ». Désactivé, seuls les chargements comptent.

## Lire la cellule

- `12 · median 5,800.00` : douze cotations correspondent, la médiane des tarifées est 5 800.
- `3 · no median` : trois correspondent mais aucune n'avait de prix.
- **No match**, **Failed**, **Unresolved**, **Pending** : pas d'historique; survolez pour la raison.

Les statistiques n'utilisent que les cotations dans la devise de la voie.
```

`docs/help/fr/rfp-pricing.md`

```markdown
---
title: Tarifer une voie
order: 100
hint: Choisissez une source de coût (une soumission, la médiane de l'historique ou un montant saisi), fixez une marge ou un prix de vente, puis Save price.
---

## Le panneau

Cliquez sur une voie pour ouvrir son panneau à droite. Il reste visible pendant que vous faites défiler le tableau.

## Source du coût

- **Bid** : choisissez un des tarifs de transporteur enregistrés pour cette voie. Le coût est le tarif de la soumission.
- **History median** : la médiane du dernier chargement d'historique.
- **Manual** : saisissez le coût vous-même.

## Marge ou prix de vente

Saisissez un **Margin %** et le prix de vente suit (« Sell follows the margin »), ou saisissez un **Sell** et la marge suit (« Margin follows the sell »). Un prix de vente saisi est conservé quand le coût change plus tard; le tableau lui met l'étiquette **manual**. Videz le prix de vente pour revenir au mode marge.

## Enregistrer

**Save price** écrit le coût, la marge et le prix de vente sur la voie et la marque **Priced**. **Add carrier rate** enregistre une nouvelle soumission pour cette voie et la sélectionne comme coût.

## Résultats

Sous le formulaire, les lignes d'historique de la voie sont listées exactement comme Lane Benchmark les montre, pour voir quelles cotations ont fait la médiane.
```

`docs/help/fr/rfp-inline.md`

```markdown
---
title: Modifier dans le tableau
order: 110
hint: Cliquez sur une cellule Cost, Margin ou Sell et tapez. Entrée enregistre et descend, Tab descend, Maj+Tab remonte, Échap annule.
---

## Cellules modifiables

**Cost**, **Margin** et **Sell** se modifient dans le tableau, comme un chiffrier. Cliquez sur une cellule (la ligne est sélectionnée en même temps), tapez une valeur et appuyez sur :

- **Entrée** ou **Tab** : enregistrer et ouvrir la même cellule sur la ligne suivante.
- **Maj+Tab** : enregistrer et ouvrir la même cellule sur la ligne précédente.
- **Échap** : fermer sans enregistrer.

Cliquer ailleurs enregistre aussi. Un coût saisi ici met la source du coût à Manual; un prix de vente saisi ici est un prix manuel (étiquette **manual**) et la marge le suit.

## Erreurs

Une valeur qui ne peut pas être enregistrée (zéro, négatif, marge au-dessus de 100) affiche un message rouge sous la cellule, qui reste ouverte jusqu'à ce que vous corrigiez ou appuyiez sur Échap.

## Voies identiques

Quand vous tarifez une voie qui a des jumelles dans le même projet (mêmes extrémités, mode et équipement), une barre propose de copier le coût et le prix de vente. **Apply** copie; **Not now** refuse.
```

`docs/help/fr/rfp-bids.md`

```markdown
---
title: Enregistrer les soumissions des transporteurs
order: 120
hint: Add carrier rate enregistre la cotation d'un transporteur pour une voie sans créer de chargement : transporteur existant ou texte libre, tarif, devise, dates de validité.
---

## Quand enregistrer une soumission

Un transporteur a répondu à votre appel d'offres avec un tarif. Enregistrez-le pour qu'il compte comme historique pour cette voie, pour les autres RFP et dans Lane Benchmark.

## Le formulaire

- **Carrier** : tapez deux lettres et choisissez le compte, ou activez **Carrier not in the system** et tapez le nom et un contact (nom, courriel, téléphone).
- **Rate** et **Currency**; **Fuel surcharge** et **FSC included** au besoin; **Transit days**.
- **Valid from** et **Expires on** : par défaut aujourd'hui et aujourd'hui + 30 jours.
- **Notes** : ce que le transporteur a dit d'important.

**Save bid** l'enregistre et, depuis le panneau de la voie, la sélectionne comme source du coût.

## Où les soumissions apparaissent

Dans le panneau de la voie (Active ou Expired), dans Lane Benchmark avec l'étiquette **Bid**, et dans l'historique des autres projets sous « Include RFP bids ». Une soumission appartient au projet où elle a été enregistrée et ne compte jamais dans l'historique de ce même projet.
```

`docs/help/fr/rfp-bulk.md`

```markdown
---
title: Actions en lot
order: 130
hint: Choisissez Selected ou All lanes, puis Use median, Apply margin, cost ou sell, Add carrier rate, ou Delete. Les traitements vont par 200 voies avec un bouton Stop.
---

## Portée

**Selected (N)** agit sur les voies cochées; **All lanes (N)** sur toutes les voies du projet.

## Actions

- **Use median** : donne à chaque voie le coût de sa médiane d'historique. Les voies déjà costées par une soumission ou à la main sont laissées telles quelles; la barre dit combien et propose **Overwrite them**. Les voies sans médiane sont comptées à part.
- **Apply margin**, **Apply cost**, **Apply sell** : fixent cette valeur sur chaque voie de la portée et recalculent le reste.
- **Add carrier rate** : enregistre la même soumission sur chaque voie de la portée et la sélectionne comme coût (les voies dans une autre devise sont ignorées).
- **Delete selected** : supprime les voies et leurs soumissions. Un second clic confirme.

## Progression et Stop

Les longs traitements montrent une barre de progression. **Stop** arrête après le lot en cours; la ligne de résumé dit combien de voies ont été mises à jour, ignorées ou en échec.
```

`docs/help/fr/rfp-filters-export.md`

```markdown
---
title: Filtres, sélection et export
order: 140
hint: Show resserre le tableau (Unpriced, No history match, Manual…), la boîte de recherche filtre par texte, la case d'en-tête sélectionne les lignes affichées, Export to Excel construit le classeur.
---

## Show et recherche

**Show** ne garde qu'un type de voie : All, Unpriced, No history match, Unresolved ends, Manual cost or sell, ou Selected. La boîte de recherche cherche dans l'origine, la destination et l'équipement. Le compteur se lit « N of M lanes ».

## Sélectionner

Cochez les lignes une à une, ou cochez la case d'en-tête pour sélectionner toutes les lignes affichées (un filtre plus tout-sélectionner est le moyen le plus rapide de tarifer un sous-ensemble en lot).

## Export to Excel

**Export to Excel** télécharge un classeur à trois feuilles : **Lanes** (chaque voie avec son historique, coût, marge, prix de vente, vente annuelle et source du prix), **Bids**, et **Summary** (compteurs, vente annuelle totale par devise, marge moyenne, par mode). Ouvrez-le dans Excel ou Numbers.
```

`docs/help/fr/faq.md`

```markdown
---
title: Questions et problèmes
order: 150
hint: No match, Failed, historique ancien, mauvaise devise, onglet absent : les causes habituelles et quoi faire.
---

## « No match » sur une voie

Les extrémités sont résolues mais aucune cotation ni soumission ne correspond dans la période et la précision. Élargissez le rayon, allongez la période, ou vérifiez les filtres de mode et d'équipement.

## « Failed » sur une voie

La recherche elle-même a échoué (souvent un délai dépassé sur un très grand rayon). Cliquez sur **Retry failed**; si ça persiste, réduisez le rayon ou la période.

## L'historique semble ancien

L'historique est un instantané pris quand vous avez cliqué sur Load ou Refresh. L'infobulle indique quand. Cliquez sur **Refresh history** pour en prendre un nouveau.

## La médiane est dans la mauvaise devise

Les statistiques n'utilisent que les cotations dans la devise de la voie (celle du projet). Une voie avec des cotations en USD seulement n'a pas de médiane en CAD; enregistrez une soumission ou saisissez le coût.

## Je ne vois pas l'onglet, ou un bouton dit que je manque d'autorisation

Demandez à votre administrateur les ensembles d'autorisations `Lane_Benchmark_User` et `RFP_Tool_User`.

## Quelque chose cloche

Envoyez à votre administrateur le nom du projet, le numéro de la voie et ce que vous attendiez. Les changements à ces outils passent par une demande de tirage (pull request), donc le correctif sera suivi.
```

- [ ] **Step 2: Check slugs and hint lengths match**

Run:

```bash
diff <(ls docs/help/en) <(ls docs/help/fr) && echo SLUGS_MATCH
for f in docs/help/fr/*.md; do awk -v f="$f" '/^hint:/{sub(/^hint: /,""); if (length($0) > 240) print "TOO LONG", f, length($0)}' "$f"; done
```

Expected: `SLUGS_MATCH`, no "TOO LONG" line. (`length()` in awk counts bytes on some systems; accented text may read up to ~10 % longer than its character count. If a hint reads over 240 only because of accents, run `node -e 'console.log([..."<hint>"].length)'` to confirm the character count is under 240.)

- [ ] **Step 3: Commit**

```bash
git add docs/help/fr
git commit -m "Write the French help guide"
```

---

### Task 3: Build script, static resource and `help:check`

**Files:**

- Create: `scripts/help/build.mjs`
- Create: `force-app/main/default/staticresources/helpCenter.resource-meta.xml`
- Create (generated): `force-app/main/default/staticresources/helpCenter/index.json`, `en/*.html`, `fr/*.html`
- Modify: `package.json` (scripts, devDependency `marked`), `manifest/package.xml` (StaticResource member)

**Interfaces:**

- Produces: `index.json` shaped `{ "sections": [ { "slug": string, "order": number, "title": { "en": string, "fr": string }, "hint": { "en": string, "fr": string } } ] }` sorted by `order`; `<lang>/<slug>.html` containing only the allowed tags. Tasks 4–6 read these. `npm run help:build` and `npm run help:check`.

- [ ] **Step 1: Add the dependency and scripts**

Run: `npm install --save-dev --save-exact marked@15.0.12`

Then in `package.json` `scripts`, add after `"test:unit:coverage"`:

```json
    "help:build": "node scripts/help/build.mjs",
    "help:check": "node scripts/help/build.mjs --check",
```

- [ ] **Step 2: Write the build script**

`scripts/help/build.mjs`:

```js
// Builds docs/help/{en,fr}/*.md into the helpCenter static resource.
// `node scripts/help/build.mjs` writes the resource; `--check` rebuilds into
// a temp folder and exits 1 if the committed resource differs or the
// content breaks a rule (slug missing in one language, hint over 240 chars,
// duplicate order, disallowed tag).
import { marked } from "marked";
import { promises as fs } from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  "..",
  ".."
);
const SRC = path.join(ROOT, "docs", "help");
const OUT = path.join(
  ROOT,
  "force-app",
  "main",
  "default",
  "staticresources",
  "helpCenter"
);
const LANGS = ["en", "fr"];
const HINT_MAX = 240;
const ALLOWED = new Set([
  "h2",
  "h3",
  "p",
  "strong",
  "em",
  "code",
  "a",
  "ul",
  "ol",
  "li",
  "table",
  "thead",
  "tbody",
  "tr",
  "th",
  "td",
  "br"
]);

marked.use({ gfm: true });

function frontMatter(text, file) {
  const m = /^---\n([\s\S]*?)\n---\n([\s\S]*)$/.exec(text);
  if (!m) throw new Error(`${file}: missing front matter`);
  const meta = {};
  for (const line of m[1].split("\n")) {
    const i = line.indexOf(":");
    if (i < 0) throw new Error(`${file}: bad front matter line "${line}"`);
    meta[line.slice(0, i).trim()] = line.slice(i + 1).trim();
  }
  for (const key of ["title", "order", "hint"]) {
    if (!meta[key]) throw new Error(`${file}: front matter needs ${key}`);
  }
  const order = Number(meta.order);
  if (!Number.isInteger(order))
    throw new Error(`${file}: order must be an integer`);
  if ([...meta.hint].length > HINT_MAX) {
    throw new Error(
      `${file}: hint is ${[...meta.hint].length} chars, max ${HINT_MAX}`
    );
  }
  return { title: meta.title, order, hint: meta.hint, body: m[2] };
}

// Keeps only the allowed tags; on <a>, keeps only a safe href. Content is
// repo-authored, so this is a guard against mistakes, not an attacker.
function sanitize(html, file) {
  return html.replace(/<\/?([a-zA-Z0-9]+)([^>]*)>/g, (tag, name, attrs) => {
    const lower = name.toLowerCase();
    if (!ALLOWED.has(lower))
      throw new Error(`${file}: tag <${lower}> is not allowed`);
    if (tag.startsWith("</")) return `</${lower}>`;
    if (lower !== "a") return `<${lower}>`;
    const href = /href="([^"]*)"/.exec(attrs);
    const value = href ? href[1] : "";
    if (!/^(#|\/|https:\/\/)/.test(value))
      throw new Error(
        `${file}: link "${value}" must start with #, / or https://`
      );
    return `<a href="${value}">`;
  });
}

async function readLang(lang) {
  const dir = path.join(SRC, lang);
  const files = (await fs.readdir(dir)).filter((f) => f.endsWith(".md")).sort();
  const out = new Map();
  for (const f of files) {
    const text = await fs.readFile(path.join(dir, f), "utf8");
    const parsed = frontMatter(text, `${lang}/${f}`);
    out.set(f.replace(/\.md$/, ""), {
      ...parsed,
      html: sanitize(marked.parse(parsed.body), `${lang}/${f}`)
    });
  }
  return out;
}

async function build(outDir) {
  const byLang = {};
  await Promise.all(
    LANGS.map(async (lang) => {
      byLang[lang] = await readLang(lang);
    })
  );
  const slugs = [...byLang.en.keys()];
  for (const lang of LANGS) {
    const missing = slugs.filter((s) => !byLang[lang].has(s));
    const extra = [...byLang[lang].keys()].filter((s) => !byLang.en.has(s));
    if (missing.length || extra.length) {
      throw new Error(
        `${lang}: missing ${missing.join(",") || "-"}; extra ${extra.join(",") || "-"}`
      );
    }
  }
  const sections = slugs
    .map((slug) => ({
      slug,
      order: byLang.en.get(slug).order,
      title: Object.fromEntries(
        LANGS.map((l) => [l, byLang[l].get(slug).title])
      ),
      hint: Object.fromEntries(LANGS.map((l) => [l, byLang[l].get(slug).hint]))
    }))
    .sort((a, b) => a.order - b.order);
  const orders = new Set();
  for (const s of sections) {
    if (orders.has(s.order)) throw new Error(`order ${s.order} is used twice`);
    orders.add(s.order);
    if (byLang.fr.get(s.slug).order !== s.order)
      throw new Error(`${s.slug}: order differs between languages`);
  }
  await fs.rm(outDir, { recursive: true, force: true });
  await fs.mkdir(outDir, { recursive: true });
  await fs.writeFile(
    path.join(outDir, "index.json"),
    JSON.stringify({ sections }, null, 2) + "\n"
  );
  await Promise.all(
    LANGS.map(async (lang) => {
      await fs.mkdir(path.join(outDir, lang), { recursive: true });
      await Promise.all(
        slugs.map((slug) =>
          fs.writeFile(
            path.join(outDir, lang, `${slug}.html`),
            byLang[lang].get(slug).html
          )
        )
      );
    })
  );
  return sections.length;
}

async function tree(dir) {
  const out = new Map();
  async function walk(d, rel) {
    for (const e of await fs.readdir(d, { withFileTypes: true })) {
      const p = path.join(d, e.name);
      const r = rel ? `${rel}/${e.name}` : e.name;
      if (e.isDirectory()) await walk(p, r);
      else out.set(r, await fs.readFile(p, "utf8"));
    }
  }
  await walk(dir, "");
  return out;
}

async function check() {
  const tmp = await fs.mkdtemp(path.join(os.tmpdir(), "helpCenter-"));
  await build(tmp);
  const [want, have] = await Promise.all([tree(tmp), tree(OUT)]);
  const problems = [];
  for (const [file, content] of want) {
    if (!have.has(file)) problems.push(`missing: ${file}`);
    else if (have.get(file) !== content) problems.push(`stale: ${file}`);
  }
  for (const file of have.keys())
    if (!want.has(file)) problems.push(`extra: ${file}`);
  await fs.rm(tmp, { recursive: true, force: true });
  if (problems.length) {
    console.error(
      `helpCenter is out of date - run npm run help:build\n${problems.join("\n")}`
    );
    process.exit(1);
  }
  console.log("helpCenter is up to date");
}

if (process.argv.includes("--check")) {
  await check();
} else {
  const n = await build(OUT);
  console.log(`built ${n} sections into ${path.relative(ROOT, OUT)}`);
}
```

- [ ] **Step 3: Write the resource meta file**

`force-app/main/default/staticresources/helpCenter.resource-meta.xml`:

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<StaticResource xmlns="http://soap.sforce.com/2006/04/metadata">
    <cacheControl>Public</cacheControl>
    <contentType>application/zip</contentType>
    <description
  >Help center content built from docs/help by npm run help:build (phase 5)</description>
</StaticResource>
```

- [ ] **Step 4: Build and check**

Run: `npm run help:build && npm run help:check && ls force-app/main/default/staticresources/helpCenter force-app/main/default/staticresources/helpCenter/en | head -20 && grep -c '"slug"' force-app/main/default/staticresources/helpCenter/index.json`

Expected: `built 15 sections into force-app/main/default/staticresources/helpCenter`, `helpCenter is up to date`, the listings, and `15`. If the build throws on a tag (for example `<hr>` from a `---` inside a body, or `<h1>`), fix the Markdown source in Tasks 1–2's files, not the allowlist.

- [ ] **Step 5: Prove the check catches drift**

Run: `echo x >> force-app/main/default/staticresources/helpCenter/en/faq.html; npm run help:check; echo "exit $?"; npm run help:build >/dev/null`

Expected: the check prints `stale: en/faq.html` and `exit 1`; the rebuild restores the file (`git status` shows no change under `staticresources` afterwards).

- [ ] **Step 6: Register the resource in the manifest**

In `manifest/package.xml`, inside the `<types>` block whose `<name>` is `StaticResource`, add `<members>helpCenter</members>` before `<members>sheetJs</members>`.

- [ ] **Step 7: Deploy the resource alone (sanity)**

Run: `sf project deploy start -o sandbox --source-dir force-app/main/default/staticresources/helpCenter -l NoTestRun -w 10 --json | python3 -c "import json,sys; r=json.load(sys.stdin)['result']; print(r['id'], r['status'])"`

Expected: `<id> Succeeded`. Record the id for the Outcome.

- [ ] **Step 8: Commit**

```bash
git add package.json package-lock.json scripts/help/build.mjs force-app/main/default/staticresources/helpCenter force-app/main/default/staticresources/helpCenter.resource-meta.xml manifest/package.xml
git commit -m "Build the help guide into the helpCenter static resource"
```

---

### Task 4: `c/helpContent` module

**Files:**

- Create: `force-app/main/default/lwc/helpContent/helpContent.js`, `helpContent.js-meta.xml`, `__tests__/helpContent.test.js`
- Modify: `manifest/package.xml` (LightningComponentBundle member `helpContent`)

**Interfaces:**

- Consumes: the static resource from Task 3 via `@salesforce/resourceUrl/helpCenter`.
- Produces (all named exports):
  - `loadIndex()` → `Promise<{ sections: Section[] }>` cached after the first call.
  - `loadSection(slug, lang)` → `Promise<string>` HTML, cached per `lang/slug`.
  - `findSection(index, slug)` → `Section | null`.
  - `defaultLang(locale)` → `"fr" | "en"`.
  - `readLang()` → `"fr" | "en" | null`; `writeLang(lang)`.
  - `sectionUrl(slug, lang)` → page reference `{ type: "standard__navItemPage", attributes: { apiName: "Help_Center" }, state: { c__section: slug, c__lang: lang } }`.
  - `resetCache()` for tests.

- [ ] **Step 1: Write the failing tests**

`force-app/main/default/lwc/helpContent/__tests__/helpContent.test.js`:

```js
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

jest.mock("@salesforce/resourceUrl/helpCenter", () => "/resource/helpCenter", {
  virtual: true
});

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
    } catch (e) {
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
```

- [ ] **Step 2: Run to verify it fails**

Run: `npx sfdx-lwc-jest -- force-app/main/default/lwc/helpContent`
Expected: FAIL, cannot find module `c/helpContent`.

- [ ] **Step 3: Write the module**

`force-app/main/default/lwc/helpContent/helpContent.js`:

```js
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
  } catch (e) {
    return null;
  }
}

export function writeLang(lang) {
  if (!LANGS.includes(lang)) {
    return;
  }
  try {
    window.localStorage.setItem(KEY, lang);
  } catch (e) {
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
```

`force-app/main/default/lwc/helpContent/helpContent.js-meta.xml`:

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<LightningComponentBundle xmlns="http://soap.sforce.com/2006/04/metadata">
  <apiVersion>64.0</apiVersion>
  <isExposed>false</isExposed>
</LightningComponentBundle>
```

- [ ] **Step 4: Run to verify it passes**

Run: `npx sfdx-lwc-jest -- force-app/main/default/lwc/helpContent && npx eslint force-app/main/default/lwc/helpContent`
Expected: 6 tests pass, ESLint clean. (If `Storage.prototype` is not spy-able in this jsdom, replace that part of the test with `Object.defineProperty(window, "localStorage", { value: { getItem() { throw new Error("blocked"); } }, configurable: true })` and restore the original afterwards.)

- [ ] **Step 5: Register and commit**

Add `<members>helpContent</members>` to the `LightningComponentBundle` block of `manifest/package.xml` (keep the block's existing ordering style: insert next to the other `help*`/`lane*` names alphabetically).

```bash
git add force-app/main/default/lwc/helpContent manifest/package.xml
git commit -m "Add the helpContent module for the help center"
```

---

### Task 5: `c/helpHint` — the "?" popover

**Files:**

- Create: `force-app/main/default/lwc/helpHint/helpHint.html`, `helpHint.js`, `helpHint.css`, `helpHint.js-meta.xml`, `__tests__/helpHint.test.js`
- Modify: `manifest/package.xml`

**Interfaces:**

- Consumes: `loadIndex`, `findSection`, `defaultLang`, `readLang`, `sectionUrl` from `c/helpContent`; `LOCALE` from `@salesforce/i18n/locale`; `NavigationMixin`.
- Produces: `<c-help-hint topic="<slug>" label="Help about pricing">`. `data-id`s: `open`, `popover`, `text`, `more`, `close`.

- [ ] **Step 1: Write the failing tests**

`force-app/main/default/lwc/helpHint/__tests__/helpHint.test.js`:

```js
import { createElement } from "lwc";
import HelpHint from "c/helpHint";
import { resetCache } from "c/helpContent";

const mockNavigateCalls = [];
jest.mock("lightning/navigation", () => {
  const Navigate = Symbol("Navigate");
  const NavigationMixin = (Base) =>
    class extends Base {
      [Navigate](pageReference) {
        mockNavigateCalls.push(pageReference);
      }
    };
  NavigationMixin.Navigate = Navigate;
  return { NavigationMixin, CurrentPageReference: { emit: () => {} } };
});
jest.mock("@salesforce/resourceUrl/helpCenter", () => "/resource/helpCenter", {
  virtual: true
});
jest.mock("@salesforce/i18n/locale", () => ({ default: "en-US" }), {
  virtual: true
});

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

function mount(props = {}) {
  const el = createElement("c-help-hint", { is: HelpHint });
  Object.assign(el, { topic: "rfp-pricing" }, props);
  document.body.appendChild(el);
  return el;
}

describe("c-help-hint", () => {
  beforeEach(() => {
    resetCache();
    mockNavigateCalls.length = 0;
    try {
      window.localStorage.clear();
    } catch (e) {
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

  it("renders only the button until opened, then the hint in the default language", async () => {
    const el = mount();
    await flush();
    expect(field(el, "popover")).toBeNull();
    expect(field(el, "open").alternativeText).toBe("Help");
    field(el, "open").click();
    await flush();
    await flush();
    expect(field(el, "text").textContent).toBe("Pick a cost source.");
    expect(field(el, "more").textContent).toContain("Read more");
  });

  it("uses the stored language and navigates to the section on Read more", async () => {
    window.localStorage.setItem("helpCenter.lang.v1", "fr");
    const el = mount({ label: "Aide" });
    await flush();
    field(el, "open").click();
    await flush();
    await flush();
    expect(field(el, "text").textContent).toBe("Choisissez une source.");
    expect(field(el, "more").textContent).toContain("En savoir plus");
    field(el, "more").click();
    expect(mockNavigateCalls[0]).toEqual({
      type: "standard__navItemPage",
      attributes: { apiName: "Help_Center" },
      state: { c__section: "rfp-pricing", c__lang: "fr" }
    });
    await flush();
    expect(field(el, "popover")).toBeNull();
  });

  it("closes on Escape, on the close button and on an outside click", async () => {
    const el = mount();
    await flush();
    field(el, "open").click();
    await flush();
    await flush();
    expect(field(el, "popover")).not.toBeNull();
    el.shadowRoot.dispatchEvent(
      new KeyboardEvent("keydown", {
        key: "Escape",
        bubbles: true,
        composed: true
      })
    );
    await flush();
    expect(field(el, "popover")).toBeNull();

    field(el, "open").click();
    await flush();
    field(el, "close").click();
    await flush();
    expect(field(el, "popover")).toBeNull();

    field(el, "open").click();
    await flush();
    document.body.click();
    await flush();
    expect(field(el, "popover")).toBeNull();
  });

  it("says when a topic has no help yet, and when the index cannot load", async () => {
    const el = mount({ topic: "unknown" });
    await flush();
    field(el, "open").click();
    await flush();
    await flush();
    expect(field(el, "text").textContent).toBe("No help for this area yet.");
    expect(field(el, "more")).toBeNull();

    resetCache();
    global.fetch = jest.fn(() => Promise.resolve({ ok: false, status: 500 }));
    const broken = mount();
    await flush();
    field(broken, "open").click();
    await flush();
    await flush();
    await flush();
    expect(field(broken, "text").textContent).toBe(
      "No help for this area yet."
    );
  });

  it("removes its document listener when removed from the page", async () => {
    const add = jest.spyOn(document, "addEventListener");
    const remove = jest.spyOn(document, "removeEventListener");
    const el = mount();
    await flush();
    field(el, "open").click();
    await flush();
    expect(add).toHaveBeenCalledWith("click", expect.any(Function), true);
    document.body.removeChild(el);
    expect(remove).toHaveBeenCalledWith("click", expect.any(Function), true);
    add.mockRestore();
    remove.mockRestore();
  });
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `npx sfdx-lwc-jest -- force-app/main/default/lwc/helpHint`
Expected: FAIL, cannot find module `c/helpHint`.

- [ ] **Step 3: Write the component**

`force-app/main/default/lwc/helpHint/helpHint.html`:

```html
<template>
  <span class="hint" onkeydown="{handleKeydown}">
    <lightning-button-icon
      data-id="open"
      icon-name="utility:info"
      size="x-small"
      variant="bare"
      alternative-text="{label}"
      title="{label}"
      onclick="{handleToggle}"
    ></lightning-button-icon>
    <template lwc:if="{open}">
      <section
        data-id="popover"
        class="slds-popover slds-nubbin_top-left popover"
        role="dialog"
        aria-label="{label}"
      >
        <lightning-button-icon
          data-id="close"
          class="slds-float_right"
          icon-name="utility:close"
          size="small"
          variant="bare"
          alternative-text="{closeLabel}"
          onclick="{handleClose}"
        ></lightning-button-icon>
        <div class="slds-popover__body">
          <p data-id="text">{text}</p>
          <template lwc:if="{hasSection}">
            <a data-id="more" href="#" onclick="{handleMore}">{moreLabel}</a>
          </template>
        </div>
      </section>
    </template>
  </span>
</template>
```

`force-app/main/default/lwc/helpHint/helpHint.css`:

```css
.hint {
  position: relative;
  display: inline-block;
  margin-left: 0.25rem;
  vertical-align: middle;
}
.popover {
  position: absolute;
  top: 1.75rem;
  left: -0.5rem;
  width: 20rem;
  z-index: 9000;
}
```

`force-app/main/default/lwc/helpHint/helpHint.js`:

```js
import { LightningElement, api } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import LOCALE from "@salesforce/i18n/locale";
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

  disconnectedCallback() {
    this.detach();
  }

  async handleToggle(event) {
    event.stopPropagation();
    if (this.open) {
      this.close();
      return;
    }
    this.lang = readLang() || defaultLang(LOCALE);
    this.open = true;
    this.attach();
    try {
      const index = await loadIndex();
      this.section = findSection(index, this.topic);
    } catch (e) {
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
```

`force-app/main/default/lwc/helpHint/helpHint.js-meta.xml`:

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<LightningComponentBundle xmlns="http://soap.sforce.com/2006/04/metadata">
  <apiVersion>64.0</apiVersion>
  <isExposed>false</isExposed>
</LightningComponentBundle>
```

- [ ] **Step 4: Run to verify it passes**

Run: `npx sfdx-lwc-jest -- force-app/main/default/lwc/helpHint && npx eslint force-app/main/default/lwc/helpHint`
Expected: 5 tests pass, ESLint clean. The Escape test dispatches on the shadow root; if the handler on the wrapping `span` does not receive it, dispatch the event on `field(el, "popover")` instead (it bubbles up to the span).

- [ ] **Step 5: Register and commit**

Add `<members>helpHint</members>` to the manifest's `LightningComponentBundle` block.

```bash
git add force-app/main/default/lwc/helpHint manifest/package.xml
git commit -m "Add the helpHint popover"
```

---

### Task 6: `c/helpCenter` tab component, FlexiPage, tab, apps, permission sets

**Files:**

- Create: `force-app/main/default/lwc/helpCenter/helpCenter.html`, `helpCenter.js`, `helpCenter.css`, `helpCenter.js-meta.xml`, `__tests__/helpCenter.test.js`
- Create: `force-app/main/default/flexipages/Help_Center.flexipage-meta.xml`, `force-app/main/default/tabs/Help_Center.tab-meta.xml`
- Modify: `applications/Lane_Benchmark.app-meta.xml`, `applications/TransPro.app-meta.xml`, `permissionsets/Lane_Benchmark_User.permissionset-meta.xml`, `permissionsets/RFP_Tool_User.permissionset-meta.xml`, `manifest/package.xml`

**Interfaces:**

- Consumes: `c/helpContent` (all exports), `CurrentPageReference`, `NavigationMixin`, `LOCALE`.
- Produces: the Help tab at `/lightning/n/Help_Center` accepting `c__section` and `c__lang`. `data-id`s: `nav`, `nav-item` (one per section, with `data-slug`), `lang-en`, `lang-fr`, `filter`, `title`, `body`, `error`, `loading`.

- [ ] **Step 1: Write the failing tests**

`force-app/main/default/lwc/helpCenter/__tests__/helpCenter.test.js`:

```js
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
jest.mock("@salesforce/resourceUrl/helpCenter", () => "/resource/helpCenter", {
  virtual: true
});
jest.mock("@salesforce/i18n/locale", () => ({ default: "fr-CA" }), {
  virtual: true
});

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
    }
  ]
};
const pages = {
  "/resource/helpCenter/index.json": JSON.stringify(index),
  "/resource/helpCenter/en/overview.html": "<h2>Overview EN</h2>",
  "/resource/helpCenter/fr/overview.html": "<h2>Aperçu FR</h2>",
  "/resource/helpCenter/en/rfp-pricing.html": "<h2>Pricing EN</h2>",
  "/resource/helpCenter/fr/rfp-pricing.html": "<h2>Tarifer FR</h2>"
};

const flush = () => Promise.resolve().then(() => Promise.resolve());
const settle = async () => {
  for (let i = 0; i < 4; i++) {
    await flush();
  }
};
const field = (el, id) => el.shadowRoot.querySelector(`[data-id="${id}"]`);
const items = (el) => [
  ...el.shadowRoot.querySelectorAll('[data-id="nav-item"]')
];

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
    } catch (e) {
      // ignore
    }
    global.fetch = jest.fn((url) => {
      const body = pages[url];
      if (body === undefined) {
        return Promise.resolve({ ok: false, status: 404 });
      }
      return Promise.resolve({
        ok: true,
        json: () => Promise.resolve(JSON.parse(body)),
        text: () => Promise.resolve(body)
      });
    });
  });
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("opens the overview in the locale's language when the URL says nothing", async () => {
    const el = await mount();
    expect(items(el).map((i) => i.dataset.slug)).toEqual([
      "overview",
      "rfp-pricing",
      "faq"
    ]);
    expect(items(el)[0].textContent).toContain("À quoi servent ces outils");
    expect(field(el, "title").textContent).toBe("À quoi servent ces outils");
    expect(field(el, "body").value).toBe("<h2>Aperçu FR</h2>");
    expect(field(el, "lang-fr").variant).toBe("brand");
  });

  it("lands on the section and language from the URL", async () => {
    const el = await mount({ c__section: "rfp-pricing", c__lang: "en" });
    expect(field(el, "title").textContent).toBe("Pricing a lane");
    expect(field(el, "body").value).toBe("<h2>Pricing EN</h2>");
    expect(field(el, "lang-en").variant).toBe("brand");
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

  it("prefers the remembered language over the locale", async () => {
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

  it("filters the column by title", async () => {
    const el = await mount({ c__lang: "en" });
    field(el, "filter").value = "pric";
    field(el, "filter").dispatchEvent(
      new CustomEvent("change", { detail: { value: "pric" } })
    );
    await settle();
    expect(items(el).map((i) => i.dataset.slug)).toEqual(["rfp-pricing"]);
  });

  it("shows an error when the content does not load", async () => {
    global.fetch = jest.fn(() => Promise.resolve({ ok: false, status: 500 }));
    const el = await mount();
    expect(field(el, "error").textContent).toContain("did not load");
    expect(field(el, "body")).toBeNull();
  });
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `npx sfdx-lwc-jest -- force-app/main/default/lwc/helpCenter`
Expected: FAIL, cannot find module `c/helpCenter`.

- [ ] **Step 3: Write the component**

`force-app/main/default/lwc/helpCenter/helpCenter.html`:

```html
<template>
  <lightning-card title="{cardTitle}" icon-name="utility:help">
    <lightning-button-group slot="actions">
      <lightning-button
        data-id="lang-en"
        label="EN"
        variant="{enVariant}"
        onclick="{handleEn}"
      ></lightning-button>
      <lightning-button
        data-id="lang-fr"
        label="FR"
        variant="{frVariant}"
        onclick="{handleFr}"
      ></lightning-button>
    </lightning-button-group>
    <div class="slds-p-horizontal_medium">
      <template lwc:if="{error}">
        <p data-id="error" class="slds-text-color_error">{error}</p>
      </template>
      <template lwc:else>
        <lightning-layout multiple-rows>
          <lightning-layout-item
            size="12"
            medium-device-size="4"
            padding="around-x-small"
          >
            <lightning-input
              data-id="filter"
              type="search"
              label="{filterLabel}"
              value="{filter}"
              onchange="{handleFilter}"
            ></lightning-input>
            <nav
              data-id="nav"
              class="slds-nav-vertical slds-m-top_small"
              aria-label="{cardTitle}"
            >
              <ul>
                <template for:each="{visibleSections}" for:item="s">
                  <li key="{s.slug}" class="{s.itemClass}">
                    <button
                      type="button"
                      data-id="nav-item"
                      data-slug="{s.slug}"
                      class="slds-nav-vertical__action nav-button"
                      aria-current="{s.current}"
                      onclick="{handlePick}"
                    >
                      {s.label}
                    </button>
                  </li>
                </template>
              </ul>
            </nav>
          </lightning-layout-item>
          <lightning-layout-item
            size="12"
            medium-device-size="8"
            padding="around-x-small"
          >
            <template lwc:if="{loading}">
              <lightning-spinner
                data-id="loading"
                alternative-text="Loading"
                size="small"
              ></lightning-spinner>
            </template>
            <template lwc:if="{section}">
              <h2
                data-id="title"
                class="slds-text-heading_medium slds-m-bottom_small"
              >
                {title}
              </h2>
              <lightning-formatted-rich-text
                data-id="body"
                class="body"
                value="{html}"
              ></lightning-formatted-rich-text>
            </template>
          </lightning-layout-item>
        </lightning-layout>
      </template>
    </div>
  </lightning-card>
</template>
```

`force-app/main/default/lwc/helpCenter/helpCenter.css`:

```css
.nav-button {
  width: 100%;
  text-align: left;
  background: none;
  border: 0;
  cursor: pointer;
}
.body {
  line-height: 1.5;
}
```

`force-app/main/default/lwc/helpCenter/helpCenter.js`:

```js
import { LightningElement, wire } from "lwc";
import { CurrentPageReference, NavigationMixin } from "lightning/navigation";
import LOCALE from "@salesforce/i18n/locale";
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
      : readLang() || defaultLang(LOCALE);
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
    } catch (e) {
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
```

`force-app/main/default/lwc/helpCenter/helpCenter.js-meta.xml`:

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<LightningComponentBundle xmlns="http://soap.sforce.com/2006/04/metadata">
  <apiVersion>64.0</apiVersion>
  <isExposed>true</isExposed>
  <masterLabel>Help Center</masterLabel>
  <targets>
    <target>lightning__AppPage</target>
    <target>lightning__HomePage</target>
  </targets>
</LightningComponentBundle>
```

- [ ] **Step 4: Run to verify it passes**

Run: `npx sfdx-lwc-jest -- force-app/main/default/lwc/helpCenter && npx eslint force-app/main/default/lwc/helpCenter`
Expected: 8 tests pass, ESLint clean. If the `filter` test fails because `lightning-input`'s stub does not carry `detail.value`, the handler already falls back through `event.detail.value || ""`; set `field(el, "filter").value` and dispatch a `change` `CustomEvent` with `{ detail: { value: "pric" } }` as written.

- [ ] **Step 5: FlexiPage, tab, apps, permission sets, manifest**

`force-app/main/default/flexipages/Help_Center.flexipage-meta.xml`:

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<FlexiPage xmlns="http://soap.sforce.com/2006/04/metadata">
    <flexiPageRegions>
        <itemInstances>
            <componentInstance>
                <componentName>helpCenter</componentName>
                <identifier>c_helpCenter</identifier>
            </componentInstance>
        </itemInstances>
        <name>main</name>
        <type>Region</type>
    </flexiPageRegions>
    <masterLabel>Help Center</masterLabel>
    <template><name>flexipage:defaultAppHomeTemplate</name></template>
    <type>AppPage</type>
</FlexiPage>
```

`force-app/main/default/tabs/Help_Center.tab-meta.xml` (ruling R54: the motif is the one the other two tabs already use and deploy with; the admin can pick a help icon in Setup later):

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<CustomTab xmlns="http://soap.sforce.com/2006/04/metadata">
    <description>Help: how to use Lane Benchmark and the RFP Tool</description>
    <flexiPage>Help_Center</flexiPage>
    <label>Help</label>
    <motif>Custom80: Motorcycle</motif>
</CustomTab>
```

In `applications/Lane_Benchmark.app-meta.xml` add `<tabs>Help_Center</tabs>` right after `<tabs>RFP_Tool</tabs>`; the same in `applications/TransPro.app-meta.xml` (line ~774).

In both permission sets, add after the existing `RFP_Tool` (or `Lane_Benchmark`) `tabSettings` block:

```xml
<tabSettings>
        <tab>Help_Center</tab>
        <visibility>Visible</visibility>
    </tabSettings>
```

In `manifest/package.xml`: `<members>Help_Center</members>` in the `FlexiPage` block and in the `CustomTab` block (alphabetical: before `Lane_Benchmark`), and `<members>helpCenter</members>` in the `LightningComponentBundle` block.

- [ ] **Step 6: Deploy and open it**

Run: `sf project deploy start -o sandbox --manifest manifest/package.xml -l NoTestRun -w 30 --json | python3 -c "import json,sys; r=json.load(sys.stdin)['result']; print(r['id'], r['status'], r.get('numberComponentsDeployed'), 'errors', r.get('numberComponentErrors'))"`

Expected: `Succeeded`, 0 errors. Then `sf org open -o sandbox -p /lightning/n/Help_Center --url-only` prints the URL (do not open a browser from the task; the controller checks it). Record the deploy id.

- [ ] **Step 7: Commit**

```bash
git add force-app/main/default/lwc/helpCenter force-app/main/default/flexipages/Help_Center.flexipage-meta.xml force-app/main/default/tabs/Help_Center.tab-meta.xml force-app/main/default/applications force-app/main/default/permissionsets manifest/package.xml
git commit -m "Add the Help tab with the bilingual guide"
```

---

### Task 7: Place the hints in the twelve areas

**Files:**

- Modify (markup only): `lwc/laneBenchmark/laneBenchmark.html`, `lwc/laneBenchmarkFilters/laneBenchmarkFilters.html`, `lwc/laneBenchmarkStats/laneBenchmarkStats.html`, `lwc/laneBenchmarkResults/laneBenchmarkResults.html`, `lwc/rfpProjectList/rfpProjectList.html`, `lwc/rfpUpload/rfpUpload.html`, `lwc/rfpColumnMapper/rfpColumnMapper.html`, `lwc/rfpToolbar/rfpToolbar.html`, `lwc/rfpBulkBar/rfpBulkBar.html`, `lwc/rfpLaneTable/rfpLaneTable.html`, `lwc/rfpLanePanel/rfpLanePanel.html`, `lwc/rfpBidForm/rfpBidForm.html`
- Create: `force-app/main/default/lwc/helpContent/__tests__/placement.test.js`

**Interfaces:**

- Consumes: `c/helpHint` (Task 5), `index.json` (Task 3).
- Ruling R55 (deviation from spec §5.3's table): the `lb-lane` hint goes in the `laneBenchmark` container's "Lane" card `actions` slot, not inside `laneBenchmarkPlacePicker` (that component is rendered twice, once per end, and would show two identical hints). Everything else as the spec lists.

- [ ] **Step 1: Write the failing placement test**

`force-app/main/default/lwc/helpContent/__tests__/placement.test.js`:

```js
// Every "?" in the app points at a section that exists, and every area the
// spec lists has its "?". Reads the templates and the built index from disk.
const fs = require("fs");
const path = require("path");

const LWC = path.resolve(__dirname, "..", "..");
const INDEX = path.resolve(
  LWC,
  "..",
  "staticresources",
  "helpCenter",
  "index.json"
);
const EXPECTED = {
  laneBenchmark: "lb-lane",
  laneBenchmarkFilters: "lb-filters",
  laneBenchmarkStats: "lb-stats",
  laneBenchmarkResults: "lb-results",
  rfpProjectList: "rfp-projects",
  rfpUpload: "rfp-upload",
  rfpColumnMapper: "rfp-upload",
  rfpToolbar: "rfp-history",
  rfpBulkBar: "rfp-bulk",
  rfpLaneTable: "rfp-inline",
  rfpLanePanel: "rfp-pricing",
  rfpBidForm: "rfp-bids"
};

function topicsIn(bundle) {
  const html = fs.readFileSync(
    path.join(LWC, bundle, `${bundle}.html`),
    "utf8"
  );
  return [...html.matchAll(/<c-help-hint[^>]*\btopic="([^"]+)"/g)].map(
    (m) => m[1]
  );
}

describe("help hint placement", () => {
  const slugs = new Set(
    JSON.parse(fs.readFileSync(INDEX, "utf8")).sections.map((s) => s.slug)
  );

  it("puts the expected topic in each host template", () => {
    Object.entries(EXPECTED).forEach(([bundle, topic]) => {
      expect({ bundle, topics: topicsIn(bundle) }).toEqual({
        bundle,
        topics: [topic]
      });
    });
  });

  it("only uses topics that exist in the built index", () => {
    const dirs = fs
      .readdirSync(LWC, { withFileTypes: true })
      .filter((d) => d.isDirectory())
      .map((d) => d.name)
      .filter((name) => fs.existsSync(path.join(LWC, name, `${name}.html`)));
    dirs.forEach((bundle) => {
      topicsIn(bundle).forEach((topic) => {
        expect({ bundle, topic, known: slugs.has(topic) }).toEqual({
          bundle,
          topic,
          known: true
        });
      });
    });
  });
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `npx sfdx-lwc-jest -- force-app/main/default/lwc/helpContent/__tests__/placement.test.js`
Expected: FAIL — every bundle has `topics: []`.

- [ ] **Step 3: Add the twelve hints (markup only)**

Each insertion is one element. Use the `label` shown so screen readers name the area.

1. `laneBenchmark.html` line 8: change `<lightning-card title="Lane" icon-name="standard:location">` to

```html
<lightning-card title="Lane" icon-name="standard:location">
  <c-help-hint
    slot="actions"
    topic="lb-lane"
    label="Help: choosing a lane"
  ></c-help-hint
></lightning-card>
```

2. `laneBenchmarkFilters.html`: as the first child of the template's root element, before the Lookback field:

```html
<div class="slds-m-bottom_xx-small">
  <span class="slds-form-element__label">Filters</span>
  <c-help-hint
    topic="lb-filters"
    label="Help: filters and lookback"
  ></c-help-hint>
</div>
```

3. `laneBenchmarkStats.html` line 2, inside the card after the opening tag:

```html
<c-help-hint
  slot="actions"
  topic="lb-stats"
  label="Help: reading the statistics"
></c-help-hint>
```

4. `laneBenchmarkResults.html` line 2, inside the card after the opening tag (before the existing `lwc:if={hasRows}` export button):

```html
<c-help-hint
  slot="actions"
  topic="lb-results"
  label="Help: results and export"
></c-help-hint>
```

(Two elements in the `actions` slot render side by side.)

5. `rfpProjectList.html` line 4–6: inside the `<h2>` after the text `RFP projects`:

```html
<h2 class="slds-text-heading_small slds-m-bottom_x-small">
  RFP projects
  <c-help-hint topic="rfp-projects" label="Help: RFP projects"></c-help-hint>
</h2>
```

6. `rfpUpload.html` line 3–5: inside the `<label>` after its text:

```html
<label class="slds-form-element__label" for="file"
  >Lane file (.xlsx, .xlsm, .xls, .csv — up to 3 MB, 2,000 lanes)
  <c-help-hint
    topic="rfp-upload"
    label="Help: uploading a lane file"
  ></c-help-hint
></label>
```

7. `rfpColumnMapper.html`: as the first child inside the root `<div class="slds-grid slds-wrap slds-gutters_small">`:

```html
<div class="slds-col slds-size_1-of-1 slds-p-bottom_x-small">
  <span class="slds-form-element__label">Column mapping</span>
  <c-help-hint
    topic="rfp-upload"
    label="Help: mapping the columns"
  ></c-help-hint>
</div>
```

8. `rfpToolbar.html`: a new `slds-col` right after the `radius-unit` column and before the `include-bids` column:

```html
<div class="slds-col">
  <c-help-hint topic="rfp-history" label="Help: loading history"></c-help-hint>
</div>
```

9. `rfpBulkBar.html`: a new `slds-col` as the first child of the inner `slds-grid` (before the scope button group):

```html
<div class="slds-col">
  <c-help-hint topic="rfp-bulk" label="Help: bulk actions"></c-help-hint>
</div>
```

10. `rfpLaneTable.html` line 15: change `<th scope="col" class="w-3">#</th>` to

```html
<th scope="col" class="w-3">
  #
  <c-help-hint
    topic="rfp-inline"
    label="Help: editing in the table"
  ></c-help-hint>
</th>
```

(The `#` column is 3 rem wide; if the icon wraps under the `#`, change the class to `w-5` on this `th` only.)

11. `rfpLanePanel.html` line 4: inside the `<h2>` after `{laneTitle}`:

```html
<h2 class="slds-text-heading_small slds-m-bottom_x-small">
  {laneTitle}
  <c-help-hint topic="rfp-pricing" label="Help: pricing a lane"></c-help-hint>
</h2>
```

12. `rfpBidForm.html`: as the first child of the root `<div class="slds-box ... bid-form">`, before the grid:

```html
<div class="slds-m-bottom_xx-small">
  <span class="slds-form-element__label">Carrier rate</span>
  <c-help-hint
    topic="rfp-bids"
    label="Help: recording carrier bids"
  ></c-help-hint>
</div>
```

- [ ] **Step 4: Run all Jest and ESLint**

Run: `npm test 2>&1 | tail -5 && npx eslint force-app/main/default/lwc && echo ESLINT_OK`
Expected: the placement test passes; every existing suite still passes (a host suite that asserted on `querySelectorAll("h2")` text or on the first `slds-col` may need its selector tightened, never its assertion weakened; note each such edit in the report). Jest suites: 31 + 3 new bundles' suites + placement = 35.

- [ ] **Step 5: Deploy the hosts**

Run: `sf project deploy start -o sandbox --source-dir force-app/main/default/lwc -l NoTestRun -w 30 --json | python3 -c "import json,sys; r=json.load(sys.stdin)['result']; print(r['id'], r['status'], r.get('numberComponentsDeployed'), 'errors', r.get('numberComponentErrors'))"`

Expected: `Succeeded`, 0 errors. Record the id.

- [ ] **Step 6: Commit**

```bash
git add force-app/main/default/lwc
git commit -m "Place a help hint in each Lane Benchmark and RFP area"
```

---

### Task 8: CI, docs, final deploy, browser checks

**Files:**

- Modify: `.github/workflows/ci.yml`, `README.md`, `docs/superpowers/specs/2026-09-07-pricing-department-roadmap.md`, `docs/superpowers/specs/2026-09-12-phase-5-help-center-design.md`

- [ ] **Step 1: CI runs the content check**

In `.github/workflows/ci.yml`, in the `lwc` job, add `- run: npm run help:check` right after `- run: npm run prettier:verify`.

- [ ] **Step 2: README**

Add a row to the "What is in here" table after the last RFP `UI` row:

```
| UI               | `lwc/helpCenter`, `helpHint`, `helpContent`; `staticresources/helpCenter`; `flexipages/Help_Center`, `tabs/Help_Center` | Phase 5: the Help tab (bilingual user guide built from `docs/help`), the "?" hint popover, and the module that loads the content |
```

Add a section `## Help center (phase 5)` right before `## Known issues worth fixing`:

```markdown
## Help center (phase 5)

Pricers get a **Help** tab (`Help_Center`, in the Lane Benchmark and Trans-Pro
apps) with the user guide in English and French, and a small "?" next to the
title of each area in Lane Benchmark and the RFP Tool that opens a one-line hint
with a "Read more" link into the matching section.

**Editing the guide.** The source is `docs/help/en/<slug>.md` and
`docs/help/fr/<slug>.md` — one file per section, the same slugs in both
languages, a front-matter block with `title`, `order` and `hint` (the popover
text, at most 240 characters), then Markdown limited to `##`/`###` headings,
paragraphs, bold, italics, inline code, links, lists and tables. No images.
After editing run `npm run help:build`; it renders the files into the
`helpCenter` static resource, which is committed. `npm run help:check` (run by
CI) fails when the resource is stale or a rule is broken. Deploy the resource
with the normal full-manifest command; users see the change after a reload.

**Adding a hint.** Put `<c-help-hint topic="<slug>" label="Help: <area>">` in
the host component's markup (no JavaScript needed). The placement test in
`lwc/helpContent/__tests__/placement.test.js` lists where each hint sits and
fails on a topic that is not in the guide.

**Language.** The tab opens in French for a `fr*` Salesforce locale and in
English otherwise; the EN | FR toggle is remembered per browser
(`helpCenter.lang.v1`). Deep links: `/lightning/n/Help_Center?c__section=rfp-pricing&c__lang=fr`.

**Access.** Tab visibility comes with `Lane_Benchmark_User` and `RFP_Tool_User`.
No Apex is involved.
```

- [ ] **Step 3: Roadmap and spec Outcome**

In the roadmap table add a row after phase 4:

```
| 5   | Help center         | Bilingual user guide on a Help tab built from `docs/help`, plus "?" hints in every tool area linking to it | Done 2026-09-12 (PostProduc) |
```

Append `## Outcome — phase 5 (2026-09-12)` to the phase 5 spec: branch, the eight commits, deploy ids from Tasks 3, 6, 7 and this task, Jest suites/tests before and after, rulings R54 (tab motif) and R55 (`lb-lane` hint in the container card), and a "Browser check" line reading "pending (controller)".

- [ ] **Step 4: Final full deploy with tests**

Run the README's full-manifest command pair against `sandbox`: first `-l NoTestRun`, then `-l RunSpecifiedTests` with the 22 classes. Expected: 0 errors, 124/124 (the Apex count is unchanged by this phase). Record both ids in the Outcome.

- [ ] **Step 5: Full local gate**

Run: `npm test 2>&1 | tail -4 && npm run lint && npm run prettier:verify && npm run help:check`
Expected: all green.

- [ ] **Step 6: Commit**

```bash
git add .github/workflows/ci.yml README.md docs/superpowers/specs/2026-09-07-pricing-department-roadmap.md docs/superpowers/specs/2026-09-12-phase-5-help-center-design.md
git commit -m "Document the help center and run its content check in CI"
```

- [ ] **Step 7: Browser checks (controller, not the implementer)**

In PostProduc, after deleting the `ComponentDefStorage` IndexedDB database and reloading:

1. The Help tab is in the Lane Benchmark app after RFP Tool; it opens on "What these tools do" in English (the test user's locale is en).
2. FR switches the column and the body to French; reload keeps FR; EN switches back.
3. The filter box narrows the column ("pric" → one entry).
4. On the RFP Tool, open a project, click the "?" next to a lane title in the panel: the popover shows the pricing hint; "Read more" opens the Help tab on "Pricing a lane" in the current language; the browser back button returns to the workbench.
5. Escape closes a popover; clicking elsewhere closes it; two hints never show at once.
6. The "?" in the lane table header, the toolbar, the bulk bar, the bid form, the upload label, the mapper and the project list all open.
7. Lane Benchmark: the "?" on the Lane card, Filters, Statistics and Results open; the Results card still shows Export CSV next to the "?".
8. The French text of three sections reads naturally (the user reviews the rest).

Record the results in the Outcome, replacing "pending (controller)".
