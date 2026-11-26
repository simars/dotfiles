# Window Keys Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One window-key prefix (Ctrl+Option+Cmd on the Macs, Ctrl+Alt+Super on Omarchy) for focus, swap, go to
desktop N, send to desktop N, tile (Mac) and rescue, beside Swish and Omarchy's own keys.

**Architecture:** Mac: a Hammerspoon module (`dot_hammerspoon/window_keys.lua.tmpl`) acts on key presses only; it
switches desktops by pressing macOS's own "Switch to Desktop N" shortcuts, which chezmoi's macOS settings script
binds to a hidden combination; a shared table in `.chezmoidata/macos.toml` feeds both. Omarchy: a private guide in
`~/.cfg` adds a marked block of aliases to `~/.config/hypr/bindings.lua`.

**Tech Stack:** Hammerspoon 1.1.1 Lua, chezmoi templates, bash 3.2-compatible scripts (Macs), Hyprland Lua config
(Omarchy), `tests/host-profiles.sh`.

**Spec:** `docs/superpowers/specs/2026-11-26-mac-window-keys-design.md`

## Global Constraints

- Prefix: Mac `{"cmd","ctrl","alt"}` (Ctrl+Option+Cmd); Omarchy `SUPER + CTRL + ALT`. Shift added for swap and send.
- Keys: arrows focus, Shift+arrows swap, 1–9 desktop N, Shift+1–9 send and follow, L tile (Mac only), U rescue.
- Never take a macOS or Omarchy shortcut; never edit `/usr/share/omarchy`; Omarchy's own Super keys stay.
- Mac scripts run under bash 3.2; no osascript; no SIP changes; no new apps.
- Public repo: no work identifiers. Commit as `Simar Singh <simarpaulsingh@gmail.com>`, no agent trailers, gitleaks
  clean, cheatsheet updated in the same commit as the behaviour (CLAUDE.md 2). `~/.cfg` only through `config`.
- Over SSH to a Mac: `export SSH_AUTH_SOCK=/run/user/1000/gcr/ssh` first; the remote shell is zsh (arrays from 1):
  wrap loops in `bash -c`.
- Nothing is pushed and no Mac is applied without the user's go-ahead (Task 6 asks).

## Review Focus

1. A screen with fewer desktops than N, or a global number above 16: no key is pressed, an alert says why
   (Task 3 tests `globalDesktop` returning nil).
2. A full-screen app's space between desktops: it must not count (Task 3 tests a `type = 4` space).
3. The main display listed as `"Main"` instead of its UUID in Mission Control's data (Task 3 tests it).
4. A Mac whose hidden shortcuts already match writes nothing and restarts nothing; a second apply says "match the
   repo" (Task 2 tests it).
5. Re-running the Omarchy guide's `apply.sh`, and running `undo.sh`, leaves `bindings.lua` byte-identical to before
   (Task 4 tests it on a scratch copy).

---

### Task 1: Pick the hidden combination (live check on mbp)

**Files:** none in the repo; the throwaway `~/.hammerspoon/spike_keys.lua` on mbp (source in the session scratchpad,
`spike/spike_keys.lua`).

**Interfaces:**
- Produces: the hidden combination for Task 2: a modifier mask, a Hammerspoon modifier list, and 16 (key name, key
  code) pairs.

- [ ] **Step 1: Tell the user** the desktops on mbp will switch a few times for a minute, then on mbp set ids 118,
  119, 126, 127 (Desktops 1, 2, 9, 10) to the **keypad** candidate: mask `1835008` (Ctrl+Option+Cmd), key codes
  `83` (pad1), `84` (pad2), `92` (pad9), `82` (pad0), character `65535`; then `activateSettings -u`.
- [ ] **Step 2: Press each through Hammerspoon** with a one-off URL handler in `local.lua`
  (`hs.eventtap.keyStroke({"cmd","ctrl","alt"}, "pad1", 0)` etc., 1 s apart) and read the spike log's
  "desktop changed" lines. Expected: laptop shows space of Desktop 1, then 2; ultrawide 9, then 10.
- [ ] **Step 3: If nothing changed**, retry with mask `1835008 + 2097152` (numeric-pad flag) = `3932160`; if still
  nothing, use the **fallback**: mask `917504` (Ctrl+Option+Shift), digits `18 19 20 21 23 22 26 28 25 29`, then
  `-` 27, `=` 24, `[` 33, `]` 30, `;` 41, `'` 39; first confirm on mbp with `hs.hotkey.systemAssigned` that none of
  those 16 is taken, then repeat Step 2.
- [ ] **Step 4: Record the winner** (mask, modifier list, 16 key names with codes; keypad 11–16: `pad-` 78, `pad+`
  69, `pad*` 67, `pad/` 75, `pad=` 81, `pad.` 65) as a comment in the plan's Task 2 Step 3 before starting Task 2.

