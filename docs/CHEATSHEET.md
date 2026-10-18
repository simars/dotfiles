# Workstation Quick Reference & Cheatsheet

A concise, high-density quick reference for modern CLI tools, search and navigation workflows, core Git commands, polyglot runtime management (`mise`), and machine-specific configuration points across macOS and Linux developer workstations.

---

## 1. Modern CLI & Observability Tools

The workstation environment provides modern Rust and Go command-line utilities configured with intelligent fallbacks and dynamic shell integration.

| Category | Command / Alias | Target Tool | Purpose & Usage Example |
| :--- | :--- | :--- | :--- |
| **Dynamic Preview** | `fp` | `fzf` + `bat` | Fuzzy find files with real-time syntax-highlighted preview:<br>`fp` |
| **Directory List** | `ll` | `eza` (or `ls`) | Detailed list with file icons and git status:<br>`ll` (falls back to `ls -lah` if `eza` absent) |
| **Directory Tree (Depth 2)** | `lt` | `eza --tree` | Tree view limited to 2 directory levels:<br>`lt` |
| **Directory Tree (Full)** | `ltree` | `eza --tree` | Recursive directory tree visualization with icons:<br>`ltree [path]` |
| **Syntax Pager** | `preview <file>` | `bat` | View file with line numbers, syntax highlighting, and Git gutter:<br>`preview config.json` |
| **JSON Explorer (Interactive)** | `fx <file.json>` | `fx` | Interactive TUI for navigating, folding, and querying JSON:<br>`fx package.json` or `curl ... \| fx` |
| **JSON Stream Processor** | `jq <filter>` | `jq` | Slice, filter, map, and transform JSON data from streams:<br>`curl -s api.endpoint \| jq '.items[0].id'` |
| **Disk Observability (Table)** | `dfh` | `duf` | Human-friendly visual table of mounted filesystems & usage:<br>`dfh` |
| **Disk Observability (Tree)** | `duh` | `dust` | Graphical tree representation of disk consumption sorted by size:<br>`duh` or `duh -d 2` |
| **System Monitor** | `top` | `btop` | Interactive real-time CPU, memory, disks, and network monitor:<br>`top` |
| **HTTP Client** | `http` / `https` | `httpie` | Intuitive HTTP requests with formatted JSON and colorized output:<br>`http GET api.github.com/users/simars` |

### Guarded Alias Architecture
In `~/.aliases`, modern aliases (`ll`, `lt`, `ltree`, `preview`, `fp`, `dfh`, `duh`, `top`) are strictly guarded with `if command -v <tool> &> /dev/null`. If a tool is not installed or unavailable on legacy architectures, the alias gracefully falls back (e.g. `ll` falling back to `ls -lah`) or remains cleanly inactive without throwing shell syntax errors.

---

## 2. Search & Navigation Shortcuts

### ripgrep (`rg`) Patterns
`ripgrep` recursively searches directories for regex patterns while respecting `.gitignore`.

| Shortcut / Pattern | Purpose | Example |
| :--- | :--- | :--- |
| `rg <query>` | Fast recursive search in current directory | `rg "MISE_ENV_AUTO_RELOAD"` |
| `rg -i <query>` | Case-insensitive search | `rg -i "homebrew"` |
| `rg -t <type> <query>` | Search only files of a specific language/type | `rg -truby "ActiveRecord"`<br>`rg -tpy "dataclass"`<br>`rg -tgo "http.Handler"` |
| `rg -g '<glob>' <query>` | Search only files matching a glob pattern | `rg -g '*.tmpl' "chezmoi"` |
| `rg -l <query>` | List only filenames containing matches | `rg -l "TODO"` |
| `rg -C <num> <query>` | Display context lines before and after matches | `rg -C 3 "func main"` |
| `rg --hidden <query>` | Search hidden files and dotfiles | `rg --hidden "work"` |

### fzf Interactive Keybindings
`fzf` provides fuzzy interactive completion directly in `zsh` sessions:

