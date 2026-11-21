# Herdr Layouts and Rotation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** tmux's preset layouts, `next-layout` and `rotate-window` in Herdr, on tmux's keys after the prefix.

**Architecture:** one bash + jq script, `herdr-layout`, driving `herdr pane layout|swap|move|zoom`; Herdr
`[[keys.command]]` bindings call it.

**Tech Stack:** bash, jq, chezmoi, `tests/host-profiles.sh`.

**Spec:** `docs/superpowers/specs/2026-11-21-herdr-layouts-design.md`

## Global Constraints

- Keys only after the prefix; tmux untouched; never close a pane.
- Main size 80 columns / 24 rows as a share, within 0.1..0.9.
- Commit as Simar Singh, conventional commits, cheatsheet in the same commit.

## Review Focus

- The focused pane keeps focus after a rebuild (moved back with `--focus`), and after a rotation.
- Ids from move replies are used, not assumed (a pane id may change on a move).
- The temporary tab is named on failure and is never left behind on success.
- Two panes in a main layout (rest = one pane); tiled with 2, 3, 5 panes.
- `next` with no state, with state from a preset, and wrapping after tiled.

---

### Task 1: `herdr-layout` and its keys

**Files:** Create `dot_local/bin/executable_herdr-layout`; Modify `dot_config/herdr/config.toml.tmpl`,
`docs/CHEATSHEET.md`; Test `tests/host-profiles.sh`.

- [ ] Write failing checks with a stub `herdr` that serves `layout.json`, logs every other call and answers
  `pane move` with `{"result":{"move_result":{"pane":{"pane_id":<moved>},"created_tab":{"tab_id":"w1:t9"}}}}`:
  rotate-up / rotate-down swap sequences (3 panes); even-horizontal sequence (out, then back with ratios 0.3333 and
  0.5); main-vertical with 4 panes on a 160-wide tab (main ratio 0.5, then 1/3, 1/2 down); main-vertical-mirrored
  anchor; tiled with 5 panes (rows of 3 and 2); `next` from no state, after a preset, wrapping; one pane does nothing;
  zoomed tab unzoomed first; focused pane moved back with `--focus`. Herdr config has the 10 bindings.
- [ ] Run; expect FAIL. Implement; run; expect PASS; `herdr config check` on the render; real session check of every
  preset and both rotations; commit.

### Task 2: Docs, review, rollout

- [ ] Cheatsheet tmux/Herdr table rows and "tmux keys Herdr lacks", testing guide §9.16, FUTURE §12 line.
- [ ] Final review by a fresh reviewer; fix; fast-forward main; apply on works; push and roll out to the Macs when the
  user says so.
