---
name: dotfiles-workstation-migration
description: Use when migrating a new or existing workstation (Apple Silicon arm64, Intel x86_64, or Ubuntu Linux) to modern chezmoi, mise, and hybrid age dotfiles, conducting pre-apply impact audits, adopting legacy thoughtbot/rcm dotfiles, or running post-apply verification.
---

# Dotfiles Workstation Migration

## Overview

A safe, idempotent, and reversible workflow for bootstrapping or migrating developer workstations to modern dotfiles managed via **`chezmoi`**, **`mise`**, and **hybrid `age` encryption**. 

**Core principle:** NEVER overwrite active configurations or delete legacy repositories without an upfront impact audit, pre-apply safety backup, and evidence-based post-apply verification.

---

## When to Use

Use this process whenever:
- Onboarding a new workstation (macOS Apple Silicon `arm64`, macOS Intel `x86_64`, or Ubuntu Linux).
- Migrating a machine from legacy dotfiles systems (e.g. thoughtbot `rcm`, symlink farms, or bare git repos like `~/.cfg`).
- Applying major template refactors or new runtime versions across machines.
- Running health checks or post-migration verification on existing setups.

Do NOT use for:
- Routine single-file edits on an already verified workstation (use standard `chezmoi edit` and `chezmoi apply`).

---

## The 7-Stage Migration Workflow

```
[1. Discovery] ──> [2. Impact Audit] ──> [3. Pre-Apply Fixes] ──> [4. Safety Backup]
                                                                          │
[7. Document & Push] <── [6. Test Matrix] <── [5. Live Apply] <──────────┘
```

### Stage 1: Pre-Flight Discovery & Architecture Identification
Run environment discovery before touching any files:
```bash
# 1. Architecture and OS
uname -m && uname -s

# 2. Existing Homebrew / Package Manager state
which brew && brew --prefix
which chezmoi && chezmoi --version

# 3. Existing Legacy Storage & Invariants
ls -ld ~/.cfg ~/dotfiles ~/dotfiles-local ~/.aliases ~/.zshrc.local 2>/dev/null || true

# 4. Identity & Secret Files Presence
ls -la ~/.ssh/id_rsa ~/.ssh/id_rsa.pub ~/.config/chezmoi/key.txt ~/secrets.env 2>/dev/null || true
```

**Key Architectural Invariants:**
* **Apple Silicon (`arm64`):** Homebrew prefix is `/opt/homebrew`.
* **Intel Mac (`x86_64`):** Homebrew prefix is `/usr/local`. Enforce `HOMEBREW_NO_BOTTLE_SOURCE_FALLBACK=1` and `--no-upgrade` to prevent source compilation lockups on Tier 3 architectures.
* **Linux (`Ubuntu/Debian`):** Package manager is `apt`. Standalone binaries (`mise`, `starship`, `gitleaks`) installed into `~/.local/bin`.

---

### Stage 2: Deep Impact Analysis & Dependency Audit
Inspect the precise diff against active files and identify potential collisions:

1. **Check Template State & Data:**
   ```bash
   chezmoi init
   chezmoi data
   ```
2. **Review Diff Line-by-Line:**
   ```bash
   chezmoi diff
   ```
   * **PATH Hierarchy:** Ensure `mise` shims, `~/.local/bin`, and Homebrew bin are preserved.
   * **Local Sources:** Ensure `.zshrc` preserves sourcing for machine-specific configs (`~/.aliases`, `~/.zshrc.local`, `~/secrets.env`, `work.secret.env`).
   * **Git Config:** Verify `name`, `email`, editor (`code --wait` on macOS), and URL rewrites.
3. **Audit Dangling Symlinks:**
   Scan for files in `$HOME` that point to legacy dotfiles repositories:
   ```bash
   find ~ -maxdepth 3 -lname '*dotfiles/*' 2>/dev/null
   ```

---

### Stage 3: Upfront Bottleneck Remediation
Resolve known friction points before applying:

