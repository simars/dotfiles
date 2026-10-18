# Cross-Platform Dotfiles Migration Design Specification (`chezmoi` + `mise` + `age`)

## 1. Executive Summary & Context

This document specifies the architecture and migration plan for transitioning from the legacy dotfiles setup (based on thoughtbot/dotfiles symlinks and an Atlassian-style bare git repository at `~/.cfg`) to a modern, declarative, cross-platform configuration managed by **`chezmoi`**, **`mise`**, and a **hybrid `age` encryption model**.

### Primary Objectives
1. **Single Source of Truth:** Unify configuration files in a structured source repository located at `~/.local/share/chezmoi` (standalone Git repository).
2. **Safe Coexistence & Rollback:** Preserve the existing `~/.cfg` bare repository and `~/dotfiles` without disruption, backing up active files into a timestamped directory before applying changes.
3. **Hybrid Age Encryption:** Support the existing `~/.ssh/id_rsa` as the primary local encryption identity and recipient, while enabling an `age` key recipient fallback for headless/CI automation.
4. **Polyglot Runtime Engine:** Standardize language management across macOS and Ubuntu using `mise` (Go, Python, Node).
5. **Deterministic Multi-OS Support:** Native Homebrew integration on macOS (`arm64` and `amd64`) and APT + standalone binary bootstrapping on Ubuntu Linux.
6. **Continuous Integration & Secret Prevention:** GitHub Actions matrix pipeline (`macos-13`, `macos-14`, `ubuntu-latest`) and local pre-commit `gitleaks` interception.

---

## 2. Target Platforms & Toolchain

### Target Platforms
* **macOS Apple Silicon (`darwin/arm64`)**: Homebrew prefix `/opt/homebrew`
* **macOS Intel (`darwin/amd64`)**: Homebrew prefix `/usr/local`
* **Ubuntu Linux 26.04 LTS (`linux/amd64` and `linux/arm64`)**: APT packages and standalone binary installers

### Core Toolchain
* **Dotfiles Engine:** `chezmoi` (Go-templated configuration)
* **Encryption:** `age` (dual-recipient support: OpenSSH RSA/Ed25519 + native X25519 age keys)
* **Polyglot Runtimes:** `mise` managing Go (`latest`), Python (`3.12`), Node (`22`), and virtualenvs
* **Shell & Prompt:** `zsh` + `starship`
* **Multiplexers & Terminals:** `tmux` (Ctrl+b, vi-navigation), `herdr` (synchronized Ctrl+b bindings), `alacritty` (Tokyo Night)
* **Editors:** Neovim (`lazy.nvim`, treesitter, telescope), VS Code (synchronized `settings.json` and extension bundle)
* **Containers:** Colima + Docker CLI (macOS), Official Docker Engine (Ubuntu)
* **Security & Quality:** `gitleaks` (local git hook + GitHub Action), `shellcheck`

---

## 3. Repository Architecture & File Blueprint

The chezmoi source repository resides at `~/.local/share/chezmoi` (Git repository on branch `main`).

```text
~/.local/share/chezmoi/
├── .github/
│   └── workflows/
│       └── ci.yml
├── .gitleaks.toml
├── .chezmoi.toml.tmpl
├── .chezmoiignore
├── .chezmoidata/
│   └── packages.toml
├── README.md
├── Library/
│   └── Application Support/
│       └── Code/
│           └── User/
│               └── symlink_settings.json.tmpl
├── dot_config/
│   ├── Code/
│   │   └── User/
│   │       └── settings.json.tmpl
│   ├── alacritty/
│   │   └── alacritty.toml
│   ├── herdr/
│   │   └── config.yaml
│   ├── mise/
│   │   ├── config.toml
│   │   └── default-python-packages
│   ├── nvim/
│   │   └── init.lua.tmpl
│   ├── starship.toml.tmpl
│   └── tmux/
│       └── tmux.conf
├── dot_gitconfig.tmpl
├── dot_tmux.conf.tmpl
├── dot_zprofile.tmpl
├── dot_zshrc.tmpl
├── private_dot_ssh/
│   └── private_config.tmpl
├── run_after_00_install_hooks.sh.tmpl
├── run_onchange_after_90_sync_runtimes.sh.tmpl
├── run_onchange_after_95_vscode_extensions.sh.tmpl
└── run_onchange_before_00_install_packages.sh.tmpl
```

