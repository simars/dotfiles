# Caps Lock Prefix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Holding Caps Lock acts as the window-key prefix on the Macs and on Omarchy; a tap still toggles capitals.

**Architecture:** Mac: `hidutil` maps Caps Lock to F18 (a LaunchAgent at login, and the macOS settings script on each
apply); a Hammerspoon event tap in the window-keys module turns "F18 held + key" into the window-key actions and a
lone F18 tap into a Caps Lock toggle. Omarchy: keyd (private guide) makes a held Caps Lock Ctrl+Alt+Super and a tap
Caps Lock, so the window-keys guide's bindings fire unchanged.

**Tech Stack:** Hammerspoon 1.1.1 Lua (`hs.eventtap`, `hs.hid.capslock`), macOS `hidutil` and launchd, chezmoi
templates and bash 3.2, keyd 2.6 (Arch extra), `tests/host-profiles.sh`, `tests/hammerspoon-stub.lua`.

**Spec:** `docs/superpowers/specs/2026-11-26-caps-lock-prefix-design.md`

## Global Constraints

- Tap Caps Lock = capitals on/off as today; hold + key = prefix + key; Omarchy Shift+Caps = Compose, unchanged.
- No Escape on Caps; no other key; the three-key prefix keeps working; no new Mac app; no SIP change.
- Mac remap: source `0x700000039` (Caps Lock) to destination `0x70000006D` (F18): decimal `30064771129` and
  `30064771181` in `hidutil`'s JSON. F18 is macOS key code `79`.
- Omarchy: `omarchy pkg add keyd` only (never pacman); config `/etc/keyd/default.conf`; sudo only from the user's
  terminal (apply.sh), never from the agent.
- Public chezmoi repo: no work identifiers; commit as `Simar Singh <simarpaulsingh@gmail.com>`, no trailers; gitleaks
  clean; cheatsheet in the same commit as behaviour; `~/.cfg` only via `config`/`git --git-dir=$HOME/.cfg`.
- Nothing pushed and nothing applied to another machine without the user's go-ahead.

## Review Focus

1. A Caps tap toggles capitals exactly once, even though the key auto-repeats while held (Task 3 test: repeated F18
   downs then one up = one toggle).
2. Caps held, a window key pressed, Caps released: no capitals toggle (Task 3 test).
3. A keyboard plugged in after login (the Kinesis) still has the remap (Task 1 live check; Task 2 adds the trigger if
   it fails).
4. A Mac where the remap is missing (before the agent ran, or after `hidutil` was reset) is fixed by the next apply
   and reported if that fails (Task 2 tests).
5. On Omarchy, a guide run twice leaves one config and `undo.sh` restores whatever `/etc/keyd/default.conf` held
   before (Task 4 offline test).

---

### Task 1: Throwaway check on mbp (with the user at the unlocked screen)

**Files:** none in the repo; a one-off `~/.hammerspoon/local.lua` + `caps_spike.lua` on mbp, removed after.

**Interfaces:**
- Produces: for Task 2, whether `hidutil property --set` without `--matching` reaches a keyboard connected later
  (yes: login agent alone is enough; no: the agent also runs on keyboard connect); for Task 3, that Hammerspoon sees
  F18 (`keyCode 79`) down/up through an `hs.eventtap` and that `hs.hid.capslock.toggle()` toggles capitals and its light.

- [ ] **Step 1:** On mbp: `hidutil property --set '{"UserKeyMapping":[{"HIDKeyboardModifierMappingSrc":30064771129,"HIDKeyboardModifierMappingDst":30064771181}]}'`;
  spike logs F18 down/up and toggles capitals on a lone tap; Caps+Left logs "layer left". Expected in its log: down,
  up, toggle on tap; "layer left" and no toggle on Caps+Left.
- [ ] **Step 2:** The user unplugs and replugs an external keyboard (or plugs one in), taps Caps on it. Expected: the
  same log lines. Record the result in the ledger.
- [ ] **Step 3:** Remove the spike files and reset with `hidutil property --set '{"UserKeyMapping":[]}'`.

### Task 2: The remap on every Mac (chezmoi)

**Files:**
- Create: `private_Library/LaunchAgents/dotfiles.caps-lock-f18.plist` (label `dotfiles.caps-lock-f18`)
- Modify: `run_after_97_macos_defaults.sh.tmpl`, `.chezmoidata/macos.toml` (one `[caps_lock_remap]` table: `src`,
  `dst`), `tests/host-profiles.sh` (the `md` stub section), `docs/CHEATSHEET.md` ("Same macOS Settings on Every Mac")

**Interfaces:**
- Produces: on every Mac, Caps Lock arrives as F18 (key code 79).

- [ ] **Step 1: Failing tests:**
  - `check "darwin and intel manage the Caps Lock agent"` yes yes; Linux hosts no (`.chezmoiignore` already ignores
    `Library` off macOS).
  - `check "the Caps Lock agent runs hidutil with Caps Lock to F18 at load"`: the plist has `RunAtLoad` true and the
    `UserKeyMapping` JSON with `30064771129` and `30064771181` (and, if Task 1 Step 2 failed, a `LaunchEvents` IOKit
    keyboard match).
  - With a `hidutil` stub in `$md/bin` (`property --get UserKeyMapping` prints a file; `--set` writes it):
    `check "Caps Lock remap missing: set, reported as updated"` (`hidutil --set` called once; the updated line names
    `Caps Lock as F18`); `check "Caps Lock remap present: nothing set"`; `check "Caps Lock remap cannot be set: NOTE and
    to-do"` (stub `--set` exits 1; to-do "Log out and back in, so Caps Lock works as the window-key prefix").
