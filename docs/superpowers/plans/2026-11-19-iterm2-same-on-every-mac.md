# The Same iTerm2 on Every Mac Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every Mac gets the same iTerm2 look, global settings and trigger behaviour from the repo. Each apply checks
the default profile and the Claude Code integration, and reports settings changed on one Mac only.

**Architecture:**
- A new chezmoi-owned dynamic profile, "Shared Look (chezmoi)", holds the look and the trigger switch.
- The existing rewritable profile becomes its child.
- The macOS iTerm2 after-script writes global settings from `.chezmoidata/macos.toml` and prints the checks.
- `tests/host-profiles.sh` tests everything off macOS, through rendered templates and stub commands.

**Tech Stack:** chezmoi templates, bash, jq, `defaults` (stubbed in tests), Python 3 for the one-off capture.

**Spec:** `docs/superpowers/specs/2026-11-19-iterm2-same-on-every-mac-design.md`

## Global Constraints

- macOS only. Other hosts manage neither profile file and render the after-script empty.
- **File names.**
  - Shared profile: `private_Library/private_Application Support/iTerm2/DynamicProfiles/chezmoi-0-shared-look.json.tmpl`,
    target `chezmoi-0-shared-look.json`. Its name must sort before `chezmoi-option-as-alt.json`.
  - After-script: `run_after_96_macos_iterm2.sh.tmpl`, replacing `run_after_96_macos_terminal_clipboard.sh.tmpl`.
- **Shared profile identity.** `Name` "Shared Look (chezmoi)", `Guid` `chezmoi-shared-look`,
  `Dynamic Profile Parent Name` "Default". Not rewritable (no `Rewritable` key).
- **Child profile** (`modify_chezmoi-option-as-alt.json`, stays a plain script).
  - Sets `Dynamic Profile Parent GUID` to `chezmoi-shared-look`.
  - Deletes `Dynamic Profile Parent Name`, `Right Option Key Sends` and `Enable Triggers in Interactive Apps`.
  - Keeps today's `Name`, `Guid`, `Option Key Sends` 2, `Rewritable` true, and adds the Claude triggers when missing.
  - Passes everything else through, and leaves non-JSON or no-`jq` input unchanged.
- **The picks.**
  - Fonts: `Normal Font` and `Non Ascii Font` are `JetBrainsMonoNFM-Regular 12`, with `Use Non-ASCII Font` false.
  - `ASCII Ligatures` and `Non-ASCII Ligatures` are false.
  - `Silence Bell` and `Flashing Bell` are true.
  - Everything else is mbp-work's "Default" values. Excluded: `Name`, `Guid`, `Description`, `Default Bookmark`,
    `Shortcut`, `Tags`, `Working Directory`, `Option Key Sends`.
- **Data** (`.chezmoidata/macos.toml`).
  - `iterm2_triggers_in_interactive_apps = false`.
  - `[iterm2_globals]` holds `AllowClipboardAccess = true`, `CopySelection = true`,
    `DoubleClickPerformsSmartSelection = true`, `ShowFullScreenTabBar = false`, `HapticFeedbackForEsc = false`,
    `SoundForEsc = false`, `VisualIndicatorForEsc = false`, `"Print In Black And White" = true` and
    `PasteTabToStringTabStopSize = 4`.
- **After-script behaviour.**
  - It is informational: always exit 0, and every line starts with `OK:   ` (three spaces) or `NOTE: `.
  - It is silent when `"${ITERM2_APP:-/Applications/iTerm.app}"` is not a directory.
  - `ITERM2_APP` is the only test hook, and it defaults to the real path.
- **Repository rules.**
  - `docs/CHEATSHEET.md` is updated in the same commit as the behaviour it documents.
  - `bash tests/host-profiles.sh` ends `N passed, 0 failed`.
  - `gitleaks detect --source . -v` is clean.
  - No work organisation names, work emails or work paths anywhere.
- **Commits.** Conventional, author `Simar Singh <simarpaulsingh@gmail.com>`, no `Co-Authored-By` or agent trailers.

