# Design: Agent shortcuts and wrapper echo

**Date:** 2026-11-17
**Status:** Approved
**Size:** small change (short design)

## Intent

Starting a coding agent with the project's 1Password secrets (`with-op`) and without permission prompts takes a long
command today (`cld --dangerously-skip-permissions`). One short, predictable name per combination makes it easy, and
the same letters should mean the same thing for every agent. Separately, the shell wrappers that decide at run time what
to run should say what they ran, because that decision (were secrets loaded? which tmux session?) is invisible today.

## Goals

- Claude, Copilot and Cursor (the agents used with project secrets) get a name for each of: secrets, no prompts, both.
- Codex and Antigravity get a no-prompts name only: they never run with `with-op`.
- `with-op`, `tat` and `dkill` print the command they are about to run.

## Non-goals and anti-goals

- No plain aliases (`cld` for `claude`): the tool's own name already is the plain version.
- No echo for aliases, and none for pass-through wrappers that choose nothing (`config`, `wt`, `wr`, Omarchy's `ssh`,
  `iso2sd`, `try` shims) or for tools with their own output (`mise-audit`, `setup-guides`, `ssh-key-remember`, `cheat`,
  `userland`).
- Anti-goal: the echo must never reach a pipe or an agent's tool output (`ll | grep`, Claude Code calling `config`).
- Anti-goal: no `with-op` alias for Codex or Antigravity, even by accident of a shared helper.

## Approaches considered

**Naming.**
- A, chosen: a three-letter tool code plus `o` (secrets, `with-op`) and `y` (no prompts), in that order; no plain alias.
- B: secrets by default (`cld` = `with-op claude`), `n` to opt out (`cldn`, `cldny`). Kept the old `cld` habit, but the
  same name would load secrets for one agent and never for another, and it needs as many names as A.
- A with plain aliases (`cld` = `claude`): dropped. They add nothing over the real command, and a bare `cld` that no
  longer loads secrets would fail silently for someone used to the old meaning; without it, `cld` is "command not found".

**Echo.**
- Chosen: one `printf` in each wrapper, just before it runs the command it chose.
- A zsh `preexec` hook that prints alias expansions: zsh only, needs a list of whose aliases count, noisy for `ls`, `..`,
  `g` and the Mac's GNU `userland` aliases. Dropped together with the alias echo.
- `set -x` tracing: prints every internal step, not the one command that matters.

## Decisions

### Aliases (`dot_aliases`, replacing `cld` and `csr`)

| Agent | `o` secrets | `y` no prompts | `oy` both |
|---|---|---|---|
| Claude | `cldo` = `with-op claude` | `cldy` = `claude --dangerously-skip-permissions` | `cldoy` |
| Copilot | `cplo` = `with-op copilot` | `cply` = `copilot --yolo` | `cploy` |
| Cursor agent | `csao` = `with-op cursor-agent` | `csay` = `cursor-agent --yolo` | `csaoy` |
| Cursor editor | `csro` = `with-op cursor .` | (no flag exists) | |
| Codex | | `cdxy` = `codex --dangerously-bypass-approvals-and-sandbox` | |
| Antigravity | | `agyy` = `agy --dangerously-skip-permissions` | |

`oy` is `with-op <tool> <y flag>`. Flags were read from each tool's `--help` on 2026-11-17 (claude 2.1.326, copilot
1.0.113, cursor-agent 2026.11.13, codex 0.169.0, agy 1.5.10). Codex has no `--yolo`; its only full skip also turns off
its sandbox. Each alias is defined only when its tool is on `PATH` (`command -v`, AGENTS.md section 3.2), so a machine
without Copilot has no `cpl*`. None of the names clashes with a command, builtin or alias on Omarchy, mbp-work or mbp
(checked 2026-11-17). Omarchy's own `c`, `cx` and `cy` stay untouched. Extra arguments append (`cldoy --resume`).

### Echo

- Format: `→ <command>` on one line, arguments quoted with `printf %q` so the line can be pasted and run. bash and zsh
  quote some characters differently (`a#b` becomes `a\#b` and `=x` becomes `\=x` in zsh), but each pastes back
  correctly into the shell that printed it; `tat` is POSIX `sh`, which has no `%q`, and prints its session name as is (already free of
  `.` and `:`).
- Only when stderr is a terminal (`[ -t 2 ]`), and to stderr.
- `with-op`: `→ op run --no-masking --environment <id> [--env-file=.env] -- <cmd...>`; without `.op-env` or `.env`:
  `→ <cmd...>  (no .op-env or .env: no secrets)`.
- `tat`: `→ tmux new-session -As <name>` outside tmux; inside it, `→ tmux new-session -Ad -s <name>` when it creates the
  session, then `→ tmux switch-client -t <name>`.
- `dkill`: `→ (cd <dir>/ && docker compose down)` for each folder it stops.

### Documentation and tests

- `docs/CHEATSHEET.md`: the "1Password-Aware Runner" section lists the new names and the echo, says `cld` and `csr` are
  gone (now `cldo` and `csro`); the `tat` and `dkill` entries mention the echo.
- `tests/host-profiles.sh`: each alias expands as in the table when its tool is on `PATH` (stub binaries) and is absent
  when not; `cld` and `csr` are gone; no `with-op` alias for Codex or Antigravity; the echo is silent when stderr is not
  a terminal; and the echoed line is right when it is.

## Left to the builder

- How the tests fake a terminal on stderr (for example `script`, whose flags differ between GNU and BSD).
- Where the shared echo code lives, if any is shared: `with-op` and `dkill` are shell functions in `~/.aliases`, `tat` is
  a separate `sh` script.
