#!/usr/bin/env bash
#
# Check what each kind of host gets from this repository, from any machine, without applying anything.
# `chezmoi --override-data` renders the templates as if this were macOS, Omarchy, Arch, Ubuntu or Debian, and the
# checks below hold the platform rules of AGENTS.md section 4: Omarchy keeps its own configs except the merged tmux and
# Herdr ones, Omarchy installs only with `omarchy pkg`, and ~/.bashrc is managed on macOS only.
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
        darwin) echo '{"chezmoi":{"os":"darwin","arch":"arm64","osRelease":{"id":"","idLike":""}}}' ;;
        intel) echo '{"chezmoi":{"os":"darwin","arch":"amd64","osRelease":{"id":"","idLike":""}}}' ;;
        omarchy) echo '{"chezmoi":{"os":"linux","osRelease":{"id":"omarchy","idLike":"arch"}}}' ;;
        arch) echo '{"chezmoi":{"os":"linux","osRelease":{"id":"arch","idLike":""}}}' ;;
        ubuntu) echo '{"chezmoi":{"os":"linux","osRelease":{"id":"ubuntu","idLike":"debian"}}}' ;;
        debian) echo '{"chezmoi":{"os":"linux","osRelease":{"id":"debian","idLike":""}}}' ;;
    esac
}
hosts="darwin intel omarchy arch ubuntu debian"

# Targets Omarchy ships and updates itself (plus herdr's existing config there, and the script that runs
# `mise install`). They must be managed everywhere else, so the Omarchy rule cannot leak.
omarchy_owned=".config/nvim/init.lua .config/nvim/lua/config/options.lua .config/alacritty/alacritty.toml
.config/starship.toml .config/mise/config.toml 90_sync_runtimes.sh .local/bin/mise-audit"

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
    [[ "$host" == darwin || "$host" == intel ]] && expected=yes
    check "$host manages .bashrc" "$expected" "$(manages "$host" .bashrc)"
    check "$host does not manage the repository's own tests" no "$(manages "$host" tests/host-profiles.sh)"
done

packages=run_onchange_before_00_install_packages.sh.tmpl
for host in $hosts; do
    render "$host" "$packages" > "$work/$host.packages"
    check "$host package script is valid bash" "" "$(bash -n "$work/$host.packages" 2>&1)"
done
# Packages install only on Apple silicon Macs. Intel Macs and Linux hosts are set up by hand and only say so.
check "darwin package script runs brew bundle" yes "$(grep -q 'brew bundle --no-upgrade' "$work/darwin.packages" && echo yes || echo no)"
for host in intel omarchy arch ubuntu debian; do
    check "$host package script installs nothing (no brew, apt, curl or sudo)" 0 "$(grep -cE 'brew |apt-get|dpkg|curl|sudo' "$work/$host.packages")"
done
for host in intel arch ubuntu debian; do
    check "$host package script reports the skip" 1 "$(grep -c '==> Skipping' "$work/$host.packages")"
    check "$host package script never calls omarchy" 0 "$(grep -c 'omarchy pkg\|install_missing' "$work/$host.packages")"
done
# Omarchy installs its listed packages with Omarchy's own commands only, never pacman directly.
check "omarchy package script installs with omarchy pkg add" 1 "$(grep -c '^install_missing "pkg add" ' "$work/omarchy.packages")"
check "omarchy package script installs AUR with omarchy pkg aur add" 1 "$(grep -c '^install_missing "pkg aur add" "lunarvim-git"$' "$work/omarchy.packages")"
check "omarchy package list leaves out bitwarden-cli (Node conflict)" 0 "$(grep -c 'bitwarden' "$work/omarchy.packages")"
check "omarchy package script never calls pacman or yay" 0 "$(grep -cE 'pacman |yay ' "$work/omarchy.packages")"
check "omarchy package script installs only from a terminal" 1 "$(grep -c '\[\[ -t 0 && -t 1 \]\]' "$work/omarchy.packages")"

# No host rewrites URLs: a rewrite to SSH made every fetch need an unlocked key (brew update, LazyVim).
for host in $hosts; do
    check "$host ~/.gitconfig rewrites no URLs" 0 "$(render "$host" dot_gitconfig.tmpl | grep -ciE 'insteadof')"
done

# Leak guard: on Omarchy chezmoi writes exactly one Neovim file; every other host gets the whole LazyVim tree.
check "omarchy manages only shared.lua under .config/nvim" ".config/nvim/lua/plugins/shared.lua" \
    "$(chezmoi --override-data "$(host_data omarchy)" managed --include=files | grep -E '^\.config/nvim/' | xargs)"
for host in darwin intel arch ubuntu; do
    for target in .config/nvim/init.lua .config/nvim/lua/config/options.lua .config/nvim/lua/plugins/shared.lua \
        .config/nvim/lua/plugins/theme.lua .config/nvim/lazy-lock.json .config/nvim/.neoconf.json; do
        check "$host manages $target" yes "$(manages "$host" "$target")"
    done
    check "$host gets no Omarchy-only Neovim file" "" "$(grep -E 'remote_clipboard|omarchy-theme-hotreload|all-themes' "$work/$host.managed")"
done

# Leak guard: on Omarchy chezmoi writes exactly these under ~/.config/mise, and nothing else.
check "omarchy manages only the shared mise settings" ".config/mise .config/mise/conf.d .config/mise/conf.d/50-shared.toml" \
    "$(grep -E '^\.config/mise(/|$)' "$work/omarchy.managed" | sort | xargs)"
