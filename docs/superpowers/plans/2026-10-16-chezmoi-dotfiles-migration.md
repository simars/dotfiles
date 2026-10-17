# Cross-Platform Dotfiles Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build and verify a complete, cross-platform `chezmoi` dotfiles repository located at `~/.local/share/chezmoi` using `mise`, hybrid `age` encryption (supporting `~/.ssh/id_rsa` and native age keys), and automated package/runtime bootstrapping.

**Architecture:** Initialize a standalone Git repository at `~/.local/share/chezmoi` holding 24 blueprint files. Configuration files are parameterized via Go templates, packages are defined declaratively in `.chezmoidata/packages.toml`, secrets are protected by hybrid `age` encryption and local `gitleaks` pre-commit hooks, and existing `~/.cfg` and `~/dotfiles` are safely preserved with pre-apply backups.

**Tech Stack:** `chezmoi`, `mise`, `age`, `zsh`, `starship`, `tmux`, `herdr`, `alacritty`, `Neovim` (`lazy.nvim`), `VS Code`, `Docker/Colima`, `gitleaks`, `shellcheck`, GitHub Actions.

## Global Constraints

* Target repository location: `~/.local/share/chezmoi` (standalone Git repository on branch `main`).
* Exact chezmoi prefixes (`dot_`, `private_`, `symlink_`, `run_after_`, `run_onchange_before_`, `run_onchange_after_`) and suffixes (`.tmpl`) must be preserved verbatim.
* Do not delete or overwrite the existing `~/.cfg` bare git repository or `~/dotfiles`.
* Any existing target dotfile in `$HOME` must be backed up to `~/.dotfiles.backup.<timestamp>/` before live apply.
* All shell scripts must pass `shellcheck` (where applicable) and adhere to `set -euo pipefail`.
* Hybrid encryption must support `~/.ssh/id_rsa` identity and public recipient alongside the fallback age key `age1ql3z7hjy54pw3hyww5ayyfg7zqgvc7w3j2elw8zmrj2kg5sfn9aqmcac8p`.

---

### Task 1: Repository Scaffolding & Core Metadata

**Files:**
- Create: `~/.local/share/chezmoi/.chezmoiignore`
- Create: `~/.local/share/chezmoi/README.md`
- Test: Directory presence and Git repository initialization

**Interfaces:**
- Consumes: None
- Produces: `~/.local/share/chezmoi` initialized as a Git repository on `main` branch with `.chezmoiignore` and `README.md`.

- [ ] **Step 1: Create repository directory and initialize Git**

```bash
mkdir -p "$HOME/.local/share/chezmoi"
cd "$HOME/.local/share/chezmoi"
if [[ ! -d .git ]]; then
  git init -b main
fi
```

- [ ] **Step 2: Verify git repository status**

Run: `git -C "$HOME/.local/share/chezmoi" branch --show-current`
Expected: `main`

- [ ] **Step 3: Write `.chezmoiignore`**

Create `~/.local/share/chezmoi/.chezmoiignore`:
```text
README.md
.github/
.github/**
.gitleaks.toml

{{ if ne .chezmoi.os "darwin" }}
Library/
Library/**
{{ end }}
```

- [ ] **Step 4: Write `README.md`**

Create `~/.local/share/chezmoi/README.md`:
```markdown
# Cross-Platform Dotfiles (`chezmoi` + `mise` + `age`)

Deterministic workstation setup for **macOS (Apple Silicon & Intel)** and **Ubuntu Linux 26.04 LTS**.

## Fresh Machine Bootstrap

### 1. Provision Age Secret Key (Optional if using encrypted files)
```bash
mkdir -p ~/.config/chezmoi
nano ~/.config/chezmoi/key.txt
chmod 600 ~/.config/chezmoi/key.txt
```

### 2. Initialize & Apply Dotfiles
```bash
sh -c "$(curl -fsLS https://get.chezmoi.io)" -- init --apply git@github.com:<your-username>/dotfiles.git
```

### 3. Activate Docker Group on Ubuntu (Without Logging Out)
```bash
newgrp docker
```

## Day-to-Day Operations
* **Edit a managed file:** `chezmoi edit ~/.zshrc`
* **Add a new file:** `chezmoi add ~/.config/some-tool/config.toml`
* **Add an encrypted secret:** `chezmoi add --encrypt ~/.ssh/id_ed25519`
* **Pull & apply latest changes:** `chezmoi update`
```

- [ ] **Step 5: Verify files exist and commit**

