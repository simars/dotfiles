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
* **Core & Modern Aliases:**
  * `ll` (modern `eza -la --icons --git` listing; gracefully falls back to `ls -lah` if `eza` is missing)
  * `lt` / `ltree` (`eza --tree` directory tree listings)
  * `preview` (`bat` syntax-highlighted pager)
  * `dfh` (`duf` modern disk usage)
  * `duh` (`dust` visual directory disk usage)
  * `top` (`btop` modern resource monitor)
  * `fp` (`fzf` interactive fuzzy search with `bat` syntax-highlighted preview)
  * `g status` (git shortcut)
  * `cz status` (chezmoi shortcut)
  * `brews` (brew upgrade/cleanup shortcut)
  * `d-up` / `d-down` (Colima container helpers)
* **Modern CLI Utilities:**
  ```bash
  which eza bat btop duf dust http jq fx
  head -n 20 ~/.zshrc | bat --style=numbers --color=always
  ```
* **Polyglot Runtimes (`mise`):**
  ```bash
  mise current
  python --version   # Python 3.12.x (with httpie, ruff, black, pytest, pip)
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

## 5. Live Verification on Intel MacBooks (`simars-macbook-16i` & `simars-macbook-32i`)

The entire configuration was deployed and verified across two live Intel macOS machines via SSH (`simars-macbook-16i.example-tailnet.ts.net` and `simars-macbook-32i.example-tailnet.ts.net`).

### 5.1 Environment Profile
* **Host 1:** `simars@simars-macbook-16i.example-tailnet.ts.net` (16-inch Intel MacBook Pro, Core i9 `x86_64`, macOS 26.2 Tahoe)
* **Host 2:** `simars@simars-macbook-32i.example-tailnet.ts.net` (16-inch Intel MacBook Pro, 32GB RAM, Core i9 `x86_64`, macOS 26.5 Tahoe)
* **Architecture:** `x86_64` (Intel)
* **Shell:** `/bin/zsh` (login interactive shell)
* **Homebrew Prefix:** `/usr/local`
* **Pre-Apply Safety Backups:** Created at `~/.dotfiles.backup.20261017_001018/` and `~/.dotfiles.backup.20261017_133040/`

### 5.2 Verification Checklist & Results

| Component | Tested Command / Behavior | Status | Evidence / Notes |
|---|---|---|---|
| **Safety Backup** | `cp -PR` of active dotfiles | PASS | All active files backed up before each apply execution |
| **Apply Execution** | `chezmoi apply -v` | PASS | Exit code 0; rendered templates, applied `.aliases`, executed hooks |
| **PATH Hierarchy** | `zsh -lic 'echo $PATH'` | PASS | Correct order: `~/.local/share/mise/shims`, `/usr/local/bin`, `~/.local/bin` |
| **Polyglot Runtimes** | `mise current` | PASS | Go `1.27.2`, Python `3.12.15`, Node `22.23.3` operational |
| **Starship Prompt** | `starship prompt` | PASS | Rendered directory, git branch, and prompt symbol cleanly |
| **Zsh Environment** | `HISTFILE`, `HISTSIZE=50000` | PASS | History persistence, `unsetopt NOMATCH`, and local config sourcing |
| **Legacy Sourcing** | Sourcing `dotfiles-local/` | PASS | Sourced `work.secret.env`, `~/.aliases`, `~/.zshrc.local` without errors |
| **Git Configuration** | `git config user.email` | PASS | Resolved `Simar Singh <simarpaulsingh@gmail.com>`, editor `code --wait` |
| **GitHub SSH Auth** | `ssh -T -p 443 git@ssh.github.com` | PASS | `Hi simars! You've successfully authenticated, but GitHub does not provide shell access.` |
| **Tmux Config** | `tmux -f ~/.tmux.conf start-server` | PASS | Exit code 0, all vi-keys and mouse settings validated |
| **Herdr Multiplexer** | `which herdr && herdr --version` | PASS | Resolved `/Users/simars/.local/bin/herdr` (`herdr 0.9.5` standalone binary) |
| **Classic Vim** | `which vim && vim --version` | PASS | System / Homebrew `vim` (Vim 9.1) functional with `.vimrc` settings |
| **Neovim** | `which nvim && nvim --version` | PASS | Resolved `nvim` (`v0.10.0` / `v0.12.6`), `init.lua` loaded |
| **LunarVim** | `which lvim && lvim --version` | PASS | Installed via upstream installer into `/Users/simars/.local/bin/lvim` |
| **Age Hybrid Encryption**| `chezmoi add --encrypt` + `chezmoi cat` | PASS | Dual recipients (`-> ssh-rsa` & `-> X25519`) verified; round-trip decrypt succeeded |
| **Modern CLI (`btop`)** | `which btop && btop --version` | PASS | Installed in `/usr/local/bin/btop` (`1.4.7`) via legacy bottle cache |
| **Modern CLI (`duf`)** | `which duf && duf --version` | PASS | Installed in `/usr/local/bin/duf` (`0.9.1`) via legacy bottle cache |
| **Modern CLI (`jq`)** | `which jq && jq --version` | PASS | Installed in `/usr/local/bin/jq` (`1.8.2`) |
| **Modern CLI (`bat`, `dust`, `fx`)** | Standalone GitHub Tarball Fallbacks | PASS | Downloaded to `~/.local/bin` via `run_onchange_before_00_install_packages.sh.tmpl` |
| **Modern CLI (`httpie`)** | `mise` default python package | PASS | Installed via `dot_config/mise/default-python-packages` into Python 3.12 |
| **Modern Alias: `top`** | `type top` | PASS | Resolves to `top is an alias for btop` on both Intel hosts |
| **Modern Alias: `dfh`** | `type dfh` | PASS | Resolves to `dfh is an alias for duf` on both Intel hosts |
| **Modern Alias: `ll`** | `type ll` | PASS | Graceful fallback: cleanly falls back to `ls -lah` when `eza` is unbottled |
| **Guarded Aliases (`fp`, `duh`)** | `type fp && type duh` | PASS | Cleanly inactive / guarded by `command -v`; zero shell syntax or missing command errors |

### 5.3 Key Bottlenecks Solved

1. **Intel macOS Tier 3 Homebrew Deprecation & Modern CLI Strategy:**
   * *Problem:* In September 2026, Homebrew officially transitioned Intel macOS (`x86_64`) to Tier 3 support and stopped building new bottles. Formulae with unbottled dependencies (e.g. `eza` and `bat` requiring `libgit2` and `openssl@4`) attempted to build LLVM/Rust toolchains from source.
   * *Fix:* Configured `export HOMEBREW_NO_BOTTLE_SOURCE_FALLBACK=1` and `--no-upgrade` in `run_onchange_before_00_install_packages.sh.tmpl` to prevent hours of compiling and build crashes. Added automated standalone binary fallbacks for Darwin `x86_64` (`bat`, `dust`, `fx`) in `run_onchange_before_00_install_packages.sh.tmpl`, and added `httpie` to `dot_config/mise/default-python-packages`.
