# New-Machine Automation: Fewer Hand Steps on a Fresh Mac or Omarchy Machine

Date: 2026-11-26. Status: approved by the user 2026-11-26. A builder check found nothing open; its points are
recorded as calls below.

## Intent

`docs/NEW_MACHINE.md` still has about a dozen hand steps on a Mac (Omarchy already has a one-command bootstrap,
`bootstrap/omarchy.sh`). The user wants everything that can be automated automated, so a new machine is one command
plus sign-ins and a few clicks, and the private setup (`~/.cfg`) is one pasted line that clones it and then **asks
about** the steps the user should run.

## Decided with the user (2026-11-26)

- Out of scope: iTerm2's Claude Code integration (stays a menu click), Tailscale (stays per Mac: App Store or
  standalone variants differ).
- In scope, three pieces, in this order: (1) small chezmoi automations, (2) an interactive installer in `~/.cfg`,
  (3) a Mac bootstrap in the chezmoi repo.
- The `~/.cfg` entry point is **one line using the SSH key**, because `.cfg` is private (no raw download):
  `git clone --bare git@github.com:simars/.cfg.git ~/.cfg && bash <(git --git-dir=$HOME/.cfg show HEAD:guides/install.sh)`
  (`bash <(...)`, not `| bash`, so the script's questions can read the keyboard).
- The Mac apps the user installs by hand become Homebrew casks: 1Password, Claude, Google Chrome, Slack, Visual Studio
  Code, Cursor; plus the `gh` formula.

## Stays manual, by nature (the installer and the apply list them)

Copying the SSH key; typing its passphrase once; browser sign-ins (Claude, `gh`, 1Password, Slack, Chrome, VS
Code/Cursor Settings Sync); macOS privacy clicks (Hammerspoon's Device Control and Data Access, Screen Sharing
control); per-machine choices (monitors, theme, web apps; Mac power: always-on or normal); logging out after
trackpad settings.

## Piece 1: chezmoi automations (public repo)

| Automation | Where | Detail |
| :--- | :--- | :--- |
| Casks `1password`, `claude`, `google-chrome`, `slack`, `visual-studio-code`, `cursor`; formula `gh` | `.chezmoidata/packages.toml` (Apple silicon; Intel by hand per `docs/INTEL_MACS.md`, which lists them) | Before `brew bundle`, the package script **adopts** an app that is already in `/Applications` but not from Homebrew (`brew install --cask --adopt <cask>`) and **skips** one installed from the App Store (`Contents/_MASReceipt`; mbp-work's Slack), so `brew bundle` neither fails on nor duplicates it; the skip is named in the apply's output |
| `gh` uses SSH | a `run_after` check (Mac and Omarchy) | `gh config get git_protocol` not `ssh` → `gh config set git_protocol ssh`; silent without `gh` |
| macOS's Ctrl+Space input-source shortcut off | `run_after_97_macos_defaults.sh.tmpl` (already writes symbolic hotkeys) | id 60 `enabled = 0`; replaces the iTerm2 script's NOTE and to-do for it |
| iTerm2's default profile = chezmoi's | `run_after_96_macos_iterm2.sh.tmpl` | `defaults write com.googlecode.iterm2 "Default Bookmark Guid" chezmoi-left-option-as-alt`, **only while iTerm2 is not running** (it overwrites its preferences on quit); while it runs, the existing NOTE stays |
| LunarVim linked on Omarchy | `run_onchange_after_91_omarchy_setup.sh.tmpl` | the NEW_MACHINE step 5 link (`/usr/share/lunarvim` → `~/.local/share/lunarvim/lvim`, `lvim --headless +qa`) when `lvim` is installed and the link is missing; never `init-lvim.sh` |
| Hammerspoon's first open | the requirement check on a Mac | Hammerspoon installed and never opened (not running, quarantine flag set): `open -a Hammerspoon` once, so macOS's "downloaded app" and permission dialogs appear on screen; NOTE stays until it runs. Never removes the quarantine flag (Gatekeeper is the user's call) |

Docs: `docs/NEW_MACHINE.md` (steps shrink), `docs/CHEATSHEET.md`, `docs/INTEL_MACS.md` (the new casks by hand).

## Piece 2: `~/.cfg` installer (private repo)

`guides/install.sh` (lives in `~/guides`, which `.cfg` already tracks; runs with bash 3.2 on Macs). Safe to re-run:
every step checks first, says `done` and skips, or asks `[Y/n]` (a `--yes` flag accepts every default; no terminal =
list only, change nothing). Steps:

1. **Repository:** if `~/.cfg` is missing, clone it (bare, SSH); `config checkout` (stops and names files it would
   overwrite); `status.showUntrackedFiles no`, the fetch refspec, upstream `origin/main`. A `config` helper in
   `~/.local/bin` when neither chezmoi's helper nor the alias exists yet (machines without chezmoi).
2. **Mac only:** link `~/.zshrc.local` and `~/.aliases.local` to `~/dotfiles-local` (never overwrite a real file; say so).
3. **Claude Code:** installed? (Mac: `curl -fsSL https://claude.ai/install.sh | bash`; Omarchy ships it). Logged in?
   ask to run `claude` now. Then `make setup` in `~/ai-tooling` (ask).
4. **GitHub CLI:** logged in? ask to run `gh auth login`.
5. **Guides:** Omarchy: `setup-guides apply` (sudo, asks). Mac: ask for `~/guides/macos/remote-access/apply.sh`
   (sudo), then ask "always-on or normal power?" (`~/guides/macos/always-on/apply.sh` only for always-on).
6. **Summary:** each step done / skipped / failed, then what stays manual (the list above), then
   `chezmoi apply` until "Nothing to do".

The Omarchy bootstrap's own `~/.cfg` and guides steps call this installer instead (one implementation).

## Piece 3: `bootstrap/macos.sh` (public repo)

Mirrors `bootstrap/omarchy.sh` (one command from a fresh Mac's Terminal, safe to re-run, pauses only where the user
must act): Command Line Tools, Homebrew, SSH key (stops and says where to copy it, as Omarchy's does), chezmoi
`init --apply` (the four questions), chezmoi's remote switched to SSH, `ssh-key-remember`, `ssh -T git@github.com`,
then the `.cfg` line from Piece 2. `docs/NEW_MACHINE.md` section A becomes: run it, then the manual list.
Apple silicon only; on an Intel Mac it stops and points to `docs/INTEL_MACS.md`.

## Transparency (user's requirement, 2026-11-26)

The `.cfg` installer and both bootstraps show what they do: before each step, one plain line saying why
(`==> Link this Mac's own shell settings from ~/dotfiles-local`), then **every command exactly as it runs**
(`$ ln -s ~/dotfiles-local/zshrc.local ~/.zshrc.local`), then its outcome (`done`, `skipped: already linked`,
`FAILED: <reason>`). Questions show the command they would run before asking. Nothing that changes the machine runs
without its command printed first (one shared `run` helper does print-then-execute; checks that only read stay quiet
unless they decide something).

## Constraints

Public repo: no work identifiers, nothing private beyond what is already public (the `.cfg` clone URL is already in
`bootstrap/omarchy.sh` and `setup-guides`). Scripts: `set -euo pipefail`, idempotent, bash 3.2 on Macs, GNU-first
fallbacks. Every new automatic step has a test in `tests/host-profiles.sh` (or the installer's own offline test with
stubs). The apply's to-do list keeps naming whatever is still manual (CLAUDE.md 3.5).

## Approaches considered (the `.cfg` entry)

- **A. Clone with the SSH key, run the installer from the clone** (picked): needs only the SSH key; nothing private
  published.
- B. `gh api` raw download: needs `gh` installed and logged in first.
- C. A public stub in the chezmoi repo doing A: convenient, but a private-repo helper in a public repo for no gain.

## Calls made after the builder check

- **Adoption** needs no fallback: all six casks update themselves, so Homebrew does not compare versions when it
  adopts a hand-installed copy; app names are `1Password.app`, `Claude.app`, `Google Chrome.app`, `Slack.app`,
  `Visual Studio Code.app`, `Cursor.app`.
- **Power question:** default "normal" (the always-on guide forbids always-on on a Mac that travels), so `--yes` never
  makes a Mac always-on; done-ness from `always-on/status.sh` (`ALWAYS ON` / `REGULAR`).
- **Remote access done-ness:** check Remote Login and Touch ID for sudo directly; the guide's verdict never reads ready
  because Screen Sharing control stays a click.
- **Re-runs:** the pasted line is for a fresh machine (its `git clone` fails once `~/.cfg` exists); later runs call
  `~/guides/install.sh` directly, and both bootstraps skip the clone when `~/.cfg` exists.
- **Omarchy bootstrap** runs the whole installer (so it also asks about Claude Code, ai-tooling and `gh`);
  `--with-remote-unlock` stays in the bootstrap.
- **Other systems** (Linux without Omarchy, a Mac without chezmoi): the installer skips OS-specific steps it cannot do.
- **Mac facts checked on a Mac during the build:** how "never opened" shows for Hammerspoon, writing shortcut 60 on a
  fresh Mac, iTerm2's default profile before its first launch; tests use stand-ins (`brew`, `open`, `xattr`, as the
  suite already does for `defaults`, `pgrep`, `hidutil`).

## Left to the builder

The installer's prompt wording; whether adoption is tested on mbp-work (it has hand-installed 1Password, Claude,
Chrome, Cursor) or mbp first; the requirement check's wording for skipped App Store apps.
