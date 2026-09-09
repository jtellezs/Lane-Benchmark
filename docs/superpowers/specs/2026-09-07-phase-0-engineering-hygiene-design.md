# Phase 0: Engineering Hygiene

Status: approved design, spec under user review. Parent: [roadmap](2026-09-07-pricing-department-roadmap.md).

## Purpose

Give the project a safe place to develop, an automated definition of "done",
and tests that describe real behavior, before any feature work. Ship the
already-known bugs as the first change through that pipeline.

## Environments

| Org        | Alias       | Role                                                                           | Data |
| ---------- | ----------- | ------------------------------------------------------------------------------ | ---- |
| Full       | `Full`      | Develop, test, CI. Real deploys land here.                                     | Real |
| PostProduc | `sandbox`   | UAT after sign-off in Full                                                     | Real |
| Production | `vscodeOrg` | Live. Deployed after UAT sign-off; never from a laptop without a validated run | Real |

DevPro (Developer Pro) was evaluated first for development and CI, but retired: a
Developer Pro sandbox cannot insert `rtms__Load__c` because the Revenova managed triggers
need configuration records that only a data-carrying sandbox provides, so the org's own
tests fail there.

Refresh runbook (DevPro was refreshed 2026-09-08 from production, job
`0GROG0000002Dqn4AE`; previous refresh took ~70 minutes):

1. `sf org refresh sandbox -n DevPro -o vscodeOrg --async --no-prompt`
2. Check: `sf org resume sandbox --job-id <id> -o ienescu@trans-pro.com`
   or query `SandboxProcess` on production.
3. A refresh creates a new org id and appends `.invalid` to every user email.
   Remove the dead CLI entry (`sf org logout -o devpro-sandbox --no-prompt`),
   then log in: `sf org login web -a devpro -r https://test.salesforce.com`.
4. Regenerate the CI secret (below) because the auth URL is per org id.
5. Retrieve the project manifest from the refreshed DevPro into a scratch
   folder and diff against the repo. The repo is the reference; deploy it to
   DevPro. Any difference where production is newer than what we pulled from
   PostProduc is reviewed component by component before overwriting the repo.

Promotion path: pull request → CI validates against Full → merge to `main`
→ manual deploy to Full → manual deploy to PostProduc for UAT → production.
CI validates only; it never deploys in phase 0.

## Repository and tooling

- Install the scaffolded Node toolchain and commit `package-lock.json`:
  `@salesforce/sfdx-lwc-jest`, ESLint with the LWC config, Prettier with the
  Apex and XML plugins, Husky pre-commit running lint-staged.
- Add `force-app/main/default/profiles/**` to `.forceignore`. The scoped
  `Pricing` profile stays in the repo for reference and is never deployed.
- Rename the project to `PricingDepartment` in `sfdx-project.json`.
- Docs: `docs/superpowers/specs/` for the roadmap and one spec per phase,
  `docs/superpowers/plans/` for implementation plans.
- Git: no attribution trailers in commits. Push `origin` (personal) first,
  then `tplm`; the README documents the credential-helper command for `tplm`.

## Continuous integration

One workflow file, `.github/workflows/ci.yml`, identical in both repositories
(`IulianEnescu78/PricingDepartment` and `TPLM/PricingDepartment`), triggered on
`pull_request` and on `push` to `main`. Three independent jobs:

| Job    | Steps                                                                                                                                                                                                                                                                        | Fails when                                             |
| ------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------ |
| `lwc`  | `npm ci`, ESLint, Prettier check, `sfdx-lwc-jest --coverage`                                                                                                                                                                                                                 | any lint error, formatting drift, or failing Jest test |
| `apex` | install `@salesforce/cli`, `sf org login sfdx-url` from secret, `sf project deploy validate -x manifest/package.xml --post-destructive-changes manifest/destructiveChangesPost.xml --test-level RunSpecifiedTests --tests PricingDepartmentControllerTest --target-org Full` | compile error, test failure, or deployment error       |
| `pmd`  | PMD (latest 7.x) with the Apex quickstart ruleset on `force-app/**/*.cls`, results as PR annotations                                                                                                                                                                         | any Priority 1 or 2 violation                          |

