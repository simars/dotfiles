# chezmoi apply Runs ai-tooling's Deploy: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** On any machine where the private `~/ai-tooling` exists, every `chezmoi apply` also runs ai-tooling's deploy, so `make setup` is no longer a step to remember. The deploy covers the Claude config links, Cursor artifacts, skill links, the generated agent instructions, and upgrading outdated Herdr agent hooks.

**Architecture:**
- ai-tooling gets one non-interactive entry point, `make deploy` (`scripts/deploy.sh`). It runs the four existing deploy scripts and then upgrades outdated Herdr integrations.
  - Each step prints its command (`+ …`) and stays quiet unless it warns or fails.
  - A failure does not stop the other steps.
- chezmoi gets `run_after_98_ai_tooling.sh.tmpl`, which runs that target when `~/ai-tooling/Makefile` exists. It never prompts and never fails the apply; a failure becomes a line in the apply's to-do list.
- `make setup` keeps the one-time work (dependency checks, the Copilot CLI install, the `gh` hint) and calls `scripts/deploy.sh` for the rest.
- `~/install.sh` is unchanged. It runs `make setup` only when ai-tooling is not linked yet, and a second deploy in the same install is idempotent and takes about a second, so running it twice costs nothing.

**Tech Stack:** bash (bash 3.2-compatible in the chezmoi script), make, the existing ai-tooling deploy scripts, the `herdr` CLI; tests in ai-tooling's `scripts/tests/` and chezmoi's `tests/host-profiles.sh`.

**Spec:** `~/ai-tooling/docs/superpowers/specs/2026-11-27-unified-agent-experience-design.md` (private `~/.cfg`), Part 2. Part 3 (the capability baseline) gets its own plan and will add a step to `scripts/deploy.sh`.

## Global Constraints

- **Two repositories.**
  - The chezmoi repo is public: no work organisation names, emails or paths (its AGENTS.md 3.3). Work in a worktree under `~/.local/share/chezmoi-worktrees/`.
  - ai-tooling lives in the private bare repo `~/.cfg`: edit `~/ai-tooling` in place and commit with `config` (`/usr/bin/git --git-dir=$HOME/.cfg/ --work-tree=$HOME`), as `Simar Singh <simarpaulsingh@gmail.com>`. Never use plain `git` in `$HOME`.