| Keybinding | Action | Description |
| :--- | :--- | :--- |
| `Ctrl + R` | **History Search** | Fuzzy-search command history. Press `Enter` to run or `Tab` to edit on command line. |
| `Ctrl + T` | **Fuzzy File Finder** | Interactively search and select files from current directory; pastes selected path at cursor. |
| `Alt + C` (or `Esc + C`) | **Directory Jump** | Interactively fuzzy-search subdirectories and immediately `cd` into selection. |

### zoxide (`z`) Directory Jumping
`zoxide` tracks the directories you visit most frequently and jumps to them instantly using fuzzy matching:

| Command | Action | Description |
| :--- | :--- | :--- |
| `z <dir>` | Smart Jump | Jump to highest-ranked directory matching query (e.g. `z chezmoi` -> `~/.local/share/chezmoi`). |
| `zi` | Interactive Jump | Open interactive `fzf` menu of scored directories to select destination. |
| `z -` | Previous Directory | Return to previous working directory (equivalent to `cd -`). |
| `z <query1> <query2>` | Multi-Query Jump | Match path segments (e.g. `z work api` -> `~/workspace/work-api`). |

---

## 3. Core Git & Legacy Invariants

### Git Command Shortcuts
Common Zsh Git aliases and customized Git config aliases:

| Alias / Command | Target Command | Description |
| :--- | :--- | :--- |
| `gst` | `git status` | Short status showing staged, modified, and untracked files. |
| `gco` | `git checkout` | Checkout branch or file paths. |
| `gcm` | `git checkout $(git_main_branch)` | Switch directly to repository's default branch (`main` or `master`). |
| `gl` | `git pull` | Fetch from and integrate with remote branch. |
| `gp` | `git push` | Push committed changes to default remote. |
| `gd` | `git diff` | Show unstaged modifications in working directory. |
| `g` | `git` | Root shorthand for `git`. |
| `git aa` | `git add --all` | Stage all changes (new, modified, and deleted files). |
| `git ap` | `git add --patch` | Interactively select hunks to stage. |
| `git ci` | `git commit -v` | Commit with verbose diff displayed in commit message editor. |
| `git pf` | `git push --force-with-lease` | Push safely with lease verification to avoid overwriting teammate commits. |
| `git st` | `git status` | Native Git status alias. |
| `git branches` | `git for-each-ref ...` | View branches formatted with relative commit age, author, and branch name. |

### Legacy Atlassian Bare Repository Invariant (`config`)
Before migration to `chezmoi`, dotfiles were historically tracked via an unmanaged Git bare repository located at `~/.cfg`.

* **Bare Repo Alias:**
  ```bash
  alias config='/usr/bin/git --git-dir=$HOME/.cfg/ --work-tree=$HOME'
  ```
* **Usage & Invariant Rules:**
  * Use `config status` or `config diff` to inspect legacy unmigrated files during audits.
  * Never commit new files to `config`. All active workstation dotfiles are strictly managed by `chezmoi`.
  * The `config` alias is preserved in `.zshrc` to protect historical auditability and prevent legacy automation breaks.
  * `~/.cfg` no longer depends on the retired thoughtbot `~/dotfiles`: its hook shims are gone, `info/exclude` links to the shared list below, and it inherits the global `~/.gitignore`.

### Shared Per-Repo Git Exclude List
Repositories created under the retired thoughtbot `init.templatedir` link `.git/info/exclude` to one shared list (media, archives, `*.env*`, `*.sql`, `*.csv`, `node_modules/`, Claude Code runtime files), managed by chezmoi at `~/.config/git/info-exclude`.

| Task | Command | Description |
| :--- | :--- | :--- |
| **Edit the list** | `chezmoi edit ~/.config/git/info-exclude` | Change patterns once; every linked repo picks them up on `chezmoi apply`. |
| **Link a new repo** | `ln -sfn ~/.config/git/info-exclude .git/info/exclude` | Opt a fresh clone into the shared list (new clones no longer get it automatically). |
| **Explain a match** | `git check-ignore -v <path>` | Show which list and line ignores a path (`.git/info/exclude:<line>:<pattern>`). |

