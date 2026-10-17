# Design Specification: Modern CLI & Observability Tools

**Date:** 2026-10-17  
**Status:** Approved  
**Target Environments:** macOS Apple Silicon (`arm64`), macOS Intel (`x86_64`), Ubuntu Linux (`amd64`/`arm64`)  
**Dotfiles Manager:** `chezmoi` (`~/.local/share/chezmoi` tracking `git@github.com:simars/dotfiles.git`)

---

## 1. Overview & Goals

This specification outlines the addition of a modern, fast, and ergonomic CLI utility suite across all developer workstations managed by `chezmoi`.

### Core Goals:
1. **Enhanced Terminal Productivity:** Provide modern replacements and companions for traditional Unix utilities (`eza` for `ls`, `bat` for `cat`, `duf`/`dust` for `df`/`du`, `btop` for `top`/`htop`, `jq`/`fx` for JSON processing, and `httpie` for API queries).
2. **Dynamic Previewing (`fp`):** Provide an interactive file-previewing workflow combining `fzf` and `bat` (`alias fp="fzf --preview 'bat --style=numbers --color=always --line-range :500 {}'"`).
3. **Non-Destructive & Guarded Aliasing:** Keep standard POSIX utilities (`ls`, `cat`, `df`, `du`) untouched, while offering intuitive shortcuts (`ll`, `tree`, `preview`, `dfh`, `duh`, `top`, `fp`) conditionally enabled only when the backing tools are present.
4. **Cross-Architecture Resilience:** Guarantee seamless deployment across Apple Silicon (`arm64`), Intel macOS (`x86_64`), and Ubuntu Linux with automatic binary normalization and fallbacks.

---

## 2. Toolset Scope & Architectural Decisions

### 2.1 Included Utilities

| Tool | Purpose | Package Name (Brew) | Package Name (APT) | Primary Use Case |
|---|---|---|---|---|
| **`eza`** | Modern `ls` alternative | `eza` | `eza` / fallback binary | Fast directory listings with Git status and colorized trees |
| **`bat`** | Modern `cat` alternative | `bat` | `bat` (`batcat` symlinked) | Syntax-highlighted file viewing and `fzf` preview backend |
| **`btop`** | Resource & GPU monitor | `btop` | `btop` | Real-time CPU, RAM, disk, network, and GPU/Metal metrics |
| **`duf`** | Disk usage / free utility | `duf` | `duf` | Formatted table replacement for `df -h` |
| **`dust`** | Disk usage tree analyzer | `dust` | `dust` | Graphical disk space tree replacement for `du -sh *` |
| **`httpie`** | Human-friendly HTTP client | `httpie` | `httpie` | Simplified JSON API requests (`http` / `https` commands) |
| **`jq`** | CLI JSON parser/filter | `jq` | `jq` | Scripting, slicing, and filtering JSON streams |
| **`fx`** | Terminal JSON viewer | `fx` | `fx` / fallback binary | Interactive terminal JSON explorer with collapsible tree |

### 2.2 Explicit Exclusions & Handled Dependencies
* **`fd`:** Already managed in `.chezmoidata/packages.toml` under `[darwin.brew].formulae` and `[ubuntu.apt].packages`.
* **`nvtop` (Omitted):** Homebrew recently flagged `nvtop` as deprecated due to an upstream checksum security advisory with scheduled deprecation in 2027. Furthermore, on macOS `btop` already provides native Apple Silicon Metal GPU usage and memory monitoring out of the box. `nvtop` is therefore omitted in favor of standardizing on `btop`.

---

## 3. Package Management & Platform Normalization

### 3.1 Declarative Package Registry (`.chezmoidata/packages.toml`)
The tools will be added to the declarative package lists:

```toml
[darwin.brew]
formulae = [
    # Existing formulae...
    "bat",
    "btop",
    "duf",
    "dust",
    "eza",
    "fx",
    "httpie",
    "jq",
    # ...
]

[ubuntu.apt]
packages = [
    # Existing packages...
    "bat",
    "btop",
    "duf",
    "dust",
    "httpie",
    "jq",
    # ...
]
```