```bash
cd "$HOME/.local/share/chezmoi"
test -f .chezmoiignore && test -f README.md
git add .chezmoiignore README.md
git commit -m "chore: scaffold chezmoi repository and documentation"
```

---

### Task 2: Declarative Package Registry & System Bootstrapper

**Files:**
- Create: `~/.local/share/chezmoi/.chezmoidata/packages.toml`
- Create: `~/.local/share/chezmoi/run_onchange_before_00_install_packages.sh.tmpl`
- Test: Shell syntax validation with `bash -n` and hash matching

**Interfaces:**
- Consumes: OS detection from chezmoi (`.chezmoi.os`, `.chezmoi.arch`)
- Produces: Automated package installer script that triggers only on package change

- [ ] **Step 1: Write `.chezmoidata/packages.toml`**

Create `~/.local/share/chezmoi/.chezmoidata/packages.toml`:
```toml
[darwin.brew]
formulae = [
    "age",
    "colima",
    "curl",
    "docker",
    "docker-compose",
    "fd",
    "git",
    "gitleaks",
    "mise",
    "neovim",
    "ripgrep",
    "shellcheck",
    "starship",
    "tmux",
    "zsh"
]
casks = [
    "alacritty",
    "font-jetbrains-mono-nerd-font",
    "iterm2",
    "warp",
    "wave"
]

[ubuntu.apt]
packages = [
    "age",
    "build-essential",
    "ca-certificates",
    "curl",
    "fd-find",
    "fontconfig",
    "git",
    "gnupg",
    "neovim",
    "ripgrep",
    "shellcheck",
    "tmux",
    "unzip",
    "zsh"
]
```

- [ ] **Step 2: Write `run_onchange_before_00_install_packages.sh.tmpl`**

Create `~/.local/share/chezmoi/run_onchange_before_00_install_packages.sh.tmpl`:
```bash
#!/usr/bin/env bash
# packages.toml hash: {{ include ".chezmoidata/packages.toml" | sha256sum }}
set -euo pipefail

if [[ "${CHEZMOI_CI:-false}" == "true" ]]; then
    echo "==> CI environment detected: skipping system-level package installation."
    exit 0
fi

{{ if eq .chezmoi.os "darwin" -}}
echo "==> Starting macOS Bootstrap ({{ .chezmoi.arch }})..."

if ! command -v brew &> /dev/null; then
    echo "==> Installing Homebrew..."
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

if [[ -x "/opt/homebrew/bin/brew" ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
elif [[ -x "/usr/local/bin/brew" ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null || /usr/local/bin/brew shellenv)"
fi

echo "==> Synchronizing Homebrew Formulae & Casks via Brew Bundle..."
brew bundle --file=/dev/stdin <<EOF
{{ range .packages.darwin.brew.formulae -}}
brew {{ . | quote }}
{{ end -}}
{{ range .packages.darwin.brew.casks -}}
cask {{ . | quote }}
{{ end -}}
EOF

{{ else if eq .chezmoi.os "linux" -}}
echo "==> Starting Ubuntu Linux Bootstrap ({{ .chezmoi.arch }})..."
export DEBIAN_FRONTEND=noninteractive

sudo apt-get update -y
sudo apt-get install -y \
{{- range .packages.ubuntu.apt.packages }}
    {{ . | quote }} \
{{- end }}
    ;

# Normalize fd-find binary name to fd on Ubuntu
mkdir -p "$HOME/.local/bin"
if command -v fdfind &> /dev/null && ! command -v fd &> /dev/null; then
    ln -sf "$(command -v fdfind)" "$HOME/.local/bin/fd"
fi

# Install Starship if missing
if ! command -v starship &> /dev/null; then
    echo "==> Installing Starship prompt..."
    curl -sS https://starship.rs/install.sh | sh -s -- --yes --bin-dir "$HOME/.local/bin"
fi

# Install Mise if missing
if ! command -v mise &> /dev/null; then
    echo "==> Installing mise polyglot runtime..."
    curl -fsSL https://mise.run | sh
fi

# Install Gitleaks if missing
if ! command -v gitleaks &> /dev/null; then
    echo "==> Installing Gitleaks..."
    GITLEAKS_VERSION="8.21.2"
    ARCH="$(dpkg --print-architecture)"
    if [[ "$ARCH" == "amd64" ]]; then GL_ARCH="x64"; else GL_ARCH="arm64"; fi
    curl -fsSL "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_linux_${GL_ARCH}.tar.gz" \
        | sudo tar -xz -C /usr/local/bin gitleaks
fi

# Install JetBrainsMono Nerd Font on Linux if missing
FONT_DIR="$HOME/.local/share/fonts/JetBrainsMono"
if [[ ! -d "$FONT_DIR" ]]; then
    echo "==> Installing JetBrainsMono Nerd Font..."
    mkdir -p "$FONT_DIR"
    curl -fsSL "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip" -o /tmp/JetBrainsMono.zip
    unzip -q -o /tmp/JetBrainsMono.zip -d "$FONT_DIR"
    rm -f /tmp/JetBrainsMono.zip
    fc-cache -fv &> /dev/null || true
fi

# Install Official Docker Engine if missing
if ! command -v docker &> /dev/null; then
    echo "==> Installing Official Docker Engine..."
    sudo install -m 0755 -d /etc/apt/keyrings
    sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
        | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt-get update -y
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi

if ! getent group docker > /dev/null; then
    sudo groupadd docker
fi
if ! id -nG "$USER" | grep -qw "docker"; then
    sudo usermod -aG docker "$USER"
fi
{{ end -}}
```

