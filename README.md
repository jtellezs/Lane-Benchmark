# Pricing Department (Salesforce)

Source for the **Pricing Department** Lightning app used by the Trans-Pro pricing team.
It is a single Lightning App Page that lists recent carrier quotes with filters and
min / max / average stats, so pricing can benchmark a lane before quoting a customer.

Retrieved on 2026-09-07 from the `postproduc` sandbox (sf alias `sandbox`).

## What is in here

| Layer | Component | Notes |
|---|---|---|
| Navigation | `tabs/Pricing_Department` | Custom tab pointing at the app page |
| Page | `flexipages/Pricing_Department` | App page, default home template, one region |
| UI | `lwc/pricingDepartment` | Filters, quote table, stats header, carrier detail modal |
| Apex | `classes/PricingDepartmentController` | Two `@AuraEnabled(cacheable=true)` methods: `getCarrierQuotes`, `getUniqueModeOptions` |
| Apex tests | `PricingDepartmentControllerTest3`, `PricingDepartmentController_TGN_TEST` | |
| Data | `objects/rtms__CarrierQuote__c/fields/*` | 24 custom fields on the Revenova TMS Carrier Quote object, almost all formulas |
| Data (2nd layer) | fields on `rtms__CarrierService__c`, `rtms__TransportationProfile__c`, `rtms__Load__c`, `Account` | Custom fields those formulas read through lookups |
| Security | `profiles/Pricing` | Scoped copy of the Pricing profile (only entries for components in this project). Access is profile-based; no permission set exists for this app |

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

| Org | Alias | Role | Data |
|---|---|---|---|
| Production | `vscodeOrg` | Source of truth, last stop. Never deploy from a laptop. | Real |
| PostProduc (Full) | `sandbox` | UAT and anything that needs real loads, stops, quotes | Real, copied at refresh |
| DevPro (Developer Pro) | `devpro` | All development and CI validation | Metadata only, no records |

After a DevPro refresh, authorize the refreshed org with:

```bash
sf org resume sandbox --job-id <id> -o ienescu@trans-pro.com
```

If the job id isn't available, fall back to a browser login:

```bash
sf org login web -a devpro -r https://test.salesforce.com
```

Then regenerate the CI secret (see CI section). A refresh changes the org id and appends `.invalid` to every user email.

```bash
# Re-pull everything in the manifest
sf project retrieve start -x manifest/package.xml -o sandbox

# Deploy back (validate first)
sf project deploy validate -x manifest/package.xml -o sandbox
sf project deploy start    -x manifest/package.xml -o sandbox

# Run the tests
sf apex run test -n PricingDepartmentControllerTest3 -n PricingDepartmentController_TGN_TEST -o sandbox -r human
```

Org aliases: `sandbox` = postproduction sandbox, `Full` = full sandbox, `vscodeOrg` = production.

## Known issues worth fixing

- `PricingDepartmentController` is `without sharing` and hardcodes an excluded Contact Id (`0033l00002px9ja`).
- Every filter is a `LIKE '%x%'` on formula fields, which cannot use indexes; dedupe happens in Apex after the 500-row limit is applied.
- `handleAcceptedQuotesFilterChange` in the LWC logs `isAcceptedQuotesChecked.isPriceDepChecked`, which throws a ReferenceError.
- `fetchModeOptions` (server-side mode options) is never called; modes are derived client-side from the result set instead.
- `PricingDepartmentControllerTest3` (TestGen, 2023) calls `getCarrierQuotes` with 8 arguments; the method now takes 9, so that test no longer compiles. `PricingDepartmentController_TGN_TEST` is the current one.
- Both tests insert an empty Carrier Quote and only assert nothing; they exercise coverage, not behavior.
- The LWC API version is 57.0 while the project is on 64.0.

## Git remotes

| Remote | URL | Account |
|---|---|---|
| `origin` | https://github.com/IulianEnescu78/PricingDepartment | personal (primary) |
| `tplm` | https://github.com/TPLM/PricingDepartment | Trans-Pro org, via the `IulianEnescu` GitHub login |

Always push `origin` first, then `tplm`. The default credential helper holds the personal
login, which cannot see the private TPLM repo, so push to `tplm` with the work token:

```bash
git push origin main
WT=$(gh auth token -u IulianEnescu) && git -c credential.helper= -c "credential.helper=!f() { echo username=IulianEnescu; echo password=$WT; }; f" push tplm main
```
