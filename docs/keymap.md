# Vimkin keymap — conventions

Vimkin's bindings follow the conventions Jon already has in his hands, so the app
feels like the tools it teaches. Two sources:

**tmux** (`~/.config/tmux/tmux.conf`) — a `C-a` prefix, then a *single mnemonic
key* per action (`j` copy-mode, `k` sessions, `w` windows, `x` kill, `p` float),
and `C-h/j/k/l` for vim-aware pane movement.

**neovim** (LazyVim + which-key) — a leader key, actions grouped by domain
(`<leader>o` Obsidian → `n` new, `o` search, `s` switch, `b` backlinks), capitals
for the "new/bigger" sibling (`ol` link, `oL` link-new), and **a popup that shows
the available continuations** instead of asking you to remember them.

## The rules we adopt

1. **The launcher is the prefix.** `⌘⇧Space` opens the launcher from anywhere —
   this is Vimkin's front door, the way `C-a` is tmux's. You do not need the app
   window open, or even focused.
2. **One key per action after the prefix**, mnemonic, like tmux. No chords.
3. **Show the continuations.** The launcher lists what each key does, and `?`
   opens the full map for the current surface — which-key, not memory.
4. **`hjkl` moves, `Return` opens, `Esc` backs out**, everywhere in navigation.
5. **Capital = the bigger sibling** (`g` progress → `G` full mastery map).
6. **`⌘` for chrome mid-practice.** While an engine surface is capturing, plain
   keys belong to Vim; app verbs ride on `⌘` so they can never collide with a
   motion. This is the same instinct as tmux's prefix: a namespace that the
   inner program will never claim.

## The map

### Launcher (`⌘⇧Space` — the front door)

| Key | Action |
|---|---|
| *type* | search every Vim command in plain English ("delete inside quotes" → `di"`) |
| `⏎` | practise the selected command |
| `⌃N` / `⌃P` | move through matches |
| `:` | **command mode** — the next key goes somewhere |
| `:a` `:d` `:l` `:p` `:g` `:y` | Adventure · Daily Run · Lessons · Practice · Progress · Playground |
| `?` | show this map |
| `Esc` | dismiss |

**Why `:` and not bare letters.** An earlier draft of this doc said letters jump
while the query is empty. Playing it killed that: the query is *always* empty
when you start typing, so "delete inside quotes" fired Daily Run on the `d` and
quit the app on the `q`. Six mnemonics are the first letters of *delete, append,
yank, paste, line, goto* — the vocabulary the launcher exists to look up.

So the launcher takes Vim's own answer: text is a search, `:` addresses the
program. Lookup — done fifty times a day — costs zero extra keys; going
somewhere costs one.

### Navigation (menus, lists, the world map)

| Key | Action |
|---|---|
| `h j k l` | move the selection |
| `gg` / `G` | first / last |
| `⏎` | open |
| `Esc` / `q` | back |
| `?` | keys for this surface |

### Engine surfaces (a lesson, a drill, a level)

Every plain key belongs to `VimEngine`. Chrome rides on `⌘`:

| Key | Action |
|---|---|
| `Esc Esc` | leave (the first `Esc` is the engine's) |
| `⌘K` | show the keys for this step |
| `⌘R` | reset the page |
| `⌘J` | skip |
| `⌘E` | end the set |