- [ ] **Step 3: Verify packages and script template**

Run:
```bash
cd "$HOME/.local/share/chezmoi"
test -f .chezmoidata/packages.toml
test -f run_onchange_before_00_install_packages.sh.tmpl
git add .chezmoidata/packages.toml run_onchange_before_00_install_packages.sh.tmpl
git commit -m "feat: add declarative packages registry and OS bootstrap script"
```

---

### Task 3: Interactive Configuration & Hybrid Encryption Model

**Files:**
- Create: `~/.local/share/chezmoi/.chezmoi.toml.tmpl`
- Create: `~/.local/share/chezmoi/.gitleaks.toml`
- Create: `~/.local/share/chezmoi/run_after_00_install_hooks.sh.tmpl`
- Test: Verification of Gitleaks configuration and pre-commit hook syntax

**Interfaces:**
- Consumes: User prompt variables (`email`, `name`, `is_work`), `~/.ssh/id_rsa.pub`
- Produces: `.chezmoi.toml` renderer, secret allowlist, and git commit hook interceptor

- [ ] **Step 1: Write `.chezmoi.toml.tmpl`**

Create `~/.local/share/chezmoi/.chezmoi.toml.tmpl`:
```toml
{{- $email := promptStringOnce . "email" "What is your Git email address" -}}
{{- $name := promptStringOnce . "name" "What is your Git full name" -}}
{{- $isWork := promptBoolOnce . "is_work" "Is this a work machine" -}}

encryption = "age"

[data]
    email = {{ $email | quote }}
    name = {{ $name | quote }}
    is_work = {{ $isWork }}

[age]
{{- if stat (joinPath .chezmoi.homeDir ".ssh/id_rsa") }}
    identity = "{{ .chezmoi.homeDir }}/.ssh/id_rsa"
{{- else if stat (joinPath .chezmoi.homeDir ".config/chezmoi/key.txt") }}
    identity = "{{ .chezmoi.homeDir }}/.config/chezmoi/key.txt"
{{- end }}
    recipients = [
        {{- $sshPub := joinPath .chezmoi.homeDir ".ssh/id_rsa.pub" -}}
        {{- if stat $sshPub }}
        {{ include $sshPub | trim | quote }},
        {{- end }}
        "age1ql3z7hjy54pw3hyww5ayyfg7zqgvc7w3j2elw8zmrj2kg5sfn9aqmcac8p"
    ]
```

- [ ] **Step 2: Write `.gitleaks.toml`**

Create `~/.local/share/chezmoi/.gitleaks.toml`:
```toml
[extend]
useDefault = true

[allowlist]
description = "Allow encrypted age files, CI mocks, and public age/ssh recipient keys"
paths = [
  '''\.age$''',
  '''\.github/workflows/ci\.yml''',
  '''key\.txt$'''
]
regexes = [
  '''age1[a-z0-9]{58}''',
  '''AGE-SECRET-KEY-1[A-Z0-9]{58}''',
  '''ssh-rsa AAAAB3NzaC1yc2E[A-Za-z0-9+/=]+'''
]
```

- [ ] **Step 3: Write `run_after_00_install_hooks.sh.tmpl`**

