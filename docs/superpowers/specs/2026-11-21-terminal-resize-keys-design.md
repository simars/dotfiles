# Terminal Resize and Reload Keys (Plan A) — Design

Short design, approved by the user in conversation on 2026-11-21. Follows
`2026-11-20-terminal-leader-keys-design.md`.

## Intent

After the prefix (`Ctrl-b` / `Ctrl-Space`, tmux and Herdr) or the leader (`Super-b` / `Cmd-b`, Ghostty), the same
letter should do the same thing. Today `r` breaks that (tmux and Herdr reload, Ghostty enters resize mode), Ghostty's
leader has no `Alt+arrows` step resize, and only tmux and Ghostty can make panes equal.

## Approaches (user picked A)

* **A. `r` stays reload.** Ghostty's leader `r` becomes reload; Ghostty's resize mode is entered by leader +
  `Alt+arrows`. tmux and Herdr keys unchanged. Smallest change, lowest conflict risk. **Picked.**
* **B. `r` becomes resize everywhere**, reload moves to `Ctrl+r`; tmux gains a custom resize key table. More change,
  moves a learned habit, adds a mode to tmux.
* `Ctrl+arrows` after the prefix or leader was ruled out for both: macOS takes them (Spaces, Mission Control) before any
  terminal, on mbp-work too.

## Design

| After prefix / leader | tmux | Herdr | Ghostty |
| :--- | :--- | :--- | :--- |
| `r` | reload (unchanged) | reload (unchanged) | `reload_config` (was resize mode) |
| `Alt+arrows` | resize 5 cells, repeats (unchanged) | resize (unchanged) | resize 40 px, then stay in `term_resize` |
| `Shift+e` | equalize, tmux `E` (unchanged) | new: custom command `herdr-equalize` | `equalize_splits`; `=` kept |

* Ghostty `term_resize`: `h j k l` / arrows 20 px (fine), `Alt+arrows` 40 px (coarse, about tmux's 5 cells);
  `Esc` / `Enter` leave; other keys ignored (unchanged).
* `herdr-equalize` (`dot_local/bin/executable_herdr-equalize`): reads `herdr pane layout`, and for each split, outermost
  first, sets its ratio to the share of panes across that axis on its first side (a split along the other axis counts
  its wider side), so every column and row is the same size, like Ghostty's equalize. It sets a ratio with
  `herdr pane resize --amount <delta>` on the pane at the split's boundary, checks the ratio moved, and fails with a
  message otherwise. Herdr moves the split at the named edge of the pane, so a split grows through a pane before its
  boundary (`right` / `down`) and shrinks through one after it (`left` / `up`); Herdr moves a ratio at most 0.5 per
  call, so steps are capped at 0.45 (both found in the final review). Bound as a Herdr `[[keys.command]]` on `prefix+shift+e`.
* Spike (2026-11-21, Herdr 0.9.5, a separate `--session`): `--amount` is a ratio delta on the split at that edge of
  the pane; a 3-column and a 7-pane mixed layout became even; a second run changed nothing. Split ids encode the tree
  path (`split_<n>_<path>`, `root`, then `0` first child / `1` second); the script depends on that, and on jq.
* Docs: cheatsheet (both key tables, the trip points, prefix `Ctrl+arrows` dead on the Macs), AGENTS §4.2,
  FUTURE_CONSIDERATIONS §12, testing guide §9.16.

## Anti-goals

No change to tmux's or Herdr's existing keys; nothing new without a prefix or leader; no Ghostty native key changes.

## Left to the builder

Test wording; the stubbed `herdr` used to test the script.
