#!/usr/bin/env bash
#
# Install the Pricing Department app into a sandbox - the reinstall to run after a
# sandbox refresh, when the org comes back as a copy of production without this branch.
#
# It deploys every component in manifest/package.xml, assigns the two permission sets,
# and then reports the two things no deploy can carry, because they are data rather
# than metadata: the Mapbox key (a value in the TPRO_KPI__c custom setting) and the
# Pricing_Place__c dictionary (records built by a batch).
#
#   scripts/install-sandbox.sh                   # deploy + assign, then report
#   scripts/install-sandbox.sh --dry-run         # validate only, change nothing
#   scripts/install-sandbox.sh --build-places    # also start the dictionary batch
#   scripts/install-sandbox.sh --org my-sandbox  # a sandbox other than `sandbox`
#
# Production is deliberately out of scope. It goes live through the runbook in
# README.md ("Production is the admin's step"), which runs the full test suite and the
# one-time destructive manifest. This script refuses to run against a production org.

set -euo pipefail

ORG="sandbox"
BUILD_PLACES="false"
DRY_RUN="false"

PERMISSION_SETS=(Lane_Benchmark_User RFP_Tool_User)

usage() {
  sed -n '3,18p' "${BASH_SOURCE[0]}" | sed 's|^# \{0,1\}||'
}

fail() {
  printf '\nerror: %s\n' "$1" >&2
  exit 1
}

step() {
  printf '\n== %s\n' "$1"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --org)
      [ $# -ge 2 ] || fail "--org needs an alias"
      ORG="$2"
      shift 2
      ;;
    --build-places)
      BUILD_PLACES="true"
      shift
      ;;
    --dry-run)
      DRY_RUN="true"
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      fail "unknown option: $1 (try --help)"
      ;;
  esac
done

cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

command -v sf >/dev/null 2>&1 || fail "the Salesforce CLI (sf) is not on PATH"
[ -f manifest/package.xml ] || fail "manifest/package.xml not found - run this from the repo"

# Reads one value from a single-row query. Keeps the script free of jq and node.
org_value() {
  sf data query -o "$ORG" -q "$1" --result-format csv 2>/dev/null | sed -n '2p' | tr -d '"\r'
}

# Aggregates render as an empty row in CSV, so counts are read from the JSON totalSize.
org_count() {
  sf data query -o "$ORG" -q "$1" --json 2>/dev/null |
    sed -n 's/.*"totalSize"[: ]*\([0-9][0-9]*\).*/\1/p' | head -1
}

step "Checking org '$ORG'"
IS_SANDBOX="$(org_value "SELECT IsSandbox FROM Organization" || true)"
[ -n "$IS_SANDBOX" ] || fail "could not query org '$ORG' - is the alias right and the session live? (sf org login web -a $ORG)"
[ "$IS_SANDBOX" = "true" ] || fail "org '$ORG' is not a sandbox. Production goes live through the runbook in README.md, not this script."
printf 'sandbox confirmed\n'

step "Deploying manifest/package.xml"
# An `[ ... ] && ...` one-liner here would abort the whole script under `set -e`
# whenever the test is false, so the flag is applied with a full `if`.
DEPLOY_ARGS=(-x manifest/package.xml -o "$ORG" -l NoTestRun -w 30)
if [ "$DRY_RUN" = "true" ]; then
  DEPLOY_ARGS+=(--dry-run)
fi
sf project deploy start "${DEPLOY_ARGS[@]}"

if [ "$DRY_RUN" = "true" ]; then
  printf '\nDry run: nothing was changed. Permission sets and data were left alone.\n'
  exit 0
fi

step "Assigning permission sets"
for permset in "${PERMISSION_SETS[@]}"; do
  if output="$(sf org assign permset -n "$permset" -o "$ORG" 2>&1)"; then
    printf '%s assigned\n' "$permset"
  elif printf '%s' "$output" | grep -qi 'duplicate\|already'; then
    printf '%s already assigned\n' "$permset"
  else
    printf '%s\n' "$output" >&2
    fail "could not assign $permset"
  fi
done

step "Checking what the deploy could not carry"

# Never selects Mapbox_Api_Key__c itself, so the token cannot reach a terminal or a log.
MAPBOX_SET="$(org_value "SELECT Id FROM TPRO_KPI__c WHERE Mapbox_Api_Key__c != null LIMIT 1" || true)"
PLACE_COUNT="$(org_count "SELECT COUNT() FROM Pricing_Place__c" || true)"

if [ "$BUILD_PLACES" = "true" ]; then
  printf 'Starting the place dictionary batch\n'
  sf apex run -o "$ORG" -f scripts/apex/buildPlaces.apex
  printf 'Batch queued - watch it in Setup > Apex Jobs.\n'
fi

step "Result"
printf 'Deployed and permission sets assigned in %s.\n\n' "$ORG"

REMAINING=0

if [ -z "$MAPBOX_SET" ]; then
  REMAINING=$((REMAINING + 1))
  cat <<'EOF'
[ ] Mapbox key. Setup > Custom Settings > TPRO KPI > Manage > the org default record,
    field Mapbox_Api_Key__c: paste the public pk. token. Without it the map picker,
    the radius preview and truck routing stay dark. Restrict the token in the Mapbox
    account to *.my.salesforce.com, *.lightning.force.com and *.sandbox.my.salesforce.com.
EOF
else
  printf '[x] Mapbox key is set.\n'
fi

# --build-places is tested first: the batch has already been queued above, so an empty
# dictionary is being dealt with and must not be reported as a step still to do.
if [ "$BUILD_PLACES" = "true" ]; then
  printf '[x] Place dictionary batch started (it held %s places). Watch Setup > Apex Jobs;\n' "${PLACE_COUNT:-0}"
  printf '    the lane pickers fill in as it runs, which took about an hour in PostProduc.\n'
elif [ -z "$PLACE_COUNT" ] || [ "$PLACE_COUNT" = "0" ]; then
  REMAINING=$((REMAINING + 1))
  cat <<EOF
[ ] Place dictionary is empty. Build it:
        sf apex run -o $ORG -f scripts/apex/buildPlaces.apex
    or rerun this script with --build-places. It runs asynchronously (about an hour in
    PostProduc) and the lane pickers stay empty until it finishes.
EOF
else
  printf '[x] Place dictionary has %s places.\n' "$PLACE_COUNT"
fi

if [ "$REMAINING" -eq 0 ]; then
  printf '\nNothing left to do by hand. Open the TransPro app and check the Lane Benchmark tab.\n'
else
  printf '\n%s manual step(s) above, then open the TransPro app and check the Lane Benchmark tab.\n' "$REMAINING"
fi