Create `~/.local/share/chezmoi/run_after_00_install_hooks.sh.tmpl`:
```bash
#!/usr/bin/env bash
set -euo pipefail

SOURCE_DIR="$(chezmoi source-path)"
HOOK_DIR="${SOURCE_DIR}/.git/hooks"

if [[ -d "${HOOK_DIR}" ]]; then
    cat << 'EOF' > "${HOOK_DIR}/pre-commit"
#!/usr/bin/env bash
set -e

if ! command -v gitleaks &> /dev/null; then
    echo "WARNING: 'gitleaks' binary not found. Skipping staged secret scan."
    exit 0
fi

REPO_ROOT="$(git rev-parse --show-toplevel)"
echo "==> Running Gitleaks secret scan on staged changes..."

if ! gitleaks protect --staged --verbose --config "${REPO_ROOT}/.gitleaks.toml"; then
    echo "=========================================================================="
    echo " COMMIT ABORTED: Gitleaks detected potential unencrypted secrets!"
    echo " Encrypt sensitive files first using: chezmoi add --encrypt <file>"
    echo "=========================================================================="
    exit 1
fi
EOF
    chmod +x "${HOOK_DIR}/pre-commit"
fi
```

- [ ] **Step 4: Verify and commit**

```bash
cd "$HOME/.local/share/chezmoi"
git add .chezmoi.toml.tmpl .gitleaks.toml run_after_00_install_hooks.sh.tmpl
git commit -m "feat: add hybrid age encryption, gitleaks config, and pre-commit hook"
```

---

### Task 4: Shell Configuration, Environment & Prompt

**Files:**
- Create: `~/.local/share/chezmoi/dot_zprofile.tmpl`
- Create: `~/.local/share/chezmoi/dot_zshrc.tmpl`
- Create: `~/.local/share/chezmoi/dot_config/starship.toml.tmpl`
- Test: Syntax check and template variable validation

**Interfaces:**
- Consumes: `.chezmoi.os`, `.is_work`
- Produces: `~/.zprofile`, `~/.zshrc`, `~/.config/starship.toml`

- [ ] **Step 1: Write `dot_zprofile.tmpl`**

Create `~/.local/share/chezmoi/dot_zprofile.tmpl`:
```sh
# 1. Architecture-Aware Homebrew Initialization (macOS)
{{ if eq .chezmoi.os "darwin" -}}
if [[ -x "/opt/homebrew/bin/brew" ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
elif [[ -x "/usr/local/bin/brew" ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
fi
{{ end -}}

# 2. User Binaries & Mise Shims
export PATH="$HOME/.local/bin:$HOME/.local/share/mise/shims:$PATH"

# 3. macOS Colima Docker Socket Routing
{{ if eq .chezmoi.os "darwin" -}}
export DOCKER_HOST="unix://${HOME}/.colima/default/docker.sock"
{{ end -}}
```

- [ ] **Step 2: Write `dot_zshrc.tmpl`**

Create `~/.local/share/chezmoi/dot_zshrc.tmpl`:
```sh
# Ensure local bin is always in PATH for interactive non-login shells
export PATH="$HOME/.local/bin:$PATH"

{{ if eq .chezmoi.os "darwin" -}}
if [[ -x "/opt/homebrew/bin/brew" ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
elif [[ -x "/usr/local/bin/brew" ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
fi
alias flushdns="sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder"
alias brews="brew update && brew upgrade && brew cleanup"
alias d-up="colima start --cpu 4 --memory 8 --disk 40"
alias d-down="colima stop"
{{ else if eq .chezmoi.os "linux" -}}
alias update="sudo apt-get update && sudo apt-get upgrade -y"
{{ end -}}

# Global Navigation & Tool Aliases
alias ll="ls -lah"
alias g="git"
alias cz="chezmoi"
alias tm="tmux new-session -A -s main"

# Container Lifecycle Helpers
dkill() {
    for d in */; do
        if [[ -f "${d}docker-compose.yml" || -f "${d}docker-compose.yaml" ]]; then
            (cd "$d" && docker compose down)
        fi
    done
}
alias dprune="docker system prune -a --volumes -f"

# Zsh Completions
autoload -Uz compinit && compinit -C

# Mise Polyglot Runtime Activation
export MISE_ENV_AUTO_RELOAD=1
if command -v mise &> /dev/null; then
    eval "$(mise activate zsh)"
fi

# Starship Prompt Activation
if command -v starship &> /dev/null; then
    eval "$(starship init zsh)"
fi
```

- [ ] **Step 3: Write `dot_config/starship.toml.tmpl`**

Create `~/.local/share/chezmoi/dot_config/starship.toml.tmpl`:
```toml
format = """
$os$directory$git_branch$git_status$docker_context\
$line_break$character"""

[directory]
style = "bold blue"
truncate_to_repo = true

[git_branch]
symbol = "🌱 "
style = "bold magenta"

[character]
{{- if .is_work }}
success_symbol = "[💼 ❯](bold purple)"
{{- else }}
success_symbol = "[⚡ ❯](bold green)"
{{- end }}
error_symbol = "[❌ ❯](bold red)"

[docker_context]
symbol = "🐳 "
style = "bold cyan"
only_with_files = true
```

