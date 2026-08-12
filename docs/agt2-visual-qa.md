# Visual QA loop on agt-2

The app is developed on the Mac but **looked at on agt-2**, so a GUI app never
steals the desktop you are working on. agt-2 has a live console session, Swift
6.0.3 (CommandLineTools, no Xcode) and the `steer` CLI.

## The loop

```bash
# 1. push the working tree to agt-2 (from the repo/worktree root)
rsync -az --delete --exclude '.build' --exclude 'dist' --exclude '.git' \
  ./ jon@agt-2:~/git/vimkin-qa/

# 2. build, install and launch there
ssh jon@agt-2 'cd ~/git/vimkin-qa && bash scripts/make-app.sh 0.1.0-dev >/dev/null &&
  rm -rf /Applications/Vimkin.app && cp -R dist/Vimkin.app /Applications/ &&
  pkill -f Vimkin; open -a /Applications/Vimkin.app'

# 3. look at it — screenshot + accessibility tree in one call
ssh jon@agt-2 'steer apps activate Vimkin >/dev/null; sleep 1; steer see --app Vimkin'

# 4. pull the screenshot back and actually LOOK at it
scp jon@agt-2:<screenshot-path-from-step-3> /tmp/qa.png
```

## Driving it

```bash
ssh jon@agt-2 'steer hotkey j'         # a key
ssh jon@agt-2 'steer hotkey return'    # Return
ssh jon@agt-2 'steer hotkey escape'    # Esc
ssh jon@agt-2 'steer type "hello"'     # a string
ssh jon@agt-2 'steer click B1'         # click element by id (mouse — avoid, we are keyboard-first)
```

`steer see` returns an element map (`B1`, `S2`, …) plus a screenshot path. The
element map is the fastest way to assert **keyboard reachability**: drive with
`steer hotkey` only, and confirm the tree changed. If a surface can only be
reached with `steer click`, it is a keyboard-navigation bug.

## Rules

- **Never verify a UI claim from the accessibility tree alone.** Pull the PNG and
  look at it. The tree proves structure; only the image proves it looks good.
- Keep the Mac's own `/Applications/Vimkin.app` out of this loop — agt-2 is the
  display machine.
