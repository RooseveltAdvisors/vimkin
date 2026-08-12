# Vimkin release checklist

The procedure for cutting a Vimkin release. Work top to bottom; do not skip a
box. Anything a machine can check is in `scripts/gate.sh` — this document is the
part a machine **cannot** do, plus the order to do it in.

Copy this file's checkboxes into the release issue/PR and tick them there.

---

## 0. Preflight

- [ ] Working tree is clean (`git status` empty) and on `main`, up to date with
      `origin/main`.
- [ ] Every PR intended for this release is merged. `gh pr list --state open`
      shows nothing you meant to include.
- [ ] Decide the version. Vimkin has **no version file** — the git tag is the
      only source of truth, and `scripts/make-app.sh` stamps it into
      `Info.plist`. Semver: `MAJOR.MINOR.PATCH`, tag is `v` + that.

      Version chosen: `vX.Y.Z`

## 1. Changelog

- [ ] Move everything under `## Unreleased` in `CHANGELOG.md` into a new
      `## X.Y.Z — YYYY-MM-DD` section, and leave `## Unreleased` empty above it.
- [ ] Read the entries as a player, not as the author. Each line says what
      changed *for them*, not which file moved.
- [ ] Commit: `docs: changelog for vX.Y.Z`.

## 2. The gate (everything automatable)

- [ ] Run the full gate locally with the real version:

      ```sh
      bash scripts/gate.sh X.Y.Z
      ```

      All 12 stages must read `PASS`. It builds warnings-as-errors, runs all
      three test tiers plus the whole suite (and proves the tiers partition it),
      assembles `Vimkin.app`, lints the `Info.plist`, builds the DMG, mounts it,
      and verifies the checksum. If any stage fails, **stop** — a red gate is
      never "known flaky", it is the release blocking itself.

- [ ] Test count is what you expect. A feature PR that added no tests is a
      defect, not a release.

- [ ] `git push` and confirm the **CI** workflow is green on `main`. CI runs the
      same `scripts/gate.sh`, so a green local gate and a red CI means an
      environment difference worth understanding before you tag.

## 3. Manual visual QA — the part CI cannot do

CI proves the app *assembles*, that key→action tables and view-model state
machines behave, and that every authored level is beatable. **It proves nothing
about pixels.** Nothing headless can tell you a view lays out, animates, or is
legible. So install the actual DMG the gate just built and walk the app.

- [ ] Install the built artifact, not a `swift run` build:

      ```sh
      open dist/vimkin-X.Y.Z.dmg
      # drag Vimkin to Applications, then:
      xattr -dr com.apple.quarantine /Applications/Vimkin.app
      open /Applications/Vimkin.app
      ```

- [ ] Cold launch: app opens in **under ~2s** to the title screen, with no
      "damaged / cannot be opened" dialog and nothing logged to Console that
      looks like a missing resource.

Walk every surface. For each, "good" is stated so this is a check, not a vibe.

