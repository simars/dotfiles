# Omarchy stock configs (snapshots)

Copies of the stock files the shared tmux and Herdr configs were merged from, taken from omarchy 4.5.0-3
(`/usr/share/omarchy/config/tmux/tmux.conf`, `/usr/share/omarchy/config/herdr/config.toml`).

`run_after_95_omarchy_stock_drift.sh.tmpl` compares Omarchy's current stock files with these on every apply on
Omarchy and prints the difference when an Omarchy update changed them. It never fails the apply. When it reports a
change: merge what is wanted into `dot_config/tmux/tmux.conf` or `dot_config/herdr/config.toml.tmpl`, then copy the
new stock file here in the same commit.
