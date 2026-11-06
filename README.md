# Cross-Platform Dotfiles (`chezmoi` + `mise` + `age`)

Deterministic workstation setup for **macOS on Apple silicon** (dotfiles and packages), **Intel Macs** (dotfiles; tools by hand, see `docs/INTEL_MACS.md`) and **Omarchy Linux** (dotfiles, plus a short package list installed with `omarchy pkg add`).

## Fresh Machine Bootstrap

### 1. Provision Age / SSH Secret Key (Optional if using encrypted files)
```bash
# If using native age key:
mkdir -p ~/.config/chezmoi
nano ~/.config/chezmoi/key.txt
chmod 600 ~/.config/chezmoi/key.txt

# Or ensure your SSH key is present:
ls -la ~/.ssh/id_rsa
```

### 2. Initialize & Apply Dotfiles
```bash
sh -c "$(curl -fsLS https://get.chezmoi.io)" -- init --apply git@github.com:simars/dotfiles.git
```

---

## Day-to-Day Cheat Sheet

| Task | Command | Description |
|---|---|---|
| **Inspect Pending Changes** | `chezmoi diff` | Show diff between target templates and active `$HOME` |
| **Apply Changes** | `chezmoi apply` | Render templates and apply changes to `$HOME` |
| **Edit a Managed File** | `chezmoi edit ~/.zshrc` | Open source template in `$EDITOR` and re-apply |
| **Add a New File** | `chezmoi add ~/.config/some-tool/config.toml` | Track a new configuration file in chezmoi |
| **Add an Encrypted Secret** | `chezmoi add --encrypt ~/.ssh/id_work` | Encrypt a sensitive file with hybrid age/ssh keys |
| **Pull & Apply Remote Updates** | `chezmoi update` | Pull latest commits from GitHub and apply |
| **Open Source Directory** | `chezmoi cd` | Launch interactive shell inside `~/.local/share/chezmoi` |
| **Check Managed Files** | `chezmoi managed` | List all files currently managed by chezmoi |
| **Inspect System Status** | `chezmoi status` | List state changes between source and destination |
| **Fresh Machine Bootstrap** | `sh -c "$(curl -fsLS https://get.chezmoi.io)" -- init --apply git@github.com:simars/dotfiles.git` | Bootstrap an entire workstation in one command |

---

## Secret Providers (1Password, Bitwarden & Age)
* **1Password:** `1password-cli` is installed by Homebrew on Apple silicon Macs. Retrieve secrets with:
  `{{ onepasswordRead "op://vault/item/field" }}` or `{{ (onepassword "Item" "Vault").password }}`
* **Bitwarden:** `bitwarden-cli` is auto-installed. Unlock with `bw login` / `export BW_SESSION="$(bw unlock --raw)"` and retrieve secrets with:
  `{{ (bitwarden "item" "ItemName").notes }}` or `{{ (bitwardenFields "item" "ItemName").fieldName.value }}`
* **Hybrid Age:** Encrypt standalone secret files directly using `chezmoi add --encrypt ~/.ssh/id_work`. Unlocks with `~/.ssh/id_rsa` or `key.txt`. Uses the external `age` binary (`useBuiltin = false`) to natively support `ssh-rsa` and `ssh-ed25519` key formats.

---

## Cross-Platform & Remote Management Notes

* **Apple Silicon vs. Intel macOS:**
  * Apple Silicon (`arm64`): Homebrew installs to `/opt/homebrew`, full precompiled bottle coverage.
  * Intel (`x86_64`): Homebrew lives in `/usr/local` and is Tier 3 there; it compiles any formula without an Intel bottle. `chezmoi apply` installs no packages on Intel Macs: install tools by hand with `docs/INTEL_MACS.md`, which also checks what Homebrew can pour without compiling.
* **Remote Machine Management (`ssh -A`):**
  * Dotfiles configure Git to route GitHub URLs through `ssh.github.com:443`.
  * When administering secondary machines over SSH headlessly, connect with agent forwarding:
    ```bash
    ssh -A <user>@<host>
    ```
    This allows remote `git`, `chezmoi update`, and GitHub access to authenticate seamlessly using your workstation's unlocked agent without storing unencrypted keys or typing passphrases.
* **Non-Interactive / Headless Bootstrap:**
  * `.chezmoi.toml.tmpl` includes fallback defaults (`simarpaulsingh@gmail.com`, `Simar Singh`, `is_work = false`) so automated or headless installations run cleanly without requiring an interactive TTY.


## Directory Structure Overview
```text
~/.local/share/chezmoi/
├── .github/workflows/ci.yml           # CI: secret scan, shellcheck, host profiles and a test apply on Ubuntu, Intel and Apple silicon macOS
├── .gitleaks.toml                     # Secret scanner allowlist configuration
├── .gitignore                         # Local key and OS artifact exclusion
├── .chezmoi.toml.tmpl                 # Interactive init config + hybrid encryption setup
├── .chezmoiignore                     # Repository metadata exclusion
├── .chezmoidata/
│   └── packages.toml                  # Homebrew formulae and casks for Apple silicon Macs
├── README.md                          # Bootstrap instructions & cheat sheet
├── docs/
│   ├── FUTURE_CONSIDERATIONS.md          # Platform lifecycle roadmap & remediation
│   └── TESTING_AND_VERIFICATION_GUIDE.md # Comprehensive runbook
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
├── dot_local/bin/executable_tat       # tat: attach to or create a tmux session named after the directory
├── dot_zprofile.tmpl                  # Architecture-aware Homebrew & mise shims
├── dot_zshrc.tmpl                     # Aliases, Docker helpers, mise & starship activation
├── private_dot_ssh/
│   └── private_config.tmpl            # Port 443 SSH routing for GitHub + personal hosts
├── run_onchange_before_00_install_packages.sh.tmpl # brew bundle on Apple silicon; a skip message everywhere else
└── run_onchange_after_90_sync_runtimes.sh.tmpl    # Automatic mise tool installer
```