2. **Resilient Shell Alias Guarding & Graceful Degradation:**
   * *Problem:* Aliases for modern utilities (`ll`, `lt`, `preview`, `duh`, `fp`) could crash or cause command errors on architectures where specific binaries are not installed.
   * *Fix:* In `dot_aliases`, all modern aliases are strictly guarded by `if command -v <tool> &> /dev/null`. When `eza` is missing, `ll` cleanly falls back to `ls -lah`. When `bat` is missing, `fp` is not registered, preventing broken interactive subshells. Local overrides (`~/.aliases.local`) source at the end of the file.
3. **Go Age Internal Library vs External Age Binary:**
   * *Problem:* Chezmoi's internal age library (`useBuiltin = true`) failed on SSH RSA recipients with `malformed recipient ...: mixed case`.
   * *Fix:* Configured `useBuiltin = false` in `.chezmoi.toml.tmpl`. Chezmoi now delegates to the external `age` binary (`~/.local/bin/age`), which natively supports RSA and Ed25519 SSH recipients.
4. **Headless SSH & Non-TTY Prompts:**
   * *Problem:* In automated SSH sessions without a TTY, `promptStringOnce` failed because `/dev/tty` could not be opened.
   * *Fix:* Supplied fallback defaults to `promptStringOnce` (`email` -> `"simarpaulsingh@gmail.com"`, `name` -> `"Simar Singh"`) and `promptBoolOnce` (`is_work` -> `false`).
5. **Git URL Rewriting & SSH Agent Forwarding:**
   * *Problem:* With `insteadOf = https://github.com/`, all GitHub access requires SSH keys. On a remote machine over headless SSH, passphrase-protected keys cannot prompt for a passphrase without macOS Keychain GUI integration.
   * *Fix:* Connecting via `ssh -A simars@simars-macbook-16i.example-tailnet.ts.net` forwards the local unlocked SSH agent, enabling remote GitHub operations effortlessly.
6. **Mise Modern TOML Deprecation Warnings:**
   * *Problem:* Mise warned that root-level `uv_venv_auto` and `default_packages_file` keys are deprecated.
   * *Fix:* Grouped under `[settings.python]` table in `~/.config/mise/config.toml`.

### 5.4 Deferred / Future Considerations & Chezmoi Handling

For full architectural details and recovery roadmaps, see [FUTURE_CONSIDERATIONS.md](FUTURE_CONSIDERATIONS.md).

* **Intel Mac Standalone Binary Fallbacks for Unbottled Rust/C++ Tools (`eza`):**
  * *Context:* Homebrew Tier 3 deprecation leaves unbottled rust/C++ formulae without pre-compiled bottles. `bat`, `dust`, `fx`, and `httpie` are now reliably installed via standalone GitHub releases and mise. For `eza`, standalone precompiled releases (`eza-community/eza`) or bottled dependencies will be integrated in a future release; meanwhile, the guarded `ll` alias safely and seamlessly provides `ls -lah`.
* **Intel Mac Command Line Tools Update:**
  * *Automated Handling:* Pre-package hook checks `xcode-select -p` and triggers prompt. Added `cz-update-clt` alias (`softwareupdate --all --install --force`) for one-command system updates.
* **Homebrew Formula Cleanup on Intel:**
  * *Automated Handling:* Automated `brew autoremove && brew cleanup -s` executes in `run_onchange_before_00_install_packages.sh.tmpl`. Added `cz-brew-prune` alias to `.zshrc`.
* **Keychain Unlock for Remote Secondary Machine:**
  * *Automated Handling:* `.zprofile` preloads Keychain credentials via `ssh-add --apple-load-keychain`. Added `run_once_after_10_ssh_keychain.sh.tmpl` which automatically enrolls `~/.ssh/id_rsa` into macOS Keychain when run interactively.
* **Interactive Navigation (`zi` / `zoxide`):**
  * *Automated Handling:* Added `zoxide` and `fzf` to `packages.toml` with standalone curl fallbacks so `z` and `zi` are guaranteed to work across all architectures.

---

## 6. Live Verification on Apple Silicon Mac Studio (`Darwin arm64`)

The dotfiles configuration was deployed live to the primary Apple Silicon workstation (`arm64`).

### 6.1 Environment Profile
* **Host:** `Simars-MacBook-Pro-13.local` (Apple Silicon Mac Studio / M-series `arm64`)
* **Architecture:** `arm64` (Apple Silicon)
* **Kernel & OS:** Darwin 25.6.0 (`macOS 26.6` Tahoe)
* **Homebrew Prefix:** `/opt/homebrew`
* **Shell:** `/bin/zsh`
* **Pre-Apply Safety Backup:** Created at `~/.dotfiles.backup.20261017_121837/`

### 6.2 Verification Checklist & Results