* **Homebrew Cask Collisions:**
  If an application was previously downloaded manually (e.g. `/Applications/Wave.app`), adopt it into Homebrew first:
  ```bash
  brew install --cask --force <app-name>
  ```
* **Homebrew Dependency Tab Warnings:**
  If `brew` warns of circular dependencies (e.g., `libtiff`, `webp`), refresh local receipts:
  ```bash
  brew reinstall libtiff webp
  ```
* **Age Binary Encryption Engine:**
  Ensure `useBuiltin = false` is configured under `[age]` in `.chezmoi.toml.tmpl`. This directs chezmoi to use `/opt/homebrew/bin/age` or `~/.local/bin/age`, preventing mixed-case `ssh-rsa` recipient errors.

---

### Stage 4: Mandatory Safety Backup
Create both a target file directory backup and a full archive of legacy repositories:

```bash
# 1. Target files backup
BACKUP_DIR="$HOME/.dotfiles.backup.$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR/.config" "$BACKUP_DIR/.ssh"
cp -P ~/.zshrc ~/.zprofile ~/.gitconfig ~/.tmux.conf "$BACKUP_DIR/" 2>/dev/null || true
cp -P ~/.ssh/config "$BACKUP_DIR/.ssh/" 2>/dev/null || true
[[ -d ~/.config/herdr ]] && cp -RP ~/.config/herdr "$BACKUP_DIR/.config/"
[[ -d ~/.config/mise ]] && cp -RP ~/.config/mise "$BACKUP_DIR/.config/"

# 2. Legacy repository tarball archive (if legacy ~/dotfiles exists)
if [[ -d "$HOME/dotfiles" ]]; then
    tar -czf "$HOME/.dotfiles.legacy.$(date +%Y%m%d_%H%M%S).tar.gz" -C "$HOME" dotfiles
fi
```

---

### Stage 5: Live Apply & Execution Monitoring
Execute dry-run first, followed by live apply:

```bash
# Dry run verification
chezmoi apply -v --dry-run

# Live execution
chezmoi apply -v
```

Monitor during execution:
1. **Package Provisioning:** Homebrew `brew bundle --no-upgrade` or Apt package installations (including `vim`, `neovim`, `herdr`, and modern CLI utilities: `eza`, `bat`, `btop`, `duf`, `dust`, `httpie`, `jq`, `fx`).
2. **Resilient Binary Fallbacks:** Standalone binaries (`herdr`, `neovim`, `age`, `starship`, `mise`, `fzf`, `zoxide`, `bat`, `dust`, `fx`) automatically downloaded into `~/.local/bin` if Homebrew skips unbottled formulae on Intel macOS.
3. **Editor Automation:** LunarVim (`lvim`) installed automatically via unattended installer once `neovim` and runtimes are present.
4. **Runtime Compilation:** `mise install --yes` (Node 22, Go latest, Python 3.12 + httpie/pip/ruff/black/pytest).
5. **Post-Apply Hooks:** Gitleaks pre-commit hook in `~/.local/share/chezmoi/.git/hooks/pre-commit` and Keychain enrollment.

---

### Stage 6: Post-Apply Verification Matrix
Validate all subsystems in a fresh login interactive shell (`zsh -lic`):