## Review Focus

1. A key added to the child script but not to the report's list would make every Mac print a false `NOTE:`. Task 2's
   all-OK test runs the report on the child script's own output.
2. A captured value names a font that isn't installed, such as Hack. Task 1 tests that the shared profile contains no
   "Hack".
3. The shared file is renamed so it sorts after the child, and inheritance silently breaks. Task 1 tests the order.
4. A boolean global is read back as `1`/`0`, while the repo says `true`/`false`. A wrong comparison would rewrite it on
   every apply. Task 2 tests that matching values give `OK:` and write nothing.
5. The child profile is not JSON, or there is no `jq`. The script must say nothing about local changes and still exit
   0. Task 2 has a test.

---

### Task 0: Spike: a dynamic profile as another dynamic profile's parent (controller, throwaway)

- [ ] On mbp-work, write `~/Library/Application Support/iTerm2/DynamicProfiles/zz-spike-a.json`. It holds one profile:
  `Name` "Spike Parent", `Guid` `spike-parent`, `Dynamic Profile Parent Name` "Default", `Normal Font` "Courier 13".
- [ ] Write `zz-spike-b.json` with: `Name` "Spike Child", `Guid` `spike-child`,
  `Dynamic Profile Parent GUID` `spike-parent`.
- [ ] Wait 5 s. Then read iTerm2's cached copy:
  `plutil -extract "New Bookmarks" json -o - ~/Library/Preferences/com.googlecode.iterm2.plist | jq '.[] | select(.Guid=="spike-child") | ."Normal Font"'`.
  Expected: `"Courier 13"`. If the cache isn't updated, ask the user to open a tab with "Spike Child" and confirm the
  font is Courier.
- [ ] Delete both files. If inheritance failed, stop and report to the user: the fallback is approach B.

### Task 1: The shared look profile, the switch and the child's new parent

