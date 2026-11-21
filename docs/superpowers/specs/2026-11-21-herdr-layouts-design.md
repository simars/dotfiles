# Herdr Layouts and Rotation Like tmux — Design

Short design, approved by the user in conversation on 2026-11-21. Follows
`2026-11-21-terminal-resize-keys-design.md`.

## Intent

Herdr should arrange panes the way tmux does after the prefix: `Space` cycles the preset layouts, `Alt+1`..`7` pick one,
`Ctrl+o` / `Alt+o` rotate the panes. Herdr has none of these actions, so a script drives Herdr's CLI.

## Approaches

* **Script over Herdr's CLI (picked).** `herdr pane swap` swaps any two panes in place (sizes stay with the places, focus
  stays with the pane); `herdr pane move` puts a pane beside another with a ratio, keeping its id and its process.
* **Ghostty: nothing.** Ghostty 1.4 has no swap, move, rotate or layout action and no IPC to drive one; rebuilding a
  split closes its program. A leader key that opens a new tab already split would start new shells, unlike tmux.
* **Main pane = the focused pane** was offered and not picked: tmux uses the first pane.

## Design

`dot_local/bin/executable_herdr-layout ACTION [PANE_ID]` (pane defaults to `$HERDR_ACTIVE_PANE_ID`, then
`$HERDR_PANE_ID`), bash + jq, `herdr` from `$HERDR_BIN_PATH`.

* Pane order is the order of `herdr pane layout`'s `panes` (the split tree, first to last, as tmux's pane index after a
  layout). The first pane is the main pane.
* `rotate-up` (tmux `C-o`, `rotate-window -U`): each pane moves one place back, the first goes last:
  `swap first second`, `swap first third`, ... `rotate-down` (`M-o`, `-D`): `swap last before-last`, ..., `swap last
  first`.
* Presets, as tmux 3.8 (`next` cycles in tmux's order: even-horizontal, even-vertical, main-horizontal,
  main-horizontal-mirrored, main-vertical, main-vertical-mirrored, tiled):

  | Name (tmux key) | Outer split | Groups (shares) | Inside a group |
  | :--- | :--- | :--- | :--- |
  | even-horizontal (`M-1`) | right | each pane alone, equal | |
  | even-vertical (`M-2`) | down | each pane alone, equal | |
  | main-horizontal (`M-3`) | down | main (24 rows), rest | right, equal |
  | main-vertical (`M-4`) | right | main (80 columns), rest | down, equal |
  | tiled (`M-5`) | down | rows of ceil(sqrt(n)) panes, equal | right, equal |
  | main-horizontal-mirrored (`M-6`) | down | rest, main last | right, equal |
  | main-vertical-mirrored (`M-7`) | right | rest, main last | down, equal |

  Main size is tmux's default `main-pane-width` 80 / `main-pane-height` 24 as a share of the tab, kept within 0.1..0.9
  (Herdr's ratio limits).
* Rebuild: the first pane of the first group (the anchor) stays; every other pane moves to one temporary tab
  (`--new-tab`, then beside the first one moved); then each group's first pane goes back beside the previous group's
  first pane along the outer split, and then each group's other panes beside the previous one along the inner split.
  `--ratio` is the share the target keeps: `share_j / (share_j + ... + share_k)` between groups, `1 / panes left`
  inside a group. The temporary tab closes when empty. Pane ids are taken from each move's reply.
* A zoomed tab is unzoomed first (tmux does too). The focused pane is moved back with `--focus`, every other with
  `--no-focus`. One pane: nothing to do. `next` remembers per tab, in
  `${XDG_STATE_HOME:-~/.local/state}/herdr-layout/`, which preset was applied last (presets record it too).
* If a move fails midway the panes left in the temporary tab keep running; the script names that tab.
* Herdr keys (`[[keys.command]]`, `prefix+space`, `prefix+alt+1`..`7`, `prefix+ctrl+o`, `prefix+alt+o`), cheatsheet,
  testing guide.
* Depends on Herdr 0.9.5 behaviour found by spikes on 2026-11-21: a move within the same tab does nothing (hence the
  temporary tab); `--ratio` is the target's share; a move reply has `move_result.pane.pane_id` and
  `move_result.created_tab.tab_id`.

## Anti-goals

No change to tmux; no new key without the prefix; never close or restart a pane's program.

## Left to the builder

Test wording; the stub `herdr` (logs commands, serves a layout, answers moves).