Secret: `SFDX_AUTH_URL_FULL`, set in the TPLM repository only
(`TPLM/PricingDepartment`). Obtained after the Full login with
`sf org auth show-sfdx-auth-url -o Full --json` (current CLI versions redact
the URL from `sf org display`), piped straight into `gh secret set` (work
token for TPLM). The value is never printed, echoed, or written to a file.
Rotated after every Full refresh. The personal mirror
(`IulianEnescu78/PricingDepartment`) has no org secret; its `apex` job detects
that (`secrets.SFDX_AUTH_URL_FULL != ''` read into a job-level `env`) and
skips its Salesforce steps instead of failing, so the job still succeeds
there. The `apex` job only validates for real in the TPLM repository.

Branch protection on `main`: `IulianEnescu78/PricingDepartment` requires
`["lwc", "pmd"]` (no secret there, so `apex` cannot be a required context);
`TPLM/PricingDepartment` requires `["lwc", "apex", "pmd"]`. Both require a
pull request and no force pushes. The `tplm` mirror push after merge is done
by the developer, not by CI.

Concurrency: the `apex` job uses a concurrency group per branch so two pushes
in a row do not run two validations against Full at once.

## Tests

Apex, in Full:

- Retire `PricingDepartmentControllerTest3` (calls the controller with a stale
  8-argument signature; does not compile) and
  `PricingDepartmentController_TGN_TEST` (asserts nothing) via
  `manifest/destructiveChangesPost.xml`.
- `PricingTestDataFactory` (`@IsTest` utility) builds the minimum valid graph
  the Revenova managed triggers accept: customer Account, vendor Account with
  `rtms__TransportationProfile__c`, quote Contact, `rtms__CarrierService__c`,
  `rtms__Mode__c`, `rtms__EquipmentType__c` (with category), `rtms__Load__c`
  with first and last `rtms__Stop__c` on geocoded location Accounts, and
  `rtms__CarrierQuote__c` rows. Discovering the required fields is the first
  task in Full; the result is captured once in the factory.
- `PricingDepartmentControllerTest` asserts behavior, one method per rule:
  origin filter, destination filter, date window boundary, hazmat, market
  test (customer name), accepted and declined flags, excluded contact,
  in-Apex deduplication of identical quotes, distinct mode list, and the
  500-row limit.

LWC, with Jest:

- Extract `calculateStats` and the row-shaping logic from
  `pricingDepartment.js` into a pure module `lwc/quoteStats/quoteStats.js`
  (no DOM, no wire). Unit-test min, max, average, zero handling, and row
  classes.
- Component tests for `pricingDepartment`: renders with mocked Apex, each
  filter handler updates state, the accepted-quotes checkbox no longer
  throws, reset restores defaults.

## Bug-fix pull request

The first change through the pipeline. Scope is limited to what is already
known; no feature work.

- LWC: fix the ReferenceError in `handleAcceptedQuotesFilterChange`; delete
  the unused `fetchModeOptions`; set `apiVersion` to 64.0.
- Apex: keep `without sharing` and add a class-level comment that it is
  intentional (pricing must see every team's quotes). Replace the hardcoded
  Contact Id with custom metadata type `Pricing_Department_Setting__mdt`
  (record `Default`, field `Excluded_Contact_Ids__c`, comma-separated). The
  controller reads it once per transaction.
- Permission set `Pricing_Department_User`: tab visibility, Apex class
  access, and read on every Carrier Quote field the page uses, including
  `Quote_Date__c`. Existing profile grants are untouched. From now on access
  is granted by assigning this permission set.

## Out of scope for phase 0

Any change to Load, Stop, or Place data; any new filter or UI element; any
deploy to PostProduc or production; touching profile assignments.

## Definition of done

1. Full refreshed, logged in as `Full`, repo deployed to it, diff against
   the refreshed org reviewed and resolved.
2. `npm ci` clean; Husky pre-commit active; lockfile committed.
3. `ci.yml` green on a real pull request in both repos; branch protection on.
4. Old test classes gone from Full; new factory and controller tests pass
   in Full; Jest passes locally and in CI.
5. Bug-fix PR merged through the pipeline and deployed to Full only.
6. README updated with the environment table, runbook, and CI notes.
