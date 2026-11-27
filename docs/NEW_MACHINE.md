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
- Time: the first apply on a Mac installs 46 Homebrew tools and 8 apps.

## A. New Apple-silicon Mac

1. **Finish macOS setup** and open Terminal.
2. **Command Line Tools and Homebrew** (chezmoi's install step tries both too, but Homebrew's installer needs your
   password, so do it here):
   ```bash
   xcode-select --install            # wait for the dialog to finish
   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
   eval "$(/opt/homebrew/bin/brew shellenv)"
   ```
3. **SSH key** (from your USB stick or another copy):
   ```bash
   install -m 700 -d ~/.ssh && install -m 600 <copy>/id_rsa ~/.ssh/ && install -m 644 <copy>/id_rsa.pub ~/.ssh/
   ```
4. **chezmoi**, into `~/.local/bin`, then the dotfiles over https (the repository is public):
   ```bash
   sh -c "$(curl -fsLS get.chezmoi.io)" -- -b "$HOME/.local/bin" init --apply https://github.com/simars/dotfiles.git
   ```
   - It asks four questions: your Git email and name, your work email and your work GitHub orgs (separated by commas,
     spelled as in clone URLs). Answer the work ones on every machine, or `none` for the email on one that never has
     work repositories. The answers stay in `~/.config/chezmoi/chezmoi.toml` on this machine, never in the
     repository, and chezmoi builds the work rules in `~/.gitconfig` and `~/.gitconfig.work` from them. To change
     them later: `chezmoi init --prompt`, then `chezmoi apply`.
   - It then installs the Homebrew tools and apps in `.chezmoidata/packages.toml` (iTerm2, Ghostty, kitty, Wave, Warp,
     the Herdr app, Hammerspoon, the 1Password CLI, the Nerd Font, 1Password, Claude, Chrome, Slack, VS Code, Cursor, `gh`),
     LunarVim and the mise runtimes. Apps already installed by hand are taken over by Homebrew; App Store copies are left alone.
   - It sets macOS's own settings (Dock, Mission Control, Finder, trackpad, appearance, menu bar; cheatsheet: "Same
     macOS Settings on Every Mac"), restarts the Dock and Finder, and lists a log out for the trackpad settings.
   - It ends with the to-do list. Most of it is the steps below.
5. **Open a new terminal tab.** zsh now loads the new setup: Homebrew, `~/.local/bin` (chezmoi, `ssh-key-remember`)
   and `config` (the `~/.cfg` helper) are on `PATH`.
6. **Switch chezmoi to SSH and save the key's passphrase** (in a terminal on the Mac, not over SSH: the Keychain is
   locked there):
   ```bash
   chezmoi git -- remote set-url origin git@github.com:simars/dotfiles.git
   ssh-key-remember                 # once per machine; the agent then unlocks the key at every login
   ssh -T git@github.com            # "successfully authenticated" means it works
   ```
7. **Private files: `~/.cfg`** (ai-tooling, the guides, dotfiles-local, llm):
   ```bash
   git clone --bare git@github.com:simars/.cfg.git ~/.cfg
   config config status.showUntrackedFiles no
   config config remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*'
   config fetch origin
   config checkout                  # stops and names any file it would overwrite: move those aside, run it again
   config branch --set-upstream-to=origin/main main
   ```
