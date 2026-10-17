# Dotfiles Architecture, Testing & Verification Guide

This guide documents the architecture, migration safety, testing procedures, and day-to-day operations for the modern cross-platform dotfiles repository managed with **`chezmoi`**, **`mise`**, and **hybrid `age` encryption**.

---

## 1. System Architecture & Blueprint

### 1.1 Source vs. Destination
* **Source Repository:** `~/.local/share/chezmoi` (Git repository on branch `main`, tracking `git@github.com:simars/dotfiles.git`).
* **Target / Destination:** Active `$HOME` (`/Users/simars` on macOS, `/home/<user>` on Ubuntu).
* **Remote Legacy Backup:** Prior GitHub history is preserved on the remote branch [`legacy-backup`](https://github.com/simars/dotfiles/tree/legacy-backup).

### 1.2 Repository Tree
```text
~/.local/share/chezmoi/
├── .github/workflows/ci.yml           # Cross-platform CI matrix (macOS Intel/ARM, Ubuntu)
├── .gitleaks.toml                     # Secret scanner allowlist configuration
├── .gitignore                         # Local key and OS artifact exclusion
├── .chezmoi.toml.tmpl                 # Interactive init config + hybrid encryption setup
├── .chezmoiignore                     # OS-specific filter (ignores macOS Library on Linux)
├── .chezmoidata/
│   └── packages.toml                  # Declarative package definitions (Homebrew + APT)
├── README.md                          # Bootstrap instructions & cheat sheet
├── docs/
│   └── TESTING_AND_VERIFICATION_GUIDE.md # This guide
├── Library/Application Support/Code/User/
│   └── symlink_settings.json.tmpl     # macOS symlink to ~/.config/Code/User/settings.json
├── dot_config/
│   ├── Code/User/settings.json.tmpl   # Canonical VS Code editor configuration
│   ├── alacritty/alacritty.toml       # GPU-accelerated terminal styling (Tokyo Night)
│   ├── herdr/config.yaml              # Terminal orchestrator mapped to Ctrl+b bindings
│   ├── mise/
│   │   ├── config.toml                # Go (latest), Python (3.12), Node (22) tool definitions
│   │   └── default-python-packages    # Global packages (ruff, black, pytest, pip)
│   ├── nvim/init.lua.tmpl             # Self-bootstrapping lazy.nvim + treesitter + telescope
│   ├── starship.toml.tmpl             # Cross-platform shell prompt
│   └── tmux/tmux.conf                 # 256-color, vi-keys, mouse mode tmux config
├── dot_gitconfig.tmpl                 # Cross-platform git configuration + work overrides
├── dot_tmux.conf.tmpl                 # Sourcing ~/.config/tmux/tmux.conf
├── dot_zprofile.tmpl                  # Architecture-aware Homebrew & mise shims
├── dot_zshrc.tmpl                     # Aliases, Docker helpers, mise & starship activation
├── private_dot_ssh/
│   └── private_config.tmpl            # Port 443 SSH routing for GitHub + conditional work hosts
├── run_after_00_install_hooks.sh.tmpl # Installs Gitleaks pre-commit hook into chezmoi git repo
├── run_onchange_before_00_install_packages.sh.tmpl # Homebrew / APT automated package installer
├── run_onchange_after_90_sync_runtimes.sh.tmpl    # Automatic mise tool installer
└── run_onchange_after_95_vscode_extensions.sh.tmpl# Automatic VS Code extension installer
```

---

## 2. Hybrid Age / SSH Encryption Model

### 2.1 Multi-Recipient Architecture
Files encrypted with `chezmoi add --encrypt` are simultaneously encrypted for:
1. **Your Personal SSH Key:** `~/.ssh/id_rsa.pub` (or `~/.ssh/id_ed25519.pub`).
2. **Automation Fallback Age Key:** `age1ql3z7hjy54pw3hyww5ayyfg7zqgvc7w3j2elw8zmrj2kg5sfn9aqmcac8p` (used in GitHub Actions CI or secondary devices without private SSH keys).

### 2.2 Dynamic Decryption Resolution
When `chezmoi apply` or `chezmoi diff` decrypts a secret, `.chezmoi.toml.tmpl` dynamically selects the identity:
* If `~/.ssh/id_rsa` exists, it uses your SSH key.
* Otherwise, if `~/.ssh/id_ed25519` exists, it uses your Ed25519 SSH key.
* Otherwise, if `~/.config/chezmoi/key.txt` exists, it uses the native age private key.

### 2.3 Secret Leak Prevention
* **`.gitleaks.toml`**: Blocks unencrypted secrets, while allowing encrypted `.age` files and public recipient strings (`ssh-rsa`, `ssh-ed25519`, `age1...`). Private keys (`AGE-SECRET-KEY-1...`, `key.txt`) are excluded from the allowlist and git-ignored.
* **Pre-commit Hook:** Automatically installed in `~/.local/share/chezmoi/.git/hooks/pre-commit` via `run_after_00_install_hooks.sh.tmpl`.

### 2.4 Multi-Provider Secret Architecture (1Password + Bitwarden + Age)
`chezmoi` supports querying multiple secret providers concurrently at template render time:

1. **1Password (`op` CLI)**:
   * **Setup:** In 1Password Desktop App: `Settings -> Developer -> Check "Integrate with 1Password CLI"`.
   * **In Templates:**
     ```ini
     # Secret reference URI
     aws_secret_key = {{ onepasswordRead "op://Personal/AWS/secret_access_key" }}
     
     # Full item inspection
     {{ $gh := onepassword "GitHub Personal Token" "Personal" }}
     export GITHUB_TOKEN="{{ $gh.password }}"
     ```
2. **Bitwarden (`bw` CLI)**:
   * **Setup:** `bw login` and export session: `export BW_SESSION="$(bw unlock --raw)"`.
   * **In Templates:**
     ```bash
     {{ $item := bitwarden "item" "OpenAI API Key" }}
     export OPENAI_API_KEY="{{ $item.notes }}"
     
     {{ $fields := bitwardenFields "item" "CustomService" }}
     export SERVICE_KEY="{{ $fields.apiKey.value }}"
     ```
3. **Layered Strategy:**
   * **`age` (Hybrid):** For initial bootstrap secrets (`~/.ssh/id_rsa`, git signing keys) needed before browser/app login.
   * **1Password:** For macOS desktop workflows with Touch ID authentication.
   * **Bitwarden:** For shared team credentials and server automation.

---

## 3. Preservation Invariants & Rollback Safety

1. **Untouched Legacy Repositories:**
   * `~/.cfg` (bare repository connected to `git@github.com:simars/.cfg.git`) and the `config` alias remain 100% functional.
   * `~/dotfiles` (thoughtbot clone) remains completely untouched.
2. **Pre-Apply Timestamped Backup:**
   * All active `$HOME` files and symlinks (`.zshrc`, `.zprofile`, `.gitconfig`, `.tmux.conf`, `.config/starship.toml`) were archived before any changes:
     `~/.dotfiles.backup.20261016_201631/`
3. **Emergency Rollback Command:**
   ```bash
   cp -PR ~/.dotfiles.backup.20261016_201631/. "$HOME/"
   ```

---

## 4. End-to-End Testing & Verification Runbook

Follow these sequential steps to thoroughly test your new setup:

### Phase 1: Non-Destructive Inspection
Inspect all template outputs against your current `$HOME` without modifying anything:
```bash
# 1. View exact line-by-line diff
chezmoi diff

# 2. Perform a dry-run apply
chezmoi apply --dry-run --verbose
```

### Phase 2: Live Apply to `$HOME`
Apply the configuration to your workstation:
```bash
chezmoi apply -v
```
During this initial run:
1. `chezmoi` prompts for:
   * **Git email address** (e.g. `you@work.example`)
   * **Git full name** (e.g. `Simar Singh`)
   * **Is this a work machine** (`true` or `false`)
2. `chezmoi` renders configurations into `$HOME`.
3. `run_onchange_before_00_install_packages.sh.tmpl` verifies Homebrew dependencies via `brew bundle`.
4. `run_onchange_after_90_sync_runtimes.sh.tmpl` installs `mise` runtimes (Go, Python 3.12, Node 22).
5. `run_onchange_after_95_vscode_extensions.sh.tmpl` synchronizes VS Code extensions.
6. `run_after_00_install_hooks.sh.tmpl` arms the local Gitleaks pre-commit hook.

### Phase 3: Shell & Environment Validation
Open a new shell session:
```bash
exec zsh
```
Verify the following:
* **Prompt:** Confirm Starship prompt appears with directory, git status, and character symbols.
* **Architecture-Aware PATH:** Run `echo $PATH` and verify `/opt/homebrew/bin` (or `/usr/local/bin`) and `~/.local/share/mise/shims` appear early in the path.
* **Aliases:**
  * `ll` (formatted directory listing)
  * `g status` (git shortcut)
  * `cz status` (chezmoi shortcut)
  * `brews` (brew upgrade/cleanup shortcut)
  * `d-up` / `d-down` (Colima container helpers)
* **Polyglot Runtimes (`mise`):**
  ```bash
  mise current
  python --version   # Python 3.12.x
  node --version     # v22.x
  go version         # go1.x
  ruff --version     # verified global Python package
  ```

### Phase 4: Terminal Multiplexer Parity
Test keybinding synchronization across `tmux` and `herdr`:
* **tmux:**
  1. Start session: `tm`
  2. Split horizontally: `Ctrl+b` + `%`
  3. Split vertically: `Ctrl+b` + `"`
  4. Navigate panes: `Ctrl+b` then `h` (left), `j` (down), `k` (up), `l` (right)
  5. Close pane: `Ctrl+b` + `x`
* **herdr:**
  1. Launch `herdr`
  2. Verify split bindings (`%`, `"`) and navigation bindings (`h/j/k/l`) match `tmux` identically.

### Phase 5: Code Editors
* **Neovim:**
  Launch `nvim`. On first launch, `lazy.nvim` automatically clones and bootstraps Tokyo Night colorscheme, Treesitter syntax highlighting, and Telescope search (`<leader>ff`).
* **VS Code:**
  Launch `code`. Confirm Tokyo Night theme, JetBrains Mono font, relative line numbers, and installed extensions (`golang.go`, `ms-python.python`, `gitlens`, `prettier`).

### Phase 6: Hybrid Encryption Round-Trip Test
Verify secret encryption and decryption using your SSH key:
```bash
# 1. Create a test secret file
echo "SECRET_TOKEN=my-secure-token-12345" > ~/.test_token

# 2. Add as an encrypted file to chezmoi
chezmoi add --encrypt ~/.test_token

# 3. Confirm encrypted file was created in source repo
ls -l ~/.local/share/chezmoi/encrypted_dot_test_token.age

# 4. Decrypt and verify content
chezmoi cat ~/.test_token

# 5. Clean up test token
rm ~/.test_token
chezmoi forget ~/.test_token
rm ~/.local/share/chezmoi/encrypted_dot_test_token.age
```

---

## 5. Day-to-Day Operations Cheat Sheet

| Task | Command | Description |
|---|---|---|
| **Inspect Differences** | `chezmoi diff` | Show diff between templates and active `$HOME` |
| **Apply Updates** | `chezmoi apply` | Render templates and apply changes to `$HOME` |
| **Edit a Managed File** | `chezmoi edit ~/.zshrc` | Open source template in `$EDITOR` and re-apply |
| **Add a New File** | `chezmoi add ~/.config/app/config.toml` | Track a new configuration file in chezmoi |
| **Add an Encrypted Secret** | `chezmoi add --encrypt ~/.ssh/id_work` | Encrypt a sensitive file with hybrid age/ssh keys |
| **Pull & Apply Remote Updates** | `chezmoi update` | Pull latest commits from GitHub and apply |
| **Open Source Directory** | `chezmoi cd` | Launch interactive shell inside `~/.local/share/chezmoi` |
| **List Managed Files** | `chezmoi managed` | List all files currently managed by chezmoi |
| **Inspect File Status** | `chezmoi status` | List state changes between source and destination |
| **Fresh Machine Bootstrap** | `sh -c "$(curl -fsLS https://get.chezmoi.io)" -- init --apply git@github.com:simars/dotfiles.git` | Bootstrap an entire workstation in one command |
