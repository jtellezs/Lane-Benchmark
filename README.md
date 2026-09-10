# Pricing Department (Salesforce)

Source for the **Pricing Department** Lightning app used by the Trans-Pro pricing team.
It is a single Lightning App Page that lists recent carrier quotes with filters and
min / max / average stats, so pricing can benchmark a lane before quoting a customer.

Retrieved on 2026-09-07 from the `postproduc` sandbox (sf alias `sandbox`).

## What is in here

| Layer            | Component                                                                                                                                                                                           | Notes                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| ---------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Navigation       | `tabs/Pricing_Department`                                                                                                                                                                           | Custom tab pointing at the app page                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| Page             | `flexipages/Pricing_Department`                                                                                                                                                                     | App page, default home template, one region                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              |
| UI               | `lwc/pricingDepartment`                                                                                                                                                                             | Filters, quote table, stats header, carrier detail modal                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| Apex             | `classes/PricingDepartmentController`                                                                                                                                                               | One `@AuraEnabled(cacheable=true)` method: `getCarrierQuotes`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            |
| Data             | `objects/Pricing_Place__c/*`                                                                                                                                                                        | Phase 1 place dictionary: normalized city/province/country key, `Aliases__c`/`Spellings__c`, `Source__c` (`Locations`/`Mapbox`), geolocation, `Location_Count__c`/`Load_Count_365d__c`                                                                                                                                                                                                                                                                                                                                                                                                                                   |
| Apex             | `classes/PlaceNormalizer`                                                                                                                                                                           | Phase 1: normalizes raw `ShippingCity`/`ShippingState`/`ShippingCountry` into dictionary keys                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            |
| Apex (batch)     | `classes/PlaceBuilderBatch`, `PlaceWriteBatch`, `PlaceUsageBatch`                                                                                                                                   | Phase 1: builds/refreshes `Pricing_Place__c` from shipping locations, then fills `Load_Count_365d__c`; never deletes, never overwrites `Aliases__c`/`Active__c`                                                                                                                                                                                                                                                                                                                                                                                                                                                          |
| Apex             | `classes/LaneSearchService`, `LaneSearchQueryBuilder`, `LaneSearchFilters`                                                                                                                          | Phase 1: typed lane search over `rtms__CarrierQuote__c` (any precision, filters, per-currency stats, dedupe, truncation)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| Apex             | `classes/LaneSearchRequest`, `LaneSearchResult`                                                                                                                                                     | Phase 1: typed request/result DTOs shared by `LaneSearchService` and `LaneBenchmarkController`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| Navigation       | `tabs/Lane_Benchmark`, `flexipages/Lane_Benchmark`, `applications/Lane_Benchmark`, `applications/TransPro` (tab added)                                                                              | Phase 2: the Lane Benchmark page's own tab/page/app, plus the tab appended to the existing `TransPro` app                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                |
| UI               | `lwc/laneBenchmark`, `laneBenchmarkPlacePicker`, `laneBenchmarkFilters`, `laneBenchmarkStats`, `laneBenchmarkResults`, `laneBenchmarkMap`, `laneBenchmarkCsv`, `laneBenchmarkStorage`, `marginMath` | Phase 2: the nine Lane Benchmark bundles — container, place picker, filters, stats/margin, results table with CSV export, static map preview, and the CSV/storage/margin pure modules                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| Apex             | `classes/LaneBenchmarkController`                                                                                                                                                                   | Aura/LWC entry points for the Lane Benchmark page: search, place autocomplete, filter options, geocode, map preview                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| Apex             | `classes/LaneBenchmarkPlaceService`                                                                                                                                                                 | `Pricing_Place__c` reads/writes behind `LaneBenchmarkController`'s `geocode()`/`mapPreviewUrl()`, split out to keep the controller under the PMD CyclomaticComplexity threshold                                                                                                                                                                                                                                                                                                                                                                                                                                          |
| Apex             | `classes/MapboxGeocoder`                                                                                                                                                                            | Forward geocoding and static map URLs through the org's Mapbox account                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   |
| Apex tests       | `PricingDepartmentControllerTest`, `PricingTestDataFactoryTest`, `PlaceNormalizerTest`, `PlaceBuilderBatchTest`, `LaneSearchServiceTest`, `MapboxGeocoderTest`, `LaneBenchmarkControllerTest`       | Behavior tests; `PricingTestDataFactory` builds the minimum valid Revenova graph the managed triggers require, so tests do not depend on org data                                                                                                                                                                                                                                                                                                                                                                                                                                                                        |
| Data             | `objects/rtms__CarrierQuote__c/fields/*`                                                                                                                                                            | 24 custom fields on the Revenova TMS Carrier Quote object, almost all formulas                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| Data (2nd layer) | fields on `rtms__CarrierService__c`, `rtms__TransportationProfile__c`, `rtms__Load__c`, `Account`                                                                                                   | Custom fields those formulas read through lookups                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        |
| Security         | `permissionsets/Pricing_Department_User`                                                                                                                                                            | The way to grant access from now on: tab, Apex class, read on every field the page uses except `rtms__Carrier_Service__c`, `rtms__Vendor__c`, and `rtms__Load__c` (required/master-detail fields; Salesforce rejects field permissions on them, they are always readable once the object is). Also grants object Read on `rtms__Load__c` because Carrier Quote is its master-detail child, and object Read/Edit + field read (Edit also on `Aliases__c`/`Active__c`) on `Pricing_Place__c` so the place dictionary is queryable outside of system-mode Apex. `profiles/Pricing` is kept for reference and never deployed |
| Security         | `permissionsets/Lane_Benchmark_User`                                                                                                                                                                | Grants access to the Lane Benchmark page: app/tab visibility, Apex class access (`LaneBenchmarkController`, `LaneBenchmarkPlaceService`, `LaneSearchService`, `MapboxGeocoder`), object read on `rtms__CarrierQuote__c`/`rtms__Load__c`/`Pricing_Place__c`, field read on every field the page shows. Assign this to the pricing team; `Pricing_Department_User` is unchanged                                                                                                                                                                                                                                            |
| Security (CSP)   | `cspTrustedSites/Mapbox_API`                                                                                                                                                                        | `img-src` trusted site for `https://api.mapbox.com`, needed for the Lane Benchmark static map preview                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |

Not included on purpose:

- Managed-package metadata (`rtms__*` fields and objects, the `rtms.CarrierQuoteUpsert` trigger) is not retrievable.
- Two record-triggered flows on Carrier Quote (`UAT_Carrier_Quote_Created`, `UAT_Carrier_Quote_Delete`) belong to a separate UAT tracking system and only call its subflows. They are left out so a deploy from this project never touches them.

## How the data flows

```
Load (rtms__Load__c)  ──┐
Carrier Service ────────┼─► formula fields on rtms__CarrierQuote__c ─► SOQL in controller ─► LWC table
Vendor Account ─────────┘
```

Nearly every column in the table is a cross-object formula on Carrier Quote
(origin, destination, mode, equipment, customer, contact, carrier risk, blacklist flag).
The controller queries those formulas with `LIKE` filters, dedupes rows in Apex, and
returns at most 500 records ordered by `Quote_Date__c` desc.

## Working with the org

### Environments

| Org        | Alias       | Role                                            | Data                    |
| ---------- | ----------- | ----------------------------------------------- | ----------------------- |
| PostProduc | `sandbox`   | Develop, test, CI, UAT. Real deploys land here. | Real, copied at refresh |
| Production | `vscodeOrg` | Live. Deployed after sign-off in PostProduc     | Real                    |

Full is other teams' active development sandbox and is not used for this project.
A Developer Pro sandbox (`devpro`) was also tried, but it cannot insert `rtms__Load__c`:
the Revenova managed triggers need configuration records that only a data-carrying
sandbox has.

### After a PostProduc refresh

Re-authorize the refreshed org:

```bash
sf org login web -a sandbox -r https://test.salesforce.com
```

Then regenerate the CI secret in the TPLM repository (see CI section). A refresh changes
the org id and appends `.invalid` to every user email.

```bash
# Re-pull everything in the manifest
sf project retrieve start -x manifest/package.xml -o sandbox

# Deploy back (validate first)
sf project deploy validate -x manifest/package.xml -o sandbox
sf project deploy start    -x manifest/package.xml -o sandbox

# Run the tests
sf apex run test -n PricingDepartmentControllerTest -n PlaceNormalizerTest -n PricingTestDataFactoryTest -n PlaceBuilderBatchTest -n LaneSearchServiceTest -n MapboxGeocoderTest -n LaneBenchmarkControllerTest -o sandbox -r human -w 15
```

```bash
# Deploy to PostProduc. --post-destructive-changes is a two-step, not a re-runnable one:
# add the members to manifest/destructiveChangesPost.xml, deploy once, then empty the
# manifest again. A second deploy naming already-deleted components fails the whole run.
sf project deploy start -x manifest/package.xml --post-destructive-changes manifest/destructiveChangesPost.xml -o sandbox -l RunSpecifiedTests -t PricingDepartmentControllerTest PlaceNormalizerTest PricingTestDataFactoryTest PlaceBuilderBatchTest LaneSearchServiceTest MapboxGeocoderTest LaneBenchmarkControllerTest
```