- [ ] **Step 4: Verify and commit**

```bash
cd "$HOME/.local/share/chezmoi"
git add dot_zprofile.tmpl dot_zshrc.tmpl dot_config/starship.toml.tmpl
git commit -m "feat: add shell profile, interactive zshrc, and starship prompt config"
```

---

### Task 5: Polyglot Language Runtimes & Code Editors

**Files:**
- Create: `~/.local/share/chezmoi/dot_config/mise/config.toml`
- Create: `~/.local/share/chezmoi/dot_config/mise/default-python-packages`
- Create: `~/.local/share/chezmoi/run_onchange_after_90_sync_runtimes.sh.tmpl`
- Create: `~/.local/share/chezmoi/dot_config/Code/User/settings.json.tmpl`
- Create: `~/.local/share/chezmoi/Library/Application Support/Code/User/symlink_settings.json.tmpl`
- Create: `~/.local/share/chezmoi/run_onchange_after_95_vscode_extensions.sh.tmpl`
- Create: `~/.local/share/chezmoi/dot_config/nvim/init.lua.tmpl`
- Test: Verify JSON syntax, Lua syntax, and lifecycle hook scripts

**Interfaces:**
- Consumes: `.chezmoi.homeDir`
- Produces: `mise` configuration, Neovim self-bootstrapper, and VS Code settings & extensions

- [ ] **Step 1: Write `mise` configuration and default packages**

Create `~/.local/share/chezmoi/dot_config/mise/config.toml`:
```toml
[tools]
go = "latest"
python = "3.12"
node = "22"

[settings]
experimental = true
python_venv_auto_create = true
python_default_packages_file = "~/.config/mise/default-python-packages"
```

Create `~/.local/share/chezmoi/dot_config/mise/default-python-packages`:
```text
pip
wheel
ruff
black
pytest
```

- [ ] **Step 2: Write `run_onchange_after_90_sync_runtimes.sh.tmpl`**

Create `~/.local/share/chezmoi/run_onchange_after_90_sync_runtimes.sh.tmpl`:
```bash
#!/usr/bin/env bash
# mise config hash: {{ include "dot_config/mise/config.toml" | sha256sum }}
set -euo pipefail

if [[ "${CHEZMOI_CI:-false}" == "true" ]]; then
    echo "==> CI environment detected: skipping mise runtime compilation."
    exit 0
fi

export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"

if command -v mise &> /dev/null; then
    echo "==> Synchronizing Mise language runtimes..."
    mise install --yes
fi
```

- [ ] **Step 3: Write VS Code settings and extension installer**

Create `~/.local/share/chezmoi/dot_config/Code/User/settings.json.tmpl`:
```json
{
  "editor.fontSize": 14,
  "editor.fontFamily": "'JetBrainsMono Nerd Font', 'Fira Code', Menlo, monospace",
  "editor.fontLigatures": true,
  "editor.lineNumbers": "relative",
  "editor.minimap.enabled": false,
  "editor.renderWhitespace": "selection",
  "editor.formatOnSave": true,
  "editor.tabSize": 2,
  "files.trimTrailingWhitespace": true,
  "files.insertFinalNewline": true,
  "workbench.colorTheme": "Tokyo Night",
  "terminal.integrated.defaultProfile.osx": "zsh",
  "terminal.integrated.defaultProfile.linux": "zsh",
  "terminal.integrated.fontSize": 13,
  "terminal.integrated.fontFamily": "JetBrainsMono Nerd Font",
  "terminal.integrated.cursorBlinking": true,
  "security.workspace.trust.untrustedFiles": "open"
}
```

Create `~/.local/share/chezmoi/Library/Application Support/Code/User/symlink_settings.json.tmpl`:
```text
{{ .chezmoi.homeDir }}/.config/Code/User/settings.json
```

Create `~/.local/share/chezmoi/run_onchange_after_95_vscode_extensions.sh.tmpl`:
```bash
#!/usr/bin/env bash
set -euo pipefail

if [[ "${CHEZMOI_CI:-false}" == "true" ]]; then
    exit 0
fi

export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$PATH"

if command -v code &> /dev/null; then
    echo "==> Synchronizing VS Code extensions..."
    EXTENSIONS=(
        "golang.go"
        "ms-python.python"
        "ms-python.black-formatter"
        "eamodio.gitlens"
        "esbenp.prettier-vscode"
        "enkia.tokyo-night"
    )
    for ext in "${EXTENSIONS[@]}"; do
        code --install-extension "$ext" --force &> /dev/null || true
    done
fi
```

