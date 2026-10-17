# Workstation Cheatsheet & Agentic Maintenance Design

## 1. Overview & Goals

As the workstation environment expands across macOS Apple Silicon (`arm64`), macOS Intel (`x86_64`), and Ubuntu Linux (`amd64`/`arm64`), having a single, authoritative cheatsheet accessible directly from the terminal ensures instant reference for modern tools, shortcuts, and workflows.

Equally important, to prevent documentation rot as new tools and aliases are introduced in future sessions, the repository must enforce **agentic maintenance** through explicit multi-layer instruction files (`AGENTS.md`, `CLAUDE.md`, `.agents/rules/`), skill updates, and verification checklists.

---

## 2. Core Architecture & Components

### 2.1 The Cheatsheet (`docs/CHEATSHEET.md` & `~/.cheatsheet.md`)
* **Canonical Source:** Located in [`docs/CHEATSHEET.md`](file:///Users/simars/.local/share/chezmoi/docs/CHEATSHEET.md) within the chezmoi dotfiles repository.
* **Home Deployment:** Managed via `dot_cheatsheet.md` in chezmoi, rendering to `~/.cheatsheet.md` on every managed machine.
* **Content Coverage:**
  1. **Modern CLI Utilities & Observability:**
     - Dynamic preview: `fp` (`fzf` with 500-line colored `bat` preview).
     - Directory tree & list: `ll` (`eza -la --icons --git`), `lt` (`eza -T --level=2 --icons`), `ltree` (`eza -T --icons`).
     - Paging & inspection: `preview <file>` (`bat --style=numbers --color=always`).
     - JSON data: `fx <file.json>` (interactive drilldown TUI), `jq <filter>` (stream parsing).
     - Disk usage: `dfh` (`duf`), `duh` (`dust`).
     - System monitoring: `top` (`btop` with GPU/CPU/Memory/Network).
     - HTTP client: `http` / `https` (`httpie`).
  2. **Navigation & Search:**
     - `rg` (ripgrep) flags and patterns.
     - `fzf` keybindings (`Ctrl+R` history search, `Ctrl+T` file widget, `Alt+C` directory cd).
     - `z` (zoxide) smart directory jumping.
  3. **Core Git & Legacy Invariants:**
     - Standard git aliases (`gst`, `gco`, `gcm`, `gl`, `gp`, `gd`).
     - Bare-repo dotfiles helper: `config` (`/usr/bin/git --git-dir=$HOME/.cfg/ --work-tree=$HOME`).
     - Chezmoi workflow: `chezmoi diff`, `chezmoi apply -v`, `chezmoi cd`.
  4. **Runtime & Language Management:**
     - `mise` commands: `mise ls`, `mise use <tool>@<version>`, `mise run`, `mise doctor`.
  5. **Customization & Local Overrides:**
     - Local machine files: `~/.aliases.local`, `~/.zshrc.local`, `~/secrets.env`, `~/work.secret.env`.

### 2.2 Shell Integration: `cheat` & `cheatsheet`
Implemented in [`dot_aliases`](file:///Users/simars/.local/share/chezmoi/dot_aliases):
```bash
# Workstation Cheatsheet Viewer
cheat() {
  local sheet="$HOME/.cheatsheet.md"
  if [ ! -f "$sheet" ]; then
    sheet="$HOME/.local/share/chezmoi/docs/CHEATSHEET.md"
  fi

  if [ ! -f "$sheet" ]; then
    echo "Error: Cheatsheet not found at ~/.cheatsheet.md or ~/.local/share/chezmoi/docs/CHEATSHEET.md" >&2
    return 1
  fi

  if command -v bat &> /dev/null; then
    bat --style=plain --paging=auto "$sheet"
  elif command -v less &> /dev/null; then
    less -RF "$sheet"
  else
    cat "$sheet"
  fi
}
alias cheatsheet="cheat"
```
* **Paging Behavior:** Uses `bat --style=plain --paging=auto` so small outputs print directly while long sections scroll smoothly with `less -RF`.
* **Fallback:** Gracefully cascades to `less` or standard `cat` if `bat` is not installed.
* **Precedence:** Positioned before the sourcing of `~/.aliases.local` so users can customize or extend `cheat` if desired.

### 2.3 Agentic Maintenance Mechanism
To guarantee that future AI assistants and subagents update the cheatsheet whenever features are added, instructions are established at multiple agent discovery tiers:

1. **Repository-Level Instructions (`~/.local/share/chezmoi/AGENTS.md` & `CLAUDE.md`):**
   - Universal guidance file read automatically by coding agents when opening the dotfiles repository.
   - Enforces the **Cheatsheet Maintenance Invariant**:
     > *"Whenever adding, modifying, or removing any package, CLI tool, shell alias, git alias, or runtime configuration, you MUST update docs/CHEATSHEET.md and test `cheat` before marking the task or PR complete."*
   - Re-states critical system invariants (`config` bare-repo alias, local overrides, Gitleaks secret zero-tolerance).
   - Symlinked or mirrored to `CLAUDE.md` for Claude Code compatibility.

2. **User Home Agent Instructions (`~/AGENTS.md`):**
   - Managed via `dot_AGENTS.md` in chezmoi and deployed to `~/AGENTS.md`.
   - Ensures agents starting in the user home directory or other workspaces recognize dotfiles conventions and the cheatsheet maintenance rule.

3. **Antigravity Rule (`.agents/rules/maintain-cheatsheet.md`):**
   - Managed via `dot_agents/rules/maintain-cheatsheet.md` and deployed to `~/.agents/rules/maintain-cheatsheet.md`.
   - Triggers whenever files matching `dot_aliases`, `.chezmoidata/packages.toml`, `dot_zshrc.tmpl`, or `run_onchange_*` are referenced or edited.

4. **Skill Synchronization (`dotfiles-workstation-migration`):**
   - Updates [`dot_agents/skills/dotfiles-workstation-migration/SKILL.md`](file:///Users/simars/.local/share/chezmoi/dot_agents/skills/dotfiles-workstation-migration/SKILL.md) and [`~/.agents/skills/dotfiles-workstation-migration/SKILL.md`](file:///Users/simars/.agents/skills/dotfiles-workstation-migration/SKILL.md) with cheatsheet verification in the verification checklist.

---

## 3. Verification & Acceptance Criteria

1. **Cheatsheet Content:** `docs/CHEATSHEET.md` accurately documents all 8 new tools (`eza`, `bat`, `btop`, `duf`, `dust`, `httpie`, `jq`, `fx`), all aliases (`fp`, `ll`, `lt`, `ltree`, `preview`, `dfh`, `duh`, `top`), git, `mise`, and override points.
2. **Terminal Command:** Running `cheat` and `cheatsheet` renders the cheatsheet with syntax highlighting and clean pagination via `bat`.
3. **Chezmoi Consistency:** `chezmoi apply -v` succeeds without errors on Apple Silicon and remote Intel MacBooks (`simars-macbook-16i`, `simars-macbook-32i`).
4. **Agent Discovery:** `AGENTS.md`, `CLAUDE.md`, and `.agents/rules/maintain-cheatsheet.md` are present, correctly formatted, and contain explicit maintenance instructions.
5. **Security & Gitleaks:** 0 secrets detected; clean pre-commit check.
