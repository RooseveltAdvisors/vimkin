#!/bin/bash
# gate.sh — the Vimkin release gate. One command, every check, same on a laptop
# and on CI (.github/workflows/ci.yml runs this exact script, so local and CI
# cannot drift).
#
#   bash scripts/gate.sh [version]
#
# Stages, each PASS/FAIL with a timing:
#   1  taxonomy      every @Suite carries exactly one tier tag
#   2  dependencies  Package.swift declares no third-party dependency
#   3  build         debug build, warnings-as-errors
#   4  warnings      build log contains no `warning:` of any kind
#   5  test:unit     tier 1 — pure logic
#   6  test:integr.  tier 2 — real collaborators
#   7  test:accept.  tier 3 — headless UI contracts
#   8  test:all      the whole suite, and the three tiers must partition it
#   9  app-bundle    release build + Vimkin.app assembles, ad-hoc signature valid
#  10  info-plist    plutil -lint plus the keys the bundle cannot launch without
#  11  dmg           DMG builds, mounts, and contains the app
#  12  checksum      the published sha256 verifies against the DMG
#
# Escape hatches (for inner-loop use only — never for a release):
#   GATE_SKIP_PACKAGING=1   skip stages 9-12
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1

VERSION="${1:-0.0.0-gate}"
SCRATCH="$ROOT/.build/gate"
LOG_DIR="$ROOT/.build/gate-logs"
# Warnings-as-errors is the primary guard. It is sound across incremental
# builds: SwiftPM treats a flag change as a new build configuration, so every
# object in this scratch path was compiled under the flag and is warning-free.
WERROR=(-Xswiftc -warnings-as-errors)

mkdir -p "$LOG_DIR"
MD_SUMMARY="$LOG_DIR/summary.md"
{
  echo "### Vimkin release gate — \`$VERSION\`"
  echo
  echo "| | stage | time | detail |"
  echo "|---|---|---|---|"
} > "$MD_SUMMARY"

BOLD=""; RED=""; GREEN=""; DIM=""; OFF=""
if [ -t 1 ]; then BOLD=$'\033[1m'; RED=$'\033[31m'; GREEN=$'\033[32m'; DIM=$'\033[2m'; OFF=$'\033[0m'; fi

FAILURES=0
STAGE_NO=0
SUMMARY=""

stage_start() {
  STAGE_NO=$((STAGE_NO + 1))
  STAGE_NAME="$1"
  STAGE_T0=$(date +%s)
  printf '%s' "${BOLD}[$STAGE_NO/12] ${STAGE_NAME}${OFF} ... "
}

stage_end() {  # stage_end <rc> [detail]
  local rc="$1" detail="${2:-}" verdict elapsed=$(( $(date +%s) - STAGE_T0 ))
  if [ "$rc" -eq 0 ]; then verdict=PASS; else verdict=FAIL; FAILURES=$((FAILURES + 1)); fi
  if [ "$rc" -eq 0 ]; then
    printf '%sPASS%s %s(%ss)%s %s\n' "$GREEN" "$OFF" "$DIM" "$elapsed" "$OFF" "$detail"
  else
    printf '%sFAIL%s %s(%ss)%s %s\n' "$RED" "$OFF" "$DIM" "$elapsed" "$OFF" "$detail"
  fi
  SUMMARY="${SUMMARY}  ${verdict}  ${STAGE_NAME}  ${elapsed}s  ${detail}"$'\n'
  # Markdown row for CI ($GITHUB_STEP_SUMMARY) — see .github/workflows/ci.yml.
  printf '| %s | %s | %ss | %s |\n' "$verdict" "$STAGE_NAME" "$elapsed" "$detail" >> "$MD_SUMMARY"
}

# Pulls "N" out of swift-testing's "Test run with N tests in M suites passed".
test_count() { grep -oE 'Test run with [0-9]+ test' "$1" | tail -1 | grep -oE '[0-9]+' || echo 0; }

run_tier() {  # run_tier <tier>
  local tier="$1" log="$LOG_DIR/test-$1.log"
  stage_start "test:$tier"
  if bash scripts/test-tier.sh "$tier" --scratch-path "$SCRATCH" "${WERROR[@]}" > "$log" 2>&1; then
    local n; n="$(test_count "$log")"
    eval "COUNT_${tier}=\$n"
    stage_end 0 "$n tests"
  else
    stage_end 1 "see $log"
  fi
}

echo "${BOLD}Vimkin release gate${OFF} — version ${VERSION}"
echo "${DIM}logs: $LOG_DIR${OFF}"
echo