for host in darwin intel arch ubuntu; do
    check "$host does not manage mise conf.d" no "$(manages "$host" .config/mise/conf.d/50-shared.toml)"
    check "$host manages default-python-packages" yes "$(manages "$host" .config/mise/default-python-packages)"
    check "$host mise config skips deprecated default_packages_file" 0 "$(render "$host" dot_config/mise/config.toml.tmpl | grep -c default_packages_file)"
done
check "omarchy mise settings carry no tools" 0 "$(render omarchy dot_config/mise/conf.d/50-shared.toml.tmpl | grep -cE '^\[tools\]|^(node|python|go) *=')"
check "omarchy mise settings skip the deprecated default_packages_file" 0 "$(render omarchy dot_config/mise/conf.d/50-shared.toml.tmpl | grep -c default_packages_file)"

# tmux and Herdr are one shared config everywhere, Omarchy included. Herdr keeps Omarchy's chrome only there.
for host in $hosts; do
    check "$host manages tmux.conf" yes "$(manages "$host" .config/tmux/tmux.conf)"
    check "$host manages herdr config" yes "$(manages "$host" .config/herdr/config.toml)"
    check "$host does not manage ~/.tmux.conf" no "$(manages "$host" .tmux.conf)"
done
render omarchy dot_config/herdr/config.toml.tmpl > "$work/omarchy.herdr"
render darwin dot_config/herdr/config.toml.tmpl > "$work/darwin.herdr"
for line in 'window_title = "{hostname}: {workspace}"' 'panel_bg = "reset"' 'surface_dim = "black"' 'prefix = "ctrl+b"'; do
    check "omarchy herdr has $line" 1 "$(grep -cxF -- "$line" "$work/omarchy.herdr")"
done
check "darwin herdr has no Omarchy chrome" 0 "$(grep -cE 'window_title|panel_bg|^\[theme' "$work/darwin.herdr")"
# Omarchy's [ui] holds exactly its stock [ui] settings (order, comments and blank lines aside).
check "omarchy herdr [ui] is Omarchy's stock [ui]" "" "$(diff <(sed -n '/^\[ui\]/,$p' docs/omarchy-stock/herdr.toml | grep -vE '^(#|$)' | sort) <(sed -n '/^\[ui\]/,$p' "$work/omarchy.herdr" | grep -vE '^(#|$)' | sort))"
check "darwin herdr keeps gaps" 1 "$(grep -cxF 'pane_gaps = true' "$work/darwin.herdr")"
# The stock-drift report runs on Omarchy only and never fails.
drift=run_after_95_omarchy_stock_drift.sh.tmpl
for host in $hosts; do
    expected=0
    [[ "$host" == omarchy ]] && expected=1
    check "$host stock-drift report present" "$expected" "$(render "$host" "$drift" | grep -c '^check_stock tmux')"
done
check "omarchy stock-drift report is valid bash" "" "$(render omarchy "$drift" | bash -n 2>&1)"

# git's editor: VS Code on macOS; none on Omarchy, so git follows $EDITOR (Omarchy's launcher); nvim elsewhere.
check "darwin ~/.gitconfig editor" "editor = code --wait" "$(render darwin dot_gitconfig.tmpl | grep -E '^\s*editor' | xargs)"
check "omarchy ~/.gitconfig sets no editor" 0 "$(render omarchy dot_gitconfig.tmpl | grep -c 'editor =')"
check "ubuntu ~/.gitconfig editor" "editor = nvim" "$(render ubuntu dot_gitconfig.tmpl | grep -E '^\s*editor' | xargs)"

# ssh: every host knows the Macs it reaches; the placeholder work stanza stays off Omarchy.
for host in $hosts; do
    check "$host ~/.ssh/config has the work MacBook" 1 "$(render "$host" private_dot_ssh/private_config.tmpl | grep -c '^Host mbp-work.local$')"
    check "$host ~/.ssh/config has simar-mbp" 1 "$(render "$host" private_dot_ssh/private_config.tmpl | grep -c '^Host simar-mbp.local$')"
done
check "omarchy ~/.ssh/config has no work stanza" 0 "$(render omarchy private_dot_ssh/private_config.tmpl | grep -c 'internal')"

# The requirement check suggests fixes from the host's own package manager, and leaves Omarchy's mise alone.
requirements=run_after_99_assert_requirements.sh.tmpl
for host in $hosts; do
    render "$host" "$requirements" > "$work/$host.requirements"
    check "$host requirement check is valid bash" "" "$(bash -n "$work/$host.requirements" 2>&1)"
done
for host in omarchy arch; do
    check "$host requirement check never suggests apt" 0 "$(grep -c 'apt-get' "$work/$host.requirements")"
done
check "arch requirement check suggests pacman for gitleaks" 1 "$(grep -c 'sudo pacman -S gitleaks' "$work/arch.requirements")"
# Omarchy installs packages only through its own command.
check "omarchy requirement check suggests omarchy pkg add for gitleaks" 1 "$(grep -c 'omarchy pkg add gitleaks' "$work/omarchy.requirements")"
check "omarchy requirement check never suggests pacman or sudo" 0 "$(grep -cE 'pacman|sudo' "$work/omarchy.requirements")"
check "omarchy requirement check reports missing listed packages" 1 "$(grep -c 'lists packages that are not installed. Fix: omarchy pkg add ' "$work/omarchy.requirements")"
check "omarchy requirement check never mentions mise-audit" 0 "$(grep -c 'mise-audit' "$work/omarchy.requirements")"
check "intel requirement check points to the Intel guide" yes "$(grep -q 'docs/INTEL_MACS.md' "$work/intel.requirements" && echo yes || echo no)"
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
