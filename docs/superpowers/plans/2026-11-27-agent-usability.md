# Same Keys in Every Agent: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `chezmoi apply` gives every installed CLI coding agent (Claude Code, Copilot CLI, Cursor's agent, Codex, OpenCode) the same usability settings, vim keys and copy on select, on every machine, and puts them back after a manual change.

**Architecture:**
- One data file holds the two intents.
- One `modify_` script per agent translates them into that agent's own keys and passes everything else in the file through. JSON files go through a shared jq include; Codex's TOML goes through a small section-aware awk include.
- A `.chezmoiignore` rule skips agents that are neither set up nor installed.
- Claude's `editorMode` and `tui` move here from ai-tooling, so each key has one owner.

**Tech Stack:** chezmoi templates, bash 3.2-compatible scripts, jq, POSIX awk; `tests/host-profiles.sh`.

**Spec:** `~/ai-tooling/docs/superpowers/specs/2026-11-27-unified-agent-experience-design.md` (private `~/.cfg`), Part 1. Parts 2 (the apply runs ai-tooling) and 3 (capability baseline) get their own plans.

## Global Constraints

- Public repository: no work organisation names, emails or paths (AGENTS.md 3.3).
- Scripts run under bash 3.2 (macOS `/bin/bash`) and macOS `awk`.
  - No `mapfile`, no `${var,,}`, no gawk-only functions.
- A `modify_` script's stdout **is** the file.
  - It prints nothing else: no `+ command` echo, no warnings on stdout.
  - Missing input becomes the minimal file.
  - Input it cannot parse, or a missing `jq`, passes through unchanged.
  - A second run changes nothing.
- Keep the target's existing modes:
  - folders `.claude`, `.cursor`, `.codex` and `.config/opencode` stay 755, so their sources use `dot_` (not `private_dot_`);
  - `.copilot` is 700 (`private_dot_copilot`, already in place);
  - the files `~/.claude/settings.json`, `~/.codex/config.toml` and `~/.config/opencode/cli.json` are 600 (`modify_private_…`);
  - `~/.cursor/cli-config.json` and `~/.copilot/settings.json` are 644 (`modify_…`).

  Spiked on 2026-11-27: `dot_x/modify_private_f` keeps a 755 folder and a 600 file, with an empty diff.
- Intents, all `true`: `vim_keys`, `copy_on_select`. A `false` writes the agent's opposite value; it does not leave the key alone.
- `docs/CHEATSHEET.md` changes in the same commit as the code (AGENTS.md section 2).
- Each commit passes `bash tests/host-profiles.sh` (0 failed) and `gitleaks detect --source . -v` (no leaks).
- Conventional commits as `Simar Singh <simarpaulsingh@gmail.com>`, with no agent trailers and no push.
- Work in a worktree under `~/.local/share/chezmoi-worktrees/`, never inside the source (AGENTS.md section 5).

## Review Focus

1. **A settings file the agent wrote with comments or trailing commas** (OpenCode reads JSONC). The script must leave it byte-for-byte unchanged, not empty it. Every JSON task has a "not JSON passes through" test.
2. **Codex `config.toml` with subtables after `[tui]`** (`[tui.notifications]`, `[hooks.state."…"]`), with `[tui]` missing, or with the keys already set to other values. Keys go into `[tui]` only, exactly once. Task 4 tests all four shapes.
3. **A host without the agent** (a Mac without Codex, CI): nothing is managed, so no folder is created. Task 1 tests presence true and false.
4. **The agent rewrites the file in its own key order between applies.** The next apply changes only the two intents, and a second apply changes nothing. Each task has an idempotence test.
5. **ai-tooling's Claude deploy running after the apply** must not revert `editorMode` or `tui`, and must not delete them either. Task 5 checks that the shared file no longer has these keys and that the retired list doesn't name them.

---

### Task 1: Intents, the presence rule and the ignore entries

**Files:**
- Create: `.chezmoidata/agents.toml`
- Create: `.chezmoitemplates/agent-present`
- Modify: `.chezmoiignore` (append one block per agent)
- Modify: `tests/host-profiles.sh` (`host_data`, and new checks after the Copilot block, around line 634)

**Interfaces:**
- Produces: data `.agent_usability.vim_keys` and `.agent_usability.copy_on_select` (bool).
- Produces: template `agent-present`, called as `includeTemplate "agent-present" (dict "data" . "dir" ".codex" "cmd" "codex")`. It renders `yes` when the agent is present and an empty string otherwise.
  - Present means: `.data.agents_present` when that key exists (tests only), else `stat (joinPath .data.chezmoi.destDir .dir)` or `lookPath .cmd`.
