# Phase 0: Engineering Hygiene Implementation Plan

> **Note (2026-09-09):** environment references to DevPro/Full in this plan are historical. The pipeline adopted during execution is PostProduc -> Production; see the phase 0 spec and README.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the Pricing Department Salesforce project a dev sandbox, CI that validates every pull request, behavior-level tests, and ship the known bugs as the first change through that pipeline.

**Architecture:** Two branches. `phase-0/foundation` installs tooling, extracts pure LWC logic into a testable module, adds an Apex test data factory and real controller tests, retires the old tests, and adds the CI workflow; it merges before branch protection exists. `phase-0/bug-fixes` is the first pull request gated by CI: LWC fixes, custom metadata for the excluded contact, and a permission set. CI only validates against DevPro; humans deploy.

**Tech Stack:** Salesforce DX (`sf` CLI 2.x, API 64.0), Apex, Lightning Web Components, `@salesforce/sfdx-lwc-jest`, ESLint 9 with `@salesforce/eslint-config-lwc`, Prettier 3 with Apex/XML plugins, Husky + lint-staged, GitHub Actions, PMD 7.

**Spec:** `docs/superpowers/specs/2026-09-07-phase-0-engineering-hygiene-design.md` (parent roadmap: `docs/superpowers/specs/2026-09-07-pricing-department-roadmap.md`)

## Global Constraints

- Org aliases: `vscodeOrg` = production (never deploy), `sandbox` = PostProduc full sandbox (UAT and real-data checks only), `devpro` = DevPro Developer Pro sandbox (all development, CI validation). DevPro has **metadata only, no records**.
- CI validates only (`sf project deploy validate`); it never deploys.
- `sourceApiVersion` is `64.0`; the LWC `apiVersion` becomes `64.0`.
- `PricingDepartmentController` stays `without sharing`, with a comment saying so.
- Profiles are never deployed: `force-app/main/default/profiles/**` goes in `.forceignore`.
- Git: **no attribution trailers** in any commit. Push `origin` (personal) first, then `tplm`, using the command from the README:
  `WT=$(gh auth token -u IulianEnescu) && git -c credential.helper= -c "credential.helper=!f() { echo username=IulianEnescu; echo password=$WT; }; f" push tplm <branch>`
- The CI secret is named `SFDX_AUTH_URL_DEVPRO` in both repos and is never printed, echoed, or written to a file.
- Out of scope: any change to Load, Stop, or Place data; new filters or UI; deploys to PostProduc or production; profile assignments.

## Prerequisite (manual, blocks Task 1 onward)

The DevPro refresh (job `0GROG0000002Dqn4AE`) must be complete and the user must have logged in. The user runs, in this order:

```bash
sf org resume sandbox --job-id 0GROG0000002Dqn4AE -o ienescu@trans-pro.com   # until Status: Completed
sf org logout -o devpro-sandbox --no-prompt                                    # dead pre-refresh login
sf org login web -a devpro -r https://test.salesforce.com                       # browser login to the refreshed org
```

Verify: `sf org display -o devpro` shows `Connected Status: Connected` and an Org Id different from the pre-refresh one.

---

## File structure

| Path                                                                                   | Responsibility                                              |
| -------------------------------------------------------------------------------------- | ----------------------------------------------------------- |
| `.forceignore`                                                                         | Exclude profiles and Jest tests from deploys                |
| `.github/workflows/ci.yml`                                                             | Three CI jobs: `lwc`, `apex`, `pmd`                         |
| `config/pmd-ruleset.xml`                                                               | PMD ruleset: Apex quickstart, priority 1-2 gate             |
| `manifest/package.xml`                                                                 | Deployable members (already exists; updated)                |
| `manifest/destructiveChangesPost.xml`                                                  | Removes the two retired test classes                        |
| `force-app/main/default/lwc/quoteStats/quoteStats.js`                                  | Pure functions: statistics, row shaping, mode options       |
| `force-app/main/default/lwc/quoteStats/__tests__/quoteStats.test.js`                   | Unit tests for the pure module                              |
| `force-app/main/default/lwc/pricingDepartment/*`                                       | Existing component, slimmed to UI state + Apex calls        |
| `force-app/main/default/lwc/pricingDepartment/__tests__/pricingDepartment.test.js`     | Component tests                                             |
| `force-app/main/default/classes/PricingTestDataFactory.cls`                            | Builds the minimum valid Revenova graph for tests           |
| `force-app/main/default/classes/PricingDepartmentControllerTest.cls`                   | Behavior tests for the controller                           |
| `force-app/main/default/classes/PricingDepartmentController.cls`                       | Existing controller; excluded contacts from custom metadata |
| `force-app/main/default/objects/Pricing_Department_Setting__mdt/**`                    | Custom metadata type + `Excluded_Contact_Ids__c`            |
| `force-app/main/default/customMetadata/Pricing_Department_Setting.Default.md-meta.xml` | The one settings record                                     |
| `force-app/main/default/permissionsets/Pricing_Department_User.permissionset-meta.xml` | Tab, Apex, field read access                                |
| `README.md`                                                                            | Environment table, runbook, CI notes                        |

Retired: `classes/PricingDepartmentControllerTest3.cls(-meta.xml)`, `classes/PricingDepartmentController_TGN_TEST.cls(-meta.xml)`.

---

### Task 1: Reconcile the repo against the refreshed DevPro

**Files:**

- Modify: `force-app/**` only if the diff review says production had newer Pricing Department metadata (expected: no changes)
- Modify: `README.md` (environment table)

**Interfaces:**

- Produces: DevPro contains exactly the repo's version of every manifest member. Later tasks deploy to `devpro` freely.

- [ ] **Step 1: Confirm the org is the refreshed one**

Run: `sf org display -o devpro --json | python3 -c "import json,sys; r=json.load(sys.stdin)['result']; print(r['id'], r['connectedStatus'])"`
Expected: an Org Id that is not `00DAq00000AOoCQMA1` (the pre-refresh DevPro) and `Connected`.

- [ ] **Step 2: Retrieve the manifest from DevPro into the scratchpad and diff**

```bash
S=/private/tmp/claude-501/-Users-iulian-Documents-Personal-PricingDepartemnt/807bc83e-ba13-4dfd-a891-1d50262f98b0/scratchpad/devpro-diff
rm -rf "$S" && mkdir -p "$S" && cd "$S" && sf project generate -n p -t empty >/dev/null && cd p
cp /Users/iulian/Documents/Personal/PricingDepartemnt/manifest/package.xml .
sf project retrieve start -x package.xml -o devpro
diff -r force-app/main/default /Users/iulian/Documents/Personal/PricingDepartemnt/force-app/main/default \
  -x profiles -x __tests__ | head -100
```

Expected: only differences in the `Pricing` profile (excluded) or none. Production is the refresh source; PostProduc was the repo source. If any file under `classes/`, `lwc/`, `objects/`, `flexipages/`, or `tabs/` differs, stop and show the diff to the user before choosing a side. Do not overwrite the repo silently.

- [ ] **Step 3: Deploy the repo to DevPro**

Run: `cd /Users/iulian/Documents/Personal/PricingDepartemnt && sf project deploy start -x manifest/package.xml -o devpro -l NoTestRun`
Expected: `Status: Succeeded`. (No tests yet; the old test classes are still in the org and one does not compile, which is why `NoTestRun` is used here and only here.)

- [ ] **Step 4: Add the environment table to the README**

Insert after the "Working with the org" heading in `README.md`:

