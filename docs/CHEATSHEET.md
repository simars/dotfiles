# Workstation Quick Reference & Cheatsheet

A concise, high-density quick reference for modern CLI tools, search and navigation workflows, core Git commands, polyglot runtime management (`mise`), and machine-specific configuration points across macOS and Linux developer workstations.

---

## 1. Modern CLI & Observability Tools

The workstation environment provides modern Rust and Go command-line utilities configured with intelligent fallbacks and dynamic shell integration.

| Category | Command / Alias | Target Tool | Purpose & Usage Example |
| :--- | :--- | :--- | :--- |
| **Dynamic Preview** | `fp` | `fzf` + `bat` | Fuzzy find files with real-time syntax-highlighted preview:<br>`fp` |
| **Plain Listing** | `ls` | `ls --color=auto` | The system's own `ls` on every host, in colour on a terminal. Only colour is added, so its flags (`ls -ltr`, `ls -S`) and piped output stay standard. On Omarchy this replaces Omarchy's eza `ls` (Omarchy's `lsa` follows); on macOS `userland gnu` makes it `gls --color=auto`. `\ls` skips the alias. |
| **Directory List** | `ll` | `eza` (or `ls`) | Detailed list with file icons and git status:<br>`ll` (falls back to `ls -lah` if `eza` absent) |
| **Directory Tree (Depth 2)** | `lt` | `eza --tree` | Tree view limited to 2 directory levels, long listing with git status (`--long --git`), the same as Omarchy's:<br>`lt` (on Omarchy, Omarchy's own `lt` is kept) |
| **Parent Directories** | `..` `...` `....` | `cd ..` | Up one, two or three levels (Omarchy's names; its own are kept there) |
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

### 1Password-Aware Runner and Agent Shortcuts (`with-op`, `cldo`, `cldy`, ...)
`with-op <command...>` runs a command under `op run` when the current directory has a `.op-env` or a `.env`; with neither it runs the command untouched. `.op-env` lists 1Password Environment IDs (not names), one per line with `#` comments allowed, and each becomes `--environment <id>`; when two define the same variable the last one wins. `.env` is passed as `--env-file=.env`, so `op://` references in it resolve, and a legacy `OP_TARGET_ENVIRONMENT=<id>` line in it adds one more Environment. Only the current directory is checked, not its parents. It passes `--no-masking`: with secrets loaded, `op run` otherwise pipes output through a masking filter, interactive tools such as `claude` see no terminal, and `claude` falls into `--print` mode. The cost is that a secret the command prints shows in clear text. Before running, it prints `→ <command>` to the terminal (stderr, only when it is one, so pipes and agents never see it); without `.op-env` or `.env` the line ends `(no .op-env or .env: no secrets)`. It is a function (bash and zsh), so it also works where aliases are stripped.

| Command | Expands to | Use |
| :--- | :--- | :--- |
| `with-op <cmd>` | `op run --no-masking [--environment <id>]... [--env-file=.env] -- <cmd>` | Any command that needs the project's 1Password secrets. |

| Agent | `o` (secrets) | `y` (no prompts) | `oy` (both) | Plain |
| :--- | :--- | :--- | :--- | :--- |
| Claude Code | `cldo` = `with-op claude` | `cldy` = `claude --dangerously-skip-permissions` | `cldoy` | `claude` |
| Copilot | `cplo` = `with-op copilot` | `cply` = `copilot --yolo` | `cploy` | `copilot` |
| Cursor agent | `csao` = `with-op cursor-agent` | `csay` = `cursor-agent --yolo` | `csaoy` | `cursor-agent` |
| Cursor editor | `csro` = `with-op cursor .` | none | none | `cursor` |
| Codex | none | `cdxy` = `codex --dangerously-bypass-approvals-and-sandbox` | none | `codex` |
| Antigravity | none | `agyy` = `agy --dangerously-skip-permissions` | none | `agy` |

The letters mean the same for every agent: `o` runs it under `with-op` (the project's 1Password secrets), `y` adds its no-prompt flag, `oy` does both, and the plain name is the tool itself. Only Claude, Copilot and Cursor get `o`, since they are the agents used with project secrets. Each alias exists only where its tool is installed, and extra arguments append (`cldy -p "hi"`). Codex has no `--yolo`: its flag also turns off its sandbox. `cld` and `csr` were replaced by `cldo` and `csro`. These are aliases, so interactive shells only.

**Alternate Claude account (`claude-a`, `-a` suffix).** For when the main account's credits run out: `claude-a` (a script in `~/.local/bin`, so it also works under `with-op` and without aliases) runs `claude` on the alternate account with its own config directory, `~/.claude-a`. Its own directory because in the main one claude sends the main account's ID, cached in `~/.claude.json`, with every request, so usage shows against the main login although the token pays. Before each start it syncs `~/.claude-a` from the main config: every entry of `~/.claude` is linked (settings, `CLAUDE.md`, rules, skills, commands, hooks, plugins, themes, `projects` with session history and memory, history), except the per-account and per-process ones (sign-in, org policy and settings caches, sessions, jobs, daemon, telemetry, caches); `~/.claude.json` is copied without its account keys (`oauthAccount`, cached usage, org and model data), so MCP servers, preferences and project trust follow, while the alternate account keeps its own values for those keys and its own trusted folders. An entry of its own where a link now belongs moves to `~/.claude-a/.pre-link/`. `claude-a --resume` continues a session the main account started. `claude-a --sync` only syncs and `--sync --dry-run` prints without changing anything; each command it runs is printed (`→ ...`, to a terminal when starting claude), never the token. `cldo-a`, `cldy-a` and `cldoy-a` are `cldo`, `cldy` and `cldoy` on it. It signs in with its own login when it has one, else with a long-lived token. The login (`CLAUDE_CONFIG_DIR=~/.claude-a claude auth login`, or `/login` inside `claude-a`) is stored for `~/.claude-a` only, never touching the main sign-in, and brings claude.ai connectors, the organisation's plugins and Remote Control; `claude-a` uses it whenever `~/.claude-a/.claude.json` has an `oauthAccount`, which a login writes and a token never does. The token goes in `CLAUDE_CODE_OAUTH_TOKEN`: the last `CLAUDE_A_OAUTH_TOKEN=` line of `~/.config/ai-tooling/secrets.env` (chmod 600, never committed; read, not sourced), or `CLAUDE_A_OAUTH_TOKEN` in the environment, made with `claude setup-token`; it makes model requests only, so connectors, the organisation's plugins, Remote Control and `/schedule` are off. Do either in a browser signed in as the alternate account: one still signed in to the main account signs in, or mints a token for, the main account. It warns when `ANTHROPIC_API_KEY` or `ANTHROPIC_AUTH_TOKEN` would outrank its sign-in.

| Command | Expands to |
| :--- | :--- |
| `claude-a` | sync, then `CLAUDE_CONFIG_DIR=~/.claude-a claude`, with its login or `CLAUDE_CODE_OAUTH_TOKEN=<CLAUDE_A_OAUTH_TOKEN>` |
| `claude-a --sync [--dry-run]` | the sync alone |
| `cldo-a` | `with-op claude-a` |
| `cldy-a` | `claude-a --dangerously-skip-permissions` |
| `cldoy-a` | `with-op claude-a --dangerously-skip-permissions` |

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

### zsh Line Editor (every host)
`~/.zshrc` gives zsh the same keys and completion on every machine: Omarchy's zsh settings, with vi keys.

| Key / setting | What it does |
| :--- | :--- |
| `Esc` | vi normal mode (`i`, `a`, `A` back to typing). Set with `bindkey -v` in `~/.zshrc`, so it no longer depends on `$EDITOR`. |
| `Alt + Left` / `Alt + Right` | Back / forward one word, staying in typing mode (left Option on the Macs, as in every Mac app). Works inside tmux and herdr too: they leave these keys to the shell. |
| `Up` / `Down` | Previous / next command that **starts with what is already typed** (empty line: every command). Insert and normal mode. |
| `→` or `End` | Accept the grey suggestion from history (`zsh-autosuggestions`). |
| `Tab` / `Shift + Tab` | Highlighted completion menu, forward / back. Case-insensitive, matches inside words, coloured like `ls`. `**<Tab>` opens fzf. |
| Syntax highlighting | Commands turn green when they exist, red when not (`zsh-syntax-highlighting`, loaded last). |
| ` command` (leading space) | Not saved to history (`HIST_IGNORE_SPACE`). |
| `# note` at the prompt | A comment, not an error (`INTERACTIVE_COMMENTS`). |
| `somedir` | `cd somedir` (`AUTO_CD`). `cd` into a symlink goes to its real path (`CHASE_LINKS`). |

* **Plugins:** `zsh-autosuggestions` and `zsh-syntax-highlighting` come from the system package: `packages.toml` (Homebrew on Apple silicon; `zsh-autosuggestions` via `omarchy pkg add` on Omarchy, whose zsh already brings syntax highlighting). An old oh-my-zsh clone of autosuggestions still works as a fallback. Without a package, zsh runs without it, and the requirement check after `chezmoi apply` prints a `WARN` with the fix.
* **Omarchy:** its zsh options pick emacs keys; `~/.zshrc` switches to vi afterwards and binds the arrows, Shift-Tab and Omarchy's `Ctrl + Alt + F/L/V` fzf keys again in vi mode.
* **`$VAR<Tab>`** completes variable names on every host (Omarchy's zsh turns this off; `~/.zshrc` turns it back on). `Ctrl + Alt + V` also picks a variable with fzf.

### Omarchy's Helpers on Every Host
On the Macs (and any host without Omarchy) `~/.zshrc` loads `~/.config/zsh/shared-helpers.zsh`, which chezmoi generates from snapshots of Omarchy's own files (`docs/omarchy-stock/shell/`), so the same helpers and keys work as on Omarchy. Interactive zsh only.

| Command / key | What it does |
| :--- | :--- |
| `Ctrl + Alt + F` | fzf over files (with `fd`); a token ending in `/` searches that folder. Pastes the pick. |
| `Ctrl + Alt + L` | fzf over `git log`; pastes the chosen commit hashes. |
| `Ctrl + Alt + V` | fzf over shell variables; pastes the name. |
| `cx` / `c` / `cy` | Claude Code (auto permission mode) / opencode / codex |
| `t` / `h` | `tmux attach` or a new `Work` session / `herdr` |
| `tdl c [cx]`, `tdlm c`, `tds`, `tsl 4 <cmd>` | tmux layouts: editor, AI and terminal panes; one such window per subfolder; editor, diff watch, terminal and opencode; the same command in N panes |
| `hdl`, `hdlm`, `hds`, `hsl` | the same layouts in herdr |
| `ic`, `ix`, `icx` | `tdl c`, `tdl cx`, `tdl c cx` |
| `ff`, `eff`, `sff host:/path/` | fzf with bat preview; edit the pick; scp the pick (newest files first) |
| `n [path]` | nvim (`.` when no path) |
| `ga <branch>` / `gd` | new git worktree beside the repo and `cd` into it / remove the current worktree and branch (asks via `gum`) |
| `fip host port...`, `dip port...`, `lip` | forward local ports over SSH / stop them / list them (on macOS `lip` shows only PIDs) |
| `gcm`, `gcam`, `gcad` | `git commit -m`, `-a -m`, `-a --amend` |
| `d`, `mup`, `compress dir`, `decompress f.tar.gz` | docker; `mise up` without the release-age wait; tar.gz a folder (Apple's `/usr/bin/compress` stays for scripts); untar |
| `ssh host` (typed, interactive) | Omarchy's reconnecting ssh: a session that drops after 30 s or more reconnects until `Ctrl + C`; resets the mouse and screen modes a dead remote tmux left on. Runs in bash, as on Omarchy. Scripts, `ssh -f` and `ssh host cmd` are unchanged |

Not taken over: Linux-only helpers (`a`, `rsw`/`lsw`/`dsw`, `iso2sd`, `format-drive`, `open`); `cd` stays plain on every host (Omarchy's zoxide `cd` is removed there too; `z` / `zi` jump); `r` stays zsh's repeat-last-command on the Macs (Omarchy keeps `r` = rails); each side keeps its own prompt. Decisions: `docs/ZSH_UNIFICATION.md`. The `Ctrl + Alt` keys (and fzf's `Alt + C`) need the terminal to send Option as Alt; see "Option as Alt in the Mac Terminals" below. Man pages go through `bat` on every host. `gum` is in `packages.toml` for `gd`.

### iTerm2 Shell Integration and Claude Code (macOS)
`~/.zshrc` loads iTerm2's shell integration from the app itself, only in iTerm2 (inside tmux there too; not in Wave, Warp or SSH sessions):

| Key / command | What it does |
| :--- | :--- |
| `Cmd + Shift + Up` / `Down` | Jump to the previous / next prompt |
| `Cmd + Shift + A` | Select the output of the last command (then `Cmd + C`) |
| Edit > Marks and Annotations > Alert on next mark | Notify when the running command ends |
| Toolbelt (`Cmd + Shift + B`) | Recent directories, command history, captured output |
| `imgcat f.png`, `it2dl f`, `it2ul`, `it2copy`, `cc-status` | iTerm2's utilities, on `PATH` in iTerm2 only: show an image, download / upload over SSH, copy to the clipboard, Claude Code status |

**Claude Code integration** (iTerm2 3.7, set up once per Mac from the menu **iTerm2 > Install Claude Code Integration**; when it asks about the dynamic profile, choose **Mark Rewritable and Install**): shows each tab's Claude Code state (working, waiting for you, idle) in iTerm2's Session Status and tab indicators, through a hook it adds to `~/.claude/settings.json`. ai-tooling's settings merge keeps that hook (it merges your live settings first and owns no `hooks` key). Undo: **iTerm2 > Uninstall Claude Code Integration**. iTerm2's separate **AI Chat** needs its own model provider and API key and is not set up.

### Same iTerm2 on Every Mac
chezmoi gives every Mac the same iTerm2 look from the repo. A second dynamic profile, **"Shared Look (chezmoi)"** (`~/Library/Application Support/iTerm2/DynamicProfiles/chezmoi-0-shared-look.json`, from `chezmoi-0-shared-look.json.tmpl`), is the parent of "Default (Left Option as Alt)", so that profile shows the shared look plus left Option as Alt.

| What | Where it lives |
| :--- | :--- |
| The look: JetBrains Mono Nerd Font Mono 12, no second font, no ligatures (iTerm2 drops GPU rendering with ligatures on), the Atom colours, silent bell with a screen flash, 10,000 lines of scrollback | `chezmoi-0-shared-look.json.tmpl`; chezmoi owns the whole file and iTerm2 never rewrites it |
| Triggers in full-screen apps (herdr, tmux, vim, Claude Code): off, so iTerm2 stops warning that triggers are slow there | `iterm2_triggers_in_interactive_apps` in `.chezmoidata/macos.toml` |

* **Change the look:** edit the template in the repo, commit, push, then `chezmoi update` on each Mac. iTerm2 reloads dynamic profiles by itself.
* **Changes made in iTerm2's Settings** to "Default (Left Option as Alt)" stay on that Mac only, and every apply names them; except right Option and the "triggers in interactive apps" checkbox, which the next apply resets to the shared look's values. The shared look itself goes back to the repo's values when its file reloads.
* **The profile list** shows "Shared Look (chezmoi)" too; it cannot be hidden. Use "Default (Left Option as Alt)".
* **Global settings**, kept outside profiles and written key by key where a Mac differs (`[iterm2_globals]` in `.chezmoidata/macos.toml`): clipboard access for programs (OSC 52), copy on select, double-click selects a whole URL or path, no tab bar in full screen, no Touch Bar Esc feedback, print in black and white, a pasted tab becomes 4 spaces. iTerm2 reads them at start, so the apply that changes one says to reopen iTerm2. Window frames, the toolbelt and update checks stay per Mac.
* **After every apply** `run_after_96_macos_iterm2.sh` prints, with `OK:` or `NOTE:`: whether the global settings match, whether chezmoi's profile is the default, whether the Claude Code integration is installed, and which settings were saved in "Default (Left Option as Alt)" on this Mac only (keys beyond chezmoi's own whose value differs from the shared look, since iTerm2 keeps some keys it saves even with the shared look's value; and triggers beyond the two Claude Code ones). The first three put their fix on the to-do list; local changes are only reported, since a deliberate local tweak may stay.
* **Still by hand, once per Mac:** install the Claude Code integration (iTerm2 > Install Claude Code Integration), make chezmoi's profile the default, reopen iTerm2 after the first apply, and Warp's Option setting if you use Warp.

### Same macOS Settings on Every Mac
chezmoi writes macOS's own settings from `[[macos_defaults]]` in `.chezmoidata/macos.toml`, key by key where a Mac differs, after every apply (`run_after_97_macos_defaults.sh`, every Mac, Intel too). A change made in System Settings goes back at the next apply: change the repo instead (commit, push, `chezmoi update` on each Mac).

| Area | Settings |
| :--- | :--- |
| Dock | hidden, shown on hover at once with a quick slide; small icons (16) magnified to 128 on hover; minimized windows get their own Dock tile (Scale effect); no bouncing; no recent apps |
| Mission Control | windows grouped by app; dragging a window to the top edge does nothing; thumb and three fingers spread shows the desktop; desktops keep the order you give them (never rearranged by recent use); each display has its own desktops |
| Desktop shortcuts | macOS's own "Switch to Desktop 1–16" on a hidden combination (Ctrl+Option+Shift + `1`–`0` `-` `=` `[` `]` `;` `'`), which the window keys press for you ("Window Keys" below); Desktop N counts across screens, the main display's first |
| Caps Lock | arrives as F18 while Hammerspoon runs (it sets macOS's own `hidutil` remap at start, after a wake, at unlock and when a USB device appears, and clears it when it quits); Hammerspoon turns a tap back into Caps Lock and a hold into the window-key prefix ("Window Keys" below) |
| Windows and keys | double-clicking a title bar fills the screen; clicking the scroll bar jumps there; holding a key repeats it (no accent pop-up: Option+key still types accents) |
| Appearance | Dark, never Auto (the terminals' colours are dark) |
| Trackpad | natural scrolling (mouse too), tracking speed 2.5, tap to click; no tap-to-drag, drag lock or three-finger drag, so three-finger swipes stay for spaces and Mission Control |
| Finder | list view, path bar, status bar, folders first, search the current folder, new windows in Downloads, no extension-change warning, external drives on the desktop |
| Menu bar | battery percentage on, Spotlight icon off (Cmd-Space still works); both keys are older macOS's and were not yet seen working on macOS 27: check the menu bar after the first apply |

* **Left to each Mac:** the Dock's apps, hot corners, the clock (macOS's "date when space allows"), which Control Center items show in the menu bar.
* **When it changes something** the apply restarts the Dock, Finder or Control Center (only while they run), says which keys it wrote, and puts **log out and back in** on the to-do list for the trackpad, scrolling, appearance and Spotlight keys, which macOS reads at login. Apps pick up the title-bar, scroll-bar and key-repeat settings when reopened.
* **Invert Colors:** if macOS's Accessibility shortcut Invert colors (Ctrl+Option+Cmd+8) is turned on, the apply names it and puts turning it off on the to-do list: it takes the window key for desktop 8.
* **Remote access is checked, not set:** the same script reports Remote Login (SSH), Screen Sharing and wake for network access on AC, and puts any that is off on the to-do list with its fix (`OK:   remote access: ...` when all are on). Turning them on needs System Settings or sudo, so chezmoi never does it.
* **List view** applies to folders that never saved their own view; others keep theirs (View > as List, then View > Show View Options > Use as Defaults).

### Lost and Minimized Windows (macOS and Omarchy)
Cmd+Tab picks an app, not a window: when every window of the app is minimized, or sits off-screen after a display change, the app comes to the front and nothing shows. These bring the windows back:

| You want | macOS | Omarchy |
| :--- | :--- | :--- |
| Bring back the app you just picked: unhide it, restore its minimized windows, pull its off-screen ones in, stacked on this screen | **Cmd+Ctrl+U** (Hammerspoon) | |
| The same for every app | **Cmd+Ctrl+Shift+U** | **Super+Ctrl+U**: every minimized window (Super+M) and every off-screen floating window to this workspace (private guide `~/guides/omarchy/window-rescue`) |
| Restore one minimized window while switching | Cmd+Tab to the app, press Option, then let go of Cmd (several minimized windows: may not work) | Click it in the dock |
| See all of an app's windows, minimized ones too | Ctrl+Down (App Exposé); click one | |
| Center or fill the active window | Fn+Ctrl+C / Fn+Ctrl+F | |
| Arrange several windows | Fn+Ctrl+Shift+arrows, or Swish's swipes | Hyprland tiles by itself |
| Unminimize with the trackpad | Swish's unminimize swipe: once for this screen, twice for all | |

* **Stacked:** each window brought back is centered on the screen you are using, the next one 40 px down and right, the last one focused; a short alert says what came back ("Nothing minimized or off-screen" otherwise).
* **Not moved:** windows on another Space (Cmd+Tab switches to their Space: macOS's default, System Settings > Desktop & Dock > Mission Control) and windows that are simply on another screen.
* **Hammerspoon** comes with the other casks (Intel Macs: by hand, `docs/INTEL_MACS.md`). chezmoi writes `~/.hammerspoon/init.lua`, `window_rescue.lua` and `window_keys.lua` ("Window Keys" below); put this Mac's own additions in `~/.hammerspoon/local.lua`. It reloads itself when they change and starts at login. Once per Mac: open it, choose Open at macOS's downloaded-app question, and switch it on in System Settings > Privacy & Security > Device Control and Data Access (Accessibility before macOS 27; add it with + if it is not listed). The config never asks for that permission itself: on macOS 27 asking showed "Hammerspoon would like to control this Mac" on every config reload. The apply lists Hammerspoon until it runs.
* **Closed to the tray** (the window closed, the app still running in the menu bar or Omarchy's tray): there is no window to bring back. Open the app again, or use its tray icon.
* **Check it:** each run adds a line to `~/Library/Logs/window-rescue.log`. Over SSH: `open -g "hammerspoon://window-rescue"` (`?all=1` for every app), then read the log.

### Window Keys (macOS and Omarchy)
One prefix for window keys on every machine: **Ctrl+Option+Cmd** on the Macs, **Ctrl+Alt+Super** on Omarchy. On a Windows-style keyboard that is the same three keys on both (Ctrl, Win, Alt: macOS treats Win as Cmd and Alt as Option); on a Mac keyboard, the three keys left of the space bar. Add Shift to move instead of look.

| Keys | macOS (Hammerspoon) | Omarchy (alias of Omarchy's own key, which stays) |
| :--- | :--- | :--- |
| Prefix + arrows | Focus the window in that direction, across screens too | Super+arrows |
| Prefix + Shift + arrows | Swap the focused window with that one | Super+Shift+arrows |
| Prefix + 1–9 | Desktop N **of the screen under the mouse** | Super+1–9 (workspace N of this monitor) |
| Prefix + Shift + 1–9 | Send the window to desktop N of its screen, and go with it | Super+Shift+1–9 |
| Prefix + L | Lay out this screen's windows once, like Hyprland (dwindle) | — (Hyprland tiles by itself) |
| Prefix + U | Window rescue (as Cmd+Ctrl+U, above) | Window rescue (as Super+Ctrl+U) |

* **Caps Lock is a one-key prefix:** hold Caps Lock instead of the three keys (Caps+arrows, Caps+Shift+arrows, Caps+1–9, Caps+Shift+1–9, Caps+L, Caps+U); a quick tap still turns capitals on and off. On Omarchy, Shift then Caps is still Compose. Typing fast from Caps onto a letter (within 200 ms) stays Caps Lock + letter, so it never fires a window or Omarchy shortcut. Mac: Hammerspoon (Caps Lock arrives as F18 while it runs); Omarchy: keyd, private guide `~/guides/omarchy/caps-prefix`.
* **Caps Lock in password fields (Mac):** macOS hides keys from Hammerspoon there (secure input), so a Caps tap does not toggle capitals in a password field; toggle before clicking into it. The three-key prefix works everywhere. If Caps Lock ever does nothing at all (Hammerspoon crashed), `hidutil property --set '{"UserKeyMapping":[]}'` gives it back until Hammerspoon starts again.
* **Swish keeps working:** the keys act only when pressed, nothing re-tiles behind your back, and macOS's own desktops stay the workspaces, so Swish's snaps and desktop swipes are untouched.
* **Desktop numbers are per screen**, as Omarchy's workspaces are per monitor. macOS itself counts desktops across screens (the main display's first), so the keys work out macOS's number and press its hidden "Switch to Desktop N" shortcut ("Same macOS Settings on Every Mac" above). Desktops keep their order (rearranging by recent use is off), up to 16 in total.
* **Sending** holds the window by its title bar while macOS switches desktop: the mouse jumps there for half a second after you let go of the keys. If an app's windows do not move (`~/Library/Logs/window-keys.log` says `NOT moved`), focus one and run `open -g "hammerspoon://window-keys-probe"`: the log lists the spots that drag it; add one to `GRAB` in `dot_hammerspoon/window_keys.lua.tmpl`.
* **Not taken:** Cmd+Ctrl+arrows stay Ghostty's split resize on the Mac. On Omarchy, Ctrl+Alt+Super+Shift+arrows replaces Ghostty's 100 px split resize (Super+Ctrl+Shift+arrows and the leader's Alt+arrows remain). macOS's Invert Colors shortcut (Ctrl+Option+Cmd+8) would take desktop 8: the apply warns if it is on.
* **Where:** Mac, `~/.hammerspoon/window_keys.lua` (chezmoi; needs Hammerspoon, see "Lost and Minimized Windows"); Omarchy, the private guide `~/guides/omarchy/window-keys` (`setup-guides apply`).
* **Near miss:** tmux and Herdr use Ctrl+Alt+arrows (panes, no prefix); add Super/Cmd and you are moving windows.

### Option as Alt in the Mac Terminals
A Mac terminal sends `Alt` keys (`Esc` plus the key) only when Option is set to act as Meta; otherwise Option types special characters (`ƒ`, `©`, `ü`). chezmoi sets **left Option = Alt, right Option = special characters** (macOS only):

| Terminal | How chezmoi sets it |
| :--- | :--- |
| iTerm2 | Dynamic profile "Default (Left Option as Alt)" (`~/Library/Application Support/iTerm2/DynamicProfiles/chezmoi-option-as-alt.json`): the shared look "Shared Look (chezmoi)" (below) with left Option `Esc+`; right Option comes from the shared look (`Normal`). chezmoi sets only its keys, adds the Claude Code workgroup triggers when missing, and keeps what iTerm2 saves there (the profile is rewritable, as the Claude Code integration asks). Make it the default once: Settings > Profiles, select it, Other Actions > Set as Default. Change looks in the repo's shared look, not in "Default" or in iTerm2's Settings. |
| Warp | **Not managed by chezmoi:** Warp syncs its settings through your Warp account and overwrote chezmoi's value. Set it once in Warp (Settings > Features > Keys: Left Option is Meta on, Right Option is Meta off); the sync carries it to the other Macs. |
| Wave | `~/.config/waveterm/settings.json`: `"term:macoptionismeta": true` (Wave has no left/right split: both Option keys act as Alt there). Only this key is set. |
| kitty | `~/.config/kitty/kitty.conf`: `macos_option_as_alt left` (with `copy_on_select clipboard`), appended under a chezmoi marker; the rest of the file is kept. |
| Ghostty | `~/.config/ghostty/config`: `macos-option-as-alt = left` (with `copy-on-select = clipboard`), the same way. |
| Herdr app | `~/.config/herdr-app/settings.json`: `"option_as_alt": "left"` (its default `auto` covers only US-style layouts, not Canadian). It reads herdr's own `~/.config/herdr/config.toml` for keys, default shell and copy on select. |

### Copy and Paste (macOS and Omarchy)
| | Omarchy | macOS |
| :--- | :--- | :--- |
| Copy / paste / cut / select all, in every app and terminal | `Super + C` / `V` / `X` / `A` (in a terminal, Omarchy sends `Ctrl + Shift + C` / `V`, so `Ctrl + C` still stops a program) | `Cmd + C` / `V` / `X` / `A` |
| Clipboard history | `Super + Ctrl + V`, or `Super + Shift + V` (like Paste's `Shift + Cmd + V`; added by `~/guides/omarchy/terminals-clipboard`) | Paste (Setapp): `Shift + Cmd + V`; also Spotlight's clipboard history |
| Copy in tmux (mouse or copy mode), herdr, Neovim, also on a remote host over SSH | lands on the clipboard (foot accepts OSC 52) | lands on the clipboard: Wave allows it by default; iTerm2's "Applications in terminal may access clipboard" is one of the shared global settings ("Same iTerm2 on Every Mac"; reopen iTerm2 after the apply that sets it) |

Programs in the terminal can **set** the clipboard this way, never read it. **Selecting with the mouse copies at once** in every terminal: iTerm2 (its default) and Wave (`term:copyonselect`, set by chezmoi) on macOS; foot (`selection-target=both`, set by chezmoi), Alacritty (`[selection] save_to_clipboard`, set by the Omarchy guide) and Wave on Omarchy; kitty (`copy_on_select clipboard`) and Ghostty (`copy-on-select = clipboard`) on both, set by chezmoi; and in herdr, the Herdr app and tmux everywhere. Copilot CLI, Antigravity, Codex and Claude Code take the mouse over from the terminal and Herdr and select text themselves; chezmoi sets Copilot's and Antigravity's `copyOnSelect` and Codex's `copy_on_select`, and reports Claude Code's (see "Same Keys in Every Agent" below), which Copilot has on by default only on macOS, so on Omarchy a selection there copied nothing until `Ctrl + C` or a right-click. foot stays Omarchy's default terminal; Alacritty, kitty, Ghostty, Wave (`waveterm-bin`, AUR) and the Herdr app (`herdr-app`) are installed beside it; Wave and the Herdr app are tagged as terminals (Omarchy tags the others itself) so `Super + C` / `Super + V` copy and paste there instead of sending `Ctrl + C`.

### Same Keys in Every Agent
The CLI coding agents get the same three settings: vim keys in the prompt, copy on select, and the mouse. The values come from `[agent_usability]` in `.chezmoidata/agents.toml`, they apply only where the agent is set up (its folder exists or its command is installed), and each apply puts every value back and leaves the rest of the file alone. A `false` writes the agent's opposite value; it does not leave the key alone (Antigravity is the exception, see its row). The one exception is Claude Code's copy on select, which lives in a file chezmoi does not write: the apply only reports it when it is off. A setting an agent does not have says "not available".

| Agent | File | Vim keys | Copy on select | Mouse |
| :--- | :--- | :--- | :--- | :--- |
| Claude Code | `~/.claude/settings.json` | `editorMode` | on by default; kept in `~/.claude.json`, which chezmoi does not write; the apply's to-do list says if it is off | no setting: `env.CLAUDE_CODE_DISABLE_MOUSE` (`"1"` turns the mouse off; removed when on), with `tui` set to `fullscreen` |
| Copilot CLI | `~/.copilot/settings.json` | `editorMode` | `copyOnSelect` | `mouse` |
| Cursor's agent (`cursor-agent`) | `~/.cursor/cli-config.json` | `editor.vimMode` | not available | not available |
| Antigravity (`agy`) | `~/.gemini/antigravity-cli/settings.json` | `editorMode` `vim`, which Antigravity's settings check accepts; off removes the key (its default), since it rejects `normal` | on is its default, so the key is removed (it drops `true` itself); `copyOnSelect` `false` is written only when off | always on in its full-screen mode; no setting |
| Codex | `~/.codex/config.toml` (`[tui]`) | `vim_mode_default` | `copy_on_select = "always"` | not available (Codex has only `mouse_scroll_speed`) |

`cursor-agent` reads `$XDG_CONFIG_HOME/cursor/cli-config.json` instead of `~/.cursor/cli-config.json` when `XDG_CONFIG_HOME` is set. Nothing here sets it, so the managed file is the one Cursor uses.

### Ghostty over SSH (every host)
Ghostty sets `TERM=xterm-ghostty`, and ssh passes it on through every hop (Ghostty on a Mac → works → another Mac). A host without that terminal description garbles typing: zsh can't move the cursor, so each redraw appends and the history suggestion looks like typed text. chezmoi compiles Ghostty's description into `~/.terminfo` on every host whose system has none (`run_onchange_after_92_ghostty_terminfo.sh`, from `terminfo/xterm-ghostty.terminfo`; Omarchy has it from the `ghostty-terminfo` package), and the check after every apply warns if it is missing. By hand: `tic -x -o ~/.terminfo ~/.local/share/chezmoi/terminfo/xterm-ghostty.terminfo`, or from a host that has it, `infocmp -x xterm-ghostty | ssh <host> 'tic -x -'`. Refresh the copy after a Ghostty update: `infocmp -x xterm-ghostty`, keeping the file's comment lines. A session started before the fix needs `exec zsh` or a new login.

### Wave Panes and Tabs (macOS and Omarchy)
Wave's own keys use Cmd on macOS where they use Alt on Linux. Wave has no setting to change its keys.

| Do | macOS | Omarchy | Shell, inside Wave (both) |
| :--- | :--- | :--- | :--- |
| Split right | `Cmd + D` | `Alt + D`, or `Super + D` (added by `~/guides/omarchy/wave-keys`, Wave windows only) | `wsr` (`wsplit right`) |
| Split down | `Cmd + Shift + D` | `Alt + Shift + D` (`Super + Shift + D` stays Omarchy's Docker) | `wsd` (`wsplit down`) |
| New pane in this folder, Wave picks where | | | `wt` |
| New pane running a command | | | `wr <command> [args...]` |
| Split with the mouse | split buttons on each pane header (`app:showsplitbuttons`, set by chezmoi) | same | |
| New tab / close pane | `Cmd + T` / `Cmd + W` | `Alt + T` / `Alt + W` | |
| Previous / next tab | `Cmd + [` / `Cmd + ]` | `Alt + [` / `Alt + ]` | |

`wsr` and `wsd` press Wave's split keys through Hyprland on Omarchy, only when Wave is the active window. On macOS (and in a Wave session on another machine) they open a pane where Wave chooses and name the key to press instead: pressing keys from a script on macOS would need Accessibility permission for Wave, which would let anything running in Wave control every app. `wt`, `wr`, `wsr`, `wsd` exist only in Wave's shells (`WAVETERM_BLOCKID` set, `wsh` on `PATH`). New panes keep the folder and the connection of the focused pane.

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
| `gh config set git_protocol ssh` | Set by every apply when it is not | Makes `gh repo clone` store SSH URLs. Check with `gh config get git_protocol`. |
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
Every `git commit`, in any repo, runs `~/.config/git/hooks/gitleaks-pre-commit` through `hook.gitleaks` in `~/.gitconfig` to scan staged changes for secrets. In addition, `~/.config/git/hooks/git-identity-guard` runs on `pre-commit` (`hook.identity-pre-commit`), `commit-msg` (`hook.identity-commit-msg`), and `pre-push` (`hook.identity-pre-push`) to enforce that the author and committer match the expected global identity (`~/.gitconfig`, whose work `includeIf` rules include `~/.gitconfig.work`, plus `~/.gitconfig.local`) and that no `Co-Authored-By:` trailer is present. A repo's own `.git/hooks/*` still runs after them.

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

* **After every apply:** the last lines are a to-do list, `==> To do on this machine after this apply:` with numbered fixes, or `==> Nothing to do on this machine after this apply.` It gathers the requirement check's warnings, the once-per-machine steps not done yet (SSH key, `~/.cfg`, ai-tooling not set up, the dotfiles-local links on a Mac, `gh` on SSH and logged in, LunarVim on Omarchy, iTerm2's default profile and Claude Code integration), and the apps to reload because their config just changed (Ghostty `Ctrl+Shift+,` / `Cmd+Shift+,`, `herdr server reload-config`, tmux `Ctrl-b r`, foot new windows, `exec zsh` in open shells). Scripts add to it with `todo` from `.chezmoitemplates/after-apply.sh`. Where `~/ai-tooling` exists, the apply also runs `make -C ~/ai-tooling deploy` (script `run_after_98_ai_tooling.sh`), so the agents' settings, instructions and skills follow the repository on every apply; its steps and any failure show in the apply output, and a failure adds one line to the list, as does a step that only warned (`⚠`; the deploy tells the script through a temporary status file, `AI_DEPLOY_STATUS_FILE`) (a missing or unusable `make`, such as a Mac without the Xcode command line tools, or a `~/.cfg` not yet pulled, is named there). The script puts Homebrew on `PATH` and runs the deploy with `ARGS=` pinned empty, so an `ARGS=--dry-run` in your shell never turns an apply into a dry run. A new machine, step by step: `docs/NEW_MACHINE.md`.
* **What chezmoi touches:** single files, written as real files (no symlinks). It never deletes or replaces anything it does not manage, so the rest of `~/.config` stays as it is. It does set the permissions of the directories it manages (`~/.vim` is `0700`).
* **Apple silicon Macs:** chezmoi installs the formulae and casks in `[darwin.brew]` of `.chezmoidata/packages.toml` with `brew bundle`, apps included: 1Password, Claude, Google Chrome, Slack, Visual Studio Code, Cursor (Tailscale stays per Mac). An app already in `/Applications` that Homebrew did not install is taken over first (`brew install --cask --adopt`, printed as it runs); one from the App Store is left alone and left out of `brew bundle`. Intel Macs: by hand (`docs/INTEL_MACS.md`).
* **Omarchy:** chezmoi installs only the packages in `[omarchy]` of `.chezmoidata/packages.toml` (`age`, `duf`, `dust`, `fx`, `gitleaks`, `httpie`, `shellcheck`, `vim`, `wget`, `zsh`, `zsh-autosuggestions`, `omarchy-zsh`, `alacritty`, `kitty`, `ghostty`, `herdr-app`, `chezmoi`, the apps `google-chrome`, `visual-studio-code-bin`, `cursor-bin`, `claude-desktop`, `slack-desktop` (Tailscale and 1Password come through Omarchy's installers, below), and `lunarvim-git` and `waveterm-bin` (Wave) from the AUR; LunarVim then needs a one-time per-user link: `mkdir -p ~/.local/share/lunarvim && ln -s /usr/share/lunarvim ~/.local/share/lunarvim/lvim`, then `lvim --headless +qa`. Never run the package's `init-lvim.sh`: it overwrites `~/.config/lvim/config.lua` and installs tools with `yarn global` and `cargo`. If its build seems stuck on `gdb-add-index` lines, that is makepkg's slow `debug` pass, not a loop), only with `omarchy pkg add` / `omarchy pkg aur add`, and only when `chezmoi apply` runs in a terminal (they ask for the sudo password). Otherwise it prints the command, and the check after every apply keeps listing what is missing. Runtimes: `omarchy install dev-env go` (or `python`, ...). `bitwarden-cli` is macOS-only: Arch's package needs Node 22, which conflicts with Omarchy's Node. Build AUR packages with the system Python first (`PATH="/usr/bin:$PATH" omarchy pkg aur add ...`) once `omarchy install dev-env python` has put mise's Python on `PATH`. Omarchy's own Alacritty, Starship, `~/.config/mise/config.toml` and Neovim files are left alone; tmux and Herdr use the shared configs; Neovim gets only `lua/plugins/shared.lua`.
* **Other Linux:** no system packages are installed; the distribution brings its own.
* **zsh on Omarchy:** the interactive shell, the way Omarchy's `omarchy-zsh` package does it: a marked block in `~/.bashrc` (added by `~/guides/omarchy/zsh/apply.sh`, not by chezmoi) hands a new terminal's bash, or an interactive SSH login, over to zsh. The login shell stays bash, so the desktop session, `ssh host '<command>'`, `bash -c` and scripts never run zsh. In interactive shells `~/.zshrc` first loads `omarchy-zsh`'s zsh options (Up/Down search history by prefix, highlighted Tab menu, case-insensitive completion, syntax highlighting, `AUTO_CD`, `EXTENDED_GLOB`; its emacs keys are switched to vi later, as on every host, see "zsh Line Editor"), then Omarchy's own current envs, aliases and helpers from `$OMARCHY_PATH/default/bash` (`cx`, `a`, `h`, `mup`, `hdl`, `rsw`, `fip` and the rest, as in bash; `EDITOR` and `BROWSER` are Omarchy's launchers). `ssh` (reconnect), `iso2sd` and `format-drive` run in bash, because zsh misreads them. Everything after that block still wins: history (50,000 lines), fzf, zoxide, mise, starship, `~/.aliases`, `~/.zshrc.local`. It exports `SHELL=/usr/bin/zsh`, so tmux, herdr and nvim's terminal open zsh, and `CLAUDE_CODE_SHELL=/usr/bin/bash`, so Claude Code keeps bash (the Macs set it in `~/.zprofile`, which a non-login zsh does not read). Without the package the block is skipped and zsh behaves as on other Linux hosts. Undo: `~/guides/omarchy/zsh/undo.sh`.

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

### New Mac (one command)
From Terminal on a fresh Apple-silicon Mac (Intel Macs: `docs/INTEL_MACS.md`):

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/simars/dotfiles/main/bootstrap/macos.sh)
```

Command Line Tools (macOS's dialog, then run it again), Homebrew, the SSH key (stops until `~/.ssh/id_rsa` is there),
`chezmoi init --apply` (apps, macOS settings, Ctrl+Space off, iTerm2's default profile, `gh` over SSH, Hammerspoon
opened once), GitHub over SSH and the passphrase, then `~/.cfg` and its installer (`~/guides/install.sh`: dotfiles-local
links, Claude Code, ai-tooling, `gh` login, remote access, power; it asks). Every command is printed before it runs;
safe to run again. Then yours: sign-ins, Tailscale, Hammerspoon's permission, iTerm2's Claude Code integration, Screen
Sharing control, a log out (`docs/NEW_MACHINE.md`, section A).

### New Omarchy Machine (one command)
From a terminal on a fresh Omarchy, signed in as yourself:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/simars/dotfiles/main/bootstrap/omarchy.sh)
# with the remote disk unlock (changes boot; per machine): add --with-remote-unlock
```

| Step | What happens | Your part |
| :--- | :--- | :--- |
| 1. chezmoi, git | `omarchy pkg add chezmoi git` | sudo password |
| 2. Dotfiles and setup | `chezmoi init --apply` (https): packages and apps, Tailscale and 1Password installers, `python` / `go` runtimes, shell plugins | chezmoi's four questions (Git email and name, work email or `none`, work GitHub orgs); the Tailscale login link |
| 3. SSH key | stops until `~/.ssh/id_rsa` is there (copy it by hand), saves its passphrase (`ssh-key-remember`), checks GitHub over SSH, switches chezmoi's remote to SSH | copy the key; its passphrase once |
| 4. `~/.cfg` and the rest | clones the private bare repository, then runs its installer (`~/guides/install.sh`): checkout (never overwrites a file; stops and names it), the Claude Code login, ai-tooling, the `gh` login, `setup-guides apply` (zsh, terminals-clipboard, wave-keys, window-rescue, window-keys, caps-prefix) | answer its questions (Enter takes the default) |
| 5. Remote disk unlock | only with `--with-remote-unlock`: the guide's `apply.sh`; the router steps are in its README | router, first unlock at the machine |
| 6. Summary | the requirement check and the guides' verdicts | read it |

Every command that changes the machine is printed (`$ command`) before it runs, in the bootstrap and in the installer.

Safe to run again: after a stop (the SSH key, a failed step) fix the cause and run the same command. Per machine afterwards: monitors (the bar's Display widget, monitor-layout), the tablet mapping, theme, web apps, and signing in to the apps. Then, not done by the bootstrap: `claude` (log in), `gh auth login` and `gh config set git_protocol ssh`; `chezmoi apply` deploys ai-tooling once `~/.cfg` is checked out, and the to-do list at the end of it names whatever is left. The whole list, Mac included: `docs/NEW_MACHINE.md`.

### Omarchy Setup (beyond packages)
Listed in `.chezmoidata/omarchy.toml`; `chezmoi apply` on Omarchy does what it can and the requirement check after every apply reports the rest, each with its fix.

| What | Listed as | Done by `chezmoi apply` | If missing |
| :--- | :--- | :--- | :--- |
| Runtimes `python`, `go` (`omarchy install dev-env`) | `omarchy_dev_env` | yes, from a terminal (needs sudo); otherwise prints the command | `omarchy install dev-env <lang>` |
| Tailscale (service, login, operator, Taildrop, bar widget) and 1Password (+ CLI, browser extension) | `omarchy_installers` | yes, from a terminal, when the package is missing | `omarchy install service tailscale` / `service 1password` |
| Shell plugins: monitor-layout (replaces Omarchy's display widget), drawing-tablet, sandman | `omarchy_plugins` | yes: `omarchy plugin add <url>` (latest version), enabled in the bar's right section | `omarchy plugin add <url> --enable` |
| Guides `zsh`, `terminals-clipboard`, `wave-keys`, `window-rescue`, `window-keys`, `caps-prefix` (`~/guides/omarchy`, private `~/.cfg`) | `omarchy_guides` | **no**, only reported | `setup-guides apply` (`setup-guides` alone shows each guide's verdict) |

Plugin settings stay per machine: `~/.config/omarchy/monitor-layout.json` (your monitors), `~/.config/omarchy-drawing-tablet/tablets.json` (tablet to screen), `~/.config/omarchy/sandman.json`. Update plugins with `omarchy plugin update`. On a new machine, `setup-guides` first asks for `~/.cfg` and prints the clone command.

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
| `dkill` | `docker compose down` in every subdirectory of the current directory that has a `docker-compose.yml` or `.yaml`, printing each `(cd <dir>/ && docker compose down)` first when run on a terminal | `cd ~/code && dkill` |
| `dprune` | `docker system prune -a --volumes -f`: removes every stopped container, unused image, network and volume, without asking | `dprune` |

### SSH Hosts
`~/.ssh/config` (chezmoi) holds only what every host shares: `Host *` defaults, GitHub over port 443 (`ssh.github.com`), and first of all `Include config.d/*.conf`. Your own machines live in `~/.ssh/config.d/own-machines.conf`, which comes from the private `~/.cfg` repository (`config pull --rebase origin main` updates it), so this public repository names none of them, nor the tailnet, DDNS names or home addresses. Until `~/.cfg` is checked out, the include matches nothing and only GitHub and the defaults apply. The machine list, every path to each, the findings behind them and a check script are in `~/guides/ssh-reachability/` (also from `~/.cfg`).

Aliases follow `<machine>[-unlock].<how>`, where the suffix says how the name is reached; the bare name goes over Tailscale. Every path to one machine shares its `User`, key, agent forwarding, keepalives and one `HostKeyAlias`, so switching paths never asks to trust the machine again. Keepalives (every 30 s, 3 missed) end a dead connection within about 90 s, and the `ssh` wrapper then reconnects.

| Suffix | Reached through | Works from |
| :--- | :--- | :--- |
| `.tailnet` (or no suffix) | Tailscale's full MagicDNS name, which keeps resolving when another VPN replaces the DNS search list | anywhere Tailscale is up |
| `.local` | Bonjour/Avahi | home network |
| `.viaworks` | the Mac's `.local` name, through the always-on Omarchy machine over Tailscale | anywhere, while the Mac is at home: **wakes a sleeping Mac** (home-network traffic wakes a Mac on AC power; Tailscale traffic does not), and works when its Tailscale is off. Add `-J works.tplink` if yours is down too |
| `.lan` | the address reserved on the home router | home network |
| `.ddns`, `.tplink` | the router's port forwards, through a DDNS name | anywhere |

Agent forwarding is on for your own machines only, so `git pull`, `chezmoi update` and other GitHub access in an SSH session there use the key of the machine you connect from (a Mac's Keychain is locked to SSH sessions, and Omarchy sets its agent only for the desktop session). Never under `Host *`: while a session is open, an admin of the remote machine could use the key. A `-unlock` alias reaches a machine's disk-unlock screen while it boots (root on port 2222, its own host key alias, no agent; see `~/guides/omarchy/remote-disk-unlock`).

### Tailscale CLI on the Macs (`tailscale`)
`~/.local/bin/tailscale` (macOS only) runs Tailscale's CLI whichever variant is installed: Homebrew's open-source `tailscale` or the Standalone app's launcher in `/usr/local/bin` when present, otherwise the CLI inside the App Store app (`/Applications/Tailscale.app/Contents/MacOS/Tailscale`, which has no installer of its own). Omarchy and other Linux hosts use the packaged `/usr/bin/tailscale`. Over a plain `ssh host 'cmd'`, macOS's PATH is only `/usr/bin:/bin:/usr/sbin:/sbin`, so use `ssh host '~/.local/bin/tailscale status'` or a login shell (`ssh host zsh -lc 'tailscale status'`).

| Command | Use |
| :--- | :--- |
| `tailscale status` | Peers, and how each is reached (`direct` or `relay`) |
| `tailscale ping <host>` | Whether a peer answers through Tailscale, and by which path |
| `tailscale debug prefs` | This machine's settings (Tailscale SSH, exit node, auto-update) |

### Which Machine Am I On (prompt tag, tmux and Herdr bars)
Every machine's short name is in three places:

| Where | Shows | When |
| :--- | :--- | :--- |
| zsh prompt | `~/proj ❯ … [works]` on the right of the line you type on, magenta | SSH sessions only (local terminals unchanged) |
| tmux status bar | the name at the right end of the top bar, magenta | always |
| Herdr tab bar | the name at the right end of the tab bar (after `ZOOM` when zoomed) | always; it runs on the Herdr server, so a session attached from another machine names the machine it runs on |

* **The names** are the SSH aliases (`works`, `mbp`, `mbp-work`, `mbp-16i`, `mbp-32i`): `~/.local/bin/host-label` prints this machine's from `~/dotfiles-local/host-labels` in the private `~/.cfg` ("hostname label" per line, the hostname as `hostname -s` prints it, any case), else its short hostname in lower case. `host-label` alone prints it; `host-label <hostname>` looks one up.
* **A new machine:** add its line to `~/dotfiles-local/host-labels`, commit with `config`.
* **The prompt** puts it on the right because Starship's prompt starts with a blank line. Inside a tmux or Herdr session started on the machine itself and attached over SSH, the shell does not know it runs over SSH, so there the bar names the machine instead of the prompt.

### SSH Key Passphrase (`ssh-key-remember`)
`ssh-key-remember` (`~/.local/bin`, every host) saves the `~/.ssh/id_rsa` passphrase in the machine's own keyring once, so the SSH agent unlocks the key by itself after every login and reboot instead of asking. On Omarchy it stores the entry GNOME keyring's SSH agent (`gcr-ssh-agent`) looks up, after checking the passphrase against the key; on macOS it runs `ssh-add --apple-use-keychain`, and `UseKeychain yes` plus `ssh-add --apple-load-keychain` in `~/.zprofile` read it back. Nothing goes into this repository. Run it in a terminal on the machine itself: macOS's Keychain is locked to SSH sessions. After every `chezmoi apply` the requirement check runs `--check` and warns while the passphrase is not saved.

* **Asked for the passphrase although it is saved?** The shell is not talking to that agent: `ssh-add -l` says `Error connecting to agent`. A tmux or Herdr server started from an SSH login hands every pane that login's forwarded agent socket (Herdr through `~/.config/herdr/herdr.sock.agent`), which is gone once the login ends; only a `herdr --remote` attach points Herdr's link somewhere else. On Linux, `~/.zshrc` then switches a new shell to GNOME keyring's agent (`$XDG_RUNTIME_DIR/gcr/ssh`) whenever `SSH_AUTH_SOCK` is dead, and leaves a live one alone. In a shell that is already open: `export SSH_AUTH_SOCK=$XDG_RUNTIME_DIR/gcr/ssh`. For good, start the server from a terminal at the machine (`herdr server stop` ends the programs in its panes, then `herdr`), so its panes also stop inheriting that login's `SSH_CONNECTION` (the `[works]` tag in the prompt, and Copilot CLI taking itself for remote) and get `WAYLAND_DISPLAY`.

| Command | Use |
| :--- | :--- |
| `ssh-key-remember` | Save the passphrase once on this machine (says so and exits if it is already saved). |
| `ssh-key-remember --check` | Report only, never prompt: exit 0 saved (or no passphrase), 1 not saved, 2 cannot tell (a Mac over SSH). |
| `ssh-key-remember --force` | Save it again, after changing the passphrase. |
| `ssh-key-remember <key>` | Another key than `~/.ssh/id_rsa`. |

### Claude Code's Shell (macOS and Omarchy)
Claude Code runs its Bash tool in bash, not zsh. Claude writes bash, and zsh differs from it in ways that break those commands: `"$sha:path"` applies the `:a` or `:s` modifier, `"$r[: ]"` is read as an array subscript, and an unquoted `$pair` is not split on spaces. `~/.zprofile` therefore exports `CLAUDE_CODE_SHELL`: Homebrew's bash 5, or Apple's `/bin/bash` 3.2 where Homebrew has none (Intel Macs). Claude Code then sources `~/.bashrc` instead of `~/.zshrc`. That file is deployed by chezmoi and defines no aliases, because an alias also blocks a function of the same name. On Omarchy, interactive zsh exports `CLAUDE_CODE_SHELL=/usr/bin/bash` from `~/.zshrc`, and Claude Code reads Omarchy's `~/.bashrc` there (not managed by chezmoi).

| Command | Purpose | Example |
| :--- | :--- | :--- |
| `echo $CLAUDE_CODE_SHELL` | See which bash Claude Code will use | `/opt/homebrew/bin/bash`. Takes effect for `claude` started from a new terminal |
| Ask Claude to run `echo "$BASH_VERSION"` | Confirm the tool shell | Prints `5.3...`. Empty output means it is still zsh |
| `export CLAUDE_CODE_SHELL=/bin/zsh` | Go back to zsh on one host | In `~/.zshenv`, which zsh reads before `~/.zprofile` |
| `~/.bashrc.local` | Host additions to Claude's bash | Lines installers append to `~/.bashrc` (fzf, LM Studio) belong here |

### tmux Sessions
`tat` (`~/.local/bin/tat`, deployed by chezmoi) opens the tmux session named after the current directory, so each project keeps its own session that survives a detach. Dots and colons in the directory name become dashes (`my.app` gives `my-app`), because tmux cannot target a session name that contains them. `tat` prints the tmux command it runs (`→ tmux new-session -As my-app`) when stderr is a terminal. It is a POSIX `sh` script adapted from [thoughtbot/dotfiles](https://github.com/thoughtbot/dotfiles/blob/main/bin/tat).

| Command | Purpose | Example |
| :--- | :--- | :--- |
| `tat` | Attach to, or create, the session named after the current directory | `cd ~/code/my.app && tat` attaches `my-app`, creating it on first use |
| `tat <name>` | Same, with an explicit session name | `tat scratch` |
| `tat` (inside tmux) | Switch the client to that session instead of nesting one, creating it first if needed | `tat other-project` from any session |
| `tm` | Attach to, or create, one fixed session called `main` | Alias for `tmux new-session -A -s main` (in `~/.aliases`, so bash has it too) |
| `Ctrl-b d` | Detach and leave the session running | `tmux ls` lists sessions, `tat` re-attaches |
| `Ctrl-b !` | Break the current pane out into its own window | Press `Ctrl-b`, release, then `Shift-1`. herdr binds the same keys to move the pane into a new tab |
| `Ctrl-b J` | Move the current pane into another window you pick | Press `Ctrl-b`, release, then `Shift-j`. The program keeps running; a window left empty closes (in Herdr a tab, and a workspace left without tabs). herdr binds the same keys for its tabs |

### tmux and Herdr Keys (macOS and Omarchy)
One config on every machine. The prefix is `Ctrl-b` or `Ctrl-Space` (Omarchy's old prefix) in both; Herdr needs 0.9.2 or later for `Ctrl-Space`, in its running server too (the apply's to-do list says when the server is older). Press the prefix, release, then the key. `Alt` chords need Option-as-Meta in a Mac terminal. On Omarchy, Super+Alt+K and Super+Ctrl+K list every key. New panes open zsh in both (tmux `default-shell`, Herdr `default_shell`), whatever shell started the server.

| Key | tmux | Herdr |
| :--- | :--- | :--- |
| `h` `j` `k` `l` (or arrows) | Focus pane left, down, up, right | Same |
| `{` `}` / `Shift-h` `Shift-l` | Swap pane up, down / left, right | Same |
| `Alt-arrows` (after the prefix) | Resize pane (tmux default) | Same |
| `"` `-` (or `Alt-Enter`) | Split, new pane below | Same |
| `%` `v` (or `Alt-Shift-Enter`) | Split, new pane to the right | Same |
| `x` (or `Alt-Esc`) | Kill pane (asks first) | Close pane (asks first) |
| `z` / `;` / `o` | Zoom / last pane / next pane | Same |
| `Shift-e` | Spread the current pane and its neighbours evenly (tmux `E`) | Make every pane in the tab equal, by `herdr-equalize` (Herdr has no such action; the script evens each split's ratio), as Ghostty's leader `Shift-e` does |
| `!` | Break pane into a new window | Move pane into a new tab |
| `Shift-j` | Move the pane into another window: pick it in `choose-tree`, the pane joins on the right (`join-pane -h`) | Same, in a popup that lists every other tab of every workspace (fzf, or a numbered list without it), by `herdr-join`, which unzooms first as tmux does; `Esc` (fzf) or Enter with no number (list) cancels |
| `Space` / `Alt-1`..`7` | Next preset layout / pick one: side by side, stacked, main on top, main on the left, tiled, main at the bottom, main on the right | Same, by `herdr-layout` (it rebuilds the tab through a temporary tab; programs keep running) |
| `Ctrl-o` / `Alt-o` | Rotate the panes forward / back (the next pane becomes the main pane; focus stays on the place) | Same, by `herdr-layout` |
| `c` / `,` / `&` | New / rename / kill window (asks first) | New / rename / close tab (asks first) |
| `1`..`9` (or `Alt-1`..`9`), `n` `p` | Go to window | Go to tab |
| `Alt-Left` / `Alt-Right` | Not bound (Omarchy's stock: previous / next window); passed to the pane, where zsh jumps a word | Same, for tabs |
| `R` `C` `K` `P` `N` | Rename / new / kill (asks first) / previous / next session | `Shift-r` (or `$`) `Shift-c` `Shift-k` `Shift-p` `Shift-n` for workspaces (closing asks first) |
| `s` / `w` | Choose session / choose window (tmux defaults) | Workspace picker (both keys) |
| `(` / `)` | Previous / next session (tmux defaults) | Previous / next workspace |
| `f` | Find window (tmux default) | Goto picker |
| `q` | Show pane numbers; press one to jump (tmux default) | Goto picker (also `g`); Herdr has no pane numbers |
| `r` | Reload config | Same |
| `[` | Copy mode (`v` select, `y` copy) | Same |
| `e` | Open the scrollback in `$EDITOR` (popup) | Same |
| `Shift-t` | Rename pane (tmux: pane title) | Same |
| `?` | Key list (Omarchy's menu on Omarchy) | Help |
| `d` | Detach | Same |
| `Ctrl-Alt-arrows` / `Ctrl-Alt-Shift-arrows` | Focus / resize pane, no prefix | Same |
| `b`, `Shift-o`, `Shift-s`, `Shift-g` | | Sidebar, notification target, settings, new git worktree |

On the Macs `Ctrl-arrows` after the prefix never arrive (macOS switches Spaces or opens Mission Control), so tmux's 1-cell resize and Herdr's resize mode work only on Omarchy; resize with `Alt-arrows` after the prefix, or `Ctrl-Option-Shift-arrows`.

tmux keys Herdr lacks: paste buffers (`]` `#` `=`), command prompt (`:`), mark (`m`), move or pick a window by number (`.` `'`), and `PageUp` into copy mode.

`omarchy refresh tmux` (or `herdr`) puts Omarchy's stock file back; `chezmoi apply ~/.config/tmux/tmux.conf` (or `~/.config/herdr/config.toml`) restores the shared one.

### Terminal Tabs and Splits (`Cmd-b` / `Super-b`)
The terminal's own tabs and splits use tmux's letters behind a different prefix: `Cmd-b` on the Macs, `Super-b` on Omarchy (Super is Omarchy's Cmd). Press the leader, release, then the key, exactly as after `Ctrl-b` in tmux. `Ctrl-b` / `Ctrl-Space` stay tmux's and Herdr's. Any other key after the leader does nothing (it is never typed into the program); `Esc` leaves. foot has no tabs or splits; whether `Super-b` types anything there is still to be checked by hand. Native keys still work: Cmd+T, Cmd+D, Cmd+1..9 on the Macs; Ctrl+Shift+T, Ctrl+Shift+W, Ctrl+Tab on Omarchy's Ghostty.

| Key after the leader | Ghostty (Mac and Omarchy) | iTerm2 (Mac) |
| :--- | :--- | :--- |
| `c` | New tab | Not yet (iTerm2 leader still to come) |
| `%` `v` / `"` `-` | Split right / split down | |
| `h` `j` `k` `l` (or arrows) | Focus split left, down, up, right | |
| `;` / `o` | Previous / next split | |
| `x` / `&` | Close split / close tab (ask first while a program runs) | |
| `z` | Zoom the split | |
| `1`..`9`, `n` `p` | Go to tab, next / previous tab | |
| `,` | Rename tab | |
| `Shift-e` (or `=`) | Make splits equal (tmux `E`) | |
| `Alt-arrows` (Mac: left `Option`) | Resize 40 px, then stay in resize mode: `h` `j` `k` `l` / arrows 20 px, `Alt-arrows` 40 px; `Esc` or `Enter` to stop | |
| `r` | Reload Ghostty's config (as `r` reloads tmux and Herdr); new key bindings still need a restart | |
| `?` | Command palette | |

Ghostty cannot move a split into its own tab, so `!` does nothing. Set in Ghostty's config by `dot_config/ghostty/modify_config.tmpl` (key tables `term` and `term_resize`).

### Moving Between Panes (and Where It Can Trip You)
Each layer has its own keys; the letters are the same, the prefix says which layer moves.

| Layer | Omarchy | Mac |
| :--- | :--- | :--- |
| Desktop windows | `Super+arrows` (Hyprland) | |
| Ghostty splits | `Super-b` then `h` `j` `k` `l` / arrows; `Super+Ctrl+[` `]` previous / next | `Cmd-b` then `h` `j` `k` `l` / arrows; `Cmd+Opt+arrows`; `Cmd+[` `]` |
| iTerm2 panes | | `Cmd+Opt+arrows` (iTerm2's own; no leader yet) |
| tmux and Herdr panes | `Ctrl-b` then `h` `j` `k` `l` / arrows; `Ctrl+Alt+arrows` | Same (left Option only) |
| Neovim windows | `Ctrl+h` `j` `k` `l` (LazyVim) | Same |

One key cannot carry on from tmux or Herdr into the next Ghostty split: Ghostty can be told to pass a split key on when it has no split that way (`performable:`), but then Ghostty moves first and skips tmux's panes, and tmux has no way to tell Ghostty to move. Where it can trip you (seen in the configs and sources, not yet in use):

* **`;` differs.** tmux and Herdr go to the pane last used; Ghostty has no such action, so `Super-b ;` / `Cmd-b ;` goes to the previous split in layout order. Same with two splits, not always with three.
* **At the edge.** tmux wraps (`h` in the leftmost pane goes to the rightmost); Ghostty stays put; Herdr not checked.
* **The wrong prefix does nothing, silently.** `Cmd-b h` inside tmux moves Ghostty's split, not tmux's pane; with no Ghostty split there, nothing happens. Cmd and Ctrl sit side by side on the Mac.
* **Resize mode stays on.** After `Super-b` / `Cmd-b` then `Alt-arrow`, every key but `h` `j` `k` `l`, arrows, `Alt-arrows`, `Esc` and `Enter` is ignored until `Esc` or `Enter`.
* **Neovim in tmux or Herdr.** `Ctrl+h` stops at Neovim's edge; the next pane needs `Ctrl-b h` or `Ctrl+Alt+arrows`.
* **ssh to a host without this tmux config.** Stock tmux has no `h` `j` `k` `l` or `Ctrl+Alt+arrows`; use `Ctrl-b` arrows, `o`, `;`.
* **Herdr inside tmux.** tmux takes `Ctrl-b` and `Ctrl+Alt+arrows` first (parked: `docs/FUTURE_CONSIDERATIONS.md` §11).
* **Omarchy: `Super+arrows` moves windows**, never Ghostty's splits.
* **Mac: right Option is not Alt**, so `Ctrl+right Option+arrows` does not reach tmux or Herdr; iTerm2 has no `Cmd-b` leader yet.

Possible fixes, not made: `docs/FUTURE_CONSIDERATIONS.md` §12.

### Keys the Terminal Must Not Take (macOS and Omarchy)
A key reaches Claude Code, Herdr, tmux or zsh only if nothing before it takes it: first the desktop (Hyprland, macOS), then the terminal app, then Herdr or tmux. A key that is taken does something else instead (Ctrl-Enter in Ghostty made the window full screen, which hides Omarchy's top bar).

| Key | Needed by | Taken by | What to do |
| :--- | :--- | :--- | :--- |
| `Ctrl-Enter` | Claude Code: send queued messages now | Ghostty on Omarchy (full screen) | Given back by chezmoi. Full screen is `Super-F`. Where a terminal sends it as plain Enter, use `Ctrl-x Ctrl-s` |
| `Alt-1`..`9` | Herdr and tmux: go to tab / window | Ghostty on Omarchy (its own tabs) | Given back by chezmoi. Ghostty's tabs: `Ctrl-Tab`, `Ctrl-PgUp` / `Ctrl-PgDn` |
| `Ctrl-Alt-arrows` | Herdr and tmux: focus pane | Ghostty on Omarchy (its own splits) | Given back by chezmoi |
| `Ctrl-b` | Claude Code: run in the background | Herdr and tmux (the prefix) | Press it twice |
| `Super-b` | Ghostty's terminal leader on Omarchy | Hyprland, if Omarchy ever binds Super+B | Left free on purpose; after each apply the requirement check says `OK:   Super+B is free in Hyprland`, or warns and names the binding |
| `Cmd-b` | Ghostty's terminal leader on the Macs (iTerm2's too, once its leader is set up) | Nothing on macOS | |
| `Ctrl-Space` | tmux and Herdr: second prefix | macOS: Select the previous input source, while that shortcut is on | The apply turns it off on every Mac (`run_after_97_macos_defaults.sh`); these Macs never switch input language. |
| `Alt-Enter` | Claude Code: new line | Herdr and tmux (split) | `Shift-Enter` or `Ctrl-j` |
| `Alt-t` `Alt-d` `Alt-n` `Alt-w` `Alt-g` `Alt-1`..`9` ... | Claude Code (`Alt-t` thinking), zsh (`Alt-d` delete word), Herdr | Wave on Omarchy: Wave's Mac `Cmd` keys are `Alt` on Linux, and Wave cannot change them | Run agents and Herdr in Ghostty or foot on Omarchy; Wave is fine on macOS |
| `Alt-Space`, right `Alt`, `F9` | Programs | Omarchy's dictation (toggle; push to talk), once a dictation app is installed; `F9` comes from `~/.config/hypr/bindings.lua` | Not changed; delete the `F9` lines there to give `F9` back |

A running Ghostty needs a restart for changed key bindings: quit it (every window; a new window joins the running Ghostty) and start it again. Reloading its config (`Ctrl-Shift-,`) applies most other settings, but did not pick up new key bindings on 2026-11-20. `ghostty +list-keybinds` shows what Ghostty still takes.

---

## 5. Machine-Specific Customization Points

The configuration strictly separates shared, tracked dotfiles from machine-specific overrides and sensitive local credentials.

| Local Configuration File | Loading Mechanism | Intended Purpose |
| :--- | :--- | :--- |
| `~/.aliases.local` | Sourced at end of `~/.aliases` | Machine-specific shell aliases, hardware shortcuts, or team-specific alias overrides. |
| `~/.zshrc.local` | Sourced at end of `~/.zshrc` | Host-specific Zsh functions, custom prompt overrides, local PATH additions, the sourcing of work-specific env files, or private configurations. |
| `~/.bashrc.local` | Sourced at end of `~/.bashrc` (macOS) | Host additions to Claude Code's bash, such as the lines installers append to `~/.bashrc`. No aliases. |
| `~/.gitconfig.local` | Included via `~/.gitconfig`, last | One machine's own Git settings, such as hardware GPG/SSH signing keys. Not for the work email: that comes from `chezmoi init`. |
| `~/.gitconfig.work` | `includeIf` rules in `~/.gitconfig` | Managed by chezmoi from the `chezmoi init` answers (work email, work GitHub orgs), kept only in `~/.config/chezmoi/chezmoi.toml`. Used for remotes in the work orgs and for clones under `~/<org>/`. Change the answers with `chezmoi init --prompt`, then `chezmoi apply`; type org names as in clone URLs (matching is case-sensitive). Check with `git config --show-origin user.email`. |
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
