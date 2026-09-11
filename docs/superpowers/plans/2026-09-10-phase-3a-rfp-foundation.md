# Phase 3a: RFP Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create the RFP data model (project, lane, bid), the bid service that writes searchable lane keys, and make bids a filterable second source in Lane Benchmark, plus a customer-Account component listing RFP projects.

**Architecture:** Three custom objects. `BenchmarkRateService` copies the lane keys (city lane, state lane, zip3 lane, geolocations) from the lane's resolved `Pricing_Place__c` records onto each bid so `BidSearchQueryBuilder` can query bids with the same precision semantics as `LaneSearchQueryBuilder` queries Loads. `BidSearchService` runs that query and merges bid rows into `LaneSearchResult.rows`; `LaneSearchService` only calls it. The Lane Benchmark filters gain a Source control; results render bid rows with a badge. `RfpController.projectsForAccount` feeds `rfpProjectsForAccount` on customer Account pages.

**Tech Stack:** Salesforce DX (API 64.0), Apex, LWC, Jest (`@salesforce/sfdx-lwc-jest`), ESLint (`@salesforce/eslint-config-lwc/recommended`), Prettier, PMD 7.15.0 quickstart P3, PostProduc sandbox (alias `sandbox`).

**Spec:** `docs/superpowers/specs/2026-09-10-phase-3-rfp-tool-design.md` (section "Implementation split", plan 3a).

## Global Constraints

- Only org alias `sandbox` (PostProduc). Never `vscodeOrg`, `Full`, `devpro`.
- Every deploy passes every test class with `-t`. The list at the start of this plan: `PricingDepartmentControllerTest PlaceNormalizerTest PricingTestDataFactoryTest PlaceBuilderBatchTest LaneSearchServiceTest MapboxGeocoderTest LaneBenchmarkControllerTest LaneBenchmarkPlaceServiceTest`. Each task that adds a test class appends it to this list, to `.github/workflows/ci.yml` (`--tests` line), and to both README lists (`sf apex run test -n ...` and `sf project deploy start ... -t ...`) in the same commit.
- Deploy in the foreground: `sf project deploy start -x manifest/package.xml -o sandbox -l RunSpecifiedTests -t <list> -w 30`. For Task 1 run `sf project deploy validate` with the same arguments first.
- PMD: `/private/tmp/pmd_install/pmd-bin-7.15.0/bin/pmd check --dir force-app --rulesets config/pmd-ruleset.xml --minimum-priority 3 --format text --fail-on-violation` must exit 0 before every commit. Per-method cyclomatic ≤ 10, class total ≤ 40, `TooManyFields` ≤ 20: split classes, never suppress.
- Jest: `npm test`; lint: `npm run lint`; format: `npx prettier --check <files>`. The pre-commit hook must pass; never `--no-verify`.
- Commit messages carry no trailers (no Co-Authored-By, no Signed-off-by).
- `@api` values mutated internally use get/set backing fields (`@lwc/lwc/no-api-reassignments`). Base-component text is never asserted through `textContent`.
- RFP Apex (`RfpController`, `BenchmarkRateService`) runs in user mode (`WITH USER_MODE`, `Database.insert(records, AccessLevel.USER_MODE)`); the phase 1 search stays system mode by documented design. All SOQL is bound; no user text is concatenated into a query.
- No secrets. The Mapbox token stays in the custom setting.
- Implementers do not call the advisor tool and do not dispatch subagents.

## Rulings that amend the spec (recorded here, ledgered by the controller)

1. `LaneSearchRequest` field is `sourceFilter` of enum `RowSource { ALL, LOADS, BIDS }`, not `source` of enum `Source` (a field named like its enum type fails to compile, as `acceptedFilter` proved). If the compiler rejects `ALL` as reserved, rename the value to `ALL_SOURCES` in the enum, the LWC and the tests, and report it.
2. `LaneSearchResult.Row` is at 19 fields against a `TooManyFields` limit of 20. The bid attributes live in ONE nested `@AuraEnabled public BidDetail bid` (null for loads): `rateId`, `expiresOn`, `status`, `transitDays`, `fuelSurcharge`, `fscIncluded`. The LWC derives "is a bid" from `bid != null`.
3. `Benchmark_Rate__c` gains `Equipment_Category__c` Text(40), copied from the lane, so the equipment-category filter applies to bids.
4. For bids, `marketTestOnly = true`, `acceptedFilter = ACCEPTED` and `acceptedFilter = DECLINED` return no bids (those concepts do not exist on a bid).
5. `RfpController` is created in 3a with `projectsForAccount` only; 3b extends it.
6. No Account FlexiPage is edited (the org has 30 Account record pages). `rfpProjectsForAccount` is exposed to `lightning__RecordPage` for `Account`, renders nothing unless the record type is `Customer` or `New_Customer`, and the admin adds it in App Builder to the page pricing uses. That manual step is recorded in the spec Outcome.
7. Roll-ups on `RFP_Project__c` filter on checkbox formulas `Has_Cost__c` / `Has_Sell__c` (`NOT(ISBLANK(...))`) rather than on "field not blank" criteria.
8. Bid rows never dedupe (their fingerprint includes the bid Id). `truncated` is true if the quote query or the bid query hit its limit, or the merged list exceeded `rowLimit`.
9. Bid lane keys are built from the lane's resolved places (`Origin_Place__r`, `Destination_Place__r`: `City__c`, `Province__c`, `Postal_Prefix__c`, geolocation), never from spreadsheet text, so CITY precision matches through `PlaceNormalizer.cityLaneVariants`.

> **Defects found in this plan's verbatim code during execution:**
>
> - Task 1's field generator emitted a `<summarizedField>` on a COUNT roll-up; Salesforce rejects it ("bad value for restricted picklist field: Id"). Fixed to omit the element entirely for `summaryOperation = count`.
> - Task 5's brief named the merge method `BidSearchService.merge`, but `MERGE` is a reserved Apex identifier; the method is `mergeRows`.
> - Task 5's brief always ran the quote query; with `sourceFilter = BIDS` it must be skipped entirely, since `LaneSearchQueryBuilder` has no `RowSource` concept.
> - Task 4's `BidSearchQueryBuilderTest.filtersAndSourceRules` asserted `!soql.contains('Expires_On__c')`, which can never pass against the required `SELECT_CLAUSE`; narrowed to `!soql.contains('Expires_On__c >= TODAY')`.
> - Task 5's `BidSearchServiceTest` hard-coded an Id literal, which PMD's `AvoidHardcodingId` flags; replaced with a `mockRateId()` helper.
> - Task 1's field generator set `formulaTreatBlanksAs = BlankAsZero` on every formula, including the checkbox formulas `Has_Cost__c`/`Has_Sell__c`, which makes `NOT(ISBLANK(...))` always true; fixed to `BlankAsBlank`.
> - Task 1's generated `fieldPermissions` for `RFP_Tool_User` omitted every Summary and formula field of the three objects and every `Pricing_Place__c` field; `WITH USER_MODE` queries need explicit read access on those too.
> - Task 1's field-count note: the generator's actual output is 10/42/35 (`RFP_Project__c`/`RFP_Lane__c`/`Benchmark_Rate__c`), not the 10/40/37 this plan's self-review table states.
> - Generator `BlankAsZero` regression: Task 7 hand-patched `Has_Cost__c`/`Has_Sell__c` to `formulaTreatBlanksAs = BlankAsBlank` in the committed metadata, but never updated the generator's `formula()`, which still hardcoded `BlankAsZero`; a re-run would have silently regressed both fields. Fixed in the final review fix wave by giving `formula()` a `blanks` parameter.
> - No trigger for record-page bids: through Task 8, only `BenchmarkRateService.save()` stamped lane keys/geolocations/project/mode, so a bid created or edited directly on the `Benchmark_Rate__c` record page (never going through `save()`) kept blank lane keys and never matched a Lane Benchmark search — the spec's 3a exit criterion ("a bid created through the record page already appears in Lane Benchmark") was not actually met. Fixed in the final review fix wave by moving that stamping into `BenchmarkRateTrigger` (before insert/update), which runs regardless of how the bid was created.

---

## File structure

| Path                                                                                        | Responsibility                                                                 |
| ------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------ |
| `force-app/main/default/objects/RFP_Project__c/**`                                          | Project object, fields, roll-ups                                               |
| `force-app/main/default/objects/RFP_Lane__c/**`                                             | Lane object (master-detail), fields, `Has_Cost__c`/`Has_Sell__c` formulas      |
| `force-app/main/default/objects/Benchmark_Rate__c/**`                                       | Bid object, fields, `Status__c`/`Carrier_Display__c` formulas, validation rule |
| `force-app/main/default/permissionsets/RFP_Tool_User.permissionset-meta.xml`                | Pricing team access                                                            |
| `force-app/main/default/permissionsets/Lane_Benchmark_User.permissionset-meta.xml` (modify) | Read on `Benchmark_Rate__c`                                                    |
| `force-app/main/default/classes/RfpTestDataFactory.cls` (+Test)                             | Builders for project, lane, bid, place                                         |
| `force-app/main/default/classes/BenchmarkRateService.cls` (+Test)                           | Save bids in user mode; copy lane keys                                         |
| `force-app/main/default/classes/LaneSearchRequest.cls` (modify)                             | `sourceFilter` + default                                                       |
| `force-app/main/default/classes/LaneSearchResult.cls` (modify)                              | `Row.bid` (`BidDetail`)                                                        |
| `force-app/main/default/classes/BidSearchQueryBuilder.cls` (+Test)                          | SOQL for bids by precision and filters                                         |
| `force-app/main/default/classes/BidSearchService.cls` (+Test)                               | Run the bid query, convert to rows, merge with quote rows                      |
| `force-app/main/default/classes/LaneSearchService.cls` (modify)                             | Rows-based collect, calls `BidSearchService`                                   |
| `force-app/main/default/classes/RfpController.cls` (+Test)                                  | `projectsForAccount`                                                           |
| `force-app/main/default/lwc/laneBenchmarkFilters/**` (modify)                               | Source radio group                                                             |
| `force-app/main/default/lwc/laneBenchmarkResults/**` (modify)                               | Bid badge, expiry, CSV Source column                                           |
| `force-app/main/default/lwc/laneBenchmark/**` (modify)                                      | `sourceFilter` in the service request                                          |
| `force-app/main/default/lwc/rfpProjectsForAccount/**`                                       | Account page component                                                         |
| `manifest/package.xml`, `.github/workflows/ci.yml`, `README.md`, spec Outcome               | Registration and docs                                                          |

---

### Task 1: Objects, fields, validation rule, permission sets

**Files:**

- Create: `force-app/main/default/objects/RFP_Project__c/RFP_Project__c.object-meta.xml` and `fields/*.field-meta.xml`
- Create: `force-app/main/default/objects/RFP_Lane__c/RFP_Lane__c.object-meta.xml` and `fields/*.field-meta.xml`
- Create: `force-app/main/default/objects/Benchmark_Rate__c/Benchmark_Rate__c.object-meta.xml`, `fields/*.field-meta.xml`, `validationRules/Carrier_Or_Name_Required.validationRule-meta.xml`
- Create: `force-app/main/default/permissionsets/RFP_Tool_User.permissionset-meta.xml`
- Modify: `force-app/main/default/permissionsets/Lane_Benchmark_User.permissionset-meta.xml`
- Modify: `manifest/package.xml`
- Create: `scripts/metadata/gen_rfp_fields.py` (generator, committed so the field list stays reproducible)

**Interfaces:**

- Produces: the three objects with the exact API names below; every later task depends on them.

- [ ] **Step 1: Branch**

```bash
git checkout main && git pull origin main && git checkout -b phase-3a/foundation
```

- [ ] **Step 2: Object files**

`force-app/main/default/objects/RFP_Project__c/RFP_Project__c.object-meta.xml`:

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<CustomObject xmlns="http://soap.sforce.com/2006/04/metadata">
    <label>RFP Project</label>
    <pluralLabel>RFP Projects</pluralLabel>
    <nameField>
        <label>Project name</label>
        <type>Text</type>
    </nameField>
    <deploymentStatus>Deployed</deploymentStatus>
    <sharingModel>ReadWrite</sharingModel>
    <enableActivities>false</enableActivities>
    <enableHistory>false</enableHistory>
    <enableReports>true</enableReports>
    <enableSearch>true</enableSearch>
    <description
  >One customer RFP: the uploaded lane file, its lanes, bids and prices. Phase 3 of the Pricing Department project.</description>
</CustomObject>
```

`force-app/main/default/objects/RFP_Lane__c/RFP_Lane__c.object-meta.xml`:

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<CustomObject xmlns="http://soap.sforce.com/2006/04/metadata">
    <label>RFP Lane</label>
    <pluralLabel>RFP Lanes</pluralLabel>
    <nameField>
        <label>Lane number</label>
        <type>AutoNumber</type>
        <displayFormat>L-{000000}</displayFormat>
    </nameField>
    <deploymentStatus>Deployed</deploymentStatus>
    <sharingModel>ControlledByParent</sharingModel>
    <enableActivities>false</enableActivities>
    <enableHistory>false</enableHistory>
    <enableReports>true</enableReports>
    <enableSearch>false</enableSearch>
    <description
  >One spreadsheet row of an RFP Project: the lane as the customer wrote it, the resolved places, the history snapshot and the chosen cost/sell.</description>
</CustomObject>
```

