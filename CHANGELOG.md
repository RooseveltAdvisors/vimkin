# Changelog

Notable changes to Vimkin, newest first. Entries describe what changed **for a
player**, not which files moved.

The version is the git tag — there is no version file. See
[`docs/release-checklist.md`](docs/release-checklist.md) for how a release is
cut.

## Unreleased

- **The launcher is now the front door.** `⌘⇧Space` summons it from anywhere
  (it was `⌘⇧V`; an existing install migrates to the new key automatically, and
  a shortcut you chose yourself is left alone). Type to search every Vim
  command in plain English as before — but on an empty box, one key now opens
  any surface in the app: `a` Adventure, `d` Daily Run, `l` Lessons,
  `p` Practice, `g` Progress, `y` Playground. The keys are on screen the whole
  time, and `?` opens the full map.
- Looking something up still never steals focus from what you were doing; only
  opening a surface brings Vimkin forward.
- `?` now shows a **grouped** key map — Move / Go / Keys / Leave — instead of
  one flat list.
- `h j k l` moves on every list, not just the world map.
- `⌘R` resets the page inside a level, the way it already did in the dojo.
- The playground walks documents with `⌘[` / `⌘]`; `⌘J` and `⌘K` now mean the
  same thing everywhere else in the app (skip a drill / show me the keys).
