# Agentic Maintenance Instructions & Repository Invariants

> **Audience:** Autonomous AI coding agents (Antigravity, Claude Code, Cursor, Codex, etc.) and human developers maintaining these dotfiles.

---

## 1. Repository Identity & Purpose

This repository contains multi-machine, cross-platform workstation dotfiles managed via [chezmoi](https://www.chezmoi.io/). It provides deterministic developer environment bootstrapping, shell configuration, and runtime tooling across:
- **macOS Apple Silicon (`arm64`)**: Primary modern Mac workstations (e.g. Mac Studio, Apple Silicon MacBook Pro). Homebrew lives in `/opt/homebrew`.
- **macOS Intel (`x86_64`)**: Legacy Intel Mac hardware (e.g. 16" and 32GB MacBook Pro). Homebrew lives in `/usr/local`.
- **Ubuntu Linux (`amd64` / `arm64`)**: Linux servers, cloud instances, and devcontainers.

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

### 3.2 Non-Destructive Aliases
- **Invariant:** Never overwrite standard POSIX utility binaries (`ls`, `cat`, `df`, `du`, `top`) with hard unaliased overrides that alter default POSIX flags or output formatting.
- **Modern Replacements:**
  - `bat` is surfaced via `preview` and `fp` (fzf preview), never aliased directly over `cat`.
  - `eza` is surfaced via `ll`, `lt`, and `ltree`, never aliased over `ls` without fallback.
  - `duf` is aliased to `dfh` (preserving `df`).
  - `dust` is aliased to `duh` (preserving `du`).
  - `btop` is aliased to `top` only when guarded with `if command -v btop &> /dev/null`.
- **Guarded Execution:** Every modern tool alias must be wrapped in `if command -v <tool> &> /dev/null` guards in `dot_aliases`.

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

### 4.1 macOS Intel (`x86_64`) Tier 3 Homebrew Deprecation
- Intel macOS (macOS 26+) is classified as Tier 3 / deprecated in Homebrew.
- **Do Not Compile from Source:** Homebrew 7 on Intel builds any formula that has no bottle (its "no bottle available" refusal only applies to arm64 CPUs), and `HOMEBREW_NO_BOTTLE_SOURCE_FALLBACK` no longer exists (it only covered failed bottle downloads, and the install script still exports it as a no-op). One apply compiled `llvm`, `rust` and `node` for 7 hours. On Intel the install script therefore runs `brew bundle --no-upgrade` through `brew_bundle_bottled_only`, which drops every formula that is not installed and whose runtime dependencies are not all bottled (any non-arm64 tag) or installed and current, prints the reason for each skip, and keeps only already-installed formulae if Homebrew cannot be queried. Do not bypass it with `brew install --build-from-source` unless the user asks.
- **Standalone Binary Fallback:** For unbottled or failing Rust/C++/Go packages (`bat`, `dust`, `fx`, `mise`, `age`, `starship`), provision or instruct fallback to precompiled standalone binaries installed into `~/.local/bin`.
- **Exception, `git`:** No precompiled git exists for Intel macOS, Intel Homebrew has no git bottle, and Xcode 27 (Apple git 2.54) is Apple silicon only. The install script therefore builds a pinned git from source into `~/.local` on Intel Macs (checksum verified, `NO_RUST=YesPlease NO_GETTEXT=YesPlease NO_TCLTK=YesPlease`, about a minute). This is outside Homebrew, so the "do not compile" rule above is unaffected. The post-apply check treats `/usr/bin/git` as a warning on Intel and as a failure on Apple silicon.

### 4.2 macOS Apple Silicon (`arm64`)
- Homebrew prefix is `/opt/homebrew`.
- Precompiled bottles are fully supported and preferred.

### 4.3 Ubuntu Linux (`amd64` / `arm64`)
- Package names occasionally differ from Homebrew formula names:
  - `bat` on Debian/Ubuntu is installed as `batcat`. Normalize `batcat` -> `bat` via a symlink in `~/.local/bin/bat`.
  - Package manager is APT (`apt-get install -y`).

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
