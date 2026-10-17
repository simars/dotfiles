# Workstation Migration Runbook

A safe, repeatable, and reversible guide for migrating or onboarding any workstation (Apple Silicon macOS `arm64`, Intel macOS `x86_64`, or Ubuntu Linux) to modern cross-platform dotfiles managed with **`chezmoi`**, **`mise`**, and **hybrid `age` encryption**.

---

## 1. Prerequisites & Architectural Overview

Before starting migration on a target machine, understand its target state:

* **Source Repository:** `~/.local/share/chezmoi` (tracking `git@github.com:simars/dotfiles.git` on `main`).
* **Package Managers:**
  * macOS Apple Silicon: `/opt/homebrew`
  * macOS Intel: `/usr/local` (with bottle fallback protection)
  * Ubuntu Linux: `apt-get` + standalone tools in `~/.local/bin`
* **Polyglot Runtimes (`mise`):**
  * Node: `22` (LTS)
  * Python: `3.12` (+ `pip`, `wheel`, `ruff`, `black`, `pytest`)
  * Go: `latest`
* **Hybrid Age Encryption:**
  * Recipient 1: Personal SSH key (`~/.ssh/id_rsa.pub`)
  * Recipient 2: Automation fallback Age key (`age1ql3z...`)
  * External engine: `useBuiltin = false` delegates to `age` binary (`/opt/homebrew/bin/age` or `~/.local/bin/age`).

---

## 2. Phase-by-Phase Migration Workflow

### Phase 1: Environment Discovery & Legacy Audit
Run discovery commands to assess the workstation's baseline:

```bash
# 1. Architecture and OS
uname -m && uname -s

# 2. Package Manager and Homebrew prefix
which brew && brew --prefix
which chezmoi && chezmoi --version

# 3. Check for legacy storage repositories
ls -ld ~/.cfg ~/dotfiles ~/dotfiles-local ~/.aliases ~/.zshrc.local 2>/dev/null || true

# 4. Audit symlinks pointing to legacy dotfiles (if ~/dotfiles exists)
find ~ -maxdepth 3 -lname '*dotfiles/*' 2>/dev/null
```

### Phase 2: Template Initialization & Impact Review
1. **Regenerate / Verify Configuration:**
   ```bash
   chezmoi init
   chezmoi data
   ```
2. **Review Diff Against Active Files:**
   ```bash
   chezmoi diff
   ```
   * Ensure PATH order maintains `mise` shims and Homebrew prefix ahead of system paths.
   * Verify all machine-local sourcing lines (`~/.aliases`, `~/.zshrc.local`, `~/secrets.env`, `work.secret.env`) are preserved in `.zshrc`.
   * Check Git user configuration (`Simar Singh <simarpaulsingh@gmail.com>`).

### Phase 3: Upfront Bottleneck Remediation
Address common platform-specific hurdles before running apply:

* **Adopt Pre-existing Applications:**
  If an app was previously installed manually (e.g. `/Applications/Wave.app`), adopt it into Homebrew first:
  ```bash
  brew install --cask --force wave
  ```
* **Clear Homebrew Keg Tab Circular Dependencies:**
  If `brew` outputs circular dependency warnings (`libtiff`, `webp`), refresh local receipts:
  ```bash
  brew reinstall libtiff webp
  ```
* **Intel Mac Tier 3 Protection:**
  Ensure `HOMEBREW_NO_BOTTLE_SOURCE_FALLBACK=1` and `--no-upgrade` are set in the package installer hook so unbottled packages on deprecated macOS versions don't lock the terminal into building LLVM from source.

### Phase 4: Mandatory Safety Backups
Always create a timestamped backup before altering active dotfiles:

```bash
# 1. Target configuration backup
BACKUP_DIR="$HOME/.dotfiles.backup.$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR/.config" "$BACKUP_DIR/.ssh"
cp -P ~/.zshrc ~/.zprofile ~/.gitconfig ~/.tmux.conf "$BACKUP_DIR/" 2>/dev/null || true
cp -P ~/.ssh/config "$BACKUP_DIR/.ssh/" 2>/dev/null || true
[[ -d ~/.config/herdr ]] && cp -RP ~/.config/herdr "$BACKUP_DIR/.config/"
[[ -d ~/.config/mise ]] && cp -RP ~/.config/mise "$BACKUP_DIR/.config/"

# 2. Legacy repository archive (if legacy ~/dotfiles is present)
if [[ -d "$HOME/dotfiles" ]]; then
    tar -czf "$HOME/.dotfiles.legacy.$(date +%Y%m%d_%H%M%S).tar.gz" -C "$HOME" dotfiles
fi
```