### Task 2: Desktop shortcuts and fixed desktop order in the macOS settings script

**Files:**
- Modify: `.chezmoidata/macos.toml` (Dock group; new Spaces group; new `[desktop_shortcuts]` table)
- Modify: `run_after_97_macos_defaults.sh.tmpl`
- Modify: `tests/host-profiles.sh` (the `md` stub section, ~lines 741–830)
- Modify: `docs/CHEATSHEET.md` ("Same macOS Settings on Every Mac": desktops keep their order)

**Interfaces:**
- Produces: `.desktop_shortcuts` with `mask` (int), `hs_modifiers` (list of strings), `keys` (16 tables
  `{ name = "pad1", code = 83 }`, Desktop 1 first; id = 117 + index). Task 3 reads it.

- [ ] **Step 1: Confirm the two Mission Control keys** with the user at a Mac (CLAUDE.md 3.5): read
  `defaults read com.apple.dock mru-spaces` and `defaults read com.apple.spaces spans-displays`, have the user flip
  "Automatically rearrange Spaces based on most recent use" and then "Displays have separate Spaces" in System
  Settings > Desktop & Dock, read again, flip both back. Expected: each read changes with its switch
  (`mru-spaces` 0/1; `spans-displays` 1 when separate Spaces is off). If a key does not change, stop and report.
- [ ] **Step 2: Write the failing tests** in `tests/host-profiles.sh`, next to the existing new-Mac checks:
  - Extend the `defaults` stub: `write DOMAIN KEY -dict-add ID XML` appends `"$scope $2 $3 $5"` to `$MD/written` and
    `ID enabled MASKLINE` to `$MD/hotkeys-written` without touching the read file; add a `bin/activateSettings` stub
    that appends `activated` to `$MD/activated`, and let the script take its path from `ACTIVATE_SETTINGS` (default
    the real path) so the stub is used.
  - `check "macOS settings on a new Mac: writes every key whose unset value differs (30 of 43)" 30 …` (old 29 of 41
    plus `mru-spaces`; `spans-displays` is `same_when_unset`). Hotkey entries are counted separately.
  - `check "desktop shortcuts on a new Mac: ids 118–133 written once, settings activated once" "16|1"`.
  - `check "desktop shortcuts: a Mac that already has them writes none and does not activate" "0|0"` with a
    `defaults read com.apple.symbolichotkeys AppleSymbolicHotKeys` text form (as the `hotkeys()` helper writes)
    holding all 16 with the wanted values.
  - `check "desktop shortcuts: one entry with the wrong mask is rewritten alone" "1|1"`.
  - `check "macOS Invert Colors on Ctrl+Option+Cmd+8 is named and goes on the to-do list" "1|1"` with id 21
    `enabled = 1`; and `0|0` with `enabled = 0` or absent.
  - `check "macOS settings: a second apply writes nothing and restarts nothing"`: existing check, still passes.
- [ ] **Step 3: Run** `bash tests/host-profiles.sh 2>&1 | grep -E 'FAIL|passed'`. Expected: the new checks FAIL.
- [ ] **Step 4: Implement.** In `macos.toml`: `"mru-spaces" = false` in the Dock group; a new group
  `domains = ["com.apple.spaces"]`, `takes_effect = "logout"`, `same_when_unset = ["spans-displays"]`,
  `"spans-displays" = false`; `[desktop_shortcuts]` from Task 1, with a comment block in the file's style (what ids
  118–133 are, why a hidden combination, the Desktop 1–16 numbering across screens). In the 97 script, after the
  `[[macos_defaults]]` loop: `ensure_desktop_key ID CODE MASK` reads the current entry once from
  `defaults read com.apple.symbolichotkeys AppleSymbolicHotKeys` (awk over the text form, as
  `run_after_96_macos_iterm2.sh.tmpl` does for id 60), writes with
  `defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add ID '<dict>…enabled true, parameters
  (65535, CODE, MASK), type standard…</dict>'` only when enabled, code or mask differ, adds `"Desktop N shortcut"` to
  `updated`, and after all 16 runs `"$ACTIVATE_SETTINGS" -u` once if any was written. Then the Invert Colors check:
  id 21 `enabled = 1` → `echo "NOTE: macOS's Invert Colors shortcut (Ctrl+Option+Cmd+8) takes the window key for
  desktop 8"` and `todo "Turn off System Settings > Keyboard > Keyboard Shortcuts > Accessibility > Invert colors,
  so Ctrl+Option+Cmd+8 reaches the window keys"`.
