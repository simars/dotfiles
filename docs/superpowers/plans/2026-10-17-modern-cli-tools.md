# Modern CLI & Observability Tools Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Integrate a modern CLI and observability toolset (`bat`, `btop`, `duf`, `dust`, `eza`, `fx`, `httpie`, `jq`) with guarded non-destructive aliases (including dynamic `fzf` + `bat` preview `fp`) across Apple Silicon, Intel macOS, and Ubuntu Linux via `chezmoi`.

**Architecture:** Declarative package declarations in `.chezmoidata/packages.toml`, automatic binary normalization (e.g. `batcat` -> `bat`) and Tier 3 Intel macOS standalone fallbacks in `run_onchange_before_00_install_packages.sh.tmpl`, non-destructive aliases guarded with `command -v` in `dot_aliases`, and multi-machine verification across Apple Silicon and Intel hosts.

**Tech Stack:** `chezmoi`, Homebrew (`darwin.brew`), APT (`ubuntu.apt`), Zsh, `fzf`, `bat`, `btop`, `duf`, `dust`, `eza`, `fx`, `httpie`, `jq`, `gitleaks`.

## Global Constraints

- **Preserve Legacy Invariants:** Bare repo `~/.cfg`, local environment files (`~/.aliases.local`, `~/.zshrc.local`, `~/secrets.env`, `~/dotfiles-local/`), and standard POSIX builtins (`ls`, `cat`, `df`, `du`) must remain intact.
- **Security & Secret Protection:** Every commit must pass Gitleaks pre-commit scanning (`gitleaks protect --staged`).
- **Intel Mac Tier 3 Protection:** Enforce `HOMEBREW_NO_BOTTLE_SOURCE_FALLBACK=1` and `--no-upgrade` during Homebrew operations to prevent long source builds on deprecated architectures.
- **Headless SSH Optimization:** Ensure `StrictHostKeyChecking accept-new` and SSH agent forwarding (`ssh -A`) are respected during remote operations.

---

### Task 1: Package Registry Declarations

**Files:**
- Modify: `.chezmoidata/packages.toml`

**Interfaces:**
- Consumes: Existing `.chezmoidata/packages.toml`
- Produces: Declarative formulae in `[darwin.brew].formulae` and packages in `[ubuntu.apt].packages`

- [ ] **Step 1: Inspect current packages.toml**
  Run: `chezmoi data | grep -A 25 "darwin"`
  Expected: JSON/TOML output displaying current brew formulae.

- [ ] **Step 2: Add modern CLI tools to packages.toml**
  Add `"bat"`, `"btop"`, `"duf"`, `"dust"`, `"eza"`, `"fx"`, `"httpie"`, `"jq"` to `[darwin.brew].formulae`.
  Add `"bat"`, `"btop"`, `"duf"`, `"dust"`, `"httpie"`, `"jq"` to `[ubuntu.apt].packages`.
  Ensure alphabetical sorting and formatting match existing conventions.

- [ ] **Step 3: Verify template syntax with chezmoi diff**
  Run: `chezmoi diff`
  Expected: Diff shows updated package hash and added packages in `00_install_packages.sh`.

- [ ] **Step 4: Commit changes**
  Run:
  ```bash
  git -C ~/.local/share/chezmoi add .chezmoidata/packages.toml
  git -C ~/.local/share/chezmoi commit -m "feat(packages): add modern CLI tools to package definitions"
  ```
  Expected: Gitleaks scan passes (0 leaks), commit created.

---

### Task 2: Platform Normalization & Fallbacks

**Files:**
- Modify: `run_onchange_before_00_install_packages.sh.tmpl`

**Interfaces:**
- Consumes: `packages.toml` hash, OS and architecture template variables
- Produces: Standalone binary fallbacks and symlinks in `~/.local/bin`

- [ ] **Step 1: Add Debian/Ubuntu batcat normalization**
  In `run_onchange_before_00_install_packages.sh.tmpl` (under `{{ else if eq .chezmoi.os "linux" -}}`), add:
  ```bash
  # Normalize batcat binary name to bat on Debian/Ubuntu
  if command -v batcat &> /dev/null && ! command -v bat &> /dev/null; then
      mkdir -p "$HOME/.local/bin"
      ln -sf "$(command -v batcat)" "$HOME/.local/bin/bat"
  fi
  ```