### Phase 5: Live Execution (`chezmoi apply -v`)
Execute the dry-run, then apply:

```bash
# Test dry-run
chezmoi apply -v --dry-run

# Live apply
chezmoi apply -v
```

**What happens during apply:**
1. Packages are installed via `brew bundle --no-upgrade` or `apt-get`.
2. Core standalone tools (`starship`, `mise`, `age`, `zoxide`, `fzf`) fall back to standalone curl binaries if package managers skip them.
3. Templates are rendered to `$HOME`.
4. Post-apply hooks install the Gitleaks pre-commit secret scanner.
5. Language runtimes are synced via `mise install --yes`.

### Phase 6: Post-Apply Verification Matrix
Execute all verification commands in a clean login interactive shell:

```bash
# 1. Prompt and PATH
zsh -lic 'TERM=xterm-256color starship prompt && echo "PATH: $PATH"'

# 2. Core CLI Tools
zsh -lic 'which zoxide fzf rg nvim tmux age gitleaks'

# 3. Directory Navigation Functions
zsh -lic 'type z && type zi'

# 4. Language Runtimes
zsh -lic 'mise current && go version && python --version && node --version'

# 5. Git & SSH Configuration
zsh -lic 'git config user.email && git config core.editor'
ssh -T -p 443 git@ssh.github.com

# 6. Hybrid Age Round-Trip Test
TMP_DIR=$(mktemp -d)
TMP_KEY="$TMP_DIR/key.txt"
TMP_PUB=$(age-keygen -o "$TMP_KEY" 2>&1 | grep "Public key:" | awk '{print $3}')
MSG="VERIFICATION_TEST_$(date +%s)"
ENCRYPTED=$(echo "$MSG" | chezmoi encrypt --age-recipient "$TMP_PUB")
DECRYPTED=$(echo "$ENCRYPTED" | age -d -i "$TMP_KEY")
[[ "$DECRYPTED" == "$MSG" ]] && echo "SUCCESS: Age crypto verified"
rm -rf "$TMP_DIR"

# 7. Legacy Alias Invariant Check
zsh -lic 'type ll && type b && type migrate && type s'
if alias config &>/dev/null; then
    zsh -lic 'config status --short'
fi
```

### Phase 7: Retiring Legacy Repositories
Once all verifications pass on a machine migrating from thoughtbot `rcm`:

1. **Prune Obsolete Symlinks:**
   ```bash
   rm -f ~/.vimrc.bundles ~/.CODE_OF_CONDUCT.md ~/.rcrc ~/docs ~/.zshenv ~/.ctags ~/.asdfrc ~/.hushlogin
   rm -rf ~/.vim/ftplugin ~/.vim/plugin ~/.ctags.d ~/.git_template ~/.bin ~/.zsh
   rm -f ~/.cfg/info/exclude ~/.cfg/hooks/* 2>/dev/null || true
   ```
2. **Retire `~/dotfiles`:**
   Ensure the legacy tarball backup exists (`ls -l ~/.dotfiles.legacy.*.tar.gz`), then remove `~/dotfiles`:
   ```bash
   rm -rf ~/dotfiles
   ```
3. **Document Machine Verification:**
   Update `docs/TESTING_AND_VERIFICATION_GUIDE.md` and `docs/FUTURE_CONSIDERATIONS.md`, commit, and push.

---

## 3. Platform Quick Reference

| Platform | Homebrew Prefix | Binary Fallbacks | Package Hook Notes |
|---|---|---|---|
| **Apple Silicon macOS** | `/opt/homebrew` | Native bottles | Tier 1 official support; zero source builds. |
| **Intel macOS** | `/usr/local` | `~/.local/bin` | Enforces `HOMEBREW_NO_BOTTLE_SOURCE_FALLBACK=1`. |
| **Ubuntu Linux** | N/A (`apt`) | `~/.local/bin` | Uses `sudo apt-get` with noninteractive debconf. |
