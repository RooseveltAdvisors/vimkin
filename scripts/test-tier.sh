#!/bin/bash
# test-tier.sh — run ONE tier of the test suite.
#
#   bash scripts/test-tier.sh unit
#   bash scripts/test-tier.sh integration
#   bash scripts/test-tier.sh acceptance
#
# Any extra arguments are forwarded to `swift test` (e.g. --scratch-path).
# The tier's `--filter` regex is derived from the `.tags(...)` on each @Suite by
# scripts/tiers.sh — nothing here is hand-maintained.
#
# Runs through scripts/test.sh so the CommandLineTools framework-path handling
# (needed on a machine without full Xcode) applies to tier runs too.
set -euo pipefail

TIER="${1:-}"
[ -n "$TIER" ] || { echo "usage: test-tier.sh {unit|integration|acceptance} [swift test args...]" >&2; exit 2; }
shift

HERE="$(cd "$(dirname "$0")" && pwd)"
FILTER="$("$HERE/tiers.sh" filter "$TIER")"

exec bash "$HERE/test.sh" --filter "$FILTER" "$@"