- [ ] **Step 2: Add standalone fallbacks for eza and fx on Linux**
  Add standalone binary checks if `eza` or `fx` are missing from apt on Linux:
  ```bash
  if ! command -v eza &> /dev/null; then
      echo "==> Installing eza fallback..."
      EZA_ARCH="{{ if eq .chezmoi.arch "arm64" }}aarch64{{ else }}x86_64{{ end }}"
      curl -fsSL "https://github.com/eza-community/eza/releases/latest/download/eza_${EZA_ARCH}-unknown-linux-gnu.tar.gz" | tar -xz -C "$HOME/.local/bin" eza 2>/dev/null || true
  fi

  if ! command -v fx &> /dev/null; then
      echo "==> Installing fx fallback..."
      FX_ARCH="{{ if eq .chezmoi.arch "arm64" }}arm64{{ else }}amd64{{ end }}"
      curl -fsSL "https://github.com/antonmedv/fx/releases/latest/download/fx_linux_${FX_ARCH}" -o "$HOME/.local/bin/fx" 2>/dev/null || true
      chmod +x "$HOME/.local/bin/fx" 2>/dev/null || true
  fi
  ```

- [ ] **Step 3: Verify script compilation with chezmoi diff**
  Run: `chezmoi diff`
  Expected: Clean diff with rendered shell scripts for both Darwin and Linux sections.

- [ ] **Step 4: Commit changes**
  Run:
  ```bash
  git -C ~/.local/share/chezmoi add run_onchange_before_00_install_packages.sh.tmpl
  git -C ~/.local/share/chezmoi commit -m "feat(bootstrap): add binary normalization and fallbacks for modern CLI tools"
  ```
  Expected: Gitleaks scan passes (0 leaks), commit created.

---

### Task 3: Shell Aliases & Dynamic FZF Preview

**Files:**
- Modify: `dot_aliases`

**Interfaces:**
- Consumes: Shell environment, presence of `eza`, `bat`, `fzf`, `duf`, `dust`, `btop`
- Produces: Guarded aliases (`ll`, `lt`, `ltree`, `preview`, `fp`, `dfh`, `duh`, `top`)

- [ ] **Step 1: Write failing alias test in a test subshell**
  Run: `zsh -lic 'type fp 2>/dev/null || echo "MISSING_FP"'`
  Expected: `MISSING_FP`

- [ ] **Step 2: Add guarded aliases to dot_aliases**
  Append to `dot_aliases`:
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

- [ ] **Step 3: Verify chezmoi diff on aliases**
  Run: `chezmoi diff dot_aliases`
  Expected: Shows addition of modern aliases.

- [ ] **Step 4: Commit changes**
  Run:
  ```bash
  git -C ~/.local/share/chezmoi add dot_aliases
  git -C ~/.local/share/chezmoi commit -m "feat(aliases): add guarded modern CLI aliases and dynamic fzf preview fp"
  ```
  Expected: Gitleaks scan passes (0 leaks), commit created.

---

### Task 4: Apple Silicon Deployment & Verification

**Files:**
- Apply: active `$HOME` on `Simars-MacBook-Pro-13.local` (`arm64`)

**Interfaces:**
- Consumes: Templates in `~/.local/share/chezmoi`
- Produces: Installed binaries in `/opt/homebrew/bin` and updated `~/.aliases`

- [ ] **Step 1: Execute live apply on Apple Silicon**
  Run: `chezmoi apply -v`
  Expected: Homebrew bundles `bat`, `btop`, `duf`, `dust`, `eza`, `fx`, `httpie`, `jq`. Exit code 0.

- [ ] **Step 2: Verify binary availability and versions**
  Run:
  ```bash
  zsh -lic '
  which eza bat btop duf dust http jq fx
  eza --version | head -n 1
  bat --version
  btop --version
  duf --version
  dust --version
  http --version
  jq --version
  fx --version
  '
  ```
  Expected: All 8 binaries present in `/opt/homebrew/bin` (or `~/.local/bin`), exit code 0.

- [ ] **Step 3: Verify alias resolution**
  Run:
  ```bash
  zsh -lic 'type fp ll lt ltree preview dfh duh top'
  ```
  Expected: All aliases defined and mapped to respective tools.

- [ ] **Step 4: Test dynamic bat formatting**
  Run: `head -n 20 ~/.zshrc | bat --style=numbers --color=always`
  Expected: Formatted, numbered, colored output rendered to stdout without errors.

