# Pricing Department (Salesforce)

Source for the **Pricing Department** Lightning app used by the Trans-Pro pricing team.
It is a single Lightning App Page that lists recent carrier quotes with filters and
min / max / average stats, so pricing can benchmark a lane before quoting a customer.

Retrieved on 2026-09-07 from the `postproduc` sandbox (sf alias `sandbox`).

## What is in here

| Layer            | Component                                                                                         | Notes                                                                                                                                                                                                                                                                                                                                                                                                                                                  |
| ---------------- | ------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Navigation       | `tabs/Pricing_Department`                                                                         | Custom tab pointing at the app page                                                                                                                                                                                                                                                                                                                                                                                                                    |
| Page             | `flexipages/Pricing_Department`                                                                   | App page, default home template, one region                                                                                                                                                                                                                                                                                                                                                                                                            |
| UI               | `lwc/pricingDepartment`                                                                           | Filters, quote table, stats header, carrier detail modal                                                                                                                                                                                                                                                                                                                                                                                               |
| Apex             | `classes/PricingDepartmentController`                                                             | Two `@AuraEnabled(cacheable=true)` methods: `getCarrierQuotes`, `getUniqueModeOptions`                                                                                                                                                                                                                                                                                                                                                                 |
| Apex tests       | `PricingDepartmentControllerTest`, `PricingTestDataFactory`                                       | Behavior tests; the factory builds the minimum valid Revenova graph the managed triggers require, so tests do not depend on org data                                                                                                                                                                                                                                                                                                                   |
| Data             | `objects/rtms__CarrierQuote__c/fields/*`                                                          | 24 custom fields on the Revenova TMS Carrier Quote object, almost all formulas                                                                                                                                                                                                                                                                                                                                                                         |
| Data (2nd layer) | fields on `rtms__CarrierService__c`, `rtms__TransportationProfile__c`, `rtms__Load__c`, `Account` | Custom fields those formulas read through lookups                                                                                                                                                                                                                                                                                                                                                                                                      |
| Security         | `permissionsets/Pricing_Department_User`                                                          | The way to grant access from now on: tab, Apex class, read on every field the page uses except `rtms__Carrier_Service__c`, `rtms__Vendor__c`, and `rtms__Load__c` (required/master-detail fields; Salesforce rejects field permissions on them, they are always readable once the object is). Also grants object Read on `rtms__Load__c` because Carrier Quote is its master-detail child. `profiles/Pricing` is kept for reference and never deployed |

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
sf apex run test -n PricingDepartmentControllerTest -o sandbox -r human -w 10
```

```bash
# Deploy to PostProduc (destructive changes remove retired classes; re-runnable)
sf project deploy start -x manifest/package.xml --post-destructive-changes manifest/destructiveChangesPost.xml -o sandbox -l RunSpecifiedTests -t PricingDepartmentControllerTest
```

Org aliases: `sandbox` = PostProduc, `vscodeOrg` = production.

## Known issues worth fixing

- `PricingDepartmentController` is `without sharing` and hardcodes an excluded Contact Id (`0033l00002px9ja`).
- Every filter is a `LIKE '%x%'` on formula fields, which cannot use indexes; dedupe happens in Apex after the 500-row limit is applied.
- `handleAcceptedQuotesFilterChange` in the LWC logs `isAcceptedQuotesChecked.isPriceDepChecked`, which throws a ReferenceError.
- `fetchModeOptions` (server-side mode options) is never called; modes are derived client-side from the result set instead.
- The LWC API version is 57.0 while the project is on 64.0.

## Continuous integration

`.github/workflows/ci.yml` runs on every pull request and on pushes to `main`, identically
in both repositories:

| Job    | What it does                                                                           | Fails on                                   |
| ------ | -------------------------------------------------------------------------------------- | ------------------------------------------ |
| `lwc`  | `npm ci`, ESLint, Prettier check, Jest with coverage                                   | lint error, formatting drift, failing test |
| `apex` | `sf project deploy validate` against PostProduc with `PricingDepartmentControllerTest` | compile error, test failure                |
| `pmd`  | PMD 7 Apex quickstart, priority 1-2                                                    | any P1/P2 violation                        |

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