```bash
# 1. Prompt & PATH
zsh -lic 'TERM=xterm-256color starship prompt && echo "PATH: $PATH"'

# 2. Core CLI Tools & Terminal Orchestrator
zsh -lic 'which zoxide fzf rg tmux age gitleaks herdr && herdr --version'

# 3. Modern CLI Utilities
zsh -lic 'which eza bat btop duf dust http jq fx'

# 4. Modern & Legacy Shell Aliases
zsh -lic 'type fp ll lt ltree preview dfh duh top'
zsh -lic 'type b && type migrate && type s'
if alias config &>/dev/null; then
    zsh -lic 'config status --short'
fi

# 5. Dynamic FZF Bat Preview Verification
zsh -lic 'head -n 20 ~/.zshrc | bat --style=numbers --color=always'

# 6. Editor Ecosystem (Vim, Neovim, LunarVim)
zsh -lic 'which vim && vim --version | head -n 1'
zsh -lic 'which nvim && nvim --version | head -n 1'
zsh -lic 'which lvim && lvim --version | head -n 1'

# 7. Directory Navigation Functions
zsh -lic 'type z && type zi'

# 8. Polyglot Runtimes
zsh -lic 'mise current && go version && python --version && node --version'

# 9. Git & SSH Configuration
zsh -lic 'git config user.email && git config core.editor'
ssh -T -p 443 git@ssh.github.com

# 10. Hybrid Age Round-Trip Test
TMP_DIR=$(mktemp -d)
TMP_KEY="$TMP_DIR/key.txt"
TMP_PUB=$(age-keygen -o "$TMP_KEY" 2>&1 | grep "Public key:" | awk '{print $3}')
MSG="VERIFICATION_TEST_$(date +%s)"
ENCRYPTED=$(echo "$MSG" | chezmoi encrypt --age-recipient "$TMP_PUB")
DECRYPTED=$(echo "$ENCRYPTED" | age -d -i "$TMP_KEY")
[[ "$DECRYPTED" == "$MSG" ]] && echo "SUCCESS: Age crypto verified"
rm -rf "$TMP_DIR"

# 11. Workstation Cheatsheet & Agentic Maintenance Verification
zsh -lic 'type cheat && cheat | head -n 20'
test -f ~/.cheatsheet.md && grep -q "Modern CLI Utilities" ~/.cheatsheet.md && echo "SUCCESS: ~/.cheatsheet.md verified"
test -f ~/AGENTS.md && diff -u AGENTS.md ~/AGENTS.md && echo "SUCCESS: ~/AGENTS.md synchronized"
```

#### Multi-Platform Subsystem Verification Matrix

| Subsystem / Component | Verification Command | Apple Silicon Mac (`arm64`) | Intel Mac (`x86_64`) | Ubuntu Linux (`amd64`/`arm64`) | Verification Strategy & Invariants |
|---|---|---|---|---|---|
| **Cheatsheet Command** | `type cheat && cheat \| head -n 20` | Function active (`bat` pager) | Function active (`bat` or `less`) | Function active (`bat` or `less`) | Sourced via `~/.aliases`, renders formatted cheatsheet with graceful fallback |
| **Cheatsheet File** | `test -f ~/.cheatsheet.md` | Present & up-to-date | Present & up-to-date | Present & up-to-date | Managed via `dot_cheatsheet.md.tmpl`, rendered from single source `docs/CHEATSHEET.md` |
| **Agentic Invariants** | `test -f ~/AGENTS.md && diff -u AGENTS.md ~/AGENTS.md` | Present & in-sync | Present & in-sync | Present & in-sync | Managed via `dot_AGENTS.md.tmpl`, enforces non-negotiable cheatsheet maintenance |
| **Prompt & Shell** | `starship prompt` | Native `/opt/homebrew` | Native `/usr/local` / `~/.local/bin` | Native `~/.local/bin` | Fast, deterministic prompt with git status & exit codes |
| **Core Utilities** | `which zoxide fzf rg tmux age gitleaks herdr` | Native Homebrew bottles | Native bottles / fallback binaries | Standalone release binaries | Zero compilation overhead; modern CLI tools installed |
| **Observability Tools** | `which eza bat btop duf dust http jq fx` | Native Homebrew bottles | Homebrew / `~/.local/bin` / `mise` | APT / `~/.local/bin` / `mise` | Guarded aliases degrade safely on Tier 3 Intel |
| **Modern Aliases** | `type fp ll lt ltree preview dfh duh top` | Modern `eza`, `bat`, `duf`, `dust`, `btop` | Guarded `ls -lah`, `bat`, `duf`, `dust`, `btop` | Guarded aliases active | Idempotent aliases across all architectures |
| **Bare-Repo Invariant** | `type config` | Active (`alias config=...`) | Active (`alias config=...`) | Active (`alias config=...`) | Preserved for legacy bare repo interaction (`~/.cfg`) |
| **Polyglot Runtimes** | `mise current` (Node, Go, Python) | Managed by `mise` | Managed by `mise` | Managed by `mise` | Fully isolated polyglot environment |
| **Hybrid Age Crypto** | `chezmoi encrypt` + `age -d` | RSA & native Age keys | RSA & native Age keys | Standalone Age keys | Round-trip encryption and decryption verified |

