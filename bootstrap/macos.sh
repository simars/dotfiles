#!/usr/bin/env bash
# Bring a fresh Apple-silicon Mac to the shared setup, in one command, from Terminal on that Mac:
#
#   bash <(curl -fsSL https://raw.githubusercontent.com/simars/dotfiles/main/bootstrap/macos.sh)
#
# Safe to run again: every step checks first and skips what is done, so after a stop (the Command Line Tools dialog,
# the SSH key) fix the cause and run the same command. It pauses only where you must act: the Command Line Tools
# dialog, Homebrew's password, the SSH key (copied by hand), chezmoi's four questions, the key's passphrase, and the
# questions of ~/.cfg's installer. Every command that changes the Mac is printed (as "$ command") before it runs.
#
#   1. Command Line Tools               xcode-select --install (macOS's dialog), then run this again
#   2. Homebrew                         Homebrew's own installer
#   3. SSH key                          copied by hand to ~/.ssh/id_rsa (the script stops and says how)
#   4. dotfiles, packages, apps,        chezmoi init --apply (public repository, https): Homebrew packages and apps,
#      macOS settings                   macOS settings, LunarVim, mise runtimes
#   5. GitHub over SSH                  chezmoi's remote switched to SSH; the passphrase saved once (ssh-key-remember)
#   6. ~/.cfg and the rest              the private repository's installer (~/guides/install.sh): ~/dotfiles-local
#                                       links, Claude Code and ai-tooling, gh login, remote access, power; it asks
#   7. summary                          chezmoi apply's to-do list
#
# Intel Macs are set up by hand (docs/INTEL_MACS.md). docs/NEW_MACHINE.md, section A, has what stays yours to do.
# Runs under macOS's own bash 3.2.
set -uo pipefail

REPO_HTTPS=https://github.com/simars/dotfiles.git
REPO_SSH=git@github.com:simars/dotfiles.git
CFG_SSH=git@github.com:simars/.cfg.git
BREW_PREFIX="${BREW_PREFIX:-/opt/homebrew}" # tests point it at a scratch Homebrew
SOURCE="$HOME/.local/share/chezmoi"

step() { printf '\n==> %s\n' "$*"; }
die() { printf '\nbootstrap: %s\n' "$*" >&2; exit 1; }
run() { printf '    $ %s\n' "$*"; "$@"; } # print the command, then run it

# 0. Where we are
[[ "$(uname -s)" == Darwin ]] || die "this is not macOS; on Omarchy use bootstrap/omarchy.sh."
[[ "$(uname -m)" == arm64 ]] || die "this is an Intel Mac: set it up by hand with docs/INTEL_MACS.md in the dotfiles."
[[ $EUID -ne 0 ]] || die "run it as yourself, not root."
if [[ ! -t 0 && -z "${BOOTSTRAP_ASSUME_TTY:-}" ]]; then # tests set BOOTSTRAP_ASSUME_TTY
    cat << 'EOF'
