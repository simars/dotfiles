# zsh on the Macs and on Omarchy: what is unified and what is still open

zsh at the prompt behaves the same on the Macs and on Omarchy: vi keys, the same options, completion, history
suggestions, syntax highlighting, `ls`, and Omarchy's helpers and fzf keys (cheatsheet: "zsh Line Editor" and
"Omarchy's Helpers on Every Host"). This file records the differences that are left, with a recommendation each, so
they can be decided later. Nothing here is implemented yet.

Status: open (written 2026-11-15).

## Done (for reference)

| What | How |
| :--- | :--- |
| vi keys, options, Tab menu, prefix history search, plugins | `dot_zshrc.tmpl` section 5a, every host |
| `ls` | the system `ls --color=auto` everywhere (Omarchy's eza `ls` replaced on purpose) |
| `$VAR<Tab>` | turned back on on Omarchy (its zsh options disable it); Ctrl+Alt+V works too |
| Omarchy's helpers and Ctrl+Alt+F/L/V on the Macs | `dot_config/zsh/shared-helpers.zsh.tmpl`, generated from `docs/omarchy-stock/shell/` |
| Ctrl+Alt+F on Omarchy | Omarchy's widget kept as `fzf-find-files-widget` (fzf's setup replaced it before) |
| man pages through bat | Macs too |

## Group 2: name clashes, no side effects either way

| # | Clash | Options | Recommendation |
| :--- | :--- | :--- | :--- |
| 2a | `r`: Omarchy aliases it to `rails`; in zsh `r` is a builtin that repeats the last command. Omarchy has already lost the builtin; the Macs keep it. | rails everywhere, or the builtin everywhere (unalias `r` on Omarchy) | **rails everywhere.** The Rails aliases (`b`, `s`, `migrate`) are already shared, and Up then Enter repeats a command. Change: drop `r` from the `unalias` line in the helpers template. |
| 2b | `compress`: Omarchy's helper makes `<dir>.tar.gz`; macOS has `/usr/bin/compress` (LZW `.Z`, obsolete). | Omarchy's everywhere, or keep Apple's on the Macs | **Omarchy's everywhere.** Only typed commands change; scripts still get `/usr/bin/compress` (`command compress` too). Change: drop `compress` from the `unfunction` line. |
| 2c | Prompt: Omarchy owns its `~/.config/starship.toml` (chezmoi must not manage it there); the Macs get chezmoi's `dot_config/starship.toml.tmpl`. | Omarchy's look on the Macs too (render the Mac file from a snapshot of Omarchy's, covered by the drift report), or keep two looks | **Omarchy's look on the Macs.** Visual only. Check first that it needs nothing Linux-only and that the Mac fonts have its glyphs (JetBrains Mono Nerd Font is installed). |
| 2d | `EDITOR`: Omarchy's launcher (`omarchy-launch-editor`, opens nvim) vs `nvim` | — | **Leave.** Both open nvim; the launcher does not exist on macOS. |

## Group 3: choices with side effects

| # | Item | Side effects | Options | Recommendation |
| :--- | :--- | :--- | :--- | :--- |
| 3a | `cd` as zoxide (Omarchy's `zd`): `cd dir` when it exists, else jump with zoxide and print the path. Omarchy only today. | A typo in `cd` jumps to some other folder instead of failing. zsh's `cd -2`, `cd +1` (directory stack) and `cd old new` (swap part of the path) stop working; `cd -P` and `cd -q` are taken as zoxide queries. Scripts are not affected (alias). | (i) adopt on the Macs; (ii) drop on Omarchy (`unalias cd` after its aliases), keeping `z`; (iii) keep the difference | **(ii) drop on Omarchy.** `cd` stays predictable everywhere and `z`/`zi` are one letter away. |
| 3b | Reconnecting `ssh` (Omarchy's `ssh-reconnect`): when an interactive session that lasted 30 s or more drops with exit code 255, it loops "Reconnecting (Ctrl-C to stop)". Omarchy only today. | Applies to typed `ssh` only (scripts, `ssh -f` forwards and `ssh host cmd` without a terminal are left alone). zsh misreads the function, so on Omarchy it runs in bash; the Macs would need the same wrapper, with Homebrew's bash. A deliberately ended session that exits 255 would reconnect until Ctrl-C. | adopt on the Macs, or keep the difference | **Adopt on the Macs.** The trigger is narrow, and the Macs are the ones that SSH into works. Add `ssh-reconnect` to the snapshots and the same `_omarchy_bash`-style wrapper (named without "omarchy") in the helpers template. |
| 3c | GNU tools: the Macs alias them at the prompt (`userland gnu`), Omarchy has them natively. | `userland gnu-path` (GNU first on `PATH`) also reaches scripts, and macOS scripts that use BSD flags break. | — | **Leave.** At the prompt they already behave the same. |
| 3d | Login shell: zsh on the Macs, bash on Omarchy (the hand-over starts zsh in terminals). | Changing either changes what scripts, `ssh host 'cmd'` and (on Omarchy) the desktop session run. | — | **Leave.** |
| 3e | `~/.zshrc.local` (dotfiles-local) is wired on the Macs only. | Wiring it on Omarchy would bring Homebrew and Mac paths to Linux. | — | **Leave.** |

## Known small differences inside the shared helpers

- `lip` uses `pgrep -af`; macOS `pgrep` lists only the PIDs (`-a` means something else there). Use `pgrep -lf 'ssh.*-L'`
  on a Mac to see the commands.
- `sff` uses GNU `find -printf`; on the Macs the generated helper calls `gfind` (coreutils' findutils) when installed.
- `rsw`, `lsw`, `dsw` (rsync on change) need `inotifywait` and `setsid` and are left out on the Macs.

## How to apply a decision

Each item is a small change to `dot_zshrc.tmpl` or `dot_config/zsh/shared-helpers.zsh.tmpl`, plus tests in
`tests/host-profiles.sh` and the cheatsheet, then a live check on works and on a Mac. Update this file in the same
commit: move the item to "Done".