- [ ] **Step 4: Write `dot_config/nvim/init.lua.tmpl`**

Create `~/.local/share/chezmoi/dot_config/nvim/init.lua.tmpl`:
```lua
-- Leader & Core Options
vim.g.mapleader = " "
vim.g.maplocalleader = " "
vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.mouse = "a"
vim.opt.clipboard = "unnamedplus"
vim.opt.expandtab = true
vim.opt.shiftwidth = 4
vim.opt.tabstop = 4
vim.opt.ignorecase = true
vim.opt.smartcase = true
vim.opt.termguicolors = true
vim.opt.signcolumn = "yes"
vim.opt.updatetime = 250
vim.opt.timeoutlen = 300

-- Bootstrap lazy.nvim (compatible with vim.uv and vim.loop)
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
local uv = vim.uv or vim.loop
if not uv.fs_stat(lazypath) then
  vim.fn.system({
    "git", "clone", "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git", "--branch=stable", lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

-- Plugin Specifications
require("lazy").setup({
  {
    "folke/tokyonight.nvim",
    lazy = false,
    priority = 1000,
    config = function()
      vim.cmd([[colorscheme tokyonight-night]])
    end,
  },
  {
    "nvim-telescope/telescope.nvim",
    dependencies = { "nvim-lua/plenary.nvim" },
    keys = {
      { "<leader>ff", "<cmd>Telescope find_files<cr>", desc = "Find Files" },
      { "<leader>fg", "<cmd>Telescope live_grep<cr>", desc = "Live Grep" },
      { "<leader>fb", "<cmd>Telescope buffers<cr>", desc = "Buffers" },
    },
  },
  {
    "nvim-treesitter/nvim-treesitter",
    build = ":TSUpdate",
    config = function()
      local status_ok, configs = pcall(require, "nvim-treesitter.configs")
      if status_ok then
        configs.setup({
          ensure_installed = { "lua", "vim", "bash", "go", "python", "json", "yaml" },
          highlight = { enable = true },
        })
      end
    end,
  },
})
```

- [ ] **Step 5: Verify syntax and commit**

```bash
cd "$HOME/.local/share/chezmoi"
git add dot_config/mise run_onchange_after_90_sync_runtimes.sh.tmpl \
        dot_config/Code "Library/Application Support/Code" \
        run_onchange_after_95_vscode_extensions.sh.tmpl \
        dot_config/nvim
git commit -m "feat: add mise polyglot runtimes, nvim lazy bootstrap, and VS Code configs"
```

---

### Task 6: Multiplexers, Terminals & Remote Auth

**Files:**
- Create: `~/.local/share/chezmoi/dot_config/tmux/tmux.conf`
- Create: `~/.local/share/chezmoi/dot_tmux.conf.tmpl`
- Create: `~/.local/share/chezmoi/dot_config/herdr/config.yaml`
- Create: `~/.local/share/chezmoi/dot_config/alacritty/alacritty.toml`
- Create: `~/.local/share/chezmoi/dot_gitconfig.tmpl`
- Create: `~/.local/share/chezmoi/private_dot_ssh/private_config.tmpl`
- Test: File creation and permissions verification

**Interfaces:**
- Consumes: `.name`, `.email`, `.is_work`
- Produces: `~/.tmux.conf`, `~/.config/tmux/tmux.conf`, `~/.config/herdr/config.yaml`, `~/.config/alacritty/alacritty.toml`, `~/.gitconfig`, `~/.ssh/config` (0600)

- [ ] **Step 1: Write tmux configuration**

Create `~/.local/share/chezmoi/dot_config/tmux/tmux.conf`:
```tmux
# Standard Prefix (Ctrl-b)
set -g prefix C-b
bind C-b send-prefix

# Terminal & True Color
set -g default-terminal "tmux-256color"
set -ag terminal-overrides ",xterm-256color:RGB"

# Ergonomics & Indexing
set -g mouse on
set -g base-index 1
setw -g pane-base-index 1
set -g renumber-windows on
set -sg escape-time 0
set -g history-limit 50000

# Standard Splits (preserve current working directory)
bind '"' split-window -v -c "#{pane_current_path}"
bind % split-window -h -c "#{pane_current_path}"
bind c new-window -c "#{pane_current_path}"

# Vi-Style Pane Navigation
setw -g mode-keys vi
bind h select-pane -L
bind j select-pane -D
bind k select-pane -U
bind l select-pane -R

# Quick Config Reload
bind r source-file ~/.config/tmux/tmux.conf \; display-message "tmux.conf reloaded"
```