```markdown
### Environments

| Org                    | Alias       | Role                                                    | Data                      |
| ---------------------- | ----------- | ------------------------------------------------------- | ------------------------- |
| Production             | `vscodeOrg` | Source of truth, last stop. Never deploy from a laptop. | Real                      |
| PostProduc (Full)      | `sandbox`   | UAT and anything that needs real loads, stops, quotes   | Real, copied at refresh   |
| DevPro (Developer Pro) | `devpro`    | All development and CI validation                       | Metadata only, no records |

After a DevPro refresh: `sf org logout -o devpro --no-prompt`, `sf org login web -a devpro -r https://test.salesforce.com`, then regenerate the CI secret (see CI section). A refresh changes the org id and appends `.invalid` to every user email.
```

- [ ] **Step 5: Commit**

```bash
git checkout -b phase-0/foundation
git add README.md
git commit -m "Document environments and DevPro refresh runbook"
```

---

### Task 2: Node toolchain, Husky, forceignore, project name

**Files:**

- Modify: `package.json` (name only), `sfdx-project.json` (name), `.forceignore`
- Create: `package-lock.json`

**Interfaces:**

- Produces: `npm run lint`, `npm run prettier:verify`, `npm test` all runnable; pre-commit hook active.

- [ ] **Step 1: Rename the project**

In `sfdx-project.json` change `"name": "PricingDepartemnt"` to `"name": "PricingDepartment"`.
In `package.json` change `"name": "salesforce-app"` to `"name": "pricing-department"` and `"description": "Salesforce App"` to `"description": "Pricing Department Lightning app (Trans-Pro)"`.

- [ ] **Step 2: Exclude profiles from deploys**

Append to `.forceignore`:

```
# Profiles are reference only; access is granted through permission sets
force-app/main/default/profiles/**
```

- [ ] **Step 3: Install dependencies and activate Husky**

Run: `npm install`
Expected: `package-lock.json` created, `node_modules/` present, `.husky/_` created by the `prepare` script. If `npm install` reports peer-dependency conflicts, rerun with `npm install --legacy-peer-deps` and note it in the README.

- [ ] **Step 4: Run every tool once**

Run: `npm run lint && npm run prettier:verify; npm test -- --passWithNoTests`
Expected: `lint` passes or reports only issues inside `pricingDepartment.js` (these are fixed in Task 4; if lint fails on the unused `fetchModeOptions` or on `console.log`, that is expected here). `prettier:verify` will list unformatted files; run `npm run prettier` once to format the whole repo, then `npm run prettier:verify` must pass. `npm test` reports "No tests found" and exits 0.

- [ ] **Step 5: Confirm the pre-commit hook fires**

Run: `git add -A && git commit -m "Install Node toolchain, format sources, exclude profiles from deploys"`
Expected: lint-staged output appears before the commit is created. If the hook fails because `sfdx-lwc-jest` finds no related tests, the `--passWithNoTests` flag already in `package.json` handles it.

---

### Task 3: Extract `quoteStats` pure module with Jest tests

**Files:**

- Create: `force-app/main/default/lwc/quoteStats/quoteStats.js`
- Create: `force-app/main/default/lwc/quoteStats/quoteStats.js-meta.xml`
- Create: `force-app/main/default/lwc/quoteStats/__tests__/quoteStats.test.js`
- Modify: `force-app/main/default/lwc/pricingDepartment/pricingDepartment.js`

**Interfaces:**

- Produces (imported by Task 4 and later phases):
  - `calculateStats(quotes: Array<{CAD_Quote_Total__c:number}>) => { min:number, max:number, avg:number, roundedAvg:string, nbOfQuotes:number, nbOfQuotesNotZero:number }`
  - `shapeRows(quotes: Array<object>) => Array<object & { rowNumber:number, id:number, cellModeClass:string, showAdditionalContent:boolean, additionalContentKey:string }>`
  - `modeOptionsFrom(quotes: Array<{Mode__c:string}>) => Array<{label:string, value:string}>` with `{ label: '-- All --', value: '' }` first

- [ ] **Step 1: Write the failing tests**

`force-app/main/default/lwc/quoteStats/__tests__/quoteStats.test.js`:

```javascript
import { calculateStats, shapeRows, modeOptionsFrom } from "c/quoteStats";

const q = (total, mode = "Truckload", id = "a") => ({
  Id: id,
  CAD_Quote_Total__c: total,
  Mode__c: mode
});

describe("calculateStats", () => {
  it("returns zeros for an empty list", () => {
    expect(calculateStats([])).toEqual({
      min: 0,
      max: 0,
      avg: 0,
      roundedAvg: "0.00",
      nbOfQuotes: 0,
      nbOfQuotesNotZero: 0
    });
  });

  it("ignores zero totals for min, max and average but counts them", () => {
    const s = calculateStats([q(0), q(100), q(300)]);
    expect(s.min).toBe(100);
    expect(s.max).toBe(300);
    expect(s.avg).toBe(200);
    expect(s.roundedAvg).toBe("200.00");
    expect(s.nbOfQuotes).toBe(3);
    expect(s.nbOfQuotesNotZero).toBe(2);
  });

  it("rounds the average to two decimals as a string", () => {
    expect(calculateStats([q(100), q(101), q(101)]).roundedAvg).toBe("100.67");
  });
});

describe("shapeRows", () => {
  it("numbers rows from 1 and assigns the mode cell class", () => {
    const rows = shapeRows([
      q(1, "LTL", "x"),
      q(2, "Truckload", "y"),
      q(3, "Freight Forwarding", "z"),
      q(4, "Drayage", "w")
    ]);
    expect(rows.map((r) => r.rowNumber)).toEqual([1, 2, 3, 4]);
    expect(rows.map((r) => r.cellModeClass)).toEqual([
      "ltl-cell",
      "ftl-cell",
      "freight-cell",
      ""
    ]);
    expect(rows[0].additionalContentKey).toBe("x-additional-content");
    expect(rows[0].showAdditionalContent).toBe(false);
  });

  it("does not mutate the input objects", () => {
    const input = [q(1)];
    shapeRows(input);
    expect(input[0].rowNumber).toBeUndefined();
  });
});

describe("modeOptionsFrom", () => {
  it("lists distinct modes after an All option", () => {
    expect(
      modeOptionsFrom([q(1, "LTL"), q(2, "Truckload"), q(3, "LTL")])
    ).toEqual([
      { label: "-- All --", value: "" },
      { label: "LTL", value: "LTL" },
      { label: "Truckload", value: "Truckload" }
    ]);
  });
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `npx sfdx-lwc-jest -- force-app/main/default/lwc/quoteStats`
Expected: FAIL, "Cannot find module 'c/quoteStats'".

- [ ] **Step 3: Write the module**

`force-app/main/default/lwc/quoteStats/quoteStats.js`:

```javascript
const MODE_CELL_CLASS = {
  LTL: "ltl-cell",
  Truckload: "ftl-cell",
  "Freight Forwarding": "freight-cell"
};

export function calculateStats(quotes) {
  let sum = 0;
  let count = 0;
  let countZero = 0;
  let min = Number.MAX_VALUE;
  let max = -Number.MAX_VALUE;

  quotes.forEach((quote) => {
    const total = quote.CAD_Quote_Total__c;
    if (!total) {
      countZero += 1;
      return;
    }
    if (total < min) min = total;
    if (total > max) max = total;
    sum += total;
    count += 1;
  });

  const avg = count === 0 ? 0 : sum / count;
  return {
    min: count === 0 ? 0 : min,
    max: count === 0 ? 0 : max,
    avg,
    roundedAvg: avg.toFixed(2),
    nbOfQuotes: count + countZero,
    nbOfQuotesNotZero: count
  };
}

export function shapeRows(quotes) {
  return quotes.map((quote, index) => ({
    ...quote,
    rowNumber: index + 1,
    id: index,
    cellModeClass: MODE_CELL_CLASS[quote.Mode__c] || "",
    showAdditionalContent: false,
    additionalContentKey: `${quote.Id}-additional-content`
  }));
}

export function modeOptionsFrom(quotes) {
  const modes = [...new Set(quotes.map((quote) => quote.Mode__c))];
  return [
    { label: "-- All --", value: "" },
    ...modes.map((mode) => ({ label: mode, value: mode }))
  ];
}
```

`force-app/main/default/lwc/quoteStats/quoteStats.js-meta.xml`:

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<LightningComponentBundle xmlns="http://soap.sforce.com/2006/04/metadata">
    <apiVersion>64.0</apiVersion>
    <isExposed>false</isExposed>
</LightningComponentBundle>
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `npx sfdx-lwc-jest -- force-app/main/default/lwc/quoteStats`
Expected: PASS, 7 tests.

- [ ] **Step 5: Use the module in the component**

In `force-app/main/default/lwc/pricingDepartment/pricingDepartment.js`:

Add after the two `@salesforce/apex` imports:

```javascript
import { calculateStats, shapeRows, modeOptionsFrom } from "c/quoteStats";
```

Replace the body of the `if (result) { ... }` block inside `fetchCarrierQuotes` with:

```javascript
this.carrierQuotesData = shapeRows(result);
this.errors = undefined;
this.applyStats(calculateStats(result));
this.modeOptions = modeOptionsFrom(result);
```

Delete the methods `generateModeOptions`, `calculateStats`, `getRowClass`, and `getAdditionalContentKey` from the class. Add this method in their place:

```javascript
applyStats(stats) {
    this.minQuoteTotal = stats.min;
    this.maxQuoteTotal = stats.max;
    this.avgQuoteTotal = stats.avg;
    this.roundedAVG = stats.roundedAvg;
    this.nbOfQuotes = stats.nbOfQuotes;
    this.nbOfQuotesNotZero = stats.nbOfQuotesNotZero;
}
```

Remove the now-unused tracked fields `expandedRowIndex`, `additionalContentKey`, `titleValue`, and the commented `minIndex`/`maxIndex` lines.

- [ ] **Step 6: Lint and run all Jest**

Run: `npm run lint && npm test`
Expected: lint passes except for pre-existing issues in `handleAcceptedQuotesFilterChange` and `console.log` calls (fixed in Task 4); Jest PASS.

- [ ] **Step 7: Commit**

```bash
git add force-app/main/default/lwc
git commit -m "Extract quote statistics and row shaping into a pure quoteStats module"
```

---

### Task 4: Apex test data factory (discovery in DevPro)

**Files:**

- Create: `force-app/main/default/classes/PricingTestDataFactory.cls`
- Create: `force-app/main/default/classes/PricingTestDataFactory.cls-meta.xml`
- Create (temporary, deleted at end of task): `scripts/apex/factorySmoke.apex`
- Modify: `manifest/package.xml`

**Interfaces:**

- Produces (used by Task 5):
  - `PricingTestDataFactory.Graph` with public fields `customer`, `vendor`, `originLocation`, `destinationLocation` (Account), `quoteContact` (Contact), `profile` (rtms__TransportationProfile__c), `mode` (rtms__Mode__c), `equipment` (rtms__EquipmentType__c), `carrierService` (rtms__CarrierService__c)
  - `static Graph createGraph()` inserts everything above and returns it
  - `static rtms__Load__c createLoad(Graph g, String origin, String destination)` inserts a load with two stops on the graph's location accounts and returns it re-queried with `rtms__First_Stop__c`, `rtms__Last_Stop__c`
  - `static rtms__CarrierQuote__c buildQuote(Graph g, rtms__Load__c load, Decimal cadTotal)` returns an **uninserted** quote so tests can tweak fields before insert

Facts already established from the PostProduc describe (the factory encodes them):

| Object                         | Required / needed                                                                                                                                                                               | Why                                                                           |
| ------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------- |
| Account (vendor)               | `RecordType` = `Carrier`, `rtms__TMS_Type__c` = `Carrier (Ground)`                                                                                                                              | Validation rule `Carrier_service_only_for_carriers`                           |
| Account (customer)             | `rtms__TMS_Type__c` = `Customer`, full Billing address, `Industry`                                                                                                                              | Validation rules `Billing_Addres_is_Mandatory`, `Force_to_enter_the_industry` |
| Account (locations)            | `RecordType` = `Shipper_Consignee`, `ShippingCity/State/Country`, `ShippingLatitude/Longitude`                                                                                                  | Load origin/destination formulas read `rtms__Location2__r`                    |
| rtms__TransportationProfile__c | `RecordType` = `Carrier`                                                                                                                                                                        | Active rule `Credit_limit_zero` only bites `Shipper_Consignee`                |
| rtms__Mode__c                  | `Name`, `rtms__Order__c`, `rtms__Minimum_Weight__c`, `rtms__Maximum_Weight__c`                                                                                                                  | Required fields                                                               |
| rtms__EquipmentType__c         | `Name`, `rtms__Max_Weight__c`, `rtms__Mode__c` (multipicklist), `rtms__Category__c`                                                                                                             | Required fields                                                               |
| rtms__CarrierService__c        | `rtms__Mode__c`, `rtms__Carrier__c`, `rtms__Transportation_Profile__c`, `rtms__Minimum_Weight__c`, `rtms__Maximum_Weight__c`, `rtms__Quote_Contact__c`                                          | Required fields; contact drives `Contact_ID__c`                               |
| rtms__Load__c                  | `rtms__Total_Weight__c`, `TPRO_Division_Name__c` = `Trans-Pro Logistics Inc`, `rtms__Customer__c`, `rtms__Mode__c`, `rtms__Equipment_Type__c`, `Mode_For_Sharing__c`, `CurrencyIsoCode` = `CAD` | Required + formulas the page reads                                            |
| rtms__Stop__c                  | `rtms__Load__c`, `rtms__Number__c`, `rtms__Location2__c`                                                                                                                                        | Required; location feeds origin/destination                                   |
| rtms__CarrierQuote__c          | `rtms__Load__c`, `rtms__Carrier_Service__c`, `rtms__Vendor__c`, `rtms__Carrier_Total__c`, `CurrencyIsoCode` = `CAD`                                                                             | Required + `CAD_Quote_Total__c` formula                                       |

Known unknown: the custom triggers `LoadTrigger`, `LoadStatusTrigger`, `LoadFinancialTrigger`, `LoadARTrigger`, `StopTrigger`, `AccountTrigger` and the managed Revenova triggers may demand more. Step 3 is the discovery loop; every fix goes into the factory, never into a test.

- [ ] **Step 1: Write the factory**

`force-app/main/default/classes/PricingTestDataFactory.cls`:

```apex
/**
 * Builds the minimum valid Revenova graph the Pricing Department tests need.
 * DevPro has no records, so every test creates its data through this class.
 * If a managed or custom trigger rejects an insert, fix it HERE, not in a test.
 */
