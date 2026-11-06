# Agentic Maintenance Instructions & Repository Invariants

> **Audience:** Autonomous AI coding agents (Antigravity, Claude Code, Cursor, Codex, etc.) and human developers maintaining these dotfiles.

---

## 1. Repository Identity & Purpose

This repository contains multi-machine, cross-platform workstation dotfiles managed via [chezmoi](https://www.chezmoi.io/). It provides deterministic developer environment bootstrapping, shell configuration, and runtime tooling across:
- **macOS Apple Silicon (`arm64`)**: Primary modern Mac workstations (e.g. Mac Studio, Apple Silicon MacBook Pro). Homebrew lives in `/opt/homebrew`.
- **macOS Intel (`x86_64`)**: Legacy Intel Mac hardware (e.g. 16" and 32GB MacBook Pro). Homebrew lives in `/usr/local`. Dotfiles only; tools by hand (`docs/INTEL_MACS.md`).
- **Linux (Omarchy)**: dotfiles, plus the few packages listed for it, installed with Omarchy's own commands; Omarchy keeps its own configs except tmux and Herdr (section 4.2).

---

## 2. Mandatory Invariant: Cheatsheet Maintenance

> [!IMPORTANT]
> **Cheatsheet Synchronization is Non-Negotiable.**
> Whenever any package, CLI utility, shell alias, git shortcut, runtime tool, or workflow is **added, modified, or removed**, the agent **MUST** update [`docs/CHEATSHEET.md`](file:///Users/simars/.local/share/chezmoi/docs/CHEATSHEET.md) within the **same commit or task**.

### Rules for Cheatsheet Maintenance:
1. **Single Source of Truth:** `docs/CHEATSHEET.md` is the canonical reference. `dot_cheatsheet.md.tmpl` renders this file directly to `~/.cheatsheet.md`.
2. **Atomic Commits:** Never submit code changes (e.g., in `dot_aliases`, `.chezmoidata/packages.toml`, `dot_zshrc.tmpl`) without the corresponding documentation in `docs/CHEATSHEET.md`.
3. **Verification Before Completion:**
   - Always execute `cheat` (or `cheatsheet`) in a subshell to verify proper rendering:
     ```bash
     zsh -c 'source dot_aliases && cheat | head -n 30'
     ```
   - Ensure markdown table columns, code blocks, and descriptions are cleanly formatted and parse properly with `bat`, `less`, and `cat`.

---

## 3. Core Architectural Invariants

Agents must strictly uphold these architectural guarantees at all times:

### 3.1 Preserve Legacy Bare-Repo Helper
- **Invariant:** Never remove, break, or redefine the legacy bare-repo helper alias:
  ```bash
  alias config='/usr/bin/git --git-dir=$HOME/.cfg/ --work-tree=$HOME'
  ```
- **Rationale:** Legacy scripts, historical commits, and manual recovery workflows rely on this alias to interact with the raw `~/.cfg` repository.
- **Companion script:** `dot_local/bin/executable_config` runs the same command for shells without the alias: Claude Code's bash (`CLAUDE_CODE_SHELL`, set in `dot_zprofile.tmpl`) and any non-interactive zsh, where `dot_zshrc.tmpl` removes all aliases (§3.2). Keep the two in step. Never add aliases to `dot_bashrc`: Claude Code replays them into every command, and an alias also blocks a function of the same name.

### 3.2 Non-Destructive Aliases
- **Invariant:** Never overwrite standard POSIX utility binaries (`ls`, `cat`, `df`, `du`, `top`) with hard unaliased overrides that alter default POSIX flags or output formatting.
- **Modern Replacements:**
  - `bat` is surfaced via `preview` and `fp` (fzf preview), never aliased directly over `cat`.
  - `eza` is surfaced via `ll`, `lt`, and `ltree`, never aliased over `ls` without fallback.
  - `duf` is aliased to `dfh` (preserving `df`).
  - `dust` is aliased to `duh` (preserving `du`).
  - `btop` is aliased to `top` only when guarded with `if command -v btop &> /dev/null`.
- **Guarded Execution:** Every modern tool alias must be wrapped in `if command -v <tool> &> /dev/null` guards in `dot_aliases`.
- **Interactive Shells Only:** `dot_zshrc.tmpl` ends with `unalias -a` when the shell is not interactive. Claude Code sources `~/.zshrc` in a non-interactive login shell and replays its aliases into every command, where they change commands and block functions of the same name. Anything a non-interactive shell needs must be a script on `PATH` or a function, never an alias.
- **Exception, GNU userland on macOS (`userland`):** `dot_zshrc.tmpl` defines `userland gnu|apple|gnu-path` and runs it last, after `~/.zshrc.local`, with `MACOS_USERLAND` or `gnu` as the mode. `gnu` aliases each native command that `coreutils`, `findutils`, `gawk`, `gnu-sed`, `gnu-tar`, `grep` and `make` also provide (`ls` to `gls`, `sed` to `gsed`; about 89, never shell builtins) in interactive shells only, and rewrites self-referencing aliases such as `mkdir="mkdir -p"` to the GNU tool; `apple` undoes that; `gnu-path` puts the `gnubin` directories first on `PATH` for the current shell. These are the only sanctioned replacements of `ls`, `cat`, `df` and `du`. Never put a `gnubin` directory on `PATH` unconditionally: child processes inherit it, and macOS scripts that branch on `$OSTYPE` and then use BSD flags (`sed -i ''`, `stat -f`, `date -v`, `base64 -D`, `mktemp -t`) break; a local script did, on `stat -f %m`. Keep the formula list explicit: `libtool` ships a `gnubin` too, and GNU `libtool` in place of Apple's `/usr/bin/libtool` breaks Xcode builds. Scripts in this repository must work with either variant: try the GNU form first and fall back (`stat -c %Y f 2>/dev/null || stat -f %m f`), because GNU `stat -f` prints filesystem information and fails, so a BSD-first fallback appends to that output.
- **Same-name upgrades:** Homebrew's `bash` (5.x) and `rsync` (3.x) precede Apple's bash 3.2 and `openrsync` by `PATH` order; `/bin/bash` and `/usr/bin/rsync` remain for anything that names them.

### 3.2a No URL Rewrites in Git
- **Invariant:** `dot_gitconfig.tmpl` sets no `url.*.insteadOf`. The GitHub https-to-ssh rewrite it once had made every fetch need an unlocked SSH key: `brew update` failed on the Intel Macs, and on Omarchy LazyVim's plugin updates would have. Repositories store SSH URLs instead (`git remote set-url origin git@github.com:<owner>/<repo>.git`), and `gh config set git_protocol ssh` makes `gh repo clone` do the same.

### 3.3 Local Override Precedence
- **Invariant:** Never modify, overwrite, delete, or commit machine-local override files:
  - `~/.aliases.local`
  - `~/.zshrc.local`
  - `~/secrets.env`
  - any work-specific env file that `~/.zshrc.local` sources
- **Rationale:** These files are strictly reserved for uncommitted host-specific overrides, employer-specific configurations, and local credentials. Dotfiles templates source these files at the very end of their respective configurations to guarantee local precedence.
- **No work identifiers in this repository:** it is public. Do not write work organisation names, work email addresses or the paths of work-specific files into any tracked file, message or commit. Refer to them generically ("the work orgs", "the work email") and keep the specifics in `~/.zshrc.local` and `~/.gitconfig.local`.

### 3.4 Zero Secret Leaks & Gitleaks Enforcement
- **Invariant:** Every commit must pass `gitleaks` scanning with 0 findings.
- **Rule:** Never commit raw API tokens, passwords, private keys, or credentials into repository files or templates.
- **Verification:** Run Gitleaks before committing:
  ```bash
  gitleaks detect --source ~/.local/share/chezmoi -v
  ```

---

## 4. Platform Specifics & Multi-Architecture Rules

### 4.1 Packages: Apple Silicon and Omarchy
- **Apple silicon Macs** (Homebrew in `/opt/homebrew`) get `brew bundle --no-upgrade` with `.chezmoidata/packages.toml`, then LunarVim, from `run_onchange_before_00_install_packages.sh.tmpl`. Omarchy gets its own short list (below). Every other host gets dotfiles only and a one-line skip message.
- **Intel Macs** (`x86_64`, Homebrew in `/usr/local`, Tier 3 in Homebrew) are set up by hand with `docs/INTEL_MACS.md`: Homebrew 7 on Intel compiles any formula without an Intel bottle (one apply built `llvm`, `rust` and `node` for 7 hours), and the automation that avoided it (a bottled-only `brew bundle` filter, standalone binary fallbacks, a from-source git) cost more than it saved. Never automate package installs there again, and never `brew install` a formula the guide's check reports as `compile`.
- **Omarchy** installs only the packages in `[omarchy]` of `packages.toml`, only with `omarchy pkg add` and `omarchy pkg aur add` (never `pacman`, `yay`, `apt` or downloaded binaries), and only when stdin and stdout are a terminal, because they need the sudo password; otherwise the script prints the command and exits 0. The requirement check warns about listed packages still missing. Runtimes come from `omarchy install dev-env <lang>`, never from this repository.
- **Other Linux hosts** (no Ubuntu host uses this repository) bring their own packages. The Ubuntu bootstrap was removed on 2026-10-30; if an Ubuntu host joins, add a branch for it rather than reviving the old one, which was never run.

### 4.2 Omarchy
- **Omarchy owns its configs:** on Omarchy (`.chezmoi.osRelease.id` is `omarchy`), `.chezmoiignore` leaves Omarchy's Neovim files, `~/.config/alacritty`, `~/.config/starship.toml`, `~/.config/mise/config.toml` (and the `mise install` script) and `mise-audit` alone. Ignore **exact files or file patterns**, never a directory you need one file from: gitignore-style negation cannot undo an ignored parent directory. Never manage an Omarchy-shipped config there unless it is merged on purpose (below).
- **Files chezmoi adds on Omarchy:** `~/.config/nvim/lua/plugins/shared.lua` is the only Neovim file (line endings, Go parsers). mise there is Omarchy's by default: `omarchy_mise_project_settings` in `.chezmoidata/omarchy.toml` is `false` (option A), so `dot_config/mise/conf.d/50-shared.toml.tmpl` renders empty and chezmoi deletes any earlier copy; `true` (option B) deploys it with the version-file and uv settings, and no tools (Omarchy's `node = latest` must win). Neither option sets `go.set_gobin = false` (bash there never puts `~/go/bin` on `PATH`; Go tools go in with `mise use -g go:<module>`). `python.default_packages_file` is gone on every host (replaced by python's postinstall hook in `config.toml`, which Omarchy does not get). To switch, change that one value; the cheatsheet's "mise on Omarchy" has the steps. Tests assert both options and the Neovim set exactly.
- **Merged on purpose: tmux and Herdr.** `dot_config/tmux/tmux.conf` and `dot_config/herdr/config.toml.tmpl` are one config on every host, merged from Omarchy's stock files (`docs/omarchy-stock/`) and the Mac's keys; Herdr's look stays per platform, and Omarchy's block must keep `window_title` (Hyprland's group bar) and its `[theme.custom]`. `run_after_95_omarchy_stock_drift.sh` reports when an Omarchy update changes a stock file: merge the change, then refresh the snapshot in the same commit.
- **Shared configs on Omarchy:** `~/.gitconfig` there keeps every Omarchy setting in `~/.config/git/config` (git reads both) and sets no `core.editor`, so git follows Omarchy's `$EDITOR`. `~/.aliases` is sourced at the end of `~/.bashrc`, after Omarchy's aliases, so never redefine an Omarchy name there unguarded (`lt` is defined only when missing). The requirement check suggests `omarchy pkg add` fixes there (`pacman` on Arch) and treats mise on Omarchy as Omarchy's, so it does not compare its version.
- **Check without the host:** `tests/host-profiles.sh` (run by CI on every push) renders the repository as an Apple silicon Mac, an Intel Mac, Omarchy, Arch, Ubuntu and Debian with `chezmoi --override-data` and fails if a rule above breaks. Add new platform rules to it. `tests/host-profiles.sh --base main` also reports each `run_onchange_` script whose macOS or Ubuntu render changed: hosts like that re-run it on their next apply, so a change meant for one platform must leave the others byte-identical.

---

## 5. Development & Verification Workflow

When performing tasks in this repository, follow this execution sequence:

1. **Check Status & Plan:**
   Inspect current state and pending template diffs before making edits:
   ```bash
   chezmoi status
   ```
2. **Apply Changes with Diff First:**
   Always inspect template output before applying changes to the live `$HOME`:
   ```bash
   chezmoi diff
   chezmoi apply -v
   ```
3. **Verify Shell & Subshell Compatibility:**
   Test aliases and functions in both `zsh` and POSIX shells:
   ```bash
   zsh -c 'source dot_aliases && cheat | head -n 20'
   ```
4. **Update Cheatsheet:**
   If any command, tool, or alias was touched, update `docs/CHEATSHEET.md`.
5. **Run Security Scanner:**
   Verify no secrets were introduced:
   ```bash
   gitleaks detect --source ~/.local/share/chezmoi -v
   ```