- [ ] **Step 5: Push verified commits to GitHub**
  Run: `git -C ~/.local/share/chezmoi push origin main`
  Expected: Successfully pushed to `git@github.com:simars/dotfiles.git`.

---

### Task 5: Remote Intel macOS Deployment & Verification

**Files:**
- Apply: `simars-macbook-16i` (`x86_64`) and `simars-macbook-32i` (`x86_64`)

**Interfaces:**
- Consumes: Remote repository updates on `main` via SSH agent forwarding (`ssh -A`)
- Produces: Installed binaries and aliases on Intel workstations

- [ ] **Step 1: Pull and apply on simars-macbook-16i**
  Run:
  ```bash
  ssh -A -i ~/.ssh/id_rsa simars@simars-macbook-16i.example-tailnet.ts.net "git -C ~/.local/share/chezmoi pull && ~/.local/bin/chezmoi apply -v"
  ```
  Expected: Exit code 0, packages installed or downloaded via fallbacks.

- [ ] **Step 2: Run verification matrix on simars-macbook-16i**
  Run:
  ```bash
  ssh -A -i ~/.ssh/id_rsa simars@simars-macbook-16i.example-tailnet.ts.net "zsh -lic 'which eza bat btop duf dust http jq fx && type fp ll dfh duh top'"
  ```
  Expected: All tools found, aliases verified, exit code 0.

- [ ] **Step 3: Pull and apply on simars-macbook-32i**
  Run:
  ```bash
  ssh -A -i ~/.ssh/id_rsa simars@simars-macbook-32i.example-tailnet.ts.net "git -C ~/.local/share/chezmoi pull && ~/.local/bin/chezmoi apply -v"
  ```
  Expected: Exit code 0, packages installed or downloaded via fallbacks.

- [ ] **Step 4: Run verification matrix on simars-macbook-32i**
  Run:
  ```bash
  ssh -A -i ~/.ssh/id_rsa simars@simars-macbook-32i.example-tailnet.ts.net "zsh -lic 'which eza bat btop duf dust http jq fx && type fp ll dfh duh top'"
  ```
  Expected: All tools found, aliases verified, exit code 0.

---

### Task 6: Documentation & Skill Synchronization

**Files:**
- Modify: `docs/WORKSTATION_MIGRATION_RUNBOOK.md`
- Modify: `docs/TESTING_AND_VERIFICATION_GUIDE.md`
- Modify: `dot_agents/skills/dotfiles-workstation-migration/SKILL.md`
- Modify: `/Users/simars/.agents/skills/dotfiles-workstation-migration/SKILL.md`

**Interfaces:**
- Consumes: Empirical test results from Tasks 4 and 5
- Produces: Updated runbook, guide, and skill files with modern CLI verification commands

- [ ] **Step 1: Update WORKSTATION_MIGRATION_RUNBOOK.md**
  Add modern CLI tools (`eza`, `bat`, `btop`, `duf`, `dust`, `httpie`, `jq`, `fx`) and `fp` alias to Phase 5 and Phase 6 verification commands.

- [ ] **Step 2: Update TESTING_AND_VERIFICATION_GUIDE.md**
  Document the modern CLI tools addition, test commands, and live verification evidence across Apple Silicon and Intel machines.

- [ ] **Step 3: Update SKILL.md in both locations**
  Add modern tools and aliases to Stage 6 verification checklist in both `dot_agents/skills/...` and `~/.agents/skills/...`.

- [ ] **Step 4: Verify chezmoi diff and git status**
  Run: `chezmoi diff && git -C ~/.local/share/chezmoi status`
  Expected: Only clean documentation changes shown.

- [ ] **Step 5: Commit and push documentation**
  Run:
  ```bash
  git -C ~/.local/share/chezmoi add docs/WORKSTATION_MIGRATION_RUNBOOK.md docs/TESTING_AND_VERIFICATION_GUIDE.md dot_agents/skills/dotfiles-workstation-migration/SKILL.md
  git -C ~/.local/share/chezmoi commit -m "docs: document modern CLI tools integration, aliases, and multi-machine verification"
  git -C ~/.local/share/chezmoi push origin main
  ```
  Expected: Gitleaks scan passes (0 leaks), pushed to `origin/main`.
