# Cheatsheet & Agentic Maintenance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create a comprehensive workstation cheatsheet accessible directly from the terminal (`cheat` / `cheatsheet`), and establish multi-layer agentic maintenance mechanisms (`AGENTS.md`, `CLAUDE.md`, `.agents/rules/`, migration skill) to ensure future AI agents automatically keep it synchronized as new features are added.

**Architecture:**
- **Source:** [`docs/CHEATSHEET.md`](file:///Users/simars/.local/share/chezmoi/docs/CHEATSHEET.md) serves as the canonical cheatsheet markdown documentation.
- **Deployment:** Deployed as `~/.cheatsheet.md` via `dot_cheatsheet.md` managed by chezmoi.
- **Shell Command:** Added to [`dot_aliases`](file:///Users/simars/.local/share/chezmoi/dot_aliases) as a zero-dependency function `cheat` (aliased to `cheatsheet`) rendering with `bat --style=plain --paging=auto` (falling back to `less -RF` or `cat`).
- **Agent Instructions:** Project-level [`AGENTS.md`](file:///Users/simars/.local/share/chezmoi/AGENTS.md) and symlink `CLAUDE.md`, user home `~/AGENTS.md` via `dot_AGENTS.md`, Antigravity rule in `.agents/rules/maintain-cheatsheet.md`, and updated verification checklist in `dotfiles-workstation-migration` skill.

**Tech Stack:**
- chezmoi
- zsh / POSIX shell
- bat / less
- Markdown / Antigravity rule definitions

## Global Constraints

- Never break or override standard POSIX utilities (`ls`, `cat`, `df`, `du`, `top`).
- Never break the `config` bare-repo git alias (`/usr/bin/git --git-dir=$HOME/.cfg/ --work-tree=$HOME`).
- Preserve local machine override precedence (`~/.aliases.local`, `~/.zshrc.local`, `~/secrets.env`, `~/work.secret.env`).
- Maintain 100% Gitleaks compliance (0 leaks detected on every commit).
- Multi-architecture compatibility across Apple Silicon (`arm64`), Intel macOS (`x86_64`), and Ubuntu Linux.

---

### Task 1: Canonical Cheatsheet Documentation & Home File

**Files:**
- Create: `docs/CHEATSHEET.md`
- Create: `dot_cheatsheet.md`

**Interfaces:**
- Produces: `docs/CHEATSHEET.md` and `~/.cheatsheet.md` containing organized tables of all modern CLI tools (`eza`, `bat`, `btop`, `duf`, `dust`, `httpie`, `jq`, `fx`), aliases (`fp`, `ll`, `lt`, `ltree`, `preview`, `dfh`, `duh`, `top`), git workflows (`config`, `gst`, `gco`, etc.), runtime management (`mise`), and local override points.

- [ ] **Step 1: Write `docs/CHEATSHEET.md`**

Create `docs/CHEATSHEET.md` with structured sections:
1. Modern CLI & Observability Tools (`fp`, `ll`, `lt`, `ltree`, `preview`, `fx`, `jq`, `top`, `dfh`, `duh`, `http`).
2. Search & Navigation (`rg`, `fzf`, `z`).
3. Core Git & Bare Repo (`config`, `gst`, `gco`, `gcm`, `gl`, `gp`, `gd`, `chezmoi`).
4. Runtime Version Management (`mise`).
5. Local Configuration & Override Points (`~/.aliases.local`, `~/.zshrc.local`, `~/secrets.env`, `~/work.secret.env`).

- [ ] **Step 2: Create chezmoi managed template `dot_cheatsheet.md`**

Create `dot_cheatsheet.md` linking or rendering content from `docs/CHEATSHEET.md`.

- [ ] **Step 3: Verify formatting and syntax**

Run: `test -f docs/CHEATSHEET.md && test -f dot_cheatsheet.md`
Run: `chezmoi diff dot_cheatsheet.md`
Expected: Diff shows new `~/.cheatsheet.md` file.

- [ ] **Step 4: Commit**

```bash
git -C ~/.local/share/chezmoi add docs/CHEATSHEET.md dot_cheatsheet.md
git -C ~/.local/share/chezmoi commit -m "feat(docs): create canonical workstation cheatsheet"
```

---

### Task 2: Shell Integration for `cheat` & `cheatsheet`

**Files:**
- Modify: `dot_aliases`

**Interfaces:**
- Consumes: `~/.cheatsheet.md` or `~/.local/share/chezmoi/docs/CHEATSHEET.md`
- Produces: Shell function `cheat` and alias `cheatsheet`

- [ ] **Step 1: Write failing subshell test for `cheat`**

Run: `zsh -c 'source dot_aliases && cheat --version'`
Expected: Command not found or function missing.

- [ ] **Step 2: Add `cheat` function and `cheatsheet` alias to `dot_aliases`**

Insert before the final `~/.aliases.local` sourcing block:
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

- [ ] **Step 3: Verify shell function in subshell test**

Run: `zsh -c 'source dot_aliases && type cheat && type cheatsheet'`
Expected: `cheat is a shell function` and `cheatsheet is an alias for cheat`.

- [ ] **Step 4: Commit**

```bash
git -C ~/.local/share/chezmoi add dot_aliases
git -C ~/.local/share/chezmoi commit -m "feat(aliases): add cheat function and cheatsheet alias"
```

---

### Task 3: Agentic Maintenance Instructions (`AGENTS.md`, `CLAUDE.md`, `dot_AGENTS.md`)

**Files:**
- Create: `AGENTS.md`
- Create: `CLAUDE.md` (symlink or mirror)
- Create: `dot_AGENTS.md`

**Interfaces:**
- Produces: Persistent instructions discovered by AI agents in repository root and user home.

- [ ] **Step 1: Create `AGENTS.md` in repository root**

Specify:
1. Mandatory Invariant: Whenever adding, modifying, or removing any package, CLI tool, alias, or workflow, the agent **MUST** update `docs/CHEATSHEET.md` and test `cheat` before completing work.
2. Legacy & Safety Invariants: `config` bare repo alias, local overrides, Gitleaks checks.
3. Architecture-specific guidelines (Apple Silicon vs Intel Tier 3 vs Ubuntu).

- [ ] **Step 2: Symlink or mirror `CLAUDE.md` to `AGENTS.md`**

Ensure Claude-based agents discover identical instructions.

- [ ] **Step 3: Create `dot_AGENTS.md`**

Mirror `AGENTS.md` into chezmoi so `~/AGENTS.md` is deployed to all machines.

- [ ] **Step 4: Verify agent instruction files**

Run: `test -f AGENTS.md && test -f CLAUDE.md && test -f dot_AGENTS.md`
Run: `chezmoi diff dot_AGENTS.md`
Expected: Diff shows new `~/AGENTS.md` file.

- [ ] **Step 5: Commit**

```bash
git -C ~/.local/share/chezmoi add AGENTS.md CLAUDE.md dot_AGENTS.md
git -C ~/.local/share/chezmoi commit -m "feat(agents): add agentic maintenance instructions and rules"
```

---

### Task 4: Antigravity Rule & Custom Skill Synchronization

**Files:**
- Create: `dot_agents/rules/maintain-cheatsheet.md`
- Modify: `dot_agents/skills/dotfiles-workstation-migration/SKILL.md`
- Modify: `/Users/simars/.agents/skills/dotfiles-workstation-migration/SKILL.md`

**Interfaces:**
- Produces: Progressive Antigravity rule triggered on dotfiles modifications; updated skill verification checklist.

- [ ] **Step 1: Create `dot_agents/rules/maintain-cheatsheet.md`**

Define Antigravity rule with triggers for `dot_aliases`, `.chezmoidata/packages.toml`, `dot_zshrc.tmpl`, and `run_onchange_*`, requiring cheatsheet updates whenever changes are made.

- [ ] **Step 2: Update `dotfiles-workstation-migration` skill in `dot_agents/skills/` and `~/.agents/skills/`**

Add cheatsheet verification and agentic maintenance requirements into the skill's post-apply checklist and verification matrix.

- [ ] **Step 3: Verify rule and skill files**

Run: `diff -u dot_agents/skills/dotfiles-workstation-migration/SKILL.md ~/.agents/skills/dotfiles-workstation-migration/SKILL.md`
Expected: Output is empty (files in sync).

- [ ] **Step 4: Commit**

```bash
git -C ~/.local/share/chezmoi add dot_agents/
git -C ~/.local/share/chezmoi commit -m "feat(rules): add cheatsheet maintenance rule and update migration skill"
```

---

### Task 5: Local & Remote Deployment, Verification, and Push

**Files:**
- Test: Local Apple Silicon Mac Studio (`Simars-MacBook-Pro-13.local`)
- Test: Remote Intel MacBook (`simars-macbook-16i`)
- Test: Remote Intel MacBook (`simars-macbook-32i`)

**Interfaces:**
- Deploys changes via `chezmoi apply -v` across all machines and verifies `cheat` execution.

- [ ] **Step 1: Apply locally and verify**

Run: `chezmoi apply -v`
Run: `zsh -i -c 'type cheat && test -f ~/.cheatsheet.md && test -f ~/AGENTS.md'`
Run: `zsh -i -c 'cheat | head -n 30'`
Expected: Successful execution and syntax-highlighted output.

- [ ] **Step 2: Push commits to GitHub `origin/main`**

Run: `git -C ~/.local/share/chezmoi push origin main`
Expected: All commits pushed cleanly.

- [ ] **Step 3: Deploy and verify on `simars-macbook-16i` via SSH**

Run over SSH:
```bash
ssh simars@simars-macbook-16i.example-tailnet.ts.net "cd ~/.local/share/chezmoi && git pull && ~/.local/bin/chezmoi apply -v && zsh -i -c 'type cheat && test -f ~/.cheatsheet.md && test -f ~/AGENTS.md && cheat | head -n 20'"
```
Expected: Successfully updated, `cheat` function active, `~/.cheatsheet.md` and `~/AGENTS.md` present.

- [ ] **Step 4: Deploy and verify on `simars-macbook-32i` via SSH**

Run over SSH:
```bash
ssh simars@simars-macbook-32i.example-tailnet.ts.net "cd ~/.local/share/chezmoi && git pull && ~/.local/bin/chezmoi apply -v && zsh -i -c 'type cheat && test -f ~/.cheatsheet.md && test -f ~/AGENTS.md && cheat | head -n 20'"
```
Expected: Successfully updated, `cheat` function active, `~/.cheatsheet.md` and `~/AGENTS.md` present.

- [ ] **Step 5: Final Gitleaks & Git status verification**

Run: `git -C ~/.local/share/chezmoi status`
Run: `gitleaks detect --source ~/.local/share/chezmoi -v`
Expected: Working tree clean, 0 leaks found.