`force-app/main/default/objects/Benchmark_Rate__c/Benchmark_Rate__c.object-meta.xml`:

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<CustomObject xmlns="http://soap.sforce.com/2006/04/metadata">
    <label>Benchmark Rate</label>
    <pluralLabel>Benchmark Rates</pluralLabel>
    <nameField>
        <label>Bid number</label>
        <type>AutoNumber</type>
        <displayFormat>B-{000000}</displayFormat>
    </nameField>
    <deploymentStatus>Deployed</deploymentStatus>
    <sharingModel>ReadWrite</sharingModel>
    <enableActivities>false</enableActivities>
    <enableHistory>false</enableHistory>
    <enableReports>true</enableReports>
    <enableSearch>true</enableSearch>
    <description
  >A carrier bid for a lane, captured without a Load. Lane keys are copied from the lane's places so Lane Benchmark can search bids at every precision.</description>
</CustomObject>
```

- [ ] **Step 3: Field generator**

Create `scripts/metadata/gen_rfp_fields.py` and run it from the repo root (`python3 scripts/metadata/gen_rfp_fields.py`). It writes every field file listed; re-running overwrites the same files.

```python
#!/usr/bin/env python3
"""Writes the RFP_Project__c / RFP_Lane__c / Benchmark_Rate__c field metadata (phase 3a)."""
import os

ROOT = "force-app/main/default/objects"

def w(obj, name, body):
    d = os.path.join(ROOT, obj, "fields")
    os.makedirs(d, exist_ok=True)
    with open(os.path.join(d, f"{name}.field-meta.xml"), "w") as f:
        f.write('<?xml version="1.0" encoding="UTF-8" ?>\n'
                '<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">\n'
                f"    <fullName>{name}</fullName>\n{body}</CustomField>\n")

def text(obj, name, label, length, help=None, required=False):
    h = f"    <inlineHelpText>{help}</inlineHelpText>\n" if help else ""
    w(obj, name, f"    <label>{label}</label>\n    <type>Text</type>\n    <length>{length}</length>\n"
                 f"    <required>{'true' if required else 'false'}</required>\n{h}")

def longtext(obj, name, label, length=32768, lines=5):
    w(obj, name, f"    <label>{label}</label>\n    <type>LongTextArea</type>\n    <length>{length}</length>\n"
                 f"    <visibleLines>{lines}</visibleLines>\n")

def number(obj, name, label, precision, scale):
    w(obj, name, f"    <label>{label}</label>\n    <type>Number</type>\n    <precision>{precision}</precision>\n"
                 f"    <scale>{scale}</scale>\n    <required>false</required>\n    <unique>false</unique>\n")

def currency(obj, name, label, required=False):
    w(obj, name, f"    <label>{label}</label>\n    <type>Currency</type>\n    <precision>16</precision>\n"
                 f"    <scale>2</scale>\n    <required>{'true' if required else 'false'}</required>\n")

def percent(obj, name, label, default=None):
    d = f"    <defaultValue>{default}</defaultValue>\n" if default is not None else ""
    w(obj, name, f"    <label>{label}</label>\n    <type>Percent</type>\n    <precision>5</precision>\n"
                 f"    <scale>2</scale>\n    <required>false</required>\n{d}")

def checkbox(obj, name, label, default=False):
    w(obj, name, f"    <label>{label}</label>\n    <type>Checkbox</type>\n"
                 f"    <defaultValue>{'true' if default else 'false'}</defaultValue>\n")

def date(obj, name, label):
    w(obj, name, f"    <label>{label}</label>\n    <type>Date</type>\n    <required>false</required>\n")

def datetime_(obj, name, label):
    w(obj, name, f"    <label>{label}</label>\n    <type>DateTime</type>\n    <required>false</required>\n")

def email(obj, name, label):
    w(obj, name, f"    <label>{label}</label>\n    <type>Email</type>\n    <required>false</required>\n    <unique>false</unique>\n")

def phone(obj, name, label):
    w(obj, name, f"    <label>{label}</label>\n    <type>Phone</type>\n    <required>false</required>\n")

def location(obj, name, label):
    w(obj, name, f"    <label>{label}</label>\n    <type>Location</type>\n"
                 f"    <displayLocationInDecimal>true</displayLocationInDecimal>\n    <scale>6</scale>\n    <required>false</required>\n")

def picklist(obj, name, label, values, default_first=True):
    vals = "".join(
        f"            <value><fullName>{v}</fullName><default>{'true' if (i == 0 and default_first) else 'false'}</default><label>{v}</label></value>\n"
        for i, v in enumerate(values))
    w(obj, name, f"    <label>{label}</label>\n    <type>Picklist</type>\n    <required>false</required>\n"
                 f"    <valueSet>\n        <restricted>true</restricted>\n        <valueSetDefinition>\n            <sorted>false</sorted>\n{vals}"
                 f"        </valueSetDefinition>\n    </valueSet>\n")

def lookup(obj, name, label, target, relname, rellabel, filter_xml="", delete="SetNull"):
    w(obj, name, f"    <label>{label}</label>\n    <type>Lookup</type>\n    <referenceTo>{target}</referenceTo>\n"
                 f"    <relationshipName>{relname}</relationshipName>\n    <relationshipLabel>{rellabel}</relationshipLabel>\n"
                 f"    <deleteConstraint>{delete}</deleteConstraint>\n    <required>false</required>\n{filter_xml}")

def master_detail(obj, name, label, target, relname, rellabel):
    w(obj, name, f"    <label>{label}</label>\n    <type>MasterDetail</type>\n    <referenceTo>{target}</referenceTo>\n"
                 f"    <relationshipName>{relname}</relationshipName>\n    <relationshipLabel>{rellabel}</relationshipLabel>\n"
                 f"    <relationshipOrder>0</relationshipOrder>\n    <reparentableMasterDetail>false</reparentableMasterDetail>\n"
                 f"    <writeRequiresMasterRead>false</writeRequiresMasterRead>\n")

def formula(obj, name, label, ftype, expr, extra=""):
    w(obj, name, f"    <label>{label}</label>\n    <type>{ftype}</type>\n    <formula>{expr}</formula>\n"
                 f"    <formulaTreatBlanksAs>BlankAsZero</formulaTreatBlanksAs>\n{extra}")

def rollup(obj, name, label, child_obj, child_field, relname, filter_field=None):
    flt = (f"    <summaryFilterItems>\n        <field>{filter_field}</field>\n        <operation>equals</operation>\n"
           f"        <value>True</value>\n    </summaryFilterItems>\n") if filter_field else ""
    w(obj, name, f"    <label>{label}</label>\n    <type>Summary</type>\n    <summarizedField>{child_field}</summarizedField>\n"
                 f"    <summaryForeignKey>{child_obj}.{relname}</summaryForeignKey>\n    <summaryOperation>count</summaryOperation>\n{flt}")

def record_type_filter(obj_label, names):
    return ("    <lookupFilter>\n        <active>true</active>\n"
            f"        <errorMessage>Choose a {obj_label} account.</errorMessage>\n"
            "        <filterItems>\n            <field>Account.RecordType.DeveloperName</field>\n"
            f"            <operation>equals</operation>\n            <value>{names}</value>\n        </filterItems>\n"
            "        <isOptional>false</isOptional>\n    </lookupFilter>\n")

P, L, B = "RFP_Project__c", "RFP_Lane__c", "Benchmark_Rate__c"

# ---- RFP_Project__c
lookup(P, "Customer__c", "Customer", "Account", "RFP_Projects", "RFP Projects",
       record_type_filter("customer", "Customer, New_Customer"))
picklist(P, "Status__c", "Status", ["Draft", "Pricing", "Sent", "Awarded", "Lost"])
date(P, "Due_Date__c", "Due date")
percent(P, "Default_Margin__c", "Default margin %", default="15")
longtext(P, "Column_Mapping__c", "Column mapping (JSON)")
text(P, "Source_File_Name__c", "Source file name", 255)
longtext(P, "Notes__c", "Notes")
rollup(P, "Lane_Count__c", "Lanes", L, f"{L}.Id", "RFP_Project__c")
rollup(P, "Costed_Count__c", "Lanes with a cost", L, f"{L}.Id", "RFP_Project__c", f"{L}.Has_Cost__c")
rollup(P, "Sold_Count__c", "Lanes with a sell price", L, f"{L}.Id", "RFP_Project__c", f"{L}.Has_Sell__c")

# ---- RFP_Lane__c
master_detail(L, "RFP_Project__c", "RFP Project", P, "RFP_Lanes", "RFP Lanes")
number(L, "Row_Number__c", "Row number", 6, 0)
longtext(L, "Raw_Row__c", "Original row (JSON)")
for side in ("Origin", "Destination"):
    text(L, f"{side}_City__c", f"{side} city", 80)
    text(L, f"{side}_Province__c", f"{side} province/state", 80)
    text(L, f"{side}_Country__c", f"{side} country", 2)
    text(L, f"{side}_Postal__c", f"{side} postal", 12)
    lookup(L, f"{side}_Place__c", f"{side} place", "Pricing_Place__c", f"RFP_Lanes_{side}", f"RFP Lanes ({side})")
    checkbox(L, f"{side}_Resolved__c", f"{side} resolved")
text(L, "Mode__c", "Mode", 40)
text(L, "Equipment_Category__c", "Equipment category", 40)
text(L, "Equipment_Type__c", "Equipment type", 80)
text(L, "Commodity__c", "Commodity", 255)
number(L, "Quantity__c", "Quantity", 12, 2)
text(L, "Quantity_Unit__c", "Quantity unit", 20)
number(L, "Shipments_Per_Year__c", "Shipments per year", 8, 0)
checkbox(L, "Hazmat__c", "Hazmat")
number(L, "Customer_Fuel_Surcharge__c", "Customer fuel surcharge", 10, 2)
checkbox(L, "Customer_FSC_Included__c", "Customer FSC included")
number(L, "Hist_Count__c", "History count", 8, 0)
for n, lab in (("Hist_Min__c", "History min"), ("Hist_Median__c", "History median"),
               ("Hist_Average__c", "History average"), ("Hist_Max__c", "History max")):
    currency(L, n, lab)
text(L, "Hist_Precision__c", "History precision", 20, help="CITY, PROVINCE or RADIUS-50KM")
number(L, "Hist_Lookback_Days__c", "History lookback (days)", 5, 0)
datetime_(L, "Hist_As_Of__c", "History as of")
picklist(L, "Hist_Status__c", "History status", ["Pending", "Done", "Failed", "No match", "Unresolved"])
currency(L, "Cost__c", "Cost")
picklist(L, "Cost_Source__c", "Cost source", ["Bid", "History median", "Manual"], default_first=False)
lookup(L, "Selected_Bid__c", "Selected bid", B, "Selected_For_Lanes", "Selected for lanes")
percent(L, "Margin__c", "Margin %")
currency(L, "Sell__c", "Sell")
longtext(L, "Notes__c", "Notes", 4000, 3)
formula(L, "Has_Cost__c", "Has cost", "Checkbox", "NOT(ISBLANK(Cost__c))")
formula(L, "Has_Sell__c", "Has sell", "Checkbox", "NOT(ISBLANK(Sell__c))")

# ---- Benchmark_Rate__c
lookup(B, "RFP_Lane__c", "RFP Lane", L, "Benchmark_Rates", "Benchmark Rates")
lookup(B, "RFP_Project__c", "RFP Project", P, "Benchmark_Rates", "Benchmark Rates")
lookup(B, "Carrier__c", "Carrier", "Account", "Benchmark_Rates", "Benchmark Rates",
       record_type_filter("carrier", "Carrier, New_Carrier"))
text(B, "Carrier_Name__c", "Carrier name (not in the system)", 255)
text(B, "Contact_Name__c", "Contact name", 120)
email(B, "Contact_Email__c", "Contact email")
phone(B, "Contact_Phone__c", "Contact phone")
formula(B, "Carrier_Display__c", "Carrier", "Text",
        "IF(ISBLANK(Carrier__c), Carrier_Name__c, Carrier__r.Name)")
currency(B, "Rate__c", "Rate", required=True)
currency(B, "Fuel_Surcharge__c", "Fuel surcharge")
checkbox(B, "FSC_Included__c", "FSC included")
number(B, "Transit_Days__c", "Transit days", 3, 0)
date(B, "Valid_From__c", "Valid from")
date(B, "Expires_On__c", "Expires on")
formula(B, "Status__c", "Status", "Text", 'IF(Expires_On__c < TODAY(), "Expired", "Active")')
longtext(B, "Notes__c", "Notes", 4000, 3)
text(B, "Mode__c", "Mode", 40)
text(B, "Equipment_Category__c", "Equipment category", 40)
text(B, "Equipment_Type__c", "Equipment type", 80)
checkbox(B, "Hazmat__c", "Hazmat")
for side in ("Origin", "Destination"):
    text(B, f"{side}_City__c", f"{side} city", 80)
    text(B, f"{side}_Province__c", f"{side} province/state", 80)
    text(B, f"{side}_Country__c", f"{side} country", 2)
    text(B, f"{side}_Postal__c", f"{side} postal", 12)
    lookup(B, f"{side}_Place__c", f"{side} place", "Pricing_Place__c", f"Benchmark_Rates_{side}", f"Benchmark Rates ({side})")
    location(B, f"{side}_Geolocation__c", f"{side} geolocation")
text(B, "City_Lane__c", "City lane", 255, help='"City, ST:City, ST", as Revenova writes rtms__City_Lane__c')
text(B, "State_Lane__c", "State lane", 20, help='"ST:ST"')
text(B, "Zip3_Lane__c", "Zip3 lane", 20, help='"H7P:L1J"')
print("done")
```

Validation rule `force-app/main/default/objects/Benchmark_Rate__c/validationRules/Carrier_Or_Name_Required.validationRule-meta.xml`:

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<ValidationRule xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Carrier_Or_Name_Required</fullName>
    <active>true</active>
    <description
  >A bid names a carrier: an existing Account or a free-text carrier name.</description>
    <errorConditionFormula
  >ISBLANK(Carrier__c) &amp;&amp; ISBLANK(Carrier_Name__c)</errorConditionFormula>
    <errorMessage
  >Pick a carrier account or enter the carrier name.</errorMessage>
</ValidationRule>
```

