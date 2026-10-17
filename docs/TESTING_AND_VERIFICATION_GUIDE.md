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
├── .chezmoiignore                     # Repository metadata exclusion
├── .chezmoidata/
│   └── packages.toml                  # Declarative package definitions (Homebrew + APT)
├── README.md                          # Bootstrap instructions & cheat sheet
├── docs/
│   ├── FUTURE_CONSIDERATIONS.md          # Platform lifecycle roadmap & remediation
│   └── TESTING_AND_VERIFICATION_GUIDE.md # This guide
├── dot_config/
│   ├── alacritty/alacritty.toml       # GPU-accelerated terminal styling (Tokyo Night)
│   ├── herdr/config.toml              # Terminal orchestrator mapped to Ctrl+b bindings
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
│   └── private_config.tmpl            # Port 443 SSH routing for GitHub + personal hosts
├── run_after_00_install_hooks.sh.tmpl # Installs Gitleaks pre-commit hook into chezmoi git repo
├── run_onchange_before_00_install_packages.sh.tmpl # Homebrew / APT automated package installer
└── run_onchange_after_90_sync_runtimes.sh.tmpl    # Automatic mise tool installer
```

---

## 2. Hybrid Age / SSH Encryption Model

### 2.1 Multi-Recipient Architecture
Files encrypted with `chezmoi add --encrypt` are simultaneously encrypted for:
1. **Your Personal SSH Key:** `~/.ssh/id_rsa.pub`.
2. **Automation Fallback Age Key:** `age1ql3z7hjy54pw3hyww5ayyfg7zqgvc7w3j2elw8zmrj2kg5sfn9aqmcac8p` (used in GitHub Actions CI or secondary devices without private SSH keys).

### 2.2 Dynamic Decryption Resolution & External Age Engine
When `chezmoi apply` or `chezmoi diff` decrypts a secret, `.chezmoi.toml.tmpl` dynamically selects the identity:
* If `~/.ssh/id_rsa` exists on the workstation, it uses your primary SSH key (`~/.ssh/id_rsa`).
* If `~/.ssh/id_ed25519` exists, it uses your Ed25519 SSH key.
* Otherwise, if `~/.config/chezmoi/key.txt` exists (such as in headless or CI environments), it uses the native age private key.

> [!NOTE]
> `.chezmoi.toml.tmpl` specifies `useBuiltin = false` under `[age]`. Chezmoi's internal Go age implementation rejects `ssh-rsa` recipients with `malformed recipient ...: mixed case`. Setting `useBuiltin = false` delegates encryption to the external `age` binary (`~/.local/bin/age` or `/opt/homebrew/bin/age`), which natively and robustly supports RSA and Ed25519 SSH recipients.

### 2.3 Secret Leak Prevention
* **`.gitleaks.toml`**: Blocks unencrypted secrets, while allowing encrypted `.age` files and public recipient strings (`ssh-rsa`, `age1...`). Private keys (`AGE-SECRET-KEY-1...`, `key.txt`) are excluded from the allowlist and git-ignored.
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
5. `run_after_00_install_hooks.sh.tmpl` arms the local Gitleaks pre-commit hook.

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
  VS Code is managed via native VS Code Settings Sync (independent of chezmoi to preserve macOS `0700` `~/Library` security permissions). Verify that your extensions and settings sync seamlessly through your Microsoft/GitHub login.

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

## 5. Live Verification on Intel MacBook (`simars-macbook-16i`)

The entire system was field-tested on a live Intel machine via SSH (`ssh -i ~/.ssh/id_rsa simars@simars-macbook-16i.example-tailnet.ts.net`).

### 5.1 Environment Profile
* **Host:** `simars-macbook-16i.example-tailnet.ts.net` (Tailscale)
* **Architecture:** `x86_64` (Intel Core i7/i9)
* **Kernel & OS:** Darwin 25.2.0 (`macOS 26.2` Tahoe/Sequoia+)
* **Shell:** `/bin/zsh`
* **Pre-Apply Safety Backup:** Created at `~/.dotfiles.backup.20261017_001018/`

### 5.2 Verification Checklist & Results

| Component | Tested Command / Behavior | Status | Evidence / Notes |
|---|---|---|---|
| **Safety Backup** | `cp -PR` of active dotfiles | PASS | All active files backed up to `~/.dotfiles.backup.20261017_001018/` |
| **Apply Execution** | `chezmoi apply -v --force` | PASS | Exit code 0; rendered templates and executed run-once hooks |
| **PATH Hierarchy** | `zsh -lic 'echo $PATH'` | PASS | Correct order: `~/.local/share/mise/shims`, `/usr/local/bin`, `~/.local/bin` |
| **Polyglot Runtimes** | `mise current` | PASS | Go `1.27.2`, Python `3.12.15`, Node `22.23.3` operational |
| **Starship Prompt** | `starship prompt` | PASS | Rendered directory, git branch, and prompt symbol cleanly |
| **Zsh Environment** | `HISTFILE`, `HISTSIZE=50000` | PASS | History persistence, `unsetopt NOMATCH`, and local config sourcing |
| **Legacy Sourcing** | Sourcing `dotfiles-local/` | PASS | Sourced `work.secret.env`, `~/.aliases`, `~/.zshrc.local` without errors |
| **Git Configuration** | `git config user.email` | PASS | Resolved `Simar Singh <simarpaulsingh@gmail.com>`, editor `code --wait` |
| **GitHub SSH Auth** | `ssh -T -p 443 git@ssh.github.com` | PASS | `Hi simars! You've successfully authenticated, but GitHub does not provide shell access.` |
| **Tmux Config** | `tmux -f ~/.tmux.conf start-server` | PASS | Exit code 0, all vi-keys and mouse settings validated |
| **Age Hybrid Encryption**| `chezmoi add --encrypt` + `chezmoi cat` | PASS | Created age header with both `-> ssh-rsa` and `-> X25519` recipients; decrypted cleanly |

