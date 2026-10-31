#!/usr/bin/env bash
#
# Check what each kind of host gets from this repository, from any machine, without applying anything.
# `chezmoi --override-data` renders the templates as if this were macOS, Omarchy, Arch, Ubuntu or Debian, and the
# checks below hold the platform rules of AGENTS.md section 4: Omarchy keeps its own configs, apt runs on Ubuntu and
# Debian only, and ~/.bashrc is managed on macOS only.
#
# Usage: tests/host-profiles.sh [--base <git ref>]
#   --base also reports each run_onchange_ script whose macOS or Ubuntu render differs from <ref>: hosts like that
#   re-run it on their next apply. A report, not a failure.
#
# Needs an initialized chezmoi (CI runs `chezmoi init` first). Runs under bash 3.2, the macOS /bin/bash.

set -u

base=""
if [[ "${1:-}" == "--base" ]]; then
    base="${2:?--base needs a git ref}"
fi

cd "$(dirname "$0")/.." || exit 1

# Every host sets both id and idLike: --override-data merges into the real data, so a Linux runner's own
# ID_LIKE=debian would otherwise leak into the Arch host.
host_data() {
    case "$1" in
        darwin) echo '{"chezmoi":{"os":"darwin","osRelease":{"id":"","idLike":""}}}' ;;
        omarchy) echo '{"chezmoi":{"os":"linux","osRelease":{"id":"omarchy","idLike":"arch"}}}' ;;
        arch) echo '{"chezmoi":{"os":"linux","osRelease":{"id":"arch","idLike":""}}}' ;;
        ubuntu) echo '{"chezmoi":{"os":"linux","osRelease":{"id":"ubuntu","idLike":"debian"}}}' ;;
        debian) echo '{"chezmoi":{"os":"linux","osRelease":{"id":"debian","idLike":""}}}' ;;
    esac
}
hosts="darwin omarchy arch ubuntu debian"

# Targets Omarchy ships and updates itself (plus herdr's existing config there, and the script that runs
# `mise install`). They must be managed everywhere else, so the Omarchy rule cannot leak.
omarchy_owned=".config/nvim/init.lua .config/tmux/tmux.conf .tmux.conf .config/alacritty/alacritty.toml
.config/starship.toml .config/mise/config.toml .config/herdr/config.toml 90_sync_runtimes.sh"

work="$(mktemp -d "${TMPDIR:-/tmp}/host-profiles.XXXXXX")"
trap 'rm -rf "$work"' EXIT
pass=0
fail=0

check() { # check NAME EXPECTED ACTUAL
    if [[ "$3" == "$2" ]]; then
        pass=$((pass + 1))
    else
        fail=$((fail + 1))
        echo "FAIL $1: expected [$2], got [$3]"
    fi
}

manages() { # manages HOST TARGET
    if grep -qxF -- "$2" "$work/$1.managed"; then echo yes; else echo no; fi
}

render() { # render HOST FILE [SOURCE_DIR]
    local source="${3:-.}"
    chezmoi --source "$source" --override-data "$(host_data "$1")" execute-template < "$source/$2"
}

for host in $hosts; do
    if ! chezmoi --override-data "$(host_data "$host")" managed --include=all > "$work/$host.managed"; then
        echo "FAIL chezmoi managed for $host"
        exit 1
    fi
done

for target in $omarchy_owned; do
    check "omarchy leaves $target alone" no "$(manages omarchy "$target")"
    for host in darwin arch ubuntu; do
        check "$host manages $target" yes "$(manages "$host" "$target")"
    done
done

for host in $hosts; do
    expected=no
    [[ "$host" == darwin ]] && expected=yes
    check "$host manages .bashrc" "$expected" "$(manages "$host" .bashrc)"
    check "$host does not manage the repository's own tests" no "$(manages "$host" tests/host-profiles.sh)"
done

packages=run_onchange_before_00_install_packages.sh.tmpl
for host in $hosts; do
    render "$host" "$packages" > "$work/$host.packages"
    check "$host package script is valid bash" "" "$(bash -n "$work/$host.packages" 2>&1)"
done
for host in omarchy arch; do
    check "$host package script has no apt, dpkg or sudo" 0 "$(grep -cE 'apt-get|dpkg|sudo' "$work/$host.packages")"
    check "$host package script reports the skip" 1 "$(grep -c 'Skipping system packages' "$work/$host.packages")"
done
for host in ubuntu debian; do
    check "$host package script installs with apt" yes "$(grep -q 'sudo apt-get install' "$work/$host.packages" && echo yes || echo no)"
done

# No host rewrites URLs: a rewrite to SSH made every fetch need an unlocked key (brew update, LazyVim).
for host in $hosts; do
    check "$host ~/.gitconfig rewrites no URLs" 0 "$(render "$host" dot_gitconfig.tmpl | grep -ciE 'insteadof')"
done

# The requirement check suggests fixes from the host's own package manager, and leaves Omarchy's mise alone.
requirements=run_after_99_assert_requirements.sh.tmpl
for host in $hosts; do
    render "$host" "$requirements" > "$work/$host.requirements"
    check "$host requirement check is valid bash" "" "$(bash -n "$work/$host.requirements" 2>&1)"
done
for host in omarchy arch; do
    check "$host requirement check suggests pacman for gitleaks" 1 "$(grep -c 'Fix: sudo pacman -S gitleaks' "$work/$host.requirements")"
    check "$host requirement check never suggests apt" 0 "$(grep -c 'apt-get' "$work/$host.requirements")"
done
check "ubuntu requirement check suggests apt for git" 1 "$(grep -c 'apt-get install -y git' "$work/ubuntu.requirements")"
for host in $hosts; do
    expected=1
    [[ "$host" == omarchy ]] && expected=0
    check "$host requirement check compares mise with this repository's version" "$expected" \
        "$(grep -c 'the release ~/.config/mise/config.toml was verified on' "$work/$host.requirements")"
done

if [[ -n "$base" ]]; then
    mkdir -p "$work/base"
    git archive "$base" | tar -x -C "$work/base"
    for script in run_onchange_*.tmpl; do
        [[ -f "$work/base/$script" ]] || continue
        for host in darwin ubuntu; do
            if ! cmp -s <(render "$host" "$script") <(render "$host" "$script" "$work/base"); then
                echo "NOTE $script renders differently on $host than at $base: such hosts re-run it on the next apply"
            fi
        done
    done
fi

echo "$pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
