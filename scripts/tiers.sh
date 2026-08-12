#!/bin/bash
# tiers.sh — the test taxonomy, derived from the source rather than maintained.
#
# The `.tags(.unit) / .tags(.integration) / .tags(.acceptance)` marker on each
# `@Suite` IS the source of truth (see Tests/VimkinTests/TestTiers.swift). This
# script reads those tags back out so a tier can be run on its own, and so the
# gate can prove no suite escaped classification.
#
#   scripts/tiers.sh check            # every @Suite carries exactly one tier
#   scripts/tiers.sh list <tier>      # the suite type names in a tier
#   scripts/tiers.sh filter <tier>    # the `swift test --filter` regex for a tier
#   scripts/tiers.sh counts           # suite counts per tier
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_DIR="$ROOT/Tests/VimkinTests"

# Emits: <tier>\t<SuiteTypeName>\t<file>\t<tagCount>
# `tier` is "none" when a @Suite carries no tier tag at all.
scan() {
  find "$TEST_DIR" -name '*.swift' ! -name 'TestTiers.swift' | sort | xargs awk '
    FNR == 1 { pending = 0 }
    /@Suite/ {
      pending = 1; tier = "none"; ntags = 0
      if ($0 ~ /\.tags\(\.unit\)/)        { tier = "unit";        ntags++ }
      if ($0 ~ /\.tags\(\.integration\)/) { tier = "integration"; ntags++ }
      if ($0 ~ /\.tags\(\.acceptance\)/)  { tier = "acceptance";  ntags++ }
    }
    pending && match($0, /struct[ \t]+[A-Za-z_][A-Za-z0-9_]*/) {
      name = substr($0, RSTART, RLENGTH)
      sub(/^struct[ \t]+/, "", name)
      printf "%s\t%s\t%s\t%d\n", tier, name, FILENAME, ntags
      pending = 0
    }
  '
}

valid_tier() {
  case "${1:-}" in
    unit | integration | acceptance) ;;
    *) echo "tiers.sh: unknown tier '${1:-}' (want: unit|integration|acceptance)" >&2; exit 2 ;;
  esac
}

cmd_list() {
  valid_tier "${1:-}"
  scan | awk -F'\t' -v t="$1" '$1 == t { print $2 }' | sort
}

# Anchored with a trailing "/" (the separator between the suite type name and
# the test name in a swift-testing ID) so a suite name that is a prefix of
# another — TerrainMapTests vs TerrainMapContentTests — cannot bleed across
# tiers. The gate proves this holds by checking the tier counts sum to the
# full-run count.
cmd_filter() {
  valid_tier "${1:-}"
  local names
  names="$(cmd_list "$1" | paste -sd '|' -)"
  [ -n "$names" ] || { echo "tiers.sh: tier '$1' has no suites" >&2; exit 1; }
  printf '(%s)/' "$names"
}

cmd_check() {
  local rows bad_none bad_multi dupes rc=0
  rows="$(scan)"

  bad_none="$(printf '%s\n' "$rows" | awk -F'\t' '$1 == "none" { print "  " $2 "  (" $3 ")" }')"
  if [ -n "$bad_none" ]; then
    echo "FAIL: @Suite with no tier tag — add .tags(.unit|.integration|.acceptance):" >&2
    printf '%s\n' "$bad_none" >&2
    rc=1
  fi

  bad_multi="$(printf '%s\n' "$rows" | awk -F'\t' '$4 > 1 { print "  " $2 "  (" $3 ")" }')"
  if [ -n "$bad_multi" ]; then
    echo "FAIL: @Suite with more than one tier tag — a suite belongs to exactly one tier:" >&2
    printf '%s\n' "$bad_multi" >&2
    rc=1
  fi

  dupes="$(printf '%s\n' "$rows" | awk -F'\t' '{ print $2 }' | sort | uniq -d)"
  if [ -n "$dupes" ]; then
    echo "FAIL: duplicate suite type names — the --filter regex cannot separate them:" >&2
    printf '  %s\n' "$dupes" >&2
    rc=1
  fi

  [ "$rc" -eq 0 ] && echo "OK: every @Suite carries exactly one tier tag."
  return "$rc"
}

cmd_counts() {
  scan | awk -F'\t' '
    { n[$1]++; total++ }
    END {
      printf "unit         %3d suites\n", n["unit"]
      printf "integration  %3d suites\n", n["integration"]
      printf "acceptance   %3d suites\n", n["acceptance"]
      if (n["none"]) printf "UNCLASSIFIED %3d suites\n", n["none"]
      printf "total        %3d suites\n", total
    }'
}

case "${1:-check}" in
  check)   cmd_check ;;
  list)    shift; cmd_list "${1:-}" ;;
  filter)  shift; cmd_filter "${1:-}" ;;
  counts)  cmd_counts ;;
  *) echo "usage: tiers.sh {check|list <tier>|filter <tier>|counts}" >&2; exit 2 ;;
esac