- **No push, in either repository.** Conventional commits, no agent trailers.
- **Print each command before it runs:** `+ <command>`, shell-quoted, the real command as executed (the user's rule). Each `scripts/deploy.sh` step's own output is hidden when it succeeds without warnings, so a step with nothing to do prints exactly one line, its `+` line. `--dry-run` prints the `+` lines and runs nothing.
- **The deploy never prompts, needs no sudo and no network.**
  - The bridge runs it with stdin from `/dev/null`.
  - It never runs `npm`, `gh` or `make mcp-*`, and never prints MCP setup advice. ai-tooling's MCP fan-out is retired: say nothing about `make mcp-setup` anywhere these scripts print.
- **The bridge never fails `chezmoi apply`:** it always exits 0, and a failed deploy adds one `todo` line (from `.chezmoitemplates/after-apply.sh`).
- **Herdr:** upgrade only integrations `herdr integration status` reports as `outdated`. Never install one that is `not installed`. Do nothing when `herdr` is not on `PATH`.
- **chezmoi docs:** `docs/CHEATSHEET.md` changes in the same commit as chezmoi code (its AGENTS.md section 2). Each chezmoi commit passes `bash tests/host-profiles.sh` (0 failed) and `gitleaks detect --source . -v`.
- **ai-tooling tests:** each ai-tooling commit passes `make -C ~/ai-tooling test` (`ALL PASS`).

## Review Focus

1. **`~/ai-tooling` present but older**, with a Makefile that has no `deploy` target (a Mac before `~/.cfg` is pulled). The apply finishes, and the to-do says to pull `~/.cfg` (`config pull --rebase origin main`). Task 3 tests it.
2. **No terminal** (an apply over SSH, or run by an agent). Nothing waits for input: a deploy step that reads stdin gets end-of-file at once. Task 3 tests it with a stub that runs `read`.
3. **One step fails** (Herdr's server is down, or one deploy script errors). The other steps still run, the failure's output is shown, and the summary names the step. Tasks 1 and 2 test it.
4. **The apply runs from inside Claude Code while the deploy merges `~/.claude/settings.json`.** chezmoi's keys (`editorMode`, `tui`) survive, and a second apply shows no diff. Task 4 checks it.
5. **A second apply with nothing to do** prints only the `+` lines: the bridge's line, then one line per deploy step. Task 1 tests the deploy side; Task 4 checks it live.

---

### Task 1: `make deploy` in ai-tooling

**Files:**
- Create: `~/ai-tooling/scripts/deploy.sh`
- Modify: `~/ai-tooling/Makefile` (add `deploy` to `.PHONY` and as a target, next to `setup`)
- Modify: `~/ai-tooling/scripts/setup.sh`:
  - replace its four direct deploy calls with `"$AI_HOME/scripts/deploy.sh"`;
  - drop the MCP lines in its header comment and final summary;
  - keep `jq` check, Copilot install, `gh` hint.
- Modify: `~/ai-tooling/docs/AI_TOOLING.md`: `make deploy` in the Make UX list; one line saying `chezmoi apply` runs it.
- Test: create `~/ai-tooling/scripts/tests/test_deploy.sh` (picked up by `run_all.sh`).

**Interfaces:**
- Produces: `scripts/deploy.sh [--dry-run] [--verbose]`.
  - It runs, in order: `$AI_HOME/claude/deploy.sh`, `$AI_HOME/cursor/deploy.sh`, `$AI_HOME/skills/deploy.sh`, `$AI_HOME/agents/deploy.sh`.
  - Before each step it prints `+ <command>` (`printf '+ %q'`).
  - It captures the step's output, and prints it only when the step exits non-zero, when its output contains `⚠`, or with `--verbose`.
  - After all steps:
    - all passed: exit 0, nothing more printed;
    - a step failed: print `ai-tooling deploy: failed: <names>` (space-separated, step names `claude cursor skills agents`) and exit 1.
- Produces: the step runner `deploy_step NAME CMD...`, which Task 2 and Part 3 reuse.
- Produces: `make deploy`, which runs `scripts/deploy.sh $(ARGS)`.

- [ ] **Step 1: Write the failing test** `scripts/tests/test_deploy.sh`. It is hermetic, in the style of `test_agents.sh`: `HOME` is a mktemp dir, and `unset CODEX_HOME COPILOT_HOME XDG_CONFIG_HOME OPENCODE_CONFIG_DIR`. Cases:
  - **The real repository** (`AI_HOME="$ROOT"`):
    - the first run exits 0;
    - the second run's whole output is exactly four lines, each starting `+ ` and ending in `claude/deploy.sh`, `cursor/deploy.sh`, `skills/deploy.sh`, `agents/deploy.sh`, in that order;
    - `$HOME/.claude/CLAUDE.md` is a link to `$ROOT/claude/CLAUDE.md`.
  - **`--dry-run` with a stub `AI_HOME`** (four stub `*/deploy.sh` scripts that each touch `$STUB_LOG/<name>`): it prints the four `+` lines, and no marker file exists.
  - **A failing step** (the stub `cursor/deploy.sh` prints `boom` and exits 3): the exit code is 1, the output contains `boom`, the last line is `ai-tooling deploy: failed: cursor`, and the markers for `claude`, `skills` and `agents` exist.
  - **A warning** (the stub `skills/deploy.sh` prints `⚠ check me` and exits 0): the exit code is 0 and the output contains `⚠ check me`.
  - **The real `scripts/setup.sh` text** contains no `mcp-setup` (`grep -c mcp-setup` gives `0`).
- [ ] **Step 2: Run** `bash ~/ai-tooling/scripts/tests/test_deploy.sh`. Expected: FAIL (`scripts/deploy.sh` is missing).
- [ ] **Step 3: Implement** `scripts/deploy.sh` per the Interfaces, then the Makefile target, then the `setup.sh` changes.
  - Unknown options exit 64 with a usage line.
  - Source `scripts/lib/common.sh` only if needed; the steps already do their own setup.
- [ ] **Step 4: Run** `make -C ~/ai-tooling test`. Expected: `ALL PASS`. Then run `make -C ~/ai-tooling deploy` twice on this machine. Expected: the second run prints exactly four `+` lines.
- [ ] **Step 5: Commit** with `config add` on the changed and new files, then `config commit -m "feat: make deploy, the non-interactive part of make setup"`.

### Task 2: Upgrade outdated Herdr agent hooks in `make deploy`

**Files:**
- Modify: `~/ai-tooling/scripts/deploy.sh` (a fifth step, after `agents`)
- Modify: `~/ai-tooling/docs/AI_TOOLING.md` (one line)
- Test: `~/ai-tooling/scripts/tests/test_deploy.sh`

**Interfaces:**
- Consumes: `deploy_step NAME CMD...` (Task 1).
- Produces: step names `herdr:<target>`. When `herdr` is on `PATH`, the step:
  - runs `herdr integration status` (printing `+ herdr integration status`);
  - takes each line matching `^[a-z0-9-]+: outdated` (the target is the text before `:`);
  - runs `deploy_step "herdr:<target>" herdr integration install <target>` for each.

  Do not parse `--outdated-only`: its output is one prose sentence, not a list (checked on 2026-11-27 with herdr 0.9.5).

- [ ] **Step 1: Write the failing test.** Put a stub `herdr` first on `PATH`. For `integration status` it prints these lines:
  ```
  pi: current (v9) (/x)
  claude: outdated (v10 < v11) (/x)
  devin: not installed (/x)
  cursor: outdated (v1 < v2) (/x)
  ```
  It appends each `integration install <t>` call to a log, and exits 1 when `<t>` is `cursor`. With a stub `AI_HOME` (Task 1's stubs):
  - the log is exactly `claude` then `cursor`;
  - the output has `+ herdr integration install claude` and `+ herdr integration install cursor`;
  - the last line is `ai-tooling deploy: failed: herdr:cursor`;
  - the exit code is 1;
  - `devin` is never installed.

  With a stub reporting nothing outdated: the only herdr output is `+ herdr integration status`.

  Also update Task 1's "second run is exactly four lines" case: run it with `PATH` not containing any `herdr` (a real one may be installed on the test machine), so it stays four lines.

  Without `herdr` on `PATH` (`PATH` without the stub, and `command -v herdr` false): the output has no `herdr` line and the exit code is 0.
- [ ] **Step 2: Run** `bash ~/ai-tooling/scripts/tests/test_deploy.sh`. Expected: FAIL on the herdr cases.
- [ ] **Step 3: Implement** the step.
- [ ] **Step 4: Run** `make -C ~/ai-tooling test`. Expected: `ALL PASS`.
- [ ] **Step 5: Commit** with `config commit -m "feat: make deploy upgrades outdated Herdr agent hooks"`.

### Task 3: chezmoi runs the deploy on every apply

**Files (chezmoi worktree):**
- Create: `run_after_98_ai_tooling.sh.tmpl`
- Modify: `run_after_99_assert_requirements.sh.tmpl` (the `ai-tooling is not set up here` note, around line 243)
- Modify: `docs/CHEATSHEET.md`:
  - the "After every apply" bullet says the apply runs `make -C ~/ai-tooling deploy` where `~/ai-tooling` exists;
  - every `make setup` mention that this replaces now says that the apply handles it.
- Modify: `docs/NEW_MACHINE.md` (line ~43 and ~87: ai-tooling is deployed by `chezmoi apply` once `~/.cfg` is checked out; `make setup` is still how the Copilot CLI install and the `gh` hint run).
- Modify: `AGENTS.md` 3.5 (one sentence: `run_after_98` runs ai-tooling's deploy and turns its failure into a `todo`).
- Test: `tests/host-profiles.sh`

**Interfaces:**
- Consumes: `make -C ~/ai-tooling deploy` (Task 1). It exits non-zero on failure, and its last line is `ai-tooling deploy: failed: …`.
- Consumes: `todo MESSAGE` from `.chezmoitemplates/after-apply.sh`. It appends to `${CHEZMOI_CACHE_DIR:-…}/after-apply.$PPID`.
- Produces: `run_after_98_ai_tooling.sh` on every host. It is not OS-specific and runs under bash 3.2.
  - It starts `set -u` and includes `{{ template "after-apply.sh" . }}`.
  - When `$HOME/ai-tooling/Makefile` is missing, it exits 0 silently.
  - When `make` is not on `PATH`, it adds `todo "ai-tooling was not deployed: make is missing (Xcode command line tools on a Mac)"` and exits 0.
  - Otherwise it prints `+ make -C <dir> deploy`, then runs `make -C "$dir" --no-print-directory deploy < /dev/null`, letting its output through.
  - On a non-zero exit, it adds `todo "ai-tooling's deploy failed (see above): run make -C ~/ai-tooling deploy. If it says there is no rule for deploy, pull ~/.cfg first (config pull --rebase origin main)"`.
  - It always exits 0.

- [ ] **Step 1: Write the failing tests** in `tests/host-profiles.sh`.
  - `run_after_98_ai_tooling.sh` is managed on every host.
  - Render it for omarchy and for darwin; each render passes `bash -n`.
  - Behaviour runs use the omarchy render in a scratch `HOME`, with `CHEZMOI_CACHE_DIR` pointing at a scratch dir, run as `bash script`. Read the to-do file `"$CHEZMOI_CACHE_DIR"/after-apply.*` afterwards. Cases:
    - **(a) No `~/ai-tooling`:** empty output, exit 0, no to-do file.
    - **(b) A stub `~/ai-tooling/Makefile`** whose `deploy` target runs `@read -r x || true; echo deployed` (it must not wait): the output's first line is `+ make -C $HOME/ai-tooling deploy` (shell-quoted form), the output contains `deployed`, exit 0, no to-do.
    - **(c) The stub's `deploy` exits 1:** exit 0, and the to-do file holds the line starting `ai-tooling's deploy failed`.
    - **(d) A Makefile with no `deploy` target:** exit 0, and the same to-do line, which names `config pull`.
    - **(e) `make` missing** (`PATH` with only the shell's own tools, no `make`): exit 0, and the to-do starts `ai-tooling was not deployed: make is missing`.
  - Run the cases only when `make` is on the test machine's `PATH`. Otherwise print a `SKIP` line, as the suite does elsewhere.
- [ ] **Step 2: Run** `bash tests/host-profiles.sh 2>&1 | tail -3`. Expected: FAIL on the new checks.
- [ ] **Step 3: Implement** the script per the Interfaces. In `run_after_99`, change the existing note's fix from `cd ~/ai-tooling && make setup` to `make -C ~/ai-tooling deploy (the apply runs it; see its output above)`.
- [ ] **Step 4: Run** the suite and `shellcheck` on both renders. Expected: `0 failed`, shellcheck clean. Also run `gitleaks detect --source . -v`.
- [ ] **Step 5: Commit:** `feat: chezmoi apply runs ai-tooling's deploy where ~/ai-tooling exists`.

### Task 4: Roll out and check on this machine (controller)

- [ ] **Step 1:** Fast-forward the chezmoi `main` onto the branch: `git merge --ff-only`, after confirming with `git merge-base --is-ancestor`.
- [ ] **Step 2:** Run `chezmoi apply`. Expected:
  - the apply's output has `+ make -C /home/simars/ai-tooling deploy`, then the deploy's `+` lines, including `+ herdr integration install claude`, `codex`, `copilot`, `opencode` and `cursor`;
  - the to-do list has no ai-tooling line.
- [ ] **Step 3:** Run `herdr integration status | grep -c ': outdated'`. Expected: `0`.
- [ ] **Step 4:** Run `chezmoi apply` again. Expected:
  - the bridge section shows only `+` lines (one for make, four for the deploy steps, one for `herdr integration status`);
  - `chezmoi diff | wc -l` gives `0`;
  - `jq '{editorMode, tui}' ~/.claude/settings.json` gives `"vim"` and `"fullscreen"`.
- [ ] **Step 5:** Remove the worktree and branch. Report what was verified, including whether the Herdr hook upgrade changed `~/.claude/settings.json` or `~/.copilot/settings.json`, and whether the next apply then rewrote them.
