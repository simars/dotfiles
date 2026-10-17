# Cross-Platform Dotfiles (`chezmoi` + `mise` + `age`)

Deterministic workstation setup for **macOS (Apple Silicon & Intel)** and **Ubuntu Linux 26.04 LTS**.

## Fresh Machine Bootstrap

### 1. Provision Age / SSH Secret Key (Optional if using encrypted files)
```bash
# If using native age key:
mkdir -p ~/.config/chezmoi
nano ~/.config/chezmoi/key.txt
chmod 600 ~/.config/chezmoi/key.txt

# Or ensure your SSH key is present:
ls -la ~/.ssh/id_rsa # or ~/.ssh/id_ed25519
```

### 2. Initialize & Apply Dotfiles
```bash
sh -c "$(curl -fsLS https://get.chezmoi.io)" -- init --apply git@github.com:simars/dotfiles.git
```

### 3. Activate Docker Group on Ubuntu (Without Logging Out)
```bash
newgrp docker
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

## Directory Structure Overview
```text
~/.local/share/chezmoi/
├── .github/workflows/ci.yml           # Cross-platform CI matrix (macOS Intel/ARM, Ubuntu)
├── .gitleaks.toml                     # Secret scanner allowlist configuration
├── .chezmoi.toml.tmpl                 # Interactive init config + hybrid encryption setup
├── .chezmoiignore                     # OS-specific filter (ignores macOS Library on Linux)
├── .chezmoidata/
│   └── packages.toml                  # Declarative package definitions (Homebrew + APT)
├── README.md                          # Bootstrap instructions & cheat sheet
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