# ── 1. taxonomy ──────────────────────────────────────────────────────────────
stage_start "taxonomy"
if out="$(bash scripts/tiers.sh check 2>&1)"; then
  stage_end 0 "$(bash scripts/tiers.sh counts | tr '\n' ' ' | tr -s ' ')"
else
  stage_end 1; echo "$out" >&2
fi

# ── 2. dependencies (the zero-dependency invariant) ──────────────────────────
stage_start "dependencies"
dep_problem=""
if grep -qE '\.package\s*\(' Package.swift; then
  dep_problem="Package.swift declares a .package() dependency"
elif grep -qE 'dependencies:\s*\[[^]]*\.(product|byName)\s*\(' Package.swift; then
  dep_problem="Package.swift target depends on an external product"
elif [ -f Package.resolved ] && grep -q '"identity"' Package.resolved; then
  dep_problem="Package.resolved pins an external package"
fi
if [ -z "$dep_problem" ]; then
  stage_end 0 "zero third-party dependencies"
else
  stage_end 1 "$dep_problem"
fi

# ── 3. build (warnings-as-errors) ────────────────────────────────────────────
BUILD_LOG="$LOG_DIR/build.log"
stage_start "build"
if swift build --scratch-path "$SCRATCH" "${WERROR[@]}" > "$BUILD_LOG" 2>&1; then
  stage_end 0 "debug, -warnings-as-errors"
else
  stage_end 1 "see $BUILD_LOG"; tail -30 "$BUILD_LOG" >&2
fi

# ── 4. warnings (belt and braces: catches clang / SwiftPM manifest warnings
#        that -warnings-as-errors does not turn into errors) ─────────────────
stage_start "warnings"
if warn="$(grep -E 'warning:' "$BUILD_LOG" || true)"; [ -z "$warn" ]; then
  stage_end 0 "build log clean"
else
  stage_end 1 "$(printf '%s\n' "$warn" | wc -l | tr -d ' ') warning line(s)"
  printf '%s\n' "$warn" >&2
fi

# ── 5-7. the three tiers, each runnable and run on its own ───────────────────
COUNT_unit=0; COUNT_integration=0; COUNT_acceptance=0
run_tier unit
run_tier integration
run_tier acceptance

# ── 8. the whole suite, and the partition proof ──────────────────────────────
ALL_LOG="$LOG_DIR/test-all.log"
stage_start "test:all"
if bash scripts/test.sh --scratch-path "$SCRATCH" "${WERROR[@]}" > "$ALL_LOG" 2>&1; then
  COUNT_all="$(test_count "$ALL_LOG")"
  tier_sum=$((COUNT_unit + COUNT_integration + COUNT_acceptance))
  if [ "$tier_sum" -eq "$COUNT_all" ] && [ "$COUNT_all" -gt 0 ]; then
    stage_end 0 "$COUNT_all tests = ${COUNT_unit}u + ${COUNT_integration}i + ${COUNT_acceptance}a"
  else
    stage_end 1 "tiers do not partition the suite: ${COUNT_unit}+${COUNT_integration}+${COUNT_acceptance}=${tier_sum} vs ${COUNT_all} total"
  fi
else
  stage_end 1 "see $ALL_LOG"; grep -E '✘|error:' "$ALL_LOG" | head -30 >&2
fi

if [ "${GATE_SKIP_PACKAGING:-0}" = "1" ]; then
  echo
  echo "${DIM}stages 9-12 skipped (GATE_SKIP_PACKAGING=1) — NOT a releasable run${OFF}"
else

APP="$ROOT/dist/Vimkin.app"
PLIST="$APP/Contents/Info.plist"
DMG="$ROOT/dist/vimkin-${VERSION}.dmg"

# ── 9. app bundle ────────────────────────────────────────────────────────────
APP_LOG="$LOG_DIR/make-app.log"
stage_start "app-bundle"
app_problem=""
# The release build inherits warnings-as-errors too — release-only warnings are
# still warnings.
if ! SWIFT_BUILD_FLAGS="-Xswiftc -warnings-as-errors" bash scripts/make-app.sh "$VERSION" > "$APP_LOG" 2>&1; then
  app_problem="make-app.sh failed — see $APP_LOG"
elif grep -qE 'warning:' "$APP_LOG"; then
  app_problem="release build emitted warnings — see $APP_LOG"
elif [ ! -x "$APP/Contents/MacOS/Vimkin" ]; then
  app_problem="no executable at Contents/MacOS/Vimkin"
elif [ ! -d "$APP/Contents/Resources/Vimkin_Vimkin.bundle" ]; then
  app_problem="the Content resource bundle is missing — the app would launch with no levels, lessons or corpus"
