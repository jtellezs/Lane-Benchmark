#!/usr/bin/env bash
# Runs the same PMD gate CI runs, so a violation is caught before the push rather than after.
# Downloads PMD once into pmd-bin-$PMD_VERSION/ (git-ignored) and reuses it thereafter.
set -euo pipefail

PMD_VERSION="${PMD_VERSION:-7.15.0}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PMD_HOME="$ROOT/pmd-bin-$PMD_VERSION"

if [ ! -x "$PMD_HOME/bin/pmd" ]; then
  echo "Downloading PMD $PMD_VERSION..."
  TMP="$(mktemp -d)"
  curl -sSL -o "$TMP/pmd.zip" \
    "https://github.com/pmd/pmd/releases/download/pmd_releases%2F$PMD_VERSION/pmd-dist-$PMD_VERSION-bin.zip"
  unzip -q "$TMP/pmd.zip" -d "$ROOT"
  rm -rf "$TMP"
fi

# Mirrors .github/workflows/ci.yml exactly: same ruleset, same priority, same fail-on-violation.
exec "$PMD_HOME/bin/pmd" check \
  --dir "$ROOT/force-app" \
  --rulesets "$ROOT/config/pmd-ruleset.xml" \
  --minimum-priority 3 \
  --format text \
  --fail-on-violation \
  --no-progress