| Component | Tested Command / Behavior | Status | Evidence / Notes |
|---|---|---|---|
| **Safety Backup** | `cp -PR` of active dotfiles | PASS | All active files & configs backed up to `~/.dotfiles.backup.20261017_121837/` |
| **Homebrew Cask Adoption**| `brew install --cask --force wave` | PASS | Successfully adopted existing `/Applications/Wave.app` into Homebrew |
| **Dependency Tab Cleanup**| `brew reinstall libtiff webp` | PASS | Cleared stale keg tab circular dependency warning |
| **Apply Execution** | `chezmoi apply -v` | PASS | Exit code 0; rendered all templates and executed hooks |
| **Homebrew Bundle** | Native `arm64` bottle installations | PASS | All formulae (`age`, `colima`, `gitleaks`, `mise`, `neovim`, `zsh`) & casks installed |
| **PATH Hierarchy** | `zsh -lic 'echo $PATH'` | PASS | Correct order: `mise` runtimes, `/Users/simars/.local/share/mise/shims`, `/Users/simars/.local/bin`, `/opt/homebrew/bin` |
| **Polyglot Runtimes** | `mise current` | PASS | Go `1.27.2`, Python `3.12.15`, Node `22.23.3` operational (`arm64` native) |
| **Default Python Tools** | `pip`, `wheel`, `ruff`, `black`, `pytest` | PASS | Installed automatically into Mise Python 3.12 environment |
| **Starship Prompt** | `TERM=xterm-256color starship prompt` | PASS | Rendered directory, git branch, and `⚡ ❯` symbol cleanly |
| **Directory Navigation** | `zoxide` and `zi` | PASS | `which zoxide` -> `/opt/homebrew/bin/zoxide`, `z` and `zi` shell functions active |
| **Core Utilities** | `fzf`, `rg`, `nvim`, `tmux`, `age`, `gitleaks` | PASS | All binaries resolved in `/opt/homebrew/bin` |
| **Git Configuration** | `git config user.email` | PASS | Resolved `Simar Singh <simarpaulsingh@gmail.com>`, editor `code --wait` |
| **Bare Repo Invariant** | `config status --short` | PASS | Aliased to `git --git-dir=$HOME/.cfg/ --work-tree=$HOME`, zero regressions |
| **Untouched Storage** | Verify `~/.cfg`, `~/dotfiles`, `~/dotfiles-local` | PASS | All legacy repositories and local env files preserved intact |
| **GitHub SSH Auth** | `ssh -T -p 443 git@ssh.github.com` | PASS | `Hi simars! You've successfully authenticated, but GitHub does not provide shell access.` |
| **Tmux Config** | `tmux -f ~/.tmux.conf start-server` | PASS | Exit code 0, vi-keys, mouse support, and reload bindings active |
| **Herdr Multiplexer** | `which herdr && herdr --version` | PASS | Resolved `/opt/homebrew/bin/herdr` (`0.9.5`), tmux parity bindings active |
| **Classic Vim** | `which vim && vim --version` | PASS | Resolved `/opt/homebrew/bin/vim` (`VIM 9.2`), `.vimrc` configurations active |
| **Neovim** | `which nvim && nvim --version` | PASS | Resolved `/opt/homebrew/bin/nvim` (`v0.12.6`), `init.lua` loaded |
| **LunarVim** | `which lvim && lvim --version` | PASS | Installed into `/Users/simars/.local/bin/lvim` (`NVIM v0.12.6`), LuaJIT runtime |
| **Gitleaks Pre-Commit**| `.git/hooks/pre-commit` | PASS | Pre-commit secret scanning active, passed with zero leaks found |
| **Age Hybrid Encryption**| `chezmoi encrypt` + `chezmoi decrypt` | PASS | Dual recipients (`-> ssh-rsa` & `-> X25519`) verified; round-trip decrypt succeeded |
| **Modern CLI Utilities** | `which eza bat btop duf dust http jq fx` | PASS | All 8 modern CLI binaries installed in `/opt/homebrew/bin` via native bottles |
| **Modern Shell Aliases** | `type fp ll lt ltree preview dfh duh top` | PASS | All 8 aliases active and resolved to modern CLI tooling |
| **Dynamic FZF Preview** | `head -n 20 ~/.zshrc \| bat --style=numbers --color=always` | PASS | Syntax highlighting, line numbering, and color formatting rendered cleanly |

### 6.3 Key Bottlenecks Solved on Apple Silicon

1. **Homebrew Keg Tab Circular Dependency (`libtiff`, `webp`):**
   * *Problem:* A stale tab in local Homebrew metadata flagged `Formulae dependency graph sorting found a circular dependency: libtiff, webp` on every brew command.
   * *Fix:* Executed `brew reinstall libtiff webp` which refreshed the bottle receipts from Homebrew API, eliminating the warning.
2. **Cask Application Overwrite Collision (`Wave.app`):**
   * *Problem:* `/Applications/Wave.app` was installed manually before chezmoi migration. `brew bundle` would error on cask collision.
   * *Fix:* Adopted via `brew install --cask --force wave` before running apply, bringing the existing app into declarative Homebrew management.
3. **Age Binary Integration with Chezmoi:**
   * *Problem:* Chezmoi's built-in age Go library fails on `ssh-rsa` recipients with mixed-case format errors.
   * *Fix:* Verified `useBuiltin = false` in `.chezmoi.toml.tmpl` seamlessly invokes `/opt/homebrew/bin/age` on Apple Silicon, flawlessly encrypting for both RSA SSH keys and the automation fallback key.

### 6.4 Core Tools Expansion (Herdr, Vim, Neovim, LunarVim)

To provide an out-of-the-box development and multiplexing environment across all machines:

* **Declarative Packaging:**
  Added `herdr` and `vim` to `.chezmoidata/packages.toml` (`[darwin.brew].formulae` and `[ubuntu.apt].packages`).
* **Resilient Architecture Fallbacks (`run_onchange_before_00_install_packages.sh.tmpl`):**
  * **Apple Silicon:** Homebrew installs precompiled bottles for `herdr`, `vim`, and `neovim`.
  * **Intel macOS:** Because Homebrew on Intel macOS (Tier 3) skips unbottled formulae, the package hook automatically downloads standalone binaries for `herdr` (`0.9.5`) and `neovim` (`0.12.6`) directly from official GitHub releases into `~/.local/bin`. System `/usr/bin/vim` remains operational.
  * **Linux:** APT installs `vim` and `neovim`; standalone binary fallback exists for `herdr`.
* **LunarVim (`lvim`) Automation:**
  Automatically installed via upstream installer (`bash <(curl -fsSL https://raw.githubusercontent.com/lunarvim/lunarvim/master/utils/installer/install.sh) --yes --no-install-dependencies`) once `neovim` and polyglot runtimes are ready.
* **Headless SSH Optimization:**
  Added `StrictHostKeyChecking accept-new` to `private_dot_ssh/private_config.tmpl` to prevent headless git/mise/lvim clones from failing on unverified GitHub host keys.

### 6.5 Modern CLI Tools & Interactive Preview Integration

To provide a modern, performant, and visual command-line workflow:

* **Declarative Packaging:**
  Added `eza`, `bat`, `btop`, `duf`, `dust`, `httpie`, `jq`, and `fx` to `.chezmoidata/packages.toml` (`[darwin.brew].formulae` and `[ubuntu.apt].packages`).
* **Resilient Architecture Fallbacks:**
  * **Apple Silicon:** All modern CLI utilities pour directly from precompiled Homebrew bottles into `/opt/homebrew/bin`.
  * **Intel macOS (`x86_64`):** With Homebrew Tier 3 deprecation, formulae lacking bottles are skipped without hanging. `bat`, `dust`, and `fx` download standalone GitHub release binaries to `~/.local/bin`; `httpie` is installed into the global Python 3.12 environment via `dot_config/mise/default-python-packages`.
* **Interactive FZF Bat Preview (`fp`):**
  The `fp` alias pairs `fzf` with dynamic syntax-highlighted previews:
  `fzf --preview 'bat --style=numbers --color=always --line-range :500 {}'`
* **Guarded Aliases with Graceful Degradation:**
  In `dot_aliases`, modern aliases are guarded with `command -v`. When `eza` is missing, `ll` cleanly falls back to `ls -lah`. Missing optional utilities omit their aliases cleanly without shell errors.

---

## 7. Day-to-Day Operations Cheat Sheet

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

---

## 8. Multi-Machine Verification Matrix

Summary of empirical verification results across all tested developer workstations:

