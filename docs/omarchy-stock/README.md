# Omarchy stock configs (snapshots)

Copies of the stock files the shared tmux and Herdr configs were merged from, taken from omarchy 4.5.0-3
(`/usr/share/omarchy/config/tmux/tmux.conf`, `/usr/share/omarchy/config/herdr/config.toml`).

`run_after_95_omarchy_stock_drift.sh.tmpl` compares Omarchy's current stock files with these on every apply on
Omarchy and prints the difference when an Omarchy update changed them. It never fails the apply. When it reports a
change: merge what is wanted into `dot_config/tmux/tmux.conf` or `dot_config/herdr/config.toml.tmpl`, then copy the
new stock file here in the same commit.

## shell/

Omarchy's shell helpers and zsh options, taken from omarchy 4.5.0-3 and omarchy-zsh 1.5.0-2:
`/usr/share/omarchy/default/bash/aliases`, `default/bash/fns/{compression,herdr,ssh-port-forwarding,tmux,worktrees}`
and `/usr/share/omarchy-zsh/shell/zoptions`. `dot_config/zsh/shared-helpers.zsh.tmpl` builds the helper file for hosts
without Omarchy from them (zoptions: only its fzf key block). The same drift report covers them. When one changes:
look at the change (a new alias may clash with a Mac command; see `docs/ZSH_UNIFICATION.md`), adjust the removals in
the template if needed, then copy the new file here.