Create `~/.local/share/chezmoi/dot_tmux.conf.tmpl`:
```tmux
source-file ~/.config/tmux/tmux.conf
```

- [ ] **Step 2: Write herdr configuration**

Create `~/.local/share/chezmoi/dot_config/herdr/config.yaml`:
```yaml
leader: "ctrl+b"

bindings:
  split_horizontal: "%"
  split_vertical: '"'
  new_pane: "c"
  close_pane: "x"
  nav_left: "h"
  nav_down: "j"
  nav_up: "k"
  nav_right: "l"
  nav_left_alt: "left"
  nav_down_alt: "down"
  nav_up_alt: "up"
  nav_right_alt: "right"

settings:
  shell: "zsh"
  mouse_events: true
  synchronize_on_start: false
```

- [ ] **Step 3: Write Alacritty configuration**

Create `~/.local/share/chezmoi/dot_config/alacritty/alacritty.toml`:
```toml
[window]
padding = { x = 12, y = 12 }
dynamic_padding = true
opacity = 0.95
decorations = "buttonless"

[font]
size = 14.0
normal = { family = "JetBrainsMono Nerd Font", style = "Regular" }
bold = { family = "JetBrainsMono Nerd Font", style = "Bold" }
italic = { family = "JetBrainsMono Nerd Font", style = "Italic" }

[colors.primary]
background = "#1e1e2e"
foreground = "#cdd6f4"

[cursor]
style = "Block"
unfocused_hollow = true
```

- [ ] **Step 4: Write `dot_gitconfig.tmpl`**

Create `~/.local/share/chezmoi/dot_gitconfig.tmpl`:
```ini
[user]
    name = {{ .name }}
    email = {{ .email }}

[core]
    autocrlf = input
{{- if eq .chezmoi.os "darwin" }}
    editor = code --wait
{{- else }}
    editor = nvim
{{- end }}

[init]
    defaultBranch = main

[pull]
    rebase = true

[color]
    ui = auto

{{- if .is_work }}
[url "git@github.com:corporate-org/"]
    insteadOf = https://github.com/corporate-org/
{{- end }}
```

- [ ] **Step 5: Write `private_dot_ssh/private_config.tmpl`**

Create `~/.local/share/chezmoi/private_dot_ssh/private_config.tmpl`:
```text
Host *
    AddKeysToAgent yes
    IdentitiesOnly yes
{{- if eq .chezmoi.os "darwin" }}
    UseKeychain yes
{{- end }}

Host github.com
    HostName ssh.github.com
    Port 443
    User git
    IdentityFile ~/.ssh/id_ed25519

{{- if .is_work }}
Host *.internal.company.com
    User engineering
    IdentityFile ~/.ssh/id_ed25519_work
{{- end }}
```

- [ ] **Step 6: Verify and commit**

```bash
cd "$HOME/.local/share/chezmoi"
git add dot_config/tmux dot_tmux.conf.tmpl dot_config/herdr dot_config/alacritty dot_gitconfig.tmpl private_dot_ssh
git commit -m "feat: add tmux, herdr, alacritty, gitconfig, and ssh configs"
```

---

### Task 7: CI Matrix Workflow, Sandbox Verification & Safety Pre-Flight

**Files:**
- Create: `~/.local/share/chezmoi/.github/workflows/ci.yml`
- Test: GitHub Actions file syntax, local sandbox dry-run execution, pre-apply backup script

**Interfaces:**
- Consumes: All 24 files in `~/.local/share/chezmoi`
- Produces: Verified repository with passing dry-run and ready-to-apply status

- [ ] **Step 1: Write `.github/workflows/ci.yml`**

