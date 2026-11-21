# Terminal Resize and Reload Keys Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** `r` reloads after every prefix/leader; Ghostty's leader gains `Alt+arrows` resize and `Shift+e` equalize;
Herdr gains `prefix Shift+e` equalize.

**Architecture:** Ghostty keys are lines appended by `dot_config/ghostty/modify_config.tmpl`; Herdr's equalize is a
bash + jq script driven by Herdr's CLI and bound as a `[[keys.command]]`.

**Tech Stack:** bash, jq, chezmoi templates, `tests/host-profiles.sh`.

**Spec:** `docs/superpowers/specs/2026-11-21-terminal-resize-keys-design.md`

## Global Constraints

- tmux and Herdr existing keys unchanged; nothing new without a prefix or leader.
- Ghostty steps: `Alt+arrows` 40 px, `h j k l` / arrows in `term_resize` 20 px.
- Commit as Simar Singh, conventional commits, no agent trailers; cheatsheet in the same commit as the key change.

## Review Focus

- Multiple `chain=` lines after one binding must survive the kv awk (kept with their binding, idempotent).
- Mac and Omarchy leader blocks stay identical apart from the leader key.
- `herdr-equalize` on a tab with one pane (no splits) exits 0 and does nothing.
- `herdr-equalize` when a resize does not move the ratio (zoomed tab) fails with a message, no loop.
- Herdr's custom command runs on the server: use `$HOME/.local/bin/herdr-equalize`, `HERDR_BIN_PATH` for herdr.

---

### Task 1: Ghostty leader `r`, `Alt+arrows`, `Shift+e`

**Files:** Modify `dot_config/ghostty/modify_config.tmpl:26-66`; Test `tests/host-profiles.sh` (Ghostty leader block,
~line 710).

- [ ] Write failing checks: `term/r=reload_config` followed by `chain=deactivate_key_table`; no
  `chain=activate_key_table:term_resize` directly after `term/r`; for each direction
  `term/alt+arrow_<d>=resize_split:<d>,40` followed by `chain=deactivate_key_table` then
  `chain=activate_key_table:term_resize`; `term_resize/alt+arrow_<d>=resize_split:<d>,40` (4);
  `term/shift+e=equalize_splits`; `term/equal` kept. Drop the `term/r` exclusion in the chain-after-action check.
- [ ] Run `bash tests/host-profiles.sh`; expect the new checks to FAIL.
- [ ] Implement; run tests; expect all pass. Commit with the cheatsheet Ghostty table update.

### Task 2: `herdr-equalize` and Herdr `prefix+shift+e`

**Files:** Create `dot_local/bin/executable_herdr-equalize`; Modify `dot_config/herdr/config.toml.tmpl`; Test
`tests/host-profiles.sh`.

- [ ] Write failing checks with a stub `herdr` on PATH (serves layout JSON from a state file; `pane resize` records its
  arguments and swaps in the next layout): uneven 2-split layout → first resize is the root split's boundary pane,
  direction and amount as computed, exit 0 once even; one-pane layout → no resize, exit 0; resize that leaves the
  ratio unchanged → exit 1 with `stayed at`. Herdr config renders a `[[keys.command]]` with `key = "prefix+shift+e"`
  whose command names `herdr-equalize`.
- [ ] Run tests; expect FAIL. Implement the script from the spike; run; expect PASS. Commit with the cheatsheet
  tmux/Herdr table update.

### Task 3: Docs and rollout

- [ ] Cheatsheet trip points (resize mode entry, prefix `Ctrl+arrows` on the Macs), AGENTS §4.2, FUTURE §12,
  testing guide §9.16 rows. Full suite, gitleaks, commit.
- [ ] Fast-forward main, push (approved), apply on works, mbp-work, mbp.