@IsTest
public class PricingTestDataFactory {
  public static final String DIVISION = 'Trans-Pro Logistics Inc';

  public class Graph {
    public Account customer;
    public Account vendor;
    public Account originLocation;
    public Account destinationLocation;
    public Contact quoteContact;
    public rtms__TransportationProfile__c profile;
    public rtms__Mode__c mode;
    public rtms__EquipmentType__c equipment;
    public rtms__CarrierService__c carrierService;
  }

  private static Id recordTypeId(String sobjectName, String developerName) {
    return Schema.getGlobalDescribe()
      .get(sobjectName)
      .getDescribe()
      .getRecordTypeInfosByDeveloperName()
      .get(developerName)
      .getRecordTypeId();
  }

  public static Graph createGraph() {
    Graph g = new Graph();

    g.customer = new Account(
      Name = 'Test Customer',
      RecordTypeId = recordTypeId('Account', 'Customer'),
      rtms__TMS_Type__c = 'Customer',
      Industry = 'Other',
      BillingStreet = '1 Test St',
      BillingCity = 'Montreal',
      BillingState = 'Quebec',
      BillingPostalCode = 'H1A 1A1',
      BillingCountry = 'Canada',
      CurrencyIsoCode = 'CAD'
    );
    g.vendor = new Account(
      Name = 'Test Carrier',
      RecordTypeId = recordTypeId('Account', 'Carrier'),
      rtms__TMS_Type__c = 'Carrier (Ground)',
      CurrencyIsoCode = 'CAD'
    );
    g.originLocation = location(
      'Origin Co',
      'Montreal',
      'Quebec',
      'Canada',
      45.5019,
      -73.5674
    );
    g.destinationLocation = location(
      'Destination Co',
      'Toronto',
      'Ontario',
      'Canada',
      43.6532,
      -79.3832
    );
    insert new List<Account>{
      g.customer,
      g.vendor,
      g.originLocation,
      g.destinationLocation
    };

    g.quoteContact = new Contact(
      FirstName = 'Quote',
      LastName = 'Contact',
      AccountId = g.vendor.Id,
      Email = 'quote.contact@example.invalid',
      Phone = '514-555-0100'
    );
    insert g.quoteContact;

    g.profile = new rtms__TransportationProfile__c(
      Name = 'Test Carrier Profile',
      RecordTypeId = recordTypeId('rtms__TransportationProfile__c', 'Carrier'),
      rtms__Company_Risk__c = 'Acceptable'
    );
    insert g.profile;

    g.mode = new rtms__Mode__c(
      Name = 'Truckload',
      rtms__Order__c = 1,
      rtms__Minimum_Weight__c = 0,
      rtms__Maximum_Weight__c = 100000
    );
    insert g.mode;

    g.equipment = new rtms__EquipmentType__c(
      Name = 'Dry Van 53\'',
      rtms__Max_Weight__c = 45000,
      rtms__Mode__c = 'Truckload',
      rtms__Category__c = 'Van',
      rtms__Enabled__c = true
    );
    insert g.equipment;

    g.carrierService = new rtms__CarrierService__c(
      Name = 'Test Carrier Service',
      rtms__Carrier__c = g.vendor.Id,
      rtms__Mode__c = g.mode.Id,
      rtms__Transportation_Profile__c = g.profile.Id,
      rtms__Quote_Contact__c = g.quoteContact.Id,
      rtms__Minimum_Weight__c = 0,
      rtms__Maximum_Weight__c = 100000
    );
    insert g.carrierService;
    return g;
  }

  private static Account location(
    String name,
    String city,
    String state,
    String country,
    Decimal lat,
    Decimal lng
  ) {
    return new Account(
      Name = name,
      RecordTypeId = recordTypeId('Account', 'Shipper_Consignee'),
      rtms__TMS_Type__c = 'Shipper/Consignee',
      ShippingStreet = '1 Dock Rd',
      ShippingCity = city,
      ShippingState = state,
      ShippingPostalCode = 'A1A 1A1',
      ShippingCountry = country,
      ShippingLatitude = lat,
      ShippingLongitude = lng,
      CurrencyIsoCode = 'CAD'
    );
  }

  /** Inserts a load with a pickup at the origin location and a delivery at the destination location. */
  public static rtms__Load__c createLoad(
    Graph g,
    Account origin,
    Account destination
  ) {
    rtms__Load__c load = new rtms__Load__c(
      Name = 'Test Load',
      rtms__Customer__c = g.customer.Id,
      rtms__Mode__c = g.mode.Id,
      rtms__Equipment_Type__c = g.equipment.Id,
      rtms__Total_Weight__c = 1000,
      Mode_For_Sharing__c = 'Truckload',
      TPRO_Division_Name__c = DIVISION,
      CurrencyIsoCode = 'CAD'
    );
    insert load;

    rtms__Stop__c pickup = new rtms__Stop__c(
      rtms__Load__c = load.Id,
      rtms__Number__c = 1,
      rtms__Location2__c = origin.Id
    );
    rtms__Stop__c delivery = new rtms__Stop__c(
      rtms__Load__c = load.Id,
      rtms__Number__c = 2,
      rtms__Location2__c = destination.Id
    );
    insert new List<rtms__Stop__c>{ pickup, delivery };

    load = [
      SELECT Id, rtms__First_Stop__c, rtms__Last_Stop__c
      FROM rtms__Load__c
      WHERE Id = :load.Id
    ];
    if (load.rtms__First_Stop__c == null || load.rtms__Last_Stop__c == null) {
      load.rtms__First_Stop__c = pickup.Id;
      load.rtms__Last_Stop__c = delivery.Id;
      update load;
    }
    return load;
  }

  /** Returns an uninserted carrier quote on the graph's carrier service. Tests tweak fields, then insert. */
  public static rtms__CarrierQuote__c buildQuote(
    Graph g,
    rtms__Load__c load,
    Decimal cadTotal
  ) {
    return new rtms__CarrierQuote__c(
      rtms__Load__c = load.Id,
      rtms__Carrier_Service__c = g.carrierService.Id,
      rtms__Vendor__c = g.vendor.Id,
      rtms__Quote_Contact__c = g.quoteContact.Id,
      rtms__Carrier_Total__c = cadTotal,
      CurrencyIsoCode = 'CAD'
    );
  }
}
```

`force-app/main/default/classes/PricingTestDataFactory.cls-meta.xml`:

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<ApexClass xmlns="http://soap.sforce.com/2006/04/metadata">
    <apiVersion>64.0</apiVersion>
    <status>Active</status>
</ApexClass>
```

- [ ] **Step 2: Add the class to the manifest and deploy it alone**

In `manifest/package.xml`, add `<members>PricingTestDataFactory</members>` to the `ApexClass` type.

Run: `sf project deploy start -m ApexClass:PricingTestDataFactory -o devpro -l NoTestRun`
Expected: `Status: Succeeded`. Compile errors here mean a field name is wrong; fix against `sf sobject describe -s <object> -o devpro`.

- [ ] **Step 3: Discovery loop with an anonymous Apex smoke script**

Create `scripts/apex/factorySmoke.apex`:

```apex
// Runs inside a savepoint so nothing persists in DevPro.
Savepoint sp = Database.setSavepoint();
try {
    PricingTestDataFactory.Graph g = PricingTestDataFactory.createGraph();
    rtms__Load__c load = PricingTestDataFactory.createLoad(g, g.originLocation, g.destinationLocation);
    rtms__CarrierQuote__c quote = PricingTestDataFactory.buildQuote(g, load, 1500);
    insert quote;
    quote = [SELECT Origin__c, Destination__c, Mode__c, Equipment_Type__c, Carrier_Name__c, Contact_ID__c,
                    CAD_Quote_Total__c, Quote_Date__c, Hazmat__c, Accepted_quote__c, Decline_Quotes__c
             FROM rtms__CarrierQuote__c WHERE Id = :quote.Id];
    System.debug('SMOKE OK ' + JSON.serializePretty(quote));
} finally {
    Database.rollback(sp);
}
```