---

## 4. Detailed Component Specifications

### 4.1 Hybrid Encryption Architecture (`.chezmoi.toml.tmpl` & `.gitleaks.toml`)
* **Multi-Recipient Model:**
  When secrets are encrypted using `chezmoi add --encrypt`, `age` will encrypt for both:
  1. The user's SSH public key (`~/.ssh/id_rsa.pub` if present).
  2. The fallback automation `age` recipient (`age1ql3z7hjy54pw3hyww5ayyfg7zqgvc7w3j2elw8zmrj2kg5sfn9aqmcac8p`).
* **Decryption Identity Resolution:**
  1. If `~/.ssh/id_rsa` exists on the workstation, set `identity` to `~/.ssh/id_rsa`.
  2. Otherwise, if `~/.config/chezmoi/key.txt` exists (such as on headless servers or in CI), set `identity` to `~/.config/chezmoi/key.txt`.
* **Secret Interception:**
  * `.gitleaks.toml` allows `.age` encrypted files, CI configuration, and public keys (`age1...`, `ssh-rsa ...`).
  * `run_after_00_install_hooks.sh.tmpl` automatically writes and marks executable `.git/hooks/pre-commit` in `~/.local/share/chezmoi` to run `gitleaks protect --staged`.

### 4.2 Declarative Package System (`packages.toml` & Lifecycle Script)
* `.chezmoidata/packages.toml` defines formulae/casks for Homebrew on macOS and packages for APT on Linux.
* `run_onchange_before_00_install_packages.sh.tmpl`:
  * Includes a hash check header: `{{ include ".chezmoidata/packages.toml" | sha256sum }}` so package installations run only when dependencies change.
  * Honors `CHEZMOI_CI=true` to skip heavyweight system packages in CI test runs.
  * Installs Homebrew non-interactively if absent on macOS and executes `brew bundle`.
  * Installs APT packages, symlinks `fdfind` to `fd`, downloads `starship`, `mise`, `gitleaks`, JetBrains Mono Nerd Font, and official Docker CE on Linux.

### 4.3 Shell & Environment Management
* **`dot_zprofile.tmpl`:**
  * Architecture-aware Homebrew initialization (`/opt/homebrew` vs `/usr/local`).
  * Prepends `$HOME/.local/bin` and `$HOME/.local/share/mise/shims` to `$PATH`.
  * Configures `DOCKER_HOST="unix://${HOME}/.colima/default/docker.sock"` on macOS.
* **`dot_zshrc.tmpl`:**
  * Interactive aliases (`ll`, `g`, `cz`, `tm`, `brews`, `d-up`, `d-down`, `dkill`, `dprune`).
  * Enables zsh completion (`autoload -Uz compinit && compinit -C`).
  * Activates `mise` auto-reload and shell hook (`eval "$(mise activate zsh)"`).
  * Activates `starship` prompt hook (`eval "$(starship init zsh)"`).

### 4.4 Development Runtimes & Editors
* **`mise`:**
  * Configured via `dot_config/mise/config.toml` with `python_venv_auto_create = true`.
  * Default packages: `pip`, `wheel`, `ruff`, `black`, `pytest`.
  * Synced via `run_onchange_after_90_sync_runtimes.sh.tmpl` tracking the hash of `config.toml`.
* **VS Code:**
  * `dot_config/Code/User/settings.json.tmpl`: Configures Tokyo Night theme, JetBrains Mono font, relative line numbers, trim whitespace, and default zsh terminal.
  * `Library/Application Support/Code/User/symlink_settings.json.tmpl`: Points to `~/.config/Code/User/settings.json` on macOS.
  * Extension sync script installs `golang.go`, `ms-python.python`, `ms-python.black-formatter`, `eamodio.gitlens`, `esbenp.prettier-vscode`, `enkia.tokyo-night`.
