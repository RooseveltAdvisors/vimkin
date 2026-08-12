# Third-party notices

Vimkin has **no third-party runtime dependencies** — it is pure Swift, SwiftUI, SpriteKit, and system frameworks. The notices below cover source code adapted into this project.

## vimhint — MIT License

Copyright (c) Kyle Dickey — https://github.com/kyledickey/vimhint

Four pieces of Vimkin are derived from vimhint and remain under the MIT License:

| Vimkin file | Derived from | Nature of the adaptation |
|---|---|---|
| `Sources/Vimkin/UI/Overlay/HotkeyManager.swift` | `vimhint/HotkeyManager.swift` | Carbon `RegisterEventHotKey` manager, recording-suppression debounce, keyCode→name tables. Adapted: new storage key, new hotkey signature, Swift 6 concurrency. |
| `Sources/Vimkin/UI/Overlay/HotkeyRecorder.swift` | `vimhint/HotkeyRecorder.swift` | Local `NSEvent` monitor shortcut recorder. Adapted: Vimkin styling. |
| `Sources/Vimkin/UI/Overlay/OverlayPanel.swift` | `vimhint/SidebarWindow.swift` | Non-activating `NSPanel` recipe (style mask, level, collection behavior, `orderFrontRegardless`). Adapted: centered card geometry, fade+scale animation. |
| `scripts/create-dmg.sh` | `vimhint/scripts/create-dmg.sh` | `hdiutil` drag-to-install DMG packaging. |

The MIT License text is reproduced below as required.

```
MIT License

Copyright (c) 2026 Kyle Dickey

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## On other Vim-learning games

Vimkin is an **independent, original work**. It shares a genre with other games that teach Vim — most notably the idea of a skill-gated world where new motions open new ground. Game *mechanics and rules* are not protected by copyright; their *expression* is, and Vimkin uses none of it.

Everything expressive in Vimkin is original to this project: the name, the paper-and-ink world, the Vimkins and the Entropy Worm, the cursor-spirit, every level document and its writing, all level and world titles, all art (generated for this project), and all code. No assets, text, level content, character designs, world names, or code from any other Vim-learning game appear here.

## Generated assets

All artwork in `assets/` and `Sources/Vimkin/Content/` was generated for this project using locally-run open-weight models, from prompts written for Vimkin's own art direction (`assets/briefs/style-guide.md`). Each asset carries a `.provenance.md` sidecar recording its prompt, model, and parameters. The artwork is released under the same MIT License as the rest of the project.