Run: `sf apex run -f scripts/apex/factorySmoke.apex -o devpro | grep -E "SMOKE OK|Exception|FIELD_CUSTOM_VALIDATION|REQUIRED_FIELD|Error" `
Expected on first run: probably an insert error naming a field or validation rule. For each error: add the field or value to the factory in the object's builder, redeploy the class (Step 2 command), rerun. Stop when the output contains `SMOKE OK` and the debug shows `Origin__c` = `Montreal, Quebec`, `Destination__c` = `Toronto, Ontario`, `Mode__c` = `Truckload`, `Equipment_Type__c` = `Dry Van 53'`, `Carrier_Name__c` = `Test Carrier`, `CAD_Quote_Total__c` = `1500`, `Contact_ID__c` = the contact's 15-character id.

If `rtms__Origin__c` on the load comes back blank even with stops linked, the managed formula needs a field on the stop or location we have not set (for example `rtms__City__c`/`rtms__State_Province__c` on the stop). Add them to `createLoad` and document why in a comment.

- [ ] **Step 4: Record what the loop found**

Add a comment block at the top of `PricingTestDataFactory.cls` under the class doc listing each field that had to be added during discovery and the error message that required it. Delete `scripts/apex/factorySmoke.apex`.

- [ ] **Step 5: Commit**

```bash
git add force-app/main/default/classes/PricingTestDataFactory.cls force-app/main/default/classes/PricingTestDataFactory.cls-meta.xml manifest/package.xml
git commit -m "Add PricingTestDataFactory that builds a valid Revenova graph for tests"
```

---

### Task 5: Behavior tests for the controller

**Files:**

- Create: `force-app/main/default/classes/PricingDepartmentControllerTest.cls`
- Create: `force-app/main/default/classes/PricingDepartmentControllerTest.cls-meta.xml`
- Modify: `force-app/main/default/classes/PricingDepartmentController.cls` (add a `@TestVisible` excluded-contact override only)
- Modify: `manifest/package.xml`

**Interfaces:**

- Consumes: `PricingTestDataFactory.createGraph()`, `createLoad(Graph, Account, Account)`, `buildQuote(Graph, rtms__Load__c, Decimal)`
- Produces: `PricingDepartmentControllerTest`, the only test class CI runs. `PricingDepartmentController.excludedContactIdsOverride` (`@TestVisible private static Set<String>`), reused in Task 8.

Note on dates: `Quote_Date__c` = `Shipping_Date__c` if set, else `DATEVALUE(CreatedDate)`. `Shipping_Date__c` reads the load's expected ship date, which is a read-only formula, so tests leave it blank and move `CreatedDate` with `Test.setCreatedDate`.

Note on the excluded contact: the controller currently hardcodes `Contact_ID__c != '0033l00002px9ja'`. Custom metadata cannot be inserted in tests, so this task adds a test-visible override the tests set; Task 8 wires the override to real custom metadata.

- [ ] **Step 1: Add the override hook to the controller (minimal, no behavior change)**

In `PricingDepartmentController.cls`, add inside the class, above `getCarrierQuotes`:

```apex
    // Test hook. Task 8 replaces the hardcoded id below with custom metadata read through this set.
    @TestVisible private static Set<String> excludedContactIdsOverride;

    private static Set<String> excludedContactIds() {
        if (excludedContactIdsOverride != null) {
            return excludedContactIdsOverride;
        }
        return new Set<String>{ '0033l00002px9ja' };
    }
```

Then in both SOQL queries replace `Contact_ID__c != '0033l00002px9ja'` with `Contact_ID__c NOT IN :excluded`, and add `Set<String> excluded = excludedContactIds();` as the first line of `fetchCarrierQuotes` and of `getUniqueModeOptions`.

- [ ] **Step 2: Write the failing tests**

`force-app/main/default/classes/PricingDepartmentControllerTest.cls`:

```apex
@IsTest
private class PricingDepartmentControllerTest {
  private static final String ALL = '';
  private static final Integer DAYS = 30;

  private static List<rtms__CarrierQuote__c> search(
    String origin,
    String destination,
    String mode,
    String hazmat,
    String priceDep,
    String equipment,
    Integer days,
    String accepted,
    String declined
  ) {
    return PricingDepartmentController.getCarrierQuotes(
      origin,
      destination,
      mode,
      hazmat,
      priceDep,
      equipment,
      days,
      accepted,
      declined
    );
  }

  private static rtms__CarrierQuote__c insertQuote(
    PricingTestDataFactory.Graph g,
    rtms__Load__c load,
    Decimal total
  ) {
    rtms__CarrierQuote__c q = PricingTestDataFactory.buildQuote(g, load, total);
    insert q;
    return q;
  }

  @TestSetup
  static void noExclusions() {
    // Nothing here on purpose: each test builds its own graph so field values are explicit.
  }

  @IsTest
  static void returnsQuotesMatchingOriginAndDestination() {
    PricingDepartmentController.excludedContactIdsOverride = new Set<String>();
    PricingTestDataFactory.Graph g = PricingTestDataFactory.createGraph();
    rtms__Load__c mtlToTor = PricingTestDataFactory.createLoad(
      g,
      g.originLocation,
      g.destinationLocation
    );
    rtms__Load__c torToMtl = PricingTestDataFactory.createLoad(
      g,
      g.destinationLocation,
      g.originLocation
    );
    insertQuote(g, mtlToTor, 1000);
    insertQuote(g, torToMtl, 2000);

    Test.startTest();
    List<rtms__CarrierQuote__c> result = search(
      'Montreal',
      'Toronto',
      ALL,
      ALL,
      ALL,
      ALL,
      DAYS,
      ALL,
      ALL
    );
    Test.stopTest();

    System.assertEquals(
      1,
      result.size(),
      'Only the Montreal -> Toronto quote should match'
    );
    System.assertEquals(1000, result[0].CAD_Quote_Total__c);
    System.assertEquals('Montreal, Quebec', result[0].Origin__c);
  }

  @IsTest
  static void originFilterIsCaseInsensitiveSubstring() {
    PricingDepartmentController.excludedContactIdsOverride = new Set<String>();
    PricingTestDataFactory.Graph g = PricingTestDataFactory.createGraph();
    rtms__Load__c load = PricingTestDataFactory.createLoad(
      g,
      g.originLocation,
      g.destinationLocation
    );
    insertQuote(g, load, 1000);

    System.assertEquals(
      1,
      search('montr', ALL, ALL, ALL, ALL, ALL, DAYS, ALL, ALL).size()
    );
    System.assertEquals(
      0,
      search('Calgary', ALL, ALL, ALL, ALL, ALL, DAYS, ALL, ALL).size()
    );
  }

  @IsTest
  static void dateWindowExcludesOlderQuotes() {
    PricingDepartmentController.excludedContactIdsOverride = new Set<String>();
    PricingTestDataFactory.Graph g = PricingTestDataFactory.createGraph();
    rtms__Load__c load = PricingTestDataFactory.createLoad(
      g,
      g.originLocation,
      g.destinationLocation
    );
    rtms__CarrierQuote__c recent = insertQuote(g, load, 1000);
    rtms__CarrierQuote__c old = insertQuote(g, load, 2000);
    Test.setCreatedDate(recent.Id, Datetime.now().addDays(-2));
    Test.setCreatedDate(old.Id, Datetime.now().addDays(-10));

    Test.startTest();
    List<rtms__CarrierQuote__c> last5 = search(
      ALL,
      ALL,
      ALL,
      ALL,
      ALL,
      ALL,
      5,
      ALL,
      ALL
    );
    List<rtms__CarrierQuote__c> last30 = search(
      ALL,
      ALL,
      ALL,
      ALL,
      ALL,
      ALL,
      30,
      ALL,
      ALL
    );
    Test.stopTest();

    System.assertEquals(
      1,
      last5.size(),
      'A 10-day-old quote is outside a 5-day window'
    );
    System.assertEquals(2, last30.size());
  }

  @IsTest
  static void hazmatFilterMatchesOnlyHazardousLoads() {
    PricingDepartmentController.excludedContactIdsOverride = new Set<String>();
    PricingTestDataFactory.Graph g = PricingTestDataFactory.createGraph();
    rtms__Load__c plain = PricingTestDataFactory.createLoad(
      g,
      g.originLocation,
      g.destinationLocation
    );
    rtms__Load__c hazardous = PricingTestDataFactory.createLoad(
      g,
      g.originLocation,
      g.destinationLocation
    );
    hazardous.rtms__Hazardous_Materials__c = true;
    update hazardous;
    insertQuote(g, plain, 1000);
    insertQuote(g, hazardous, 2000);

    List<rtms__CarrierQuote__c> result = search(
      ALL,
      ALL,
      ALL,
      'Hazmat',
      ALL,
      ALL,
      DAYS,
      ALL,
      ALL
    );

    System.assertEquals(1, result.size());
    System.assertEquals(2000, result[0].CAD_Quote_Total__c);
  }

  @IsTest
  static void marketTestFilterMatchesCustomerName() {
    PricingDepartmentController.excludedContactIdsOverride = new Set<String>();
    PricingTestDataFactory.Graph g = PricingTestDataFactory.createGraph();
    Account marketTest = g.customer.clone(false, true, false, false);
    marketTest.Name = 'Market Test';
    insert marketTest;
    rtms__Load__c normal = PricingTestDataFactory.createLoad(
      g,
      g.originLocation,
      g.destinationLocation
    );
    rtms__Load__c mt = PricingTestDataFactory.createLoad(
      g,
      g.originLocation,
      g.destinationLocation
    );
    mt.rtms__Customer__c = marketTest.Id;
    update mt;
    insertQuote(g, normal, 1000);
    insertQuote(g, mt, 3000);

    List<rtms__CarrierQuote__c> result = search(
      ALL,
      ALL,
      ALL,
      ALL,
      'Market Test',
      ALL,
      DAYS,
      ALL,
      ALL
    );

    System.assertEquals(1, result.size());
    System.assertEquals(3000, result[0].CAD_Quote_Total__c);
  }