* **Neovim:**
  * Self-bootstraps `lazy.nvim` if missing.
  * Sets up Tokyo Night scheme, Telescope (`<leader>ff`, `<leader>fg`, `<leader>fb`), and Treesitter parser definitions.

### 4.5 Multiplexing & Terminal Sync
* **`tmux` (`dot_config/tmux/tmux.conf` & `dot_tmux.conf.tmpl`):**
  * Leader: `Ctrl+b`.
  * Split bindings: `%` (horizontal), `"` (vertical) preserving working directory.
  * Vi-keys: `h`, `j`, `k`, `l` pane selection.
  * Base index: 1; mouse: on; history: 50,000.
* **`herdr` (`dot_config/herdr/config.yaml`):**
  * Leader: `ctrl+b`.
  * Mirror bindings for splits (`%`, `"`), navigation (`h`, `j`, `k`, `l`, arrow keys), and tabs (`c`, `x`).
* **`alacritty` (`dot_config/alacritty/alacritty.toml`):**
  * JetBrains Mono Nerd Font (size 14), Tokyo Night background/foreground, 0.95 opacity.

---

## 5. Migration, Safety & Rollback Strategy

### 5.1 Preservation Invariant
* Existing bare repo `~/.cfg` will **not** be modified or deleted. Its `config` alias continues to function.
* Existing repository `~/dotfiles` remains intact in place.

### 5.2 Automated Pre-Apply Backup
Before running the first `chezmoi apply`, an automated backup captures all existing target files and symlinks:
```bash
BACKUP_DIR="$HOME/.dotfiles.backup.$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"
for file in .zshrc .zprofile .gitconfig .tmux.conf .config/starship.toml .config/tmux/tmux.conf; do
  if [[ -e "$HOME/$file" || -L "$HOME/$file" ]]; then
    mkdir -p "$BACKUP_DIR/$(dirname "$file")"
    cp -P "$HOME/$file" "$BACKUP_DIR/$file"
  fi
done
```

### 5.3 Rollback Mechanism
If rollback is desired, symlinks can be restored from the generated `$BACKUP_DIR` with:
```bash
cp -PR "$BACKUP_DIR/." "$HOME/"
```

---

## 6. Verification & Testing Protocol

### 6.1 GitHub Actions Matrix (`.github/workflows/ci.yml`)
* **Job 1 (Lint & Security):**
  * Checkout code.
  * Gitleaks action scan using `.gitleaks.toml`.
  * ShellCheck on non-template `.sh` scripts.
* **Job 2 (Matrix Test Apply):**
  * Runners: `ubuntu-latest` (x86_64), `macos-13` (Intel), `macos-14` (Apple Silicon).
  * Setup chezmoi & age.
  * Generate mock age key for CI runner.
  * Execute `chezmoi init` with non-interactive prompts.
  * Execute `chezmoi diff`.
  * Execute `chezmoi apply --dry-run --verbose`.
  * Execute `chezmoi apply --verbose`.

### 6.2 Local Sandbox Verification Protocol
1. **Directory Tree Integrity:** Confirm all 24 blueprint files exist without placeholders.
2. **Gitleaks Check:** Execute `gitleaks detect --no-git --config .gitleaks.toml` inside repository.
3. **Template Compilation in Sandbox:**
   ```bash
   SANDBOX="$(mktemp -d)"
   CHEZMOI_CI=true chezmoi init \
     --source="$HOME/.local/share/chezmoi" \
     --destination="$SANDBOX" \
     --config="$SANDBOX/chezmoi.toml" \
     --promptString "What is your Git email address=you@example.com" \
     --promptString "What is your Git full name=Simar Singh" \
     --promptBool "Is this a work machine=false"
   CHEZMOI_CI=true chezmoi status \
     --source="$HOME/.local/share/chezmoi" \
     --destination="$SANDBOX" \
     --config="$SANDBOX/chezmoi.toml"
   rm -rf "$SANDBOX"
   ```
4. **Interactive Dry-Run:** Run `chezmoi diff` against actual `$HOME` before any write.