- Produces: data key `agents_present` (bool, tests only), which overrides the detection.

- [ ] **Step 1: Write the failing tests.** In `host_data`, add `"agents_present":true` to every host's JSON.

  After the existing Copilot block, add:
  ```bash
  agents=".copilot/settings.json"   # Tasks 2-4 add each agent's target as its script lands
  for host in $hosts; do for t in $agents; do check "$host manages $t where the agent is present" yes "$(manages "$host" "$t")"; done; done
  absent="$(chezmoi --override-data "$(host_data omarchy | jq -c '.agents_present = false')" managed --include=all)"
  for t in .claude .copilot .cursor .codex .config/opencode; do check "no agent: $t is left alone" 0 "$(printf '%s\n' "$absent" | grep -cE "^${t//./\\.}(/|$)")"; done
  check "usability intents are vim keys and copy on select" "true true" "$(chezmoi --override-data "$(host_data omarchy)" execute-template '{{ .agent_usability.vim_keys }} {{ .agent_usability.copy_on_select }}')"
  ```

- [ ] **Step 2: Run** `bash tests/host-profiles.sh 2>&1 | tail -3`. Expected: FAIL. The intents check fails, and only the existing Copilot paths are managed.

- [ ] **Step 3: Implement.**
  - `agents.toml`: an `[agent_usability]` table with the two intents and a comment pointing to the cheatsheet ("Same Keys in Every Agent").
  - `agent-present`, as specified under Interfaces.
  - `.chezmoiignore`: one block per agent, each ignoring `<dir>` and `<dir>/**` unless `agent-present` renders `yes`. The pairs are `.claude`/`claude`, `.copilot`/`copilot`, `.cursor`/`cursor-agent`, `.codex`/`codex` and `.config/opencode`/`opencode`.

  The script files arrive in later tasks, so `$agents` starts with Copilot's target alone. The "no agent" check already covers all five folders: an ignore rule with nothing under it ignores nothing.

- [ ] **Step 4: Run** the suite. Expected: `0 failed`.

- [ ] **Step 5: Commit:** `feat(agents): one list of usability intents, applied only where an agent is set up`.

### Task 2: Shared JSON include, Copilot and Claude

**Files:**
- Create: `.chezmoitemplates/modify-json.sh`
- Rename: `private_dot_copilot/modify_settings.json` → `private_dot_copilot/modify_settings.json.tmpl`
- Create: `dot_claude/modify_private_settings.json.tmpl`
- Modify: `run_after_99_assert_requirements.sh.tmpl` (next to the Copilot `reload_hint`, around line 386): add Claude's.
- Modify: `docs/CHEATSHEET.md`: a new section, "Same Keys in Every Agent", after "Copy and Paste".
  - One row per agent; Antigravity's row reads "not available: its CLI settings have neither key (2026-11-27)".
  - Update the Copilot sentence in the copy paragraph to point to the new section.
- Modify: `AGENTS.md` 4.2: the `modify_` list names the agent scripts and their keys.
- Test: `tests/host-profiles.sh`

**Interfaces:**
- Consumes: `.agent_usability.*` and the `agent-present` rule from Task 1.
- Produces: `.chezmoitemplates/modify-json.sh`. The calling template sets `filter` (a jq program) and `args` (a bash array of `--argjson name value` pairs), then does `{{ template "modify-json.sh" . }}`.
  - The include reads stdin and turns blank input into `{}`.
  - It runs `jq --indent 2 "${args[@]}" "$filter"` and prints the result; if `jq` is missing or fails, it prints the input unchanged.
  - Its body is today's Copilot script, generalised.
- Produces: the jq arguments `$vim` and `$copy` (bool) in every JSON agent script.

- [ ] **Step 1: Write the failing tests.** Replace the Copilot behaviour checks; add Claude's. Render each script with `render omarchy <file>` into `$work`, then pipe input to `bash`:
  - Copilot `{"a":1}` gives `{"a":1,"editorMode":"vim","copyOnSelect":true}`.
  - Claude `{"model":"x"}` gives `{"model":"x","editorMode":"vim","copyOnSelect":true,"tui":"fullscreen"}`.
  - Both: blank input gives just the keys; `not json` passes through unchanged; a second run equals the first.
  - With `agent_usability` overridden to `false`: Copilot writes `"editorMode":"normal","copyOnSelect":false`, Claude writes `"editorMode":"normal","copyOnSelect":false`, and `tui` stays `"fullscreen"`.
  - Add `.claude/settings.json` to `$agents`.

