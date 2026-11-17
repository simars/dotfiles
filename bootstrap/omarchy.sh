#!/usr/bin/env bash
# Bring a fresh Omarchy machine to the shared setup, in one command, from a terminal on that machine:
#
#   bash <(curl -fsSL https://raw.githubusercontent.com/simars/dotfiles/main/bootstrap/omarchy.sh)
#   bash <(curl -fsSL https://raw.githubusercontent.com/simars/dotfiles/main/bootstrap/omarchy.sh) --with-remote-unlock
#
# Safe to run again: every step checks first and skips what is done, so after a stop (the SSH key, a failed step)
# fix the cause and run the same command. It pauses only where you must act: sudo password, chezmoi's three
# questions (email, name, work machine), the Tailscale login link, the SSH key passphrase.
#
#   1. chezmoi and git                  omarchy pkg add
#   2. dotfiles, packages, apps,        chezmoi init --apply (public repository, https): packages.toml (omarchy pkg add),
#      runtimes, shell plugins          Tailscale and 1Password installers, dev-env runtimes, shell plugins
#   3. SSH key                          copied by hand to ~/.ssh/id_rsa (the script stops and says how); its passphrase
#                                       saved once with ssh-key-remember; GitHub reached over SSH
#   4. ~/.cfg                           the private bare repository (ai-tooling, dotfiles-local, guides, llm, scripts)
#   5. guides                           setup-guides apply: zsh, terminals-clipboard, wave-keys
#   6. remote disk unlock (opt-in)      --with-remote-unlock: that guide's apply.sh, then its README for the router steps
#   7. summary                          the requirement check and every guide's verdict
#
# Not done here (per machine, or yours to do): monitors (~/.config/hypr/monitors.lua, monitor-layout), the tablet
# mapping, the theme, web apps, signing in to 1Password, Slack and the rest. docs/CHEATSHEET.md, "New Omarchy Machine".
set -euo pipefail

REPO_HTTPS="https://github.com/simars/dotfiles.git"
REPO_SSH="git@github.com:simars/dotfiles.git"
CFG_SSH="git@github.com:simars/.cfg.git"
BIN="$HOME/.local/bin"

with_remote_unlock=0
for arg in "$@"; do
    case "$arg" in
        --with-remote-unlock) with_remote_unlock=1 ;;
        -h | --help)
            echo "usage: omarchy.sh [--with-remote-unlock]   (fresh Omarchy -> shared setup; safe to run again)"
            echo "steps: chezmoi and git, chezmoi init --apply, SSH key (copied by hand), ~/.cfg, guides,"
            echo "       remote disk unlock (only with --with-remote-unlock), summary"
            exit 0
            ;;
        *)
            echo "usage: omarchy.sh [--with-remote-unlock]" >&2
            exit 2
            ;;
    esac
done

step() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
die() { printf '\nbootstrap: %s\n' "$*" >&2; exit 1; }
cfg() { git --git-dir="$HOME/.cfg" --work-tree="$HOME" "$@"; }

# 0. Where we are
grep -qx 'ID=omarchy' /etc/os-release 2> /dev/null || die "this is not Omarchy (/etc/os-release has no ID=omarchy)."
[[ $EUID -ne 0 ]] || die "run it as yourself, not root."
[[ -t 0 && -t 1 ]] || die "run it in a terminal: it asks for your sudo password, chezmoi's questions and logins."
command -v omarchy > /dev/null || die "the omarchy command is missing; finish Omarchy's own installation first."

# 1. chezmoi and git
step "1/7 chezmoi and git"
omarchy pkg add chezmoi git

# 2. Dotfiles, packages, apps, runtimes, shell plugins
step "2/7 Dotfiles, packages, apps, runtimes and shell plugins (chezmoi)"
if [[ -d "$HOME/.local/share/chezmoi/.git" ]]; then
    chezmoi update || die "chezmoi update failed; fix what it reports, then run this again."