| Target | Binary / Alias | Apple Silicon Mac Studio (`arm64`) | `simars-macbook-16i` (`x86_64`) | `simars-macbook-32i` (`x86_64`) | Strategy & Resolution |
|---|---|---|---|---|---|
| **Binary** | `btop` | `/opt/homebrew/bin/btop` (1.4.7) | `/usr/local/bin/btop` (1.4.7) | `/usr/local/bin/btop` (1.4.7) | PASS (Native Homebrew bottles on ARM & Intel) |
| **Binary** | `duf` | `/opt/homebrew/bin/duf` (0.9.1) | `/usr/local/bin/duf` (0.9.1) | `/usr/local/bin/duf` (0.9.1) | PASS (Native Homebrew bottles on ARM & Intel) |
| **Binary** | `jq` | `/opt/homebrew/bin/jq` (1.8.2) | `/usr/local/bin/jq` (1.8.2) | `/usr/local/bin/jq` (1.8.2) | PASS (Native Homebrew bottles on ARM & Intel) |
| **Binary** | `eza` | `/opt/homebrew/bin/eza` (0.23.5) | Deferred (Tier 3 unbottled) | Deferred (Tier 3 unbottled) | PASS (Native on ARM; guarded fallback on Intel) |
| **Binary** | `bat` | `/opt/homebrew/bin/bat` (0.26.1) | `~/.local/bin/bat` (0.26.1) | `~/.local/bin/bat` (0.26.1) | PASS (Native on ARM; standalone release on Intel) |
| **Binary** | `dust` | `/opt/homebrew/bin/dust` (1.2.6) | `~/.local/bin/dust` (1.2.6) | `~/.local/bin/dust` (1.2.6) | PASS (Native on ARM; standalone release on Intel) |
| **Binary** | `http` | `/opt/homebrew/bin/http` (3.2.4) | Mise Python 3.12 `httpie` | Mise Python 3.12 `httpie` | PASS (Native on ARM; mise default Python on Intel) |
| **Binary** | `fx` | `/opt/homebrew/bin/fx` (40.0.0) | `~/.local/bin/fx` (40.0.0) | `~/.local/bin/fx` (40.0.0) | PASS (Native on ARM; standalone release on Intel) |
| **Alias** | `top` | `alias for btop` | `alias for btop` | `alias for btop` | PASS (Active across all hosts) |
| **Alias** | `dfh` | `alias for duf` | `alias for duf` | `alias for duf` | PASS (Active across all hosts) |
| **Alias** | `preview` | `alias for bat` | `alias for bat` | `alias for bat` | PASS (Active across all hosts) |
| **Alias** | `ll` | `alias for eza -la --icons --git` | `alias for ls -lah` | `alias for ls -lah` | PASS (Modern on ARM; graceful fallback on Intel) |
| **Alias** | `lt` / `ltree` | `alias for eza --tree` | Guarded (cleanly omitted) | Guarded (cleanly omitted) | PASS (Active on ARM; zero errors on Intel) |
| **Alias** | `duh` | `alias for dust` | `alias for dust` | `alias for dust` | PASS (Active with dust binary) |
| **Alias** | `fp` | `alias for fzf --preview ...` | `alias for fzf --preview ...` | `alias for fzf --preview ...` | PASS (Active with bat binary) |

---

## 9. Live Verification on `Simars-MacBook-Work` (Apple Silicon, Rosetta Homebrew)

First migration attempt on an Apple Silicon machine carried over from an Intel Mac: the hardware is `arm64`, but Homebrew is the Intel `/usr/local` install running under Rosetta. The native `/opt/homebrew` changeover was completed later the same day (see §9.6).

### 9.1 Environment Profile
* **Host:** `Simars-MacBook-Work` (Apple M2 Max, 32 GB), macOS 26.6.2 (Darwin 25.6.0)
* **Homebrew:** `/usr/local`, x86_64 under Rosetta (161 formulae, Command Line Tools 11.7)
* **chezmoi:** v2.73.2, native `arm64` in `~/.local/bin`, so `.chezmoi.arch` renders `arm64`
* **Legacy state:** thoughtbot `rcm` (`~/dotfiles` + `~/dotfiles-local`) alongside the bare repo `~/.cfg`
* **Backups:** `~/.dotfiles.legacy.20261017_163746.tar.gz`; `~/.dotfiles.backup.20261017_163746/` with a full symlink manifest and a generated `restore-legacy-symlinks.sh`

### 9.2 Verification Checklist & Results

| Component | Tested Command / Behavior | Status | Evidence / Notes |
|---|---|---|---|
| **Modern CLI (8/8)** | `which eza bat btop duf dust http jq fx` | PASS | `eza`, `btop`, `jq` in `/usr/local/bin` (x86_64); `bat`, `dust`, `fx`, `duf` in `~/.local/bin` (arm64 releases); `http` from mise Python 3.12 |
| **Guarded Aliases** | `type fp ll lt ltree preview dfh duh top` | PASS | All 8 resolve; `ls`, `cat`, `df`, `du` still the system binaries |
| **Bare Repo Invariant** | `config status --short`, `config fsck` | PASS | Alias active, `fsck` clean, 382 tracked files, no remaining dependency on `~/dotfiles` |
| **Polyglot Runtimes** | `mise current` | PASS | Go 1.27.2, Node 22.23.3, Python 3.12.15 (x86_64 builds: the `mise.run` fallback ran under Rosetta `bash`) |
| **Cheatsheet** | `cheat`, `~/.cheatsheet.md` | PASS | Renders through `bat`; contains "Modern CLI & Observability Tools" |
| **Agent Instructions** | repo-only checks | PASS | `AGENTS.md`, `CLAUDE.md`, `.agents/rules/` exist only in the source dir; no `~/AGENTS.md` or `~/CLAUDE.md` |
| **Age Hybrid Encryption** | `chezmoi encrypt --age-recipient` + `age -d` | PASS | Round trip succeeded; configured recipients carry `ssh-rsa` and `X25519` stanzas; `age` v1.3.2 arm64 |
| **Gitleaks** | `gitleaks detect --source ~/.local/share/chezmoi -v` | PASS | No leaks; pre-commit hook active and run on each commit |
| **PATH Hierarchy** | `zsh -lic 'print -l $path'` | PASS | mise runtimes, mise shims, `~/.local/bin`, then `/usr/local/bin` |
| **GitHub SSH** | `ssh -T git@github.com` | PASS | Authenticated with the deployed `~/.ssh/config` |
| **Legacy Retirement** | `find ~ -lname "$HOME/dotfiles/*"` | PASS | 0 live links outside the backup; `~/dotfiles` removed after verification |
| **Per-Repo Excludes** | `git check-ignore -v` probes | PASS | 320 `.git/info/exclude` links repointed to `~/.config/git/info-exclude`; ignore decisions identical before and after; 2,889 dead thoughtbot hook shims removed |