- [ ] **Step 2: Run** the suite. Expected: FAIL on the new Claude and Copilot checks.

- [ ] **Step 3: Implement.** The jq filters:
  - Copilot: `.editorMode = (if $vim then "vim" else "normal" end) | .copyOnSelect = $copy`
  - Claude: `.editorMode = (if $vim then "vim" else "normal" end) | .copyOnSelect = $copy | .tui = "fullscreen"`

  The `reload_hint` message for Claude: `Claude Code's settings changed: restart open Claude Code sessions to pick them up`. The process is `claude`.

- [ ] **Step 4: Run** the suite, `shellcheck` on each rendered script, and `zsh -c 'source dot_aliases && cheat | grep -c "Same Keys in Every Agent"'`. Expected: `0 failed`, shellcheck silent, and `cheat` prints `1` once the cheatsheet is applied. Before applying, check the rendered `dot_cheatsheet.md.tmpl` instead.

- [ ] **Step 5: Commit:** `feat(agents): vim keys and copy on select in Claude Code and Copilot CLI`.

### Task 3: Cursor's agent and OpenCode

**Files:**
- Create: `dot_cursor/modify_cli-config.json.tmpl`
- Create: `dot_config/opencode/modify_private_cli.json.tmpl`
- Modify: `run_after_99_assert_requirements.sh.tmpl`: `reload_hint` for both, with processes `cursor-agent` and `opencode`.
- Modify: `docs/CHEATSHEET.md` ("Same Keys in Every Agent" rows)
- Test: `tests/host-profiles.sh`

**Interfaces:**
- Consumes: `modify-json.sh` with `filter` and `args` (Task 2).

- [ ] **Step 1: Write the failing tests.**
  - Cursor `{"editor":{"vimMode":false},"display":{"mode":"zen"}}` gives `{"editor":{"vimMode":true},"display":{"mode":"zen"}}`.
  - OpenCode `{"theme":{"name":"system"}}` gives `{"theme":{"name":"system"},"terminal":{"copy":"select"}}`.
  - With the intents `false`: Cursor `vimMode` is `false`, and OpenCode's `terminal.copy` is `"manual"`.
  - OpenCode input with a `//` comment passes through unchanged.
  - Blank input, `not json` and the second run behave as in Task 2.
  - Add both targets to `$agents`.

- [ ] **Step 2: Run** the suite. Expected: FAIL on the new checks.

- [ ] **Step 3: Implement.** The filters:
  - Cursor: `.editor.vimMode = $vim`. Cursor's agent has no copy-on-select or mouse setting, so the cheatsheet row says "not available".
  - OpenCode: `.terminal.copy = (if $copy then "select" else "manual" end)`. OpenCode 2.x has no vim mode, so the row says "not available".

  These come from OpenCode's own migration code (`packages/cli/src/config/migrate.ts`, which writes `terminal.copy` = `select`|`manual` into `cli.json`).

- [ ] **Step 4: Run** the suite and shellcheck. Expected: `0 failed`.

- [ ] **Step 5: Commit:** `feat(agents): vim keys in Cursor's agent, copy on select in OpenCode`.

### Task 4: Codex (TOML)

**Files:**
- Create: `.chezmoitemplates/toml-section-set.awk.sh`
- Create: `dot_codex/modify_private_config.toml.tmpl`
- Modify: `run_after_99_assert_requirements.sh.tmpl`: `reload_hint` for Codex, process `codex`.
- Modify: `docs/CHEATSHEET.md` (the Codex row)
- Test: `tests/host-profiles.sh`

**Interfaces:**
- Produces: `toml-section-set.awk.sh`, included after the caller sets `SECTION` (for example `tui`) and `BLOCK` (newline-separated `key = value` lines). Values reach awk through the environment, not `-v`, as `kv-settings.awk.sh` does for macOS awk.
  - It removes every line inside `[SECTION]` (up to the next line starting with `[`) whose key matches a `BLOCK` key.
  - It inserts `BLOCK` directly after the `[SECTION]` header.
  - When the section is missing, it appends a blank line, `[SECTION]` and `BLOCK` at the end.
  - Blank input gives `[SECTION]` plus `BLOCK`.
  - A line `[SECTION.sub]` is a different section.