  @IsTest
  static void acceptedAndDeclinedFlagsFilterOnAcceptedCheckbox() {
    PricingDepartmentController.excludedContactIdsOverride = new Set<String>();
    PricingTestDataFactory.Graph g = PricingTestDataFactory.createGraph();
    rtms__Load__c load = PricingTestDataFactory.createLoad(
      g,
      g.originLocation,
      g.destinationLocation
    );
    rtms__CarrierQuote__c accepted = PricingTestDataFactory.buildQuote(
      g,
      load,
      1000
    );
    accepted.rtms__Accepted__c = true;
    rtms__CarrierQuote__c declined = PricingTestDataFactory.buildQuote(
      g,
      load,
      2000
    );
    insert new List<rtms__CarrierQuote__c>{ accepted, declined };

    List<rtms__CarrierQuote__c> onlyAccepted = search(
      ALL,
      ALL,
      ALL,
      ALL,
      ALL,
      ALL,
      DAYS,
      'true',
      ALL
    );
    List<rtms__CarrierQuote__c> onlyDeclined = search(
      ALL,
      ALL,
      ALL,
      ALL,
      ALL,
      ALL,
      DAYS,
      ALL,
      'true'
    );

    System.assertEquals(1, onlyAccepted.size());
    System.assertEquals(1000, onlyAccepted[0].CAD_Quote_Total__c);
    System.assertEquals(1, onlyDeclined.size());
    System.assertEquals(2000, onlyDeclined[0].CAD_Quote_Total__c);
  }

  @IsTest
  static void excludedContactIsNeverReturned() {
    PricingTestDataFactory.Graph g = PricingTestDataFactory.createGraph();
    rtms__Load__c load = PricingTestDataFactory.createLoad(
      g,
      g.originLocation,
      g.destinationLocation
    );
    insertQuote(g, load, 1000);
    String fifteen = String.valueOf(g.quoteContact.Id).left(15);

    PricingDepartmentController.excludedContactIdsOverride = new Set<String>{
      fifteen
    };
    System.assertEquals(
      0,
      search(ALL, ALL, ALL, ALL, ALL, ALL, DAYS, ALL, ALL).size(),
      'Quotes whose contact is excluded must not be returned'
    );
    System.assertEquals(
      0,
      PricingDepartmentController.getUniqueModeOptions(ALL, ALL).size()
    );

    PricingDepartmentController.excludedContactIdsOverride = new Set<String>();
    System.assertEquals(
      1,
      search(ALL, ALL, ALL, ALL, ALL, ALL, DAYS, ALL, ALL).size()
    );
  }

  @IsTest
  static void identicalQuotesAreDeduplicated() {
    PricingDepartmentController.excludedContactIdsOverride = new Set<String>();
    PricingTestDataFactory.Graph g = PricingTestDataFactory.createGraph();
    rtms__Load__c load = PricingTestDataFactory.createLoad(
      g,
      g.originLocation,
      g.destinationLocation
    );
    insertQuote(g, load, 1000);
    insertQuote(g, load, 1000);
    insertQuote(g, load, 1250);

    List<rtms__CarrierQuote__c> result = search(
      ALL,
      ALL,
      ALL,
      ALL,
      ALL,
      ALL,
      DAYS,
      ALL,
      ALL
    );

    System.assertEquals(
      2,
      result.size(),
      'Same total, carrier, lane, mode and equipment collapse to one row'
    );
  }

  @IsTest
  static void uniqueModeOptionsAreDistinctAndLaneScoped() {
    PricingDepartmentController.excludedContactIdsOverride = new Set<String>();
    PricingTestDataFactory.Graph g = PricingTestDataFactory.createGraph();
    rtms__Load__c a = PricingTestDataFactory.createLoad(
      g,
      g.originLocation,
      g.destinationLocation
    );
    rtms__Load__c b = PricingTestDataFactory.createLoad(
      g,
      g.originLocation,
      g.destinationLocation
    );
    b.Mode_For_Sharing__c = 'LTL';
    update b;
    rtms__Load__c elsewhere = PricingTestDataFactory.createLoad(
      g,
      g.destinationLocation,
      g.originLocation
    );
    insertQuote(g, a, 1000);
    insertQuote(g, a, 1100);
    insertQuote(g, b, 500);
    insertQuote(g, elsewhere, 900);

    List<String> modes = PricingDepartmentController.getUniqueModeOptions(
      'Montreal',
      'Toronto'
    );

    System.assertEquals(2, modes.size());
    System.assert(modes.contains('Truckload') && modes.contains('LTL'));
  }

  @IsTest
  static void resultIsCappedAtFiveHundredRows() {
    PricingDepartmentController.excludedContactIdsOverride = new Set<String>();
    PricingTestDataFactory.Graph g = PricingTestDataFactory.createGraph();
    rtms__Load__c load = PricingTestDataFactory.createLoad(
      g,
      g.originLocation,
      g.destinationLocation
    );
    List<rtms__CarrierQuote__c> quotes = new List<rtms__CarrierQuote__c>();
    for (Integer i = 0; i < 520; i++) {
      quotes.add(PricingTestDataFactory.buildQuote(g, load, 1000 + i)); // distinct totals so dedupe keeps all
    }
    insert quotes;

    Test.startTest();
    List<rtms__CarrierQuote__c> result = search(
      ALL,
      ALL,
      ALL,
      ALL,
      ALL,
      ALL,
      DAYS,
      ALL,
      ALL
    );
    Test.stopTest();

    System.assertEquals(500, result.size());
  }
}
```

`PricingDepartmentControllerTest.cls-meta.xml`: same content as the factory's meta file (apiVersion 64.0, Active).

- [ ] **Step 3: Deploy and run the tests, expect failures that teach**

Add `<members>PricingDepartmentControllerTest</members>` to the `ApexClass` type in `manifest/package.xml`.

Run: `sf project deploy start -m ApexClass:PricingDepartmentController -m ApexClass:PricingDepartmentControllerTest -o devpro -l RunSpecifiedTests -t PricingDepartmentControllerTest`
Expected: most tests pass on first run if Task 4's smoke passed. Typical failures and their meaning:

- `returnsQuotesMatchingOriginAndDestination` fails on `Origin__c`: the managed load origin formula formats differently (for example `Montreal, QC`). Read the actual value in the failure message and update the assertion to the real format; note it in the test.
- `hazmatFilterMatchesOnlyHazardousLoads` fails with a validation error on `update hazardous`: a Load validation rule triggers on update. Set `rtms__Hazardous_Materials__c` through a new optional parameter instead: add `public static rtms__Load__c createLoad(Graph g, Account origin, Account destination, Boolean hazmat)` to the factory and have the 3-argument overload call it with `false`.
- `resultIsCappedAtFiveHundredRows` hits a governor limit inside managed triggers: reduce to 20 quotes and change the assertion to `System.assert(result.size() <= 500)` plus a comment that the cap is enforced by `LIMIT 500` in the query. Do not delete the test.

- [ ] **Step 4: Rerun until green**

Run: `sf apex run test -n PricingDepartmentControllerTest -o devpro -r human -w 10`
Expected: `Outcome: Passed`, 10 of 10, and `PricingDepartmentController` coverage above 85 %.

- [ ] **Step 5: Commit**

```bash
git add force-app/main/default/classes manifest/package.xml
git commit -m "Add behavior tests for PricingDepartmentController with a test-visible exclusion hook"
```

---

### Task 6: Retire the old test classes

**Files:**

- Delete: `force-app/main/default/classes/PricingDepartmentControllerTest3.cls`, `.cls-meta.xml`
- Delete: `force-app/main/default/classes/PricingDepartmentController_TGN_TEST.cls`, `.cls-meta.xml`
- Create: `manifest/destructiveChangesPost.xml`
- Modify: `manifest/package.xml`, `README.md`

**Interfaces:**

- Produces: DevPro no longer contains the two classes; CI's `RunSpecifiedTests` list has one name.

- [ ] **Step 1: Write the destructive manifest**

`manifest/destructiveChangesPost.xml`:

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<Package xmlns="http://soap.sforce.com/2006/04/metadata">
    <types>
        <members>PricingDepartmentControllerTest3</members>
        <members>PricingDepartmentController_TGN_TEST</members>
        <name>ApexClass</name>
    </types>
    <version>64.0</version>
</Package>
```

Remove both names from the `ApexClass` type in `manifest/package.xml`, and also remove the `Profile` type block entirely (profiles are ignored now). Delete the four class files from `force-app`.

- [ ] **Step 2: Deploy with the destructive changes to DevPro**

Run: `sf project deploy start -x manifest/package.xml --post-destructive-changes manifest/destructiveChangesPost.xml -o devpro -l RunSpecifiedTests -t PricingDepartmentControllerTest`
Expected: `Status: Succeeded`, with the two classes listed as `Deleted`.

Verify: `sf data query -t -q "SELECT Name FROM ApexClass WHERE Name LIKE 'PricingDepartment%'" -o devpro`
Expected: exactly `PricingDepartmentController` and `PricingDepartmentControllerTest`.

- [ ] **Step 3: Update the README**

In the "What is in here" table replace the Apex tests row with:

```markdown
| Apex tests | `PricingDepartmentControllerTest`, `PricingTestDataFactory` | Behavior tests; the factory builds the minimum valid Revenova graph because DevPro has no records |
```

In "Known issues worth fixing" delete the two bullets about the old test classes. Under "Working with the org" change the test command to `sf apex run test -n PricingDepartmentControllerTest -o devpro -r human -w 10` and add:

```bash
# Deploy to DevPro (destructive changes remove retired classes; re-runnable)
sf project deploy start -x manifest/package.xml --post-destructive-changes manifest/destructiveChangesPost.xml -o devpro -l RunSpecifiedTests -t PricingDepartmentControllerTest
```

- [ ] **Step 4: Commit**

```bash
git add -A force-app/main/default/classes manifest README.md
git commit -m "Retire coverage-only test classes via destructive changes"
```

---

### Task 7: CI workflow, secrets, branch protection

**Files:**

- Create: `.github/workflows/ci.yml`
- Create: `config/pmd-ruleset.xml`
- Modify: `README.md`

**Interfaces:**

- Consumes: `npm run lint`, `npm run prettier:verify`, `npm test`, `manifest/package.xml`, test class `PricingDepartmentControllerTest`.
- Produces: status checks named `lwc`, `apex`, `pmd`; secret `SFDX_AUTH_URL_DEVPRO` in both repos.

Spec deviation, deliberate: PMD runs through its CLI with `--minimum-priority 2`, printing violations in the job log, instead of PR annotations. The GitHub PMD action cannot gate on priority and SARIF upload needs code scanning, which private repos on these plans may not have.

- [ ] **Step 1: PMD ruleset**

`config/pmd-ruleset.xml`:

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<ruleset
  name="Pricing Department Apex rules"
  xmlns="http://pmd.sourceforge.net/ruleset/2.0.0"
  xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
  xsi:schemaLocation="http://pmd.sourceforge.net/ruleset/2.0.0 https://pmd.sourceforge.io/ruleset_2_0_0.xsd"
