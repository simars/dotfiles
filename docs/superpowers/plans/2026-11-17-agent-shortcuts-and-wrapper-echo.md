# Agent Shortcuts and Wrapper Echo Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace `cld`/`csr` with one alias per agent and mode (`o` secrets, `y` no prompts), and make `with-op`, `tat` and `dkill` print the command they run.

**Architecture:** Aliases and the two shell functions live in `dot_aliases` (sourced by bash and zsh); `tat` is a POSIX `sh` script. Each wrapper prints `→ <command>` to stderr just before running it, only when stderr is a terminal. All checks go in `tests/host-profiles.sh`, which fakes a terminal with `script(1)` and skips the terminal checks where it cannot.

**Tech Stack:** bash and zsh (interactive, `EXTENDED_GLOB` on), POSIX `sh`, chezmoi, `script(1)` (util-linux on Linux, BSD on macOS).

**Spec:** `docs/superpowers/specs/2026-11-17-agent-shortcuts-and-wrapper-echo-design.md`

## Global Constraints

- Public repository: no work organisation names, work email, work folder paths or 1Password Environment IDs in any tracked file or commit message (AGENTS.md 3.3).
- Every alias is wrapped in `if command -v <tool> &> /dev/null; then ... fi` (AGENTS.md 3.2).
- `dot_aliases` must work when sourced by bash and by zsh, including zsh with `EXTENDED_GLOB` (escape `#`, `^`, `~` in patterns). `tat` stays POSIX `sh`.
- `tests/host-profiles.sh` runs under bash 3.2 (macOS `/bin/bash`): no associative arrays, `mapfile`, `${var,,}`. CI runs it on `ubuntu-latest` and `macos-26`.
- Echo format: `→ ` then the command; to stderr; only when `[ -t 2 ]`; arguments quoted with `printf %q` (bash and zsh quote some characters differently, e.g. zsh prints `a#b` as `a\#b` and `=x` as `\=x`, but each output pastes back correctly into the shell that printed it).
- y flags, verbatim: `claude --dangerously-skip-permissions`, `copilot --yolo`, `cursor-agent --yolo`, `codex --dangerously-bypass-approvals-and-sandbox`, `agy --dangerously-skip-permissions`.
- `docs/CHEATSHEET.md` changes in the same commit as the code it documents (AGENTS.md 2).
- Commit as `Simar Singh <simarpaulsingh@gmail.com>` (the repo's configured identity), conventional messages, no `Co-Authored-By` or other trailers. Never push.

## Review Focus

1. A host with only some agents (mbp has only `codex` and `agy`): exactly `cdxy` and `agyy` exist, no `cld*`/`cpl*`/`csa*`/`csro`. Test in Task 1.
2. A prompt with spaces (`cldoy "fix the bug"`): the agent gets one argument, and the echo shows it quoted (`fix\ the\ bug`). Test in Task 2.
3. The wrapped command's exit status passes through `with-op` unchanged after the echo (`with-op false` returns 1). Test in Task 2.
4. A compose folder with a space in its name (`my svc/`): `dkill` echoes `(cd my\ svc/ && ...)` and still stops it. Test in Task 4.
5. macOS CI, where BSD `script` may not give a terminal without a terminal on stdin: the terminal checks print one SKIP line instead of failing, and the non-terminal checks still run. Probe in Task 2.

---

### Task 1: Agent aliases

**Files:**
- Modify: `dot_aliases:156-157` (replace `cld` and `csr`)
- Modify: `docs/CHEATSHEET.md:32-39` (section "1Password-Aware Runner")
- Test: `tests/host-profiles.sh` (after the `with-op reads .op-env` checks)

**Interfaces:**
- Consumes: `with-op` (existing function in `dot_aliases`).
- Produces: aliases `cldo cldy cldoy cplo cply cploy csao csay csaoy csro cdxy agyy`; test fixture `$work/agents/bin` holding stub executables named `claude copilot cursor-agent cursor codex agy`.

- [ ] **Step 1: Write the failing checks**

Create the six stubs (`#!/bin/sh` + `echo "$0 $*"`, executable) in `$work/agents/bin`, and a stub dir `$work/agents/some` with only `codex` and `agy`. Each check runs from the repository root as `$(PATH=<path> /bin/bash -c 'source dot_aliases 2> /dev/null; <body>')`:

```bash
agent_aliases="cldo cldy cldoy cplo cply cploy csao csay csaoy csro cdxy agyy"
# <path> = "$work/agents/bin:$PATH", <body> = alias $agent_aliases (pass the list in as $0 or an env var)
check "agent aliases expand as designed" "alias cldo='with-op claude'
alias cldy='claude --dangerously-skip-permissions'
alias cldoy='with-op claude --dangerously-skip-permissions'
alias cplo='with-op copilot'
alias cply='copilot --yolo'
alias cploy='with-op copilot --yolo'
alias csao='with-op cursor-agent'
alias csay='cursor-agent --yolo'
alias csaoy='with-op cursor-agent --yolo'
alias csro='with-op cursor .'
alias cdxy='codex --dangerously-bypass-approvals-and-sandbox'
alias agyy='agy --dangerously-skip-permissions'" "<that command's output>"
# <path> = "$work/agents/some" ONLY (on Arch /bin is /usr/bin, which holds the real cursor); <body> uses builtins only:
#   out=; for n in $agent_aliases; do alias "$n" > /dev/null 2>&1 && out="$out $n"; done; echo "${out# }"
check "only installed agents get aliases" "cdxy agyy" "<that command's output>"
# <path> = "$work/agents/bin:$PATH"; <body> = alias cld csr 2> /dev/null
check "cld and csr are gone" "" "<that command's output>"
# <path> = "$work/agents/bin:$PATH"; <body> = alias | grep -E "with-op (codex|agy)"
check "codex and agy never run under with-op" "" "<that command's output>"
```

- [ ] **Step 2: Run, expect failures**

Run: `bash tests/host-profiles.sh 2>&1 | grep -E '^FAIL|passed'`
Expected: FAIL for "agent aliases expand as designed", "only installed agents get aliases", "cld and csr are gone".

- [ ] **Step 3: Replace lines 156-157 of `dot_aliases`**

One `command -v` block per tool (`claude`, `copilot`, `cursor-agent`, `cursor`, `codex`, `agy`), aliases exactly as in the check, preceded by a short comment block naming the scheme: `o` = with-op (Claude, Copilot, Cursor only), `y` = the tool's no-prompt flag, `oy` both; plain = the tool's own name.

- [ ] **Step 4: Update `docs/CHEATSHEET.md` section "1Password-Aware Runner"**

Heading becomes `### 1Password-Aware Runner and Agent Shortcuts (`with-op`, `cldo`, `cldy`, ...)`. Keep the `with-op` paragraph and row. Replace the `cld`/`csr` rows with one table: Agent | `o` | `y` | `oy` | plain, as in the spec. Add one paragraph: letters, `o` only for Claude/Copilot/Cursor, each alias exists only where its tool is installed, extra arguments append, Codex's flag also drops its sandbox, `cld` and `csr` were replaced by `cldo` and `csro`.

- [ ] **Step 5: Run, expect pass; check rendering and parsing**

Run: `bash tests/host-profiles.sh 2>&1 | tail -1` → `N passed, 0 failed`
Run: `zsh -n dot_aliases && zsh -c 'source dot_aliases && cheat | head -n 5'` → no error, cheatsheet title.

- [ ] **Step 6: Commit**

```bash
git add dot_aliases docs/CHEATSHEET.md tests/host-profiles.sh
git commit -m "feat(aliases): agent shortcuts with o (1Password) and y (no prompts) letters"
```

---

### Task 2: `with-op` echo and the terminal test helper

**Files:**
- Modify: `dot_aliases` (`with-op`, and a new helper just above it; comment block above `with-op`)
- Modify: `docs/CHEATSHEET.md` (`with-op` paragraph)
- Test: `tests/host-profiles.sh` (helpers next to `check()`; checks after Task 1's)

**Interfaces:**
- Consumes: the `$work/with-op` fixture (stub `op`, `.op-env` with `env111`, `env222`) already in the tests.
- Produces:
  - `dot_aliases`: `__echo_cmd [-n NOTE] WORD...` — when `[ -t 2 ]`, writes `→` and each WORD as ` %q` to stderr, then `  (NOTE)` if given, then a newline; always returns 0.
  - `tests/host-profiles.sh`: `repo="$PWD"` (set right after the existing `cd` to the repository root); `on_tty CMD...` runs CMD with stdin/stdout/stderr on a pseudo-terminal and prints its output with `\r` removed; `tty_ok` is `yes` when that works; `tty_check NAME EXPECTED DIR CMD...` calls `check NAME EXPECTED "$(cd DIR && on_tty CMD...)"` when `tty_ok` is `yes`, otherwise does nothing. The `cd` is inside the command substitution so `check`'s counters are updated in the main shell. CMD starts with `env PATH=<stub dir>:$PATH` when it needs stubs.

- [ ] **Step 1: Add the test helpers**

`on_tty`: if `script --version 2>/dev/null | grep -q util-linux`, run `SHELL=/bin/bash script -qec "<CMD words joined with printf %q>" /dev/null < /dev/null`; else `script -q /dev/null CMD... < /dev/null`. Pipe through `tr -d '\r'`. Probe once: `tty_ok` is `yes` only when `on_tty sh -c '[ -t 2 ] && echo yes'` prints exactly `yes`. When it is not, print one line `SKIP terminal checks: script(1) gives no terminal here` and have the summary line still end in `N passed, 0 failed` (skips are not failures).

- [ ] **Step 2: Write the failing checks**

`$work/no-secrets` is a new empty directory. `op_p="PATH=$work/with-op/bin:$PATH"`, passed as one word to `env`.

```bash
op_line="→ op run --no-masking --environment env111 --environment env222 -- true"
stub_line="run --no-masking --environment env111 --environment env222 -- true"
tty_check "with-op echoes the op run command (bash)" "$op_line
$stub_line" "$work/with-op" env "$op_p" bash -c 'source "$0"; with-op true' "$repo/dot_aliases"
tty_check "with-op echoes the op run command (zsh EXTENDED_GLOB)" "$op_line
$stub_line" "$work/with-op" env "$op_p" zsh -fc 'setopt EXTENDED_GLOB; source "$0"; with-op true' "$repo/dot_aliases"
tty_check "with-op says when no secrets load" "→ echo hi  (no .op-env or .env: no secrets)
hi" "$work/no-secrets" bash -c 'source "$0"; with-op echo hi' "$repo/dot_aliases"
# Review Focus 2: one argument with spaces
tty_check "with-op quotes arguments with spaces" "$op_line fix\\ the\\ bug
$stub_line fix the bug" "$work/with-op" env "$op_p" bash -c 'source "$0"; with-op true "fix the bug"' "$repo/dot_aliases"
# Review Focus 3: exit status, no terminal needed
check "with-op passes the exit status through" 1 \
    "$(cd "$work/no-secrets" && bash -c 'source "$0"; with-op false; echo $?' "$repo/dot_aliases")"
```

The existing non-terminal checks ("with-op reads .op-env (bash)" and "(zsh with EXTENDED_GLOB)") already capture stderr with `2>&1`; they must keep passing unchanged. That proves the echo is silent off a terminal.

- [ ] **Step 3: Run, expect failures**

Run: `bash tests/host-profiles.sh 2>&1 | grep -E '^(FAIL|SKIP)|passed'`
Expected: the three echo checks FAIL (no `→` line); "passes the exit status through" may already pass.

- [ ] **Step 4: Implement `__echo_cmd` and call it in `with-op`**

In `with-op`: with no flags, `__echo_cmd -n "no .op-env or .env: no secrets" "$@"` before `"$@"`; otherwise `__echo_cmd op run --no-masking "${flags[@]}" -- "$@"` before `op run ...`. Keep `"$@"; return` so the status passes through. Add one sentence to the comment above `with-op`: it prints the command it runs to stderr when that is a terminal.

- [ ] **Step 5: Update `docs/CHEATSHEET.md`**

In the `with-op` paragraph add: before running, it prints `→ <command>` to the terminal (stderr, only when it is one, so pipes and agents never see it); without `.op-env` or `.env` the line ends `(no .op-env or .env: no secrets)`.

- [ ] **Step 6: Run, expect pass**

Run: `bash tests/host-profiles.sh 2>&1 | grep -E '^(FAIL|SKIP)|passed'`
Expected: `N passed, 0 failed`, no SKIP on Omarchy.

- [ ] **Step 7: Commit**

```bash
git add dot_aliases docs/CHEATSHEET.md tests/host-profiles.sh
git commit -m "feat(aliases): with-op prints the command it runs on a terminal"
```

---

### Task 3: `tat` echo

**Files:**
- Modify: `dot_local/bin/executable_tat`
- Modify: `docs/CHEATSHEET.md:463-471` (tmux Sessions intro)
- Test: `tests/host-profiles.sh`

**Interfaces:**
- Consumes: `tty_check`, `on_tty`, `tty_ok` from Task 2.
- Produces: nothing for later tasks.

- [ ] **Step 1: Write the failing checks**

Fixture: `$work/tat/my.app/` and stub `$work/tat/bin/tmux`: `has-session` exits `${STUB_TMUX_HAS:-1}`, anything else prints `tmux $*`. Run from `$work/tat/my.app` with `PATH="$work/tat/bin:$PATH"` and `TMUX` unset unless stated.

```bash
tat_dir="$work/tat/my.app"; tat="$repo/dot_local/bin/executable_tat"; tp="PATH=$work/tat/bin:$PATH"
check "tat is silent off a terminal" "tmux new-session -As my-app" "$(cd "$tat_dir" && env -u TMUX "$tp" sh "$tat" 2>&1)"
tty_check "tat echoes outside tmux" "→ tmux new-session -As my-app
tmux new-session -As my-app" "$tat_dir" env -u TMUX "$tp" sh "$tat"
tty_check "tat echoes create and switch inside tmux" "→ tmux new-session -Ad -s my-app
tmux new-session -Ad -s my-app
→ tmux switch-client -t my-app
tmux switch-client -t my-app" "$tat_dir" env TMUX=x STUB_TMUX_HAS=1 "$tp" sh "$tat"
check "tat is valid sh" "" "$(sh -n dot_local/bin/executable_tat 2>&1)"
```

- [ ] **Step 2: Run, expect the two `tty_check`s to fail**

Run: `bash tests/host-profiles.sh 2>&1 | grep -E '^FAIL|passed'`

- [ ] **Step 3: Implement `show_cmd` in `executable_tat`**

`show_cmd() { if [ -t 2 ]; then printf '→ %s\n' "$*" >&2; fi; }`, called immediately before each of the three `tmux` invocations that act (`new-session -As`, `new-session -Ad -s`, `switch-client -t`), never before `has-session`. The session name is printed as is (spec).

- [ ] **Step 4: Update the tmux Sessions intro in `docs/CHEATSHEET.md`**

One sentence: `tat` prints the tmux command it runs (`→ tmux new-session -As my-app`) when stderr is a terminal.

- [ ] **Step 5: Run, expect pass**

Run: `bash tests/host-profiles.sh 2>&1 | tail -1` → `N passed, 0 failed`

- [ ] **Step 6: Commit**

```bash
git add dot_local/bin/executable_tat docs/CHEATSHEET.md tests/host-profiles.sh
git commit -m "feat(tat): print the tmux command it runs on a terminal"
```

---

### Task 4: `dkill` echo

**Files:**
- Modify: `dot_aliases:85-92` (`dkill`)
- Modify: `docs/CHEATSHEET.md:416` (`dkill` row)
- Test: `tests/host-profiles.sh`

**Interfaces:**
- Consumes: `tty_check` from Task 2.
- Produces: nothing.

- [ ] **Step 1: Write the failing checks**

Fixture `$work/dkill/` with `api/docker-compose.yml`, `web/docker-compose.yaml`, `docs/` (no compose file), `my svc/docker-compose.yml`; stub `$work/dkill/bin/docker` printing `docker $* in $(basename "$PWD")`. Run from `$work/dkill` with `PATH="$work/dkill/bin:$PATH"`.

```bash
dkill_out="docker compose down in api
docker compose down in my svc
docker compose down in web"
dp="PATH=$work/dkill/bin:$PATH"
check "dkill is silent off a terminal" "$dkill_out" \
    "$(cd "$work/dkill" && env "$dp" bash -c 'source "$0"; dkill' "$repo/dot_aliases" 2>&1)"
dkill_tty="→ (cd api/ && docker compose down)
docker compose down in api
→ (cd my\\ svc/ && docker compose down)
docker compose down in my svc
→ (cd web/ && docker compose down)
docker compose down in web"
tty_check "dkill echoes each folder (bash)" "$dkill_tty" "$work/dkill" env "$dp" bash -c 'source "$0"; dkill' "$repo/dot_aliases"
tty_check "dkill echoes each folder (zsh EXTENDED_GLOB)" "$dkill_tty" "$work/dkill" env "$dp" zsh -fc 'setopt EXTENDED_GLOB; source "$0"; dkill' "$repo/dot_aliases"
```

- [ ] **Step 2: Run, expect the two `tty_check`s to fail**

- [ ] **Step 3: Implement**

Inside the `if` of `dkill`, before `(cd "$d" && docker compose down)`: `if [[ -t 2 ]]; then printf '→ (cd %q && docker compose down)\n' "$d" >&2; fi`.

- [ ] **Step 4: Update the `dkill` row in `docs/CHEATSHEET.md`**

Append to its Purpose cell: `, printing each `(cd <dir>/ && docker compose down)` first`.

- [ ] **Step 5: Run, expect pass** — `bash tests/host-profiles.sh 2>&1 | tail -1` → `N passed, 0 failed`

- [ ] **Step 6: Commit**

```bash
git add dot_aliases docs/CHEATSHEET.md tests/host-profiles.sh
git commit -m "feat(aliases): dkill prints each docker compose down it runs"
```

---

### Task 5: Deploy and verify on this machine

**Files:** none changed.

- [ ] **Step 1: Repository checks**

Run: `bash tests/host-profiles.sh 2>&1 | tail -2`, `zsh -c 'source dot_aliases && cheat | head -n 30'`, `gitleaks detect --source ~/.local/share/chezmoi --no-banner`
Expected: `N passed, 0 failed`; the cheatsheet renders with the new table; `no leaks found`.

- [ ] **Step 2: Apply only the two targets**

Run: `chezmoi status` (expect only `~/.aliases` and `~/.local/bin/tat` pending), then `chezmoi diff ~/.aliases ~/.local/bin/tat`, then `chezmoi apply -v ~/.aliases ~/.local/bin/tat`.

- [ ] **Step 3: Interactive check in the real zsh, without starting an agent or 1Password**

Run, in a project folder that has a `.op-env`, under a pseudo-terminal: `zsh -ic 'function op { print -r -- "$@"; }; with-op true'` via `script -qec ... /dev/null`
Expected: a `→ op run --no-masking --environment <id> -- true` line, then the stub's echo. Then `zsh -ic 'alias cldoy cplo csay cdxy agyy'` shows the designed expansions, and `zsh -ic 'alias cld'` prints nothing.

- [ ] **Step 4: Tell the user** that open terminals need `source ~/.aliases`, that `cld`/`csr` are now `cldo`/`csro`, and that the Macs get it after a push and `chezmoi update`. No push.