### 5.3 Key Bottlenecks Solved

1. **Intel macOS Tier 3 Homebrew Deprecation:**
   * *Problem:* Homebrew deprecated precompiled bottles for Intel x86_64 on newer macOS releases. Without bottles, `brew bundle` tried to build LLVM, Rust, and dependencies from source, failing due to older Xcode/CLT.
   * *Fix:* Configured `export HOMEBREW_NO_BOTTLE_SOURCE_FALLBACK=1` and `--no-upgrade` in `run_onchange_before_00_install_packages.sh.tmpl`. Core CLI tools (`mise`, `age`, `starship`) are reliably downloaded as standalone precompiled binaries into `~/.local/bin`.
2. **Go Age Internal Library vs External Age Binary:**
   * *Problem:* Chezmoi's internal age library (`useBuiltin = true`) failed on SSH RSA recipients with `malformed recipient ...: mixed case`.
   * *Fix:* Configured `useBuiltin = false` in `.chezmoi.toml.tmpl`. Chezmoi now delegates to the external `age` binary (`~/.local/bin/age`), which natively supports RSA and Ed25519 SSH recipients.
3. **Headless SSH & Non-TTY Prompts:**
   * *Problem:* In automated SSH sessions without a TTY, `promptStringOnce` failed because `/dev/tty` could not be opened.
   * *Fix:* Supplied fallback defaults to `promptStringOnce` (`email` -> `"simarpaulsingh@gmail.com"`, `name` -> `"Simar Singh"`) and `promptBoolOnce` (`is_work` -> `false`).
4. **Git URL Rewriting & SSH Agent Forwarding:**
   * *Problem:* With `insteadOf = https://github.com/`, all GitHub access requires SSH keys. On a remote machine over headless SSH, passphrase-protected keys cannot prompt for a passphrase without macOS Keychain GUI integration.
   * *Fix:* Connecting via `ssh -A simars@simars-macbook-16i.example-tailnet.ts.net` forwards the local unlocked SSH agent, enabling remote GitHub operations effortlessly.
5. **Mise Modern TOML Deprecation Warnings:**
   * *Problem:* Mise warned that root-level `uv_venv_auto` and `default_packages_file` keys are deprecated.
   * *Fix:* Grouped under `[settings.python]` table in `~/.config/mise/config.toml`.

### 5.4 Deferred / Future Considerations & Chezmoi Handling

For full architectural details and recovery roadmaps, see [FUTURE_CONSIDERATIONS.md](FUTURE_CONSIDERATIONS.md).

* **Intel Mac Command Line Tools Update:**
  * *Automated Handling:* Pre-package hook checks `xcode-select -p` and triggers prompt. Added `cz-update-clt` alias (`softwareupdate --all --install --force`) for one-command system updates.
* **Homebrew Formula Cleanup on Intel:**
  * *Automated Handling:* Automated `brew autoremove && brew cleanup -s` executes in `run_onchange_before_00_install_packages.sh.tmpl`. Added `cz-brew-prune` alias to `.zshrc`.
* **Keychain Unlock for Remote Secondary Machine:**
  * *Automated Handling:* `.zprofile` preloads Keychain credentials via `ssh-add --apple-load-keychain`. Added `run_once_after_10_ssh_keychain.sh.tmpl` which automatically enrolls `~/.ssh/id_rsa` into macOS Keychain when run interactively.
* **Interactive Navigation (`zi` / `zoxide`):**
  * *Automated Handling:* Added `zoxide` and `fzf` to `packages.toml` with standalone curl fallbacks so `z` and `zi` are guaranteed to work across all architectures.

---

## 6. Day-to-Day Operations Cheat Sheet

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