>
    <description
  >Apex quickstart rules. CI fails on priority 1 and 2 only.</description>
    <rule ref="rulesets/apex/quickstart.xml">
        <!-- Test classes deliberately create many records inline. -->
        <exclude name="ApexUnitTestClassShouldHaveRunAs" />
    </rule>
</ruleset>
```

- [ ] **Step 2: Workflow**

`.github/workflows/ci.yml`:

```yaml
name: CI

on:
  pull_request:
  push:
    branches: [main]

concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true

jobs:
  lwc:
    name: lwc
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: 20
          cache: npm
      - run: npm ci
      - run: npm run lint
      - run: npm run prettier:verify
      - run: npm run test:unit:coverage

  apex:
    name: apex
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: 20
      - name: Install Salesforce CLI
        run: npm install -g @salesforce/cli
      - name: Authenticate to DevPro
        env:
          SFDX_AUTH_URL: ${{ secrets.SFDX_AUTH_URL_DEVPRO }}
        run: |
          if [ -z "$SFDX_AUTH_URL" ]; then echo "SFDX_AUTH_URL_DEVPRO secret is not set"; exit 1; fi
          echo "$SFDX_AUTH_URL" | sf org login sfdx-url --sfdx-url-stdin --alias devpro --set-default
      - name: Validate deploy and run tests
        run: >
          sf project deploy validate
          --manifest manifest/package.xml
          --post-destructive-changes manifest/destructiveChangesPost.xml
          --test-level RunSpecifiedTests
          --tests PricingDepartmentControllerTest
          --target-org devpro
          --wait 30

  pmd:
    name: pmd
    runs-on: ubuntu-latest
    env:
      PMD_VERSION: 7.15.0
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: 21
      - name: Install PMD
        run: |
          curl -sSL -o pmd.zip "https://github.com/pmd/pmd/releases/download/pmd_releases%2F${PMD_VERSION}/pmd-dist-${PMD_VERSION}-bin.zip"
          unzip -q pmd.zip
      - name: Run PMD (fail on priority 1-2)
        run: >
          ./pmd-bin-${PMD_VERSION}/bin/pmd check
          --dir force-app/main/default/classes
          --rulesets config/pmd-ruleset.xml
          --minimum-priority 2
          --format text
          --fail-on-violation true
```

Validate locally before committing: `python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/ci.yml')); print('yaml ok')"` (install PyYAML with `pip3 install pyyaml` if missing).

Note: `--post-destructive-changes` on `deploy validate` is idempotent once the classes are gone; if a future CLI version rejects it for already-absent members, drop that flag from the workflow and keep it in the README deploy command only.

- [ ] **Step 3: Set the secret in both repos without printing it**

```bash
AUTH_JSON=$(sf org display -o devpro --verbose --json)
python3 -c "import json,sys; sys.stdout.write(json.loads(sys.argv[1])['result']['sfdxAuthUrl'])" "$AUTH_JSON" \
  | gh secret set SFDX_AUTH_URL_DEVPRO -R IulianEnescu78/PricingDepartment
python3 -c "import json,sys; sys.stdout.write(json.loads(sys.argv[1])['result']['sfdxAuthUrl'])" "$AUTH_JSON" \
  | GH_TOKEN=$(gh auth token -u IulianEnescu) gh secret set SFDX_AUTH_URL_DEVPRO -R TPLM/PricingDepartment
unset AUTH_JSON
gh secret list -R IulianEnescu78/PricingDepartment
GH_TOKEN=$(gh auth token -u IulianEnescu) gh secret list -R TPLM/PricingDepartment
```

Expected: both lists show `SFDX_AUTH_URL_DEVPRO` with today's date. Never `echo` the URL.

- [ ] **Step 4: Commit and push the foundation branch, merge it**

```bash
git add .github config README.md
git commit -m "Add CI: LWC lint and Jest, Apex validate against DevPro, PMD priority gate"
git push -u origin phase-0/foundation
WT=$(gh auth token -u IulianEnescu) && git -c credential.helper= -c "credential.helper=!f() { echo username=IulianEnescu; echo password=$WT; }; f" push -u tplm phase-0/foundation
gh pr create -R IulianEnescu78/PricingDepartment --base main --head phase-0/foundation --title "Phase 0 foundation: tooling, tests, CI" --body "See docs/superpowers/plans/2026-09-07-phase-0-engineering-hygiene.md, Tasks 1-7."
```

Watch the run: `gh run watch -R IulianEnescu78/PricingDepartment` (and the same with the TPLM token). Expected: `lwc`, `apex`, `pmd` all green. If `pmd` fails on existing controller code, fix the violation in the controller (they are real findings) and push again; do not lower the priority gate.

When green: `gh pr merge -R IulianEnescu78/PricingDepartment --merge --delete-branch`, then `git checkout main && git pull origin main` and push `main` to `tplm`. Open and merge the same PR on TPLM only if its `main` does not already contain the merge commit (`GH_TOKEN=... gh pr list -R TPLM/PricingDepartment`).

- [ ] **Step 5: Branch protection**

For each repo (`IulianEnescu78/PricingDepartment` with the default token, `TPLM/PricingDepartment` with `GH_TOKEN=$(gh auth token -u IulianEnescu)`):

```bash
gh api -X PUT repos/<owner>/PricingDepartment/branches/main/protection \
  --input - <<'EOF'
{
  "required_status_checks": { "strict": true, "contexts": ["lwc", "apex", "pmd"] },
  "enforce_admins": false,
  "required_pull_request_reviews": null,
  "restrictions": null,
  "allow_force_pushes": false,
  "allow_deletions": false
}
EOF
```

Expected: HTTP 200 with the protection JSON. If the API answers `403` with "Upgrade to GitHub Pro" (private repos on a free personal plan) or the org equivalent, record in the README that protection is unavailable on the current plan and that the required checks are enforced by convention: never merge a red PR. Do not make the repo public to get protection.

- [ ] **Step 6: README CI section and commit**

Append to `README.md`:

````markdown
## Continuous integration

`.github/workflows/ci.yml` runs on every pull request and on pushes to `main`, identically in both repositories:

| Job    | What it does                                                                       | Fails on                                   |
| ------ | ---------------------------------------------------------------------------------- | ------------------------------------------ |
| `lwc`  | `npm ci`, ESLint, Prettier check, Jest with coverage                               | lint error, formatting drift, failing test |
| `apex` | `sf project deploy validate` against DevPro with `PricingDepartmentControllerTest` | compile error, test failure                |
| `pmd`  | PMD 7 Apex quickstart, priority 1-2                                                | any P1/P2 violation                        |

CI never deploys. Deploys to DevPro are run by a developer after merge (command above).

Secret `SFDX_AUTH_URL_DEVPRO` must exist in both repos. Regenerate it after every DevPro refresh:

```bash
AUTH_JSON=$(sf org display -o devpro --verbose --json)
python3 -c "import json,sys; sys.stdout.write(json.loads(sys.argv[1])['result']['sfdxAuthUrl'])" "$AUTH_JSON" | gh secret set SFDX_AUTH_URL_DEVPRO -R IulianEnescu78/PricingDepartment
python3 -c "import json,sys; sys.stdout.write(json.loads(sys.argv[1])['result']['sfdxAuthUrl'])" "$AUTH_JSON" | GH_TOKEN=$(gh auth token -u IulianEnescu) gh secret set SFDX_AUTH_URL_DEVPRO -R TPLM/PricingDepartment
unset AUTH_JSON
```
````

````

```bash
git add README.md
git commit -m "Document CI jobs and secret rotation"
git push origin main
WT=$(gh auth token -u IulianEnescu) && git -c credential.helper= -c "credential.helper=!f() { echo username=IulianEnescu; echo password=$WT; }; f" push tplm main
````

(If branch protection succeeded, this README commit must go through a PR instead: branch `phase-0/ci-docs`, open, wait for green, merge.)

---

### Task 8: LWC bug fixes with component tests

**Files:**

- Modify: `force-app/main/default/lwc/pricingDepartment/pricingDepartment.js`
- Modify: `force-app/main/default/lwc/pricingDepartment/pricingDepartment.html` (lines 106-165, the four checkbox inputs)
- Modify: `force-app/main/default/lwc/pricingDepartment/pricingDepartment.js-meta.xml`
- Create: `force-app/main/default/lwc/pricingDepartment/__tests__/pricingDepartment.test.js`

**Interfaces:**

- Consumes: `c/quoteStats` (Task 3), mocked Apex modules.
- Produces: checkbox inputs carry `data-filter="marketTest" | "hazmat" | "declined" | "accepted"`; the component exposes no new public API.

- [ ] **Step 1: Start the bug-fix branch**

```bash
git checkout main && git pull origin main
git checkout -b phase-0/bug-fixes
```

- [ ] **Step 2: Write the failing component tests**

`force-app/main/default/lwc/pricingDepartment/__tests__/pricingDepartment.test.js`:

```javascript
import { createElement } from "lwc";
import PricingDepartment from "c/pricingDepartment";
import getCarrierQuotes from "@salesforce/apex/PricingDepartmentController.getCarrierQuotes";

jest.mock(
  "@salesforce/apex/PricingDepartmentController.getCarrierQuotes",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/PricingDepartmentController.getUniqueModeOptions",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const QUOTES = [
  {
    Id: "a",
    CAD_Quote_Total__c: 100,
    Mode__c: "LTL",
    Origin__c: "Montreal, Quebec"
  },
  {
    Id: "b",
    CAD_Quote_Total__c: 300,
    Mode__c: "Truckload",
    Origin__c: "Toronto, Ontario"
  },
  {
    Id: "c",
    CAD_Quote_Total__c: 0,
    Mode__c: "Truckload",
    Origin__c: "Laval, Quebec"
  }
];

const flush = () => new Promise((resolve) => setTimeout(resolve, 0));

async function mount() {
  const element = createElement("c-pricing-department", {
    is: PricingDepartment
  });
  document.body.appendChild(element);
  await flush();
  return element;
}

