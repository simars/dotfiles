# Workstation Quick Reference & Cheatsheet

A concise, high-density quick reference for modern CLI tools, search and navigation workflows, core Git commands, polyglot runtime management (`mise`), and machine-specific configuration points across macOS and Linux developer workstations.

---

## 1. Modern CLI & Observability Tools

The workstation environment provides modern Rust and Go command-line utilities configured with intelligent fallbacks and dynamic shell integration.

| Category | Command / Alias | Target Tool | Purpose & Usage Example |
| :--- | :--- | :--- | :--- |
| **Dynamic Preview** | `fp` | `fzf` + `bat` | Fuzzy find files with real-time syntax-highlighted preview:<br>`fp` |
| **Directory List** | `ll` | `eza` (or `ls`) | Detailed list with file icons and git status:<br>`ll` (falls back to `ls -lah` if `eza` absent) |
| **Directory Tree (Depth 2)** | `lt` | `eza --tree` | Tree view limited to 2 directory levels:<br>`lt` (on Omarchy, Omarchy's own `lt` is kept: it adds `--long --git`) |
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

All aliases are for interactive shells. When `~/.zshrc` is sourced by a shell that is not interactive, as Claude Code does to build its tool shell, it ends by removing every alias, including those from `~/.aliases.local`, `~/.zshrc.local` and the env files it sources. Commands then run as typed, and a helper function named like an alias (`g`, `config`) can be defined. `config` still works there as `~/.local/bin/config`.

### 1Password-Aware Runner (`with-op`, `cld`, `csr`)
`with-op <command...>` runs a command under `op run` when the current directory has a `.op-env` or a `.env`; with neither it runs the command untouched. `.op-env` lists 1Password Environment IDs (not names), one per line with `#` comments allowed, and each becomes `--environment <id>`; when two define the same variable the last one wins. `.env` is passed as `--env-file=.env`, so `op://` references in it resolve, and a legacy `OP_TARGET_ENVIRONMENT=<id>` line in it adds one more Environment. Only the current directory is checked, not its parents. It passes `--no-masking`: with secrets loaded, `op run` otherwise pipes output through a masking filter, interactive tools such as `claude` see no terminal, and `claude` falls into `--print` mode. The cost is that a secret the command prints shows in clear text. It is a function (bash and zsh), so it also works where aliases are stripped.

| Command | Expands to | Use |
| :--- | :--- | :--- |
| `with-op <cmd>` | `op run --no-masking [--environment <id>]... [--env-file=.env] -- <cmd>` | Any command that needs the project's 1Password secrets. |
| `cld` | `with-op claude` | Claude Code with the project's secrets. Interactive shells only (alias). |
| `csr` | `with-op cursor .` | Cursor on the current directory with the project's secrets. Interactive shells only (alias). |

### GNU & Linux-Compatible Tools (macOS)
On macOS, `userland` decides which variant the plain names `ls`, `sed`, `grep`, `find`, `tar`, `awk`, `make` and the rest of coreutils run. The default, `gnu`, aliases them to the GNU versions in your interactive shell only; scripts and other child processes keep Apple's tools, so macOS scripts that use BSD flags keep working. On Ubuntu the plain names are GNU already.

| Mode | What You Type | Scripts & Child Processes | Use It For |
| :--- | :--- | :--- | :--- |
| `userland gnu` (default) | GNU (`ls` is an alias for `gls`) | Apple | Everyday Linux-style work |
| `userland apple` | Apple | Apple | Following macOS docs; GNU stays available as `gsed`, `gls`, `gtar`, ... |
| `userland gnu-path` | GNU | GNU (`gnubin` first on `PATH`) | Running a Linux-minded script or Makefile from this shell |

* **Current mode:** `userland`. Switching changes the current shell only; a new shell starts in the host default.
* **Host default:** `export MACOS_USERLAND=apple` (or `gnu-path`) in `~/.zshrc.local`.
* **One Apple command in `gnu` mode:** `\sed ...` or `command sed ...` skips the alias; full paths (`/usr/bin/sed`, `/bin/ls`) always work.
* **Where the aliases stop:** after `sudo`, `xargs`, `find -exec`, `watch`, `env` and `nohup`, and inside `bash -c`, commands come from `PATH`, which is Apple's in `gnu` mode. Use the `g` name there (`find . -name '*.txt' -exec gsed -i 's/a/b/' {} +`) or switch to `userland gnu-path`.
* **Interactive shells only:** `~/.zshrc` runs `userland` only when the shell is interactive. Claude Code sources `~/.zshrc` in a non-interactive shell and replays its aliases into every command, so without this guard `date -v-1d` ran `gdate` there and failed.

| Linux Command | Formula | Notes & Example |
| :--- | :--- | :--- |
| `ls`, `cat`, `cp`, `date`, `df`, `du`, `stat`, `readlink`, `sort`, `timeout`, ... | `coreutils` | All of GNU coreutils:<br>`date -d '2 days ago'`, `readlink -f .`, `timeout 5 curl -s example.com` |
| `sed` | `gnu-sed` | In-place edit without BSD's `''` argument:<br>`sed -i 's/foo/bar/' file` |
| `grep`, `egrep`, `fgrep` | `grep` | Perl-compatible regex:<br>`grep -P '\d{3}' file` |
| `awk` | `gawk` | `awk '{ print toupper($1) }' file` |
| `find`, `xargs`, `locate` | `findutils` | `find . -name '*.log' -printf '%s %p\n'`<br>`... \| xargs -r rm` (skips `rm` when the input is empty) |
| `tar` | `gnu-tar` | `tar --exclude-vcs -czf ../src.tgz .` |
| `make` | `make` | GNU Make 4.x (`/usr/bin/make` is 3.81). |
| `bash` | `bash` | Bash 5 for `bash` and `#!/usr/bin/env bash`; `/bin/bash` stays 3.2. |
| `rsync` | `rsync` | rsync 3 instead of Apple's `openrsync`; `/usr/bin/rsync` stays. |
| `wget` | `wget` | `wget -qO- example.com` |
| `ip`, `bridge`, `ss` | `iproute2mac` | `ip addr`, `ip route get 1.1.1.1`, `ip neigh` (wraps `ifconfig`, `route` and `netstat`). |
| `watch` | `watch` | procps-ng's `watch`:<br>`watch -n 2 'docker ps'` |
| `pstree` | `pstree` | `pstree -p $$` (this shell's ancestors and children) |
| `ps`, `pgrep`, `pkill`, `uptime`, `w` | built in | BSD versions; `ps aux` and `ps -ef` both work. |
| `free`, `vmstat` | none | procps-ng (the `procps` formula) is Linux-only because it reads `/proc`; use `btop` or `vm_stat`. |

* **The same in every mode:** `bash` 5, `rsync` 3, `wget`, `timeout`, `ip`, `watch` and `pstree` are on `PATH` regardless (`/bin/bash` stays 3.2 and `/usr/bin/rsync` stays `openrsync`).
* **Scripts for both systems:** where BSD and GNU flags differ, try the GNU form first and fall back: `stat -c %Y f 2>/dev/null || stat -f %m f`. Never the other way round: GNU `stat -f` prints filesystem information and fails, so the fallback's output is appended to it. Or use a form both accept: `sed -i.bak`, `base64 -d`, `mktemp "${TMPDIR:-/tmp}/x.XXXXXX"`. Branch on `$OSTYPE` only for OS facts such as paths, launchd vs systemd, or the package manager.
* **Intel Macs (secondary hosts):** dotfiles only; their tools are installed by hand (`docs/INTEL_MACS.md`). `userland gnu` aliases only the GNU tools that are installed there: `findutils`, `gnu-sed` and `make` pour on Intel, so `sed`, `find`, `xargs` and `make` are GNU while `ls`, `grep`, `awk` and `tar` stay Apple's.

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
| `rg --hidden <query>` | Search hidden files and dotfiles | `rg --hidden "TODO"` |

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
| `git clone git@github.com:<owner>/<repo>.git` | Clone over SSH | Git rewrites no URLs, so an `https://` clone stays HTTPS: fine for public repositories, but private ones then ask for a token. Clone your own and work repositories with the SSH URL. |
| `gh config set git_protocol ssh` | Once per machine | Makes `gh repo clone` store SSH URLs. Check with `gh config get git_protocol`. |
| `git remote set-url origin git@github.com:<owner>/<repo>.git` | Move a clone to SSH | For an existing clone whose `git config --get remote.origin.url` starts with `https://github.com/`. |
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
  * `~/.local/bin/config` runs the same command in shells that do not have the alias: Claude Code's bash, scripts, `xargs`. Interactive zsh still uses the alias.
  * `~/.cfg` no longer depends on the retired thoughtbot `~/dotfiles`: its hook shims are gone, `info/exclude` links to the shared list below, and it inherits the global `~/.gitignore`.

### Shared Per-Repo Git Exclude List
Repositories created under the retired thoughtbot `init.templatedir` link `.git/info/exclude` to one shared list (media, archives, `*.env*`, `*.sql`, `*.csv`, `node_modules/`, Claude Code runtime files), managed by chezmoi at `~/.config/git/info-exclude`.

| Task | Command | Description |
| :--- | :--- | :--- |
| **Edit the list** | `chezmoi edit ~/.config/git/info-exclude` | Change patterns once; every linked repo picks them up on `chezmoi apply`. |
| **Link a new repo** | `ln -sfn ~/.config/git/info-exclude .git/info/exclude` | Opt a fresh clone into the shared list (new clones no longer get it automatically). |
| **Explain a match** | `git check-ignore -v <path>` | Show which list and line ignores a path (`.git/info/exclude:<line>:<pattern>`). |

### Secret Scanning & Identity Guard on Commit/Push (Git 2.54+)
Every `git commit`, in any repo, runs `~/.config/git/hooks/gitleaks-pre-commit` through `hook.gitleaks` in `~/.gitconfig` to scan staged changes for secrets. In addition, `~/.config/git/hooks/git-identity-guard` runs on `pre-commit` (`hook.identity-pre-commit`), `commit-msg` (`hook.identity-commit-msg`), and `pre-push` (`hook.identity-pre-push`) to enforce that the author and committer match the expected global identity (`~/.gitconfig` + `~/.gitconfig.local` / `~/.gitconfig.work` `includeIf` rules) and that no `Co-Authored-By:` trailer is present. A repo's own `.git/hooks/*` still runs after them.

| Task | Command | Description |
| :--- | :--- | :--- |
| **See active hooks** | `git hook list pre-commit` | Lists `gitleaks` and `identity-pre-commit` plus any repo hook (`git hook list commit-msg` and `git hook list pre-push` list the message and push guards). Empty output means this git is older than 2.54 and nothing runs. |
| **False positive** | `gitleaks:allow` comment on the line | Lets that line through; for findings you cannot annotate, add their fingerprint to `.gitleaksignore`. |
| **Skip once** | `git commit --no-verify` | Bypasses all pre-commit and commit-msg hooks for this commit only (`git push --no-verify` for pre-push). |
| **Opt a repo out** | `git config hook.gitleaks.enabled false` | Disables the secret scan in the current repo only (or `hook.identity-pre-commit.enabled false`, etc. for the identity guard). |
| **Scan by hand** | `gitleaks git --pre-commit --staged --redact` | Same check the hook runs, without committing. |
| **Check requirements** | `git --version` | The global hooks need git >= 2.54 (`.chezmoidata/requirements.toml`). Every `chezmoi apply` ends with a check: a `WARN` when git is older (the hooks then do not run on that machine), a `FAIL` when `gitleaks` is missing, each with its fix. |
| **Intel Macs: git for the hooks** | `~/.local/bin/git --version` | Apple's git there stops at 2.50.1 and Intel Homebrew has no git bottle: build git into `~/.local` by hand (`docs/INTEL_MACS.md`, section 4), or commits there go unscanned. |
| **Intel Macs: what Homebrew can install** | The check in `docs/INTEL_MACS.md`, section 1 | Lists each formula as `installed`, `pour` (safe to `brew install`) or `compile` (do not: Homebrew on Intel builds it from source, as it once did for 7 hours). |

### Chezmoi Workflow Commands
`chezmoi` manages dotfiles declaratively from `~/.local/share/chezmoi`.

| Command / Alias | Action | Description |
| :--- | :--- | :--- |
| `cz` | `chezmoi` | Shorthand alias for `chezmoi` (in `~/.aliases`: zsh and bash). |
| `chezmoi diff` | Inspect Changes | Compare managed dotfiles in `$HOME` against templates/sources without modifying disk. |
| `chezmoi diff <file>` | Inspect Specific File | Diff a specific target file (e.g. `chezmoi diff ~/.cheatsheet.md`). |
| `chezmoi apply -v` | Apply State | Render templates and apply desired dotfiles to `$HOME` with verbose progress. |
| `chezmoi cd` | Source Repository | Change working directory directly into `~/.local/share/chezmoi`. |
| `chezmoi status` | Status Check | List all managed files that differ from the source state. |
| `chezmoi update` | Pull & Apply | Pull latest changes from remote Git repository and apply them immediately. |
| `chezmoi edit <target>` | Edit Source File | Open the source file or template corresponding to `<target>` in `$EDITOR`. |
| `chezmoi --override-data '{"chezmoi":{"os":"linux","osRelease":{"id":"omarchy"}}}' managed --include=all` | Preview Another Host | List what an Omarchy host would get, from this machine. Change `os` and `id` for others (`ubuntu`, `arch`). Nothing is applied. |
| `tests/host-profiles.sh --base main` | Check All Host Kinds | From the source directory: checks what macOS, Omarchy, Arch, Ubuntu and Debian hosts get (CI runs it on every push), and notes scripts that would re-run on existing hosts. |

* **What chezmoi touches:** single files, written as real files (no symlinks). It never deletes or replaces anything it does not manage, so the rest of `~/.config` stays as it is. It does set the permissions of the directories it manages (`~/.vim` is `0700`).
* **Omarchy:** chezmoi installs only the packages in `[omarchy]` of `.chezmoidata/packages.toml` (`age`, `duf`, `dust`, `fx`, `gitleaks`, `httpie`, `shellcheck`, `vim`, `wget`, `zsh`, and `lunarvim-git` from the AUR; LunarVim then needs a one-time per-user link: `mkdir -p ~/.local/share/lunarvim && ln -s /usr/share/lunarvim ~/.local/share/lunarvim/lvim`, then `lvim --headless +qa`. Never run the package's `init-lvim.sh`: it overwrites `~/.config/lvim/config.lua` and installs tools with `yarn global` and `cargo`. If its build seems stuck on `gdb-add-index` lines, that is makepkg's slow `debug` pass, not a loop), only with `omarchy pkg add` / `omarchy pkg aur add`, and only when `chezmoi apply` runs in a terminal (they ask for the sudo password). Otherwise it prints the command, and the check after every apply keeps listing what is missing. Runtimes: `omarchy install dev-env go` (or `python`, ...). `bitwarden-cli` is macOS-only: Arch's package needs Node 22, which conflicts with Omarchy's Node. Build AUR packages with the system Python first (`PATH="/usr/bin:$PATH" omarchy pkg aur add ...`) once `omarchy install dev-env python` has put mise's Python on `PATH`. Omarchy's own Alacritty, Starship, `~/.config/mise/config.toml` and Neovim files are left alone; tmux and Herdr use the shared configs; Neovim gets only `lua/plugins/shared.lua`.
* **Other Linux:** no system packages are installed; the distribution brings its own.
* **zsh on Omarchy:** an optional shell (`zsh` from bash); the login shell stays bash, and Omarchy's bash aliases do not exist in it. `~/.zshrc` there skips the macOS parts and keeps history, fzf, zoxide, mise, starship and `~/.aliases`.

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
| `mise-audit` | Find Missing Project Pins | List the runtime pins under `$HOME` that mise has not installed (also run, as a warning, after every `chezmoi apply`):<br>`mise-audit` |
| `mise-audit --install` | Install Missing Project Pins | Run `mise install` in every project with a missing pin, then report what still failed:<br>`mise-audit --install` |

### mise on Omarchy
Omarchy ships its tools (node `latest`, the agent CLIs, `uv`) in `/etc/mise/conf.d/` and owns `~/.config/mise/config.toml`; chezmoi never touches either. Whether mise there also follows projects' own version files is one switch, `omarchy_mise_project_settings` in `.chezmoidata/omarchy.toml`:

| | **A** (`false`) | **B** (`true`, current) |
| :--- | :--- | :--- |
| What chezmoi deploys | Nothing for mise. `~/.config/mise/conf.d/50-shared.toml` renders empty, so an apply deletes an earlier copy | `~/.config/mise/conf.d/50-shared.toml`: version files for python and ruby, `uv_venv_auto`, prebuilt Rubies only (`ruby.compile = false`) |
| `.python-version`, `.ruby-version`, Gemfile `ruby` | Ignored by mise | Pick the runtime in that project |
| `.nvmrc`, `.node-version` | Ignored by mise | **Also ignored**: Omarchy's npm-based agent CLIs run, and auto-update, on the `node` mise picks for the folder, so a project must not change it. Pin a Node project with `mise use --env local node@<version>` |
| A repo's uv `.venv` | Not switched on (use `uv run`, or `source .venv/bin/activate`) | Switched on at `cd` |
| `.tool-versions`, `mise.toml`, `mise.local.toml` | Read | Read |
| Pinning a repo | `mise use --env local ruby@$(cat .ruby-version)` writes `mise.local.toml` (globally git-ignored) | Nothing to do for Python and Ruby; `mise install` once if the version is missing |

| Task | Command |
| :--- | :--- |
| Which option is live | `chezmoi execute-template '{{ .omarchy_mise_project_settings }}'` (`true` is B) and `mise settings get idiomatic_version_file_enable_tools` (`["python", "ruby"]` is B, `[]` is A) |
| Switch for good | Set the value in `.chezmoidata/omarchy.toml`, commit, then on Omarchy `chezmoi diff ~/.config/mise` and `chezmoi apply ~/.config/mise` |
| Try the other option without a commit | Add `omarchy_mise_project_settings = false` (or `true`) under `[data]` in `~/.config/chezmoi/chezmoi.toml` (wins over the repo value until `chezmoi init` rewrites the file), then `chezmoi apply ~/.config/mise`. Remove the line and apply again to go back |
| Pin a project mise does not follow by itself | `mise use --env local python@3.12` (unpinned repos), `mise use --env local node@22.13.0` (`.nvmrc` repos), then `mise install` |

**`omarchy install dev-env`:** `go`, `python` and `node` only add or install the global runtime Omarchy already declares, and are safe. **Never `dev-env ruby`:** it installs a global Rails and writes `idiomatic_version_file_enable_tools = ["ruby"]` into `~/.config/mise/config.toml`, which replaces this repository's list and silently stops `.python-version` from being followed. The requirement check after `chezmoi apply` warns when the effective list is not python and ruby and names the file that set it. Fix: `mise settings add idiomatic_version_file_enable_tools python`. Rails stays per project: `bundle install`, then `bin/rails`; a new app with `bundle init && bundle add rails && bundle exec rails new . --force`.

**Habits:** run `omarchy update`, `omarchy pkg …` and `uv tool install` from `~`, not inside a pinned repo; install Python CLIs with `uv tool install` or `omarchy pkg add`, not as loose `#!/usr/bin/env python3` scripts.

Neither option sets `go.set_gobin = false` (bash on Omarchy never puts `~/go/bin` on `PATH`). The deprecated `python.default_packages_file` is gone everywhere: the other hosts install global Python packages with a postinstall hook in `config.toml`, which chezmoi does not manage on Omarchy. So on Omarchy `go install` writes to the current Go version's `bin` directory, which is on `PATH` until the next Go upgrade. Install Go tools you keep with `mise use -g go:<module>@latest` (for example `mise use -g go:github.com/air-verse/air@latest`): mise builds each one into its own directory, so it survives Go upgrades, lists it in Omarchy's `~/.config/mise/config.toml`, and `mise up --bump` updates it. `mise-audit` is not deployed on Omarchy.

### Project Runtimes
Projects choose their runtime; nothing global changes outside them.

* **Files mise reads:** `.tool-versions`, `mise.toml`, and (enabled in `~/.config/mise/config.toml`) `.ruby-version`, a Gemfile `ruby "3.2.3"` line, `.python-version`, `.nvmrc` and `.node-version`. On Omarchy (option B above) only the Python and Ruby ones.
* **Ruby:** no global version, so outside a project `ruby` is macOS's `/usr/bin/ruby`. mise never compiles Ruby on its own on macOS: Apple silicon installs prebuilt Rubies and refuses versions that have none (EOL 2.x), and Intel Macs have no prebuilt Rubies. Compile on purpose with `MISE_RUBY_COMPILE=true mise install ruby@<version>` (or `MISE_RUBY_COMPILE=true mise-audit --install`).
* **Go:** `go.mod` is not read as a pin (Go runs older modules on the newest toolchain); pin an exact Go in `.tool-versions` if a project needs one. `go install` writes to `~/go/bin`, which is on `PATH` (on Omarchy, see *mise on Omarchy* above).
* **Pin fails with `No GitHub artifact attestations found`:** the pinned patch release has no signed build. Pin the latest patch of the same minor instead: `mise ls-remote python 3.11 | tail -1`.

### Default Editor
`~/.zshrc` sets `EDITOR` to the first of `nvim`, `vim` and `vi` found on `PATH`, and `VISUAL` to the same unless it is already set. A value already in the environment wins, so to choose another editor export both in `~/.zshenv`, which zsh reads before `~/.zshrc`. This runs before `~/.aliases` is read, so the aliases below get the chosen editor.

| Command | Purpose | Example |
| :--- | :--- | :--- |
| `e <file>` | Open in `$EDITOR` | `e notes.md` (`chezmoi edit` uses the same program; `git commit` follows `core.editor`: VS Code on macOS, `nvim` on other Linux; Omarchy sets no `core.editor`, so git follows `$EDITOR`, Omarchy's `omarchy-launch-editor`) |
| `v <file>` | Open in `$VISUAL`, or `$EDITOR` when `VISUAL` is unset (Omarchy sets only `EDITOR`) | `v notes.md` |
| `echo $EDITOR $VISUAL` | See which editor was picked | Prints `nvim nvim` where Neovim is installed, `vim vim` otherwise |

### Neovim (LazyVim, the same as Omarchy's)
Every machine runs Omarchy's LazyVim setup. On Omarchy it is Omarchy's own (`omarchy-nvim`); chezmoi adds only `~/.config/nvim/lua/plugins/shared.lua`. Elsewhere chezmoi deploys a copy of it without the Omarchy-only parts (theme switcher, Wayland clipboard helper, the 19 extra theme plugins). `lazy-lock.json` and `lazyvim.json` are seeded once and then belong to Neovim (`:Lazy restore` installs the pinned commits). Needs `lazygit` and `tree-sitter-cli`.

| Key or setting | What it does | Notes |
| :--- | :--- | :--- |
| `<leader>` | Space | |
| `<leader>ff` / `<leader>fb` | Find files / buffers | snacks picker (was Telescope on the Mac) |
| `<leader>sg` or `<leader>/` | Live grep | Was `<leader>fg` on the Mac |
| `<leader>fg` | Git files | LazyVim's default |
| `<leader>gg` | lazygit | |
| `<leader>e` | File tree (neo-tree) | |
| Indent 2, relative numbers off, format on save off | Omarchy's settings | `:lua vim.g.autoformat = true` turns formatting on for the session |
| Theme | `tokyonight-night` | `lua/plugins/theme.lua`; Omarchy follows its own theme switcher |
| Treesitter | LazyVim's parsers plus `go`, `gomod`, `gowork`, `gosum` | Built on first launch (`shared.lua`) |

### Line Endings (Vim, Neovim, LunarVim)
`~/.vim/plugin/line-endings.vim`, which all three editors load, flags files that are not LF. Opening one prints `notes.txt: CRLF line endings; :Lf saves it with LF`, and the status line shows `[CRLF]` or `[mixed]` (in LunarVim's lualine, `CRLF` or `mixed`) until the file is saved with LF. Mixed means some lines end in CRLF and others in LF: Vim shows those lines with `^M`, and `:set ff?` still says `unix`. `~/.config/lvim/config.lua` is managed by chezmoi for this; change it with `chezmoi edit`. In Neovim, `lua/plugins/shared.lua` sources the script and puts the label first in lualine's right side.

| Command | Purpose | Example |
| :--- | :--- | :--- |
| `:Lf` | Save the file with LF: converts CRLF and mixed lines and drops a UTF-8 byte-order mark | `:Lf`, or `:Lf!` for a read-only file |
| `:set ff?` | The buffer's format (`dos` is CRLF) | Says `unix` for a mixed file; the label does not |
| `.editorconfig` in a project | Every save in that project writes LF | `root = true`, `[*]`, `end_of_line = lf`. Built into Neovim; `~/.vimrc` turns it on in Vim |
| `file <path>` | Check one file from the shell | `ASCII text, with CRLF line terminators` |
| `rg -l '\r$'` | List the files with CRLF lines | `rg -l '\r$' ~/projects/app` |
| `perl -pi -e 's/\r$//' <files>` | Convert in bulk, the same with Apple or GNU tools | `rg -l0 '\r$' . \| xargs -0 perl -pi -e 's/\r$//'` |

* Git already stores LF: `core.autocrlf=input` converts CRLF when you commit. Files outside a repository keep their CRLF until saved with `:Lf`.
* Files that end lines with CR alone (old Mac OS) are flagged as mixed; `:Lf` does not split them.

### Docker Helpers
Defined in `~/.aliases`, so they work in zsh and bash (Omarchy).

| Command | Purpose | Example |
| :--- | :--- | :--- |
| `dkill` | `docker compose down` in every subdirectory of the current directory that has a `docker-compose.yml` or `.yaml` | `cd ~/code && dkill` |
| `dprune` | `docker system prune -a --volumes -f`: removes every stopped container, unused image, network and volume, without asking | `dprune` |

### SSH Hosts
`~/.ssh/config` (chezmoi) names your own machines the same way everywhere: `<machine>[-unlock].<how>`, where the suffix says how the name is reached. The bare name means `.tailnet`. Every path to one machine shares its `User`, key, agent forwarding and one `HostKeyAlias`, so switching paths never asks to trust the machine again. GitHub goes over port 443 (`ssh.github.com`). Omarchy gets no work-network stanza.

| Suffix | Reached through | Works from |
| :--- | :--- | :--- |
| `.tailnet` (or no suffix) | Tailscale short name (MagicDNS) | anywhere Tailscale is up |
| `.local` | Bonjour/Avahi | home network |
| `.lan` | the address reserved on the home router (`works` only) | home network |
| `.ddns` | `simars.ddns.net`, through the router's port forwards (`works` only) | anywhere |
| `.tplink` | `simars.tplinkdns.com`, the same router through TP-Link's DNS (`works` only) | anywhere |

| Machine | Aliases |
| :--- | :--- |
| `works` (Omarchy, `simars-works`) | `works`, `works.tailnet`, `works.local`, `works.lan`, `works.ddns`, `works.tplink` |
| `works-unlock` (its disk-unlock screen at boot) | `works-unlock` (= `.ddns`), `works-unlock.ddns`, `works-unlock.tplink`, `works-unlock.lan` |
| `mbp-work` (work MacBook) | `mbp-work`, `mbp-work.tailnet`, `mbp-work.local` |
| `mbp` (`simar-mbp`) | `mbp`, `mbp.tailnet`, `mbp.local` |
| `macstudio` | `macstudio`, `macstudio.tailnet`, `macstudio.local` |

Those four own machines get `ForwardAgent yes`, so `git pull`, `chezmoi update` and other GitHub access in an SSH session there use the key of the machine you connect from (a Mac's Keychain is locked to SSH sessions, and Omarchy sets its agent only for the desktop session). Never under `Host *`: while a session is open, an admin of the remote machine could use the key.

`ssh works-unlock` (or `.tplink`, or `.lan` at home) reaches works' disk-unlock screen while it boots: type the disk passphrase and the boot continues. It connects as `root` on port 2222 with its own host key alias (`works-unlock`) and no agent. There is no `.tailnet` or `.local` for it: neither Tailscale nor Avahi runs before the disk is unlocked. The machine side is set up outside this repository (`~/guides/omarchy/remote-disk-unlock` on works).

### SSH Key Passphrase (`ssh-key-remember`)
`ssh-key-remember` (`~/.local/bin`, every host) saves the `~/.ssh/id_rsa` passphrase in the machine's own keyring once, so the SSH agent unlocks the key by itself after every login and reboot instead of asking. On Omarchy it stores the entry GNOME keyring's SSH agent (`gcr-ssh-agent`) looks up, after checking the passphrase against the key; on macOS it runs `ssh-add --apple-use-keychain`, and `UseKeychain yes` plus `ssh-add --apple-load-keychain` in `~/.zprofile` read it back. Nothing goes into this repository. Run it in a terminal on the machine itself: macOS's Keychain is locked to SSH sessions. After every `chezmoi apply` the requirement check runs `--check` and warns while the passphrase is not saved.

| Command | Use |
| :--- | :--- |
| `ssh-key-remember` | Save the passphrase once on this machine (says so and exits if it is already saved). |
| `ssh-key-remember --check` | Report only, never prompt: exit 0 saved (or no passphrase), 1 not saved, 2 cannot tell (a Mac over SSH). |
| `ssh-key-remember --force` | Save it again, after changing the passphrase. |
| `ssh-key-remember <key>` | Another key than `~/.ssh/id_rsa`. |

### Claude Code's Shell (macOS)
Claude Code runs its Bash tool in bash, not zsh. Claude writes bash, and zsh differs from it in ways that break those commands: `"$sha:path"` applies the `:a` or `:s` modifier, `"$r[: ]"` is read as an array subscript, and an unquoted `$pair` is not split on spaces. `~/.zprofile` therefore exports `CLAUDE_CODE_SHELL`: Homebrew's bash 5, or Apple's `/bin/bash` 3.2 where Homebrew has none (Intel Macs). Claude Code then sources `~/.bashrc` instead of `~/.zshrc`. That file is deployed by chezmoi and defines no aliases, because an alias also blocks a function of the same name.

| Command | Purpose | Example |
| :--- | :--- | :--- |
| `echo $CLAUDE_CODE_SHELL` | See which bash Claude Code will use | `/opt/homebrew/bin/bash`. Takes effect for `claude` started from a new terminal |
| Ask Claude to run `echo "$BASH_VERSION"` | Confirm the tool shell | Prints `5.3...`. Empty output means it is still zsh |
| `export CLAUDE_CODE_SHELL=/bin/zsh` | Go back to zsh on one host | In `~/.zshenv`, which zsh reads before `~/.zprofile` |
| `~/.bashrc.local` | Host additions to Claude's bash | Lines installers append to `~/.bashrc` (fzf, LM Studio) belong here |

### tmux Sessions
`tat` (`~/.local/bin/tat`, deployed by chezmoi) opens the tmux session named after the current directory, so each project keeps its own session that survives a detach. Dots and colons in the directory name become dashes (`my.app` gives `my-app`), because tmux cannot target a session name that contains them. It is a POSIX `sh` script adapted from [thoughtbot/dotfiles](https://github.com/thoughtbot/dotfiles/blob/main/bin/tat).

| Command | Purpose | Example |
| :--- | :--- | :--- |
| `tat` | Attach to, or create, the session named after the current directory | `cd ~/code/my.app && tat` attaches `my-app`, creating it on first use |
| `tat <name>` | Same, with an explicit session name | `tat scratch` |
| `tat` (inside tmux) | Switch the client to that session instead of nesting one, creating it first if needed | `tat other-project` from any session |
| `tm` | Attach to, or create, one fixed session called `main` | Alias for `tmux new-session -A -s main` (in `~/.aliases`, so bash has it too) |
| `Ctrl-b d` | Detach and leave the session running | `tmux ls` lists sessions, `tat` re-attaches |
| `Ctrl-b !` | Break the current pane out into its own window | Press `Ctrl-b`, release, then `Shift-1`. herdr binds the same keys to move the pane into a new tab |

### tmux and Herdr Keys (macOS and Omarchy)
One config on every machine. The prefix is `Ctrl-b`; tmux also takes `Ctrl-Space` (Omarchy's old prefix). Press the prefix, release, then the key. `Alt` chords need Option-as-Meta in a Mac terminal. On Omarchy, Super+Alt+K and Super+Ctrl+K list every key.

| Key | tmux | Herdr |
| :--- | :--- | :--- |
| `h` `j` `k` `l` (or arrows) | Focus pane left, down, up, right | Same |
| `{` `}` / `Shift-h` `Shift-l` | Swap pane up, down / left, right | Same |
| `Alt-arrows` (after the prefix) | Resize pane (tmux default) | Same |
| `"` `-` (or `Alt-Enter`) | Split, new pane below | Same |
| `%` `v` (or `Alt-Shift-Enter`) | Split, new pane to the right | Same |
| `x` (or `Alt-Esc`) | Kill pane, no prompt | Close pane |
| `z` / `;` / `o` | Zoom / last pane / next pane | Same |
| `!` | Break pane into a new window | Move pane into a new tab |
| `c` / `,` / `&` | New / rename / kill window (asks first) | New / rename / close tab |
| `1`..`9` (or `Alt-1`..`9`), `n` `p` (or `Alt-Right` `Alt-Left`) | Go to window | Go to tab |
| `R` `C` `K` `P` `N` | Rename / new / kill / previous / next session | `Shift-r` (or `$`) `Shift-c` `Shift-k` `Shift-p` `Shift-n` for workspaces |
| `s` / `w` | Choose session / choose window (tmux defaults) | Workspace picker (both keys) |
| `q` | Show pane numbers; press one to jump (tmux default) | Goto picker (also `g`); Herdr has no pane numbers |
| `r` | Reload config | Same |
| `[` | Copy mode (`v` select, `y` copy) | Same |
| `e` | Open the scrollback in `$EDITOR` (popup) | Same |
| `Shift-t` | Rename pane (tmux: pane title) | Same |
| `?` | Key list (Omarchy's menu on Omarchy) | Help |
| `d` | Detach | Same |
| `Ctrl-Alt-arrows` / `Ctrl-Alt-Shift-arrows` | Focus / resize pane, no prefix | Same |
| `b`, `Shift-o`, `Shift-s`, `Shift-g` | | Sidebar, notification target, settings, new git worktree |

`omarchy refresh tmux` (or `herdr`) puts Omarchy's stock file back; `chezmoi apply ~/.config/tmux/tmux.conf` (or `~/.config/herdr/config.toml`) restores the shared one.

---

## 5. Machine-Specific Customization Points

The configuration strictly separates shared, tracked dotfiles from machine-specific overrides and sensitive local credentials.

| Local Configuration File | Loading Mechanism | Intended Purpose |
| :--- | :--- | :--- |
| `~/.aliases.local` | Sourced at end of `~/.aliases` | Machine-specific shell aliases, hardware shortcuts, or team-specific alias overrides. |
| `~/.zshrc.local` | Sourced at end of `~/.zshrc` | Host-specific Zsh functions, custom prompt overrides, local PATH additions, the sourcing of work-specific env files, or private configurations. |
| `~/.bashrc.local` | Sourced at end of `~/.bashrc` (macOS) | Host additions to Claude Code's bash, such as the lines installers append to `~/.bashrc`. No aliases. |
| `~/.gitconfig.local` | Included via `~/.gitconfig` | Machine-specific Git configurations, alternative email addresses, or hardware GPG/SSH signing keys. |
| `~/.gitconfig.work` | `includeIf` in `~/.gitconfig.local` | Work email for remotes in the work GitHub orgs and for clones under the matching `~/<org>/` directories. Check with `git config --show-origin user.email`. |
| `~/secrets.env` | Sourced if readable by `~/.zshrc` | Local environment variables, personal API tokens, and development secrets (never committed to Git). |
| Work-specific env files | Sourced if readable by `~/.zshrc.local` | Corporate/enterprise environment credentials, staging tokens, and internal endpoint variables. They are listed in `~/.zshrc.local`, not in this repository. |

> [!TIP]
> Never commit secrets or machine-specific tokens into `~/.local/share/chezmoi`. Place sensitive variables in `~/secrets.env` or in a work-specific env file sourced from `~/.zshrc.local`, which are ignored by Git and protected from repository leaks.

---

## 6. Terminal Applications (macOS)

| App | Installed By | Notes |
| :--- | :--- | :--- |
| iTerm2 | `cask "iterm2"` in `packages.toml` | Brew adopts an existing `/Applications/iTerm.app` without replacing it. |
| Warp | `cask "warp"` in `packages.toml` | Same adoption behaviour as iTerm2. |
| Wave | `cask "wave"` in `packages.toml` | Adopt or reinstall it from a different terminal, never from inside Wave. |
| Alacritty | Not managed by Homebrew | Its cask was disabled on 2026-09-01 for failing the macOS Gatekeeper check, so install or update the app by hand. `~/.config/alacritty/alacritty.toml` is still deployed by chezmoi. |
