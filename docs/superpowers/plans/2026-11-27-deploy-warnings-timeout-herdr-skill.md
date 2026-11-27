# Deploy Warnings, a Herdr Time Limit and Herdr's Skill: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Three follow-ups to "chezmoi apply runs ai-tooling's deploy":
1. A deploy `⚠` warning reaches the apply's to-do list.
2. A hung Herdr command can no longer hang the apply.
3. Every agent gets Herdr's official skill, from `herdr --skill`, on every machine with Herdr.

**Architecture:**
- **Warnings and the time limit live in `~/ai-tooling/scripts/deploy.sh`.**
  - The deploy keeps exit 0 for warnings, because make turns any recipe failure into exit 2 and would hide the difference.
  - It writes its outcome (`ok`, `warnings: <steps>`, `failed: <steps>`) to the file named by `AI_DEPLOY_STATUS_FILE` when that variable is set.
  - chezmoi's `run_after_98_ai_tooling.sh.tmpl` sets the variable and adds the matching to-do.
- **Herdr's skill is a new deploy step, run before the `skills` step.**
  - It renders `herdr --skill` into `~/.agents/skills/herdr/SKILL.md` only when the text changed.
  - The existing skills step then links it into Claude and Antigravity.
  - Codex, Copilot CLI and Cursor's agent read `~/.agents/skills` directly. OpenCode does too; it is out of scope but harmless.
  - chezmoi's `dot_agents/skills` has no `exact_` prefix, so it leaves the folder alone (checked: `chezmoi unmanaged ~/.agents/skills` lists the other skills).

**Tech Stack:** bash, make, the `herdr` CLI (0.9.5, which has `--skill`); tests in `~/ai-tooling/scripts/tests/test_deploy.sh` and chezmoi `tests/host-profiles.sh`.

**Spec:** `~/ai-tooling/docs/superpowers/specs/2026-11-27-unified-agent-experience-design.md`, Part 2, plus the user's request of 2026-11-27: "official herdr skills installed in every agent (OpenCode ignored)". Deferred items from the Part 2 final review are M7 (warnings never reach the to-do list) and M8 (no time limit on Herdr).

## Global Constraints

- **The chezmoi repository is public:** no work organisation names. Use a worktree under `~/.local/share/chezmoi-worktrees/`. Cheatsheet changes go in the same commit as code. `bash tests/host-profiles.sh` must show 0 failed (996 passed at 23f96e5). gitleaks must be clean.
- **ai-tooling** is `~/ai-tooling` in the bare repo `~/.cfg`. Commit with `/usr/bin/git --git-dir=$HOME/.cfg/ --work-tree=$HOME` from `$HOME`, as `Simar Singh <simarpaulsingh@gmail.com>`, and never with plain git. `make -C ~/ai-tooling test` must print `ALL PASS`.
- **Commits:** no push, conventional commits, no agent trailers.
- **Print each command before it runs:** the printed `+` line is the real command, with its redirects and any time-limit wrapper. A step with nothing to do prints one line.
- **The apply never hangs, prompts or fails:** the bridge always exits 0.
- **Never run real side effects in tests:** no real `herdr integration install`, no real `make deploy` (use `--dry-run` or a scratch `HOME`), no `chezmoi apply`.

## Review Focus

1. **A one-time warning** (for example "backed up to .bak") adds a to-do once, and the next apply is clean. Task 1 tests a second run.
2. **No timeout tool on a Mac** (no `timeout` or `gtimeout`): the perl fallback limits the time. Task 2 tests it with `timeout` and `gtimeout` hidden.
3. **A `herdr --skill` that fails or prints nothing** must never leave an empty or truncated `SKILL.md`, and an existing good copy stays. Task 3 tests it.
4. **Herdr upgraded to a new version:** the next deploy rewrites the skill once, and the run after that prints one unchanged line. Task 3 tests it.
5. **Herdr removed from a machine:** the generated skill is removed, but only if ai-tooling generated it, never a hand-made `herdr` skill. Task 3 tests it.

---

### Task 1: Deploy warnings reach the to-do list

**Files:**
- Modify: `~/ai-tooling/scripts/deploy.sh`
- Modify: `~/ai-tooling/docs/AI_TOOLING.md` (one line)
- Modify (chezmoi): `run_after_98_ai_tooling.sh.tmpl`, `docs/CHEATSHEET.md` (the after-apply bullet), and `AGENTS.md` 3.5 if its run_after_98 sentence needs it
- Test: `~/ai-tooling/scripts/tests/test_deploy.sh`, chezmoi `tests/host-profiles.sh`