else
    chezmoi init --apply "$REPO_HTTPS" || die "chezmoi init failed; fix what it reports, then run this again."
fi

# 3. SSH key, copied by hand
step "3/7 SSH key"
if [[ ! -f "$HOME/.ssh/id_rsa" ]]; then
    cat >&2 << 'EOF'
No ~/.ssh/id_rsa yet. Copy your key here by hand, then run this command again:
  - from another of your machines, if this one already accepts SSH logins:
        scp ~/.ssh/id_rsa ~/.ssh/id_rsa.pub <user>@<this-machine>:.ssh/
  - or from a USB stick or another copy you keep:
        install -m 700 -d ~/.ssh && install -m 600 <copy>/id_rsa ~/.ssh/ && install -m 644 <copy>/id_rsa.pub ~/.ssh/
EOF
    exit 1
fi
chmod 700 "$HOME/.ssh"
chmod 600 "$HOME/.ssh/id_rsa"
# Saves the passphrase in the login keyring once (it says so if already saved); asks for it here.
"$BIN/ssh-key-remember" || echo "    ssh-key-remember did not finish; the agent will ask for the passphrase instead."
# GitHub's test login always exits 1 (no shell), so judge by its message, not the exit status.
github_reply="$(ssh -o StrictHostKeyChecking=accept-new -T git@github.com 2>&1 || true)"
if [[ "$github_reply" == *"successfully authenticated"* ]]; then
    echo "    GitHub accepts this key over SSH."
else
    die "GitHub does not accept ~/.ssh/id_rsa over SSH yet (ssh -T git@github.com). Check the key, then run this again."
fi
git -C "$HOME/.local/share/chezmoi" remote set-url origin "$REPO_SSH"

# 4. The private ~/.cfg repository
step "4/7 ~/.cfg (private repository)"
if [[ ! -d "$HOME/.cfg" ]]; then
    git clone --bare "$CFG_SSH" "$HOME/.cfg"
fi
cfg config status.showUntrackedFiles no
cfg config remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*'
cfg fetch -q origin
if [[ -z "$(cfg ls-files | head -n 1)" ]]; then
    # First checkout (a bare clone has no index yet). Never overwrite: a checkout that would replace existing files
    # stops and names them.
    if ! out="$(cfg checkout 2>&1)"; then
        echo "$out" >&2
        die "$HOME/.cfg could not check out without overwriting the files above; move them aside, then run this again."
    fi
fi
cfg branch -q --set-upstream-to=origin/main main 2> /dev/null || true
echo "    ~/.cfg at $(cfg log -1 --format='%h %s')"

# 5. Guides
step "5/7 Guides (setup-guides apply)"
"$BIN/setup-guides" apply || echo "    Some guides are not active; see their README in ~/guides/omarchy/<guide>."

# 6. Remote disk unlock, opt-in
if [[ $with_remote_unlock -eq 1 ]]; then
    step "6/7 Remote disk unlock (--with-remote-unlock)"
    guide="$HOME/guides/omarchy/remote-disk-unlock"
    [[ -x "$guide/apply.sh" ]] || die "$guide/apply.sh is missing."
    (cd "$guide" && ./apply.sh)
    echo "    Next: the router steps and the first unlock at the machine, in $guide/README.md."
else
    step "6/7 Remote disk unlock: skipped (opt-in: --with-remote-unlock)"
fi

# 7. Summary
step "7/7 Summary"
chezmoi apply || true
"$BIN/setup-guides" || true
cat << 'EOF'

Done. What stays per machine or needs you (docs/CHEATSHEET.md, "New Omarchy Machine"):
  - monitors: arrange them in the bar's Display widget (monitor-layout); the tablet mapping in its widget
  - theme, web apps, and signing in to 1Password, Chrome, Slack, VS Code, Cursor, Claude
  - open a new terminal: it starts zsh (the login shell stays bash)
EOF