- [ ] **Step 5: Run the tests.** Expected: `… passed, 0 failed`.
- [ ] **Step 6: Cheatsheet**: in "Same macOS Settings on Every Mac", add the two Mission Control rows (desktops keep
  the order you give them; separate Spaces per display) and one line on the hidden desktop shortcuts (Desktop 1–16,
  never pressed by hand; the window keys use them). Check: `zsh -c 'source dot_aliases && cheat | grep -n "Spaces"'`.
- [ ] **Step 7: Commit** (`gitleaks git --log-opts="origin/main..HEAD"` clean):
  `feat(macos): desktops keep their order; macOS's desktop shortcuts on a hidden combination`.

### Task 3: The Hammerspoon window-keys module

**Files:**
- Create: `dot_hammerspoon/window_keys.lua.tmpl`
- Modify: `dot_hammerspoon/init.lua` (start it after the rescue)
- Modify: `dot_hammerspoon/window_rescue.lua` only if `M.rescue` is not already callable from another module
- Modify: `tests/host-profiles.sh` (Hammerspoon section, ~line 1028)
- Modify: `docs/CHEATSHEET.md` (new "### Window Keys (macOS and Omarchy)" after "Lost and Minimized Windows")

**Interfaces:**
- Consumes: `.desktop_shortcuts` (Task 2); `require("window_rescue").rescue(allApps: boolean)`.
- Produces: module table `M` with `M.start()`, and pure, testable
  `M.globalDesktop(displays, screenUUID, isPrimary, n) -> globalNumber|nil, desktopsOnScreen, spaceID|nil` where
  `displays` is the shape of `hs.spaces.data_managedDisplaySpaces()` (list of `{ ["Display Identifier"] = s,
  Spaces = { { ManagedSpaceID = id, type = t } } }`).

- [ ] **Step 1: Write the failing tests:**
  - `for host in darwin intel: check "$host manages the window keys" yes "$(manages "$host" .hammerspoon/window_keys.lua)"`;
    Linux hosts `no`.
  - `check "window keys render and compile" ok` : `render darwin dot_hammerspoon/window_keys.lua.tmpl > $work/wk.lua &&
    luac -p $work/wk.lua` (guarded by `command -v luac`).
  - `check "window keys carry the 16 hidden desktop keys" 16` : count of key entries in the rendered table.
  - Guarded by `command -v lua`, run the rendered module under `lua` with a stub `hs = {}` global and check
    `globalDesktop` (displays: laptop UUID `A` with spaces `1,6,8,4,7,5,9,10` type 0; ultrawide `B` with `89` type 0,
    `200` type 4, `98` type 0):
    `A,primary,2 → 2`; `B,not primary,2 → 10 (space 98)` (full-screen 200 skipped); `B,3 → nil, 2`;
    `"Main"` as A's identifier with isPrimary true, n 1 → `1`; a 17th global desktop → `nil`.
  - `check "init.lua starts the window keys after the rescue" 1` : `require("window_keys").start()` follows the rescue line.
- [ ] **Step 2: Run** the suite. Expected: the new checks FAIL.
- [ ] **Step 3: Implement** from the spike (`spike/spike_keys.lua`), keeping: focus (`focusWindow<Dir>(nil, true, true)`),
  swap (frames exchanged, focus kept), tile (dwindle, 8 px gap), the send sequence (wait for released modifiers,
  max 2 s; grab point; mouse events with `{}` flags; 60 ms steps; 0.5 s hold; mouse put back), the grab table
  (Chrome `x = f.x + f.w - 140, y = f.y + 6`; Slack `x = f.x + min(260, 0.22 f.w), y = f.y + 14`; default right of
  the zoom button + 6). Bindings: prefix `{"cmd","ctrl","alt"}` + `left/right/up/down` focus, + Shift swap, + `1`–`9`
  go (screen under the mouse), + Shift + `1`–`9` send (screen of the focused window), + `l` tile, + `u`
  `window_rescue.rescue(false)`. Hidden keys from the template: `{{ range .desktop_shortcuts.keys }}{ "{{ .name }}" },{{ end }}`
  and `hs_modifiers`. Refusals (`globalDesktop` nil) → `hs.alert.show` ("Only N desktops on this screen" /
  "Desktop beyond 16 has no shortcut") and a log line. `hs.urlevent.bind("window-keys-probe", …)` runs the spike's
  probe on the focused window. Log `~/Library/Logs/window-keys.log`: send, tile, refusal, probe only. Header comment
  in the style of `window_rescue.lua` (what, why the hidden shortcuts, Swish untouched, cheatsheet section).
- [ ] **Step 4: Run** the suite. Expected: `… passed, 0 failed`.
- [ ] **Step 5: Cheatsheet** section: the spec's key table (Mac and Omarchy columns), two bullets (Swish untouched;
  per-screen numbering and the fixed order from Task 2), the probe command, and the log path. Verify with
  `zsh -c 'source dot_aliases && cheat | grep -n "Window Keys"'`.