This sets up a new Mac in 7 steps: Command Line Tools, Homebrew, SSH key (copied by hand), chezmoi (dotfiles, apps,
macOS settings), GitHub over SSH, ~/.cfg and its installer, summary. It asks questions and passwords,
so run it in a terminal:
  bash <(curl -fsSL https://raw.githubusercontent.com/simars/dotfiles/main/bootstrap/macos.sh)
Nothing was changed.
EOF
    exit 0
fi

# 1. Command Line Tools
step "1/7 Command Line Tools"
if xcode-select -p > /dev/null 2>&1; then
    echo "    done"
else
    run xcode-select --install
    die "finish macOS's Command Line Tools dialog, then run this again."
fi

# 2. Homebrew
step "2/7 Homebrew"
if [[ -x "$BREW_PREFIX/bin/brew" ]]; then
    echo "    done"
else
    # Printed by hand: run would print the whole installer script that $(curl ...) expands to.
    echo '    $ /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || die "Homebrew's installer failed; fix what it reports, then run this again."
fi
eval "$("$BREW_PREFIX/bin/brew" shellenv)"
export PATH="$HOME/.local/bin:$PATH"

# 3. SSH key, copied by hand
step "3/7 SSH key"
if [[ ! -f "$HOME/.ssh/id_rsa" ]]; then
    cat >&2 << 'EOF'
No ~/.ssh/id_rsa yet. Copy your key here by hand, then run this command again:
  - from another of your machines, if this Mac already accepts SSH logins (System Settings > General > Sharing >
    Remote Login):
        scp ~/.ssh/id_rsa ~/.ssh/id_rsa.pub <user>@<this-mac>:.ssh/
  - or from a USB stick or another copy you keep:
        install -m 700 -d ~/.ssh && install -m 600 <copy>/id_rsa ~/.ssh/ && install -m 644 <copy>/id_rsa.pub ~/.ssh/
EOF
    exit 1
fi
run chmod 700 "$HOME/.ssh"
run chmod 600 "$HOME/.ssh/id_rsa"

# 4. Dotfiles, packages, apps, macOS settings
step "4/7 Dotfiles, packages, apps and macOS settings (chezmoi)"
if [[ -d "$SOURCE/.git" ]]; then
    run chezmoi update || die "chezmoi update failed; fix what it reports, then run this again."
elif command -v chezmoi > /dev/null 2>&1; then
    run chezmoi init --apply "$REPO_HTTPS" || die "chezmoi init failed; fix what it reports, then run this again."
else
    echo "    \$ sh -c \"\$(curl -fsLS get.chezmoi.io)\" -- -b \"\$HOME/.local/bin\" init --apply $REPO_HTTPS"
    sh -c "$(curl -fsLS get.chezmoi.io)" -- -b "$HOME/.local/bin" init --apply "$REPO_HTTPS" || die "chezmoi init failed; fix what it reports, then run this again."
fi

# 5. GitHub over SSH
step "5/7 GitHub over SSH"
run git -C "$SOURCE" remote set-url origin "$REPO_SSH"
# Saves the passphrase in the login Keychain once (it says so if already saved); asks for it here.
run "$HOME/.local/bin/ssh-key-remember" || echo "    ssh-key-remember did not finish; the agent will ask for the passphrase instead."
# GitHub's test login always exits 1 (no shell), so judge by its message, not the exit status.
echo '    $ ssh -o StrictHostKeyChecking=accept-new -T git@github.com' # (adds GitHub's host key to ~/.ssh/known_hosts)
github_reply="$(ssh -o StrictHostKeyChecking=accept-new -T git@github.com 2>&1 || true)"
if [[ "$github_reply" == *"successfully authenticated"* ]]; then
    echo "    GitHub accepts this key over SSH."
else
    die "GitHub does not accept ~/.ssh/id_rsa over SSH yet (ssh -T git@github.com). Check the key, then run this again."
fi

# 6. The private ~/.cfg repository, then its installer for the rest (it asks before each step and prints its commands)
step "6/7 ~/.cfg and the rest (~/guides/install.sh)"
if [[ ! -d "$HOME/.cfg" ]]; then
    run git clone --bare "$CFG_SSH" "$HOME/.cfg" || die "cloning $HOME/.cfg failed (is the SSH key on GitHub?); fix it, then run this again."
fi
installer="$(git --git-dir="$HOME/.cfg" show HEAD:guides/install.sh 2> /dev/null)" || die "$HOME/.cfg has no guides/install.sh (an older copy?): git --git-dir=$HOME/.cfg fetch origin, then run this again."
# Run from the repository itself, so it works before ~/.cfg is checked out (the installer checks it out). Printed by
# hand: run would show bash's /dev/fd/63 for the <(...) part.
printf '    $ bash <(git --git-dir=%s/.cfg show HEAD:guides/install.sh)\n' "$HOME"
bash <(printf '%s\n' "$installer") || echo "    The installer reported a step that failed (above); fix it, then run this bootstrap again."

# 7. Summary
step "7/7 Summary"
run chezmoi apply || true
cat << 'EOF'

Done. What stays yours (docs/NEW_MACHINE.md, section A): sign in to the apps, install Tailscale, Hammerspoon's
permission, Screen Sharing control, iTerm2's Claude Code integration, and a log out for the trackpad settings.
Open a new terminal tab: zsh loads the new setup.
EOF