Org aliases: `sandbox` = PostProduc, `vscodeOrg` = production.

### Place dictionary

`Pricing_Place__c` was built once in PostProduc on 2026-09-09 by running:

```apex
Database.executeBatch(new PlaceBuilderBatch(), 2000);
```

(`sf apex run -o sandbox` with that one line; `PlaceBuilderBatch.finish()` chains
`PlaceWriteBatch`, which upserts the built rows in governor-safe per-scope
transactions, then chains `PlaceUsageBatch` to fill `Load_Count_365d__c`, which
also writes through `PlaceWriteBatch`.) Rerun the same command any time; it never
deletes a place and never overwrites `Aliases__c` or `Active__c`.

Result: **10,496 places** (`SELECT COUNT() FROM Pricing_Place__c`), built from
58,755 location accounts referenced by a stop, which carry 11,479 distinct raw
`ShippingCity` spellings before normalization — so `PlaceNormalizer` collapses at
least 983 spelling/case/accent variants into shared keys (places are also split by
province and country, so the true collapse per city name is higher than that
difference suggests).

The dictionary was deleted and rebuilt from scratch on 2026-09-09 after the
Mexican-province fix, because every key holding a Mexican province changed
(`general escobedo|nuevo león|mx` → `general escobedo|nl|mx`) and an upsert by
`Key__c` would have left the old keys behind. The count came back to the same
10,496: the remapping is one-to-one, since no two Mexican state names share a code.
428 of those places are Mexican and **none** of them now carries a province longer
than the 2-letter code Revenova writes. 536 places worldwide (Guangdong, Istanbul,
Shanghai, Baden-Württemberg…) keep a full province name that used to be cut to three
characters.

Rerun the top 20 with:

```bash
sf data query -q "SELECT Name, Key__c, Location_Count__c, Load_Count_365d__c, Postal_Prefix__c FROM Pricing_Place__c ORDER BY Load_Count_365d__c DESC NULLS LAST LIMIT 20" -o sandbox
```

Top 20 places by loads touching this place (last 365 days), from the rebuilt
dictionary on 2026-09-09. `Load_Count_365d__c` counts one per load END, so a
load that both picks up and delivers in the same place counts 2 there.

| Name                      | Key                         | Locations | Loads (365d) | Postal prefix |
| ------------------------- | --------------------------- | --------- | ------------ | ------------- |
| Laredo, TX, US            | `laredo\|tx\|us`            | 970       | 6173         | 780           |
| Mississauga, ON, CA       | `mississauga\|on\|ca`       | 1470      | 2995         | L5T           |
| Lachine, QC, CA           | `lachine\|qc\|ca`           | 177       | 2892         | H8T           |
| Brampton, ON, CA          | `brampton\|on\|ca`          | 691       | 2754         | L6T           |
| Montréal, QC, CA          | `montreal\|qc\|ca`          | 1152      | 2720         | H4S           |
| Anjou, QC, CA             | `anjou\|qc\|ca`             | 121       | 2577         | H1J           |
| Calgary, AB, CA           | `calgary\|ab\|ca`           | 930       | 1918         | T2C           |
| Knowlton, QC, CA          | `knowlton\|qc\|ca`          | 16        | 1310         | J0E           |
| GENERAL ESCOBEDO, NL, MX  | `general escobedo\|nl\|mx`  | 5         | 1277         | 660           |
| Toronto, ON, CA           | `toronto\|on\|ca`           | 865       | 1179         | M9W           |
| Veracruz, ME, MX          | `veracruz\|me\|mx`          | 2         | 1165         | 916           |
| Baie-d'Urfé, QC, CA       | `baie d urfe\|qc\|ca`       | 68        | 1118         | H9X           |
| Laval, QC, CA             | `laval\|qc\|ca`             | 403       | 1043         | H7L           |
| Rocky View County, AB, CA | `rocky view county\|ab\|ca` | 47        | 921          | T4A           |
| Vaughan, ON, CA           | `vaughan\|on\|ca`           | 293       | 876          | L4K           |
| San Diego, CA, US         | `san diego\|ca\|us`         | 132       | 859          | 921           |
| Burnaby, BC, CA           | `burnaby\|bc\|ca`           | 175       | 851          | V5J           |
| Edmonton, AB, CA          | `edmonton\|ab\|ca`          | 658       | 845          | T5S           |
| Boucherville, QC, CA      | `boucherville\|qc\|ca`      | 144       | 835          | J4B           |
| Dorval, QC, CA            | `dorval\|qc\|ca`            | 223       | 732          | H9P           |