| # | Surface | How to get there | Good looks like |
|---|---|---|---|
| 1 | **Title screen** | launch | All six routes reachable and readable. Window opens at ≥900×620 and the hidden title bar leaves no dead strip at the top. |
| 2 | **Tutorial** (Learn) | title → Learn | The instruction, the document and the hint are all visible **without scrolling**. Typing the taught keys advances the rep counter and the page resets between attempts. A wrong key shows the hint rather than silently doing nothing. |
| 3 | **Practice Dojo** | title → Practice, and again via the overlay's "Practice this →" | Opens as a sheet at ≥860×620. The drill's document renders with syntax tint (headings, JSON/YAML keys, comments tinted — see the `SyntaxTint` suite for the intended classification). The progress dots read clean/struggled/skipped at a glance. The summary at the end is legible, not a wall of numbers. |
| 4 | **Adventure — world map** | title → Play | Cleared levels are visibly distinct from locked ones, and only the next level is offered. |
| 5 | **Adventure — a level** | world map → level 1, then level 5 (the one that hands out `f`) | The document reads as an island map: land tiles, ink sea, signpost headings. The camera follows without ever showing sea past the world edge (level 5 is the wide one — walk to each edge). Every Vimkin sprite sits **on land**, never adrift. A **locked** key must be visibly refused with a message that names the lesson — not swallowed. |
| 6 | **Juice** | rescue a Vimkin in a level | Whisper/pop effects have **no screen shake**; only the burst shakes, and only for a beat (0.1–0.3s). Nothing stutters. With no audio assets installed the app stays silent — it never clicks, pops or crashes. |
| 7 | **Daily Run** (Arcade) | title → Daily Run | Timer counts down and is readable at a glance. The run ends cleanly at the limit. Score, combo and accuracy land on the result view without clipping. Re-entering the same day offers a *practice* replay, not a second scored run. |
| 8 | **Mastery map** (Progress) | title → Progress | Every skill state (unlearned / learning / mastered / rusty) is distinguishable **by shape or label, not by colour alone**. Streak and grace days read honestly. A rusty row can raise the dojo. |
| 9 | **Playground** | title → Playground | Free editing works; mode indicator tracks normal/insert/visual/operator-pending/command-line; the insert-mode bar cursor may sit one past the line end without drawing outside the text area. |
| 10 | **Lookup overlay** | ⌘⇧V **from a different app** (e.g. Safari) | The panel appears over the other app, focused and typable. "delete inside quotes" puts `di"` first. Esc dismisses and returns focus to where you were. "Practice this →" raises the dojo in Vimkin. |
| 11 | **Appearance** | toggle System Settings → Appearance | Both light and dark are legible — no white-on-white, no unreadable tinted text. |
| 12 | **Second display / scaling** | drag the window to a non-Retina display if you have one | Text stays crisp and layout does not break. |

- [ ] All twelve rows checked, on the installed `.app`, on this release's build.
- [ ] Anything that looked wrong is either fixed (go back to step 2) or written
      down in the release notes as a known issue. Silence is not an option.

## 4. Tag and push

- [ ] Tag the exact commit CI went green on:

      ```sh
      git tag -a vX.Y.Z -m "vX.Y.Z"
      git push origin vX.Y.Z
      ```

- [ ] The **Release** workflow runs. It re-runs `scripts/gate.sh X.Y.Z` from
      scratch on a clean runner — a tag gets no shortcut past any check a pull
      request has to pass — and only then publishes.

- [ ] The GitHub Release exists with **both** assets:
      `vimkin-X.Y.Z.dmg` and `vimkin-X.Y.Z.dmg.sha256`.

## 5. Verify the published artifact (not the local one)

- [ ] Download the DMG **from the Release page** onto a machine that has never
      built Vimkin, and verify it:

      ```sh
      shasum -a 256 -c vimkin-X.Y.Z.dmg.sha256
      ```

- [ ] Install from that download and launch it. Unsigned builds are quarantined
      by macOS; the workaround is one command and it is in the release notes:

      ```sh
      xattr -dr com.apple.quarantine /Applications/Vimkin.app
      ```

      Right-click → **Open** also works. Both paths must be stated in the
      release notes, because a user who hits "Vimkin is damaged and can't be
      opened" and has no instructions simply deletes the app.

- [ ] Title screen appears. That is the release verified against reality — the
      published bytes, on a machine with no build tree.

## 6. After

- [ ] Update the README install line if anything about installation changed.
- [ ] Open the `## Unreleased` section in `CHANGELOG.md` for the next cycle.

---

## Notes

**Signing and notarisation.** Vimkin ships **unsigned and ad-hoc-signed only**
(`codesign -s -`). There is no Developer ID and no notarisation, so quarantine
is expected, not a bug. The gate verifies the ad-hoc signature is *valid*; it
cannot verify something we do not do. If a Developer ID ever lands, add
`codesign --verify --deep --strict --verbose=2` against the real identity and a
`spctl --assess` stage to the gate, and delete the quarantine paragraph from the
release notes.

**If the gate fails on a release day.** Fix the cause. Do not tune the gate to
go green — a threshold raised to clear a failure is the failure, still there,
now invisible.