### 9.3 Key Bottlenecks Solved
1. **Intel Homebrew refuses to install on macOS 26:** `Error: Your Command Line Tools (CLT) does not support macOS 26.` Every missing formula failed in `brew bundle`. The arm64 standalone fallbacks covered `bat`, `dust`, `fx`, `age` and `herdr`; `gitleaks` and `duf` have no darwin fallback, so their official v8.30.1 / v0.9.1 `darwin_arm64` releases were installed into `~/.local/bin` after checksum verification.
2. **`~/.cfg` depended on `~/dotfiles`:** its hooks, `info/exclude` and repo-local `core.excludesfile` all pointed into the thoughtbot checkout. Hooks removed, `info/exclude` repointed to the shared list, `core.excludesfile` unset so it inherits the global `~/.gitignore`.
3. **Repo exclude lists lived in `~/dotfiles`:** 320 git dirs created under `init.templatedir=~/.git_template` symlinked `.git/info/exclude` into the checkout. The list is now chezmoi-managed at `~/.config/git/info-exclude`.
4. **Host lines in the thoughtbot `zshrc`:** Windsurf, pnpm, Docker Desktop completions and LM Studio moved to `dotfiles-local/zshrc.local`; the `mysql-client@8.4` lookup now checks both Homebrew prefixes explicitly.
5. **`~/.gitignore` was a hard link to `~/dotfiles/gitignore`:** chezmoi's atomic write replaced it; the local `**/.claude/settings.local.json` pattern was carried into `dot_gitignore`.

### 9.4 Rollout of `c2a5402` to the Other Hosts

| Host | Arch | `~/.cfg` | chezmoi apply | Home-level agent files |
|---|---|---|---|---|
| `simar-mbp` (`Simars-MacBook-Pro-13`) | arm64 | fast-forward to `36bb53b` | Pending set matched expectations exactly; applied | `~/AGENTS.md`, `~/CLAUDE.md`, `~/.agents/rules/maintain-cheatsheet.md` removed |
| `simars-macbook-32i` | x86_64 | fast-forward to `36bb53b` (incl. 2 herdr commits) | Same | Same |
| `simars-macbook-16i` | x86_64 | fast-forward to `36bb53b` | Same | Same |

### 9.5 Same-Day Follow-Up on the Other Hosts

| Host | Exclude links → central | Hook shims removed | Thoughtbot links removed | Legacy dirs | Work identity |
|---|---|---|---|---|---|
| `simar-mbp` | 38 (+ `~/.cfg`) | 342 | 0 | `~/dotfiles` already gone | `~/.gitconfig.local` + `.work`; 5/5 work repos resolve to `@work.example` |
| `simars-macbook-32i` | 92 (+ `~/.cfg`) | 837 | 48 | thoughtbot `~/dotfiles` archived and removed | 7/7 |
| `simars-macbook-16i` | 252 (+ `~/.cfg`) | 2,277 | 41 | `~/dotfiles` (`legacy-backup` clone) and `~/symlinks.dotfiles.thoughtbot` archived and removed | 28/28 |

Verification: `git check-ignore -v` in work trees reports `.git/info/exclude:88:*.env*`, `:125:*.sql` and `:21:node_modules/`; no dangling `info/exclude` links; `~/.cfg` `fsck` clean on every host; `chezmoi status` clean. `chezmoi init` on 32i regenerated its config, which differed from the template only by a trailing newline.

### 9.6 Native Homebrew Changeover (2026-10-17)

`Simars-MacBook-Work` moved to native `/opt/homebrew` (Homebrew 7.0.9, arm64, `Rosetta 2: false`), following [`NATIVE_HOMEBREW_KICKOFF.md`](NATIVE_HOMEBREW_KICKOFF.md). The Intel brew in `/usr/local` is still installed; retiring it is a separate decision.

| Step | Result | Evidence / Notes |
|---|---|---|
| **Command Line Tools** | PASS, but not as the kickoff assumed | The "CLT 11.7" was never a real install. It was a 2019-2020 leftover in `/Library/Developer/CommandLineTools` (Apple Git-126, clang 11.0.3, x86_64, SDKs up to 10.15, no `pkgutil` receipt). Brew's `CLT.installed?` only tests that `usr/bin/clang` exists, so the stale directory overrode Xcode 27.1 and produced "does not support macOS 26". Removed with `sudo rm -rf`, replaced with CLT 26.6 (`xcode-select --install`); receipt `26.6.0.0.1781586589`, `xcode-select -p` still Xcode.app, Intel `brew doctor` reports ready |
| **Homebrew install** | PASS | `arch -arm64 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"`. The installer installs a CLT (and ends with `xcode-select --switch` to it) only when `/Library/Developer/CommandLineTools/usr/bin/git` is missing, so the new CLT had to be in place first |
| **Package script** | PASS | Rendered with `chezmoi execute-template` into a scratch file and run with `/bin/bash`; chezmoi state untouched; 28/28 `packages.toml` formulae native arm64. `cask "wave"` was removed from the scratch copy |
| **Casks** | PASS | `iterm2`, `warp` and (via the later `chezmoi apply`, run over SSH with Wave not running) `wave` adopted: brew adopts an existing app without `--force`, and the app bundles were not modified (`Wave.app` is still dated Apr 16 2026). The `alacritty` cask was disabled on 2026-09-01 (Gatekeeper), so it left `packages.toml` (`cc170f6`) |
| **Go tools** | PASS | All 20 `~/go/bin` tools were x86_64. Rebuilt natively with `go install <module>@<same version>`: 18 at their original versions; `gopls` v0.15.3 and `staticcheck` v0.4.7 pin an `x/tools` whose `tokeninternal` package no longer compiles on Go 1.27 (`invalid array length`), so those two went to the latest releases (`gopls` v0.24.0, `staticcheck` v0.8.2). 20/20 arm64 and smoke-tested; the old binaries were backed up before the swap |
| **Extra formulae** | PASS | 31 Intel leaves installed natively (`gh`, `mysql-client@8.4`, `openjdk` and 28 others). Not installed: `go`, `asdf`, `nvm`, `rbenv` (superseded by mise) and `python@3.8`, `python@3.9`, `python@3.10`, `v8@3.15`, `rc`, `nvtop` (gone, disabled or deprecated) |
| **mise** | PASS | Native 2026.10.13. The x86 `~/.local/bin/mise` and `installs/` were removed; Go 1.27.2, Node 22.23.3 and Python 3.12.15 reinstalled, all arm64, with the default Python packages; shims re-pointed at `/opt/homebrew/bin/mise` |
| **Fallbacks** | PASS | `bat`, `dust`, `fx`, `duf`, `gitleaks`, `age`, `age-keygen`, `herdr` removed from `~/.local/bin` only after the native binary existed (versions identical). The gitleaks hook's PATH includes `/opt/homebrew/bin`, so scanning continues |
| **Intel leftovers** | PASS | `asdf`, then the git 2.49 keg, uninstalled from the Intel brew (asdf was its only dependent; `~/.asdf` kept). Brew left `/usr/local/etc/gitconfig`, which nothing reads |
| **`gh` login** | PASS | The old token was invalid; after `gh auth login -h github.com` the native `/opt/homebrew/bin/gh` reports `Logged in to github.com account simars` (scopes `gist`, `read:org`, `repo`, `workflow`) and `gh api user` returns the login |

