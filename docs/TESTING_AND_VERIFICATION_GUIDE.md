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

First migration attempt on an Apple Silicon machine carried over from an Intel Mac: the hardware is `arm64`, but Homebrew is the Intel `/usr/local` install running under Rosetta. The native `/opt/homebrew` changeover is deferred (see `FUTURE_CONSIDERATIONS.md` §8).

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