- [ ] **Step 1: Write the failing tests.** The keys are `vim_mode_default = true` and `copy_on_select = "always"`, both in `[tui]`, as in Codex's `codex-rs/config/src/types.rs`; `copy_on_select` is a lowercase enum, `auto|always|never`.
  - This machine's shape, `[features]\nhooks = true\n\n[tui]\nscreen_reader_detection_done = true\n\n[hooks.state]\n`, gives a `[tui]` that holds both keys plus `screen_reader_detection_done`, with `[features]` and `[hooks.state]` unchanged.
  - No `[tui]` gives a `[tui]` block appended at the end.
  - `[tui]\ncopy_on_select = "never"\n[tui.notifications]\nx = 1\n` gives `"always"` exactly once, under `[tui]` and not under `[tui.notifications]`.
  - Blank input gives `[tui]` and the two keys.
  - With the intents `false`: `vim_mode_default = false` and `copy_on_select = "never"`.
  - A second run equals the first.
  - Add `.codex/config.toml` to `$agents`.

- [ ] **Step 2: Run** the suite. Expected: FAIL on the new checks.

- [ ] **Step 3: Implement** the awk include, and the template that sets `SECTION=tui` and `BLOCK` from the intents.

- [ ] **Step 4: Run** the suite, shellcheck, and `printf '%s' "$out" | python3 -c 'import sys,tomllib; tomllib.loads(sys.stdin.read())'` on each test output, which proves the output still parses as TOML. Expected: `0 failed`, no parse errors.

- [ ] **Step 5: Commit:** `feat(agents): vim keys and copy on select in Codex`.

### Task 5: ai-tooling hands Claude's usability keys to chezmoi

**Files (private `~/.cfg`, through `config`):**
- Modify: `~/ai-tooling/claude/settings.shared.json` (delete `editorMode` and `tui`)
- Modify: `~/ai-tooling/docs/AI_TOOLING.md`: one line saying chezmoi owns Claude's `editorMode`, `copyOnSelect` and `tui`.
- Test: `~/ai-tooling/scripts/tests/` (the existing suite)

- [ ] **Step 1: Write the failing test.** Add `scripts/tests/test_usability_keys_owned_by_chezmoi.sh`. It asserts that `jq 'has("editorMode") or has("tui") or has("copyOnSelect")' claude/settings.shared.json` prints `false`, and that `claude/settings.retired.json` does not name those keys.
- [ ] **Step 2: Run** `make -C ~/ai-tooling test`. Expected: the new test FAILS.
- [ ] **Step 3: Implement.** Delete the two keys from `settings.shared.json`. Do not add them to `settings.retired.json`, or the deploy would delete chezmoi's values.
- [ ] **Step 4: Run** `make -C ~/ai-tooling test`. Expected: all pass.

  Then run `make -C ~/ai-tooling claude-deploy` followed by `jq '{editorMode, tui}' ~/.claude/settings.json`. Expected: `"vim"` and `"fullscreen"`, still there.
- [ ] **Step 5: Commit:** `config add ai-tooling/claude/settings.shared.json ai-tooling/docs/AI_TOOLING.md ai-tooling/scripts/tests/test_usability_keys_owned_by_chezmoi.sh && config commit -m "refactor(claude): usability keys move to chezmoi"`.

### Task 6: Roll out and check on this machine

- [ ] **Step 1:** Fast-forward `main` onto the branch: `git merge --ff-only`, after confirming with `git merge-base --is-ancestor main <branch>`.
- [ ] **Step 2:** Run `chezmoi diff`. Expected: changes only in the five agent files and `.cheatsheet.md`, with no `old mode`/`new mode` lines.
- [ ] **Step 3:** Run `chezmoi apply`, then `chezmoi diff | wc -l`. Expected: `0`.
- [ ] **Step 4:** Pre-seeded files survive a first launch. This is the design's untested claim.
  - For each agent, start it once in a temporary `HOME` holding only the file this repository renders.
  - Use a scratch Herdr tab: `herdr tab create`, then `herdr pane run`, then quit the agent.
  - Diff the file afterwards. Expected: both intents still set.

  Record each result in the cheatsheet row. Where an agent overwrites the file, the row says that its settings arrive on the second apply after its first start.
- [ ] **Step 5:** A drag in Copilot and in Codex copies, and `Esc` then `h`/`l` move the cursor in each agent's prompt. Expected: both work. Run this in a fresh Herdr pane after the user restarts Herdr.
- [ ] **Step 6:** Remove the worktree and branch; report what was verified and what wasn't.