Create `~/.local/share/chezmoi/.github/workflows/ci.yml`:
```yaml
name: CI Dotfiles Matrix

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]
  workflow_dispatch:

concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

jobs:
  security-and-lint:
    name: Security Scan & ShellCheck
    runs-on: ubuntu-latest
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Run Gitleaks Secret Detector
        uses: gitleaks/gitleaks-action@v2
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          GITLEAKS_CONFIG: .gitleaks.toml

      - name: Install ShellCheck
        run: |
          sudo apt-get update -y
          sudo apt-get install -y shellcheck

      - name: Validate Non-Template Shell Scripts
        run: |
          find . -type f -name "*.sh" -not -name "*.tmpl" -exec shellcheck {} +

  test-matrix:
    name: Test Apply (${{ matrix.os }})
    needs: security-and-lint
    strategy:
      fail-fast: false
      matrix:
        include:
          - os: ubuntu-latest
            arch: x86_64
          - os: macos-13
            arch: x86_64
          - os: macos-14
            arch: arm64
    runs-on: ${{ matrix.os }}
    env:
      CHEZMOI_CI: "true"

    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Install chezmoi & age
        run: |
          if [[ "${{ runner.os }}" == "macOS" ]]; then
            brew install chezmoi age
          else
            sh -c "$(curl -fsLS https://get.chezmoi.io)" -- -b "$HOME/.local/bin"
            echo "$HOME/.local/bin" >> "$GITHUB_PATH"
            sudo apt-get update -y && sudo apt-get install -y age
          fi

      - name: Generate Mock Age Identity Key
        run: |
          mkdir -p ~/.config/chezmoi
          age-keygen -o ~/.config/chezmoi/key.txt
          chmod 600 ~/.config/chezmoi/key.txt

      - name: Initialize chezmoi & Render Config
        run: |
          chezmoi init \
            --source="$GITHUB_WORKSPACE" \
            --promptString "What is your Git email address=ci-bot@example.com" \
            --promptString "What is your Git full name=CI Runner" \
            --promptBool "Is this a work machine=false"

      - name: Verify Template Compilation (chezmoi diff)
        run: chezmoi diff

      - name: Execute Dry-Run Apply
        run: chezmoi apply --dry-run --verbose

      - name: Execute Full Apply in Isolated Runner
        run: chezmoi apply --verbose
```

- [ ] **Step 2: Commit CI workflow**

```bash
cd "$HOME/.local/share/chezmoi"
git add .github/workflows/ci.yml
git commit -m "ci: add multi-os matrix pipeline for macOS and Ubuntu"
```

- [ ] **Step 3: Verify File Count & Directory Structure**

Run:
```bash
cd "$HOME/.local/share/chezmoi"
find . -maxdepth 5 -not -path '*/.git*' | sort
```
Expected: All 24 files listed in Section 3 of design specification present.

- [ ] **Step 4: Install chezmoi locally if not present**

Run:
```bash
if ! command -v chezmoi &>/dev/null; then
  brew install chezmoi
fi
chezmoi --version
```
Expected: `chezmoi version 2.x...`

- [ ] **Step 5: Execute Isolated Sandbox Verification**

Run:
```bash
SANDBOX_DIR="$(mktemp -d)"
CHEZMOI_CI=true chezmoi init \
  --source="$HOME/.local/share/chezmoi" \
  --destination="$SANDBOX_DIR" \
  --config="$SANDBOX_DIR/chezmoi.toml" \
  --promptString "What is your Git email address=you@work.example" \
  --promptString "What is your Git full name=Simar Singh" \
  --promptBool "Is this a work machine=false"

CHEZMOI_CI=true chezmoi diff \
  --source="$HOME/.local/share/chezmoi" \
  --destination="$SANDBOX_DIR" \
  --config="$SANDBOX_DIR/chezmoi.toml"

CHEZMOI_CI=true chezmoi apply --dry-run --verbose \
  --source="$HOME/.local/share/chezmoi" \
  --destination="$SANDBOX_DIR" \
  --config="$SANDBOX_DIR/chezmoi.toml"

rm -rf "$SANDBOX_DIR"
```
Expected: Exit code 0, all templates compile cleanly.

- [ ] **Step 6: Execute Automated Pre-Apply Backup of Existing Dotfiles**

Run:
```bash
BACKUP_DIR="$HOME/.dotfiles.backup.$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"
for file in .zshrc .zprofile .gitconfig .tmux.conf .config/starship.toml .config/tmux/tmux.conf; do
  if [[ -e "$HOME/$file" || -L "$HOME/$file" ]]; then
    mkdir -p "$BACKUP_DIR/$(dirname "$file")"
    cp -P "$HOME/$file" "$BACKUP_DIR/$file"
    echo "Backed up $file -> $BACKUP_DIR/$file"
  fi
done
echo "Backup complete: $BACKUP_DIR"
```
Expected: Existing symlinks (`.gitconfig`, `.tmux.conf`, `.zshrc`) safely archived.

- [ ] **Step 7: Perform Non-Destructive chezmoi diff against actual HOME**

Run:
```bash
chezmoi diff --source="$HOME/.local/share/chezmoi"
```
Expected: Clean diff output displaying proposed changes against `$HOME`.
