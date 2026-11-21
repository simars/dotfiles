# Move a Pane into Another Tab Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `Ctrl-b Shift-j` moves the current pane into another existing tab, in tmux and Herdr.

**Architecture:** tmux binds `choose-tree` + `join-pane`. Herdr binds a popup running `herdr-join`, which lists tabs
(fzf or a numbered prompt) and calls `herdr pane move`.

**Tech Stack:** bash, jq, fzf (optional), Herdr 0.9.5 CLI, tmux 3.8, chezmoi templates, `tests/host-profiles.sh`.

**Spec:** `docs/superpowers/specs/2026-11-21-herdr-join-design.md`

## Global Constraints

* Bash 3.2 compatible (the Macs run `/bin/bash` 3.2): no `mapfile`, no `;;&`, no associative arrays.
* `herdr` from `${HERDR_BIN_PATH:-herdr}`; pane from `$1`, then `$HERDR_ACTIVE_PANE_ID`, then `$HERDR_PANE_ID`.
* Same key on both: tmux `J`, Herdr `prefix+shift+j`. Cheatsheet updated in the same commit.

## Review Focus

1. Only one tab exists: a clear "no other tab" message, no move.
2. The choice is not a number on the list (`9`, `x`): refused, no move.
3. Herdr answers with an error or not JSON: the message reaches the user (popup waits for Enter in a terminal).
4. A tab in another workspace: moved there (listing covers every workspace).
5. The popup's `HERDR_ACTIVE_PANE_ID` is the pane that was focused, not the popup: checked with a real key press.

---

### Task 1: herdr-join, its key, tmux's key, docs

**Files:**
- Create: `dot_local/bin/executable_herdr-join`
- Modify: `dot_config/herdr/config.toml.tmpl` (a `[[keys.command]]` after herdr-equalize's)
- Modify: `dot_config/tmux/tmux.conf` (after `bind ... ! break-pane`)
- Test: `tests/host-profiles.sh` (after the herdr-layout block)
- Docs: `docs/CHEATSHEET.md`, `docs/TESTING_AND_VERIFICATION_GUIDE.md` §9.16, `docs/FUTURE_CONSIDERATIONS.md` §12

- [ ] **Step 1: Write the failing tests.** A stub `herdr` in `$work/herdr-join` answers `pane layout` (tab `w1:t1`),
  `tab list` (w1:t1 2 panes, w1:t2 label "2", w2:t1 label "logs"), `workspace list` (w1 "chezmoi", w2 "other"),
  logs `pane move` and answers it from `move.json`. `join_run` pipes stdin into the script with pane `p1`.
  * config, both hosts: `prefix+shift+j` is `type = "popup"` running `.local/bin/herdr-join`.
  * tmux: exactly one `bind ... J choose-tree -Zw "join-pane -h -t '%%'"`.
  * list: `1) chezmoi  2  (1 pane)` and `2) other  1: logs  (3 panes)` on stderr, w1:t1 absent.
  * `2` → `exit 0`, call `move p1 --tab w2:t1 --split right --focus`.
  * empty input → `exit 0`, no call. `9` and `x` → `exit 1`, no call.
  * only one tab → `exit 1`, stderr names "no other tab", no call.
  * move answers `{"error":{"message":"tab w1:t2 not found"}}` → `exit 1`, message on stderr. Answers `oops` → `exit 1`.
  * no pane id → `exit 1`.
- [ ] **Step 2: Run** `bash tests/host-profiles.sh 2>&1 | tail -5`. Expected: the new checks FAIL.
- [ ] **Step 3: Implement** the script, the Herdr key, the tmux key.
- [ ] **Step 4: Run** the suite. Expected: all pass. `herdr config check` on the rendered config: `config: ok`.
- [ ] **Step 5: Real keys** in a throwaway Herdr `--session` and a throwaway tmux server (Review Focus 4 and 5).
- [ ] **Step 6: Docs**, then commit `feat(herdr): move a pane into another tab with prefix Shift-j, in tmux too`.