The two Mexican rows are the point of the fix: they read `Nue` and `Mex` before it,
and no CITY or PROVINCE search could reach either place. Every count here is lower
than the first build's, because the number now means loads (one per end) rather than
every stop on every load.

Montréal/Montreal spot check. `Spellings__c` is a long text area with one
spelling per line; the block below is reformatted onto single lines (`/`
between spellings) so it fits here:

```
SELECT Name, Key__c, Spellings__c FROM Pricing_Place__c WHERE Key__c LIKE 'montreal|%'
Montréal, QC, CA | montreal|qc|ca | MONTREAL / MONTREAL, / MONTRÉAL / MONTRÉAL, / Montreal / Montreal, / Montréal / Montréal, / montreal
Montreal, , CA   | montreal||ca   | MONTREAL / Montreal
```

`montreal|qc|ca` is the intended collapse: `Spellings__c` shows "Montréal",
"Montreal" and "MONTREAL" (plus accented/cased/punctuated variants) all merged
into one place under `ShippingState = QC` (the raw location accounts have 577
"Montréal", 573 "MONTREAL", and 18 more such rows — see the spec Outcome for the
full breakdown — plus a few unrelated near-matches like "Montrose" and
"Montréal-Nord", which correctly stay separate places). `montreal||ca` is a
second, minor key from a handful of accounts where the full city/province/postal
string was typed into `ShippingCity` with `ShippingState` left blank (e.g.
"Montreal QC", "MONTREAL, QC H2P 1L5") — real, messy source data the normalizer
correctly treats as a different (blank-province) key rather than silently
guessing the province.

`Name` has no field-level security of its own, so anyone who can edit
`Pricing_Place__c` (the `Pricing_Department_User` permission set grants object
Edit, for `Aliases__c` and `Active__c`) can also retype the place's name - and
`PlaceBuilderBatch` overwrites it on the next run. Only `Aliases__c` and
`Active__c` survive a rebuild.

### Lane search

`LaneSearchService.search(LaneSearchRequest)` returns a `LaneSearchResult` (rows,
`statsByCurrency` per currency, `truncated`, `elapsedMs`, `dedupedCount`). A worked
example against real data lives at `scripts/apex/laneSearchExample.apex` (run with
`sf apex run -f scripts/apex/laneSearchExample.apex -o sandbox`); measured timings
are recorded in `docs/superpowers/specs/2026-09-09-phase-1-search-foundation-design.md`
under Outcome. Sample request, city precision, last 90 days:

```apex
LaneSearchRequest r = new LaneSearchRequest();
r.originKey = 'montreal|qc|ca';
r.destinationKey = 'toronto|on|ca';
r.originPrecision = LaneSearchRequest.Precision.CITY;
r.destinationPrecision = LaneSearchRequest.Precision.CITY;
r.lookbackDays = 90;
LaneSearchResult res = LaneSearchService.search(r);
```

### Support case

Custom-index request for `rtms__Load__c.rtms__City_Lane__c` /
`rtms__State_Lane__c` / `rtms__Zip3_Lane__c`: case number ______ (filed by the
user).

## Lane Benchmark (phase 2)

A new page, tab and Lightning app, alongside the existing Pricing Department
page (which stays untouched until pricing confirms the switch — see
"Retiring the old tab" below).

**Opening it:** either the **Lane Benchmark** tab inside the **TransPro**
app, or the standalone **Lane Benchmark** app from the App Launcher.

**Precision** (chosen per origin and destination independently):

- **Exact city** — matches the place's normalized city/province/country key.
- **Province or state** — matches anywhere in that province/state.
- **Postal prefix** — matches the first three characters of the postal code.
- **Radius** — matches within a distance (mi or km) of the place's
  geolocation; a static map preview appears once at least one end uses this
  precision.

**Margin controls:** one margin percentage (default 15, buttons for 15% and
20%, or free entry 0-100) applies across every currency's stats card and
drives the suggested sell price (`cost × (1 + margin / 100)`) shown next to
the median and average.

**CSV export:** "Export CSV" downloads the currently visible rows
(RFC 4180 quoting, UTF-8 BOM so accented city names open correctly in
Excel/Numbers), named `lane-benchmark-<origin>-<destination>-<yyyymmdd>.csv`.

**Remembered filters:** the last search request is saved to `localStorage`
under the key `laneBenchmark.request.v1` and restored (and re-run) the next
time the page opens. The filters panel has a "Clear saved filters" link that
removes that key and also resets the page back to an empty request and no
result — a full reset, not just a storage clear.