8. **This Mac's own settings** from `~/dotfiles-local`, plus local-only files (cheatsheet, "Machine-Specific
   Customization Points"):
   ```bash
   ln -s ~/dotfiles-local/zshrc.local ~/.zshrc.local
   ln -s ~/dotfiles-local/aliases.local ~/.aliases.local
   ```
   On a work Mac, also create any work env files `~/.zshrc.local` sources. They are never committed. (The work git
   email needs nothing here: it comes from chezmoi's questions in step 4.)
9. **Claude Code, then ai-tooling** (Claude's, Cursor's and the other agents' shared config, skills and agents):
   ```bash
   curl -fsSL https://claude.ai/install.sh | bash
   claude                           # log in, then quit
   cd ~/ai-tooling && make setup
   ```
   Add MCP servers with each agent's own command or claude.ai connectors (`~/ai-tooling/docs/MCP_NATIVE_SETUP.md`).
   Never run ai-tooling's retired `make mcp-*`.
10. **GitHub CLI** (chezmoi installed it):
    ```bash
    gh auth login                    # the apply sets gh to clone over SSH
    ```
11. **Sign in to the apps:** 1Password (then Settings > Developer > Integrate with 1Password CLI, for `op`), Claude,
    Chrome, Slack, VS Code and Cursor (Settings Sync carries their settings): chezmoi installed them. Tailscale is the
    one app it does not install: install it (App Store or standalone) and sign in; the short SSH host names need it.
12. **iTerm2, once:**
    - Open iTerm2, then the menu **iTerm2 > Install Claude Code Integration**; choose **Mark Rewritable and Install**.
    - chezmoi's profile, **Default (Left Option as Alt)**, becomes the default by itself when the apply runs while
      iTerm2 is closed; if iTerm2 was open, the list says to quit it and apply again.
    - Quit and reopen iTerm2, so it loads the shared global settings chezmoi wrote (cheatsheet: "Same iTerm2 on Every
      Mac"). New tabs then have the shared look: JetBrains Mono Nerd Font Mono, the Atom colours, a silent bell.
13. **Warp, if you use it:** Settings > Features > Keys: Left Option is Meta on, Right Option is Meta off. Warp's
    account sync carries it to your other Macs, and chezmoi leaves it alone.
14. **Ctrl+Space for tmux and Herdr:** nothing to do: the apply turns off macOS's **Select the previous input
    source** (Ctrl+Space), which would take tmux's and Herdr's second prefix (these Macs never switch input language).
15. **Hammerspoon, once.** It runs the window keys (Ctrl+Option+Cmd), the Caps Lock prefix (hold Caps Lock for the
    window keys) and the window rescue (Cmd+Ctrl+U); cheatsheet: "Window Keys" and "Lost and Minimized Windows". Until
    this step none of them work, and Caps Lock stays plain Caps Lock. Open it
    (`open -a Hammerspoon`), choose **Open** when macOS asks about an app downloaded from the Internet, and allow
    it in System Settings > Privacy & Security > Device Control and Data Access (Accessibility before macOS 27): switch
    Hammerspoon on there, or add it with **+** from `/Applications` if it is not listed. chezmoi's config never asks
    for it (on macOS 27 asking showed the dialog on every config reload). It starts at login after that. The apply
    lists it while it is not running. Its own settings (Dock icon, console on top) can stay off.
16. **Remote access and power** (System Settings or sudo, so chezmoi only checks them):
    - System Settings > General > Sharing: turn on **Remote Login** (SSH) and **Remote Management** (screen sharing
      and control; a script can't turn on screen control). The apply lists either one while it is off.
    - From `~/.cfg`'s guides: `~/guides/macos/remote-access/apply.sh` (Remote Login and Touch ID for `sudo`) and
      `~/guides/macos/always-on/` for the power setup: regular (sleeps, woken by home-network traffic) or always on.
17. **Check:** `chezmoi apply`. Repeat steps from the list until it says `Nothing to do on this machine`.

## B. New Omarchy machine

1. **Install Omarchy**, sign in, and open a terminal (`Super + Enter`).
2. **Run the bootstrap.** Have the SSH key at hand; it stops until the key is in place.
   ```bash
   bash <(curl -fsSL https://raw.githubusercontent.com/simars/dotfiles/main/bootstrap/omarchy.sh)
   ```
   - Add `--with-remote-unlock` only for unlocking the disk over SSH. That guide's README has the router steps and
     the first unlock at the machine.
   - It installs chezmoi and git, then applies the dotfiles, packages, apps, runtimes, Tailscale, 1Password and shell
     plugins. It also copies in your SSH key, clones `~/.cfg` and applies the guides (zsh, terminals-clipboard,
     wave-keys, window-rescue, window-keys, caps-prefix).
   - It pauses for the sudo password, chezmoi's four questions (as on the Mac: Git email and name, work email or
     `none`, work GitHub orgs), the Tailscale login link, the SSH key and its passphrase.
   - It is safe to run again: after any stop, fix what it says and run the same command.
3. **Open a new terminal.** It starts zsh; the login shell stays bash.
4. **Claude Code and ai-tooling.** Omarchy ships `claude` and `gh`; the bootstrap does not set up ai-tooling.
   ```bash
   claude                           # log in, then quit
   cd ~/ai-tooling && make setup
   gh auth login                    # the apply sets gh to clone over SSH
   ```
5. **LunarVim, if the list asks:**
   ```bash
   mkdir -p ~/.local/share/lunarvim && ln -s /usr/share/lunarvim ~/.local/share/lunarvim/lvim && lvim --headless +qa
   ```
   Never run the package's `init-lvim.sh`.
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