Verification suite, run in a clean login shell:

| Component | Status | Evidence / Notes |
|---|---|---|
| **Modern CLI (8/8)** | PASS | All in `/opt/homebrew/bin` (arm64) except `http`, which comes from mise Python 3.12 |
| **Guarded Aliases** | PASS | `fp ll lt ltree preview dfh duh top` resolve; `ls`, `cat`, `df`, `du` are still the system binaries |
| **Bare Repo Invariant** | PASS | `config` alias defined at `dot_zshrc.tmpl:29`; 382 tracked files; `fsck` clean; no `~/dotfiles` |
| **Polyglot Runtimes** | PASS | `mise current`: Go 1.27.2, Node 22.23.3, Python 3.12.15; `node -p process.arch` and `go version` report arm64 |
| **Cheatsheet** | PASS | `cheat` renders; section 6 (terminal apps) was added with the alacritty change |
| **Agent Instructions** | PASS | `AGENTS.md` and `CLAUDE.md` only in the source dir; no `~/AGENTS.md`, `~/CLAUDE.md` or `~/.agents/rules/maintain-cheatsheet.md` |
| **Age Hybrid Encryption** | PASS | The encrypted header carries `ssh-rsa` and `X25519` stanzas (age v1.3.2 arm64). The decrypt half needs the SSH key passphrase, which an agent session cannot supply, so it was run in an interactive terminal: `printf 'x\n' \| chezmoi encrypt \| chezmoi decrypt` round-tripped as expected (confirmed by the operator) |
| **Gitleaks** | PASS | No leaks; `run_after_99_assert_requirements` exits 0: terminal git 2.56.0, `/usr/bin/git` 2.54.0, gitleaks 8.30.1 |
| **PATH Hierarchy** | PASS | mise runtimes, mise shims, `~/.local/bin`, `/opt/homebrew/bin`, then `/usr/local/bin`; `brew --prefix` is `/opt/homebrew` |
| **GitHub SSH** | PASS | Authenticated |
| **Legacy Retirement** | PASS | 0 links into `~/dotfiles` |

Lessons and loose ends:
1. `brew bundle check` reports outdated packages as missing, so it is not a test for "installed"; use `brew list`. Pruning `~/Brewfile` (tracked in `~/.cfg`) took two commits, `a091096` and `77f3d6a`, from 245 to 217 lines.
2. Editing `packages.toml` changes the install script's hash, so the next `chezmoi apply` re-runs `brew bundle`. That is idempotent, and it is what adopted `wave`. Run it with a PATH where `#!/usr/bin/env bash` resolves to the native `/bin/bash` (for example `PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"`); with the Intel brew first on PATH it would pick the x86_64 `/usr/local/bin/bash` (§8.2 of `FUTURE_CONSIDERATIONS.md`).
3. In zsh `path` is tied to `$PATH`, so a script variable named `path` silently empties PATH. Use another name in agent or shell snippets.

### 9.7 Rollout of `cc170f6` and `ae05e62` to All Hosts (2026-10-17 to 2026-10-18)

Both repos were pushed as fast-forwards (`simars/dotfiles` `3bf53a7..ae05e62`, `simars/.cfg` `46b3f35..77f3d6a`; no bypassed rules were reported), then applied on every host.

| Host | Arch | Repos updated by | `chezmoi apply` | Notes |
|---|---|---|---|---|
| `Simars-MacBook-Work` | arm64 | pushed from here | exit 0 | 33 Brewfile entries installed and `wave` adopted; requirement check OK (git 2.56.0, `/usr/bin/git` 2.54.0, gitleaks 8.30.1). Run with a native-first PATH |
| `simar-mbp` | arm64 | `config pull --rebase` and `git pull --ff-only` from GitHub | exit 0 | `wave` already installed; requirement check OK |
| `simars-macbook-32i` | x86_64 | git bundles over `scp` | exit 1 | `brew bundle` printed "no bottle available" for 16 formulae (Tier 3 Intel, source fallback disabled, so nothing was compiled); the requirement check fails (git 2.50.1) |
| `simars-macbook-16i` | x86_64 | git bundles over `scp` | exit 1 | `brew bundle` died with `Error: SIGTERM` in a child process during the cask installs (cause unknown, no debris left); `1password-cli`, `font-jetbrains-mono-nerd-font`, `warp` and `wave` then installed cleanly one at a time; the requirement check fails (git 2.50.1) |

* 32i and 16i hold the same SSH key as the Mac (identical fingerprint) but cannot unlock it from a non-interactive session (`Permission denied (publickey)`), and no agent socket was available for `ssh -A`. The repos were fast-forwarded from verified git bundles instead, each script aborting unless the host sat on the expected prerequisite commit, and each host's `origin/main` ref was advanced to the pushed commit by hand. A later interactive `git fetch` reconciles them.
* The exit 1 on the Intel hosts comes from `run_after_99_assert_requirements`, which is working as intended (see `FUTURE_CONSIDERATIONS.md` §8.5).
* Verified on every host: `chezmoi status` empty apart from the always-run scripts, `~/.cfg` at `77f3d6a` with no changes and a clean `fsck`, `~/.cheatsheet.md` carrying the new section 6, no merge commits.

### 9.8 Standalone git on the Intel Hosts: Rollout of `d87ec39` (2026-10-18)

`d87ec39` builds a pinned git 2.56.0 into `~/.local` on Intel Macs and turns the Apple-git check into a `WARN` there (design and rationale: `FUTURE_CONSIDERATIONS.md` §8.5). It reached the other hosts as a git bundle (`03ed4b4..d87ec39`), the same way as §9.7. It was not yet pushed to GitHub when this section was written.

**The check, tested before rollout** (rendered per architecture, `bash -n` and shellcheck clean):

| Scenario | Result |
|---|---|
| arm64, real machine | Exit 0 |
| Intel, Apple git too old | `WARN`, exit 0 |
| arm64, Apple git too old | `FAIL`, exit 1 (still a hard requirement) |
| Intel, terminal git too old | `FAIL`, exit 1 |

**Rollout:**

| Host | Arch | `chezmoi apply` | Notes |
|---|---|---|---|
| `Simars-MacBook-Work` | arm64 | exit 0 | The install script did not re-run (its arm64 render is byte-identical to before); requirement check OK |
| `simar-mbp` | arm64 | exit 0 | Same |
| `simars-macbook-32i` | x86_64 | exit 0 | Built git 2.56.0 (x86_64) into `~/.local`; keychain helper and `~/.local/etc/gitconfig` present; `git hook list pre-commit` shows `gitleaks`; a synthetic `ghp_` token commit was blocked and the token never appeared in the output; no build directory left in `/tmp`; `/usr/bin/git` is 2.50.1, reported as `WARN` |
| `simars-macbook-16i` | x86_64 | exit 0 | Requirement check printed `OK: terminal git is git 2.56.0 (~/.local/bin/git)`, the `WARN` for `/usr/bin/git` 2.50.1, and "Requirement check passed with warnings". The live token test was run later (see §9.9) |