**Mapbox reuse:** the picker's "Search on the map" fallback and the radius
map preview call Mapbox through the same setup `KPI_ReportController`
already uses — no new credential was created:

- Token: the org-default record of the hierarchy custom setting
  `TPRO_KPI__c`, field `Mapbox_Api_Key__c` (a public `pk.` token).
- Remote Site Setting: `MapBox`, for `https://api.mapbox.com`.
- CSP Trusted Site: `Mapbox_API` (`img-src`, for the static map `<img>`).

Because the token is public and appears in the static-map image URL,
add URL restrictions on it in the Mapbox account for `*.my.salesforce.com`,
`*.lightning.force.com` and `*.sandbox.my.salesforce.com` so it only works
from this org's domains.

**Permission set:** assign `Lane_Benchmark_User` to the pricing team —

```bash
sf org assign permset -n Lane_Benchmark_User -o sandbox
```

**Retiring the old tab (phase 4):** once pricing has switched over, the
`Pricing_Department` tab/page/LWC and its permission set are removed in a
separate change (roadmap phase 4); nothing about that removal is done yet.

## Known issues worth fixing

- The excluded Contact Ids now live in `Pricing_Department_Setting__mdt` (record `Default`, field `Excluded_Contact_Ids__c`) instead of being hardcoded. `PricingDepartmentController` is still `without sharing`; that is intentional and documented in the class. The repo is the source of truth for `Pricing_Department_Setting.Default`; every deploy overwrites the org value, so admins request changes by pull request.
- Every filter is a `LIKE '%x%'` on formula fields, which cannot use indexes; dedupe happens in Apex after the 500-row limit is applied.

## Continuous integration

`.github/workflows/ci.yml` runs on every pull request and on pushes to `main`, identically
in both repositories:

| Job    | What it does                                                                                                  | Fails on                                   |
| ------ | ------------------------------------------------------------------------------------------------------------- | ------------------------------------------ |
| `lwc`  | `npm ci`, ESLint, Prettier check, Jest with coverage                                                          | lint error, formatting drift, failing test |
| `apex` | validates the manifest against PostProduc and runs the project's test classes (see the workflow for the list) | compile error, test failure                |
| `pmd`  | PMD 7 Apex quickstart, priority 3 (all quickstart rules), text output in the job log                          | any quickstart violation                   |

CI never deploys. Deploys to PostProduc are run by a developer after merge (command
above).

Secret `SFDX_AUTH_URL_POSTPRODUC` is set in the TPLM repository only. The personal
mirror (`IulianEnescu78/PricingDepartment`) has no org secret, so its `apex` job detects
that and skips its Salesforce steps instead of failing; the `apex` job only validates for
real in the TPLM repository. Regenerate the secret after every PostProduc refresh:

```bash
set -o pipefail
sf org auth show-sfdx-auth-url -o sandbox --json 2>/dev/null \
  | python3 -c "import json,sys; u=json.load(sys.stdin)['result']['sfdxAuthUrl']; assert u.startswith('force://'); sys.stdout.write(u)" \
  | GH_TOKEN=$(gh auth token -u IulianEnescu) gh secret set SFDX_AUTH_URL_POSTPRODUC -R TPLM/PricingDepartment
```

Never echo or print the auth URL; pipe it directly from `sf org auth show-sfdx-auth-url` into
`gh secret set`. (`sf org display --verbose --json` no longer includes the real URL on current
CLI versions; it returns a `[REDACTED]` placeholder.)

### Branch protection

Enabled on `main` in both repositories: required status checks (strict, i.e. branches
must be up to date before merging), no force pushes, no deletions.
`IulianEnescu78/PricingDepartment` requires `["lwc", "pmd"]` (it has no org secret, so
`apex` cannot be a required context there); `TPLM/PricingDepartment` requires
`["lwc", "apex", "pmd"]`.

## Git remotes

| Remote   | URL                                                 | Account                                            |
| -------- | --------------------------------------------------- | -------------------------------------------------- |
| `origin` | https://github.com/IulianEnescu78/PricingDepartment | personal (primary)                                 |
| `tplm`   | https://github.com/TPLM/PricingDepartment           | Trans-Pro org, via the `IulianEnescu` GitHub login |

Always push `origin` first, then `tplm`. The default credential helper holds the personal
login, which cannot see the private TPLM repo, so push to `tplm` with the work token:

```bash
git push origin main
WT=$(gh auth token -u IulianEnescu) && git -c credential.helper= -c "credential.helper=!f() { echo username=IulianEnescu; echo password=$WT; }; f" push tplm main
```