- [ ] **Step 2:** Run the suite. Expected: the new checks FAIL.
- [ ] **Step 3:** Implement: the plist; in the 97 script, read `hidutil property --get UserKeyMapping`, and when it
  lacks the pair set it (`HIDUTIL` env override for the stub, default `/usr/bin/hidutil`).
- [ ] **Step 4:** Suite passes. Cheatsheet row. Commit `feat(macos): Caps Lock arrives as F18 on every Mac`.

### Task 3: The Caps layer in Hammerspoon

**Files:**
- Modify: `dot_hammerspoon/window_keys.lua.tmpl`, `tests/hammerspoon-stub.lua`, `tests/host-profiles.sh`,
  `docs/CHEATSHEET.md` ("Window Keys": the Caps rows)

**Interfaces:**
- Consumes: F18 = key code 79 (Task 2); the module's existing `focusDir`, `swapDir`, `M.go`, `M.send`, `tile`,
  `window_rescue.rescue(false)`.
- Produces: `M.capsKey(kind, keyName, shift, isRepeat) -> action, consume` (pure: no `hs` calls), where `kind` is
  `"down"` or `"up"`, `keyName` an `hs.keycodes.map` name (`"f18"`, `"left"`, `"1"`, `"l"`), and `action` one of
  `"toggle-caps"`, `"focus <dir>"`, `"swap <dir>"`, `"go <n>"`, `"send <n>"`, `"tile"`, `"rescue"`, or nil; `consume`
  true for every event while F18 is held and for F18 itself. `M.start()` adds an `hs.eventtap` (keyDown, keyUp) that
  calls it and runs the action.

- [ ] **Step 1: Failing tests** (Lua, the stub's style), each a sequence of `M.capsKey` calls and the actions it
  returns:
  - `"f18 down, f18 up" -> toggle-caps`; `"f18 down x3 (repeats), f18 up" -> toggle-caps once`;
  - `"f18 down, left down, left up, f18 up" -> focus left`, no toggle-caps;
  - `"f18 down, left down shift" -> swap left`; `"3 down" -> go 3`; `"3 down shift" -> send 3`; `"l" -> tile`;
    `"u" -> rescue`; `"a down" -> nil, consumed`;
  - outside the layer: `"left down" -> nil, not consumed`.
- [ ] **Step 2:** Run. Expected: FAIL (`capsKey` missing).
- [ ] **Step 3:** Implement `M.capsKey` with module state (held, used) and the event tap in `M.start()` (keep it in
  `M.capsTap`, restart it if `isEnabled()` turns false).
- [ ] **Step 4:** Suite passes. Cheatsheet: Caps rows in "Window Keys". Commit
  `feat(macos): hold Caps Lock for the window keys; a tap still toggles capitals`.

### Task 4: The Omarchy guide (private `~/.cfg`) and its registration

**Files:**
- Create: `~/guides/omarchy/caps-prefix/{README.md,apply.sh,undo.sh,status.sh,test.sh,common.sh}`
- Modify: `~/guides/README.md`, `~/guides/omarchy/README.md`; chezmoi `.chezmoidata/omarchy.toml` `omarchy_guides`
  (+ `"caps-prefix"`), its test, `docs/NEW_MACHINE.md`, `bootstrap/omarchy.sh` comment, cheatsheet guide lists.

**Interfaces:**
- Produces: `/etc/keyd/default.conf` containing exactly
  `[ids]` `*` / `[main]` `capslock = overload(window, capslock)` / `[window:C-A-M]`, marked as written by the guide;
  `status.sh` VERDICT ACTIVE when keyd is installed, `keyd` service active, and the file matches.

- [ ] **Step 1: Failing offline test** (`test.sh`, scratch paths via `KEYD_CONF`, stubs for `omarchy`, `systemctl`,
  `keyd`, `sudo` on PATH): apply writes the exact config; apply twice = same file; an existing unrelated config is
  backed up and restored byte for byte by undo; undo when not applied exits 0; apply installs keyd only when
  `omarchy pkg missing keyd`.
- [ ] **Step 2:** Run. Expected: FAIL.
- [ ] **Step 3:** Implement (pattern of `window-keys`; sudo for `/etc` writes and `systemctl enable --now keyd`,
  then `sudo keyd reload`).
- [ ] **Step 4:** `test.sh` passes. Commit in `~/.cfg`.
- [ ] **Step 5:** The user runs `~/guides/omarchy/caps-prefix/apply.sh` in a terminal; then checks: Caps tap toggles
  capitals; Caps+Left/2/Shift+2/U act as Ctrl+Alt+Super; Shift+Caps, Space, N types the name (Compose); keyboard
  layout and the other input settings unchanged (`hyprctl devices` shows keyd's virtual keyboard with the same
  layout). If any fails: `undo.sh`, ledger, fix.
- [ ] **Step 6:** chezmoi registration (guide list, tests, docs) and commit.

### Task 5: Review and rollout

- [ ] **Step 1:** One fresh reviewer on the whole change (chezmoi range and the `~/.cfg` guide); fix what it confirms.
- [ ] **Step 2:** With the user's go-ahead: push `.cfg` then chezmoi; `chezmoi update` twice on mbp, mbp-work,
  mbp-16i (second: "match the repo"); the user taps and holds Caps on mbp once; `setup-guides` on works all ACTIVE.