**Files:**
- Create: `.chezmoidata/macos.toml` (the switch only; Task 2 adds the globals)
- Create: `private_Library/private_Application Support/iTerm2/DynamicProfiles/chezmoi-0-shared-look.json.tmpl`
- Modify: `private_Library/private_Application Support/iTerm2/DynamicProfiles/modify_chezmoi-option-as-alt.json`
- Modify: `docs/CHEATSHEET.md` (the iTerm2 row; a new "Same iTerm2 on every Mac" block after "iTerm2 Shell
  Integration and Claude Code")
- Test: `tests/host-profiles.sh` (iTerm2 profile checks, around lines 287-302)

**Interfaces:**
- Produces: data key `.iterm2_triggers_in_interactive_apps`, and the shared profile's `Guid` `chezmoi-shared-look`.
- Produces in tests: `shared_look VALUE` renders the shared template for darwin. `VALUE` is `repo` (don't override)
  or `true`/`false`, passed as `--override-data "$(host_data darwin | jq -c ". + {iterm2_triggers_in_interactive_apps: $VALUE}")"`.

- [ ] **Step 1: Capture (one-off, not committed).** Export with `ssh mbp-work 'defaults export com.googlecode.iterm2 -'`
  to the scratchpad. Load it with `python3 -I` and `plistlib`, and take the `New Bookmarks` entry whose `Name` is
  "Default". Drop the excluded keys and apply the picks from Global Constraints. Print the result as `json.dumps(…,
  indent=2, sort_keys=True)`. This becomes the profile body in the template, between the identity keys and the switch
  line.

- [ ] **Step 2: Write the failing tests.** In the existing `jq` guard, add:

```bash
shared="Library/Application Support/iTerm2/DynamicProfiles/chezmoi-0-shared-look.json"
check "darwin manages the shared iTerm2 look" yes "$(manages darwin "$shared")"
for host in omarchy arch ubuntu; do check "$host leaves the shared iTerm2 look alone" no "$(manages "$host" "$shared")"; done
check "shared look loads before the profile that inherits from it" yes "$([[ chezmoi-0-shared-look.json < chezmoi-option-as-alt.json ]] && echo yes)"
check "shared look: identity and parent" "Shared Look (chezmoi)|chezmoi-shared-look|Default|false" \
    "$(shared_look repo | jq -r '.Profiles[0] | "\(.Name)|\(.Guid)|\(."Dynamic Profile Parent Name")|\(has("Rewritable"))"')"
check "shared look: JetBrains Mono Nerd Font Mono, no second font, no ligatures" "JetBrainsMonoNFM-Regular 12|JetBrainsMonoNFM-Regular 12|false|false|false" \
    "$(shared_look repo | jq -r '.Profiles[0] | "\(."Normal Font")|\(."Non Ascii Font")|\(."Use Non-ASCII Font")|\(."ASCII Ligatures")|\(."Non-ASCII Ligatures")"')"
check "shared look: silent, flashing bell and all 16 ANSI colours" "true|true|true" \
    "$(shared_look repo | jq -r '.Profiles[0] as $p | "\($p."Silence Bell")|\($p."Flashing Bell")|\([range(0;16) | "Ansi \(.) Color"] | all(. as $k | $p | has($k)))"')"
check "shared look: no per-Mac or left-Option keys" "" \
    "$(shared_look repo | jq -r '.Profiles[0] | keys[] | select(IN("Description","Default Bookmark","Shortcut","Tags","Working Directory","Option Key Sends"))')"
check "shared look: names no font that isn't installed (Hack)" 0 "$(shared_look repo | grep -c Hack)"
check "shared look: triggers off in full-screen apps by default" false "$(shared_look repo | jq '.Profiles[0]."Enable Triggers in Interactive Apps"')"
check "shared look: switch on writes true" true "$(shared_look true | jq '.Profiles[0]."Enable Triggers in Interactive Apps"')"
check "iTerm2 profile: inherits from the shared look" "chezmoi-shared-look|false|false|false|2" \
    "$(printf '' | bash "$iterm_modify" | jq -r '.Profiles[0] | "\(."Dynamic Profile Parent GUID")|\(has("Dynamic Profile Parent Name"))|\(has("Right Option Key Sends"))|\(has("Enable Triggers in Interactive Apps"))|\(."Option Key Sends")"')"
check "iTerm2 profile: drops the old parent and a local trigger switch, keeps other local settings" "false|false|x" \
    "$(printf '{"Profiles": [{"Dynamic Profile Parent Name": "Default", "Enable Triggers in Interactive Apps": true, "Font": "x"}]}' | bash "$iterm_modify" | jq -r '.Profiles[0] | "\(has("Dynamic Profile Parent Name"))|\(has("Enable Triggers in Interactive Apps"))|\(.Font)"')"
check "iTerm2 profile: leaves a file that is not JSON alone" "not json" "$(printf 'not json' | bash "$iterm_modify")"
```

  Update the existing "left Option Esc+, right Option from Default…" check. Its name becomes "…right Option from the
  shared look…", with the same expected value.

- [ ] **Step 3: Run** `bash tests/host-profiles.sh 2>&1 | tail -15`. Expected: FAIL lines for the new checks.

- [ ] **Step 4: Implement.**
  - `.chezmoidata/macos.toml` with the switch and its comments. Follow `.chezmoidata/omarchy.toml`'s style: switch
    for good, or try without a commit under `[data]` in `~/.config/chezmoi/chezmoi.toml`.
  - The shared template: a `{{/* … */}}` comment on top, saying what the file is, that iTerm2 never rewrites it, and
    why its name sorts first. Then the JSON with identity keys, the captured body, and
    `"Enable Triggers in Interactive Apps": {{ .iterm2_triggers_in_interactive_apps }}`.
  - The child script: add the parent GUID and the three deletions to the jq program, and rewrite its header comment
    (look and switch now come from the shared profile).

- [ ] **Step 5: Run** `bash tests/host-profiles.sh 2>&1 | tail -3`. Expected: `… passed, 0 failed`.

- [ ] **Step 6: Cheatsheet.**
  - In the iTerm2 row: the profile now inherits from "Shared Look (chezmoi)", not from your "Default". Change looks
    in the repo, not in "Default".
  - Add a "Same iTerm2 on every Mac" block with:
    - what is shared (the look, with the picks in one line, and the trigger switch) and the two files;
    - how to change it (edit, commit, push, `chezmoi update` on each Mac);
    - that edits in iTerm2's Settings stay on that Mac;
    - that the profile list shows the shared profile.

- [ ] **Step 7: Commit** `feat(iterm2): one shared look for every Mac, triggers off in full-screen apps`.

### Task 2: Global settings and the four checks in the iTerm2 after-script

**Files:**
- Rename and modify: `run_after_96_macos_terminal_clipboard.sh.tmpl` → `run_after_96_macos_iterm2.sh.tmpl` (`git mv`)
- Modify: `.chezmoidata/macos.toml` (add `[iterm2_globals]`)
- Modify: `docs/CHEATSHEET.md` (the "Same iTerm2 on every Mac" block; the clipboard row mentioning reopening iTerm2)
- Test: `tests/host-profiles.sh` (the clipboard checks, around lines 325-330)

**Interfaces:**
- Consumes: the child script's output, the profile as chezmoi writes it (`printf '' | bash "$iterm_modify"`).
- Produces: the rendered darwin script, with one line per global, in key order:
  - `ensure_global "<key>" -bool true|false`, or
  - `ensure_global "<key>" -int <n>`.

  `ensure_global` compares `defaults read com.googlecode.iterm2 "<key>"` against `1`/`0`/`<n>`. On a mismatch or a
  missing key it runs `defaults write com.googlecode.iterm2 "<key>" -bool|-int <value>` and records the key.

  Output lines, exactly, in this order:
  1. `OK:   iTerm2's global settings match the repo`, or
     `NOTE: iTerm2 global settings updated: <keys joined ", ">; quit and reopen iTerm2 for them to take effect` (iTerm2
     running), or `OK:   iTerm2 global settings updated: <keys>` (not running).
  2. `OK:   iTerm2's default profile is "Default (Left Option as Alt)"`, or
     `NOTE: iTerm2's default profile is not "Default (Left Option as Alt)": Settings > Profiles, select it, Other Actions > Set as Default (open iTerm2 once first if it never ran)`.
  3. `OK:   iTerm2's Claude Code integration is installed`, or
     `NOTE: iTerm2's Claude Code integration is missing (hook or helper): iTerm2 > Install Claude Code Integration`.
  4. `OK:   iTerm2 profile has no settings changed on this Mac only`, or
     `NOTE: iTerm2 settings changed on this Mac only, not shared: <list>. To share them, move them into chezmoi-0-shared-look.json.tmpl; to drop them, delete them from ~/Library/Application Support/iTerm2/DynamicProfiles/chezmoi-option-as-alt.json`.
     `<list>` is the extra keys in jq `keys` order, then `trigger <action>` for each extra trigger, joined by `, `.
     Line 4 is absent when the file is missing or not JSON, or there is no `jq`.

- [ ] **Step 1: Write the failing tests.** Rename the three clipboard checks to the new file. Change the first one to
  assert that the render contains `ensure_global "AllowClipboardAccess" -bool true`. Add:
  - `manages darwin 96_macos_iterm2.sh` → `yes`, and `manages darwin 96_macos_terminal_clipboard.sh` → `no`.
  - The rendered script contains exactly 9 `ensure_global "` lines.
  - It contains `ensure_global "Print In Black And White" -bool true`, `ensure_global "ShowFullScreenTabBar" -bool false`
    and `ensure_global "PasteTabToStringTabStopSize" -int 4`.

  Add a helper `iterm_after` driven by a stub directory `$work/it`:
  - `$work/it/iTerm.app/`.
  - `home/` with `.claude/settings.json`, `.config/iterm2/it2` and the profile file.
  - `defaults/<key>` files. A stub `defaults` prints a key's file for `read` (exit 1 if missing), and for `write` stores
    the value and appends the key to `defaults/written`.
  - A stub `pgrep` whose exit code comes from `$work/it/running`.

  It runs the rendered script with `HOME`, `PATH` and `ITERM2_APP` pointed there, and prints the output plus
  `exit=<code>`. Set up the all-OK state as:
  - every global at its repo value (`1`/`0`/`4`);
  - `Default Bookmark Guid` = `chezmoi-left-option-as-alt`;
  - a settings.json whose hook command is `"/Users/x/.config/iterm2/it2" handle-agent-hook`, plus an executable `it2`;
  - the child profile from `printf '' | bash "$iterm_modify"`.

  Checks:
  - all-OK state gives the four `OK:` lines, then `exit=0`, and `defaults/written` does not exist;
  - `DoubleClickPerformsSmartSelection` at `0` with iTerm2 running gives
    `NOTE: iTerm2 global settings updated: DoubleClickPerformsSmartSelection; quit and reopen iTerm2 for them to take effect`,
    and the stored value is `true`;
  - a missing `PasteTabToStringTabStopSize` is written and listed;
  - the Guid `246D2B5F` or an empty Guid gives the default-profile `NOTE:`;
  - settings.json without `iterm2/it2`, or no `it2` file, gives the integration `NOTE:`;
  - a child with `Font`, `Columns` and a trigger `iTermHighlightLineTrigger` gives the local-changes `NOTE:` with
    `Columns, Font, trigger iTermHighlightLineTrigger`;
  - a child that is not JSON gives no line 4, and `exit=0`;
  - no iTerm2 (`ITERM2_APP` missing) gives empty output;
  - non-darwin hosts render empty.

- [ ] **Step 2: Run** `bash tests/host-profiles.sh 2>&1 | tail -20`. Expected: FAIL lines for the new and renamed
  checks.

- [ ] **Step 3: Implement.**
  - Add `[iterm2_globals]` to `.chezmoidata/macos.toml`, one comment per key saying what it does.
  - `git mv` the script, keeping its darwin guard. Add `export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"` and the
    `ITERM2_APP` guard.
  - Define `ensure_global`, rendering its calls with
    `{{ range $k, $v := .iterm2_globals }}…{{ if kindIs "bool" $v }}-bool {{ $v }}{{ else }}-int {{ $v }}{{ end }}…{{ end }}`.
  - Then the three checks. The report's owned keys are `Name`, `Guid`, `Dynamic Profile Parent GUID`,
    `Option Key Sends`, `Rewritable` and `Triggers`. The owned trigger actions are `iTermEnterWorkgroupTrigger` and
    `iTermExitWorkgroupTrigger`.
  - Rewrite the header comment.

- [ ] **Step 4: Run** `bash tests/host-profiles.sh 2>&1 | tail -3`. Expected: `… passed, 0 failed`.

- [ ] **Step 5: Cheatsheet.**
  - The block gains the global settings (one line listing them), the four checks, and "what stays manual": install the
    Claude Code integration, set the default profile once, reopen iTerm2 after the first apply, Warp's Option setting.
  - The clipboard row drops the "chezmoi turns on" wording in favour of "a shared global setting".

- [ ] **Step 6: Final checks, then commit.**
  - `gitleaks detect --source . -v` is clean.
  - Search the changed files for the work organisation names (the controller has them; never write them here):
    nothing.
  - Commit `feat(iterm2): shared global settings, and checks for the default profile, Claude Code and local changes`.

### After the tasks (controller)

1. Whole-branch review.
2. Fast-forward main: `642da78` (CI fix), spec, plan, Task 1, Task 2.
3. Ask the user before pushing.
4. On each Mac: `chezmoi update` over SSH. Then the user reopens iTerm2; herdr sessions on works survive.
5. Verify on both Macs:
   - the after-script prints four `OK:` lines;
   - Help > GPU Renderer Availability shows GPU rendering on;
   - the slow-trigger warning is gone in herdr;
   - the user confirms both Macs look the same and that `claude` in a local tab opens the workgroup.