elif ! codesign --verify --deep --strict "$APP" > /dev/null 2>&1; then
  app_problem="the ad-hoc signature does not verify"
fi
if [ -z "$app_problem" ]; then
  stage_end 0 "$(du -sh "$APP" | cut -f1 | tr -d ' ') bundle"
else
  stage_end 1 "$app_problem"
fi

# ── 10. Info.plist ───────────────────────────────────────────────────────────
# A malformed Info.plist shipped once. It cannot ship again: the file is linted
# AND every key the bundle needs to launch is read back out of it.
stage_start "info-plist"
plist_problem=""
if [ ! -f "$PLIST" ]; then
  plist_problem="no Info.plist in the bundle"
elif ! plutil -lint "$PLIST" > /dev/null 2>&1; then
  plist_problem="plutil -lint rejected the plist"
else
  for key in CFBundleExecutable CFBundleIdentifier CFBundleName CFBundlePackageType \
             CFBundleShortVersionString CFBundleVersion LSMinimumSystemVersion; do
    if ! value="$(plutil -extract "$key" raw -o - "$PLIST" 2>/dev/null)" || [ -z "$value" ]; then
      plist_problem="missing or empty key: $key"; break
    fi
  done
  if [ -z "$plist_problem" ]; then
    got="$(plutil -extract CFBundleShortVersionString raw -o - "$PLIST")"
    [ "$got" = "$VERSION" ] || plist_problem="CFBundleShortVersionString is '$got', expected '$VERSION'"
  fi
  if [ -z "$plist_problem" ]; then
    exe="$(plutil -extract CFBundleExecutable raw -o - "$PLIST")"
    [ -x "$APP/Contents/MacOS/$exe" ] || plist_problem="CFBundleExecutable '$exe' does not exist in the bundle"
  fi
fi
if [ -z "$plist_problem" ]; then
  stage_end 0 "lint + 7 required keys + version match"
else
  stage_end 1 "$plist_problem"
fi

# ── 11. DMG ──────────────────────────────────────────────────────────────────
DMG_LOG="$LOG_DIR/create-dmg.log"
stage_start "dmg"
dmg_problem=""
if ! bash scripts/create-dmg.sh "$VERSION" > "$DMG_LOG" 2>&1; then
  dmg_problem="create-dmg.sh failed — see $DMG_LOG"
elif [ ! -f "$DMG" ]; then
  dmg_problem="no DMG at $DMG"
else
  MOUNT="$(mktemp -d)"
  if hdiutil attach "$DMG" -nobrowse -readonly -mountpoint "$MOUNT" > /dev/null 2>&1; then
    [ -d "$MOUNT/Vimkin.app" ] || dmg_problem="the DMG does not contain Vimkin.app"
    [ -L "$MOUNT/Applications" ] || dmg_problem="the DMG has no /Applications drop target"
    hdiutil detach "$MOUNT" -quiet > /dev/null 2>&1 || hdiutil detach "$MOUNT" -force -quiet > /dev/null 2>&1
  else
    dmg_problem="the DMG does not mount"
  fi
  rmdir "$MOUNT" 2>/dev/null || true
fi
if [ -z "$dmg_problem" ]; then
  stage_end 0 "$(du -h "$DMG" | cut -f1 | tr -d ' '), mounts with Vimkin.app + /Applications"
else
  stage_end 1 "$dmg_problem"
fi

# ── 12. checksum ─────────────────────────────────────────────────────────────
stage_start "checksum"
if [ ! -f "$DMG.sha256" ]; then
  stage_end 1 "no $DMG.sha256"
elif shasum -a 256 -c "$DMG.sha256" > /dev/null 2>&1; then
  stage_end 0 "$(cut -d' ' -f1 < "$DMG.sha256")"
else
  stage_end 1 "the published sha256 does not match the DMG"
fi

fi  # GATE_SKIP_PACKAGING

echo
echo "${BOLD}── gate summary ──${OFF}"
printf '%s' "$SUMMARY"
{
  echo
  echo "**Tests:** ${COUNT_all:-?} total = ${COUNT_unit} unit + ${COUNT_integration} integration + ${COUNT_acceptance} acceptance"
} >> "$MD_SUMMARY"
if [ "$FAILURES" -eq 0 ]; then
  echo >> "$MD_SUMMARY"; echo "**GATE PASSED**" >> "$MD_SUMMARY"
  echo "${GREEN}${BOLD}GATE PASSED${OFF}"
  exit 0
fi
echo >> "$MD_SUMMARY"; echo "**GATE FAILED — $FAILURES stage(s)**" >> "$MD_SUMMARY"
echo "${RED}${BOLD}GATE FAILED — $FAILURES stage(s)${OFF}"
exit 1