Run `npx prettier --write "force-app/main/default/objects/RFP_Project__c/**" "force-app/main/default/objects/RFP_Lane__c/**" "force-app/main/default/objects/Benchmark_Rate__c/**"`.

- [ ] **Step 4: Permission sets**

`force-app/main/default/permissionsets/RFP_Tool_User.permissionset-meta.xml` — object permissions create/read/edit (no delete, no modifyAll; `viewAllRecords` false) on `RFP_Project__c`, `RFP_Lane__c`, `Benchmark_Rate__c`; read on `Pricing_Place__c` (`viewAllRecords` true) and `Account`; classAccesses `RfpController`, `BenchmarkRateService`, `LaneBenchmarkController`, `LaneBenchmarkPlaceService`, `LaneSearchService`, `MapboxGeocoder`; fieldPermissions for every field the generator wrote that is not required, not a formula, not a roll-up and not a master-detail (editable true, readable true). Generate that block with:

```bash
python3 - <<'EOF'
import glob, re, os
out=[]
for obj in ("RFP_Project__c","RFP_Lane__c","Benchmark_Rate__c"):
    for p in sorted(glob.glob(f"force-app/main/default/objects/{obj}/fields/*.field-meta.xml")):
        s=open(p).read()
        if "<required>true</required>" in s or "<type>MasterDetail</type>" in s or "<formula>" in s or "<type>Summary</type>" in s:
            continue
        name=os.path.basename(p).replace(".field-meta.xml","")
        out.append(f"    <fieldPermissions>\n        <editable>true</editable>\n        <field>{obj}.{name}</field>\n        <readable>true</readable>\n    </fieldPermissions>")
print("\n".join(out))
EOF
```

