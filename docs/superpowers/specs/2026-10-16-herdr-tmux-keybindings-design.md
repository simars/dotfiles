# Herdr Tmux Keybindings Design Specification

## Overview
Configure Herdr to provide an authentic `tmux` keybinding and navigation experience matching the user's primary workflow (`C-b` prefix, vim-style pane navigation, standard split & window management) while retaining Herdr-specific AI capabilities.

The configuration will reside in `~/dotfiles-local/herdr.config.toml` and be symlinked to `~/.config/herdr/config.toml`, following the user's established `dotfiles-local` customization architecture.

---

## File Architecture

1. **Source File**: `~/dotfiles-local/herdr.config.toml`
2. **Target Symlink**: `~/.config/herdr/config.toml` -> `~/dotfiles-local/herdr.config.toml`
3. **Backup File**: `~/.config/herdr/config.toml.bak` (created prior to linking)

---

## Keybinding Specifications

### Prefix
* **Prefix Key**: `"ctrl+b"` (Herdr's single prefix key matching tmux default `C-b`)

### Pane Splits
* **Vertical Split (Left / Right)**:
  * Primary (Native): `"prefix+%"`
  * Secondary (Mnemonic command): `"prefix+v"` (`herdr pane split --current --direction right`)
* **Horizontal Split (Top / Bottom)**:
  * Primary (Native): `"prefix+\""`
  * Secondary (Mnemonic command): `"prefix+minus"` (`herdr pane split --current --direction down`)

### Pane Navigation & Manipulation
* **Focus Left**: `"prefix+h"` (Matches `bind-key h select-pane -L`)
* **Focus Down**: `"prefix+j"` (Matches `bind-key j select-pane -D`)
* **Focus Up**: `"prefix+k"` (Matches `bind-key k select-pane -U`)
* **Focus Right**: `"prefix+l"` (Matches `bind-key l select-pane -R`)
* **Cycle Next Pane**: `"prefix+o"` (Matches standard tmux `C-b o`)
* **Toggle Last Active Pane**: `"prefix+;"` (Matches standard tmux `C-b ;`)
* **Break Pane into New Tab**: `"prefix+!"` (Matches standard tmux `C-b !` `break-pane`)
* **Toggle Zoom Pane**: `"prefix+z"` (Matches standard tmux `C-b z`)
* **Close / Kill Pane**: `"prefix+x"` (Matches standard tmux `C-b x`)

### Tab / Window Management
* **New Tab**: `"prefix+c"` (Matches standard tmux `C-b c`)
* **Close Tab**: `"prefix+&"` (Matches standard tmux `C-b &`)
* **Rename Tab**: `"prefix+,"` (Matches standard tmux `C-b ,`)
* **Next Tab**: `"prefix+n"` (Matches standard tmux `C-b n`)
* **Previous Tab**: `"prefix+p"` (Matches standard tmux `C-b p`)
* **Switch Tab 1..9**: `"prefix+1..9"` (1-indexed base matching tmux `base-index 1`)

### Session / Workspace & Navigation Pickers
* **Workspace Picker**: `"prefix+s"` (Matches standard tmux `C-b s` session tree)
* **Rename Workspace**: `"prefix+$"` (Matches standard tmux `C-b $` rename session)
* **Detach Client**: `"prefix+d"` (Matches standard tmux `C-b d`)
* **Scrollback Mode**: `"prefix+["` (Matches standard tmux `C-b [` copy/scroll mode)

### Herdr Feature Re-homing
* **Settings**: `"prefix+shift+s"` (Shifted to free `prefix+s` for workspace picker)
* **Open Notification Target**: `"prefix+shift+o"` (Shifted to free `prefix+o` for pane cycling)
* **Toggle Sidebar**: `"prefix+b"` (Retained for quick AI sidebar expand/collapse)
* **Reload Config**: `"prefix+shift+r"` (Quick reload shortcut)
* **Help Sheet**: `"prefix+?"` (Keybinding reference list)

---

## Visual & UI Settings

```toml
onboarding = false

[ui]
tab_bar_position = "top"
mouse_capture = true
copy_on_select = true

# Placeholders for future customization (defaults retained as requested)
pane_outer_borders = true
pane_gaps = true
```

---

## Verification & Deployment Strategy

1. **Pre-flight Syntax Check**:
   Validate `~/dotfiles-local/herdr.config.toml` using `herdr config check`.
2. **Atomic Symlink Deployment**:
   Back up existing config to `~/.config/herdr/config.toml.bak` if not already linked. Create symlink `ln -sfn ~/dotfiles-local/herdr.config.toml ~/.config/herdr/config.toml`.
3. **Live Server Reload**:
   Reload the live server state via `herdr server reload-config`.
4. **Verification**:
   Perform split, navigation, tab, and session picker tests against running session.