- [ ] **Step 6: Commit**: `feat(macos): window keys on Ctrl+Option+Cmd: focus, swap, desktops, send, tile`.

### Task 4: The Omarchy guide (private `~/.cfg`) and its registration (chezmoi)

**Files:**
- Create: `~/guides/omarchy/window-keys/{README.md,apply.sh,undo.sh,status.sh,common.sh}` (copy the structure of
  `~/guides/omarchy/window-rescue/`, including its `HYPRLAND_INSTANCE_SIGNATURE` fallback and
  `block_description`-style own-block recognition)
- Modify: `~/guides/README.md`, `~/guides/omarchy/README.md` (one line each)
- Modify (chezmoi): `.chezmoidata/omarchy.toml` `omarchy_guides` → add `"window-rescue", "window-keys"`;
  `dot_local/bin/executable_setup-guides*` if its list is not rendered from the data; `tests/host-profiles.sh` if it
  asserts the list; `docs/CHEATSHEET.md` Omarchy column of the Window Keys table (Task 3's section) names the guide.

**Interfaces:**
- Consumes: Omarchy's actions as in `/usr/share/omarchy/default/hypr/bindings/tiling.lua`:
  `hl.dsp.focus({ direction = d })`, `hl.dsp.window.swap({ direction = d })`, `o.workspaces.focus(n)`,
  `o.workspaces.move_window(n)`; the rescue `~/guides/omarchy/window-rescue/rescue.sh`.
- Produces: `status.sh` printing `VERDICT: ACTIVE` when the block is present and loaded.

- [ ] **Step 1: Write the block** in `common.sh` (`KEY_PREFIX="SUPER + CTRL + ALT"`): 4 focus, 4 swap
  (`+ SHIFT`), 9 go and 9 send on `code:10`–`code:18`, 1 rescue (`U`); 27 bindings, each described
  "Window keys: …". Conflict check: none of the 27 key combinations appears in `omarchy menu keybindings --print`
  outside this block (with the signature fallback, as in window-rescue's `common.sh`).
- [ ] **Step 2: Test on a scratch copy** (`BINDINGS=<copy>`): apply twice → one block; undo → `cmp` with the
  original succeeds. Expected: no output from `cmp`.
- [ ] **Step 3: Apply for real**, then `hyprctl configerrors` (expected: no errors) and
  `hyprctl binds -j | jq '[.[] | select(.modmask == 76 or .modmask == 77) | select(.description | startswith("Window keys"))] | length'`
  (expected: `27`); `./status.sh` → `VERDICT: ACTIVE`. Ask the user to press P + Left/Right, P + 2 / P + 1 and
  P + Shift + 2 once.
- [ ] **Step 4: Commit in `~/.cfg`** (`config add …; config commit`):
  `feat(guides): window-keys: Ctrl+Alt+Super window keys, as on the Macs`.
- [ ] **Step 5: chezmoi**: add both guides to `omarchy_guides`; run the suite (expected `… passed, 0 failed`);
  `setup-guides` on works lists five guides, all ACTIVE. Commit:
  `feat(omarchy): report the window-rescue and window-keys guides`.

### Task 5: Review

- [ ] **Step 1:** One fresh reviewer on the whole branch diff (chezmoi `origin/main..HEAD` and `.cfg`
  `origin/main..HEAD`) against the spec; fix what it confirms; re-run the suite and gitleaks.

### Task 6: Rollout (with the user's go-ahead)

- [ ] **Step 1: Ask the user** to push chezmoi and `~/.cfg` (the earlier unpushed commits `f81bc53`, `d2b2184`,
  `008afa2`, the specs and this work). `.cfg` first, so `setup-guides` never reports a guide that is not there.
- [ ] **Step 2: mbp:** remove `~/.hammerspoon/local.lua`, `~/.hammerspoon/spike_keys.lua`,
  `~/Library/Logs/window-keys-spike.log`; `chezmoi update` twice (second: "match the repo"); with the user at the
  screen: P + arrows, P + Shift + arrows, P + 2 / P + 1 on each screen, P + Shift + 2 on Chrome and Slack, P + L,
  P + U, a Swish snap; read `~/Library/Logs/window-keys.log`.
- [ ] **Step 3: mbp-work, mbp-16i:** `.cfg` pull, `chezmoi update` twice. 16i: Hammerspoon stays a hand install
  (`docs/INTEL_MACS.md`); its keys are checked when the user installs it. mbp-32i: `.cfg` pull and `chezmoi git pull`
  only, plus `chezmoi apply ~/.cheatsheet.md`.
- [ ] **Step 4: works:** `config pull` (already local), `chezmoi apply`; `setup-guides` all ACTIVE.
- [ ] **Step 5:** Update the memory file `dotfiles-hosts.md` with the rollout state.