function checkbox(element, name) {
  return element.shadowRoot.querySelector(
    `input[type="checkbox"][data-filter="${name}"]`
  );
}

describe("c-pricing-department", () => {
  beforeEach(() => {
    getCarrierQuotes.mockResolvedValue(QUOTES);
  });
  afterEach(() => {
    while (document.body.firstChild)
      document.body.removeChild(document.body.firstChild);
    jest.clearAllMocks();
  });

  it("loads quotes on connect with the default 5-day window", async () => {
    await mount();
    expect(getCarrierQuotes).toHaveBeenCalledTimes(1);
    expect(getCarrierQuotes.mock.calls[0][0]).toMatchObject({
      dateRangeFilter: "5",
      originFilter: ""
    });
  });

  it("renders one row per quote and the computed statistics", async () => {
    const element = await mount();
    const rows = element.shadowRoot.querySelectorAll("tbody tr[data-index]");
    expect(rows.length).toBe(3);
    expect(element.shadowRoot.textContent).toContain("200.00 CAD");
  });

  it("toggling the accepted-quotes checkbox sets the filter without throwing", async () => {
    const element = await mount();
    const box = checkbox(element, "accepted");
    box.checked = true;
    expect(() => box.dispatchEvent(new CustomEvent("change"))).not.toThrow();
    await flush();
    element.shadowRoot
      .querySelector('lightning-button[label="Apply Filters"]')
      .click();
    await flush();
    expect(getCarrierQuotes).toHaveBeenLastCalledWith(
      expect.objectContaining({ acceptedQuotesFilter: "true" })
    );
  });

  it("each checkbox maps to its filter value", async () => {
    const element = await mount();
    const expectations = [
      ["hazmat", "hazmatFilter", "Hazmat"],
      ["marketTest", "priceDepFilter", "Market Test"],
      ["declined", "declinedQuotesFilter", "true"]
    ];
    for (const [name, param, value] of expectations) {
      const box = checkbox(element, name);
      box.checked = true;
      box.dispatchEvent(new CustomEvent("change"));
    }
    await flush();
    element.shadowRoot
      .querySelector('lightning-button[label="Apply Filters"]')
      .click();
    await flush();
    const args = getCarrierQuotes.mock.calls.at(-1)[0];
    expect(args.hazmatFilter).toBe("Hazmat");
    expect(args.priceDepFilter).toBe("Market Test");
    expect(args.declinedQuotesFilter).toBe("true");
  });

  it("reset restores defaults and reloads", async () => {
    const element = await mount();
    checkbox(element, "hazmat").checked = true;
    checkbox(element, "hazmat").dispatchEvent(new CustomEvent("change"));
    element.shadowRoot.querySelector('lightning-button[label="Reset"]').click();
    await flush();
    const args = getCarrierQuotes.mock.calls.at(-1)[0];
    expect(args).toMatchObject({
      hazmatFilter: "",
      dateRangeFilter: "5",
      acceptedQuotesFilter: ""
    });
  });

  it("shows the error block when Apex rejects", async () => {
    getCarrierQuotes.mockRejectedValue(new Error("boom"));
    const element = await mount();
    expect(
      element.shadowRoot.querySelectorAll("tbody tr[data-index]").length
    ).toBe(0);
    expect(element.shadowRoot.textContent).toMatch(/error/i);
  });
});
```

Before running, confirm the two button labels in `pricingDepartment.html` (lines 182 and 186). If they differ from `Apply Filters` and `Reset`, use the real labels in the test; do not rename the buttons.

- [ ] **Step 3: Run tests to verify they fail**

Run: `npx sfdx-lwc-jest -- force-app/main/default/lwc/pricingDepartment`
Expected: FAIL. `checkbox()` returns `null` (no `data-filter` attributes yet) and the accepted-checkbox test throws `ReferenceError: isAcceptedQuotesChecked is not defined`.

- [ ] **Step 4: Fix the component**

In `pricingDepartment.html`, add a `data-filter` attribute to each of the four `<input type="checkbox"` elements: line 106 block `data-filter="marketTest"`, line 124 block `data-filter="hazmat"`, line 142 block `data-filter="declined"`, line 160 block `data-filter="accepted"`.

In `pricingDepartment.js`:

Replace the four checkbox handlers with:

```javascript
handleHazmatFilterChange(event) {
    this.isHazmatChecked = event.target.checked;
    this.hazmatFilter = this.isHazmatChecked ? 'Hazmat' : '';
}

handlePriceDepFilterChange(event) {
    this.isPriceDepChecked = event.target.checked;
    this.priceDepFilter = this.isPriceDepChecked ? 'Market Test' : '';
}

handleAcceptedQuotesFilterChange(event) {
    this.isAcceptedQuotesChecked = event.target.checked;
    this.acceptedQuotesFilter = this.isAcceptedQuotesChecked ? 'true' : '';
}

handleDeclinedQuotesFilterChange(event) {
    this.isDeclinedQuotesChecked = event.target.checked;
    this.declinedQuotesFilter = this.isDeclinedQuotesChecked ? 'true' : '';
}
```

Delete the `fetchModeOptions` method and the now-unused `getUniqueModeOptions` import. Remove every remaining `console.log`. In `fetchCarrierQuotes`, replace `this.errors = 'No data found'` with `this.errors = { body: { message: 'No data found' } };` only if the template renders `errors.body.message`; otherwise leave it. Check the template block at line 451 and match it.

In `pricingDepartment.js-meta.xml` set `<apiVersion>64.0</apiVersion>`.

- [ ] **Step 5: Run all Jest and lint, verify pass**

Run: `npm run lint && npm test`
Expected: lint clean, Jest PASS (quoteStats 7 + pricingDepartment 6).

- [ ] **Step 6: Commit**

```bash
git add force-app/main/default/lwc
git commit -m "Fix accepted-quotes checkbox ReferenceError, drop dead code, add component tests"
```

---

### Task 9: Excluded contacts from custom metadata

**Files:**

- Create: `force-app/main/default/objects/Pricing_Department_Setting__mdt/Pricing_Department_Setting__mdt.object-meta.xml`
- Create: `force-app/main/default/objects/Pricing_Department_Setting__mdt/fields/Excluded_Contact_Ids__c.field-meta.xml`
- Create: `force-app/main/default/customMetadata/Pricing_Department_Setting.Default.md-meta.xml`
- Modify: `force-app/main/default/classes/PricingDepartmentController.cls`
- Modify: `force-app/main/default/classes/PricingDepartmentControllerTest.cls`
- Modify: `manifest/package.xml`

**Interfaces:**

- Consumes: `excludedContactIdsOverride` from Task 5.
- Produces: `Pricing_Department_Setting__mdt.Default.Excluded_Contact_Ids__c` = comma-separated Contact Ids (15 or 18 chars). `PricingDepartmentController.excludedContactIds()` returns both the 15- and 18-character form of each.

- [ ] **Step 1: Metadata files**

`Pricing_Department_Setting__mdt.object-meta.xml`:

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<CustomObject xmlns="http://soap.sforce.com/2006/04/metadata">
    <label>Pricing Department Setting</label>
    <pluralLabel>Pricing Department Settings</pluralLabel>
    <visibility>Public</visibility>
</CustomObject>
```

`fields/Excluded_Contact_Ids__c.field-meta.xml`:

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Excluded_Contact_Ids__c</fullName>
    <externalId>false</externalId>
    <fieldManageability>DeveloperControlled</fieldManageability>
    <inlineHelpText
  >Comma-separated Contact Ids whose carrier quotes are hidden from the Pricing Department page.</inlineHelpText>
    <label>Excluded Contact Ids</label>
    <length>255</length>
    <required>false</required>
    <type>Text</type>
    <unique>false</unique>
</CustomField>
```

`customMetadata/Pricing_Department_Setting.Default.md-meta.xml`:

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<CustomMetadata
  xmlns="http://soap.sforce.com/2006/04/metadata"
  xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
  xmlns:xsd="http://www.w3.org/2001/XMLSchema"
>
    <label>Default</label>
    <protected>false</protected>
    <values>
        <field>Excluded_Contact_Ids__c</field>
        <value xsi:type="xsd:string">0033l00002px9ja</value>
    </values>
</CustomMetadata>
```

Add to `manifest/package.xml`:

```xml
    <types>
        <members>Pricing_Department_Setting__mdt</members>
        <name>CustomObject</name>
    </types>
    <types>
        <members>Pricing_Department_Setting.Default</members>
        <name>CustomMetadata</name>
    </types>
```

and `<members>Pricing_Department_Setting__mdt.Excluded_Contact_Ids__c</members>` inside the existing `CustomField` type.

- [ ] **Step 2: Write the failing test**

Add to `PricingDepartmentControllerTest.cls`:

```apex
    @IsTest
    static void excludedContactIdsComeFromCustomMetadataInBothIdLengths() {
        PricingDepartmentController.excludedContactIdsOverride = null;
        Set<String> ids = PricingDepartmentController.excludedContactIds();
        List<Pricing_Department_Setting__mdt> settings = [SELECT Excluded_Contact_Ids__c FROM Pricing_Department_Setting__mdt WHERE DeveloperName = 'Default'];
        System.assertEquals(1, settings.size(), 'The Default setting record must be deployed');
        for (String raw : settings[0].Excluded_Contact_Ids__c.split(',')) {
            Id contactId = Id.valueOf(raw.trim());
            System.assert(ids.contains(String.valueOf(contactId)), '18-char form present');
            System.assert(ids.contains(String.valueOf(contactId).left(15)), '15-char form present');
        }
    }
```

This requires `excludedContactIds()` to be `@TestVisible`; make it so in the next step.

- [ ] **Step 3: Replace the hardcoded id in the controller**

Replace the block added in Task 5 with:

