# Terminal Leader Keys Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** tmux's letters drive the terminals' own tabs and splits behind `Cmd-b` (Mac: iTerm2, Ghostty) / `Super-b`
(Omarchy: Ghostty), Herdr's keys match the user's tmux, and nothing collides with Hyprland, macOS, tmux or Herdr.

**Architecture:** Ghostty gets a one-shot key table (`term`) and a modal resize table (`term_resize`) through the
existing `modify_config.tmpl` block. iTerm2 gets its global Leader and leader bindings through the existing
`run_after_96` after-script, once a spike on a Mac shows the preference format. Herdr's shared config gains a second
prefix and tmux defaults. The requirement checks guard the keys the scheme depends on (Hyprland Super+B, macOS
Ctrl+Space, a stale Herdr server).

**Tech Stack:** chezmoi templates, bash (`set -euo pipefail` in scripts, bash 3.2-compatible tests), awk, Ghostty 1.4
config, Herdr 0.9.5 TOML, tmux 3.8, iTerm2 preferences (`defaults`), Hyprland `hyprctl`.

**Spec:** `docs/superpowers/specs/2026-11-20-terminal-leader-keys-design.md`

## Global Constraints

- Leader: `cmd+b` on darwin, `super+b` on Linux (Omarchy). Letters after it are the user's tmux letters.
- Every close asks first: Ghostty block sets `confirm-close-surface = true` on both platforms.
- Never change Hyprland or macOS shortcuts; checks only report and add a to-do (`report warn` / `note` / `todo`).
- Herdr prefix: `prefix = ["ctrl+b", "ctrl+space"]` on every host.
- App-written files only get their listed settings from `modify_` scripts; Omarchy's other Ghostty lines and the
  existing unbinds (Ctrl+Enter, Alt+1..9, Ctrl+Alt+arrows) stay.
- Same commit as each change: `docs/CHEATSHEET.md` (AGENTS.md §2). Every apply ends with the to-do list (AGENTS.md §3.5).
- `tests/host-profiles.sh` passes; `gitleaks detect --source ~/.local/share/chezmoi -v` has 0 findings.
- Commits: conventional, author `Simar Singh <simarpaulsingh@gmail.com>`, no agent trailers, no push.
- Worktrees, if used, under `~/.local/share/chezmoi-worktrees/`, never inside the source.

## Review Focus

1. A leader letter with no binding (e.g. `Super-b q`) must do nothing at all: no stray `q` in Claude Code or zsh.
   Pinned by `ghostty +validate-config` plus the `term/catch_all=ignore` test in Task 1, and the hands-on step in Task 4.
2. Pressing the leader twice or pressing Esc after it must leave the terminal in normal mode (no stuck table). Task 1
   binds `term/escape` and `term_resize/escape`; hands-on check in Task 4.
3. Re-running `chezmoi apply` must not duplicate or reorder the block, and must keep Omarchy's own `keybind` and
   `config-file` lines. Idempotence test in Task 1.
4. The old Herdr server (0.9.1) reading the prefix array must keep `Ctrl-b` working. Hands-on check in Task 2.
5. On a Mac where Ghostty or iTerm2 already binds `Cmd-b` to something, the leader must not silently fight it. Check
   in Tasks 5 and 6.

---

### Task 1: Ghostty leader block on both platforms