**Interfaces:**
- Produces, in `deploy.sh`: the names of steps that succeeded but printed `⚠` go into `WARNED`. After all steps:
  - if any step failed: the existing `ai-tooling deploy: failed: <names>` line, exit 1;
  - else if any warned: print `ai-tooling deploy: warnings: <names>` (stderr) and exit 0;
  - when `AI_DEPLOY_STATUS_FILE` is set, write exactly one line to it: `ok`, `warnings: <names>`, or `failed: <names>`;
  - under `--dry-run`, write nothing to the status file.
- Produces, in `run_after_98`:
  - it creates the status file with `mktemp "${TMPDIR:-/tmp}/ai-tooling-deploy.XXXXXX"`, removes it on exit, and runs and prints `AI_DEPLOY_STATUS_FILE=<%q path> make -C <%q dir> --no-print-directory deploy ARGS= < /dev/null`;
  - when make exits 0 and the status file starts with `warnings:`, it adds `todo "ai-tooling's deploy warned (see the ⚠ lines above): fix what they name, then run make -C ~/ai-tooling deploy"`;
  - when make fails, it adds the existing failure to-do. A missing or empty status file with exit 0 is treated as `ok`.

- [ ] **Step 1: Write the failing tests.**
  - **ai-tooling** (stub `AI_HOME`): the stub `skills/deploy.sh` prints `  ⚠ check me` and exits 0. Assert:
    - exit 0;
    - the last line is `ai-tooling deploy: warnings: skills`;
    - with `AI_DEPLOY_STATUS_FILE` set, the file holds exactly `warnings: skills`.

    Also: all clean gives `ok`; a failure plus a warning gives `failed: …` and exit 1; `--dry-run` leaves the status file untouched.
  - **chezmoi:** extend the bridge's existing stub-Makefile tests. A stub `deploy` target writes `warnings: skills` to `$$AI_DEPLOY_STATUS_FILE` and exits 0. Assert:
    - the apply script exits 0;
    - the to-do file has exactly the warning line;
    - the printed `+` line starts `+ AI_DEPLOY_STATUS_FILE=`;
    - the status file is gone afterwards.

    A stub that writes `ok` adds no to-do.
- [ ] **Step 2: Run both suites.** Expected: FAIL on the new checks.
- [ ] **Step 3: Implement** per the Interfaces.
- [ ] **Step 4: Run both suites.** Expected: `ALL PASS`; chezmoi `0 failed`.
- [ ] **Step 5: Commit** one ai-tooling commit (`feat: make deploy reports warnings to its caller`) and one chezmoi commit (`feat: a deploy warning goes on the apply's to-do list`).

### Task 2: A time limit on Herdr commands

**Files:**
- Modify: `~/ai-tooling/scripts/deploy.sh`
- Test: `~/ai-tooling/scripts/tests/test_deploy.sh`

**Interfaces:**
- Produces: `with_timeout SECONDS CMD...`. It runs CMD under the first available of:
  - `timeout SECONDS`;
  - `gtimeout SECONDS`;
  - `perl -e 'alarm shift; exec @ARGV' SECONDS`.

  If none exists, it runs CMD as it is.