Header of the file (copy the element order used by `Lane_Benchmark_User`): label `RFP Tool User`, description `Create RFP projects, lanes and carrier bids. Assign this to the pricing team.`, `hasActivationRequired` false, then classAccesses, objectPermissions, fieldPermissions. No tab or application visibility yet (3b adds them). `RfpController` and `BenchmarkRateService` do not exist until Tasks 3 and 7: list them anyway, and deploy this permission set for the first time in Task 3 (Task 1's deploy uses the manifest without `RFP_Tool_User`; add it to the manifest in Task 3).

`Lane_Benchmark_User`: add an objectPermissions block for `Benchmark_Rate__c` (read only, `viewAllRecords` false) and read-only fieldPermissions (editable false, readable true) for the same `Benchmark_Rate__c` fields the script above lists.

- [ ] **Step 5: Manifest**

Add to `manifest/package.xml`: `CustomObject` members `RFP_Project__c`, `RFP_Lane__c`, `Benchmark_Rate__c`; `CustomField` members for every generated field (`<object>.<field>`; produce the list with `ls force-app/main/default/objects/<obj>/fields | sed 's/.field-meta.xml//'`); new `<types>` block `ValidationRule` with member `Benchmark_Rate__c.Carrier_Or_Name_Required`; `PermissionSet` `Lane_Benchmark_User` is already there.

- [ ] **Step 6: Validate, then deploy**

```bash
sf project deploy validate -x manifest/package.xml -o sandbox -l RunSpecifiedTests -t PricingDepartmentControllerTest PlaceNormalizerTest PricingTestDataFactoryTest PlaceBuilderBatchTest LaneSearchServiceTest MapboxGeocoderTest LaneBenchmarkControllerTest LaneBenchmarkPlaceServiceTest -w 30
```

If a lookup filter is rejected, remove the `<lookupFilter>` block from that field (record it in the report; 3b filters in the record picker instead). If a roll-up is rejected, report the exact message and stop (BLOCKED). When the validation succeeds, run the same command with `deploy start` instead of `deploy validate`. Expected: Succeeded, 60/60 tests.

- [ ] **Step 7: Commit**

```bash
git add force-app/main/default/objects force-app/main/default/permissionsets manifest/package.xml scripts/metadata/gen_rfp_fields.py
git commit -m "Add RFP Project, RFP Lane and Benchmark Rate objects with permission sets"
```

---

### Task 2: RfpTestDataFactory

**Files:**

- Create: `force-app/main/default/classes/RfpTestDataFactory.cls` (+ `-meta.xml`, API 64.0)
- Create: `force-app/main/default/classes/RfpTestDataFactoryTest.cls` (+ `-meta.xml`)
- Modify: `.github/workflows/ci.yml`, `README.md` (add `RfpTestDataFactoryTest` to the lists), `manifest/package.xml` (ApexClass members)

**Interfaces:**

- Consumes: `PricingTestDataFactory.createGraph()`, `PlaceNormalizer.key`.
- Produces:
  - `public static Pricing_Place__c createPlace(String city, String prov, String country, Decimal lat, Decimal lng, String prefix)` — inserted.
  - `public static RFP_Project__c createProject(Account customer)` — inserted, Status Draft, Default_Margin 15, CurrencyIsoCode 'CAD'.
  - `public static RFP_Lane__c createLane(RFP_Project__c project, Pricing_Place__c origin, Pricing_Place__c destination)` — inserted, row number 1, cities/provinces/countries copied from the places, both `*_Resolved__c` true, Mode 'Truckload', Equipment_Category 'Van', Equipment_Type "Dry Van 53'".
  - `public static Benchmark_Rate__c buildBid(RFP_Lane__c lane, Decimal rate)` — NOT inserted: `RFP_Lane__c`, `Carrier_Name__c = 'Bid Carrier'`, `Contact_Name__c = 'Bid Contact'`, `Contact_Email__c = 'bid@example.invalid'`, `Rate__c = rate`, `CurrencyIsoCode = 'CAD'`, `Valid_From__c = Date.today()`, `Expires_On__c = Date.today().addDays(30)`. Lane keys are NOT set here; `BenchmarkRateService.save` sets them (Task 3).

- [ ] **Step 1: Write the failing test**

```apex
@IsTest
private class RfpTestDataFactoryTest {
  @IsTest
  static void buildersCreateAConsistentGraph() {
    PricingTestDataFactory.Graph g = PricingTestDataFactory.createGraph();
    Pricing_Place__c mtl = RfpTestDataFactory.createPlace(
      'Montréal',
      'QC',
      'CA',
      45.5019,
      -73.5674,
      'H1A'
    );
    Pricing_Place__c tor = RfpTestDataFactory.createPlace(
      'Toronto',
      'ON',
      'CA',
      43.6532,
      -79.3832,
      'M5V'
    );
    RFP_Project__c p = RfpTestDataFactory.createProject(g.customer);
    RFP_Lane__c lane = RfpTestDataFactory.createLane(p, mtl, tor);
    Benchmark_Rate__c bid = RfpTestDataFactory.buildBid(lane, 1234.56);

    System.assertEquals('montreal|qc|ca', mtl.Key__c);
    System.assertEquals(
      'Draft',
      [SELECT Status__c FROM RFP_Project__c WHERE Id = :p.Id].Status__c
    );
    RFP_Lane__c saved = [
      SELECT
        Origin_City__c,
        Origin_Province__c,
        Origin_Country__c,
        Destination_City__c,
        Origin_Place__c,
        Destination_Place__c,
        Origin_Resolved__c,
        Margin__c,
        RFP_Project__c
      FROM RFP_Lane__c
      WHERE Id = :lane.Id
    ];
    System.assertEquals('Montréal', saved.Origin_City__c);
    System.assertEquals('QC', saved.Origin_Province__c);
    System.assertEquals('CA', saved.Origin_Country__c);
    System.assertEquals(tor.Id, saved.Destination_Place__c);
    System.assertEquals(true, saved.Origin_Resolved__c);
    System.assertEquals(15, saved.Margin__c);
    System.assertEquals(p.Id, saved.RFP_Project__c);
    System.assertEquals(null, bid.Id, 'buildBid does not insert');
    System.assertEquals(lane.Id, bid.RFP_Lane__c);
    System.assertEquals(Date.today().addDays(30), bid.Expires_On__c);
  }
}
```

- [ ] **Step 2: Run it to see it fail** — `sf apex run test -n RfpTestDataFactoryTest -o sandbox -r human -w 15` cannot run before deploy; instead deploy both classes together in Step 4 and treat a compile failure of the test alone as the RED evidence (record the first `deploy validate` error in the report).

- [ ] **Step 3: Implement**

```apex
/**
 * Test builders for the phase 3 RFP objects. Places mirror LaneSearchServiceTest.place();
 * projects/lanes/bids carry the minimum the services and Lane Benchmark need.
 */
@IsTest
public class RfpTestDataFactory {
  public static Pricing_Place__c createPlace(
    String city,
    String prov,
    String country,
    Decimal lat,
    Decimal lng,
    String prefix
  ) {
    Pricing_Place__c p = new Pricing_Place__c(
      Name = city + ', ' + prov,
      Key__c = PlaceNormalizer.key(city, prov, country),
      City__c = city,
      Province__c = prov,
      Country__c = country,
      Geolocation__Latitude__s = lat,
      Geolocation__Longitude__s = lng,
      Postal_Prefix__c = prefix,
      Active__c = true,
      Source__c = 'Locations'
    );
    insert p;
    return p;
  }

  public static RFP_Project__c createProject(Account customer) {
    RFP_Project__c p = new RFP_Project__c(
      Name = 'Test RFP',
      Customer__c = customer.Id,
      Status__c = 'Draft',
      Default_Margin__c = 15,
      CurrencyIsoCode = 'CAD'
    );
    insert p;
    return p;
  }

  public static RFP_Lane__c createLane(
    RFP_Project__c project,
    Pricing_Place__c origin,
    Pricing_Place__c destination
  ) {
    RFP_Lane__c lane = new RFP_Lane__c(
      RFP_Project__c = project.Id,
      Row_Number__c = 1,
      Origin_City__c = origin.City__c,
      Origin_Province__c = origin.Province__c,
      Origin_Country__c = origin.Country__c,
      Origin_Postal__c = origin.Postal_Prefix__c,
      Origin_Place__c = origin.Id,
      Origin_Resolved__c = true,
      Destination_City__c = destination.City__c,
      Destination_Province__c = destination.Province__c,
      Destination_Country__c = destination.Country__c,
      Destination_Postal__c = destination.Postal_Prefix__c,
      Destination_Place__c = destination.Id,
      Destination_Resolved__c = true,
      Mode__c = 'Truckload',
      Equipment_Category__c = 'Van',
      Equipment_Type__c = 'Dry Van 53\'',
      Margin__c = 15,
      Hist_Status__c = 'Pending',
      CurrencyIsoCode = 'CAD'
    );
    insert lane;
    return lane;
  }

  public static Benchmark_Rate__c buildBid(RFP_Lane__c lane, Decimal rate) {
    return new Benchmark_Rate__c(
      RFP_Lane__c = lane.Id,
      Carrier_Name__c = 'Bid Carrier',
      Contact_Name__c = 'Bid Contact',
      Contact_Email__c = 'bid@example.invalid',
      Rate__c = rate,
      CurrencyIsoCode = 'CAD',
      Valid_From__c = Date.today(),
      Expires_On__c = Date.today().addDays(30)
    );
  }
}
```

- [ ] **Step 4: Register and deploy**

Add both classes to `manifest/package.xml` (ApexClass), `RfpTestDataFactoryTest` to `.github/workflows/ci.yml` and both README lists, then deploy with the nine-class list. Expected: Succeeded, 61/61.

- [ ] **Step 5: PMD, commit**

```bash
/private/tmp/pmd_install/pmd-bin-7.15.0/bin/pmd check --dir force-app --rulesets config/pmd-ruleset.xml --minimum-priority 3 --format text --fail-on-violation
git add force-app/main/default/classes/RfpTestDataFactory* manifest/package.xml .github/workflows/ci.yml README.md
git commit -m "Add RfpTestDataFactory builders for projects, lanes, bids and places"
```

---

### Task 3: BenchmarkRateService (save bids, copy lane keys)

**Files:**

- Create: `force-app/main/default/classes/BenchmarkRateService.cls` (+meta), `BenchmarkRateServiceTest.cls` (+meta)
- Modify: `manifest/package.xml` (ApexClass members + `PermissionSet` `RFP_Tool_User`), CI/README lists

**Interfaces:**

- Consumes: `PlaceNormalizer.provinceCode`, `PlaceNormalizer.cityLaneSide`, `RfpTestDataFactory`.
- Produces: `public static Benchmark_Rate__c save(Benchmark_Rate__c bid)` — user mode upsert (insert when `Id` null, update otherwise); when `RFP_Lane__c` is set, copies from the lane and its places: `RFP_Project__c`, `Mode__c`, `Equipment_Category__c`, `Equipment_Type__c`, `Hazmat__c`, `Origin_*`/`Destination_*` city, province, country, postal, place, geolocation, `City_Lane__c`, `State_Lane__c`, `Zip3_Lane__c`; defaults `Valid_From__c` to today and `Expires_On__c` to today + 30 when blank; returns the saved record re-queried with `Carrier_Display__c` and `Status__c`. Throws `LaneSearchException` with a user sentence when the lane does not exist or when `Rate__c` is null.
- `public static String cityLane(Pricing_Place__c o, Pricing_Place__c d)`, `stateLane`, `zip3Lane` — public statics so the query builder tests can assert the exact format.

- [ ] **Step 1: Write the failing test**

```apex
@IsTest
private class BenchmarkRateServiceTest {
  private class Fx {
    PricingTestDataFactory.Graph g;
    Pricing_Place__c mtl;
    Pricing_Place__c tor;
    RFP_Project__c project;
    RFP_Lane__c lane;
  }
  private static Fx fx() {
    Fx f = new Fx();
    f.g = PricingTestDataFactory.createGraph();
    f.mtl = RfpTestDataFactory.createPlace(
      'Montréal',
      'QC',
      'CA',
      45.5019,
      -73.5674,
      'H1A'
    );
    f.tor = RfpTestDataFactory.createPlace(
      'Toronto',
      'ON',
      'CA',
      43.6532,
      -79.3832,
      'M5V'
    );
    f.project = RfpTestDataFactory.createProject(f.g.customer);
    f.lane = RfpTestDataFactory.createLane(f.project, f.mtl, f.tor);
    return f;
  }

  @IsTest
  static void saveCopiesLaneKeysFromThePlaces() {
    Fx f = fx();
    Test.startTest();
    Benchmark_Rate__c saved = BenchmarkRateService.save(
      RfpTestDataFactory.buildBid(f.lane, 1500)
    );
    Test.stopTest();
    Benchmark_Rate__c b = [
      SELECT
        RFP_Project__c,
        City_Lane__c,
        State_Lane__c,
        Zip3_Lane__c,
        Origin_City__c,
        Origin_Province__c,
        Origin_Country__c,
        Origin_Place__c,
        Origin_Geolocation__Latitude__s,
        Destination_Geolocation__Longitude__s,
        Mode__c,
        Equipment_Category__c,
        Equipment_Type__c,
        Valid_From__c,
        Expires_On__c,
        Carrier_Display__c,
        Status__c
      FROM Benchmark_Rate__c
      WHERE Id = :saved.Id
    ];
    System.assertEquals(f.project.Id, b.RFP_Project__c);
    System.assertEquals('Montréal, QC:Toronto, ON', b.City_Lane__c);
    System.assertEquals('QC:ON', b.State_Lane__c);
    System.assertEquals('H1A:M5V', b.Zip3_Lane__c);
    System.assertEquals('Montréal', b.Origin_City__c);
    System.assertEquals(f.mtl.Id, b.Origin_Place__c);
    System.assertEquals(45.5019, b.Origin_Geolocation__Latitude__s);
    System.assertEquals(-79.3832, b.Destination_Geolocation__Longitude__s);
    System.assertEquals('Truckload', b.Mode__c);
    System.assertEquals('Van', b.Equipment_Category__c);
    System.assertEquals('Bid Carrier', b.Carrier_Display__c);
    System.assertEquals('Active', b.Status__c);
  }

  @IsTest
  static void saveDefaultsDatesAndUpdatesInPlace() {
    Fx f = fx();
    Benchmark_Rate__c bid = RfpTestDataFactory.buildBid(f.lane, 1500);
    bid.Valid_From__c = null;
    bid.Expires_On__c = null;
    Benchmark_Rate__c saved = BenchmarkRateService.save(bid);
    System.assertEquals(Date.today(), saved.Valid_From__c);
    System.assertEquals(Date.today().addDays(30), saved.Expires_On__c);
    saved.Rate__c = 1600;
    Benchmark_Rate__c again = BenchmarkRateService.save(saved);
    System.assertEquals(saved.Id, again.Id);
    System.assertEquals(
      1600,
      [SELECT Rate__c FROM Benchmark_Rate__c WHERE Id = :saved.Id].Rate__c
    );
    System.assertEquals(1, [SELECT COUNT() FROM Benchmark_Rate__c]);
  }

  @IsTest
  static void saveRejectsMissingRateAndMissingCarrier() {
    Fx f = fx();
    Benchmark_Rate__c noRate = RfpTestDataFactory.buildBid(f.lane, null);
    try {
      BenchmarkRateService.save(noRate);
      System.assert(false, 'expected an exception');
    } catch (LaneSearchException e) {
      System.assert(e.getMessage().contains('rate'), e.getMessage());
    }
    Benchmark_Rate__c noCarrier = RfpTestDataFactory.buildBid(f.lane, 900);
    noCarrier.Carrier_Name__c = null;
    try {
      BenchmarkRateService.save(noCarrier);
      System.assert(false, 'expected the validation rule');
    } catch (DmlException e) {
      System.assert(e.getMessage().contains('carrier'), e.getMessage());
    }
  }

  @IsTest
  static void laneKeyHelpersMatchTheLoadFormat() {
    Pricing_Place__c o = new Pricing_Place__c(
      City__c = 'Laval',
      Province__c = 'QC',
      Postal_Prefix__c = 'H7P'
    );
    Pricing_Place__c d = new Pricing_Place__c(
      City__c = 'Oshawa',
      Province__c = 'ON',
      Postal_Prefix__c = 'L1J'
    );
    System.assertEquals(
      'Laval, QC:Oshawa, ON',
      BenchmarkRateService.cityLane(o, d)
    );
    System.assertEquals('QC:ON', BenchmarkRateService.stateLane(o, d));
    System.assertEquals('H7P:L1J', BenchmarkRateService.zip3Lane(o, d));
  }
}
```

- [ ] **Step 2: Implement**

```apex
/**
 * Saves carrier bids (Benchmark_Rate__c) in user mode and stamps the lane keys Lane Benchmark
 * searches on. The keys come from the lane's resolved Pricing_Place__c records (canonical City__c,
 * Province__c, Postal_Prefix__c and coordinates), never from spreadsheet text, so a CITY-precision
 * search matches a bid through PlaceNormalizer.cityLaneVariants exactly as it matches a Load.
 */
public with sharing class BenchmarkRateService {
  public static Benchmark_Rate__c save(Benchmark_Rate__c bid) {
    if (bid.Rate__c == null) {
      throw new LaneSearchException('A bid needs a rate.');
    }
    if (bid.RFP_Lane__c != null) {
      applyLane(bid, loadLane(bid.RFP_Lane__c));
    }
    bid.Valid_From__c = bid.Valid_From__c ?? Date.today();
    bid.Expires_On__c = bid.Expires_On__c ?? Date.today().addDays(30);
    if (bid.Id == null) {
      Database.insert(bid, AccessLevel.USER_MODE);
    } else {
      Database.update(bid, AccessLevel.USER_MODE);
    }
    return reload(bid.Id);
  }

  private static RFP_Lane__c loadLane(Id laneId) {
    List<RFP_Lane__c> lanes = [
      SELECT
        Id,
        RFP_Project__c,
        Mode__c,
        Equipment_Category__c,
        Equipment_Type__c,
        Hazmat__c,
        Origin_City__c,
        Origin_Province__c,
        Origin_Country__c,
        Origin_Postal__c,
        Origin_Place__c,
        Origin_Place__r.City__c,
        Origin_Place__r.Province__c,
        Origin_Place__r.Postal_Prefix__c,
        Origin_Place__r.Geolocation__Latitude__s,
        Origin_Place__r.Geolocation__Longitude__s,
        Destination_City__c,
        Destination_Province__c,
        Destination_Country__c,
        Destination_Postal__c,
        Destination_Place__c,
        Destination_Place__r.City__c,
        Destination_Place__r.Province__c,
        Destination_Place__r.Postal_Prefix__c,
        Destination_Place__r.Geolocation__Latitude__s,
        Destination_Place__r.Geolocation__Longitude__s
      FROM RFP_Lane__c
      WHERE Id = :laneId
      WITH USER_MODE
    ];
    if (lanes.isEmpty()) {
      throw new LaneSearchException(
        'The RFP lane for this bid no longer exists.'
      );
    }
    return lanes[0];
  }

  private static void applyLane(Benchmark_Rate__c bid, RFP_Lane__c lane) {
    bid.RFP_Project__c = lane.RFP_Project__c;
    bid.Mode__c = lane.Mode__c;
    bid.Equipment_Category__c = lane.Equipment_Category__c;
    bid.Equipment_Type__c = lane.Equipment_Type__c;
    bid.Hazmat__c = lane.Hazmat__c;
    applyOrigin(bid, lane);
    applyDestination(bid, lane);
    Pricing_Place__c o = lane.Origin_Place__r;
    Pricing_Place__c d = lane.Destination_Place__r;
    if (o != null && d != null) {
      bid.City_Lane__c = cityLane(o, d);
      bid.State_Lane__c = stateLane(o, d);
      bid.Zip3_Lane__c = zip3Lane(o, d);
    }
  }

  private static void applyOrigin(Benchmark_Rate__c bid, RFP_Lane__c lane) {
    bid.Origin_City__c = lane.Origin_City__c;
    bid.Origin_Province__c = lane.Origin_Province__c;
    bid.Origin_Country__c = lane.Origin_Country__c;
    bid.Origin_Postal__c = lane.Origin_Postal__c;
    bid.Origin_Place__c = lane.Origin_Place__c;
    bid.Origin_Geolocation__Latitude__s = lane.Origin_Place__r
      ?.Geolocation__Latitude__s;
    bid.Origin_Geolocation__Longitude__s = lane.Origin_Place__r
      ?.Geolocation__Longitude__s;
  }

  private static void applyDestination(
    Benchmark_Rate__c bid,
    RFP_Lane__c lane
  ) {
    bid.Destination_City__c = lane.Destination_City__c;
    bid.Destination_Province__c = lane.Destination_Province__c;
    bid.Destination_Country__c = lane.Destination_Country__c;
    bid.Destination_Postal__c = lane.Destination_Postal__c;
    bid.Destination_Place__c = lane.Destination_Place__c;
    bid.Destination_Geolocation__Latitude__s = lane.Destination_Place__r
      ?.Geolocation__Latitude__s;
    bid.Destination_Geolocation__Longitude__s = lane.Destination_Place__r
      ?.Geolocation__Longitude__s;
  }

  /** "City, ST:City, ST" from the canonical place spellings, the way Revenova writes rtms__City_Lane__c. */
  public static String cityLane(Pricing_Place__c o, Pricing_Place__c d) {
    return PlaceNormalizer.cityLaneSide(
        o.City__c,
        PlaceNormalizer.provinceCode(o.Province__c)
      ) +
      ':' +
      PlaceNormalizer.cityLaneSide(
        d.City__c,
        PlaceNormalizer.provinceCode(d.Province__c)
      );
  }

  public static String stateLane(Pricing_Place__c o, Pricing_Place__c d) {
    return PlaceNormalizer.provinceCode(o.Province__c) +
      ':' +
      PlaceNormalizer.provinceCode(d.Province__c);
  }

  public static String zip3Lane(Pricing_Place__c o, Pricing_Place__c d) {
    return prefix(o.Postal_Prefix__c) + ':' + prefix(d.Postal_Prefix__c);
  }

  private static String prefix(String p) {
    return p == null ? '' : p.replace(' ', '').left(3).toUpperCase();
  }

  private static Benchmark_Rate__c reload(Id bidId) {
    return [
      SELECT
        Id,
        Name,
        RFP_Lane__c,
        RFP_Project__c,
        Carrier__c,
        Carrier_Name__c,
        Carrier_Display__c,
        Contact_Name__c,
        Contact_Email__c,
        Contact_Phone__c,
        Rate__c,
        CurrencyIsoCode,
        Fuel_Surcharge__c,
        FSC_Included__c,
        Transit_Days__c,
        Valid_From__c,
        Expires_On__c,
        Status__c,
        Notes__c,
        City_Lane__c,
        State_Lane__c,
        Zip3_Lane__c
      FROM Benchmark_Rate__c
      WHERE Id = :bidId
      WITH USER_MODE
    ];
  }
}
```

- [ ] **Step 3: Register, deploy, PMD, commit**

Add `BenchmarkRateService`, `BenchmarkRateServiceTest` and `PermissionSet` member `RFP_Tool_User` to the manifest; add the test class to CI and README lists; deploy with the ten-class list (expected 65/65: four new tests). Assign the permission set to yourself: `sf org assign permset -n RFP_Tool_User -o sandbox`. PMD clean. Commit: `Add BenchmarkRateService: save bids in user mode and copy lane keys from the places`.

---

### Task 4: `sourceFilter`, `Row.bid` and BidSearchQueryBuilder

**Files:**

- Modify: `force-app/main/default/classes/LaneSearchRequest.cls`
- Modify: `force-app/main/default/classes/LaneSearchResult.cls`
- Create: `force-app/main/default/classes/BidSearchQueryBuilder.cls` (+meta), `BidSearchQueryBuilderTest.cls` (+meta)
- Modify: manifest, CI/README lists

**Interfaces:**

- Produces:
  - `LaneSearchRequest.RowSource { ALL, LOADS, BIDS }`, field `public RowSource sourceFilter = RowSource.ALL;`, `applyDefaults()` line `sourceFilter = sourceFilter ?? RowSource.ALL;`.
  - `LaneSearchResult.BidDetail { Id rateId; Date expiresOn; String status; Decimal transitDays; Decimal fuelSurcharge; Boolean fscIncluded; }` all `@AuraEnabled`; `Row.bid` (`@AuraEnabled public BidDetail bid;`, no initializer, null for loads).
  - `public static String BidSearchQueryBuilder.buildSoql(LaneSearchRequest req, Map<String, Object> binds, Map<String, Pricing_Place__c> places)` — returns null when the request can never match a bid (`sourceFilter == LOADS`, `marketTestOnly`, `acceptedFilter != ANY_STATUS`); otherwise the SOQL below. Bind names are prefixed `b` (`bOCity`, `bDProv`, `bModes`, ...) so they never collide with the quote query's binds when both live in one map.

- [ ] **Step 1: Failing tests**

```apex
@IsTest
private class BidSearchQueryBuilderTest {
  private static Map<String, Pricing_Place__c> places() {
    return new Map<String, Pricing_Place__c>{
      'montreal|qc|ca' => new Pricing_Place__c(
        Key__c = 'montreal|qc|ca',
        City__c = 'Montréal',
        Province__c = 'QC',
        Country__c = 'CA',
        Postal_Prefix__c = 'H1A',
        Geolocation__Latitude__s = 45.5,
        Geolocation__Longitude__s = -73.5
      ),
      'toronto|on|ca' => new Pricing_Place__c(
        Key__c = 'toronto|on|ca',
        City__c = 'Toronto',
        Province__c = 'ON',
        Country__c = 'CA',
        Postal_Prefix__c = 'M5V',
        Geolocation__Latitude__s = 43.6,
        Geolocation__Longitude__s = -79.3
      )
    };
  }
  private static LaneSearchRequest req() {
    LaneSearchRequest r = new LaneSearchRequest();
    r.originKey = 'montreal|qc|ca';
    r.destinationKey = 'toronto|on|ca';
    r.validate();
    return r;
  }

  @IsTest
  static void cityPrecisionUsesLaneVariantsAndActiveWindow() {
    LaneSearchRequest r = req();
    Map<String, Object> binds = new Map<String, Object>();
    String soql = BidSearchQueryBuilder.buildSoql(r, binds, places());
    System.assert(soql.startsWith('SELECT Id, Name, '), soql);
    System.assert(soql.contains('FROM Benchmark_Rate__c'), soql);
    System.assert(soql.contains('CreatedDate = LAST_N_DAYS:90'), soql);
    System.assert(soql.contains('City_Lane__c LIKE :bOCity'), soql);
    System.assert(soql.contains('City_Lane__c LIKE :bDCity'), soql);
    System.assert(soql.contains('Valid_From__c <= TODAY'), soql);
    System.assert(soql.contains('Expires_On__c >= TODAY'), soql);
    System.assert(
      soql.endsWith('ORDER BY CreatedDate DESC LIMIT :bRowLimitPlusOne'),
      soql
    );
    List<String> oPatterns = (List<String>) binds.get('bOCity');
    System.assert(oPatterns.contains('Montréal, QC:%'), oPatterns);
    System.assert(oPatterns.contains('Montreal, QC:%'), oPatterns);
    System.assert(
      ((List<String>) binds.get('bDCity')).contains('%:Toronto, ON')
    );
    System.assertEquals(2001, binds.get('bRowLimitPlusOne'));
  }

  @IsTest
  static void provinceZip3AndRadiusMapToTheirColumns() {
    LaneSearchRequest r = req();
    r.originPrecision = LaneSearchRequest.Precision.PROVINCE;
    r.destinationPrecision = LaneSearchRequest.Precision.ZIP3;
    Map<String, Object> binds = new Map<String, Object>();
    String soql = BidSearchQueryBuilder.buildSoql(r, binds, places());
    System.assert(soql.contains('State_Lane__c LIKE :bOProv'), soql);
    System.assert(soql.contains('Zip3_Lane__c LIKE :bDZip3'), soql);
    System.assertEquals('QC:%', binds.get('bOProv'));
    System.assertEquals('%:M5V', binds.get('bDZip3'));

    r = req();
    r.originPrecision = LaneSearchRequest.Precision.RADIUS;
    r.originRadius = 50;
    r.radiusUnit = LaneSearchRequest.Unit.KM;
    binds = new Map<String, Object>();
    soql = BidSearchQueryBuilder.buildSoql(r, binds, places());
    System.assert(
      soql.contains(
        'DISTANCE(Origin_Geolocation__c, GEOLOCATION(:bOLat, :bOLng), \'km\') < :bORadius'
      ),
      soql
    );
    System.assertEquals(50, binds.get('bORadius'));
  }

  @IsTest
  static void filtersAndSourceRules() {
    LaneSearchRequest r = req();
    r.modes = new List<String>{ 'Truckload' };
    r.equipmentCategories = new List<String>{ 'Van' };
    r.equipmentTypes = new List<String>{ 'Dry Van 53\'' };
    r.hazmatOnly = true;
    r.currencyIsoCode = 'CAD';
    Map<String, Object> binds = new Map<String, Object>();
    String soql = BidSearchQueryBuilder.buildSoql(r, binds, places());
    System.assert(soql.contains('Mode__c IN :bModes'), soql);
    System.assert(
      soql.contains(
        '(Equipment_Category__c IN :bCats OR Equipment_Type__c IN :bTypes)'
      ),
      soql
    );
    System.assert(soql.contains('Hazmat__c = true'), soql);
    System.assert(soql.contains('CurrencyIsoCode = :bCurrency'), soql);

    r = req();
    r.sourceFilter = LaneSearchRequest.RowSource.BIDS;
    soql = BidSearchQueryBuilder.buildSoql(
      r,
      new Map<String, Object>(),
      places()
    );
    System.assert(
      !soql.contains('Expires_On__c'),
      'BIDS also returns expired bids: ' + soql
    );

    r = req();
    r.sourceFilter = LaneSearchRequest.RowSource.LOADS;
    System.assertEquals(
      null,
      BidSearchQueryBuilder.buildSoql(r, new Map<String, Object>(), places())
    );
    r = req();
    r.marketTestOnly = true;
    System.assertEquals(
      null,
      BidSearchQueryBuilder.buildSoql(r, new Map<String, Object>(), places())
    );
    r = req();
    r.acceptedFilter = LaneSearchRequest.Accepted.DECLINED;
    System.assertEquals(
      null,
      BidSearchQueryBuilder.buildSoql(r, new Map<String, Object>(), places())
    );
  }

  @IsTest
  static void defaultsApplySourceAll() {
    LaneSearchRequest r = (LaneSearchRequest) JSON.deserialize(
      '{"originKey":"montreal|qc|ca"}',
      LaneSearchRequest.class
    );
    r.validate();
    System.assertEquals(LaneSearchRequest.RowSource.ALL, r.sourceFilter);
    LaneSearchResult.Row row = new LaneSearchResult.Row();
    System.assertEquals(null, row.bid, 'loads carry no bid detail');
  }
}
```

- [ ] **Step 2: Implement the request and result changes**

In `LaneSearchRequest`: after the `Accepted` enum add

```apex
/** Which rows a search returns: Loads' carrier quotes, phase 3 bids (Benchmark_Rate__c), or both. */
public enum RowSource {
  ALL,
  LOADS,
  BIDS
}
```

after `acceptedFilter` add `public RowSource sourceFilter = RowSource.ALL;` and in `applyDefaults()` add `sourceFilter = sourceFilter ?? RowSource.ALL;`.

In `LaneSearchResult`, after `CarrierDetail`:

```apex
// Phase 3: set only on rows that come from Benchmark_Rate__c (bids). Grouped, like CarrierDetail,
// so Row stays under PMD's TooManyFields threshold; the LWC treats bid != null as "this is a bid".
public class BidDetail {
  @AuraEnabled
  public Id rateId;
  @AuraEnabled
  public Date expiresOn;
  @AuraEnabled
  public String status;
  @AuraEnabled
  public Decimal transitDays;
  @AuraEnabled
  public Decimal fuelSurcharge;
  @AuraEnabled
  public Boolean fscIncluded;
}
```

and on `Row`: `@AuraEnabled public BidDetail bid;` (last field).

- [ ] **Step 3: Implement the builder**

```apex
/**
 * Dynamic SOQL for bids (Benchmark_Rate__c) with the same precision semantics as
 * LaneSearchQueryBuilder has for Loads: CITY matches City_Lane__c against the place's spelling
 * variants, PROVINCE matches State_Lane__c, ZIP3 matches Zip3_Lane__c, RADIUS uses DISTANCE() on
 * the copied geolocation. The per-end bookkeeping is a smaller copy of LaneSearchQueryBuilder's
 * LaneEnd (private there); the two builders address different objects and fields, so a shared
 * abstraction would have to be parameterised on six field names for two callers.
 * Returns null when the request can never match a bid (see canMatchBids).
 */
public with sharing class BidSearchQueryBuilder {
  private static final String SELECT_CLAUSE =
    'SELECT Id, Name, RFP_Lane__c, RFP_Project__c, Carrier__c, Carrier_Name__c, Carrier_Display__c, ' +
    'Contact_Name__c, Contact_Email__c, Contact_Phone__c, Rate__c, CurrencyIsoCode, Fuel_Surcharge__c, ' +
    'FSC_Included__c, Transit_Days__c, Valid_From__c, Expires_On__c, Status__c, Mode__c, ' +
    'Equipment_Category__c, Equipment_Type__c, Hazmat__c, Origin_City__c, Origin_Province__c, ' +
    'Destination_City__c, Destination_Province__c, Notes__c, CreatedDate FROM Benchmark_Rate__c';

  private class BidEnd {
    String key;
    LaneSearchRequest.Precision precision;
    String explicitZip3;
    Decimal radius;
    String bindPrefix; // 'bO' or 'bD'
    String geoField; // Origin_Geolocation__c / Destination_Geolocation__c
    String likePrefix;
    String likeSuffix;
  }

  public static String buildSoql(
    LaneSearchRequest req,
    Map<String, Object> binds,
    Map<String, Pricing_Place__c> places
  ) {
    if (!canMatchBids(req)) {
      return null;
    }
    List<String> conditions = new List<String>();
    conditions.add(
      'CreatedDate = LAST_N_DAYS:' + String.valueOf(req.lookbackDays)
    );
    if (req.sourceFilter != LaneSearchRequest.RowSource.BIDS) {
      conditions.add('Valid_From__c <= TODAY');
      conditions.add('Expires_On__c >= TODAY');
    }
    addEnd(conditions, binds, req, originEnd(req), places);
    addEnd(conditions, binds, req, destinationEnd(req), places);
    addFilters(req, conditions, binds);
    binds.put('bRowLimitPlusOne', req.rowLimit + 1);
    return SELECT_CLAUSE +
      ' WHERE ' +
      String.join(conditions, ' AND ') +
      ' ORDER BY CreatedDate DESC LIMIT :bRowLimitPlusOne';
  }

  /** Bids have no accepted/declined state and no customer, so those filters exclude every bid. */
  private static Boolean canMatchBids(LaneSearchRequest req) {
    return req.sourceFilter != LaneSearchRequest.RowSource.LOADS &&
      req.marketTestOnly != true &&
      req.acceptedFilter == LaneSearchRequest.Accepted.ANY_STATUS;
  }

  private static BidEnd originEnd(LaneSearchRequest req) {
    BidEnd e = new BidEnd();
    e.key = req.originKey;
    e.precision = req.originPrecision;
    e.explicitZip3 = req.originZip3;
    e.radius = req.originRadius;
    e.bindPrefix = 'bO';
    e.geoField = 'Origin_Geolocation__c';
    e.likePrefix = '';
    e.likeSuffix = ':%';
    return e;
  }

  private static BidEnd destinationEnd(LaneSearchRequest req) {
    BidEnd e = new BidEnd();
    e.key = req.destinationKey;
    e.precision = req.destinationPrecision;
    e.explicitZip3 = req.destinationZip3;
    e.radius = req.destinationRadius;
    e.bindPrefix = 'bD';
    e.geoField = 'Destination_Geolocation__c';
    e.likePrefix = '%:';
    e.likeSuffix = '';
    return e;
  }

  private static void addEnd(
    List<String> conditions,
    Map<String, Object> binds,
    LaneSearchRequest req,
    BidEnd e,
    Map<String, Pricing_Place__c> places
  ) {
    if (
      e.precision == LaneSearchRequest.Precision.ZIP3 &&
      String.isNotBlank(e.explicitZip3)
    ) {
      addLike(conditions, binds, e, 'Zip3_Lane__c', 'Zip3', e.explicitZip3);
      return;
    }
    Pricing_Place__c place = places.get(e.key);
    if (place == null) {
      return;
    }
    if (e.precision == LaneSearchRequest.Precision.CITY) {
      addCity(conditions, binds, e, place);
    } else if (e.precision == LaneSearchRequest.Precision.PROVINCE) {
      addLike(conditions, binds, e, 'State_Lane__c', 'Prov', place.Province__c);
    } else if (e.precision == LaneSearchRequest.Precision.ZIP3) {
      addLike(
        conditions,
        binds,
        e,
        'Zip3_Lane__c',
        'Zip3',
        place.Postal_Prefix__c
      );
    } else {
      addRadius(conditions, binds, req, e, place);
    }
  }

  private static String pattern(BidEnd e, String raw) {
    return e.likePrefix + LaneSearchQueryBuilder.escapeLike(raw) + e.likeSuffix;
  }

  private static void addCity(
    List<String> conditions,
    Map<String, Object> binds,
    BidEnd e,
    Pricing_Place__c place
  ) {
    List<String> patterns = new List<String>();
    for (String v : PlaceNormalizer.cityLaneVariants(place)) {
      patterns.add(pattern(e, v));
    }
    binds.put(e.bindPrefix + 'City', patterns);
    conditions.add('City_Lane__c LIKE :' + e.bindPrefix + 'City');
  }

  private static void addLike(
    List<String> conditions,
    Map<String, Object> binds,
    BidEnd e,
    String field,
    String bindSuffix,
    String raw
  ) {
    if (String.isBlank(raw)) {
      throw new LaneSearchException(
        'Place ' +
          e.key +
          ' has no postal prefix or province for this precision'
      );
    }
    binds.put(e.bindPrefix + bindSuffix, pattern(e, raw));
    conditions.add(field + ' LIKE :' + e.bindPrefix + bindSuffix);
  }

  private static void addRadius(
    List<String> conditions,
    Map<String, Object> binds,
    LaneSearchRequest req,
    BidEnd e,
    Pricing_Place__c place
  ) {
    if (
      place.Geolocation__Latitude__s == null ||
      place.Geolocation__Longitude__s == null
    ) {
      throw new LaneSearchException('Place ' + e.key + ' has no coordinates');
    }
    String unit = req.radiusUnit == LaneSearchRequest.Unit.KM ? 'km' : 'mi';
    binds.put(e.bindPrefix + 'Lat', place.Geolocation__Latitude__s);
    binds.put(e.bindPrefix + 'Lng', place.Geolocation__Longitude__s);
    binds.put(e.bindPrefix + 'Radius', e.radius);
    conditions.add(
      'DISTANCE(' +
        e.geoField +
        ', GEOLOCATION(:' +
        e.bindPrefix +
        'Lat, :' +
        e.bindPrefix +
        'Lng), \'' +
        unit +
        '\') < :' +
        e.bindPrefix +
        'Radius'
    );
  }

  private static void addFilters(
    LaneSearchRequest req,
    List<String> conditions,
    Map<String, Object> binds
  ) {
    if (String.isNotBlank(req.currencyIsoCode)) {
      binds.put('bCurrency', req.currencyIsoCode);
      conditions.add('CurrencyIsoCode = :bCurrency');
    }
    if (req.modes != null && !req.modes.isEmpty()) {
      binds.put('bModes', req.modes);
      conditions.add('Mode__c IN :bModes');
    }
    addEquipment(req, conditions, binds);
    if (req.hazmatOnly == true) {
      conditions.add('Hazmat__c = true');
    }
  }

  private static void addEquipment(
    LaneSearchRequest req,
    List<String> conditions,
    Map<String, Object> binds
  ) {
    Boolean hasCats =
      req.equipmentCategories != null && !req.equipmentCategories.isEmpty();
    Boolean hasTypes =
      req.equipmentTypes != null && !req.equipmentTypes.isEmpty();
    if (hasCats) {
      binds.put('bCats', req.equipmentCategories);
    }
    if (hasTypes) {
      binds.put('bTypes', req.equipmentTypes);
    }
    if (hasCats && hasTypes) {
      conditions.add(
        '(Equipment_Category__c IN :bCats OR Equipment_Type__c IN :bTypes)'
      );
    } else if (hasCats) {
      conditions.add('Equipment_Category__c IN :bCats');
    } else if (hasTypes) {
      conditions.add('Equipment_Type__c IN :bTypes');
    }
  }
}
```

- [ ] **Step 4: Register, deploy, PMD, commit**

Manifest, CI and README lists gain `BidSearchQueryBuilderTest` (11-class list). Deploy; expected 69/69. PMD must be clean — `addEnd` is at 6 and the class total should be under 30; if PMD reports more, move `addFilters`/`addEquipment` into `BidSearchFilters` (same shape as `LaneSearchFilters`). Commit: `Add sourceFilter, Row.bid and BidSearchQueryBuilder for bids in lane search`.

---

### Task 5: BidSearchService and the merge into LaneSearchService

**Files:**

- Create: `force-app/main/default/classes/BidSearchService.cls` (+meta), `BidSearchServiceTest.cls` (+meta)
- Modify: `force-app/main/default/classes/LaneSearchService.cls`
- Modify: `force-app/main/default/classes/LaneSearchServiceTest.cls` (one new test)
- Modify: manifest, CI/README lists

**Interfaces:**

- Produces:
  - `public static List<LaneSearchResult.Row> BidSearchService.search(LaneSearchRequest req, Map<String, Pricing_Place__c> places, BidSearchService.Outcome out)` — runs `BidSearchQueryBuilder.buildSoql`; returns an empty list when it is null; sets `out.truncated` when more than `req.rowLimit` bids came back (and drops the extra one).
  - `public class Outcome { public Boolean truncated = false; }`
  - `public static LaneSearchResult.Row toRow(Benchmark_Rate__c b)`.
  - `public static List<LaneSearchResult.Row> merge(List<LaneSearchResult.Row> quotes, List<LaneSearchResult.Row> bids, Integer rowLimit)` — linear merge of two lists already ordered by `createdDate` descending; result capped at `rowLimit`.
  - `public static String fingerprint(LaneSearchResult.Row r)` — quote rows: `carrierTotal|carrierName|origin|destination|mode|equipment` (same values as before, now read from the Row); bid rows append `|bid:<rateId>`.
- `LaneSearchService.search` becomes: validate → loadPlaces → quote query (unchanged) → `quoteRows = toRows(quotes)` → `bidRows = BidSearchService.search(req, places, out)` → `rows = BidSearchService.merge(quoteRows, bidRows, req.rowLimit)` → `result.truncated = quotesTruncated || out.truncated || (quoteRows.size() + bidRows.size() > req.rowLimit)` → `collectRows(rows, result)` (fingerprint via `BidSearchService.fingerprint`, stats from `row.carrierTotal` and `row.currencyIsoCode ?? 'CAD'`).

- [ ] **Step 1: Failing tests**

`BidSearchServiceTest`:

```apex
@IsTest
private class BidSearchServiceTest {
  private static LaneSearchResult.Row row(
    String kind,
    Datetime created,
    Decimal total
  ) {
    LaneSearchResult.Row r = new LaneSearchResult.Row();
    r.createdDate = created;
    r.carrierTotal = total;
    r.carrierName = 'C';
    r.origin = 'A';
    r.destination = 'B';
    r.mode = 'Truckload';
    r.equipment = 'Van';
    if (kind == 'bid') {
      r.bid = new LaneSearchResult.BidDetail();
      r.bid.rateId = '001000000000001AAA';
    }
    return r;
  }

  @IsTest
  static void mergeKeepsDateOrderAndCap() {
    Datetime t = Datetime.now();
    List<LaneSearchResult.Row> quotes = new List<LaneSearchResult.Row>{
      row('quote', t.addHours(-1), 100),
      row('quote', t.addHours(-3), 300)
    };
    List<LaneSearchResult.Row> bids = new List<LaneSearchResult.Row>{
      row('bid', t, 50),
      row('bid', t.addHours(-2), 200),
      row('bid', t.addHours(-4), 400)
    };
    List<LaneSearchResult.Row> merged = BidSearchService.merge(quotes, bids, 4);
    System.assertEquals(4, merged.size());
    System.assertEquals(50, merged[0].carrierTotal);
    System.assertEquals(100, merged[1].carrierTotal);
    System.assertEquals(200, merged[2].carrierTotal);
    System.assertEquals(300, merged[3].carrierTotal);
  }

  @IsTest
  static void fingerprintNeverCollapsesBids() {
    LaneSearchResult.Row a = row('quote', Datetime.now(), 100);
    LaneSearchResult.Row b = row('quote', Datetime.now(), 100);
    System.assertEquals(
      BidSearchService.fingerprint(a),
      BidSearchService.fingerprint(b)
    );
    LaneSearchResult.Row c = row('bid', Datetime.now(), 100);
    System.assertNotEquals(
      BidSearchService.fingerprint(a),
      BidSearchService.fingerprint(c)
    );
  }

  @IsTest
  static void toRowMapsTheBid() {
    PricingTestDataFactory.Graph g = PricingTestDataFactory.createGraph();
    Pricing_Place__c mtl = RfpTestDataFactory.createPlace(
      'Montréal',
      'QC',
      'CA',
      45.5019,
      -73.5674,
      'H1A'
    );
    Pricing_Place__c tor = RfpTestDataFactory.createPlace(
      'Toronto',
      'ON',
      'CA',
      43.6532,
      -79.3832,
      'M5V'
    );
    RFP_Lane__c lane = RfpTestDataFactory.createLane(
      RfpTestDataFactory.createProject(g.customer),
      mtl,
      tor
    );
    Benchmark_Rate__c bid = RfpTestDataFactory.buildBid(lane, 1500);
    bid.Transit_Days__c = 2;
    bid.Fuel_Surcharge__c = 100;
    bid.FSC_Included__c = true;
    Benchmark_Rate__c saved = BenchmarkRateService.save(bid);
    Benchmark_Rate__c full = Database.query(
      BidSearchQueryBuilder.buildSoql(
          minimalRequest(),
          new Map<String, Object>{ 'bRowLimitPlusOne' => 10 },
          new Map<String, Pricing_Place__c>()
        )
        .replace('LIMIT :bRowLimitPlusOne', 'LIMIT 10')
    );
    LaneSearchResult.Row r = BidSearchService.toRow(full);
    System.assertEquals(saved.Id, r.quoteId);
    System.assertEquals(saved.Name, r.quoteName);
    System.assertEquals('Montréal, QC', r.origin);
    System.assertEquals('Toronto, ON', r.destination);
    System.assertEquals('Bid Carrier', r.carrierName);
    System.assertEquals('Bid Contact', r.contactName);
    System.assertEquals('bid@example.invalid', r.carrier.contactEmail);
    System.assertEquals(1500, r.carrierTotal);
    System.assertEquals('CAD', r.currencyIsoCode);
    System.assertEquals(Date.today(), r.quoteDate);
    System.assertEquals(saved.Id, r.bid.rateId);
    System.assertEquals(Date.today().addDays(30), r.bid.expiresOn);
    System.assertEquals('Active', r.bid.status);
    System.assertEquals(2, r.bid.transitDays);
    System.assertEquals(true, r.bid.fscIncluded);
    System.assertEquals('Bid', r.loadStatus);
  }

  private static LaneSearchRequest minimalRequest() {
    LaneSearchRequest r = new LaneSearchRequest();
    r.validate();
    return r;
  }
}
```

(The `toRowMapsTheBid` query trick exercises the real SELECT clause; if `Database.query` rejects the replaced string, query the same field list directly in the test.)

Add to `LaneSearchServiceTest`:

```apex
  @IsTest
  static void bidsMergeIntoRowsAndObeyTheSourceFilter() {
    Fixture f = fixture();
    Test.startTest();
    createLoadsAndQuotes(f);
    Pricing_Place__c mtl = [SELECT Id, City__c, Province__c, Country__c, Postal_Prefix__c FROM Pricing_Place__c WHERE Key__c = 'montreal|qc|ca'];
    Pricing_Place__c tor = [SELECT Id, City__c, Province__c, Country__c, Postal_Prefix__c FROM Pricing_Place__c WHERE Key__c = 'toronto|on|ca'];
    RFP_Lane__c lane = RfpTestDataFactory.createLane(RfpTestDataFactory.createProject(f.g.customer), mtl, tor);
    BenchmarkRateService.save(RfpTestDataFactory.buildBid(lane, 1200));
    Benchmark_Rate__c expired = RfpTestDataFactory.buildBid(lane, 999);
    expired.Valid_From__c = Date.today().addDays(-60);
    expired.Expires_On__c = Date.today().addDays(-1);
    BenchmarkRateService.save(expired);

    LaneSearchResult all = LaneSearchService.search(req('montreal|qc|ca', 'toronto|on|ca'));
    LaneSearchRequest loadsOnly = req('montreal|qc|ca', 'toronto|on|ca');
    loadsOnly.sourceFilter = LaneSearchRequest.RowSource.LOADS;
    LaneSearchResult loads = LaneSearchService.search(loadsOnly);
    LaneSearchRequest bidsOnly = req('montreal|qc|ca', 'toronto|on|ca');
    bidsOnly.sourceFilter = LaneSearchRequest.RowSource.BIDS;
    LaneSearchResult bids = LaneSearchService.search(bidsOnly);
    Test.stopTest();

    System.assertEquals(2, all.rows.size(), 'one quote + one active bid');
    System.assertEquals(1, loads.rows.size());
    System.assertEquals(null, loads.rows[0].bid);
    System.assertEquals(2, bids.rows.size(), 'active and expired bids, no quotes');
    Set<String> statuses = new Set<String>{ bids.rows[0].bid.status, bids.rows[1].bid.status };
    System.assert(statuses.contains('Expired') && statuses.contains('Active'), statuses);
    System.assertEquals(2, all.statsByCurrency.get('CAD').count, 'stats count both sources');
    System.assertEquals(1100, all.statsByCurrency.get('CAD').avg);
  }
```

- [ ] **Step 2: Implement `BidSearchService`**

```apex
/**
 * Phase 3: bids (Benchmark_Rate__c) as a second row source for LaneSearchService. Runs the SOQL
 * BidSearchQueryBuilder builds, converts bids to LaneSearchResult.Row (bid != null marks them),
 * and merges them with the quote rows by CreatedDate descending. Lives in its own class so
 * LaneSearchService (already split twice for PMD) stays an orchestrator.
 */
public without sharing class BidSearchService {
  public class Outcome {
    public Boolean truncated = false;
  }

  @SuppressWarnings('PMD.ApexCRUDViolation') // system mode by design, like LaneSearchService
  public static List<LaneSearchResult.Row> search(
    LaneSearchRequest req,
    Map<String, Pricing_Place__c> places,
    Outcome out
  ) {
    Map<String, Object> binds = new Map<String, Object>();
    String soql = BidSearchQueryBuilder.buildSoql(req, binds, places);
    List<LaneSearchResult.Row> rows = new List<LaneSearchResult.Row>();
    if (soql == null) {
      return rows;
    }
    List<Benchmark_Rate__c> bids = Database.queryWithBinds(soql, binds, AccessLevel.SYSTEM_MODE);
    out.truncated = bids.size() > req.rowLimit;
    if (out.truncated) {
      bids.remove(bids.size() - 1);
    }
    for (Benchmark_Rate__c b : bids) {
      rows.add(toRow(b));
    }
    return rows;
  }

  public static LaneSearchResult.Row toRow(Benchmark_Rate__c b) {
    LaneSearchResult.Row r = new LaneSearchResult.Row();
    r.quoteId = b.Id;
    r.quoteName = b.Name;
    r.origin = PlaceNormalizer.cityLaneSide(b.Origin_City__c, b.Origin_Province__c);
    r.destination = PlaceNormalizer.cityLaneSide(b.Destination_City__c, b.Destination_Province__c);
    r.mode = b.Mode__c;
    r.equipment = b.Equipment_Type__c;
    r.equipmentCategory = b.Equipment_Category__c;
    r.carrierName = b.Carrier_Display__c;
    r.contactName = b.Contact_Name__c;
    r.currencyIsoCode = b.CurrencyIsoCode;
    r.carrierTotal = b.Rate__c;
    r.quoteDate = b.Valid_From__c;
    r.hazmat = b.Hazmat__c;
    r.accepted = null;
    r.loadStatus = 'Bid';
    r.opsComments = b.Notes__c;
    r.createdDate = b.CreatedDate;
    r.carrier.contactEmail = b.Contact_Email__c;
    r.carrier.contactPhone = b.Contact_Phone__c;
    r.bid = new LaneSearchResult.BidDetail();
    r.bid.rateId = b.Id;
    r.bid.expiresOn = b.Expires_On__c;
    r.bid.status = b.Status__c;
    r.bid.transitDays = b.Transit_Days__c;
    r.bid.fuelSurcharge = b.Fuel_Surcharge__c;
    r.bid.fscIncluded = b.FSC_Included__c;
    return r;
  }

  /** Both inputs are ordered by createdDate descending (their queries say so); linear merge, capped. */
  public static List<LaneSearchResult.Row> merge(
    List<LaneSearchResult.Row> quotes,
    List<LaneSearchResult.Row> bids,
    Integer rowLimit
  ) {
    List<LaneSearchResult.Row> out = new List<LaneSearchResult.Row>();
    Integer i = 0;
    Integer j = 0;
    while (out.size() < rowLimit && (i < quotes.size() || j < bids.size())) {
      Boolean takeQuote = j >= bids.size() ||
        (i < quotes.size() && !isBefore(bids[j].createdDate, quotes[i].createdDate));
      out.add(takeQuote ? quotes[i++] : bids[j++]);
    }
    return out;
  }

  /** true when a is strictly newer than b (null sorts last). */
  private static Boolean isBefore(Datetime a, Datetime b) {
    if (a == null) {
      return false;
    }
    return b == null || a > b;
  }

  public static String fingerprint(LaneSearchResult.Row r) {
    String base =
      String.valueOf(r.carrierTotal) + '|' + r.carrierName + '|' + r.origin + '|' + r.destination +
      '|' + r.mode + '|' + r.equipment;
    return r.bid == null ? base : base + '|bid:' + r.bid.rateId;
  }
}
```

- [ ] **Step 3: Modify `LaneSearchService`**

Replace the body of `search` from `List<rtms__CarrierQuote__c> quotes = ...` onward with:

```apex
    List<rtms__CarrierQuote__c> quotes = Database.queryWithBinds(soql, binds, AccessLevel.SYSTEM_MODE);
    LaneSearchResult result = new LaneSearchResult();
    Boolean quotesTruncated = quotes.size() > req.rowLimit;
    if (quotesTruncated) {
      quotes.remove(quotes.size() - 1);
    }
    List<LaneSearchResult.Row> quoteRows = new List<LaneSearchResult.Row>();
    for (rtms__CarrierQuote__c q : quotes) {
      quoteRows.add(toRow(q));
    }
    BidSearchService.Outcome bidOutcome = new BidSearchService.Outcome();
    List<LaneSearchResult.Row> bidRows = BidSearchService.search(req, places, bidOutcome);
    result.elapsedMs = (System.currentTimeMillis() - t0).intValue();
    result.truncated = quotesTruncated || bidOutcome.truncated ||
      quoteRows.size() + bidRows.size() > req.rowLimit;
    collectRows(BidSearchService.merge(quoteRows, bidRows, req.rowLimit), result);
    return result;
```

and change `collectRows` to take `List<LaneSearchResult.Row> rows`: fingerprint = `BidSearchService.fingerprint(r)`; on survive `result.rows.add(r)`; currency = `r.currencyIsoCode == null ? 'CAD' : r.currencyIsoCode`; total = `r.carrierTotal == null ? 0 : r.carrierTotal`. Update the doc comment. `toRow(rtms__CarrierQuote__c)` is unchanged.

- [ ] **Step 4: Register, deploy, PMD, commit**

Manifest (`BidSearchService`, `BidSearchServiceTest`), CI/README lists (12 classes). Deploy; expected 73/73. All existing `LaneSearchServiceTest` tests must still pass unchanged (they build quotes only; bids absent). PMD clean. Commit: `Merge bids into lane search results through BidSearchService`.

---

### Task 6: Lane Benchmark UI — Source filter, bid rows, CSV

**Files:**

- Modify: `force-app/main/default/lwc/laneBenchmarkFilters/laneBenchmarkFilters.js`, `.html`, `__tests__/laneBenchmarkFilters.test.js`
- Modify: `force-app/main/default/lwc/laneBenchmarkResults/laneBenchmarkResults.js`, `.html`, `.css`, `__tests__/laneBenchmarkResults.test.js`
- Modify: `force-app/main/default/lwc/laneBenchmark/laneBenchmark.js`, `__tests__/laneBenchmark.test.js`

**Interfaces:**

- `DEFAULT_FILTERS` gains `sourceFilter: "ALL"`; the container's `toServiceRequest()` passes `sourceFilter: r.sourceFilter`. A saved request without `sourceFilter` restores as `ALL` (the `value` setter spreads `cloneDefaults()` first, so this is automatic).
- Results: a row with `r.bid` renders a `Bid` badge in the Carrier cell, `Expires <date>` (and `Expired` styling when `bid.status === "Expired"`) in the Flags cell instead of Accepted/Declined, and the detail row shows transit days and fuel surcharge. `CSV_COLUMNS` gains `{ label: "Source", field: "source" }` first and `{ label: "Expires on", field: "bid.expiresOn" }` last; `handleExport` maps rows to add `source: r.bid ? "Bid" : "Load"` before `toCsv`.

- [ ] **Step 1: Failing Jest tests**

Filters (`laneBenchmarkFilters.test.js`), add to `DEFAULTS` `sourceFilter: "ALL"` and:

```javascript
it("emits the source filter and defaults it to ALL", async () => {
  const el = await mount();
  expect(el.shadowRoot.querySelector('[data-id="source"]').value).toBe("ALL");
  const handler = jest.fn();
  el.addEventListener("filterschange", handler);
  change(el, "source", "BIDS");
  await flush();
  expect(handler.mock.calls[0][0].detail.sourceFilter).toBe("BIDS");
});

it("restores a saved value without sourceFilter as ALL", async () => {
  const { sourceFilter, ...legacy } = DEFAULTS;
  expect(sourceFilter).toBe("ALL");
  const el = await mount(legacy);
  expect(el.shadowRoot.querySelector('[data-id="source"]').value).toBe("ALL");
});
```

Results (`laneBenchmarkResults.test.js`): add a third fixture row

```javascript
  {
    quoteId: "b1",
    quoteName: "B-000001",
    origin: "Montréal, QC",
    destination: "Toronto, ON",
    mode: "Truckload",
    equipment: "Dry Van 53'",
    carrierName: "New Carrier Inc",
    contactName: "Sam Bid",
    carrier: { contactEmail: "sam@new.test", contactPhone: null, risk: null, loadCount: null, attention: "" },
    currencyIsoCode: "CAD",
    carrierTotal: 1200,
    quoteDate: "2026-09-10",
    createdDate: "2026-09-10T10:00:00.000Z",
    hazmat: false,
    accepted: null,
    loadStatus: "Bid",
    opsComments: null,
    bid: { rateId: "b1", expiresOn: "2026-10-10", status: "Active", transitDays: 2, fuelSurcharge: 100, fscIncluded: true }
  }
```

and tests:

```javascript
it("marks bid rows with a badge and their expiry instead of accepted/declined", async () => {
  const el = await mount();
  const rows = el.shadowRoot.querySelectorAll("tbody tr[data-index]");
  const bidRow = rows[2];
  expect(bidRow.querySelector('[data-id="bid-badge"]').textContent).toBe("Bid");
  expect(bidRow.querySelector('[data-id="flags"]').textContent).toContain(
    "Expires 2026-10-10"
  );
  expect(bidRow.querySelector('[data-id="flags"]').textContent).not.toContain(
    "Declined"
  );
  expect(rows[0].querySelector('[data-id="bid-badge"]')).toBeNull();
});

it("exports a Source column and the expiry", async () => {
  const el = await mount();
  const created = [];
  const origCreate = URL.createObjectURL;
  URL.createObjectURL = jest.fn(() => "blob:x");
  URL.revokeObjectURL = jest.fn();
  const blobSpy = jest.spyOn(global, "Blob").mockImplementation((parts) => {
    created.push(parts[0]);
    return {};
  });
  el.shadowRoot.querySelector('[data-id="export"]').click();
  const csv = created[0];
  expect(csv.split("\n")[0]).toMatch(/^﻿"Source",/);
  expect(csv).toContain('"Bid",');
  expect(csv).toContain('"Load",');
  expect(csv.split("\n")[0]).toMatch(/"Expires on"\r?$/);
  blobSpy.mockRestore();
  URL.createObjectURL = origCreate;
});
```

(Adapt the export assertions to the existing export test's mocking style if one already stubs `Blob`/`URL`; keep the three expectations.)

Container (`laneBenchmark.test.js`): in the test that asserts the `search` payload, add `expect(payload.sourceFilter).toBe("ALL")`.

- [ ] **Step 2: Implement**

Filters JS: `DEFAULT_FILTERS` adds `sourceFilter: "ALL"`; add

```javascript
  sourceOptions = [
    { label: "All", value: "ALL" },
    { label: "Loads only", value: "LOADS" },
    { label: "Bids only", value: "BIDS" }
  ];
  handleSource(event) {
    this.update({ sourceFilter: event.detail.value });
  }
```

Filters HTML, before the Quote status radio group:

```html
<lightning-radio-group
  data-id="source"
  label="Source"
  type="button"
  options="{sourceOptions}"
  value="{value.sourceFilter}"
  onchange="{handleSource}"
></lightning-radio-group>
```

Results JS: in `viewRows` add

```javascript
      isBid: !!r.bid,
      bidExpiry: r.bid ? `Expires ${r.bid.expiresOn}` : "",
      bidClass: r.bid && r.bid.status === "Expired" ? "slds-text-color_weak bid-expired" : "",
      transitText: r.bid && r.bid.transitDays != null ? `${r.bid.transitDays} d transit` : "",
      fscText: r.bid && r.bid.fuelSurcharge != null ? `FSC ${Number(r.bid.fuelSurcharge).toFixed(2)}${r.bid.fscIncluded ? " (included)" : ""}` : "",
```

and change `acceptedText` to `r.bid ? "" : r.accepted ? "Accepted" : "Declined"`. `CSV_COLUMNS`: prepend `{ label: "Source", field: "source" }`, append `{ label: "Expires on", field: "bid.expiresOn" }`. `handleExport`: `const csv = toCsv(this._rows.map((r) => ({ ...r, source: r.bid ? "Bid" : "Load" })), CSV_COLUMNS);`.

Results HTML: in the Carrier cell after the button add

```html
<template lwc:if="{r.isBid}"
  ><span data-id="bid-badge" class="slds-badge slds-m-left_x-small"
    >Bid</span
  ></template
>
```

Flags cell becomes `<td data-id="flags" class="slds-cell-wrap"><span class={r.bidClass}>{r.hazmatText} {r.acceptedText} {r.bidExpiry}</span></td>`. Detail row: append ` · {r.transitText} {r.fscText}` inside the existing div (renders empty for loads). Row `class` attribute: add `class={r.bidClass}` on the `<tr>` so expired bids grey out.

CSS: add `.bid-expired td { opacity: 0.6; }`.

Container: `toServiceRequest()` adds `sourceFilter: r.sourceFilter,`.

- [ ] **Step 3: Run, lint, commit**

`npm test` (expected 62 + 5 = 67 or the count you reach; report it), `npm run lint`, prettier. Commit: `Lane Benchmark: source filter and bid rows`.

---

### Task 7: RfpController.projectsForAccount and rfpProjectsForAccount

**Files:**

- Create: `force-app/main/default/classes/RfpController.cls` (+meta), `RfpControllerTest.cls` (+meta)
- Create: `force-app/main/default/lwc/rfpProjectsForAccount/rfpProjectsForAccount.js`, `.html`, `.js-meta.xml`, `__tests__/rfpProjectsForAccount.test.js`
- Modify: manifest (ApexClass + LightningComponentBundle), CI/README lists

**Interfaces:**

- `@AuraEnabled(cacheable=true) public static List<RfpController.ProjectSummary> projectsForAccount(Id accountId)` — user mode; `ProjectSummary { Id id; String name; String status; Date dueDate; Decimal laneCount; Decimal costedCount; Decimal soldCount; Integer bidCount; List<String> fileNames; }` all `@AuraEnabled`. Ordered by `CreatedDate DESC`. Errors surface as `AuraHandledException` with a user sentence (copy `LaneBenchmarkController.userError`'s two-line setMessage pattern into a private `userError` here).
- LWC `c-rfp-projects-for-account`: `@api recordId`; `getRecord` wire on `Account.RecordType.DeveloperName`; renders only when the developer name is `Customer` or `New_Customer`; wires `projectsForAccount({ accountId: recordId })`; a row click navigates to the project record page (`NavigationMixin.Navigate` with `standard__recordPage`; 3b retargets it to the RFP tab).

- [ ] **Step 1: Failing tests**

```apex
@IsTest
private class RfpControllerTest {
  @IsTest
  static void projectsForAccountSummarisesLanesBidsAndFiles() {
    PricingTestDataFactory.Graph g = PricingTestDataFactory.createGraph();
    Pricing_Place__c mtl = RfpTestDataFactory.createPlace(
      'Montréal',
      'QC',
      'CA',
      45.5019,
      -73.5674,
      'H1A'
    );
    Pricing_Place__c tor = RfpTestDataFactory.createPlace(
      'Toronto',
      'ON',
      'CA',
      43.6532,
      -79.3832,
      'M5V'
    );
    RFP_Project__c p = RfpTestDataFactory.createProject(g.customer);
    RFP_Lane__c lane = RfpTestDataFactory.createLane(p, mtl, tor);
    lane.Cost__c = 1000;
    lane.Sell__c = 1150;
    update lane;
    RfpTestDataFactory.createLane(p, tor, mtl);
    BenchmarkRateService.save(RfpTestDataFactory.buildBid(lane, 1000));
    ContentVersion cv = new ContentVersion(
      Title = 'lanes.xlsx',
      PathOnClient = 'lanes.xlsx',
      VersionData = Blob.valueOf('x')
    );
    insert cv;
    Id docId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id]
    .ContentDocumentId;
    insert new ContentDocumentLink(
      ContentDocumentId = docId,
      LinkedEntityId = p.Id,
      ShareType = 'V'
    );

    Test.startTest();
    List<RfpController.ProjectSummary> out = RfpController.projectsForAccount(
      g.customer.Id
    );
    Test.stopTest();

    System.assertEquals(1, out.size());
    System.assertEquals('Test RFP', out[0].name);
    System.assertEquals('Draft', out[0].status);
    System.assertEquals(2, out[0].laneCount);
    System.assertEquals(1, out[0].costedCount);
    System.assertEquals(1, out[0].soldCount);
    System.assertEquals(1, out[0].bidCount);
    System.assertEquals(new List<String>{ 'lanes.xlsx' }, out[0].fileNames);
    System.assertEquals(
      0,
      RfpController.projectsForAccount(g.vendor.Id).size()
    );
  }
}
```

- [ ] **Step 2: Implement**

```apex
/**
 * @AuraEnabled entry points of the RFP tool. Phase 3a ships projectsForAccount (the customer
 * Account component); phase 3b adds the workbench methods. Runs in user mode: RFP records are
 * created and read by pricing users under their own permissions.
 */
public with sharing class RfpController {
  public class ProjectSummary {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public Date dueDate;
    @AuraEnabled
    public Decimal laneCount = 0;
    @AuraEnabled
    public Decimal costedCount = 0;
    @AuraEnabled
    public Decimal soldCount = 0;
    @AuraEnabled
    public Integer bidCount = 0;
    @AuraEnabled
    public List<String> fileNames = new List<String>();
  }

  @AuraEnabled(cacheable=true)
  public static List<ProjectSummary> projectsForAccount(Id accountId) {
    try {
      Map<Id, ProjectSummary> byId = new Map<Id, ProjectSummary>();
      for (RFP_Project__c p : [
        SELECT
          Id,
          Name,
          Status__c,
          Due_Date__c,
          Lane_Count__c,
          Costed_Count__c,
          Sold_Count__c
        FROM RFP_Project__c
        WHERE Customer__c = :accountId
        WITH USER_MODE
        ORDER BY CreatedDate DESC
        LIMIT 200
      ]) {
        byId.put(p.Id, toSummary(p));
      }
      if (byId.isEmpty()) {
        return new List<ProjectSummary>();
      }
      addBidCounts(byId);
      addFileNames(byId);
      return byId.values();
    } catch (QueryException e) {
      throw userError('RFP projects could not be loaded for this account.');
    }
  }

  private static ProjectSummary toSummary(RFP_Project__c p) {
    ProjectSummary s = new ProjectSummary();
    s.id = p.Id;
    s.name = p.Name;
    s.status = p.Status__c;
    s.dueDate = p.Due_Date__c;
    s.laneCount = p.Lane_Count__c ?? 0;
    s.costedCount = p.Costed_Count__c ?? 0;
    s.soldCount = p.Sold_Count__c ?? 0;
    return s;
  }

  private static void addBidCounts(Map<Id, ProjectSummary> byId) {
    for (AggregateResult ar : [
      SELECT RFP_Project__c pid, COUNT(Id) n
      FROM Benchmark_Rate__c
      WHERE RFP_Project__c IN :byId.keySet()
      WITH USER_MODE
      GROUP BY RFP_Project__c
    ]) {
      byId.get((Id) ar.get('pid')).bidCount = (Integer) ar.get('n');
    }
  }

  private static void addFileNames(Map<Id, ProjectSummary> byId) {
    for (ContentDocumentLink l : [
      SELECT LinkedEntityId, ContentDocument.Title
      FROM ContentDocumentLink
      WHERE LinkedEntityId IN :byId.keySet()
      WITH USER_MODE
    ]) {
      byId.get(l.LinkedEntityId).fileNames.add(l.ContentDocument.Title);
    }
  }

  private static AuraHandledException userError(String message) {
    AuraHandledException e = new AuraHandledException(message);
    e.setMessage(message);
    return e;
  }
}
```

(`Map.values()` preserves insertion order, which is the query order.)

LWC `rfpProjectsForAccount.js`:

```javascript
import { LightningElement, api, wire } from "lwc";
import { getRecord } from "lightning/uiRecordApi";
import { NavigationMixin } from "lightning/navigation";
import projectsForAccount from "@salesforce/apex/RfpController.projectsForAccount";

const RT_FIELD = "Account.RecordType.DeveloperName";
const CUSTOMER_TYPES = new Set(["Customer", "New_Customer"]);

export default class RfpProjectsForAccount extends NavigationMixin(
  LightningElement
) {
  @api recordId;
  recordTypeName = null;
  projects = [];
  error = null;

  @wire(getRecord, { recordId: "$recordId", fields: [RT_FIELD] })
  wiredAccount({ data, error }) {
    if (data) {
      this.recordTypeName =
        data.fields.RecordType.value?.fields?.DeveloperName?.value ?? null;
    } else if (error) {
      this.recordTypeName = null;
    }
  }

  @wire(projectsForAccount, { accountId: "$recordId" })
  wiredProjects({ data, error }) {
    if (data) {
      this.projects = data.map((p) => ({
        ...p,
        files: (p.fileNames || []).join(", ")
      }));
      this.error = null;
    } else if (error) {
      this.projects = [];
      this.error = error?.body?.message || "RFP projects could not be loaded.";
    }
  }

  get isCustomer() {
    return CUSTOMER_TYPES.has(this.recordTypeName);
  }
  get hasProjects() {
    return this.projects.length > 0;
  }

  handleOpen(event) {
    const id = event.currentTarget.dataset.id;
    this[NavigationMixin.Navigate]({
      type: "standard__recordPage",
      attributes: {
        recordId: id,
        objectApiName: "RFP_Project__c",
        actionName: "view"
      }
    });
  }
}
```

`rfpProjectsForAccount.html`:

```html
<template>
  <template lwc:if="{isCustomer}">
    <lightning-card title="RFP Projects" icon-name="standard:contract">
      <div class="slds-p-horizontal_small">
        <template lwc:if="{error}"
          ><p data-id="error" class="slds-text-color_error">
            {error}
          </p></template
        >
        <template lwc:if="{hasProjects}">
          <table class="slds-table slds-table_bordered slds-table_cell-buffer">
            <thead>
              <tr>
                <th scope="col">Project</th>
                <th scope="col">Status</th>
                <th scope="col">Due</th>
                <th scope="col">Lanes</th>
                <th scope="col">Costed</th>
                <th scope="col">Sold</th>
                <th scope="col">Bids</th>
                <th scope="col">Files</th>
              </tr>
            </thead>
            <tbody>
              <template for:each="{projects}" for:item="p">
                <tr key="{p.id}" data-id="project-row">
                  <td>
                    <button
                      class="slds-button slds-text-link"
                      data-id="{p.id}"
                      onclick="{handleOpen}"
                    >
                      {p.name}
                    </button>
                  </td>
                  <td>{p.status}</td>
                  <td>{p.dueDate}</td>
                  <td>{p.laneCount}</td>
                  <td>{p.costedCount}</td>
                  <td>{p.soldCount}</td>
                  <td>{p.bidCount}</td>
                  <td class="slds-cell-wrap">{p.files}</td>
                </tr>
              </template>
            </tbody>
          </table>
        </template>
        <template lwc:else
          ><p class="slds-text-color_weak slds-p-around_small">
            No RFP projects yet.
          </p></template
        >
      </div>
    </lightning-card>
  </template>
</template>
```

`rfpProjectsForAccount.js-meta.xml`:

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<LightningComponentBundle xmlns="http://soap.sforce.com/2006/04/metadata">
    <apiVersion>64.0</apiVersion>
    <isExposed>true</isExposed>
    <masterLabel>RFP Projects (customer)</masterLabel>
    <description
  >Lists the RFP projects, files and bids for a customer account. Renders nothing on non-customer record types.</description>
    <targets>
        <target>lightning__RecordPage</target>
    </targets>
    <targetConfigs>
        <targetConfig targets="lightning__RecordPage">
            <objects>
                <object>Account</object>
            </objects>
        </targetConfig>
    </targetConfigs>
</LightningComponentBundle>
```

Jest (`__tests__/rfpProjectsForAccount.test.js`), using `@salesforce/sfdx-lwc-jest`'s wire adapters (`getRecord` from `lightning/uiRecordApi` is auto-stubbed; emit with `getRecord.emit(...)`; mock the Apex wire with `jest.mock("@salesforce/apex/RfpController.projectsForAccount", () => { const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest"); return { default: createApexTestWireAdapter(jest.fn()) }; }, { virtual: true })`):

```javascript
it("renders projects for a Customer account and nothing for a Carrier", async () => {
  const el = mount("001x");
  getRecord.emit({
    fields: {
      RecordType: {
        value: { fields: { DeveloperName: { value: "Customer" } } }
      }
    }
  });
  projectsForAccount.emit([
    {
      id: "a1",
      name: "Costco Q4",
      status: "Pricing",
      dueDate: "2026-10-01",
      laneCount: 12,
      costedCount: 4,
      soldCount: 3,
      bidCount: 5,
      fileNames: ["lanes.xlsx"]
    }
  ]);
  await flush();
  const rows = el.shadowRoot.querySelectorAll('[data-id="project-row"]');
  expect(rows.length).toBe(1);
  expect(rows[0].textContent).toContain("Costco Q4");
  expect(rows[0].textContent).toContain("lanes.xlsx");

  getRecord.emit({
    fields: {
      RecordType: { value: { fields: { DeveloperName: { value: "Carrier" } } } }
    }
  });
  await flush();
  expect(el.shadowRoot.querySelector("lightning-card")).toBeNull();
});

it("shows the empty state and the error text", async () => {
  const el = mount("001y");
  getRecord.emit({
    fields: {
      RecordType: {
        value: { fields: { DeveloperName: { value: "New_Customer" } } }
      }
    }
  });
  projectsForAccount.emit([]);
  await flush();
  expect(el.shadowRoot.textContent).toContain("No RFP projects yet.");
  projectsForAccount.error({ body: { message: "boom" } });
  await flush();
  expect(el.shadowRoot.querySelector('[data-id="error"]').textContent).toBe(
    "boom"
  );
});
```

- [ ] **Step 3: Register, deploy, tests, PMD, commit**

Manifest: ApexClass `RfpController`, `RfpControllerTest`; LightningComponentBundle `rfpProjectsForAccount`. CI/README lists gain `RfpControllerTest` (13 classes). Deploy (expected 74/74). `npm test` green. PMD clean. Commit: `Add RfpController.projectsForAccount and the customer Account component`.

Then in PostProduc, as a manual step: open a customer Account, App Builder → edit the page pricing uses → drag "RFP Projects (customer)" into the right sidebar → activate for the org or the app as the admin prefers. Record the page's developer name in the report (the controller carries it into the spec Outcome).

---

### Task 8: Docs and outcome

**Files:**

- Modify: `README.md` (section "RFP Tool (phase 3a)": objects, permission sets, the Source filter, the Account component and how to add it in App Builder, test-class list), `docs/superpowers/specs/2026-09-10-phase-3-rfp-tool-design.md` (append `## Outcome — 3a (<date>)`: deploy ids, test counts, rulings 1-9 from this plan's header as recorded adaptations, the Account page used), `docs/superpowers/specs/2026-09-07-pricing-department-roadmap.md` (phase 3 row: "3a done <date>; 3b next").

- [ ] **Step 1: Write the docs** (no invented numbers: take every id and count from the task reports).
- [ ] **Step 2: Commit** `Document phase 3a and record its outcome`.

---

## Self-review

**Spec coverage (3a scope).** Objects and fields: Task 1 (with rulings 3 and 7). Permission sets: Task 1 (+ Task 3 registers `RFP_Tool_User`). `BenchmarkRateService` with lane keys from places: Task 3 (ruling 9). `sourceFilter`/`Row.bid`/`BidSearchQueryBuilder`: Task 4 (rulings 1, 2, 4). Merge and stats over both sources, expired handling under BIDS: Task 5 (ruling 8). Lane Benchmark Source control, badge, expiry, CSV Source column: Task 6. `rfpProjectsForAccount` + `RfpController.projectsForAccount`: Task 7 (rulings 5, 6). Docs: Task 8. Not in 3a by design: tab/app/page, import, history, workbench, export (3b).

**Placeholders.** None: every field is in the generator, every class body is written, every test is written. Two documented contingencies (lookup filter rejection, `ALL` reserved) name the exact fallback.

**Type consistency.** `RowSource` values ALL/LOADS/BIDS used identically in Apex (`LaneSearchRequest.RowSource.X`), the LWC (`"ALL"`, `"LOADS"`, `"BIDS"`) and tests. `BidDetail` fields (`rateId, expiresOn, status, transitDays, fuelSurcharge, fscIncluded`) match `toRow`, the Jest fixture and the results template. Bind prefixes `bO`/`bD`/`b*` used identically in builder and tests. `BenchmarkRateService.save` returns the reloaded record with `Carrier_Display__c`/`Status__c` as the tests read. `RfpController.ProjectSummary` fields match the LWC's use and the Jest emit.