### Secret Scanning on Commit (Git 2.54+)
Every `git commit`, in any repo, runs `~/.config/git/hooks/gitleaks-pre-commit` through the `hook.gitleaks` entry in `~/.gitconfig`. It scans only the staged changes, uses the repo's own `.gitleaks.toml` if present, and redacts what it reports. A repo's own `.git/hooks/pre-commit` still runs after it.

| Task | Command | Description |
| :--- | :--- | :--- |
| **See active hooks** | `git hook list pre-commit` | Lists `gitleaks` plus any repo hook. Empty output means this git is older than 2.54 and nothing is scanned. |
| **False positive** | `gitleaks:allow` comment on the line | Lets that line through; for findings you cannot annotate, add their fingerprint to `.gitleaksignore`. |
| **Skip once** | `git commit --no-verify` | Bypasses all pre-commit hooks for this commit only. |
| **Opt a repo out** | `git config hook.gitleaks.enabled false` | Disables the scan in the current repo only. |
| **Scan by hand** | `gitleaks git --pre-commit --staged --redact` | Same check the hook runs, without committing. |
| **Check requirements** | `git --version` and `/usr/bin/git --version` | Both must be >= 2.54 (`.chezmoidata/requirements.toml`). Every `chezmoi apply` asserts this and that `gitleaks` is installed, printing the fix and failing until met. On Intel Macs only the terminal git is a hard requirement; `/usr/bin/git` is reported as a `WARN` and the apply still passes. |
| **Intel Macs: standalone git** | `~/.local/bin/git --version` | Xcode 27 is Apple silicon only and Intel Homebrew has no git bottle, so `chezmoi apply` builds git from source into `~/.local` (pinned version, checksum verified, about a minute, needs the Command Line Tools). GUI apps that use `/usr/bin/git` (Apple's 2.50.1) skip the hook, so commit from a terminal. |
| **Intel Macs: bottled formulae only** | `chezmoi apply` (look for `skipping X: Homebrew would have to compile ...`) | Homebrew on Intel compiles anything that has no bottle (llvm, rust and node took 7 hours). The install script gives `brew bundle` only the formulae whose runtime dependencies are all bottled or installed, and prints each skip with its reason. Build a skipped one on purpose with `brew install --build-from-source <formula>`. |

### Chezmoi Workflow Commands
`chezmoi` manages dotfiles declaratively from `~/.local/share/chezmoi`.

| Command / Alias | Action | Description |
| :--- | :--- | :--- |
| `cz` | `chezmoi` | Shorthand alias for `chezmoi`. |
| `chezmoi diff` | Inspect Changes | Compare managed dotfiles in `$HOME` against templates/sources without modifying disk. |
| `chezmoi diff <file>` | Inspect Specific File | Diff a specific target file (e.g. `chezmoi diff ~/.cheatsheet.md`). |
| `chezmoi apply -v` | Apply State | Render templates and apply desired dotfiles to `$HOME` with verbose progress. |
| `chezmoi cd` | Source Repository | Change working directory directly into `~/.local/share/chezmoi`. |
| `chezmoi status` | Status Check | List all managed files that differ from the source state. |
| `chezmoi update` | Pull & Apply | Pull latest changes from remote Git repository and apply them immediately. |
| `chezmoi edit <target>` | Edit Source File | Open the source file or template corresponding to `<target>` in `$EDITOR`. |

---

## 4. Environment & Runtime Management (`mise`)

`mise` is the polyglot runtime and tool version manager powering the workstation (managing Node, Python, Go, and developer utilities).

| Command | Purpose | Example |
| :--- | :--- | :--- |
| `mise ls` | List Installed Runtimes | Show all installed tool versions and their active status:<br>`mise ls` |
| `mise use <tool>@<ver>` | Activate Tool Version | Set runtime version for current directory (creates `.tool-versions` or updates `mise.toml`):<br>`mise use node@22`<br>`mise use -g python@3.12` (sets global default) |
| `mise run <task>` | Execute Task | Run project tasks defined in `mise.toml`:<br>`mise run test` |
| `mise doctor` | Environment Diagnostics | Verify shims, PATH ordering, plugin health, and configuration sanity:<br>`mise doctor` |
| `mise install` | Install Missing Tools | Install all runtime versions specified in `.tool-versions` or `mise.toml`:<br>`mise install` |
| `mise current` | Active Versions | Display currently active versions for all tools in active shell:<br>`mise current` |
| `mise prune` | Cleanup Runtimes | Uninstall unused and outdated runtime versions:<br>`mise prune -y` |

### Default Editor
`~/.zshrc` sets `EDITOR` to the first of `nvim`, `vim` and `vi` found on `PATH`, and `VISUAL` to the same unless it is already set. A value already in the environment wins, so to choose another editor export both in `~/.zshenv`, which zsh reads before `~/.zshrc`. This runs before `~/.aliases` is read, so the aliases below get the chosen editor.

| Command | Purpose | Example |
| :--- | :--- | :--- |
| `e <file>` | Open in `$EDITOR` | `e notes.md` (`chezmoi edit` uses the same program; `git commit` follows `core.editor`: VS Code on macOS, `nvim` elsewhere) |
| `v <file>` | Open in `$VISUAL` | `v notes.md` |
| `echo $EDITOR $VISUAL` | See which editor was picked | Prints `nvim nvim` where Neovim is installed, `vim vim` otherwise |

---

## 5. Machine-Specific Customization Points

The configuration strictly separates shared, tracked dotfiles from machine-specific overrides and sensitive local credentials.

| Local Configuration File | Loading Mechanism | Intended Purpose |
| :--- | :--- | :--- |
| `~/.aliases.local` | Sourced at end of `~/.aliases` | Machine-specific shell aliases, hardware shortcuts, or team-specific alias overrides. |
| `~/.zshrc.local` | Sourced at end of `~/.zshrc` | Host-specific Zsh functions, custom prompt overrides, local PATH additions, or private configurations. |
| `~/.gitconfig.local` | Included via `~/.gitconfig` | Machine-specific Git configurations, alternative email addresses, or hardware GPG/SSH signing keys. |
| `~/.gitconfig.work` | `includeIf` in `~/.gitconfig.local` | Work email for `work`, `WORK-ORG-2` and `WORK-ORG-3` remotes or clones under `~/work/`, `~/WORK-ORG-2/`, `~/WORK-ORG-3/`. Check with `git config --show-origin user.email`. |
| `~/secrets.env` | Sourced if readable by `~/.zshrc` | Local environment variables, personal API tokens, and development secrets (never committed to Git). |
| `~/work.secret.env`<br>`~/work.env`<br>`~/dotfiles-local/.../work.secret.env` | Sourced if readable by `~/.zshrc` | Corporate/enterprise environment credentials, staging tokens, and internal endpoint variables. |

> [!TIP]
> Never commit secrets or machine-specific tokens into `~/.local/share/chezmoi`. Place sensitive variables in `~/secrets.env` or `~/work.secret.env`, which are ignored by Git and protected from repository leaks.

---

## 6. Terminal Applications (macOS)

| App | Installed By | Notes |
| :--- | :--- | :--- |
| iTerm2 | `cask "iterm2"` in `packages.toml` | Brew adopts an existing `/Applications/iTerm.app` without replacing it. |
| Warp | `cask "warp"` in `packages.toml` | Same adoption behaviour as iTerm2. |
| Wave | `cask "wave"` in `packages.toml` | Adopt or reinstall it from a different terminal, never from inside Wave. |
| Alacritty | Not managed by Homebrew | Its cask was disabled on 2026-09-01 for failing the macOS Gatekeeper check, so install or update the app by hand. `~/.config/alacritty/alacritty.toml` is still deployed by chezmoi. |
