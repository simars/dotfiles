# Move a Pane into Another Tab (tmux join-pane) — Design

Short design, approved by the user in conversation on 2026-11-21. Follows `2026-11-21-herdr-layouts-design.md`.

## Intent

One key after the prefix moves the current pane into another existing tab, in tmux and in Herdr alike, with the
program in it still running. tmux does it with `join-pane`, but binds no key for it; Herdr has `herdr pane move` and no
key at all.

## Approaches

* **Picker, then move (picked).** tmux: `choose-tree -Zw` lists the windows and runs `join-pane` on the one picked.
  Herdr: a `[[keys.command]]` of `type = "popup"` runs a script that lists the tabs and calls `herdr pane move`.
* **Move to the next / previous tab, no picker.** Set aside: with more than two tabs it takes several presses and moves
  the pane through tabs it was not meant for.
* **Ghostty: nothing.** Ghostty 1.4 cannot move a split (no action, no IPC).

## Design

* Key: `Ctrl-b Shift-j` (or `Ctrl-Space Shift-j`) in both; free in both configs. "j" for join.
* Placement, both: to the right of the target tab's focused pane, half of it (tmux `join-pane -h`; Herdr `--split
  right`, Herdr's default ratio 0.5), focus follows the pane into its tab. A tab left without panes closes (tmux closes
  the window, Herdr the tab; seen in Herdr 0.9.5).
* tmux: `bind -N "Move pane into another window" J choose-tree -Zw "join-pane -h -t '%%'"`. Picking the pane's own
  window is tmux's own error message.
* Herdr: `dot_local/bin/executable_herdr-join [PANE_ID]` (pane defaults to `$HERDR_ACTIVE_PANE_ID`, then
  `$HERDR_PANE_ID`), bash + jq, `herdr` from `$HERDR_BIN_PATH`.
  * Lists every tab of every workspace (`herdr tab list`, labels from `herdr workspace list`) except the pane's own tab
    (from `herdr pane layout`): `<workspace label>  <tab number>[: <tab label>]  (<n> panes)`, the label only when it
    is not the number.
  * Picks with fzf when it is installed and stdin is a terminal; otherwise a numbered list on stderr and a number read
    from stdin. An empty choice (fzf `Esc`, or Enter alone) cancels and exits 0.
  * Moves with `herdr pane move PANE --tab TAB --split right --focus`. A tab in another workspace works too (Herdr
    gives the pane a new id there; the program keeps running).
  * Errors (no pane id, no other tab, a choice that is not on the list, Herdr refusing or not answering JSON) print
    `herdr-join: ...` on stderr and exit 1; in a terminal the popup then waits for Enter so the message can be read.
* Herdr popup facts (Herdr 0.9.5, measured in a throwaway `--session`): the popup has a terminal; it gets
  `HERDR_ACTIVE_PANE_ID` / `HERDR_ACTIVE_TAB_ID` of the pane under it, `HERDR_BIN_PATH`, `HERDR_SOCKET_PATH`; it closes
  when the command exits. `herdr tab list` covers every workspace. A move into the pane's own tab answers
  `changed: false, reason: same_tab`; an unknown tab answers `{"error":{"code":"tab_not_found",...}}`.

## Left to the builder

Popup size (Herdr's default), the fzf prompt and colours, the cheatsheet and testing-guide wording.