---

### Stage 7: Legacy Decommissioning & Documentation Feedback
Once all verifications pass:

1. **Promote Remaining Assets to Chezmoi (if not already done):**
   * Global gitignore: `dot_gitignore`
   * Commit template: `dot_gitmessage`
   * Shell aliases: `dot_aliases`
   * Classic vim: `dot_vimrc`
   * Tool configs: `dot_psqlrc`, `dot_gemrc`, `dot_rspec`
2. **Prune Dangling Symlinks:**
   Remove obsolete thoughtbot symlinks (`~/.rcrc`, `~/.bin`, `~/.git_template`, `~/.zsh`).
3. **Retire Legacy Directory:**
   Safely remove `~/dotfiles` (backed up in tarball).
4. **Document & Push:**
   Update `docs/TESTING_AND_VERIFICATION_GUIDE.md` and `docs/FUTURE_CONSIDERATIONS.md` with machine-specific findings, commit with Gitleaks check, and push to `origin/main`.

---

## Troubleshooting & Platform Edge Cases

| Symptom | Root Cause | Remediation |
|---|---|---|
| `mixed case` error on age recipient | Chezmoi built-in Go age library does not handle RSA SSH recipients. | Set `useBuiltin = false` in `.chezmoi.toml.tmpl` to invoke `/opt/homebrew/bin/age` or `~/.local/bin/age`. |
| `brew bundle` hangs compiling LLVM | Unbottled formula on Intel Mac falling back to source compilation. | Set `HOMEBREW_NO_BOTTLE_SOURCE_FALLBACK=1` and `--no-upgrade` in bootstrap script. |
| Cask install fails with `already an App at ...` | App was previously downloaded outside Homebrew. | Adopt before apply: `brew install --cask --force <app>`. |
| Prompt fails with `TERM=dumb` in non-interactive tests | Subshell launched without full terminal emulation. | Run with `TERM=xterm-256color zsh -lic 'starship prompt'`. |
| `zi: command not found` | `zoxide` or `fzf` missing from package registry. | Both must be declared in `.chezmoidata/packages.toml` with curl fallbacks in bootstrap script. |
| `promptStringOnce` hangs in headless SSH | Automated script lacks interactive `/dev/tty`. | Provide default parameters in `.chezmoi.toml.tmpl` so headless runs resolve automatically. |
| `Host key verification failed` during headless clone | GitHub SSH host key not pre-cached in `~/.ssh/known_hosts`. | Add `StrictHostKeyChecking accept-new` to SSH client config (`private_dot_ssh/private_config.tmpl`). |
| LunarVim installer fails with permission denied | Git clones over SSH via `insteadOf = https://github.com/` without agent. | Connect to remote machine with SSH agent forwarding: `ssh -A <host>`. |
| Unbottled `herdr` or `neovim` on Intel macOS | Homebrew Tahoe x86_64 lacks bottles for modern formulae. | Bootstrap script automatically downloads official standalone binaries into `~/.local/bin`. |
| Unbottled modern CLI utilities on Intel macOS (`bat`, `dust`, `fx`, `eza`) | Homebrew Tier 3 deprecation skips unbottled formulae under `HOMEBREW_NO_BOTTLE_SOURCE_FALLBACK=1`. | Automated standalone fallbacks in bootstrap hook for `bat`, `dust`, `fx` into `~/.local/bin`; `httpie` via `default-python-packages`; guarded `ll` alias safely degrades to `ls -lah`. |