### 3.2 Platform Normalization & Binary Fallbacks (`run_onchange_before_00_install_packages.sh.tmpl`)

1. **Debian/Ubuntu Binary Normalization:**
   Debian packages rename `bat` to `batcat` to prevent name collision. The bootstrap script will normalize this automatically:
   ```bash
   if command -v batcat &> /dev/null && ! command -v bat &> /dev/null; then
       mkdir -p "$HOME/.local/bin"
       ln -sf "$(command -v batcat)" "$HOME/.local/bin/bat"
   fi
   ```
2. **Intel macOS Tier 3 Protection:**
   Because `HOMEBREW_NO_BOTTLE_SOURCE_FALLBACK=1` is enforced on macOS, Homebrew skips unbottled formulae on Intel macOS rather than locking into source compilation. The script ensures standalone precompiled GitHub release binaries download into `~/.local/bin` for any formula skipped by Homebrew on legacy architectures.

---

## 4. Shell Integration & Aliasing (`dot_aliases`)

All aliases will be placed in `dot_aliases` (sourced by `.zshrc`), guarded with `command -v` to ensure zero broken aliases in restricted or minimal environments:

```bash
# ==============================================================================
# Modern CLI Tool Enhancements
# ==============================================================================

# eza: Modern directory listing with git status & icons
if command -v eza &> /dev/null; then
    alias ll="eza -la --icons --git"
    alias lt="eza --tree --level=2 --icons"
    alias ltree="eza --tree --icons"
fi

# bat: Syntax-highlighted viewer & dynamic interactive preview
if command -v bat &> /dev/null; then
    alias preview="bat"
    if command -v fzf &> /dev/null; then
        # Preview files dynamically using fzf and bat as you type
        alias fp="fzf --preview 'bat --style=numbers --color=always --line-range :500 {}'"
    fi
fi

# duf: Human-friendly disk usage table
if command -v duf &> /dev/null; then
    alias dfh="duf"
fi

# dust: Visual disk usage tree
if command -v dust &> /dev/null; then
    alias duh="dust"
fi

# btop: Resource & GPU monitor
if command -v btop &> /dev/null; then
    alias top="btop"
fi
```

### Invariants Preserved:
* POSIX `ls`, `cat`, `df`, `du`, and standard `fzf` are left completely untouched.
* `jq`, `httpie` (`http`), and `fx` are invoked directly by their native binary names without wrapper aliases.

---

## 5. Verification Matrix & Testing Plan

### 5.1 Verification Checklist (`zsh -lic`)
```bash
# 1. Binary availability
which eza bat btop duf dust http jq fx

# 2. Version outputs
eza --version | head -n 1
bat --version
btop --version
duf --version
dust --version
http --version
jq --version
fx --version

# 3. Alias verification
type fp ll lt ltree preview dfh duh top

# 4. Interactive pipeline sanity check
head -n 20 ~/.zshrc | bat --style=numbers --color=always
```

### 5.2 Rollout Stages
1. **Primary Workstation (Apple Silicon Mac Studio `arm64`):**
   * Apply changes via `chezmoi apply -v`.
   * Verify all 8 formulae install cleanly via Homebrew bottles.
   * Test `fp` and aliases in a fresh shell.
2. **Secondary Intel Workstation (`simars-macbook-16i` `x86_64`):**
   * Pull and execute `chezmoi apply -v` over SSH.
   * Verify all binaries and aliases.
3. **Tertiary Intel Workstation (`simars-macbook-32i` `x86_64`):**
   * Pull and execute `chezmoi apply -v` over SSH.
   * Verify all binaries and aliases.
4. **Documentation & Skill Sync:**
   * Update `docs/WORKSTATION_MIGRATION_RUNBOOK.md`.
   * Update `docs/TESTING_AND_VERIFICATION_GUIDE.md`.
   * Update `dot_agents/skills/dotfiles-workstation-migration/SKILL.md` and `~/.agents/skills/dotfiles-workstation-migration/SKILL.md`.
   * Run Gitleaks pre-commit validation and push to `origin/main`.