**Files:**
- Modify: `dot_config/ghostty/modify_config.tmpl`
- Modify (only if a test shows it is needed): `.chezmoitemplates/kv-settings.awk.sh`
- Test: `tests/host-profiles.sh` (Ghostty section, after the line `check "Ghostty on macOS: keys left to Ghostty (it uses Cmd)" ...`)
- Docs: `docs/CHEATSHEET.md` (new section "Terminal Tabs and Splits (`Cmd-b` / `Super-b`)", placed after "tmux and
  Herdr Keys"), `AGENTS.md` §4.2 (the Ghostty modify-script sentence), `docs/FUTURE_CONSIDERATIONS.md` (new section
  "Nesting Herdr Inside tmux (parked 2026-11-20)", text from the spec's "Parked: nesting")

**Interfaces:**
- Produces: the Ghostty block contains, per platform, `keybind = <leader>=activate_key_table_once:term`, table names
  `term` and `term_resize`, and `confirm-close-surface = true`. Task 4 and 6 rely on these names in docs.

Bindings (darwin uses `cmd+b`, Linux `super+b`; the rest is identical on both):

| Trigger | Action |
| :--- | :--- |
| `<leader>` | `activate_key_table_once:term` |
| `term/catch_all` | `ignore` |
| `term/escape` | `deactivate_all_key_tables` |
| `term/c` | `new_tab` |
| `term/%`, `term/v` | `new_split:right` |
| `term/"`, `term/-` | `new_split:down` |
| `term/h`,`j`,`k`,`l` and `term/arrow_left`,`down`,`up`,`right` | `goto_split:left/down/up/right` |
| `term/;` / `term/o` | `goto_split:previous` / `goto_split:next` |
| `term/x` | `close_surface` |
| `term/z` | `toggle_split_zoom` |
| `term/1`..`term/9` | `goto_tab:1`..`9` |
| `term/n` / `term/p` | `next_tab` / `previous_tab` |
| `term/,` | `prompt_tab_title` |
| `term/&` | `close_tab` |
| `term/=` | `equalize_splits` |
| `term/?` | `toggle_command_palette` |
| `term/r` | `activate_key_table:term_resize` |
| `term_resize/h`,`j`,`k`,`l` and arrows | `resize_split:left/down/up/right,20` |
| `term_resize/escape`, `term_resize/enter` | `deactivate_all_key_tables` |
| `term_resize/catch_all` | `ignore` |

`!` is not bound (Ghostty cannot move a split into a tab; `move_tab_to_new_window` is a different thing).

- [ ] **Step 1: Find trigger spellings that validate.** On works, write each trigger above into a scratch file in the
  session scratchpad and run `ghostty +validate-config --config-file=<file>`. A scratch run already showed
  `term/percent` fails and `term/"` passes. For each punctuation key try the character first, then Ghostty's key name
  (`equal`, `comma`, `semicolon`, `minus`, `slash`). Record the spelling that passes. If no spelling passes for a key,
  drop that row and note it for the cheatsheet.

- [ ] **Step 2: Write the failing tests** in `tests/host-profiles.sh`:

```bash
ghostty_lead="$(printf 'config-file = ?"~/.local/state/omarchy/current/theme/ghostty.conf"\nconfirm-close-surface=false\nkeybind = shift+enter=csi:13;2u\n' | bash "$work/ghostty.sh")"
check "Ghostty on Omarchy: Super-b opens the term table once" 1 "$(grep -cxF 'keybind = super+b=activate_key_table_once:term' <<< "$ghostty_lead")"
check "Ghostty on Omarchy: unbound letters after the leader are swallowed" 1 "$(grep -cxF 'keybind = term/catch_all=ignore' <<< "$ghostty_lead")"
check "Ghostty on Omarchy: resize table swallows the rest too" 1 "$(grep -cxF 'keybind = term_resize/catch_all=ignore' <<< "$ghostty_lead")"
check "Ghostty on Omarchy: Omarchy's theme include and own keys kept" "1 1" "$(grep -cF 'config-file = ?' <<< "$ghostty_lead") $(grep -cxF 'keybind = shift+enter=csi:13;2u' <<< "$ghostty_lead")"
check "Ghostty on Omarchy: closing asks first, one line" "confirm-close-surface = true" "$(grep -E '^confirm-close-surface' <<< "$ghostty_lead")"
check "Ghostty on Omarchy: leader block is idempotent" "$ghostty_lead" "$(bash "$work/ghostty.sh" <<< "$ghostty_lead")"
check "Ghostty on Omarchy: every leader binding is distinct (awk kept all)" \
    "$(grep -cE '^keybind = (term|term_resize)/' <<< "$ghostty_lead")" "$(grep -E '^keybind = (term|term_resize)/' <<< "$ghostty_lead" | sort -u | wc -l | tr -d ' ')"
ghostty_mac_lead="$(printf 'a = 1\n' | bash "$work/ghostty-mac.sh")"
check "Ghostty on macOS: Cmd-b opens the term table once, no Super-b" "1 0" \
    "$(grep -cxF 'keybind = cmd+b=activate_key_table_once:term' <<< "$ghostty_mac_lead") $(grep -c 'super+b' <<< "$ghostty_mac_lead")"
check "Ghostty: both platforms bind the same term letters" \
    "$(grep -E '^keybind = term' <<< "$ghostty_lead")" "$(grep -E '^keybind = term' <<< "$ghostty_mac_lead")"
```

  Also change the existing check `"Ghostty on macOS: keys left to Ghostty (it uses Cmd)"` to count only
  `=unbind` lines that are not under `term` (`grep -c '^keybind = [^t].*=unbind'`), expected 0.

- [ ] **Step 3: Run the tests to verify they fail.**
  Run: `tests/host-profiles.sh 2>&1 | grep -E 'FAIL.*(Ghostty|leader)'`
  Expected: the new checks FAIL (no `super+b` line yet).

- [ ] **Step 4: Implement.** In `dot_config/ghostty/modify_config.tmpl`, set `LEADER` to `cmd+b` (darwin) or `super+b`
  (else), append `confirm-close-surface = true` to `BLOCK` on both platforms, then append the table rows above as
  `keybind = ...` lines (a `for` loop over `h:left j:down k:up l:right` pairs and `1..9` keeps it short). Update the
  script's header comment to name the leader and point at the cheatsheet section. If the "every leader binding is
  distinct" or idempotence check fails because a trigger contains `=`, fix the trigger extraction in
  `kv-settings.awk.sh` (take the trigger up to the first `=` after the table prefix) and add a check for it.

- [ ] **Step 5: Run the tests to verify they pass.**
  Run: `tests/host-profiles.sh 2>&1 | tail -3`
  Expected: `N passed, 0 failed`.

- [ ] **Step 6: Validate the real render on works.**
  Run: `chezmoi cat ~/.config/ghostty/config > "$SCRATCH/ghostty.config" && ghostty +validate-config --config-file="$SCRATCH/ghostty.config"`
  Expected: no output, exit 0.

- [ ] **Step 7: Docs.** Cheatsheet section with the letter table (Ghostty column; iTerm2 column marked "Task 6" until
  delivered), a line that Esc leaves the leader, `r` then `h j k l` resizes until Esc/Enter, and that foot has no tabs;
  "Keys the Terminal Must Not Take" gains rows for `Super-b` (Hyprland must leave it free) and `Cmd-b`. AGENTS.md §4.2:
  add "and a `Cmd-b` / `Super-b` leader with tmux's letters for Ghostty's own tabs and splits, and
  `confirm-close-surface = true`" to the Ghostty sentence. FUTURE_CONSIDERATIONS: parked nesting section.
  Run: `zsh -c 'source dot_aliases && cheat | grep -A12 "Terminal Tabs and Splits"'` — renders as a table.

- [ ] **Step 8: Diff, apply, commit.**
  Run: `chezmoi diff ~/.config/ghostty/config` (only the chezmoi block changes, Omarchy's lines stay), then
  `chezmoi apply ~/.config/ghostty/config`, then `gitleaks detect --source . -v` (0 findings).
  ```bash
  git add dot_config/ghostty/modify_config.tmpl .chezmoitemplates/kv-settings.awk.sh tests/host-profiles.sh docs/CHEATSHEET.md AGENTS.md docs/FUTURE_CONSIDERATIONS.md
  git commit -m "feat(ghostty): Cmd-b / Super-b leader with tmux's letters for tabs and splits; closing asks first"
  ```

### Task 2: Herdr keys match the user's tmux

**Files:**
- Modify: `dot_config/herdr/config.toml.tmpl` (`[keys]`)
- Modify: `run_after_99_assert_requirements.sh.tmpl` (next to the existing `reload_hint ... herdr` line)
- Test: `tests/host-profiles.sh` (herdr section, near `check "herdr binds nothing to alt+left/right"`)
- Docs: `docs/CHEATSHEET.md` "tmux and Herdr Keys"

**Interfaces:**
- Produces: requirement-check line `NOTE: Herdr's server runs an older binary (...)` with a to-do; Task 4 reads it.

- [ ] **Step 1: Check key names against the client.** Write a scratch copy of the rendered config with
  `prefix = ["ctrl+b", "ctrl+space"]`, `previous_workspace` gaining `"prefix+("`, `next_workspace` gaining `"prefix+)"`,
  `goto` gaining `"prefix+f"`, `copy_mode` gaining `"prefix+pageup"`, and run `herdr config check` on it
  (`HOME`/`XDG_CONFIG_HOME` pointed at a scratch dir so the live config is untouched). For each rejected key name try
  Herdr's named punctuation (`leftparen`/`rightparen` or similar from its diagnostics, `pageup`/`page_up`). Drop a key
  with no accepted spelling and note it for the cheatsheet. Do the same with the Herdr desktop app's engine if it has a
  check command (`hc --help`); if it has none, note that the app is checked by hand in Task 4.

- [ ] **Step 2: Write the failing tests:**

```bash
for host in darwin omarchy; do
    check "$host herdr takes Ctrl-b and Ctrl-Space as prefixes, like tmux" 1 "$(grep -cxF 'prefix = ["ctrl+b", "ctrl+space"]' "$work/$host.herdr")"
    check "$host herdr has tmux's ( ) for previous/next workspace" 2 "$(grep -cE '^(previous|next)_workspace = .*"prefix\+' "$work/$host.herdr")"
done
check "requirement check names a stale Herdr server" 1 "$(render omarchy run_after_99_assert_requirements.sh.tmpl | grep -c 'server_binary_stale')"
```
  (Use the spellings found in Step 1 inside the second check's pattern.)

- [ ] **Step 3: Run to verify they fail.** Run: `tests/host-profiles.sh 2>&1 | grep -E 'FAIL.*herdr|FAIL.*Herdr'` —
  the new checks FAIL.

- [ ] **Step 4: Implement the config.** In `[keys]`: `prefix = ["ctrl+b", "ctrl+space"]` with a comment that it
  mirrors tmux's `prefix2` and needs a Herdr server ≥ 0.9.2 (an older one falls back to `ctrl+b`); add the Step 1 keys
  to `previous_workspace`, `next_workspace`, `goto`, `copy_mode`. Remove the header comment line that says Herdr takes
  one prefix.

- [ ] **Step 5: Implement the stale-server check** in `run_after_99_assert_requirements.sh.tmpl`, all hosts, guarded by
  `command -v herdr` and `command -v jq`: read `herdr status --json`; when `.server.server_binary_stale` is `true`, call
  `note "Herdr's server runs an older binary (server <server.version>, installed <client.version>), so new keys such as Ctrl-Space wait for it. Fix: <command>"`.
  `<command>`: first check on works whether `herdr update --handoff` (or another documented handoff) replaces a stale
  server without closing panes when no newer release exists; use it if so, else
  `herdr server stop (closes its panes; do it when nothing is running there), then start herdr again`. Silent when no
  server runs. Never stops the server itself. Also, with the existing `version_ge`, `report warn` when the installed
  `herdr --version` is below 0.9.2: "Herdr <v> predates multiple prefixes, so Ctrl-Space is not a Herdr prefix. Fix:
  herdr update" (`brew upgrade herdr` on the Macs, `omarchy pkg add herdr` is already latest on Omarchy). Add a test
  that the rendered check contains `version_ge` with `0.9.2`.

- [ ] **Step 6: Run the tests to verify they pass.** Run: `tests/host-profiles.sh 2>&1 | tail -1` — `0 failed`.
  Also run the rendered check on works: `chezmoi execute-template < run_after_99_assert_requirements.sh.tmpl | bash 2>&1 | grep -i herdr`
  — prints the NOTE (works' server is 0.9.1).

- [ ] **Step 7: Apply and hands-on on the old server.** `chezmoi diff ~/.config/herdr/config.toml`, `chezmoi apply
  ~/.config/herdr/config.toml`, `herdr config check` (no errors), `herdr server reload-config`; in a Herdr window,
  `Ctrl-b c` still makes a tab (Review Focus 4). Record whether `Ctrl-Space` works on the 0.9.1 server.

- [ ] **Step 8: Docs and commit.** Cheatsheet "tmux and Herdr Keys": header line says both take `Ctrl-b` and
  `Ctrl-Space`; rows for `(` `)` and `f`; one line "tmux keys Herdr lacks: layouts (`Space`, `M-1..5`, `E`), rotate
  (`C-o`), paste buffers (`]` `#` `=`), command prompt (`:`), mark (`m`), move/index window (`.` `'`)".
  ```bash
  git add dot_config/herdr/config.toml.tmpl run_after_99_assert_requirements.sh.tmpl tests/host-profiles.sh docs/CHEATSHEET.md
  git commit -m "feat(herdr): Ctrl-Space as second prefix and tmux's ( ) f PageUp; to-do for a stale Herdr server"
  ```

### Task 3: Omarchy guard for Super-b, and foot

**Files:**
- Modify: `run_after_99_assert_requirements.sh.tmpl` (Omarchy-only block)
- Modify (only if Step 4 shows a leak): `dot_config/foot/modify_foot.ini`
- Test: `tests/host-profiles.sh`
- Docs: `docs/CHEATSHEET.md` ("Keys the Terminal Must Not Take")

**Interfaces:**
- Produces: requirement-check function `check_super_b` (Omarchy only), prints `OK:   Super+B is free in Hyprland
  (terminal leader)` or `report warn "Hyprland binds Super+B (<description>) ..."`.

- [ ] **Step 1: Write the failing tests.** Stub `hyprctl` and `jq` usage: render the Omarchy requirement check, then
  run only `check_super_b` with a stub `hyprctl` in `PATH` printing `[{"modmask":64,"key":"B","description":"X"}]`
  (expect a line containing `Hyprland binds Super+B (X)`) and one printing `[{"modmask":65,"key":"B","description":"Browser"}]`
  (expect `OK:   Super+B is free`). Extract the function the way existing tests source rendered snippets (e.g.
  `sed -n '/^check_super_b()/,/^}/p'`), and add `check "darwin requirement check has no Hyprland check" 0 ...`.

- [ ] **Step 2: Run to verify they fail.** Expected: FAIL, function missing.

- [ ] **Step 3: Implement `check_super_b`** in the Omarchy block: skip silently unless `hyprctl binds -j` answers and
  `jq` exists; select binds with `modmask == 64` and `key` equal to `b` ignoring case; warn with the description(s)
  and the fix "Ghostty's terminal leader needs Super+B: unbind it in ~/.config/hypr/bindings.lua or pick another
  leader in dot_config/ghostty/modify_config.tmpl". Call it.

- [ ] **Step 4: Test foot by hand on works.** In foot, run `cat -v` (no tmux), press Super+B: note what prints. Then in
  `tmux` inside foot, run `cat -v` and press Super+B. If nothing prints in both, foot does not leak: skip Step 5 and
  record "foot: Super+B ignored" in the cheatsheet row.

- [ ] **Step 5 (only if Step 4 printed something): bind it to nothing in foot.** Extend `modify_foot.ini` to also
  ensure `noop=Super+b` under `[key-bindings]` (same pass-through awk pattern it uses for `[main]`; foot accepts one
  `noop=` line with several space-separated keys, so merge into an existing `noop=` line rather than adding a second).
  Add tests: section missing, section present without `noop`, `noop=` present with another key, second run unchanged.

- [ ] **Step 6: Run tests, apply, verify.** `tests/host-profiles.sh 2>&1 | tail -1` → `0 failed`; `chezmoi apply` the
  changed files; the requirement check prints `OK:   Super+B is free in Hyprland (terminal leader)`.

- [ ] **Step 7: Docs and commit.**
  ```bash
  git add run_after_99_assert_requirements.sh.tmpl tests/host-profiles.sh docs/CHEATSHEET.md dot_config/foot/modify_foot.ini
  git commit -m "feat(omarchy): check that Hyprland leaves Super+B to the terminal leader"
  ```

### Task 4: tmux terminal features, and the works hands-on matrix

**Files:**
- Modify (only per findings): `dot_config/tmux/tmux.conf` (the `terminal-features` lines under `# General`)
- Docs: `docs/CHEATSHEET.md`, `docs/TESTING_AND_VERIFICATION_GUIDE.md` (new subsection with the matrix and results)

- [ ] **Step 1: Add Ghostty's extended keys for tmux before 3.8.** After `set -ag terminal-features "xterm-kitty:extkeys"`
  add `set -ag terminal-features "xterm-ghostty:extkeys"` with a comment (tmux 3.8 detects Ghostty itself; older
  tmux on the Macs does not). Add a test that the line exists once.

- [ ] **Step 2: Measure on works.** In each of foot and Ghostty, `tmux new -s probe`, then
  `tmux display -p '#{client_termfeatures}'`. Record whether `extkeys` is present. If foot lacks it, add a
  terminal-features line that targets foot only if tmux can tell foot apart (check `tmux display -p '#{client_termname}'`
  and XTVERSION-based detection); otherwise document "foot: Ctrl+Enter / Shift+Enter inside tmux arrive as plain keys"
  in "Keys the Terminal Must Not Take".

- [ ] **Step 3: Hands-on matrix on works** (foot, Ghostty; each local and `ssh localhost` into tmux): `Ctrl-b c` and
  `Ctrl-Space c` make tmux windows; in Ghostty `Super-b %`, `Super-b h`, `Super-b r` then `l l` then Esc,
  `Super-b q` (nothing happens, no `q` typed), `Super-b` Esc (back to normal typing), `Super-b x` asks while a program
  runs; Claude Code inside tmux gets Ctrl+Enter and Shift+Enter; a `y` in tmux copy mode and in Herdr copy mode lands
  in the Wayland clipboard (local) and through OSC 52 (over ssh). The Herdr desktop app on works still starts and
  takes `Ctrl-b`. Write the results as a table.

- [ ] **Step 4: Commit.**
  ```bash
  git add dot_config/tmux/tmux.conf tests/host-profiles.sh docs/CHEATSHEET.md docs/TESTING_AND_VERIFICATION_GUIDE.md
  git commit -m "fix(tmux): extended keys from Ghostty on tmux before 3.8; record the works key matrix"
  ```

### Task 5: macOS Ctrl+Space check (needs no Mac to write; a Mac to verify)

**Files:**
- Modify: `run_after_96_macos_iterm2.sh.tmpl` (before the "Settings changed in iTerm2 on this Mac only" block)
- Test: `tests/host-profiles.sh` (the stub-Mac section around `iterm_after`)
- Docs: `docs/NEW_MACHINE.md` (macOS steps), `docs/CHEATSHEET.md` ("Keys the Terminal Must Not Take")

- [ ] **Step 1: Write the failing tests** using the existing stub Mac (`iterm_after`, stub `defaults`): a stub
  `defaults read com.apple.symbolichotkeys AppleSymbolicHotKeys` output in which id `60` has `enabled = 1` → output
  contains `Ctrl+Space selects the previous input source` and a to-do; with `enabled = 0` → `OK:   Ctrl+Space reaches
  tmux`; with entry `60` absent → print nothing (iTerm2's script cannot tell the default state, so stay silent). Check the real `defaults` output shape on a Mac before fixing the stub format; until then the stub
  uses the plist text form `60 = { enabled = 1; ... };`.

- [ ] **Step 2: Run to verify they fail.**

- [ ] **Step 3: Implement** a check that reads `defaults read com.apple.symbolichotkeys AppleSymbolicHotKeys`,
  finds entry `60`, and when enabled prints `NOTE: macOS takes Ctrl+Space (select the previous input source), so it
  never reaches tmux or Herdr` with `todo "Turn off System Settings > Keyboard > Keyboard Shortcuts > Input Sources >
  Select the previous input source, so Ctrl+Space reaches tmux and Herdr"`. Never writes the setting.

- [ ] **Step 4: Run tests to verify they pass;** add the step to `docs/NEW_MACHINE.md`; commit.
  ```bash
  git add run_after_96_macos_iterm2.sh.tmpl tests/host-profiles.sh docs/NEW_MACHINE.md docs/CHEATSHEET.md
  git commit -m "feat(macos): to-do when macOS takes Ctrl+Space from tmux and Herdr"
  ```

### Task 6: iTerm2 leader (on a Mac)

Runs from a session on a Mac or when `ssh mbp-work` answers. The Macs were unreachable on 2026-11-20.

**Files:**
- Modify: `run_after_96_macos_iterm2.sh.tmpl`, `.chezmoidata/macos.toml` (new table `iterm2_leader`)
- Test: `tests/host-profiles.sh` (stub Mac)
- Docs: `docs/CHEATSHEET.md` (iTerm2 column of "Terminal Tabs and Splits"), "Same iTerm2 on Every Mac"

- [ ] **Step 1: Spike (by hand, reversible).** `defaults export com.googlecode.iterm2 "$SCRATCH/before.plist"`; in
  iTerm2 Settings > Keys set Leader to Cmd-B and add leader bindings for `c` (New Tab with Current Profile) and `%`
  (Split Vertically with Current Profile); export to `after.plist`; `diff <(plutil -p before.plist) <(plutil -p after.plist)`.
  Record: the leader's preference key and value format, where leader bindings live (`GlobalKeyMap` entry key format,
  action code numbers), and whether profile `"Keyboard Map": {}` in `chezmoi-0-shared-look.json` shadows them. Also
  record whether an unbound letter after the leader reaches the program (`cat -v`), and whether iTerm2 already binds
  Cmd-B. Undo by hand or `defaults import` the before file.

- [ ] **Step 2: Map the letters** of Task 1's table to iTerm2 actions found in the spike (menu items through "Select
  Menu Item" where there is no direct action). Letters with no action get iTerm2's Ignore action if Step 1 showed
  unbound letters leak; resize gets the native keys if there is no repeatable form. Put the map in
  `.chezmoidata/macos.toml` as `[iterm2_leader]` (leader plus `letter = action` entries in the format the spike found).

- [ ] **Step 3: Write failing stub-Mac tests:** leader missing → written and "quit and reopen iTerm2" to-do; leader
  present and bindings equal → `OK:   iTerm2's leader keys match the repo`; a user's own extra `GlobalKeyMap` entry
  survives the write.

- [ ] **Step 4: Implement** `ensure_leader` in `run_after_96_macos_iterm2.sh.tmpl` beside `ensure_global`: write only
  what differs, merge into `GlobalKeyMap` without dropping other entries, add to `updated`/`failed` so the existing
  reopen to-do and failure note cover it.

- [ ] **Step 5: Run tests, apply on the Mac, verify** each letter in iTerm2; update the cheatsheet's iTerm2 column;
  commit.
  ```bash
  git add run_after_96_macos_iterm2.sh.tmpl .chezmoidata/macos.toml tests/host-profiles.sh docs/CHEATSHEET.md
  git commit -m "feat(iterm2): Cmd-b leader with tmux's letters for tabs and splits"
  ```

### Task 7: Mac hands-on matrix (on a Mac)

- [ ] **Step 1:** `ghostty +list-keybinds --default | grep 'cmd+b'` — nothing (else note what it was and that the
  leader replaces it). `chezmoi cat ~/.config/ghostty/config | ghostty +validate-config --config-file=/dev/stdin`
  (or a temp file) — exit 0.
- [ ] **Step 2:** `tmux -V`, `herdr --version`; requirement check shows no Herdr or Ctrl+Space to-do left.
- [ ] **Step 3:** The Task 4 Step 3 matrix with iTerm2 and Ghostty on the Mac, `Cmd-b` as leader, plus Cmd+T, Cmd+D,
  Cmd+1..9 still native in both; `ssh works` into tmux from each.
- [ ] **Step 4:** Add the Mac rows to `docs/TESTING_AND_VERIFICATION_GUIDE.md`; fix the cheatsheet where a key
  behaved differently; commit `docs: record the Mac key matrix for the terminal leader`.
