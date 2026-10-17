# Herdr Tmux Keybindings Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Configure Herdr to support tmux keybindings and navigation patterns via a version-controlled config file in `~/dotfiles-local/` symlinked to `~/.config/herdr/config.toml`.

**Architecture:** Define the key mappings and UI settings in `~/dotfiles-local/herdr.config.toml`. Create a backup of any existing Herdr configuration, establish an atomic symbolic link to `~/.config/herdr/config.toml`, validate syntax with `herdr config check`, and reload the running Herdr server via `herdr server reload-config`.

**Tech Stack:** Herdr CLI / socket API, TOML configuration, macOS zsh / symlinks.

## Global Constraints
- Prefix key: `ctrl+b`
- Dotfiles source path: `~/dotfiles-local/herdr.config.toml`
- Live config path: `~/.config/herdr/config.toml`
- Retain existing `pane_outer_borders = true` and `pane_gaps = true` with configurable placeholders.

---

### Task 1: Create `~/dotfiles-local/herdr.config.toml`

**Files:**
- Create: `/Users/simars/dotfiles-local/herdr.config.toml`

**Interfaces:**
- Produces: Valid TOML configuration file for Herdr containing all tmux mappings and UI settings.

- [x] **Step 1: Write the configuration file**

Write the complete configuration to `/Users/simars/dotfiles-local/herdr.config.toml`:

```toml
# Herdr configuration - Tmux Keybinding Overlay
# Source: ~/dotfiles-local/herdr.config.toml

onboarding = false

[keys]
# Primary Prefix Key
prefix = "ctrl+b"

# --- Splits ---
# Primary native splits
split_vertical = "prefix+%"
split_horizontal = "prefix+\""

# --- Pane Navigation & Manipulation ---
focus_pane_left = "prefix+h"
focus_pane_down = "prefix+j"
focus_pane_up = "prefix+k"
focus_pane_right = "prefix+l"
cycle_pane_next = "prefix+o"
last_pane = "prefix+;"
zoom = "prefix+z"
close_pane = "prefix+x"

# --- Tab / Window Management ---
new_tab = "prefix+c"
close_tab = "prefix+&"
rename_tab = "prefix+,"
next_tab = "prefix+n"
previous_tab = "prefix+p"
switch_tab = "prefix+1..9"

# --- Session / Workspace Management ---
workspace_picker = "prefix+s"
rename_workspace = "prefix+$"
detach = "prefix+d"

# --- Scrollback / Copy Mode ---
edit_scrollback = "prefix+["

# --- Re-homed Herdr Features ---
settings = "prefix+shift+s"
open_notification_target = "prefix+shift+o"
toggle_sidebar = "prefix+b"
reload_config = "prefix+shift+r"
help = "prefix+?"

# --- Secondary Mnemonic Splits ---
[[keys.command]]
key = "prefix+v"
type = "shell"
command = "herdr pane split --current --direction right"

[[keys.command]]
key = "prefix+minus"
type = "shell"
command = "herdr pane split --current --direction down"

[ui]
tab_bar_position = "top"
mouse_capture = true
copy_on_select = true

# Visual border and gap placeholders (defaults retained)
pane_outer_borders = true
pane_gaps = true
```

- [x] **Step 2: Validate configuration syntax using Herdr CLI**

Run:
```bash
HERDR_CONFIG_PATH=/Users/simars/dotfiles-local/herdr.config.toml herdr config check
```
Expected output:
```
config: ok
```

---

### Task 2: Deploy Symlink & Backup Existing Config

**Files:**
- Create: `/Users/simars/.config/herdr/config.toml.bak` (if previous file exists and is not symlink)
- Modify: `/Users/simars/.config/herdr/config.toml` (symlink)

**Interfaces:**
- Consumes: `/Users/simars/dotfiles-local/herdr.config.toml`
- Produces: Active symlink at `/Users/simars/.config/herdr/config.toml` pointing to `~/dotfiles-local/herdr.config.toml`

- [x] **Step 1: Backup existing file if needed and create symlink**

Run:
```bash
if [ -f ~/.config/herdr/config.toml ] && [ ! -L ~/.config/herdr/config.toml ]; then
  cp ~/.config/herdr/config.toml ~/.config/herdr/config.toml.bak
fi
ln -sfn /Users/simars/dotfiles-local/herdr.config.toml /Users/simars/.config/herdr/config.toml
```

- [x] **Step 2: Verify symlink target and check default configuration**

Run:
```bash
ls -la ~/.config/herdr/config.toml
herdr config check
```
Expected output:
```
lrwxr-xr-x ... /Users/simars/.config/herdr/config.toml -> /Users/simars/dotfiles-local/herdr.config.toml
config: ok
```

---

### Task 3: Reload Server & Verify Keybindings

**Files:**
- Modify: Runtime state of running Herdr server

**Interfaces:**
- Consumes: `/Users/simars/.config/herdr/config.toml`

- [x] **Step 1: Reload live Herdr server**

Run:
```bash
herdr server reload-config
```
Expected output:
```
server config reloaded
```
(or exit code 0 acknowledgment if server is currently running)

- [x] **Step 2: Check server and client status**

Run:
```bash
herdr status
```
Expected output:
Shows server active and confirms configuration is loaded cleanly.

- [x] **Step 3: Commit plan doc to dotfiles repository**

Run:
```bash
git -C ~/dotfiles add docs/superpowers/plans/2026-10-16-herdr-tmux-keybindings.md
git -C ~/dotfiles commit -m "docs: add implementation plan for herdr tmux keybindings"
```