**Build notes:**
1. Without `NO_RUST=YesPlease` the build stops with `cargo: command not found`, and the osxkeychain helper must be built with the same make flags: with gettext enabled it failed to link. The HTTPS test that failed during the build was caused by the user's own `url.insteadOf` rule, not by a defect in the build.
2. A bash function called from `|| true` ignores `set -e`, so the build steps are chained with `&&`, and the work directory is removed only on success (the log path is printed on failure).

**Finding, 16i: the apply compiled 30 formulae from source and ran for about 7.4 hours.** The apply started around 00:50 and finished at 08:17; the log's own timings add up to 7.1 hours of compilation. The largest builds were `llvm` (1 h 57 min), `llvm@21` (1 h 42 min), `node` (54 min), `rust` (42 min), `mise` (31 min), `zig@0.16` (19 min), `z3` (14 min) and `gettext` (12 min). Many were dependencies of `bitwarden-cli` (`node`, `llvm`, `rust`), `colima` and `curl`.
* The script exports `HOMEBREW_NO_BOTTLE_SOURCE_FALLBACK=1` to forbid exactly this (`AGENTS.md` §4.1). On 32i the same `brew bundle` stopped with `no bottle available!` for formulae such as `git`, `mise`, `neovim`, `vim`, `herdr`, `go`, `httpie` and `openssl@4`, and built nothing. The difference between the hosts was a Homebrew version difference, established later (see §9.9): 32i ran Homebrew 6.0.12, which refuses fresh installs without a bottle, and 16i ran 7.0.9, which only refuses them on arm64 CPUs. `HOMEBREW_NO_BOTTLE_SOURCE_FALLBACK` is not in either version's source.
* Side effects on 16i: `docker` and `docker-compose` built but were not linked (`/usr/local/bin/docker` and `docker-compose` already exist), `vim` was not linked (`share/emacs/site-lisp/cmake/cmake-mode.el` belongs to `cmake`), `neovim` refused to install because `utf8proc` is pinned, `herdr` failed, and `brew autoremove` removed `lua`. A Homebrew-built `git` 2.56.0_1 now also sits in `/usr/local`; the standalone git in `~/.local/bin` is first on the script's PATH. `brew bundle` still ended in the script's "Some Homebrew packages could not be installed ... Continuing" warning, which is why the apply exited 0.
* Follow-up is recorded in `FUTURE_CONSIDERATIONS.md` §8.2. The §9.7 "exit 1" results for the Intel hosts above are superseded by this table.


### 9.9 Guard Rollout and Review of All Four Hosts (2026-10-18)

`105ecac` (bottle-only `brew bundle` on Intel) and `52f1401` (`brew update` with an empty `HOME`) were pushed to `simars/dotfiles` as fast-forwards (`03ed4b4..105ecac`, then `..52f1401`; no merge commits, no bypassed rules). `~/.cfg` was already in sync at `a29d9ff` on all four hosts. `simar-mbp` pulled from GitHub; the Intel hosts, which cannot unlock the SSH key for GitHub, took verified git bundles guarded on the expected prerequisite commit.

**Root cause of the 7-hour build (§9.8), established.** Homebrew 7.0.9 only refuses a fresh install without a bottle on arm64 CPUs (`fresh_install?` in `extend/os/mac/formula_installer.rb`), so on Intel it compiles; Homebrew 6.0.12 refused on any CPU. `HOMEBREW_NO_BOTTLE_SOURCE_FALLBACK` is in neither source. Hence 32i (6.0.12) refused and 16i (7.0.9) compiled, and 32i would have compiled after its brew updated. `brew update` could not update Homebrew on 32i at all, because `~/.gitconfig` rewrites https clones to ssh and `bin/brew` drops every environment variable except `HOME` and `HOMEBREW_*`, so `GIT_CONFIG_GLOBAL` has no effect.

**The guard, tested before it ran for real.** `brew_bundle_bottled_only` was extracted from the rendered script and run on both Intel hosts under the system `/bin/bash` 3.2 with only `brew bundle` stubbed.

| Test | 32i | 16i |
|---|---|---|
| Real Brewfile (28 formulae) | Kept 11 installed or bottled formulae, skipped 17 with the formulae that would need compiling | Kept 25, skipped `herdr`, `neovim`, `vim` |
| Same list plus `nosuchformula` | `WARNING ... installing only what is already installed`; kept only the installed ones | Same |
| On Homebrew 7.0.9 (32i after updating) | Identical skip list to 6.0.12 | n/a (already 7.0.9) |
| Real `brew update` with an empty `HOME` | 6.0.12 to 7.0.9, no temporary directory left | No-op |
| arm64 render of the script | Byte-identical to before (`cmp`), so arm64 hosts do not re-run it | |

**Apply results.**

| Host | `chezmoi apply` | Duration | Notes |
|---|---|---|---|
| `Simars-MacBook-Work` | exit 0 | seconds | Install script did not re-run; requirement check OK (git 2.56.0, `/usr/bin/git` 2.54.0, gitleaks 8.30.1) |
| `simar-mbp` | exit 0 | seconds | Same |
| `simars-macbook-16i` | exit 0 (twice) | 26 s, then 18 s (was 7.4 hours) | Nothing compiled; skipped `herdr`, `neovim`, `vim`; `docker` and `docker-compose` kegs from the earlier compile still failed to link on each apply until they were uninstalled (below) |
| `simars-macbook-32i` | exit 0 | 13 s | Nothing compiled; 17 formulae skipped with reasons; Homebrew was on 7.0.9 |

