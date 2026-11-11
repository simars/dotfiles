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
# mise on Omarchy: option B (.chezmoidata/omarchy.toml, the default since 2026-11-06) deploys the shared settings
# without node; option A renders them empty, so chezmoi deletes any earlier copy. Neither carries tools,
# default_packages_file or set_gobin.
check "omarchy mise defaults to option B" true "$(chezmoi execute-template '{{ .omarchy_mise_project_settings }}')"
omarchy_a='{"chezmoi":{"os":"linux","osRelease":{"id":"omarchy","idLike":"arch"}},"omarchy_mise_project_settings":false}'
check "omarchy option A renders no mise settings" "" "$(chezmoi --override-data "$omarchy_a" execute-template < dot_config/mise/conf.d/50-shared.toml.tmpl | tr -d '[:space:]')"
omarchy_b='{"chezmoi":{"os":"linux","osRelease":{"id":"omarchy","idLike":"arch"}},"omarchy_mise_project_settings":true}'
chezmoi --override-data "$omarchy_b" execute-template < dot_config/mise/conf.d/50-shared.toml.tmpl > "$work/omarchy-b.mise"
check "omarchy option B follows python and ruby version files and uv venvs" 2 "$(grep -cE '^idiomatic_version_file_enable_tools = \["python", "ruby"\]$|^uv_venv_auto = true$' "$work/omarchy-b.mise")"
# Omarchy's npm-based agent CLIs run on the node mise picks for the folder, so a project's .nvmrc must not reach them.
check "omarchy option B never follows node version files" 0 "$(grep -c '"node"' "$work/omarchy-b.mise")"
check "omarchy option B installs prebuilt Rubies only" 1 "$(grep -cE '^compile = false$' "$work/omarchy-b.mise")"
check "omarchy option B mise settings carry no tools" 0 "$(grep -cE '^\[tools\]|^(node|python|go) *=' "$work/omarchy-b.mise")"
check "omarchy option B skips the deprecated default_packages_file" 0 "$(grep -c default_packages_file "$work/omarchy-b.mise")"
check "omarchy option B leaves GOBIN to mise (bash has no ~/go/bin)" 0 "$(grep -cE 'settings\.go|set_gobin' "$work/omarchy-b.mise")"
for host in darwin intel arch ubuntu; do
    check "$host mise config follows node, python and ruby version files" 1 "$(render "$host" dot_config/mise/config.toml.tmpl | grep -c '^idiomatic_version_file_enable_tools = \["node", "python", "ruby"\]$')"
    check "$host mise config keeps set_gobin = false" 1 "$(render "$host" dot_config/mise/config.toml.tmpl | grep -c '^set_gobin = false$')"
done

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

# ssh: every host gets the own machines under <machine>[-unlock].<how> (bare name = .tailnet; works-unlock = .ddns).
for host in $hosts; do
    render "$host" private_dot_ssh/private_config.tmpl > "$work/$host.ssh_config"
    # ssh -G here may not know macOS's UseKeychain; resolve from a copy without it.
    cfg="$work/$host.ssh_config.resolve"
    grep -v 'UseKeychain' "$work/$host.ssh_config" > "$cfg"
    # Resolve an alias the way ssh does (first value wins), from the rendered file only.
    for pair in works=simars-works works.tailnet=simars-works works.local=simars-works.local works.lan=192.168.68.146 \
        works.ddns=simars.ddns.net works.tplink=simars.tplinkdns.com \
        works-unlock=simars.ddns.net works-unlock.ddns=simars.ddns.net works-unlock.tplink=simars.tplinkdns.com \
        works-unlock.lan=192.168.68.146 mbp-work=simars-macbook-work mbp-work.tailnet=simars-macbook-work \
        mbp-work.local=simars-macbook-work.local mbp=simar-mbp mbp.tailnet=simar-mbp mbp.local=simar-mbp.local \
        macstudio=macstudio macstudio.tailnet=macstudio macstudio.local=macstudio.local; do
        alias=${pair%%=*}
        check "$host ssh $alias reaches ${pair#*=}" "${pair#*=}" "$(ssh -G -F "$cfg" "$alias" 2> /dev/null | awk '$1=="hostname"{print $2}')"
    done
    # One host key per machine, whichever path; the unlock screen has its own.
    for pair in works.lan=works works.tplink=works mbp-work.local=mbp-work mbp=mbp macstudio.local=macstudio \
        works-unlock.tplink=works-unlock; do
        check "$host ssh ${pair%%=*} checks host key ${pair#*=}" "${pair#*=}" "$(ssh -G -F "$cfg" "${pair%%=*}" 2> /dev/null | awk '$1=="hostkeyalias"{print $2}')"
    done
    check "$host ~/.ssh/config has no unlock path that can't exist at boot" 0 "$(grep -cE '^Host .*works-unlock\.(tailnet|local)' "$cfg")"
    check "$host ~/.ssh/config keeps none of the old simar- names" 0 "$(grep -cE '^Host .*(simar-works|simar-mbp)' "$cfg")"
done
# Agent forwarding goes to the own machines only, never to every host, GitHub or the work stanza.
for host in $hosts; do
    check "$host ~/.ssh/config forwards the agent to the four own machines" 4 "$(grep -c '^    ForwardAgent yes$' "$work/$host.ssh_config")"
    check "$host ~/.ssh/config never forwards the agent to every host or GitHub" 0 \
        "$(awk '/^Host /{h=$2} /ForwardAgent yes/ && (h=="*" || h=="github.com" || h ~ /internal/)' "$work/$host.ssh_config" | wc -l | tr -d ' ')"
done
# works' disk-unlock screen: root on port 2222, its own host key alias, never the agent, on every path.
for host in $hosts; do
    for alias in works-unlock works-unlock.ddns works-unlock.tplink works-unlock.lan; do
        check "$host $alias connects as root on 2222 with no agent and a tty" "root 2222 no true" \
            "$(ssh -G -F "$work/$host.ssh_config.resolve" "$alias" 2> /dev/null | awk '$1=="user"{u=$2} $1=="port"{p=$2} $1=="forwardagent"{f=$2} $1=="requesttty"{t=$2} END{print u, p, f, t}')"
    done
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
check "omarchy requirement check warns when another file overrides the version-file setting" 1 "$(grep -c 'not $want_idiomatic, so projects' "$work/omarchy.requirements")"
check "omarchy option A requirement check skips that warning" 0 "$(chezmoi --override-data "$omarchy_a" execute-template < "$requirements" | grep -c want_idiomatic)"
for host in darwin intel arch ubuntu; do
    check "$host requirement check has no Omarchy version-file check" 0 "$(grep -c want_idiomatic "$work/$host.requirements")"
done
check "omarchy requirement check never mentions mise-audit" 0 "$(grep -c 'mise-audit' "$work/omarchy.requirements")"
# ssh-key-remember: deployed everywhere, checked (warn only) after every apply; the old Mac-only run_once enrolment is gone.
for host in $hosts; do
    check "$host manages ssh-key-remember" yes "$(manages "$host" .local/bin/ssh-key-remember)"
    check "$host requirement check warns when the SSH passphrase is not saved" 1 "$(grep -c 'Fix: ssh-key-remember' "$work/$host.requirements")"
    check "$host has no run_once keychain enrolment" no "$(manages "$host" 10_ssh_keychain.sh)"
done
check "ssh-key-remember is valid bash" "" "$(bash -n dot_local/bin/executable_ssh-key-remember 2>&1)"
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