```apex
    // Test hook: tests set this to control exclusions because custom metadata cannot be inserted in tests.
    @TestVisible private static Set<String> excludedContactIdsOverride;

    /**
     * Contact Ids whose quotes are hidden, from Pricing_Department_Setting__mdt.Default.
     * Contact_ID__c is a formula returning the 15-character id, so both forms are included.
     */
    @TestVisible
    private static Set<String> excludedContactIds() {
        if (excludedContactIdsOverride != null) {
            return excludedContactIdsOverride;
        }
        Set<String> ids = new Set<String>();
        Pricing_Department_Setting__mdt setting = Pricing_Department_Setting__mdt.getInstance('Default');
        if (setting == null || String.isBlank(setting.Excluded_Contact_Ids__c)) {
            return ids;
        }
        for (String raw : setting.Excluded_Contact_Ids__c.split(',')) {
            String trimmed = raw.trim();
            if (trimmed.length() == 15 || trimmed.length() == 18) {
                Id contactId = Id.valueOf(trimmed);
                ids.add(String.valueOf(contactId));
                ids.add(String.valueOf(contactId).left(15));
            }
        }
        return ids;
    }
```

Also replace the class declaration line with:

```apex
/**
 * Data source for the Pricing Department page.
 * Runs WITHOUT SHARING on purpose: pricing must benchmark against every team's carrier quotes,
 * regardless of load ownership. Do not change to with sharing without a product decision.
 */
public without sharing class PricingDepartmentController {
```

- [ ] **Step 4: Deploy to DevPro and run the tests**

Run: `sf project deploy start -x manifest/package.xml --post-destructive-changes manifest/destructiveChangesPost.xml -o devpro -l RunSpecifiedTests -t PricingDepartmentControllerTest`
Expected: `Status: Succeeded`, 11 of 11 tests passing.

- [ ] **Step 5: Commit**

```bash
git add force-app/main/default/objects/Pricing_Department_Setting__mdt force-app/main/default/customMetadata force-app/main/default/classes manifest/package.xml
git commit -m "Read excluded contact ids from Pricing_Department_Setting custom metadata"
```

---

### Task 10: Permission set `Pricing_Department_User`

**Files:**

- Create: `force-app/main/default/permissionsets/Pricing_Department_User.permissionset-meta.xml`
- Modify: `manifest/package.xml`, `README.md`

**Interfaces:**

- Produces: a permission set granting the tab, the controller, and read on every field the page queries. Nothing else assigns or depends on it in phase 0.

- [ ] **Step 1: Generate the field list from the controller, not by hand**

Run:

```bash
python3 - <<'EOF'
import re
src=open('force-app/main/default/classes/PricingDepartmentController.cls').read()
select=re.search(r'SELECT(.*?)FROM rtms__CarrierQuote__c', src, re.S).group(1)
fields=sorted({f.strip() for f in select.split(',') if f.strip() and '.' not in f and f.strip() not in ('Id','Name','CurrencyIsoCode')})
for f in fields:
    print(f"""    <fieldPermissions>
        <editable>false</editable>
        <field>rtms__CarrierQuote__c.{f}</field>
        <readable>true</readable>
    </fieldPermissions>""")
EOF
```

Expected: 29 `fieldPermissions` blocks (formula fields included; Salesforce accepts read permissions on formulas and ignores editable).

- [ ] **Step 2: Write the permission set**

`Pricing_Department_User.permissionset-meta.xml`, pasting the generated blocks where marked:

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<PermissionSet xmlns="http://soap.sforce.com/2006/04/metadata">
    <label>Pricing Department User</label>
    <description
  >Grants everything needed to use the Pricing Department page. Assign this instead of editing profiles.</description>
    <hasActivationRequired>false</hasActivationRequired>
    <classAccesses>
        <apexClass>PricingDepartmentController</apexClass>
        <enabled>true</enabled>
    </classAccesses>
    <objectPermissions>
        <allowCreate>false</allowCreate>
        <allowDelete>false</allowDelete>
        <allowEdit>false</allowEdit>
        <allowRead>true</allowRead>
        <modifyAllRecords>false</modifyAllRecords>
        <object>rtms__CarrierQuote__c</object>
        <viewAllRecords>false</viewAllRecords>
    </objectPermissions>
    <!-- paste generated fieldPermissions blocks here -->
    <tabSettings>
        <tab>Pricing_Department</tab>
        <visibility>Visible</visibility>
    </tabSettings>
</PermissionSet>
```

Add `<types><members>Pricing_Department_User</members><name>PermissionSet</name></types>` to `manifest/package.xml`.

- [ ] **Step 3: Deploy and verify field access through the API**

Run: `sf project deploy start -m PermissionSet:Pricing_Department_User -o devpro -l NoTestRun`
Expected: `Status: Succeeded`. If it fails on a specific field ("field not found" or "cannot set permissions on required field"), delete that block and note the field in the README.

Assign to yourself in DevPro and prove the `Quote_Date__c` gap is closed:

```bash
sf org assign permset -n Pricing_Department_User -o devpro
sf data query -q "SELECT Id, Quote_Date__c FROM rtms__CarrierQuote__c LIMIT 1" -o devpro
```

Expected: the query runs without "No such column" (0 rows is fine; DevPro has no data).

- [ ] **Step 4: README and commit**

Replace the Security row of the README table with:

```markdown
| Security | `permissionsets/Pricing_Department_User` | The way to grant access from now on: tab, Apex class, read on every field the page uses. `profiles/Pricing` is kept for reference and never deployed |
```

Delete the "Known issues" bullet about `Quote_Date__c` field-level security.

```bash
git add force-app/main/default/permissionsets manifest/package.xml README.md
git commit -m "Add Pricing_Department_User permission set covering tab, Apex and field read access"
```

---

### Task 11: Bug-fix pull request through CI, deploy to DevPro

**Files:**

- Modify: `README.md` (final known-issues cleanup)

**Interfaces:**

- Consumes: everything from Tasks 8-10 on `phase-0/bug-fixes`.

- [ ] **Step 1: Final README cleanup**

In "Known issues worth fixing" delete the bullets about the ReferenceError, `fetchModeOptions`, and the API version. Keep the bullets about `LIKE` filters and Apex-side dedupe; they are phase 2's problem. Rename the hardcoded-contact bullet to state it now lives in custom metadata.

```bash
git add README.md
git commit -m "README: reflect phase 0 fixes"
```

- [ ] **Step 2: Push and open the pull request in both repos**

```bash
git push -u origin phase-0/bug-fixes
WT=$(gh auth token -u IulianEnescu) && git -c credential.helper= -c "credential.helper=!f() { echo username=IulianEnescu; echo password=$WT; }; f" push -u tplm phase-0/bug-fixes
gh pr create -R IulianEnescu78/PricingDepartment --base main --head phase-0/bug-fixes \
  --title "Phase 0: fix known bugs, custom metadata exclusions, permission set" \
  --body "Tasks 8-11 of docs/superpowers/plans/2026-09-07-phase-0-engineering-hygiene.md. First change gated by CI."
GH_TOKEN=$(gh auth token -u IulianEnescu) gh pr create -R TPLM/PricingDepartment --base main --head phase-0/bug-fixes \
  --title "Phase 0: fix known bugs, custom metadata exclusions, permission set" \
  --body "Tasks 8-11 of docs/superpowers/plans/2026-09-07-phase-0-engineering-hygiene.md. First change gated by CI."
```

- [ ] **Step 3: Wait for green in both repos**

Run: `gh pr checks -R IulianEnescu78/PricingDepartment phase-0/bug-fixes --watch` and the same with the TPLM token.
Expected: `lwc`, `apex`, `pmd` all pass in both. A failure is fixed on the branch and pushed to both remotes; never merged red.

- [ ] **Step 4: Merge, mirror, deploy to DevPro**

```bash
gh pr merge -R IulianEnescu78/PricingDepartment phase-0/bug-fixes --merge --delete-branch
git checkout main && git pull origin main
WT=$(gh auth token -u IulianEnescu) && git -c credential.helper= -c "credential.helper=!f() { echo username=IulianEnescu; echo password=$WT; }; f" push tplm main
sf project deploy start -x manifest/package.xml --post-destructive-changes manifest/destructiveChangesPost.xml -o devpro -l RunSpecifiedTests -t PricingDepartmentControllerTest
```

Expected: deploy `Succeeded`, 11 tests passing. Check the TPLM PR shows as merged; if it is still open because GitHub did not detect the merge commit, merge it there too (`--merge`), which is a no-op on content.

- [ ] **Step 5: Verify the definition of done**

Check each item and record the result in the phase 0 spec under a new `## Outcome` heading with the date:

1. `sf org display -o devpro` connected; `diff` from Task 1 resolved.
2. `npm ci` clean; `.husky/_` exists; `package-lock.json` committed.
3. Last CI runs on `main` green in both repos; branch protection status (on, or unavailable on plan).
4. `sf data query -t -q "SELECT Name FROM ApexClass WHERE Name LIKE 'Pricing%'" -o devpro` lists exactly `PricingDepartmentController`, `PricingDepartmentControllerTest`, `PricingTestDataFactory`; `npm test` passes.
5. Bug-fix PR merged; DevPro deploy succeeded; nothing deployed to `sandbox` or `vscodeOrg`.
6. README has the environment table, runbook, and CI section.

Commit the outcome note directly on `main` if protection is off, otherwise through a one-line PR.

---

## Self-review

**Spec coverage.** Environments and runbook: Task 1 and the prerequisite. Repository and tooling (toolchain, lockfile, Husky, forceignore profiles, project rename, docs convention): Task 2; docs folders already exist. CI three jobs, secret in both repos, branch protection, concurrency: Task 7. Tests (retire old classes, factory, behavior tests, quoteStats extraction, component tests): Tasks 3, 4, 5, 6, 8. Bug-fix PR (handler, dead code, API version, custom metadata, without-sharing comment, permission set): Tasks 8, 9, 10, 11. Definition of done: Task 11 Step 5. Deviation recorded: PMD gate via CLI log instead of annotations (Task 7).

**Placeholders.** None. The only genuinely unknown work, which trigger requirements the factory must satisfy, is expressed as an explicit discovery loop with a stop condition (Task 4 Step 3) rather than "handle errors".

**Type consistency.** `PricingTestDataFactory.Graph` fields and the three static methods are used identically in Tasks 4, 5, 9. `excludedContactIdsOverride` (Task 5) is the same name Task 9 keeps. `calculateStats` / `shapeRows` / `modeOptionsFrom` (Task 3) match the import in Task 3 Step 5 and the behaviors asserted in Task 8. Test class name `PricingDepartmentControllerTest` matches the CI `--tests` flag and every deploy command. Checkbox `data-filter` values in Task 8 Step 2 match Step 4.