**Fixes made during the review.**
1. 16i: `brew uninstall docker docker-compose`. They were built unlinked by the earlier compile (Docker Desktop's links occupy `/usr/local/bin`), nothing used them, and `brew bundle` retried the link on every apply. Docker Desktop's CLI is untouched. The guard will not reinstall them (no bottle).
2. 32i: `brew untap homebrew/bundle`, a deprecated tap that `brew bundle` no longer needs (it is built in).
3. 32i and 16i: `mise reshim`. `mise doctor` reported missing shims for Python CLIs (`http`, `httpie`, `https`, `idna`, `markdown-it`, `normalizer`, `pygmentize`); it now reports no problems.
4. 32i and 16i: `brew ruby` turned Homebrew developer mode on during probing; `brew developer off` restored it (the state before was off, since the probe announced the switch).

**Verification on all four hosts.** `chezmoi` at `52f1401`, clean tree, no merge commits, `chezmoi status` shows only the always-run scripts; `~/.cfg` at `a29d9ff`, clean; `~/.cheatsheet.md` carries the new Intel row; a clean-environment login shell resolves git 2.56.0 and the `gitleaks` hook is listed; `mise doctor` has no problems on all four hosts. A random fake `ghp_` token committed in a throwaway repo on 16i was blocked (exit 1, the token never printed, no commit created), and a clean commit passed. On Work, `brew doctor` has only the Command Line Tools notice.

**False alarms, so nobody chases them again.**
* `zsh -lic exit` from a tool shell without a terminal prints `can't change option: zle`; in a pseudo-terminal there is no output.
* `brew doctor` run from a tool shell warns that `/usr/bin` precedes `/opt/homebrew/bin`; a clean login shell has Homebrew first.
* The login PATH lists a few Apple system directories that do not exist (`/var/run/com.apple.security.cryptexd/...`, `/pkg/env/global/bin`, `/Library/Apple/usr/bin`); they come from `/etc/paths.d`.
* On Work the stale-looking `/usr/local/opt/...` branches in `~/.zshrc.local` are `elif` guards that never match now.
* The requirement check uses its own PATH, so on 16i it reports the standalone `~/.local/bin/git` while an interactive shell uses the Homebrew-built `/usr/local/bin/git`; both are 2.56.0.

Open decisions and user actions are in `FUTURE_CONSIDERATIONS.md` §8.6.


### 9.10 Cleanup After the Review (2026-10-18)

Done on the owner's calls after §9.9.

| Host | Removed | Result |
|---|---|---|
| `simars-macbook-16i` | The unrequested leftovers of the 7-hour build, in rounds, protecting every `packages.toml` formula: round 1 `aklomp-base64`, `automake`, `cmake`, `cxxopts`, `go`, `libtool`, `ninja`, `python-setuptools`, `ruby`, `rust`, `sphinx-doc`, `zig@0.16`; round 2 `autoconf`, `llvm`, `llvm@21`, `pkgconf`; round 3 `z3` | Cellar 5.5 GB to 1.3 GB; every `packages.toml` formula still installed; `brew missing` empty |
| `simars-macbook-32i` | `rc`, `gemini-cli` (and `/usr/local/bin/gemini`), `the_silver_searcher`, `pcre`, plus the dependency libraries brew removed with `gemini-cli` (including `icu4c@78`, `fmt`, `readline` and `simdutf`) | `rg` and `zsh` unaffected; `brew doctor` hygiene warnings gone except Xcode 26.2 |
| `Simars-MacBook-Work`, `simar-mbp` | `the_silver_searcher` (and `pcre` on `simar-mbp`, removed by autoremove) | `brew autoremove --dry-run` empty |
| `simars-macbook-32i`, `simars-macbook-16i` | Every remaining explicit install outside `packages.toml`, after checking that nothing depends on it and that no config calls it: `pkgconf`, `telnet`, `tree` on 32i; `ctags`, `dive`, `ghz`, `gotags`, `kompose`, `nvm`, `stow`, `tree`, `watch` on 16i | Both hosts hold exactly the `packages.toml` formulae that Intel can install (11 on 32i, 23 on 16i); `brew missing` empty; `mise doctor` clean; 16i Cellar 1.3 GB to 1.2 GB |
| All four | `brew cleanup --prune=all` | Caches freed 2.5 GB (16i), 1.3 GB (32i), 1.8 GB (`simar-mbp`), 3.8 GB (Work) |

* `ag` on 32i was built against `pcre`, but the current bottle uses `pcre2`, which was already installed. `brew reinstall the_silver_searcher` poured that bottle without compiling and made `pcre` unused. `ag` was then removed anyway because `ripgrep` is the managed search tool and nothing in the dotfiles, editor configs or scripts calls `ag`. `pcre2` stays: `ripgrep` and `zsh` depend on it.
* `~/Brewfile` dropped `brew "rc"`, `brew "the_silver_searcher"` and `cask "mysqlworkbench"` (`.cfg` `8bd73f2`); `brew bundle check` on Work now reports the dependencies as satisfied. `MySQLWorkbench.app` on Work was not touched. The Brewfile still lists `rust`, which is installed natively on Work and is not used on the Intel hosts.
* A smoke test after the cleanup passed on `simar-mbp` and 16i (`rg`, `git`, `zsh`, `jq`, `mise`, `bw`, `http`, `colima`, `curl`). One `bw --version` on 16i printed a line starting "Could not fi" right after the cache cleanup; three reruns and a split of stdout and stderr all gave `2026.10.0`, so it was not reproducible.
* The `tree` hits in the dotfiles are `eza --tree` aliases and an nvim plugin name, not the `tree` binary. The `gotags` hook of the old `vim-go` plugin in `~/.vim/bundle` is optional (no `tagbar` plugin is set up), and nothing sources `nvm`. `~/.nvm` (259 MB, node 10.14.2 and 14.17.3) is data and was not touched.
* A first attempt removed nothing because the candidate list reached `brew` as a single word: zsh does not split an unquoted variable. Use `setopt shwordsplit` or `${=var}` in zsh snippets.
* Left alone on purpose: the non-Homebrew files in `/usr/local` on Work, `~/.nvm` on 16i, and the Xcode update on 32i.

---

## 10. Global Secret-Scanning Hook Verification (2026-10-17)

The hook (`hook.gitleaks` in `~/.gitconfig`, running `~/.config/git/hooks/gitleaks-pre-commit`) was tested in a sandbox with a throwaway global config and repos, on git 2.54.0 (Apple, `Simars-MacBook-Work`) and 2.56.0 (Homebrew, `simar-mbp`). Both versions gave identical results.

| Scenario | Result |
|---|---|
| Clean commit | Committed |
| Commit with a synthetic `ghp_` token | Blocked (exit 1); the token value never appears in the output |
| `git hook list pre-commit` | Lists `gitleaks` |
| `git commit --no-verify` | Committed (bypass works) |
| Repo with its own `.git/hooks/pre-commit` | Both run; the repo hook runs after gitleaks, even when gitleaks blocks |
| `git config hook.gitleaks.enabled false` | Repo opted out |
| Bare repo + separate work tree (the `config` alias) | Clean commit passes, secret blocked |
| Minimal launchd PATH (GUI apps) | Blocked: the hook adds the usual install locations to PATH |
| Malformed `.gitleaks.toml` | Blocked as "gitleaks failed to run", not as a finding (gitleaks exits 3 for findings, 1 for errors) |
| 10,201 staged files (52 MB) | Scanned in 2.6 s |
| Git 2.49 / 2.50.1 (older) | Configuration ignored silently: the secret was committed, which is why the version is asserted |

Rollout: on `Simars-MacBook-Work` the assertion passes and a live test with the real `~/.gitconfig` blocked a synthetic token. On `simar-mbp`, `simars-macbook-32i` and `simars-macbook-16i` the files deployed and `chezmoi apply` exited 1 with the per-check fixes listed in `FUTURE_CONSIDERATIONS.md` §8.5. Superseded: after `d87ec39` all four hosts exit 0 (§9.8).