- Each Herdr step (status and every install) runs as `deploy_step <name> with_timeout "$HERDR_TIMEOUT" herdr …`. The time limit comes from `AI_DEPLOY_HERDR_TIMEOUT`, default `60`.
- The `+` line prints the real wrapped command, for example `+ timeout 60 herdr integration install claude`. Resolve the wrapper first, so the printed line is the command that runs.
- A timed-out step (exit 124 from timeout/gtimeout, or 142 from perl's SIGALRM) fails as `herdr:<target>`, or `herdr` for status. It prints `timed out after <N> s` with the step's output.

- [ ] **Step 1: Write the failing tests.** The stub `herdr` sleeps 5 seconds on `integration install slow`, and `AI_DEPLOY_HERDR_TIMEOUT=1`. Assert:
  - the deploy finishes in under 4 seconds;
  - the last line names `herdr:slow`;
  - the output has `timed out after 1 s`;
  - other targets still install.

  Repeat with a PATH that hides `timeout` and `gtimeout`, using a symlink farm like the existing no-herdr one but without those two, so the perl branch runs. Skip with a `SKIP` line if `perl` is missing.

  Assert the `+` line for an install starts with the wrapper actually used.
- [ ] **Step 2: Run.** Expected: FAIL (the stub sleeps for the full 5 seconds).
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `make -C ~/ai-tooling test`. Expected: `ALL PASS`.
- [ ] **Step 5: Commit:** `fix: make deploy gives Herdr commands a time limit`.

### Task 3: Herdr's official skill for every agent

**Files:**
- Modify: `~/ai-tooling/scripts/deploy.sh` (a `herdr-skill` step, after `agents` and before the Herdr hook step; the existing `skills` step must run after it, so move the order to claude, cursor, herdr-skill, skills, agents, herdr)
- Modify: `~/ai-tooling/docs/AI_TOOLING.md` (the skills section: Herdr's skill is generated from the installed binary)
- Modify (chezmoi): `docs/CHEATSHEET.md` (one line in the skills or Herdr section)
- Test: `~/ai-tooling/scripts/tests/test_deploy.sh`

**Interfaces:**
- **The step runs only when `herdr` is on `PATH`.** The destination is `${AGENTS_SKILLS_DIR:-$HOME/.agents/skills}/herdr/SKILL.md`, plus a marker file `.generated-by-ai-tooling` in the same folder.
- **The commands it prints and runs:**
  - `+ herdr --skill > <tmp>` (under `with_timeout`, as in Task 2), writing to a temp file next to the destination;
  - then, only when the temp file is non-empty, starts with `---`, and differs from the destination: `+ mkdir -p <dir>` (if needed), then `+ mv <tmp> <dst>`, then `+ touch <dir>/.generated-by-ai-tooling` (if missing);
  - when the text is unchanged, it removes the temp file quietly; the step prints just its first `+` line.
- **On failure:** when `herdr --skill` fails, or prints nothing, or prints no frontmatter, the step fails (`herdr-skill`), the destination stays as it was, and the temp file is removed.
- **When `herdr` is not on `PATH`** and the folder has the marker: `+ rm -r <dir>`. A `herdr` skill folder without the marker is never touched.
- **Under `--dry-run`:** print the commands, change nothing.

- [ ] **Step 1: Write the failing tests** with a stub `herdr` whose `--skill` prints a fixed file starting `---\nname: herdr\n`. Cases:
  - **First run:** the file is created and its content equals the stub's; the marker exists.
  - **Second run:** the herdr-skill step prints only its first `+` line, and the file's mtime is unchanged (set an old mtime first, `touch -t 200001010000`).
  - **Changed stub output:** the file is rewritten.
  - **Stub prints nothing:** the step fails, and the existing file is unchanged.
  - **No herdr on PATH:**
    - with the marker, the folder is removed;
    - without the marker (a hand-made `herdr` skill), it is untouched.
  - **Skill links:** with the real `skills/deploy.sh`, real `AI_HOME` and scratch `HOME`, after a deploy `~/.claude/skills/herdr` links to `~/.agents/skills/herdr`.
- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `make -C ~/ai-tooling test` (`ALL PASS`). Then run `bash ~/ai-tooling/scripts/deploy.sh --dry-run` on the real machine; it should print the herdr-skill commands. Never run the real deploy here.
- [ ] **Step 5: Commit** in ai-tooling (`feat: make deploy installs Herdr's own skill for every agent`) and in chezmoi (the cheatsheet line, `docs: ...`).

### Task 4: Roll out and check (controller)

- [ ] **Step 1:** Fast-forward chezmoi `main` (rebase first if `main` moved). Run `chezmoi apply`. Expected:
  - the herdr-skill step creates `~/.agents/skills/herdr/SKILL.md`;
  - `~/.claude/skills/herdr` and `~/.gemini/config/skills/herdr` link to it;
  - `herdr --skill | cmp - ~/.agents/skills/herdr/SKILL.md` succeeds;
  - no ai-tooling to-do.
- [ ] **Step 2:** Run a second `chezmoi apply`. Expected: only `+` lines, "Nothing to do", and `chezmoi diff` is empty.
- [ ] **Step 3:** Check that each agent can see the skill: Claude lists `herdr` in its skills, and Codex, Copilot and Cursor read `~/.agents/skills`. Report anything not checked live.
