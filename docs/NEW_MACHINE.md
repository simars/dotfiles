# New Machine Guide (Apple-silicon Mac and Omarchy)

Everything a new machine needs, in order, with what chezmoi does for you and what is yours to do. Intel Macs follow
[`INTEL_MACS.md`](INTEL_MACS.md) instead (dotfiles only, tools by hand).

> [!NOTE]
> Checked on 2026-11-19 against the machines already set up (two Apple-silicon Macs and one Omarchy machine). Neither
> path has run on a blank machine yet: the Omarchy bootstrap was re-run on a machine already set up (2026-11-16). Fix
> this file in the same commit when a step turns out different.

**Every `chezmoi apply` (and `chezmoi update`) ends with a list.** Either `==> Nothing to do on this machine after
this apply.`, or `==> To do on this machine after this apply:` followed by numbered steps with the exact fix. The
list covers the once-per-machine steps below that chezmoi can see. It also covers warnings from the requirement check,
and apps whose config just changed and need a reload. Follow it until it says nothing is left (see
[After every apply](#after-every-apply)).

## Before you start (both)

- **Your SSH key**, `id_rsa` and `id_rsa.pub`, on a USB stick or on another of your machines, and its passphrase.
  GitHub, `~/.cfg` and the hosts in `~/.ssh/config` need it.
- Time: the first apply on a Mac installs about 47 Homebrew tools and 14 apps.

## A. New Apple-silicon Mac

1. **Finish macOS setup** and open Terminal.
2. **Run the bootstrap.** Have the SSH key at hand; it stops until the key is in place.
   ```bash
   bash <(curl -fsSL https://raw.githubusercontent.com/simars/dotfiles/main/bootstrap/macos.sh)
   ```
   - It installs the Command Line Tools (macOS's dialog: finish it, then run the same command again) and Homebrew
     (asks for your password), stops until `~/.ssh/id_rsa` is there (it prints the copy command), then runs
     `chezmoi init --apply` (chezmoi's four questions: Git email and name, work email or `none`, work GitHub orgs).
     The answers stay in `~/.config/chezmoi/chezmoi.toml`, never in the repository; change them later with
     `chezmoi init --prompt`, then `chezmoi apply`.
   - chezmoi installs the Homebrew tools and apps in `.chezmoidata/packages.toml` (iTerm2, Ghostty, kitty, Wave, Warp,
     the Herdr app, Hammerspoon, the 1Password CLI, the Nerd Font, 1Password, Claude, Chrome, Slack, VS Code, Cursor,
     `gh`), LunarVim and the mise runtimes. Apps already installed by hand are taken over by Homebrew; App Store
     copies are left alone. It sets macOS's own settings (cheatsheet: "Same macOS Settings on Every Mac"), turns off
     macOS's Ctrl+Space input-source shortcut (tmux's and Herdr's second prefix), makes chezmoi's iTerm2 profile the
     default (while iTerm2 is closed), sets `gh` to clone over SSH and opens Hammerspoon once.
   - It then switches chezmoi to SSH, saves the key's passphrase in the Keychain (`ssh-key-remember`, asks for it once),
     clones `~/.cfg` and runs its installer (`~/guides/install.sh`), which asks about each of: linking this Mac's own
     settings from `~/dotfiles-local`, installing Claude Code and logging in, ai-tooling, the `gh` login, remote access
     (Remote Login, Touch ID for sudo; sudo) and power (always-on or normal; normal by default).
   - Every command that changes the Mac is printed (`$ command`) before it runs. It is safe to run again: after any
     stop, fix what it says and run the same command. Later, `~/guides/install.sh` alone repeats the private part.
   - On a work Mac, also create any work env files `~/.zshrc.local` sources. They are never committed.
3. **Sign in to the apps:** 1Password (then Settings > Developer > Integrate with 1Password CLI, for `op`), Claude,
   Chrome, Slack, VS Code and Cursor (Settings Sync carries their settings). Tailscale is the one app chezmoi does not
   install: install it (App Store or standalone) and sign in; the short SSH host names need it.
4. **Hammerspoon, once.** It runs the window keys (Ctrl+Option+Cmd), the Caps Lock prefix (hold Caps Lock for the
   window keys) and the window rescue (Cmd+Ctrl+U); cheatsheet: "Window Keys" and "Lost and Minimized Windows". Until
   this step none of them work, and Caps Lock stays plain Caps Lock. The first apply opens it for you (once); if it
   did not, open it (`open -a Hammerspoon`). Choose **Open** when macOS asks about an app downloaded from the Internet, and allow
   it in System Settings > Privacy & Security > Device Control and Data Access (Accessibility before macOS 27): switch
   Hammerspoon on there, or add it with **+** from `/Applications` if it is not listed. chezmoi's config never asks
   for it (on macOS 27 asking showed the dialog on every config reload). It starts at login after that. The apply
   lists it while it is not running. Its own settings (Dock icon, console on top) can stay off.
5. **iTerm2, once:** the menu **iTerm2 > Install Claude Code Integration**; choose **Mark Rewritable and Install**.
   Then quit and reopen iTerm2, so it loads the shared global settings (cheatsheet: "Same iTerm2 on Every Mac").
6. **Warp, if you use it:** Settings > Features > Keys: Left Option is Meta on, Right Option is Meta off. Warp's
   account sync carries it to your other Macs, and chezmoi leaves it alone.
7. **Screen Sharing control:** System Settings > General > Sharing > **Remote Management** (a script can't turn on
   screen control). The apply lists it while it is off.
8. **MCP servers:** with each agent's own command or claude.ai connectors (`~/ai-tooling/docs/MCP_NATIVE_SETUP.md`).
   Never run ai-tooling's retired `make mcp-*`.
9. **Log out and back in** once, for the trackpad settings.
10. **Check:** `chezmoi apply`. Repeat steps from the list until it says `Nothing to do on this machine`.

## B. New Omarchy machine

1. **Install Omarchy**, sign in, and open a terminal (`Super + Enter`).
2. **Run the bootstrap.** Have the SSH key at hand; it stops until the key is in place.
   ```bash
   bash <(curl -fsSL https://raw.githubusercontent.com/simars/dotfiles/main/bootstrap/omarchy.sh)
   ```
   - Add `--with-remote-unlock` only for unlocking the disk over SSH. That guide's README has the router steps and
     the first unlock at the machine.
   - It installs chezmoi and git, then applies the dotfiles, packages, apps, runtimes, Tailscale, 1Password and shell
     plugins. It checks your SSH key, clones `~/.cfg` and runs its installer (`~/guides/install.sh`), which asks
     about the Claude Code login, ai-tooling, the `gh` login and the guides (zsh, terminals-clipboard, wave-keys,
     window-rescue, window-keys, caps-prefix). Every command is printed before it runs.
   - It pauses for the sudo password, chezmoi's four questions (as on the Mac: Git email and name, work email or
     `none`, work GitHub orgs), the Tailscale login link, the SSH key and its passphrase.
   - It is safe to run again: after any stop, fix what it says and run the same command.
3. **Open a new terminal.** It starts zsh; the login shell stays bash.
4. **Claude Code, ai-tooling and `gh`:** the bootstrap's installer asked about each. Anything you said No to, or that
   failed: run `~/guides/install.sh` again (it skips what is done).
5. **LunarVim:** nothing to do: the apply links it for you once LunarVim is installed (never its `init-lvim.sh`).
   If LunarVim arrives later, the list names the link command.
6. **Per machine, by hand:**
   - Arrange the monitors in the bar's Display widget (monitor-layout), and the tablet in its widget.
   - Pick the theme and add the web apps.
   - Sign in to 1Password, Chrome, Slack, VS Code and Cursor (Settings Sync), and Claude.
   - Add MCP servers and connectors as on the Mac.
7. **Check:** `chezmoi apply`, then follow the list until it says `Nothing to do on this machine`.

## After every apply

What the list at the end of `chezmoi apply` / `chezmoi update` can name:

| Kind | Examples | Where it comes from |
| :--- | :--- | :--- |
| Requirement warnings | gitleaks missing (fails the apply), old git or mise, SSH passphrase not saved, missing Omarchy packages, runtimes, plugins or guides | `run_after_99_assert_requirements.sh` |
| Once-per-machine steps not done | no SSH key, `~/.cfg` not cloned, ai-tooling not set up, dotfiles-local links missing (Mac), Hammerspoon not installed or not running (Mac), `gh` not on SSH or not logged in, LunarVim not linked (Omarchy) | `run_after_99_assert_requirements.sh` |
| No work email answer | `chezmoi init` never got a work email (an init with `--promptDefaults`, or a machine set up before 2026-11-19): `chezmoi init --prompt` | `run_after_99_assert_requirements.sh` |
| iTerm2 (Mac) | reopen iTerm2 for updated global settings; chezmoi's profile not the default; Claude Code integration missing; macOS still takes Ctrl+Space (settings changed on one Mac only are reported, not listed) | `run_after_96_macos_iterm2.sh` |
| macOS settings (Mac) | log out and back in after trackpad, scrolling, appearance or Spotlight settings were written; a key `defaults` could not write; Remote Login, Screen Sharing or wake for network access on AC is off | `run_after_97_macos_defaults.sh` |
| A config changed under a running app | Ghostty: `Ctrl+Shift+,` (Mac: `Cmd+Shift+,`); Herdr: `herdr server reload-config`; tmux: `Ctrl-b r`; foot: new windows; open shells: `exec zsh` | `run_after_99_assert_requirements.sh` (checksums in `~/.local/state/chezmoi-after-apply`; the first apply only records them) |
| Omarchy stock files changed | merge the change into the chezmoi source | `run_after_95_omarchy_stock_drift.sh` |

Uninstalled project runtimes (`mise-audit`) stay a `WARN:` line above the list, not on it: a pin that can never
install (an old Ruby) would keep the list from ever saying "Nothing to do". It cannot see sign-ins to apps, Warp's Option setting, MCP connectors or the remote unlock's router steps. Over
SSH on a Mac it cannot read the Keychain, so the SSH passphrase and `gh` login show as "not checked" there.
